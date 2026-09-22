# Blocks: buildings, terrain features and props

TrenchBroom pieces for dressing levels: buildings, bigger terrain features,
small props, and the solar farms and compute sites the machines built for
themselves. They are built in the same style as the hand-made blocks
(`long_bridge`, `tower`, `checkpoint`): worldspawn brushes only, PSX textures,
chamfered bases, wedge ramps and metal posts.

Every piece is a `.map` you can open in TrenchBroom, plus a **prefab** `.tscn`
beside it. The prefab is a `FuncGodotMap` root pointing at the map, with the
built geometry saved under it, the same shape as `concrete_bridge.tscn`.

| Folder | What |
|---|---|
| `maps/blocks/building_*` | Buildings for the 32 × 24 m sketch-map lots. |
| `maps/blocks/features/` | Set pieces placed by hand: rocks, a cliff ledge, berms, trench lining, a crater rim, a pillbox, a watchtower, containers, a pylon, fuel tanks. |
| `maps/blocks/props/` | Small pieces for scattering or placing by hand: boulders, rubble, barriers, sandbags, hesco, tank traps, drums, crates, wrecks, poles, pipes. |
| `maps/blocks/solar/` | AI-built solar: panel rows, a tracker, a field the size of a lot, heliostats and a solar tower, battery containers, inverters, drone docks. |
| `maps/blocks/compute/` | AI compute: server racks, chillers, a generator, a transformer, a data hall, a compute obelisk, cables, cabinets, a satellite dish. |
| `maps/blocks/landmarks/` | Set pieces a map is built round: the orbital tether anchor at the heart of the valley basin. |
| `maps/blocks/scatter/` | Ready-made `TerrainScatterLayer`s that scatter the props. |

## Conventions

- **Scale:** 32 units = 1 m, as in the map settings.
- **Origin:** ground level (z 0) at the centre of the footprint, so a prefab
  drops straight onto the ground or a building lot.
- **Axes:** Quake +Y becomes Godot +X, and Quake +X becomes Godot +Z. Each
  building's long side therefore lies along a lot's local X.
- **Buried bases:** props sit a little into the ground, so nothing floats on a
  slope.
- **Textures:** only those with a material in `textures/PSX_Textures/`. Building
  a piece never makes FuncGodot write new material files.
- **Brushes are convex.** The tools warn if one isn't: a concave brush builds
  smaller than drawn, silently. They also warn about a box thinner than one
  unit (1/32 m), which builds as nothing.
- **Texture scale:** in the tools, `"PSX_Textures/name@0.3"` gives a face that
  texture at scale 0.3. The solar cells and rack grilles use it, since at
  scale 1 a 256 px texture spans 8 m.
- **The glow:** `glitch_tx_1` stands in for the machines' glowing circuitry
  (seams, status strips, charge points). Its material has no emission, so it
  only glows if you give that material some. That changes every map using the
  texture.

## Placing a piece

Instance the prefab under the level's `NavigationRegion3D`, so the navmesh bake
sees it, then move and turn it as you like. Rebake the navmesh after placing
anything solid.

**Never press Build on an instance.** That saves a second copy of the geometry
into the level, beside the prefab's own.

## Scattering props

Put a `TerrainScatter` under the terrain and add a layer from
`maps/blocks/scatter/`, or drop prop prefabs into any layer's **Scenes** list.

| Layer | What it spreads |
|---|---|
| `scatter_boulders` | The three boulders, clumped, solid (0.9 m collider), fine on steep ground and mountains. |
| `scatter_micro_terrain` | Mounds, rock slabs and small boulders. Knee-high relief with no collision, faded out at 250 m. |
| `scatter_debris` | Rubble, blocks, tank traps, drums, crates and barriers, in clumps. Kept off steep ground and mountains. |
| `scatter_wrecks` | Cars and robots, rarely, and allowed onto roads. |
| `scatter_tech_debris` | Toppled racks, cable runs, network cabinets and drone docks. Rare clumps on flat ground, for the land round a compute site. |

How scatter layers behave:
- **Drawn as MultiMeshes.** A layer uses only the prefab's mesh, so its
  collision comes from the layer's `collision_radius` (a cylinder), not from
  the brushes. Place a prop by hand when it needs exact collision, such as
  cover to shoot over.
- **Off painted ground.** Roads, building lots and scorch are left clear up to
  each layer's `max_paint`.
- **Rates are starting points.** The per-hectare numbers are first guesses;
  tune them per level.

## Editing a piece

1. Change its `.map` in TrenchBroom.
2. Open its prefab in Godot, select the root and press **Build**.

Every level and scatter layer using it updates. Without the editor, rebuild a
whole folder's prefabs headless:

```bash
godot --headless --path . --script res://tools/block_prefabs.gd -- maps/blocks/props --force
```

## Making more

