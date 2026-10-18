#!/usr/bin/env bash
# ─────────────────────────────────────────────
# RUN ONE BUCKET OF SUITES, BY NAME.
#
#   bash tools/bucket.sh campaign
#   bash tools/bucket.sh terrain --quick     # skip suites that boot world.tscn
#   bash tools/bucket.sh --list              # what buckets exist, and their size
#   SUITE_TIMEOUT=600 bash tools/bucket.sh frames
#
# WHY THIS EXISTS. Agents were picking their own subsets — "the suites this
# touched" — which is a list invented fresh each time, unreviewable, and
# different on every run. A bucket is a NAMED set somebody agreed to, so
# "campaign passed, 40 suites" means the same thing twice running.
#
# MEMBERSHIP IS READ FROM THE FILE, never from a list in here. Each suite
# carries a `# BUCKET: <name>` line near the top. That is deliberate and it is
# the same rule tools/test.sh uses for its --fast tier: a list kept in the
# runner drifts the first time somebody adds a suite and forgets, and a drifted
# list is worse than no list because it still reports a pass.
#
# AN UNTAGGED SUITE IS NAMED AND COUNTED AS A PROBLEM. A suite in no bucket is
# a suite no instruction will ever tell anyone to run.
#
# A SUITE THAT ASSERTS NOTHING IS A FAILURE, not a pass. Ported from
# gate_terrain.sh, whose first version counted PASS lines and so reported a
# suite that checks nothing as "ok (0 pass)" — the exact failure this project
# keeps rediscovering. An exit code cannot tell "everything passed" from
# "nothing ran": both are 0.
#
# Three suites legitimately print a table and assert nothing. They carry a
# `# REPORTS:` line, the same read-from-the-file way buckets work, so they are
# told apart from a suite that has silently stopped testing. Measured across
# all 103 suites: 100 print a recognisable assertion line, and the 3 that do
# not are exactly those three. The detector is not a guess.
#
# THE TIMEOUT IS THE POINT, same as gate_terrain.sh. tools/test.sh has none,
# and tools/test_designator_squad.gd never terminates — so one hang stalls
# everything behind it and leaves orphaned Godot pairs behind. Here a suite
# that overruns is killed, reported as TIMEOUT, and COUNTED AS A FAILURE,
# because a suite nobody can finish is a suite nobody is watching.
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

# Per suite, not for the run. Raise it with SUITE_TIMEOUT rather than editing.
TIMEOUT="${SUITE_TIMEOUT:-240}"

bucket_of() { sed -n 's/^# BUCKET: *//p' "$1" | head -1; }

# ── --list ───────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--list" ] || [ -z "${1:-}" ]; then
	echo "BUCKETS"
	for b in campaign terrain frames kit shell; do
		n=0
		for f in tools/test_*.gd; do
			[ "$(bucket_of "$f")" = "$b" ] && n=$((n + 1))
		done
		printf "  %-10s %3d suite(s)\n" "$b" "$n"
	done
	untagged=""
	for f in tools/test_*.gd; do
		[ -z "$(bucket_of "$f")" ] && untagged="$untagged $(basename "$f" .gd)"
	done
	if [ -n "$untagged" ]; then
		echo
		echo "UNTAGGED — in no bucket, so nothing will ever tell anyone to run them:"
		echo "  $untagged"
	fi
	echo
	echo "Usage: bash tools/bucket.sh <name> [--quick]"
	exit 0
fi

WANT="$1"
QUICK=0
[ "${2:-}" = "--quick" ] && QUICK=1

case " campaign terrain frames kit shell " in
	*" $WANT "*) ;;
	*) echo "No bucket '$WANT'. Run with --list."; exit 2 ;;
esac

FAIL=0
RAN=0
SKIPPED=0
REPORTED=0
PARKED_N=0
PARKED_NAMES=""
FAILED_NAMES=""

