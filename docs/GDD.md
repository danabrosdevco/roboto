# Roboto — game design document

What the game currently contains, what is built but switched off, and what is
only proposed. Living document: when you add a frame, a weapon, a mission or a
map, it gets a row here in the same commit.

Opened 2026-09-23. Every number below was read out of the build that day.

**Status vocabulary, used throughout:**

| Tag | Means |
|---|---|
| **LIVE** | reachable in a normal playthrough |
| **DARK** | built and working, not wired to anything the player can reach |
| **PROPOSED** | designed, not built |
| **OBSOLETE** | superseded; kept until appendixed |

This file says *what is*. `docs/BRIEFING.md` says how the code is shaped,
`docs/GAMEPLAN.md` argues for the demo's arc, `docs/BOARD.md` says who is doing
what right now.

---

## 1. The game

A first-person squad-command shooter. You are a rogue drone commanding robots.
Persistent squad, discrete missions from a home base. Levels are TrenchBroom
brush geometry via FuncGodot, on generated terrain.

The pillar: **you are not the gun, you are the commander.** Every system should
push toward ordering robots rather than out-shooting things yourself.

---

## 2. Campaign ladder

The intended flow, and what actually exists behind each stage.

| # | Stage | Map | Missions | Status |
|---|---|---|---|---|
| 1 | Sim arena (training) | `proving_level` | arena 1, 3, 5 | **LIVE** |
| 2 | Valley | `valley_basin_level` | basin 1 | **LIVE** — one mission of a six-mission ladder |
| 3 | Coast | `coastal-road_level` | coast 1 | **LIVE** |
| 4 | Three bridges | `pittsburgh_level` | pitt 1 "Three Rivers" | **LIVE** |
| 5 | Mutaha | `mutaha_level` | mutaha 1 | **LIVE** |
| 6 | Causeway | `causeway_level` | — | **no mission exists** |

Home base is `depot_level`, loaded by `Env/world.tscn` and used as the tutorial
fallback base.

The live campaign is the seven missions listed in `Env/world.tscn`. Everything
else in `Campaign/missions/` is outside it.

### Maps not in the ladder

| Map | Size | Status |
|---|---|---|
| `causeway_level` | 4.1 MB — largest in repo | built, no mission |
| `valley_level` | 429 KB | **OBSOLETE** — confirmed dead 2026-09-23 |
| `arena_level` | 313 KB | **OBSOLETE** — superseded by proving |
| `homebase_level` | 142 KB | **OBSOLETE** — depot replaced it |
| `civil-unrest_level`, `oyster-bay_level` | | unreferenced |
| `WIP_TERRAIN`, `working_terrain`, `terrain_template_level`, `tb_level`, `test_01/02_tb_level`, `trenchbroom_level` | | scaffolding |

### Missions outside the live campaign

15 of 22 mission files. The bulk is a **duplicated six-mission ladder** authored
twice — `mission_valley_*` on `valley_level` and `mission_valley_basin_*` on
`valley_basin_level` (sweep, push, assault, siege, foundry). Plus
`mission_arena` / `_2_mixed` / `_4_pack_hunt` on the old arena, and two
helicopter test missions.

---

## 3. Frames (chassis)

`ChassisDefinition` — the frame decides base stats and, more importantly, **how
many slots** it carries. Slots are the real progression currency.

| id | Name | HP | Cost | Supply | Rank | Status |
|---|---|---|---|---|---|---|
| `soldier` | Soldier | 60 | 50 | 1 | 0 | **LIVE** |
| `chaser` | Chaser Chassis | 60 | 55 | 1 | 0 | **LIVE** |
| `leaper` | Leaper Chassis | 45 | 70 | 1 | 0 | **LIVE** |
| `mechanic` | Mechanic Chassis | 60 | 70 | 1 | 0 | **LIVE** |
| `reclaimer` | Reclaimer | 150 | 130 | 2 | 0 | **LIVE** |
| `rover` | Rover Chassis | 180 | 150 | 2 | 0 | **LIVE** |
| `spotter` | Spotter Drone | 80 | 180 | 1 | 1 | **LIVE** — every number unplaytested |
| `walker` | Walker | 320 | 320 | 3 | 2 | **LIVE** — the ceiling; every number unplaytested |

