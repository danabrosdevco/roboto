@tool
class_name TerrainRecipe
extends Resource

# ─────────────────────────────────────────────
# TERRAIN RECIPE — every knob that shapes a generated terrain, and nothing else.
#
# Pure data. TerrainGenerator turns a recipe, plus whatever TerrainStamp and
# TerrainPath nodes sit under the GeneratedTerrain, into a TerrainData. The
# same recipe and seed give the same heights every time, on every machine.
#
# EVERY PROPERTY EMITS `changed`. A plain @export does not announce itself when
# the inspector edits it, and that signal is the only way GeneratedTerrain can
# tell a slider moved — without it auto-regenerate would silently never fire.
#
# ENUMS ARE APPEND-ONLY. `layout` is stored as an int in every preset and every
# level that embeds a recipe; inserting a value remaps all of them.
#
# Presets live in res://Env/terrain/presets/. GeneratedTerrain copies a preset
# when you assign one in the editor, so tweaking a level never edits the preset.
#
# For direct control over the layout, paint a SKETCH (the Sketch group): a small
# image whose colours put mountains, water, flat ground, urban blocks, shelled
# and rough ground where you draw them. Unpainted areas fall back to the rest
# of this recipe. See TerrainSketch for the palette.
# ─────────────────────────────────────────────

enum Layout { VALLEY, BASIN, OPEN }

const Sketch := preload("res://Env/terrain/terrain_sketch.gd")

@export_group("Size")
## Width of the map along X. Rounded UP to whole 64-cell chunks.
@export_range(128.0, 4096.0, 1.0, "suffix:m") var size_x: float = 1024.0:
	set(v): size_x = v; emit_changed()
## Depth of the map along Z. Rounded UP to whole 64-cell chunks.
@export_range(128.0, 4096.0, 1.0, "suffix:m") var size_z: float = 512.0:
	set(v): size_z = v; emit_changed()
## Distance between height samples. 2 m suits big squad maps; 1 m gives crisper
## cover and trenches at four times the cost. Block out at 4 m, finish at 1–2 m.
@export_range(0.5, 8.0, 0.25, "suffix:m") var cell_size: float = 2.0:
	set(v): cell_size = v; emit_changed()
## Change this for a different terrain from the same recipe.
@export var random_seed: int = 1:
	set(v): random_seed = v; emit_changed()

@export_group("Layout")
## VALLEY: a meandering floor along the long axis between rising sides.
## BASIN: a bowl ringed by high ground. OPEN: rolling ground everywhere.
@export var layout: Layout = Layout.VALLEY:
	set(v): layout = v; emit_changed()
## Shift everything so the playable floor averages y = 0. Level work is easier
## when "the ground" is roughly zero.
@export var floor_at_zero: bool = true:
	set(v): floor_at_zero = v; emit_changed()

@export_subgroup("Floor")
## VALLEY: width of the floor. BASIN: diameter of the floor.
@export_range(10.0, 3000.0, 1.0, "suffix:m") var floor_width: float = 150.0:
	set(v): floor_width = v; emit_changed()
## Width of the slope from the floor up to the surrounding land.
@export_range(0.0, 1500.0, 1.0, "suffix:m") var floor_shoulder: float = 150.0:
	set(v): floor_shoulder = v; emit_changed()
## How far the floor sits below the land around it.
@export_range(0.0, 300.0, 0.5, "suffix:m") var floor_depth: float = 28.0:
	set(v): floor_depth = v; emit_changed()
## How much of the hills survive on the floor. 0 = billiard table, 1 = as
## rough as the land around it.
@export_range(0.0, 1.0, 0.01) var floor_roughness: float = 0.3:
	set(v): floor_roughness = v; emit_changed()
## How ragged the edge of the floor is.
@export_range(0.0, 1.0, 0.01) var floor_edge_noise: float = 0.35:
	set(v): floor_edge_noise = v; emit_changed()

@export_subgroup("Meander")
## VALLEY only: how far the valley swings side to side.
@export_range(0.0, 1000.0, 1.0, "suffix:m") var meander: float = 90.0:
	set(v): meander = v; emit_changed()
## VALLEY only: distance between bends.
@export_range(50.0, 5000.0, 1.0, "suffix:m") var meander_scale: float = 650.0:
	set(v): meander_scale = v; emit_changed()

@export_group("Border Mountains")
## Which map edges rise into mountains. Leave a side open for a valley that runs
## off the map, and keep GeneratedTerrain.boundary_walls on so nobody walks off.
@export_flags("North (-Z)", "South (+Z)", "West (-X)", "East (+X)") var border_sides: int = 15:
	set(v): border_sides = v; emit_changed()
