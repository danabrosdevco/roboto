# KITE — integration brief

Supply 2 · aerial · **armed** · player-buyable · model built, nothing else wired

The companion to `docs/frames/KITE.md` (design) and `tools/build_kite.gd` (the
model). This document is the build order. It cites
`docs/briefs/FRAME_ANATOMY.md` by section rather than restating it — read that
first, it is the map.

Everything below carries a `file:line`. Where I could not find something I say
so in §9. **I changed no code, scene or resource writing this.**

---

## 0. The one-line summary

The Kite's model is finished and sits on `spotter_drone.gd`, a script whose
`handle_weapon_logic` and `roll_combat_action` are literally `pass` with the
comment *"No weapon, ever."* It is the player's first armed aerial and, as
shipped, it cannot fire a shot. That is the whole of this brief: a
`ChassisDefinition`, one whitelist line on an existing weapon, and a `kite.gd`
of roughly 90 lines that restores the weapon loop and points the pod at things.

### Verified, first, because everything else depends on it

| claim | status |
|---|---|
| `spotter_drone.gd:175-176` `handle_weapon_logic` is `pass` | **TRUE** |
| `spotter_drone.gd:179-180` `roll_combat_action` is `pass` | **TRUE** |
| `spotter_drone.gd:174` comment "No weapon, ever." | **TRUE** (lines 172-174) |
| `kite.tscn:111` root script is `spotter_drone.gd` | **TRUE** (`ExtResource("1_hj01i")`) |
| `kite.tscn:131` `weapon_mount = NodePath("Rig/Turret/GunPivot/WeaponMount")` | **TRUE** — the mount *is* wired |
| `Rig/Turret` (`kite.tscn:330`) and `Rig/Turret/GunPivot` (`kite.tscn:360`) exist, unwired | **TRUE** — no `turret`/`gun_pivot` export on `Soldier`, `Enemy` or `spotter_drone.gd` |
| `enemy.gd:2895` `hull_spoils_aim` escapes only via a non-null `turret` property | **TRUE**, verbatim |
| `kite.tscn` carries **no** `Allowed*Options` lines | **TRUE** — stripped by `build_kite.gd:223-249`, so the empty default applies |
| `enemy.gd:3053-3054` `roll_combat_action` returns on an empty combat array | **TRUE** |
| `Squad._enforce_leash` (`Managers/AI/squad.gd:640`) measures 3D and ignores `slot_tolerance` | **TRUE** — see §7 |

So the design doc's §6 is **correct on all four of its code requirements**.
What it gets wrong is elsewhere; see §10.

---

## 1. What "successful" means

**The thing a player can do that they cannot today:** buy a flying frame that
shoots, put it over a position, and have it put rounds down onto that position
from above while the squad on the ground walks there. Today every aerial the
player owns is a camera (`chassis_spotter.tres:17` `weapon_slots = 0`), so an
aerial purchase is currently a sensor purchase and nothing else.

**The honest version.** `docs/frames/KITE.md` §2 already retracts the original
justification and it was right to: there is no vertical immunity in this game.
`AIWeapon.check_damage` (`Character/weapon/ai_weapon.gd:396-399`) builds its ray
from `muzzle_origin.global_position` toward `weapon_target` — a position, not an
orientation — so a ground frame's elevation limits never touch the damage
resolution, and the vision cone is flattened before the FOV test
(`enemy.gd:962-964`, `forward.y = 0.0`). Height buys the Kite nothing the
engine enforces.

What it does buy, mechanically and measurably:

- **Range the squad does not have to walk.** `machine_gun` reaches 99 m
  (`ai-wep_machine_gun.tscn:16`) from a platform that crosses terrain at 18 m/s
  ignoring the navmesh (`spotter_drone.gd:220`, `off_navmesh_is_normal` 392).
  A Kite is shooting at the objective while a Rover is still finding a route to
  it. That is the real proposition and it is a real one.
- **A target that most of the enemy army is bad at.** 0.7 m sphere
  (`build_kite.gd:417`) at 22 m, moving, against range-proportional spread
  (`enemy.gd:5235`, `spread_m = spread_mrad * dist / 1000.0`).
- **Line of fire.** `_clear_line_of_fire` (`enemy.gd:269-289`) makes ground
  frames hold fire and sidestep when a squadmate is in the lane. A frame
  shooting downward out of a formation has that problem much less often.

**And the cost, which is what stops this being thin.** The Kite is permanently
`_is_moving()` (`enemy.gd:2837-2838`, threshold 0.6 m/s, cruise 18), so it
permanently eats `moving_accuracy_penalty` — **3.0x spread**
(`enemy.gd:199`, applied at `enemy.gd:5251-5252`). It cannot stop to aim: AIM
sets `movement_state = NONE` (`enemy.gd:3953-3957`) and the flight code does not
read `movement_state`. So the Kite is a frame that trades accuracy for reach and
mobility, permanently, and 90 hull means it loses any exchange it is caught in.
That is a legible, non-thin identity: **the gun that gets there first and
cannot be aimed properly.**

**If the human disagrees, the thing to cut is the frame, not the gun.** A Kite
without a weapon is a worse Spotter.

---

## 2. The `ChassisDefinition`

New file: **`Campaign/chassis/chassis_kite.tres`**. Nearest template:
`Campaign/chassis/chassis_spotter.tres` — copy it and change every line below.
**Do not copy it blind: three of its values are actively wrong for an armed
frame** (`base_accuracy`, `weapon_slots`, `built_in`).

