# LANCE — integration brief

Supply 1 · wheeled scout/harasser · model built, **nothing else exists**

Companion to `docs/frames/LANCE.md` (design) and `docs/briefs/FRAME_ANATOMY.md`
(the map). This document is the build order. Where it disagrees with the design
doc it says so and says why.

**What exists today:** `Character/characters/ai/lance.tscn` (root script
`rover.gd`, in `groups=["enemies"]`) and `tools/build_lance.gd`, the one-shot
generator. **Do not re-run the generator.** Its own header says the `.tscn` is
the source of truth from the moment it ran, and everything this brief asks for
in the scene is a hand edit to `lance.tscn`.

**Nothing else.** No `ChassisDefinition`, no weapon, no catalogue entry, no
`KillKinds.FRAMES` key, no icons, no test, no behaviour script.

> **Verification note.** Three Godot processes were running in this checkout
> while this brief was written, so per the rule in `FRAME_ANATOMY.md` §7 I ran
> **nothing** through Godot. Every claim below is read off source and off the
> `.tscn` by hand, with a `file:line`. The two places where a number needs
> *measuring* rather than reading are called out as such in §7.

---

## 1. What "successful" means for this frame

A player who has six supply and wants eyes on a flank can today spend 1 on a
rifleman who walks at 6 m/s (`soldier_rifle.tscn:67`) or 2 on a Rover
(`chassis_rover.tres`, `supply = 2`). There is nothing in between, and the gap
is the biggest one on the sheet. Success for the Lance is that a supply-1 seat
can buy **arrival**: a frame that is on the overlook, or in the enemy's flank,
before the squad's line has closed, and that pays for that by dying to anything
that gets alongside it — because it has no turret and must point its whole body
to shoot.

**Be honest about how thin this is.** Two things currently make the frame's
promise smaller than the design doc believes:

1. **It will ship with exactly one fittable gun.** Every `kind = 0` weapon in
   `Campaign/items/` that is `fits_vehicles = true` already carries a
   `chassis_whitelist` that excludes `lance` — `machine_gun` and `heavy_mg` and
   `autocannon` are `[&"walker", &"rover"]`, `grenade_launcher` is `[&"rover"]`,
   `mortar` is `[&"reclaimer"]`. Everything with an *empty* whitelist
   (`m4`, `carbine`, `bolt`, `dmr`, `squad_auto`, `cluster_launcher`) is
   `fits_vehicles = false` and is refused by `drives = true`
   (`chassis_definition.gd:89-90`). So `LANCE.md` §4's claim that "the Lance can
   take any vehicle-legal weapon… a Lance with a machine gun is a legitimate and
   different thing" is **false against the data on disk**. See §3.
2. **It cannot turn to face a target while parked** — the measured consequence
   of the stub turret, `rover.gd:597-600`. Unfixed, a Lance that stops is a
   Lance that can only shoot whatever happens to be inside a 6° cone off its
   nose (`lance.tscn:180`, `fire_cone_degrees = 6.0`). See §4; this is the one
   piece of new code the frame genuinely needs.

With both closed the frame is worth building: it is the cheapest seat in the
game, it is the only frame that aims by driving, and it is the first thing the
player owns that can be somewhere else. With neither closed it is a slower,
blinder Rover that costs 90.

---

## 2. The `ChassisDefinition`

New file: **`Campaign/chassis/chassis_lance.tres`**, script
`res://Campaign/chassis_definition.gd`. Copy `chassis_rover.tres` as the
skeleton — same `vehicle`/`drives` shape, two `[ext_resource]` lines, no
sub-resources.

