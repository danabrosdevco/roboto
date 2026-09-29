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
| `maps/blocks/estates/` | The big housing: five- to eight-storey slabs, towers, courtyard and U blocks, a deck-access block, a broken slab, a collapsed corner, an unfinished frame and a market hall. Each takes two or four lots. |
| `maps/blocks/features/` | Set pieces placed by hand: rocks, a cliff ledge, berms, trench lining, a crater rim, a pillbox, a watchtower, containers, a pylon, fuel tanks. |
| `maps/blocks/props/` | Small pieces for scattering or placing by hand: boulders, rubble, barriers, sandbags, hesco, tank traps, drums, crates, wrecks, poles, pipes. |
| `maps/blocks/solar/` | AI-built solar: panel rows, a tracker, a field the size of a lot, heliostats and a solar tower, battery containers, inverters, drone docks, and canopy arrays big enough to walk under. |
| `maps/blocks/compute/` | AI compute: server racks, chillers, a generator, a transformer, a data hall, a compute obelisk, monoliths, cables, cabinets, a satellite dish. |
| `maps/blocks/landmarks/` | Set pieces a map is built round: the orbital tether anchor at the heart of the valley basin, and a clock tower and a big wheel, one on each bank of Mutaha. |
| `maps/blocks/industrial/` | The city's industry: warehouses, a sawtooth factory, hangars, a plant office and gate, a car park and a parking deck, container and scrap yards, a coal pile, a smokestack, a blast furnace, silos, a water tower, a gantry crane, a gas holder, a conveyor, a pipe rack, a substation, rail track and wagons, a coal barge, a lock and dam. |
| `maps/blocks/machines/` | Machine tools, a robot arm and a robot assembly line, plant and vehicles: forklift, excavator, bulldozer, racking, steel coils, a workbench, a semi-truck. |
| `maps/blocks/fortifications/` | Hardpoints: a command bunker, gun and mortar pits, hesco walls, T-walls, a hesco sangar, a checkpoint, dragon's teeth, razor wire, a sentry turret's mount, an ammo dump, a floodlight mast. |
| `maps/blocks/bridges/` | Bridges built off `long_bridge.map`: short to very long, two-lane and highway, a footbridge, two trusses, a causeway, a shelled bridge, a gorge bridge and a stone humpback. The squad can walk over every one. |
| `maps/blocks/causeway/` | A derelict highway in 48 m sections that butt end to end, with an approach ramp and three states of disrepair. For a crossing too long to be one bridge. |
| `maps/blocks/fortress/` | Machine-built fortification: the citadel (a 260 m tower inside a 200 m walled fort, with the pit down to its basement), a keep on its own podium, and wall and gate sections for outworks. |
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
- **One entity, one mesh.** FuncGodot builds a mesh per entity, and this
  project renders in GL compatibility, which lights at most eight lights per
  mesh. A big piece that needs lamps inside it has to be split: `entity(
  "func_detail")` in the tools starts a new solid entity, and `fort_tower`
  uses one per floor so each of its twelve data halls can be lit. The cost is
  one concave collision shape per entity instead of a convex hull per brush,
  which for interior floors is the better shape anyway.
- **Nothing knee-high collides.** A stone, a slab or a brick lying on the
  ground is texture, not cover. Give it a collider and the navmesh bake
  punches a hole where it stands and fans triangles across the whole field
  round it, for an obstacle the squad would have stepped over. `prop_rock_slabs`
  is the example: it builds with no collision at all. The line is intent, not
  height — `prop_sandbag_nest` is shorter than `prop_boulder_a` and is cover.
- **A scatter layer's collider has nothing to do with its props.** The layer
  draws them as MultiMeshes and puts a cylinder of `collision_radius` round
  each one, and that cylinder is what the navmesh sees. It has to fit inside
  the smallest prop the layer spreads, at the smallest scale it spreads it;
  `tools/test_scatter.gd` fails the build if it does not. A layer that spreads
  ground detail should have no collider at all, as `scatter_micro_terrain` has
  none.
