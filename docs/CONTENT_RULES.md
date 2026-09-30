# CONTENT RULES — how to add things without breaking them

Written after a session that hit every trap in here at least once. Each rule
exists because something silently didn't work, not because it seemed tidy.

**Read §0 before anything.** Those five apply to every kind of content.

---

# §0 · THE FIVE THAT BITE EVERYTHING

### 0.1 Scene values beat script defaults — and a MISSING line is a value
An `@export` you didn't author in the `.tscn` takes the script default, silently
and forever. Two live bugs from this alone:

- `SquadSpawnPoint.max_slots` defaulted to **4**. Every hand-built level writes
  `999` over it; the Hillfort didn't, so a seven-seat squad deployed four.
- `soldier_chassis.tscn` and `mechanic_chassis.tscn` never authored
  `move_speed`, so they ran at `Enemy`'s default 4.5 while the player and every
  enemy trooper ran at 6.0. Your own squad was 25% slower than its enemies.

**Rule:** when adding a frame or weapon, diff its `.tscn` against a working
sibling and author every field the sibling authors, even if the value matches
what you think the default is.

### 0.2 `load_steps` must equal (ext_resource + sub_resource + 1)
Too low and Godot **silently drops the tail sub-resources**. `check.sh` catches
it — run it after every hand-edit that adds a resource.

```bash
echo "ext: $(grep -c '^\[ext_resource' F)  sub: $(grep -c '^\[sub_resource' F)"
```

### 0.3 Never invent a `uid://`
Hand-writing `uid="uid://cwatcherbody001"` works headless (it falls back to the
path with a warning) and **fails in the editor**, which resolves the UID
properly and gets nothing. The editor then assigns the file a real UID and every
reference to your invented one is stale.

This cost the Watcher an entire playtest, and the Mark One's model had the same
break for a whole session.

**Rule:** omit `uid=` from `ext_resource` lines entirely. Path resolution
cannot go stale. Let the editor assign UIDs to files it owns.

**To find the ones already in the tree**, compare every UID *declared* on a
file's first line (plus every `.import`) against every UID *referenced*. What
is referenced and never declared is a dangling pointer:
```bash
find . -path ./.claude -prune -o \( -name '*.tscn' -o -name '*.tres' \) -print |
  while read -r f; do head -1 "$f" | grep -oE 'uid://[a-z0-9]+'; done | sort -u > /tmp/dec
find . -path ./.claude -prune -o -name '*.import' -print |
  while read -r f; do grep -oE 'uid="uid://[a-z0-9]+"' "$f" | tr -d 'uid="'; done | sort -u >> /tmp/dec
find . -path ./.claude -prune -o \( -name '*.tscn' -o -name '*.tres' \) -print |
  while read -r f; do tail -n +2 "$f" | grep -oE 'uid://[a-z0-9]+'; done | sort -u > /tmp/ref
comm -13 <(sort -u /tmp/dec) /tmp/ref
```
That sweep found sixteen, including `item_bolt.tres` pointing at a UID the Mark
One's own player scene had never declared — the game's starting weapon, loading
by path fallback the whole time.

### 0.4 Enums are append-only
Their values are stored as ints in `.tscn` and `.tres` files. Adding a value in
the middle silently reassigns every authored reference.

### 0.5 Gates, every time
```bash
bash tools/check.sh --changed     # must print PASS
bash tools/test.sh                # after touching a system with an invariant
bash tools/smoke.sh               # after touching anything that loads at boot
```
`master.gd` is the main scene — touching it means `smoke.sh`.

---

# §1 · WEAPONS

### 1.1 The item
`Campaign/items/item_<id>.tres`, `kind = 0`.

| field | trap |
|---|---|
| `player_scene` | a HUDWeapon scene |
| `ai_scene` | an AIWeapon scene — **omit it and the weapon is half-built.** `recoilless` shipped with no `ai_scene` for months: no enemy and no squadmate could ever hold one |
| `usable_by_player` / `usable_by_ai` | both default true; `machine_gun` is player-false because it is a mount |
| `fits_vehicles` | true = turret mount, false = carried |
| `ammo_type` | `&""` means it feeds from nothing |
| `in_shop` | false hides it from the shop **and from the unlock screen** |
| `weapon_damage` | display only — the real numbers live on the scenes |

### 1.2 `player_mount_offset` OVERWRITES the scene transform
`equipment_loadout.gd:550` does this **after** `add_child`:
```gdscript
node.position = item.player_mount_offset
node.rotation_degrees = item.player_mount_rotation_degrees
```
So the item can silently move a weapon that already positions itself.

