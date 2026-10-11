# BASTION — design document

HOME COMMAND · supply 3 · ground · deployable hardpoint · enemy only
**status: concept selected, not built**

**Prerequisite: `docs/frames/ENEMY_FACTIONS.md`. Do not build this before
`are_hostile` is a table.**

---

## 1. Concept

**Selected: B — THE PYLON (planted).** 3.44 W x 4.48 H x 4.21 L.

Legs locked straight, four long outriggers hammered down, and the field held
overhead as a canopy hoop on a mast. A parasol over a position.

**The overhead hoop is the clearest statement of "projecting something over an
area"**, which is the entire unit, and it is readable from any angle — which
matters, because the planted state is the thing the player has to recognise in
order to play around it. The locked legs and driven outriggers say planted
without needing the hoop at all, so the silhouette carries two facts at once.

The other three: **A REDOUBT** sits down on its skirts with four corner spades
and a 3.7 m emitter collar girdling the hull — an excellent pillbox, and the
best "this is immovable", but a collar reads as armour rather than as a field.
**D LAAGER** unfolds four armour panels off the hull corners with emitters
along their top edges, putting the panels on the diagonals so the fore/aft
lanes and the eye stay visible; it says *cover*, which is a different promise
from *hardening*. **C ON THE MARCH** is the only walking option and is the one
to reuse for the unplanted state rather than as the primary read.

**It uses the player's own vocabulary deliberately** — `K.hull`, `K.head`,
`K.leg`, the turret ring, the single offset eye. Home Command is the player's
parent organisation, so this frame should look like it came off the same line,
with more plate and better finish. That is the faction statement.
state is the thing to recognise.*

Art brief: Home Command is the player's own parent organisation, so **this frame
should look RIGHT** — the same chamfered hull, turret ring, single offset eye
and boxy digitigrade limbs as the Walker, but more of it and better finished.
Institutional green. It is the only one of the enemy three that should use the
player's visual vocabulary, and that is the point: it is the army the player's
own side belongs to.

## 2. What it is for

Two jobs at once, and the second is the interesting one.

**It walks, then plants.** Immobile, heavily armoured, and projecting a
protective field that raises nearby Home Command units' `signal_resistance`. It is
the mirror of the player's Warden: one degrades, one hardens.

**It is the first enemy that rewards killing a support unit first.** Everything
hostile today is either a threat you shoot or an objective you break. A Bastion
makes the squad around it measurably harder to suppress, so the correct play is
to deal with the thing that is not shooting at you — which is a decision the
game cannot currently ask.

It also gives Home Command a doctrine on screen. Swarm is numbers, Argus is
intelligence, Home Command is **position**: a frame whose whole statement is "this
ground is now expensive".

## 3. Stats

| field | value | why |
|---|---|---|
| `id` | `&"bastion"` | **permanent once a kill is saved** |
| faction | HOME COMMAND | |
| `supply` | 3 | |
| `cost` | 0 | `purchasable = false` |
| `base_health` | 300 | under the Bulwark's 400; it is not a duel |
| `base_speed` | 0.6 walking, **0.0 planted** | |
| `base_sensor_range` | 60 | |
| `weapon_slots` | 1 | it defends itself |
| `starting_weapon_id` | `&"heavy_mg"` | existing |
| `turret` | true | needs the `turret` **node**, section 6 |
| `vehicle` | true | |
| `drives` | false | legged |
| `equipment_slots` | 0 | |
| `module_slots` | 0 | |
| `musters_at_base` | false | |
| `signal_resistance` (scene) | 2.0 | it is the hardening frame; it is hardened |

## 4. New weapon — `shield_projector`

The inverse of the Warden's jammer, and the second EMITTER. Same class, same
plumbing, opposite sign.

| field | value |
|---|---|
| kind | 0 (WEAPON) — see the Warden doc for why there is no fourth `Kind` |
| `fits_vehicles` | true |
| `usable_by_player` | false |
| `base_damage` | 0 |
| radius | 14 m |
| effect | raises allied `signal_resistance` while inside |

**It occupies the second weapon slot conceptually but not literally** — the
Bastion has `weapon_slots = 1` and that slot holds the MG. The projector is
built into the frame (`built_in`), which is the honest way to model a thing
that is not optional equipment.

