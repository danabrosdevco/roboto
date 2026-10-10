# SEE-ENGINE — integration brief

Argus · supply 3 · ground · command node · enemy only ·
**model built, nothing registered**

Written for a builder. The map is `docs/briefs/FRAME_ANATOMY.md`; this document
cites it by section instead of restating it. Everything else carries a
`file:line`.

**What exists today:** `Character/characters/ai/see_engine.tscn` — root node
`SeeEngine`, a `CharacterBody3D` with `groups=["enemies"]`
(`see_engine.tscn:218`), root script `walker.gd`, `sensor_range = 110.0`
(`see_engine.tscn:306`), `turret` wired to `Rig/GimbalYaw` and `gun_pivot` to
`Rig/GimbalYaw/LensPitch` — and `tools/build_see_engine.gd`. There is no
`ChassisDefinition`, no `kill_kinds` entry, no `see_engine.gd`, and no
`Enums.Factions.ARGUS` for it to belong to.

> ### Prerequisite — read `docs/integration/BROODCARRIER.md` §0 first
>
> `Managers/enums.gd`'s `are_hostile()` has no default arm. Appending a faction
> value without rewriting it as a table gives you a robot that is
> simultaneously invisible and near-invulnerable, in both directions, across
> thirty-five call sites, not one of which errors.
>
> That section carries the verification, the replacement code, the mechanical
> appends in `faction_livery.gd` / `hud_palette.gd` / `squad_commander.gd` /
> `ai_manager.gd`, and the `tools/test_factions.gd` assertions. **It is step 1
> of this frame's order of work.** It matters more here than for either of the
> other two, because this frame's entire effect is keyed on its own `faction`
> (§1) — an ARGUS See-Engine on today's `enums.gd` would write contacts into a
> table nothing reads and the frame would be indistinguishable from scenery.

---

## 1. The §6.2 question, answered: **cheap effect, medium frame**

`docs/frames/SEE_ENGINE.md` §6.2 and §8 say this is the single question that
decides the frame's cost, and to check it before anything else. I checked it.
The answer has three parts and only the first one is the one the doc expected.

### 1.1 The aim bonus is genuinely free — zero new code

`Enemy.get_aim_spread_multiplier()` (`enemy.gd:3246-3261`) ends with:

```gdscript
	if _contact_assisted():
		mult *= SPOTTED_SPREAD
	return mult
```

`SPOTTED_SPREAD` is `0.82` (`enemy.gd:5266` — below 1.0 because the function
returns *spread*, so smaller is tighter). `_contact_assisted()`
(`enemy.gd:5269-5276`) is:

```gdscript
func _contact_assisted() -> bool:
	if ai_manager == null or combat_target == null or not is_instance_valid(combat_target):
		return false
	if Settings.debug_tools_enabled():
		if not bool(Settings.get_value("debug.contact_accuracy")):
			return false
	return ai_manager.is_fresh(faction, combat_target)
```

**It is already faction-scoped, on the shooter's own faction.** So the moment
anything writes an ARGUS contact for a body, *every* ARGUS robot shooting at
that body shoots 18% tighter, with no new accuracy term, no radius, no
registration and nothing to recompute. `AIManager.is_fresh`
(`ai_manager.gd:314-318`) is a dictionary lookup against
`contact_fresh_seconds = 3.0` (`ai_manager.gd:201`), and `note_seen`
(`ai_manager.gd:260-266`) is O(1). **The doc's §6.2 hope is correct and the
fallback it describes — "an explicit accuracy bonus applied to same-faction
units in radius" — should not be built.**

Two bonuses fall out of this for free, and both are worth knowing:

- **"a SWARM or STRATCOM unit does NOT benefit" is structural, not something
  you implement.** `_contacts` is keyed by faction (`ai_manager.gd:197`,
  `_contacts_for` at 218-221), so a Swarm robot asking `is_fresh(SWARM, x)`
  reads a different table. The §6 assertion is testing a property of the ledger,
  not of this frame.
- **the Bastion's "ally means same faction, not not-hostile" trap does not
  exist here.** There is no filter to get wrong.

### 1.2 But the *seeing* is not free, and `sensor_range = 110` does nothing for it

This is the part the design doc gets wrong, and it is the whole cost of the
frame.

`grep -rn "note_seen" --include=*.gd` over the main checkout returns **two**
call sites in game code:

- `Character/characters/ai/enemy.gd:5136`, inside
  `_on_detection_body_entered` (declared at 5103) — the **Detection `Area3D`**
  callback;
- `Character/characters/ai/enemy.gd:4884`, in the `ENEMY_SPOTTED` stimulus
  handler, re-broadcasting a squadmate's callout into the receiver's own table.

**`_tick_vision` — the function `sensor_range` actually drives — never calls
`note_seen`.** `sight_range()` is `maxf(4.0, sensor_range + sensor_bonus)`
(`enemy.gd:910-911`) and `_tick_vision` (929-1027) uses it for the cone, the
awareness ramp and the LOS shortlist, and ends by calling `trigger_combat` or
`change_combat_target` (1021-1027). No contact is written. `trigger_combat`
(`enemy.gd:5155`) does not write one either.

So the only thing that writes a contact for a frame's own eyes is the
**Detection `Area3D`**, and `build_see_engine.gd:365` gives this frame a sphere
of **25.0 m** — the same radius every other robot has
(`build_brood.gd:342`, `build_bastion.gd:427`, `spotter_drone.tscn:17`). Note
also that `detection_radius = 20.0` on the root (`see_engine.tscn:304`) is *not*
that area's radius: it is only read by `get_effective_detection_radius()`
(`enemy.gd:5040-5046`) as the signal-degradation gate at `enemy.gd:5128`.

**Consequence, stated plainly: a See-Engine built today, with the highest
sensor range in the game, contributes contacts over 25 m like everything else.
Its headline stat is decorative for its headline effect.**