| field | value | why / citation |
|---|---|---|
| `id` | `&"kite"` | **PERMANENT.** `FRAME_ANATOMY.md` §2.5 — written to the save in three places and the `RENAMED` hook covers only kill tallies |
| `display_name` | `"Kite"` | one word, so `_recruit_name` (`campaign_state.gd:769-770`) takes it whole as the callsign |
| `description` | see below | |
| `icon` | leave null | `FRAME_ANATOMY.md` §1.3 item 8 — let `tools/bake_icons.gd` do it |
| `scene` | `res://Character/characters/ai/kite.tscn` | **PERMANENT PATH.** §2.5: a moved `.tscn` makes every saved record fall back to `default_chassis` |
| `cost` | `240` | design doc §3; above the Spotter's 180 |
| `purchasable` | `true` | without it `recruit()` refuses outright (`campaign_state.gd:740-741`) |
| `supply` | `2` | design doc §3 |
| `starting_weapon_id` | `&"machine_gun"` | §3 of this brief. **Requires the whitelist line** — this bypasses `takes()` (`campaign_state.gd:750-751`) and will otherwise ship the Bulwark's bug verbatim |
| `coax_weapon_id` | `&""` | the scene has **no `coax_mount`**. `FRAME_ANATOMY.md` trap 6.12: `equip_coax_scene` warns per body per mission if anything tries |
| `base_health` | `90` | absolute for a player frame (`soldier_record.gd:238`). Matches `kite.tscn:138-139` |
| `base_speed` | `1.0` | **not the doc's 1.2 — see the box below** |
| `base_accuracy` | `1.0` | **not 0.0, and this is the trap.** See the box below |
| `base_sensor_range` | `70.0` | absolute (`squad_spawner.gd:350`). Below the Spotter's 90: it is not the scout |
| `weapon_slots` | `1` | one mount exists |
| `built_in` | `""` | **not the Spotter's `"OPTICS"`.** `built_in` is a filename (`icons.gd:63-66`, trap 6.10) and it displays *in place of* a weapon slot (`factory_page.gd:258-259`) — on an armed frame that hides the gun |
| `weapon_replaces_built_in` | `false` | nothing to replace |
| `turret` | `true` | the pod traverses, and `enemy.gd:2895` needs the *property*. §4 |
| `vehicle` | `true` | ARMOR team (`campaign_state.gd:494-496`); both existing flyers do this |
| `drives` | `false` | it has no wheels, so nanite/repair items are not refused by `takes()` line 89-90 |
| `equipment_slots` | `0` | design doc §3. Open question in §8 |
| `module_slots` | `2` | design doc §3 |
| `musters_at_base` | `false` | **and there is a model reason, not just the Spotter's precedent.** `build_kite.gd:32-48`: the origin is the midpoint of the airframe's own bounding box, so a Kite sitting on a pad under gravity renders half-buried. `_parked()` (`spotter_drone.gd:145-158`) re-enables gravity at base. Keep it out of the hub (`campaign.gd:910-917`) |
| `required_rank` | `1` | **inert.** `FRAME_ANATOMY.md` §2 and trap 6.4: read only by `set_chassis` (`campaign_state.gd:1165`), never by `recruit()` or `factory_page.gd`. Set it for documentation and gate the frame with a mission `unlocks` entry (§5) |

> ### `base_accuracy` must not be 0.0, and copying the Spotter will make it 0.0
>
> `chassis_spotter.tres:19` sets `base_accuracy = 0.0`. For a **player** frame
> that field is a *multiplier*: `soldier_record.recompute_stats` stores it as
> `effective_accuracy` (`soldier_record.gd:239,262`) and `squad_spawner.gd:348`
> applies `soldier.accuracy_skill *= record.effective_accuracy`. At 0.0 the
> frame's `accuracy_skill` (0.75 by default, `enemy.gd:190`) becomes **zero**,
> and `get_inaccurate_target` (`enemy.gd:5231-5235`) then computes
> `spread_mrad = ai_spread_mrad / maxf(0.0, 0.01)` = `12 / 0.01` = **1200 mrad**
> — about 69 degrees of cone. The Kite would fire, score hits on nothing, and
> nothing would warn.
>
> It is harmless on the Spotter only because the Spotter has no weapon. **This
> is the single most likely silent failure in the whole frame** and the design
> doc does not list the field at all. `1.0` is the neutral value; `0.9` if the
> human wants it slightly worse than a line trooper.

> ### `base_speed` is inert for a flyer, so do not spend a number on it
>
> `base_speed` multiplies `move_speed` (`soldier_record.gd:254` →
> `squad_spawner.gd:349`). **The flight code never reads `move_speed`**:
> `spotter_drone._steer` (269-290) uses `cruise_speed`, `orbit_speed`,
> `acceleration`, `turn_speed` and `rotation_speed`, and `move_speed` appears
> nowhere in `spotter_drone.gd`. So the doc's 1.2 changes a number that only
> the shop card reads (`item_facts.chassis_speed` instantiates the scene,
> `FRAME_ANATOMY.md` trap 6.9).
>
> Set `1.0` and tune the Kite's real speed as `cruise_speed` / `orbit_speed` on
> `kite.tscn` (currently 18.0 / 8.0, lines 113 and 118). Say so on the card or
> the card lies. *(`base_speed` is also ignored outright for enemies —
> trap 6.9 — which matters if the Kite is ever fielded against the player.)*

**Description** (player-facing; `KillKinds.name_of` strips a trailing
`" CHASSIS"`, so do not add one):

> Coaxial rotors and a gun in a pod. Carries a turret gun to altitude and fires
> down from it, which puts rounds on a position before anything on legs has
> found a route there. Ninety hull, it never stops moving, and it never shoots
> straight because of it. An EMP drops it out of the sky.

Nothing in the table above except `id` and `scene` is permanent
(`FRAME_ANATOMY.md` §2.5) — every stat, cost, supply and slot count is safe to
retune after shipping.

---

## 3. The weapon — **no new `ItemDefinition`, one existing file edited**

**Answer: no.** `machine_gun` is the right gun and it already exists.

`Campaign/items/item_machine_gun.tres` → `Character/weapon/ai-wep_machine_gun.tscn`:
plain `ai_weapon.gd` (line 3), `weapon_type = 1`, 15 damage, falloff from 30 m,
`max_effective_range = 99.0`, `ai_spread_mrad = 12.0`, bursts of 8–16, a
100-round magazine and a 5 s reload (lines 11-27). It is `fits_vehicles = true`,
`usable_by_ai = true`, `cost = 150`, and `required_rank = 0`
(`item_machine_gun.tres:13,20-21,35`).

That is exactly an aerial suppression gun: long magazine, long reload, long
reach, mediocre precision. The Kite's permanent 3x moving penalty wants a
weapon that fires *a lot of* rounds, which this does and `autocannon` does not.

**Subclass decision, against `FRAME_ANATOMY.md` §3.4: no subclass.** The rule
there is "you need a subclass if and only if the round is not a hitscan ray."
`ai-wep_machine_gun.tscn` is a hitscan ray on the base script. Nothing about
firing it from 22 m changes that — `check_damage` is position-to-position
(`ai_weapon.gd:396-399`), unmasked, and already 3D.

### The whitelist question — and the Bulwark's bug is pre-loaded here

`item_machine_gun.tres:37`:

```
chassis_whitelist = Array[StringName]([&"rover", &"walker"])
```

`ChassisDefinition.takes` (`chassis_definition.gd:91`) refuses a WEAPON when
`turret and not item.chassis_whitelist.has(id)`. The Kite sets `turret = true`.
So **as it stands, a Kite would deploy armed** — `recruit()` writes
`starting_weapon_id` straight into `weapon_ids[0]` without consulting `takes()`
(`campaign_state.gd:750-751`) — **and the player could never refit it, and
removing the gun would be irreversible.** That is `FRAME_ANATOMY.md` trap 6.2,
word for word, and it is how the Bulwark ended up armable exactly once
(`chassis_bulwark.tres:15` issues `heavy_mg`, `item_heavy_mg.tres:37`
whitelists `[walker, rover]`).

