# FEATURE CHECKLISTS — what a new thing actually needs

**Read this when the request is a new chassis, map, site, mission, weapon or
objective.** `CLAUDE.md` points here and treats working the list as binding.

A feature here is never one file. Every list below is reconstructed from what
actually broke, and most entries fail **silently** — the thing loads, nothing
errors, and it is simply absent or inert until somebody plays it.

**Account for every line in your report** — done, or why it does not apply.
"I added the chassis" is not a report; the list is what "added" means.

If a line is wrong or missing, **fix the list in the same change**. A checklist
nobody maintains is worse than none, because it is trusted.

## A new CHASSIS

1. `Campaign/chassis/chassis_<name>.tres`, **with `supply` set** — `supply` is
   what `measure_resistance.gd` sums, and 0 makes a whole mission read as free
2. A scene at `Character/characters/ai/<name>.tscn`
3. **A `CollisionShape3D` whose transform you have checked.** An offset capsule
   tested at the body origin reads as buried in the floor it is standing on
4. **`activation_distance`, set per SCENE.** Unset is 75 m, and an ADVANCE
   authored from further out than that never sets off
5. A default weapon in its weapon slot
6. An entry in the `ItemCatalogue` if the player can own it, with a price and
   an unlock on some mission's `unlocks` — otherwise it is unreachable
7. An icon
8. Barks, or it falls back to the faction pool and nobody notices but the ear
9. `tools/test_<name>.gd` carrying `# BUCKET: frames`
10. `tools/_advance_reach.gd` re-run if it walks

The `.tres` and the scene are two separate registrations. One without the other
fails in a way that looks like a spawn bug.

## A new MAP

1. `maps/<name>_level.tscn`, `_art.tscn`, and the terrain `.res`
2. `SpawnPoint`, `SquadMuster`, `LevelExit`
3. **Navmesh baked AFTER all geometry.** The order is build → terrain →
   navmesh → cover, and a rebuild throws away the later three
4. **`filter_baking_aabb` grown to cover everything you built**, with a few
   metres to spare. It clips the bake and says nothing: on Proving it stayed
   pinned to the old arena, so a new wing baked empty and nothing ever pathed
   onto it, with no error anywhere
5. **`agent_height` set to 3.0.** The default is 1.5 and a Walker is 3.00 m
   tall, so the mesh promises headroom the squad does not have
6. **Know which bake source you are on.** Ten active levels set
   `geometry_parsed_geometry_type = 1` and bake from STATIC COLLIDERS; seven
   leave it unset and bake from mesh instances. The same geometry therefore
   bakes differently depending on the level, and **a clearance result does not
   transfer between them.** `docs/TERRAIN.md` → Clearance
7. **Nothing solid between 0.25 m and 0.5 m, anywhere.** The baker will not
   climb it and the body steps over it, so it bakes as a wall that the squad
   then walks through
8. **The size you asked for is not the size you get.** Terrain rounds up to
   whole 64-cell chunks — 128 m at a 2 m cell. 352 × 288 baked as 384 × 384:
   half again the ground, out of the density band, and only the bake's own
   printout says so
9. **`boundary_inset` set deliberately.** It defaults to 60 m, which on a
   384 × 256 map walls off a third of the playable ground
10. `SquadObjectivePoint` markers **with `tag` set** — missions resolve by tag,
    never by node path
11. **A `PatrolPath` node if you want patrols.** Markers alone are not a route:
    `route_tag` resolves against nodes in the `patrol_paths` group, so a handful
    of `Patrol1..6` children find nothing and the squad stands still
12. Cover points baked
13. **The minimap bake, NAMED** — `bash tools/minimap.sh <your-level>`. With no
    argument it bakes every level in the project and dirties files the other
    lanes are working in; it once left 29 committed files modified
14. A slice if it is a capturable site — see below
15. `bucket.sh terrain`, and `probe_nav_vs_art.gd` if anything is built at
    runtime on top of the bake

## A new SITE — a map that can be taken and held

1. `Env/world_objects/<name>_slice.gd` with `cores_by_node` — **matched by NODE
   NAME, not by tag.** This is the opposite of everything else on the map
2. **A tier matching the prefab instanced:** small 0, standard 1, large 2. A
   mismatch sizes the interact volume wrong and puts the player INSIDE it,
   where the ray reports nothing to press