Only two items have a non-zero mount: `m4` and `bolt`, and they are identical
because the Mark One's item was **copied from the Ancient Rifle** and inherited
it. The m4's HUD scene has no Holder and no pose exports — the mount is the
only thing placing it. The bolt's scene places itself, so the inherited mount
shoved it 19cm right and 21cm low, and two rounds of "fixed" ADS went by before
anyone checked the item instead of the model.

**Rule:** if the HUD scene has a `Holder` and pose exports, `player_mount_offset`
must be **ZERO**.

### 1.3 Viewmodel poses are RADIANS
`base_rotation` / `ads_rotation` are lerped straight into `viewmodel.rotation`.
The class default is `Vector3(-0.3, 6.0, 2.8)` — 6.0 radians is 344°, which is
why an unauthored weapon sits sideways.

**Author all four:** `base_position`, `base_rotation`, `ads_position`,
`ads_rotation`. Never rely on the default.

### 1.4 ADS: build the sight line FLAT, then translate. Never pitch.
The rear aperture **centre** and the front post **tip** must both land on the
camera axis (x = 0, y = 0). Aligning the wrong part of the rear sight — the
bridge instead of the hole — puts the whole picture below the crosshair.

**`ads_rotation` is zero on every iron-sighted weapon, and must be.** The shot
is not traced down the camera. `hud_weapon_template.gd` fires from the camera
**along the muzzle's +X axis**, so pitching the model to level a rising sight
line aims the bullet somewhere the sights are not. The Mark One carried a
`-0.01148` pitch for exactly this reason and put its rounds 0.76° under the
crosshair while the sight picture looked plausible.

So the fix belongs in the MODEL: give the rear aperture centre and the front
post tip the **same height**. The house number is **model y 0.573** — rear
sight base at 0.438, ears at 0.573, bridge at 0.6905 (aperture 0.473–0.673),
front post at 0.503 with a 0.14 box, tip 0.573. Copy those five numbers.

Then the pose is arithmetic, identical for every weapon on the standard
Holder (`scale 0.26` at `(0.104, -0.123, -0.55)`):
```
ads_position.y = 0.123 / 0.26 - 0.573 = -0.099923
ads_position.z = -0.4                     # 0.26 * -0.4 + 0.104 = 0, centred
ads_position.x = -(0.27 / 0.26) - <rear sight x>   # puts the aperture 0.278m out
ads_rotation   = Vector3(0, 0, 0)
```

**Nothing may enter the y 0.573 / z 0 line between the two sights.** Two
weapons shipped broken on this and neither looked broken in the scene tree: the
Squad Automatic's carry-handle posts sat dead on the centreline, and the
Cluster Launcher's drum was a metre and a half across and stood 3.7° above the
line of sight. Check every part's top between the sight stations.

Verify by measuring, not by eye:
```bash
godot --path . --audio-driver Dummy --script res://tools/preview_viewmodel.gd -- <outdir> <weapon.tscn>
```
It prints the camera-local x, y and depth of both sights plus the line's tilt.
**Correct reads as zeroes**; anything else is the correction, in metres, in
camera space — divide by the Holder's 0.26 to get `ads_position` units. It also
renders under the game's real environment (`Env/world_environment.tres`), which
matters: the old flat-ambient rig had no radiance map, so every `metallic`
material came out near-black and a perfectly good front post looked missing.

That tool also applies the item's mount offset. It did not, which is why it
lied — see 1.2.

**The models declare their own sight line.** Put an empty `Node3D` named
`Aperture` at the rear aperture centre and one named `Tip` at the front post
tip; the probe finds them by name anywhere under the model. It used to derive
the aperture from a node called `RearSight/EarL`, which worked only while every
rear sight was two ears and a bridge — the Squad Automatic's M249 peep has no
ears, and the probe went **silent** rather than wrong, which is worse.

### 1.4a The one exception: weapons that arc
A launcher wants its bore **above** the line of sight, because the round falls
the whole way. So `ads_rotation` is NOT zero for those, and the model does the
opposite of 1.4: the rear aperture sits **high**, the sight line runs downhill
to the front post, and the pose pitches the gun nose-up to level it. That pitch
is the elevation, and it is also what the shot is traced along — so the two
cannot disagree.

