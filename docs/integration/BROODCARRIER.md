# BROODCARRIER — integration brief

Swarm · supply 2 · aerial · spawner · enemy only · **model built, nothing registered**

Written for a builder. The map is `docs/briefs/FRAME_ANATOMY.md`; this document
cites it by section instead of restating it. Everything else carries a
`file:line`.

**What exists today:** `Character/characters/ai/brood.tscn` — root node
`Broodcarrier`, a `CharacterBody3D` with `groups=["enemies"]`
(`brood.tscn:306`), root script `spotter_drone.gd` — and
`tools/build_brood.gd`. There is no `ChassisDefinition`, no `kill_kinds` entry,
no behaviour script, no mission entry, and no `Enums.Factions.SWARM` for it to
belong to.

**This file also carries section 0, the prerequisite shared by all three enemy
frames.** `docs/integration/BASTION.md` and `docs/integration/SEE_ENGINE.md`
reference it rather than repeating it. Section 0 is the first work in all three
orders of work.

---

## 0. SHARED PREREQUISITE — `are_hostile` must become a table

Owner: whoever starts first of the three. The other two briefs point here.

### 0.1 What I verified, and what I could not

`docs/frames/ENEMY_FACTIONS.md` was written before the models existed. I
re-checked its three load-bearing claims against the current working tree.

**CONFIRMED — the enum and the function.** `Managers/enums.gd:9` is still
`enum Factions { PLAYER, ENEMY, ALLIED, NEUTRAL }`. `are_hostile`
(`enums.gd:26-38`) still matches four values and still falls out to
`return false` on line 38. There is no default arm and no `push_error`.

**CONFIRMED — the `_is_friendly` claim, and it is worse than stated.**
`Character/weapon/ai_weapon.gd:314-320`:

```gdscript
func _is_friendly(body: Node) -> bool:
	var mine = _owner_faction()
	if mine == null:
		return false
	if not body.has_method("get_faction"):
		return false
	return not Enums.are_hostile(mine, body.get_faction())
```

With an unknown faction on the *shooter*, `are_hostile` returns false for every
body in the world, so `_is_friendly` returns **true** for every body in the
world. That reaches three places, not one:

- `friendly_in_line()` (`ai_weapon.gd:325`, the check at `371-372`) returns true
  the moment any body is between muzzle and target — **the frame refuses its own
  shot**;
- `_one_round()` (`ai_weapon.gd:463-465`) applies `friendly_fire_multiplier` to
  everything it hits and emits `friendly_hit`;
- `check_melee_damage` (`ai_weapon.gd:590`) skips every body in the sweep, so a
  melee frame swings through its target.

**CONFIRMED — the call-site count, exactly.** `grep -rn "Enums\.are_hostile("
--include=*.gd` in the main checkout (worktrees excluded) returns **35 calls**,
of which 31 are in game code and 4 in `tools/`. Per file: `enemy.gd` 5,
`ai_manager.gd` 4, `analytics.gd` 2, `mine.gd` 2, `explosion.gd` 2,
`ai_weapon.gd` 2, `player_repair_tool.gd` 2, and one each in `tracer.gd`,
`hud_weapon_template.gd`, `hatchling_payload.gd`, `emp_blast.gd`,
`squad_hud.gd`, `player_repair_lance.gd`, `squad_commander.gd`,
`possession.gd`, `ai_repair_kit.gd`, `diver.gd`, `enemy_force_spawner.gd`,
`eliminate_objective.gd`. The audit's "thirty-five" is right on the nose.
**None of the 35 errors, warns or logs when the answer is wrong.**

**CONFIRMED — the two hardcoded `== ENEMY` comparisons, and there are exactly
two.** `Character/components/squad_commander.gd:756`
(`(ai as Enemy).faction != Enums.Factions.ENEMY`) and
`Managers/ai_manager.gd:497` (`requesting_ai.faction == Enums.Factions.ENEMY`).
The first is the audit's "new factions never hear the player's transmit".

**CONFIRMED — the graceful tables.** `faction_livery.gd:23-28` is a Dictionary
read through `COLORS.get(faction, COLORS[Enums.Factions.NEUTRAL])`
(`faction_livery.gd:125`) — a missing key renders grey, it does not crash.
`hud_palette.faction_color` (`hud_palette.gd:72-79`) has a `_:` arm returning
`FAC_SWARM`, so all three new factions render amber until arms are added. The
three colours are already written and unused: `FAC_SWARM`, `FAC_HOME`,
`FAC_ARGUS` at `hud_palette.gd:63-65`.

**CONFIRMED — missions can already name a faction.**
`Campaign/enemy_squad_spec.gd:103` is
`@export var faction: Enums.Factions = Enums.Factions.ENEMY`, and
`Campaign/enemy_force_spawner.gd:270` is `soldier.faction = spec.faction`,
executed before `add_child` so `AI._ready()` sees it. Writing `faction = 4` in
a mission `.tres` spawns a Swarm squad the day the enum value exists. No schema
change.

**CORRECTED — the on-disk count, and the claim that every value is `1`.** The
audit says "805 places … every single one of them is `1`". Current count across
`.tres` and `.tscn` project-wide: **816 × `faction = 1`, 6 × `faction = 2`
(ALLIED), 1 × `faction = 0` (PLAYER)**, plus 9 × `editor_preview_faction = 1`.
Within `Campaign/missions/` alone (including the new `appendix/` subfolder):
530 lines across 27 files, all `= 1`. So the number has drifted and "every
single one is 1" is false. **The conclusion is unaffected** — every value on
disk is inside the existing `0..3` range, so appending at the end is still a
literal no-op for all of them, and reordering would still silently repoint
every hostile in the game.

