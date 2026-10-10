# PICKET — integration brief

Supply 2 · legged anti-air · model built, **nothing else exists**

Companion to `docs/frames/PICKET.md` (design) and `docs/briefs/FRAME_ANATOMY.md`
(the map). This document is the build order. Where it disagrees with the design
doc it says so and says why — and on this frame it disagrees about the weapon,
which is the centre of the brief.

**What exists today:** `Character/characters/ai/picket.tscn` (root script
`walker.gd`, in `groups=["enemies"]`) and `tools/build_picket.gd`, the one-shot
generator. **Do not re-run the generator.** Everything this brief asks for in
the scene is a hand edit to `picket.tscn`.

**Nothing else.** No `ChassisDefinition`, no weapon, no catalogue entry, no
`KillKinds.FRAMES` key, no icons, no test, no mission unlock.

> **Verification note.** Three Godot processes were running in this checkout
> while this brief was written, so per `FRAME_ANATOMY.md` §7 I ran **nothing**
> through Godot. Every claim is read off source and off the `.tscn` by hand with
> a `file:line`. The numbers that need *measuring* are named as such in §7.

---

## 1. What "successful" means for this frame — and the honest problem

Success would be: the player sees helicopters on the mission briefing, spends 2
supply on a Picket instead of a second Rover, and the air threat stops being
something that happens to them. Concretely — a frame that **acquires an aerial
contact at 75 m instead of 45**, engages it for the whole of its approach rather
than the last two seconds, and visibly points a launcher at it so the counter is
legible.

**Now the honest part, and it is not comfortable.**

`PICKET.md` §2 already concedes the ground this frame was supposed to stand on:
there is no mechanism that denies a high shot, and a rifleman will shoot straight
up. That is verified — the vision cone's FOV test is **flat** (`enemy.gd:960-961`
sets `forward.y = 0.0`, and 985-986 zeroes the candidate offset's `y` before
measuring the angle, so anything overhead is always "in cone"), the facing is
flat (`enemy.gd:2831`), the fire gate is flat (`walker.gd:243`, `to.y = 0.0`),
and the damage ray is full 3D with no mask (`ai_weapon.gd:441`). Everything
already engages everything overhead.

So the frame's whole claim rests on §6's three things that "are all stats, not
code". **Two of the three are wrong, and I can show it:**

1. **"`flak`'s shape… 18 mrad spread… shreds a 90-hull Kite and embarrasses
   itself against a 400-hull Bulwark; the weapon discriminates by target size."**
   **It discriminates the other way.** Nothing in `AIWeapon` knows a target's
   size. The only size-sensitive mechanism in the chain is spread:
   `get_inaccurate_target` offsets the aim point by `mrad × dist / 1000` metres
   (`enemy.gd:5232-5241`) and `check_damage` casts one ray per pellet at
   whatever collider is there (`ai_weapon.gd:396-429`). At 60 m, 18 mrad is
   ±1.08 m of lateral scatter — **larger than a drone and smaller than a
   Bulwark**. A wide-spread gun therefore misses *small* targets and connects
   with *large* ones. The design doc's mechanism is inverted.
2. **"Sensor range 75… a frame that sees them at 75 m engages them closer to its
   own spread floor than a frame that sees them at 45."** The conclusion is
   right and the reason is not. Spread is proportional to range
   (`enemy.gd:5235`), so seeing further means engaging *further* and therefore
   with *more* spread. `aim_floor` is reached by **settling**, not by proximity
   (`get_aim_spread_multiplier`, `enemy.gd:5246-5250`). What a 75 m sensor
   actually buys is that the contact exists at all: `sight_range()` gates
   acquisition outright (`enemy.gd:945, 980-984`) and `acquire_far_penalty = 4.0`
   (`picket.tscn:263`) means a contact at the edge of reach takes 1.4 s to
   call — so the Picket starts shooting seconds earlier and gets more of the
   approach. That is a real edge. Say it that way.
3. **"It is the only frame whose barrel is modelled to point there."** True, and
   it is cosmetic, and the doc says so.

**Verdict.** The gap is thin, and two frames in this batch have been cut for
exactly that. What is left after the corrections is genuinely three things —
**reach (95 m), acquisition (75 m sensor, earliest engagement in the game), and
the only silhouette that reads as an answer to being bombed** — plus a weapon
that, built the way §3 recommends rather than the way the design doc specifies,
is the first gun in the game tuned to hit something small and fast. That is
enough to build, but it is not enough to *market*, and the frame will feel like
a counter-pick only once the air game is a designed matchup. **That change is
the elevation gate logged in `docs/briefs/NEW_FRAMES.md` §7, it is a
combat-model decision, and it must not be smuggled in here** — it was written
once, reverted, and `enemy.gd` is byte-identical with HEAD. If the human reads
§1 and decides the frame is not worth it without the gate, that is a reasonable
conclusion and this brief does not argue against it.

---

## 2. The `ChassisDefinition`

New file: **`Campaign/chassis/chassis_picket.tres`**, script
`res://Campaign/chassis_definition.gd`. Copy `chassis_walker.tres` as the
skeleton — same `vehicle = true` / `drives = false` shape.

