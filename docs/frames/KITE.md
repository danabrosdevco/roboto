# KITE — design document

Supply 2 · **aerial** · armed · **status: concept selected, not built**

---

## 1. Concept

**Selected: D — SKYHOOK.** 2.20 W x 1.92 H x 2.35 L.

A coaxial rotor pair with the lower disc turned 60 degrees so the blades
interleave, a small body, and the entire weapon in a pod slung on a thin pylon
and canted 24 degrees down.

**The silhouette is a diagram of the job**: crossed rotors say flying with no
ambiguity, and a gun pod hanging below a tiny body says the frame exists to
carry that gun somewhere high. It is also structurally unlike both existing
aerials — the Spotter is a 0.8 m four-rotor core and the enemy bomber is a
four-arm X at 2x scale, and none of these four is a four-arm X.

The other three: **A GUNSHIP** (main rotor, tail boom, chin turret) is the most
immediate read and the most conventional; at 4.18 m long it is also the biggest,
and the rotor disc dominates everything else. **B DUCT**, a single 2.5 m
shrouded fan with the body slung beneath, is identifiable at the longest range
of the four but reads as a saucer. **C JUMP JET** adds speed to the angle
proposition but, with no rotor, a still frame has to work hard to say "flying"
at all.

**Risk carried forward:** a pod slung under an aircraft is what the enemy
bomber's ordnance looks like. The pod is given a ring, an eye and a muzzle
brake so it reads as a weapon rather than a bomb.

Art brief: must read as **flying** and **armed**, both at a glance, and must
not be mistaken for the Spotter (small unarmed camera drone) or the enemy
quadcopter bomber. Drawn airborne — body at y 1.5–2.5, no legs.

## 2. What it is for

Every flying thing the player owns is a camera. The Spotter has
`weapon_slots = 0` and its script stubs out the entire weapon loop.

The Kite is the first armed aerial on the player's side, and its proposition is
**attack angle**: it engages from a position ground frames have to walk to.
It is made of paper — 90 hull — so it is a frame you commit and then protect,
not one you leave parked.

**Honest caveat, discovered in research and not papered over:** the original
justification was "ground units cannot shoot up". That is false —
`gun_max_pitch_degrees` is cosmetic, the fire gate discards elevation
(`walker.gd:243`), the damage ray is unmasked 3D, and infantry have no pitch at
all. So the Kite's angle advantage is currently *soft*: it comes from being
small, distant and fast against range-proportional spread, not from immunity.
It is still a real advantage — it is why the existing flyers survive — but it
is an emergent one, and the Kite inherits it rather than being granted it.

## 3. Stats

| field | value | why |
|---|---|---|
| `id` | `&"kite"` | permanent once a kill is saved |
| `supply` | 2 | |
| `cost` | 240 | above the Spotter's 180; it shoots |
| `base_health` | 90 | above Spotter's 80, far under Rover's 180 |
| `base_speed` | 1.2 | |
| `base_sensor_range` | 70 | below the Spotter's 90 — it is not the scout |
| `weapon_slots` | 1 | |
| `starting_weapon_id` | `&"machine_gun"` | existing, vehicle-legal |
| `turret` | true | **and it needs the node, not just the flag** — §6 |
| `vehicle` | true | |
| `drives` | false | |
| `equipment_slots` | 0 | |
| `module_slots` | 2 | |
| `required_rank` | 3 | |

## 4. New weapons

**None required.** `machine_gun` and `heavy_mg` are both vehicle-legal and
both work on a turret mount. A dedicated light aerial gun is a later nicety,
not a dependency.

## 5. Model

New scene `Character/characters/ai/kite.tscn` from `tools/build_kite.gd`.
Script `kite.gd` — base class is the central decision, §6.

