# BROODCARRIER — design document

SWARM · supply 2 · **aerial** · spawner · enemy only
**status: concept selected, not built**

**Prerequisite: `docs/frames/ENEMY_FACTIONS.md`. Do not build this before
`are_hostile` is a table.**

---

## 1. Concept

**Selected: A — THE BUNCH.** 2.90 W x 2.27 H x 3.28 L.

A lift hoop overhead with nine jittered pods hanging beneath it like fruit, and
two offspring already dropping free.

**The proposition needs no caption.** Pods hanging in a cluster say "full of
things", and the two drones drawn mid-release say what the things are and
where they go. The ring-over-cluster outline is unlike anything else in the
roster, and the jitter in the pod positions is what makes it read as Swarm
rather than as a magazine — nothing here is precision-made.

The other three: **B BASKET** (a lid with mismatched fans over six ribs
converging into a floorless mouth ring) takes "open underside" literally and is
clean, but a basket reads as empty. **C GRAVID ABDOMEN** — a bloated
three-segment body held nose-down with pods barnacled over its skin — is the
most Swarm of the four and the most organic, and was the close second; it
reads as a creature rather than a machine, which cuts both ways. **D HANGING
NEST** is compact and its seven downward brood tubes make the direction of
arrival unambiguous, but at 5.00 m across it is the widest thing on the sheet
for a supply-2 frame.
Art brief: must read as **flying** and **full of things**. Clustered pods, a
cluster of small shapes slung underneath, an open underside. Drawn airborne,
body at y 2.0–3.0, no legs. Swarm is amber, accreted, asymmetric — nothing
precision-made, and visibly *not* the player's factory.

## 2. What it is for

The Nest already spawns things, and its counter is that it cannot move: walk
over and break it. That is a fine puzzle once.

**The Broodcarrier is the Nest with the counter removed.** It keeps producing
and it keeps relocating, so the answer stops being "go there" and becomes
"stop it, now, while it is in reach" — which is a different and better
pressure, and it is the first enemy that punishes a squad for being slow
rather than for being out of position.

It is also the frame that makes Swarm mean something mechanically rather than
only in the colour table. Swarm is swarm: this is the unit that produces the
swarm.

## 3. Stats

| field | value | why |
|---|---|---|
| `id` | `&"brood"` | **permanent once a kill is saved** |
| faction | SWARM | |
| `supply` | 2 | |
| `cost` | 0 | `purchasable = false` — enemy only |
| `base_health` | 200 | high for a flyer; killing it is the objective |
| `base_speed` | 0.7 | slow, so that reaching it is possible |
| `base_sensor_range` | 70 | |
| `weapon_slots` | 0 | **it never shoots** — the brood is the weapon |
| `turret` | false | |
| `vehicle` | true | |
| `drives` | false | |
| `equipment_slots` | 0 | the spawn is behaviour, not an item |
| `module_slots` | 0 | |
| `musters_at_base` | false | |

**`weapon_slots = 0` is the design.** A flying spawner that also shot would be
two units. This one is a problem you have to prioritise, not a thing that
threatens you directly, which is what makes ignoring it a decision with a cost.

## 4. New weapons

**None.** It spawns existing Hoppers/Leapers.

## 5. Model

New scene from `tools/build_brood.gd`; script `brood_carrier.gd`.

**Base class: copy the Spotter's flight model, not the bomber's.** Verified in
research: the Spotter's `handle_movement` is 34 lines with no phase machine and
it already answers the squad seams (`slot_tolerance`, `formation_width`,
`takes_cover`, `off_navmesh_is_normal`). The bomber overrides **none** of
those, so it inherits `takes_cover() -> true` and can be handed a *ground
cover point* as a loiter centre — a latent bug you would inherit by copying it.

```
Broodcarrier (CharacterBody3D, groups=["enemies"])  <- add_to_group(.., TRUE)
+- CollisionShape3D   sphere ~0.9 (Spotter 0.5, bomber 0.6 — this is bigger)
+- Bark / NavigationAgent3D / Detection
+- GroundRay (RayCast3D, built in _ready, target (0,-300,0), mask 1)
+- Rig
|  +- Hull: accreted, asymmetric, NOT the chamfered player hull
|  +- Brood bay: visible pods underneath, emptying as they launch
|  +- Rotors
+- SparkBurst / OilSpray
+- FactionLivery  (TYPED Array[Node3D])
```

**The pods must visibly empty.** Same argument as the Vessel: a spawner whose
remaining stock the player cannot read is a spawner the player cannot make a
decision about.

No eye in the player's sense — Swarm should not have the Walker's single
offset eye. Whatever sensor it has should read as *not ours*.

Plus the five silent traps: typed node-path exports, `add_to_group(.., true)`,
typed `Array[Node3D]`, mount yaw **+90 degrees** if any mount exists at all,
and the `turret`-node rule (not relevant — nothing fires).

## 6. Code requirements

**Nothing in `Enemy` or `Soldier`.** Three pieces:

1. **Flight.** Lift the Spotter's `_steer` / `_altitude_velocity` /
   `_ground_height` / `_turn_toward` / `_orient` set. These are already shared
   between the Spotter and the bomber, so a third copy is the moment to ask
   whether they should be a shared flight component — **recommend extracting
   it when this frame is built**, since that makes three.

2. **The spawn loop.** A timer, a cap on live offspring, and a release point
   under the hull. The Nest is the reference for the behaviour; the hatchling
   payload is the reference for faction inheritance.

3. **Faction inheritance on the offspring.** Spawned Hoppers must be SWARM,
   not ENEMY. This is the thing most likely to be got wrong silently, because
   ENEMY works today and SWARM is the new value.

**Known gap:** `Squad._enforce_leash` measures 3D and does not consult
`slot_tolerance`, so any flyer well above the ground is permanently outside the
leash. This applies to enemy squads too. If the Broodcarrier is placed in an
enemy squad rather than solo, expect it to be recalled constantly.

## 7. Tests

`tools/test_brood.gd`:

- registered, supply 2, `purchasable = false`, `weapon_slots = 0`
- faction SWARM, and **`are_hostile(PLAYER, SWARM)` is true in both
  directions** — the assertion that proves task zero was actually done
- it spawns offspring on a timer and **stops at the cap**
- **offspring inherit SWARM**, not ENEMY
- the brood bay reads as emptying
- it flies: holds altitude over varying ground
- it can be shot down; `enter_downed` crashes it rather than leaving it standing
- in `"enemies"` and `AI.SIGNAL_GROUP`
- it never enters a firing state

## 8. Open

- Spawn rate and cap. Too fast and it is a fail state; too slow and it is
  scenery.
- Whether killing it should kill the brood already out. Cleaner as a player
  promise ("break the carrier and the fight ends") but less interesting than
  leaving them alive.
- Whether to extract the shared flight component now (section 6.1). Three
  copies is the threshold where not doing it starts costing.