3. `bunker_marker`, `bunker_mount`, `bunker_fallback`
4. A slice node in the level `.tscn`, its `ext_resource`, and the `load_steps`
   bumped
5. `LevelExit.requires_objectives_complete = true`, or the way out is open
   before the operation is won
6. **`optional = true` on any capture the design does not require.** An
   operation is won at the bunker; compulsory captures make an optional route
   unfinishable
7. `Campaign/locations/loc_<name>.tres`
8. Registered in `Campaign/location_catalogue.tres`
9. **`connects_to` reciprocal BOTH WAYS.** A one-way edge is a frontier you can
   cross in one direction and not the other, and nothing complains
10. **A callsign pool entry in `Campaign/callsigns.gd`, keyed by LOCATION id.**
    Miss it and the site drops to the faction pool — audible only
11. `LAYOUT`, `ICONS` and `HEIGHTS` in `ops_table.gd`, keyed by MISSION id
12. `bucket.sh campaign` **and `test_campaign_spine.gd`** — a new Location moves
    §2's income totals, the BFS from the opening site, and a degree count

## A new MISSION

1. `Campaign/missions/mission_<id>.tres`, **`load_steps` = ext + sub + 1**
2. **Registered in `Env/world.tscn`** — a shared file, so say that you touched it
3. **Inserted before the last entry.** `is_final_mission()` reads the last slot
   of that array
4. `requires` naming a mission that **is itself registered**. Gating on an
   unregistered mission locks the campaign with no error at all: it can never
   be completed, so the board simply never offers what comes after it
5. `active_objectives` naming objectives that exist in the level — anything
   left out is freed at `_ready`
6. Every spec's `post_tag` and `spawn_tag` resolving, or it spawns on its raw
   ring offset
7. **`always_active = true` on every ADVANCE spec**
8. **`reinforcement_tag` set to an OBJECTIVE ID** for reserves. It is not a
   free-form tag — `Campaign._on_objective_changed` passes the completed
   objective's id straight to `wake()`, so a typo means the wave never comes
   and the fight is quietly easier than it was authored to be
9. `measure_resistance.gd` to set the Location's `resistance` — §2 says
   measured, never typed
10. `spawn_geometry_audit.gd` — buried, enclosed, floorless or
    standing-on-the-objective bodies

## A new WEAPON or MODULE

1. An `ItemDefinition` `.tres` with the right `Kind`
2. Registered in the `ItemCatalogue`
3. A price, and an unlock on some mission's `unlocks`, or it is unreachable
4. An icon
5. **A viewmodel at `Character/weapon/<name>_hud_weapon.tscn`**
6. **A RELOAD ANIMATION.** Hand-authored as easing segments, and it has to be
   continuous: no jump over 0.045 m or 6° between adjacent frames, the gun back
   at its base pose by the end, and every part the reload moved returned to
   where the model scene put it. A step at a segment boundary is invisible in
   the source and very visible in the hand, because the viewmodel does not lerp
   during a reload and takes the jump whole
7. **Add it to the list in `tools/test_reload_motion.gd`.** That list is
   hardcoded, so a new weapon is NOT covered until it is named there — and an
   uncovered reload is exactly the kind that develops a step
8. **Probe the viewmodel pose, never guess** — `POSES=at@...` renders candidates
   side by side. X is roll, Z is pitch, and the values are degrees
9. An AI weapon entry if enemies carry it, or the spawner warns that the
   catalogue does not have it as an AI weapon and they field nothing
10. `bucket.sh kit`

## A new OBJECTIVE type

1. Extends `MissionObjective`, with `id`, `display_name` and `verb()`
2. **`display_name` names the THING and `verb()` supplies the action.** Do not
   author the whole phrase into the name
3. `optional` and `is_extraction` set deliberately, not left at the default
4. Its interactible on **collision layer 3** — the player's `InteractRaycast`
   is mask 2 and layer 1 never meets it
5. Named in some mission's `active_objectives`, or it is freed at `_ready`
6. Every early return warns

## True for all of them

- **Enums are append-only.** Their values are stored as ints in `.tscn` files
- **Scene values beat script defaults.** Changing an `@export` default does
  nothing to a node already in a scene
- **`duplicate()` a shared resource** before handing it to an instance

