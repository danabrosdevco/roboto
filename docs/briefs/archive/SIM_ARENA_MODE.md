# THE SIM ARENA, THE TUTORIAL, AND THE LAB

**Phase 6.4 and 6.5.** Written 2026-10-13, corrected the same day.

## CORRECTION — the induction is not broken, and it stays in the depot

An earlier draft of this brief said the induction ran in the wrong place and
that three of its objectives "cannot be completed and pass themselves",
quoting warnings from a headless boot. **Both claims were wrong.**

The warnings only appear under `--script` runs, where
`get_tree().current_scene` is null, there is no player body and no casualty is
staged. In a real boot `current_scene` IS Master, `keys_reviewed` exists and is
emitted at `master.gd:890`, the player has a SquadCommander, and the casualty
is staged by `Campaign._stage_first_tutorial`. A proper headless boot logs none
of them.

> **The depot induction works, it is well built, and it is staying where it
> is.** It is the right place for it: the first thing the game teaches is the
> base, and the base is where you are.

It already has eight objectives, including the one that was going to be asked
for — `induct_pick_op`, "CHOOSE AN OPERATION", which completes on
`SELECT_MISSION` at the operations table.

## THE SHAPE, AS DECIDED

| | where | what it teaches |
| --- | --- | --- |
| **1 · Induction** | the depot | keys, repair, revive, buy, fit, FOLLOW, ADVANCE, choose an operation |
| **2 · Three sim missions** | the sim arena | shooting, a squad in a fight, holding ground |
| **3 · Lab fights** | the sim arena | nothing — it is a toy, and it is for the player |

The induction ends by sending you to the operations table. The three arenas are
what you do next. The lab is there forever after.

## WHAT THE SIM ARENA NEEDS

The mechanics are done: a mission flagged `sim = true` passes no turn, pays
nothing, takes no ground, gives the other side no move, and repeats.
`tools/test_turn_loop.gd` covers all six. What is missing is that it is still a
**pin on the operations board**, chosen the same way a war is.

### A free action must not look like a costly one

The board offers "Three Rivers" and "Sim Arena: Firing Line" as the same kind
of choice, in the same place, with the same furniture. One costs a turn and can
lose you a site. The other cannot. That is a trap, and it is the whole reason
this is a mode rather than a mission type.

### The screen

**Two halves, because they are two different things:**

**TRAINING** — the three authored arenas, in order, with their clears shown.
Free, repeatable, no turn. This is the campaign's on-ramp and the thing that
gates Hillfort.

**THE LAB** — `Managers/lab.gd` already exists and already runs AI-vs-AI
matchups with the player in spectator. It needs a front end:

- pick a side each: frames, counts, kit
- **WATCH** — spectator, the Lab's existing `_become_ghost()`
- **LEAD** — the player fights on one side with a squad of their choosing

### The loadout question, which is the only real design decision

The arenas currently deploy the campaign squad. For a practice mode that is
wrong in a specific way: trying something costs you the arrangement you had,
and testing a Walker means buying one.

**A · A SANDBOX ROSTER.** Anything in the catalogue, opened or not, free.
Practising a Bulwark before you can afford one is what a practice track is for,
and it makes the Tooling Fabricator's prices legible — you can try the line
before paying 520 to open it.

**B · WHAT YOU OWN, borrowed and returned.** Snapshot and restore on exit.
Honest, teaches nothing about kit you have not bought.

> **A.** The sim is where you find out what a frame does; the Fabricator is
> where you pay for having found out.

## THE GATE, WHICH IS NOW ANSWERED

**SUPERSEDED 2026-10-22.** `arena_5_proving` is off the campaign and
`arena_1_contact` was cut, so the chain is one link long: `hfw_1_fort`
requires `arena_3_firing_line` and nothing else. What follows was written
when there were three exercises and is kept for the argument, not the data.

With the induction in the depot and the arena as free training, **that gate is
the tutorial** — eight lessons at base, one in the arena, then the war. Keep
the chain and call it what it is.

## Done when

- The arenas are gone from the operations table
- There is one place you enter the sim from, and it is not a site marker
- Training lists the three arenas with their clears
- The Lab can be driven from the UI: pick two sides, WATCH or LEAD
- A sim run uses a sim roster, not the campaign squad
- `tools/test_turn_loop.gd` still passes — no mechanics change here

---

## DONE, 2026-10-13 — the two exercises are assaults

The arena was rebuilt larger by `tools/build_proving.gd` (88×54 m → 135×70,
with a 30×30 m bay behind the enemy blockhouse). Both exercises were reworked
against it.

| | objectives | leaves by |
| --- | --- | --- |
| **1 · First Contact** | `proving_clear` → `proving_extract` | the blockhouse gate, z 37 |
| **2 · Take And Hold** | `proving_capture` → `proving_bunker` → `proving_extract_bay` | the bay gate, z 86 |

The second teaches the verb the campaign is made of: work a core, wait for the
drone, take the bunker, go home from there. It does **not** require clearing
the floor — neither does a real site operation.

### The level holds both extractions, and exactly one is ever live

`MissionObjective._ready` frees the objective the operation left out. The gate
it hangs on does **not** go with it: `LevelExit`'s own Area3D ends the mission
on body entry whether the objective exists or not, and `_refresh_live` lights
it as soon as the real objectives are done. Two lit beacons, either of which
ends the run, in the level that teaches the player what extraction is.

So `LevelExit` gained **`pairs_with_objective`**: a gate paired with an
objective that is gone frees itself. Empty on every other level, which has one
way out.

### The order is enforced, not merely displayed

`HoldableCore._drive_authored` calls `complete()` on capture without consulting
`active`, so the bunker could be taken before the core and tick a line the HUD
had never shown. `TrainingCore` shuts its own terminal — collision layer 0,
invisible to the interact ray — until its prerequisite completes. A sweep found
no other core-driven objective with a prerequisite; `reach_objective` and
`eliminate_objective` both already guard on `active`.

### What proves it

- `tools/probe_arena_cores.gd` — 15 checks: floor under every placement, the
  navmesh, all four pad corners, a walked path from the spawn, both gates on
  ground, and the bay gate clear of the bunker pad. It caught that the bay
  floor is at y **0**, not the 0.5 the navmesh bakes at.
- `tools/test_arena_assault.gd` — 21 checks, and it needs a *running* level:
  packed, the scene has two of everything.

### Two suites were failing on correct behaviour

Both predate features they never heard about, and both were red for a day:

- `test_mission_objectives` required every mission to name an extraction. A
  site operation is won at the bunker and names none — Valley Basin's two
  missions read as unfinishable. Now exempt when the level carries a
  `*_slice.gd` or `site_operation.gd`.
- `test_debug_switches` required UNLOCK ALL MISSIONS to open *every* mission.
  A defence is filtered out before the switch is read, deliberately — it
  answers a raid that is in doubt, and a switch that conjured one would make
  losing ground impossible. Now counts the ladder, not the list.