**The Spotter Drone** is the first player frame that carries no weapon and the
first that flies. It exists to close the gap between a 45 m sensor and an 80 m
rifle: `Enemy._on_combat_triggered` engages the *whole* squad the moment any
one member acquires a target, so a single 90 m sensor at altitude converts that
gap for everybody. It needed no new systems — the flight primitives are the
bomber's (`enemy_helicopter.gd`) and the sharing already existed.

It is deliberately fragile, and the three counters are the design rather than
bugs to fix: an EMP or sustained suppression drops it out of the sky
(`_enter_ekill` calls `die()`, because losing the link at altitude means losing
lift), a marksman pair can shoot it down through 80 HP, and it cruises at ~22 m
which is well inside rifle reach. It goes **down** rather than being destroyed,
so a Mechanic can stand it back up.

Every value above is a first guess — 80 HP, 180 res, rank 1, 90 m sensor, and
the flight numbers in the scene — and none of them has been played.

Not buildable — these `ChassisDefinition` files exist but are **not** an unused
player tier. Confirmed 2026-09-23:

| id | Name | HP | What it actually is |
|---|---|---|---|
| `gunship` | Quadcopter Bomber | 100 | **enemy** — points at `enemy_helicopter.tscn` |
| `marksman` | Marksman | 90 | **enemy** — points at `soldier_marksman.tscn` |
| `mortar_track` | Mortar Track | 150 | the **Reclaimer** with `starting_weapon_id = "mortar"` |
| `rover_gl` | Lobber Rover | 180 | the **Rover** with `starting_weapon_id = "grenade_launcher"` |
| `rifleman` | Rifle Trooper | 100 | enemy-side |
| `shotgunner` | Shotgun Trooper | 100 | enemy-side |
| `nest` | Nest | 500 | structure — does not move; the first of many enemy structures |

Mortar Track and Lobber Rover are **loadouts, not frames**: the mortar and the
grenade launcher are equippable weapons on frames that already exist.

**The ceiling problem — raised.** The Rover was the heaviest thing in the game
for a long time. The **Walker** is now the ceiling at 320 HP, and it is the
first frame to use `weapon_slots = 2`. That field had always existed, but
everything downstream assumed one gun — `Enemy.weapon` is a single reference
and `handle_weapon_logic` drives that one — so two mounts was runtime work,
not data. See §4.

**The Walker's edge is not its hull, it is its legs.** `drives = false` is
deliberate: `ChassisDefinition.takes()` only refuses infantry kit when `drives`
is true, so a Walker takes leg kit a Rover cannot — Nanite Reboot is
`fits_vehicles = false`, and a self-reviving 320-hull gun platform is a
different object from a rover that stays where it falls. Verified
2026-09-24: Nanite Reboot returns `true` for walker, `false` for rover.
`vehicle = true` still musters it with ARMOR.

It is a **turret on legs**: ordinary Soldier movement (it walks the navmesh,
it does not use the Rover's bicycle model, which exists to stop a wheeled hull
sliding sideways and says nothing about legs), with the Rover's turret pattern
on top — fixed traverse rate, no firing until on target. Getting round the side
faster than `turret_traverse_degrees` remains the counter, and because both
guns share the one mount, flanking beats both at once.

Its legs answer for **direction, not only distance**. The cycle advances by
ground covered, the way the Rover's wheels do, but split into the body's own
frame first: a backpedal runs the whole stride in reverse, and a strafe turns
into a sideways shuffle where neither leg ever crosses the other way. It
matters because a turret on legs spends the fight facing its target and moving
somewhere else — heading and travel disagree almost all the time, which is the
one case a distance-only gait gets wrong. Pinned by `tools/test_walker.gd`.

The identity comes from the fit, not the frame: autocannon is anti-armour,
Heavy MG is a suppression platform, mortar is indirect. Same 320 hull, three
jobs.

---

## 4. Weapons

AI weapons carry **range falloff** — `base_damage` at point blank decaying to
`min_damage` past `damage_falloff_start`. Authoritative values live in the
scenes, not the item resources.

