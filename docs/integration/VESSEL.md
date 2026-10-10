# VESSEL — integration brief

Supply 3 · wheeled · carrier · **model built, nothing registered**

Written for a builder. The map is `docs/briefs/FRAME_ANATOMY.md`; this document
cites it by section instead of restating it. Everything else carries a
`file:line`.

**What exists today:** `Character/characters/ai/vessel.tscn` (root script
`rover.gd`, `groups=["enemies"]`, a real traversing turret, a bay with named
doors and named cargo) and `tools/build_vessel.gd`. There is no
`ChassisDefinition`, no catalogue entry, no `kill_kinds` entry, no behaviour
script.

---

## 0. Two things in the design doc are wrong. Read these first.

**(a) `starting_weapon_id = &"machine_gun"` with `turret = true` is the Bulwark
bug, exactly.** `VESSEL.md` §3 and §4 call `machine_gun` "existing,
vehicle-legal". It is vehicle-legal and it is **not Vessel-legal**:
`Campaign/items/item_machine_gun.tres:37` is
`chassis_whitelist = Array[StringName]([&"rover", &"walker"])`.
`ChassisDefinition.takes` (`chassis_definition.gd:91`) refuses a `kind = WEAPON`
item on a `turret = true` frame whose id is not in that whitelist, and
`CampaignState.can_fit` (`campaign_state.gd:1099`) is the gate the squad screen
uses. Meanwhile `recruit()` writes `starting_weapon_id` straight into
`weapon_ids[0]` without consulting `takes()` (`campaign_state.gd:750-751`).

So the Vessel would deploy armed, the player could never refit it, and taking
the gun off would be irreversible — which is the state the Bulwark has shipped
in (`FRAME_ANATOMY.md` §6.2). **Fix: add `&"vessel"` to
`item_machine_gun.tres:37`.** Nothing warns if you do not.

Every vehicle weapon in the catalogue has the same shape, checked:
`autocannon` `[walker, rover]`, `heavy_mg` `[walker, rover]`,
`grenade_launcher` `[rover]`, `mortar` `[reclaimer]`. Whichever gun the Vessel
is meant to carry, its id goes on that item's whitelist.

**(b) `equipment_slots = 2, pre-loaded with hatchling` is not a thing a chassis
can do, and 2 is the wrong number anyway.**

- `ChassisDefinition.equipment_slots` is a **count**, read only by
  `resize_slots` (`soldier_record.gd:158`) and `equipment_capacity`
  (`campaign_state.gd:316-331`). There is no field for a default item. What a
  squad body actually carries is built in `squad_spawner._fit_loadout` from
  `record.equipment_ids` — the player's purchases (`squad_spawner.gd:313-331`).
- **One hatchling slot already gives two releases.**
  `Campaign/items/item_hatchling.tres` sets `quantity = 2`, which
  `squad_spawner.gd:324` copies onto the slot and `AIEquipmentSlot.initialize()`
  turns into `_quantity_remaining = 2` (`ai_equipment_slot.gd:26-27`).
  `ItemFacts` prints it as "2 PER MISSION" (`item_facts.gd:76`). So
  `equipment_slots = 2` both filled with hatchlings is **four** releases, not
  the two the frame is designed around.

There is a loophole worth naming and then not using: `squad_spawner.gd:330-331`
only assigns `soldier.equipment_slots` when the record produced a non-empty
list, so `AIEquipmentSlot`s authored into `vessel.tscn` would survive for a
player who fitted nothing — and vanish the moment they fit anything. That is
not "pre-loaded", that is a frame whose contents disappear when the player
touches the loadout screen. **Do not do it.**

---

## 1. What "successful" means

**The player buys one supply-3 frame that is not a gun, drives it to a flank,
and puts two bodies on the ground where the squad is not.** The read is the
doors: closed while it travels, open when it is committed, closed again when
the bay is spent — so the thing the player is deciding about is a thing they
can see from the command height.

### Be honest: the gap is thin as specified, and here is exactly how thin

Traced through what already exists:

- `item_hatchling.tres` → `ai_scene = ai_hatchling.tscn`, which is
  `ai_deploy.gd` with `canister_scene = hatchling_canister.tscn`
  (`ai_hatchling.tscn:22-30`).
- The canister's `explosion_scene` is `hatchling_payload.tscn`
  (`hatchling_canister.tscn`), whose `unit_scene` is
  `Character/characters/ai/enemy_nest-chaser.tscn` — **the hopper/leaper**
  (`hatchling_payload.tscn:4,8`).
- `hatchling_payload.gd` defaults: `count = 1` (line 25), `lifetime = 25.0`
  (31), `can_be_downed = false` (73-74), and it **never joins a squad** —
  `_release` sets faction, name, `always_active`, `credit_kills_to`, registers
  with the `AIManager` and sics it at the nearest hostile (48-86). No
  `Squad.add_ai_to_squad` call anywhere in the file.