**Required edit, one line:**

```
# Campaign/items/item_machine_gun.tres:37
chassis_whitelist = Array[StringName]([&"rover", &"walker", &"kite"])
```

**Recommended second edit, same line shape:** add `&"kite"` to
`item_heavy_mg.tres:37` as well, so there is an upgrade path for the pod. Do
**not** add `autocannon` (`item_autocannon.tres:37`): 260 compute of gun on a
240 compute airframe with a 3x spread penalty is a bad buy, and a 20 mm firing
from a 0.7 m sphere is a silhouette lie. Leave it as a later decision.

**Do not add `&"kite"` to anything not vehicle-legal.** `squad_auto` and `m4`
are `fits_vehicles = false` with empty whitelists — an empty whitelist means
`takes()` refuses them on a turret frame, which is correct and should stay.

### While fixing that line, fix the Bulwark too

`item_heavy_mg.tres:37` should carry `&"bulwark"`. It is the same one-line fix
for the same live defect and it is cheaper to do in the same pass than to leave
as a second ticket. **Flag it to the human rather than doing it silently** —
it changes an existing frame's refit legality.

---

## 4. The behaviour — `kite.gd`

### 4.1 Base class: **`extends SpotterDrone`**. Decided.

`Character/characters/ai/kite.gd`, `extends SpotterDrone`, and **no
`class_name`** (a new global symbol is not resolvable headless until the editor
rescans — `spotter_drone.gd:94-96` records exactly that cost; `kite.tscn`
references the script by path and the tests can too).

Why, against the three options:

- **`extends SpotterDrone`.** Gets the whole flight model (`handle_movement`
  220, `_steer` 269, `_turn_toward` 296, `_separation` 303,
  `_altitude_velocity` 318, `_ground_height` 328, `_orient` 341), the
  `GroundRay` built in `_ready` (116-120), `air_clearance` look-ahead, the
  `"air"` group (108), the parked-at-base rule (145-158), the three squad seams
  (`takes_cover` 191, `slot_tolerance` 198, `formation_width` 204), the crash /
  downed / revive / EMP set (359-386) and `off_navmesh_is_normal` (392). It
  needs to *undo* two stubs and *add* aiming. That is the smallest script.
- **`extends Soldier` + copy the flight model.** Would be a third verbatim copy
  of ~120 lines of steering. Rejected.
- **`extends EnemyHelicopter`.** Rejected, and the design doc §6.4 is right
  about why: the bomber overrides **none** of `takes_cover`, `slot_tolerance`
  or `formation_width` (verified — those identifiers do not appear in
  `enemy_helicopter.gd`), so it inherits `takes_cover() → true` and `Squad`
  will hand it a ground cover point as a loiter centre (`squad.gd:554-555`,
  `1540-1541`). Its `handle_movement` (180-209) is a four-phase bombing run
  built around release timing, which is not an aiming problem.

**Type-check safety, verified:** `grep -rn "SpotterDrone"` across `*.gd` finds
no `is SpotterDrone` test anywhere — only `kill_kinds.gd:56`, three build
scripts and three tools, all by path or string. So a Kite inheriting that class
name captures nothing. The one place to watch is
`spotter_drone._separation()` (303-313), which walks the `"air"` group and
pushes apart from *anything* in it — so Kites and Spotters will deconflict with
each other, which is wanted.

### 4.2 The shared flight component: **defer, and the reason is that this frame does not create a third copy**

`BROODCARRIER.md` §6.1 recommends extracting a shared flight component "when a
third flyer appears… since that makes three." Its trigger is **three copies of
the code**, not three flyers. Extending `SpotterDrone` adds a third flyer and
**zero** new copies, so the trigger is not met by the Kite.

**Position: defer the extraction. Do it when the Broodcarrier lands, because
that frame genuinely forks the flight model** (`build_brood.gd:100` already
commits to `spotter_drone.gd`, but a carrier that must hold station over a
release point wants a different `handle_movement`).

**What deferring costs, stated so it is a decision and not a drift:**

1. `spotter_drone.gd` and `enemy_helicopter.gd` hold near-verbatim twins of
   `_turn_toward`, `_separation`, `_altitude_velocity`, `_ground_height`,
   `_flat_body_forward`, `_orient` and the `_lifted` / `_ground_ray` ritual.
   They have **already diverged**: the bomber's `_steer` takes a `pitch`
   argument, its `_altitude_velocity` clamps to `run_speed` and its
   `_ground_height` falls back to `_home.y` where the Spotter's falls back to
   `_station.y`. Every flight fix is two edits and has been for a while.
2. Adding the Kite makes `spotter_drone.gd` load-bearing for **three** frames
   (Spotter, Kite, Broodcarrier), so a tuning change aimed at the scout now
   changes a gunship. Mitigation: the Kite overrides nothing inside `_steer`,
   and every flight number it wants to differ on is already an `@export` on the
   scene (`kite.tscn:112-120`).
3. The extraction gets harder, not easier, the longer it waits — by one more
   caller.

**It does not cost correctness.** Nothing in this brief needs the extraction to
exist. Say so to the coordinator and move on.

### 4.3 Exports `kite.gd` must declare

```gdscript
@export_group("Turret")
## The gun pod. MUST be named `turret` — enemy.gd:2895 escapes hull_spoils_aim
## only via a property literally called `turret` being non-null, so a rename
## here is a frame that never fires and never says why.
@export var turret: Node3D                      # -> Rig/Turret
@export var gun_pivot: Node3D                   # -> Rig/Turret/GunPivot
@export var turret_traverse_degrees: float = 90.0
@export var gun_elevation_degrees: float = 60.0
@export var gun_min_pitch_degrees: float = -55.0
@export var gun_max_pitch_degrees: float = 10.0
@export var fire_cone_degrees: float = 9.0
```

Wire them in `kite.tscn` as **node objects, not NodePaths**, exactly as
`build_kite.gd:556-568` warns — the exports are typed `Node3D`, so a NodePath
assignment does nothing and nothing errors. The paths are
`Rig/Turret` (`kite.tscn:330`) and `Rig/Turret/GunPivot` (`kite.tscn:360`).

