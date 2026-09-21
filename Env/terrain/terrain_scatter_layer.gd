@tool
class_name TerrainScatterLayer
extends Resource

# ─────────────────────────────────────────────
# TERRAIN SCATTER LAYER — one kind of prop spread over a terrain by rule:
# dead trees on the shelves, boulders at the foot of the mountains, stones
# across the floor. TerrainScatter holds a list of these.
#
# Every property emits `changed` so the scatter can redraw while you tune it —
# the same reason as TerrainRecipe: a plain @export never announces itself.
# ─────────────────────────────────────────────

@export var enabled: bool = true:
	set(v): enabled = v; emit_changed()
## Models to pick from at random (.glb, .fbx, .tscn), used at their authored
## size — scale 1.0 is the model as it was made. Only their meshes are used,
## drawn as MultiMeshes; scripts, lights and collision inside them are ignored.
## Use collision_radius below for solid props.
@export var scenes: Array[PackedScene] = []:
	set(v): scenes = v; emit_changed()
## Bare meshes to pick from as well — handy for blockout primitives (a
## CylinderMesh trunk, a BoxMesh boulder) before the real props exist.
@export var meshes: Array[Mesh] = []:
	set(v): meshes = v; emit_changed()
## How many per hectare (100 × 100 m) where the rules allow.
@export_range(0.0, 2000.0, 0.1) var per_hectare: float = 20.0:
	set(v): per_hectare = v; emit_changed()
## 0 spreads evenly. Toward 1, props gather in groves with bare ground between.
@export_range(0.0, 1.0, 0.01) var clumping: float = 0.0:
	set(v): clumping = v; emit_changed()
## Size of the groves when clumping.
@export_range(5.0, 1000.0, 1.0, "suffix:m") var clump_size: float = 70.0:
	set(v): clump_size = v; emit_changed()

@export_group("Shape")
@export_range(0.01, 50.0, 0.01) var min_scale: float = 1.0:
	set(v): min_scale = v; emit_changed()
@export_range(0.01, 50.0, 0.01) var max_scale: float = 1.0:
	set(v): max_scale = v; emit_changed()
@export var random_yaw: bool = true:
	set(v): random_yaw = v; emit_changed()
## 0 stands upright (trees); 1 lies along the slope (rocks, debris).
@export_range(0.0, 1.0, 0.01) var align_to_ground: float = 0.0:
	set(v): align_to_ground = v; emit_changed()
## How far into the ground each prop is pushed, so nothing floats on a slope.
@export_range(0.0, 10.0, 0.01, "suffix:m") var sink: float = 0.15:
	set(v): sink = v; emit_changed()

@export_group("Where")
## Steepest ground a prop will stand on.
@export_range(0.0, 90.0, 0.5, "suffix:°") var max_slope: float = 30.0:
	set(v): max_slope = v; emit_changed()
@export var min_height: float = -1000.0:
	set(v): min_height = v; emit_changed()
@export var max_height: float = 1000.0:
	set(v): max_height = v; emit_changed()
## Terrain zone range: 0 open ground … 1 border mountains.
@export_range(0.0, 1.0, 0.01) var min_mountain: float = 0.0:
	set(v): min_mountain = v; emit_changed()
@export_range(0.0, 1.0, 0.01) var max_mountain: float = 0.4:
	set(v): max_mountain = v; emit_changed()
## Stay off roads, pads and scorch stronger than this. Keeps building pads and
## roads clear without hand-deleting anything.
@export_range(0.0, 1.0, 0.01) var max_paint: float = 0.2:
	set(v): max_paint = v; emit_changed()
## Only inside the terrain's boundary walls.
@export var inside_boundary: bool = true:
	set(v): inside_boundary = v; emit_changed()
## Keep out of painted water (and off the strip of bank under its surface).
@export var avoid_water: bool = true:
	set(v): avoid_water = v; emit_changed()

@export_group("Solidity")
## Trunk / boulder collider radius. 0 = walk-through (grass, small stones).
@export_range(0.0, 20.0, 0.01, "suffix:m") var collision_radius: float = 0.0:
	set(v): collision_radius = v; emit_changed()
@export_range(0.1, 50.0, 0.1, "suffix:m") var collision_height: float = 4.0:
	set(v): collision_height = v; emit_changed()

@export_group("Rendering")
@export var cast_shadows: bool = true:
	set(v): cast_shadows = v; emit_changed()
## Stop drawing beyond this distance. 0 = always drawn. Small clutter wants it.
@export_range(0.0, 5000.0, 1.0, "suffix:m") var visibility_range_end: float = 0.0:
	set(v): visibility_range_end = v; emit_changed()
