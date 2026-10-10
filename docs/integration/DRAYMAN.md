# DRAYMAN — integration brief

Supply 2 · wheeled · logistics · **model built, nothing registered**

Written for a builder. The map is `docs/briefs/FRAME_ANATOMY.md`; this document
cites it by section instead of restating it. Everything else carries a
`file:line`.

**What exists today:** `Character/characters/ai/drayman.tscn` (root script
`rover.gd`, in `groups=["enemies"]`) and `tools/build_drayman.gd`. There is no
`ChassisDefinition`, no catalogue entry, no `kill_kinds` entry, no behaviour
script, no item.

---

## 0. The premise in the design doc is dead. Read this first.

`docs/frames/DRAYMAN.md` §2 and §4 build the whole frame on refilling
squadmates' magazines. **That problem does not exist.** Verified, three ways:

- `Character/weapon/ai_weapon.gd:217-220` — `_finish_reload()` ends with
  `magazine_current = magazine_size`. There is no reserve, no pool, no
  subtraction. An AI reload is a free refill.
- `grep -n "magazine_current\|reserve\|ammo" Character/weapon/ai_weapon.gd`
  returns the magazine counter, `infinite_ammo` (line 68) and nothing else.
  `ai_weapon.gd` never mentions `AmmoPool`, `AmmoStock` or a reserve.
- `AmmoPool` (`Character/equipment/ammo_pool.gd:2`) and `AmmoStock`
  (`Character/equipment/ammo_stock.gd:2`) are reached from exactly three
  places, all player-side: `Character/characters/player/test_character.gd:48`
  (`@export var ammo: AmmoPool`), `Character/equipment/equipment_loadout.gd:27`,
  `Character/equipment/player_equipment.gd:129`. The transfer that makes ammo
  finite is `Character/equipment/player_weapon.gd:349`
  (`var granted: int = ammo.take(ammo_type, wanted)`), and `PlayerWeapon` is
  not an `AIWeapon`.

**Squad ammunition is infinite.** A frame that refills squadmate magazines
would be a frame with no observable effect, and `check.sh` would pass on it.
Do not build it.

The human's ruling was *"maybe the drayman can resupply but also carry other
things? i think it's fine."* §1 below answers what it carries.

---

## 1. What "successful" means

**Recommendation: the Drayman carries consumables to the two things in the game
that actually run out — the player's ammunition reserve, and the squad's
equipment charges.**

Both are genuinely finite and neither has any in-mission answer today:

| resource | where it lives | who spends it | who restores it today |
|---|---|---|---|
| player ammunition | `AmmoPool._counts` (`ammo_pool.gd:24`) | `player_weapon.gd:349` | **nothing in a mission.** `EquipmentLoadout.refill()` (`equipment_loadout.gd:648`) is called on `returned_to_base` and `deployed` (`test_character.gd:206`, `218`) and on respawn (`test_character.gd:765`) |
| squad equipment charges | `AIEquipmentSlot._quantity_remaining` (`ai_equipment_slot.gd:24`) | `_spend_equipment` → `slot.consume()` (`enemy.gd:3790`) | **nothing.** `initialize()` (`ai_equipment_slot.gd:26`) runs once at spawn; `SoldierRecord` writes the survivor's remaining count back (`soldier_record.gd:433`) and restores it from `equipment_max` at base (`soldier_record.gd:215`) |

The thing a player can do that they cannot today, in one sentence: **take a
long mission with a loud loadout — rockets, the cluster launcher, mines, smoke
— and not have the last third of it be a pistol fight.**

That is a real gap, and it is worth saying exactly how real: the player's ammo
is per-*life*, not per-mission, because `test_character.gd:765` refills on
respawn. So the Drayman's player-resupply job matters on a long run without a
death, and is worth nothing to a player who dies often. The equipment-charge
job has no such escape hatch — once the squad's smoke is gone it is gone for
the mission — which is why the recommendation is **both jobs, not one**.

### The alternatives, and what each costs