This is not only this frame's problem — `chassis_spotter.tres`'s own
description says the Spotter sees "roughly twice as far as anything on the
ground — and everyone fights on what it finds", and on the same trace the
Spotter's 90 m sensor does not feed the contact table either. **I am reporting
that as a separate finding and not fixing it here.** It is arguably a bug in
the Spotter, it is definitely a one-line claim in a shipped item description
that the code does not support, and changing `_tick_vision` to call `note_seen`
would alter the accuracy of every robot in the game. Not this frame's change.

**What this frame needs is one function.** `see_engine.gd` ticks on an interval
and calls `note_seen` for everything it can actually see:

```gdscript
## WHAT MAKES THIS FRAME A FRAME. The contact ledger and the aim bonus both
## already exist (AIManager.note_seen/is_fresh, Enemy._contact_assisted) — what
## does NOT exist is anything that feeds the ledger from a robot's SENSOR
## RANGE. _tick_vision() (enemy.gd:929) is the function sensor_range drives and
## it never calls note_seen; the only self-sighting that does is the Detection
## Area3D callback (enemy.gd:5136), a 25 m sphere. So a 110 m sensor buys this
## frame nothing at all without these twenty lines.
func _tick_watch(delta: float) -> void:
	_watch_timer -= delta
	if _watch_timer > 0.0:
		return
	# WELL UNDER AIManager.contact_fresh_seconds (3.0, ai_manager.gd:201), or
	# the contacts this frame is holding open flicker stale between sweeps and
	# the formation's aim bonus comes and goes.
	_watch_timer = watch_interval
	if ai_manager == null or not alive or get_signal_state() == SignalState.EKILL:
		return
	var eyes_at: Vector3 = global_position + Vector3.UP * 0.9
	for h in ai_manager.get_hostiles_in_radius(self, sensor_range):
		if h == null or not is_instance_valid(h) or not (h is Node3D):
			continue
		# IT HAS TO ACTUALLY SEE IT. Without this the frame feeds the whole
		# formation contacts through terrain, which is a wallhack, not a sensor.
		if not is_path_clear(eyes_at, (h as Node3D).global_position, h):
			continue
		ai_manager.note_seen(faction, h)
```

Everything it calls exists: `AIManager.get_hostiles_in_radius(requesting_ai,
radius)` at `ai_manager.gd:501-520` (and it already filters by
`Enums.are_hostile`, which is **the fourth reason §0 comes first** — on today's
`enums.gd` this returns an empty array for an ARGUS caller),
`Enemy.is_path_clear` at `enemy.gd:5062`, `AIManager.note_seen` at
`ai_manager.gd:260`. `_threat_actor()` (`enemy.gd:5514`) is the shipped
precedent for calling `get_hostiles_in_radius` with `sensor_range`.

**Cost of that function: watch it.** `get_hostiles_in_radius` walks `all_ai`
with no cache (`ai_manager.gd:511-518`) — unlike `hostiles_for`, which caches
per faction for 0.4 s (`ai_manager.gd:117`, `358-374`). At 110 m on a
186-hostile level that is a full list walk plus up to N raycasts per sweep.
`watch_interval` at 1.0 s is the starting point and §7 step 5 measures it.
`MEMORY.md`: measure CPU, not wall clock, and pace the loop with
`Engine.max_fps = 60`.

**The tempting shortcut, and why not to take it.** Enlarging the Detection
`Area3D` to 110 m needs no script at all. Do not: `_on_detection_body_entered`
(`enemy.gd:5103-5145`) also calls `trigger_combat(body)` and emits
`ENEMY_SPOTTED`, so a 110 m detection sphere makes a weaponless command node
charge into every fight on the map, and a 110 m radius physics area on a
186-body level is a real broadphase cost. The callback is an acquisition path,
not a sensor.

### 1.3 And the *legibility* is not free either — this is the real cost

`docs/frames/SEE_ENGINE.md` §6.3 says killing it must visibly degrade the
formation or the player never learns the rule, and names "the existing
suppression VFX and the HUD's contact brackets" as the obvious hooks.
**The contact brackets are not available.** `Character/hud/hud.gd:70-72`:

```gdscript
func _on_contact_seen(faction, body: Node) -> void:
	# Only your side's sightings. The enemy's contact table is their business.
	if int(faction) != int(Enums.Factions.ALLIED):
		return
```

The `AIManager.contact_seen` signal (`ai_manager.gd:257`) is the only consumer
path to the screen, `hud.gd:56` is the only connection, and it filters to
ALLIED. The one other reader of an enemy contact table is
`Character/hud/contact_overlay.gd:62`, which is a debug panel and hardcodes
`[ALLIED, ENEMY]`.

**So today there is no player-facing readout of an enemy faction's contact
freshness, and the effect itself is an 18% spread multiplier.** A player cannot
perceive 0.82 on a spread cone. Killing the See-Engine would change nothing
they can see, which by the design doc's own standard — *"If the player cannot
see the difference, the unit does not exist"* — means the unit does not exist.

This is the same failure that killed two frames this week.
`git show c7178bf7` on the Warden: *"nothing can leave the field. No AI knows it
is being jammed … so the counter-play the frame existed to create does not
exist on either side."* The See-Engine is one step better — the effect is real
and measurable — and one step short, because it is not *perceivable*.

**Three options, in order of my preference. Pick one before writing
`see_engine.gd`, because it decides what the frame is.**

| option | cost | what the player sees |
|---|---|---|
| **A — the eye tells you.** The `Rig/GimbalYaw` gimbal already traverses toward whatever the body faces (`walker.gd:206-228`), and `Rig/GimbalYaw/LensPitch/Pupil` (`see_engine.tscn:592`) carries its own emissive material. **Light the pupil while it is feeding contacts, and kill it on death.** | **small** — one material parameter driven from `_tick_watch`, plus the death path | "that thing is watching us, and it stopped". The silhouette is already one enormous eye; this makes the eye a state indicator |
| **B — the formation misses.** Accept that the degradation is statistical and make it *audible* instead: hostile fire near the player that stops being accurate. | **zero**, and it does not work. 18% is below perception | nothing |
| **C — the HUD learns about enemy contacts.** Lift `hud.gd:71-72`'s ALLIED filter and render hostile-side contact marks differently. | **large, and it is a different feature** — it tells the player what the enemy knows, which is a design decision about information, not a frame | a lot, most of it not about this frame |

