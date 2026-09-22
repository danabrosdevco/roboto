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
| `maps/blocks/compute/` | AI compute: server racks, chillers, a generator, a transformer, a data hall, a compute obelisk, monoliths, cables, cabinets, a satellite dish. |
| `maps/blocks/landmarks/` | Set pieces a map is built round: the orbital tether anchor at the heart of the valley basin, and a clock tower and a big wheel, one on each bank of Mutaha. |
| `maps/blocks/industrial/` | The city's industry: warehouses, a sawtooth factory, hangars, a plant office and gate, a car park and a parking deck, container and scrap yards, a coal pile, a smokestack, a blast furnace, silos, a water tower, a gantry crane, a gas holder, a conveyor, a pipe rack, a substation, rail track and wagons, a coal barge, a lock and dam. |
| `maps/blocks/machines/` | Machine tools, a robot arm and a robot assembly line, plant and vehicles: forklift, excavator, bulldozer, racking, steel coils, a workbench, a semi-truck. |
| `maps/blocks/fortifications/` | Hardpoints: a command bunker, gun and mortar pits, hesco walls, T-walls, a hesco sangar, a checkpoint, dragon's teeth, razor wire, a sentry turret's mount, an ammo dump, a floodlight mast. |
| `maps/blocks/bridges/` | Bridges built off `long_bridge.map`: short to very long, two-lane and highway, a footbridge, two trusses, a causeway, a shelled bridge, a gorge bridge and a stone humpback. The squad can walk over every one. |
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
- **Ground detail can be built without collision.** `no_collision()` in the
  tools puts every brush after it into a `func_detail_illusionary` entity
  instead of worldspawn: FuncGodot gives it a mesh and no collision shape. It
  is for things the squad should walk over rather than into — rail track is the
  one that uses it. In TrenchBroom, select the brushes and move them to a
  `func_detail_illusionary` entity to do the same by hand. Nothing tall belongs
  in one: a wall with no collision is a hole the squad walks through. Note that
  a navmesh baked from *mesh instances* still sees the geometry; only the
  levels that bake from static colliders are spared it.
- **Nothing tall rests on a top face.** The navmesh baker sees surfaces, not
  solids. The top face of a brush under (or inside) another solid 1.5 m or
  taller bakes as a floor within that solid, sealed where the squad can never
  get to it. An order can still snap to that floor. Let stacked pieces meet
  under something shallower, as the bridges' piers meet their 1 m deck, or
  build them as one brush. `tools/test_bridges.gd` checks the bridges for this.

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
| `tools/block_industrial.gd` | `industrial/`, `machines/` and `fortifications/` maps, the clock tower and big wheel in `landmarks/` and the monolith in `compute/` (it extends the AI-infra tool). Name pieces after the folder to write only those. |
| `tools/block_bridges.gd` | `bridges/` maps (it extends the industrial tool) |
| `tools/block_prefabs.gd` | A prefab for each map in a folder |