So the Vessel as specified costs **340 compute and 3 supply** and produces
**two single hoppers, each alive for 25 seconds, neither of which takes an
order.** Against the Walker at 320 for a permanent two-mount gun platform, that
is not a trade a player makes twice.

**Recommendation: fix this with one new scene and no new code.** A
`Character/weapon/hatchling/vessel_bay_payload.tscn` — the same
`hatchling_payload.gd`, different `@export` values:

```
unit_scene = enemy_nest-chaser.tscn   # unchanged
count      = 2                        # two bodies per release, four per bay
unit_name  = "HATCHLING"
lifetime   = 600.0                    # the mission, effectively
seek_radius = 45.0                    # unchanged
```

plus a `vessel_bay_canister.tscn` (`hatchling_canister.tscn` with
`explosion_scene` repointed) and an `ai_vessel_bay.tscn`
(`ai_hatchling.tscn` with `canister_scene` repointed and `min_hostiles` raised
to 2, which is what `ai_deploy.gd:26-29` already says the drone pack should do).
Three `.tscn` files, zero `.gd` files, and the frame's output becomes four
persistent bodies released in two waves. **That is a supply-3 proposition.**

**Do not set `lifetime = 0.0` meaning "forever".** `_expire_later`
(`hatchling_payload.gd:109-113`) does `create_timer(lifetime, false)` with no
zero guard, so 0.0 fires on the next frame and destroys the unit immediately.
Found while reading; flagged here because it is the obvious thing someone will
try.

### On "should released drones join the squad"

`VESSEL.md` §6.3 recommends they do. **Recommend against it for v1**, and the
reason is a citation that already exists: `enemy_nest.gd:29-32` —
*"WHAT COMES OUT IS NOT IN A SQUAD. Chasers and leapers rush whatever they can
see; a squad node around them would only add formation orders they would
immediately break."* The hatchling releases that same hopper chassis, and
`hatchling_payload.gd` was deliberately written not to squad them.

`Squad.add_ai_to_squad(ai)` exists (`Managers/AI/squad.gd:1023`), so it is
possible — but the payload emits no signal when it releases, so `vessel.gd`
would have to discover the new bodies by watching the tree. That is real work
for a behaviour the Nest's own author argued against. **Leave it open, do not
build it.**

---

## 2. The `ChassisDefinition`

`Campaign/chassis/chassis_vessel.tres`. Copy
`Campaign/chassis/chassis_walker.tres` as the template — it is the other
supply-3 frame and the one this one is balanced against.