Values and why they are not the Walker's: traverse 90°/s because an orbiting
platform's bearing to a fixed target changes continuously (the Walker's 55 is a
deliberate counter — getting around the side of it; there is no getting around
the side of a flyer). Elevation 60°/s and a min pitch of −55° because a frame
22 m up shooting something 25 m away horizontally wants about −41° of
depression, and the Walker's −12° would clamp it to a gun pointing at the
horizon. `fire_cone_degrees` 9 against the Walker's 7: a 0.7 m platform
yawing and rolling under `_orient` (`spotter_drone.gd:341-349`) cannot hold a
7° cone, and a cone it cannot hold is a frame that holds fire.

### 4.4 `AllowedMovementOptions` and `AllowedCombatOptions` — as values

Authored on **`kite.tscn`** (they are `@export`s on `Enemy`, lines 1105-1106),
typed `Array[int]` exactly as `soldier_rifle.tscn:70-71` and
`vehicle_rover.tscn:165-166` write them:

```
AllowedMovementOptions = Array[int]([2])
AllowedCombatOptions = Array[int]([1, 2])
```

`MovementOptions {ADVANCE=0, REPOSITION=1, FALLBACK=2, LEAP=3, CHASE=4}`,
`CombatOptions {MOVE=0, AIM=1, FIRE=2}` (`enemy.gd:1091-1092`).

**And no, a flyer does not want a ground frame's set.** This is the one place
the Kite must diverge from `soldier_rifle.tscn`'s `[0,1] / [0,1,2]`, and the
reasoning is mechanical:

- **`MOVE` is deliberately absent from the combat options.** `perform_action`
  (`enemy.gd:3927-3946`) turns MOVE into `move_to(find_reposition_target())` or
  `move_to(find_advance_target())`. On a flyer `move_to` is overridden
  (`spotter_drone.gd:166-170`) to mean *"this is now my orbit centre"*. So every
  MOVE roll would hand the Kite's station to a navmesh point chosen for a robot
  on foot: `find_reposition_target` (`enemy.gd:3975-3986`) is a **2 m** lateral
  step, which is nothing at all to something flying a 14 m orbit at 18 m/s. The
  Kite's flight is the squad's and the orbit's; the combat dice must not own it.
  *(Second reason: §7. The leash rewrites `_station` back to the formation
  anchor within 1.6 s anyway, so a MOVE roll is not just useless, it is
  futile.)*
- **`AIM` and `FIRE` are both present, and FIRE is why the array is non-empty
  at all.** `FIRE` → `_commit_burst` (`enemy.gd:3948`, 3960-3972), which is what
  makes the gun fire *bursts of 8–16* from the weapon's own rhythm instead of
  single shots through the full settle gate. `FRAME_ANATOMY.md` §6.1 is explicit
  that an empty combat array means `_commit_burst` is never called and the frame
  "still shoots, slowly, in single shots" — on a frame whose entire case is
  volume of fire, that is the difference between the Kite working and not.
  `AIM` → `_enter_aim_stance` (3953-3957) sets `movement_state = NONE`, which
  the flight code ignores, and clears `_burst_left`. So AIM is the Kite's
  "hold fire and let the spread settle" and it costs it nothing it can act on.
  Keep it: without it the frame fires continuously and `_aim_tracking` never
  gets to matter.
- **`AllowedMovementOptions = [FALLBACK]`, which is read on reload and nowhere
  else for this frame.** `_pick_movement_option` is reached from exactly one
  call site, `perform_action`'s MOVE branch (verified:
  `grep -rn "_pick_movement_option("` finds only `enemy.gd:3133` the
  declaration and `enemy.gd:3930` the call), so with MOVE absent the array's
  *only* live reader is `_on_reload_started` (`enemy.gd:3039-3042`), which does
  `move_to(find_fallback_target())` when FALLBACK is in the list. That is
  precisely right for a 90-hull aerial with a 5 s reload: it breaks station and
  comes back. It is also the frame's whole defensive behaviour, bought with one
  array element.
- **Do not include `LEAP` or `CHASE`.** `LEAP` calls `leap_towards` on a body
  with no gravity; `CHASE` sets `MovementState.CHASING`, which `handle_chasing`
  (`enemy.gd:2759`) steers along the navmesh the flyer is not on.

### 4.5 Every function `kite.gd` overrides, one line each

| # | function | declared | why the Kite must override it |
|---|---|---|---|
| 1 | `_ready()` | `spotter_drone.gd:106` | `super()` for the ray/group/arc, then warn if `turret == null` the way `walker.gd:90-91` does, and cache the pod's rest cant for #4 |
| 2 | `handle_weapon_logic(delta)` | `enemy.gd:2846`, stubbed at `spotter_drone.gd:175` | **restore it** — `super.super()` is not available in GDScript, so this calls the grandparent explicitly (§4.6). Without it the frame has no weapon state machine at all |
| 3 | `roll_combat_action()` | `enemy.gd:3052`, stubbed at `spotter_drone.gd:179` | **restore it** — this is what reaches `_commit_burst`, so it is what makes the gun fire in bursts |
| 4 | `_update_facing(delta)` | `enemy.gd:2780`, stubbed at `spotter_drone.gd:184` | traverse the pod and pitch the gun. **`rover.gd:597-615` is the template, not `walker.gd:206`** — the Rover's version does *not* call `super()`, which is correct here because the body's attitude belongs to `_orient` (`spotter_drone.gd:341`). Copy the Rover and subtract the pod's rest cant from `want_pitch` (§4.7) |
| 5 | `_turret_forward()` | `walker.gd:229` / `rover.gd:615` | the bearing `_weapon_on_target` compares against. Flattened (`f.y = 0.0`), so the pod's 24° cant does not enter the fire cone |
| 6 | `_weapon_on_target()` | `enemy.gd:2999` | the fire cone. `rover.gd:625-630` verbatim. **`FRAME_ANATOMY.md` §4.2: "overriding it wrong is a frame that never shoots"** |
| 7 | `_sight_forward()` | `enemy.gd:1046` | **the one nobody has written down.** `_tick_vision` (`enemy.gd:960-964`) builds its FOV cone from this, and the base returns `-basis.z` — the *airframe's* nose, which `_orient` points along the flight path. An orbiting Kite would therefore sweep its 130° cone (`enemy.gd:531`) around the circle and lose sight of its own target every half-orbit. `rover.gd:621-622` solves exactly this by returning `_turret_forward()`; do the same. The Spotter does not need it because losing a contact costs it nothing |

That is **seven functions**, of which two are restorations, four are the
Rover's turret set, and one (`_sight_forward`) is new reasoning. Roughly 90
lines with the comments this project expects.

**Explicitly NOT overridden** — inherited from `SpotterDrone` and must stay
that way: `handle_movement`, `handle_gravity`, `_apply_motion`, `move_to`,
`takes_cover`, `slot_tolerance`, `formation_width`, `off_navmesh_is_normal`,
`_enter_ekill`, `enter_downed`, `_on_crash_started`, `_on_crash_landed`,
`_on_revived`, `_steer` and everything under it.