**The effect needs care.** `signal_resistance` divides both incoming
suppression and EMP lock duration (`ai.gd:116-138`). Raising it on a squad is
strong, and it is strong against exactly the systems the player just gained.
A multiplier around 1.6 for units inside is a starting point; anything near
3.0 would make a Bastion squad effectively immune to suppression, which is not
a fight, it is a wall.

## 5. Model

New scene from `tools/build_bastion.gd`; script `bastion.gd`, `extends Walker`
— it is a legged frame with a turret and the Walker's gait, traverse and
facing are all generic.

```
Bastion (CharacterBody3D, groups=["enemies"])   <- add_to_group(.., TRUE)
+- CollisionShape3D
+- Bark / NavigationAgent3D / Detection
+- Rig
|  +- Hull (CSGMesh3D)  the player's chamfered vocabulary, heavier
|  +- Turret (Node3D)   <- MUST exist and be exported as `turret`
|  |  +- Head: cheek + brow cut, ONE eye (own StandardMaterial3D, NOT in livery)
|  |  +- Antenna
|  |  +- GunPivot -> WeaponMount   <- yaw +PI/2
|  +- Projector: a dish or coil, visibly ON when planted
|  +- Spades / skirts: deployed when planted, stowed when walking
|  +- HipL/R -> KneeL/R -> FootL/R
+- SparkBurst / OilSpray
+- FactionLivery  (TYPED Array[Node3D], eye excluded)
```

**The planted state must be visible from any angle.** Spades down, skirts out,
projector lit. A frame whose most important state is invisible is a frame the
player cannot play around, and the whole unit is about reading the field.

Plus the five silent traps: typed node-path exports, `add_to_group(.., true)`,
typed `Array[Node3D]`, `WeaponMount` yaw **+90 degrees**, and the `turret`-node
rule in `hull_spoils_aim`.

## 6. Code requirements

**Nothing in `Enemy` or `Soldier`.** Three pieces:

1. **`suppress_in_radius` with a negative sign** — or more precisely, an
   allied-side variant that writes `signal_resistance` rather than draining
   `signal_integrity`. The Warden's static is the model; this one iterates
   `AI.SIGNAL_GROUP`, filters to *non*-hostiles of the Bastion's faction, and
   applies a resistance multiplier with a falloff.

   **The restore is the hard part.** `signal_resistance` is a plain export with
   no stack or timer. Multiplying it on entry and dividing on exit is fragile —
   two overlapping Bastions, or one dying mid-effect, leaves a robot
   permanently hardened. **Recommend a `_resistance_bonus` additive field that
   is recomputed from scratch each tick** rather than mutated, so there is
   nothing to restore and no ordering to get wrong.

2. **Plant / unplant.** A state on `bastion.gd`: zero speed, the visual change,
   and the projector only active while planted. The decision of *when* is AI
   behaviour and the simplest honest version is "plant on first contact,
   unplant if the fight moves out of range".

3. **Faction.** HOME COMMAND, and the projector must only help HOME COMMAND. Given the
   recommendation in the shared prerequisite that the three enemy factions are
   **not** hostile to each other, "ally" here must mean *same faction*, not
   *not-hostile* — otherwise a Bastion would harden Swarm and Argus units too.
   This is a real trap and it follows directly from that recommendation.

## 7. Tests

`tools/test_bastion.gd`:

- registered, supply 3, `purchasable = false`, faction HOME COMMAND
- **`are_hostile(PLAYER, HOME COMMAND)` true both ways** — proves task zero
- planted: speed is zero and the projector is active; walking: the inverse
- a HOME COMMAND unit inside the radius has raised `signal_resistance`; one outside
  does not; **a SWARM unit inside does NOT** (section 6.3)
- **the bonus is removed cleanly** when the Bastion dies, tested by killing it
  and re-reading the neighbour — the fragile case
- two overlapping Bastions do not stack into immunity
- the `turret` node exists; a fitted weapon points forward
- in `"enemies"` and `AI.SIGNAL_GROUP`; typed arrays populated; eye survives a
  repaint

## 8. Open

- The resistance multiplier. 1.6 is a guess and the ceiling is "not a wall".
- Whether it should plant automatically or only at authored positions. Authored
  is more controllable for mission design and less interesting in a fight.
- Whether a planted Bastion should be immune to being pushed — `move_and_slide`
  shoving exists and a hardpoint that can be nudged is not a hardpoint.