The Cluster Launcher is the worked example: aperture `y 0.789326`, post tip
`0.573`, `ads_rotation.z = +0.0696466` (3.99°), which at 42 m/s is a 25m zero.
Its launcher script fires along `tracer_origin.global_transform.basis.x`, not
the camera forward — firing down the view axis throws the round flat and makes
the whole sight decorative.

**A true hold-over ladder does not fit on screen.** Elevation scales onto the
view by `sight_radius / eye_relief`, which here is 0.806 / 0.278 ≈ 2.9×. A
25–100m band is 13° of elevation, so the ladder wants 38° on a 45° screen. That
is why real launchers MOVE the sight rather than holding over, and why the
range ticks on that model are a scale read against a pivoting leaf rather than
points to aim with. Build the ticks stylised, keep the zero real, and put the
true table in the model's header.

### 1.5 The AI weapon scene
`weapon_type`: `0` MELEE · `1` HITSCAN · `2` PROJECTILE.

**PROJECTILE needs a subclass.** The base `AIWeapon` does not branch on it. The
override point is `check_damage(weapon_target: Vector3)` — not `_fire_shot()`,
which does not exist. Useful base helpers: `_level_node()`, `_owner_body()`,
`get_forward_vector()`, `play_muzzle_flash()`.

`min_effective_range` is a balance lever, not flavour: the Recoilless uses 12m
so a rocket trooper cannot walk into your squad and kill itself plus three of
yours.

### 1.6 Audio
`WeaponAudio` enforces `MIN_UNIT_SIZE = 32` on any sound it stages, so authoring
a smaller `unit_size` does nothing. Set `volume_db` to place the weapon in the
mix; `unit_size` only matters above 32.

### 1.7 Icon
```bash
godot --path . --audio-driver Dummy --script res://tools/bake_icons.gd -- "" <id>
```
The empty first argument means "the real `res://icons`". **Icons are green line
art on transparency** — they look blank in an image viewer. Check the file size
(a real one is 3–7KB) or bake a sheet to a temp folder, which draws them on the
studio background.

New PNGs have no `.import` until the editor has focus once.

### 1.8 It must be in the catalogue, and a mission must unlock it
Add the item to `Campaign/items & catalogue/…`. Then:

**`locked_by()` only gates what a mission NAMES in `unlocks`.** An item no
mission names is on sale from the first visit to base. Removing something from
an unlock list makes it *more* available, not less.

### 1.9 Recoil: a weapon with no `recoil_curve` does not kick at all
`_tick_recoil()` reads `recoil_curve.sample(t)`. With no curve there is no
kick — not a small one, **none** — no matter what `recoil_per_shot` and
`camera_recoil_scale` say. Only the Ancient Rifle had a curve, so three
weapons shipped with numbers that did nothing and it read as a tuning problem
rather than a missing resource. Give every player weapon its own
`*_recoil_curve.tres`; the template now warns once if you forget.

**The number in the scene is not the number you feel.** The kick is *added*
every frame while a lerp drags the camera back, so what you see is roughly
`per-frame add ÷ (delta × look_interp_speed)` — about 5× the per-frame value.
Do not guess it:
```bash
godot --headless --path . --script res://tools/test_recoil.gd
```
That replays the template's arithmetic at 60fps and prints peak pitch and yaw
in degrees per weapon. Current spread: Ancient Rifle 16°/9°, Mark One 24°/13°,
Squad Automatic 18°/9°, Cluster Launcher 26°/12°.

**Anything you add to the camera must have something pulling it back.**
`cam.rotation.x` is safe because `update_view()` *sets* it from
`look_direction.x` before adding the kick. Yaw had no such line — the player
body carries yaw, so nothing ever wrote `cam.rotation.y` — and `+=`
accumulated for as long as the trigger was held, walking the camera 160° off.
It is now lerped back to 0 first. `test_recoil.gd` bounds both axes so it
cannot come back.

**The curve is PER SHOT and re-arms on every round**, so on anything automatic
it only ever plays its first fraction and every shot kicks identically. "Jumps,
then steadies" is `settle_shots` / `settle_to` on the weapon, not the curve.

---

# §2 · EQUIPMENT AND MODULES

`kind = 1` EQUIPMENT · `kind = 2` MODULE.

### 2.1 Modules can only pull thirteen levers
`health_bonus`, `accuracy_bonus`, `damage_bonus`, `speed_multiplier`,
`signal_bonus`, `sensor_bonus`, `signal_resistance_bonus`,
`self_revive_seconds`, `equipment_slot_bonus`, `suppressive_fire`,
`required_rank`, `requires_chassis`, `chassis_whitelist`.