for suite in tools/test_*.gd; do
	[ -f "$suite" ] || continue
	[ "$(bucket_of "$suite")" = "$WANT" ] || continue
	base="$(basename "$suite" .gd)"
	# The world is the expensive part, so its presence is the tier marker —
	# read from the file, exactly as test.sh --fast does it.
	if [ "$QUICK" = "1" ] && grep -q "world.tscn" "$suite"; then
		SKIPPED=$((SKIPPED + 1))
		continue
	fi
	# PARKED — known to be failing on authored content, not on logic, and
	# named in its own file with the reason. Skipped here AND by test.sh, both
	# reading the same tag, because two runners with different opinions about
	# what is parked is how `bucket.sh terrain` first reported FAIL on a suite
	# test.sh had deliberately been skipping for days.
	#
	# A parked suite is a suite nobody is watching. The summary names them.
	if grep -q "^# PARKED:" "$suite"; then
		echo "── $base ── PARKED: $(sed -n 's/^# PARKED: *//p' "$suite" | head -1)"
		echo
		PARKED_N=$((PARKED_N + 1))
		PARKED_NAMES="$PARKED_NAMES $base"
		continue
	fi
	RAN=$((RAN + 1))
	echo "── $base ──"
	out="$(timeout "${TIMEOUT}s" "$GODOT" --headless --audio-driver Dummy --path . \
		--script "res://$suite" 2>&1)"
	status=$?
	# THE NOISE FILTER, AND IT IS NOT COSMETIC.
	#
	# Measured across three buckets: 15,748 lines of output, 13,356 of them
	# noise — 84%. In a REAL boot, 254 of 267 ERROR lines are one harmless
	# dummy-renderer artifact. When 95% of errors are noise nobody reads
	# errors, and three real ones sat in plain sight for weeks because of it.
	#
	# WHAT IS DROPPED, and why each is safe:
	#   Parameter "m" is null / mesh_get_surface_count
	#       the headless dummy renderer has no mesh storage, so EVERY
	#       primitive mesh logs this. Nothing to do with the project.
	#   at: push_warning (core/variant/variant_utility...)
	#       the boilerplate second line of every push_warning. The warning
	#       itself is kept — only its "this came from push_warning" is cut.
	#   ObjectDB instances leaked at exit
	#       fires on almost every tool run and says nothing actionable
	#       without --verbose.
	#
	# EVERY OTHER `at:` LINE IS KEPT, because that is where a real error says
	# which file it came from — "at: (core/variant/array.cpp:245)" is how the
	# one genuine engine bug in this project was located.
	printf '%s\n' "$out" | grep -vE "^Godot Engine|^$|godotengine\.org|Parameter \"m\" is null|at: mesh_get_surface_count|at: push_warning \(core/variant|ObjectDB instances leaked"
	# Any line that looks like an assertion result. Deliberately broad — the
	# house style is `PASS`/`FAIL` per check, but plenty of suites print
	# `  ok  ` rows or a single `ALL ... CHECKS PASS`, and all of them count.
	asserted="$(printf '%s\n' "$out" | grep -cE "PASS|FAIL| ok |CHECKS")"
	if [ "$status" -eq 124 ]; then
		echo "   TIMEOUT after ${TIMEOUT}s — counted as a failure."
		FAIL=1
		FAILED_NAMES="$FAILED_NAMES $base(timeout)"
	elif [ "$status" -ne 0 ]; then
		FAIL=1
		FAILED_NAMES="$FAILED_NAMES $base"
	elif [ "$asserted" -eq 0 ]; then
		# Exit 0 and nothing that looks like a check. Either a declared report
		# or a suite that has stopped testing, and those are indistinguishable
		# from out here — which is why the tag is in the file, not guessed.
		if grep -q "^# REPORTS" "$suite"; then
			echo "   (report — prints a table, asserts nothing, declared)"
			REPORTED=$((REPORTED + 1))
		else
			echo "   ASSERTED NOTHING — exit 0 with no checks. Counted as a failure."
			echo "   If that is deliberate, give it a '# REPORTS:' line saying why."
			FAIL=1
			FAILED_NAMES="$FAILED_NAMES $base(no-assertions)"
		fi
	fi
	echo
done

echo "─────────────────────────────────────────"
NOTE=""
[ "$SKIPPED" -gt 0 ] && NOTE=" ($SKIPPED skipped, --quick)"
[ "$REPORTED" -gt 0 ] && NOTE="$NOTE ($REPORTED report-only)"
if [ "$PARKED_N" -gt 0 ]; then
	NOTE="$NOTE ($PARKED_N PARKED:$PARKED_NAMES)"
fi
if [ "$FAIL" -eq 0 ]; then
	echo "PASS  bucket '$WANT' — $RAN suite(s)$NOTE"
else
	echo "FAIL  bucket '$WANT' — $RAN suite(s)$NOTE"
	echo "      failed:$FAILED_NAMES"
fi
exit $FAIL
