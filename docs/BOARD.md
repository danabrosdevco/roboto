# Board

**The one place.** What is next, and what needs you. Opened 2026-09-23,
restructured 2026-09-28 into a single file so there is nowhere else to look.

**Shipping to: RECORD READY 2026-10-01 · PLAYTEST BUILD 2026-10-08.**

`todo.txt` is a pointer to this. The long-lived reference lives elsewhere and
this file does not repeat it: `docs/GDD.md` is what the game contains,
`docs/BRIEFING.md` is how the code is shaped, `docs/GAMEPLAN.md` is the
argument for the demo's dramatic arc.

---

## YOUR DESK

Only you can clear these. If this list is long, the agents are blocked and the
board has failed.

### Look at

1. **Play coast road, basin and Mutaha, and say which is most fun and which is
   most broken.** This is the only input M1 needs from you, and it cannot be
   delegated — three missions exist and nobody has said whether any of them is
   enjoyable. Everything else on the roadmap is a fix; this is the judgement.
2. **Three of four squad orders lose 100% of the time** in the Laboratory. You
   said you would test this while working — parked, not chased.

**Deferred on purpose — Mutaha's draw-call count.** Comes back the moment the
rework lands. It is risk #2 on the roadmap.

Nothing else is waiting on you. Mutaha WIP approved, Bridge07 confirmed.

### Already ruled — kept here until the code catches up

- Falloff stays; early guns should drop off hard. Explosives not degrading is
  accepted. MG and GL rovers test about equal today.
- `armour_class` goes on `ChassisDefinition` only; `Enemy` does not carry it.
- The Nest stays as it is — a structure that does not move, and the first of
  many enemy structures.
- AI shotgun switched to pellets; the in-game number is correct as it stands.
- `valley_level` is dead. `arena_level` and `homebase_level` look dead too.
- Chaser and Leaper are enemy frames, not stock. Removed from the shop.
- Fitted kit is not faction-painted; it gets its own materials.
- The capsule soldier stays. An anatomical body was built and rejected.
- **The Mutaha WIP is approved.** "I dig mutaha wip" — 2026-09-28. Keep
  building on the copy; it gets promoted over `mutaha_level.tscn` when you say
  it is finished, not before.
- **`Bridge07` / `SouthCrossing` stays.** It is what was asked for. The west
  bank keeps its southern route.
- **Supply is not a fixed pool — it is bought.** Seats and upgrades come out of
  COMPUTE the player allocates in the software and factory screens, so the cap
  is whatever they chose to spend on it. Ruled 2026-09-28.
- **The player CAN carry anti-armour** — but the answer to the long-range-god
  problem is to give the player *better things to want*, not to deny them the
  option. Ruled 2026-09-28; see BACKLOG "player-side kit worth carrying".
- **Armour is RULED, 2026-09-28.** FLAT applies AFTER range falloff; full rule,
  classes, damage types and the counter are in `docs/briefs/ARMOUR.md`.
- **Review happens by playtesting as changes pull through**, not in GitHub
  Desktop. The working tree being busy is not a blocker.

---

## NOW

One item per lane. Not two.

| Lane | Item | State |
|---|---|---|
| TERRAIN | **Mutaha rework — apartment blocks** | WIP approved; larger blocks asked for direct |
| GAMEPLAY | **Mutaha: make it good** | live; activation distance already 250 → 120 |
| MARKETING | **pitch + shot lists for the three recording missions** | new lane, briefed 2026-09-28 |
| COORDINATOR | board, briefs, reports | 2026-09-28 |

**Mutaha is the priority and both lanes are on it.** They do not collide:
TERRAIN is rebuilding the map on a copy, GAMEPLAY is tuning robot behaviour in
`Character/**`. The one to watch is that **the perf numbers were measured on
the OLD Mutaha** — 141 → 22 full-brain robots, 25.0 → 7.4 ms. The rework
extends the town 130 m, removes a span and adds a crossing, so those need
re-taking once it lands rather than assumed to carry over.

---

## NEXT

Ordered. Causeway waits for Mutaha, by your call.

1. **Mutaha tuning.** Activation distance is **not level data** — it is a
   per-chassis `@export` on the robot scenes, so a change there is global to
   every map, not Mutaha-only. The infantry are already 250 → 120 (rifle,
   marksman, shotgun); still at 250 are the helicopter and the spotter drone,
   at 200 the nest and the walker. Flyers arguably want the longer reach; that
   is a judgement, not an oversight. Then re-measure on the reworked map.
2. **Three small finishes, all owed.** Spotters fly and make noise in the
   depot (should park and hush whenever `Campaign.in_mission` is false, which
   covers home base too). Soldier weapons draw at quarter size — `WeaponMount`
   bakes a 0.25 scale, and all five infantry mounts want the same new value or
   the squad's guns and the enemy's disagree. Lobber Rover's icon is identical
   to the Rover's.