| option | cost | verdict |
|---|---|---|
| refill squadmate magazines (the doc's §4) | zero code, zero effect | **dead.** §0 |
| top the player's `AmmoPool` only | one function call per channel | good, but thin on its own: per-life, not per-mission |
| restock squadmate `AIEquipmentSlot`s only | one call per channel | good, but invisible — nothing in the HUD shows a charge coming back except the designator's count |
| add a *reserve* to `AIWeapon` so squad ammo becomes finite, then feed it | a new system in a 809-line base class that every hostile in the game also runs; a global difficulty change nobody authored | **out of scope for this frame.** If the project ever wants it, it is its own brief, and the Drayman becomes its answer afterwards for free |
| carry something the squad cannot otherwise bring (a deployable, a beacon) | a new item plus new behaviour plus a reason | a different frame. Not this one |

### Honesty, stated plainly

A Drayman whose only job is topping the player up is a frame that does nothing
for four missions out of five. The equipment-charge half is what makes it a
squad decision rather than a convenience, and **if only one half ships, ship
the equipment half** — the opposite of the doc's §6 recommendation, which was
written when squad ammo was believed to be finite.

Two frames were cut this week for a thin gap. This one's gap is real but
narrow, and it is narrow because the ammunition system the doc thought it was
completing turned out to be player-only.

---

## 2. The `ChassisDefinition`

`Campaign/chassis/chassis_drayman.tres`, script
`res://Campaign/chassis_definition.gd`. Copy
`Campaign/chassis/chassis_reclaimer.tres` as the template — it is the nearest
frame in every respect and already carries the tool-arm shape.

| field | value | reasoning |
|---|---|---|
| `id` | `&"drayman"` | **PERMANENT.** `FRAME_ANATOMY.md` §2.5: written to the save in three places and the `RENAMED` hook covers only `kills_by_kind` |
| `display_name` | `"Drayman"` | `_recruit_name` takes the first word for the callsign (`campaign_state.gd:769`); one word is correct |
| `description` | "Six-wheeled logistics truck. Its boom hands ammunition and equipment back to whoever is running dry." | factory and hologram cards |
| `icon` | null | let `tools/bake_icons.gd` do it — §5 |
| `scene` | `res://Character/characters/ai/drayman.tscn` | **PERMANENT.** §2.5: moving the `.tscn` orphans every saved record |
| `cost` | 170 | the doc's figure, above the Reclaimer's 130 (`chassis_reclaimer.tres`) |
| `purchasable` | `true` | mandatory or `recruit()` refuses (`campaign_state.gd:740`) |
| `supply` | 2 | the Reclaimer's |
| `base_health` | 170 | the doc's. Matches `health`/`max_health` already authored at `drayman.tscn:458-459`, so the two cannot disagree |
| `base_speed` | 0.95 | **a multiplier, not a speed** (§6.9). `drayman.tscn:461` already carries `move_speed = 6.65`, which is the Rover's 7.0 × 0.95. Leaving `base_speed = 0.95` here multiplies it *again* at `squad_spawner.gd:349`, giving 6.32. **Set `base_speed = 1.0` and let the scene own the speed**, or set the scene back to 7.0. Pick one; do not ship both |
| `base_accuracy` | 0.0 | it never fires. The Spotter and Nest set 0.0 on purpose (§2 Stats) |
| `base_sensor_range` | 40.0 | the doc's, and already on the scene (`drayman.tscn:508`) |
| `weapon_slots` | 1 | the boom occupies it — the Reclaimer's arrangement |
| `starting_weapon_id` | `&""` | **the Reclaimer's value, and it matters.** `recruit()` writes this straight into `weapon_ids[0]` without consulting `takes()` (`campaign_state.gd:750-751`), and `_issue_weapon` arms an enemy body on a non-empty id regardless of `weapon_slots` (§3.2). Empty is the only safe value for a frame that must never hold a gun |
| `coax_weapon_id` | `&""` | `drayman.tscn` has no `coax_mount`; a coax pool would warn per body per mission (§6.12) |
| `built_in` | `"ARM"` | the doc's §3. **A filename, not an enum** (§6.10): `Icons.built_in` does `path("items", "arm")` and there is no `icons/items/arm_s.png`, so the roster's weapon column is blank until one is baked. Also deliberate: `factory_page._badges` keys the MEDIC and ARTICULATED ARM badges off the literal `"WELDER"` (§6.10), and a logistics truck should get neither |
| `weapon_replaces_built_in` | `true` | the Reclaimer's. If a drayman-whitelisted tool is ever authored, fitting it hides the arm's tool head |
| `turret` | `false` | the doc's, and **it is already safe**: every vehicle-legal weapon in the catalogue carries a non-empty `chassis_whitelist` that excludes `drayman` — `autocannon`, `heavy_mg`, `machine_gun` all `[walker, rover]`, `grenade_launcher` `[rover]`, `mortar` `[reclaimer]`. `takes()` refuses all five on the item's own whitelist (`chassis_definition.gd:84-91`). **Lock this with a test** (§6) rather than trusting it, because a future vehicle gun with an empty whitelist would fit silently. The alternative is `turret = true`, which makes the slot whitelist-gated for all time — but it also flips a badge in `factory_page._badges` (319) and reads as "turret" on a frame that has none |
| `vehicle` | **`false`** — a change from the doc | `vehicle` is *which team it joins* (`campaign_state._is_vehicle`, 494-496) and it drives `Squad.vehicles_only` and `armor_follow_distance` (`squad_spawner._all_vehicles`, 179-187). `chassis_reclaimer.tres` sets `vehicle = false` with `drives = true` for exactly this reason: a support vehicle has to travel with the thing it supports. The Drayman's customers are the player and the infantry squad. **The doc says `true`; it is wrong for the same reason it would be wrong for the Reclaimer.** Flagged for the human because it is a feel call |
| `drives` | `true` | wheeled. `takes()` then refuses anything with `fits_vehicles = false` (`chassis_definition.gd:89-90`), which is the leg-kit refusal the doc wants |
| `equipment_slots` | 2 | the doc's. Note the Reclaimer has 0 |
| `module_slots` | 2 | the doc's. The Reclaimer has 3 |
| `musters_at_base` | `true` | it should stand in the hub like the Reclaimer |
| `required_rank` | **leave 0** | `required_rank` is read only by `set_chassis` (`campaign_state.gd:1165`) and never by the factory (§6.4). The doc's `required_rank = 2` would be inert, exactly as the Bulwark's 3 is. **Gate it with a mission `unlocks` entry** (`campaign.gd:1068-1082`) |

**Permanent once written:** `id`, `scene`, and any enum ordering this frame
introduces (it introduces none). Everything else — stats, slots, cost, supply,
`display_name`, `description`, `built_in` — is retunable (§2.5).

---

## 3. Items and weapons

### Is a new `ItemDefinition` needed? **No.**

`FRAME_ANATOMY.md` §3.3 settles it: *"a tool that is part of the body needs no
item at all — it is `built_in` plus code."* The arm is built into
`drayman.tscn` as geometry (`Rig/ArmBase → Shoulder → Elbow → Wrist`,
`build_drayman.gd:872-925`) and `weapon_mount` is already authored at
`Rig/ArmBase/Shoulder/Elbow/Wrist/WeaponMount` (`drayman.tscn:450`).

So: **drop `supply_boom` entirely.** `docs/frames/DRAYMAN.md` §4 proposes it as
a `kind = 0` item with `base_damage = 0`, and nothing is gained by it:

- It would need an `ai_scene` that is an `AIWeapon` or `equip_weapon_scene`
  warns and drops it (`enemy.gd:58-72`), and an `AIWeapon` that never fires is
  a `handle_weapon_logic` state machine running for nothing.
- `hud_glyphs._item_for_scene` (`hud_glyphs.gd:72-81`) would then show a gun
  glyph on a frame that cannot shoot.
- `built_in = "ARM"` already occupies the slot visually
  (`factory_page.gd:258-259`, `chassis_hologram.gd:312-315`).

**The subclass-or-not decision (§3.4) therefore does not arise: there is no
weapon.** If a drayman-whitelisted *gun* is ever wanted, `item_mortar.tres`
(`chassis_whitelist = [&"reclaimer"]`) is the template to copy, and §3.4's rule
applies then — a subclass only if the round is not a hitscan ray.

### The correction block in `DRAYMAN.md` §4 is right and must be carried forward

`item_repair_lance.tres` is **not** a precedent for anything AI-side:
`usable_by_player` aside, it is `fits_vehicles = false`, has no `ai_scene`, and
`fits_ai()` is therefore false (`item_definition.gd:145-150`). Confirmed by
reading the file. The Reclaimer is the precedent, and `reclaimer.gd:863` is the
one place in the game that builds its own mount inside `equip_weapon_scene`.

**The Drayman does not inherit that contract**, and `build_drayman.gd:163-173`
already decided so in writing: the mount is *authored*, not runtime. Anything
that guards on `weapon_mount != null` is correct for the Drayman. Do not copy
`reclaimer.gd:863`.

### Does the arm need to be an item at the *catalogue* level?

No, but note the consequence: `hud_glyphs.gd:61` reads `built_in` for the
roster's weapon column and `Icons.built_in` (`icons.gd:63-66`) will return
null. **Bake `icons/items/arm_s.png`, `_m.png`, `_l.png`** or accept a blank
column, which is what the Bulwark did with its chassis icons and still has
(§6.3).

---

## 4. The behaviour

### Script

`Character/characters/ai/drayman.gd`, **`extends Rover`** — not `Soldier`, and
not `Reclaimer`.

- `rover.gd` is already the root script of `drayman.tscn`
  (`build_drayman.gd:183`) and gives Ackermann steering, reverse, whisker
  blocking, pack spacing, suspension, wreck pose (`FRAME_ANATOMY.md` §4.3).
- **Not `Reclaimer`:** `reclaimer.gd` extends `mechanic.gd` by path string
  (§4) and brings a welding brain, a salvage job and a mortar brain, all of
  which would have to be switched off. `DRAYMAN.md` §8 lists this as open; it
  is now closed — **no.** Copy the *shape* of `mechanic.gd`'s
  `_choose_patient` (219) / `_tend` (286) / `_tool_on` (346) / `_start_welding`
  (370) / `_stop_welding` (378) loop, not the class.

### `Allowed*Options` — give these as values

`drayman.tscn:519-520` currently ships
`AllowedMovementOptions = Array[ExtResource("2_kwpm7")]([])` and the same for
combat. `roll_combat_action` returns immediately on an empty combat array
(`enemy.gd:3053-3054`), with the three consequences `FRAME_ANATOMY.md` §6.1
lists.

**Set, copying `vehicle_rover.tscn`'s own shape:**

```
AllowedMovementOptions = Array[int]([0, 2])      # ADVANCE, FALLBACK
AllowedCombatOptions   = Array[int]([0])         # MOVE
```

Reasoning, and it is deliberately not the Rover's `[0, 2, 4]` / `[0, 1, 2]`:

- `MovementOptions` is `{ADVANCE=0, REPOSITION=1, FALLBACK=2, LEAP=3, CHASE=4}`
  and `CombatOptions` is `{MOVE=0, AIM=1, FIRE=2}` (`enemy.gd:1091-1092`).
- **ADVANCE** so it can close on whoever it is resupplying under its own
  decision loop. **FALLBACK** so it breaks contact — the whole point of a truck
  is that it should not be in the fight. **No CHASE** (4) and **no REPOSITION**
  (1): neither means anything to a vehicle with no gun, and CHASE on a frame
  that cannot shoot is a truck driving at a rifleman.
- **MOVE only in combat.** AIM and FIRE both drive `handle_weapon_logic`, and
  there is no weapon. Keeping MOVE in the array is what keeps
  `roll_combat_action` alive at all — an empty array is the §6.1 defect, and
  `_commit_burst` / `_enter_aim_stance` being unreachable is correct here
  because there is nothing to burst.
- These go in the `.tscn`, not in `_ready()`. `enemy_nest.gd:72-76` clears them
  in `_ready` instead, which is the precedent for a frame that wants them
  empty; the Drayman wants them non-empty, so author them.

### Two authored switches, free (§4.1)

- `aggressive = false` — already the default. A Drayman that never took cover
  and took every role as ADVANCER is a truck in the front rank.
- **`formation_trail`** — set it. `soldier.gd:52`; the Mechanic's value is
  specifically why it stops being the first thing every fight finds. Match or
  exceed the Mechanic's. Read it off `mechanic_chassis.tscn` and state the
  number in the commit.

### Functions `drayman.gd` overrides

| function | declared | why the Drayman overrides it |
|---|---|---|
| `handle_weapon_logic(delta)` | `enemy.gd:2846` | **`pass`.** No weapon, no mount contents, no aim/fire machine. `spotter_drone.gd:175` is the shipped example of exactly this |
| `_weapon_on_target()` | `enemy.gd:2999` | return `false`. Nothing should ever read as on-target |
| `takes_cover()` | `soldier.gd:145` | **do not write it.** Checked: `rover.gd:578` already returns `false`, which is what a 3.3 m truck needs — `Squad` splits its members on this function (`FRAME_ANATOMY.md` §4.2) and false means "parks on the spot instead of being sent to a cover point" |
| `enter_cover_seeking()` | `soldier.gd:124` | **do not write it.** `rover.gd:574` already stubs it to `change_soldier_state(SoldierState.NONE)` |
| `_physics_process(delta)` | — | the resupply tick, modelled on `mechanic.gd:189`. **Call `super(delta)`** or the frame stops driving. Throttle it on `mechanic.gd`'s `think_interval` idiom (0.3 s), not per frame — CLAUDE.md forbids a new `_process` and this is a `_physics_process` with a clock |
| `_choose_customer()` | new | the Mechanic's `_choose_patient` (219) with a different test: who is low. Candidates are the player (`Enemy.player`, `enemy.gd:1116`, typed `Player`) and `squad.get_living_soldiers()` (`squad.gd:1063`) |
| `_hand_over(delta)` | new | the Mechanic's `_tend` (286): channel while in reach, carry fractional progress, emit sparks, release on arrival or on the customer walking off |
| `_keeping_back()` | `mechanic.gd:437` | the Mechanic's hang-back loop is the right behaviour for a truck too. Reuse the shape, not the class |
| `_update_facing(delta)` | `enemy.gd:2780` | **probably not.** `rover.gd:597` already splits hull from turret, and `build_drayman.gd:139-161` deliberately zeroed `turret_traverse_degrees` and `gun_elevation_degrees` so `rover.gd`'s aiming code is a no-op every frame. Leave it. Overriding this is how you accidentally give a supply truck a tracking arm, which is the art brief's one explicit prohibition |
| `_collapse_pieces()` | `enemy.gd:4644` | **no.** `rover.gd:788` already does the vehicle wreck, and `visible_pieces` is the whole `Rig` (`build_drayman.gd:609-610`) so it goes over as one object |

### The two channels, concretely

**Channel A — the player's reserve.** Reach the pool through
`player.loadout.ammo` or `player.ammo` (`test_character.gd:47-48`).
`AmmoPool.add(ammo_type, amount)` (`ammo_pool.gd:123`) returns how much was
actually stored and respects capacity, so overflow is free. Which types: walk
`player.loadout` rather than guessing calibres — `EquipmentLoadout.refill()`
(`equipment_loadout.gd:648`) is the shape, and it already restocks every
`PlayerEquipment` *and* the pool. **Do not call `refill()`**: it is a full
top-up including every magazine and reservoir, which is the base-camp
behaviour. The Drayman should move the pool, a magazine's worth per channel
tick, and leave what is loaded alone.

**Channel B — squad equipment charges.** `AIEquipmentSlot` has no public
restore: `initialize()` (`ai_equipment_slot.gd:26`) sets
`_quantity_remaining = quantity` and `consume()` (32) decrements. There is no
`restore()`. **This is the one line of new API the frame needs** — add
`func restore(n: int = 1) -> void` to `ai_equipment_slot.gd`, clamped to
`quantity`. That is a two-line addition to a 36-line resource, it touches
nothing that reads `remaining()`, and it is the honest alternative to reaching
into `_quantity_remaining` from `drayman.gd`.

**Capacity.** `DRAYMAN.md` §4 is right that an infinite resupply frame is a
non-decision. Carry a finite count on `drayman.gd` as an `@export`
(`@export var loads: int = 8`), decremented per completed hand-over, and
**warn when it runs out** — CLAUDE.md's rule is that every early return says
why, and a Drayman that has silently stopped working is the most expensive bug
shape this project has.

### The known gap, restated and still true

`DRAYMAN.md` §6 says no AI will ever *request* resupply. Confirmed:
`AIEquipment.EquipmentContext` (`ai_equipment.gd:30-96`) has no "I am low"
field, and `_score_combat_option`'s `low_ammo` is local to the robot scoring
it. So the Drayman has to *poll* — that is what `_choose_customer` is for, and
it is why the Mechanic's `search_radius` / `_skip_until` idiom
(`mechanic.gd:35`, `91`) is the right one to copy: it is the project's existing
answer to "nobody is going to ask me".

---

## 5. Registration — `FRAME_ANATOMY.md` §1, walked

| # | item | status | fails how |
|---|---|---|---|
| 1 | `Campaign/chassis/chassis_drayman.tres` | **to write**, §2 | nothing can reference the frame |
| 2 | root script resolves to `Soldier` | **already fine** — `rover.gd` extends `Soldier`; `drayman.gd extends Rover` keeps it. Changing `drayman.tscn`'s `script` to `drayman.gd` is part of this work | hard error at spawn (`enemy_force_spawner.gd:265-267`) |
| 3 | `groups=["enemies"]` | **already fine** (`drayman.tscn:399`) | **silent** |
| 4 | `Campaign/kill_kinds.gd` `FRAMES` | **to add** — `&"drayman": "res://Campaign/chassis/chassis_drayman.tres"` beside `&"bulwark"` at line 35 | **silent**: no debrief icon, blank roster glyph, no baked icon |
| 5 | `Allowed*Options` non-empty | **to fix** — `drayman.tscn:519-520`, §4 | **silent**, and the biggest live defect in the batch |
| 6 | `Campaign/items & catalogue/test_item_catalogue.tres` | **to add** — an `[ext_resource]` **and** an entry in the `chassis = Array[...]` list at line 48 (which today holds soldier, mechanic, reclaimer, rover, spotter, walker, bulwark) | **silent in the shop.** Also makes `recompute_stats` warn-and-fall-back (`soldier_record.gd:229-236`) and `supply_of` return 1 (`campaign_state.gd:315-317`) |
| 7 | `purchasable = true` | §2 | `recruit()` refuses (`campaign_state.gd:740-741`) |
| 8 | `icons/chassis/drayman_{s,m,l}.png` | **to bake** — `tools/bake_icons.gd`, which reads `catalogue.chassis` + `KillKinds.FRAMES`, so items 4 and 6 must land first | **silent**: name with no picture. The Bulwark still has none (§6.3) |
| 11 | `KillKinds.SCENES` | **not needed.** Basename `drayman` equals id `drayman`, so `kind_of` falls through to `SCENES.get(base, StringName(base))` (`kill_kinds.gd:70`) | — |
| 12 | `enemy_loadouts.gd` `TABLES` | **do not add.** A player-only support frame has no enemy variation to roll, and adding a key commits you to `test_enemy_loadouts.gd:91-124` | every body identical — correct here |
| 13 | `Campaign/cosmetics.gd` | skip. `for_frame` returns `[NONE]` and the cycle control still works (`cosmetics.gd:84-90`) | no hat |
| 14 | a mission's `unlocks` | **do add**, and it is the real gate — `required_rank` is inert (§6.4). Without it the frame is on sale from the first visit to base and `audit_economy.gd:167` prints the line | on sale immediately |
| 15 | `Campaign/lab/plans/*.tres` | optional. `bulwark_screen.tres` is the precedent, but an AI-vs-AI matchup measures a frame's combat and this one has none | no bench number |
| 16 | `tools/test_drayman.gd` | **write it**, §6 | — |
| 17 | `tools/probe_nav_reach.gd` `FRAMES` | optional. `drayman.tscn`'s capsule is radius 0.85, height 3.4 — **identical to the Rover's**, and `FRAMES` already has `"rover": [0.85, 1.70, 0.75]`. No new entry needed; say so rather than adding a duplicate | — |
| 18 | a new `ItemDefinition` | **none**, §3 | — |

Not applicable: §1.4 items 9 and 10 (mission `EnemySquadSpec`, `Enums.Factions`)
— this is a player frame and introduces no faction.

---

## 6. Tests — `tools/test_drayman.gd`

Model it on `tools/test_bulwark.gd`; its `_test_the_chassis_is_registered`
(70-90) is §1.3 of the anatomy as a test and is the cheapest thing to copy.
`tools/test.sh` runs every `tools/test_*.gd`, so wiring is free.

**Registration**

1. `chassis_drayman.tres` loads, `def.id == &"drayman"`, `def.scene != null`.
2. `def.purchasable` is true and the id appears in
   `load("res://Campaign/items & catalogue/test_item_catalogue.tres").chassis`.
3. `KillKinds.FRAMES.has(&"drayman")` and
   `KillKinds.frame_of(&"drayman") != null`.
4. `int(def.weapon_slots) == 1` and `String(def.starting_weapon_id) == ""` —
   the second is the assertion that keeps a gun off it, because
   `starting_weapon_id` bypasses `takes()` (§6.2).
5. `def.built_in == "ARM"`.

**The gun can never be fitted — the assertion that locks §2's `turret = false`**

6. For every item in `catalogue.items` with `kind == ItemDefinition.Kind.WEAPON`:
   `def.takes(item) == false`. Asserted across the whole catalogue, not against
   a list of five ids, so a future vehicle gun with an empty `chassis_whitelist`
   fails here instead of appearing on a supply truck.

**The scene**

7. Spawned, the body `is_in_group("enemies")` **and**
   `is_in_group(AI.SIGNAL_GROUP)` — `test_bulwark.gd:120-127` is the copy.
8. `weapon_mount != null` and it is a descendant of the node named `Wrist`
   (walk up the tree, do not compare names — `test_bulwark.gd:107-118` is the
   idiom). This is what proves the authored-mount decision in
   `build_drayman.gd:163-173` survived.
9. `body.weapon == null` after a frame, and stays null: nothing fits.
10. `AllowedMovementOptions` and `AllowedCombatOptions` are both non-empty and
    are `Array[int]`. Assert the *contents* — `[0, 2]` and `[0]` — so §6.1
    cannot quietly come back, and assert the type because an untyped array
    saves as `[]` in silence (§6.6).
11. `FactionLivery.pieces` is non-empty and does **not** contain the eye: paint
    the body a hostile faction and assert `Rig/Head/Eye`'s material is
    unchanged.
12. The frame never enters a firing state: drive `handle_weapon_logic` for N
    ticks with a live hostile in reach and assert `weapon_state` never leaves
    IDLE.

**The behaviour**

13. A player with a part-empty `AmmoPool` within reach has its count *raised*
    after a channel; one outside `weld_reach`-equivalent does not.
14. A squadmate with a spent `AIEquipmentSlot` (`consume()` called until
    `remaining() == 0`) is restored to at least 1 when in reach.
15. **Capacity is finite.** After `loads` completed hand-overs it stops, and
    the refusal is observable (a warning, or a `loads == 0` read) — asserted,
    because an infinite one makes the whole frame a non-decision.
16. It refuses a customer who is already full — no wasted load.
17. **Squad ammunition is still infinite, and the frame knows it.** Assert that
    an `AIWeapon` with `magazine_current == 0` reaches `magazine_size` through
    `_finish_reload()` alone, with no Drayman present. This is the §0 premise
    as an assertion: if someone later adds a reserve to `ai_weapon.gd`, this
    test fails and the Drayman's brief gets reopened on purpose.

---

## 7. Order of work

| step | do | prove |
|---|---|---|
| 1 | `chassis_drayman.tres` + `kill_kinds.gd` entry + catalogue entry (both the `ext_resource` and the array) | `bash tools/check.sh --changed` prints PASS. `tools/test_drayman.gd` steps 1-6 pass. The frame appears in the factory |
| 2 | Fix `AllowedMovementOptions` / `AllowedCombatOptions` in `drayman.tscn`; settle the `base_speed` double-multiply (§2) | test steps 10 and 7-9. `bash tools/smoke.sh` — the two `Cannot assign contents of "Array[Object]" to "Array[int]"` errors on load stop |
| 3 | `tools/bake_icons.gd`, and `icons/items/arm_*.png` | the PNGs land in `icons/chassis/`. **Say in the report whether they did** (§6.3) |
| 4 | `drayman.gd extends Rover` with the two stubs only — `handle_weapon_logic` and `_weapon_on_target` — plus `formation_trail`, and repoint `drayman.tscn`'s `script` | `bash tools/smoke.sh`. A spawned Drayman drives, never aims, never fires. Lab or `tools/mockup_shots.gd` for a look |
| 5 | `AIEquipmentSlot.restore()` | `bash tools/test.sh` whole — this touches a shared resource that `soldier_record.gd`, `squad_spawner.gd` and the designator all read |
| 6 | Channel B: `_choose_customer` + `_hand_over` restoring equipment charges, with `loads` finite | test steps 14, 15, 16 |
| 7 | Channel A: the player's `AmmoPool` | test step 13 |
| 8 | A mission `unlocks` entry | `tools/test_ledger.gd` (826-831 asserts an unlock resolves to something buyable) |
| 9 | Hand to the human | it cannot be judged without playing. **State explicitly that `loads = 8` is a guess** — `DRAYMAN.md` §8 already says so |

Steps 1-4 are shippable on their own: a registered, buyable, drivable truck
that carries nothing. That is a worse frame than the Bulwark and should not be
the stopping point, but it is a safe checkpoint.

---

## 8. Open questions and risks

1. **The job is narrow and the human should know before approving.** §1: the
   player's ammo is per-life (`test_character.gd:765`), so half the frame is
   worth nothing to a player who dies. The equipment-charge half is the part
   that holds. If the human does not want a frame whose value is "your squad's
   smoke comes back", this is the moment to cut it — and cutting it is a
   reasonable answer, since the premise it was approved on is gone (§0).
2. **`vehicle = true` or `false`.** §2. The doc says true; the Reclaimer, which
   is the lineage, says false, and the argument for false is the same argument.
   This changes which team it joins and therefore how it moves with the squad.
   **Human call.**
3. **`base_speed` is specified twice** in two different units. §2. Pick one.
4. **`AIEquipmentSlot.restore()` is a shared-resource change.** Two lines, but
   `ai_equipment_slot.gd` is read by `soldier_record.gd` (206, 215, 433, 467,
   532), `squad_spawner.gd` (324), `enemy_loadouts.gd` (414) and the
   designator. Run the whole `tools/test.sh`, not `--changed`.
5. **`built_in = "ARM"` has no icon art.** §6.10. Either bake it or accept the
   blank, and say which.
6. **`loads = 8` is a guess**, and so is the channel rate. Neither can be
   judged without playing.
7. **No AI will ever request resupply.** §4. An AI-commanded Drayman is
   reactive at best. Same honest answer the doc gave; nothing has changed.
8. **Not checked:** whether the crate stack should visibly deplete as `loads`
   falls. `build_drayman.gd:720-743` builds twelve named crates
   (`Load/Crate000`…) and two strap runs, so hiding a course per few loads is
   cheap and would make the frame's state readable the way the Vessel's bay is.
   Not specified above because it is an art call. **Recommend it** — it is the
   same argument `VESSEL.md` §5 makes, and it costs a loop over named nodes.

---

# AMENDMENT — 2026-10-10, human review.

**Approved, and it gets more equipment slots.**

The human's words: *"drayman. yes and we can give it more equipment slots as
well."* Two things follow.

1. **The narrow-gap warning in §1 is answered — build it.** The job is
   restoring squad equipment charges, which this brief established is the one
   consumable in the game with no escape hatch (`AIEquipmentSlot` has
   `initialize`, `has_uses`, `consume` and `remaining`, and no way back). The
   ammunition half is dropped as the premise it was.
2. **Raise `equipment_slots` above the value in §2's table**, and say in your
   report what you chose and why. The frame now has two reasons for them: what
   it restores to others, and what it carries itself. Those are different
   arguments and the number should follow whichever the build settles on —
   check whether `AIEquipmentSlot` restore works slot-for-slot or by item id,
   because that decides whether a Drayman must *carry* smoke to refill smoke.

The two-line `AIEquipmentSlot.restore()` this brief specifies is a change to a
shared resource script. It needs the full `tools/test.sh`, not just
`check.sh --changed`.
