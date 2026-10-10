# WARDEN — design document

Supply 2 · ground · **emitter platform** · **status: concept selected, not built**

---

## 1. Concept

**Selected: A — THE MAST.** 1.97 W x 6.68 H x 2.24 L.

A telescoping column rising off a Walker-sized hull, crowned with a bulb, six
down-swept radials, and a ring of free-floating nodes round the head.

**Two corrections from building it, both found by measuring rather than by
looking.** The prose above said *four* radials; `ConceptsB.warden_a()` builds
**six**, and six is what was rendered and what was chosen — the prose was
wrong, not the code.

And **the floating ring was a bug that turned out to be worth keeping.** Each
rib's terminal bead is drawn at the rod's outer tip, but the rod carried a
`+125°` tilt where it needed `−125°`: in Godot a rotation about +X sends local
+Y to `(0, cos θ, sin θ)`, so +125° gives `(0, −0.574, +0.819)` — down and
*inboard*, not down and outward, and the concept's own comment asserts the
opposite sign. The rods therefore swept the wrong way and every bead hung
0.57 m clear of the rod it belonged to. That is what "a loose ring of
unattached nodes" was describing. It reads well enough that the model keeps
it **deliberately**: the rods are built at −125° so they attach, and the halo
is six separate spheres interleaved between them. Section 1 now lists two
features because there genuinely are two.

**It is the only one of the four that radiates rather than aims.** The field is
a radius, and a silhouette that promises a direction is a silhouette that lies
about the mechanic — the player would spend the first fight trying to point it
at something. The crown's radials and the floating node ring say *outward, all
ways*, and at icon size the column reads as a single vertical stroke with a
blob on it, which nothing else in the roster does.

**Its height is the problem and also the answer.** At 6.68 m it is three
Walkers tall and will catch on every bridge deck and doorway in the game. The
resolution is that the mast **telescopes**: stowed while moving, raised while
emitting. That makes the frame's most important state readable from any angle
and at any distance, exactly as the Bastion's planted state must be — which is
right, because the Bastion is this frame's opposite number and the two should
rhyme. Stowed should be about 2.6 m and raised about 4.5 m, not 6.7. See
section 8.

The other three: **B DISH** is the clearest "this projects something" on the
sheet and was the close second, but a dish is a *beam*, and this weapon has no
facing. **D CAGE** — an open frame of energised rods with ball-tipped nodes —
is the most literal reading of the art brief and the most distinct shape here,
but an open lattice at 40 pixels is a grey smudge, and this frame has to be
identifiable in a squad list. **C COIL CART** stacks concentric hoops on a
wheeled bed; it reads as a Tesla cart, which is charming and is also the one
thing the brief ruled out — it is a radio van.

Art brief: must say "this projects something" and must **not** read as a gun or
a radio van. A mast, a dish, a coil, a frame of rods — something energised.
Nothing on it should resemble a barrel: it is the only non-lethal frame in the
game and should look like it.

## 2. What it is for

Suppression, EMP, `signal_resistance` and the contact ledger all exist, and the
only things that drive them are a grenade and the side effect of ordinary
gunfire. There is no frame whose *job* is the signal layer.

The Warden carries the game's first **EMITTER**: a mast projecting a continuous
jamming field that degrades enemy signal inside a radius. No ammunition, no
projectile, no line of fire. A shield stops rounds; it does not stop a field.

It kills nothing. That is the point — it is the first frame that is purely a
force multiplier, and a squad built around one has to be a squad.

**What a degraded enemy actually suffers**, from the existing ladder
(`ai.gd:44-52`): FUZZED 0.85 costs accuracy, DEGRADED 0.62 halves sensors and
stutters movement, CRITICAL 0.38 makes it ignore squad orders, EKILL 0.12 stops
it. The Warden's field should reach DEGRADED on anything standing in it and
**must not reach EKILL** — see §6.

## 3. Stats

| field | value | why |
|---|---|---|
| `id` | `&"warden"` | permanent once a kill is saved |
| `supply` | 2 | |
| `cost` | 230 | |
| `base_health` | 160 | it has to survive being the priority target |
| `base_speed` | 0.9 | |
| `base_sensor_range` | 55 | it needs to know what is in its own field |
| `weapon_slots` | 1 | occupied by the mast |
| `starting_weapon_id` | `&"jammer_mast"` | new, §4 |
| `turret` | **false** | so the whitelist rule does not apply, §4 |
| `weapon_replaces_built_in` | true | |
| `built_in` | `"MAST"` | **this is the new mount class** |
| `vehicle` | true | |
| `drives` | false | |
| `equipment_slots` | 1 | |
| `module_slots` | 2 | |
| `required_rank` | 3 | |

## 4. New weapon — `jammer_mast`, and the EMITTER class

**The emitter is NOT a fourth `ItemDefinition.Kind`.** Research was explicit
and the reasoning is in `docs/briefs/NEW_FRAMES.md` section 2. In this codebase
a mount class is a `ChassisDefinition` concept — `ui_kit.mount_class()` already
derives "TURRET / INFANTRY / ARTICULATED ARM" from the *frame*, not from a flag
on the item. A fourth `Kind` would cost a fourth id array in `SoldierRecord`
(plus resize, `to_dict`/`from_dict`, `all_fitted_ids`, `recover_kit`), a fourth
arm in `_slots_for`, a fourth entry in `holds_elsewhere`, a fourth shop shelf,
a fourth slot row and a fourth enemy-loadout pool — and leave four silent holes
behind.

The precedent is already shipped: **`item_repair_lance.tres` is `kind = 0`** —
a channelled healing tool occupying a weapon mount. The line in this codebase
is drawn at *which slot it occupies*, not at *whether it kills*.