@export_range(0.0, 500.0, 0.5, "suffix:m") var border_height: float = 75.0:
	set(v): border_height = v; emit_changed()
## How far in from the edge the mountains start to rise.
@export_range(0.0, 1500.0, 1.0, "suffix:m") var border_width: float = 170.0:
	set(v): border_width = v; emit_changed()
## How ragged the foot of the mountains is, in metres of in-and-out wobble.
@export_range(0.0, 500.0, 1.0, "suffix:m") var border_noise: float = 70.0:
	set(v): border_noise = v; emit_changed()
## 0 = smooth ramps, 1 = sharp ridged peaks.
@export_range(0.0, 1.0, 0.01) var border_ruggedness: float = 0.7:
	set(v): border_ruggedness = v; emit_changed()

@export_group("Hills")
## Height of the rolling hills, above and below their mean.
@export_range(0.0, 200.0, 0.5, "suffix:m") var hills_height: float = 12.0:
	set(v): hills_height = v; emit_changed()
## Typical distance between hilltops.
@export_range(10.0, 3000.0, 1.0, "suffix:m") var hills_scale: float = 260.0:
	set(v): hills_scale = v; emit_changed()
@export_range(1, 8) var hills_octaves: int = 5:
	set(v): hills_octaves = v; emit_changed()
## Domain warp: bends the hills so they stop reading as noise.
@export_range(0.0, 500.0, 1.0, "suffix:m") var hills_warp: float = 70.0:
	set(v): hills_warp = v; emit_changed()

@export_group("Ridges")
## Sharp-crested ridgelines over the hills. Good for sightlines and flanks.
@export_range(0.0, 300.0, 0.5, "suffix:m") var ridge_height: float = 16.0:
	set(v): ridge_height = v; emit_changed()
@export_range(20.0, 3000.0, 1.0, "suffix:m") var ridge_scale: float = 420.0:
	set(v): ridge_scale = v; emit_changed()
## How much ridge relief reaches onto the floor. 0 keeps the floor open.
@export_range(0.0, 1.0, 0.01) var ridge_on_floor: float = 0.1:
	set(v): ridge_on_floor = v; emit_changed()

@export_group("Detail")
## Knee-high undulation: what gives a squad cover on "flat" ground.
@export_range(0.0, 20.0, 0.05, "suffix:m") var detail_height: float = 1.2:
	set(v): detail_height = v; emit_changed()
@export_range(2.0, 200.0, 0.5, "suffix:m") var detail_scale: float = 18.0:
	set(v): detail_scale = v; emit_changed()

@export_group("Terraces")
## Height of each step. 0 turns terracing off.
@export_range(0.0, 50.0, 0.25, "suffix:m") var terrace_step: float = 0.0:
	set(v): terrace_step = v; emit_changed()
@export_range(0.0, 1.0, 0.01) var terrace_strength: float = 0.75:
	set(v): terrace_strength = v; emit_changed()

@export_group("Craters")
@export_range(0, 2000) var crater_count: int = 30:
	set(v): crater_count = v; emit_changed()
@export_range(1.0, 100.0, 0.5, "suffix:m") var crater_radius_min: float = 3.0:
	set(v): crater_radius_min = v; emit_changed()
@export_range(1.0, 200.0, 0.5, "suffix:m") var crater_radius_max: float = 14.0:
	set(v): crater_radius_max = v; emit_changed()
## Bowl depth as a fraction of the radius.
@export_range(0.0, 1.0, 0.01) var crater_depth: float = 0.3:
	set(v): crater_depth = v; emit_changed()
## Rim height as a fraction of the radius.
@export_range(0.0, 0.5, 0.01) var crater_rim: float = 0.1:
	set(v): crater_rim = v; emit_changed()
## Keep craters on the playable floor rather than up in the mountains.
@export var craters_on_floor: bool = true:
	set(v): craters_on_floor = v; emit_changed()

@export_group("Erosion")
## Slumping: slopes steeper than the talus angle shed material downhill. Cheap.
@export_range(0, 50) var thermal_passes: int = 5:
	set(v): thermal_passes = v; emit_changed()
@export_range(10.0, 80.0, 0.5, "suffix:°") var talus_angle: float = 42.0:
	set(v): talus_angle = v; emit_changed()
## Rainfall erosion: carves gullies and drops fans below them. 0 = off. This is
## the expensive stage — block out with it at 0, raise it for the final pass.
@export_range(0.0, 2.0, 0.01) var hydraulic_strength: float = 0.6:
	set(v): hydraulic_strength = v; emit_changed()

@export_group("Finish")
## Light blur over the whole map after erosion and craters.
@export_range(0, 10) var smooth_passes: int = 1:
	set(v): smooth_passes = v; emit_changed()