**COULD NOT CONFIRM — `contact_overlay.gd`'s "hardcoded `[ALLIED, ENEMY]`
list".** I found it, but it is not a bug worth listing with the others: it is
the debug contact overlay's `_gather()` (`Character/hud/contact_overlay.gd:62`),
a developer readout gated behind debug tools, and the consequence is that an
enemy faction's contact table is absent from a diagnostic panel. Listed
accurately rather than as a defect.

**COULD NOT CONFIRM — any plan for `hud.gd`'s filter.** See
`docs/integration/SEE_ENGINE.md` §1; `Character/hud/hud.gd:71-72` filters
contact marks to ALLIED only, which is a real consequence for the See-Engine
and no consequence at all for this frame.

### 0.2 What "rewrite `are_hostile` as a table" means in code

Append at the end of `Factions` — `Managers/enums.gd:9` — giving
`SWARM = 4`, `STRATCOM = 5`, `ARGUS = 6`. Append only; `FRAME_ANATOMY.md` §2.5
records that these are stored as raw ints in `.tscn` and `.tres`.

Then replace `enums.gd:26-38` with:

```gdscript
## Who attacks whom, as data.
##
## A TABLE, NOT A MATCH. The match this replaced had four arms and fell out to
## `return false`, so appending a fifth Factions value made every robot
## carrying it simultaneously invisible AND near-invulnerable, in both
## directions, across thirty-five call sites, not one of which errors.
## GDScript does not warn on a non-exhaustive match on an enum. The whole
## audit is docs/frames/ENEMY_FACTIONS.md.
##
## Keyed by the ATTACKER; the value is everything it attacks. A faction with no
## row still gets a wrong answer — but it is now a wrong answer that
## push_errors and that tools/test_factions.gd fails on, instead of one that
## ships silently.
##
## THE THREE ENEMY FACTIONS ARE NOT HOSTILE TO EACH OTHER, and that is a
## performance decision, not a fiction one. AIManager.activation_sources()
## (ai_manager.gd:546) is built from hostiles_for() (358), and
## nearest_hostile_distance_sq() (564) is the only thing that wakes a frozen
## robot. Make two hostile forces each other's activation sources and they keep
## each other awake across the whole map, and the distance cull stops culling.
const HOSTILITY := {
	Factions.PLAYER:   [Factions.ENEMY, Factions.SWARM, Factions.STRATCOM, Factions.ARGUS],
	Factions.ENEMY:    [Factions.PLAYER, Factions.ALLIED],
	Factions.ALLIED:   [Factions.ENEMY, Factions.SWARM, Factions.STRATCOM, Factions.ARGUS],
	Factions.NEUTRAL:  [],
	Factions.SWARM:    [Factions.PLAYER, Factions.ALLIED],
	Factions.STRATCOM: [Factions.PLAYER, Factions.ALLIED],
	Factions.ARGUS:    [Factions.PLAYER, Factions.ALLIED],
}

static func are_hostile(faction_a: Factions, faction_b: Factions) -> bool:
	var row = HOSTILITY.get(faction_a)
	if row == null:
		# LOUD, because the silent version of this cost a whole frame batch.
		push_error("Enums.are_hostile: Factions value %d has no HOSTILITY row. Everything is about to read as friendly to it." % int(faction_a))
		return false
	return (row as Array).has(faction_b)
```

Two things to note about this table rather than assume:

- **It reproduces the old function exactly for the original four.** The old
  code's first line was `if faction_b == Factions.NEUTRAL: return false`;
  the table reproduces that by never listing NEUTRAL in any row. All sixteen
  original pairs agree. Check this before anything else — see §6 of this brief.
- **`NEUTRAL: []` is a row, not an omission.** It has to be present or the
  `push_error` fires on a faction that is working correctly.

Then the mechanical appends, which do not error if skipped and should be done
in the same change so nobody has to remember them:

| file:line | what |
|---|---|
| `faction_livery.gd:23-28` | three `COLORS` entries. Skipped → all three render grey |
| `hud_palette.gd:72-79` | three `match` arms using `FAC_SWARM`/`FAC_HOME`/`FAC_ARGUS` (63-65). Skipped → all three render Swarm amber |
| `squad_commander.gd:756` | `!= Enums.Factions.ENEMY` → `Enums.are_hostile(Enums.Factions.PLAYER, (ai as Enemy).faction)`. Skipped → **the new factions never hear the player's transmit** |
| `ai_manager.gd:497` | same shape |
| `contact_overlay.gd:62` | add the three to the debug list. Cosmetic |

**A naming conflict you will hit, and it is not mine to settle.** `HEAD` uses
**StratCom** (`git grep -l StratCom HEAD` → `lore.txt`, `CLAUDE.md`,
`campaign_state.gd`, `docs/frames/*`). The **working tree has been mass-renamed
to "Home Command"** by another agent, uncommitted — on-disk `CLAUDE.md:8,14,16,29`,
`docs/frames/BASTION.md`, `docs/frames/SEE_ENGINE.md`, `docs/frames/README.md:46`,
`campaign_state.gd:101,575`. `grep -c StratCom CLAUDE.md` is 0 on disk and
non-zero in `HEAD`. I have used **`STRATCOM`** as the enum identifier, because
that is the committed name and the identifier is the thing `FRAME_ANATOMY.md`
§2.5 makes permanent. **Ask the human before writing it.** Note that the
display name is a separate, non-permanent decision, and that
`hud_palette.gd:64` already ships the colour constant as `FAC_HOME`.

