# BASTION — integration brief

StratCom · supply 3 · ground · deployable hardpoint · enemy only ·
**model built, nothing registered**

Written for a builder. The map is `docs/briefs/FRAME_ANATOMY.md`; this document
cites it by section instead of restating it. Everything else carries a
`file:line`.

**What exists today:** `Character/characters/ai/bastion.tscn` — root node
`Bastion`, a `CharacterBody3D` with `groups=["enemies"]` (`bastion.tscn:616`),
root script `walker.gd`, built in the **planted** state with `move_speed = 0.0`
(`build_bastion.gd:582`) — and `tools/build_bastion.gd`. There is no
`ChassisDefinition`, no `kill_kinds` entry, no `bastion.gd`, no item, and no
`Enums.Factions.STRATCOM` for it to belong to.

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
> of this frame's order of work and nothing here can be validated before it.**
> It also carries the unresolved **STRATCOM vs "Home Command"** naming
> conflict, which this frame's faction identifier depends on.

---

## 0. Three claims in `docs/frames/BASTION.md` are now false

The design doc was written before the models and before the Warden was cut.
Three of its citations no longer resolve, and two of them are load-bearing.

1. **`suppress_in_radius` does not exist.** §6.1 says "`suppress_in_radius`
   with a negative sign — … The Warden's static is the model".
   `grep -rn "suppress_in_radius" --include=*.gd` over the main checkout
   returns **nothing**. There is no such function and never was in the
   committed tree. The nearest real thing is the one shared suppression pass at
   `Character/weapon/ai_weapon.gd:469-...`, which is static, takes everything as
   arguments, and drains `signal_integrity` — it is not a template for writing
   `signal_resistance`.
2. **The Warden is cut.** §2 ("It is the mirror of the player's Warden"), §4
   ("The inverse of the Warden's jammer, and the second EMITTER" /
   "see the Warden doc for why there is no fourth `Kind`") and §6.1 all cite a
   frame that was killed on 2026-10-10 — `docs/frames/WARDEN.md:1-5`,
   `git show c7178bf7`. `warden.tscn` and `tools/build_warden.gd` are deleted.
   So there is no first EMITTER, no mirror, and the "why there is no fourth
   `Kind`" argument has to be re-made rather than cited. §3 below re-makes it
   and reaches a different answer.
3. **§6's "Nothing in `Enemy` or `Soldier`" is wrong for this frame.** It is
   true of `Enemy` and `Soldier` literally, and false in spirit: the resistance
   effect cannot be done correctly without two lines in
   `Character/characters/ai/ai.gd`. §4.4 is the whole argument, and it is the
   most important thing in this brief.

The frame's *premise* survives all three. Nothing below changes what the unit
is for.

---

## 1. What "successful" means

**The player's correct first shot is at the thing that is not shooting at
them, and they can tell by looking.**

Everything hostile today is either a threat you shoot or an objective you
break. A Bastion makes the squad standing around it measurably harder to
suppress, so "deal with the support unit first" becomes a real decision — one
the game cannot currently ask. And it gives StratCom a doctrine on screen:
Swarm is numbers, Argus is intelligence, StratCom is **position**. A frame whose
whole statement is "this ground is now expensive".

**The gap is real and the delivery is the risk.** The mechanic is genuinely new
— nothing in the game raises an ally's `signal_resistance` — but
`signal_resistance` is read in exactly two places (`ai.gd:117` for suppression
damage and `ai.gd:138` for EMP lock duration) and a change in either is a
*rate*, not an event. A player who cannot perceive it has been handed a unit
that does nothing. **Two things make it legible and both are mandatory:**

- **the planted state is unmistakable from any bearing** — outriggers driven,
  skirts out, canopy lit. The model already carries this
  (`build_bastion.gd:94-98` chose four-fold symmetry over three for exactly
  this reason) and §4.3 is the script that switches it;
- **the player can see that their suppression is not landing.** The signal
  layer already has a readout — `Enemy.get_signal_state()` drives the HUD's
  suppression VFX — so the honest version is: a suppressed robot inside a
  Bastion's canopy drops one state band instead of two. **Review this with the
  human in front of the game (§7 step 6).** It cannot be asserted and it is the
  whole unit.

Unlike the two frames cut this week (`docs/frames/WARDEN.md`,
`git show c7178bf7`), this one does answer "what does it do" in a sentence:
*it walks to a position, plants, and makes everything of its own side inside its
canopy hard to suppress.* The Warden's failure was the opposite verb with no
readout; this frame's job is to not repeat the readout half.

---

## 2. The `ChassisDefinition`

New file `Campaign/chassis/chassis_bastion.tres`. Copy the shape of
`Campaign/chassis/chassis_bulwark.tres` — the closest frame by role
(`turret = true`, `vehicle = true`, `drives = false`, legged, carries
`heavy_mg`).

