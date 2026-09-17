#!/usr/bin/env bash
# Runs every tools/test_*.gd headless.
#
# These test LOGIC, not scenes — the ledger, and anything else whose rules can
# be stated as "after this sequence, that must be true". They complement
# check.sh, which only proves scripts parse.
#
# Exit code 0 = all suites passed.

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

FAIL=0
FOUND=0

for suite in tools/test_*.gd; do
	[ -f "$suite" ] || continue
	FOUND=$((FOUND + 1))
	echo "── $(basename "$suite") ──"
	# The engine banner is on stdout and says nothing useful here.
	"$GODOT" --headless --path . --script "res://$suite" 2>&1 \
		| grep -vE "^Godot Engine|^$|godotengine\.org"
	status=${PIPESTATUS[0]}
	if [ "$status" -ne 0 ]; then
		FAIL=1
	fi
	echo
done

if [ "$FOUND" = "0" ]; then
	echo "no test suites found (tools/test_*.gd)"
	exit 0
fi

if [ "$FAIL" = "0" ]; then
	echo "ALL SUITES PASS"
else
	echo "SUITE FAILURES — see above."
fi
exit $FAIL
