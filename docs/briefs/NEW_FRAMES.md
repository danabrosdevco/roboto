# Brief — ten new frames

Written 2026-10-10 by GAMEPLAY. Status: **brief complete, build started**.

Ten chassis, following the process the Bulwark went through: concept art first,
then one frame built end to end — scene, script, chassis definition, catalogue,
livery, CSG bake and a test suite — before the next one starts.

---

## 1. What exists, and what it leaves out

| frame | supply | hull | role |
|---|---|---|---|
| soldier | 1 | 60 | modular infantry |
| mechanic | 1 | 60 | medic |
| rover | 2 | 180 | fast light armour |
| reclaimer | 2 | 150 | support vehicle, medic or light mortar |
| spotter | 1 | 80 | aerial sensors, **no weapon** |
| walker | 3 | 320 | two mounts, firepower platform |
| bulwark | 3 | 400 | one mount and a shield, assault |

Enemy: quadcopter bomber, leaper/hopper, chaser, nest, watcher, marksman,
mortar track, helicopter.

**Six holes, and they are what the ten below are for.**

1. **No supply-1 vehicle.** The jump from a 1-supply soldier to a 2-supply
   rover is the biggest step on the sheet and there is nothing in it.
2. **No PLAYER aerial that fights.** The Spotter has `weapon_slots = 0`.
   Every flying thing the player owns is a camera. (The enemy bomber already
   has `weapon_slots = 1` — and it IS the "helicopter": one unit, id
   `gunship`, display name "Quadcopter Bomber". The brief first listed them
   as two.)
3. **~~Nothing counters air.~~ CORRECTED — the opposite is true, and it is
   worse.** This was the headline of the gap analysis and it was false.
   `gun_max_pitch_degrees` only rotates `gun_pivot` — the MODEL. The firing
   gate throws elevation away (`walker.gd:243`, `to.y = 0.0`), the damage ray
   is full 3D with no collision mask (`ai_weapon.gd:441`), and infantry have
   no pitch at all (`enemy.gd:2831`, `face_dir.y = 0.0`). **A rifleman will
   shoot straight up.** Everything in the game can already hit anything
   overhead.
   The real gap is the inverse: there is NO MECHANISM THAT DENIES A HIGH
   SHOT. Aerials are hard to hit only by accident — a 0.5 m collider at 22 m,
   with range-proportional spread doing the rest. The whole air game is a
   side effect, which is why nothing in it reads as a decision.
4. **Nothing resupplies.** Ammunition is a real system — `ammo_type`,
   magazines, reloads — and a squad that runs dry stays dry.
5. **No player-side terrain shaping.** Mines exist as items; nothing is built
   around placing them.
6. **No weapon that attacks signal.** Suppression, EMP, `signal_resistance`
   and the contact ledger all shipped today, and the only things that use them
   are a grenade and the side effect of ordinary gunfire.

## 2. The new weapon class: EMITTER — and how it is actually built

The three classes today are **infantry**, **turret** and **articulated arm**.
**EMITTER** is the fourth: a mast or dish projecting a continuous FIELD rather
than firing rounds. No ammunition, no reload — a duty cycle instead. No
projectile, so nothing to dodge and nothing to block: a shield stops rounds, it
does not stop a field. And it acts on `signal_integrity`, not health, so it
never kills anything.

That last point is what makes it a class and not a gun. Every other weapon
answers "how fast does this remove hit points". An emitter answers "how much of
the enemy's ability to fight does this take away" — a question the codebase can
now express and nothing yet asks. It also makes a frame genuinely non-lethal,
which no frame is today.

### It is NOT a fourth `ItemDefinition.Kind`

That was the first instinct and the research killed it. **In this codebase a
mount class is a `ChassisDefinition` concept, not an item one.**
`ui_kit.mount_class()` already derives "TURRET / INFANTRY / ARTICULATED ARM"
from the FRAME — from `turret`, `weapon_replaces_built_in`, `built_in` and
`weapon_slots` — and the comment there argues the case explicitly: read it off
the frame rather than add a flag to the item.

A fourth `Kind` would cost a fourth id array in `SoldierRecord` (plus its
resize, its `to_dict`/`from_dict`, `all_fitted_ids` and `recover_kit`), a
fourth arm in `_slots_for`, a fourth entry in `holds_elsewhere`, a fourth shop
shelf, a fourth slot row, a fourth enemy-loadout pool — and leave four silent
holes behind, of which the sharpest is that
`ChassisDefinition.takes()` gates turret exclusivity on `kind == WEAPON`, so a
non-WEAPON emitter would bypass the whitelist and bolt onto a Rover.