| field | value | why / citation |
|---|---|---|
| `id` | `&"lance"` | **PERMANENT.** `FRAME_ANATOMY.md` §2.5: written to the save as `chassis_id` (`soldier_record.gd:486`), as `kills_by_kind` keys (483) and as armoury stock (`campaign_state.gd:1234`). `CampaignState.RENAMED` is applied to kill tallies only. No collision: the *item* `repair_lance` is a different namespace, and `tools/test_lance.gd` is a test file, not an id. |
| `display_name` | `"Lance"` | `_recruit_name` takes the **first word** as the callsign (`campaign_state.gd:769-770`), so a one-word name is what you want. `KillKinds.name_of` strips a trailing `" CHASSIS"` (`kill_kinds.gd:81-84`); don't add one. |
| `description` | see below | factory card and hologram. Must say *no turret* — it is the whole frame. |
| `icon` | leave **null** | an inspector-set texture beats the baked PNG (`icons.gd:43-44`). Let `bake_icons.gd` do it (§5). |
| `scene` | `lance.tscn` | **PERMANENT PATH.** Serialised as a path (`soldier_record.gd:472`); a move makes every saved Lance fall back to `squad_spawner.default_chassis` (269-272). |
| `cost` | `90` | design doc. Between the soldier's 50 and the Rover's 150. Not permanent — retune freely, and run `tools/audit_economy.gd` once it exists. |
| `purchasable` | `true` | mandatory or `recruit()` refuses outright (`campaign_state.gd:740-741`). |
| `supply` | `1` | the point of the frame. Note `supply_of` returns 1 for an *unknown* frame too (`campaign_state.gd:315-317`), so supply 1 is the one stat whose correctness is invisible — the catalogue entry in §5 is what proves it. |
| `starting_weapon_id` | `&"light_cannon"` | §3. Written straight into `weapon_ids[0]` without consulting `takes()` (`campaign_state.gd:750-751`), so this must still be a gun the frame can legally refit — see §3. |
| `coax_weapon_id` | `&""` | `lance.tscn` has **no** `coax_mount` node (the root `node_paths` list at `lance.tscn:146` does not include one). A coax would warn once per body per mission (`enemy.gd:77-81`, trap 6.12). |
| `base_health` | `110` | absolute for a player frame (`soldier_record.gd:238`). Agrees with `lance.tscn:205-206`, so a hand-placed Lance and a bought one match. |
| `base_speed` | **`1.0`** — not the doc's 1.35 | **A CORRECTION, AND THE BIGGEST SINGLE ERROR IN THE DESIGN DOC.** `base_speed` is a *multiplier* (`soldier_record.gd:254` → `squad_spawner.gd:349`, `soldier.move_speed *= …`). `build_lance.gd:530-536` already applied the doc's 1.35 to the Rover's 7.0 and wrote `move_speed = 9.45` into the scene (`lance.tscn:208`). Writing 1.35 here multiplies it a second time: **12.76 m/s**, 1.8× a Rover. Put 1.0 here and let the scene carry the speed. |
| `base_accuracy` | `1.0` | multiplier (`squad_spawner.gd:348`). The scene already sets `accuracy_skill = 0.75` (`lance.tscn:226`), which is line-trooper standard; leave the frame neutral. |
| `base_sensor_range` | `60.0` | absolute (`squad_spawner.gd:350`). Matches `lance.tscn:255`, so this is a confirming duplicate rather than an override. |
| `weapon_slots` | `1` | one mount exists (`Rig/GunMount/GunPivot/WeaponMount`). Capped at 2 by `_fit_loadout` anyway (`squad_spawner.gd:300-301`). |
| `built_in` | `"CLAWS"` | matches the Rover, the Walker and the Bulwark. **Note it is a blank icon:** `Icons.built_in` does `path("items", "claws")` (`icons.gd:63-66`) and `icons/items/` has no `claws_*.png`; `icon_art.gd:129-135` `BUILT_INS` has no `claws` key either. This is pre-existing on five shipped frames, not something the Lance introduces — see §8. |
| `weapon_replaces_built_in` | `false` | the gun does not stand where the claws were. |
| `turret` | **`false`** | the defining trait, and it is *also* the thing that keeps the frame refittable: `takes()` only applies the whitelist rule when `turret` is true (`chassis_definition.gd:91`), so a `turret = false` frame avoids the Bulwark's "armable exactly once" hole (`FRAME_ANATOMY.md` §6.2) entirely. |
| `vehicle` | `true` | musters with ARMOR (`campaign_state.gd:468-496`). Consequence: an all-vehicle squad follows at `armor_follow_distance = 10.0` plus `team_follow_step = 5.0` per team rank (`squad_spawner.gd:75-80, 176`) — see §8 on whether a 9.45 m/s frame stays inside that. |
| `drives` | `true` | wheels. Refuses `fits_vehicles = false` kit (`chassis_definition.gd:89-90`), which is what keeps Nanite Reboot (`item_nanite_reboot.tres`, `fits_vehicles = false`) off it. Load-bearing: a cheap vehicle that self-revives makes the soldier pointless. |
| `equipment_slots` | `1` | design doc. Sizes `record.equipment` (`soldier_record.gd:158`). |
| `module_slots` | `1` | design doc. One module on the cheapest frame is the right shape; the Rover gets 3. |
| `musters_at_base` | `true` | it stands in the hangar. Only read by `campaign.gd:910-917`. |
| `required_rank` | `0` | **and understand that the field does nothing.** `recruit()` never reads it (`campaign_state.gd:739-764`); only `set_chassis` does (1165). `FRAME_ANATOMY.md` §6.4. The Lance *wants* to be available from the first visit, so 0 is both correct and inert, and **no mission `unlocks` entry is needed** — which is the one frame in this batch where the trap and the design agree. |

Suggested `description` (it has to carry the turretless constraint, because
nothing else on the card will):

> Two driven wheels, a castor and a gun bolted in the nose. No turret ring: it
> aims by pointing itself, so it shoots what it is driving at and nothing else.
> The cheapest thing you can field that is not on foot.

**Permanent once written:** `id`, `scene` path, and any `Enums` ordering this
touches (it touches none). **Safe to retune at any time:** every stat, every
slot count, `cost`, `supply`, `display_name`, `description`, `built_in`
(`FRAME_ANATOMY.md` §2.5).

---

## 3. The weapon — `light_cannon`

### 3.1 Subclass, or `.tres` plus an existing scene?

**No subclass. A `.tres` plus a new scene on the plain `ai_weapon.gd`.**

Answered against the rule in `FRAME_ANATOMY.md` §3.4: *you need a subclass if
and only if the round is not a hitscan ray.* A `light_cannon` as the design doc
specifies it — one high-damage round, slow cycle, 85 m, 7 mrad — is a hitscan
ray. Everything it needs is already an `@export` on the base
(`ai_weapon.gd:11-83`): `fire_cooldown`, `base_damage`, `min_damage`,
`damage_falloff_start`, `max_effective_range`, `ai_spread_mrad`,
`magazine_size`, `reload_time`, `suppression_per_shot`, `near_miss_radius`,
`burst_min`/`burst_max`, muzzle flash, muzzle origin, audio, tracer.

**Closest template, named:** `Character/weapon/ai-wep_autocannon.tscn`. Same
family — a cannon with a low rate, a committed burst and its own magazine — and
it is the shortest of the gun scenes (33 lines). Copy it and change the numbers.
Note what it does *not* have: no root transform. The muzzle sits at local
**+X 1.7** (`ai-wep_autocannon.tscn`, `Muzzle` node), which is why every frame's
`WeaponMount` is yawed **+PI/2** to turn a weapon's +X onto the frame's -Z.
`lance.tscn:405` already is: basis `(-4.37e-08, 0, 1 / 0, 1, 0 / -1, 0, -4.37e-08)`
is `rotation.y = +PI/2`, and `tools/check_frame.gd` asserts exactly that.

### 3.2 The `ItemDefinition`

New file: **`Campaign/items/item_light_cannon.tres`**, script
`res://Campaign/item_definition.gd`. Copy `item_autocannon.tres`.

