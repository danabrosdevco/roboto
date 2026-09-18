#!/usr/bin/env bash
# Merge playtest sessions into one report.
#
# Usage:  tools/analytics.sh <folder>
#         tools/analytics.sh            (this machine's own sessions)
#
# Unzip each tester's analytics folder into <folder>, side by side. Every
# events.jsonl underneath is read, and <folder>/combined_report.md is written
# with the same tables the game writes per session.

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

ARGS=()
if [ $# -gt 0 ]; then
	# Godot wants a Windows path, not Git Bash's /d/... form.
	if command -v cygpath >/dev/null 2>&1; then
		ARGS=(-- "$(cygpath -m "$1")")
	else
		ARGS=(-- "$1")
	fi
fi

"$GODOT" --headless --path . --script res://tools/analytics_report.gd "${ARGS[@]}" 2>&1 \
	| grep -vE "^Godot Engine|^$|godotengine\.org"
exit "${PIPESTATUS[0]}"