### 0.3 The test that protects it

New file `tools/test_factions.gd` — `tools/test.sh` runs every
`tools/test_*.gd`, so it is free to wire. Model it on `tools/test_bulwark.gd`'s
`_ok(label, cond, detail)` reporter (`test_bulwark.gd:52`). Seven assertions,
and the first is the one that matters most:

1. **Every `Factions` value has a row.**
   `for v in Enums.Factions.values(): assert HOSTILITY.has(v)`. This is the
   assertion that makes the *next* append fail loudly instead of repeating
   this bug. Nothing else in the suite does that.
2. **Regression lock on the original four.** All sixteen ordered pairs of
   PLAYER/ENEMY/ALLIED/NEUTRAL, asserted against the hardcoded truth table of
   the old `enums.gd:26-38`. Proves the rewrite changed no existing behaviour.
3. **The three new factions are hostile to PLAYER in both directions.**
   `are_hostile(PLAYER, SWARM)` and `are_hostile(SWARM, PLAYER)`, and the same
   for STRATCOM and ARGUS. Six assertions.
4. **And to ALLIED in both directions.** Six more.
5. **The three are NOT hostile to each other, in either direction** — six
   assertions, and they are the cull invariant from §0.2 written down.
6. **Nothing attacks NEUTRAL.**
   `for a in values(): assert not are_hostile(a, NEUTRAL)`.
7. **No faction attacks itself.** `for a in values(): assert not
   are_hostile(a, a)`.

---

## 1. What "successful" means

**The squad loses because it was slow, and the player can see the clock.**

The Nest (`Character/characters/ai/enemy_nest.gd`) already produces bodies on a
timer with a live cap, and its counter is that it cannot move: walk over and
break it. The Broodcarrier is that unit with the counter removed — it keeps
producing and it keeps relocating, so the answer stops being "go there" and
becomes "stop it now, while it is in reach". It is the first hostile that
punishes slowness rather than bad positioning.

**The gap this fills is real, and it is narrow.** There is exactly one novel
mechanic here — a mobile producer — and everything else is the Nest's code with
the Spotter's flight model under it. The honest statement of the risk is that a
Broodcarrier the squad cannot reach is not a pressure, it is weather: it
produces, the squad fights brood forever, and nothing the player does changes
anything. **Two things make it a unit rather than weather, and both are
mandatory, not polish:**

- **the pods visibly empty** — `build_brood.gd:41-48` built nine named siblings
  specifically so a script can; a spawner whose remaining stock the player
  cannot read is a spawner the player cannot make a decision about;
- **a finite stock.** Nine pods and a nine-body lifetime total, not an infinite
  timer with a live cap. The Nest's `max_alive` (`enemy_nest.gd:42`) is a
  concurrency cap with unlimited total output, which is correct for a building
  that you are expected to go and break. For a thing that flies away from you,
  unlimited total output means the fight has no end state that the player can
  produce. **Recommendation: nine total, from nine pods, and the bay tells you
  how many are left.** See §8 — this is the one design question in the frame.

With both: "there are six left, it is over there, go". That is a sentence a
tester can say back to you, which is the bar two frames in this batch failed
this week (`docs/frames/WARDEN.md`, `git show c7178bf7`).

---

## 2. The `ChassisDefinition`

New file `Campaign/chassis/chassis_brood.tres`. Copy the shape of
`Campaign/chassis/chassis_spotter.tres` — it is the other `weapon_slots = 0`
flyer and the only `.tres` precedent for one.

