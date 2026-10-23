# Frame anatomy — everything a chassis needs in order to exist

The integration companion to `FRAME_MODELS.md`. That document stops at the
`.tscn`. This one starts there and ends at a frame that is buyable, spawnable,
killable and countable.

**Read this, then write your frame's brief.** Where it says *mandatory* it means
the frame is broken without it. Where it says *silent* it means nothing errors,
nothing warns, and the bug presents as a game-feel complaint weeks later.

Every claim below carries a `file:line`. Where I could not find something I say
so in section 8 rather than guessing.

Traced on the **Soldier** (`chassis_soldier.tres` → `soldier_chassis.tscn` →
`soldier.gd`), cross-checked against the **Rover** (vehicle), the **Bulwark**
(most recent frame) and the **Spotter Drone** (`weapon_slots = 0`).

---

## 1. The checklist

### 1.1 The two files that are already yours

| file | state |
|---|---|
| `Character/characters/ai/<frame>.tscn` | **exists** for all eight |
| `tools/build_<frame>.gd` | **exists** for all eight |

Both are done. Nothing in this document asks you to touch either, except where
section 6 says a value in the scene is wrong.

### 1.2 Mandatory for any frame at all

| # | where | what | if missed |
|---|---|---|---|
| 1 | `Campaign/chassis/chassis_<id>.tres` | a `ChassisDefinition` with `id`, `display_name`, `scene`, and the stats | nothing can reference the frame; `EnemySquadSpec.roster` and `ItemCatalogue.chassis` both take `ChassisDefinition`, not a scene |
| 2 | the scene's root script | must resolve to a `Soldier` or a subclass | **hard error, but only at spawn.** `enemy_force_spawner.gd:265` and `squad_spawner.gd:273` both do `_CsgBake.make(frame.scene) as Soldier`; a plain `Enemy` root casts to null and the body is dropped with a `push_error` (`enemy_force_spawner.gd:267`). All eight new frames are already fine — `walker.gd`, `rover.gd` and `spotter_drone.gd` all extend `Soldier` |
| 3 | the scene's `groups=["enemies"]` | persistent group on the root node | silent: invisible to `AIManager`, to EMP, and to every hostile sweep. All eight already have it (verified: `grep groups= Character/characters/ai/*.tscn`) |
| 4 | `Campaign/kill_kinds.gd` `FRAMES` (14–37) | `&"<id>": "res://Campaign/chassis/chassis_<id>.tres"` | silent: `frame_of()` returns null (`kill_kinds.gd:73-77`), so the debrief prints a raw id with no icon (`debrief_screen.gd:685-692`), the roster glyph is blank (`hud_glyphs.gd:64-67`), and `tools/bake_icons.gd:126-129` never bakes an icon for it |
| 5 | the scene's `AllowedMovementOptions` / `AllowedCombatOptions` | non-empty `Array[int]` | silent, and **all eight are currently empty.** See trap 6.1 — this is the single biggest live defect in the batch |

### 1.3 Mandatory to be *buyable* (player frames: Lance, Picket, Drayman, Kite, Vessel)

| # | where | what | if missed |
|---|---|---|---|
| 6 | `Campaign/items & catalogue/test_item_catalogue.tres` | append to both the `[ext_resource]` block and the `chassis = Array[...]([...])` line (currently line 48) | silent in the shop: `squad_manager_ui.buildable_frames()` (440–453) walks `catalogue.chassis` only, so the frame simply is not offered. Worse downstream: `SoldierRecord.recompute_stats` warns and falls back to class defaults (`soldier_record.gd:229-236`), and `CampaignState.supply_of` returns 1 for an unknown frame (`campaign_state.gd:315-317`) |
| 7 | `purchasable = true` on the `.tres` | | `recruit()` refuses outright (`campaign_state.gd:740-741`) |
| 8 | `icons/chassis/<id>_s.png`, `_m.png`, `_l.png` | baked by `tools/bake_icons.gd` | silent: `Icons.chassis` returns null (`icons.gd:45`) and the UI shows the name alone. **The Bulwark shipped without these and still has none** — see trap 6.3 |

**`Campaign/item_catalogue.tres` is a dead stub.** It carries soldier and
nothing else (`item_catalogue.tres:21`). The live catalogue is
`Campaign/items & catalogue/test_item_catalogue.tres`, wired in at
`Env/world.tscn:20`. Edit the one in the `items & catalogue` folder. Both
`test_enemy_loadouts.gd:21` and `test_bulwark.gd:86` hard-code the live path.

### 1.4 Mandatory to be *fielded by a mission* (enemy frames: Broodcarrier, Bastion, See-Engine)

| # | where | what | if missed |
|---|---|---|---|
| 9 | a mission `.tres` | an `[ext_resource]` for the chassis plus an `EnemySquadSpec` sub-resource whose `roster` array holds it | the frame exists and nothing spawns it. `mission_salient_1_overthetop.tres` is the Bulwark's worked example |
| 10 | `Enums.Factions` + `are_hostile()` | **read `docs/frames/ENEMY_FACTIONS.md` first** | thirty-five silent call sites. `enums.gd:29-38` matches four values and falls through to `return false` |

Enemy frames are **deliberately not** in the player catalogue.
`test_ledger.gd:449-465` pins this as an assertion: a frame left in the
catalogue and named by no mission's `unlocks` is on sale from the first minute,
because `locked_by()` only gates what a mission names (`campaign.gd:1068-1082`).

### 1.5 Optional, and what each one buys