### 4.6 The restoration problem, concretely

GDScript has no `super.super()`. `SpotterDrone.handle_weapon_logic` is `pass`,
so `kite.gd` cannot reach `Enemy.handle_weapon_logic` through the chain. Two
ways, and the second is the one to take:

- **Rejected:** copy `enemy.gd:2846-2949` into `kite.gd`. A hundred lines of
  the most-edited state machine in the project, forked. No.
- **Take this one:** restore via the base class's own method object.

```gdscript
# WHY THIS IS NOT super(delta). SpotterDrone's version is `pass` — it is an
# unarmed scout and says so (spotter_drone.gd:172-174). The Kite needs Enemy's
# loop, which is two steps up the chain, and GDScript has no super.super().
# Calling it off the script resource is the only way to reach past one stub
# without forking a hundred lines of state machine.
const _ENEMY := preload("res://Character/characters/ai/enemy.gd")

func handle_weapon_logic(delta: float) -> void:
    _ENEMY.handle_weapon_logic.bind(delta).call()   # see note
```

**This is the one thing in this brief I have not run.** The reliable form in
Godot 4.3 is a `Callable` built from the base script's method on `self`; if the
builder cannot make a clean one-liner work, the fallback is explicit and cheap:
**delete the two stubs from `spotter_drone.gd` and move them down into a tiny
`scout_drone.gd` that the Spotter and Broodcarrier extend.** That makes
`SpotterDrone` the flight model and "no weapon, ever" an opt-in — which is what
it should have been, and which is the cheap half of §4.2's extraction. Decide
this at step 3 of §6 with the probe in front of you, and **report which way it
went**, because it changes `spotter_drone.gd`, a shared file.

### 4.7 The pitch double-count (visual, not functional — but fix it)

`Rig/Turret` carries a fixed **−24°** of X rotation (`build_kite.gd:624`), the
pod's down-cant, and `build_kite.gd:56-70` is deliberate about it: Node3D euler
order is YXZ, so a later `turret.rotation.y = yaw` yaws about the body vertical
and *then* applies the cant, and the two do not fight. Correct.

But `rover.gd:605-612` computes `want_pitch` from **world** geometry
(`atan2(to.y, horizontal)`) and assigns it to `gun_pivot.rotation.x`, which is
local to the already-canted turret. Copied verbatim, the Kite's gun would sit at
`−24° + want_pitch` — about −60° when aiming at something 41° below. The gun
would visibly point well under its target.

**It does not stop the frame firing.** `_weapon_on_target` flattens y
(`rover.gd:625-630`) and `check_damage` resolves position-to-position
(`ai_weapon.gd:396-399`), so elevation is cosmetic for both the gate and the
damage — which is the same fact `KITE.md` §2 uses to retract its own
justification. It is still wrong on screen on the frame whose whole silhouette
argument is "the gun, its eye and its ring all look where it shoots"
(`build_kite.gd:58`).

**Fix:** cache `_pod_cant = turret.rotation.x` in `_ready()` and clamp
`want_pitch - _pod_cant` instead of `want_pitch`. One line, and a comment
saying why, because the next person to read it will think it is a bug.

---

## 5. Registration — `FRAME_ANATOMY.md` §1, walked for this frame

**S** = fails silently. **H** = hard error, and only at spawn.

| § | item | Kite | state |
|---|---|---|---|
| 1.1 | `kite.tscn` + `tools/build_kite.gd` | — | **done** |
| 1.2 ① | `Campaign/chassis/chassis_kite.tres` | §2 | **TODO** — nothing can reference the frame without it |
| 1.2 ② | root script resolves to `Soldier` | `kite.gd extends SpotterDrone extends Soldier` | **H** — fine, but re-check after editing the scene's script |
| 1.2 ③ | `groups=["enemies"]` | `kite.tscn:110` | **done** (`build_kite.gd:404`, persistent) |
| 1.2 ④ | `KillKinds.FRAMES` | `&"kite": "res://Campaign/chassis/chassis_kite.tres"` next to `kill_kinds.gd:35` | **TODO — S.** Without it `frame_of()` returns null (73-77): raw id in the debrief, blank roster glyph, and `bake_icons.gd:126-129` never bakes an icon |
| 1.2 ⑤ | `Allowed*Options` | §4.4 | **TODO — S.** Currently *absent from the scene entirely* (`build_kite.gd:223-249` strips the mistyped lines), which is the same empty default |
| 1.3 ⑥ | `test_item_catalogue.tres` — `[ext_resource]` **and** the `chassis = Array[...]` line (currently **line 48**) | append | **TODO — S.** Both edits or neither: `buildable_frames()` (440-453) walks `catalogue.chassis` only. Edit the one under `Campaign/items & catalogue/`; `Campaign/item_catalogue.tres` is a dead stub |
| 1.3 ⑦ | `purchasable = true` | §2 | **TODO** — `recruit()` refuses otherwise |
| 1.3 ⑧ | `icons/chassis/kite_{s,m,l}.png` | `tools/bake_icons.gd` | **TODO — S.** Needs ④ and ⑥ first. **Run it and report whether the PNGs landed** — the Bulwark's never did (trap 6.3) |
| 1.5 ⑪ | `KillKinds.SCENES` | **not needed** | basename `kite` == id `kite`, so `kind_of` falls through (`kill_kinds.gd:70`) |
| 1.5 ⑫ | `EnemyLoadouts.TABLES` | **not needed** | player frame. Adding a key commits you to `test_enemy_loadouts.gd:91-124` |
| 1.5 ⑬ | `Campaign/cosmetics.gd` | **skip** | no hat on an aircraft; `for_frame` returns `[NONE]` and the cycle control still works |
| 1.5 ⑭ | a mission `unlocks` entry | **TODO** — the real gate, since `required_rank` is inert | `mission_salient_1_overthetop.tres:596` currently has `unlocks = Array[StringName]([])` and is the obvious host. **Order matters:** `machine_gun` is unlocked by `mission_hillfort_1_relay.tres:471`, so put the Kite's unlock no earlier, or the player owns a frame whose gun they cannot buy a spare of. **Coordinator's call** |
| 1.5 ⑮ | a lab plan | optional | `Campaign/lab/plans/bulwark_screen.tres` is the precedent. Worth one: a flyer-vs-ground matchup is the only way to see whether the 3x spread penalty leaves the gun worth carrying |
| 1.5 ⑯ | `tools/test_kite.gd` | §6 | **TODO** — `tools/test.sh` picks up `tools/test_*.gd` with no wiring |
| 1.5 ⑰ | `probe_nav_reach.gd` `FRAMES` | **not needed** | it does not walk |
| 1.6 | CSG bake, teams, `"signal"` group, `AIManager` | — | free. `csg_bake.gd:177-189` reads the directory; `vehicle = true` is the whole of team assignment |