| field | value | note |
|---|---|---|
| `id` | `&"brood"` | **PERMANENT.** `FRAME_ANATOMY.md` §2.5. `kill_kinds.gd:21-23` is the recorded case: the quadcopter bomber's id is still `gunship` because renaming it would orphan every tally in `campaign.json`. `CampaignState.RENAMED` (`campaign_state.gd:1473`) is applied to `kills_by_kind` only |
| `display_name` | `"Broodcarrier"` | one word, which is what `_recruit_name` (`campaign_state.gd:769-770`) wants; irrelevant here because the frame is never recruited, but `enemy_force_spawner.gd:280` writes it as `analytics_kind` and it is what the debrief prints |
| `description` | one sentence naming the pods and the fact that it never shoots | read by the hologram and factory cards, neither of which this frame reaches |
| `icon` | null | let `tools/bake_icons.gd` do it — but see §5, it will not, and that is fine |
| `scene` | `res://Character/characters/ai/brood.tscn` | **PERMANENT-ish.** Serialised as a path (`soldier_record.gd:472`); moving the `.tscn` orphans saved records |
| `cost` | `0` | |
| `purchasable` | `false` | **mandatory.** `test_ledger.gd:449-465` asserts a catalogue frame no mission unlocks is on sale from minute one |
| `supply` | `2` | design doc §3 |
| `starting_weapon_id` | `&""` | **mandatory and non-obvious.** `FRAME_ANATOMY.md` §3.2: `_issue_weapon` (`enemy_force_spawner.gd:503-504`) is **not** gated on `weapon_slots`, only on `starting_weapon_id != &""`. A non-empty id arms a `weapon_slots = 0` frame |
| `coax_weapon_id` | `&""` | |
| `base_health` | `200` | matches `brood.tscn`'s `health`/`max_health` 200 (`build_brood.gd:464-465`). `_apply_frame` assigns only if `> 0` (`enemy_force_spawner.gd:527-529`) |
| `base_speed` | `0.7` | **IGNORED FOR ENEMIES.** `FRAME_ANATOMY.md` §6.9 / `_apply_frame` (`enemy_force_spawner.gd:524-532`) sets health, accuracy and sensors and nothing else. The real figure is `move_speed = 6.0` and `cruise_speed = 6.0` on the scene (`build_brood.gd:487-488`). Write 0.7 anyway for the card; do not expect it to do anything |
| `base_accuracy` | `0.0` | it never shoots. The Spotter and the Nest both set 0.0 on purpose (`FRAME_ANATOMY.md` §2 Stats) |
| `base_sensor_range` | `70.0` | matches the scene (`build_brood.gd:467`) |
| `weapon_slots` | `0` | the design |
| `built_in` | `"BROOD"` | **this will be a blank in the roster's weapon column, and you should know that before writing it.** `Icons.built_in` (`icons.gd:63-66`) does `path("items", name.to_lower())` — a filename, not an enum (`FRAME_ANATOMY.md` §6.10). There is no `icons/items/brood_*.png`. The Spotter's `"OPTICS"` works only because an Optics *item* icon happens to exist. Alternative: leave `built_in` empty |
| `weapon_replaces_built_in` | `false` | |
| `turret` | `false` | nothing aims; `brood.tscn` has a `WeaponMount` with no pivot (`build_brood.gd:369-370`) and nothing will ever hang on it |
| `vehicle` | `true` | team assignment only (`campaign_state.gd:468-496`), and irrelevant to an enemy |
| `drives` | `false` | |
| `equipment_slots` | `0` | |
| `module_slots` | `0` | |
| `musters_at_base` | `false` | |
| `required_rank` | `0` | `FRAME_ANATOMY.md` §6.4: the field is inert in the factory. Do not use it to gate anything |

---

## 3. Items and weapons

**None. There is nothing to make.**

`weapon_slots = 0`, `starting_weapon_id = &""`, and the spawn is behaviour on
the chassis, not an item. No `ItemDefinition`, no `AIWeapon` scene, no
subclass. `FRAME_ANATOMY.md` §3.4's rule ("you need a subclass if and only if
the round is not a hitscan ray") does not apply because there is no round.

**The one thing to resist.** The brood is not a projectile and must not be
modelled as a weapon that fires Hoppers. `Character/weapon/hatchling/hatchling_payload.gd`
exists and spawns bodies, and it is reached from equipment, not a mount — it is
the Diver's delivery, a one-shot. Using it here would put the frame's entire
purpose inside an `AIWeapon` on a frame whose design is that it has no weapon,
and `handle_weapon_logic` is `pass` on its script anyway
(`spotter_drone.gd:175`), so nothing would ever fire it. Read it for the faction
line and then leave it alone.

---

## 4. The behaviour

**Script: `Character/characters/ai/brood_carrier.gd`, `extends SpotterDrone`.**

Extend, do not copy. `spotter_drone.gd` is 393 lines and the design doc's §6.1
is right that this is the third copy of the flight helpers — but extending it
costs nothing today, gets all eight of its opt-outs for free, and leaves the
extraction as a separate refactor rather than a precondition. `bulwark.gd
extends Walker` is the precedent (`FRAME_ANATOMY.md` §4).

`brood.tscn:306` already has `spotter_drone.gd` on the root, so this is a
one-line `script` swap in the scene plus the new file.

### 4.1 What it overrides

| function | base | one line on why |
|---|---|---|
| `_physics_process(delta)` | `enemy.gd:1420` | `super(delta)` first, then the spawn tick. `enemy_nest.gd:153-170` is the shape — the tick runs **after** `super()` and behind the same gates (`alive`, `frame_waited`, not `PASSIVE`, not `SignalState.EKILL`). A culled Broodcarrier has `_physics_process` off entirely (`ai_manager.gd:576-593`), so it stops producing while frozen, which is correct and should be stated in a comment so nobody "fixes" it |
| `_fighting()` | new, copy `enemy_nest.gd:177-183` | the gate on producing at all: it has a live target of its own, or its squad has called contact. Without it the carrier empties its bay into an empty map before the squad arrives |
| `_hatch()` | new, modelled on `enemy_nest.gd:184-227` | the actual release. Section 4.2 is the whole of it |
| `_release_point()` | new | under the hull, not on the navmesh. `enemy_nest.gd:231-237` snaps to `NavigationServer3D.map_get_closest_point`, which is right for a building and wrong for something at 12 m altitude — the offspring are ground frames and should be dropped, so release at the pod's world position and let gravity and `Enemy.handle_gravity` do the rest. **Prove the drop:** a Hopper released at `cruise_height = 12.0` has to land on the navmesh and not inside geometry |
| `_deplete_bay(n)` | new | `bay.get_node("Pod%d" % n).visible = false`, counting up from 1. `build_brood.gd:41-48` names and orders the nine siblings lowest-first for exactly this, and `Pod1` is the one modelled already open |
| `enter_downed()` / `_enter_ekill()` | `enemy.gd:4264` / `ai.gd:179` | **inherited, do not touch.** `spotter_drone.gd:359-371` already makes losing the link at altitude mean losing lift, which is what makes EMP anti-air. Verify it, do not re-implement it |
| `takes_cover()` | `soldier.gd:145` | **inherited** `false` from `spotter_drone.gd:191`. This is the specific reason the design doc §5 says to copy the Spotter and not the bomber: `enemy_helicopter.gd` overrides none of the squad seams, inherits `takes_cover() -> true`, and can be handed a ground cover point as a loiter centre |
| `slot_tolerance()` / `formation_width()` | `enemy.gd:1033` / `1040` | **inherited** from `spotter_drone.gd:198,204`. A flyer that does not override `slot_tolerance` is re-ordered every single frame |
| `handle_weapon_logic()` / `roll_combat_action()` | `enemy.gd:2846` / `3052` | **inherited as `pass`** (`spotter_drone.gd:175`, `179`). For an armed frame on this script that would be the defect `FRAME_ANATOMY.md` §4.3 warns about. Here it is exactly right, and §4.2 below says what that means for the option arrays |

