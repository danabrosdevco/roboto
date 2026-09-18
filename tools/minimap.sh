#!/usr/bin/env bash
# Bakes a top-down map image + objective metadata for each level.
#
# NOT headless: the dummy renderer returns blank textures, so this opens a
# window for a few seconds. That is expected — let it run.
#
# Pass a substring to bake one level:   bash tools/minimap.sh valley
set -uo pipefail
cd "$(dirname "$0")/.."

if [ -z "${GODOT:-}" ]; then
	for candidate in \
		"/d/Godot Games/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe" \
		"/c/Program Files/Godot/Godot_v4.3-stable_win64_console.exe" \
		"godot"
	do
		if [ -x "$candidate" ] || command -v "$candidate" >/dev/null 2>&1; then
			GODOT="$candidate"; break
		fi
	done
fi
[ -z "${GODOT:-}" ] && { echo "Godot not found. Set GODOT=..."; exit 2; }

echo "── Minimap bake ──"
OUT=$("$GODOT" --path . --script tools/minimap_bake.gd -- "${1:-}" 2>&1)
echo "$OUT" | grep -E "^OK|^FAIL" | sed 's/^/      /'
if echo "$OUT" | grep -q "MINIMAP BAKE DONE"; then
	echo
	echo "Reimporting so the new PNGs become loadable textures..."
	"$GODOT" --headless --path . --import >/dev/null 2>&1
	echo "PASS"
	exit 0
fi
echo "$OUT" | grep -E "SCRIPT ERROR|Parse Error" | head -5
echo "FAILED"
exit 1
