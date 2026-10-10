# DRAYMAN — design document

Supply 2 · wheeled · logistics · **status: concept selected, not built**

---

## 1. Concept

**Selected: A — THE FLATBED.** 3.23 W x 2.56 H x 3.35 L.

Six wheels under a low bed, a block of strapped crates stacked over the rear
axles, and a boom folded down off the shoulder with a grab at its end.

**Two facts in one outline: it is carrying something, and it can hand it
over.** That is the entire frame, and the crates do the first half at any size
— a stack of boxes survives being drawn at 40 pixels in a way that nothing else
on this sheet does. It is also unmistakably Reclaimer lineage: same wheelbase,
same low bed, same arm folded against the body. That is the point of having a
lineage at all.

**Steal B's belt.** A's boom ends in a generic grab, which says *cargo*; B's
ends in a linked feed belt, which says *ammunition*. The built version should
take that tip. It costs one part and it is the difference between a supply
truck and this specific supply truck.

The other three: **B HOPPER** is the best single idea in the batch — a drum
with a belt paying out of it — but a cylinder on a truck bed reads as a fuel
tanker before it reads as a magazine, and the belt turns to noise at icon size.
**D ARTICULATED** is the sheet's most convincing *truck* and the most honest
shape for a load carrier, but it is a tractor and a trailer: the navmesh has no
notion of a trailer, and an articulated body is a real engineering cost for a
frame whose whole interest is in what it does while parked. **C PACKHORSE** is
legged, which contradicts `drives = true` in section 3 and breaks the Reclaimer
lineage in the same stroke.

Art brief: Reclaimer lineage, and it must read as **carrying a load** — crates,
belts, a hopper, racks — and as having a **reach** to hand it over. The one
thing it must not look like is a gun truck.

## 2. What it is for

Ammunition is a real system here. Items carry an `ammo_type`; `AIWeapon` tracks
`magazine_current` against `magazine_size`; `reconsider_weapon()` tops a robot
up below 35%; `_score_combat_option` reads `low_ammo` and changes what a robot
is willing to do.

**And nothing refills it.** A long mission currently ends when the belt-fed
guns run dry rather than when the squad dies, and the player has no answer
except bringing fewer heavy weapons.

The Drayman turns ammunition from a countdown into a decision: you can field
the squad auto and the heavy MG *if* you bring the thing that feeds them. It is
the second half of a system that shipped with only its first half.

It is also the frame that makes the Reclaimer's lineage a lineage — two support
vehicles that are support in different directions, one medical and one
logistical.

## 3. Stats

| field | value | why |
|---|---|---|
| `id` | `&"drayman"` | permanent once a kill is saved |
| `supply` | 2 | same as the Reclaimer it stands beside |
| `cost` | 170 | above the Reclaimer's 130 |
| `base_health` | 170 | slightly above the Reclaimer's 150 — it is a truck |
| `base_speed` | 0.95 | loaded |
| `base_sensor_range` | 40 | the Reclaimer's. It is not a scout |
| `weapon_slots` | 1 | the boom occupies it |
| `starting_weapon_id` | `&"supply_boom"` | new, section 4 |
| `turret` | false | |
| `weapon_replaces_built_in` | true | |
| `built_in` | `"ARM"` | the Reclaimer's existing mount class, reused |
| `vehicle` | true | |
| `drives` | true | wheeled; refused leg kit, like the Reclaimer |
| `equipment_slots` | 2 | |
| `module_slots` | 2 | |
| `required_rank` | 2 | |

## 4. New weapon — `supply_boom`

An articulated arm that refills a squadmate's magazines. It occupies the weapon
slot and does no damage, exactly as the repair tool and the repair lance
already do — `item_repair_lance.tres` is `kind = 0` and heals.

| field | value |
|---|---|
| kind | 0 (WEAPON) |
| `fits_vehicles` | true |
| `usable_by_player` | false |
| `base_damage` | 0 |
| reach | ~6 m, the Reclaimer's boom length |
| rate | one magazine per ~2.5 s of continuous channel |
| capacity | a finite number of magazines per mission, probably 8 |

**Capacity is what stops it being a non-decision.** An infinite resupply frame
removes the ammunition system rather than completing it; a finite one means the
player is choosing *which* guns get fed.