**Nothing in `Enemy` or `Soldier` is edited.** Confirmed: everything above is a
subclass override or a new function.

### 4.2 `AllowedMovementOptions` and `AllowedCombatOptions`

**Values: both `Array[int]([])` — empty, deliberately — and the type annotation
in the `.tscn` must be fixed.**

This is the one of the eight frames for which empty is the right answer, and it
needs the reasoning written down or somebody will "fix" it later.

`roll_combat_action` returns immediately on an empty combat array
(`enemy.gd:3053-3054`). On this frame that return is unreachable, because
`spotter_drone.gd:179` overrides `roll_combat_action` to `pass` — the dice is
never rolled whatever the arrays contain. `spotter_drone.gd:29-32` records why
the Spotter opted out in the first place. The frame still moves: movement comes
from `handle_movement` (`spotter_drone.gd:220`), which replaces navigation
entirely, orbiting a station set by `move_to` (`spotter_drone.gd:166`) from
squad orders.

So: both arrays stay empty, and `brood_carrier.gd` carries a comment saying
that they are empty because the dice is stubbed, not because the generator left
them so.

**What does need fixing is the type.** `brood.tscn:395-396` currently reads:

```
AllowedMovementOptions = Array[ExtResource("2_n02fu")]([])
AllowedCombatOptions = Array[ExtResource("2_n02fu")]([])
```

Both should be `Array[int]([])`, as `soldier_rifle.tscn:70-71` and
`vehicle_rover.tscn:165-166` have them. This is a hand edit to the `.tscn`
(**not** a re-run of `build_brood.gd` — its header lines 8-12 are emphatic, and
`CLAUDE.md` records that force-rebuilds have cost this project its gameplay
layers twice). It also silences the
`Cannot assign contents of "Array[Object]" to "Array[int]"` pair that
`build_see_engine.gd:103-109` documents as expected on load.

### 4.3 The spawn loop, concretely

New exports on `brood_carrier.gd`, named after the Nest's so the two read side
by side (`enemy_nest.gd:34-47`):

```gdscript
@export var brood: Array[ChassisDefinition] = []        # TYPED. See below.
@export var release_min_seconds: float = 7.0
@export var release_max_seconds: float = 12.0
@export var max_alive: int = 4                          # concurrency cap
@export var total_pods: int = 9                         # LIFETIME cap. See §1.
@export var first_release_seconds: float = 4.0
@export var bay: Node3D                                 # Rig/BroodBay
```

`brood` must be `Array[ChassisDefinition]` and must be assigned a typed array
by whoever authors it — `FRAME_ANATOMY.md` §6.6: `EnemyNest.hatchlings` is on
that list and a plain `Array` packs as `[]` in silence. Populate with
`Campaign/chassis/chassis_hopper.tres` (id `&"leaper"`, per
`kill_kinds.gd:19`), listed twice if you want it weighted.

The body of `_hatch()` is `enemy_nest.gd:184-227` with four changes:

1. **the live-list prune and the cap** stay as they are
   (`_forget_dead()` / `if _mine.size() >= max_alive: return`,
   `enemy_nest.gd:188-190`, `239-245`) — and gain the lifetime check
   `if _released >= total_pods: return`, which the Nest does not have;
2. **`_deplete_bay(_released + 1)` before the body is added**, so the pod the
   offspring came out of is gone by the time it is on screen;
3. **the release point** is `_release_point()`, not `_hatch_spot()`;
4. **nothing else.** In particular `body.faction = faction` is already there
   (`enemy_nest.gd:199`) — see §4.4.

**The parts of `_hatch` that are not optional**, because `enemy_nest.gd:184-227`
does the spawner's whole job by hand and skipping any one of them is silent:
`_CsgBake.make(frame.scene) as Soldier` with a null check (189-193),
`body.faction = faction` (199), `body.always_active = always_active` (200),
health from the frame (201-202), a `soldier_name` (203),
`get_parent().add_child(body)` (213), the position **after** add_child (214),
`ai_manager.register_enemy(body)` (215-216), and handing the newborn its
parent's target (219-223) so it leaves heading for the fight instead of
standing under the carrier waiting to notice one.