| field | value |
|---|---|
| kind | **0 (WEAPON)** |
| `fits_vehicles` | true |
| `usable_by_player` | false |
| `base_damage` | 0 |
| `ai_scene` | an `AIWeapon` subclass that never fires, see section 6 |
| field radius | 18 m |
| drain | ~0.09 signal/second at the centre, falling to ~0.02 at the edge |
| floor | stops at `SIGNAL_CRITICAL` — never e-kills |

**The drain has to beat recovery.** `signal_recovery_rate` is 0.04/s and is
divided by nothing, while incoming drain is divided by the target's
`signal_resistance`. A field under 0.04 times resistance per second makes no
net progress at all. 0.09 at the centre gives real pressure against resistance
1.0 and visible-but-survivable pressure against a Bulwark's 2.4.

The new mount class costs roughly three vocabulary additions:
`ui_kit.mount_class()`, the slot heading in `squad_page.gd`, and the mount line
in `factory_page.gd`.

## 5. Model

New scene from `tools/build_warden.gd`; script `warden.gd`, extending `Soldier`
or `Walker` depending on whether it has legs (the concept decides).

```
Warden (CharacterBody3D, groups=["enemies"])   <- add_to_group("enemies", TRUE)
+- CollisionShape3D
+- Bark / NavigationAgent3D / Detection
+- Rig
|  +- Hull (CSGMesh3D)
|  +- Head: ONE eye, own StandardMaterial3D, NOT in livery
|  +- MastMount   <- the WeaponMount equivalent; the mast scene parents here
+- SparkBurst / OilSpray
+- FactionLivery  (TYPED Array[Node3D], eye excluded)
```

Plus the five silent traps: typed node-path exports, `add_to_group(.., true)`,
typed `Array[Node3D]`, `WeaponMount` yaw **+90 degrees**, and the `turret`-node
rule in `hull_spoils_aim`. The Warden has no turret node and never fires, so
the last one is harmless here, but the mount still needs the correct yaw in
case a conventional weapon is ever fitted to it.

## 6. Code requirements

**Nothing in `Enemy` or `Soldier`.** Three new pieces, all additive:

**1. `AIWeapon.suppress_in_radius()` — one new static.**
Next to the existing `suppress_along`. It is `emp_blast.gd`'s distance sweep
over `AI.SIGNAL_GROUP` with `lerpf` falloff, plus a floor:

```
suppress_in_radius(tree, centre, radius, rate * delta, source, faction, floor)
```

**It must be floored**, and this is not a nicety:
`spotter_drone._enter_ekill` calls `die()`. An emitter that reaches EKILL is an
anti-air weapon whether or not that was the intent, and would delete the
player's own Spotter if the field ever overlapped it. `squad_commander`'s
`_lean_on_squad` already floors its own drain at `SIGNAL_CRITICAL` for exactly
this reason — copy that.

**2. `EmitterMast extends AIWeapon`** — the mast node. Overrides, each because
a specific call site assumes a gun:

| override | why |
|---|---|
| `sustained_dps() -> 0.0` | else the target-saturation ledger believes something is being killed and waves other robots off it |
| `_max_range() -> field radius` | so `engage_standoff` and `_is_outranged` mean something |
| `infinite_ammo = true` | else `needs_reload()` parks the state machine in RELOAD forever |
| `fire()` -> no-op | |

Its `_physics_process` is the whole weapon: one call to
`suppress_in_radius(..., rate * delta, ...)`.

**3. `warden.gd` no-ops `handle_weapon_logic` and `roll_combat_action`** —
exactly as `spotter_drone.gd` and `mechanic.gd` already do. There is nothing to
aim and nothing to fire, so the combat roll has no business running.

**Known gap, logged not solved:** no AI anywhere knows it is standing in a
field. `EquipmentContext` has `threat_bearing` and `under_fire_seconds` and
nothing for "I am being jammed", so **no robot will ever walk out of one**.
Worse, `_score_combat_option` reads `pinned = signal_integrity < SIGNAL_FUZZED`
and makes a suppressed robot *less* willing to move. The field is therefore
strictly stronger against AI than it would be against a human, which is a
balance fact to know before tuning the radius.

## 7. Tests

`tools/test_warden.gd`:

- registered, catalogue, supply 2, `built_in = "MAST"`, `turret = false`
- `jammer_mast` exists, is `kind = 0`, and **`sustained_dps()` returns 0.0** —
  the assertion that protects the targeting ledger
- a hostile inside the radius loses signal over time; one outside does not
- **it never reaches EKILL**, asserted by running a target to the floor and
  checking `get_signal_state() != EKILL` — the Spotter-deleting case
- an ALLIED frame in the radius is unaffected
- the drain beats `signal_recovery_rate` at the centre and does **not** at the
  edge, measured — that is the field's whole shape
- in `"enemies"` and `AI.SIGNAL_GROUP`; typed arrays populated; eye survives a
  repaint
- the frame never enters a firing state

## 8. Open

- Radius 18 m and 0.09/s are first guesses. The only honest way to set them is
  to watch a fight.
- Whether the field should be visible. An invisible area effect the enemy
  cannot react to and the player cannot see is a bad deal for both; some ground
  decal or shimmer is probably required, and is not designed here.
- **The telescoping mast, from section 1.** Stowed ~2.6 m, raised ~4.5 m. The
  rendered concept is 6.68 m tall and that number must not survive into the
  build — it is taller than anything in the game and will catch on level
  geometry. Raising and stowing is also the cheapest way to make the field's
  on/off state visible, which section 8 already wants.
- Whether the mast should stow automatically on the move, or be an order. An
  order is more interesting and is one more thing to teach.