Ten of those are "a number goes up". Anything that changes *behaviour* needs a
new hook — do not promise it in a description you cannot deliver.

### 2.2 Equipment is quantity-based
`quantity` is uses per mission. `item_hatchling` is `quantity = 2`. A passive
"every N seconds" item puts the decision in the AI's hands and the player
forgets they have it — prefer a used item.

### 2.3 `one_per_robot`
Stops two of the same module stacking on one frame. Set it for anything whose
effect would be silly doubled.

### 2.4 Stats are applied by MULTIPLICATION at spawn
`squad_spawner.gd` does `soldier.accuracy_skill *= record.effective_accuracy`
and `soldier.move_speed *= record.effective_speed`. A module's
`speed_multiplier` of 1.0 is a no-op; these are not additive.

### 2.5 Icons
Same bake as §1.7, same "looks blank" trap.

---

# §3 · CHASSIS (player-buyable frames)

`Campaign/chassis/chassis_<id>.tres`.

### 3.1 `base_speed` is a MULTIPLIER, not m/s
The body scene's `move_speed` is the real speed; `base_speed` scales it.
`chassis_walker` is `base_speed = 0.9` over a scene `move_speed = 3.2`.

Set the body scene's `move_speed` explicitly — see §0.1.

### 3.2 Vehicles need mobility numbers authored
- `floor_max_angle` — the rover had **40°**, *less* than infantry's 45° default,
  so a powered six-wheeler could not climb out of ground a man could walk out of.
- `step_height` — inherited 0.45 (an infantry kerb) while the rover's own
  obstacle whiskers only see things above ~0.75m. That left a dead zone: too
  tall to step, too short to steer around. It drove at it and stopped.
- `step_forward` — a long hull needs more clearance past a lip or it
  high-centres.

Pin the envelope with a test. `tools/test_rover_mobility.gd` asserts **both**
ends — what it can climb *and* what must still stop it. A frame that can climb
anything makes every level's geometry meaningless.

### 3.3 Slots and flags
`weapon_slots`, `equipment_slots`, `module_slots`, `turret`, `vehicle`,
`drives`, `built_in` (a role tag like `CLAWS` / `WELDER` / `HATCH` / `RELAY`),
`weapon_replaces_built_in`, `musters_at_base`.

`starting_weapon_id` **takes the gun out of stores** — `fit_item` calls
`armoury.take`. Setting it without stocking the weapon issues nothing, and the
robot musters empty-handed.

### 3.4 Register it as a kill kind
`Campaign/kill_kinds.gd`: add to `FRAMES` (id → chassis path) **and** `SCENES`
(scene basename → id). Miss this and the debrief cannot name or count it.

### 3.5 Supply, and the ladder
`supply` is the squad-seat cost. Nothing above **3** exists today, and the
Walker at [3] is the ceiling — anything at [4]+ has to be worth more than two
Walkers.

---

# §4 · ENEMY FRAMES

Everything in §3, plus:

### 4.1 Faction colour is a SHADER, not paint
Enemy frames get their rust-amber from `faction_metal.gdshader` +
`faction_livery.gd` tinting `robot_metal.tres`. Use those and the frame tints
itself.

**Never bake a faction colour, and never add an amber emissive.** Amber is the
mechanic's welder and the reclaimer — a glowing amber part reads as *repair*.
The enemy quadcopter has no glowing element at all; match that.

### 4.2 Required wiring
`groups=["enemies"]`, and node_paths for `nav_agent`, `bark`, `detection`,
`particle_effects_die`, `particle_effects_hit`, `visible_pieces`.
`weapon_mount` is optional (the nest and watcher have none).

### 4.3 Buildings
Clear `AllowedMovementOptions` and `AllowedCombatOptions` in `_ready()`, and
override `move_along_nav`, `move_to`, `order_move_to`, `takes_cover`,
`enter_cover_seeking` and `_update_facing` to nothing. Copy `enemy_nest.gd`.

**`destroy()` switches the physics tick off.** Anything you ease in
`_physics_process` freezes mid-motion forever on a dead body — the nest's fires
did exactly that. Tween death animation from `destroy()` instead.

### 4.4 `activation_distance` and culling
Beyond it a body goes passive and stops thinking (it stays **visible**). A
landmark meant to be noticed from far away needs a large value — the Watcher
uses 400.

---

# §5 · ART STYLE

Measured off `machine_gun_model.tscn`, which is the house reference.