| field | value | why / citation |
|---|---|---|
| `id` | `&"picket"` | **PERMANENT.** `FRAME_ANATOMY.md` §2.5 — written to the save as `chassis_id` (`soldier_record.gd:486`), `kills_by_kind` keys (483) and armoury stock (`campaign_state.gd:1234`); `CampaignState.RENAMED` is applied to kill tallies only. |
| `display_name` | `"Picket"` | first word becomes the callsign (`campaign_state.gd:769-770`). No trailing `" CHASSIS"` (`kill_kinds.gd:81-84`). |
| `description` | see below | |
| `icon` | leave **null** | inspector texture beats the baked PNG (`icons.gd:43-44`). |
| `scene` | `picket.tscn` | **PERMANENT PATH** (`soldier_record.gd:472`, fallback at `squad_spawner.gd:269-272`). |
| `cost` | `210` | design doc. Above Rover 150 and Spotter 180. Retunable; price with `audit_economy.gd`. |
| `purchasable` | `true` | or `recruit()` refuses (`campaign_state.gd:740-741`). |
| `supply` | `2` | and it is the first **legged** frame at supply 2 — everything else on legs is 3. |
| `starting_weapon_id` | `&"flak"` | §3. Written into `weapon_ids[0]` without consulting `takes()` (`campaign_state.gd:750-751`), which is exactly the hole that made the Bulwark armable once — see §3.4. |
| `coax_weapon_id` | `&""` | **mandatory.** `picket.tscn:171`'s `node_paths` list has **no `coax_mount`**, so `equip_coax_scene` would warn and drop, once per body per mission (`enemy.gd:77-81`, trap 6.12). |
| `base_health` | **`140`** | design doc. Absolute for a player frame (`soldier_record.gd:238`). **`picket.tscn:209-210` says 170** and the generator's comment at `build_picket.gd:551-555` claims to be following §3 while writing a different number. Unexplained divergence. Recommendation: **140 on the definition and edit the scene to 140**, so a squad-spawned, a hand-placed and a lab Picket all agree. Flag it either way. |
| `base_speed` | **`0.9`** | design doc, and **correct as written — unlike the Lance's.** `base_speed` is a multiplier (`soldier_record.gd:254` → `squad_spawner.gd:349`). `picket.tscn:212`'s `move_speed = 4.5` is `enemy.gd:115`'s untouched default, **not** a pre-multiplied figure — `build_picket.gd` never sets `move_speed` (it sets health, `soldier_name`, `activation_distance` and the collider flag, `build_picket.gd:554-563`). So 0.9 × 4.5 = **4.05 m/s**, which is what the doc asks for and slightly under the Walker's 4.16. **Do not copy the Lance's handling here; `build_lance.gd:530-536` pre-applied its multiplier and this generator did not.** |
| `base_accuracy` | `1.0` | multiplier (`squad_spawner.gd:348`). `picket.tscn:230` already has `accuracy_skill = 0.75`. |
| `base_sensor_range` | `75.0` | design doc, and **this is the frame's real mechanism** (§1). Absolute (`squad_spawner.gd:350`). The scene says 45 (`picket.tscn:259`, the `enemy.gd:527` default) — **edit the scene to 75 as well**, because for a squad-spawned body the definition wins but I could not confirm that `lab.gd` or a hand-placed body applies the definition's stats at all. Making the two agree removes the question. |
| `weapon_slots` | `1` | one mount (`Rig/Turret/GunPivot/PodCant/WeaponMount`, `picket.tscn:201`). Capped at 2 by `_fit_loadout` anyway (`squad_spawner.gd:300-301`). |
| `built_in` | `"CLAWS"` | matches Walker, Bulwark and Rover. **Note it is a blank icon** — `Icons.built_in` does `path("items", "claws")` (`icons.gd:63-66`) and there is no `icons/items/claws_*.png`, nor a `claws` key in `icon_art.gd:129-135`. Pre-existing on four shipped frames; the Picket does not introduce it. |
| `weapon_replaces_built_in` | `false` | |
| `turret` | **`true`** | the design doc's value and the right one: `picket.tscn:186` wires `turret = NodePath("Rig/Turret")`, and the node property being non-null is what excuses `hull_spoils_aim` (`enemy.gd:2895`) so a walking Picket still settles its aim. **But `ChassisDefinition.turret` is a separate thing** — it is the whitelist gate at `chassis_definition.gd:91`. Setting it true commits you to §3.4. |
| `vehicle` | `true` | musters with ARMOR (`campaign_state.gd:468-496`). Same as the Walker and the Bulwark, both of which walk. |
| `drives` | `false` | legs, so it **can** take `fits_vehicles = false` kit — Nanite Reboot included (`chassis_definition.gd:89-90`). `walker.gd:7-12` records this as the Walker's real edge over a Rover; it is the Picket's too, and it is worth one line of the description. |
| `equipment_slots` | `0` | design doc. |
| `module_slots` | `2` | design doc. One fewer than the Walker's 3. |
| `musters_at_base` | `true` | design doc; only read by `campaign.gd:910-917`. |
| `required_rank` | **`0`**, not the doc's 2 | **the field does nothing in the factory.** `recruit()` never reads it (`campaign_state.gd:739-764`); only `set_chassis` does (1165); `factory_page.gd` never reads it at all (`FRAME_ANATOMY.md` §6.4 — the Bulwark's `required_rank = 3` is inert and a rank-0 robot is born in it). The Picket **is** meant to be gated, so the gate has to be a mission `unlocks` entry — §5 item 14. Leaving 2 here is harmless but it is a lie on the card and someone will trust it. |

Suggested `description`:

> Six tubes on a trunnion and a sensor dish, on legs. Built to be positioned,
> not driven: it sees further than anything that is not a drone and it reaches
> past anything that is not a cannon. On legs, so it takes the kit a Rover
> cannot. Thin, and bad at its job unless the enemy brought aircraft.

**Permanent once written:** `id`, `scene` path. **Safe to retune:** every stat,
slot count, `cost`, `supply`, `display_name`, `description`, `built_in`.

---

## 3. The weapon — `flak`

### 3.1 Subclass, or `.tres` plus an existing scene? **No subclass.**

Answered against `FRAME_ANATOMY.md` §3.4's rule — *a subclass if and only if the
round is not a hitscan ray* — and then against something the rule does not
cover, which decides the whole frame:

> **There is no target leading anywhere in this project.** I searched for it.
> `AIWeapon.flight_time()` exists (`ai_weapon.gd:720-721`) and is used in
> exactly two places: to hold a PATIENT weapon's target long enough for the
> round to arrive (`ai_weapon.gd:785`) and to set a grenade's fuse
> (`ai_weapon_grenade_launcher.gd:223-224`). **Nothing offsets the aim point by
> the target's velocity.** `AIWeaponRecoilless._aim` fires straight at
> `weapon_target` with spread applied and no lead
> (`ai_weapon_recoilless.gd:94-106`).

That settles it. A projectile weapon — the launcher the model wants — would fire
34 m/s rounds at where an orbiting Spotter *was* (`orbit_radius = 14.0`,
`spotter_drone.gd:72`) and miss essentially every time. **Against a moving
aerial target, hitscan is the only thing in this engine that connects.** So:

**`flak` is a `.tres` plus a new scene on the plain `ai_weapon.gd`. No new
script, and `weapon_type = 1` (HITSCAN).**

**Closest template, named:** `Character/weapon/ai-wep_heavy_mg.tscn` — a
fast-cycling belt gun with a long magazine, a long reload and its own burst
rhythm. 36 lines. Copy it and change the numbers.
(`ai-wep_shotgun.tscn` is the template for the pellet fields if you keep them;
see 3.3 for why you should not.)

### 3.2 The `ItemDefinition`

New file: **`Campaign/items/item_flak.tres`**, script
`res://Campaign/item_definition.gd`. Copy `item_heavy_mg.tres`.

| field | value | why |
|---|---|---|
| `id` | `&"flak"` | an item id is a save key (fitted `weapon_ids`, unlock lists, allocations). Permanent. |
| `display_name` | `"Flak Battery"` | |
| `short_name` | `"FLAK"` | fits a 58 px slot; `short_label()` would otherwise derive "Battery". |
| `description` | "Six tubes on a ripple…" | |
| `kind` | `0` (WEAPON) | |
| `cost` | `180` | between `machine_gun` 150 and `heavy_mg` 210. Price with `audit_economy.gd`. |
| `ai_scene` | `res://Character/weapon/ai-wep_flak.tscn` | §3.3 |
| `player_scene` | **null** | no viewmodel wanted. |
| `usable_by_player` | `false` | |
| `usable_by_ai` | `true` | `fits_ai()` needs this **and** a non-null `ai_scene` (`item_definition.gd:145-150`). |
| `fits_vehicles` | `true` | the Picket is `drives = false` so this is not strictly load-bearing, but leave it true or the gun becomes unfittable the day someone puts a flak battery on a track. |
| `weapon_damage` | `0` | leaves the scene's value (`item_definition.gd:64-65`). Ballistics live in one place. |
| `ammo_type` | `&"flak"` or reuse `&"20mm"` | a new pool is a decision about the ammo economy. `tools/test_ammo.gd` exists and I did not read it. **Open — §8.** |
| `in_shop` | `true` | **required** if `flak` appears in any mission's `unlocks`: `test_ledger.gd:818-831` fails the build for an unlock the armoury will not sell. |
| `one_per_robot` | `false` | |
| `requires_chassis` | `Array[StringName]([&"picket"])` | shop gating on *owning the frame*, the mechanism `autocannon` and `heavy_mg` use (`item_definition.gd:122-133`). Different from the whitelist, which is about fitting. |
| `chassis_whitelist` | `Array[StringName]([&"picket"])` | **mandatory — see 3.4.** |
| everything else | defaults | |

