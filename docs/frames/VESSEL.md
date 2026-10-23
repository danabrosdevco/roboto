# VESSEL — design document

Supply 3 · ground · carrier · **status: concept selected, not built**

---

## 1. Concept

**Selected: A — BAY DOORS.** 3.52 W x 3.19 H x 4.72 L.

A long low six-wheeled hull with two full-length roof panels hinged open
upward, a small turret set back on one side, and the bay standing open between
them.

**It is the only one of the four whose proposition needs no caption.** Doors
open is a universally legible statement about what a vehicle is for, and it
reads *from above* — which matters here, because the player commands from a
height and the moment that has to be obvious is the release. The panels also
give the frame two silhouettes, closed and open, so the state the player cares
about is the state they can see.

**It changes one stat: `drives` becomes true.** Section 3 has the Vessel
legged. A is wheeled, and on reflection that is the better frame rather than a
concession. The stated job of this chassis is to make "spend 3" mean something
other than "buy a mech", and a wheeled carrier that must keep to open ground
while the Hatchlings it drops go anywhere is a sharper version of that than a
third set of legs — it turns the release point into a decision instead of a
formality. The cost is real and is logged in section 8.

The other three: **B APC** is the heaviest and most convincing military object
on the sheet, but its rear rack is a rack and nothing on it opens; a carrier
whose contents the player cannot see is the exact failure the art brief named.
**C** is spec-compliant and legged and its pods do open, but it is 4.39 m wide
with them out, and nothing about it says *carrier* until they move — a read
that depends on an animation is not a read. **D** is a flat deck on legs with a
lifting hoop: a pallet carrier, which is the Drayman's job, not this one.

Art brief: must read as **containing something** — bay doors, a cradle, a rack,
something that opens. At least two of the four options show the carried drones,
so the proposition is legible without a caption.

## 2. What it is for

The brief that generated these ten frames said explicitly that the Walker and
the Bulwark already shred their class, and that there is not much room above
them. That is the constraint this frame is built against.

**So the Vessel is not a bigger gun. It changes how many bodies are on the
field.** It carries two Hatchlings and releases them mid-mission: a mobile,
friendly version of the enemy Nest, whose counter today is "walk over and break
it" precisely because it cannot move.

That makes it the first supply-3 frame that is not a firepower platform, and it
gives the third supply band a second shape. Right now "spend 3" means "buy a
mech".

## 3. Stats

| field | value | why |
|---|---|---|
| `id` | `&"vessel"` | permanent once a kill is saved |
| `supply` | 3 | |
| `cost` | 340 | just above the Walker's 320 |
| `base_health` | 260 | under the Walker's 320 and well under the Bulwark's 400 |
| `base_speed` | 0.85 | |
| `base_sensor_range` | 50 | |
| `weapon_slots` | 1 | it defends itself, it does not lead |
| `starting_weapon_id` | `&"machine_gun"` | existing, vehicle-legal |
| `turret` | true | needs the `turret` **node**, see section 6 |
| `vehicle` | true | |
| `drives` | **true** | **changed by the concept** — the selected hull is wheeled, section 1 |
| `equipment_slots` | **2**, pre-loaded with `hatchling` | the frame itself |
| `module_slots` | 2 | |
| `required_rank` | 4 | the last thing unlocked |

**Deliberately weaker than the Walker in every combat stat.** A supply-3 frame
that also out-fought the Walker would make the Walker pointless, and the brief
was explicit that there is no headroom above it.

## 4. New weapons

**None.** `hatchling` already exists as `kind = 1` EQUIPMENT with
`fits_vehicles = true`, and `machine_gun` is vehicle-legal. The Vessel is the
cheapest frame on the list in new-content terms: it is a chassis and a
behaviour, nothing else.

That is a feature. Of the ten, this one can be built entirely from parts that
already work.

## 5. Model

