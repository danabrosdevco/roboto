#!/usr/bin/env bash
# Boots the game headless and fails on runtime errors.
#
# WHY. check.sh proves scripts PARSE. It cannot prove they RUN. A script that
# parses perfectly still throws on frame one from a null node path, a bad cast
# or an unassigned export — and until this existed, that whole class of problem
# was only visible to whoever launched the editor and read the debugger.
#
# Usage:  tools/smoke.sh [seconds]     default 15
#
# Exit 0 = booted and ran for the full window with no errors.

set -uo pipefail
cd "$(dirname "$0")/.."

SECONDS_TO_RUN="${1:-15}"

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
	echo "Godot not found. Set GODOT=/path/to/Godot_..._console.exe"
	exit 2
fi

LOG="$(mktemp 2>/dev/null || echo ./.smoke.log)"

echo "── Booting headless for ${SECONDS_TO_RUN}s ──"
# The game never exits on its own, so it is killed after the window. A non-zero
# status from timeout's SIGTERM is the EXPECTED outcome; only the log matters.
# `-- --no-save`: the game saves on reaching base, and this boots the real
# game, so without it every smoke run rewrote the player's campaign.json.
timeout "${SECONDS_TO_RUN}s" "$GODOT" --headless --path . -- --no-save > "$LOG" 2>&1
boot_status=$?

# Real failures. Godot prints runtime script problems as SCRIPT ERROR / ERROR,
# and an uncaught one usually drags a stack trace with it.
ERRORS='SCRIPT ERROR|Parse Error|Compile Error|Cannot call method|Invalid call|Invalid get index|Invalid set index|Attempt to call|null instance'

# Assets that are not in the repo, and the func_godot addon's own noise. Same
# list check.sh filters, for the same reason: without it nothing real is visible.
NOISE='entity_fgd|ext_resource.*non-existent|Failed loading resource|Make sure resources|icon_slipgate|func_godot|Cannot open file|custom project font'

found=$(grep -E "$ERRORS" "$LOG" | grep -Ev "$NOISE" | head -25)

echo
if [ -n "$found" ]; then
	echo "── Runtime errors ──"
	echo "$found" | sed 's/^/    /'
	echo
	echo "FAILED — the project boots but throws. Full log: $LOG"
	exit 1
fi

# timeout returns 124 when it had to kill the process, which here means the game
# was still running happily. Anything else means it died early on its own.
if [ "$boot_status" -ne 124 ] && [ "$boot_status" -ne 0 ]; then
	echo "── Exited early (status $boot_status) ──"
	tail -25 "$LOG" | sed 's/^/    /'
	echo
	echo "FAILED — did not survive the ${SECONDS_TO_RUN}s window. Full log: $LOG"
	exit 1
fi

warnings=$(grep -cE "WARNING|push_warning" "$LOG" 2>/dev/null || echo 0)
echo "      booted clean, ran ${SECONDS_TO_RUN}s, ${warnings} warning line(s)"
echo
echo "PASS"
rm -f "$LOG"
exit 0