| # | where | buys | default if skipped |
|---|---|---|---|
| 11 | `Campaign/kill_kinds.gd` `SCENES` (40–59) | scene-basename → frame id, for a body with no `chassis_id` meta | **only needed when the basename differs from the id.** `kind_of()` falls through to `SCENES.get(base, StringName(base))` (`kill_kinds.gd:70`), so `bastion.tscn` + id `bastion` resolves for free — which is exactly why the Bulwark has no `SCENES` entry and works. A frame whose scene is `see_engine.tscn` and whose id is `see_engine` is fine; `&"gunship"` → `enemy_helicopter.tscn` is why the table exists |
| 12 | `Campaign/enemy_loadouts.gd` `TABLES` (46–191) | per-body variation: rolled modules, equipment, alternative guns | every body of that frame is identical, carrying only `starting_weapon_id`. `roll_for` returns an empty dictionary for an unlisted frame (`enemy_loadouts.gd:208-210`). **Adding a key commits you to a test**: `test_enemy_loadouts.gd:91-124` asserts every entry resolves and is legal |
| 13 | `Campaign/cosmetics.gd` | hats and pauldrons | no hat. `for_frame` returns `[NONE]` (`cosmetics.gd:84-90`) and the cycle control still works. The Bulwark, Spotter, Diver and Nest all have no entry |
| 14 | a mission's `unlocks` array | gates the frame behind clearing an operation | **on sale from the first visit.** `test_ledger.gd:826-831` only asserts the reverse (that an unlock resolves to something buyable) |
| 15 | `Campaign/lab/plans/*.tres` | an AI-vs-AI bench matchup | no bench measurement. `bulwark_screen.tres` is the precedent |
| 16 | `tools/test_<frame>.gd` | the frame's own invariants | `tools/test.sh` runs every `tools/test_*.gd`, so adding one is free to wire. `test_bulwark.gd` is the model and is worth reading in full before writing yours |
| 17 | `tools/probe_nav_reach.gd` `FRAMES` (87–95) | navmesh clearance measurement for the frame's hull | the probe cannot be run for it. Values come from `tools/probe_chassis_size.gd` |
| 18 | a new `ItemDefinition` + `AIWeapon` scene | a weapon that does not exist yet | section 3 |

### 1.6 What needs no registration at all

- **CSG baking.** `csg_bake.gd:177-189` reads `res://Character/characters/ai`
  from the directory, so a new scene is baked without a list entry.
- **Icon baking** reads `catalogue.chassis` plus `KillKinds.FRAMES`
  (`bake_icons.gd:120-129`) — so items 4 and 6 are what get you an icon.
- **Teams.** `CampaignState.ensure_teams` splits on `frame.vehicle`
  (`campaign_state.gd:468-496`), so `vehicle = true` is the whole of it.
- **The `"signal"` group** (EMP, suppression) is joined in `AI._ready`
  (`ai.gd:86-88`), not per scene.
- **The `"air"` group** is joined in `spotter_drone.gd:108` / `diver.gd:100` /
  `enemy_helicopter.gd:124`, so any frame on one of those scripts gets it.
- **`AIManager` registration** is done by whoever spawns the body
  (`enemy_force_spawner.gd` ~line 322, `enemy_nest.gd:213`, `lab.gd:289`).

---

## 2. `ChassisDefinition`, field by field

`Campaign/chassis_definition.gd`. Everything below cites the declaring line and
then the places that actually read it.

### Identity

| field | line | read by | notes |
|---|---|---|---|
| `id` | 12 | everywhere | **PERMANENT ONCE SAVED.** See 2.5 |
| `display_name` | 13 | `KillKinds.name_of` (81-84) strips a trailing `" CHASSIS"`; `_recruit_name` (`campaign_state.gd:769-770`) takes the **first word** for the callsign; `set_meta(&"analytics_kind", frame.display_name)` (`enemy_force_spawner.gd:280`) | player-facing in the comms log. Name it the way a soldier would say it |
| `description` | 14 | factory and hologram cards | |
| `icon` | 15 | `Icons.chassis` (43-44) — an inspector-set texture **wins over the baked PNG** | leave null and let `bake_icons.gd` do it |
| `scene` | 18 | every spawner; also written onto the record by `set_chassis` (`soldier_record.gd:309`) and serialised as a **path** in the save (`soldier_record.gd:472`) | **renaming or moving the .tscn orphans saved records.** See 2.5 |

### Economy

| field | line | read by | notes |
|---|---|---|---|
| `cost` | 19 | `recruit` (745), `buy_chassis` (1228-1232), factory card | |
| `purchasable` | 22 | `recruit` (740), `buildable_frames` (445), `chassis_hologram._buildable` (87-98) | |
| `supply` | 25 | `supply_of` (315-317), `supply_used`, the bench rule in `recruit` (759) | seats, paid for with compute |
| `required_rank` | 79 | **only** `set_chassis` (`campaign_state.gd:1165`) | **does nothing in the factory.** `recruit()` (739-764) never looks at it, and `factory_page.gd` never reads it. The Bulwark's `required_rank = 3` is inert — a brand-new rank-0 robot is born in it. Use a mission `unlocks` entry to gate a frame |

### Stats

| field | line | player squad | enemies | notes |
|---|---|---|---|---|
| `base_health` | 38 | absolute, via `recompute_stats` (`soldier_record.gd:238`) | `_apply_frame` assigns **only if `> 0`** (`enemy_force_spawner.gd:527-529`) | 0 means "keep the scene's value" |
| `base_speed` | 39 | a **multiplier** folded into `effective_speed` (`soldier_record.gd:254`), applied as `soldier.move_speed *= …` (`squad_spawner.gd:349`) | **not applied at all.** `_apply_frame` (524-532) sets health, accuracy and sensors and nothing else | so an enemy frame's real speed is `move_speed` on its scene, full stop. `item_facts.chassis_speed` (234-248) instantiates the scene to read it, because the definition's 1.00 is not a speed |
| `base_accuracy` | 40 | multiplier → `accuracy_skill *=` (`squad_spawner.gd:348`) | assigned if `> 0` (530) | the Spotter and Nest set 0.0 on purpose |
| `base_sensor_range` | 43 | absolute → `sensor_range =` (`squad_spawner.gd:350`) | assigned if `> 0` (532) | |

### Slots and mounts