**One thing the Nest does not do, and you should.** It never sets the
`chassis_id` meta, which is why `KillKinds.SCENES` carries
`"enemy_nest-chaser": &"leaper"` (`kill_kinds.gd:47`) — a hatchling is counted
by its scene basename. Set `body.set_meta(&"chassis_id", frame.id)` the way
`enemy_force_spawner.gd:282` does, and the brood is counted correctly with no
`SCENES` entry needed. `KillKinds.kind_of` checks the meta first
(`kill_kinds.gd:66-67`).

### 4.4 Faction inheritance on the offspring

**The precedent already does the right thing: `enemy_nest.gd:199` is
`body.faction = faction`.** The design doc calls this "the thing most likely to
be got wrong silently", and it is — but not because the line is hard. It is
because:

- ENEMY works today, so a hand-written `body.faction = Enums.Factions.ENEMY`
  would look correct in review and would spawn the wrong side;
- the write has to happen **before `add_child`**. `enemy_force_spawner.gd:269`
  carries the comment: *"Before add_child — AI._ready() runs initialize() and
  reads these."* `enemy_nest.gd` sets faction at 199 and adds at 213, which is
  correct. Reorder those two and the body initialises as ENEMY and then has its
  field changed underneath whatever `initialize()` derived from it;
- `FactionLivery.apply(faction)` (`faction_livery.gd:134`) is what repaints the
  body, so an offspring with the wrong faction is also the wrong colour — which
  is the one way this bug is visible, and only after §0.2's `COLORS` entries
  exist. Until then SWARM renders grey (`faction_livery.gd:125`) and ENEMY
  renders amber, so **before §0.2 is complete, a correctly-SWARM offspring looks
  broken and an incorrectly-ENEMY one looks right.** That is the trap, stated
  properly.

Copy the line. Assert it (§6).

---

## 5. Registration

Walked against `FRAME_ANATOMY.md` §1. **S** = fails silently.

| § | item | status |
|---|---|---|
| 1.1 | `brood.tscn`, `tools/build_brood.gd` | **done.** Do not re-run the generator |
| 1.2 #1 | `Campaign/chassis/chassis_brood.tres` | **to do.** §2 |
| 1.2 #2 | root script resolves to `Soldier` | **done** — `spotter_drone.gd extends Soldier`; `brood_carrier.gd extends SpotterDrone` keeps it. Hard error at spawn if broken (`enemy_force_spawner.gd:265-267`) |
| 1.2 #3 | `groups=["enemies"]` | **done**, `brood.tscn:306` |
| 1.2 #4 | `kill_kinds.gd` `FRAMES` | **to do — S.** Add `&"brood": "res://Campaign/chassis/chassis_brood.tres"` to `kill_kinds.gd:14-37`. Missed → `frame_of()` returns null (73-77), the debrief prints a raw id with no icon (`debrief_screen.gd:685-692`), the roster glyph is blank (`hud_glyphs.gd:64-67`) |
| 1.2 #5 | `Allowed*Options` | **type fix only.** §4.2 |
| 1.3 | catalogue, `purchasable`, icons | **deliberately not done.** Enemy frame. `purchasable = false` on the `.tres` and **no** entry in `Campaign/items & catalogue/test_item_catalogue.tres` |
| 1.4 #9 | a mission `.tres` | **to do.** §5.1 |
| 1.4 #10 | `Enums.Factions` + `are_hostile` | **§0. This is the blocker** |
| 1.5 #11 | `kill_kinds.gd` `SCENES` | **not needed.** `kind_of` falls through to `SCENES.get(base, StringName(base))` (`kill_kinds.gd:70`), and basename `brood` == id `brood`. Same reason the Bulwark has no entry |
| 1.5 #12 | `enemy_loadouts.gd` `TABLES` | **do not add one.** The frame has no weapon slots and no module slots, so a pool has nothing to fill, and `enemy_loadouts.gd:109-113` records the cost of asking the legality check for something it is right to refuse. `roll_for` returns `{}` for an unlisted frame (208-210) |
| 1.5 #13 | `cosmetics.gd` | **no.** `for_frame` returns `[NONE]` (`cosmetics.gd:84-90`); the Spotter, Nest, Diver and Bulwark all have no entry |
| 1.5 #14 | mission `unlocks` | **N/A**, not purchasable |
| 1.5 #15 | a lab plan | **optional**, and worth it — see §7 step 5 |
| 1.5 #16 | `tools/test_brood.gd` | **to do.** §6 |
| 1.5 #17 | `probe_nav_reach.gd` `FRAMES` | **no.** It flies |
| 1.6 | CSG bake, teams, `"signal"` group, `"air"` group, `AIManager` registration | **all free.** `"air"` comes from `spotter_drone.gd:108`, so the subclass inherits it. `_CsgBake` reads the directory (`csg_bake.gd:177-189`) |

**Icons: there will be none, and that is the existing standard.** `bake_icons.gd`
reads `catalogue.chassis` plus `KillKinds.FRAMES` (`bake_icons.gd:120-129`), so
the `FRAMES` entry does make the frame bakeable. `FRAME_ANATOMY.md` §6.3 records
that the Bulwark has shipped with no `icons/chassis/bulwark_*.png` since it was
built, and nothing asserts their presence. Run `tools/bake_icons.gd` and say in
your report whether the three PNGs landed.

### 5.1 The mission entry

`mission_salient_1_overthetop.tres` is the Bulwark's worked example. Two edits
to whichever mission fields this frame:

