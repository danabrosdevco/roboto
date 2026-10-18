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

# PARKED SUITES — skipped, with the reason travelling IN THE SUITE as a
# `# PARKED:` line rather than in a list here. Bringing one back is deleting
# that line, and nobody has to wonder why a suite stopped running.
#
# IT MOVED OUT OF THIS FILE ON 2026-10-16, and the reason is worth keeping:
# tools/bucket.sh needs the same answer, and when the list lived here only
# this script could see it — so `bucket.sh terrain` reported FAIL on
# test_terrain, which this script had been deliberately skipping for days.
# Two runners, two lists, two different opinions about the same suite. The tag
# travels with the file, so they cannot disagree.
#
# Parked as of the move, both failing on authored content and not on logic:
#   test_terrain    template and mutaha load with terrain.data null — 99 of
#                   its 101 checks were passing, so narrowing it to the two
#                   level checks would let the rest gate again
#   test_tutorial   the depot has no lesson signs left
#
# A parked suite is a suite nobody is watching. Put them back.

# PACE THE LOOP: Engine.max_fps = 60, IN EVERY SUITE THAT BOOTS A WORLD.
#
# A `--script` run has NO FRAME CAP. `_process` then spins as fast as the
# machine allows and starves the physics tick, so every `await physics_frame`
# waits far longer in wall clock than the 1/60 s it is written as — and the
# settle loops here run as long as `for _i in 900`. That is most of why this
# suite was slow.
#
# On one suite it crossed from slow into looking BROKEN:
# tools/test_designator_squad.gd set neither this nor Settings.path and
# produced no output at all before a 150 s timeout. Adding the cap turned the
# silent hang into the real error underneath it (an out-of-bounds array read
# during world settle). A hang is the worst way for a test to fail, because it
# looks like the machine rather than the code.
#
# 2026-10-14: 47 suites boot a world and only 4 capped the loop. All of them do
# now. If you write a new suite that boots a world, put the line in.
#
# WHY THE WHOLE SUITE STILL TAKES A WHILE, and what --fast is for.
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
PARKED_NAMES=""

for suite in tools/test_*.gd; do
	[ -f "$suite" ] || continue
	base="$(basename "$suite" .gd)"
	# PARKED — READ FROM THE SUITE, not from a list here. The list that used to
	# live in this script is below, kept only as history: tools/bucket.sh also
	# needs to know what is parked, and two runners with separate lists is how
	# `bucket.sh terrain` reported FAIL on a suite this one had deliberately
	# been skipping. The tag travels with the file, so it cannot disagree.
	if grep -q "^# PARKED:" "$suite"; then
		echo "── $base.gd ── PARKED: $(sed -n 's/^# PARKED: *//p' "$suite" | head -1)"
		echo
		SKIPPED=$((SKIPPED + 1))
		PARKED_NAMES="$PARKED_NAMES $base"
		continue
	fi
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
	# NO `-- --no-save` HERE, and it is worth knowing why not, because it looks
	# like an omission next to smoke.sh.
	#
	# smoke.sh needs that flag because it boots the game WITHOUT --script, so
	# SaveSlots hands it the player's real campaigns. A suite does not: every
	# tool run has --script, and SaveSlots._is_tool_run points DIR at
	# user://saves_probe for exactly this reason — see the note on DIR. The
	# sandbox is already there.
	#
	# The flag was added here once, on the strength of a before/after mtime
	# check that appeared to catch test_mechanic and test_teams writing the
	# player's save. It did not catch that: an mtime check around a 90-second
	# suite cannot tell "this suite wrote the file" from "something else wrote
	# it while this suite ran", and the player was in the game at the time.
	# Four clean runs of both suites afterwards, no writes.
	#
	# And the flag is not free. --no-save disables saving globally, which is
	# the exact behaviour test_profiles and test_profile_menu exist to prove:
	# it cost 22 assertions across those two suites, all of them reading as
	# real failures.
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
	SKIP_NOTE=" ($SKIPPED not run$([ "$FAST_ONLY" = "1" ] && echo ", fast tier only")$([ -n "$PARKED_NAMES" ] && echo "; parked:$PARKED_NAMES"))"
else
	SKIP_NOTE=""
fi

if [ "$FAIL" = "0" ]; then
	echo "ALL SUITES PASS$SKIP_NOTE"
else
	echo "SUITE FAILURES — see above.$SKIP_NOTE"
fi
exit $FAIL