| field | value | note |
|---|---|---|
| `id` | `&"bastion"` | **PERMANENT.** `FRAME_ANATOMY.md` §2.5; `kill_kinds.gd:21-23` is the recorded case. It is also already the `.tscn` basename, which buys the §5 `SCENES` exemption |
| `display_name` | `"Bastion"` | `enemy_force_spawner.gd:280` writes it as `analytics_kind`; `KillKinds.name_of` (81-84) strips a trailing `" CHASSIS"` |
| `description` | one sentence naming the plant and the field | |
| `icon` | null | §5 |
| `scene` | `res://Character/characters/ai/bastion.tscn` | serialised as a path (`soldier_record.gd:472`); do not move it |
| `cost` | `0` | |
| `purchasable` | `false` | **mandatory** — `test_ledger.gd:449-465` |
| `supply` | `3` | design doc §3 |
| `starting_weapon_id` | `&"heavy_mg"` | **and this needs §3.1 done first or the frame is armed once and never again** |
| `coax_weapon_id` | `&""` | `bastion.tscn` has one mount, `Rig/Turret/GunPivot/WeaponMount` (`bastion.tscn:925`). `FRAME_ANATOMY.md` §6.12: giving a one-mount frame a coax pool warns per body per mission |
| `base_health` | `300` | matches the scene (`build_bastion.gd:573-574`). Under the Bulwark's 400 — it is not a duel |
| `base_speed` | `0.6` | **IGNORED FOR ENEMIES.** `FRAME_ANATOMY.md` §6.9; `_apply_frame` (`enemy_force_spawner.gd:524-532`) has no speed line. The real figure is `move_speed` on the scene, currently **`0.0`** (`build_bastion.gd:582`) because the scene is the planted state. §4.3 is what raises it to the walking value. Write 0.6 for the card; do not expect it to do anything |
| `base_accuracy` | `0.90` | assigned if `> 0` (`enemy_force_spawner.gd:530`). A hardpoint shoots well; under the Bulwark's 0.95 |
| `base_sensor_range` | `60.0` | matches the scene (`build_bastion.gd:587`) |
| `weapon_slots` | `1` | the MG. `FRAME_ANATOMY.md` §6.11: the fitting code caps at two anyway |
| `built_in` | `"EMITTER"` | §3.2 — this is the projector, and **it will render as a blank** in the roster's weapon column. `Icons.built_in` (`icons.gd:63-66`) resolves `built_in` as a *filename*; `icons/items/` has no `emitter_*.png` (listed and confirmed). `FRAME_ANATOMY.md` §6.10. It is a hostile frame and nothing shows its roster card, so this is cosmetic — but write it knowing |
| `weapon_replaces_built_in` | `false` | the projector is not swapped for the gun; the frame has both |
| `turret` | `true` | and `Rig/Turret` exists (`bastion.tscn:894`), which is the other half — `enemy.gd:2893` computes `hull_spoils_aim` from a property literally named `turret` being non-null, so a frame with a null turret never settles its aim while moving |
| `vehicle` | `true` | ARMOR team. Same as the Bulwark, which also `drives = false` |
| `drives` | `false` | legged. Also means `takes()` does not refuse items with `fits_vehicles = false` (`chassis_definition.gd:89-90`) |
| `equipment_slots` | `0` | |
| `module_slots` | `0` | |
| `musters_at_base` | `false` | |
| `required_rank` | `0` | `FRAME_ANATOMY.md` §6.4: inert in the factory. The Bulwark's `required_rank = 3` does nothing |

**On the scene, not the definition, and already correct:**
`signal_resistance = 2.0` (`build_bastion.gd:591`) — the hardening frame is
itself hardened; `ChassisDefinition` has no signal field, so this can only live
on the `.tscn`. `turret_traverse_degrees = 34.0` (594), slower than the Walker's
55 and the Bulwark's 42, so flanking a hardpoint is a real counter.
`activation_distance = 200` (571).

---

## 3. Items and weapons

Two decisions, and they go opposite ways.

### 3.1 `heavy_mg` — no new item, but a one-line edit to the existing one

**`Campaign/items/item_heavy_mg.tres` must gain `&"bastion"` in its
`chassis_whitelist`.** Read, confirmed, and this is the Bulwark's exact bug:

```
requires_chassis = Array[StringName]([&"walker"])
chassis_whitelist = Array[StringName]([&"walker", &"rover"])
```

`ChassisDefinition.takes()` (`chassis_definition.gd:84-91`) refuses it twice
over for a `turret = true` frame — once at `item.fits_chassis(id)`
(`item_definition.gd:138-139`, false because the whitelist is non-empty and
lacks `bastion`) and again at the final `turret and kind == WEAPON and not
item.chassis_whitelist.has(id)`. Meanwhile `starting_weapon_id` **bypasses
`takes()` entirely**: `recruit()` writes `weapon_ids[0]` directly
(`campaign_state.gd:750-751`) and the enemy path `_issue_weapon`
(`enemy_force_spawner.gd:503-521`) only checks `starting_weapon_id != &""` and
an empty mount. So the frame deploys armed and can never be refitted, which is
`FRAME_ANATOMY.md` §6.2's trace of how the Bulwark ended up that way. Nothing
warns.

So: **add `&"bastion"` to `chassis_whitelist` only.** Do **not** touch
`requires_chassis` — that field is shop visibility (`item_definition.gd:122-134`,
read only by `squad_manager_ui.gd:420` and `audit_economy.gd:398`) and this
frame is not purchasable, so an entry there would offer a tier-three gun to a
player who owns a Bastion they can never own.

**Sweep the family while you are in there.** `FRAME_ANATOMY.md`'s
"prefer fixing the class of problem over the instance": the Bulwark has the same
hole open today (`chassis_bulwark.tres:15` issues `heavy_mg`, line 24 sets
`turret = true`), so adding `&"bulwark"` in the same edit closes both. That is
one line and it is the whole of §6.2.

No new `.tres` and no subclass: `Character/weapon/ai-wep_heavy_mg.tscn` already
exists, is the plain `ai_weapon.gd`, and is a hitscan — `FRAME_ANATOMY.md` §3.4's
rule ("a subclass if and only if the round is not a hitscan ray") says a `.tres`
plus the existing scene is enough. For the record the AI reads
`max_effective_range = 105.0` as its reach (`ai-wep_heavy_mg.tscn:16`,
`Enemy._max_range` 3022), and the gun talks in 14–26 round bursts (20-21).

### 3.2 `shield_projector` — **do not make the item. Cut it.**

`docs/frames/BASTION.md` §4 specifies a new `ItemDefinition` and then, two
paragraphs later, says it "occupies the second weapon slot conceptually but not
literally" and "is built into the frame (`built_in`)". Both cannot be true, and
`FRAME_ANATOMY.md` §3.3 settles it in one line: *"a tool that is part of the
body needs **no item at all** — it is `built_in` plus code."*

Every way of making the item is a lie about the frame:

- `kind = 0` (WEAPON) wants a mount, and the frame's one mount holds the MG;
  `weapon_slots = 2` to give it one would make the second mount a real,
  swappable slot and pull in `enemy_loadouts.roll_for`'s coax pool
  (`enemy_loadouts.gd:226`) plus `FRAME_ANATOMY.md` §6.12's missing-`coax_mount`
  warning;
- `kind = EQUIPMENT` wants `equipment_slots > 0`, and then
  `_evaluate_equipment_use` (`enemy.gd:3703`) decides whether to use it — the
  field is not a thing the frame chooses to deploy, it is what the frame *is*
  while planted;
- `kind = MODULE` is a passive stat delta on the carrier
  (`item_definition.gd:148-150`), which is the opposite of a radius effect on
  everyone else.