3. **The onboarding regressed and it is an M2 blocker.** `test_tutorial.gd`
   fails: the base level carries **6** tutorial signs where the test wants ten.
   `homebase_level.tscn` has **14**; `depot_level.tscn` has **6**. Eight signs
   were lost when the depot replaced homebase as the base and nobody noticed,
   because the suite has been failing quietly. `TutorialToast` is also missing
   at the tree root, and the suite hard-crashes at `test_tutorial.gd:87`.
   TERRAIN owns the level file, GAMEPLAY owns the toast and the test; the
   signs' *content* can be lifted from homebase. This is exactly what a
   friend's first run hits, so it cannot wait for after the build.
4. **Causeway mission.** Largest map in the repo, intended end of the ladder,
   nothing points at it. Design agreed: advance the highway, fight the fort,
   room-by-room the tower, capture at the top.
5. **Catalogue the dark frames.** Quadcopter Bomber, Marksman, Mortar Track,
   Lobber Rover exist and none is purchasable. Icons now exist for three.
6. **Armour model — briefed and unblocked.** Full spec at
   `docs/briefs/ARMOUR.md`. Two coordinator notes on it before anyone starts:
   the `_collapse_pieces()` fix can no longer land on its own (it is entangled
   with the culling work in the same uncommitted `enemy.gd`, so land that as
   one commit first), and the Laboratory **before** measurement is perishable
   — take it before the helper goes into `apply_damage`.

---

## ROADMAP

Two dated milestones, set 2026-09-28. Everything else on this board is ordered
against them. Phases 4 and 5 of the old roadmap still exist but they are now
explicitly AFTER the build ships — see "What is deliberately not happening".

---

### M1 — RECORD READY · target 2026-10-01

**Definition of done:** you can play a mission start to finish, with a recorder
running, and send the file to a friend without apologising for anything in it.

That is a *lower* bar than feature-complete and a *higher* bar than "it runs".
What it actually requires:

- **It holds frame rate with OBS running.** Recording costs frames on top of
  the game's own. Mutaha is the risk: it went 25.0 → 7.4 ms physics, but the
  rendering cost there has never been measured.
- **Nothing on screen reads as unfinished.** This is where the "three small
  finishes" stop being chores and become blockers — they are all things a
  camera sees.
- **No crash, no soft-lock, no audio that makes the video unwatchable.**
- **The mission has a shape.** A start, a fight worth watching, an end. This is
  the only one of the four that is a design judgement rather than a fix.

**The three record blockers, reframed.** These were filed as small chores. On
video they are the whole impression:

| Blocker | Why it matters on camera |
|---|---|
| Spotters fly and drone in the depot | It is audible in every second of footage shot at base |
| Soldier weapons drawn at quarter size | Every frame with a squad in it shows toy guns |
| Lobber Rover icon identical to the Rover's | Two different frames read as the same one in the UI |

**Lane work for M1**

- **GAMEPLAY:** the three blockers above, then re-measure Mutaha once the
  rework lands. Nothing else. No new systems.
- **TERRAIN:** Mutaha apartment blocks, then promote the WIP over
  `mutaha_level.tscn` on the human's word. Then the Mutaha `LevelExit` that
  floats 0.584 m — it fails `test_terrain.gd` today.
- **HUMAN:** play coast road, basin and Mutaha and say which of the three is
  the most fun and which is the most broken. That judgement cannot be
  delegated and it is the only input M1 needs from you.

---

### M2 — PLAYTEST BUILD · target 2026-10-08

**Definition of done:** a friend on their own machine downloads it, plays three
or four missions in a ladder, and you get useful feedback back.

**Do the throwaway export THIS WEEK, not on the day.** `export_presets.cfg`
exists with two presets, which is not the same as a build that has ever run.
A first export is where missing resources, import settings and absolute paths
all surface at once, and finding that out on shipping day costs the milestone.
This is the single largest unknown on the roadmap.

What M2 needs beyond M1:

- **An export that runs on a machine that is not this one.** No editor, no
  source, no 4070.
- **A clean first run.** Your friend has no `user://` — no save, no settings,
  no unlocks, and **no onboarding**: the base is down to 6 tutorial signs from
  homebase’s 14. That path is the least-tested in the game and the first one
  they will walk.

- **A ladder, not a menu of missions.** Three or four in an order that teaches:
  arena to learn the orders, then coast road, basin, Mutaha.
- **Somewhere for the feedback to go.** Even a text file the build writes.
  Analytics already records to `user://` — that may be most of the answer.

**Lane work for M2**

- **GAMEPLAY:** export smoke test, clean-profile first run, mission ordering
  and unlock gating.
- **TERRAIN:** whichever of the three maps the human calls most broken.
- **COORDINATOR:** keep this board true; fold both lanes' reports in.

