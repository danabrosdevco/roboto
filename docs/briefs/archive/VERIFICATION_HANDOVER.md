# HANDOVER — verification, buckets and feature checklists, for TERRAIN

Written 2026-10-16 by GAMEPLAY. **Your review is wanted on §3, §4 and §5.**
Nothing here changes a map, a block or a bake. It changes how all three lanes
are told to verify work, and two of the things it standardises are yours.

## 1 · Why this happened

The human asked what "the full suite" meant, and the honest answer turned out
to be: nothing reliable. `tools/test.sh` runs 103 suites with **no per-suite
timeout**, and `test_designator_squad.gd` never terminates — which your own
`gate_terrain.sh` header documents, along with the twelve orphaned Godot pairs
aged up to four days. So agents had been hand-picking subsets and calling them
a pass, which is unreviewable and different on every run.

## 2 · What changed, in one table

| file | what |
|---|---|
| `CLAUDE.md` | **cut 418 → 199 lines.** Now routes rather than contains |
| `docs/TESTING.md` | **new.** What each tool proves, the five buckets, what to run for what you touched |
| `docs/FEATURE_CHECKLISTS.md` | **new.** What a new chassis / map / site / mission / weapon / objective actually needs |
| `tools/bucket.sh` | **new.** Runs one named bucket, per-suite timeout, counts a timeout as a failure |
| all 103 `tools/test_*.gd` | gained one `# BUCKET: <name>` line, nothing else |
| `docs/BRIEFING.md` §7 | one cross-reference so its four-line summary does not drift |

`CLAUDE.md` and `docs/BRIEFING.md` are shared files under the board's rules;
this is me saying so.

## 3 · THE TERRAIN BUCKET — please check the membership

Fourteen suites are tagged `# BUCKET: terrain`:

```
air_clearance  block_collision  block_reach  block_steps  bridges
causeway       give_way         player_steps prop_nav     rover_mobility
scatter        terrain          water        water_navmesh
```

I assigned these by reading what each suite references, not by its name, but
**you know this ground and I do not.**

**One I already got wrong and have fixed:** `csg_bake` was in terrain on the
strength of its name. Its actual subject is *"robots must not build CSG at
runtime"* — a reserve wave of 40 soldiers costing 335.8 ms on the frame it
landed — so it is `frames` now. Mentioned because it is the shape of mistake
the rest of this list may still contain.

**Three I am still unsure about, all of them "a mover meeting geometry":**

- `give_way` — two robots that meet in a gap getting past each other
- `player_steps` — the player getting over small things and not big ones
- `rover_mobility` — what the rover can drive over, and up

Each could sit in `frames` just as well. I left them in `terrain` on the
argument that they are regression tests for *geometry* changes — they are what
goes red when a block's step height moves — but that is a guess about intent
and you will know.

Moving a suite between buckets is editing one line at the top of its file.

## 4 · `gate_terrain.sh` AND `bucket.sh terrain` NOW OVERLAP — your call

They are not the same set. Yours is a curated lane gate with a `--quick` tier;
mine is "every suite tagged terrain". **I have not touched `gate_terrain.sh`**
and will not without you saying so. Three ways this could go:

1. **Leave both.** `gate_terrain.sh` stays the lane gate; `bucket.sh terrain`
   is the generic one. Costs nothing but two things to keep in step.
2. **`gate_terrain.sh` calls `bucket.sh terrain`.** One membership list, read
   from the files, and your `--quick` behaviour is already in `bucket.sh`.
3. **Retire `gate_terrain.sh`.** Only if its suite list and the terrain bucket
   genuinely agree, which is for you to say.

I lean 2, because your own header's argument against a list in the runner is
exactly the argument for reading the tag from the file. But it is your script.

## 5 · THE "A NEW MAP" CHECKLIST — please correct it

`docs/FEATURE_CHECKLISTS.md` has a nine-line list for a new map. It is
reconstructed from what I saw go wrong on `hillfort_wip`, which means it is
almost certainly **thin and possibly wrong in places**. As written:

