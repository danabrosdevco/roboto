# What the test suite actually covers

51 suites, ~1,000 assertions. Each line below is the suite's own stated purpose,
not a description written from the outside — if a suite's header and this table
disagree, the header is right and this file is stale.

```bash
bash tools/test.sh          # everything, 12–17 minutes
bash tools/test.sh --fast   # the 25 that never boot the world, ~3.5 minutes
```

**Why the full run is slow.** 25 of the suites boot `Env/world.tscn` and 21 load
a level on top. A headless run still ticks physics at 60 Hz, so
`for _i in 420: await physics_frame` is seven real seconds of waiting — it is not
the engine being inefficient, it is the suite asking for simulated time.
`test_mortar` alone is 57 seconds. `--fast` skips every suite that boots the
world, which is the logic half.

**Not parallelised, deliberately.** Every suite points `Settings` and
`SaveSlots` at the same `user://` probe paths, so two at once would race on the
same files and produce flakiness indistinguishable from a real failure.
Isolating those per process is the prerequisite.

---

## Economy, saves and settings

| suite | covers |
|---|---|
| `test_ledger` | Buying, selling and stock. Exists because four ledger bugs shipped in two days — a sell that refused issued stock, two buys that announced themselves before the goods arrived, and a "newest purchase" lookup comparing keys as strings. |
| `test_profiles` | More than one campaign at a time, and the old single save surviving the move. |
| `test_profile_menu` | The front page, driven the way a player drives it. |
| `test_settings` | Every option actually reaching the thing it controls. The largest suite after terrain. |
| `test_endings` | Dying on an operation, and winning the campaign. |
| `test_analytics` | Whether a real mission leaves a record that answers the questions asked of it. |

## The squad manager

| suite | covers |
|---|---|
| `test_squad_manager` | The three pages, driven by finding a card or button by what it says on it and clicking it — so a button that looks right and does nothing is caught. |
| `test_teams` | The squad going into the field as the teams made on the squad page. |
| `test_equipment` | Whether each item actually *does* the thing it says. |
| `test_item_facts` | The figures a gear card prints, read off the gear's own scenes rather than copied. |

## Weapons and damage

| suite | covers |
|---|---|
| `test_shot_damage` | What one round is worth, counting what it breaks up into (the Cluster Launcher's bomblets). |
| `test_ammo` | Every ammo stock carrying its real numbers. |
| `test_recoil` | What firing does to the camera, in degrees. |
| `test_lance` | The Repair Lance connecting — and saying when it does not. |
| `test_mortar` | The Reclaimer's boom taking a 60 mm tube in place of the welder, and shelling what its squad can see without seeing it itself. |
| `test_mines` | Mines only ever answering to the other side. |
| `test_smoke` | Smoke blocking sight and nothing else. |
| `test_leap` | A leap being an arc, not a launch. |

## Chassis behaviour

| suite | covers |
|---|---|
| `test_walker` | Bought half-armed — its price covers the frame and the gun it comes with. |
| `test_vehicle` | The rover driving, aiming and going down like a vehicle. |
| `test_rover_mobility` | What the rover can drive over, and up. |
| `test_reclaimer` | The tracked repair and salvage frame driving like something on tracks. |
| `test_mechanic` | The repair frame going to whoever needs it, in the right order. |
| `test_diver` | The Diver flying the run it is documented to fly. |
| `test_quadcopter` | Two things invisible until someone played a mission and reported them. |
| `test_nest` | Hives hatching bodies, and reinforcements arriving. |
| `test_wake` | A robot shot from outside its activation distance waking up. |
| `test_give_way` | Two robots meeting in a gap getting past each other. |

## Navigation and terrain

| suite | covers |
|---|---|
| `test_terrain` | The generator, the meshes, the collision and the template level. 114 assertions — the largest suite in the project. **Currently parked.** |
| `test_water_navmesh` | Rivers not being navigable, since a bake cannot tell a river bed from any other dip. |
| `test_bridges` | A bridge the squad can actually walk onto — one it cannot is a wall across the river. |
| `test_causeway` | The causeway being walkable, because on that map it *is* the mission. |
| `test_block_reach` | Every deck a piece grows navmesh on, and whether the squad can reach it. |
| `test_block_steps` | Risers a robot cannot climb. |
| `test_player_steps` | The player getting over small things and still not over big ones. |
| `test_prop_nav` | What a prop actually does to a navmesh. |
| `test_air_clearance` | A drone seeing a block at its own hover height. |
| `test_scatter` | A scatter layer not using its props' own collision. |

## Missions and objectives

| suite | covers |
|---|---|
| `test_mission_objectives` | Every mission's objectives existing in the level it deploys to. Follows instanced sub-scenes, so a gameplay layer kept in `maps/gameplay/*_ops.tscn` is read. |
| `test_mission_tags` | The other half of the same disagreement: every `post_tag`, `spawn_tag` and `route_tag` on every `EnemySquadSpec` resolving to something the level offers. A dangling one never crashes — it turns a garrison into a squad holding the wrong place, or an advance into one walking at the player's spawn — so nothing used to notice. |

Not a suite, but the tool these three lean on:
`tools/probe_mission_anchors.gd` loads a level and reports, for every squad
post, patrol point and objective, whether it is reachable from the spawn and
how far off the navmesh it snaps — plus the biggest capture core that fits
there, measured with one ray up for the ceiling and eight out for clearance.
`POINTS="x,y,z;..."` checks a coordinate *before* it is written into a level.
It has caught a post inside a warehouse, an objective under a canopy, a capture
core inside the building it was named after, and a wall walk that turned out to
have a sixteen-metre gap in it.
| `test_minimap_objectives` | What the briefing and the map board mark, through the one function that decides it. |
| `test_objective_terminals` | Every console a player can walk up to being wired to something. |
| `test_compute_cores` | Capture points that can actually be pressed. |
| `test_induction` | The first visit to base being a mission. |
| `test_tutorial` | Standing at a sign and it being readable. **Currently parked.** |

## Engine and systems

| suite | covers |
|---|---|
| `test_pause_hold` | The composition that let the game run underneath a menu. |
| `test_debug_switches` | The debug tab's switches doing what the rows say. |
| `test_csg_bake` | Robots not building CSG at runtime, and looking the same without it. |
| `test_lab` | A Laboratory plan running start to results without touching the game. |
| `test_livery` | Every metal panel actually being painted its faction colour. |
| `test_barks` | The squad saying the right thing at the right moment. |
| `test_viewmodel_poses` | What the viewmodel poses resolve to on screen. |

---

## Parked suites

Named in `tools/test.sh` rather than deleted, so bringing one back is removing a
line. Both fail on **authored content**, not on logic:

- **`test_terrain`** — the template and mutaha levels load with `terrain.data`
  null. **99 of its 101 checks were passing**, so this is the expensive one to
  leave parked: narrowing it to skip just the two level loads would get the
  generator, mesh, collision and path coverage gating again.
- **`test_tutorial`** — the depot has no lesson signs left, so the walk-up,
  library and stand-down checks have nothing to read.

A suite parked here is a suite nobody is watching.

## Removed

- **`test_bridge_spacing`** — enforced a 20 m minimum between bridges on a map.
  A layout rule for the level art rather than a logic check, and removed on
  request. `test_bridges` still covers the thing that matters: whether a squad
  can get onto one.

## Known gap

`bash tools/check.sh` (the full project parse check, not `--changed`) currently
fails on a pre-existing collision between `tools/block_homebase.gd` and
`tools/block_fortress.gd` — *"The member TRIM already exists in parent class"*.
Both are unmodified against HEAD. Everything else parses.