- **Ground detail can be built without collision.** `no_collision()` in the
  tools puts every brush after it into a `func_detail_illusionary` entity
  instead of worldspawn: FuncGodot gives it a mesh and no collision shape. It
  is for things the squad should walk over rather than into — rail track is the
  one that uses it. It is a line in a piece, not a switch: everything
  after it in THAT piece is mesh only, and every tool resets it between pieces
  — without that reset one piece calling it turned every piece after it in the
  run into a ghost, which is how the props lost their collision for an hour. In TrenchBroom, select the brushes and move them to a
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
| `tools/block_estates.gd` | `estates/` maps — the big housing blocks (it extends the doodads tool) |
| `tools/test_block_reach.gd` | nothing — it reports which decks a piece grows navmesh on and whether the squad can get to any of them |
| `tools/block_doodads.gd` | `features/` and `props/` maps (it extends the buildings tool's brush kit) |
| `tools/block_ai_infra.gd` | `solar/`, `compute/` and `landmarks/` maps (it extends the doodads tool) |
| `tools/block_industrial.gd` | `industrial/`, `machines/` and `fortifications/` maps, the clock tower and big wheel in `landmarks/` and the monolith in `compute/` (it extends the AI-infra tool). Name pieces after the folder to write only those. |
| `tools/block_bridges.gd` | `bridges/` maps (it extends the industrial tool) |
| `tools/block_fortress.gd` | `causeway/` and `fortress/` maps (it extends the bridges tool) |
| `tools/block_homebase.gd` | `maps/depot/depot_level.map` — a whole level, not a block (it extends the fortress tool) |
| `tools/block_arena.gd` | `maps/proving/proving_level.map` — a whole level, the arena, rebuilt (it extends the fortress tool) |
| `tools/block_ground.gd` | `ground/` maps — micro-terrain (it extends the fortress tool) |
| `tools/block_prefabs.gd` | A prefab for each map in a folder |

```bash
godot --headless --path . --script res://tools/block_doodads.gd -- maps/blocks
godot --headless --path . --script res://tools/block_ai_infra.gd -- maps/blocks
godot --headless --path . --script res://tools/block_industrial.gd -- maps/blocks
godot --headless --path . --script res://tools/block_bridges.gd -- maps/blocks
godot --headless --path . --script res://tools/block_fortress.gd -- maps/blocks
godot --headless --path . --script res://tools/block_homebase.gd -- maps
godot --headless --path . --script res://tools/block_arena.gd -- maps
godot --headless --path . --script res://tools/block_ground.gd -- maps/blocks
godot --headless --path . --script res://tools/block_estates.gd -- maps/blocks
godot --headless --path . --script res://tools/block_prefabs.gd -- maps/blocks/features
```

None of them overwrites an existing file without `--force`. Once you've edited
a map in TrenchBroom, the map is the source; the tools exist to make new
variants.

**Walkability:** every ramp is 30° or less, starts on open ground and meets its
landing flush. The climbable pieces were checked by dropping rays along their
routes from the ground to the top.


## Props the navmesh cannot read

Two shapes a prop can have that the navmesh gets wrong, and one helper that
fixes both. Measured, not guessed: `tools/test_prop_nav.gd` stands every prop
on a flat floor, bakes with a level's own settings, and reports how much
walkable area ended up on top of it and how wide a hole it carves. It needs a
renderer, so it opens a window for a few seconds:

```bash
godot --path . --script res://tools/test_prop_nav.gd
```

- **A GENTLE SLOPE IS WALKABLE.** Recast walks anything under 45°, and rubble
  heaps at about 30°. `prop_rubble_pile` grew navmesh up its own sides and
  left an island on top that nothing could climb to, and carved only 2.75 m of
  its 4.9 m footprint, so the squad walked into the skirt.
- **A BATTERED FOOT IS A TOEHOLD.** A jersey barrier is widest at the ground
  with a ledge 0.08 m up — inside the baker's 0.25 m climb — so the mesh crept
  onto the barrier's toe and bodies caught on the flare above it instead of
  walking round.

`clip_block(centre, half, height)` in `block_buildings.gd` is the fix. It
writes brushes textured `special/clip`, which FuncGodot drops from the visual
mesh and keeps for collision: solid, never drawn. Give the prop one of those
for its collision and build the visible shape after a `no_collision()` call.

**It is slatted, and that matters.** A flat top is walkable however high it
is, so a plain box grows an island of its own — 13.5 m² of it on the rubble
pile. Recast erodes the walkable area by the agent's radius, so nothing
narrower than twice that survives: slats 0.25 m wide at a 0.9 m pitch erode
away on top and in the gaps, and the gaps are too narrow to walk into. Two
earlier attempts did not hold: teeth 0.3 m tall on top of a solid box read as
climbable, because the baker quantises the climb to whole cells and at a
0.25 m cell 0.3 m is one cell like 0.25 m is; and 0.4 m slats are two cells
wide, which erodes to a sliver rather than to nothing.

Where a piece is built inside a bigger one — `jersey_at()` in
`block_industrial.gd` — `no_collision()` is not available, because it would
take the rest of the piece with it. There, wrap the shape in a clip box a
couple of centimetres larger instead: the toe ends up buried inside solid
geometry with no headroom above it, so no walkable span forms on it.

**A FLAT TOP IS WALKABLE TOO**, and that is the third fault. Seven more props
grew a small island of navmesh on their own tops, 0.6 to 2.9 m² of it, at
heights from 0.4 m to 3.0 m — nothing could climb to any of it. Where the art
allows, the cure is `bevel_top()`: pull the top face in and lift it, so the
faces round it are past 45° and what is left in the middle is narrower than
twice the agent's radius and erodes away. The bevel has to rise more than it
insets or its own faces are walkable.

- **`prop_concrete_blocks`** bevelled 0.4 m in over a 0.5 m rise: 2.9 → 0.2 m².
  Cast concrete with a chamfered edge is what it should have looked like.
- **`prop_hesco_row`** crowned 0.42 m in over 0.5 m: 1.8 → 0 m². Four hescos
  in a row make one flat top 1.06 m across and 4.4 m long, and an overfilled
  gabion heaps over its frame anyway.
- **`prop_boulder_c`** given 26 facets instead of 16 and half a metre more
  crown: 1.2 → 0.4 m². At sixteen the hull came out with one top facet wide
  enough to carry navmesh.
- **`prop_dirt_mound`** is the rubble pile's fault, not this one — earth heaps
  at about 20° and the mesh climbed the dome, 2.3 m² of it, connected to the
  floor so no bake setting would cull it. It has a `clip_block` now: 0 m².

`prop_car_wreck`, `prop_robot_wreck` and `prop_concrete_pipes` keep small
islands (0.6, 0.8 and 0.9 m²) and were left alone: a car roof and a fallen
torso ARE flat, and narrowing the car's cabin made it worse rather than better
— 0.6 m² became 1.5 m², because what the cabin stopped covering was the body
deck, which is flatter and wider than the roof ever was.

**At a level's own settings nothing is left.** The sweep above runs at
`region_min_size` 2 to show the raw shape of the problem; every level bakes at
4, which culls an isolated region under about a square metre, and at 4 every
one of the nineteen props reports 0 m². Run it both ways when judging a new
piece — the raw number is the one that tells you whether the prop is right.


## Micro-terrain (`maps/blocks/ground/`)

Relief you build rather than paint, written by `tools/block_ground.gd`.

Flattish ground is what the squad can fight on and painted hills are what it
cannot, so every level ends up with a floor that is correct and dead — the
heliostat field worst of all, a thousand identical mirrors on a billiard
table. These sit in between: low enough to keep the navmesh, shaped enough
that the ground has a horizon.

**The rules every piece here keeps.**

- Slopes 20° or less. The baker walks up to 45, but a body that has to steer
  while climbing wants far less than its limit, and a rover is not a goat.
- No step over 0.2 m. The navmesh climbs 0.25 m and anything near that is a
  lip the squad catches on.
- Nothing over 1.2 m. Past that it is cover, and cover belongs in `props/`
  where it gets built with vertical sides.
- Every edge meets the ground flush. A slab dropped on a field with a square
  edge is a 0.2 m kerb all the way round it.

| piece | size | what it is |
|---|---|---|
| `ground_swell` | 30 × 22 m, 0.72 m | a rise you cannot see over the far side of |
| `ground_berm` | 32 m long, 0.72 m | a graded bank: walk over it or fight behind it |
| `ground_berm_ring` | 26 m across | a ring of spoil with a dished middle |
| `ground_apron` | 16 × 12 m, 0.6 m | a gentle climb onto a kerbed pad |
| `ground_spoil` | 6 × 4.6 m, 1.1 m | a heap. The one piece here you go ROUND |
| `ground_pad` | 12 m square | concrete settled into four slabs, skirted in grit |
| `ground_washout` | 26 × 14 m | a channel between two low banks |
| `ground_track` | 30 m long, 0.16 m | worn ruts. The smallest and the most useful |

**Check every one of them with the nav test.** `tools/test_prop_nav.gd` reads
the other way round for this family: a micro-terrain piece should come out
with a WALK close to the straight-line distance, meaning the squad goes over
it rather than round, and no `SPLIT IT`.

```bash
FOLDER=ground godot --path . --script res://tools/test_prop_nav.gd
```

Three ways a piece here fails, all found by that test and all worth knowing:

- **A tread narrower than twice the agent radius erodes to nothing.** The
  washout's banks were first built in four steps across 1.4 m — 0.35 m treads
  — and came out an unwalkable staircase that cut the map in two.
- **Stacking courses from a common edge leaves a wall on that side.** Built
  from the inner edge the washout had a half-metre face along the channel;
  from the outer edge it had the same face on the field side, and the crossing
  went 43 m round rather than 26 m over. Each course is a trapezoid about the
  crest, so both faces are steps.
- **A hull's skirt is a rim of slivers.** A dome meets the ground at a knife
  edge the baker cannot walk; stepped boxes meet it flush. That is why
  `_terrace()` builds rings of boxes rather than calling `mound()`.


## The pieces

### Buildings (32 × 24 m lots)

- **house_small, house_terrace:** one- and two-storey houses with ramps to
  their roofs.
- **shop_row:** shops with shutters and an awning, and a long ramp at the back.
- **apartment:** four storeys, with a zig-zag ramp tower to the roof.
- **warehouse:** loading dock and roof ramp.
- **compound:** walled yard with a house and an outbuilding.
- **ruin_shell, ruin_low:** for lots the generator marks as ruined.

### Estates (two or four lots)

The small buildings top out at four storeys on a 32 × 24 m lot, so a town built
only from them is a field of sheds you can see straight across. These are the
blocks that break a sightline. **Each one costs the lots it covers** — whatever
places one has to leave the neighbours empty — and the sizes are set by the
sketch grid, where two lots plus the street between them is 73 m one way and
57 m the other:

| Kind | Lots | Built extent | Pieces |
|---|---|---|---|
| wide | 2 × 1 | up to 72 × 24 m | slab_five, slab_stepped, slab_broken, gallery_block, slab_dogleg, podium_row |
| deep | 1 × 2 | up to 32 × 56 m | twin_tower, point_tower, courtyard_wing |
| big | 2 × 2 | up to 72 × 56 m | courtyard_block, u_block, microdistrict, slab_pair_bridge, frame_shell, collapsed_corner, market_hall |

- **slab_five** (5 storeys, 18.8 m): 68 m of slab with two undercrofts through
  the ground floor and a gallery along the back. Ground → gallery at 8.3 →
  roof.
- **slab_stepped** (3, 5 then 7 storeys): three roofs at 11.8, 18.8 and 25.8 m,
  each reached from the one below. The best single piece for breaking a long
  street: from any angle something is in the way.
- **slab_broken:** the same slab with an 18 m bay brought down. Rubble climbs
  to the second floor and a fallen slab carries on to the third, so the breach
  is the way in and the two halves are cleared separately.
- **gallery_block** (4 storeys): deck access — open walkways down the whole
  back at 4.8 and 8.3 m, and the roof at 15.3. Three levels that all look down
  on the street.
- **slab_dogleg:** two wings offset across the street line with a stair core in
  the elbow. Gives a street a corner instead of a flat run.
- **podium_row:** two storeys of shops with a four-storey bar set back on their
  roof. The podium roof is a 71 × 16 m terrace behind a parapet.
- **twin_tower:** two seven-storey towers on a shared two-storey podium, the
  podium roof a walled yard between them.
- **point_tower:** eight storeys, 30 m to the parapet — the tallest piece here
  that is not a landmark. Walkable skirt roof at 8.3 m wrapped round its foot.
- **courtyard_wing:** an L round a yard with one way in, and a switchback ramp
  up the yard to the roof at 15.3 m.
- **courtyard_block:** a perimeter block round a 28 × 44 m courtyard you can
  only reach through an archway, with a gallery ring at 8.3 m looking into it.
- **u_block:** a U with a six-storey back and four-storey arms round a yard
  that opens south.
- **microdistrict:** two slabs at right angles with a single-storey shop block
  between them — the buildings make the space rather than filling it.
- **slab_pair_bridge:** two six-storey slabs facing each other, joined by a
  bridge at the fourth floor that lands on a gallery each side, over a deck at
  4.8 m.
- **frame_shell:** columns, floors and a little shuttering, four decks of it
  and no walls. You can see through it and still not shoot through it, which
  nothing else here does.
- **collapsed_corner:** one corner pancaked into a ramp of its own floors, up
  to the third storey. A way in that is not a staircase.
- **market_hall:** 46 m of clear-span roof at 12.3 m with a six-storey bar
  behind it. The biggest single piece of high ground in the kit.

**What you can climb.** Every deck called walkable above is reached by a ramp
of 30° or less. The TOP of a tall mass usually is NOT: a squad on a 30 m roof
sees the whole town, which is the opposite of what these are for.

**THREE RULES A RAMP HAS TO KEEP**, all three learned the hard way, and all
three invisible in the editor — `tools/test_block_reach.gd` is what finds them:

1. **A ramp never runs under the deck it climbs to.** Headroom at the foot,
   none at the top, so the baker eats the last third of it and leaves a
   walkway you can see and cannot reach. Put the ramp beside the deck or over
   it, never beneath it.
2. **A ramp needs a flat landing at each end that shares an EDGE with what it
   joins.** A sloped surface meeting a flat one at the same height touches it
   along one line, and a line is a corner, not an edge: two regions that never
   join. The exception is a ramp running head-on into a big flat deck, where
   the deck's own edge is the landing — a pad there only roofs the ramp below.
3. **The parapet breaks where the ramp ARRIVES.** A landing against a walled
   deck is a landing against a wall. Half the gaps in this family were left
   where an earlier version of the ramp used to be.

**And a floor band is a RING, never a slab.** A slab buried in a solid mass is
invisible and looks like nothing, and it is a floor to the navmesh baker, which
rasterises surfaces rather than solids: the top of every buried slab came out
as a 670 m² deck inside the building. Five storeys of that is four phantom
decks per block. Recast also merges coincident faces, so a roof slab with a
tower standing exactly on it reads as open floor with the whole inside of the
tower as headroom.

`test_block_steps.gd FOLDER=estates`: one 0.09 m riser sample across the
sixteen. `test_block_reach.gd FOLDER=estates`: every deck a piece's notes call walkable
is reachable, with three known exceptions — `courtyard_block`'s roof,
`slab_pair_bridge`'s 15.3 m galleries and `slab_stepped`'s top roof. Each of
those pieces says so in its own comment. Everything else the test still lists
is a tall mass's roof that is meant to be out of reach, or rubble.

**The plinth bank is the thing to get right.** These started with a 1 m flare
under a 1 m rise — a 45° skirt, which the navmesh baker walks and a body
cannot, so fifteen of the sixteen had the squad standing at the foot of a bank
the mesh said they were on. `pad()` in the tool flares 2 m and insets the
plinth to keep the extent, which is the buildings tool's 27°.

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
- **crater_rim** (about 14 m across): a heaved-up rim with scorched slabs, to
  put round a crater stamp. **Two of its eleven slabs are deliberately absent**,
  leaving a 2.6 m breach on roughly opposite sides — without them the ring is
  continuous and 0.6 to 1.2 m tall, and `move_and_slide` has no step-up, so a
  player who walks into the crater cannot get out. The navmesh does not show
  this: it bridges a 0.5 m climb and reports the crater fine. Check it with
  `tools/probe_crater_escape.gd`, which walks the collision surface instead.
  The loose slabs are kept out of the breach arcs for the same reason — 0.3 m
  is still a wall to a body that cannot step up.
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
  ground; those are **mesh only**, so the squad walks over them. At 0.5 m they
  are taller than the 0.25 m the baker climbs and taller than the 0.45 m a body
  steps over, so with collision each one cut the ground round the obelisk into
  wedges and bodies caught on them walking in. Its collider is therefore 15 x
  13 m, not the 24 x 28 m it looks.
  **Its mass sits 3.9 m west of its origin** (the conduits are not symmetrical),
  which matters when centring one on something.
- **compute_monolith** (7 m): a tapering black slab on a footing, with a line
  of light down each broad face and a crown of light. The broad faces face the
  prefab's ±Z. On Mutaha they ring the obelisk and line the island's avenue.
- **compute_cable_run** (12.5 m): three cables snaking into a junction box.
- **compute_network_cabinet:** a roadside cabinet with a whip antenna.
- **compute_satellite_dish:** a 4 m dish on a pedestal, tilted to face -Z.

### Landmarks

- **landmark_relay_dish** (24 m bowl, **25.3 m to the top of the rim**): a
  communications dish on a slewing mount, for a listening post or a hilltop
  station. Footprint 24 × 20 m, collision the same — the bowl overhangs its
  pedestal, so space it off its FULL extent and not off the drum at the bottom.
  - The boresight points along the map's **+X in Quake, which is +Z in Godot**,
    tilted 35° up. Yaw it to face the approach: the bowl reads as a landmark
    from in front and as a grey ellipse from behind.
  - 25.3 m is a deliberate number. A flat hilltop hides itself — from a station
    250 m out and 50 m below, the plateau's own brow cuts the line and anything
    standing up there needs about 23 m to clear it. A watchtower is 8.7 m and a
    power pylon 21.8 m; this is the piece that reads from the valley floor.
  - The ribs, rim and feed quadpod are **mesh only**. They are 0.2 m bars 20 m
    in the air and every one would otherwise carry its own collision hull for
    nothing.
  - The plinth is 0.4 m on purpose. A step nothing can climb, in the middle of
    a compound, is a collar of unwalkable ground round the best cover on it.
  - Used in `maps/ascent_level.tscn`, where it replaced a reused
    `compute_obelisk`.

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


### The solar plant (`maps/blocks/solar/`)

The mirror field had the mirrors and the tower and nothing to say what they
were FOR, and a hundred identical heliostats read as wallpaper. Six pieces for
both problems:

- **solar_salt_tanks:** two insulated tanks on a kerbed bund with the pipe
  bridge between them, 42 m across and 15 m tall. A tower plant stores its
  heat as molten salt — cold tank, hot tank, receiver moving it between them —
  so this is the second landmark on a heliostat map after the tower.
- **solar_steam_block:** turbine hall with the air-cooled condenser bank
  beside it. A plant in a desert cannot spare water to condense with, so it
  blows air through a ridge of finned tube: the tallest thing on site after
  the tower.
- **solar_wash_bay:** a drive-through frame with brush heads and a water tank
  on a stand. A field of mirrors in a desert is a field of mirrors under dust.
- **solar_heliostat_wrecked:** pylon snapped at the pedestal, mirror face-down
  and broken across its frame.
- **solar_heliostat_stowed:** parked face-up, the way a field stows in a storm.
- **solar_mirror_rack:** spare mirrors on edge in a steel frame, two broken
  ones stacked flat, a crate of fixings.

The last three are the ones that matter for a field: one wreck in twenty-two
and one stowed in eleven is enough to stop a hundred and twenty mirrors
reading as a pattern, and both cost nothing to place because they share the
heliostat's footprint.

### The causeway

For water too wide to bridge in one piece: the old highway, carried over it in
**48 m sections that butt end to end**. Lay a `causeway_ramp`, then a section
every 48 m along the same line, then another ramp turned to face back.
`tools/test_causeway.gd` lays a whole one and walks it bank to bank.

The deck is 16 m wide and 4 m up, on column piers. **There is no median and no
kerb across it** — a barrier down the middle would cut the deck into two lanes
the squad could not cross between. The only thing on it is paint.

- **causeway_span:** sound deck, three piers.
- **causeway_span_cracked:** settled over its middle pier — the deck dips 0.2 m
  and comes back, which reads as subsidence and the navmesh does not notice.
- **causeway_span_broken:** the northern half of the deck is gone over 20 m,
  leaving a 7 m lane on the south side. The lane is flat and clear.
- **causeway_ramp:** 24 m of embankment climbing to the deck at 1 in 6.
- **causeway_pier:** one pier and a stub of deck, for the carriageway that
  came down. Put a line of these alongside and the crossing reads as half of
  what it was.

**The wreckage does not collide.** Every hanging slab, fallen rail and piece of
rubble is built after `no_collision()`, so the deck the squad walks is flat and
empty. Keep it that way — this is a map made of one long walk.

### The fortress

Machine work, built to last, in the manner of the tether anchor: clean faces,
lit seams, nothing improvised.

- **fort_keep:** the whole fort, 96 m square. Its podium is the flat ground —
  4 m up, with a 16 m ramp at 1 in 6 to the gate and another at the back. Four
  corner bastions, a 14 m gate, and down the middle of the yard the ramp into
  the pit, 20 m wide at 1 in 6, ending at the portal into the data halls. A
  30 m mast over the head house is what you see from across the water.
  - **The rim is one brush from the ground to the top of the parapet**, never a
    wall standing on the podium's top face — see the convention above.
  - Everything is wide. The yard is clear, the pit is 20 m across and the gate
    is 14 m: the rover and anything larger gets down there without a thought.
 m to the tip of the relay on a 49 m shaft, standing
  in a walled fort 200 m square. Ribbed the whole way up and set back twice,
  after the courts and jails built that way, with nothing between the ribs.
  - **The way through it is the mission.** Up 60 m of ramp outside the west
    wall to the gate; the length of the yard, under the walls and the four
    bastions, and round the tower — the pit is on the FAR side from the gate,
    so the yard is crossed rather than skirted; DOWN the pit, 24 m wide at
    1 in 6, to the portal in the tower's east face; then UP twenty-four data
    halls from the basement to 138 m.
  - **The uplink is on the crown**, between the horns, and it is plant rather
    than an aerial: a clad core 16 m square and 100 m tall carrying bank
    after bank of heat exchanger fins — a data centre is mostly a machine for
    moving heat — with dish arrays on outriggers at two levels, a braced
    lattice above it and the link head at 400 m. It is how the island's
    compute leaves the island, and the reason the fort is round it.
    Nothing up there is walkable and nothing is meant to be: the top floor is
    262 m below the head. Silhouette and objective, not ground.
  - **Everything on the wall is reachable.** Eight ramps climb from the yard
    onto the walk, two a side, crossing the wall rather than running along it
    so each meets the walk on its whole width. The bastion platforms are
    FLUSH with the walk, not raised: a platform up a ramp of its own turned
    out to be unreachable from three corners of four. The height is in their
    parapets instead, 7 m on the two outer faces.
  - **Twenty-four data halls, one on top of another**, a floor every 6 m. A
    ramp from each floor to the next climbs a different inside wall each time,
    so the fight corkscrews through the building instead of running up one
    stairwell. Each floor is its own entity, so each can be lit.
  - **Every floor is a room to clear.** Rack rows down the middle for cover,
    plant on every third floor for a different shape of fight, and a 6 m lane
    round the outside so the whole squad can work round them. The cable trays
    overhead are mesh only.
  - **Each flight stops 6 m short of the wall** and the last 6 m are floor. A
    ramp run to the corner meets the floor it is reaching at a single point,
    and the navmesh will not join a point to anything — the climb dies there
    with nothing to see from either end.
  - **The inside and the outside do not meet.** No gunloops, no windows, no
    firing slots — one way in at the bottom, one way out onto the terrace at
    the top. It is also pitch dark in there. The one texture
    in the pack with an emission map is
    `hl_office_complex_style_drop_ceiling_1_1`, and the depot has a material
    for it — see the depot section below for what it took to make it work.
- **fort_wall:** 24 m of wall, 4.5 m high, butts end to end.
- **fort_gate:** the same wall with a 12 m opening headed at 6 m.

### The depot (`maps/depot/depot_level.map`)

Not a block — a whole level, the home base, written by
`tools/block_homebase.gd`. One hall, 84 × 48 m and 15 m to the ceiling, with a
range annexe hanging off its south wall. You arrive on a gallery 4 m up at the
east end and walk down a 20 m ramp at 1 in 5; from the head of it the bays are
on your right, the muster deck ahead, the range portal on your left and the
transit car at the far end.

Four things drove the size, and all four are load-bearing:

- **The muster deck.** 24 × 24 m of plated steel a 0.2 m step above the floor
  (under the navmesh's 0.25 m climb, so the squad walks on and off it), marked
  out with 36 stands four metres apart. That is the whole squad in formation
  where you can see it from the gallery, with a rover's worth of room on every
  stand. The stands are `SquadMuster/Stand01..36` in the level scene.
- **Four hangar bays**, cut into the north wall: 12 m wide, 12 m deep from the
  wall, 9 m to the lintel. A rover is 1.7 × 3.4 × 2 m, so a bay swallows one
  three times that and still leaves 3 m each side to walk round it and look.
  Each has a plated stand and a lit back wall.
- **The range annexe**, 24 × 28 m through a 12 m portal in the south wall, with
  a lit sign band over it you can read from the ramp. It is off the hall, so it
  is obvious on the first walk down and ignorable on every walk after, and it
  never stands between you and the car.
- **The transit dock** at the west end: a 22 m car on a rail bed, two body
  lengths with a 5 m opening between them, under a gantry. The rail bed is
  0.6 m up, so there is a boarding apron at the door — a 0.6 m kerb is a wall
  to a navmesh that will climb 0.25 m, and without it the squad cannot board.

**Nothing robot-shaped is built in it.** The first pass stood a charge post in
each bay and it read as a robot — a different, wrong robot standing next to the
real ones. Build the fixture, leave the volume empty and lit, and let the game
spawn a real chassis at the `ChassisBays/BayN/ChassisStand` markers.

**Zones are separate entities** (`entity("func_detail")` per bay and for the
annexe) so each is its own MESH. This renderer lights about eight lights per
mesh; one mesh for the whole depot would mean eight lights for eighty-four
metres of hall. The level scene then puts each zone's mesh on its own visual
layer and sets each light's `light_cull_mask` to match, so the bay and range
lamps cost the hall nothing. Robots stay on layer 1, lit by the hall.

**The walls are in two bands** — `banded()` — painted below 4 m and bare
concrete above. `concrete_wall_11` draws a vent strip along its bottom edge and
an oxide dado above it; `@0.909` lands the top of the paint at exactly the band
height. Run a wall texture like that full height and the dado repeats halfway
up the wall, which is what the first pass did with the green version and it
read as mould.

**No `glitch_tx_1` anywhere in it.** At trim size it reads as magenta confetti,
not as a lit strip. The trim is `metal_wall_5` and the markings are
`concrete_tx_4` — pale paint on dark steel.


### The proving ground (`maps/proving/proving_level.map`)

Not a block — a whole level, written by `tools/block_arena.gd`, and a
replacement for the arena. Same footprint: 88 × 54 m of grass in a walled
rectangle. Everything else is different, because three things made the arena
hard to read and all three are fixable in the geometry:

- **Everything in it was 4 m tall.** Every cover wall and every pillar, so
  nothing could be seen over and there was no way to tell a thing you shoot
  over from a thing you hide behind. Cover here is **1.3 m** (shoot over it),
  **1.9 m** (full cover standing) or **3.0 m** (a sight-line blocker, used at
  eight places). Nothing is thicker than 1.4 m; the arena had 3.5 m square
  pillars, which is not cover, it is a building.
- **The cover was the same colour as the ground** — all of it `Metal_04`, a
  mossy green-grey, on green grass. Cover is grey concrete now, the blockers
  are blue-grey, the crates are oxide, and the perimeter is the same blue-grey
  as the blockers so the boundary reads as one thing.
- **There was nothing to navigate by** — eighty-one near-identical blocks in a
  uniform field. There are three landmarks now: a derrick tower in the middle
  you can climb and see the whole map from, and a base at each end.

**MOBA read.** Three lanes run the length of it, cut into the grass as worn
track, with a rough strip between each pair to flank through and two
cross-lanes to rotate on. The lanes are plates 0.06 m proud — nothing to walk
over, nothing to the navmesh, and the one thing that lets you see the map's
shape while standing in it. Keep them narrow: at 12 m wide the sand ate the
field and left the grass as edging, which is backwards.

**Symmetry.** Cover is written once in the `COVER` table and stamped twice,
the second time rotated 180° about the centre, so neither end has the better
ground. The builder measures every pair of footprints against every other and
refuses to write the map if any two overlap.

Three things that cost a rebuild each, worth not repeating:

- **A ramp lying in a lane is a wall across it.** The tower's ramps ran in
  along the middle lane, and a 12 m ramp seen from eye height at its foot is a
  five-metre brown slab across the middle of everything. They come up the
  flanks now and the lane runs clean underneath the tower.
- **A kerb on a climbing ramp climbs with it.** At 1.1 m proud the ramp rails
  were a two-metre wall by halfway up. 0.25 m.
- **This environment blows out anything much above half albedo.** Pale sand
  lanes, white treadplate and pale concrete all rendered as white paper under
  the shared sun. The whole palette is chosen from the dark end.

The level scene (`build_proving.gd`, in the scratchpad) carries the arena's
mission scaffolding — hostile muster, an eliminate objective over the field,
and an extraction that only opens once it is clear — plus cover points
generated off the baked navmesh by `CoverPointSpawner`.

### Lit surfaces

`textures/PSX_Textures/hl_office_complex_style_drop_ceiling_1_1.tres` is the
only material in the project that emits, and it is hand-written. Two traps:

- **FuncGodot did not find the emission map.** It looks for PBR maps in a
  folder named after the texture, and this pack ships
  `*_emission.png` beside the texture, so the material it generated was
  albedo-only. A `.tres` next to the texture wins over the generated one, so
  the material lives there.
- **`emission_operator` must be 1 (multiply).** On the default, add, the
  emission colour goes on the whole surface and the map is added on top — the
  first attempt lit the entire ceiling like a lightbox. On multiply, only the
  tubes light.

Use it for a ceiling at 8 m a tile and for panels at `@0.25` (2 m a tile). It
does not light anything else — it only makes the fitting look lit — so the
depot still carries nine light nodes for the room itself.
