@tool
class_name TerrainData
extends Resource

# ─────────────────────────────────────────────
# TERRAIN DATA — one generated terrain, baked. Heights plus paint masks.
#
# THE HEIGHTS ARE THE LEVEL. Buildings, cover and spawn points are placed on
# them, so they are baked to a file and never silently recomputed: if the
# generator's maths changes one day, maps that already exist keep their exact
# shape. Only an explicit Generate rewrites this.
#
# Meshes and collision are NOT stored. GeneratedTerrain rebuilds them from the
# heights on load (a 1 km² map at 2 m spacing takes well under a second), which
# keeps the file small and means the meshes can never disagree with the heights.
#
# Save as binary `.res`. As text (.tres) the arrays are megabytes of digits.
#
# Grid: (cells_x + 1) × (cells_z + 1) samples, row-major, X fastest. The terrain
# is centred on its node: sample (0, 0) sits at local (-width/2, -depth/2).
# ─────────────────────────────────────────────

## Bump when the MEANING of stored arrays changes, and teach is_valid() to say so.
const FORMAT_VERSION := 1

## Bytes per sample in `control`: R road, G scorch, B pad, A hollow.
const CONTROL_STRIDE := 4

@export var format_version: int = FORMAT_VERSION
@export var cells_x: int = 0
@export var cells_z: int = 0
@export var cell_size: float = 2.0
## Render chunk edge, in cells. Also the LOD grid.
@export var chunk_cells: int = 64
@export var lod_count: int = 5
@export var heights: PackedFloat32Array = PackedFloat32Array()
## RGBA8 per sample. R road/path, G scorch (craters, burns), B pad (flattened
## building ground), A hollow (gullies and dips — darker, damper ground).
@export var control: PackedByteArray = PackedByteArray()
## One byte per sample: 0 open ground … 255 border mountain.
@export var zone: PackedByteArray = PackedByteArray()
## Worst vertical error of each chunk at each LOD, chunk-major. Mesh LOD keys.
@export var lod_errors: PackedFloat32Array = PackedFloat32Array()
## Height of the water surface from a sketch's painted water. Only meaningful
## when `water` is not empty.
@export var water_level: float = 0.0
## One byte per sample: 255 where a water surface is drawn (painted water plus
## a sliver of bank for a clean waterline), else 0. Empty = no water at all.
## Older data files predate this and load with it empty, which is correct.
@export var water: PackedByteArray = PackedByteArray()
## Building lots from painted urban areas, terrain-local. Each is
## {centre: Vector2 (x, z), size: Vector2, angle: float (radians, for
## Basis(Vector3.UP, angle)), height: float, ruined: bool}.
@export var lots: Array = []
## Where roads cross drawn water, terrain-local. Each is {start: Vector3,
## end: Vector3, width: float}: the road ends on either bank, at road height,
## with the water left open between them for a bridge.
@export var bridges: Array = []
@export var min_height: float = 0.0
@export var max_height: float = 0.0
## The recipe that made this, snapshotted. Reproducibility, not live input.
@export var recipe: Resource
## Free-text provenance: when, how big, how long it took.
@export var generated_info: String = ""


func samples_x() -> int:
	return cells_x + 1


func samples_z() -> int:
	return cells_z + 1


func sample_count() -> int:
	return (cells_x + 1) * (cells_z + 1)


func width() -> float:
	return cells_x * cell_size


func depth() -> float:
	return cells_z * cell_size


func chunks_x() -> int:
	@warning_ignore("integer_division")
	return cells_x / chunk_cells if chunk_cells > 0 else 0


func chunks_z() -> int:
	@warning_ignore("integer_division")
	return cells_z / chunk_cells if chunk_cells > 0 else 0


## Local-space bounds of the heightfield (not the skirts).
func get_aabb() -> AABB:
	return AABB(Vector3(-width() * 0.5, min_height, -depth() * 0.5),
			Vector3(width(), maxf(max_height - min_height, 0.01), depth()))


## Checks every size invariant and SAYS which one failed. A terrain that fails
## this is not built at all — half a map with the player falling through the
## other half is worse than a loud error.
func is_valid(context: String = "") -> bool:
	var where := resource_path if resource_path != "" else "unsaved TerrainData"
	if context != "":
		where = "%s (%s)" % [where, context]
	if format_version != FORMAT_VERSION:
		push_error("TerrainData %s: format_version %d, this build reads %d. Regenerate it." % [where, format_version, FORMAT_VERSION])
		return false
	if cells_x <= 0 or cells_z <= 0 or cell_size <= 0.0:
		push_error("TerrainData %s: empty grid (%d × %d cells of %.2f m). Regenerate it." % [where, cells_x, cells_z, cell_size])
		return false
	if chunk_cells <= 0 or cells_x % chunk_cells != 0 or cells_z % chunk_cells != 0:
		push_error("TerrainData %s: %d × %d cells is not a whole number of %d-cell chunks." % [where, cells_x, cells_z, chunk_cells])
		return false
	if lod_count < 1 or chunk_cells % (1 << (lod_count - 1)) != 0:
		push_error("TerrainData %s: %d LODs do not divide a %d-cell chunk." % [where, lod_count, chunk_cells])
		return false
	var n := sample_count()
	if heights.size() != n:
		push_error("TerrainData %s: %d heights for %d samples." % [where, heights.size(), n])
		return false
	if control.size() != n * CONTROL_STRIDE:
		push_error("TerrainData %s: control has %d bytes, expected %d." % [where, control.size(), n * CONTROL_STRIDE])
		return false
	if zone.size() != n:
		push_error("TerrainData %s: zone has %d bytes, expected %d." % [where, zone.size(), n])
		return false
	if not water.is_empty() and water.size() != n:
		push_error("TerrainData %s: water has %d bytes, expected %d (or none)." % [where, water.size(), n])
		return false
	return true