| field | value | why |
|---|---|---|
| `id` | `&"light_cannon"` | an item id is a save key too (fitted `weapon_ids`, unlock lists, allocations). Treat as permanent. |
| `display_name` | `"Light Cannon"` | |
| `short_name` | `"L.CAN"` | it has to fit a 58 px slot; `short_label()` derives one from the last word if blank, which here would give "Cannon" and collide visually with AC20. |
| `description` | "One round at a time out of a nose mount…" | |
| `kind` | `0` (WEAPON) | occupies the weapon mount. |
| `cost` | `70` | below `machine_gun`'s 150, because the frame it goes on costs 90. Price it properly with `audit_economy.gd`. |
| `ai_scene` | `res://Character/weapon/ai-wep_light_cannon.tscn` | §3.3 |
| `player_scene` | **null** | there is no viewmodel and none is wanted. |
| `usable_by_player` | `false` | |
| `usable_by_ai` | `true` | `fits_ai()` needs this **and** a non-null `ai_scene` (`item_definition.gd:145-150`). |
| `fits_vehicles` | `true` | mandatory: `takes()` refuses anything `fits_vehicles = false` on a `drives` frame. |
| `weapon_damage` | `0` | leaves the scene's value (`item_definition.gd:64-65`). Author ballistics in the scene, once. |
| `ammo_type` | `&"light_cannon"` or reuse `&"20mm"` | a new pool is a decision about the ammo economy; `tools/test_ammo.gd` exists and will have an opinion. **Open — see §8.** |
| `in_shop` | `true` | |
| `one_per_robot` | `false` | |
| `requires_chassis` | `Array[StringName]([&"lance"])` | **use this, not the whitelist, for shop gating.** `item_definition.gd:122-133`: hides the gun from the armoury until the player owns a Lance, which is exactly why `autocannon` and `heavy_mg` carry `requires_chassis = [&"walker"]`. |
| `chassis_whitelist` | `Array[StringName]([&"lance"])` | **see 3.4 — this is the live decision.** |
| everything else | defaults | `required_rank = 0`, all module bonuses 0. |

### 3.3 The `AIWeapon` scene

New file: **`Character/weapon/ai-wep_light_cannon.tscn`**, root `Node3D` with
`res://Character/weapon/ai_weapon.gd`, `node_paths` for
`muzzle_flash` / `muzzle_origin` / `shot_audio`, and a `Model` /
`Muzzle` / `MuzzleFlash` / `Shot` quartet copied from the autocannon.

| export | value | why |
|---|---|---|
| `weapon_type` | `1` (HITSCAN) | `Enums.AIWeaponTypes { MELEE, HITSCAN, PROJECTILE }` (`Managers/enums.gd:14`). **Append-only enum.** MELEE (0) would send it down `check_melee_damage` and it would never shoot. |
| `fire_cooldown` | `1.6` | design doc. |
| `base_damage` | `48` | design doc. |
| `min_damage` | **`30`** | **the design doc omits it and the default is 18** (`ai_weapon.gd:16`). `calculate_damage` lerps `base_damage → min_damage` across `damage_falloff_start … max_effective_range` (`ai_weapon.gd:246-252`), so left at 18 the gun loses 62 % of its damage over its own range band and the "hits hard for the supply" promise evaporates at 60 m. |
| `damage_falloff_start` | **`45.0`** | **also omitted; the default is 20.0.** At 20 m a scout's gun starts falling off almost immediately. |
| `max_effective_range` | `85.0` | design doc. This is also what the **whole AI** reads as "my reach" (`Enemy._max_range`, `enemy.gd:3022`), so it sets ADVANCE/FIRE scoring and the fallback distances, not just the damage cap. |
| `min_effective_range` | `0.0` | a scout must be able to shoot something that is on top of it (`enemy.gd:2920-2921` refuses closer than this). |
| `ai_spread_mrad` | `7.0` | design doc. Divided by `accuracy_skill * signal_integrity` and multiplied by the aim-settle factor (`enemy.gd:5231-5234`), so the number on the card is a floor, not a result. |
| `pellets` | `1` | single round. |
| `suppression_per_shot` | `5.0` | design doc, and the frame's real contribution: `suppress_along` measures along the round's whole flight path (`ai_weapon.gd:480-500`), so a near miss down a lane pins everything beside it. |
| `near_miss_radius` | `3.0` | the autocannon's 3.5 is a bigger gun; `3.0` keeps the suppression honest. |
| `burst_min` / `burst_max` | `1` / `1` | **set these, do not leave 0.** 0 defers to the robot's own `burst_min = 2` / `burst_max = 5` (`lance.tscn:230-231`, and `_commit_burst`, `enemy.gd:3959-3971`) — which on a 1.6 s single-shot gun means the frame commits to a five-round burst lasting eight seconds. "Single-shot" has to be stated on the weapon. |
| `magazine_size` | `6` | design doc. |
| `reload_time` | `3.5` | design doc. |
| `friendly_fire` / `friendly_fire_multiplier` | defaults (`true` / `0.34`) | |
| `tracer_scene` | `res://Character/weapon/tracer.tscn` | |
| `tracer_jitter_degrees` | `0.4` | the autocannon's, not the MG's 1.2 — one visible round. |

**Model.** `Character/weapon/models/` has no light cannon.
`autocannon_model.tscn` will instance and look passable but is wrong twice over:
it is the Walker's gun, and `icon_art.gd:94-107` records that two guns sharing
one model produce two icons that cannot be told apart, which is "worse than no
icon, because it reads as information." Two routes, pick one and say which:

- **Ship on `autocannon_model.tscn` as an explicit placeholder** and add a
  `DRAWINGS` entry for `&"light_cannon"` in `icon_art.gd:78-110` so the *icon*
  is distinct even while the world model is not. Cheapest, and the precedent is
  literally `&"autocannon"` and `&"heavy_mg"`, which both do this.
- **Hand-build `light_cannon_model.tscn`** the way `autocannon_model.tscn` was
  (primitives, commented header, no imported mesh) and add a `MODEL_OVERRIDES`
  entry (`icon_art.gd:24-31`) — *required*, because `model_in()` only follows
  imported `blend/glb/gltf/fbx/dae` (`icon_art.gd:75, 172-177`), so a
  hand-built `.tscn` is invisible to `model_for()` without the override.

### 3.4 `fits_chassis` / whitelist — the question the Bulwark got wrong