### The `"air"` group — confirmed, and it is free

`FRAME_ANATOMY.md` §1.6 says the `"air"` group is joined in code, not in the
scene. **Confirmed:** `spotter_drone.gd:108` `add_to_group("air")` inside
`_ready()`, called before anything else that matters, and non-persistent (the
default) which is correct for a runtime group. `kite.gd:_ready` calling
`super()` inherits it. **Nothing to do** — but the test in §6 asserts it anyway,
because the one thing that would break it is a `kite.gd:_ready` that forgets
`super()`, which is exactly the kind of thing that happens.

---

## 6. Tests — `tools/test_kite.gd`

Model on `tools/test_bulwark.gd`: `extends SceneTree`, `_ok(label, cond, detail)`
(52-58), `_spawn(path, at)` (61-67) which adds to `root` and disables
`_physics_process`/`_process`, one `await process_frame` per spawn, `free()`
after. Its `_test_the_chassis_is_registered` (70-90) is §1.3 of the anatomy as a
test and is the cheapest thing to copy.

```
godot --headless --audio-driver Dummy --path . --script res://tools/test_kite.gd
```

**Run nothing through Godot while `tools/test.sh` is in flight** — the suites
share `user://` probe paths and a parallel run produces a FAIL that looks real
and does not reproduce.

### The assertion the whole frame turns on

**`it actually fires`** — asserted, not assumed, because the weapon loop it
needs is `pass` on the script it inherits from.

```
_test_it_fires_while_moving()
  spawn kite; add ai-wep_machine_gun.tscn under `weapon_mount`
  assert  k.weapon != null                      # equip_weapon_scene took it
  spawn a hostile 40 m away on a different faction
  k.ai_state = COMBAT; k.combat_target = target; k.weapon_target = target.global_position
  k._has_los = true                             # enemy.gd:1315, plain var
  k.velocity = Vector3(18, 0, 0)                # _is_moving() -> true (enemy.gd:2837)
  tick k.handle_weapon_logic(1.0/60.0) ~240 times

  assert  k._aim_tracking > 0.0
          # THE ONE THAT CATCHES THE SILENT FAILURE. enemy.gd:2895 decays
          # _aim_tracking every frame unless a non-null `turret` property
          # exists. A Kite without it never leaves AIM and never fires.
  assert  k.weapon_state == WeaponState.FIRE at least once during the loop
  assert  k.weapon.magazine_current < k.weapon.magazine_size
          # the proof that rounds actually left, not merely that a state was
          # entered
```

Then, separately, the two halves of that in isolation, so a failure says which:

```
_test_the_pod_is_the_turret()
  assert  k.get("turret") != null                       and is Rig/Turret
  assert  k.get("gun_pivot") != null                    and turret.is_ancestor_of(gun_pivot)
  assert  gun_pivot.is_ancestor_of(k.weapon_mount)      # elevating moves the gun with it
  assert  "turret" in k and k.get("turret") != null      # enemy.gd:2895 verbatim
_test_the_weapon_loop_is_not_stubbed()
  # Guards against a future edit to spotter_drone.gd re-stubbing the Kite.
  assert  k.get_script().get_method_list() names handle_weapon_logic and roll_combat_action
  assert  k.AllowedCombatOptions.size() > 0             # enemy.gd:3053 returns on empty
  assert  CombatOptions.FIRE in k.AllowedCombatOptions  # reaches _commit_burst
```

### The rest

```
_test_the_chassis_is_registered()
  def loads; def.id == &"kite"; def.scene != null
  def.weapon_slots == 1; String(def.coax_weapon_id) == ""   # no coax_mount exists
  def.turret == true
  def.supply == 2
  def.base_accuracy > 0.0
      # THE SILENT KILLER. 0.0 is a MULTIPLIER (squad_spawner.gd:348) and makes
      # spread 1200 mrad (enemy.gd:5231-5235). chassis_spotter.tres:19 is 0.0
      # and is the file a builder would copy.
  catalogue(Campaign/items & catalogue/test_item_catalogue.tres).chassis ids has "kite"
  KillKinds.frame_of(&"kite") != null

_test_the_gun_is_legal_on_it()
  # The Bulwark's live defect, as an assertion. A frame that can be armed once
  # and never refitted passes every other check in this file.
  var item = catalogue.item(def.starting_weapon_id)
  assert  def.takes(item)        # chassis_definition.gd:84-91
  assert  item.fits_ai()         # needs ai_scene + usable_by_ai

_test_it_flies()
  given move_to(p), it holds ~cruise_height above varying ground
  (tools/test_air_clearance.gd:21 already drives the Spotter this way — copy it)

_test_it_can_be_shot_down()
  a ray from the ground at the collider hits it (0.7 m sphere, build_kite.gd:417)
  enter_downed() produces a crash, not a standing corpse
      (flatten_collider_when_downed == false, kite.tscn)

_test_emp_drops_it()
  # SpotterDrone._enter_ekill (359-363) calls die(). Assert it DELIBERATELY:
  # the open question in §8 is whether that is right for a 240-compute frame,
  # and this assertion is what makes changing the answer a visible decision
  # rather than a regression.
  k._enter_ekill();  assert not k.alive or k.downed

_test_the_groups_and_the_typed_arrays()
  k.is_in_group("enemies")            # kite.tscn:110
  k.is_in_group(AI.SIGNAL_GROUP)      # ai.gd:86-88
  k.is_in_group("air")                # spotter_drone.gd:108 — proves _ready called super()
  particle_effects_die / _hit / visible_pieces all non-empty   # trap 6.6
  FactionLivery.pieces non-empty and does NOT contain the Eye; apply(ENEMY)
  leaves the Eye's material a StandardMaterial3D while Hull becomes a ShaderMaterial
      # test_bulwark.gd:186-229 is this test; copy it
```

---

## 7. The squad leash — verified, and it is worse-documented than it is harmful

### What is actually true

`Squad._enforce_leash` (`Managers/AI/squad.gd:640-679`):

- `var gap: float = soldier.global_position.distance_to(anchor)` (658) — **full
  3D**, and the anchor is a ground-level objective point plus a formation
  offset (`_anchor_for`, 682-689);
- **never calls `slot_tolerance`** — grep confirms the only `slot_tolerance`
  call sites in the file are `squad.gd:525` (defend posts), `728`
  (`_hold_follow_formation`) and `841`;
