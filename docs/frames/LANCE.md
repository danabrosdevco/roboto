# LANCE — design document

Supply 1 · wheeled · scout / harass · **status: concept selected, not built**

---

## 1. Concept

**Selected: A — TRIKE.** 1.58 W x 1.75 H x 2.80 L.

Two big driven wheels on an exposed cross axle, a small third wheel dragging
behind, the gun lying in the nose, a whip antenna and an eye on a stalk.

**Three contact points is a plan nothing else in the roster has**, and the
exposed axle says cheap before anything else does. The gun sitting in the nose
rather than on a ring is the turretless constraint made visible.

The other three and why not: **B CHARIOT** (one axle, oversized wheels) reads
beautifully but comically, and a supply-1 frame should look poor rather than
funny. **C RECOILLESS** — the barrel IS the chassis — is the most striking of
the four and was the hardest to reject, but it reads as a towed gun, and the
Lance is a scout that harasses, not artillery. **D TECHNICAL** is the safest
and the closest to the Rover, which is the one thing this frame must not be.

The brief for the art: the cheapest vehicle in the game must read as **fast and
disposable**, and must not be mistaken for the Rover (1.7 × 0.75 × 2.4 m,
four wheels, proper turret ring). Fewer wheels, exposed frame, gun bolted to
the nose rather than seated on a ring.

## 2. What it is for

**The 1→2 supply step is the biggest gap on the sheet and nothing lives in
it.** A soldier costs 1 and a Rover costs 2, and there is no cheap vehicle at
all — so the first time a player wants wheels they pay a third of a squad for
them.

The Lance is the frame that makes supply 1 a real choice rather than "infantry
or nothing": something that arrives somewhere before the fight does.

**Its defining constraint is no turret.** It aims by pointing its whole body,
which is the Rover's counter — flank it faster than it can traverse — turned
into a chassis trait. That is the whole design: it is fast, it hits once, and
anything that gets alongside it wins.

## 3. Stats

| field | value | why |
|---|---|---|
| `id` | `&"lance"` | permanent once a kill is saved; `kills_by_kind` keys persist |
| `supply` | 1 | the point of the frame |
| `cost` | 90 | above the soldier's 50, well below the Rover's 150 |
| `base_health` | 110 | survives a burst, not an engagement |
| `base_speed` | 1.35 | the fastest thing the player owns |
| `base_sensor_range` | 60 | better eyes than infantry, worse than a Spotter |
| `weapon_slots` | 1 | |
| `starting_weapon_id` | `&"light_cannon"` | new, §4 |
| `turret` | **false** | the defining trait |
| `vehicle` | true | musters with ARMOR |
| `drives` | true | wheeled, so it is refused leg kit — including Nanite Reboot |
| `equipment_slots` | 1 | |
| `module_slots` | 1 | |
| `required_rank` | 0 | available from the start; it is the tutorial vehicle |

`drives = true` is load-bearing: `ChassisDefinition.takes()` refuses anything
with `fits_vehicles = false`, so the Lance cannot take infantry kit and cannot
self-revive. A cheap vehicle that could do both would make the soldier
pointless.

## 4. New weapon — `light_cannon`

A fixed-mount single-shot gun. Hits hard for the supply, reloads slowly, and
cannot track — the chassis aims it.

| field | value |
|---|---|
| kind | 0 (WEAPON) |
| `fits_vehicles` | true |
| `usable_by_player` | false |
| `base_damage` | 48 |
| `fire_cooldown` | 1.6 |
| `max_effective_range` | 85 |
| `ai_spread_mrad` | 7 |
| `magazine_size` | 6 |
| `reload_time` | 3.5 |
| `suppression_per_shot` | 5.0 |

High suppression per shot relative to its rate: a Lance cannot kill much on its
own but it can make a position uncomfortable while something else arrives.

**No `chassis_whitelist` needed** — the whitelist rule in
`ChassisDefinition.takes()` only bites on frames with `turret = true`, and this
frame has `turret = false`. That also means the Lance can take any
vehicle-legal weapon, which is intended: a Lance with a machine gun is a
legitimate and different thing.

## 5. Model

