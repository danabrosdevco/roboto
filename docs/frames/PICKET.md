# PICKET — design document

Supply 2 · ground · anti-air · **status: concept selected, not built**

---

## 1. Concept

Selected **C2** from the second concept round: launcher-led, six tubes canted
up and unmistakable, a sensor dish demoted to a shoulder fitting, Walker legs
underneath. 2.24 W × 3.27 H × 1.76 L as drawn.

Round one put up five answers — a tripod gun, a Rover with a high-angle
turret, a dish-led "umbrella", a crouched "mantis" holding guns up on two
arms, and a spire with a ring of barrels. Three of them failed the same way:
**they looked like guns, and a gun that happens to elevate is not a readable
answer to being bombed.** The dish was the only shape in the roster that says
*aircraft* before you have parsed anything else, so C won; C2 then fixed its
three faults (dish too big and reading as the whole unit, launcher invisible
beside it, and 4.07 m — taller than a Walker, wrong for a 2-supply frame).

It also puts a legged frame at supply 2, which is a new point on the grid:
everything legged today is supply 3.

## 2. The problem it exists for — restated, because the first version was wrong

The brief originally said "nothing counters air". **That was false and was
caught before anything was built.** Verified in the code:

| | |
|---|---|
| `walker.gd:224` | clamps `want_pitch`, writes it to `gun_pivot.rotation.x` — the MODEL |
| `walker.gd:243` | `to.y = 0.0` in `_weapon_on_target` — **the fire gate discards elevation** |
| `ai_weapon.gd:441` | damage ray is `create(from, dir * 250)` with `exclude` only — no mask, full 3D |
| `enemy.gd:2831` | `face_dir.y = 0.0` — infantry have no pitch at all |

`gun_max_pitch_degrees` is cosmetic. **A rifleman will shoot straight up.**
Everything already engages everything overhead.

So the real gap is the inverse: **there is no mechanism that DENIES a high
shot.** Aerials survive by accident — a 0.5 m collider at 22 m, with
range-proportional spread doing the rest. Nothing about the air game reads as a
decision because nothing about it is one.

**The Picket does not fix that, and does not try to.** Changing it would mean
changing how every existing frame fights, which is a combat-model decision and
not something a new chassis should smuggle in. What the Picket offers instead
is a frame that is GOOD at the job everything else is merely CAPABLE of — see
§6. The gate remains logged in the main brief as a separate question.

## 3. Stats

| field | value | why |
|---|---|---|
| `id` | `&"picket"` | permanent once a kill is saved — `kills_by_kind` keys persist |
| `supply` | 2 | the specialist band, alongside Rover and Reclaimer |
| `cost` | 210 | above Rover (150), below Spotter (180)? no — above both; it is a counter-pick |
| `base_health` | 140 | thinner than a Rover's 180. It is not meant to be shot at |
| `base_speed` | 0.9 | legs, and it wants to be positioned rather than driven |
| `base_sensor_range` | 75 | second only to the Spotter's 90 — it has to see them coming |
| `weapon_slots` | 1 | |
| `starting_weapon_id` | `&"flak"` | new, §4 |
| `coax_weapon_id` | `&""` | |
| `turret` | true | it needs the `turret: Node3D` export — see §5 |
| `vehicle` | true | musters with ARMOR |
| `drives` | false | legged, so it takes leg kit a Rover cannot |
| `equipment_slots` | 0 | |
| `module_slots` | 2 | |
| `required_rank` | 2 | |
| `musters_at_base` | true | |

Against the two frames it sits between: Rover is 180 hull / 150 cost / turret /
driven; Reclaimer is 150 hull / 130 cost / support. The Picket is the first
supply-2 frame that is bad at its job unless the enemy brought the right thing.

## 4. New weapon — `flak`

| field | value |
|---|---|
| kind | 0 (WEAPON) |
| `fits_vehicles` | true |
| `usable_by_player` | false |
| `chassis_whitelist` | `[&"picket"]` — see below |
| `base_damage` | 14 |
| `fire_cooldown` | 0.18 |
| `max_effective_range` | 95 |
| `min_effective_range` | 0 |
| `ai_spread_mrad` | 18 (wide — it is an airburst, not a rifle) |
| `magazine_size` | 40 |
| `reload_time` | 4.0 |
| `pellets` | 3 |
| `suppression_per_shot` | 2.0 |

Low damage per pellet, three pellets, fast cycle, very wide spread: it shreds a
90-hull Kite and embarrasses itself against a 400-hull Bulwark, which is the
intended shape.

**The whitelist matters.** `ChassisDefinition.takes()` refuses a WEAPON on a
`turret` frame unless the item names that frame in `chassis_whitelist`. So
`flak` cannot be bolted to a Rover, and the Picket cannot be handed an
autocannon unless the autocannon lists it. That is the existing mechanism; no
new code.

## 5. Model

New scene, `Character/characters/ai/picket.tscn`, generated once by
`tools/build_picket.gd` the way the Bulwark was — a robot scene is ~39
sub-resources with hand-numbered ids and an exact `load_steps` that `check.sh`
verifies, and writing that by hand is a transcription exercise.

Node plan, with the traps that bit the Bulwark marked:

```
Picket (CharacterBody3D, groups=["enemies"])     ← add_to_group("enemies", TRUE)
├─ CollisionShape3D     capsule r 0.8 h 2.4
├─ Bark / NavigationAgent3D / Detection
├─ Rig
│  ├─ Hull (CSGMesh3D)  1.45 × 0.9 × 1.55, glacis + tail + shoulder cuts
│  ├─ TurretRing
│  ├─ Turret (Node3D)                           ← MUST be named/exported `turret`
│  │  ├─ TurretBody (CSG)
│  │  ├─ Head: cheek + brow cut, ONE eye (StandardMaterial3D, white-tile
│  │  │   albedo — NOT the faction metal, and NOT in the livery list)
│  │  ├─ Antenna
│  │  ├─ Dish  (shoulder, cosmetic sensor)
│  │  └─ GunPivot
│  │     ├─ PodBlock  3 × 2 tubes
│  │     └─ WeaponMount  ← yaw +PI/2, NOT −PI/2
│  ├─ HipL → KneeL → FootL
│  └─ HipR → KneeR → FootR
├─ SparkBurst / OilSpray
└─ FactionLivery   (pieces = TYPED Array[Node3D], eye excluded)
```

Five things the Bulwark got wrong first time, all silent, all re-checkable here:

1. **Node-path exports are typed `Node3D`/`Bark`/`Array[Node3D]`, not
   `NodePath`.** Assigning a NodePath does nothing and the frame comes out with
   a null turret and legs the gait cannot find.
2. **`add_to_group` is not persistent by default.** Without `true` the group
   never reaches the saved scene and the frame is invisible to AIManager, to
   EMP and to every hostile sweep while looking perfectly fine.
3. **Untyped `Array` into `Array[Node3D]` saves as `[]`**, silently — which
   also makes `FactionLivery` fall back to painting the whole frame, eye
   included.
4. **The WeaponMount yaw is +90°, not −90°.** Read off the Walker's matrix it
   looks like a quarter turn either way; it is not, and the Bulwark fired
   backwards.
5. **`hull_spoils_aim` (`enemy.gd:2895`) is excused by a node property
   literally named `turret` being non-null** — not by `ChassisDefinition.turret`.
   Miss it and the aim never settles on a moving frame.

Script: `Character/characters/ai/picket.gd`, `extends Walker`. The gait,
traverse, facing split and fire cone are all generic and inherited. It changes
numbers, not behaviour — see §6.

## 6. New code

**None in `Enemy` or `Soldier`.** An earlier draft of this document proposed a
roster-wide elevation gate so that most frames could not shoot upward. That was
the wrong scope: it is a change to how every existing unit behaves, made in
service of one new frame. It was written, reverted, and `enemy.gd` is back to
byte-identical with HEAD.

**What the Picket actually needs is nothing new.** It is a legged frame with a
turret, which is `Walker`, and `Walker` already provides the gait, the traverse,
the facing split and the fire cone. `picket.gd` extends it and sets different
numbers: `gun_max_pitch_degrees` near vertical so the barrel visibly tracks a
target overhead, a high `base_sensor_range`, and a slow traverse so flanking it
remains the counter.

**So what makes it good against aircraft, given everything can already shoot
up?** Three things that are all stats, not code:

1. **`flak`'s shape.** Three pellets, 0.18 s cycle, 14 damage each, 18 mrad
   spread. Against a 90-hull Kite at 60 m that is lethal; against a 400-hull
   Bulwark it is a nuisance. The weapon discriminates by target size, which is
   the honest way to build a counter-pick in a game where everything can point
   at everything.
2. **Sensor range 75.** Aircraft are currently hard to hit because they are
   small, far and fast, and `get_inaccurate_target` scatters proportionally to
   RANGE. A frame that sees them at 75 m engages them closer to its own spread
   floor than a frame that sees them at 45.
3. **It is the only frame whose barrel is modelled to point there.** Cosmetic,
   but it is what makes the counter legible to the player, which is most of
   what a counter-pick is for.

If the air game later wants to be a designed matchup rather than an emergent
one, the elevation gate is the change that does it — and it should be taken on
its own merits, as a combat-model decision, not smuggled in under a new
chassis. Logged in `docs/briefs/NEW_FRAMES.md` §7, not here.

## 7. Tests

`tools/test_picket.gd`, modelled on `test_bulwark.gd` (47 checks). Must cover:

- chassis registered, in the catalogue, supply/slots/speed as specified
- `flak` exists, whitelisted to the Picket, and **refused** on a Rover
- the frame is in `"enemies"` and in `AI.SIGNAL_GROUP`
- node-path exports all resolve non-null; all four typed arrays are POPULATED
- the eye keeps its own `StandardMaterial3D` through a faction repaint
- a fitted weapon points where the frame faces (`dot > 0.9`), not backwards
- `flak` is lethal against a 90-hull target and poor against a 400-hull one,
  measured rather than asserted — the discrimination IS the counter-pick

## 8. Open

- `cost` is a guess. The economy audit (`tools/audit_economy.gd`) should price
  it once it exists.
- Whether the dish should rotate independently of the pods. Cheap to add later;
  not modelled now.