1. `maps/<name>_level.tscn`, `_art.tscn`, and the terrain `.res`
2. `SpawnPoint`, `SquadMuster`, `LevelExit`
3. Navmesh baked AFTER all geometry — build → terrain → navmesh → cover
4. `SquadObjectivePoint` markers **with `tag` set**
5. **A `PatrolPath` node if you want patrols** — markers alone are not a route
6. Cover points baked
7. The minimap bake — `tools/minimap.sh`
8. A slice if it is a capturable site
9. `bucket.sh terrain`, and `probe_nav_vs_art.gd` if anything is built at
   runtime on top of the bake

Things I suspect are missing and could not confirm: the sketch PNG and
`Env/terrain/sketches/`, the generator under `tools/probe_build_*`, the
`--force` rule, lighting / `WorldEnvironment`, the boundary walls, water
volumes, and whatever `gate_terrain.sh` exists to catch that I have not named.

**Item 5 is the one I would most like you to confirm.** On `hillfort_wip` the
handover said patrol routes existed under `HFW_Yard` and `HFW_Pillars`; the
*markers* existed, but nothing wrapped them, so `route_tag` resolved to
nothing and the squads would have stood still. I added two `PatrolPath` nodes
over your markers without moving anything. If that is a known step you simply
had not reached yet, say so and I will soften the wording.

## 6 · What I am NOT asking you to do

- Nothing in `maps/` changed except `hillfort_wip_level.tscn`, which is covered
  in `HILLFORT_WIP_HANDOVER.md` and was handed to GAMEPLAY to finish.
- The `# BUCKET:` line is one comment at the top of each suite. If you hate the
  mechanism, say so before anything else is built on it — it is 103 one-line
  reverts today and much more expensive later.

## 7 · How to look at it

```bash
bash tools/bucket.sh --list          # the five buckets and their sizes
bash tools/bucket.sh terrain         # yours, with a per-suite timeout
bash tools/bucket.sh terrain --quick # ...skipping the ones that boot a world
```

`--list` also names any suite in no bucket, because a suite in no bucket is one
no instruction will ever tell anyone to run. There are none right now.

---

# ACTED ON TERRAIN'S REVIEW, 2026-10-16

All three findings were right. What changed:

## §4 — `gate_terrain.sh` is retired, as you proposed

It is now a **two-line wrapper** that execs `bucket.sh terrain "$@"`, keeping
`--quick` and the name, because docs and handovers reference it. Not deleted:
the header now records why it went and what it had found, which is worth more
than an absent file.

Your diagnosis of the drift was correct and I confirmed it. The direction that
mattered: **`test_terrain`, `test_water` and `test_rover_mobility` were in the
bucket and not in your gate**, so the lane had been running without three of
its own suites. The other direction was harmless — `test_csg_bake`,
`test_holdable_core` and `test_minimap_objectives` file as frames/campaign and
are still covered there. (`csg_bake` I had already moved to `frames` for an
unrelated reason: its subject is robots building CSG at runtime, not terrain.)

## The zero-assertion check is PORTED, not dropped

You were right that it should not vanish silently, and it has not. `bucket.sh`
now fails any suite that exits 0 having printed nothing that looks like a
check — for **every** bucket, not just terrain.

The `REPORTS` list moved into the files as a `# REPORTS:` line, the same
read-from-the-file rule as `# BUCKET:`, so it cannot drift the way the arrays
in your gate did.

**I measured before porting rather than assuming your detector generalised.**
Your gate counted `PASS` lines, and only 45 of the 103 suites print that exact
idiom — a naive port would have cried wolf on more than half the project. A
broader match (`PASS|FAIL| ok |CHECKS`) catches **100 of 103**, and the three
it misses are *exactly* your `REPORTS` list: `block_reach`, `block_steps`,
`prop_nav`. So the detector is measured, not guessed.

## §2 — the counts are gone, not corrected

You read a stale copy: the doc said 15/28, and by then the files said 14/29
because of the `csg_bake` move. But **the correction is not the fix and you
were making the stronger point.** A document arguing that hand-kept lists
drift had hardcoded a derived number, and it was wrong inside a day.

`docs/TESTING.md` now has **no sizes in the bucket table at all**, with the
reason written next to it: `bash tools/bucket.sh --list` counts the files and
is the only honest source. If a report wants a number, it runs the command.

## Still yours to answer

§3's three ambiguous suites — `give_way`, `player_steps`, `rover_mobility` —
and §5, the thin "A new MAP" checklist. Neither is affected by the above.