1. an `[ext_resource type="Resource" path="res://Campaign/chassis/chassis_brood.tres" id="…"]`
   — line 11 of that file is the Bulwark's;
2. an `EnemySquadSpec` sub-resource whose `roster` array holds it, with
   `faction = 4` (SWARM). The block shape is
   `mission_salient_1_overthetop.tres:20-40`; `roster` is
   `Array[ExtResource("<the EnemySquadSpec script id>")]([…])` and the `faction`
   line is `35`.

**`roster` is `Array[ChassisDefinition]`** (`enemy_squad_spec.gd:46`) and is on
`FRAME_ANATOMY.md` §6.6's list of typed arrays that pack as `[]` in silence.

**Recommendation on how to field it:** one Broodcarrier in its **own**
`EnemySquadSpec`, `count = 0` so the roster is the whole force, `posture` set so
it loiters, and **not** in a squad with ground frames. The design doc §6 names
the reason and I confirmed the mechanism: `Squad._enforce_leash` measures 3D and
does not consult `slot_tolerance`, so a flyer at `cruise_height = 12.0` is
permanently outside the leash and is recalled constantly. That applies to enemy
squads too.

**`activation_distance` is already 250 on the scene** (`build_brood.gd:471`),
which is the Spotter's figure. `FRAME_ANATOMY.md` §6.13 and
`enemy_force_spawner.gd:537-546`: `always_active` does **not** exempt a frame
from distance culling. A Broodcarrier authored to arrive from off-map has to be
walked in by `_let_them_walk_in` (`enemy_force_spawner.gd:570`) or it will stand
on its spawn.

---

## 6. Tests

New file `tools/test_brood.gd`. `tools/test_bulwark.gd` is the model; its
`_test_the_chassis_is_registered` (70-90) is literally §5 of this brief as a
test and is the cheapest thing to copy. `tools/test.sh` picks it up with no
wiring.

**The task-zero assertion, in this file as well as in `tools/test_factions.gd`:**

```gdscript
_ok("hostile to the player, outbound",
	Enums.are_hostile(Enums.Factions.PLAYER, Enums.Factions.SWARM))
_ok("hostile to the player, inbound",
	Enums.are_hostile(Enums.Factions.SWARM, Enums.Factions.PLAYER))
```

Both directions, because §0.1 shows the two directions fail differently: the
outbound false is what makes it untargetable, the inbound false is what makes
it refuse its own shot.

Then:

- **registered:** `chassis_brood.tres` loads, `id == &"brood"`, `supply == 2`,
  `purchasable == false`, `cost == 0`, `weapon_slots == 0`,
  `starting_weapon_id == &""`, `base_sensor_range == 70.0`, and
  `KillKinds.FRAMES.has(&"brood")` with `KillKinds.frame_of(&"brood") != null`
- **not in the player catalogue:** load
  `Campaign/items & catalogue/test_item_catalogue.tres` (the path
  `test_bulwark.gd:86` hard-codes) and assert no entry has `id == &"brood"`.
  The inverse of `test_ledger.gd:449-465`
- **it never fires:** spawn it, give it a target, step physics, and assert
  `weapon == null` and `weapon_state` never becomes `WeaponState.FIRE`. Cheaper
  and stronger: assert `weapon_mount.get_child_count() == 0` after
  `EnemyForceSpawner._apply_frame` has run over it — that is the §2
  `starting_weapon_id` trap caught directly
- **it produces on a timer, and only once fighting:** step physics with no
  target and assert zero offspring after `first_release_seconds * 2`; then
  `trigger_combat(target)` and assert one appears
- **it stops at the concurrency cap:** force `max_alive = 2`, run long, assert
  live offspring never exceeds 2
- **it stops at the lifetime cap:** `total_pods = 3`, run long, assert exactly
  3 were ever produced
- **the offspring inherit SWARM, not ENEMY:**
  `_ok("offspring are swarm", child.faction == Enums.Factions.SWARM)`. The
  assertion the design doc singles out, and the one that would pass by accident
  if written as `child.faction == parent.faction` while the parent is still
  ENEMY — **assert the literal value**
- **the offspring are registered and counted:** the child is in
  `"enemies"` and `AI.SIGNAL_GROUP`, and
  `KillKinds.kind_of(child) == &"leaper"` (proves the §4.3 `chassis_id` meta)
- **the bay empties:** after N releases, pods `1..N` have `visible == false`
  and `N+1..9` have `visible == true`, read through
  `Rig/BroodBay/Pod%d`. The node names are `build_brood.gd:41-48`'s promise; if
  this assertion is hard to write, the hierarchy is wrong, not the test
- **it flies:** place it over varying ground, step physics, assert
  `global_position.y` stays within tolerance of `cruise_height` above the
  `GroundRay` hit. `spotter_drone.gd` builds its own ray in `_ready()`
  (`build_brood.gd:307-310` explains why the scene has none)
- **it crashes rather than standing:** `enter_downed()`, step physics, assert it
  descends and that `flatten_collider_when_downed` is false
  (`build_brood.gd:475`)
- **groups and typed arrays:** `is_in_group("enemies")` **and**
  `is_in_group(AI.SIGNAL_GROUP)` — `test_bulwark.gd:120-127` is the assertion to
  copy — plus `visible_pieces`, `particle_effects_die` and
  `particle_effects_hit` all non-empty (`FRAME_ANATOMY.md` §6.6)