**Recommendation: A, and A is mandatory, not polish.** It is the cheapest thing
that satisfies §6.3, it uses geometry the model already has, and it is
assertable (§6). C is a good idea and should be its own brief.

### 1.4 So: the verdict

**Cheap where the doc hoped (the aim bonus is zero lines) and medium overall,
because the two things on either side of it both have to be built: the sensor
sweep that feeds the ledger (§1.2, ~25 lines) and the readout that makes the
death legible (§1.3 option A, small but non-negotiable).**

Against `FRAME_ANATOMY.md` §5's scale: well under the Bulwark's 295 lines, well
under the Nest's 260. Call it a **~90-line `see_engine.gd`** — the watch sweep,
the pupil state, the option arrays and four small overrides — plus the ordinary
registration. **No edits to `Enemy`, `Soldier`, `Walker`, `AI` or `AIManager`,**
which makes it the cheapest of the three enemy frames and the only one of the
three that touches no shared runtime code.

---

## 2. What "successful" means

**The player works out, without being told, that the thing not shooting at them
is the reason the things shooting at them are hitting.**

While it lives, Argus units around it share contacts and shoot straighter for
it (§1.1). It barely fights, and that is the threat: it is the first enemy whose
danger is legible without a gun pointed at you, and the counter is obvious
without being easy — get past the escort and kill the thing that is not
shooting. Thematically it is also the only frame in the game that *is* Argus
rather than belonging to it.

**Be honest about where the gap is thin.** The mechanic is a one-term
accuracy multiplier that already exists, applied to a faction that does not
exist yet. Strip §1.3 out and what remains is a tall statue that makes some
numbers slightly better — which is exactly the shape of the two frames cut this
week. **The frame is carried entirely by (a) the sensor sweep making its 110 m
mean something and (b) the eye going dark when you kill it.** Both are in §1.
Build them or do not build the frame.

The human has confirmed `weapon_slots = 0` is deliberate: sentry only, no
weapons. That is settled and §3 does not reopen it.

---

## 3. The `ChassisDefinition`

New file `Campaign/chassis/chassis_see_engine.tres`. Copy the shape of
`Campaign/chassis/chassis_spotter.tres` — the other `weapon_slots = 0` sensor
frame and the only `.tres` precedent for one.