```bash
godot --headless --path . --script res://tools/block_doodads.gd -- maps/blocks
godot --headless --path . --script res://tools/block_ai_infra.gd -- maps/blocks
godot --headless --path . --script res://tools/block_industrial.gd -- maps/blocks
godot --headless --path . --script res://tools/block_bridges.gd -- maps/blocks
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
- **compute_monolith** (7 m): a tapering black slab on a footing, with a line
  of light down each broad face and a crown of light. The broad faces face the
  prefab's ±Z. On Mutaha, six ring the obelisk and more stand down the
  boulevard's median.
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
- **landmark_clock_tower** (51 m to the beacon on its spire): the landmark for
  Mutaha's west bank. It stands on a stepped plaza 18 m square. The steps are
  0.25 m, so the plaza can be walked onto from every side.
  - A brick shaft with stone quoins, bands and slit windows. The door faces
    the prefab's -Z.
  - A clock face on each side, 29 m up. The faces use `snow_1`, the lightest
    texture in the set, on a dark ring. At the stage's own shade they could
    not be seen from the street.
  - An open belfry with its bell, and a green copper spire.
  - Tall and square where the wheel is round, so the two tell the player which
    bank they are on.
- **landmark_ferris_wheel** (48 m to the top of its rim): the landmark for
  Mutaha's east bank.
  - Two rims turn on a hub 26 m up between two A-frames. Eighteen cabins still
    hang and two lie fallen at its foot, beside a ticket booth.
  - The wheel faces the prefab's ±Z. Its feet stand 27 m apart along its X.
  - At 36 m only its top cleared the rooftops across the river, so it was
    raised to 48 m.
  - The boarding platform is 1.5 m up. The bottom cabin hangs over its middle,
    so each half has its own ramp.
  - Both ramps climb the sides, square to the wheel. Along the wheel, the next
    cabin up hung over the ramp with too little headroom to walk up.
  - The squad reaches both halves on Mutaha's baked navmesh.

### Industrial

Fronts face the prefab's -Z; ramps and docks are at the back or sides. The
climbable ones were checked on the baked navmesh of `maps/pittsburgh_level.tscn`:
the squad reaches every roof and deck listed here.

- **warehouse_long** (20 × 48 m, 9 m): clad walls on a block base, six dock
  doors behind a loading dock 1.25 m up with a canopy and a ramp at its end,
  skylights. A 28° ramp up the +X side reaches the roof.
- **sawtooth_factory** (24 × 30 m): brick, five north-light teeth glazed toward
  +X, brick gables, a loading door, and a chimney.
- **hangar_arch** (26 × 36 m, 11 m): an arched shell with a closed back wall and
  the front open, door leaves slid aside. Empty inside.
- **hangar_shed** (20 × 30 m): portal frames under a pitched roof, cladding to
  3 m with a gap in each side, open ends, an overhead crane. Machine tools fit
  under it.
- **plant_office** (12 × 18 m, two storeys): ribbon windows, an entrance canopy,
  a sign frame. A ramp up the +X side reaches the roof.
- **gatehouse**: a guard booth, brick piers, a boom and a half-open sliding gate
  on a road along Z, fence off both sides.
- **parking_lot** (24 × 32 m, fits a lot): 24 marked bays, wheel stops, kerbs,
  three lamps, a pay station, five cars.
- **parking_deck** (25 × 37 m): ground, a deck at 3.5 m and a roof deck at 7 m,
  joined by two 11° ramps. Six cars.
- **container_yard** (24 × 32 m): containers stacked one to three high in two
  blocks, and a steel ramp onto one of them for a lookout.
- **scrap_yard** (26 m): scrap heaps, crushed cars, a material handler with a
  grab, sheet fencing.
- **coal_pile** (24 m across, 3.5 m high): a stockpile you can walk up, fed by a
  radial stacker.
- **smokestack** (45 m): brick, banded, a light at the top. A landmark.
- **blast_furnace** (about 53 × 41 m, 44 m tall): the furnace on its cast house,
  three stoves, the uptakes and downcomer to a dust catcher, and the skip
  incline. A 27° ramp reaches the cast house floor 6 m up. A landmark.
- **silos**: four 25 m silos, a head house, the elevator leg and a truck shed.
- **water_tower** (26 m), **gantry_crane** (29 m span), **gas_sphere** (14 m),
  **conveyor** (30 m, 18°), **pipe_rack** (25 m), **substation** (fenced yard).
- **rail_track** (24 m, square ends so lengths butt), **rail_boxcar**,
  **rail_tank_car**, **rail_gondola**: the wagons sit on the track's rails
  when both are placed at the same origin. **The track has no collision** —
  the squad walks over it, not into it. The wagons keep theirs; they are cover.
- **coal_barge** (37 × 10.5 m): set its origin at the water line. The hull goes
  down to the river bed so nothing walks under it.
- **lock_dam** (44 m deck): piers, gates, hoist houses and a control tower, the
  deck walkable across a channel with cover on its upstream side. Set its
  origin at bank height and flatten the ground under each abutment to it.

### Machines

- **lathe**, **milling**, **press** (6.5 m), **cnc**: machine tools in machine
  green.
- **robot_arm**: a six-axis robot at its cell. **assembly_line** (16 m): four
  robots building war robots on a conveyor.
- **forklift**, **excavator**, **bulldozer**, **semi_truck** (18 m): these lie
  lengthwise along the prefab's Z (built along TrenchBroom's X), cab or blade
  toward -Z.
- **pallet_rack**, **steel_coils**, **workbench**.

### Fortifications

- **command_bunker** (12 × 16 m block, 22 × 24 m with its earth banks): firing
  slits, a blast door at the back and a roof with a parapet, cupola and mast.
  A ramp up the back reaches the roof.
- **gun_emplacement** (9 m ring, gun facing -Z), **mortar_pit** (6.4 m ring with
  its ammunition): open at the back. The mortar pit is empty in the middle;
  the mortar itself is not part of the block.
- **hesco_wall** (12 m, two baskets high with a return), **t_walls** (five, one
  slumped).
- **hesco_sangar**: a two-high ring of baskets round a room, a deck on top
  behind a sandbag parapet, a tin roof, and a 2.6 m ramp up one side.
- **checkpoint** (24 m along a road on X): a chicane of jersey barriers, a spike
  strip, a boom, a guard post, T-walls, a floodlight.
- **sentry_turret**: the mount only, with no gun on it. A concrete base, a pylon
  with its mounting plate 2.4 m up, and a power box on a cable.
- **dragon_teeth**, **razor_wire** (10 m), **ammo_dump** (under a camouflage
  net), **floodlight_mast**.

Loose heaps built with the tools' `heap()` keep sharp breaks in slope on
purpose. FuncGodot drops any corner where the three faces meeting there are
within a few degrees of one plane, so a smooth dome builds with faces missing.

### Bridges

Built off `long_bridge.map`, the hand-made bridge `concrete_bridge.tscn` comes
from. Most keep its section: a concrete deck between side walls, a girder
below each and a parapet above, with an earth ramp at each end.

**Placing one.** Each runs along the prefab's Z. Its origin is the middle of
the span, at the height of the ground at the ramp feet.
- The ramps climb at 1 in 3 and meet the deck level with it.
- Their surfaces run on 0.5 m below the origin before they stop. A bank
  anywhere from 0.5 m below the origin upward buries the foot, leaving no lip
  to climb. Set a bridge no higher than its banks.
- `long_bridge.map`'s own ramps stop 0.5 m above its origin. Sink it at least
  that far into its banks, or its ramps end in a step the squad cannot climb.

**In the levels.** Mutaha's six crossings and Pittsburgh's seventeen are these
prefabs, so the terrain's own `bridge_blockouts` is off in both — leave it off,
or a plain deck builds inside every bridge. Each sits at the middle of its
crossing, turned along the line and sunk by its deck height, so the road meets
the ramps rather than the deck.

**Checked.** `tools/test_bridges.gd` bakes a navmesh round each prefab on two
banks with a river under the middle of the span, with the banks level with
the origin and again 0.45 m below it.
- The squad must walk onto the deck from both ends; on the highway, onto both
  carriageways.
- Every raised patch of navmesh on a bridge must be reachable.
- Run it after editing a bridge.

`tools/test_bridge_spacing.gd` checks the other half: no two bridges in any
level may come within 20 m of each other, measured between their decks rather
than their origins. Pittsburgh once had sixteen bridges that broke that rule
and eight pairs that ran through each other, and every one of them passed the
walkability checks above — walking a deck says nothing about whether the deck
is inside another bridge. Run it after placing bridges in a level.

Spans are between the abutments; the overall length includes the ramps.

- **bridge_short:** 12 m span, 29.5 m overall, 8 m wide, deck 2.25 m up.
- **bridge_medium:** 30 m span, 55 m overall, 10 m wide, 3.5 m up. The
  original's section, shorter.
- **bridge_long:** 72 m in three spans on wall piers, 100 m overall, 4 m up.
- **bridge_very_long:** 128 m in four spans, 162 m overall, 5 m up, for the
  widest rivers.
- **bridge_wide:** 36 m span, 61 m overall, two lanes 16 m wide, with road
  paint and four lamps.
- **bridge_highway:** 84 m on column piers, 121 m overall, 24 m wide, 5.5 m
  up. Two carriageways either side of a median barrier, which stops at the
  ends of the deck so they join on the ramps. Lane lines and eight lamps.
- **bridge_foot:** a steel footbridge 3 m wide over 30 m on one column, 56 m
  overall. Railed, with railed concrete ramps.
- **bridge_truss:** a steel Pratt through-truss, 48 m span, 70 m overall, 8 m
  wide. Braced overhead 7 m up.
- **bridge_truss_long:** the same truss over 72 m in twelve panels, 94 m
  overall and 9 m wide, for a river the 48 m one cannot reach across.
- **bridge_causeway:** 48 m on culvert walls, 59.5 m overall, 8 m wide and
  1.25 m up, with kerbs and bollards.
- **bridge_damaged:** 40 m span, 65 m overall, shelled.
  - A hole through one side of the deck, with slabs hanging into it.
  - Rubble, scorching, a burnt car and a barrier knocked askew.
  - The other side is kept 5.5 m clear past the hole, so it still carries the
    squad across.
- **bridge_gorge:** 48 m span, 56.5 m overall, 8 m wide. The deck is 0.75 m
  above the rims, on two tapered piers standing from 18 m down. Set the origin
  at rim height.
- **bridge_arch:** an old stone humpback, 30 m overall and 6 m wide. One 12 m
  arch, and the road climbing 1 in 4 to a crown 3.25 m up between brick
  parapets.