func has_water() -> bool:
	return not water.is_empty()


## Copies every stored field from another TerrainData. Used when regenerating
## into a file that is already loaded: the loaded instance is the one every open
## scene points at, so it is updated in place rather than replaced.
func copy_from(other: TerrainData) -> void:
	format_version = other.format_version
	cells_x = other.cells_x
	cells_z = other.cells_z
	cell_size = other.cell_size
	chunk_cells = other.chunk_cells
	lod_count = other.lod_count
	heights = other.heights
	control = other.control
	zone = other.zone
	lod_errors = other.lod_errors
	water_level = other.water_level
	water = other.water
	lots = other.lots
	bridges = other.bridges
	min_height = other.min_height
	max_height = other.max_height
	recipe = other.recipe
	generated_info = other.generated_info
	emit_changed()


# ── Sampling ─────────────────────────────────────────────────────────────────
# All in terrain-LOCAL space. GeneratedTerrain wraps these with its transform.

## Continuous grid coordinates of a local position. (0, 0) is sample (0, 0).
func local_to_grid(x: float, z: float) -> Vector2:
	return Vector2((x + width() * 0.5) / cell_size, (z + depth() * 0.5) / cell_size)


func contains_local(x: float, z: float) -> bool:
	var g := local_to_grid(x, z)
	return g.x >= 0.0 and g.y >= 0.0 and g.x <= cells_x and g.y <= cells_z


## Surface height at a local position, clamped to the map edge.
##
## Interpolates across the SAME triangle split the collision uses — each cell
## is cut along the (i+1, j)–(i, j+1) diagonal, which is how HeightMapShape3D
## triangulates in Godot Physics and in Jolt. Plain bilinear would disagree
## with the collision by up to half a cell's relief on every diagonal, and
## things snapped to the ground would hover or sink.
func height_at_local(x: float, z: float) -> float:
	var g := local_to_grid(x, z)
	var gx := clampf(g.x, 0.0, float(cells_x))
	var gz := clampf(g.y, 0.0, float(cells_z))
	var i := mini(int(gx), cells_x - 1)
	var j := mini(int(gz), cells_z - 1)
	var u := gx - i
	var v := gz - j
	var sx := cells_x + 1
	var k := j * sx + i
	var h00 := heights[k]
	var h10 := heights[k + 1]
	var h01 := heights[k + sx]
	var h11 := heights[k + sx + 1]
	if u + v <= 1.0:
		return h00 + u * (h10 - h00) + v * (h01 - h00)
	return h11 + (1.0 - u) * (h01 - h11) + (1.0 - v) * (h10 - h11)


## Face normal of the triangle under a local position — the slope a body
## standing there actually stands on.
func normal_at_local(x: float, z: float) -> Vector3:
	var g := local_to_grid(x, z)
	var gx := clampf(g.x, 0.0, float(cells_x))
	var gz := clampf(g.y, 0.0, float(cells_z))
	var i := mini(int(gx), cells_x - 1)
	var j := mini(int(gz), cells_z - 1)
	var sx := cells_x + 1
	var k := j * sx + i
	var c := cell_size
	var n: Vector3
	if (gx - i) + (gz - j) <= 1.0:
		n = Vector3(heights[k] - heights[k + 1], c, heights[k] - heights[k + sx])
	else:
		n = Vector3(heights[k + sx] - heights[k + sx + 1], c, heights[k + 1] - heights[k + sx + 1])
	return n.normalized()


## Nearest-sample zone value, 0 open ground … 1 border mountain.
func zone_at_local(x: float, z: float) -> float:
	var k := _nearest(x, z)
	return zone[k] / 255.0


## True where a water surface is drawn over the nearest sample.
func water_at_local(x: float, z: float) -> bool:
	return has_water() and water[_nearest(x, z)] > 0


## Nearest-sample paint, as a Color: r road, g scorch, b pad, a hollow.
func control_at_local(x: float, z: float) -> Color:
	var k := _nearest(x, z) * CONTROL_STRIDE
	return Color(control[k] / 255.0, control[k + 1] / 255.0, control[k + 2] / 255.0, control[k + 3] / 255.0)


func _nearest(x: float, z: float) -> int:
	var g := local_to_grid(x, z)
	var i := clampi(roundi(g.x), 0, cells_x)
	var j := clampi(roundi(g.y), 0, cells_z)
	return j * (cells_x + 1) + i