| field | value | reasoning |
|---|---|---|
| `id` | `&"vessel"` | **PERMANENT** (`FRAME_ANATOMY.md` §2.5): written to `SoldierRecord.chassis_id`, the `kills_by_kind` keys and armoury stock, and the `RENAMED` hook covers only the third of those |
| `display_name` | `"Vessel"` | `_recruit_name` takes the first word (`campaign_state.gd:769`) |
| `description` | "Six-wheeled carrier. Two hatchling charges ride in the open bay; it has a gun so it can get there, not so it can lead." | |
| `icon` | null | let `tools/bake_icons.gd` do it |
| `scene` | `res://Character/characters/ai/vessel.tscn` | **PERMANENT** (§2.5) |
| `cost` | 340 | the doc's, just above the Walker's 320 (`chassis_walker.tres:12`) |
| `purchasable` | `true` | or `recruit()` refuses (`campaign_state.gd:740-741`) |
| `supply` | 3 | the doc's, the Walker's |
| `base_health` | 260 | the doc's. **`vessel.tscn:388-389` already carries `health = 260` / `max_health = 260`**, so the two agree. Under the Walker's 320 |
| `base_speed` | **1.0** — a change | the doc says 0.85, but §6.9: for a player frame this is a *multiplier* applied at `squad_spawner.gd:349`, and `vessel.tscn:391` already authors `move_speed = 7.0` (the Rover's). 0.85 here gives 5.95. If 5.95 is wanted, **set `move_speed = 5.95` on the scene and leave this at 1.0**; do not specify it twice. State which you did |
| `base_accuracy` | 1.0 | it has a real gun |
| `base_sensor_range` | **45.0** | the doc says 50; `vessel.tscn:438` says 45.0. Make them agree. Either is under the Walker's 60 (`chassis_walker.tres:20`), which is the balance point that matters |
| `weapon_slots` | 1 | the doc's. The Walker's two mounts are its identity; a coax here would make the Walker pointless. `test_bulwark.gd:78-83` is the shipped assertion of exactly this reasoning |
| `starting_weapon_id` | `&"machine_gun"` | **and §0(a) must be done, or this frame can never be refitted** |
| `coax_weapon_id` | `&""` | `vessel.tscn` has one `WeaponMount` and no `coax_mount`; a coax pool would warn per body per mission (§6.12) |
| `built_in` | `""` | it carries a real gun, not a tool |
| `weapon_replaces_built_in` | `false` | nothing to replace |
| `turret` | `true` | the doc's, and the **node** exists — `vessel.tscn:554` `Rig/Turret`, exported at `turret = NodePath("Rig/Turret")`, with `turret_traverse_degrees = 95.0` and `gun_elevation_degrees = 60.0`. `enemy.gd` reads the *node* property for `hull_spoils_aim`, so the frame can fire while driving. The definition's `turret` flag is the *fitting gate* — see §0(a) |
| `vehicle` | `true` | it is an armoured carrier and belongs in the ARMOR team (`campaign_state._is_vehicle`, 494-496; `squad_spawner._all_vehicles`, 179-187). Unlike the Drayman, this one fights |
| `drives` | `true` | settled by the concept (`VESSEL.md` §1): the hull is a six-wheeler. `takes()` then refuses anything with `fits_vehicles = false` (`chassis_definition.gd:89-90`) |
| `equipment_slots` | **1** — a change from the doc's 2 | §0(b). One slot carrying `hatchling` is two releases, which is the frame as designed. Two slots is four. If the human wants four, say four and set 2 |
| `module_slots` | 2 | the doc's. The Walker has 3; fewer is part of being weaker than it |
| `musters_at_base` | `true` | it should stand in the hub |
| `required_rank` | **leave 0** | read only by `set_chassis` (`campaign_state.gd:1165`), never by the factory (§6.4). The doc's 4 would be inert exactly as the Bulwark's 3 is. **Gate it with a mission `unlocks` entry** — and it should be the last thing unlocked, which is what the doc meant |

**Permanent once written:** `id`, `scene`. It introduces no enum value, so
§2.5's ordering rule does not bite. Everything else is retunable.

**The balance constraint is the point of the frame** and belongs in the test,
not just the table: weaker than the Walker in health, sensors and mounts, and
not faster. `VESSEL.md` §7 is right that this should be asserted against
`chassis_walker.tres` directly so the two cannot silently converge.

---

## 3. Items and weapons

### Is a new `ItemDefinition` needed? **No. Confirmed.**

`VESSEL.md` §4 claims this and it holds up:

- `Campaign/items/item_hatchling.tres` is `kind = 1` (EQUIPMENT),
  `fits_vehicles = true`, `usable_by_ai = true`, `ai_scene = ai_hatchling.tscn`,
  `chassis_whitelist = []`, `quantity = 2`, `cost = 75`, `in_shop = true`. It is
  **already in the live catalogue** — `test_item_catalogue.tres:21` declares it
  as `id="18_hatchling"` and line 47 has it in the `items` array.
- `takes()` has three refusals (`chassis_definition.gd:84-91`) and the hatchling
  passes all three on a Vessel: its own whitelist is empty, `fits_vehicles` is
  true so `drives = true` does not refuse it, and the `turret` refusal applies
  only to `kind == WEAPON`.
- `fits_ai()` is true (`item_definition.gd:145-150`) — it has an `ai_scene` and
  `usable_by_ai = true` — so `squad_spawner.gd:313-331` will build an
  `AIEquipmentSlot` for it with `quantity = 2`, `label` and `item_id` set.
- The AI will use it unprompted: `Enemy._tick_equipment` (`enemy.gd:3674`) →
  `_evaluate_equipment_use` (3698) every `EQUIPMENT_RECON_TIME = 1.5 s`
  (`enemy.gd:1283`), and `AIDeploy.can_use` (`ai_deploy.gd:65-97`) asks only
  "is there anything within `release_radius` worth opening for". The player can
  also order it: `ordered_at_point = false` on `ai_hatchling.tscn`, which
  `ai_equipment.gd:106-115` documents as "the useful order is *open it*, and it
  is the one the player can give instantly".
- Icons already exist: `icons/items/hatchling_{s,m,l}.png`.

**So the Vessel is a chassis, a behaviour script, and a registration pass.** No
`ItemDefinition`, no `AIWeapon` scene, and therefore `FRAME_ANATOMY.md` §3.4's
subclass-or-not question does not arise. The only weapon is the existing
`machine_gun`, which already has `ai-wep_machine_gun.tscn` behind it.

### The one thing worth adding, and it is three scenes not an item

§1's `vessel_bay` variant: new `.tscn` files reusing `hatchling_payload.gd`,
`ai_grenade_projectile.tscn` and `ai_deploy.gd` with different exported values.
If you do add it, it **does** need an `ItemDefinition` so the player can buy it
and so `hud_glyphs._item_for_scene` (`hud_glyphs.gd:72-81`) can draw it:

| field | value | note |
|---|---|---|
| `id` | `&"bay_charge"` | permanent in the save once fitted (`soldier_record.gd:466` saves slot paths, 467 the quantity) |
| `display_name` | `"Bay Charge"` / `short_name` `"Bay"` | |
| `kind` | `1` (EQUIPMENT) | |
| `cost` | ~140 | the hatchling's 75 for twice the bodies that last |
| `ai_scene` | `res://Character/weapon/hatchling/ai_vessel_bay.tscn` | |
| `player_scene` | **null** | and `usable_by_player = false`: the player has no bay |
| `usable_by_ai` | `true` | or `fits_ai()` is false and the slot is never built |
| `fits_vehicles` | `true` | or `takes()` refuses it on `drives = true` |
| `quantity` | `2` | two releases |
| `chassis_whitelist` | `Array[StringName]([&"vessel"])` | the mortar's pattern (`item_mortar.tres`), so it cannot be fitted to a rifleman. **TYPED** — an untyped array saves as `[]` in silence (§6.6) |
| `in_shop` | `true` | |

Closest template file: `Campaign/items/item_hatchling.tres` for the shape,
`Campaign/items/item_mortar.tres` for the whitelist-to-one-frame pattern.

---

## 4. The behaviour

### Script

`Character/characters/ai/vessel.gd`, **`extends Rover`**. `rover.gd` is already
the root script (`build_vessel.gd:220`) and `vessel.tscn` authors its whole
driving block — `wheelbase = 1.4`, six wheels with `Spin` children,
`wheel_steer = [1, 1, 0, 0, -1, -1]`, `reverse_lamps`, turret traverse 95°,
gun elevation 60°, `fire_cone_degrees = 6.0`. `FRAME_ANATOMY.md` §4.3: a frame
on `rover.gd` "needs a script only for a behaviour". The doors are the
behaviour.

`VESSEL.md` §5's "`extends Walker` (legged) or `Soldier` (tracked)" is stale —
the concept settled on wheels (§1 of that doc) and the built scene is on
`rover.gd`.

### `Allowed*Options` — give these as values

`vessel.tscn:449-450` currently ships
`AllowedMovementOptions = Array[ExtResource("2_de4yg")]([])` and the same for
combat — the §6.1 defect. `roll_combat_action` returns at `enemy.gd:3053-3054`
on an empty combat array, so the frame never chooses MOVE in combat, never
commits a burst, and never settles to aim.

**Set, copying `vehicle_rover.tscn` verbatim:**

```
AllowedMovementOptions = Array[int]([0, 2, 4])   # ADVANCE, FALLBACK, CHASE
AllowedCombatOptions   = Array[int]([0, 1, 2])   # MOVE, AIM, FIRE
```

`vehicle_rover.tscn` is one of only two frames in the game with correct values
(§6.1) and it is the same chassis class, the same script, the same traversing
turret and the same single mount. Reasoning for keeping all three combat
options: unlike the Drayman, this frame **has a gun and must use it** — the
whole premise is that it can defend itself while it gets to the release point.
Reasoning for the movement set: ADVANCE and FALLBACK as the Rover has them,
CHASE because a wheeled carrier with a machine gun chasing a broken squad is
correct behaviour; no REPOSITION (1) and no LEAP (3) — a six-wheeler does
neither.

Enums: `MovementOptions {ADVANCE=0, REPOSITION=1, FALLBACK=2, LEAP=3, CHASE=4}`,
`CombatOptions {MOVE=0, AIM=1, FIRE=2}` (`enemy.gd:1091-1092`). These are
stored as ints in the `.tscn` and are append-only (§2.5).

### Functions `vessel.gd` overrides

| function | declared | why |
|---|---|---|
| `_ready()` | — | resolve `Rig/Bay/DoorL`, `Rig/Bay/DoorR`, `Rig/Bay/CargoA`, `Rig/Bay/CargoB` once; set the doors **closed** (`rotation.z = 0`) and both cargo nodes visible. **Call `super()`.** Warn and disable the door machine if any node is missing — CLAUDE.md: every early return says why |
| `_physics_process(delta)` | — | drive the door state machine and the bay-state display. **Call `super(delta)`** or the frame stops driving. This is `_physics_process`, not a new `_process` |
| `_spend_equipment(index, equipment, context)` | `enemy.gd:3779` | **the only seam that catches both release paths.** Autonomous use reaches it at `enemy.gd:3751`, the player's order at `enemy.gd:3855`. Gate it on the doors being open, then `super(...)`, then hide a cargo node and schedule the close |
| `takes_cover()` | `soldier.gd:145` | **do not write it.** Checked: `rover.gd:578` already returns `false`, and `rover.gd:574` already stubs `enter_cover_seeking()`. Both are inherited correctly |
| `_collapse_pieces()` | `enemy.gd:4644` | **no.** `rover.gd:788` already does the vehicle wreck and `visible_pieces` is the whole `Rig`. Do not touch it |
| `_update_facing(delta)` / `_turret_forward()` / `_weapon_on_target()` | `enemy.gd:2780` / `walker.gd:229` / `enemy.gd:2999` | **no.** `rover.gd:597`, `615`, `625` already split hull from turret correctly and the gun is on the turret, which is the arrangement they were written for. Overriding `_weapon_on_target` wrong is a frame that never shoots (§4.2) |

### The door state machine — the frame's whole read

**Geometry, measured off the scene.** `Rig/Bay/DoorL` is authored at basis
`(-0.642788, -0.766044 / 0.766044, -0.642788)` = **`rotation.z = +130°`**, and
`Rig/Bay/DoorR` at the mirror = **`rotation.z = -130°`**
(`vessel.tscn:609`, `643`). `build_vessel.gd:102-104` is explicit:
*"TO CLOSE, ROTATE EACH DOOR'S LOCAL Z TO ZERO … 130 degrees of travel each.
Nothing else moves."* Confirmed — the leaves are the only children, and the
hinge bars (`HingeBarL`/`HingeBarR`, 604/638) are separate body-fixed meshes.

**Four states.**

| state | doors | entered when | left when |
|---|---|---|---|
| `STOWED` | `rotation.z = 0` | default, and after a close completes | the frame commits |
| `OPENING` | lerping 0 → ±130° over `door_seconds` | the commit test below passes | travel reaches ±130° → `OPEN` |
| `OPEN` | ±130° | | the commit test has been false for `close_after` seconds, or the bay is empty → `CLOSING` |
| `CLOSING` | lerping ±130° → 0 | | travel reaches 0 → `STOWED` |

**The commit test — this is the design decision, and it is deliberately not
"open at the instant of release".** A door that opens and closes inside the
release frame is not a read; the player has to see the Vessel *decide*. So:

```
_committed() == bay_has_charges() and _fighting()
```

where `bay_has_charges()` reads `equipment_slot_for(&"hatchling")`
(`enemy.gd:3805`) and then `equipment_slots[i].remaining() > 0`
(`ai_equipment_slot.gd:35`), and `_fighting()` is **the Nest's own gate, copied
part for part** (`enemy_nest.gd:176-182`):

```
ai_state == AIState.COMBAT
  or (combat_target != null and is_instance_valid(combat_target) and combat_target.alive)
  or (squad != null and is_instance_valid(squad) and squad.has_live_contact())
```

`Squad.has_live_contact()` is `Managers/AI/squad.gd:944`.

That gives the sequence the human asked for: **drives closed → contact →
doors swing open → a release happens somewhere in the next second and a half →
bay empty → doors swing shut.** It also means the doors open *before* the base
class's 1.5 s `EQUIPMENT_RECON_TIME` tick fires, so the gate below will almost
never refuse.

**The gate in `_spend_equipment`.** A release through shut doors is the one
thing that must not happen:

```
if slot.item_id == &"hatchling" and _door_state != OPEN:
    _request_open()
    _refused_through_shut_doors += 1
    if _refused_through_shut_doors == 1:
        push_warning("%s: a hatchling release was held because the bay doors were shut. "
            % name + "The next recon tick will find them open.")
    return          # no super(), nothing consumed
super(index, equipment, context)
```

Not a coroutine, on purpose: `_spend_equipment` is called from two places
(3751, 3855) and neither awaits it, and `slot.consume()` happens inside
`super()`, so awaiting the door swing would open a window in which
`_equipment_slot_ready` (`enemy.gd:3760`) still reports the slot ready and a
second evaluation could double-spend. A one-tick hold with a warning is the
cheap correct answer. **Warn once, not per attempt** — a per-frame warning in
`_spend_equipment` is a log flood.

Exports, all authored on the script so the human can tune without a rebuild:

```
@export var door_seconds: float = 1.1      # 130 degrees of travel
@export var close_after: float = 4.0       # out of contact this long and it stows
```

Use `rotate`/`lerp_angle` in `_physics_process`, not a `Tween` — but note the
CLAUDE.md rule in the other direction: a coroutine must not outlive the tree,
and a lerp driven off `_physics_process` is safe at quit where an
`await process_frame` chain is not.

### The bay state — two hideable meshes

`VESSEL.md` §5 calls two carried meshes hidden on release "the cheap version
and enough", and the scene is built for it: `Rig/Bay/CargoA` at local
`(0, 1.36, -0.42)` and `Rig/Bay/CargoB` at `(0, 1.36, 1.08)`
(`vessel.tscn:690`, `772`), each a `Node3D` with its own rotor/skid/body
geometry under it, and the cradles and chocks left behind as separate siblings
(`CradleA`, `ChockAL`, `ChockAR` …).

Derive visibility from the slot, do not count separately:

```
var left := slot.remaining()        # 2, 1, 0
cargo_a.visible = left >= 1
cargo_b.visible = left >= 2
```

Forward bay goes first, which matches `build_vessel.gd`'s own naming order.
Deriving it rather than tracking it means a saved-and-restored charge count
(`soldier_record.gd:433`, `532`) cannot disagree with what the bay shows.

`FactionLivery.pieces` must **not** include `CargoA`/`CargoB` if they are to be
hidden — check `vessel.tscn:934` before writing this; `FactionLivery._gather`
recurses into whatever it is handed (`build_drayman.gd:495-513` documents the
trap), and a hidden node is still painted, which is harmless, but a *listed*
node that a script hides is the Picket bug waiting to happen if the geometry is
ever renamed.

---

## 5. Registration — `FRAME_ANATOMY.md` §1, walked

| # | item | status | fails how |
|---|---|---|---|
| 1 | `Campaign/chassis/chassis_vessel.tres` | **to write**, §2 | nothing can reference the frame |
| 2 | root script resolves to `Soldier` | **already fine** — `rover.gd` extends `Soldier`; `vessel.gd extends Rover` keeps it. Repointing `vessel.tscn`'s `script` is part of this work | **hard error at spawn** (`enemy_force_spawner.gd:265-267`) |
| 3 | `groups=["enemies"]` | **already fine** (`vessel.tscn:329`) | **silent** |
| 4 | `Campaign/kill_kinds.gd` `FRAMES` | **to add** — `&"vessel": "res://Campaign/chassis/chassis_vessel.tres"` beside `&"bulwark"` (line 35) | **silent**: raw id in the debrief, blank roster glyph, no icon baked (`kill_kinds.gd:73-77`, `debrief_screen.gd:685-692`, `hud_glyphs.gd:64-67`) |
| 5 | `Allowed*Options` non-empty | **to fix** — `vessel.tscn:449-450`, §4 | **silent** |
| 6 | `test_item_catalogue.tres` | **to add** — an `[ext_resource]` **and** an entry in `chassis = Array[...]` at line 48 | **silent in the shop**; plus the `recompute_stats` and `supply_of` fallbacks |
| 7 | `purchasable = true` | §2 | `recruit()` refuses |
| 8 | `icons/chassis/vessel_{s,m,l}.png` | **to bake** after 4 and 6 land | **silent**: a name and no picture |
| — | **`item_machine_gun.tres:37` whitelist** | **to add `&"vessel"`** — §0(a). Not in the anatomy's checklist because it is a trap, §6.2 | **silent**: a frame that can be armed once and never refitted |
| 11 | `KillKinds.SCENES` | **not needed.** Basename `vessel` = id `vessel`, so `kind_of` falls through at `kill_kinds.gd:70` | — |
| 12 | `enemy_loadouts.gd` `TABLES` | **do not add.** Player frame; and `weapon_slots = 1` means `roll_for` has no coax pool to offer (`enemy_loadouts.gd:226`). Adding a key commits you to `test_enemy_loadouts.gd:91-124` | identical bodies — correct |
| 13 | `Campaign/cosmetics.gd` | skip; `for_frame` returns `[NONE]` | no hat |
| 14 | a mission's `unlocks` | **do add.** The real gate, since `required_rank` is inert (§6.4). It should be the last frame unlocked | on sale from the first visit |
| 15 | `Campaign/lab/plans/*.tres` | **worth it here** — `bulwark_screen.tres` is the precedent, and a Vessel-vs-Walker matchup is the exact measurement §2's balance constraint asks for | no bench number |
| 16 | `tools/test_vessel.gd` | **write it**, §6 | — |
| 17 | `tools/probe_nav_reach.gd` `FRAMES` | **add `"vessel": [1.00, 4.00, 0.45]`** — measured off `vessel.tscn`'s capsule (radius 1.0, height 4.0, `step_height = 0.45`). This is the §8 blocker's instrument | the probe cannot be run for it |
| 18 | a new `ItemDefinition` | **none required**, §3. Optional `bay_charge`, §3 | — |

Not applicable: §1.4 items 9 and 10 — player frame, no new faction.

---

## 6. Tests — `tools/test_vessel.gd`

Model on `tools/test_bulwark.gd`. Note `tools/test_hatchling.gd` already exists
and covers the charge itself; do not duplicate it — test the *Vessel's*
relationship to it.

**Registration**

1. `chassis_vessel.tres` loads; `def.id == &"vessel"`; `def.scene != null`;
   `def.purchasable`.
2. `&"vessel"` is in `catalogue.chassis` ids and in `KillKinds.FRAMES`.
3. `int(def.weapon_slots) == 1` and `String(def.coax_weapon_id) == ""` — one
   mount, no coax, which is what keeps the Walker worth buying.
4. `def.turret == true` and `def.drives == true` and `def.vehicle == true`.
5. `int(def.equipment_slots) == 1` — §0(b). Change the number here and in §2
   together, deliberately.

**The gun can actually be fitted — the §0(a) assertion**

6. `def.takes(catalogue.item(&"machine_gun")) == true`. **This is the one that
   catches the Bulwark bug**, and it fails today. Write it before the fix so
   you watch it go green.
7. `def.takes(catalogue.item(&"hatchling")) == true` — the equipment the whole
   frame exists for.

**The balance constraint — asserted against the Walker directly**

8. `def.base_health < walker.base_health` (260 < 320).
9. `def.base_sensor_range < walker.base_sensor_range` (45 < 60).
10. `def.weapon_slots < walker.weapon_slots` (1 < 2).
11. `def.base_speed <= walker.base_speed`, and separately the *scene's*
    `move_speed` is not greater than `walker.tscn`'s — because `base_speed` is a
    multiplier and the scene owns the real number (§6.9). Load
    `chassis_walker.tres` by path so the two cannot silently converge.

**The scene**

12. `is_in_group("enemies")` **and** `is_in_group(AI.SIGNAL_GROUP)`
    (`test_bulwark.gd:120-127`).
13. `body.get("turret") != null` — else the frame cannot fire while it drives
    (`hull_spoils_aim` reads the node). `weapon_mount != null` and
    `turret.is_ancestor_of(weapon_mount)` — walk the tree, do not compare
    names.
14. A fitted `machine_gun` points **forward**: the mount's global `-Z` within a
    few degrees of the body's `-Z`. `build_vessel.gd:175-178` warns that a
    mount built at −90° instead of +90° fits, elevates, tracks and fires
    directly backwards with nothing complaining.
15. `AllowedMovementOptions == [0, 2, 4]` and `AllowedCombatOptions == [0, 1, 2]`,
    and both are `Array[int]` — contents **and** type, because an untyped array
    saves as `[]` in silence (§6.6) and an empty one is the §6.1 defect.
16. `FactionLivery.pieces` is non-empty; paint a hostile faction and assert
    `Rig/Turret/Eye`'s material is unchanged.

**The doors**

17. `Rig/Bay/DoorL` and `Rig/Bay/DoorR` both exist.
18. After `_ready`, both are **closed**: `abs(door.rotation.z) < 0.01`.
19. Driven to `OPEN`, `DoorL.rotation.z` is within a degree of `+130°` and
    `DoorR.rotation.z` of `-130°` — **signed**, so a mirrored leaf cannot pass.
20. **A release is refused while the doors are shut.** Call
    `order_use_equipment(&"hatchling", pos, false)` from `STOWED` and assert
    `slot.remaining()` is unchanged; then drive the doors open and assert the
    same call consumes one.
21. Out of contact for `close_after`, the doors return to 0.

**The bay**

22. `Rig/Bay/CargoA` and `Rig/Bay/CargoB` exist and are both visible at start.
23. After one release: `CargoA.visible == false`, `CargoB.visible == true`.
    After two: both false.
24. **It cannot release a third.** `slot.remaining() == 0` and a third order
    returns `"none left"` (`enemy.gd:3841`).
25. **A released unit has the Vessel's faction, not a default.**
    `hatchling_payload.gd:55` substitutes `PLAYER` only when the source is
    `NEUTRAL`, so set the Vessel to a non-default faction and assert the
    released body matches it. `VESSEL.md` §7 is right that this needs
    asserting, not writing.
26. If the `bay_charge` variant ships: the released unit's `lifetime` timer is
    **not** 0.0 — §1's `_expire_later` hazard.

---

## 7. Order of work

| step | do | prove |
|---|---|---|
| 0 | **Add `&"vessel"` to `item_machine_gun.tres:37`** | `tools/test_vessel.gd` step 6 goes from red to green. `bash tools/test.sh` whole — this is a shared item file |
| 1 | `chassis_vessel.tres` + `kill_kinds.gd` + catalogue (`ext_resource` **and** array); settle the `base_speed` and `base_sensor_range` double-specification | `bash tools/check.sh --changed` prints PASS; test steps 1-11; the frame appears in the factory and can be bought and refitted |
| 2 | Fix `Allowed*Options` in `vessel.tscn` | test step 15. `bash tools/smoke.sh` — the two `Array[Object]` → `Array[int]` load errors stop |
| 3 | `tools/bake_icons.gd` | the PNGs land. **Report whether they did** (§6.3) |
| 4 | `vessel.gd extends Rover` with `_ready` resolving the four nodes and the doors closed, and nothing else | `bash tools/smoke.sh`; test steps 17, 18, 22. `tools/mockup_shots.gd` for the closed silhouette — nobody has seen it, the scene was built open |
| 5 | The door state machine: `OPENING`/`OPEN`/`CLOSING`, `_committed()` off the Nest's `_fighting()` gate | test steps 19, 21. Watch it in the Lab or a headless mission |
| 6 | The `_spend_equipment` gate and the bay-state derivation | test steps 20, 23, 24 |
| 7 | Buy a `hatchling`, fit it, deploy, confirm the release and the faction | test step 25 |
| 8 | **Settle the clearance question — §8. Do this before the lab plan and before the mission unlock** | `tools/probe_nav_reach.gd` with the new `"vessel"` entry, on every shipping level |
| 9 | A lab plan (`Campaign/lab/plans/vessel_screen.tres`) and a mission `unlocks` entry | `tools/test_ledger.gd:826-831`. The bench says whether it really is weaker than the Walker |
| 10 | Hand to the human | the release timing, `close_after`, and whether two bodies or four is the frame. **None of that can be judged without playing** |

Steps 0-4 are a shippable checkpoint: a registered, buyable, armed carrier with
the doors shut and no release. Steps 5-7 are the frame.

---

## 8. Open questions and risks

### The blocker: the footprint has never been checked against a real level

`VESSEL.md` §8 flags it and it is the one item here that can make the frame
scenery. What I can add is the actual numbers, because the doc did not have them
and they change the shape of the problem:

- **The 3.53 m is the doors-open envelope, and it is geometry only.**
  `build_vessel.gd:110-116` derives it as `1.075 * (1 + sin 40°)` per side at
  `rotation.z = 130°`. Nothing in the engine collides with it or paths against
  it.
- **The collider is 2.00 m wide.** `vessel.tscn`'s `CapsuleShape3D_w4yqh` is
  radius 1.0, height 4.0, laid along Z. That is *narrower* than the `"squad"`
  envelope `probe_nav_reach.gd` already uses (`"squad": [1.13, 3.00, 0.45]`) and
  only 0.15 m wider than the Rover's 0.85.
- **The `NavigationAgent3D` says 1.4** (`vessel.tscn:493-494`), which is 2.8 m
  wide — but per the memory note and `build_drayman.gd:426-431`, **Godot
  enforces no per-agent path clearance**: only the bake does. So the agent
  radius is honesty about the frame, not a constraint on it.

**Three distinct risks, and they need settling separately:**

1. **Physical passage.** A 2.0 m collider on a navmesh baked for a 2.26 m squad
   envelope should pass everywhere the squad does. *Low risk.*
   **How to settle:** add `"vessel": [1.00, 4.00, 0.45]` to
   `probe_nav_reach.gd` `FRAMES` (87-95) and run the coverage sweep on every
   shipping level. That is one list entry and the probe already exists.
2. **Visual clipping with the doors open.** 3.53 m of leaf through a 3 m gate is
   a carrier whose doors go through a wall. *Medium risk, and it is the one
   nobody has looked at.* **How to settle:** `tools/mockup_shots.gd` loads a
   real level and writes a viewport PNG — park a Vessel with the doors open in
   each level's tightest gate and look. Cheap, and it needs no new tooling.
   **Mitigation if it fails:** the commit test in §4 already keeps the doors
   shut except in contact, so the exposure is "it opened next to a wall", not
   "it drove through the map with its doors out". A second mitigation exists and
   should only be reached for if the shots are bad: reduce `DOOR_OPEN` from 130°
   to ~110°, which costs half a metre of width for a read that is still
   unmistakable from above.
3. **Height.** The collider is 4.0 m tall and `NavigationAgent3D.height = 3.2`,
   against the squad envelope's 3.00. *Unknown.* The probe's third column is
   climb, not clearance, so **the probe does not answer this one** — flagged as
   a gap rather than assumed away.

**Recommendation: do not write the mission unlock until step 8 passes.** A
supply-3 frame the player cannot get to the places a release matters is the
failure `VESSEL.md` §1 named when it sank concept C, and it would be the third
cut in this batch.

### The rest

4. **Two bodies or four.** §1: as specified the frame produces two single
   hoppers that live 25 seconds, which is not worth 340 and 3 supply. The
   `bay_charge` variant (three `.tscn` files, no code) makes it four persistent
   bodies in two waves. **Human call, and it is the frame's value proposition.**
5. **`equipment_slots = 1`, not the doc's 2.** §0(b). One hatchling slot is
   already two releases. Two slots is four, which may be what the doc meant;
   the number has to be chosen once, in the definition, knowing that.
6. **Released drones do not join the squad**, and should not in v1 — §1, with
   `enemy_nest.gd:29-32` as the argument. `VESSEL.md` §6.3 recommends the
   opposite; it was written before the payload was read.
7. **`base_speed` and `base_sensor_range` are each specified twice** in
   different units or with different values (§2). Pick one each.
8. **The closed silhouette has never been seen.** `build_vessel.gd:104-105`
   says the leaves were built *at* 130° "because the brief asks for open". Step
   4 is the first time anyone will look at this frame shut, and the frame's
   whole proposition is that open and closed are two readable silhouettes. If
   the closed one is a featureless box, that is worth knowing before the
   behaviour is written.
9. **Whether the bay reloads at base automatically or is a purchased
   consumable.** `VESSEL.md` §8's third bullet. Answered by the existing
   machinery, not by a design decision: `SoldierRecord` writes the survivor's
   remaining charges back (`soldier_record.gd:433`) and restores them from
   `equipment_max` at base (`soldier_record.gd:215`), so **it reloads for free,
   like every other piece of equipment in the game.** Making it a consumable
   would be special-casing this one item against the whole system. Recommend
   free.
10. **`lifetime = 0.0` destroys a released unit instantly**
    (`hatchling_payload.gd:109-113`, no zero guard). Not a Vessel bug, but it
    is directly in this frame's path. Worth a one-line guard in that file by
    whoever touches it next.
