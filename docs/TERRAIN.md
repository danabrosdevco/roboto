# Generated terrain

Big heightfield levels for squad maps, made in the editor from a recipe instead
of modelled outside. It's a new base to build levels on, the same job
`3d_assets/terrain/terrain.fbx` does in `valley_level.tscn`. Place buildings,
cover and props on it as ordinary nodes.

Everything lives in `Env/terrain/`. Nothing outside that folder was changed to
add it.

---

## Quick start

1. Open **`maps/terrain_template_level.tscn`**. It is a complete mission level,
   the same size as the valley mission, with its terrain already generated and
   its navmesh baked.
2. **Scene → Save Scene As…** under a new name, e.g. `maps/foundry_level.tscn`.
3. Select `NavigationRegion3D/Terrain` and tick **Generate Terrain**. This
   writes `maps/terrain_data/foundry_level_terrain.res` for the new level. The
   template's own file is never touched.
4. Change the recipe (seed, sizes, mountains…), move or add stamps and paths,
   and tick **Generate Terrain** again.
5. When the ground is right, place buildings and props, then select
   `NavigationRegion3D` and click **Bake NavigationMesh**.
6. Point a `MissionDefinition.level_scene` at it like any other level.

Starting from an empty scene instead: add a `GeneratedTerrain` node, save the
scene, drag a preset from `Env/terrain/presets/` onto **Recipe**, and tick
**Generate Terrain**.