## 5. Model

New scene from `tools/build_drayman.gd`; script `drayman.gd`, `extends
Reclaimer` if the boom plumbing is reusable, otherwise `Soldier`.

```
Drayman (CharacterBody3D, groups=["enemies"])   <- add_to_group("enemies", TRUE)
+- CollisionShape3D
+- Bark / NavigationAgent3D / Detection
+- Rig
|  +- Hull (CSGMesh3D)
|  +- Head: ONE eye, own StandardMaterial3D, NOT in livery
|  +- Load: crates / belt racks / a hopper  (the readable part)
|  +- BoomBase -> BoomArm -> BoomTip -> WeaponMount
|  +- Wheels
+- SparkBurst / OilSpray
+- FactionLivery  (TYPED Array[Node3D], eye excluded)
```

**The Reclaimer builds its own mount inside `equip_weapon_scene`** — the boom
only exists after the tool is instantiated, which is why
`enemy_force_spawner.gd` deliberately does not guard on `weapon_mount != null`
for it. If the Drayman reuses that pattern it inherits the same contract; if it
pre-builds the boom in the scene it does not. **Decide this before building,
because it changes whether `weapon_mount` is authored or runtime.**

Plus the five silent traps: typed node-path exports, `add_to_group(.., true)`,
typed `Array[Node3D]`, `WeaponMount` yaw **+90 degrees**, and the `turret`-node
rule in `hull_spoils_aim` (not relevant — nothing fires).

## 6. Code requirements

**Nothing in `Enemy` or `Soldier`.** Two pieces:

**1. A resupply channel on the boom.** The Mechanic's welder is the model:
`mechanic.gd` has `_tend`, `_tool_on`, `_start_welding` — behaviour on the
subclass, with the tool itself not being an `AIWeapon` that fires. Copy the
shape, change the effect from `health` to magazines.

**2. The actual refill.** `AIWeapon` owns `magazine_current` and
`magazine_size`. A refill is setting the former toward the latter on the
target's `weapon` (and `coax` if present). Two things to get right:

- **The player is a valid target.** The player's weapons are `PlayerWeapon`
  under an `EquipmentLoadout`, not an `AIWeapon` on a mount — a completely
  different object. Refilling a squadmate and refilling the player are two code
  paths, and the second is the one players will actually care about. If only
  one ships first, ship the player one.
- **Reserve ammo versus magazines.** `AmmoPool` exists on the player
  (`test_character.tscn` has an `ammo` export). Whether the Drayman tops up the
  magazine or the pool behind it is a design decision that changes the feel
  completely: topping the magazine is a combat action, topping the pool is a
  between-fights one. **Recommend the pool** — it keeps the Drayman out of the
  firefight, which suits a truck.

**Known gap:** no AI will ever *request* resupply. There is no "I am low" signal
in `EquipmentContext`, and `_score_combat_option`'s `low_ammo` is local to the
robot scoring it. An AI Drayman will therefore be reactive at best. Same
honest answer as the Sapper: useful under player command, mediocre alone.

## 7. Tests

`tools/test_drayman.gd`:

- registered, catalogue, supply 2, `built_in = "ARM"`, `weapon_slots = 1`
- `supply_boom` exists, `kind = 0`, `base_damage = 0`, and
  **`sustained_dps()` returns 0.0** so the targeting ledger is not lied to
- a squadmate with a part-empty magazine is refilled when in reach; one out of
  reach is not
- **the capacity is finite** — after N refills it stops, asserted, because an
  infinite one deletes the ammunition system
- it refuses to refill a full magazine (no wasted capacity)
- in `"enemies"` and `AI.SIGNAL_GROUP`; typed arrays populated; eye survives a
  repaint
- the frame never enters a firing state

## 8. Open

- Magazine versus pool (section 6). This is the design decision of the frame
  and should be made before any code.
- Whether `extends Reclaimer` actually works, or whether the boom plumbing is
  too entangled with the welder and mortar to share.
- 8 magazines is a guess.
- The boom tip is a feed belt, not a grab (section 1). Cosmetic, but it is the
  one part that distinguishes resupply from generic cargo handling, so it is
  not optional.
