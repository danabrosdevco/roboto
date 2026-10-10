# SAPPER — design document

Supply 1 · infantry · engineer · **status: concept selected, not built**

---

## 1. Concept

**Selected: B — PLANTER.** 1.04 W x 2.10 H x 1.44 L.

Both hands on a T-handled tool driven into the ground ahead of it, a bandolier
of mine discs across the lower back, hunched over the work.

**The pose is the read.** It is the only one of the four where the verb —
putting something in the ground — IS the silhouette, and that matters more than
any fitting, because the Sapper's whole contribution happens before contact.
The oversized shoe and the cross handle are what keep the shaft from reading as
a rifle, which was the risk going in.

The other three: **A SPOOL** (wire drum, dragging plough shoe) was the close
second and is the only frame in the game that would leave a trail, but the drum
reads as a backpack at a glance. **C MULE** carries its load on a pack ladder
above its own head and reads as a porter rather than an engineer. **D BOOM**
replaces one arm with an articulated boom setting a mine — asymmetric and
legible, but it is the nearest of the four to the Mechanic's welder arm, and
those two should not be confusable.

**Mines are drawn as flat discs with a ring, ~0.26 m** — a shape new to the
roster, which is what lets a bandolier of them read as ordnance rather than
pouches.

Art brief: infantry scale (~1.8 m, the soldier's size class), and it must read
as **infantry that carries equipment** — satchels, a spool, a planting tool, a
hunched posture. Distinct from the Mechanic, which is a medic with a welder.

## 2. What it is for

Mines exist as items (`mine_heavy`, `mine_cluster`) and nothing is built around
placing them. They are a thing you happen to have, not a thing you do.

The Sapper makes **pre-committing to where a fight happens** a playable idea.
It is the only frame whose contribution is made before contact: it shapes the
ground, then the squad fights on ground it chose. That is a different verb from
anything else in the roster, all of which either shoot, heal or look.

It is deliberately a poor fighter. A supply-1 frame that laid mines *and* held
a line would simply replace the soldier.

## 3. Stats

| field | value | why |
|---|---|---|
| `id` | `&"sapper"` | permanent once a kill is saved |
| `supply` | 1 | |
| `cost` | 75 | above the soldier's 50 and the mechanic's 70 |
| `base_health` | 55 | slightly under the soldier's 60 |
| `base_speed` | 0.95 | carrying a load |
| `base_sensor_range` | 45 | infantry standard |
| `weapon_slots` | 1 | it can defend itself, badly |
| `starting_weapon_id` | `&"carbine"` | existing item, weaker than the m4 |
| `turret` | false | |
| `vehicle` | false | musters with INFANTRY |
| `drives` | false | takes leg kit, including Nanite Reboot |
| `equipment_slots` | **3** | the whole frame. Soldier has 2 |
| `module_slots` | 1 | |
| `required_rank` | 1 | |

**The stat that IS the frame is `equipment_slots = 3`.** Everything else is a
slightly worse soldier. Note `SoldierRecord` sizes equipment against
`equipment_capacity()` plus the Utility Harness bonus, so a Sapper with a
harness is the only frame in the game carrying four pieces of equipment.

## 4. New weapons

**None.** This is deliberate and is the cheapest frame on the list for that
reason: it uses `mine_heavy`, `mine_cluster`, `smoke` and `frag`, all of which
exist, all of which are `kind = 1` EQUIPMENT with a `quantity` meaning "uses
per mission".

If a dedicated tool is wanted later the obvious one is a **breaching charge** —
a placed demolition item that opens cover rather than killing — but the frame
is complete without it and should ship without it.

## 5. Model

New scene `Character/characters/ai/sapper.tscn` from `tools/build_sapper.gd`.
Script `sapper.gd`, `extends Soldier`.

**It should be built on `soldier_chassis.tscn`'s proportions, not invented.**
The soldier is the frame the player sees most and a sapper that does not read
as the same army is worse than one that is merely plain. The differences are
additive: satchels on the hips, a spool on the back, a planting tool in one
hand, and a slightly forward-leaning stance.

Same five silent traps as every other new frame — typed node-path exports,
`add_to_group("enemies", true)`, typed `Array[Node3D]`, `WeaponMount` yaw
**+90°**, and the `turret`-node rule in `hull_spoils_aim` (not relevant here,
since infantry have no turret and `hull_spoils_aim` correctly applies).

The eye keeps its own `StandardMaterial3D` with the white-tile albedo and stays
**out** of the `FactionLivery` pieces list.

## 6. Code requirements

**Minimal, and none of it in `Enemy` or `Soldier`.**

The one question is whether an AI Sapper places mines *sensibly*. Equipment use
runs through `AIEquipmentSlot` and `Enemy._evaluate_equipment_use`, which scores
against an `EquipmentContext` carrying `threat_bearing`, `threat_position` and
`under_fire_seconds`. That context has no notion of "a place worth mining" —
a chokepoint, an approach, a doorway.

Three options, cheapest first:

1. **Do nothing.** The AI Sapper drops mines when the existing equipment
   scoring says to, which will be reactive rather than planned. Acceptable for
   a first pass and honest: the frame is still useful under player command.
2. **A `sapper.gd` override** that prefers placing on the squad's *approach*
   rather than its current position — reachable from the squad's objective.
3. **Mine-aware context**, which is the real version and is out of scope.

Recommend 1 for the first build, with 2 logged. A frame whose AI is mediocre
but whose player use is strong is a normal outcome for an engineer unit.

## 7. Tests

`tools/test_sapper.gd`:

- registered, in the catalogue, supply 1, `equipment_slots = 3`
- it **accepts** `mine_heavy` and `mine_cluster`; a Rover is **refused** them
  if they are infantry-only (check `fits_vehicles` on each first — if mines are
  vehicle-legal today, this assertion is wrong and should be dropped rather
  than forced)
- with a Utility Harness it reaches four equipment slots
- in `"enemies"` and `AI.SIGNAL_GROUP`; node-path exports resolve; typed arrays
  populated; eye survives a faction repaint
- it is a worse shooter than a soldier, measured — lower `base_health` and a
  carbine rather than an m4, asserted against the soldier chassis so the two
  cannot silently converge

## 8. Open

- Whether mines are currently vehicle-legal. Decides one test and whether the
  Sapper is actually distinct from "a Rover with mines".
- `cost` versus the Mechanic's 70. Two supply-1 support frames at nearly the
  same price need a reason to pick one, and right now that reason is only
  "heal versus shape".