| field | value | note |
|---|---|---|
| `id` | `&"see_engine"` | **PERMANENT.** `FRAME_ANATOMY.md` §2.5; `kill_kinds.gd:21-23` is the recorded case (the bomber is still `gunship`). The underscore matters: it must match the `.tscn` basename `see_engine` to buy the §5 `SCENES` exemption, and it does |
| `display_name` | `"See-Engine"` | matches `soldier_name` on the scene (`build_see_engine.gd:533`). `enemy_force_spawner.gd:280` writes it as `analytics_kind`; `KillKinds.name_of` (81-84) strips a trailing `" CHASSIS"` |
| `description` | one sentence: it sees and does not shoot, and everything near it shoots better | |
| `icon` | null | §5 |
| `scene` | `res://Character/characters/ai/see_engine.tscn` | serialised as a path (`soldier_record.gd:472`); do not move it |
| `cost` | `0` | |
| `purchasable` | `false` | **mandatory** — `test_ledger.gd:449-465` |
| `supply` | `3` | design doc §3 |
| `starting_weapon_id` | `&""` | **mandatory and non-obvious.** `FRAME_ANATOMY.md` §3.2: `_issue_weapon` (`enemy_force_spawner.gd:503-504`) is **not** gated on `weapon_slots`, only on `starting_weapon_id != &""`. A non-empty id arms a `weapon_slots = 0` frame — and this frame has a real `WeaponMount` at `Rig/GimbalYaw/LensPitch/WeaponMount` (`see_engine.tscn:602`) for the gun to land in |
| `coax_weapon_id` | `&""` | |
| `base_health` | `240` | matches the scene (`build_see_engine.gd:528-529`). Killable once reached |
| `base_speed` | `0.75` | **IGNORED FOR ENEMIES.** `FRAME_ANATOMY.md` §6.9; `_apply_frame` (`enemy_force_spawner.gd:524-532`) has no speed line. The real figure is `move_speed = 2.2` on the scene (`build_see_engine.gd:532`). Write 0.75 for the card; do not expect it to do anything |
| `base_accuracy` | `0.0` | it never shoots, and `_apply_frame` assigns only if `> 0` (`enemy_force_spawner.gd:530`) so 0.0 leaves the scene's value alone. The Spotter and Nest both set 0.0 on purpose (`FRAME_ANATOMY.md` §2 Stats) |
| `base_sensor_range` | `110.0` | matches the scene (`build_see_engine.gd:540`). **The highest in the game** — the Spotter is 90 (`chassis_spotter.tres`). **And it does nothing for the contact effect without §1.2.** It does drive `_tick_vision`'s cone and `_threat_actor` |
| `weapon_slots` | `0` | the design, confirmed by the human |
| `built_in` | `"DESIGNATOR"` | **and this one actually has art.** `Icons.built_in` (`icons.gd:63-66`) resolves `built_in` as a *filename* (`FRAME_ANATOMY.md` §6.10), and `icons/items/designator_{s,m,l}.png` exist — listed and confirmed. `"OPTICS"` also resolves (the Spotter's, `icons/items/optics_*.png`), and is the safer choice if you would rather reuse the Spotter's read. **Do not invent a word**: a novel `built_in` with no art is a silent blank |
| `weapon_replaces_built_in` | `false` | there is nothing to swap for |
| `turret` | `false` | **and the scene still has a `turret` node, deliberately.** `build_see_engine.gd:64-87`: `Rig/GimbalYaw` is wired as `turret` and `Rig/GimbalYaw/LensPitch` as `gun_pivot`, so `walker.gd` yaws the lens onto whatever the frame has noticed — a real traverse, not a stub. The chassis flag stays false because `turret = true` means "the weapon slot only takes guns whitelisted to this frame" (`chassis_definition.gd:91`) and there is no slot. The non-null node also excuses `enemy.gd:2893`'s `hull_spoils_aim`, which is harmless either way on an unarmed frame |
| `vehicle` | `true` | team assignment only (`campaign_state.gd:468-496`); irrelevant to an enemy |
| `drives` | `false` | legged |
| `equipment_slots` | `0` | |
| `module_slots` | `0` | |
| `musters_at_base` | `false` | |
| `required_rank` | `0` | `FRAME_ANATOMY.md` §6.4: inert in the factory |

**On the scene, not the definition, and already correct:**
`signal_resistance = 1.4` (`build_see_engine.gd:545`) — hardened, not immune;
`ChassisDefinition` has no signal field. `turret_traverse_degrees = 24.0` (548)
— the lens sweeps slowly. `activation_distance = 200` (527).

---

## 4. Items and weapons

**None. There is nothing to make.**

`weapon_slots = 0`, `starting_weapon_id = &""`, `turret = false`, and the effect
is behaviour on the chassis, not an item. No `ItemDefinition`, no `AIWeapon`
scene, no subclass. `FRAME_ANATOMY.md` §3.4's rule ("a subclass if and only if
the round is not a hitscan ray") does not apply because there is no round, and
§3.3's rule ("a tool that is part of the body needs no item at all — it is
`built_in` plus code") is the whole answer: `built_in = "DESIGNATOR"` and the
sweep in §1.2.

`Rig/GimbalYaw/LensPitch/WeaponMount` (`see_engine.tscn:602`) exists only
because `enemy.gd` declares a typed `weapon_mount` export and a null one is a
silent null. `build_see_engine.gd:81-87` documents it as a stub and records that
it is at yaw **+PI/2** — a weapon's muzzle runs down its own +X and the mount
has to turn that onto the body's -Z. Leave the sign alone even though nothing
will hang on it; the next person to read the scene should not learn the wrong
sign from it.

---

## 5. The behaviour

**Script: `Character/characters/ai/see_engine.gd`, `extends Walker`.**

`bulwark.gd extends Walker` is the precedent (`FRAME_ANATOMY.md` §4). The
Walker gives legged gait (`walker.gd:117`), the gimbal traverse (206, 229) and
`takes_cover() = false` (251). `FRAME_ANATOMY.md` §4.3: a frame on `walker.gd`
needs a script only if the aiming geometry differs from "gun on the turret" (it
does not — there is no gun) or it has a behaviour of its own. This one has one,
and §1 is it.

`see_engine.tscn:218` already has `walker.gd` on the root, so this is a one-line
`script` swap in the scene plus the new file.

### 5.1 What it overrides

| function | base | one line on why |
|---|---|---|
| `_physics_process(delta)` | `enemy.gd:1420` (`walker.gd:112` already supers) | `super(delta)` then `_tick_watch(delta)` and `_tick_pupil(delta)`. Nothing else |
| `_tick_watch(delta)` | new | §1.2. The frame's entire reason to exist |
| `_tick_pupil(delta)` | new | §1.3 option A. Pupil emission on while it is feeding contacts, off otherwise |
| `handle_weapon_logic(delta)` | `enemy.gd:2846` | **override to `pass`.** `spotter_drone.gd:175` is the shipped example and the comment there is the reason. The frame has no weapon so the machine would do nothing anyway, but an explicit stub is what makes "it never enters a firing state" (§7) a property of the script rather than an accident of `weapon == null` |
| `roll_combat_action()` | `enemy.gd:3052` | **do NOT stub, unlike the Spotter.** See §5.2 — this frame needs the dice to pick MOVE so it can back away, which is the opposite of the Spotter's problem |
| `takes_cover()` | `soldier.gd:145` | **inherited `false`** from `walker.gd:251`. `Squad` splits its members on it (`squad.gd:554-555`, `1540-1541`): false means it parks on the spot rather than being sent to a cover point. Right for a sensor mast — **but see the risk in §9**, because a frame that does not take cover and does not shoot has no self-preservation at all |
| `_update_facing(delta)` / `_turret_forward()` / `_weapon_on_target()` | `enemy.gd:2780` / `walker.gd:229` / `239` | **all inherited.** `FRAME_ANATOMY.md` §4.2 warns that overriding `_weapon_on_target` wrong is a frame that never shoots; here the frame never shoots anyway, and `_update_facing` is what turns the big lens onto what it has noticed — which is §1.3's readout. Do not touch any of the three |
| `_tick_gait(delta)` | `walker.gd:117` | **inherited**, and only two of four legs animate. See §9 |
| `die()` | `enemy.gd:4223` | **override: kill the pupil.** `super()` first, then the emission off. The one frame-visible consequence of killing it, and the whole of §1.3 |

**No edits to `Enemy`, `Soldier`, `Walker`, `AI`, `AIManager` or `Settings`.**
Confirmed: everything above is a subclass override or a new function, and every
function `_tick_watch` calls already exists with the signature used.

New exports:

```gdscript
@export var watch_interval: float = 1.0        # seconds between contact sweeps
@export var pupil: MeshInstance3D              # Rig/GimbalYaw/LensPitch/Pupil
@export var pupil_lit_energy: float = 2.4
```

`watch_interval` must stay comfortably under `contact_fresh_seconds = 3.0`
(`ai_manager.gd:201`) or the contacts it holds open flicker stale between
sweeps. `pupil` is a typed `MeshInstance3D` export — **a `NodePath` assigned to
it silently does nothing** (`build_see_engine.gd` says the same of every root
export, and `FRAME_ANATOMY.md` §6.6 is the general case).

**The `watch_radius` question the design doc asks (§8: "what it *helps* should
probably be smaller, or one See-Engine covers a whole map") is answered by
there being no radius to pick.** The effect's reach is `sensor_range`, because
`_contact_assisted` has no distance term at all — it asks only whether the
faction's table is fresh on the target. So *every* Argus unit anywhere on the
map shoots tighter at anything this frame can see. **That is a real design
consequence and it is the human's call** (§9); it is not a parameter you can
tune without writing a distance filter that does not exist today.

### 5.2 `AllowedMovementOptions` and `AllowedCombatOptions`

**Values: `AllowedCombatOptions = Array[int]([0])` and
`AllowedMovementOptions = Array[int]([1, 2])`.**

`CombatOptions` is `{MOVE = 0, AIM = 1, FIRE = 2}` and `MovementOptions` is
`{ADVANCE = 0, REPOSITION = 1, FALLBACK = 2, LEAP = 3, CHASE = 4}`
(`enemy.gd:1091-1092`).

`see_engine.tscn:317-318` currently reads:

```
AllowedMovementOptions = Array[ExtResource("2_7b1m4")]([])
AllowedCombatOptions = Array[ExtResource("2_7b1m4")]([])
```

Both empty **and** mistyped. **This is a live defect on this frame**, unlike on
the Broodcarrier: `walker.gd` does *not* stub `roll_combat_action`, so the empty
combat array means `roll_combat_action` returns at `enemy.gd:3053-3054` and the
frame never chooses MOVE in combat at all — no REPOSITION, no FALLBACK. A
See-Engine with a squad shooting at it stands exactly where it is for the whole
fight, which is `FRAME_ANATOMY.md` §6.1's symptom.

**Why MOVE-only on the combat array.** It is the only one of the three that does
anything useful here, and excluding the other two is deliberate:

- **AIM** reaches `_enter_aim_stance` (`enemy.gd:3953`), which zeroes
  `_burst_left` and stops the frame moving to settle a shot it will never take.
  Pure downside.
- **FIRE** reaches `_commit_burst` (`enemy.gd:3960`). I traced this: it is
  *harmless* on a weaponless frame — the function guards on
  `weapon != null` for the weapon's own burst rhythm and otherwise just sets
  `_burst_left`, and `handle_weapon_logic` is stubbed anyway. But
  `_score_combat_option(FIRE)` (`enemy.gd:3115-3127`) scores it `1.0 + 2.5 +
  …` with no weapon-null guard and `_max_range()` returning the 30.0 fallback
  (`enemy.gd:3022-3023`), so FIRE would win most rolls and the frame would
  spend its decisions on a no-op. Exclude it.

**Why `[1, 2]` on the movement array.** REPOSITION (`find_reposition_target`,
`enemy.gd:3972`) and FALLBACK (`find_fallback_target`) are the two that take a
threatened sensor *away* from a threat. **ADVANCE is excluded deliberately** — a
command node must not walk into the fight, and `_score_movement_option(ADVANCE)`
is `0.4 + range_ratio * 3.0` (`enemy.gd:3162-3165`), which against the 30.0
`_max_range()` fallback of a weaponless frame scores *high* at any real
distance. Leave it in and the See-Engine charges. LEAP and CHASE are not its
vocabulary.

Compare `soldier_rifle.tscn:70-71` (`[0, 1]` / `[0, 1, 2]`) and
`vehicle_rover.tscn:165-166` (`[0, 2, 4]` / `[0, 1, 2]`), the only two frames in
the game with correct values.

**Prove it rather than trust it.** The scoring functions were written for armed
frames and a weaponless caller takes the `_max_range() == 30.0` branch
everywhere. §7 asserts that a See-Engine under fire moves *away*, which is the
behaviour these two arrays are chosen for, and it is the assertion to write
first if anything about this frame feels wrong.

Fix the type annotations to `Array[int]` by hand-editing the `.tscn`. Do **not**
re-run `build_see_engine.gd` — its header (lines 8-13) is explicit, and
`CLAUDE.md` records that force-rebuilds have cost this project its gameplay
layers. Fixing the type also silences the
`Cannot assign contents of "Array[Object]" to "Array[int]"` pair that
`build_see_engine.gd:103-109` documents as expected on load.

---

## 6. Registration

Walked against `FRAME_ANATOMY.md` §1. **S** = fails silently.

| § | item | status |
|---|---|---|
| 1.1 | `see_engine.tscn`, `tools/build_see_engine.gd` | **done.** Do not re-run the generator |
| 1.2 #1 | `Campaign/chassis/chassis_see_engine.tres` | **to do.** §3 |
| 1.2 #2 | root script resolves to `Soldier` | **done** — `walker.gd extends Soldier`; `see_engine.gd extends Walker` keeps it. Hard error at spawn if broken (`enemy_force_spawner.gd:265-267`) |
| 1.2 #3 | `groups=["enemies"]` | **done**, `see_engine.tscn:218` |
| 1.2 #4 | `kill_kinds.gd` `FRAMES` | **to do — S.** `&"see_engine": "res://Campaign/chassis/chassis_see_engine.tres"` into `kill_kinds.gd:14-37` |
| 1.2 #5 | `Allowed*Options` | **to do — S, and this is a live defect on this frame.** §5.2 |
| 1.3 | catalogue, `purchasable`, icons | **deliberately not done.** `purchasable = false`, and **no** entry in `Campaign/items & catalogue/test_item_catalogue.tres` |
| 1.4 #9 | a mission `.tres` | **to do.** §6.1 |
| 1.4 #10 | `Enums.Factions` + `are_hostile` | **`BROODCARRIER.md` §0. The blocker, and this frame's effect is keyed on it twice** — `get_hostiles_in_radius` filters on `are_hostile` (`ai_manager.gd:507,516`) and `_contact_assisted` keys the ledger on `faction` |
| 1.5 #11 | `kill_kinds.gd` `SCENES` | **not needed.** Basename `see_engine` == id `see_engine`, and `kind_of` falls through to `SCENES.get(base, StringName(base))` (`kill_kinds.gd:70`). `FRAME_ANATOMY.md` §1.5 names this exact frame as the example |
| 1.5 #12 | `enemy_loadouts.gd` `TABLES` | **do not add one.** Zero weapon slots, zero module slots, zero equipment slots — a pool would have nothing to fill. `roll_for` returns `{}` for an unlisted frame (`enemy_loadouts.gd:208-210`), and adding a key commits you to `test_enemy_loadouts.gd:91-124` |
| 1.5 #13 | `cosmetics.gd` | **no.** `for_frame` returns `[NONE]` (84-90). Also thematically wrong: Argus does not issue hats |
| 1.5 #14 | mission `unlocks` | **N/A**, not purchasable |
| 1.5 #15 | a lab plan | **yes.** §7 step 5 — it is how `watch_interval` and the §9 map-wide-reach question get numbers. `bulwark_screen.tres` is the precedent |
| 1.5 #16 | `tools/test_see_engine.gd` | **to do.** §7 |
| 1.5 #17 | `probe_nav_reach.gd` `FRAMES` | **yes.** 3.10 m wide on four overlong legs and it walks at `move_speed = 2.2`. `MEMORY.md`: the navmesh bake is the only clearance Godot enforces, and radius/climb quantise silently to cell units. Values from `tools/probe_chassis_size.gd` |
| 1.6 | CSG bake, teams, `"signal"` group, `AIManager` registration | **all free.** `_CsgBake` reads the directory (`csg_bake.gd:177-189`), which matters here — the hull is a real `CSGMesh3D` with three `CSGBox3D` flutes (`see_engine.tscn:366-385`) |

**Icons: run `tools/bake_icons.gd` and report whether they landed.** The
`FRAMES` entry is what makes the frame bakeable (`bake_icons.gd:120-129`).
`FRAME_ANATOMY.md` §6.3 and §8.3: nothing asserts icons exist, which is how the
Bulwark has gone without since it was built. This frame's design doc §1 argues
it was chosen partly because it "does so as one shape — which matters at icon
size", so it is worth actually having the icon.

### 6.1 The mission entry

`mission_salient_1_overthetop.tres` is the Bulwark's worked example — the
`[ext_resource]` at line 11, an `EnemySquadSpec` sub-resource block at 20-40,
`faction` at 35. Two edits:

1. `[ext_resource type="Resource" path="res://Campaign/chassis/chassis_see_engine.tres" id="…"]`;
2. the chassis in an `EnemySquadSpec.roster`, with `faction = 6` (ARGUS).
   `roster` is `Array[ChassisDefinition]` (`enemy_squad_spec.gd:46`) and is on
   `FRAME_ANATOMY.md` §6.6's list of typed arrays that pack as `[]` in silence.
   `enemy_force_spawner.gd:270` does `soldier.faction = spec.faction` before
   `add_child`, so the int in the file is the whole of it.

**Field it with an escort, in the same `EnemySquadSpec`.** The design doc §2 is
"get past the escort and kill the thing that is not shooting", and the effect is
only observable on units that share its faction — so the escort must be
`faction = 6` too, in the same spec. **A See-Engine escorted by a `faction = 1`
ENEMY squad demonstrates nothing**, because `_contact_assisted` reads
`is_fresh(ENEMY, target)` for those robots and the See-Engine writes
`is_fresh(ARGUS, target)`. That is the single easiest way to build this frame
and conclude it does not work.

**`activation_distance = 200` on the scene** (`build_see_engine.gd:527`).
`FRAME_ANATOMY.md` §6.13 / `enemy_force_spawner.gd:537-546`: `always_active`
does **not** exempt a frame from the distance cull. A culled See-Engine's
`_physics_process` is off (`ai_manager.gd:576-593`), so it stops feeding
contacts — correct, and worth a comment so nobody "fixes" it.

---

## 7. Tests

New file `tools/test_see_engine.gd`. `tools/test_bulwark.gd` is the model — its
`_test_the_chassis_is_registered` (70-90) is §6 of this brief as a test, its
`_ok` reporter is at 52, and `_test_the_eye_keeps_its_own_colour` (186-232) is
the livery assertion to copy. `tools/test_targeting.gd:169` is the shipped
example of driving `AIManager.note_seen` from a test. `tools/test.sh` picks it
up with no wiring.

**The task-zero assertion:**

```gdscript
_ok("hostile to the player, outbound",
	Enums.are_hostile(Enums.Factions.PLAYER, Enums.Factions.ARGUS))
_ok("hostile to the player, inbound",
	Enums.are_hostile(Enums.Factions.ARGUS, Enums.Factions.PLAYER))
```

Both directions, because `BROODCARRIER.md` §0.1 shows they fail differently.
**And on this frame the inbound direction is load-bearing twice over**:
`AIManager.get_hostiles_in_radius` filters on
`Enums.are_hostile(req_faction, …)` at `ai_manager.gd:507` and `516`, so an
inbound-false ARGUS gets an empty sweep and `_tick_watch` writes nothing — with
no warning. Add that as its own assertion:

```gdscript
_ok("the sweep can see the player at all",
	ai_manager.get_hostiles_in_radius(see_engine, 110.0).has(player))
```

Then:

- **registered:** `chassis_see_engine.tres` loads; `id == &"see_engine"`,
  `supply == 3`, `purchasable == false`, `cost == 0`, `weapon_slots == 0`,
  `starting_weapon_id == &""`, `base_sensor_range == 110.0`,
  `turret == false`; `KillKinds.FRAMES.has(&"see_engine")` and
  `frame_of(&"see_engine") != null`
- **it is the highest sensor in the game:** `base_sensor_range` strictly greater
  than every other entry in `KillKinds.FRAMES`. An assertion rather than a
  comment, because §3 claims it and a later frame could quietly beat it
- **not in the player catalogue:** load
  `Campaign/items & catalogue/test_item_catalogue.tres` (the path
  `test_bulwark.gd:86` hard-codes) and assert nothing in `chassis` has
  `id == &"see_engine"`
- **it never fires, and the mount stays empty:** run
  `EnemyForceSpawner._apply_frame` over it and assert
  `weapon_mount.get_child_count() == 0` and `weapon == null`. That is the §3
  `starting_weapon_id` trap caught directly. Then step physics with a live
  target and assert `weapon_state` never becomes `WeaponState.FIRE`
- **the option arrays:** `AllowedCombatOptions == [0]` and
  `AllowedMovementOptions == [1, 2]`, read off the **instantiated scene**, not
  the script default (`CLAUDE.md`: scene values beat script defaults), and with
  the element type asserted as int (the §5.2 annotation fix)
- **under fire it moves AWAY:** put a hostile at 20 m, run the combat timer, and
  assert the frame's distance to that hostile does not decrease. §5.2's
  ADVANCE-exclusion as an assertion, and the one to write first — the scoring
  functions were written for armed frames
- **IT WRITES CONTACTS FOR ITS OWN FACTION, AT SENSOR RANGE.** A target with
  clear line at 80 m — well outside the 25 m Detection sphere — appears in
  `ai_manager.contact_for(Enums.Factions.ARGUS, target)` and
  `ai_manager.is_fresh(ARGUS, target)` is true, after `watch_interval * 2`.
  **This is §1.2 and it is the assertion that proves the frame is a frame.**
  Without it, the test suite passes on a tall statue
- **it does not see through walls:** same target, geometry between, and
  `is_fresh(ARGUS, target)` is false. The `is_path_clear` guard in §1.2; without
  it the frame is a wallhack for its whole army
- **an ARGUS unit that cannot personally see the target still shoots tighter:**
  place a second ARGUS robot with no line to the target, set its
  `combat_target`, and assert `_contact_assisted()` is true and
  `get_aim_spread_multiplier()` is `SPOTTED_SPREAD` times what it is with the
  See-Engine dead. **Note the `Settings` gate:** `_contact_assisted`
  (`enemy.gd:5271-5273`) returns false when `Settings.debug_tools_enabled()` is
  true and `debug.contact_accuracy` is false — the test must set that value or
  it will fail for a reason that has nothing to do with this frame
- **A SWARM OR STRATCOM UNIT DOES NOT BENEFIT.** Same setup, `faction` changed,
  `_contact_assisted()` false. §1.1: this is structural (the ledger is keyed by
  faction, `ai_manager.gd:197`, `218-221`) rather than something the frame
  implements — assert it anyway, because the day somebody "simplifies"
  `_contacts` into one table this is the test that catches it
- **killing it stops the feed:** `see_engine.die()`, advance past
  `contact_fresh_seconds` (3.0, `ai_manager.gd:201`), and assert
  `is_fresh(ARGUS, target)` is false and the neighbour's
  `get_aim_spread_multiplier()` has gone back up. Note this needs real elapsed
  time — `is_fresh` compares against `Time.get_ticks_msec()`
  (`ai_manager.gd:344-345`) — so step physics frames rather than calling the
  function twice
- **the pupil goes dark when it dies:** `Rig/GimbalYaw/LensPitch/Pupil`
  (`see_engine.tscn:592`) has `emission_energy_multiplier` at
  `pupil_lit_energy` while feeding and 0 after `die()`. §1.3 option A as an
  assertion. **The only part of this frame's death the player can see**
- **the gimbal tracks:** give it a target off to one side, step physics, assert
  `Rig/GimbalYaw.rotation.y` moved toward it. `build_see_engine.gd:64-79` calls
  this "a real traverse, not a stub satisfying an export", and it is half of
  §1.3's read
- **the lens and pods keep their own material:**
  `Rig/GimbalYaw/LensPitch/Pupil`, `Rig/SensorPodA/Lens` and
  `Rig/SensorPodB/Lens` (`see_engine.tscn:592`, `399`, `417`) are **not** in the
  `FactionLivery` `pieces` array and survive `apply()`; the rest of the frame
  did get painted. `build_see_engine.gd:125-131` records that all three carry
  `robot_eye_psx.png` on their own `StandardMaterial3D` for the same reason the
  Walker's eye does. Note there is **no node named `Eye` on this frame**, so
  `check_frame.gd`'s "EYE EXCLUDED" assertion does not fire and this test is
  the only thing protecting it
- **groups and typed arrays:** `is_in_group("enemies")` **and**
  `is_in_group(AI.SIGNAL_GROUP)` (`test_bulwark.gd:120-127`), plus
  `visible_pieces`, `particle_effects_die`, `particle_effects_hit` all
  non-empty, and all nine root node paths resolving (`rig`, six leg nodes,
  `turret`, `gun_pivot`, `weapon_mount`, `nav_agent`, `bark`, `detection`)

```bash
bash tools/check.sh --changed              # must print PASS
bash tools/test.sh
bash tools/smoke.sh
"D:/Godot Games/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe" \
  --headless --audio-driver Dummy --path . \
  --script res://tools/check_frame.gd -- res://Character/characters/ai/see_engine.tscn
```

**Not while `tools/test.sh` is in flight** — the suites share `user://` probe
paths and a parallel run produces a FAIL that looks real and does not reproduce.

---

## 8. Order of work

1. **`BROODCARRIER.md` §0 — `are_hostile` as a table,
   SWARM/STRATCOM/ARGUS appended, `tools/test_factions.gd` green.** An ARGUS
   See-Engine on today's `enums.gd` gets an empty array back from
   `get_hostiles_in_radius` (`ai_manager.gd:507,516`) and writes no contacts at
   all, so every §7 assertion that matters would fail with no explanation.
   **Prove:** all seven assertion groups including the regression lock, and
   `bash tools/test.sh` green across the suite.
2. **`chassis_see_engine.tres`, the `kill_kinds.gd` entry, and the
   `Array[int]` type fix in `see_engine.tscn`.** No script yet. **Prove:** the
   "registered", "highest sensor", "not in the catalogue" and "never fires"
   assertions; `check_frame.gd` clean and the two `Array[Object]` load errors
   gone.
3. **`AllowedCombatOptions = [0]`, `AllowedMovementOptions = [1, 2]`, still
   with no `see_engine.gd`.** **Prove:** the "under fire it moves away"
   assertion, and field it with an ARGUS escort in one mission at
   `faction = 6`, `smoke.sh` green. At the end of this step the frame exists,
   is visible, is killable, and is a statue. Confirm the human is happy with
   how it reads before step 4.
4. **`see_engine.gd` — `_tick_watch` and `_tick_pupil`.** §1.2 and §1.3.
   **Prove:** the contact assertions (80 m yes, through-a-wall no), the
   assisted-neighbour assertion, the SWARM/STRATCOM-does-not-benefit
   assertion, the stops-on-death assertion, and the pupil assertions. This is
   the step where the frame becomes a frame.
5. **Measure it, then tune it.** A lab plan
   (`Campaign/lab/plans/*.tres`, `bulwark_screen.tres` is the precedent): the
   same ARGUS squad with and against the same player squad, with and without a
   See-Engine, to find out what 0.82 is actually worth in a fight. In the same
   pass, time `_tick_watch` — `get_hostiles_in_radius` is uncached
   (`ai_manager.gd:511-518`) and this calls it at 110 m. `MEMORY.md`: measure
   CPU, not wall clock, and pace the loop with `Engine.max_fps = 60` or you
   measure `_process` starving physics. **Report the number.**
6. **The human looks at the death.** §1.3 is a perception claim and
   `CLAUDE.md` says that is theirs. If the pupil going dark is not enough, the
   fallback is §1.3 option C and that is a separate brief, not a patch.

---

## 9. Open questions and risks

**For the human:**

1. **The effect has no radius, and therefore covers the whole map.**
   `_contact_assisted` (`enemy.gd:5269-5276`) has no distance term — it asks
   only whether the faction's contact table is fresh on the target. So every
   Argus unit anywhere shoots tighter at anything this frame can see. The
   design doc §8 assumed a tunable "help radius"; **there is none, and adding
   one means a distance filter that does not exist today.** My view: leave it
   map-wide. It is what makes the frame a *command node* rather than an aura,
   and the counter is still "kill it". But it is your call and it is the
   biggest open design question in the frame.
2. **ARGUS or something else, and StratCom or Home Command?**
   `BROODCARRIER.md` §0.2. `HEAD` says StratCom; the working tree has been
   renamed to "Home Command" by another agent, uncommitted. ARGUS itself is
   uncontested. Enum identifiers are permanent (`FRAME_ANATOMY.md` §2.5).
3. **`watch_interval` and whether the pupil is enough.** §8 steps 5 and 6.

**Risks:**

4. **The Spotter's description is wrong, and I did not fix it.**
   `chassis_spotter.tres` says the Spotter sees twice as far "and everyone
   fights on what it finds". On the §1.2 trace its 90 m sensor does not feed the
   contact table either — only its 25 m Detection sphere does
   (`spotter_drone.tscn:17`). Either the Spotter wants the same
   `_tick_watch` this frame is getting, or the description wants rewriting.
   **Separate task, flagged, not touched.** It is also the closest thing this
   batch has to a family-sweep finding.
5. **The frame has no self-preservation.** It does not shoot
   (`weapon_slots = 0`), does not take cover (`walker.gd:251`), and §5.2 gives
   it REPOSITION and FALLBACK only. A See-Engine whose escort dies first walks
   slowly backwards at `move_speed = 2.2` (`build_see_engine.gd:532`) until it
   is shot. That is probably correct for the unit and it will look stupid in
   the one case where it is the last thing alive. **Watch for it in §8 step 3**,
   before the script exists, because it is a mission-authoring answer (escort
   it properly) and not a code one.
6. **Two of its four legs do not animate.** `walker.gd` drives exactly two
   hips (`walker.gd:37-42`), and `build_see_engine.gd:38-62` wires the front
   pair (`Rig/LegFR` → `HipR/Knee/Foot`, `Rig/LegFL` → `HipL/Knee/Foot`) and
   leaves `Rig/LegRR` and `Rig/LegRL` static by design, with an explicit
   instruction not to edit `walker.gd` to add legs. **Known open issue.** On a
   frame that walks at 2.2 m/s and spends most of its life standing, I would
   leave it; a four-leg gait is a `walker.gd` change with eight other frames
   downstream of it. State it to the human rather than fix it.
7. **The `Settings` gate on `_contact_assisted`.** `enemy.gd:5271-5273`
   returns false when debug tools are enabled and `debug.contact_accuracy` is
   off. A tester with debug tools on and that flag off will see the whole frame
   do nothing, and nothing will say why. §7 sets it explicitly; say so in the
   hand-off.
8. **The culled See-Engine stops feeding.** `_physics_process` is switched off
   entirely by the distance cull (`ai_manager.gd:576-593`), and the contacts
   lapse within `contact_fresh_seconds`. Correct behaviour, invisible
   mechanism — comment it or it gets "fixed".
9. **`built_in = "DESIGNATOR"` works only because that icon happens to
   exist.** `icons/items/designator_*.png`, listed and confirmed. `icons.gd:60-62`
   says the Spotter's `"OPTICS"` resolving is the same coincidence. A rename to
   anything else is a silent blank (`FRAME_ANATOMY.md` §6.10).