| field | line | read by | notes |
|---|---|---|---|
| `weapon_slots` | 47 | `resize_slots` (`soldier_record.gd:157`), `_fit_loadout` (`squad_spawner.gd:298-311`), `roll_for` (`enemy_loadouts.gd:216,226`) | **effectively capped at 2.** `_fit_loadout` breaks at `i > 1` (`squad_spawner.gd:300-301`); slot 0 is the main gun, slot 1 is the coax |
| `starting_weapon_id` | 29 | `recruit` (750-751) writes it into `weapon_ids[0]`; `_issue_weapon` (`enemy_force_spawner.gd:503-521`) fits it to an empty mount; `lab.gd:268-275`; `hud_glyphs.weapon_icon` (56-57) | **bypasses `takes()`.** See trap 6.2 |
| `coax_weapon_id` | 35 | **only** `lab.gd:279-282` and `test_walker.gd:71-75` | explicitly *not* issued in the campaign: the coax is a purchase (`campaign_state.gd:753-758`) |
| `equipment_slots` | 68 | `resize_slots` (158), `equipment_capacity` (316-331 — modules can add to it) | |
| `module_slots` | 69 | `resize_slots` (159) | |
| `built_in` | 50 | `Icons.built_in` (63-66) does `path("items", name.to_lower())`; shown in place of a weapon slot (`factory_page.gd:258-259`, `chassis_hologram.gd:312-315`); `hud_glyphs.gd:61` | a **string**, not an enum, and it doubles as an icon filename. `"OPTICS"` on the Spotter happens to find `icons/items/optics_*.png`. A novel word with no art silently comes back null |
| `weapon_replaces_built_in` | 55 | `squad_page.gd:216,614,640,848,948`, `ui_kit.gd:401`, `factory_page.gd:323,350` | the Reclaimer's mortar standing where its welder was |
| `turret` | 58 | `takes()` (91), `factory_page.gd:317,348`, `ui_kit.gd:399` | "the slot takes only weapons that name this frame in `chassis_whitelist`" |

### Classification