---

### What is deliberately NOT happening before the build

Naming these so they do not creep in:

- **Armour.** It is fully briefed and ready, and it should land AFTER M2. It
  changes how every fight feels, so shipping it days before a playtest means
  the feedback is about a damage model nobody has tuned. Freeze systems, ship,
  then land it.
- **Causeway.** It is the end of the ladder, not part of the first build.
- **Visible equipment and NCO promotion.** Mocked up, not started.
- **The other nine Foundry weapons.**

### The risks, largest first

1. **The export has never been proven.** Unknown, unbounded, and on the
   critical path for M2. Retire it this week.
2. **Mutaha rendering cost is unmeasured.** Physics is fixed; draw calls are
   not. It is the biggest map and the one most likely to fail under a recorder.
3. **Mutaha is mid-rework.** The map both milestones lean on is the one being
   rebuilt. Good work, but it is the long pole.
4. **"Fun" is not a task anyone can be assigned.** Three missions exist; nobody
   has said whether any of them is enjoyable. That is the human's call and M1
   cannot close without it.

---

## BACKLOG

Wanted, ordered loosely, not scheduled.

**Mutaha performance, measured and ranked**
- Cap concurrent live enemies; stream squads in as earlier ones die rather than
  instantiating 140 at load.
- Take culled robots off the tick entirely. Measured at 1.8 ms median.
- Budget nav queries — `find_advance_point`, `reconsider_move` and
  `roll_combat_action` cost roughly 2 ms **per call**.

**Content**
- Player-side kit worth carrying. Ruled 2026-09-28: the player CAN take
  anti-armour, so the fix for the long-range-god problem is MORE good options
  rather than fewer. Needs a list before it needs code.
- The other nine Foundry-tier weapons. The FPV drone is written and untracked;
  the rest are a list, not code.
- Retire the obsolete ladder: 15 of 22 mission files are outside the live
  campaign. Appendix them, do not delete.
- Third faction — scavengers, hostile to both sides, drawn to wrecks rather
  than to ground. Three verbs: hold, manoeuvre, take. Proposed, not scoped.
- Reclaimer rename. Candidates: Rook, Bailiff, Cinder, Tithe, Magpie.

**Equipment made visible**
- Armour, relay, harness, frag and nanite as tapered hull tiles. The shape
  language is settled and rendered (`tools/mockup_parts.capsule_kit_list`);
  what is missing is the runtime that shows them per loadout.
- Soldier promotion: a rank threshold buys an NCO and the tell is a hat. Same
  attachment mechanism as the kit above, so building one builds both.

**Owed engineering**
- Distance culling has no regression test. It needed guards in five separate
  places across two sessions; a sixth path would undo it silently.
- Clean out leftover probe scripts: `tools/probe_arm.gd`, `probe_mutaha.gd` and
  six terrain probes are untracked scratch files that survived their sessions.
- Pittsburgh bridge spacing fails the suite — BridgeArch2/BridgeArch3 are 6.7 m
  apart. TERRAIN's, geometry not code.
- Rover collision shape: correct shape built, caused an unexplained pack
  cohesion regression in `test_vehicle`, reverted, cause never found.
- Coast Road cover: 42 of 102 robots have no cover within 25 m. Geometry.
- Depot navmesh: 59% of it is stranded.
- Player step-over. The robots got it; the player did not.

**Parked**
- Anatomical drone soldier body. Built and rejected 2026-09-28 — the capsule
  stays. Kept in `tools/mockup_parts.drone_body()` in case the question comes
  back. Nothing ships it.
- Boss and mini-boss, dash, heat-or-stamina, melee weapons, weapon pick-ups,
  doors and elevators, suppression as a mechanic. From the original dump; still
  wanted in principle, none scoped, none blocking.

---

## LANDED

So the board has a memory. Newest first.

**2026-09-28, TERRAIN** — Mutaha WIP built as a separate level so the real one
could not be harmed (`mutaha_wip_level.tscn` + its own sketch and terrain data;
the originals hash-verified byte-identical). Island's south span deleted — the
walk between bridgeheads goes 46 m → 884 m. West bank's town extended ~130 m
south, 22 new lots. Cover at the west bridgehead, 34 pieces, on a block the
generator had left empty. River wall round the island's south tip. A crossing
at z = 316 added beyond the ask, because without it the extended town is
unreachable. Awaiting a verdict.

**2026-09-28, TERRAIN — reverted, and self-reported.** A depot ramp pass ran
`block_homebase.gd -- maps --force` over a whole folder and overwrote
`maps/depot/depot_level.map`, destroying TrenchBroom edits that had no backup
and were unrecoverable. Rolled back to `4cc5ef2`, hash-verified. The rule that
came out of it: **`--force` over a folder is never right** — back the file up,
name the one piece, prefer a targeted edit to a regenerate. Recorded here
because a reversal that is written down stops the next agent repeating it.
**2026-09-28** — Kit shape language settled: tapered hull tiles seated tangent
to the capsule, in their own materials. Mock-up pipeline producing both line art
and in-game screenshots from one shared shape definition.

