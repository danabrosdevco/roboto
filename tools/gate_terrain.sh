#!/usr/bin/env bash
# ─────────────────────────────────────────────
# RETIRED 2026-10-16 — this is now a wrapper around `bucket.sh terrain`.
#
#   bash tools/gate_terrain.sh            # the lane's suites
#   bash tools/gate_terrain.sh --quick    # only the ones that never boot a world
#
# WHY IT WENT. This script existed because tools/test.sh has no per-suite
# timeout and tools/test_designator_squad.gd never terminates, so one hang
# stalled everything behind it. tools/bucket.sh now has that timeout, counts a
# timeout as a failure, and kills the overrunning Godot — which was this
# script's entire reason to exist.
#
# AND IT HAD BECOME THE DRIFTING LIST ITS OWN HEADER WARNED ABOUT. It
# hand-maintained two suite arrays, and TERRAIN found they had diverged from
# `# BUCKET: terrain` in both directions. Three suites squarely in this lane —
# test_terrain, test_water, test_rover_mobility — were in the bucket and NOT
# in this gate, so the lane had been running without them. The other direction
# was harmless: test_csg_bake, test_holdable_core and test_minimap_objectives
# were here but file as frames/campaign, so they are still covered elsewhere.
#
# WHAT WAS WORTH KEEPING CAME WITH IT. This gate could fail a suite that
# finishes with zero assertions — an exit code cannot tell "everything passed"
# from "nothing ran", and a test that has silently stopped testing looks
# exactly like one that passed. That check is now in bucket.sh for every
# bucket, and the three report-style suites that legitimately assert nothing
# (block_reach, block_steps, prop_nav) declare it with a `# REPORTS:` line in
# the file rather than a list in a runner.
#
# The name is kept because docs and handovers reference it. Membership now
# lives in the suites themselves: `# BUCKET: terrain`.
# ─────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.."

echo "gate_terrain.sh is retired — running 'bucket.sh terrain' instead."
echo "Membership is now the '# BUCKET: terrain' line in each suite."
echo

exec bash tools/bucket.sh terrain "$@"
