# Brief — Multiplayer, Phase 0

Written 2026-09-30, to be picked up later. **Nothing here starts before the
playtest build ships.** Phase 0 is the go/no-go for co-op multiplayer, and the
profiler has already told us most of the answer.

Owner when it starts: **GAMEPLAY**. Status: **not started, deliberately.**

---

## The headline: multiplayer is not what blocks multiplayer

A real fight — about **10 allies against 20–30 enemies**, single-player — was
profiled on 2026-09-30. **Frame time 83.63 ms.** That is roughly **12 FPS**, in
a normal fight, with one human in the game.

So the Phase 0 question changes. It was "can four commanders and their squads
hold frame rate?" It is now: **the AI decision budget is already over budget
for single-player, and multiplayer only multiplies it.** Fixing it is not
multiplayer preparation. It is a single-player bug that multiplayer would have
discovered later and more expensively.

**That is good news.** The work pays for itself whether or not a packet is ever
sent, and it can start without committing to the feature.

---

## What the profiler actually said

The costs nest — Godot reports inclusive time, so these are a call chain, not a
flat list. Read downward:

```
Soldier._physics_process      62.85 ms / 340
  Enemy._physics_process      62.56 ms / 340
    Enemy.handle_movement     52.85 ms /  90   0.587 ms per call
      Enemy.perform_action    32.75 ms /  15   2.183 ms per call
      Enemy.roll_combat_a…    32.95 ms /  15   2.197 ms per call
        Enemy.reconsider_m…   31.98 ms /  11   2.907 ms per call
          Enemy.find_advance… 30.77 ms /  11   2.797 ms per call
            Enemy._tick_nav   20.50 ms /  63   0.325 ms per call
```

**The bottom of that stack is where the time goes.** `find_advance_point` costs
**2.8 ms a call** and `reconsider_move` **2.9 ms**. These are nav queries. A
handful of robots deciding in the same frame is tens of milliseconds.

**Three further readings, all useful:**

1. **The culling work succeeded and is not the problem.** `_apply_motion` is
   **0.0089 ms per call** across 335 calls, and `_tick_signal` 0.0032 ms.
   Per-robot per-frame work is now free. Every remaining millisecond is in
   *decisions*, which is exactly where the earlier Mutaha profile pointed.
2. **The HUD is rebuilding during combat.** `ObjectiveHUD._process` 2.68 ms +
   `ObjectiveHUD._rebuild` 2.63 ms + `SquadHUD._process` 2.34 ms +
   `SquadHUD.refresh_r…` 1.56 ms + `SquadHUD._make_m…` 1.04 ms ≈ **10 ms**, and
   `Process Time` is 11.78 ms total. A rebuild is not a per-frame job. This is
   the cheapest win on the list and it is not AI work at all.
3. **Physics 3D is 18.69 ms** on its own, separate from script. Worth a look
   after the decisions are fixed, not before — it may shrink when fewer robots
   are thrashing the navigation map.

**One honest caveat on the numbers.** Call counts (340 `_physics_process`)
against a fight of 30–40 robots mean the sample spans several physics ticks, so
treat the totals as a window rather than one frame. **The per-call costs are the
robust figures** and they are the ones this brief rests on.

---

## The work, in order

### 1. Budget the decisions — the whole ballgame

Cap how many robots may run a decision per frame and round-robin the rest.
A robot that re-decides on frame 3 instead of frame 1 is indistinguishable in
play; a robot that costs 2.8 ms is not.

The functions to gate: `find_advance_point`, `reconsider_move`,
`roll_combat_action`, `perform_action`, `find_best_cover` (0.824 ms).

**Target:** no more than ~2 ms of decision cost in any single frame.

### 2. Stop the HUD rebuilding per frame

`ObjectiveHUD` and `SquadHUD` should rebuild on change, not on tick. ~10 ms for
free, and it makes the frame legible again.

### 3. Re-measure the same fight

Same 10 v 20–30 engagement. **Acceptance: frame time under 16.6 ms.** Until
that holds, multiplayer is not a conversation.

### 4. Only then, the original Phase 0 experiment

Four squads at four separate points on the map, no netcode, measure. Four
commanders wake four regions, so the active set is the thing to watch.

**Go:** under 16.6 ms with four squads' worth of robots awake.
**No-go:** over, and the feature needs a population cap designed in — which
would point at wave defence on a bounded site rather than open co-op missions.

---

## Rulings already taken, recorded so they are not re-litigated

From the human, 2026-09-30:

- **There is no pause in multiplayer.** Not "pause is synchronised" — removed.
  Most games do it this way. This kills the four `PauseHold` takers
  (`master`, `briefing`, `debrief`, `squad_manager`) as a *design* question
  rather than a sync problem, and it means **the loadout screen has to work in
  a live world.** Refitting under fire becomes a mechanic.
- **Multiplayer gets its own save**, and the save/load system needs to be more
  robust before it can. A network is its own campaign file, separate from a
  solo campaign, so nobody's progress is hostage to someone else's schedule.
- **Objectives need revising** — they assume one player. `reach_objective.gd`
  holds `_player_inside: bool`, a single boolean. Every objective type needs
  the same audit.
- **A player whose squad is wiped repairs their team.** They always carry a
  repair tool, so the answer to "what do I do now" is that you go and stand
  your robots back up. That is the game's emotional core pointed at its own
  worst moment, and it needs no new system.
- **Host migration is not happening.** If the host drops, the session saves
  and ends.
- Level-load sync, analytics ownership, salvage pooling and the debrief's
  "waiting for others" are noted as known work, not as risks.

---

## Why this is the right first phase

It is the only part of the multiplayer plan that is **worth doing even if
multiplayer never ships**. A fight at 12 FPS is a single-player defect today —
it is in the recording milestone, it is in the playtest build, and it is what a
friend will notice first. Phase 0 fixes that, and the number it produces at the
end is the number that decides whether the rest of the plan is real.

Everything after this — decoupling `player` (96 references across five files),
the netcode, the shared base, the front — waits on that one measurement.