**So: the emitter is a WEAPON-kind item whose `ai_scene` is an `AIWeapon`
subclass that never fires, on a frame with `turret = false`,
`weapon_replaces_built_in = true` and `built_in = "MAST"`.** That reuses the
Reclaimer's articulated-arm path wholesale and reduces the change to about
three additions to vocabulary tables. The precedent is already shipped: the
repair lance is `kind = 0` — a channelled healing tool that occupies a weapon
mount. **The existing line is drawn at which slot it occupies, not at whether
it kills.**

Six AI call sites then need overriding on the mast, because they all assume a
gun: `sustained_dps()` must return 0.0 or the target-saturation ledger will
believe something is being killed and wave other robots off it; `_max_range()`
wants the field radius so standoff and `_is_outranged` make sense;
`infinite_ammo = true` stops the reload loop parking the state machine; and
the frame subclass no-ops `handle_weapon_logic` / `roll_combat_action` the way
the Spotter and the Mechanic already do.

The effect itself is one new static next to `AIWeapon.suppress_along` —
`suppress_in_radius(tree, centre, radius, rate * delta, source, faction)` —
which is `emp_blast.gd`'s distance sweep with `lerpf` falloff, floored at
`SIGNAL_CRITICAL` the way `squad_commander._lean_on_squad` already floors its
own drain. **It must be floored**: `spotter_drone._enter_ekill` calls `die()`,
so an emitter that e-kills is an anti-air weapon whether or not that was the
intent.

## 3. The ten

Seven buyable, three enemy-only. Supply 1 to 3. Two aerial among the new
buyable frames, three counting the enemy carrier.

### Buyable

**1. SAPPER — supply 1, hull 55, infantry**
Cheap engineer. Carries an infantry weapon and the mine items that already
exist, and is the only frame that can place them deliberately rather than
drop them. Distinct from the Mechanic, which repairs: this one *shapes the
ground*. The gameplay is pre-committing to where a fight happens.

**2. LANCE — supply 1, hull 110, wheeled**
The missing cheap vehicle. Fast, fixed forward gun — **no turret**, so it has
to point its whole body, which is the Rover's counter turned into a chassis
trait. A technical. Dies to anything that gets a bead on it and gets places
nothing else can reach in time.
*New weapon:* `light_cannon`, a fixed-mount single-shot gun.

**3. KITE — supply 2, hull 90, AERIAL, armed**
The first flying thing the player owns that shoots. Hovers, carries one turret
mount, and is made of paper. Its whole proposition is **angle**: it attacks
from where ground frames cannot elevate to, which is exactly the hole the
Picket below exists to close. The two of them are a rock-paper-scissors pair
shipped together on purpose.

**4. PICKET — supply 2, hull 140, ground, ANTI-AIR**
`gun_max_pitch_degrees` near vertical and a sensor tuned upward. Hard-counters
the Kite, the quadcopter bomber, the helicopter and the Broodcarrier. Weak
against ground, so it is a frame you bring *because of what you expect to
meet* — the first such frame in the roster.
*New weapon:* `flak`, high elevation, airburst, poor against armour.

**5. WARDEN — supply 2, hull 160, EMITTER platform**
Carries the new class. A mast projecting a jamming field that degrades the
signal of everything hostile inside a radius, continuously, with no rounds and
no line of fire. Pairs with everything built today: suppressed robots aim
worse, lose sensor range, stutter, and at the floor stop entirely.
Non-lethal — it needs a squad around it to mean anything.
*New weapon:* `jammer_mast` (EMITTER).

**6. DRAYMAN — supply 2, hull 170, support vehicle, Reclaimer lineage**
Resupplies ammunition in the field from an articulated arm. Nothing does this
today, and a long mission currently ends when the belt-fed guns run out rather
than when the squad dies. Turns ammunition from a countdown into a logistics
decision.
*New weapon:* `supply_boom` (articulated arm).

**7. VESSEL — supply 3, hull 260, carrier**
Carries two Hatchlings and releases them mid-mission: a mobile, friendly
version of the enemy Nest. Deliberately **not** more firepower than the Walker
or Bulwark — those two already shred their class, and the answer to "what is
above them" is not a bigger gun but a frame that changes how many bodies are
on the field.

### Enemy only

**8. SWARM — BROODCARRIER (amber, supply 2, hull 200, AERIAL)**
A flying hive. Spawns Hoppers continuously until killed, and keeps moving, so
the Nest's counter — walk over and break it — does not apply. Swarm is swarm:
this is the frame that makes that true rather than stated.

