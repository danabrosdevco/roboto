#!/usr/bin/env bash
# Instantiates every mission's level and runs the real EnemyForceSpawner,
# then checks the bodies that landed match what the mission describes.
#
# Exists because a data-level check cannot catch a spawn GATE bug: Valley Siege
# once parsed as 45 hostiles and loaded as an empty valley, because the spawner
# skipped every spec whose legacy `count` was 0.
set -uo pipefail
cd "$(dirname "$0")/.."

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

echo "── Mission spawn check ──"
OUT=$("$GODOT" --headless --path . --script tools/spawn_check.gd 2>&1)
echo "$OUT" | grep -E "^PASS|^FAIL" | sed 's/^/      /'
echo

if echo "$OUT" | grep -q "ALL MISSIONS SPAWN AS AUTHORED"; then
	echo "PASS"
	exit 0
fi
echo "$OUT" | grep -E "DO NOT SPAWN"
echo "FAILED — a mission does not spawn what it describes."
exit 1