New scene `Character/characters/ai/lance.tscn`, generated once by
`tools/build_lance.gd`. Script `lance.gd`, and the open question is what it
extends — see §6.

```
Lance (CharacterBody3D, groups=["enemies"])   ← add_to_group("enemies", TRUE)
├─ CollisionShape3D   capsule, low and short
├─ Bark / NavigationAgent3D / Detection
├─ Rig
│  ├─ Hull (CSGMesh3D)  chamfered, glacis + tail
│  ├─ Head  small, scale ~0.5, ONE eye (own StandardMaterial3D, NOT in livery)
│  ├─ GunMount (fixed, no pivot)  ← WeaponMount yaw +PI/2, NOT −PI/2
│  └─ Wheels ×N
├─ SparkBurst / OilSpray
└─ FactionLivery  (pieces = TYPED Array[Node3D], eye excluded)
```

The five silent traps the Bulwark hit, all of which apply here:

1. Node-path exports are typed `Node3D`/`Bark`/`Array[Node3D]` — assigning a
   `NodePath` does nothing and leaves nulls.
2. `add_to_group` is **not persistent by default**; without `true` the frame is
   invisible to AIManager, EMP and every hostile sweep while looking fine.
3. An untyped `Array` into `Array[Node3D]` saves as `[]` **silently**, which
   also makes `FactionLivery` fall back to painting the whole frame.
4. `WeaponMount` yaw is **+90°, not −90°** — the Bulwark fired backwards.
5. `hull_spoils_aim` (`enemy.gd:2895`) is excused by a node property literally
   **named `turret`** being non-null — not by `ChassisDefinition.turret`.
   **This one is the Lance's central problem.** See §6.

## 6. Code requirements

**The one real question: what does a turretless moving vehicle do about aim?**

`enemy.gd:2895`:
```gdscript
var hull_spoils_aim: bool = _is_moving() and not ("turret" in self and get("turret") != null)
```
A frame with no `turret` node that is moving never settles `_aim_tracking`, so
it never leaves `WeaponState.AIM`. For the Lance **that is arguably correct and
is the design**: it is a vehicle that must stop to shoot accurately. But it
needs verifying rather than assuming, because "never fires at all" and "fires
badly while moving" are different outcomes and the code above produces the
first.

Three candidate answers, in order of preference:

1. **Extend `Rover` and leave `turret` null.** Rover already handles a wheeled
   hull and a fixed-gun case may already fall out of its `_update_facing`.
   Cheapest if it works; needs reading `rover.gd` before committing.
2. **Extend `Soldier`** and let the body's ordinary facing do the aiming. The
   bicycle model is lost, so it would slide sideways.
3. **A `lance.gd` override of `_weapon_on_target`** comparing the body's
   forward against the target within a cone — the Walker's version without the
   turret indirection.

**No changes to `Enemy` or `Soldier`.** An earlier draft of the Picket document
proposed a roster-wide elevation gate; it was written, reverted, and the lesson
applies here too — a new frame earns its behaviour in its own subclass.

## 7. Tests

`tools/test_lance_frame.gd` — **not** `test_lance.gd`, which already exists and
is the suite for the melee lance *weapon*:

- chassis registered and in the catalogue; supply 1; `turret = false`;
  `drives = true`
- it is **refused** infantry kit (`fits_vehicles = false` items) and Nanite
  Reboot specifically
- in `"enemies"` and in `AI.SIGNAL_GROUP`
- every node-path export resolves; all four typed arrays are POPULATED
- the eye keeps its own `StandardMaterial3D` through a faction repaint
- a fitted weapon points where the frame faces (`dot > 0.9`)
- **the aim question, settled by measurement**: a stationary Lance reaches
  `WeaponState.FIRE`; a moving one does whatever §6 decides, asserted
  explicitly either way so the behaviour is a decision and not an accident

## 8. Open

- Which base class (§6). Decide by reading `rover.gd`, not by guessing.
- Whether `base_speed = 1.35` outruns the squad it belongs to. `Squad`'s leash
  is 9–12 m and measured in 3D; a frame faster than the squad may be recalled
  constantly.
- `cost` is a guess until `tools/audit_economy.gd` prices it.