**9. STRATCOM — BASTION (institutional green, supply 3, hull 300)**
Walks, then plants and becomes a hardpoint: immobile, heavily armoured, and
projecting a protective field over nearby StratCom units. The institutional
army answer — doctrine, position, combined arms. It is also the mirror of the
Warden, and the first enemy that rewards killing a *support* unit first.

**10. ARGUS — SEE-ENGINE (tyrian, supply 3, hull 240)**
Argus is a command intelligence, so its frame commands. While it lives, every
Argus unit in range gets tightened aim and shares its contacts — straight
through the contact ledger built today. It barely fights. Kill it and the
formation it was running degrades visibly, which makes it the first enemy
whose threat is legible *and* whose counter is obvious without being easy.

## 4. Supply spread

| supply | frames |
|---|---|
| 1 | Sapper, Lance |
| 2 | Kite, Picket, Warden, Drayman, Broodcarrier |
| 3 | Vessel, Bastion, See-Engine |

## 5. New weapons

| id | class | goes on | note |
|---|---|---|---|
| `light_cannon` | turret (fixed) | Lance | no traverse; the chassis aims |
| `flak` | turret | Picket | near-vertical elevation, airburst |
| `jammer_mast` | **emitter** | Warden | signal damage in a radius, no rounds |
| `shield_projector` | **emitter** | Bastion | the inverse: raises allied resistance |
| `supply_boom` | arm | Drayman | refills magazines |

## 6. Order of work

Concept art for all ten first, in one sheet, the way the Bulwark pass did it —
silhouettes answer "is this distinct" faster than anything else and that is
requirement one. Then build in this order, each complete before the next:

1. **Picket** — closes the worst hole (nothing counters air) and needs only an
   existing weapon class.
2. **Warden** — proves the EMITTER class, which five other things depend on.
3. **Kite** — the Picket's counterpart; aerial movement is new and wants doing
   while the Picket is fresh.
4. **Lance**, **Sapper** — cheap, and they fill the supply-1 gap.
5. **Drayman**, **Vessel**.
6. **Broodcarrier**, **Bastion**, **See-Engine** — the enemy three last,
   because each reuses a system proven by one of the above.

## 7. What the research found

Three read-only sweeps were run before any building started. The faction one
came back first and it changes the order of work.

### Adding the three enemy factions: MEDIUM, and one thing must come first

**Free, which was the surprise.** No faction value reaches `campaign.json` —
`CampaignState.to_dict` and `SoldierRecord.to_dict` were read field by field
and neither carries one; the player squad's ALLIED is re-derived at spawn
(`soldier_record.gd:375`). The faction int IS on disk in 805 places, all
`EnemySquadSpec` sub-resources across 30 mission files — and every single one
of them is `1`. So appending is a literal no-op for all of them. Reordering
would silently repoint every hostile in 27 missions, which is the append-only
rule earning its keep again.

**Also free: missions can already name a faction.** `EnemySquadSpec.faction`
is an existing export (`enemy_squad_spec.gd:103`) and
`enemy_force_spawner.gd:270` already does `soldier.faction = spec.faction`.
Writing `faction = 4` in a mission would spawn a Swarm squad the day the enum
value exists. No schema change, no new spawner.

**THE BLOCKER: `are_hostile()` has no `_:` arm.** `Managers/enums.gd:29-38`
matches on four values and falls out to `return false`. The instant SWARM,
STRATCOM or ARGUS exists, a robot carrying one is both invisible and
near-invulnerable, in every direction, silently:

- nobody targets it (`ai_manager.gd:365`) and it targets nobody
- it refuses to fire — `_is_friendly` says everything is friendly, so
  `friendly_in_line` blocks its own shot (`ai_weapon.gd:320`)
- the player's rounds hit it for `friendly_fire_multiplier`
  (`hud_weapon_template.gd:333`), and blasts likewise (`explosion.gd:141`)
- mines never arm on it (`mine.gd:179`); EMP skips it (`emp_blast.gd:107`)
- its tracers render in the FRIENDLY colour (`tracer.gd:66`)
- **the player can repair it** (`player_repair_tool.gd:451`) **and possess it**
  (`possession.gd:105`)
- the pre-deploy purge leaves it standing (`enemy_force_spawner.gd:963`)
- an eliminate objective will not count it (`eliminate_objective.gd:59`)
- analytics logs killing one as friendly fire (`analytics.gd:584`)

Thirty-five call sites, not one of which errors when the answer is wrong.
GDScript does not warn on a non-exhaustive enum match, so the append compiles
clean and presents at runtime as "the new enemies just stand there".

