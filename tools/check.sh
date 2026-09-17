#!/usr/bin/env bash
# Roboto verification script.
#
# THIS IS THE MOST IMPORTANT FILE FOR AGENT WORK. An agent that cannot check its
# own output will confidently hand you code that doesn't parse. Everything else
# in the setup is comfort; this is the part that makes autonomy possible.
#
# Usage:  tools/check.sh            check everything (~60s for 91 scripts)
#         tools/check.sh --changed  check only files changed vs git HEAD
#
# Exit code 0 = clean. Non-zero = something to fix.

set -uo pipefail
cd "$(dirname "$0")/.."

# ── Godot ────────────────────────────────────────────────────────────────────
# Override with GODOT=... if you move or upgrade the editor.
#
# On Windows use the *_console.exe build. The plain .exe is a GUI binary: it
# detaches from the terminal and writes nothing to stdout, so every parse check
# would come back empty and this script would report PASS on broken code.
if [ -z "${GODOT:-}" ]; then
	for candidate in \
		"/d/Godot Games/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe" \
		"/c/Program Files/Godot/Godot_v4.3-stable_win64_console.exe" \
		"godot"
	do
		if [ -x "$candidate" ] || command -v "$candidate" >/dev/null 2>&1; then
			GODOT="$candidate"
			break
		fi
	done
fi
if [ -z "${GODOT:-}" ]; then
	echo "Godot not found. Set it explicitly, e.g."
	echo "  GODOT='/d/Godot Games/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe' tools/check.sh"
	exit 2
fi

FAIL=0

# Noise we can't fix: assets that aren't in the repo, and the func_godot addon's
# own parse errors. Filtering them is what makes a real error visible.
NOISE='entity_fgd|ext_resource.*non-existent|Failed loading resource|Make sure resources|icon_slipgate|func_godot|Cannot open file|custom project font'

# --check-only does not start the autoload singletons, so every script that
# touches one reports "Identifier not found". That is not a real error. The
# names are read from project.godot rather than hardcoded, so adding an autoload
# later doesn't quietly turn this check red.
AUTOLOADS=$(sed -n '/^\[autoload\]/,/^\[[a-z]/p' project.godot 2>/dev/null \
            | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' | cut -d= -f1 | paste -sd'|' -)
if [ -n "$AUTOLOADS" ]; then
	NOISE="$NOISE|Identifier not found: \"?($AUTOLOADS)\"?"
fi

# ── What to check ────────────────────────────────────────────────────────────
# Untracked files are included deliberately: a script an agent just created is
# exactly the one most likely to be broken, and `git diff HEAD` never lists it.
if [ "${1:-}" = "--changed" ]; then
	FILES=$( { git diff --name-only HEAD -- '*.gd'
	           git diff --cached --name-only HEAD -- '*.gd'
	           git ls-files --others --exclude-standard -- '*.gd'; } 2>/dev/null )
	SCENES=$( { git diff --name-only HEAD -- '*.tscn' '*.tres'
	            git diff --cached --name-only HEAD -- '*.tscn' '*.tres'
	            git ls-files --others --exclude-standard -- '*.tscn' '*.tres'; } 2>/dev/null )
else
	FILES=$(find . -name '*.gd' -not -path './addons/*' -not -path './.godot/*')
	SCENES=$(find . \( -name '*.tscn' -o -name '*.tres' \) -not -path './addons/*' -not -path './.godot/*')
fi

# ── GDScript parse check ─────────────────────────────────────────────────────
echo "── GDScript parse check ──"
CHECKED=0
# read -r, not `for f in $(...)`. At least one script in this project has a
# space in its filename ("ai_world_weapon_drone bomb.gd"); word-splitting tore
# it in two and both halves failed the -f test, so it was skipped in silence —
# the precise failure mode this script exists to catch.
while IFS= read -r f; do
	[ -n "$f" ] || continue
	[ -f "$f" ] || continue
	CHECKED=$((CHECKED + 1))
	out=$("$GODOT" --headless --path . --check-only --script "res://${f#./}" 2>&1 \
	      | grep -E "Parse Error|Compile Error|SCRIPT ERROR" | grep -Ev "$NOISE" | head -5)
	if [ -n "$out" ]; then
		echo "FAIL  $f"
		echo "$out" | sed 's/^/        /'
		FAIL=1
	fi
done < <(echo "$FILES" | sort -u)
if [ "$CHECKED" = "0" ]; then
	echo "      no scripts to check"
elif [ "$FAIL" = "0" ]; then
	echo "      all $CHECKED scripts parse"
fi

# ── Scene / resource integrity ───────────────────────────────────────────────
# Rewritten in awk. The original used python3, which is not installed on this
# machine — and a missing interpreter here fails silently, which is the exact
# failure mode this script exists to prevent.
echo
echo "── Scene / resource integrity ──"
echo "$SCENES" | sort -u | awk '
function grab(s, pre, arr,   i, rest, q) {
	while (1) {
		i = index(s, pre)
		if (i == 0) return
		rest = substr(s, i + length(pre))
		q = index(rest, "\"")
		if (q == 0) return
		arr[substr(rest, 1, q - 1)] = 1
		s = substr(rest, q + 1)
	}
}
function report(path,   id, problems, n, expected, missing) {
	n = 0
	for (id in used)     if (!(id in declared)) { problems[++n] = "undeclared ExtResource: " id }
	for (id in sub_used) if (!(id in sub_dec))  { problems[++n] = "undeclared SubResource: " id }
	if (load_steps != "") {
		expected = count(declared) + count(sub_dec) + 1
		if (load_steps + 0 != expected)
			problems[++n] = "load_steps=" load_steps ", expected " expected
	}
	# A path that does not exist is the silent-null bug: the resource still
	# loads, the entry just vanishes from the array.
	for (id in paths) {
		if ((getline missing < id) < 0) problems[++n] = "missing file: " id
		close(id)
	}
	if (n > 0) {
		bad = 1
		print "FAIL  " path
		for (id = 1; id <= n; id++) print "        " problems[id]
	}
}
function count(arr,   k, c) { c = 0; for (k in arr) c++; return c }
function reset() { delete declared; delete used; delete sub_dec; delete sub_used; delete paths; load_steps = "" }
BEGIN { bad = 0; files = 0 }
{
	path = $0
	sub(/^\.\//, "", path)
	if (path == "") next
	if ((getline probe < path) < 0) { close(path); next }
	close(path)
	files++
	reset()
	while ((getline line < path) > 0) {
		if (line ~ /^\[gd_(scene|resource)/) {
			if (match(line, /load_steps=[0-9]+/))
				load_steps = substr(line, RSTART + 11, RLENGTH - 11)
		}
		# Match " id=\"" with the leading space, not "id=\"". Every ext_resource
		# also carries uid="uid://..." — and "uid=\"" *contains* "id=\"", so the
		# loose match counted each uid as a second declared id and every
		# load_steps in the project looked off by one.
		if (line ~ /^\[ext_resource/) grab(line, " id=\"", declared)
		if (line ~ /^\[sub_resource/) grab(line, " id=\"", sub_dec)
		grab(line, "ExtResource(\"", used)
		grab(line, "SubResource(\"", sub_used)
		grab(line, "path=\"res://", paths)
	}
	close(path)
	report(path)
}
END {
	if (files == 0) print "      no scenes or resources to check"
	else if (!bad)  print "      all " files " scenes and resources consistent"
	exit bad
}
'
[ $? -ne 0 ] && FAIL=1

echo
if [ "$FAIL" = "0" ]; then
	echo "PASS"
else
	echo "FAILED — fix the above before committing."
fi
exit $FAIL