| Tool | Writes |
|---|---|
| `tools/block_buildings.gd` | `building_*.map` |
| `tools/block_doodads.gd` | `features/` and `props/` maps (it extends the buildings tool's brush kit) |
| `tools/block_ai_infra.gd` | `solar/`, `compute/` and `landmarks/` maps (it extends the doodads tool) |
| `tools/block_prefabs.gd` | A prefab for each map in a folder |

```bash
godot --headless --path . --script res://tools/block_doodads.gd -- maps/blocks
godot --headless --path . --script res://tools/block_ai_infra.gd -- maps/blocks
godot --headless --path . --script res://tools/block_prefabs.gd -- maps/blocks/features
```

None of them overwrites an existing file without `--force`. Once you've edited
a map in TrenchBroom, the map is the source; the tools exist to make new
variants.

**Walkability:** every ramp is 30° or less, starts on open ground and meets its
landing flush. The climbable pieces were checked by dropping rays along their
routes from the ground to the top.

## The pieces

### Buildings (32 × 24 m lots)

- **house_small, house_terrace:** one- and two-storey houses with ramps to
  their roofs.
- **shop_row:** shops with shutters and an awning, and a long ramp at the back.
- **apartment:** four storeys, with a zig-zag ramp tower to the roof.
- **warehouse:** loading dock and roof ramp.
- **compound:** walled yard with a house and an outbuilding.
- **ruin_shell, ruin_low:** for lots the generator marks as ruined.

### Features

- **rock_outcrop** (20 × 15 m, 6 m tall): a crag. A rock slab climbs to a flat
  shelf 4.25 m up, for overwatch.
- **rock_spire** (11.5 m tall): a leaning weathered pillar.
- **cliff_ledge** (16 m wide, 5 m high): layered, overhanging rock with a flat
  top. A talus ramp at one end climbs to it. Stand it against a slope or use it
  as a plateau's edge.
- **boulder_field** (about 24 m square): 13 boulders.
- **berm** (15 m long, 2 m high): an earth bank with a firing step.
- **trench_revetment** (8 m): plank walls, duckboards and sandbag parapets. Made
  for a `TerrainPath` TRENCH 4 m wide and 2 m deep; place it on the trench
  centreline at ground height.
- **crater_rim** (about 14 m across): a heaved-up rim with scorched slabs, to put
  round a crater stamp.
- **pillbox:** a six-sided bunker, half dug in, with firing slits. An earth
  ramp climbs to the roof.
- **watchtower:** a sandbagged platform 6 m up on legs, with a ramp on posts.
- **container_stack:** three shipping containers.
- **power_pylon** (21 m): a landmark.
- **fuel_tanks:** two tanks in a bund, with pipes and a catwalk.

### Props

- **boulder_a, boulder_b, boulder_c:** 1.1 m, 2.7 m and 4 m.
- **rock_slabs, dirt_mound:** micro-terrain, knee-high or lower.
- **rubble_pile:** concrete chunks with rebar.
- **jersey_barrier, concrete_blocks**
- **sandbag_wall** (4 m), **sandbag_nest** (U-shaped), **hesco_row** (4 baskets)
- **tank_trap:** a Czech hedgehog.
- **barrels, crates**
- **car_wreck, robot_wreck**
- **lamp_post** (7 m), **power_pole** (9 m)
- **concrete_pipes**

### Solar

Panels and mirrors face the prefab's -Z. Turn it so -Z points at the sun.

- **solar_panel_row** (16 m): fixed panels on legs, tilted 25°.
- **solar_tracker_row** (20 m): a single-axis tracker, with the panels turned 30°
  on a torque tube.
- **solar_field_lot** (19 × 28 m, fits a building lot): five panel rows, a cable
  tray and an inverter skid.
- **solar_heliostat:** a 3 m mirror on a pedestal, 3.7 m tall.
- **solar_tower_field** (about 44 m across): a 38 m solar tower with a glowing
  receiver band, ringed by 21 heliostats tipped at it. A plant building stands
  at its foot, with a gap in the ring on the -Z side leading to its door. A landmark.
- **solar_battery_container** (12 m): louvred sides, with air handlers on the roof.
- **solar_inverter_skid** (6 m): two inverter cabinets and a transformer.
- **solar_drone_dock** (4 m pad): a charging mast, with a maintenance drone
  parked on the pad.

### Compute

- **compute_server_rack** (2.1 m): one 42U rack.
- **compute_rack_row** (5.6 m): eight racks on a raised floor under a cable
  tray.
- **compute_racks_toppled:** racks thrown down, a door torn off, cables spilled.
- **compute_cooling_unit** (5.6 m): a chiller with three fans on top.
- **compute_chiller_yard** (20 × 14 m): four chillers on a fenced pad, with
  pipes and pumps. The -X end is open.
- **compute_generator** (12 m): a generator in a container, with exhaust stacks
  and a day tank.
- **compute_transformer:** a substation transformer on a bunded pad.
- **compute_data_hall** (19 × 29 m, fits a building lot): a windowless clad
  hall with louvre bands and status strips.
  - A roller door at the -X end.
  - Cooling plant and a parapet on the roof, 8.25 m up.
  - A 30° ramp up the +Z side climbs to the roof.
- **compute_obelisk** (16.6 m tall, 28 m across with its conduits): a black
  six-sided compute node with glowing seams and cooling fins. It stands on four
  0.25 m steps you can walk up. Three glowing conduits run out across the
  ground.
- **compute_cable_run** (12.5 m): three cables snaking into a junction box.
- **compute_network_cabinet:** a roadside cabinet with a whip antenna.
- **compute_satellite_dish:** a 4 m dish on a pedestal, tilted to face -Z.

### Landmarks

- **landmark_tether_anchor:** the ground anchor of an orbital tether, and the
  reason the valley fortress is there. It stands on a 34 × 48 m pad, the old
  tower's court.
  - A pylon carries a black anchor head 26–48 m up. The tether climbs out of
    it to 240 m, with a climber car partway up.
  - Four guy cables run from the head, over the compounds, to deadman blocks
    100 m out on the diagonals. Flatten the ground under those blocks to the
    pad's height.
  - A gallery ring 9.5 m up is reached by two ramps at 25° from opposite ends
    of the pad. Walk-tested.
  - Used in `maps/valley_basin_level.tscn`.