```
Kite (CharacterBody3D, groups=["enemies"])   ← add_to_group("enemies", TRUE)
├─ CollisionShape3D   sphere ~0.7   (Spotter is 0.5, bomber 0.6)
├─ Bark / NavigationAgent3D / Detection
├─ GroundRay (RayCast3D, built in _ready, target (0,-300,0), mask 1)
├─ Rig
│  ├─ Hull (CSGMesh3D)
│  ├─ Rotors ×N
│  ├─ Turret (Node3D)   ← MUST exist and be exported as `turret`
│  │  ├─ Head: ONE eye, own StandardMaterial3D, NOT in livery
│  │  └─ GunPivot → WeaponMount   ← yaw +PI/2
├─ SparkBurst / OilSpray
└─ FactionLivery  (TYPED Array[Node3D], eye excluded)
```

A larger collider than the existing flyers on purpose: at 0.5 m the Spotter is
hard to hit by accident, and a frame that is *meant* to be shot down should be
hittable on purpose.

Plus the five silent traps: typed exports, persistent group, typed arrays,
`WeaponMount` yaw **+90°**, and the `turret` node — see §6, where it is not a
trap but the whole problem.

## 6. Code requirements — the most expensive frame on the list

Four things, all verified in research:

**1. The weapon loop is stubbed on every existing flyer.**
`spotter_drone.gd` and `enemy_helicopter.gd` both make `handle_weapon_logic`,
`roll_combat_action` and `_update_facing` no-ops. An armed aerial has to put
them back. This is the bulk of the work and there is no precedent to copy —
the bomber "aims" only by release timing.

**2. `_aim_tracking` can never settle on something that always moves.**
`enemy.gd:2895`:
```gdscript
var hull_spoils_aim: bool = _is_moving() and not ("turret" in self and get("turret") != null)
```
`_is_moving()` is `> 0.6` horizontal; a flyer cruises at 18–27. The escape is a
node property **literally named `turret`** being non-null. A Kite without one
never leaves `WeaponState.AIM` and never fires a shot — silently.

**3. The squad leash fights flyers.** `Squad._enforce_leash` measures 3D, does
not consult `slot_tolerance`, and uses 9 m / 12 m. Anything 22 m up is
permanently outside and recalled every frame. The Spotter survives this by
accident; a frame meant to *manoeuvre in combat* will fight it. Likely needs
either a lower cruise height or a `kite.gd` override.

**4. Base class.** The Spotter's flight model is the most reusable — its
`handle_movement` is 34 lines with no phase machine, and it already answers the
squad seams (`slot_tolerance`, `formation_width`, `takes_cover`,
`off_navmesh_is_normal`). The bomber's is a four-phase bombing-run machine and
overrides **none** of those, which means it inherits `takes_cover() → true` and
can be handed a *ground cover point* as a loiter centre. Do not copy the
bomber.

**Nothing in `Enemy` or `Soldier` changes.** Everything above lives in
`kite.gd`.

## 7. Tests

`tools/test_kite.gd`:

- registered, catalogue, supply 2, `weapon_slots = 1`, `turret = true`
- **the `turret` node exists and is non-null** — the single assertion that
  stops this frame shipping unable to fire
- it reaches `WeaponState.FIRE` while moving, which is the proof that (2) is
  actually solved rather than merely understood
- a fitted weapon points where the frame faces
- it flies: given a move order it holds altitude above varying ground
- it can be shot down: a raycast from the ground at its collider hits it, and
  `enter_downed` produces a crash rather than a standing corpse
- in `"enemies"` and `AI.SIGNAL_GROUP`; typed arrays populated; eye survives a
  repaint
- **EMP kills it outright** — `spotter_drone._enter_ekill` calls `die()`. If
  the Kite inherits that, assert it deliberately; if not, assert that too

## 8. Open

- Cruise height. Low enough to stay inside the squad leash, high enough for the
  angle to mean anything. This is a number to find by playing, not by deciding.
- Whether `_enter_ekill → die()` is right for a frame the player paid 240 for.
  An EMP one-shotting a supply-2 frame may be too sharp.