And `item_repair_lance.tres` is **not** the counter-example to reach for —
`FRAME_ANATOMY.md` §3.3 is explicit that it has `usable_by_ai = false` and no
`ai_scene`, so `fits_ai()` (`item_definition.gd:145-150`) returns false and no
robot can carry it. It is a player viewmodel.

**So: `built_in = "EMITTER"`, the geometry already in the scene
(`Rig/Mast/Canopy/Emitters/Emitter0..3` and `Rig/Mast/Canopy/Lenses/Lens0..3`,
`bastion.tscn:979-1073`), and the effect in `bastion.gd`. No item, no catalogue
entry, no subclass, nothing to whitelist.** The frame is not purchasable, so
there is no shop card that needs the item to exist, and
`hud_glyphs._item_for_scene` (`hud_glyphs.gd:72-81`) — the reverse index that
makes a weapon show up in the roster — is irrelevant to a hostile.

The one thing the item would have bought is the radius and the bonus being
authored data rather than code. Keep that by putting them on `bastion.gd` as
`@export`s (§4.3), which is where the design doc's own numbers want to live
anyway.

---

## 4. The behaviour

**Script: `Character/characters/ai/bastion.gd`, `extends Walker`.**

`bulwark.gd extends Walker` is the precedent (`FRAME_ANATOMY.md` §4). The
Walker gives legged gait (`walker.gd:117`), turret traverse and elevation
(206, 229), the fire cone (239) and `takes_cover() = false` (251) — all generic
and all correct here. `FRAME_ANATOMY.md` §4.3: a frame on `walker.gd` needs a
script only if the aiming geometry differs from "gun on the turret" (it does
not — the gun is on `Rig/Turret/GunPivot`, which is what `bulwark.gd` was
written to work around and this frame does not need) **or it has a behaviour of
its own**. This one has two.

`bastion.tscn:616` already has `walker.gd` on the root, so this is a one-line
`script` swap in the scene plus the new file.

### 4.1 What it overrides

| function | base | one line on why |
|---|---|---|
| `_physics_process(delta)` | `enemy.gd:1420` (`walker.gd:112` already supers) | `super(delta)` then `_tick_plant()` and `_tick_field()`. Everything else is inherited |
| `takes_cover()` | `soldier.gd:145` | **inherited `false`** from `walker.gd:251` and that is correct: `Squad` splits its members on it (`squad.gd:554-555`, `1540-1541`) and false means "parks on the spot instead of being sent to a cover point". Verify, do not re-implement |
| `order_move_to(...)` | `soldier.gd:370` | **override: refuse while planted**, or unplant first. `enemy_nest.gd:95` and `enemy_watcher.gd:76` are the two frames that refuse orders. Without this a planted hardpoint is walked off its position by its squad with its outriggers in the ground |
| `move_to(pos, think_delay)` | `enemy.gd:2399` | **override: refuse while planted.** `enemy_nest.gd:91` is the model. Belt-and-braces with the above, because `perform_action(MOVE)` reaches `move_to` directly (`enemy.gd:3938-3946`) without going through `order_move_to` |
| `enter_cover_seeking()` | `soldier.gd:124` | **override: no-op.** `FRAME_ANATOMY.md` §4.2 calls this belt-and-braces with `takes_cover()`, and `enemy_nest.gd:104` / `enemy_watcher.gd:85` both do it |
| `_update_facing(delta)` | `enemy.gd:2780` | **inherited** from `walker.gd:206`. The turret traverses, the hull does not move while planted, and the Bulwark's split-yaw problem does not exist here |
| `_turret_forward()` / `_weapon_on_target()` | `walker.gd:229` / `239` | **inherited.** `FRAME_ANATOMY.md` §4.2 warns that overriding `_weapon_on_target` wrong is a frame that never shoots. Do not touch it |
| `_tick_gait(delta)` | `walker.gd:117` | **inherited.** `build_bastion.gd:137-145` records that the hips carry no baked rotation precisely so `_pose_leg` can write them absolutely; the planted pose *is* their rest pose, so a planted Bastion's legs stand still for free |
| `die()` | `enemy.gd:4223` | **override: kill the field in the same frame.** `super()` then `_hardening_bonus` stops being written, which §4.4's design makes self-expiring — but the *visual* (lit lenses, canopy) must go out on death or a dead Bastion still looks like it is projecting |
| `_tick_plant(delta)` | new | §4.3 |
| `_tick_field(delta)` | new | §4.4 |

**New in `ai.gd`: two changed lines and one small block.** §4.4. This is the one
place this brief contradicts the design doc's "nothing in the base classes".

### 4.2 `AllowedMovementOptions` and `AllowedCombatOptions`

**Values: `AllowedCombatOptions = Array[int]([1, 2])` and
`AllowedMovementOptions = Array[int]([])`.**

`CombatOptions` is `{MOVE = 0, AIM = 1, FIRE = 2}` and `MovementOptions` is
`{ADVANCE = 0, REPOSITION = 1, FALLBACK = 2, LEAP = 3, CHASE = 4}`
(`enemy.gd:1091-1092`).

`bastion.tscn:715-716` currently reads:

```
AllowedMovementOptions = Array[ExtResource("2_akk77")]([])
AllowedCombatOptions = Array[ExtResource("2_akk77")]([])
```

Both are empty **and** mistyped. The empty combat array is the live defect:
`roll_combat_action` returns at `enemy.gd:3053-3054`, so `perform_action` is
never reached from the combat timer, so `_commit_burst` (3960) is never called
and `_burst_left` stays 0, and `_enter_aim_stance` (3953) is never called so the
frame never settles. `FRAME_ANATOMY.md` §6.1: the frame still shoots, slowly, in
single shots, which is why it reads as a feel problem rather than a bug. On a
frame carrying a 14–26 round burst gun (`ai-wep_heavy_mg.tscn:20-21`) that is
most of what the weapon is.

**Why `[1, 2]` and not `soldier_rifle.tscn:71`'s `[0, 1, 2]`:** MOVE is the
option that reaches `_pick_movement_option` and then `move_to`
(`enemy.gd:3929-3946`). A planted hardpoint must never choose to walk. Excluding
MOVE from the dice is cheaper and more honest than letting it be chosen and then
refused inside an overridden `move_to` — and `FRAME_ANATOMY.md`'s rule that
"every early return warns" means the refusing version would log a warning every
few seconds for the whole mission.