- radii: `follow_combat_leash = 12.0` (147), `defend_combat_leash = 9.0` (148),
  with `leash_grace_multiplier = 1.6` (167) for anyone `_engaging_usefully`.

So the ceilings are **19.2 m** and **14.4 m**, and the Kite cruises at **22.0 m**
(`kite.tscn:112`). It is outside both, always, by altitude alone. Confirmed.

**And the leash is plainly the oversight, not the design.**
`_hold_follow_formation` — the *other* position-holding path, 88 lines further
down the same file — uses `_flat_gap` (728) **and** `slot_tolerance`, and
`squad.gd:722-724` says why in as many words: *"On the ground plane: a slot
takes its height from the leader, and measured in 3D a robot standing in its own
slot partway down a hill reads as metres out of it."* The leash wants the same
rule and does not have it.

### Does the Spotter already suffer it? **Yes — and here is why nobody noticed**

The Spotter is purchasable and deploys into the player's squad
(`chassis_spotter.tres:12-14`), so it is leashed on exactly the same arithmetic.
What saves it is what the recall *does*:

- `_enforce_leash` calls `soldier.order_move_to(anchor, true, true)` (679) —
  `force = true`, **`keep_target = true`**. `Soldier.order_move_to`
  (`soldier.gd:369-425`) therefore does **not** clear `combat_target` (412-413
  are gated on `not keep_target`) and does **not** drop out of COMBAT (420-421).
- `move_to` on a flyer is `_station = pos` (`spotter_drone.gd:166-170`). The
  anchor is the Spotter's own formation slot — the point it was already
  orbiting.
- It is rationed: `_may_recall` (625-632) allows one per `recall_interval` =
  **1.6 s** (164).
- Out of contact the leash does not run at all — `_enforce_leash` is reached
  only from the `context == ENGAGED` branches (491, 515), and the non-engaged
  path is `_hold_follow_formation`, which handles altitude correctly.

So for the Spotter a recall is a no-op that rewrites a station to where it
already was. `BROODCARRIER.md` §6.1's "expect it to be recalled constantly" is
right about the mechanism and overstates the harm.

### Why it is the Kite's problem anyway, and what to do

It is not that the Kite gets dragged to the ground. It is that **the Kite can
never own its own station during a firefight**: anything `kite.gd` or the combat
dice writes to `_station` is overwritten with the formation anchor within 1.6 s.
Combat manoeuvre is structurally unavailable to it.

**Decision: accept it, and make the Kite's design agree with it rather than
fight it.** That is why §4.4 leaves `MOVE` out of `AllowedCombatOptions` — the
one behaviour the leash would break is the one behaviour the frame is not given.
The two decisions are the same decision. **Do not lower `cruise_height`:** to
get inside the bare defend leash it would have to go under 9 m, which is not an
aerial, it is a hovercraft, and it would throw away the terrain-clearance
headroom `air_clearance.gd` exists for.

**Separate ticket, not this frame's** (it is a shared file and it changes the
Spotter and the bomber too):

```gdscript
# Managers/AI/squad.gd:658 — the fix shape, for the coordinator to rule on
var gap: float = _flat_gap(soldier.global_position, anchor)
var bound: float = maxf(radius, soldier.slot_tolerance(radius))
if gap <= bound:
    continue
```

Flat, and tolerant of a frame that says how much room it needs — the same two
rules `_hold_follow_formation` already follows. **Do not land it inside the
Kite's pass.**

---

## 8. Order of work, and what each step proves

1. **`item_machine_gun.tres:37` — add `&"kite"`.** Prove: a scratch probe
   loading `chassis_kite.tres` and `item_machine_gun.tres` and asserting
   `def.takes(item)`. One line, first, because the Bulwark's bug is already
   loaded in the chamber and every later step would mask it.
2. **`chassis_kite.tres`** (§2). Prove: it loads, `id == &"kite"`,
   `base_accuracy > 0.0`. **Do not move it afterwards** (trap 6.8: a renamed
   `.tres` leaves a `null` in the catalogue array).
3. **`kite.gd`** (§4). Settle the `handle_weapon_logic` restoration here
   (§4.6) and **report which of the two forms you used.** Prove:
   `check.sh --changed` prints PASS, and the frame instantiates with
   `turret != null`.
4. **Wire `turret` and `gun_pivot` in `kite.tscn`, as node objects,** and set
   the script to `kite.gd`. Prove:
   `check_frame.gd -- res://Character/characters/ai/kite.tscn` prints PASS.
5. **Author `Allowed*Options`** as `Array[int]` (§4.4). Prove: a probe reading
   both arrays off an instance and asserting `get_typed_builtin() == TYPE_INT`
   and non-empty. **This is the step most likely to be quietly wrong** — the
   scene writer has emitted these as `Array[ExtResource(...)]` on every
   generated frame in the batch (`build_kite.gd:202-222`), so author them in
   the editor or by hand and check what landed on disk.
6. **`kill_kinds.gd` `FRAMES`** + **`test_item_catalogue.tres`** (both the
   `[ext_resource]` and line 48). Prove: `tools/test_ledger.gd` still passes —
   it exercises recruit, refit and the save round-trip, and `449-465` asserts
   that a catalogue frame no mission unlocks is on sale from minute one, which
   is step 8's problem.
7. **`tools/test_kite.gd`** (§6). Prove: it fires. This is the step that makes
   the frame real; everything before it is plumbing.
8. **A mission `unlocks` entry** (§5 ⑭). Prove: `tools/test_ledger.gd:826-831`.
9. **`tools/bake_icons.gd`.** Prove: `icons/chassis/kite_s.png`, `_m`, `_l`
   exist on disk. **Say so in the report either way** — nothing asserts this
   and it is how the Bulwark's blank card survived (trap 6.3).
10. **`bash tools/check.sh --changed` → PASS, `bash tools/test.sh`,
    `bash tools/smoke.sh`.** `test.sh` because the ledger and the catalogue
    moved; `smoke.sh` because the catalogue loads at startup
    (`Env/world.tscn:20`).
11. **Optional: `Campaign/lab/plans/kite_screen.tres`.** The only way to find
    out whether a gun carrying a permanent 3x spread penalty is worth 240.

---

## 9. Open questions and risks

**For the human, before the build starts:**

1. **Is the frame worth it at all?** §1 is as honest as I can make it: the angle
   advantage is soft and emergent, and the real proposition is reach-without-a-
   route plus volume-of-fire-without-accuracy. Two frames were cut this week for
   a thin gap. This one's gap is *real* but it is **a convenience and a tempo
   advantage, not a capability nothing else has.** You are the only one who can
   say whether that is enough, and the cheapest way to find out is step 11
   before step 7.