`takes()` has three refusals (`chassis_definition.gd:84-91`):
`item.fits_chassis(id)`, `drives and not item.fits_vehicles`, and the turret
rule. **The Lance is `turret = false`, so the third never fires** — which means
the Bulwark's failure mode (`FRAME_ANATOMY.md` §6.2: armable once, un-refittable
forever) cannot happen here. Good.

What *can* happen is the inverse, and it is the live decision:

- **`chassis_whitelist = [&"lance"]`** — the gun fits only the Lance. Clean,
  self-documenting, and it stops a `light_cannon` turning up on a future
  non-turret vehicle by accident. **Recommended.**
- **`chassis_whitelist = []`** — the gun fits anything that is not a turret
  frame. Today that is the Lance and nothing else, because every other vehicle
  frame in the catalogue (`rover`, `walker`, `reclaimer`) is `turret = true`
  and would refuse a gun that does not name it. So the empty list is currently
  equivalent, and becomes a liability the moment a second `turret = false`
  vehicle exists.

**And the thing the design doc gets wrong:** `LANCE.md` §4 says that because
`turret = false`, "the Lance can take any vehicle-legal weapon… a Lance with a
machine gun is a legitimate and different thing." It cannot.
`item_machine_gun.tres` ends `chassis_whitelist = Array[StringName]([&"rover",
&"walker"])`, so `fits_chassis(&"lance")` returns false at
`item_definition.gd:138-139` and `takes()` refuses it at line 87 — before the
turret rule is ever consulted. The same is true of `heavy_mg`, `autocannon`,
`grenade_launcher` and `mortar`. **So the Lance ships with exactly one fittable
gun unless someone edits an existing item's whitelist.**

That is a balance decision and it is the human's, not the builder's. The
cheapest version is one line: add `&"lance"` to `item_machine_gun.tres`'s
whitelist, which gives the frame the "MG instead of a cannon" identity the
design doc already promises and costs nothing else. **Flagged in §8; do not do
it without a yes.**

---

## 4. The behaviour

### 4.1 Does it need its own script? **Yes — and only just.**

`FRAME_ANATOMY.md` §4.3: a frame on `rover.gd` already has Ackermann steering,
reverse, whisker blocking, pack spacing, suspension, turret traverse, wreck
pose, `takes_cover() = false`, `enter_cover_seeking` stubbed, `slot_tolerance`
and `formation_width` widened for a hull, and `_handle_path_blocked` reversing
out instead of sidestepping. The Lance needs **none** of that written.

What it needs is one function, because of a defect that is already measured and
recorded in `tools/build_lance.gd`'s header:

```
rover.gd:597-600
func _update_facing(delta: float) -> void:
    if turret == null:
        super(delta)   # warned about in _ready
        return
    ...                 # turret branch: NEVER calls super()
```

`lance.tscn:182` wires `turret = NodePath("Rig/Turret")` — a deliberate stub
with `turret_traverse_degrees = 0.0` (`lance.tscn:176`). The stub is **required**:
`hull_spoils_aim` at `enemy.gd:2895` is excused by *a node property literally
named `turret` being non-null*, not by `ChassisDefinition.turret`, so a null
turret means `_aim_tracking` decays whenever the frame moves and it never leaves
`WeaponState.AIM` (`enemy.gd:2896-2899`, and the long comment at 2880-2894
explaining what that cost the Walker).

But the stub also takes the turret branch, which never calls `super(delta)` —
so `Enemy._update_facing` (`enemy.gd:2779-2788`, the only thing that writes
`rotation.y` from a desired bearing) never runs, and with zero traverse the stub
cannot rotate either. The hull's *only* other source of yaw is
`rover.gd:333`, `rotation.y += _rolled / wheelbase * tan(_steer)`, which is
driven by distance travelled. **Parked, `_rolled` is zero, so a parked Lance
never changes facing at all.** Combined with `fire_cone_degrees = 6.0`
(`lance.tscn:180`) and `_weapon_on_target` comparing `_turret_forward()` —
which for a zero-rotation stub is the hull's forward (`rover.gd:615-619`) — a
stationary Lance can only fire at something inside 6° of its nose, forever.

Compare `walker.gd:206-212`, which takes the turret branch **and** calls
`super(delta)` on the way through, with the comment "the body still turns the
ordinary way." The Rover deliberately does not, because a six-wheeled hull
belongs to the driving. A trike with two driven wheels and a castor can pivot
on the spot, so the Lance is the one frame on `rover.gd` for which the Walker's
answer is the right one.

### 4.2 The file

**`Character/characters/ai/lance.gd`**

```gdscript
extends "res://Character/characters/ai/rover.gd"
```

**By path, not `extends Rover`.** `rover.gd` has never declared a `class_name`
and the reason is recorded at `rover.gd:468-470` — "adding a global class an
open editor has not indexed yet is how you take the whole front end down."
`reclaimer.gd:1` is the shipped precedent for the path form. Do **not** add a
`class_name` to `rover.gd`.