| field | line | read by | notes |
|---|---|---|---|
| `vehicle` | 63 | `CampaignState._is_vehicle` (494-496) → team assignment; `squad_spawner._all_vehicles` (179-187) → `Squad.vehicles_only` and `armor_follow_distance`; `factory_page._badges` (319) | **which team it joins.** Note the Bulwark sets `vehicle = true` and `drives = false`: it walks, and it is still in ARMOR |
| `drives` | 67 | `takes()` (89-90) refuses anything with `fits_vehicles = false`; `enemy_loadouts._legal` (328-330); `squad_page.gd:1095` | "wheels or tracks, so nanites are no use to it" |
| `musters_at_base` | 76 | **only** `campaign.gd:910-917` | false keeps the frame out of the hub scene (the Spotter's rotor loop) while still deploying it |

### `takes(item)` — lines 84-91

The single gate on whether an item may be fitted. Reached from
`CampaignState.can_fit` (`campaign_state.gd:1099`). Three refusals:
`item.fits_chassis(id)` (the item's own whitelist), `drives and not
item.fits_vehicles`, and `turret and kind == WEAPON and not
item.chassis_whitelist.has(id)`.

### 2.5 Permanent once written

`kill_kinds.gd:21-24` is the recorded case: the quadcopter bomber's id is still
`gunship` because career tallies in `campaign.json` were written under it. The
same property, found by reading what `to_dict` emits:

- **`id`** — written to the save in three places:
  `soldier_record.to_dict` `"chassis_id"` (`soldier_record.gd:486`), the
  `kills_by_kind` keys (483), and `armoury.add_chassis(chassis.id)` stock
  (`campaign_state.gd:1234`). A rename orphans all three.
  There *is* a migration hook — `CampaignState.RENAMED` (1473-1475), currently
  `{&"hopper": &"leaper"}`, applied to kill tallies on load
  (`soldier_record.gd:516`) — but **it is applied to `kills_by_kind` only.**
  I did not find it applied to `chassis_id` or to armoury stock.
- **`scene`** — serialised as a resource path (`soldier_record.gd:472`) and
  reloaded with a `ResourceLoader.exists` guard (520). A moved `.tscn` makes
  every saved record of that frame fall back to the spawner's
  `default_chassis` (`squad_spawner.gd:269-272`).
- **`Enums` ordering** — `faction`, `ItemDefinition.Kind`, `Enemy.AIState`,
  `MovementOptions`, `CombatOptions`, `Enums.AIWeaponTypes`. All stored as ints
  in `.tscn` and `.tres`. Append only. `ENEMY_FACTIONS.md` documents the 805
  on-disk `faction = 1` values.
- **Equipment slot `.tres` paths** — `soldier_record.gd:466` saves
  `slot.resource_path`.

Not permanent, and safe to retune at any time: every stat, every slot count,
`cost`, `supply`, `display_name`, `description`, `built_in`, `icon`.

---

## 3. How a weapon is actually made

### 3.1 The chain, traced on the M4

1. **`Campaign/items/item_m4.tres`** — an `ItemDefinition` with `id = &"m4"`,
   `kind = 0` (WEAPON), `cost`, a `player_scene`, and
   `ai_scene = res://Character/weapon/ai-wep_m4.tscn` (line 16).
2. **`Character/weapon/ai-wep_m4.tscn`** — root `Node3D` with
   `ai_weapon.gd` on it (line 3), the ballistics as exported values
   (lines 13–27), and three wired node paths: `muzzle_flash`, `muzzle_origin`,
   `shot_audio` (24–26). The root transform is yawed so the model's own axis
   lines up (line 11).
3. **Fitting, at spawn.** `Enemy.equip_weapon_scene` (`enemy.gd:58-72`) frees
   whatever is on `weapon_mount`, instantiates, sets
   `transform = Transform3D.IDENTITY`, and casts to `AIWeapon`. A non-`AIWeapon`
   scene warns (72). `equip_coax_scene` (77-92) is the same for `coax_mount`,
   and warns-and-drops if the frame has no second mount (80).
4. **Who calls it.** Player squad: `squad_spawner._fit_loadout`
   (`squad_spawner.gd:298-311`), reading `record.weapon_ids` in slot order.
   Enemies: `_issue_weapon` (`enemy_force_spawner.gd:503-521`) for
   `starting_weapon_id`, then `EnemyLoadouts.apply` (`enemy_loadouts.gd:393-403`)
   for a rolled or forced replacement. Lab: `lab.gd:262-282`.
5. **Firing.** Nothing in the weapon decides anything. `Enemy.handle_weapon_logic`
   (`enemy.gd:2846-2949`) runs the IDLE → AIM → FIRE machine and calls
   `weapon.fire(weapon_target)`. The coax is driven separately by `_tick_coax`
   (2964) and makes no decisions at all.

The catalogue is also the *reverse* index: `hud_glyphs._item_for_scene`
(`hud_glyphs.gd:72-81`) maps `ai_scene.resource_path` back to the item, which is
how the roster shows what a robot is holding. A weapon with no `ItemDefinition`
has no icon anywhere, even if it works.

### 3.2 `starting_weapon_id` and `weapon_slots`, precisely

- `weapon_slots` sizes `record.weapon_ids` (`soldier_record.gd:157`).
- `recruit()` writes `weapon_ids[0] = starting_weapon_id` **directly**
  (`campaign_state.gd:750-751`), without consulting `takes()`.
- `weapon_slots = 0` means `weapon_ids` is an empty array, the `if not
  record.weapon_ids.is_empty()` guard fails, and the frame is issued nothing.
  `_issue_weapon` for an enemy is **not** gated on `weapon_slots` — it only
  checks `starting_weapon_id != &""` (504) — so a `weapon_slots = 0` enemy frame
  with a non-empty `starting_weapon_id` *will* be armed. Set it to `&""`.
- `weapon_slots >= 2` is what unlocks the coax pool in
  `enemy_loadouts.roll_for` (226), and slot 0 is backfilled from
  `starting_weapon_id` if the roll left it empty (231-232).

### 3.3 "Weapon" means "occupies a weapon mount"

`kind = 0` is a slot type, not a damage promise. Two things to get right here,
because the brief you are writing may have inherited a wrong version of this:

- **`item_repair_lance.tres` is NOT the AI precedent.** It is `kind = 0` and it
  heals, but `usable_by_ai = false` (line 20) and it has **no `ai_scene`**, so
  `fits_ai()` returns false (`item_definition.gd:145-150`) and no robot can ever
  carry it. It is a player viewmodel only.
- **The real AI precedent is the Reclaimer.** `chassis_reclaimer.tres` has
  `weapon_slots = 1`, `starting_weapon_id = &""`, `built_in = "WELDER"` and
  `weapon_replaces_built_in = true` — a weapon mount that is *empty by default*
  and holds a tool. `item_mortar.tres` is the thing that goes in it
  (`chassis_whitelist = [&"reclaimer"]`), and fitting it hides the welder
  (`reclaimer.gd:875-882`) and switches the healing brain off
  (`reclaimer.gd:887-891`).

So: a tool that is part of the body needs **no item at all** — it is `built_in`
plus code. A tool that can be swapped for a gun needs `weapon_slots = 1`,
`weapon_replaces_built_in = true`, and an item whitelisted to the frame.

### 3.4 When a `.tres` is enough, and when you need a subclass

`Character/weapon/ai_weapon.gd` (809 lines) is the base. Three subclasses exist.

| subclass | file | overrides | why |
|---|---|---|---|
| `AIWeaponGrenadeLauncher` | `ai_weapon_grenade_launcher.gd` | `check_damage` (65), `shot_damage` (134) | the base's `check_damage` is a hitscan ray. A launcher spawns a `grenade_scene` instead, with salvo, fuse, high-arc and lob-speed exports. `shot_damage` had to go too, so analytics credit the blast and not a bullet |
| `AIWeaponRecoilless` | `ai_weapon_recoilless.gd` | `check_damage` (64), `shot_damage` (47), plus `_aim` (94) | same reason, for a `rocket_scene` |
| `AIWeaponDroneBomb` | `ai_world_weapon_drone bomb.gd` | `fire`, `play_shot_audio` | **legacy. Do not copy it.** It extends `AIWorldWeapon` (`Character/weapon/appx/ai_world_weapon.gd`), a second, older weapon base class, and `ai_weapon_grenade_launcher.gd:7-9` says in as many words that this is why it cannot be reused |

**The rule, read off those three: you need a subclass if and only if the round
is not a hitscan ray.** `AIWeapon.check_damage` (396-429) and `_one_round`
(431-501) do a ray per pellet; `check_melee_damage` (555-595) does a sphere
sweep gated on `weapon_type == MELEE`. Everything else — damage, falloff,
spread in milliradians, pellets, magazine and reload, suppression radius,
friendly-fire line checks, tracers, muzzle flash, audio, melee arc — is an
`@export` on the base (lines 11-83) and is authored in the `.tscn`.

**A `.tres` plus a scene is enough for:** a different rifle, MG, shotgun (set
`pellets` / `pellet_spread_mrad`), DMR, autocannon, or **a melee weapon**
(`ai-wep_melee.tscn` is the plain `ai_weapon.gd` with `weapon_type` unset and a
box mesh — nothing new was written for the Chaser's claws).

**A `.tres` plus `ai_weapon_grenade_launcher.gd` is enough for** anything that
lobs a charge: `ai-wep_mortar.tscn`, `ai-wep_grenade_launcher.tscn`,
`ai-wep_turret_grenade_launcher.tscn` and `ai-wep_cluster.tscn` all share that
one script with different exports. Check the existing exports
(`grenade_scene`, `salvo`, `high_arc`, `lob_speed`, `impact_fused`,
`blast_override`, `fuse_override`) before proposing a new script.

**You need a new subclass for:** a beam, a guided or homing projectile, a
weapon that applies a status rather than damage, a deployable, or anything that
needs its own target selection beyond `AIWeapon.Targeting` (the enum at 700-706
with `acquire()` at 729 already gives the mortar independent acquisition).

Also note: `max_effective_range` is what the whole AI reads as "my reach"
(`Enemy._max_range`, 3022), `min_effective_range` makes the robot refuse to fire
closer (`enemy.gd:2920-2921`), and `melee_range` is what stops a melee frame
swiping at air 30 m away (`_score_combat_option`, 3183-3189).

---

## 4. The behaviour seams

Inheritance for every frame in the game:
`<Frame> → Soldier → Enemy → AI → CharacterBody3D`.
`walker.gd`, `rover.gd`, `spotter_drone.gd`, `diver.gd`, `mechanic.gd`,
`enemy_nest.gd`, `enemy_watcher.gd` and `enemy_helicopter.gd` all extend
`Soldier` directly; `bulwark.gd` extends `Walker`; `reclaimer.gd` extends
`mechanic.gd` by path string.

### 4.1 What you get free, and must not re-implement

From **`Enemy`** (5638 lines — grep it before writing anything):

- **State machines.** `AIState {COMBAT, PATROL, SEARCH, IDLE, DEAD, PASSIVE}`,
  `MovementState`, `WeaponState`, `CombatOptions`, `MovementOptions`
  (`enemy.gd:1088-1092`).
- **The decision loop.** `roll_combat_action` (3052) weights
  MOVE/AIM/FIRE through `_score_combat_option` (3079) and dispatches via
  `perform_action` (3927); `_pick_movement_option` (3133) /
  `_score_movement_option` (3153) pick between ADVANCE, REPOSITION, FALLBACK,
  LEAP and CHASE. Both score on range ratio, line of sight, health fraction,
  magazine state and `signal_integrity`, and both apply a `repeat_penalty` to
  the previous choice.
- **Navigation.** `move_to` (2399), `_tick_nav` (2549), `move_along_nav` (2740),
  `handle_chasing` (2759), plus a per-frame budget on nav and snap queries
  (`_take_nav_query` 2579, `_take_snap_query` 2640).
- **Think throttling and culling.** `_think_tier` (748), `think_wait_seconds`
  (774), `take_think_slice` (828), `lod_scale` (1053), `_freeze_for_cull`
  (2122), `thaw_from_cull` (2129).
- **Vision.** `_tick_vision` (929), a cone plus peripheral plus an `_awareness`
  ramp, `sight_range` (910), `reacquire_range` (923).
- **Weapons.** `handle_weapon_logic` (2846), `_tick_coax` (2964), bursts,
  reloads, `_prefire_threshold` (3003), suppressive fire.
- **Equipment.** `_tick_equipment` (3674), `_evaluate_equipment_use` (3703),
  `order_use_equipment` (3833), `_ordered_context` (3863). An
  `AIEquipment.EquipmentContext` (`ai_equipment.gd:30-45`) is already populated
  with threat, nearest-downed-friendly, bearing, hostiles-around and
  `under_fire_seconds` — a new piece of equipment is a resource and a
  `can_use`/`execute` pair, not a frame concern.
- **Damage and death.** `apply_damage` (4154), `die` (4223), `enter_downed`
  (4264), `destroy` (4342), `apply_healing` (4377), `revive` (4440), the whole
  settle/collapse/wreck sequence (4485-4715), `reset` (4726).
- **Signal.** `receive_signal_damage` on `AI` (`ai.gd:116`), `_tick_signal`
  (`enemy.gd:4953`), `_enter_ekill` (4930), `_can_receive_orders` (5025).
- **Physics niceties.** `_damp_shoving` (1714), `_step_over` (1767),
  `_tick_give_way` (5363), `_tick_adrift` (1834), `_drown_check` (1944).

From **`Soldier`** (534 lines):

- **Cover.** `enter_cover_seeking` (124), `find_best_cover_point` (149),
  `release_cover` (193).
- **Fire and manoeuvre.** `enter_suppressing` (203), `enter_suppressed` (231),
  `enter_bounding` (250), `find_flank_target` (469).
- **The squad interface.** `order_move_to` (370), `assign_role` (430) with the
  `SoldierRole` enum (26), `squad` back-reference (32), `defensive_mode` (36),
  `squad_is_engaged` (76).
- **Two authored switches that need no code.** `aggressive` (48) — never takes
  cover, never suppresses, never falls back, takes every squad role as ADVANCER
  (438-442). `formation_trail` (52) — how far behind the line it walks; the
  Mechanic's value is why it stops being the first thing every fight finds.

### 4.2 The override seams, with their shipped examples

These are the functions a frame subclass is *expected* to override. If your
frame needs none of them, say "no new script needed" and mean it.

| seam | declared | overridden by | what it is for |
|---|---|---|---|
| `takes_cover()` | `soldier.gd:145` | `walker.gd:251`, `bulwark.gd:123`, `rover.gd:578`, `spotter_drone.gd:191`, `reclaimer.gd:271`, `enemy_nest.gd:100`, `enemy_watcher.gd:81`, `diver.gd:148` | **the most-overridden function in the project.** `Squad` splits its members on it (`squad.gd:554-555`, `1540-1541`): false means "parks on the spot instead of being sent to a cover point" |
| `_update_facing(delta)` | `enemy.gd:2780` | `walker.gd:206` (turret traverse), `bulwark.gd:211` (split arm/torso yaw), `rover.gd:597` (hull vs turret), `spotter_drone.gd:184` (no-op; attitude comes from flight), `enemy_nest.gd:113`, `diver.gd:144` | who points where |
| `_turret_forward()` | `walker.gd:229` | `bulwark.gd:276`, `rover.gd:615` | the bearing `_weapon_on_target` compares against |
| `_weapon_on_target()` | `enemy.gd:2999` | `walker.gd:239`, `rover.gd:625` | the fire cone. Overriding it wrong is a frame that never shoots |
| `move_to(pos, think_delay)` | `enemy.gd:2399` | `rover.gd:226`, `reclaimer.gd:580`, `spotter_drone.gd:166`, `diver.gd:130`, `enemy_nest.gd:91`, `enemy_watcher.gd:72` | a flyer sets an orbit centre; a fixed frame refuses |
| `move_along_nav(delta)` / `_tick_nav` | 2740 / 2549 | `rover.gd:243,260`, `reclaimer.gd:591,647`, `enemy_nest.gd:86`, `enemy_watcher.gd:67` | steering that is not "walk along the path" |
| `handle_movement(delta)` | `enemy.gd:2333` | `spotter_drone.gd:220`, `diver.gd:155`, `enemy_helicopter.gd:180` | **replaces navigation entirely.** The three flyers |
| `handle_gravity(delta)` | `enemy.gd:2239` | `spotter_drone.gd:155` (gravity only while parked), `diver.gd:118`, `enemy_helicopter.gd:146` | flight |
| `_apply_motion()` | `enemy.gd:1659` | `spotter_drone.gd:160`, `diver.gd:124`, `enemy_helicopter.gd:150` | plain `move_and_slide` instead of the shove/step machinery |
| `off_navmesh_is_normal()` | `enemy.gd:1830` | `spotter_drone.gd:392`, `diver.gd:418`, `enemy_helicopter.gd:551` | stops the adrift/return logic dragging a flyer back to the ground |
| `handle_weapon_logic(delta)` | `enemy.gd:2846` | `spotter_drone.gd:175` (**`pass`**), `diver.gd:135`, `enemy_helicopter.gd:163` | an unarmed frame, or one whose "weapon" is itself |
| `roll_combat_action()` | `enemy.gd:3052` | `spotter_drone.gd:179` (**`pass`**), `diver.gd:139`, `enemy_helicopter.gd:169` | opts out of the generic dice. `spotter_drone.gd:29-32` records why: the dice is what let one bomber drop and its wingman not |
| `reconsider_combat()` | `enemy.gd:3329` | `soldier.gd:85` | blocks the dice while a soldier state is running |
| `perform_action(action)` | `enemy.gd:3927` | `soldier.gd:283` | the defensive-mode / cannot-reach interception |
| `trigger_combat(body)` | `enemy.gd:5155` | `soldier.gd:320`, `mechanic.gd:132` | what to do on first contact |
| `order_move_to(...)` | `soldier.gd:370` | `mechanic.gd:157`, `reclaimer.gd:287`, `enemy_nest.gd:95`, `enemy_watcher.gd:76` | a frame that refuses orders, or defers them to its own job |
| `assign_role(role)` | `soldier.gd:430` | `mechanic.gd:149` (ignores roles outright) | |
| `enter_cover_seeking()` | `soldier.gd:124` | `rover.gd:574`, `mechanic.gd:170`, `reclaimer.gd:275`, `enemy_nest.gd:104`, `enemy_watcher.gd:85` | belt-and-braces with `takes_cover()` |
| `slot_tolerance(t)` / `formation_width()` | `enemy.gd:1033` / `1040` | `rover.gd:543,556`, `spotter_drone.gd:198,204`, `reclaimer.gd:281` | how much room the frame needs in a formation, and how close counts as "in its slot". A flyer that does not override `slot_tolerance` is re-ordered every single frame (`spotter_drone.gd:150-154`) |
| `_sight_forward()` | `enemy.gd:1046` | `rover.gd:621` | which way the sensors look when the hull and turret disagree |
| `_desired_facing()` | `enemy.gd:2794` | `mechanic.gd:177` | |
| `_handle_path_blocked()` | `enemy.gd:3233` | `rover.gd:523`, `reclaimer.gd:617` | reversing out instead of sidestepping |
| `_collapse_pieces()` | `enemy.gd:4644` | `rover.gd:788`, `reclaimer.gd:1048` | what a wreck looks like |
| `equip_weapon_scene(scene)` | `enemy.gd:58` | `reclaimer.gd:863` | **builds its own mount.** The only frame that does |
| `die()` / `destroy()` / `enter_downed()` / `_enter_ekill()` / `_on_crash_started()` / `_on_crash_landed()` / `_on_revived()` | 4223 / 4342 / 4264 / `ai.gd:179` / 4332 / 4336 / 4815 | `soldier.gd:516`, `enemy_nest.gd:121`, `enemy_watcher.gd:101`, `diver.gd:403`, `spotter_drone.gd:359-390`, `enemy_helicopter.gd:518-549` | `spotter_drone._enter_ekill` calls `die()`: losing the link at altitude means losing lift, which is what makes EMP anti-air |
| `_tick_gait(delta)` | `walker.gd:117` | `bulwark.gd:70` | legged animation |
| `_choose_patient()` / `_tool_on(p)` / `_keeping_back()` / `_live_threat()` | `mechanic.gd:219 / 346 / 437 / 445` | `reclaimer.gd:887 / 821 / 299 / 307` | the repair brain's seams |

### 4.3 Reading the table

A frame on **`walker.gd`** (Bastion, Picket, See-Engine) already has: legged
gait, turret traverse and elevation, a fire cone, and `takes_cover() = false`.
It needs a script only if the aiming geometry differs from "gun on the turret"
(which is exactly and only what `bulwark.gd` was written for) or it has a
behaviour of its own.

A frame on **`rover.gd`** (Lance, Drayman, Vessel) already has: Ackermann
steering, reverse, whisker blocking, pack spacing, suspension, turret traverse,
wreck pose. It needs a script only for a behaviour.

A frame on **`spotter_drone.gd`** (Kite, Broodcarrier) gets flight, orbit,
separation, the parked-at-base rule, and the crash/down/revive sequence — but
`handle_weapon_logic` and `roll_combat_action` are **`pass`**. **A frame on this
script that is supposed to shoot will not shoot.** The Kite is armed and the
Broodcarrier spawns; both therefore need at least those two functions restored
or replaced. `enemy_helicopter.gd` is the worked example of an armed flyer: it
stubs the same two and drives its own ordnance from a four-phase
`handle_movement` (180-330).

A frame that **spawns things** has one example: `enemy_nest.gd`. It needs an
`@export var hatchlings: Array[ChassisDefinition]` (37), a timer, a live list
with a `max_alive` cap, and `_hatch()` (184-227) — which has to do the spawner's
whole job by hand: `_CsgBake.make(...) as Soldier`, faction, `always_active`,
health from the frame, a name, `EnemyLoadouts.apply`, `add_child`, position,
`ai_manager.register_enemy`, and handing the newborn its parent's target.
**Note what it does not do: it never sets the `chassis_id` meta**, which is why
`KillKinds.SCENES` has `"enemy_nest-chaser": &"leaper"` — a hatchling is counted
by its scene name.

---

## 5. What a frame cost when it was not just stats

### The Bulwark — one script, 295 lines

Reason (`bulwark.gd:88-135`): the torso is the turret, so the shield hangs off
the thing that traverses. Walker's `_turret_forward` returns the *turret's*
bearing and `_weapon_on_target` fires off that — but on this frame the gun is a
metre out on an arm with its own joint, so inheriting either one means a frame
that refuses to fire whenever its arm bears and its torso does not, which is
most of the time it is doing its job.

Written: `_pose_arms` (81), `takes_cover` (123), `_update_facing` (211),
`_turret_forward` (276), `_body_facing` (291), `_tick_gait` (70). Plus six
`@export`s and a split-yaw cone.

Everything else it touched: `chassis_bulwark.tres`, a `TABLES` entry
(`enemy_loadouts.gd:114-118`), a catalogue entry
(`test_item_catalogue.tres:43,48`), `kill_kinds.gd:35`, a lab plan
(`bulwark_screen.tres`), a mission (`mission_salient_1_overthetop.tres`), and
`tools/test_bulwark.gd`. **No `SCENES` entry** (basename matches id), **no
cosmetics entry**, **no baked icon**, **no mission unlock**.

### The Nest — a spawner

See 4.3. The script is 260 lines, of which the hatching is ~70 and the rest is
refusing to move (`move_to`, `move_along_nav`, `order_move_to`,
`enter_cover_seeking`, `_update_facing` all stubbed) and burning down.

### The Reclaimer — a tool arm

1076 lines on top of `mechanic.gd`'s 527. The arm is IK'd by hand
(`_tick_arm` 760, `_pose_arm` 805), the mount for its weapon does not exist until
something asks for one (`equip_weapon_scene` 863 — the one frame that builds its
own mount, and `enemy_force_spawner.gd:509-512` is deliberately *not* guarded on
`weapon_mount` because of it), the welder hides when armed (`_show_welder` 875),
the healing brain switches off when armed (`_choose_patient` 887), and it gained
a whole second job — salvage (`_tick_salvage` 321 … `_pay` 521) — plus a mortar
brain (`_tick_mortar` 894 … `_laid_on` 1034).

### The Spotter Drone — flight

393 lines, and the instructive part is how much of it is *opting out*:
`handle_gravity`, `_apply_motion`, `move_to`, `handle_weapon_logic`,
`roll_combat_action`, `_update_facing`, `takes_cover`,
`off_navmesh_is_normal` are all stubs or near-stubs. The actual new code is
`handle_movement` (220) and the eight helpers under it.

---

## 6. The traps

`FRAME_MODELS.md` section 5 lists the model traps. These are the integration
ones. Everything here compiles, runs, and is wrong.

### 6.1 All eight frames have empty `Allowed*Options` — fix this first

```
bulwark      AllowedMovementOptions = Array[ExtResource("2_b16t6")]([])
bastion      AllowedMovementOptions = Array[ExtResource("2_akk77")]([])
brood        ... ([])      drayman ... ([])      lance   AllowedMovementOptions = []
picket       ... ([])      see_engine ... ([])   vessel  ... ([])
```
vs the two frames that work:
```
soldier_rifle   AllowedMovementOptions = Array[int]([0, 1])     AllowedCombatOptions = Array[int]([0, 1, 2])
vehicle_rover   AllowedMovementOptions = Array[int]([0, 2, 4])  AllowedCombatOptions = Array[int]([0, 1, 2])
```

`FRAME_MODELS.md` already names the symptom — the
`Cannot assign contents of "Array[Object]" to "Array[int]"` pair that every
generated frame prints on load — and says to report it and leave it. **What it
does not say is what the empty arrays do.**

`roll_combat_action` returns at `enemy.gd:3053-3054` when
`AllowedCombatOptions.is_empty()`. `perform_action` is therefore never reached
from the combat timer, which means:

- **the frame never chooses MOVE in combat** — no ADVANCE, no REPOSITION, no
  FALLBACK, no LEAP, no CHASE. It moves only when its squad orders it to
  (`soldier.order_move_to`), so a patrolling or garrisoned hostile stands still
  for the whole fight;
- **`_commit_burst` (3960) is never called**, so `_burst_left` stays 0 and
  `handle_weapon_logic` can only fire through the full settle gate
  (`_aim_tracking >= _prefire_threshold()`, 2925-2932). The frame still shoots,
  slowly, in single shots, which is why this reads as a feel problem rather than
  a bug;
- **`_enter_aim_stance` (3953) is never called**, so the frame never stops to
  settle.

`walker.tscn`, `spotter_drone.tscn`, `kite.tscn`, `mechanic_chassis.tscn` and
`enemy_nest.tscn` also carry no override at all, which is the same empty default
— for the stub-everything frames that is harmless, and for the Walker it is
masked by the fact that it fights under squad orders. **Decide your values
deliberately and state them in your brief.** `MovementOptions` is
`{ADVANCE=0, REPOSITION=1, FALLBACK=2, LEAP=3, CHASE=4}` and `CombatOptions` is
`{MOVE=0, AIM=1, FIRE=2}` (`enemy.gd:1091-1092`).

### 6.2 `starting_weapon_id` bypasses `takes()`, so a turret frame can be armed once and never again

`chassis_bulwark.tres:15` issues `heavy_mg`. `item_heavy_mg.tres:37` whitelists
`[&"walker", &"rover"]`. `chassis_bulwark.tres:24` sets `turret = true`.
`ChassisDefinition.takes` (`chassis_definition.gd:91`) therefore returns
**false** for `heavy_mg` on a Bulwark, and `CampaignState.can_fit`
(`campaign_state.gd:1099`) is the gate the squad screen uses.

So: `recruit()` writes the gun straight into `weapon_ids[0]` (750-751) and the
Bulwark deploys armed — but the player cannot refit it, and taking the gun off
is irreversible. `enemy_loadouts.gd:109-113` documents the same hole from the
other side ("giving it a weapons pool here would ask the legality check for
something it is right to refuse").

**If your frame sets `turret = true`, its own id must be in the
`chassis_whitelist` of every weapon it is meant to carry.** Nothing warns.

### 6.3 A frame with no baked icon just shows a name

`icons/chassis/` has no `bulwark_s.png`, `bulwark_m.png` or `bulwark_l.png`.
Confirmed by listing the directory. `Icons.chassis` returns null
(`icons.gd:45`), `Kit.icon(null, …)` draws nothing, and `icons.gd:11-13` says
this is by design — "a picture is never the only way to tell what something is".
So the most recent frame in the game has a blank factory card and a blank roster
glyph, and has had since it was built. Run `tools/bake_icons.gd` and say in your
report whether the PNGs landed.

### 6.4 `required_rank` on a chassis does not gate buying it

`recruit()` (`campaign_state.gd:739-764`) checks `purchasable` and affordability
and nothing else. `required_rank` is read only by `set_chassis` (1165), which is
*refitting an existing robot*. `factory_page.gd` never reads the field at all.
A `required_rank = 3` frame is on sale to a brand-new campaign, and
`audit_economy.gd:167` already prints the line "chassis no mission names is on
sale from the first visit to base." The real gate is an entry in a mission's
`unlocks` array (`campaign.gd:1068-1082`, `factory_page.gd:217-223`).

### 6.5 A non-exhaustive `match` on an enum never warns

`Enums.are_hostile` (`enums.gd:26-38`) matches four `Factions` values and falls
out to `return false`. GDScript does not warn. `ENEMY_FACTIONS.md` is the
worked audit: thirty-five call sites, none of which error. The same shape exists
anywhere a frame introduces an enum value — `Enemy.AIState`,
`MovementOptions`, `Enums.AIWeaponTypes`. Append only, and grep for every
`match` on the enum you touched.

### 6.6 A typed array assigned an untyped one saves as `[]`

`FRAME_MODELS.md` trap 2, repeated here because the integration side has its own
instances: `SoldierRecord.equipment` is `Array[AIEquipmentSlot]`,
`weapon_ids`/`equipment_ids`/`module_ids` are `Array[StringName]`,
`EnemySquadSpec.roster` is `Array[ChassisDefinition]`,
`EnemyNest.hatchlings` is `Array[ChassisDefinition]`,
`Enemy.equipment_slots` is `Array[AIEquipmentSlot]`. All of them pack as empty if
handed a plain `Array`, in silence. `test_bulwark.gd:190-197` is the comment
that documents it as the project's standard failure.

### 6.7 `add_to_group` without `true` never reaches the saved scene

`FRAME_MODELS.md` trap 1. All eight new scenes already pass. Worth restating
only because `test_bulwark.gd:120-127` turned it into the assertion you should
copy: `is_in_group("enemies")` **and** `is_in_group(AI.SIGNAL_GROUP)`.

### 6.8 A null in the catalogue array is a frame that silently vanishes

`item_catalogue._build_index` (`item_catalogue.gd:43-53`) exists because a
renamed or moved `.tres` leaves a `null` in the exported array, the catalogue
still loads, and every record naming that frame reports "no chassis". This one
*does* `push_error` — it is the model for how these failures should be written —
but you only see it if you read the console. **Do not rename a chassis `.tres`
after adding it to the catalogue.**

### 6.9 An enemy frame's `base_speed` is ignored

`_apply_frame` (`enemy_force_spawner.gd:524-532`) applies health, accuracy and
sensor range. There is no speed line, and none in `EnemyLoadouts.apply`
beyond the module multiplier (`enemy_loadouts.gd:429`). An enemy frame's speed
is `move_speed` on its `.tscn`, and `base_speed` on the definition does nothing
for it. For a *player* frame `base_speed` is a multiplier on the scene's value
(`soldier_record.gd:254` → `squad_spawner.gd:349`), not a speed — which is why
`item_facts.chassis_speed` (234-248) instantiates the scene to draw the card.

### 6.10 `built_in` is a filename

`Icons.built_in` (`icons.gd:63-66`) does
`path("items", StringName(name.to_lower()))`. `"WELDER"` wants
`icons/items/welder_s.png`; `"OPTICS"` on the Spotter resolves to the Optics
*item's* icon by coincidence (`icons.gd:60-62` says so). A new word with no
art is a silent blank in the roster's weapon column. Also: two badge rules in
`factory_page._badges` (323-328) key off the literal string `"WELDER"`, so
calling a repair tool anything else loses the MEDIC and ARTICULATED ARM badges.

### 6.11 `weapon_slots` is capped at two by the fitting code

`squad_spawner._fit_loadout` breaks at `i > 1` (`squad_spawner.gd:300-301`) and
`enemy_loadouts.roll_for` only knows about `weapons` and `coax` (216, 226).
`Enemy` has exactly two mount references, `weapon` and `coax`
(`enemy.gd:27`, `52`). **Do not propose a three-mount frame** without saying in
the brief that it is runtime work in `Enemy`.

### 6.12 `equip_coax_scene` on a frame with no `coax_mount` warns per body per mission

`enemy.gd:77-81`. `enemy_loadouts.gd:221-225` documents the cost of getting this
wrong. If your frame has two mounts, the scene needs a `coax_mount` node path
wired; if it does not, do not give it a `coax` pool.

### 6.13 `always_active` does not exempt a frame from distance culling

`enemy_force_spawner.gd:537-546`. A long ADVANCE from 200 m does not happen
unless the spawner explicitly walks them in (`_let_them_walk_in`, 570). Relevant
to any brief that proposes a frame arriving from off-map.

---

## 7. Proving it

```bash
bash tools/check.sh --changed              # must print PASS
bash tools/test.sh                         # every tools/test_*.gd
```

```bash
# the frame scene's own bug list — groups, typed arrays, livery, mount yaw
"D:/Godot Games/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe" \
  --headless --audio-driver Dummy --path . \
  --script res://tools/check_frame.gd -- res://Character/characters/ai/<frame>.tscn
```

If your frame adds a `TABLES` entry, `tools/test_enemy_loadouts.gd` will assert
it. If it is player-buyable, `tools/test_ledger.gd` exercises recruit, refit and
save round-trip. Write a `tools/test_<frame>.gd` modelled on
`tools/test_bulwark.gd` — its `_test_the_chassis_is_registered` (70-90) is
literally section 1.3 of this document as a test, and is the cheapest thing you
can copy.

**Do not run anything through Godot while `tools/test.sh` is in flight.** The
suites share `user://` probe paths and a parallel run produces a FAIL that looks
real and does not reproduce.

---

## 8. What I looked for and could not find

Stated plainly, because a confident wrong answer here is worse than a gap.

1. **A rename migration for `chassis_id`.** `CampaignState.RENAMED`
   (`campaign_state.gd:1473-1479`) exists and is applied to `kills_by_kind` keys
   on load (`soldier_record.gd:514-517`). I could **not** find it applied to
   `SoldierRecord.chassis_id` or to `Armoury` chassis stock. Treat an id as
   permanent unless someone extends that hook.
2. **Where a player squad body gets its `chassis_id` meta.** `enemy_force_spawner.gd:282`
   sets it for hostiles and `enemy_nest.gd` sets it for nothing; I found no
   equivalent in `squad_spawner.gd`, which sets only `record_id` (246, 444, 566).
   So a player frame is identified by `KillKinds.SCENES` / scene basename, not
   by meta. This is why item 11 matters more for player frames than for enemies.
   I did not find anything that counts the *loss* of a player frame by kind, so
   I cannot say what the user-visible consequence is.
3. **Any check that a frame in the catalogue has baked icons.** Nothing asserts
   it, which is how the Bulwark's missing PNGs survived. `check_frame.gd` does
   not cover it (I read its function list; it checks the scene, not the
   registration).
4. **A documented reason `walker.tscn` has no `Allowed*Options`.** It may be
   deliberate (the Walker fights under squad orders) or it may be the same
   generator bug as the eight new frames. I could not find a comment either way,
   so 6.1 states the mechanism and leaves the Walker's case open.
5. **Whether `AIWorldWeapon` is intended to be retired.**
   `ai_weapon_grenade_launcher.gd:7-9` says the two bases cannot be mixed and
   calls `AIWeaponDroneBomb` "older", but I found no plan to remove it.
6. **A per-frame speed field that is actually a speed.** There is none; see 6.9.
   If a brief wants to specify a speed, it specifies `move_speed` on the scene
   and must say so.