**Why the movement array can be empty:** with MOVE out of the combat array,
`_pick_movement_option` is unreachable from the combat timer. The walking half
of the frame's life is driven by squad orders through
`Soldier.order_move_to` (370), which is how the Walker fights at all —
`FRAME_ANATOMY.md` §8.4 leaves the Walker's own empty arrays as an open
question and notes it is "masked by the fact that it fights under squad
orders". Here it is deliberate rather than masked, and `bastion.gd` carries a
comment saying so.

**If the human wants the walking half to manoeuvre**, both are plain properties
and `bastion.gd` can swap them on unplant: `AllowedCombatOptions = [0, 1, 2]`
and `AllowedMovementOptions = [0, 1]` (ADVANCE, REPOSITION — `soldier_rifle`'s
values) while walking, back to `[1, 2]` / `[]` on plant. **Recommend not doing
this in the first pass**, because it makes the plant state change the decision
machine as well as the body and there is then no single thing to point at when
the frame behaves oddly.

Fix the type annotations to `Array[int]` by hand-editing the `.tscn`. Do **not**
re-run `build_bastion.gd` — its header (lines 8-14) is explicit, and `CLAUDE.md`
records that force-rebuilds have cost this project its gameplay layers. Fixing
the type also silences the
`Cannot assign contents of "Array[Object]" to "Array[int]"` pair that
`build_see_engine.gd:103-109` documents as expected on load.

### 4.3 Plant / unplant, as a state

The scene is the **planted** state. Nothing stows anything yet, but every node
a script needs is named and nested for it — `build_bastion.gd:109-135` says
exactly what an unplant must move, and I verified all of it against the `.tscn`:

| node | `.tscn` | what unplanting does |
|---|---|---|
| `Rig/Outriggers/Outrigger{F,A,L,R}/Ram` | 1080, 1131, 1182, 1233 | `Ram.rotation.x` from `PLANT_LEAN` (28°, `build_bastion.gd:180`) toward 0, folding it flat under the belly. Each `Ram` carries the whole beam-jack-blade assembly and nothing else |
| `…/Ram/Jack` and `…/Ram/Gland` | 1093 / 1088 | the `Jack` retracts into the `Beam`'s `Gland` at the same time; it is a separate node for exactly that |
| `Rig/Mast` | 933 | `rotation.x` from `-MAST_RAKE` (20°, line 182) to about -90°, laying the column down fore-and-aft on the back deck |
| `Rig/Mast/Canopy` | 946 | **counter-rotates to keep the hoop level.** A stow has to drive both or the hoop ends up on edge |
| `Rig/MastCollar` | 928 | **stays put.** It is hull |
| `Rig/Skirts/Skirt{L,R}` | 1288, 1331 | hinge nodes. `rotation.z` from `±SKIRT_CANT` (8°, line 187) to about ∓80°, swinging each apron up against the flank |
| `Rig/Skirts/Bracket{L,R}` | 1283, 1326 | **must not move.** They are hull, which is why they hang off the container and not the hinges |
| `Rig/Mast/Canopy/Lenses/Lens0..3` | 1055-1073 | the projector's lit faces. Their material is the only non-metal, non-eye material on the frame. Unplanting kills the emission |
| `Rig/HipL`, `Rig/HipR` and the aft pair | 1368+ | **nothing.** `walker.gd`'s gait already drives them and the planted pose is their rest pose |

`bastion.gd`'s state, with the numbers as exports so they are tunable without a
recompile:

```gdscript
enum Stance { WALKING, PLANTING, PLANTED, UNPLANTING }

@export var plant_seconds: float = 1.6          # the animation, both ways
@export var walk_speed: float = 2.4             # move_speed while WALKING
@export var unplant_range: float = 70.0         # fight moved further than this -> get up
```

- **`move_speed` is the state.** `build_bastion.gd:575-581` records that
  `enemy.gd` handles zero cleanly (`base_dir * move_speed` is simply zero, and
  the one place that would divide guards itself with `maxf(move_speed, 1.0)` at
  `enemy.gd:1736`). So `PLANTED` sets `move_speed = 0.0` and `WALKING` sets it
  to `walk_speed`. **Scene values beat script defaults** (`CLAUDE.md`): the
  `.tscn` ships 0.0, which is right — the frame is born planted.
- **When to plant.** The simplest honest version, from the design doc §6.2:
  **plant on first contact, unplant if the fight moves beyond
  `unplant_range`.** Hook it to `trigger_combat(body)` (`enemy.gd:5155`,
  overridden by `soldier.gd:320` — call `super()` first) rather than polling.
- **Drive the transition with a tween, not a coroutine.** `MEMORY.md` records
  that `await` on `process_frame` at quit segfaults in cleanup; use a tween
  chain. One tween per group (`Rams`, `Mast` + `Canopy`, `Skirts`), and the
  `Lenses` emission switched at the end of the planting tween and at the start
  of the unplanting one.
- **Interruptibility.** A Bastion killed mid-plant must not leave a tween
  running on a freed node. Kill the tweens in `die()`.

**Open, and for the human:** §8 of the design doc asks whether it should plant
automatically or only at authored positions, and whether a planted Bastion
should be immune to being shoved. On the second — `enemy.gd:1714`'s
`_damp_shoving` exists and a hardpoint that can be nudged out of its own
outriggers is not a hardpoint. I would set `motion_mode`/shove damping aside and
simply assert position stability in §6, then let the human look.

### 4.4 The resistance field — and why it needs two lines in `ai.gd`

**Read `signal_resistance` first.** It is a plain `@export` on `AI`
(`ai.gd:67`), base 1.0, with **no stack, no timer and no accessor**, and it is
read in exactly two places:

- `receive_signal_damage` (`ai.gd:117`): `var actual: float = amount /
  maxf(signal_resistance, 0.01)`
- `lock_signal` (`ai.gd:138`): `_signal_locked_t = maxf(_signal_locked_t,
  seconds / maxf(signal_resistance, 0.01))`