| Weapon | Base | Min | Falloff from | Notes |
|---|---|---|---|---|
| `ai-wep_marksman` | 48 | 32 | 70 m | **DARK** — new |
| `ai-wep_mortar` | 70 | 70 | — | **DARK** — new, indirect |
| `ai-wep_shotgun` | 70 | 47 | 20 m | |
| `ai-wep_grenade_launcher` | 45 | 45 | — | |
| `ai-wep_m4` | 30 | 20 | 35 m | the rifle everything uses |
| `ai-wep_pistol` | 24 | 12 | 12 m | |
| `ai-wep_turret_grenade_launcher` | 20 | 20 | — | |
| `ai-wep_machine_gun` | 15 | 9 | 30 m | rover turret; also the Walker's **coax** |
| `ai-wep_autocannon` | 60 | 45 | 60 m | **new** — walker + rover. 0.50 cooldown, mag 20 |
| `ai-wep_heavy_mg` | 22 | 14 | 45 m | **new** — walker + rover. 0.12 cooldown, mag 120, 6.0 reload, 6 suppression/shot |
| `ai-wep_melee` | — | — | — | |

### Two mounts — main and coax

The Walker is the first frame with `weapon_slots = 2`, and this is **runtime
work, not data**. `Enemy.weapon` is a single reference and `handle_weapon_logic`
drives that one gun, so a second slot needed somewhere to live:
`Enemy.coax` / `coax_mount` / `equip_coax_scene()` / `_tick_coax()`, with
`SquadSpawner` fitting weapon slot 0 to the main mount and slot 1 to the coax.

It is deliberately **not** two guns making their own decisions. The main gun
owns everything it owns today — target selection, `_prefire_threshold`, bursts,
reloads, the whole state machine. The coax asks two questions each tick: is the
main gun on target (`_weapon_on_target()`, the same turret bearing), and is the
range inside *its own* band. If both, it fires on its own cooldown. The AI never
chooses between them. Independent target selection can come later if this earns
it.

Because `_tick_coax` runs before the main gun's early returns, the coax keeps
firing through the main gun's reload — which is what a coax is for. A frame with
no `coax_mount` warns and drops a second weapon rather than half-fitting it.

**The coax is bought, not issued.** 320 buys the frame and the gun it is built
around; the second mount arrives empty, because a mount you were simply handed
is not a decision. `ChassisDefinition.coax_weapon_id` now names what the mount
is *designed around* rather than what comes with it: `CampaignState.recruit()`
fills slot 0 only, and the armoury opens a fresh Walker **on the empty slot**,
so the gap reads as something to spend on rather than something broken. The
laboratory still fits it, because a test bench measures a complete frame.

**Watch this in playtest:** the Ancient MG reaches 99 m, so as a coax it fires
at essentially everything the main gun engages. That is a lot of output for one
supply slot, and a shorter coax may be the right answer.

Item resources carry a separate `weapon_damage` used on the player side
(`item_m4` 39, `item_shotgun` 45; pistol and rocket are 0, so those resolve
elsewhere). **Two damage sources for one weapon is a drift risk** of exactly the
kind BRIEFING §4 catalogues.

Falloff start is already a designed axis — 12 m on a pistol, 70 m on the
marksman, effectively infinite on indirect fire.

---

## 5. Armour — PROPOSED, not built

There is **no armour or damage-type system in the build**. Searching for it
returns only the *armoury* (the shop) and `ARMOR` (a squad team name for
vehicles). `item_armor_plating.tres` is a flat module, not a system.

A model exists as an interactive proposal (Armour Model 2109): four classes
(Unarmoured / Light / Medium / Heavy) on one rule —

    applied = max( raw * 0.05, ( raw - max(0, FLAT[class] - pierce) ) * MULT[type][class] )

— with four damage types (small arms, explosive, industrial, anti-armour),
`pierce` eating FLAT, and a 5% floor so nothing is fully immune. Rollout in four
phases: the rule plus feedback, then anti-armour tools, then named breakable
subsystems, then heavies at 4–6 supply.

**Verified against the build:** every chassis HP figure it quotes is correct, and
the signal constants match `enemy.gd` (`signal_recovery_rate` 0.08,
`SIGNAL_FUZZED` 0.75, `SIGNAL_DEGRADED` 0.50, `SIGNAL_EKILL` 0.01).
`signal_resistance` already exists as an export, so the per-class resistance
column maps onto a real field.

**Rulings, 2026-09-23:**

- **Falloff stays, and steep falloff on early guns is wanted.** Range is the
  stat that decides fights: the player can shoot as far as they like while the
  robots must advance into sensor range, and the frames are big targets. Early
  weapons should drop off hard. The consequence is accepted — explosives do not
  degrade, so grenade launchers gain from armour landing. In testing, MG and GL
  rovers perform about the same today.