### 3.3 The `AIWeapon` scene

New file: **`Character/weapon/ai-wep_flak.tscn`**, root `Node3D` with
`res://Character/weapon/ai_weapon.gd`, `node_paths` for `muzzle_flash` /
`muzzle_origin` / `shot_audio`, and a `Model` / `Muzzle` / `MuzzleFlash` /
`Shot` quartet off the heavy MG. No root transform; the muzzle sits at local
**+X**, which is why `picket.tscn:461`'s `WeaponMount` is yawed **+PI/2** —
basis `(-4.37e-08, 0, 1 / 0, 1, 0 / -1, 0, -4.37e-08)`, which is what
`tools/check_frame.gd` asserts and what the Bulwark fired backwards for want of.

| export | value | why — and where this leaves the design doc |
|---|---|---|
| `weapon_type` | `1` (HITSCAN) | `Managers/enums.gd:14`, append-only. |
| `fire_cooldown` | `0.18` | design doc. Fast cycle is half the answer to a small fast target. |
| `base_damage` | `14` | design doc's number, **but understand what it means.** `ai_weapon.gd:386-406`: "`base_damage` stays the damage of a WHOLE shell; each pellet carries its share." With `pellets = 3` the rounds get 6/4/4, not 14 each (`_one_round`'s `share` arithmetic, `ai_weapon.gd:412-416, 458-463`). `PICKET.md` §4's "14 damage each" is wrong by 3×. With `pellets = 1` (below) 14 is 14. |
| `min_damage` | **`10`** | **the doc omits it and the default is 18** (`ai_weapon.gd:16`). `calculate_damage` lerps `base_damage → min_damage` (`ai_weapon.gd:246-252`), so left at 18 against `base_damage = 14` the gun gets **stronger with range**. That is not a tuning quibble; it is backwards. |
| `damage_falloff_start` | **`60.0`** | **also omitted; the default is 20.0.** A 95 m anti-air gun that starts losing damage at 20 m is not an anti-air gun. |
| `max_effective_range` | `95.0` | design doc, and **this is one of the frame's three real edges** (§1). Also what the whole AI reads as "my reach" (`Enemy._max_range`, `enemy.gd:3022`), so it drives ADVANCE/FIRE scoring too. |
| `min_effective_range` | `0.0` | design doc. A battery must be able to shoot something on top of it (`enemy.gd:2920-2921`). |
| `ai_spread_mrad` | **`6.0`**, not the doc's 18 | **THE CENTRAL CORRECTION.** See §1.1: wide spread misses *small* targets. At 95 m, 18 mrad is ±1.71 m of scatter against a Spotter whose collider is ~0.5 m — mostly air. 6 mrad gives ±0.57 m, which actually brackets a drone. And it is still divided by `accuracy_skill × signal_integrity` and multiplied by the settle factor (`enemy.gd:5231-5234`), so 6 is a floor and the real figure under fire is far looser. **If the human wants the gun to stay bad against armour, that is what `base_damage` and the magazine are for, not spread.** |
| `pellets` | **`1`**, not the doc's 3 | with `pellet_spread_mrad` unset (the default is 0.0, `ai_weapon.gd:30`), `check_damage` sends all three rays down the *identical* centre line (`ai_weapon.gd:413-415`: `dir = centre` unless `pellet_spread_mrad > 0.0`) — three raycasts' cost for one round's effect, and `base_damage` split three ways for no gain. Either set `pellet_spread_mrad` and accept a shotgun, or drop to one round. **One round is right here**, for the reason above. |
| `magazine_size` | `40` | design doc. 40 × 0.18 s = 7.2 s of fire, then a long reload — which is the honest way to stop the gun being a general-purpose MG. |
| `reload_time` | `4.0` | design doc. |
| `burst_min` / `burst_max` | `8` / `16` | **set these.** 0 defers to the body's `burst_min = 2` / `burst_max = 5` (`picket.tscn:234-235`, `_commit_burst` at `enemy.gd:3959-3971`), which on a 0.18 s gun is a 0.9 s tap. A battery ripples. The heavy MG's 14/26 is a suppression gun; 8/16 is a tracking burst. |
| `suppression_per_shot` | `2.0` | design doc. Low on purpose — `suppress_along` works along the whole flight path (`ai_weapon.gd:480-500`), and a 5.5 rounds-per-second gun with high suppression would pin a map. |
| `near_miss_radius` | `2.5` | default. |
| `tracer_scene` | `res://Character/weapon/tracer.tscn` | **the frame's legibility lives here.** One visible tracer per shot climbing out of six tubes at 5.5/s is what makes the counter read. |
| `tracer_jitter_degrees` | `1.0` | a little, so a ripple looks like a ripple. |
| `friendly_fire` / multiplier | defaults | |

**Model.** `Character/weapon/models/` has nothing like it, and the chassis is
*sized to the weapon*: `build_picket.gd:196-205` keeps `TUBE_R`,
`TUBE_LEN`, `TUBE_COLS`, `TUBE_ROWS` as constants precisely because "a cradle
measured in its own round numbers would stop fitting the weapon the moment
either moved." The generator then hands the weapon builder the exact geometry it
removed (`build_picket.gd:70-76`):

> "the tubes were CSGMesh3D cylinders, axis +Y, turned +90 about X so the bore
> lay along Z, each with a CSGCylinder3D subtraction offset toward local −Y (the
> muzzle) and stopping short of the far end so the breech stayed closed. A solid
> cylinder reads as a rod and six rods read as a gun… Six tubes, three across
> and two high, radius 0.14, length 1.375, spaced 0.322."

Build **`Character/weapon/models/flak_pods_model.tscn`** to those numbers, the
way `autocannon_model.tscn` was built (primitives, commented header, no imported
mesh), re-oriented so the bore runs along the weapon's **+X** like every other
AI weapon model. Then add a `MODEL_OVERRIDES` entry for `&"flak"` in
`icon_art.gd:24-31` — **required**, because `model_in()` only follows imported
`blend/glb/gltf/fbx/dae` (`icon_art.gd:75, 172-177`), so a hand-built `.tscn` is
invisible to `model_for()` without it, and the icon silently falls back to
`FALLBACK_DRAWING` (`icon_art.gd:111`).

Check the fit once it exists: the mount is at cant-local `z +0.0625`
(`picket.tscn:461`), the rails are `RAIL_LEN = 0.78` long (`build_picket.gd:205`) and the pack is 1.375,
so a correctly-built pack sits in the cradle and overhangs it — which is the
read the generator intended. A pack that floats, or that the rails pass through,
means the mount or the model's origin is wrong, not the chassis.

### 3.4 `fits_chassis` / whitelist — the Bulwark's exact mistake, waiting

`takes()` refuses three ways (`chassis_definition.gd:84-91`):
`item.fits_chassis(id)`, `drives and not item.fits_vehicles`, and —
**because the Picket is `turret = true`** — `turret and kind == WEAPON and not
item.chassis_whitelist.has(id)`.

This is trap 6.2 verbatim. The Bulwark sets `turret = true` and issues
`heavy_mg`, whose whitelist is `[&"walker", &"rover"]`; `recruit()` writes the
gun straight into `weapon_ids[0]` (`campaign_state.gd:750-751`) **bypassing
`takes()`**, so the frame deploys armed and `CampaignState.can_fit`
(`campaign_state.gd:1099`) then refuses to ever put a gun back. Armable exactly
once, and nothing warns.