Then edit `lance.tscn:150` so `ExtResource("1_ob030")` points at `lance.gd`
instead of `rover.gd` (and `lance.tscn:3`'s `ext_resource` path with it). That
is a two-line hand edit to the scene. **Do not re-run `build_lance.gd`.** Do
update the comment at `build_lance.gd:35-36` (`BODY_SCRIPT`) so a future reader
is not told the frame is on `rover.gd`.

### 4.3 Overrides, one line each

| function | base | why |
|---|---|---|
| `_update_facing(delta)` | `rover.gd:597` | the whole reason the script exists. Call `super(delta)` first so the stub turret and the gun elevation keep working, then — **only when `movement_state == MovementState.NONE`** — slew `rotation.y` toward `_desired_facing()` at a new, slow export. Gating on NONE is what keeps it from fighting `rover.gd:333`'s bicycle yaw while driving. |
| nothing else | | |

That is the entire script: one override, one `@export`, and a header comment
explaining the two paragraphs above so nobody "simplifies" it later.

Sketch, for shape only — the builder owns the final form:

```gdscript
## Degrees per second the hull turns ON THE SPOT. Far slower than
## rotation_speed (7.0, lance.tscn:210): turning the hull IS this frame's
## aiming, so it has to be slow enough that flanking still beats it — the
## Rover's counter, kept, on a frame with no turret to flank.
@export var hull_slew_degrees: float = 90.0

func _update_facing(delta: float) -> void:
    super(delta)                       # stub turret (no-op) + gun elevation
    if movement_state != MovementState.NONE:
        return                         # driving: rover.gd:333 owns the yaw
    var face := _desired_facing()      # enemy.gd:2794 — target, else look, else last move
    if face == Vector3.ZERO:
        return
    rotation.y = rotate_toward(rotation.y, atan2(-face.x, -face.z),
        deg_to_rad(hull_slew_degrees) * delta)
```

**`hull_slew_degrees` is the frame's balance dial and the human's number.** 90
is the Rover's traverse-ish feel (`rover.gd:130`, `turret_traverse_degrees =
95.0`) and makes the Lance roughly as quick to come round as a Rover's turret,
which arguably removes the counter. Something in the 45–60 range keeps "get
alongside it and you win" true. It cannot be judged from a headless run — see
§7 step 6.

**Nothing in `Enemy`, `Soldier` or `rover.gd` is edited.** `LANCE.md` §6 is
right about that and the Picket's reverted roster-wide elevation gate is the
precedent.

One consequence of a subclass worth knowing and not fixing: `rover.gd:472` and
`rover.gd:561` (`_crowded`) filter pack-spacing and crowding on
`other.get_script() != get_script()`, so Lances will keep spacing from Lances
and stop spacing from Rovers. For a frame whose `spacing_radius` is 9.0
(`lance.tscn:165`) that is arguably correct — a Lance has no business holding a
Rover's lane — but it is a behaviour change caused by the subclass, not by any
line in it.

### 4.4 `AllowedMovementOptions` and `AllowedCombatOptions` — values

**`lance.tscn:266-267` currently reads `AllowedMovementOptions = []` and
`AllowedCombatOptions = []`.** `FRAME_ANATOMY.md` §6.1 is the full account; the
short version is that `roll_combat_action` returns at `enemy.gd:3053-3054` when
the combat array is empty, so `perform_action` is never reached from the combat
timer, `_commit_burst` (3959) never runs, `_enter_aim_stance` (3953) never runs,
and the frame moves only when its squad orders it to. On the Lance there is a
second bite: `rover.gd:528-534` duplicates `AllowedCombatOptions`, erases MOVE
and picks from what is left when a path dead-ends — with an empty array that
branch does nothing and a blocked Lance just stops.

Set, in `lance.tscn`, by hand:

```
AllowedMovementOptions = Array[int]([0, 2, 4])
AllowedCombatOptions = Array[int]([0, 1, 2])
```

**These are `vehicle_rover.tscn:165-166` verbatim**, which with
`soldier_rifle.tscn:70-71` are the only two correct sets in the game. The
reasoning transfers exactly, because the Lance is on the same driving model:

- `MovementOptions` is `{ADVANCE=0, REPOSITION=1, FALLBACK=2, LEAP=3, CHASE=4}`
  (`enemy.gd:1091`). **ADVANCE (0)** closes range, which is what a harasser
  does. **FALLBACK (2)** is a `fallback_distance = 1.25` step
  (`lance.tscn:221`) and is how a 110-hull frame breaks contact. **CHASE (4)**
  sets `MovementState.CHASING`, which `rover.gd:516` (`_goal`) already
  understands.
- **REPOSITION (1) is excluded** and the reason is written down:
  `find_reposition_target` is a `reposition_distance = 2.0` sidestep, and
  `rover.gd:523-527` says of a blocked path that for "a car that cannot step
  sideways, and that counts anywhere within `arrival_radius` as there, a detour
  it 'arrives' at before it has moved." Same objection, same frame.
- **LEAP (3) is excluded** — it is `leap_towards`, for the Chaser and the
  Leaper. A wheeled frame has no leap.
- `CombatOptions` is `{MOVE=0, AIM=1, FIRE=2}` (`enemy.gd:1092`). All three,
  because the Lance is a conventional shooter: `AIM` is what stops it
  (`_enter_aim_stance`, 3953) and on a frame whose aim is spoiled by motion
  unless the stub turret excuses it, stopping is the behaviour the design
  wants; `FIRE` commits the burst; `MOVE` defers to `_pick_movement_option`.

**The typed-array form matters.** `Array[int]([0, 2, 4])`, not `[0, 2, 4]` and
not `Array[ExtResource(...)]([])`. `FRAME_ANATOMY.md` §6.6: a typed array handed
an untyped one packs as `[]` in silence.

---

## 5. Registration — `FRAME_ANATOMY.md` §1, walked

**S** = fails silently. **H** = hard error.

| # | item | Lance needs | status |
|---|---|---|---|
| 1 | `Campaign/chassis/chassis_lance.tres` | **yes** — §2 | mandatory; without it nothing can reference the frame at all |
| 2 | root script resolves to `Soldier` or a subclass | **already true**, and stays true: `lance.gd` → `rover.gd` → `Soldier`. `_CsgBake.make(frame.scene) as Soldier` (`enemy_force_spawner.gd:265`) | **H** at spawn if broken |
| 3 | `groups=["enemies"]` persistent | **already true** — `lance.tscn:146` | **S** |
| 4 | `KillKinds.FRAMES` key | **yes** — `&"lance": "res://Campaign/chassis/chassis_lance.tres"`, appended to `kill_kinds.gd:14-37` | **S**: `frame_of()` returns null (`kill_kinds.gd:73-77`), the debrief prints a raw id with no icon (`debrief_screen.gd:685-692`), the roster glyph is blank (`hud_glyphs.gd:64-67`), and `bake_icons.gd:120-129` never bakes an icon |
| 5 | non-empty `Allowed*Options` | **yes** — §4.4. Currently `[]` | **S**, and the biggest live defect |
| 6 | `test_item_catalogue.tres` — `chassis` array **and** an `[ext_resource]` | **yes.** Append a `[ext_resource type="Resource" path=".../chassis_lance.tres" id="39_lance"]` and add it to the `chassis = Array[...]` on line 48 | **S**: `buildable_frames()` walks `catalogue.chassis` only (`squad_manager_ui.gd:440-453`), so the frame is simply never offered; `recompute_stats` then warns and falls back to class defaults (`soldier_record.gd:229-236`) and `supply_of` returns 1 (`campaign_state.gd:315-317`) |
| 6b | `test_item_catalogue.tres` — **`items` array**, for `light_cannon` | **yes, and `FRAME_ANATOMY.md` §1.3 does not list it.** `_fit_loadout` resolves the gun with `cat.item(id_value)` and `continue`s on null (`squad_spawner.gd:304-306`), so a Lance recruited with `starting_weapon_id = &"light_cannon"` and no catalogue item **deploys unarmed, silently** | **S** — see §8 |
| 7 | `purchasable = true` | **yes** — §2 | `recruit()` refuses outright (`campaign_state.gd:740-741`) |
| 8 | `icons/chassis/lance_{s,m,l}.png` | **yes**, via `tools/bake_icons.gd` once 4 and 6 are in. Plus `icons/items/light_cannon_{s,m,l}.png` from the same run once 6b is in | **S**: `Icons.chassis` returns null (`icons.gd:45`) and the card shows the name alone. **The Bulwark shipped without these and still has none** — `icons/chassis/` contains no `bulwark_*.png`, verified by listing. Do not repeat it; say in your report whether the PNGs landed |
| 9 | a mission `EnemySquadSpec.roster` entry | **no.** Player frame. Optional later if a hostile Lance is wanted | — |
| 10 | `Enums.Factions` / `are_hostile` | **no.** Nothing new | — |
| 11 | `KillKinds.SCENES` | **no.** Basename `lance` matches id `lance`, so `kind_of` resolves for free via `SCENES.get(base, StringName(base))` (`kill_kinds.gd:70`). Same reason the Bulwark has no entry | — |
| 12 | `EnemyLoadouts.TABLES` | **no**, and preferably not. `roll_for` returns `{}` for an unlisted frame (`enemy_loadouts.gd:208-210`). Adding a key commits you to `test_enemy_loadouts.gd:91-124` asserting every entry resolves and is **legal** — and with one fittable gun there is no pool to roll | — |
| 13 | `Campaign/cosmetics.gd` | **no.** `for_frame` returns `[NONE]` and the cycle control still works (`cosmetics.gd:84-90`). The Bulwark, Spotter, Diver and Nest have none | — |
| 14 | a mission `unlocks` entry | **no** — deliberately. The Lance is meant to be on sale from the first visit, which is what a frame named by no mission already is (`campaign.gd:1068-1082`). **But see §8**: `audit_economy.gd:167` prints a line about exactly this, and it will now print it for the Lance too. The `light_cannon` is gated instead by `requires_chassis = [&"lance"]` (§3.2) |
| 15 | `Campaign/lab/plans/*.tres` | **recommended.** `bulwark_screen.tres` is the format: a `LabPlan` with `LabMatchup` sub-resources, a `question` written as *what to watch*, and a **control**. §7 step 6 says what to put in it |
| 16 | `tools/test_<frame>.gd` | **yes** — §6 | free to wire: `tools/test.sh` runs every `tools/test_*.gd` |
| 17 | `probe_nav_reach.gd` `FRAMES` | **optional, cheap, do it.** Append `"lance": [0.52, 1.75, 0.75]` to `tools/probe_nav_reach.gd:87-95` — radius from `CAPSULE_RADIUS = 0.52` (`build_lance.gd`), climb copied from `"rover"`'s 0.75. **Measure the height with `probe_chassis_size.gd` rather than trusting 1.75**, which is the design doc's figure for the frame *with* a cast barrel it no longer has |
| 18 | a new `ItemDefinition` + `AIWeapon` scene | **yes** — §3 |

Not needed at all (`FRAME_ANATOMY.md` §1.6): CSG baking reads the directory
(`csg_bake.gd:177-189`); the `"signal"` group is joined in `AI._ready`
(`ai.gd:86-88`); team assignment is `vehicle = true` and nothing else
(`campaign_state.gd:468-496`); `AIManager` registration belongs to whoever
spawns the body.

---

## 6. Tests — `tools/test_lance_frame.gd`

**The filename is `test_lance_frame.gd`, NOT `test_lance.gd`.**
`tools/test_lance.gd` already exists and is the melee **repair lance weapon**
suite (read its header: "THE LANCE HAS TO CONNECT"). Overwriting it would
delete a shipped suite and `tools/test.sh` would still print PASS.

Model it on `tools/test_bulwark.gd` — its `_test_the_chassis_is_registered`
(70-90) is §5 as a test and is the cheapest thing to copy, along with `_ok`
(52-57) and `_spawn` (60-66).

Assertions, grouped:

**Registration**
- `chassis_lance.tres` loads; `id == &"lance"`; `scene != null`.
- `weapon_slots == 1`; `coax_weapon_id == &""`.
- `turret == false` — **the frame's identity as a data assertion.** If this
  flips, every weapon in the game needs to name the Lance or the frame becomes
  un-refittable.
- `drives == true` and `vehicle == true`.
- `base_speed == 1.0` **and** the scene's `move_speed > 9.0` — paired, so the
  double-multiplication of §2 cannot come back. Assert the *product*:
  `frame.base_speed * scene_move_speed` is between 9 and 10.
- `test_item_catalogue.tres`'s `chassis` ids contain `"lance"`, and its `items`
  ids contain `"light_cannon"`. Hard-code the path the way
  `test_bulwark.gd:86` does.
- `KillKinds.FRAMES.has(&"lance")` and `KillKinds.frame_of(&"lance") != null`.

**The frame**
- in `"enemies"` **and** in `AI.SIGNAL_GROUP` (`test_bulwark.gd:120-127`).
- every node-path export resolves non-null: `rig`, `turret`, `gun_pivot`,
  `nav_agent`, `weapon_mount`, `bark`, `detection`.
- all four typed arrays are **populated**, not merely present: `wheels` (3),
  `wheel_steer` (3), `visible_pieces`, `particle_effects_die`,
  `particle_effects_hit`, and `FactionLivery.pieces`
  (`test_bulwark.gd:185-210` is the comment to copy with it).
- `wheels.size() == wheel_steer.size()` — `rover.gd:195-196` warns otherwise
  and the castor silently stops steering.
- `Eye` keeps its own `StandardMaterial3D` and is **not** in
  `FactionLivery.pieces`.
- `AllowedCombatOptions == [0, 1, 2]` and `AllowedMovementOptions == [0, 2, 4]`,
  **and** both are `Array[int]` — `arr.get_typed_builtin() == TYPE_INT`. Empty
  is the failure mode and empty looks like nothing.
- `turret_traverse_degrees == 0.0` — the stub must stay a stub.
- `turret != null` — **with the comment explaining why**, because the obvious
  "simplification" for a turretless frame is to clear it, and that silently
  re-arms `hull_spoils_aim` (`enemy.gd:2895`).
- `WeaponMount.rotation.y ≈ +PI/2` (`tools/check_frame.gd` asserts this too;
  duplicating it here is cheap and the Bulwark fired backwards for want of it).

**The weapon**
- `item_light_cannon.tres` loads; `kind == 0`; `fits_ai()` is true;
  `fits_vehicles == true`; `ai_scene != null`.
- `frame.takes(light_cannon) == true`.
- `frame.takes(nanite_reboot) == false` — the `drives` refusal, named
  specifically because it is the design's load-bearing exclusion.
- `frame.takes(m4) == false` — `fits_vehicles = false`.
- `rover_frame.takes(light_cannon) == false` — the Rover is `turret = true` and
  `light_cannon`'s whitelist does not name it, so the gun cannot leak onto the
  frame the Lance exists to be cheaper than.
- a fitted weapon points where the frame faces: instantiate, `equip_weapon_scene`,
  one `process_frame`, then `-weapon.global_transform.basis.z` dotted with
  `-body.global_transform.basis.z` **> 0.9**.
- `weapon.burst_min == 1` — proves the single-shot rhythm is on the weapon and
  not left to the body's 2–5 (`enemy.gd:3963-3966`).
- `calculate_damage(85.0) >= 30` — pins `min_damage`, the field the design doc
  forgot.

**The aim question, settled by measurement — the point of the suite**
`LANCE.md` §7 asks for this and it is the assertion the frame lives or dies by.
Two bodies, one stationary and one given a velocity, both with a weapon fitted
and a target set:
- a **stationary** Lance accumulates `_aim_tracking` and reaches
  `WeaponState.FIRE`.
- a **moving** Lance **also** accumulates `_aim_tracking` — because the stub
  turret excuses `hull_spoils_aim` — and that is asserted **explicitly**, so the
  behaviour is a decision and not an accident. If someone later clears
  `turret`, this test is what tells them what they broke.
- with `lance.gd` fitted: a stationary Lance whose target is 90° off its nose
  **changes `rotation.y`** over ~2 s of ticked `_update_facing`, and ends with
  `_weapon_on_target()` true. Without `lance.gd` this assertion fails, which is
  the proof §4 is needed rather than an argument for it.

Deliberately **not** asserted: geometry. `test_bulwark.gd:22-23` —
"shapes are judged by looking at them, and a test that pins box sizes only
makes the model harder to tune." Measurement belongs in
`tools/check_frame.gd`, which prints W/H/L.

---

## 7. Order of work, and what to prove at each step

Each step ends with `bash tools/check.sh --changed` printing **PASS**. Do not
run Godot while `tools/test.sh` is in flight (`FRAME_ANATOMY.md` §7).

**1 — The weapon, first.** `ai-wep_light_cannon.tscn`, then
`item_light_cannon.tres`, then the `items` array and `[ext_resource]` in
`test_item_catalogue.tres`.
*Prove:* `check.sh --changed` PASS, and a one-off probe that
`load(".../test_item_catalogue.tres").item(&"light_cannon")` is non-null and
`fits_ai()` is true. Doing the weapon first means the chassis never exists in a
state where it issues a gun that cannot be resolved.

**2 — The chassis.** `chassis_lance.tres`, then `KillKinds.FRAMES`, then the
`chassis` array and `[ext_resource]` in `test_item_catalogue.tres`.
*Prove:* `bash tools/test.sh` — `test_ledger.gd` exercises recruit, refit and
the save round-trip, and will now do it for the Lance. Watch the
`[Catalogue] N items, M chassis: [...]` line from `item_catalogue.gd:55-56` and
check `lance` is in the key list; a `null` in the array is the silent failure
(`item_catalogue.gd:43-53`, trap 6.8).

**3 — The scene edits, by hand.** In `lance.tscn`: the two `Allowed*Options`
lines (266-267) to `Array[int]([0, 2, 4])` / `Array[int]([0, 1, 2])`.
*Prove:*
```bash
"D:/Godot Games/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe" \
  --headless --audio-driver Dummy --path . \
  --script res://tools/check_frame.gd -- res://Character/characters/ai/lance.tscn
```
It checks groups, the three typed arrays, livery pieces, eye exclusion, mount
yaw, bare meshes, and prints the measured W/H/L and the capsule. **Note what it
does not check: the `Allowed*Options` arrays.** Read them back from the saved
scene yourself, by loading it and printing `get("AllowedCombatOptions")` and its
`get_typed_builtin()`, or the typed-array trap (6.6) will eat the edit silently.

**4 — `lance.gd`, and repointing the scene's script.**
*Prove:* the three-part aim assertion in §6 — stationary reaches FIRE, moving
still settles, and a parked Lance with a target 90° off its nose comes round.
That last one is the whole justification for the file; if it passes without
`lance.gd`, delete the file and say so.

**5 — `tools/test_lance_frame.gd`, then icons.**
*Prove:* `bash tools/test.sh` all green, then run `tools/bake_icons.gd` and
**list `icons/chassis/` and `icons/items/`** to confirm
`lance_{s,m,l}.png` and `light_cannon_{s,m,l}.png` actually landed. Nothing in
the project asserts this (`FRAME_ANATOMY.md` §8.3), which is why the Bulwark
still has none. Say in your report whether they did.

**6 — The lab plan, and then hand it to the human.** A `LabPlan` in
`Campaign/lab/plans/lance_scout.tres` on `bulwark_screen.tres`'s pattern, with
a **control**, because the control answers the only question that matters: *is a
Lance a different thing from a Rover, or a worse one?*
Suggested matchups: 4 Lances vs 4 riflemen at 60 m; 2 Rovers vs the same
4 riflemen as the control (same supply either way — 4 against 4); and 4 Lances
vs 4 riflemen at 20 m, where the no-turret constraint should visibly hurt.
`question` should ask the reader to watch three things:
- does the hull come round at all when a parked Lance is engaged from the side,
  and does `hull_slew_degrees` make that read as *deliberate* or as a turret?
- does a 9.45 m/s frame stay in its slot, or does the squad re-order it every
  tick? (`slot_tolerance` returns `maxf(squad_tolerance, arrival_radius=2.0)`,
  `rover.gd:543-552`, and an armour team follows at ≥10 m,
  `squad_spawner.gd:176`.)
- is 48 damage on a 1.6 s cycle "harass" or "nothing"?
*Prove:* nothing. **This is the step a human has to do**, because game feel and
balance are not measurable here (CLAUDE.md). Stop and ask.

---

## 8. Open questions and risks

**Ranked. The first two need an answer before step 1.**

1. **`machine_gun`'s whitelist — the frame's second gun.** As the data stands
   the Lance has exactly one fittable weapon (§3.4), and `LANCE.md` §4's claim
   to the contrary is wrong. One line in `item_machine_gun.tres` fixes it and
   it is a balance decision, not a build one. **Ask.** Without it the frame is
   buildable but has no loadout choice, which for a frame whose pitch is "wheels
   as a real choice" is a thin offer.
2. **`hull_slew_degrees`.** The number that decides whether the Lance is a
   turretless frame or a frame with a slow turret. Unjudgeable headless.
   45–60 °/s is my guess; the human's call (§7 step 6).
3. **`base_speed` double-count.** Resolved in this brief (§2: 1.0 on the
   definition, speed on the scene) but it is the kind of thing that gets
   "corrected" back to 1.35 by someone reading the design doc. The paired
   assertion in §6 is the guard. Flag it in the commit message.
4. **9.45 m/s against the squad leash.** `LANCE.md` §8 raises it and it is real:
   an armour-only team follows at ≥ 10 m plus 5 m per team rank
   (`squad_spawner.gd:75-80, 176`), re-ordered whenever the gap exceeds
   `slot_tolerance` (`squad.gd:728, 841`), and the Rover's override floors that
   at `arrival_radius = 2.0`. A frame moving 35 % faster than anything it
   formates with may spend the mission being recalled. Measurable in the lab
   (step 6), not here.
5. **`min_damage` and `damage_falloff_start`.** Omitted by the design doc, and
   the defaults (18 / 20.0 m) are actively wrong for an 85 m gun. Values
   proposed in §3.3; they are guesses and the lab plan should look at them.
6. **The weapon model.** Shipping on `autocannon_model.tscn` means the Lance's
   gun looks like the Walker's. `icon_art.gd:94-107` already calls the
   indistinguishable-icon version of this "worse than no icon". Pick a route in
   §3.3 and say which.
7. **`ammo_type`.** A new `&"light_cannon"` pool versus reusing `&"20mm"`.
   `tools/test_ammo.gd` exists; I did not read it, so I cannot say what a new
   pool costs. **I could not confirm this one.**
8. **`audit_economy.gd:167` will now flag the Lance** as "a chassis no mission
   names is on sale from the first visit to base." For this frame that is the
   intent, not a defect — but someone will read the line as a bug. Worth a word
   in the commit, or an exemption in the audit if the human prefers.
9. **A correction to `FRAME_ANATOMY.md`, which I want on the record.** §1.3's
   buyable checklist lists the chassis entry in `test_item_catalogue.tres` but
   **not the item entry for the frame's gun**. `_fit_loadout` resolves the
   weapon through `cat.item(id)` and `continue`s on null
   (`squad_spawner.gd:304-306`), so a frame whose `starting_weapon_id` names an
   item that is not in the catalogue **deploys unarmed and nothing warns**. That
   is a textbook silent failure and belongs in §1.3 as item 6b. (§1.5 item 18
   and §3 cover *making* the weapon; neither says to register it.) Everything
   else in `FRAME_ANATOMY.md` that this brief leaned on checked out line for
   line — `rover.gd:597-600`, `enemy.gd:2895`, `enemy.gd:3053`, the `takes()`
   refusals, trap 6.2, trap 6.4, trap 6.9 and the `[]` arrays were all verified
   against source.
10. **One smaller correction.** §6.10 says a novel `built_in` word with no art
    is a silent blank. True — and worth knowing that `"CLAWS"`, the field's
    **default** and the value on the Rover, Walker and Bulwark, is already that
    blank: `icons/items/` has no `claws_*.png` and `icon_art.gd:129-135` has no
    `claws` key. The Lance inherits an existing hole; it does not dig one.

**Is the frame worth building?** Yes, with caveat 1 answered. The supply-1 gap
is real and nothing else fills it, the no-turret constraint is a genuinely new
behaviour rather than a stat line, and the total cost is one 20-line script,
two `.tres` files, one weapon scene, five registration edits and a test. If the
answer to 1 is "no second gun", say so in the brief's revision and consider
whether a frame with one fixed loadout is a *choice* the player makes or just a
cheaper thing on the list.