So raising it both softens suppression and shortens an EMP lock — which is
exactly the systems the player has just gained, and is why the ceiling matters
(design doc §4: "anything near 3.0 would make a Bastion squad effectively
immune to suppression, which is not a fight, it is a wall").

**`docs/frames/BASTION.md` §6.1 is right that mutating it is fragile, and its
proposed fix does not go far enough.** It recommends "a `_resistance_bonus`
additive field that is recomputed from scratch each tick". The problem with
mutate-on-entry / divide-on-exit is well stated there — two overlapping
Bastions, or one dying mid-effect, leaves a robot permanently hardened. But a
per-tick recompute has to run **on the receiver**, and a receiver frozen by the
distance cull has its `_physics_process` switched off entirely
(`ai_manager.gd:576-593`, `Enemy._freeze_for_cull` at `enemy.gd:2122`) — so it
cannot recompute, and it keeps whatever it was last given, forever. The Bastion
being culled has the same effect from the other side.

**Recommendation: a stamp with an expiry, read through an accessor. Neither end
has to be running.** In `ai.gd`, next to `signal_resistance`:

```gdscript
## A hardening field somebody else is holding over this robot, as a STAMP
## rather than a mutation: whoever projects it writes it every tick with an
## expiry, and nothing ever has to take it off.
##
## WHY NOT MUTATE signal_resistance. It is a plain export with no stack and no
## timer, so multiply-on-entry / divide-on-exit means: two overlapping
## projectors double it and only one divides back; a projector that dies
## mid-effect never divides back at all; and a projector frozen by the distance
## cull has its _physics_process switched off (ai_manager.gd:576-593), so it
## cannot run an exit path even in principle. Every one of those leaves a robot
## permanently hardened, in silence, which is the expensive kind of bug.
##
## WHY NOT "RECOMPUTE FROM SCRATCH EACH TICK" EITHER, which is where
## docs/frames/BASTION.md section 6.1 stops: the recompute would have to run on
## the RECEIVER, and a culled receiver's tick is off too. An expiry is the only
## version that is correct when either end is frozen.
var _hardening_bonus: float = 0.0
var _hardening_until: float = 0.0

## MAX, NOT SUM: two Bastions are not twice as good as one. The design doc's
## own ceiling argument ("not a fight, a wall") is unenforceable under a sum.
func add_hardening(bonus: float, seconds: float) -> void:
	var now: float = float(Time.get_ticks_msec()) * 0.001
	if now > _hardening_until:
		_hardening_bonus = 0.0        # the old stamp had already lapsed
	_hardening_bonus = maxf(_hardening_bonus, bonus)
	_hardening_until = maxf(_hardening_until, now + seconds)

## What ai.gd:117 and ai.gd:138 divide by. Everything else keeps reading
## signal_resistance, which is still the robot's own permanent figure.
func effective_signal_resistance() -> float:
	if float(Time.get_ticks_msec()) * 0.001 > _hardening_until:
		return signal_resistance
	return signal_resistance + _hardening_bonus
```

and then **the two lines**: `ai.gd:117` and `ai.gd:138` change
`maxf(signal_resistance, 0.01)` to `maxf(effective_signal_resistance(), 0.01)`.
Nothing else in the project reads `signal_resistance` at runtime — the other
hits are `enemy_loadouts.gd:431` and `squad_spawner.gd:355`, which **add to** it
at spawn from module bonuses, and `squad_page.gd:1166-1169`, which displays the
player's own total. All three keep working unchanged, and all three are additive,
which is why the bonus is additive and not a multiplier.

**Additive, with the design doc's multiplier translated.** The doc asks for
"a multiplier around 1.6 for units inside". Base `signal_resistance` is 1.0
(`ai.gd:67`), so `+0.6` additive is the same number on a stock frame and
composes correctly with a module's `signal_resistance_bonus` instead of
multiplying with it.

Then `bastion.gd`:

```gdscript
@export var field_radius: float = 14.0          # design doc section 4
@export var field_bonus: float = 0.6            # additive; 1.0 base -> 1.6x
@export var field_interval: float = 0.4         # seconds between stamps
```

`_tick_field()`, on an interval and only while `PLANTED`:

```gdscript
# ALLY MEANS SAME FACTION, NOT "NOT HOSTILE". are_hostile(STRATCOM, SWARM) is
# FALSE by the recommendation in BROODCARRIER.md section 0.2 — the three enemy
# factions are deliberately not hostile to each other — so a "not hostile"
# filter would harden every Swarm and Argus unit in the radius, and NEUTRAL
# too. Nothing warns, and the symptom is a Bastion making somebody else's army
# tougher.
for n in get_tree().get_nodes_in_group(AI.SIGNAL_GROUP):
	if n == self or not (n is AI):
		continue
	if not ("faction" in n) or n.faction != faction:
		continue
	if global_position.distance_squared_to((n as Node3D).global_position) > field_radius * field_radius:
		continue
	(n as AI).add_hardening(field_bonus, field_interval * 2.5)
```

Four things in that loop that are not arbitrary:

- **`AI.SIGNAL_GROUP`, not `"enemies"`.** `ai.gd:86-88` joins it in `AI._ready`
  for everything with a `signal_integrity`, robots and the player alike —
  `ai.gd:80-85` records that EMP used to sweep `"enemies"`, which the player is
  not in. The group is the right sweep for anything that touches the signal
  layer. `Character/weapon/emp/emp_blast.gd` is the shipped example of this
  idiom.
- **`n == self` is excluded**, so the frame does not harden itself on top of its
  own `signal_resistance = 2.0`.
- **the expiry is `field_interval * 2.5`**, comfortably longer than the gap
  between stamps so there is no flicker, and short enough that the effect is
  gone within a second of the Bastion dying, being culled, or the neighbour
  walking out.
- **`get_nodes_in_group` every 0.4 s, not every frame.** `MEMORY.md` records
  that mines were the single most expensive thing in the game (68 ms of 128 ms
  of script time) partly on group sweeps. On a 186-robot level this is one group
  walk per planted Bastion per 0.4 s; measure it in §7 step 5 and say the number.

**No falloff in the first pass.** The design doc §6.1 asks for one; a hard edge
at 14 m is easier to read, easier to test, and matches the canopy's own
geometry. Add falloff only if the human says the edge feels wrong.

---

## 5. Registration

Walked against `FRAME_ANATOMY.md` §1. **S** = fails silently.

| § | item | status |
|---|---|---|
| 1.1 | `bastion.tscn`, `tools/build_bastion.gd` | **done.** Do not re-run the generator |
| 1.2 #1 | `Campaign/chassis/chassis_bastion.tres` | **to do.** §2 |
| 1.2 #2 | root script resolves to `Soldier` | **done** — `walker.gd extends Soldier`; `bastion.gd extends Walker` keeps it. Hard error at spawn if broken (`enemy_force_spawner.gd:265-267`) |
| 1.2 #3 | `groups=["enemies"]` | **done**, `bastion.tscn:616` |
| 1.2 #4 | `kill_kinds.gd` `FRAMES` | **to do — S.** `&"bastion": "res://Campaign/chassis/chassis_bastion.tres"` into `kill_kinds.gd:14-37` |
| 1.2 #5 | `Allowed*Options` | **to do — S, and this is the live defect.** §4.2 |
| 1.3 | catalogue, `purchasable`, icons | **deliberately not done.** `purchasable = false`, and **no** entry in `Campaign/items & catalogue/test_item_catalogue.tres` |
| 1.4 #9 | a mission `.tres` | **to do.** §5.1 |
| 1.4 #10 | `Enums.Factions` + `are_hostile` | **`BROODCARRIER.md` §0. The blocker** |
| 1.5 #11 | `kill_kinds.gd` `SCENES` | **not needed.** Basename `bastion` == id `bastion`, and `kind_of` falls through to `SCENES.get(base, StringName(base))` (`kill_kinds.gd:70`). Same reason the Bulwark has none |
| 1.5 #12 | `enemy_loadouts.gd` `TABLES` | **do not add one.** `module_slots = 0`, one weapon mount, and the only gun it can hold is the one in `starting_weapon_id`. `enemy_loadouts.gd:109-113` records the Bulwark's identical reasoning. `roll_for` returns `{}` for an unlisted frame (208-210), and adding a key commits you to `test_enemy_loadouts.gd:91-124` |
| 1.5 #13 | `cosmetics.gd` | **no.** `for_frame` returns `[NONE]` (84-90) |
| 1.5 #14 | mission `unlocks` | **N/A**, not purchasable |
| 1.5 #15 | a lab plan | **yes, and it is not optional here.** §7 step 5. `bulwark_screen.tres` is the precedent |
| 1.5 #16 | `tools/test_bastion.gd` | **to do.** §6 |
| 1.5 #17 | `probe_nav_reach.gd` `FRAMES` | **yes.** It is 3.44 m wide on four legs and it walks before it plants. `MEMORY.md`: the navmesh bake is the only clearance Godot enforces, and radius/climb quantise silently to cell units. Values from `tools/probe_chassis_size.gd` |
| 1.6 | CSG bake, teams, `"signal"` group, `AIManager` registration | **all free.** `vehicle = true` is the whole of the team assignment (`campaign_state.gd:468-496`); `_CsgBake` reads the directory (`csg_bake.gd:177-189`), which matters here because this frame has real `CSGMesh3D`/`CSGBox3D` nodes (`bastion.tscn:897-911`, `1098-1111`, `1291-1305`) |

**Icons: run `tools/bake_icons.gd` and report whether they landed.** The
`FRAMES` entry is what makes the frame bakeable (`bake_icons.gd:120-129`).
`FRAME_ANATOMY.md` §6.3 and §8.3: nothing asserts icons exist, which is how the
Bulwark has gone without since it was built, and `icons/chassis/` confirms no
`bulwark_*.png`.

### 5.1 The mission entry

`mission_salient_1_overthetop.tres` is the Bulwark's worked example — the
`[ext_resource]` at line 11, an `EnemySquadSpec` sub-resource block at 20-40,
`faction` at 35. Two edits:

1. `[ext_resource type="Resource" path="res://Campaign/chassis/chassis_bastion.tres" id="…"]`;
2. the chassis in an `EnemySquadSpec.roster`, with `faction = 5` (STRATCOM).
   `roster` is `Array[ChassisDefinition]` (`enemy_squad_spec.gd:46`) and is on
   `FRAME_ANATOMY.md` §6.6's list of typed arrays that pack as `[]` in silence.

**Field it *with* a squad, and that is the opposite of the Broodcarrier.** The
whole unit is "the squad around it is harder to suppress", so one Bastion in a
roster of six to eight riflemen in one `EnemySquadSpec` — one faction, one
`post_tag`, inside the 14 m radius. A solo Bastion has nothing to harden and
demonstrates nothing.

**`activation_distance = 200` on the scene** (`build_bastion.gd:571`).
`FRAME_ANATOMY.md` §6.13 / `enemy_force_spawner.gd:537-546`: `always_active`
does **not** exempt a frame from the distance cull, so a Bastion authored to
walk in from off-map has to be walked in by `_let_them_walk_in`
(`enemy_force_spawner.gd:570`). Relevant because this frame's first state is
WALKING.

---

## 6. Tests

New file `tools/test_bastion.gd`. `tools/test_bulwark.gd` is the model — its
`_test_the_chassis_is_registered` (70-90) is §5 of this brief as a test, its
`_ok` reporter is at 52, and `_test_the_eye_keeps_its_own_colour` (186-232) is
the livery assertion to copy. `tools/test.sh` picks it up with no wiring.

**The task-zero assertion:**

```gdscript
_ok("hostile to the player, outbound",
	Enums.are_hostile(Enums.Factions.PLAYER, Enums.Factions.STRATCOM))
_ok("hostile to the player, inbound",
	Enums.are_hostile(Enums.Factions.STRATCOM, Enums.Factions.PLAYER))
```

Both directions, because `BROODCARRIER.md` §0.1 shows they fail differently:
outbound-false makes it untargetable, inbound-false makes it refuse its own
shot through `_is_friendly` → `friendly_in_line`.

Then:

- **registered:** `chassis_bastion.tres` loads; `id == &"bastion"`,
  `supply == 3`, `purchasable == false`, `cost == 0`, `weapon_slots == 1`,
  `turret == true`, `starting_weapon_id == &"heavy_mg"`,
  `base_sensor_range == 60.0`; `KillKinds.FRAMES.has(&"bastion")` and
  `frame_of(&"bastion") != null`
- **not in the player catalogue:** load
  `Campaign/items & catalogue/test_item_catalogue.tres` (the path
  `test_bulwark.gd:86` hard-codes) and assert nothing in `chassis` has
  `id == &"bastion"`
- **THE GUN FITS, AND KEEPS FITTING.** `frame.takes(catalogue.item(&"heavy_mg"))`
  is **true**. This is §3.1 as one assertion, and it is the Bulwark's bug caught
  at the point it would be introduced. Add the inverse for the Bulwark in the
  same file if you took the family sweep: `chassis_bulwark.tres.takes(heavy_mg)`
  should also be true once fixed
- **the option arrays:** `AllowedCombatOptions == [1, 2]` read off the
  instantiated scene — **not off the script default.** `CLAUDE.md`: scene values
  beat script defaults. And assert the type: `typeof` of the array's elements is
  int, which is the §4.2 annotation fix
- **a fitted weapon points forward:** instantiate, `equip_weapon_scene` with
  `ai-wep_heavy_mg.tscn`, and assert the muzzle's forward is within a few
  degrees of the turret's. `build_bastion.gd` put `WeaponMount` at yaw
  **+PI/2** (`bastion.tscn:925`) and its header records that the Bulwark's first
  build had the sign backwards — the gun fitted, elevated, tracked and fired
  directly behind the frame, and nothing warned. `test_bulwark.gd:233-272` is
  the model
- **the `turret` node is non-null**, so `enemy.gd:2893`'s `hull_spoils_aim` is
  excused and the frame settles its aim while moving
- **planted vs walking:** force `Stance.PLANTED` and assert `move_speed == 0.0`,
  the `Lenses` emission on, the `Rams` at `PLANT_LEAN`; force `WALKING` and
  assert `move_speed == walk_speed`, emission off, `Rams` near 0. Read the nodes
  by the paths in §4.3
- **a planted Bastion refuses orders:** `order_move_to(somewhere_far)`, step
  physics, assert `global_position` has not moved and `movement_state` is not
  `MOVING`
- **the field hardens its own faction:** a STRATCOM neighbour at 5 m has
  `effective_signal_resistance() > signal_resistance`; one at 25 m does not
- **A SWARM NEIGHBOUR AT 5 m DOES NOT.** §4.4's "same faction, not
  not-hostile". The assertion is only meaningful once
  `are_hostile(STRATCOM, SWARM)` is false, which is `BROODCARRIER.md` §0.2's
  recommendation — assert that too in the same test, so the day somebody makes
  the enemy factions mutually hostile this test says why it matters
- **a NEUTRAL neighbour at 5 m does not.** The other half of the same trap:
  `are_hostile(anything, NEUTRAL)` is false
- **the bonus is removed cleanly when the Bastion dies.** Harden a neighbour,
  `bastion.die()`, advance time past the stamp expiry, and assert
  `effective_signal_resistance() == signal_resistance`. **The fragile case the
  design doc names, and the reason for the expiry.** Note the test has to
  advance *time*, not just frames — the expiry is on
  `Time.get_ticks_msec()`, so either step real physics frames or make the clock
  injectable
- **the bonus survives the receiver being culled.** Harden a neighbour, call
  `_freeze_for_cull()` on it (`enemy.gd:2122`), and assert the value is still
  correct, then advance past the expiry and assert it has lapsed. **This is the
  assertion that distinguishes the stamp design from the per-tick recompute**
  and the one §4.4 exists for
- **two overlapping Bastions do not stack into immunity:** two at 5 m from one
  neighbour, and `effective_signal_resistance()` equals
  `signal_resistance + field_bonus`, not `+ 2 * field_bonus`
- **suppression actually lands less hard:** `receive_signal_damage(X)` on a
  hardened and an unhardened neighbour and compare the `signal_integrity` drop.
  Asserts §4.4's two-line `ai.gd` edit end to end rather than just the accessor
- **the eye keeps its own colour:** `Rig/Turret/Eye` (`bastion.tscn:912`) and
  the four `Rig/Mast/Canopy/Lenses/Lens*` are **not** in the `FactionLivery`
  `pieces` array and survive `apply()`; the rest of the frame did get painted.
  `build_bastion.gd:218-222` records that the Bulwark's eye ended up
  faction-coloured despite being left off a list that was never there
- **groups and typed arrays:** `is_in_group("enemies")` **and**
  `is_in_group(AI.SIGNAL_GROUP)` (`test_bulwark.gd:120-127`), plus
  `visible_pieces`, `particle_effects_die`, `particle_effects_hit` all
  non-empty, and all seven rig node paths resolving

**And the whole suite, because §4.4 touches `ai.gd`.** `ai.gd` is the base of
every robot and the player. `bash tools/test.sh` in full, with
`tools/test_signal.gd` specifically green, is the regression evidence — not just
`test_bastion.gd`.

```bash
bash tools/check.sh --changed              # must print PASS
bash tools/test.sh                         # in full: ai.gd is shared
bash tools/smoke.sh
"D:/Godot Games/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe" \
  --headless --audio-driver Dummy --path . \
  --script res://tools/check_frame.gd -- res://Character/characters/ai/bastion.tscn
```

**Not while `tools/test.sh` is in flight** — the suites share `user://` probe
paths and a parallel run produces a FAIL that looks real and does not reproduce.

---

## 7. Order of work

1. **`BROODCARRIER.md` §0 — `are_hostile` as a table,
   SWARM/STRATCOM/ARGUS appended, `tools/test_factions.gd` green.** A STRATCOM
   Bastion on today's `enums.gd` never fires, is never targeted, and hardens
   nothing, and every test below would pass or fail for the wrong reason.
   **Prove:** all seven assertion groups, including the regression lock on the
   original sixteen pairs, and `bash tools/test.sh` green across the suite.
2. **`chassis_bastion.tres`, the `kill_kinds.gd` entry, the `heavy_mg`
   whitelist line, and the `Array[int]` type fix in `bastion.tscn`.** No new
   script yet. **Prove:** the "registered", "not in the catalogue",
   "the gun fits", "a fitted weapon points forward" and "`turret` is non-null"
   assertions, plus `check_frame.gd` clean and the two `Array[Object]` load
   errors gone.
3. **`AllowedCombatOptions = [1, 2]`, still with no `bastion.gd`.** The frame
   is now a Walker-shaped turret that bursts properly. **Prove:** field it in
   one mission at `faction = 5`, run `smoke.sh`, and watch it fire a *burst*
   rather than single shots — that is `FRAME_ANATOMY.md` §6.1 observed, and it
   is the cheapest real improvement in this brief.
4. **`bastion.gd` — plant/unplant only.** No field yet. **Prove:** the
   planted/walking assertions, the order-refusal assertion, and a look at it:
   `tools/mockup_shots.gd` from four bearings in both states, because
   "legible from any angle" is §1's first mandatory item and cannot be
   asserted.
5. **The field — `ai.gd`'s two lines plus `_tick_field`.** **Prove:** every
   field assertion in §6, the full `tools/test.sh`, and a cost number: time
   `_tick_field` on a level with a planted Bastion and a full roster.
   `MEMORY.md` — measure CPU, not wall clock, and pace the loop with
   `Engine.max_fps = 60` or you measure `_process` starving physics.
6. **A lab plan and then the human.** `Campaign/lab/plans/*.tres`
   (`bulwark_screen.tres` is the precedent): the same squad with and without a
   Bastion, against the same player squad, to put `field_bonus` on a measured
   number instead of 0.6. Then the human plays it, because §1's second
   mandatory item — "the player can see that their suppression is not landing"
   — is a feel judgement and `CLAUDE.md` says that is theirs.

---

## 8. Open questions and risks

**For the human:**

1. **STRATCOM or Home Command?** `BROODCARRIER.md` §0.2. `HEAD` says StratCom;
   the working tree has been renamed to "Home Command" by another agent,
   uncommitted. The enum identifier is permanent (`FRAME_ANATOMY.md` §2.5), so
   this is a decision, not a cleanup.
2. **`field_bonus`.** 0.6 additive (= the doc's 1.6×) is a guess and the
   ceiling is "not a wall". §7 step 6 gets measured numbers in front of you.
3. **Plant automatically, or only at authored positions?** The design doc §8
   leaves it open. Automatic on first contact is simpler and I have specified
   it; authored is more controllable for mission design and less interesting in
   a fight.
4. **Should a planted Bastion be immune to shoving?** `enemy.gd:1714`'s
   `_damp_shoving` can push it. A hardpoint that can be nudged out of its own
   outriggers is not a hardpoint, but making it immovable is a physics change
   and I would rather you looked at it first.
5. **Falloff on the field edge, or a hard edge at 14 m?** I have specified a
   hard edge (§4.4) because it is readable and testable.

**Risks:**

6. **`ai.gd` is the base of every robot and the player.** §4.4's two lines are
   in the suppression and EMP-lock paths. This is the highest-blast-radius edit
   in the whole frame batch, and it is why §7 makes the full `tools/test.sh` the
   gate at step 5 rather than `test_bastion.gd`.
7. **The group sweep.** One `get_tree().get_nodes_in_group(AI.SIGNAL_GROUP)`
   walk per planted Bastion per 0.4 s. `MEMORY.md` records mines as the single
   most expensive thing in the game at 68 ms of 128 ms of script time, partly on
   exactly this shape. Measure it (§7 step 5). If it bites, the fix is
   `AIManager` caching the group the way `hostiles_for` already caches hostiles
   for 0.4 s (`ai_manager.gd:117`, `140-144`) — do **not** reach for that
   pre-emptively.
8. **The culled Bastion stops projecting.** `_physics_process` is switched off
   entirely by the distance cull, so a frozen Bastion stops stamping and the
   stamps lapse within a second. Correct behaviour, invisible mechanism —
   comment it, or it gets "fixed".
9. **The `WeaponMount` yaw sign.** `+PI/2`, and `build_bastion.gd:364-368`
   records that getting it backwards gives a gun that fits, elevates, tracks and
   fires *behind* the frame with nothing warning. §6 asserts it. Do not change
   it on inspection.
10. **`built_in = "EMITTER"` is a blank icon** (`icons.gd:63-66`; no
    `icons/items/emitter_*.png`). Cosmetic on a hostile frame, stated so it is
    not discovered.
11. **The plant tween and death.** A Bastion killed mid-transition must not
    leave a tween driving a freed node. `MEMORY.md`: coroutines must not outlive
    the tree — kill the tweens in `die()`, and this is a crash, not a
    cosmetic.

---

# AMENDMENT — 2026-10-10, human review.

**The `shield_projector` stays an item. The recommendation above to cut it is
overruled.**

The human's words: *"bastion can have a special weapon as well."* So the
hardening field is a fitted weapon on the mount, not `built_in = "EMITTER"`
plus code.

What that changes from §3:

- The `ItemDefinition` **is** written. `kind = 0`, `base_damage = 0`,
  `usable_by_player = false`, whitelisted to `[&"bastion"]` and nothing else.
  The precedent is the **Reclaimer**, not the repair lance — see
  `FRAME_ANATOMY.md` §3.3 and the correction block in `docs/frames/DRAYMAN.md`.
- **The frame carries two things and has one mount.** §2 gives it
  `weapon_slots = 1` and `starting_weapon_id = &"heavy_mg"`. Decide and state
  how the projector and the MG coexist: a second mount on the model, the
  projector as the `built_in` the MG replaces, or the MG dropped. The model
  has one `WeaponMount` today, so if the answer needs two this becomes a model
  change and must be reported rather than improvised.
- **The hardening mechanism is unchanged.** §4's stamp-with-expiry read
  through an accessor still stands, and the reason still stands: a receiver
  frozen by the distance cull has `_physics_process` off and would keep a
  recomputed bonus forever. An item wrapping it does not change that.

`heavy_mg` now whitelists `bastion` (added 2026-10-10), so §3.1's blocker is
cleared.

---

# AMENDMENT — 2026-10-10, human review. THE FACTION IS **HOME COMMAND**.

The human's words: *"homecommand etc was requested and is fine."*

So the rename another lane made on disk is intended, and §0's enum must follow
it. **Do not write `STRATCOM`.** Match whatever identifier the working tree
already uses — `hud_palette.gd` has `FAC_HOME`, not `FAC_STRATCOM`, so
`HOME` is the likely answer; **read the file and match it rather than
inventing a third spelling.**

This is not cosmetic. `FRAME_ANATOMY.md` §2.5 establishes that a faction's
enum identifier is permanent the day a kill is saved against it, for the same
reason the quadcopter bomber is still called `gunship` in `kill_kinds.gd:21`.
Getting it wrong costs a rename table forever.

Check all five mechanical append sites for the same spelling before writing
any of them: `Managers/enums.gd`, `faction_livery.gd`'s `COLORS`,
`hud_palette.gd`, `kill_kinds.gd`'s `FRAMES`, and the two hardcoded
`== ENEMY` comparisons at `squad_commander.gd:756` and `ai_manager.gd:497`.