To decide the layout yourself, whether an island, a coast, a river through a
town, or a north–south map, **paint a sketch**. See
[Sketch maps](#sketch-maps) below.

**`maps/mutaha_level.tscn`** is a finished sketch-built level: a scaled-down
take on Squad's Mutaha, with a braided river through a town, highways meeting
at a crossroads, six bridges, and farmland. Open it next to
`Env/terrain/sketches/mutaha.png` to see how the sketch becomes the map.

---

## The pieces

| Node / resource | What it does |
|---|---|
| `GeneratedTerrain` | The terrain. Builds render chunks, collision and boundary walls from its data. |
| `TerrainRecipe` | Every generation knob. Presets are `.tres` files. |
| `TerrainData` | The baked result: heights and paint. Saved as a binary `.res` beside the scene. |
| `TerrainStamp` | Hand-authored shaping: **FLATTEN** (building pads), RAISE, LOWER, CRATER. |
| `TerrainPath` | A `Path3D` that cuts a **ROAD**, **TRENCH**, RIVERBED or BERM along its curve. |
| `TerrainScatter` + `TerrainScatterLayer` | Props spread by rule (per hectare, slope, height, zone, off roads, pads and water) as MultiMeshes. |
| `TerrainSketch` | Reads a painted sketch into one mask per colour. See [Sketch maps](#sketch-maps). |

Stamps and paths only act when they're somewhere under the `GeneratedTerrain`.
Folders are fine. They apply in Scene-dock order, so a lower node wins where
two overlap.

### What is saved, and what isn't

- **Saved:** the heights and paint (`TerrainData`, one `.res` per terrain), the
  recipe (inside the level), and the stamps and paths (ordinary nodes).
- **Rebuilt on every load, never saved:** the render chunks, the collision and
  the scattered props. They are children without an owner, so they never
  appear in the Scene dock or bloat the `.tscn`. A 1.4 × 0.5 km map rebuilds
  in about 0.1 s.
- **The heights are the level.** They only change when you tick Generate.
  If the generator's maths ever changes, existing maps keep their exact shape.

---

## Presets

All are sized against the valley mission: about 1.4 km × 0.5 km, with around
60 m between the floor and the highest peaks. The playable floor sits at y ≈ 0.

| Preset | Size | Layout |
|---|---|---|
| `valley` | 1408 × 512 m | Enclosed valley: a ~1.2 × 0.3 km flat floor ringed by mountains. The template uses this. |
| `ridge_plain` | 1408 × 512 m | The valley mission's own layout: a flat plain under a mountain range along the north edge, open on the other sides. |
| `basin` | 896 × 896 m | A bombed-out bowl ringed by high ground, heavily cratered. |
| `badlands` | 1152 × 640 m | Open, eroded ground with terraced mesas. Plenty of mid-height cover. |
| `canyon` | 1408 × 512 m | A deep meandering gorge with stepped walls under a plateau. |
| `crater_field` | 1024 × 512 m at 1 m | No-man's-land: flat and shelled flat. 1 m cells, so trenches drawn on it read well. |
| `sketch_coast` | 1408 × 512 m | From `sketches/coast.png`: sea along the south with a bay, a harbour town, a river off the northern range, and a shelled landing beach. |
| `sketch_river_town` | 512 × 1408 m | From `sketches/river_town.png`: **north–south**. A river through a town between two ranges, fields to the north, and a shelled front to the south. |
| `sketch_island` | 896 × 896 m | From `sketches/island.png`: an island with a ridge, an inland tarn, an airstrip, and a town on the south-west shore. |
| `sketch_mutaha` | 1024 × 1024 m | From `sketches/mutaha.png`: a scaled-down Mutaha (after the Squad map). A river braids north–south through a town on both banks, with a district between the channels. Highways from the north and west meet at a central crossroads. Dirt tracks, farmland, ponds, and low desert hills round the edge. `maps/mutaha_level.tscn` is built from it. |

**Assigning a preset in the inspector makes a local copy**, so tuning one level
never edits the preset that other levels start from. Only inspector
assignments are copied: a recipe `.tres` that a scene already references when
it loads is used as it is, so levels can share one on purpose.

### Recipe knobs worth knowing

- `cell_size`: 2 m suits big maps. 1 m gives crisper cover and trenches at four
  times the cost. Block out at 4 m.
- `random_seed`: a different terrain from the same settings.
- `layout`: VALLEY / BASIN / OPEN, plus the **Floor** subgroup (floor width,
  shoulder, depth, roughness).
- `border_*`: the enclosing mountains. `border_sides` picks the edges.
  `border_height` is the typical crest; summits reach about 1.7× it.
- `hills_*`, `ridges_*`, `detail_*`: the shape of the ground. Detail is the
  knee-high undulation that gives cover on "flat" ground.
- `craters_*`, `terrace_*`: bombardment, and stepped hillsides.
- `hydraulic_strength`: rainfall erosion (gullies and fans). This is the
  expensive stage, so leave it at 0 while blocking out.

---

## Sketch maps

Paint the layout, and the generator builds it with natural detail. A sketch is
a small image, made in any paint program, that goes in the recipe's
**Sketch → sketch** slot. Paint on black. The top of the image is north (−Z).

| Colour | RGB | Becomes |
|---|---|---|
| white | 255, 255, 255 | **Mountains.** Ridged peaks with a typical crest of `sketch_mountain_height`. Counts as mountain zone for the shader and scatter. |
| blue | 0, 0, 255 | **Water** at `water_level`. The bed shelves down to `water_depth`, and the land within `water_bank` slopes down to a dry lip. Blue blobs make lakes, lines make rivers, and edges make coast. |
| green | 0, 255, 0 | **Flat ground.** Levelled before and after erosion, for bases, airstrips and fields. |
| grey | 128, 128, 128 | **Urban blocks.** A street grid (`urban_block`, `urban_street`, `urban_angle`), each block levelled to its own height so hillside towns step down in terraces, some left as rubble (`urban_ruin`). Every block wholly inside the paint becomes a **building lot**. |
| red | 255, 0, 0 | **Shelled ground.** Craters at `shelling_per_hectare`, scorched, sized by the Craters group. |
| yellow | 255, 255, 0 | **Rough ground.** Broken hills and gullies, `rough_height` of extra relief. |
| magenta | 255, 0, 255 | **Roads.** Lines, not areas. Each stroke becomes a graded road, `road_width` metres wide for every pixel of stroke thickness. Where a road crosses blue it becomes a **bridge**. See [Roads and bridges](#roads-and-bridges). |
| black / transparent | 0, 0, 0 | **No preference.** The rest of the recipe decides. |

**Size and orientation.** Set `sketch_metres_per_pixel`, and the map takes its
size from the image. At 8 m a pixel:

- 176 × 64 px is 1408 × 512 m, the valley mission's footprint;
- **a tall 64 × 176 px image is a north–south map**, 512 × 1408 m;
- 112 × 112 px is an 896 m island map.

Leave it at 0 to stretch the sketch over `size_x` × `size_z` instead. The
generator warns if the aspect ratios disagree.

**Painting tips.**

- **Brushes:** use hard-edged ones. The generator does the blending
  (`sketch_blend`), and soft edges produce in-between colours that count as
  unpainted.
- **Pixel shapes:** don't bother smoothing them. `sketch_edge_noise` wobbles
  every edge into a natural shoreline or ridge.
- **Mixing with the recipe:** paint only what you care about. A lake and a
  town on an otherwise procedural valley works. For full control, set the
  layout to OPEN and `border_sides` to 0, as the `sketch_*` presets do.
- **Stamps and paths** still apply on top, so you can flatten a pad on painted
  rough ground, or lay a curve too precise to paint.
- **Iterating:** turn on **auto_regenerate**, keep the PNG open in your paint
  program, and save it. Godot re-imports it and the terrain regenerates.
- **Hills, not mesas:** with the OPEN layout, painted white also rises by
  `floor_depth` before `sketch_mountain_height` goes on top. At the default
  28 m, small white blobs come out as sheer-sided table mountains. For rolling
  hills, set `floor_depth` to a few metres, as `sketch_mutaha` does.

### Roads and bridges

Draw roads in magenta with a **hard pencil**, not a brush.

- **Width:** stroke thickness sets it. A 1-pixel line is a track `road_width`
  metres wide (5 m by default), and a 2-pixel line is a road twice that.
- **Junctions:** lines that touch or cross join into junctions by themselves.
- **Stray pixels:** a lone magenta dot is ignored, with a warning.
- **Grading:** the road is graded like a `TerrainPath` ROAD. It cuts and fills
  to a level bed, has a `road_falloff` bank either side, and averages out the
  bumps over `road_smoothing` metres.
- **Colours under the road:** a road across a town keeps the town under it,
  and a road over a river keeps the river. You don't have to paint around
  them.
- **Building lots:** any lot a road runs through is dropped.

**Bridges.** Wherever a road crosses painted water, the generator records a
bridge:

- **The river stays open.** It is left untouched under the bridge, not
  dammed.
- **The road climbs to a deck.** Its surface sits `bridge_clearance` above
  `water_level` (2 m by default), reached on embankments at a 10% grade.
- **Slipways stay low.** A road that runs into the water and stops isn't
  lifted.
- **Hand-placed roads count too.** A `TerrainPath` ROAD over painted water is
  bridged the same way.
- **Blockout decks:** with **bridge_blockouts** on (the default), each bridge
  gets a plain box deck with collision. You can walk and drive across it, and
  a navmesh bake covers it. Turn the blockouts off once you have a bridge
  model to place.
- **Placing models:** `get_bridges()` returns each span in world space:
  `{start, end, width}`, with both ends at road height on the banks.

**Nothing walks in the water.** A river is only a river if the squad has to
cross it on something, so the bed is not navigable. The bake can't tell a bed
from any other dip and paves it, and `Env/terrain/water_navmesh.gd` takes it
back out: when a level loads, `GeneratedTerrain._ready()` drops every navmesh
polygon standing in the water mask below the waterline. Pittsburgh loses about
4,300 polygons that way.

It runs *after* the bake on purpose, so it holds however the navmesh was made
— including from the editor's **Bake NavigationMesh** button, and on the levels
that bake from the terrain's heightmap colliders rather than its chunk meshes.
Two consequences:
- **In the editor the navmesh still covers the water.** That is the raw bake,
  and it is left alone rather than rewritten behind your back. The game strips
  it at load; `tools/test_water_navmesh.gd` proves it.
- **A crossing needs something to cross on.** Take a bridge out and the far
  bank may become unreachable, which is the point, but check what it cuts off.

Anything above the waterline survives, so bridge decks are unaffected. Movement
is otherwise untouched — no wading, no damage; hook those up in game code if you
want them. The water surfaces are also deliberately not nodes, so a bake can't
mistake the surface itself for a walkable floor. `get_paint_at()` and
`TerrainData.water_at_local()` say where water is.

**Building lots.** The editor outlines each lot on the ground, blue for clean
and orange for rubble, and each bridge span in yellow. **show_markers** turns
the outlines off. From code, `get_lots()` returns each lot's world transform
(centred on the levelled block, X along the street grid), its size, and
whether it is ruined. The same transforms can drive a building spawner later.

**Examples** live in `Env/terrain/sketches/`, one per `sketch_*` preset. Open
them next to the maps they make. Godot imports a new sketch PNG when the editor
next scans. Headless tools, such as `terrain_bake.gd` on a sketch level, need
the project to have been opened in the editor once since the PNG was added.

Generation times on this machine:

- a 1408 × 512 m map at 2 m: about 2 s;
- the 1024 × 512 m crater field at 1 m: about 2.5 s;
- Mutaha, 1024 m square with a town and 18 road segments: about 4 s.

---

## Shaping by hand

**Building pads.** Add a `TerrainStamp`. Set `footprint = RECTANGLE`, size it
to the building, and turn it about Y to match. Set its height by moving the
node up or down. Generate. The ground under it is level at exactly the stamp's
Y, with a graded bank of `falloff` metres around it and pad paint on top. A
building placed on a stamp stays put across regenerates.

**Roads and trenches.** Add a `TerrainPath` and draw it with the Path3D tools.
With `follow_terrain` on, only the line's position on the map matters: the
road takes its height from the ground, smoothed over `smoothing` metres.
TRENCH only ever digs, and BERM only ever builds up. At 2 m cells anything
narrower than about 4 m is lost between samples, so use 1 m cells for trench
lines.

Stamps draw their footprint in the viewport, and paths draw their width. Both
are editor-only.

**auto_regenerate** (off by default) regenerates about 0.6 s after any change
to the recipe, a stamp or a path. While only stamps and paths change, the
noise and erosion are reused from a cache, which keeps dragging a pad about
responsive. Leave it off on big maps with erosion on.

---

## Placing things on it

The collision exists in the editor, so **Snap Object to Floor** (PgDn) and
drag-and-drop onto the ground both work. From code:

```gdscript
var terrain: GeneratedTerrain = $NavigationRegion3D/Terrain
terrain.get_height_at(world_pos)    # ground height, or NAN off the map
terrain.get_ground_point(world_pos) # same point, dropped onto the ground
terrain.get_normal_at(world_pos)    # slope
terrain.get_zone_at(world_pos)      # 0 open ground … 1 border mountains
terrain.get_paint_at(world_pos)     # r road, g scorch, b pad, a hollow
terrain.get_playable_rect()         # inside the boundary walls (local x/z)
```

**Scattered props.** Under the terrain, add layers to the `Scatter` node and
drop your prop scenes into **Scenes**. They are used at their authored size;
scale 1.0 is the model as made. For blockouts before the art exists, put a
`CylinderMesh` or `BoxMesh` into **Meshes**. `collision_radius` gives each prop
a trunk or boulder collider. Scatter stays off roads, pads and scorch by
default, and follows the ground when you regenerate.
`get_layer_transforms(i)` returns where layer `i` put everything, for things
like spawning cover points at boulders.

---

## Navigation

The terrain goes under the `NavigationRegion3D`, as `terrain.fbx` does in the
valley. Its chunks are real meshes, so the default *Mesh Instances* bake mode
sees them, and scattered props become obstacles. **Re-bake after every
Generate.** The navmesh doesn't follow the ground by itself.

Keep `filter_baking_aabb` over the playable area only. The template's covers
about 1.1 km × 280 m and bakes in about 6 s. Its `agent_radius` / `agent_max_climb`
match the valley mission's.

A town-sized map makes a much bigger navmesh, because every block, street and
embankment is a separate walkable surface. Mutaha's covers 910 m square. At
Godot's default detail settings it came to 24,000 polygons, 1.2 MB of scene
text. Its navmesh uses these settings instead:

- `edge_max_error` 2.5
- `region_merge_size` 40
- `region_min_size` 8
- `detail_sample_max_error` 2

That gives 13,000 polygons and bakes in about 12 s. It also sits closer to the
ground than the default: at most 0.15 m below it, against 0.39 m. That matters
because `EnemyForceSpawner` spawns units at navmesh height. Use the same
settings for other big sketch maps.

---

## Collision and bounds

- Square `HeightMapShape3D` tiles (256, 128 or 64 cells a side). They are
  square on purpose: godot-jolt only builds Jolt's native height field for
  square maps, and falls back to a much slower triangle mesh otherwise.
- The render mesh uses the same triangle split as the collision, so what you
  see is what you stand on. `tools/test_terrain.gd` checks this with raycasts.
- **Boundary walls** (on by default) stand `boundary_inset` metres in from the
  edge, so nobody climbs the border mountains and walks off the world.

---

## Rendering

- One shared material, `Env/terrain/terrain_material.tres`. It is dark and
  ashen: warm earth, cool rock on slopes and mountains, and patchy dead
  scrub. Roads, pads and scorch are painted in. Everything per-terrain
  arrives as vertex data, so editing the material updates every map live.
  Textures come from `textures/Set4All` and use nearest filtering, like the
  PSX materials. Swap the textures in the material to restyle every map. To
  restyle one map only (a snowy one, say), save a copy of the material and
  assign it to that terrain's **Material**.
- Chunks carry 5 LODs as index buffers, which Godot switches by itself with
  no per-frame script. Skirts under the chunk edges hide LOD cracks. Chunks
  with roads or pads keep full detail longer so the paint stays crisp.
- It works in the Compatibility renderer the project uses: 8 samplers, and no
  instance uniforms.
- **Water** uses `Env/terrain/water_material.tres`: dark, murky and faintly
  oily, with depth-shaded shallows and a scummy shoreline. Depth arrives as
  vertex data, so it needs no depth-buffer reads. Along a coast the sea runs
  on to the horizon past the map edge. The **show_water** option turns it off.
- **Export GLB** writes the terrain as a plain `.glb` beside its data, for
  Blender or anything else.

---

## Command line

```bash
# Regenerate a level's terrain (and rebake its navmesh) without the editor
godot --headless --path . --script res://tools/terrain_bake.gd -- res://maps/foundry_level.tscn --navmesh

# Terrain test suite (also run by tools/test.sh)
godot --headless --path . --script res://tools/test_terrain.gd
```

The bake tool never resaves the scene. Packing a scene outside the editor
writes every script property out, and flattens instanced scenes. So:

- It writes only the terrain's data file.
- An embedded navmesh is baked and reported but not saved. Bake that one in
  the editor.
- A brand-new terrain whose scene doesn't reference its data file yet is
  reported too. Open the level in the editor and save it once.

---

## Invariants (see docs/BRIEFING.md §3–4 for why)

- **Enums are append-only.** `TerrainRecipe.Layout`, `TerrainStamp.Shape /
  Footprint / Paint` and `TerrainPath.Mode` are stored as ints.
  `TerrainGenerator` mirrors the stamp and path ones as constants, and
  `test_terrain.gd` fails if they drift apart.
- **Don't hand-edit `TerrainData`.** Generate writes it.
- **Duplicating a level is safe.** Generate always writes to a file named after
  the current scene, never back to the data file the scene happens to point
  at. The template's and Mutaha's navmeshes are embedded, so they copy with
  the scene. A navmesh saved as its own `.res` would be shared by both copies,
  and baking one would overwrite the other.
- **Built nodes are not internal children.** They're ordinary unowned
  children, because `NavigationRegion3D` only parses `get_children()`.
- **The build is synchronous in `_ready`.** `world.gd` places the player right
  after `add_child`, and collision built a frame later would drop them through.
