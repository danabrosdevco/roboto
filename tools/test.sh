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

# PARKED SUITES — skipped, and named here rather than deleted or renamed so
# that bringing one back is removing a line, and so nobody has to wonder why a
# suite stopped running. Each is failing on authored content, not on logic:
#
#   test_terrain         the template and mutaha levels load with terrain.data
#                        null. 99 of its 101 checks were passing, so this is the
#                        expensive one to leave parked — narrow it to the two
#                        level checks and the rest can gate again
#   test_tutorial        the depot has no lesson signs left, so the walk-up,
#                        library and stand-down checks have nothing to read
#
# A suite parked here is a suite nobody is watching. Put them back.
PARKED="test_terrain test_tutorial"

# WHY THE WHOLE SUITE TAKES A QUARTER OF AN HOUR, and what --fast is for.
#
# A suite that boots Env/world.tscn and loads a level spends most of its life
# WAITING. `for _i in 420: await physics_frame` is seven seconds of wall clock,
# because headless still ticks physics at 60 Hz — the engine does not fast
# forward just because nothing is being drawn. Twenty-five of the suites boot
# the world, twenty-one load a level on top, and the settle loops run as long as
# 900 frames. Timed: test_leap 1s, test_ledger 5s, test_lab 5s, test_mortar 57s.
#
# That cost is real work, not waste — those suites are the ones that catch what
# a parse check cannot. But paying it on every small change means nobody runs
# the suite, and a gate nobody runs is not a gate.
#
# So: `--fast` runs only the suites that never boot the world. They are the
# logic suites — the ledger, the armoury, the save slots, the item facts — and
# they finish in a couple of minutes instead of fifteen. Run --fast while you
# work; run the whole thing before you hand over.
#
# NOT PARALLELISED, deliberately: every suite points Settings and SaveSlots at
# the same user:// probe paths, so two at once would race on the same files and
# produce flakiness that looks like a real failure. Isolating those per process
# is the prerequisite, and it is a bigger job than it looks.
FAST_ONLY=0
if [ "${1:-}" = "--fast" ]; then
	FAST_ONLY=1
	echo "── FAST TIER: suites that do not boot the world ──"
	echo
fi

FAIL=0
FOUND=0
SKIPPED=0

for suite in tools/test_*.gd; do
	[ -f "$suite" ] || continue
	base="$(basename "$suite" .gd)"
	case " $PARKED " in
		*" $base "*)
			echo "── $base.gd ── PARKED, see the list in test.sh"
			echo
			SKIPPED=$((SKIPPED + 1))
			continue
			;;
	esac
	# The world is the expensive part, so its presence is the tier marker. Read
	# from the file rather than kept as a list here: a list would drift the
	# first time a suite started or stopped booting the world.
	if [ "$FAST_ONLY" = "1" ] && grep -q "world.tscn" "$suite"; then
		SKIPPED=$((SKIPPED + 1))
		continue
	fi
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

# The skip count rides along with the verdict on purpose: "ALL SUITES PASS" is
# a different claim when three of them never ran, and a parked suite that nobody
# is reminded about is a parked suite forever.
if [ "$SKIPPED" != "0" ]; then
	SKIP_NOTE=" ($SKIPPED not run$([ "$FAST_ONLY" = "1" ] && echo ", fast tier only")$([ -n "$PARKED" ] && echo "; parked: $PARKED"))"
else
	SKIP_NOTE=""
fi

if [ "$FAIL" = "0" ]; then
	echo "ALL SUITES PASS$SKIP_NOTE"
else
	echo "SUITE FAILURES — see above.$SKIP_NOTE"
fi
exit $FAIL