| | albedo | metallic | roughness |
|---|---|---|---|
| Olive (kit) | `(0.27, 0.3, 0.18)` | 0.1 | 0.85 |
| Steel (working parts) | `(0.15, 0.16, 0.17)` | 0.65 | 0.42 |
| Black (furniture, barrels) | `(0.08, 0.08, 0.09)` | 0.5 | 0.55 |

- Built from `MeshInstance3D` + `BoxMesh` / `CylinderMesh`. **No CSG** in
  weapon models. ~15–25 parts.
- Orange-brown is the *ancient / scavenged* read (the pump shotgun). Olive is
  AI-manufactured.
- **No emissive on weapons.** Nothing in the player's hands glows.
- `PrismMesh` is flat and disappears edge-on — use stacked boxes for blades.
- Check silhouette at a common camera scale with a size reference in frame, or
  you cannot judge how big a thing reads.

---

# §6 · LEVELS AND MISSIONS

### 6.1 The level must contain
- **`SpawnPoint`** — the player. Its **rotation is used**: `place_at()` sets
  `look_direction.y` from it. Hidden at runtime by `spawn_point.gd`, visible in
  the editor.
- **`SquadSpawnPoint`** — author `max_slots` (0 = everyone).
- **`LevelExit`** + a `ReachObjective` child with `is_extraction = true`.
  Exits are scaled **(4,4,4)**; their objective children carry a **0.25
  counter-scale** so the trigger volume stays 10m. Uniform scale on both —
  Godot does not support non-uniform scale on a `SphereShape3D`.
- **`EnemySquadObjs`** — `SquadObjectivePoint`s with `tag = &"obj_…"`.
- Capture objectives (`InteractObjective`) for anything a mission names.

### 6.2 `active_objectives` is a WHITELIST
`Campaign._prune_inactive_objectives()` **frees every objective the mission does
not name**. So a mission naming two ids its level does not contain ends up with
**none** — blank objective HUD, nothing to complete, no way home. That shipped
on the Hillfort and cost a playtest.

An empty `active_objectives` means "all of them", which is valid.

Guard: `tools/test_mission_objectives.gd`.

### 6.3 `reinforcement_tag` wakes from FIVE places
1. an objective id (completing it)
2. `nest_down`
3. `<callsign>_down` — that squad wiped
4. `<callsign>_engaged` — that squad's first contact
5. `wake_after_kills > 0` — a body count

**The `_down`/`_engaged` tags are lowercased**: `squad_engaged_tag("EAST-YARD")`
returns `east-yard_engaged`. Writing it in caps means it never fires — four
Qamareen squads never arrived because of exactly that.

A tag naming none of the five is **61 bodies that never spawn**, which is the
current state of Coast Road, Three Rivers and Qamareen.

### 6.4 `posture = 3` (RESERVE) is what holds a squad back
Not the presence of a `reinforcement_tag`. A squad with a tag but posture
ADVANCE spawns immediately and the tag does nothing.

Enum: `0` PATROL · `1` GARRISON · `2` ADVANCE · `3` RESERVE.

### 6.5 `roster` is the body count; `count` is dead
`body_count()` returns `roster.size()` when roster is non-empty. `count` is the
legacy one-type field and is ignored.

### 6.6 Level regeneration wipes hand-added nodes
The terrain recipe + block pass rebuilds `maps/*.tscn` and **does not preserve
nodes it did not place** — objectives, spawn positions, `max_slots`. The
Hillfort lost its objectives four times in one session.

**Rule:** put gameplay nodes in an idempotent patch script, not a hand edit.
`tools/hillfort_objectives.sh` is the pattern: exits early if the nodes are
present, anchors on node names rather than line numbers, and reads positions out
of TERRAIN's own squad points so it survives their moves.

### 6.7 Minimaps
`tools/minimap_bake.gd` has a **hardcoded level list** — a new level shows no
map until it is added. Needs a window (not `--headless`). Do not run the
`--import` step with the editor open.

---

# §7 · BEFORE YOU CALL IT DONE

- [ ] `check.sh --changed` prints PASS
- [ ] `load_steps` correct on every edited `.tscn` / `.tres`
- [ ] no invented `uid://`
- [ ] the item is in the catalogue
- [ ] a mission names it in `unlocks` (or it is free from minute one)
- [ ] registered in `kill_kinds.gd` if it can be killed
- [ ] icon baked, and checked by file size not by eye
- [ ] `smoke.sh` if anything loads at boot
- [ ] scene edits flagged to the human — the editor will write old values back
      over them if it has the file open