**2026-09-27** — Debrief rebuilt: kills and revives as headline counters,
per-team tallies beside the team name, CONTINUE can no longer be pushed
off-screen. Icons for Marksman, Mortar Track, Lobber Rover, the Mechanic's
welder, AC20 and Heavy MG. Drone rotor audio restarts after repair, via a new
`Enemy._on_revived()` seam called from both `revive()` and `reset()`. Chaser and
Leaper removed from the shop. Depot squad muster restored as a real
`SquadSpawnPoint`; level exit restored as the departure the mission terminal
writes to.

**2026-09-26 and earlier** — Distance culling actually works: it was being
undone every frame by squad orders. Full-brain robots on Mutaha at spawn
141 → 22, physics 25.0 → 7.4 ms median, from over budget to inside it.
Activation measures to the nearest **enemy** rather than to the player, so a
squad sent ahead no longer fights statues, and an engaged squad stays awake for
the length of the fight. Corpses fall as one object. Faction livery paints CSG
primitives — the nest had never been painted at all — pinned by
`tools/test_livery.gd`. Walker two-mount frame with a direction-aware gait.
Spotter Drone. Robots step over 0.45 m lips. Bits and shards removed.

**TERRAIN, committed** — depot, proving ground and heliostat built; props given
collision the navmesh can read; ramps rather than steps on anything walkable;
rivers made non-navigable.

---

## Lanes

Four lanes — TERRAIN, GAMEPLAY, MARKETING and the coordinator — share one
checkout and one branch. Collisions are prevented by who owns
which path, not by branching.

| Path | Owner |
|---|---|
| `maps/**`, `Env/terrain/**`, `Env/world_objects/**` | TERRAIN |
| `tools/block_*.gd`, `terrain_bake.gd`, `minimap_bake.gd` | TERRAIN |
| `trenchbroom/**`, `textures/**`, `docs/TERRAIN.md`, `docs/BLOCKS.md` | TERRAIN |
| `Campaign/**` (missions included), `Character/**`, `Managers/**` | GAMEPLAY |
| `tools/test_*.gd` EXCEPT the terrain suites below, `docs/GAMEPLAN.md`, `docs/BARK_LIBRARY.md` | GAMEPLAY |
| `tools/test_terrain.gd`, `test_block_*.gd`, `test_prop_nav.gd`, `test_water_navmesh.gd` | TERRAIN |
| `docs/BOARD.md`, `docs/GDD.md`, `docs/APPENDIX.md`, `docs/briefs/**` | COORDINATOR |
| `docs/marketing/**`, `docs/briefs/MARKETING.md` | MARKETING |
| `docs/reports/<LANE>.md` | that lane, and only that lane |

**Shared — neither agent edits without saying so first:** `Env/world.tscn` ·
`docs/BRIEFING.md` · `CLAUDE.md` · `project.godot` · `tools/check.sh`,
`test.sh`, `smoke.sh`

**Missions are GAMEPLAY's, not shared.** TERRAIN builds and dresses the map;
GAMEPLAY authors the operation that runs on it.

---

## Protocol

**Opening a session.** Read your lane's NOW line. If it is empty, ask before
starting — do not pick your own.

**Closing a session.** Append to `docs/reports/<YOUR LANE>.md` — see the
template at the top of that file. Each lane writes only its own report file, so
two agents can close at the same moment and never conflict. The coordinator
reads both and folds them into this board.

**The file on disk is the source of truth — not git, not the last thing you
built.** Read the live file before you edit it. Do not reconstruct a file from
history, do not regenerate over one, and do not assume the committed version is
current: another agent or the human may have edited it since, in TrenchBroom or
the Godot editor, and those edits are invisible to you until you look.

**`--force` over a folder is never right.** Back the file up, name the one
piece, and prefer a targeted edit to a regenerate. This rule exists because a
ramp pass ran `block_homebase.gd -- maps --force` on 2026-09-27 and destroyed
TrenchBroom edits in `maps/depot/depot_level.map` that had no backup and could
not be recovered — the tools printed "SKIP … it may hold TrenchBroom edits" and
`--force` went past it.

**Gates,** per CLAUDE.md — `bash tools/check.sh --changed` must print `PASS`.
`tools/test.sh` after touching the ledger, armoury or anything with an
invariant. `tools/smoke.sh` after touching anything that loads at startup.

**Staying out of each other's way.** One checkout, one branch, and another agent
is usually mid-edit. Do not `git checkout`, do not `git checkout -b`, do not
stage files that are not yours. Check the branch with `git branch --show-current`
only.
