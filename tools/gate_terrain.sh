#!/usr/bin/env bash
# ─────────────────────────────────────────────
# GATE TERRAIN — the suites that cover geometry, blocks and navigation, with a
# per-suite timeout so one hung suite cannot cost the whole run.
#
#   bash tools/gate_terrain.sh            # the lane's suites
#   bash tools/gate_terrain.sh --quick    # only the ones that never boot the world
#   SUITE_TIMEOUT=600 bash tools/gate_terrain.sh
#
# WHY THIS EXISTS AND WHY IT IS NOT test.sh --fast.
#
# tools/test.sh runs 141 suites and has no timeout on any of them. Through
# October it repeatedly failed to finish, and the cause turned out not to be
# slowness: tools/test_designator_squad.gd NEVER TERMINATES. Twelve orphaned
# Godot process pairs from it were found still running, aged eighteen hours to
# four days, about 95 MB each — and because test.sh waits on each suite
# forever, one leak stalls everything behind it. The full gate was skipped
# three times running on terrain work that could not possibly have broken it.
#
# So this is not a replacement for test.sh and must not become one. It is the
# subset a TERRAIN change can actually break, bounded in time, so that there is
# never a reason to ship geometry with no test behind it. When the whole suite
# is healthy again, run that.
#
# THE TIMEOUT IS THE POINT. A suite that overruns is reported as TIMEOUT and
# the run carries on. A timeout is NOT a pass: it is counted as a failure and
# named in the summary, because a suite nobody can finish is a suite nobody is
# watching.
#
# AND IT CLEANS UP AFTER ITSELF. Each suite's Godot is killed if it overruns,
# so this script cannot be what leaves orphans behind for the next lane.
# ─────────────────────────────────────────────
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

# Per suite, not for the run. 240 s is roughly four times the slowest of these
# on an unloaded machine; raise it with SUITE_TIMEOUT rather than editing here.
TIMEOUT="${SUITE_TIMEOUT:-240}"

# THE LANE'S SUITES. Geometry, blocks, prefabs, navigation and the things that
# stand on them. A suite belongs here if a change under maps/, tools/block_*,
# tools/build_* or a navmesh setting could plausibly break it.
#
# Deliberately NOT here: the ledger, the armoury, the store, missions, the HUD
# and anything about weapons. Terrain does not touch them, and including them
# would make this slow enough to skip — which is the failure it exists to fix.
SUITES_QUICK="
test_block_collision
test_block_reach
test_block_steps
test_bridges
test_causeway
test_prop_nav
test_water_navmesh
test_scatter
test_holdable_core
"

## REPORTS, NOT TESTS — and naming them is the point.
##
## These three print a table and assert nothing, so they cannot fail. The first
## version of this script counted PASS lines and therefore reported them as
## "ok (0 pass)", which is how a gate ends up blessing a suite that checks
## nothing — the exact failure this project keeps rediscovering.
##
## They stay in the run because the tables are worth reading. They are listed
## here so the summary can say so, and so that ANY OTHER suite finishing with
## no assertions is treated as a FAILURE: a test that has silently stopped
## testing looks identical to one that passed, and only this list tells them
## apart.
REPORTS="test_block_reach test_block_steps test_prop_nav"
## These boot world.tscn, so they are slower. --quick leaves them out.
SUITES_WORLD="
test_air_clearance
test_csg_bake
test_player_steps
test_give_way
test_minimap_objectives
"

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

LIST="$SUITES_QUICK"
[ "$QUICK" = "0" ] && LIST="$SUITES_QUICK $SUITES_WORLD"

FAIL=0
RAN=0
MISSING=""
TIMEDOUT=""
REPORTED=""
SILENT=""
ASSERTIONS=0
FAILED=""

echo "── GATE TERRAIN ──  timeout ${TIMEOUT}s a suite$([ "$QUICK" = "1" ] && echo ", --quick")"
echo

for base in $LIST; do
	suite="tools/$base.gd"
	if [ ! -f "$suite" ]; then
		MISSING="$MISSING $base"
		continue
	fi
	RAN=$((RAN + 1))
	printf "── %-26s " "$base"
	out="$(timeout --kill-after=10 "$TIMEOUT" \
		"$GODOT" --headless --audio-driver Dummy --path . --script "res://$suite" 2>&1)"
	status=$?
	nfail="$(printf '%s\n' "$out" | grep -c '^FAIL' || true)"
	npass="$(printf '%s\n' "$out" | grep -c '^PASS' || true)"
	if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
		# NOT A PASS. See the header: a suite nobody can finish is a suite
		# nobody is watching, so it is counted against the run.
		echo "TIMEOUT after ${TIMEOUT}s"
		TIMEDOUT="$TIMEDOUT $base"
		FAIL=1
	elif [ "$nfail" -gt 0 ] || [ "$status" -ne 0 ]; then
		echo "FAIL  ($npass pass, $nfail fail)"
		printf '%s\n' "$out" | grep '^FAIL' | sed 's/^/      /'
		FAILED="$FAILED $base"
		FAIL=1
	elif [ "$npass" -eq 0 ]; then
		# No PASS and no FAIL. Either a known report, or a suite that has
		# stopped asserting — and those look identical from out here, which is
		# why REPORTS is an explicit list rather than a guess.
		case " $REPORTS " in
			*" $base "*)
				echo "report (no assertions, by design)"
				REPORTED="$REPORTED $base"
				;;
			*)
				echo "NO ASSERTIONS — this suite tested nothing"
				SILENT="$SILENT $base"
				FAIL=1
				;;
		esac
	else
		echo "ok    ($npass pass)"
		ASSERTIONS=$((ASSERTIONS + npass))
	fi
done

echo
echo "── ${RAN} suite(s) run, ${ASSERTIONS} assertion(s) ──"
[ -n "$MISSING" ]  && echo "  not found:$MISSING  (renamed or deleted — fix this list)"
[ -n "$TIMEDOUT" ] && echo "  TIMED OUT:$TIMEDOUT"
[ -n "$FAILED" ]   && echo "  FAILED:$FAILED"
[ -n "$SILENT" ]   && echo "  TESTED NOTHING:$SILENT  (not in the REPORTS list — a suite stopped asserting)"
[ -n "$REPORTED" ] && echo "  reports (no assertions, by design):$REPORTED"
echo
if [ "$FAIL" -eq 0 ]; then
	echo "PASS"
	echo
	echo "  This is the lane's subset, not the whole gate. tools/test.sh is the"
	echo "  full run; use it when the suite is healthy enough to finish."
else
	echo "FAILED"
fi
exit "$FAIL"