- **the ocelli keep their own material:** the five
  `Rig/SensorCluster/Ocellus1..5` are **not** in the `FactionLivery` `pieces`
  array and survive `apply()`. `build_brood.gd:743-761` does this exclusion by
  hand because there is no node named `Eye` for `check_frame.gd`'s
  "EYE EXCLUDED" assertion to find. `test_bulwark.gd:186-232` is the model

Also run, and report:

```bash
bash tools/check.sh --changed              # must print PASS
bash tools/test.sh
bash tools/smoke.sh
"D:/Godot Games/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe" \
  --headless --audio-driver Dummy --path . \
  --script res://tools/check_frame.gd -- res://Character/characters/ai/brood.tscn
```

**Not while `tools/test.sh` is in flight** — the suites share `user://` probe
paths and a parallel run produces a FAIL that looks real and does not
reproduce.

---

## 7. Order of work

Each step ends with something proved, and nothing in a later step is started
until the earlier one is proved.

1. **§0 — `are_hostile` as a table, SWARM/STRATCOM/ARGUS appended,
   `tools/test_factions.gd` green.** Nothing else in this brief can be
   validated before this: a SWARM Broodcarrier on today's `enums.gd` is
   untargetable and invisible and every test below passes or fails for the
   wrong reason. **Prove:** `tools/test_factions.gd` passes all seven groups,
   including the regression lock on the original sixteen pairs, and
   `bash tools/test.sh` is green across the whole suite (the regression lock is
   the point — this change touches every faction decision in the game).
2. **`chassis_brood.tres` + the `kill_kinds.gd` `FRAMES` entry + the
   `Array[int]([])` type fix in `brood.tscn`.** No behaviour yet.
   **Prove:** `tools/test_brood.gd` with only the "registered", "not in the
   catalogue" and "never fires" assertions. `check_frame.gd` clean on
   `brood.tscn`, and the two `Array[Object]` load errors gone.
3. **Field it, unarmed and inert, in one mission.** `[ext_resource]` +
   its own `EnemySquadSpec` with `faction = 4`. **Prove:** `smoke.sh` green; it
   spawns, it is amber-or-grey but *visible*, the player can shoot it, it can
   kill the player, and the debrief names it "Broodcarrier" with a frame entry.
   That last one is the §0 fix observed end to end rather than asserted.
4. **`brood_carrier.gd` — the spawn loop and `_deplete_bay`.** **Prove:** the
   timer, concurrency-cap, lifetime-cap, faction-inheritance, `chassis_id`-meta
   and bay-emptying assertions. Then look at it: run `tools/mockup_shots.gd`
   over the frame mid-depletion and confirm the bay reads as emptying from the
   bottom. An assertion that pods are invisible is not the same as a player
   being able to count them.
5. **Tune.** A lab plan (`Campaign/lab/plans/*.tres`,
   `bulwark_screen.tres` is the precedent) matching one Broodcarrier against a
   player squad, to get release interval, `max_alive` and `total_pods` onto
   numbers rather than guesses. **Prove:** two plans, one at each end of the
   range, and hand the human the difference. Spawn rate and cap are game feel
   and `CLAUDE.md` says that is theirs.
6. **Legibility review with the human before calling it done.** The pods
   emptying is the whole decision loop and it is the one thing that cannot be
   asserted.

---

## 8. Open questions and risks

**For the human:**

1. **Nine total, or an endless timer with a live cap?** §1 argues nine. The
   Nest's model is unlimited-total / capped-concurrency, which works because
   the Nest cannot run away. This frame can. I recommend a finite stock and I
   am not confident enough to call it settled — it changes the frame from a
   pressure into a countdown, which is a different unit.
2. **Does killing the carrier kill the brood already out?** The design doc §8
   leaves it open. Cleaner as a player promise ("break the carrier and the
   fight ends"), less interesting than leaving them alive. I have no
   recommendation; it depends on (1).
3. **STRATCOM or Home Command?** §0.2. A naming decision with a permanent
   identifier at the end of it.
4. **Release interval and `max_alive`.** Game feel; §7 step 5 gets numbers in
   front of you.

**Risks:**

5. **The leash.** `Squad._enforce_leash` measures 3D and ignores
   `slot_tolerance`, so a flyer at 12 m is permanently out of position and gets
   recalled. Mitigated by fielding it solo (§5.1) and **not fixed** — fixing the
   leash is runtime work in `Squad` and is not this frame's.
6. **The drop.** Offspring released at `cruise_height = 12.0` have to land on
   navigable ground. Nothing guarantees it, and a Hopper that lands inside
   geometry or off the navmesh will take the adrift path
   (`enemy.gd:1834`). **Must be proved in §7 step 4 on a real level**, not in a
   bare headless scene.
7. **The culled carrier.** `_physics_process` is switched off entirely by the
   distance cull, so a frozen Broodcarrier produces nothing. Correct behaviour,
   invisible mechanism — comment it or it gets "fixed".
8. **`built_in = "BROOD"` is a blank icon**, by `icons.gd:63-66`. Known, cheap,
   and I would rather it be stated than discovered.
9. **The flight-helper extraction.** Three copies of `_steer` /
   `_altitude_velocity` / `_ground_height` / `_turn_toward` / `_orient` once
   this ships. `extends SpotterDrone` defers it rather than adding a copy, which
   is why §4 recommends extending. The refactor is a separate task and should be
   a separate task.

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