**So the order changes.** Before any enemy frame: rewrite `are_hostile` as a
TABLE rather than a match, with a test that asserts every pair in both
directions — including the pairs that do not exist yet, so the next append
cannot repeat this. That is now task zero of the enemy three.

Two further notes from the same sweep. Inter-faction hostility cannot be
expressed in `are_hostile` at all — it is pure and stateless, so "Swarm and
StratCom fight each other in mission A but not B" has nowhere to live and
would need the table to be mission-aware. And if the three ARE made mutually
hostile, `hostiles_for()` and `activation_sources()` start listing enemies as
each other's activation sources, so hostile forces keep each other awake and
the distance cull stops culling. **Recommendation: the three are hostile to
the player and to each other's targets, but NOT to each other.** It costs
nothing, avoids the cull problem, and nothing in the game yet asks to see two
enemy factions fight.

Everything else is mechanical: three entries in `faction_livery.gd`'s COLORS
dictionary (it is a Dictionary with a `.get` fallback, not a fixed array),
three match arms in `hud_palette.gd:73` (which already has a default, so the
failure is "all three render Swarm amber" rather than a crash), two hardcoded
`== ENEMY` comparisons (`ai_manager.gd:497`, `squad_commander.gd:756`), one
hardcoded `[ALLIED, ENEMY]` list in the debug overlay, and three `FRAMES`
entries in `kill_kinds.gd`.

One thing to get right first time: `kills_by_kind` keys are persisted and read
back through a rename table, and `kill_kinds.gd:21` records that the
quadcopter is still called `gunship` because renaming it would orphan every
tally written so far. **The three new frame ids are permanent the day the
first kill is saved.**

### Aerial: the gap analysis was wrong, and the real finding is better

**Verified first-hand after the report came in**, because it contradicts the
headline of §1:

- `walker.gd:224` clamps `want_pitch` — and writes it to `gun_pivot.rotation.x`.
  That is the model.
- `walker.gd:243` `to.y = 0.0` in `_weapon_on_target`. **The fire gate throws
  elevation away.**
- `ai_weapon.gd:441` builds the damage ray with `exclude` only. **No collision
  mask, full 3D, 250 m.**
- `enemy.gd:2831` `face_dir.y = 0.0`. Infantry facing is yaw only — **a
  rifleman's muzzle ray goes straight up with nothing to stop it.**

So `gun_max_pitch_degrees` is cosmetic and everything in the game can already
engage anything overhead. The frame that "closes the hole" has no hole to
close.

**What is actually missing is the opposite, and it is the more interesting
problem.** There is no mechanism that DENIES a high shot. Aerials survive by
accident — a 0.5 m collider at 22 m with range-proportional spread doing the
work — which is why nothing about the air game reads as a decision. Making air
matter needs BOTH halves: a real elevation gate in `_weapon_on_target`, so most
frames genuinely cannot reach up, AND a frame exempt from it.

**That is a change to every existing unit, so it is the user's call before it
is built.** It is also what turns the Picket from a redundant frame into a
rock-paper-scissors piece.

Three further things an armed aerial has to solve, all verified in the report:

1. **`_aim_tracking` can never settle on something that always moves.**
   `enemy.gd:2895` — `hull_spoils_aim` is excused by a node property literally
   named `turret` being non-null, NOT by `ChassisDefinition.turret`. A flying
   frame without an exported `turret: Node3D` never leaves `WeaponState.AIM`.
2. **The flyers stub the whole weapon loop.** `handle_weapon_logic`,
   `roll_combat_action` and `_update_facing` are all `pass` on the Spotter and
   the bomber. Restoring them is the bulk of the new code.
3. **The squad leash fights flyers.** `_enforce_leash` measures 3D and does not
   consult `slot_tolerance`, so anything 22 m up is permanently outside and is
   recalled every frame. The Spotter survives this by accident; a frame meant
   to manoeuvre in combat will fight it.

Also corrected: the bomber and the "helicopter" are one unit, and there is a
third flight model — the Diver — whose steering is genuinely 3D (rotating about
an arbitrary axis rather than UP) and is the right primitive if climb and dive
are to be combat manoeuvres rather than cosmetics.

### Emitter: do not add a fourth Kind

Covered in §2. The short version: mount class is a `ChassisDefinition` concept
here, not an `ItemDefinition` one, and the repair lance already proves a
weapon-slot item need not kill. A fourth `Kind` would cost eight real edits and
leave four silent holes; the biggest is that `ChassisDefinition.takes()` gates
turret exclusivity on `kind == WEAPON`, so a non-WEAPON emitter would bypass
the whitelist entirely.