- **`armour_class` goes on `ChassisDefinition` only.** Enemy should not carry
  it. One source of truth.
- **The Nest is a structure and stays as it is.** It does not move. There will
  be many more enemy structures and they can share its treatment.
- **AI shotgun**: switched to pellets, so the in-game number is correct as it
  stands. The item/scene mismatch is cosmetic, not a bug to chase.

**Still open:** whether FLAT subtracts before or after falloff. "Steep falloff
on early guns" points at *after* — raw damage drops with range, then armour
subtracts — which makes armour bite hardest at exactly the range the player
likes to fight from. That reading needs confirming before anything is built.

---

## 6. Signal — the second health bar

Separate from hull, and armour is not proposed to touch it. Near-misses within
2.5 m degrade `signal_integrity`; it recovers passively at 0.08/s. Thresholds:
0.75 fuzzed (accuracy penalty), 0.50 degraded (sensors halved, movement
stutters), 0.01 e-killed (fully disabled, latched).

This is the "infantry still matter" lever: riflemen who cannot scratch a heavy
can still suppress it. Signal comes back on its own; hull damage needs a Mechanic
or Reclaimer — so losing a fight and losing a frame stay different things.

Currently `receive_signal_damage` raises weapon spread and that is deliberately
the whole effect. `Soldier.enter_suppressed()` and `SoldierState.SUPPRESSED`
exist and nothing calls them.

---

## 7. Economy and progression

| System | Intended | Actual |
|---|---|---|
| Currency | shards (matter) / neural bits (cognition) / compute (capacity) | one undifferentiated `earned` pool |
| Compute | capacity, won not bought — gates squad size, chassis tier, and the drone's own software | partially: seats |
| Veterancy | XP → rank → unlocks frames and items | **LIVE.** The debrief awards XP and promotes: REGULAR → VETERAN → CAPTAIN. GAMEPLAN still says `add_xp()` is never called — that is stale, the build disagrees with it |
| Unlocks | missions grant items progressively | written to `state.unlocked`, **never read**; shop shows everything from minute one |
| Recruitment | buy a new robot in a frame | **not built** — the squad can only shrink |
| Ammo resupply | a campaign cost | `restock_roster()` is free on return to base |

Splitting the currency changes the save format. Per GAMEPLAN §10 that is the
most interesting design work here and the least urgent.

The SOFTWARE tab (`Campaign/software_tree.gd`, `Character/hud/squad/software_page.gd`)
is built and blank; its design is `docs/SOFTWARE_AND_GROWTH.md`.

---

## 8. The Laboratory — the balance instrument

`tools/` runs a headless squad-versus-squad harness that reports, per matchup:
win rate for each side, how many robots the winner kept, how much hull it had
left, both sides' accuracy, and damage dealt. It writes a full report to
`app_userdata/roboto/lab_sample/`.

This is the most under-used thing in the repo. Every number in §5 and every tier
number in the deck is a hypothesis it can test overnight, without a human
playing a mission.

**It is already reporting a problem.** Four squad orders were run against the
same garrison — 4 rifle troopers vs 2 shotgun troopers + 2 rifle troopers + 1
chaser at 35 m:

| Order | Allies win |
|---|---|
| Attack a target | **100%** |
| Advance onto the garrison | 0% |
| Move & hold onto them | 0% |
| Hold at range | 0% |

If three of the four verbs lose every time, the commanding layer is narrower
than the UI suggests. Worth deciding whether that is a bug in the orders or a
tuning problem before new orders are added on top.

---

## 9. Running the game

**The agents can run it.** Both build agents boot the game and capture
screenshots. `CLAUDE.md` still says "You cannot run the game. No display, and
the repo is missing art assets" — that is stale and should be rewritten, because
it changes what an agent is allowed to call verified.

---

## 10. Open design questions

Live questions, not a backlog. Answered ones move into the sections above.

1. Does armour read damage before or after range falloff?
2. Where does the Rover sit once mediums and heavies exist — does it get
   promoted to Light armour, or stay the top of the unarmoured tier?
3. Is the Ancient Rifle retired by rank, by unlock, or by simply becoming
   useless against the new classes?
4. Flying: the Quadcopter Bomber is a buildable ally at rank 2 and dark. Is the
   flying tier gated on veterancy being switched on at all?
5. What does resupply cost, and is it per-mission or per-item?
6. Which valley is *the* valley, and does the six-mission ladder survive the
   move to a six-map ladder?