2. **`equipment_slots = 0`?** The design doc says 0. An aerial EMP or smoke
   delivery is the one thing genuinely unavailable to a ground frame — the
   equipment brain is already written and populated (`enemy.gd:3674-3863`,
   `ai_equipment.gd:30-45`) and would cost one number. It would also make the
   Kite the answer to a lot of problems at once. **Left at 0 per the doc; say
   if you want it.**
3. **Does an EMP get to one-shot a 240-compute frame?** `SpotterDrone._enter_ekill`
   (359-363) calls `die()`, and the comment is right that a frozen aircraft
   hanging in mid-air reads as a bug. The alternatives are a crash it survives,
   or a slower fall. §6's test asserts the current behaviour deliberately so
   changing it is a decision.

**Risks I am handing to the builder:**

4. **`base_accuracy = 0.0`.** The highest-probability silent failure in the
   frame, because the file a builder copies sets it. §2 box, §6 assertion.
5. **The whitelist.** Second highest, because the frame *works* without it
   until the player tries to refit. §3.
6. **`super.super()`.** §4.6 is the one claim in this brief I did not execute.
   If the `Callable` form is awkward, the fallback (splitting the two stubs into
   a `scout_drone.gd`) touches a shared file and needs saying out loud.
7. **`Allowed*Options` landing as `Array[ExtResource]`.** The family bug
   (`build_kite.gd:202-222`, `FRAME_ANATOMY.md` §6.1). Check the file on disk.
8. **The leash.** §7. Accepted for this frame, ticketed separately, and the
   combat options are chosen so it costs nothing.
9. **The pitch double-count.** §4.7. Cosmetic, cheap, and it will look like a
   bug to whoever sees it next.

---

## 10. What I found wrong in the design docs

`docs/briefs/FRAME_ANATOMY.md` — **I found nothing wrong.** Every claim I
checked held, including the ones most likely to rot: §2 on `required_rank`
(`campaign_state.gd:1165` is the only reader), §1.6 on the `"air"` group
(`spotter_drone.gd:108`), §3.4's hitscan rule, §6.1's mechanism for the empty
arrays, §6.2's Bulwark trace and §6.9 on `base_speed`. §4.2's note that
"overriding `_weapon_on_target` wrong is a frame that never shoots" is the most
load-bearing sentence in it for this frame. Its §8.6 ("a per-frame speed field
that is actually a speed — there is none") is worth extending with the flyer
case: see the `base_speed` box in §2, where even `move_speed` is inert.

`docs/frames/KITE.md`:

- **§3 omits `base_accuracy` entirely**, and the obvious template for the file
  sets it to 0.0, which makes the gun miss by 69 degrees. The most expensive
  gap in the document.
- **§3's `base_speed = 1.2` is spent on nothing.** The flight code never reads
  `move_speed`. §2.
- **§4 "None required" is right about the item and wrong about the work.** No
  new `ItemDefinition`, but `item_machine_gun.tres:37` must gain `&"kite"` or
  `turret = true` makes the gun illegal on its own frame. The doc does not
  mention the whitelist at all.
- **§6.1 is right but understates one thing** — the restoration is not just
  "put them back", it is *reaching past a stub two classes up* (§4.6).
- **§6.3 says the Spotter "survives this by accident".** More precisely: the
  Spotter is leashed identically and the recall is a no-op for it because
  `keep_target = true` and because a flyer's `move_to` only rewrites a station
  it was already orbiting. §7.
- **§6 lists four code requirements and there are seven functions and a fifth
  requirement.** The missing one is `_sight_forward()`: without it an orbiting
  Kite sweeps its vision cone around the circle and loses its own target every
  half-orbit (`enemy.gd:960-964`; `rover.gd:621-622` is the fix). Nothing in
  any document names it.
- **§7 asks for a test that "a fitted weapon points where the frame faces".**
  Keep it, but note the mount's yaw is `+PI/2` not the Walker's `-PI/2`
  (`build_kite.gd:698`, and `build_kite.gd:72-76` explains why), so
  `test_bulwark.gd:258-262`'s assertion copies across only if the sign is
  adjusted.

`docs/frames/BROODCARRIER.md` §6.1 — its extraction trigger is three *copies*,
not three *flyers*, and the Kite adds a flyer without adding a copy. Deferred,
with the cost stated. §4.2.

`tools/build_kite.gd` — **accurate throughout.** Its §"WHAT THIS PASS CANNOT
WIRE" (101-119) states the `turret`/`GunPivot` situation and `enemy.gd:2895`
correctly, its euler-order reasoning (60-70) is right (`Basis` from YXZ euler is
`Ry * Rx * Rz`, so yaw is applied about the body vertical and the cant after
it), and the gun's move to starboard (145-177) is sound. The one thing it could
not know is §4.7.

---

## 11. What I could not find

1. **A clean, executed form of `super.super()`** for GDScript 4.3. §4.6 gives
   the shape and the fallback; I did not run either. Stated as a risk rather
   than asserted.
2. **Any existing armed aerial to copy for *aiming*.** There is none.
   `enemy_helicopter.gd` is the only aircraft in the game that puts ordnance on
   a target, and it does not aim: `handle_weapon_logic` (163-164),
   `roll_combat_action` (169-170) and `_update_facing` (173-174) are all `pass`,
   and every release is decided by `_predicted_impact()` (380-386) from the
   drone's own velocity and height. Its targeting (`_aim_point`, 331-344, the
   centroid of a cluster), its lead (physics of a falling bomb) and its firing
   arc (`line_tolerance` / `release_window`, a corridor on the ground) are all
   properties of *dropped ordnance on a straight pass* and **none of them
   transfers to a conventional gun.** For a hitscan gun the equivalent machinery
   already exists in `Enemy` and is what §4.5 restores. The bomber's value to
   this frame is its flight model — which the Kite gets via the Spotter — and
   its documented failures, not its weapon code.
3. **Why the Spotter's `base_accuracy` is 0.0** rather than 1.0. The field is a
   multiplier for player frames and an absolute for enemies
   (`enemy_force_spawner.gd:530`), and 0.0 means "keep the scene's value" on the
   enemy path only. I could not find a comment either way, so I am treating it
   as "harmless on an unarmed frame" rather than as a convention to copy.
4. **Whether anything counts the loss of a *player* frame by kind.**
   `FRAME_ANATOMY.md` §8.2 could not find where a player squad body gets its
   `chassis_id` meta either; I re-checked `squad_spawner.gd` and found only
   `record_id`. So I cannot say what the user-visible consequence of a missing
   `KillKinds.SCENES` entry would be for a player frame — but the Kite does not
   need one (basename matches id), so it does not block this build.