New scene from `tools/build_vessel.gd`; script `vessel.gd`, `extends Walker`
(legged) or `Soldier` (tracked) depending on the concept.

```
Vessel (CharacterBody3D, groups=["enemies"])   <- add_to_group("enemies", TRUE)
+- CollisionShape3D   larger than the Walker's r 0.85 h 3.0
+- Bark / NavigationAgent3D / Detection
+- Rig
|  +- Hull (CSGMesh3D)  the biggest hull in the game
|  +- Bay: doors or a cradle, with two drone shapes visible inside
|  +- Turret (Node3D)   <- MUST exist and be exported as `turret`
|  |  +- Head: ONE eye, own StandardMaterial3D, NOT in livery
|  |  +- GunPivot -> WeaponMount   <- yaw +PI/2
|  +- Legs or tracks
+- SparkBurst / OilSpray
+- FactionLivery  (TYPED Array[Node3D], eye excluded)
```

**The bay has to be visibly empty after launch.** A carrier that looks
identical whether it is loaded or spent is a carrier whose state the player
cannot read, and the state is the whole unit. Two carried drone meshes that get
hidden on release is the cheap version and is enough.

Plus the five silent traps: typed node-path exports, `add_to_group(.., true)`,
typed `Array[Node3D]`, `WeaponMount` yaw **+90 degrees**, and the `turret`-node
rule in `hull_spoils_aim`.

## 6. Code requirements

**Nothing in `Enemy` or `Soldier`.** The release is the only new behaviour, and
most of it already exists.

`hatchling_payload.gd` handles a hatchling being thrown: it inherits the
thrower's faction, defaulting to `PLAYER` when the source is `NEUTRAL`. The
Vessel releasing one is the same operation from a different origin.

Three things to get right:

1. **Faction inheritance.** The released drone must take the Vessel's faction,
   not a default. This is already how the payload behaves; it needs asserting,
   not writing.
2. **The bay state.** Two carried meshes, hidden on release, and a count that
   persists for the mission. If the Vessel dies with one still aboard, it is
   lost — which is a real decision for the player about when to spend them.
3. **Who commands a released drone.** The hatchling already joins the player's
   side; whether it joins the Vessel's *squad* (and so takes squad orders) or
   runs its own behaviour is the design question. **Recommend it joins the
   squad** — otherwise the Vessel's output is two units the player cannot
   direct, which is a worse version of the same supply spent on soldiers.

## 7. Tests

`tools/test_vessel.gd`:

- registered, catalogue, supply 3, `weapon_slots = 1`, `turret = true`
- **it is weaker than the Walker in combat stats**, asserted against
  `chassis_walker.tres` directly so the two cannot silently converge — this is
  the balance constraint the whole frame is built around
- the `turret` node exists and is non-null (else it never fires while moving)
- it launches two hatchlings and then cannot launch a third
- **a released hatchling has the Vessel's faction**, not a default
- the bay reads as empty after release (carried meshes hidden)
- in `"enemies"` and `AI.SIGNAL_GROUP`; typed arrays populated; eye survives a
  repaint; fitted weapon points forward

## 8. Open

- Two drones or three. Two makes each one matter; three makes the frame feel
  like a carrier. Needs playing.
- Whether released drones rejoin the squad (section 6.3). This changes whether
  the Vessel is a *commander's* tool or a fire-and-forget one.
- Whether the bay should reload at base between missions automatically, or be
  a purchased consumable. The second is more interesting and more fiddly.
- **`drives = true`, settled in section 1 and not yet costed.** A wheeled
  supply-3 frame refuses leg kit, is held to ground the Walker can cross and
  it cannot, and inherits whatever the wheeled frames already suffer on broken
  terrain. That constraint is the point of the frame, but it has to be checked
  against the actual levels before this is built: if the Vessel cannot reach
  the places a release would matter, the frame is scenery.
- Whether the bay doors are animated or simply built open. Built open is
  honest and free; animated is better and ties to section 6's release.