**So: `item_flak.tres` must carry `chassis_whitelist = Array[StringName]([&"picket"])`.**
Non-negotiable, and it is also the mechanism `PICKET.md` §4 correctly identifies
— it keeps `flak` off a Rover for free.

The other half is a design decision the doc leaves open. With
`turret = true` and `flak` whitelisted to it, the Picket can fit **`flak` and
nothing else** — because `autocannon`, `heavy_mg`, `machine_gun`,
`grenade_launcher` and `mortar` all carry whitelists that do not name it, and
everything with an empty whitelist is `fits_vehicles`-irrelevant but still has
to pass the turret rule, which an empty whitelist cannot
(`chassis_definition.gd:91` requires `chassis_whitelist.has(id)`, and
`fits_chassis` returning true for an empty list does **not** satisfy it).

That is probably correct for a specialist — the design doc says "the Picket
cannot be handed an autocannon unless the autocannon lists it. That is the
existing mechanism; no new code," and it is right. **Say in the commit that the
frame ships with one fittable gun on purpose**, so it does not get read as the
bug it looks like.

### 3.5 The upgrade path, logged and not built

The model says *missile pack* and the engine says *hitscan*, and §3.1 resolves
that in the engine's favour for v1. The thing that would make the model true is
small and specific, and it belongs in §8 rather than in this build:

A new `AIWeaponSAM extends AIWeaponRecoilless` overriding **only `_aim`**
(`ai_weapon_recoilless.gd:94`, already a declared seam) to offset the aim point
by the target's velocity × `flight_time(distance)` — both of which already
exist (`ai_weapon.gd:720`, and `CharacterBody3D.velocity` on every target). That
is the "guided projectile" case `FRAME_ANATOMY.md` §3.4 says needs a subclass,
so it is **not** free — but it is perhaps twenty lines, it would give the game
its first leading weapon, and it would make the Picket's launcher fire actual
rockets. **Do not build it under this brief.** It is a weapon-system feature
that happens to suit one frame, which is the same mistake as the reverted
elevation gate.

---

## 4. The behaviour

### 4.1 Does it need its own script? **No. And that is the honest answer.**

`PICKET.md` §5 names `Character/characters/ai/picket.gd`, `extends Walker`, and
§6 says it "changes numbers, not behaviour." **A subclass whose only content is
new `@export` defaults would change nothing**, because of the rule in CLAUDE.md:
*scene values beat script defaults.* `picket.tscn:188-191` already writes all
four turret properties explicitly —

```
188: turret_traverse_degrees = 55.0
189: gun_elevation_degrees = 40.0
190: gun_min_pitch_degrees = -12.0
191: gun_max_pitch_degrees = 35.0
```

— so a `picket.gd` declaring `@export var gun_max_pitch_degrees: float = 85.0`
would be overwritten by line 191 on load. The numbers have to be **edited into
the scene**, and once they are, the script has nothing left to hold.

Walked against `FRAME_ANATOMY.md` §4.2's table, a frame on `walker.gd`
(`walker.gd:2`, `class_name Walker`) already has, with nothing written:

- `_tick_gait` (117) — the legged walk, and `_update_facing` (206) which calls
  `super(delta)` on the way through so the body turns *and* the turret
  traverses, the split the Rover deliberately does not do;
- `_turret_forward` (229) and `_weapon_on_target` (239) — the fire cone off the
  turret's bearing, which is what makes flanking the counter;
- `takes_cover() = false` (251) — "it parks, it does not take cover", which is
  what `Squad` splits its members on (`squad.gd:554-555, 1540-1541`);
- the gun elevation assignment (`walker.gd:220-226`), the whole reason the 54°
  cant lives on `PodCant` — see 4.3.

`bulwark.gd` is the only frame that needed a script on top of this, and
`FRAME_ANATOMY.md` §5 is explicit about why: its gun is a metre out on an arm
with its own joint, so inheriting `_turret_forward` meant a frame that refused
to fire whenever its arm bore and its torso did not. **The Picket's gun is on
its turret, on the axis `walker.gd` expects.** Nothing is out of place.

**So: no `picket.gd`. The frame is `walker.gd` plus edited scene values plus a
weapon.** If a later pass finds a behaviour the frame genuinely needs — a
preference for aerial targets, say, which would be a `_score_combat_option`
override or a `Targeting` mode on the weapon — it earns a script then.

### 4.2 The scene edits that replace the script

All by hand in `picket.tscn`. Each one is a number `PICKET.md` §6 attributes to
a script that is not going to exist.

| line | from | to | why |
|---|---|---|---|
| 188 | `turret_traverse_degrees = 55.0` | **`38.0`** | §6 wants "a slow traverse so flanking it remains the counter". 55 is `walker.gd:65`'s default written out, so the scene currently says *nothing*. The Bulwark's 42 (`bulwark.tscn:160`) is the precedent for a frame that is meant to be flanked; 38 puts the Picket just under it, which is what a thing that is pointed at the sky should be. **A feel number — the human's.** |
| 191 | `gun_max_pitch_degrees = 35.0` | **`85.0`** | §6 wants "near vertical so the barrel visibly tracks a target overhead". 35 is the Walker's default. **But read 4.3 before writing this** — the effective range is not what it looks like. |
| 190 | `gun_min_pitch_degrees = -12.0` | **decision — 4.3** | |
| 189 | `gun_elevation_degrees = 40.0` | **`70.0`** | degrees per second of elevation. At 40 °/s the barrel needs over a second to cross the band it now has; a battery tracking a mover has to be quicker than its own traverse. |
| 259 | `sensor_range = 45.0` | **`75.0`** | so a hand-placed or lab Picket matches the definition (§2). |
| 209-210 | `health = 170` / `max_health = 170` | **`140`** | so all three spawn paths agree (§2). |
| 212 | `move_speed = 4.5` | leave | `base_speed = 0.9` on the definition makes it 4.05 for a squad body. Changing it here **and** keeping 0.9 there would double-count it — the Lance's bug. Pick one place; the definition is the right one for a player frame. |
| 270-271 | `Array[ExtResource("2_grdgg")]([])` | §4.4 | |

### 4.3 The thing nobody has noticed yet: the launcher cannot point at the ground

`picket.tscn:423` puts `PodCant` under `GunPivot` with basis
`(1,0,0 / 0, 0.587785, −0.809017 / 0, 0.809017, 0.587785)` — a **+54°** rotation
about +X, which maps −Z to `(0, sin 54, −cos 54)`, i.e. **muzzle up**. The
`WeaponMount` is a child of `PodCant` (`picket.tscn:461`), so the fitted weapon
inherits the cant.

`walker.gd:220-226` then **assigns** `gun_pivot.rotation.x` every frame, clamped
to `gun_min_pitch_degrees … gun_max_pitch_degrees`. The cant is *below* that
hinge, so the two add:

> **effective muzzle elevation = 54° + clamp(want, min, max)**

With the current `−12 … +35` that is **42° to 89°**. The Picket's launcher
**cannot be made to point at a ground target**, at any range, ever. It will
visibly aim over the heads of anything it is shooting at on the floor — while
still hitting it, because `check_damage` casts from `muzzle_origin` straight at
`weapon_target` regardless of how the model points (`ai_weapon.gd:398-399`).

This is almost certainly *intended* as a silhouette — the concept is called
"launcher-led" and `build_picket.gd:103-108` goes out of its way to get the
cant's sign right "on the one frame in the roster whose entire reason to exist
is shooting upward". But it is a decision nobody has stated, and it changes what
the two pitch numbers mean. Three options, and **this is the human's call**:

- **Keep it skyward.** `gun_min_pitch_degrees = -12`, `gun_max_pitch_degrees = 35`
  → 42–89°. Simple, always reads as anti-air, looks wrong against infantry.
- **Let it come down.** `gun_min_pitch_degrees = -60` → −6° to 89° (with max 35)
  or −6° to 139° (with max 85, which is nonsense — see below). The pack then
  depresses onto ground targets and still elevates, at the cost of the resting
  silhouette, since `want_pitch` is 0 outside combat (`walker.gd:221`) and the
  pack would sit at its 54° rest anyway. **This is my recommendation**:
  `gun_min_pitch_degrees = -60.0`, `gun_max_pitch_degrees = 35.0`, giving −6°
  to 89° of real elevation off one pair of numbers.
- **Re-home the cant.** Move the 54° onto the mount or the weapon model rather
  than onto `PodCant`, so `gun_pivot` is the only cant. More honest, and it
  undoes the thing `build_picket.gd:93-100` built deliberately (and the Bulwark's
  forward-broken arm is what happens when a rest pose goes on the pivot). **Not
  recommended.**

**Do not write `gun_max_pitch_degrees = 85.0` without picking one of the above.**
85 + 54 = 139°, which is past vertical and points the pack backwards over the
frame's own hull.

### 4.4 `AllowedMovementOptions` and `AllowedCombatOptions` — values

**`picket.tscn:270-271` currently reads**

```
AllowedMovementOptions = Array[ExtResource("2_grdgg")]([])
AllowedCombatOptions = Array[ExtResource("2_grdgg")]([])
```

— and `2_grdgg` is `res://Character/characters/ai/equipment/ai_equipment_slot.gd`
(`picket.tscn:4`). The generator typed both arrays as `Array[AIEquipmentSlot]`,
which is where the `Cannot assign contents of "Array[Object]" to "Array[int]"`
pair on load comes from, and both are empty besides.

`FRAME_ANATOMY.md` §6.1 has the full account. The short version:
`roll_combat_action` returns at `enemy.gd:3053-3054` on an empty combat array,
so `perform_action` (3927) is never reached from the combat timer — the frame
never chooses MOVE, `_commit_burst` (3959) never runs so `_burst_left` stays 0
and the gun can only fire through the full settle gate
(`enemy.gd:2924-2932`), and `_enter_aim_stance` (3953) never runs so it never
stops to settle. On a 0.18 s gun whose whole point is a ripple, "fires slowly in
single shots" is the worst possible failure and it reads as a feel problem.

Set, by hand:

```
AllowedMovementOptions = Array[int]([0, 1])
AllowedCombatOptions = Array[int]([0, 1, 2])
```

**These are `soldier_rifle.tscn:70-71` verbatim** — with
`vehicle_rover.tscn:165-166` the only two correct sets in the game — and the
Picket is the right frame to copy them, because `walker.gd` movement **is**
ordinary `Soldier` movement: it walks the navmesh like infantry and deliberately
does not use the Rover's bicycle model (`walker.gd:19-22`).

- `MovementOptions` is `{ADVANCE=0, REPOSITION=1, FALLBACK=2, LEAP=3, CHASE=4}`
  (`enemy.gd:1091`). **ADVANCE (0)** closes range, weighted by range ratio
  (`enemy.gd:3160-3163`) — a 95 m gun will rarely pick it, which is correct for
  a frame that wants to be positioned. **REPOSITION (1)** is a
  `reposition_distance = 2.0` sidestep (`picket.tscn:216`) to break a firing
  solution — exactly what a 140-hull frame should do, and a legged frame can
  actually step sideways, which is why the Rover excludes it and the Picket does
  not.
- **LEAP (3)** excluded: `leap_towards` is for the Chaser and the Leaper.
- **CHASE (4)** excluded: an anti-air battery does not run things down, and
  `MovementState.CHASING` would walk it off the ground it was placed on.
- **FALLBACK (2)** excluded, and this is the one judgement call in the pair.
  `find_fallback_target` is a `fallback_distance = 1.25` step
  (`picket.tscn:225`) and `_score_movement_option` gives it +1.5 below 40 %
  health (`enemy.gd:3177-3180`), which is tempting on a thin frame — but
  `Soldier` already owns the fire-and-manoeuvre layer
  (`enter_bounding`, `soldier.gd:250`; `bound_when_outranged = true`,
  `picket.tscn:219`) and a 1.25 m shuffle is cosmetic. **Flagged in §8 as
  `[0, 1, 2]` if the human wants it; `[0, 1]` is the conservative copy.**
- `CombatOptions` is `{MOVE=0, AIM=1, FIRE=2}` (`enemy.gd:1092`). All three.
  `AIM` stops the frame and lets accuracy build (`_enter_aim_stance`, 3953) and
  on a gun whose spread is the whole question that matters more here than
  anywhere; `FIRE` commits the ripple; `MOVE` defers to `_pick_movement_option`.

**Typed-array form matters.** `Array[int]([0, 1])`, not `[0, 1]` and not
`Array[ExtResource(...)]([])`: a typed array handed an untyped one packs as `[]`
in silence (`FRAME_ANATOMY.md` §6.6, `test_bulwark.gd:190-197`). Note that
`tools/check_frame.gd` does **not** check these arrays — read them back yourself
after the edit.

---

## 5. Registration — `FRAME_ANATOMY.md` §1, walked

**S** = fails silently. **H** = hard error.