@export_group("Sketch")
## A small painted map that sets the layout. Paint on black; top = north.
##   white mountains · blue water · green flat · grey urban
##   red shelled · yellow rough · black/transparent = recipe decides
## Any paint program works. See docs/TERRAIN.md and Env/terrain/sketches/.
@export var sketch: Texture2D:
	set(v):
		if sketch != null and sketch.changed.is_connected(emit_changed):
			sketch.changed.disconnect(emit_changed)
		sketch = v
		# A re-saved PNG is re-imported into the same texture, which emits
		# `changed`: pass it on, so auto_regenerate sees the new drawing.
		if sketch != null and not sketch.changed.is_connected(emit_changed):
			sketch.changed.connect(emit_changed)
		emit_changed()
## 0 stretches the sketch over size_x × size_z. Above 0, each pixel is this
## many metres and the MAP SIZE COMES FROM THE SKETCH — draw a tall image for
## a north–south map. At 8 m, a 176 × 64 sketch is the valley mission's size.
@export_range(0.0, 64.0, 0.5, "suffix:m") var sketch_metres_per_pixel: float = 0.0:
	set(v): sketch_metres_per_pixel = v; emit_changed()
## How far painted areas fade into their neighbours.
@export_range(0.0, 300.0, 1.0, "suffix:m") var sketch_blend: float = 20.0:
	set(v): sketch_blend = v; emit_changed()
## How far painted edges wander, so blocky pixels come out as natural shapes.
@export_range(0.0, 200.0, 1.0, "suffix:m") var sketch_edge_noise: float = 16.0:
	set(v): sketch_edge_noise = v; emit_changed()

@export_subgroup("Painted mountains")
## Typical crest of white areas; summits reach about 1.7× it.
@export_range(0.0, 500.0, 0.5, "suffix:m") var sketch_mountain_height: float = 38.0:
	set(v): sketch_mountain_height = v; emit_changed()

@export_subgroup("Painted water")
## Height of the water surface. With floor_at_zero the floor sits around 0,
## so a little below zero gives water with dry banks.
@export_range(-100.0, 100.0, 0.1, "suffix:m") var water_level: float = -1.5:
	set(v): water_level = v; emit_changed()
## Deepest the bed gets, well away from the shore. Narrow rivers stay shallower.
@export_range(0.5, 60.0, 0.1, "suffix:m") var water_depth: float = 5.0:
	set(v): water_depth = v; emit_changed()
## Width of the bank that slopes the land down to meet the water.
@export_range(0.0, 300.0, 1.0, "suffix:m") var water_bank: float = 30.0:
	set(v): water_bank = v; emit_changed()

@export_subgroup("Painted urban")
## City block size (east–west, north–south) between streets.
@export var urban_block: Vector2 = Vector2(40.0, 32.0):
	set(v): urban_block = v; emit_changed()
@export_range(2.0, 40.0, 0.5, "suffix:m") var urban_street: float = 8.0:
	set(v): urban_street = v; emit_changed()
## Turns the street grid.
@export_range(-90.0, 90.0, 0.5, "suffix:°") var urban_angle: float = 0.0:
	set(v): urban_angle = v; emit_changed()
## Share of blocks left as rubble rather than clean lots.
@export_range(0.0, 1.0, 0.01) var urban_ruin: float = 0.25:
	set(v): urban_ruin = v; emit_changed()

@export_subgroup("Painted shelling")
## Craters per hectare in red areas. Sizes come from the Craters group.
@export_range(0.0, 500.0, 0.5) var shelling_per_hectare: float = 30.0:
	set(v): shelling_per_hectare = v; emit_changed()

@export_subgroup("Painted rough ground")
## Extra relief in yellow areas: broken hills and gullies to fight through.
@export_range(0.0, 100.0, 0.5, "suffix:m") var rough_height: float = 8.0:
	set(v): rough_height = v; emit_changed()


## Changes whenever any generation parameter changes. GeneratedTerrain keys its
## base-height cache on this rather than on `changed`, so a recipe edited from
## code — which may never emit — still invalidates the cache.
##
## The sketch counts by its PIXELS, not its identity: re-saving the PNG keeps
## the same texture resource, and a cache keyed on identity would keep
## generating the old drawing.
func signature() -> int:
	var values: Array = []
	for p in get_property_list():
		if (p.usage & PROPERTY_USAGE_STORAGE) and (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			var v: Variant = get(p.name)
			if v is Texture2D:
				values.append(Sketch.fingerprint(v))
			elif v is Object:
				values.append((v as Object).get_instance_id())
			else:
				values.append(v)
	return hash(var_to_str(values))