| # | item | Picket needs | status |
|---|---|---|---|
| 1 | `Campaign/chassis/chassis_picket.tres` | **yes** — §2 | mandatory |
| 2 | root script resolves to `Soldier` or subclass | **already true** — `walker.gd:1`, `extends Soldier`. `_CsgBake.make(frame.scene) as Soldier` (`enemy_force_spawner.gd:265`, `squad_spawner.gd:273`) | **H** at spawn if broken |
| 3 | `groups=["enemies"]` persistent | **already true** — `picket.tscn:171` | **S** |
| 4 | `KillKinds.FRAMES` key | **yes** — `&"picket": "res://Campaign/chassis/chassis_picket.tres"` appended to `kill_kinds.gd:14-37` | **S**: `frame_of()` → null (`kill_kinds.gd:73-77`), debrief shows a raw id with no icon (`debrief_screen.gd:685-692`), roster glyph blank (`hud_glyphs.gd:64-67`), `bake_icons.gd:120-129` bakes nothing |
| 5 | non-empty `Allowed*Options` | **yes** — §4.4. Currently empty **and mistyped** | **S**, biggest live defect |
| 6 | `test_item_catalogue.tres` — `chassis` array + `[ext_resource]` | **yes.** Append the ext_resource and add it to `chassis = Array[...]` (currently line 48) | **S**: `buildable_frames()` walks `catalogue.chassis` only (`squad_manager_ui.gd:440-453`) so the frame is never offered; `recompute_stats` warns and falls back to class defaults (`soldier_record.gd:229-236`); `supply_of` returns 1 (`campaign_state.gd:315-317`) — i.e. a Picket would cost **one** seat, not two |
| 6b | `test_item_catalogue.tres` — **`items` array**, for `flak` | **yes, and `FRAME_ANATOMY.md` §1.3 does not list it.** `_fit_loadout` resolves the gun via `cat.item(id_value)` and `continue`s on null (`squad_spawner.gd:304-306`), so a Picket recruited with `starting_weapon_id = &"flak"` and no catalogue item **deploys unarmed, silently.** Also required for the §5-14 unlock to pass `test_ledger.gd:818-831` | **S** — §8 |
| 7 | `purchasable = true` | **yes** | `recruit()` refuses outright (`campaign_state.gd:740-741`) |
| 8 | `icons/chassis/picket_{s,m,l}.png` + `icons/items/flak_{s,m,l}.png` | **yes**, via `tools/bake_icons.gd` once 4, 6 and 6b are in, plus the `MODEL_OVERRIDES` entry from §3.3 | **S**: `Icons.chassis` → null (`icons.gd:45`) and the card shows a name alone. **`icons/chassis/` holds no `bulwark_*.png` at all** — verified by listing — so the most recent frame in the game has had a blank card since it was built. Nothing asserts this (`FRAME_ANATOMY.md` §8.3). **List the directory and say in your report whether the PNGs landed.** |
| 9 | a mission `EnemySquadSpec.roster` entry | **no.** Player frame. A hostile Picket would be interesting and is out of scope | — |
| 10 | `Enums.Factions` / `are_hostile` | **no.** Nothing new | — |
| 11 | `KillKinds.SCENES` | **no.** Basename `picket` matches id `picket`, so `kind_of` resolves via `SCENES.get(base, StringName(base))` (`kill_kinds.gd:70`). Same reason the Bulwark has no entry | — |
| 12 | `EnemyLoadouts.TABLES` | **no.** `roll_for` returns `{}` for an unlisted frame (`enemy_loadouts.gd:208-210`), and with one fittable gun there is no pool. Adding a key commits you to `test_enemy_loadouts.gd:91-124` asserting every entry is **legal** — and `enemy_loadouts.gd:109-113` records the Bulwark hitting exactly that wall | — |
| 13 | `Campaign/cosmetics.gd` | **no.** `for_frame` returns `[NONE]` and the cycle control still works (`cosmetics.gd:84-90`) | — |
| 14 | a mission `unlocks` entry | **YES — this is the frame's real gate**, since `required_rank` is inert (§2). Add `&"picket"` and `&"flak"` to **`mission_coast_1_road.tres:491`**, which already unlocks `optics`, `mortar`, `grenade_launcher`, `spotter`, `smoke` — and is the **first mission in `Env/world.tscn:93`'s order that fields a helicopter** (`chassis_helicopter` appears in `coast_1`, `pitt_1`, `mutaha_2`, `georgetown_1`, `polaris_1`, `causeway_1`, `salient_1`; `basin_1` fields only a Spotter). So the counter arrives the mission after the player first meets the thing it counters, which is the right shape. Alternative: `mission_pitt_1_rivers.tres:531`, one slot later, which already unlocks the Walker and would group the two legged frames. **Human's pick.** `locked_by()` only gates what a mission names (`campaign.gd:1068-1082`, `factory_page.gd:217-223`) |
| 15 | `Campaign/lab/plans/*.tres` | **strongly recommended** — this frame's whole value is a claim about a matchup, and `bulwark_screen.tres` is the format. §7 step 6 |
| 16 | `tools/test_picket.gd` | **yes** — §6. Free to wire: `tools/test.sh` runs every `tools/test_*.gd`, and **the name is not taken** (unlike the Lance's) |
| 17 | `probe_nav_reach.gd` `FRAMES` | **optional, do it.** Append `"picket": [0.80, 3.00, 0.45]` to `tools/probe_nav_reach.gd:87-95`. Radius and height are the collider exactly (`picket.tscn:17-19`, `CapsuleShape3D` r 0.8 h 3.0), climb copied from `"walker"`. **Caveat worth stating: the feet reach x ±0.975** (`build_picket.gd:148`, `364`), so 0.80 is the hull radius and not the frame's true half-width — the same understatement `probe_nav_reach.gd:80-84` warns about for the Bulwark's shield. Measure with `tools/probe_chassis_size.gd` before trusting it |
| 18 | a new `ItemDefinition` + `AIWeapon` scene + a model | **yes** — §3 |

Not needed (`FRAME_ANATOMY.md` §1.6): CSG baking reads the directory
(`csg_bake.gd:177-189`); the `"signal"` group is joined in `AI._ready`
(`ai.gd:86-88`); team assignment is `vehicle = true` alone
(`campaign_state.gd:468-496`); `AIManager` registration belongs to the spawner.

---

## 6. Tests — `tools/test_picket.gd`

Name is free. Model on `tools/test_bulwark.gd` (47 checks) — copy `_ok` (52-57),
`_spawn` (60-66) and `_test_the_chassis_is_registered` (70-90), which is §5 as a
test.

**Registration**
- `chassis_picket.tres` loads; `id == &"picket"`; `scene != null`.
- `supply == 2` — **assert it**, because `supply_of` returns 1 for an unknown
  frame (`campaign_state.gd:315-317`) and a missing catalogue entry is therefore
  invisible except as a cheap Picket.
- `weapon_slots == 1`; `coax_weapon_id == &""` — the frame has no `coax_mount`
  and a coax would warn per body per mission.
- `turret == true` **and** `drives == false` — the pair that defines it: a
  whitelisted turret on legs.
- `base_health == 140` **and** the scene's `health == 140` — the two agreeing is
  the assertion, because they disagree today (§2).
- `base_sensor_range == 75.0` **and** the scene's `sensor_range == 75.0`.
- `base_speed * scene_move_speed` is ≈ 4.05 — asserted as a **product**, so the
  Lance's double-multiplication cannot be imported here.
- `test_item_catalogue.tres`'s `chassis` ids contain `"picket"` and its `items`
  ids contain `"flak"`. Hard-code the path the way `test_bulwark.gd:86` does.
- `KillKinds.FRAMES.has(&"picket")` and `frame_of(&"picket") != null`.
- the mission named in §5-14 has `&"picket"` in its `unlocks`, **and** the
  catalogue says `flak.in_shop` — the pair `test_ledger.gd:818-831` checks
  globally, pinned here so a Picket-specific regression names itself.

**The frame**
- in `"enemies"` **and** in `AI.SIGNAL_GROUP` (`test_bulwark.gd:120-127`).
- every node-path export resolves non-null: `rig`, `hip_left`, `knee_left`,
  `hip_right`, `knee_right`, `foot_left`, `foot_right`, `turret`, `gun_pivot`,
  `nav_agent`, `weapon_mount`, `bark`, `detection`.
- `visible_pieces`, `particle_effects_die`, `particle_effects_hit` and
  `FactionLivery.pieces` are all **populated** (`test_bulwark.gd:185-210` is the
  comment to copy with it).
- `Eye` keeps its own `StandardMaterial3D` and is **not** in
  `FactionLivery.pieces`.
- `AllowedCombatOptions == [0, 1, 2]`, `AllowedMovementOptions == [0, 1]`, **and
  `get_typed_builtin() == TYPE_INT` on both** — the current value is an empty
  `Array[AIEquipmentSlot]`, so the type is as much the bug as the emptiness.
- `turret_traverse_degrees <= 42.0` — a bound, not an equality, so retuning is
  free but "it silently went back to the Walker's 55" fails.
- `takes_cover() == false` — inherited from `walker.gd:251`, asserted because
  `Squad` splits on it (`squad.gd:554-555`) and a Picket sent to infantry cover
  points would park on top of them.
- `WeaponMount.rotation.y ≈ +PI/2` (also in `check_frame.gd`; cheap to repeat).
- **it walks** — copy `test_bulwark.gd:156-182` verbatim: move the body, tick
  `_tick_gait`, assert the knee leaves rest and settles again. The gait is
  `walker.gd`'s and is driven by distance moved, so a frame that slides is a
  frame whose rig paths are wrong.

**The elevation geometry — the assertion only this frame needs**
- the fitted weapon's muzzle points **above** the horizon at
  `gun_pivot.rotation.x == 0`: `-mount.global_transform.basis.z` has
  `y > 0.75` (54° is sin 0.809). This pins the cant's **sign**, which
  `build_picket.gd:103-108` says three of five first-round concepts got wrong.
- the effective elevation band: set `gun_pivot.rotation.x` to
  `gun_min_pitch_degrees` and to `gun_max_pitch_degrees` and assert the muzzle's
  elevation angle lands where §4.3's decision says it should. **Assert the
  decision explicitly, either way**, so "the launcher cannot depress" is a
  recorded choice and not something the next reader discovers.
- `PodCant` is a **descendant of** `gun_pivot` — walked up the tree rather than
  by name, the way `test_bulwark.gd:107-115` checks the shield — because the
  whole 54°-on-a-child arrangement exists so `walker.gd:224`'s *assignment*
  cannot clamp the rest pose flat.

**The weapon**
- `item_flak.tres` loads; `kind == 0`; `fits_ai()`; `ai_scene != null`.
- `chassis_whitelist == [&"picket"]`.
- `picket_frame.takes(flak) == true`.
- `rover_frame.takes(flak) == false` **and** `walker_frame.takes(flak) == false`
  — the whitelist doing its job, which `PICKET.md` §7 asks for.
- `picket_frame.takes(heavy_mg) == false` — the turret rule refusing a gun that
  does not name the frame. Assert it **with the trap-6.2 comment**, so the next
  person to "fix" it reads why the Bulwark is armable once.
- `picket_frame.takes(nanite_reboot) == true` — `drives = false`, so leg kit
  fits. This is the Picket's non-obvious advantage over a Rover and nothing else
  in the project states it.
- a fitted weapon points where the turret faces: `equip_weapon_scene`, one
  `process_frame`, then the mount's forward **projected flat** dotted with the
  turret's flat forward **> 0.9**. Flat, because the 54° cant means the raw
  vectors can never agree — and a test that compares them unprojected will fail
  and look like a mount-yaw bug.
- `weapon.pellets == 1` and `weapon.ai_spread_mrad <= 8.0` — the two corrections
  in §3.3, pinned, because the design doc on disk says 3 and 18 and someone will
  "restore" them.
- `calculate_damage(95.0) <= calculate_damage(10.0)` — damage must not **rise**
  with range, which is what the default `min_damage = 18` against
  `base_damage = 14` does.

**What `PICKET.md` §7 asks for and should not get**
> "`flak` is lethal against a 90-hull target and poor against a 400-hull one,
> measured rather than asserted — the discrimination IS the counter-pick."

**Do not write this test. It cannot pass, and it should not.** There is no
size-discrimination mechanism in `AIWeapon` (§1.1); a hitscan gun that kills an
80-hull Spotter in six rounds kills a 400-hull Bulwark in thirty, and 40 rounds
fit in a magazine. If the human wants discrimination it needs the elevation gate
or a new mechanism, and either is a combat-model change logged elsewhere. Write
instead the two assertions that *are* true and *are* the frame:
`max_effective_range == 95.0` and `base_sensor_range == 75.0`, with a comment
saying these are the counter — reach and acquisition — and that damage is not.

Deliberately **not** asserted: geometry sizes. `test_bulwark.gd:22-23` —
measurement belongs in `tools/check_frame.gd`, which prints W/H/L.

---

## 7. Order of work, and what to prove at each step

Each step ends with `bash tools/check.sh --changed` printing **PASS**. Do not
run Godot while `tools/test.sh` is in flight (`FRAME_ANATOMY.md` §7).

**0 — Get §4.3 answered before anything else.** The pitch-clamp decision changes
two scene values and one test, and it is the only thing in this brief that a
builder cannot settle alone. Ask, with the 42°–89° arithmetic in front of you.

**1 — The weapon, first.** `flak_pods_model.tscn`, then `ai-wep_flak.tscn`, then
`item_flak.tres`, then the `items` array + `[ext_resource]` in
`test_item_catalogue.tres`, then the `MODEL_OVERRIDES` line in `icon_art.gd`.
*Prove:* `check.sh --changed` PASS, and a one-off probe that
`load(".../test_item_catalogue.tres").item(&"flak")` is non-null and `fits_ai()`.
Weapon first means the chassis never exists in a state where it issues a gun
nothing can resolve.

**2 — The chassis.** `chassis_picket.tres`, `KillKinds.FRAMES`, then the
`chassis` array + `[ext_resource]`.
*Prove:* `bash tools/test.sh`. `test_ledger.gd` exercises recruit, refit and the
save round-trip; `test_ledger.gd:818-831` will check the §5-14 unlock the moment
you add it. Watch the `[Catalogue] N items, M chassis: [...]` line
(`item_catalogue.gd:55-56`) and confirm `picket` is in the key list — a `null`
in the array is the silent failure (`item_catalogue.gd:43-53`, trap 6.8).

**3 — The mission unlock.** `&"picket"` and `&"flak"` into the chosen mission's
`unlocks`.
*Prove:* `tools/test.sh` again — the unlock check is global and will catch an
item that is not `in_shop` or a chassis not in the catalogue.

**4 — The scene edits, by hand** (§4.2 table): `Allowed*Options`, traverse,
elevation rate, the pitch clamps from step 0, `sensor_range`, `health`.
*Prove:*
```bash
"D:/Godot Games/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe" \
  --headless --audio-driver Dummy --path . \
  --script res://tools/check_frame.gd -- res://Character/characters/ai/picket.tscn
```
groups, the three typed arrays, livery pieces, eye exclusion, mount yaw, bare
meshes, plus the measured W/H/L and the capsule. **It does not check
`Allowed*Options`** — load the saved scene and print both arrays and their
`get_typed_builtin()` yourself, or the typed-array trap eats the edit in
silence. Also confirm the measured height: `build_picket.gd:136-145` says the
bare chassis is **3.74 m** (the antenna is now the tallest piece) against the
Walker's 3.81, and that a fitted launcher puts the silhouette back near 4.15 —
so expect ~3.74 bare and note what it is with the pack on.

**5 — `tools/test_picket.gd`, then icons.**
*Prove:* `bash tools/test.sh` all green, then run `tools/bake_icons.gd` and
**list `icons/chassis/` and `icons/items/`** to confirm `picket_{s,m,l}.png` and
`flak_{s,m,l}.png` landed. Nothing asserts this; it is why the Bulwark still has
none. Say in your report whether they did.

**6 — The lab plan, then stop and hand it over.**
`Campaign/lab/plans/picket_screen.tres` on `bulwark_screen.tres`'s pattern: a
`LabPlan` with `LabMatchup` sub-resources, a `question` written as *what to
watch*, and a **control**. The control is not optional here, because §1 says the
frame's edge may be too thin to see.
Suggested matchups: 2 Pickets vs 4 Spotter Drones at 80 m; **2 Rovers vs the
same 4 Spotters as the control** (same supply, 4 either way — and remember the
Rover's `machine_gun` already shoots up, `ai_weapon.gd:441`); and 2 Pickets vs
4 riflemen at 40 m, where the frame should be *bad*.
`question` should ask the reader to watch:
- **does the Picket engage sooner than the Rover?** That is the whole claim.
  `sensor_range` 75 against the Rover's 55, with `acquire_far_penalty = 4.0`
  costing 1.4 s at the edge of reach (`picket.tscn:263`, `enemy.gd:1006-1011`).
  If the two open fire at the same moment, the frame has no edge and should be
  cut.
- **does it actually hit them?** Tight spread is §3.3's bet. If 6 mrad still
  misses an orbiting drone, the answer is a lower number or a leading weapon
  (§3.5), not a wider one.
- **does the barrel read?** The one thing that is unambiguously true about this
  frame is that it is the only one whose launcher points where the threat is.
  Watch it from the ground.
- **is 38 °/s traverse "flankable" or "broken"?**
*Prove:* nothing. **This step is the human's** — game feel and balance are not
measurable here (CLAUDE.md). Stop and ask.

---

## 8. Open questions and risks

**Ranked. The first two must be answered before step 1.**

1. **Is the frame worth building at all?** §1 is the honest case: two of the
   three mechanisms the design doc relies on are inverted, and what is left is
   reach, acquisition and a silhouette. That is a real but narrow frame, and
   `PICKET.md` §2 already admits the air game is emergent rather than designed.
   **Two frames in this batch have been cut for exactly this.** My
   recommendation is build it — the corrections in §3.3 make the gun genuinely
   the first one tuned for a small fast target, and the cost is low (no script,
   one weapon, one model, six registration edits) — but the human should make
   that call having read §1 rather than §6 of the design doc.
2. **The pitch clamps (§4.3).** The 54° cant adds to `gun_pivot.rotation.x`, so
   the launcher's real band is 42°–89° today and **cannot point at the ground**.
   Nobody has stated this. Recommendation: `gun_min_pitch_degrees = -60.0`,
   `gun_max_pitch_degrees = 35.0`. **Human's call**, and it blocks step 4.
3. **`ai_spread_mrad` 6 vs the doc's 18, and `pellets` 1 vs 3.** §3.3 shows the
   doc's mechanism is inverted. I am confident about the direction and not about
   the magnitude — 6 mrad is a guess and the lab plan is where it gets settled.
4. **The height, still unresolved from `PICKET.md` §1.** The frame was 4.15 m
   with tubes, measures ~3.74 bare (`build_picket.gd:136-145`), and goes back
   near 4.15 once a pack is fitted. §1 of the design doc asks whether a launcher
   that reads at icon size is worth being the tallest 2-supply frame in the
   game. **Still open, still the human's, and nothing in this brief changes it.**
5. **`base_health` 140 vs the scene's 170.** The generator claims to follow the
   design doc and wrote a different number. Resolved in §2 as 140 both places;
   flag it in the commit so it is a decision rather than a silent pick.
6. **`min_damage` / `damage_falloff_start`.** Omitted by the design doc and the
   defaults are actively wrong (damage *rising* with range). Values in §3.3 are
   proposals.
7. **`ammo_type`.** New `&"flak"` pool versus reusing `&"20mm"`.
   `tools/test_ammo.gd` exists; **I did not read it, so I cannot say what a new
   pool costs.**
8. **`FALLBACK` in `AllowedMovementOptions`.** §4.4 excludes it. On a 140-hull
   frame there is a case for `[0, 1, 2]`. One character either way; the lab plan
   will show whether the Picket dies standing still.
9. **The missile upgrade (§3.5).** An `AIWeaponSAM` overriding `_aim` to lead
   would be the project's first leading weapon, ~20 lines, and would make the
   Picket's six tubes true. It is a weapon-system feature and must not ride in
   on a chassis — the reverted elevation gate is the precedent. **Logged, not
   proposed.**
10. **`FRAME_ANATOMY.md` corrections, for the record.** It is a good document
    and almost everything in it checked out line for line — `walker.gd:224`'s
    assignment, `enemy.gd:2895`, `enemy.gd:3053`, the `takes()` refusals, traps
    6.1, 6.2, 6.4, 6.6, 6.9, 6.12, the missing Bulwark icons, and the
    `required_rank` dead end were all verified against source. Two gaps:
    - **§1.3 does not list the weapon's own catalogue `items` entry.** A frame
      whose `starting_weapon_id` names an item that is not in
      `test_item_catalogue.tres` deploys **unarmed** and nothing warns
      (`squad_spawner.gd:304-306`). It belongs in §1.3 as item 6b. §1.5 item 18
      and §3 cover *making* a weapon; neither says to register it.
    - **§6.10's point about `built_in` extends to the default.** `"CLAWS"` — the
      field's default (`chassis_definition.gd:50`) and the value on the Rover,
      Walker and Bulwark — has no `icons/items/claws_*.png` and no
      `icon_art.gd` `BUILT_INS` key, so it is already the silent blank §6.10
      describes.
    And one thing §3.4's rule does not cover but should, because it decided this
    frame: **nothing in the project leads a moving target**, so "is the round
    hitscan?" is not only a question about which base class to use — it is the
    question of whether the weapon can hit a mover at all.

---

# AMENDMENT — 2026-10-10, human review. READ THIS BEFORE SECTION 3.

**The launcher fires rockets that land at a distance. It is INDIRECT FIRE, and
the hitscan recommendation above is overruled.**

The human's words: *"that's fine, the launcher should shoot rockets that land
at a distance."* "That's fine" answers §4's pitch question — **the 42°–89°
clamp stays**, and the recommendation to widen it to −6°…89° is dropped. At
artillery elevation a launcher that arcs is correct and a launcher that fires
flat is not.

## What changes

- **`flak` becomes a rocket, not a hitscan burst.** The reasoning that chose
  hitscan — nothing in this project leads a moving target, so a projectile
  misses an orbiting aircraft every time — **is still true and is now a
  design consequence rather than a blocker.** See the open question below.
- **The base class changes.** `ai_weapon_grenade_launcher.gd` is the indirect
  family and is already shared by four shipped weapons (mortar, GL, turret GL,
  cluster) with nothing but different exports. Check whether a fifth set of
  exports is enough before writing a subclass — that is `FRAME_ANATOMY.md`
  §3.4's rule and it probably answers this one for free.
- **The template changes** from `ai-wep_heavy_mg.tscn` to the mortar's. Read
  `item_mortar.tres` and its `ai_scene` together.
- **§4's spread reasoning no longer applies.** `ai_spread_mrad = 6.0` was
  chosen so a flat burst would not miss a small target. An arcing rocket is
  placed, not sprayed; re-derive it.

## The open question this creates, which the builder must NOT resolve alone

**A frame called Picket, designed and selected as the answer to being bombed,
now has a weapon that cannot hit an aircraft.** Nothing leads a target, so a
rocket lands where the aircraft was. Three readings, and the human picks:

1. **It is rocket artillery and the anti-air identity goes.** Honest, and the
   silhouette still works — six tubes at 54° read as artillery perfectly well.
   `PICKET.md` §2's whole argument would need rewriting.
2. **It is both**: rockets at ground targets, and air defence comes from
   something else on the frame.
3. **Leading gets built.** `AIWeaponSAM extends AIWeaponRecoilless` overriding
   `_aim` is about twenty lines and it is the thing that would make the model
   true — but it is a weapon-system feature for the whole game and must not
   ride in on one chassis.

**Build the rocket. Do not decide the identity.** Flag it in your report.
