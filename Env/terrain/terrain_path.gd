@tool
class_name TerrainPath
extends Path3D

# ─────────────────────────────────────────────
# TERRAIN PATH — draw a line, and the ground along it becomes a road, a trench,
# a riverbed or an earth berm. Applied on Generate.
#
# Draw it with the ordinary Path3D tools. With follow_terrain on (the default)
# only the line's position on the map matters: the height comes from the ground
# underneath, smoothed so a road climbs steadily instead of copying every bump.
# Turn follow_terrain off to make the ground follow the curve's own heights —
# for a ramp, a cutting, or a road that must hit an exact level.
#
#   ROAD      cut and fill to a level bed, gravel paint on the surface
#   TRENCH    dig `depth` below the ground; keep `falloff` small for steep walls
#   RIVERBED  dig `depth` with wide banks; dark, damp paint
#   BERM      heap earth `depth` high — a firing position, a flood bank
#
# At 2 m cells anything under ~4 m wide is lost between samples. Use 1 m cells
# for trench lines.
#
# ENUMS ARE APPEND-ONLY and mirror TerrainGenerator's PATH_* constants.
# ─────────────────────────────────────────────

enum Mode { ROAD, TRENCH, RIVERBED, BERM }

const OUTLINE_META := &"_terrain_path_outline"

var _warned_orphan := false

@export var enabled: bool = true:
	set(value):
		enabled = value
		_changed()
@export var mode: Mode = Mode.ROAD:
	set(value):
		mode = value
		_changed()
## Width of the level bed (road surface, trench floor).
@export_range(0.5, 200.0, 0.1, "suffix:m") var width: float = 8.0:
	set(value):
		width = value
		_changed()
## Width of the bank either side, blending into the ground.
@export_range(0.0, 200.0, 0.1, "suffix:m") var falloff: float = 6.0:
	set(value):
		falloff = value
		_changed()
## TRENCH / RIVERBED depth, BERM height. Unused by ROAD.
@export_range(0.0, 50.0, 0.1, "suffix:m") var depth: float = 2.0:
	set(value):
		depth = value
		_changed()
## Take the height from the ground under the line rather than from the curve.
@export var follow_terrain: bool = true:
	set(value):
		follow_terrain = value
		_changed()
## How far along the line bumps are averaged out when following the terrain.
@export_range(0.0, 500.0, 1.0, "suffix:m") var smoothing: float = 40.0:
	set(value):
		smoothing = value
		_changed()
## Paint the bed: gravel for ROAD, dark hollow for TRENCH and RIVERBED.
@export var paint: bool = true:
	set(value):
		paint = value
		_changed()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
		if not curve_changed.is_connected(_changed):
			curve_changed.connect(_changed)
		_draw_outline()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_notify_terrain()


## The dictionary TerrainGenerator applies: the curve resampled evenly and
## moved into the terrain's local space.
func to_terrain_modifier(terrain: Node3D) -> Dictionary:
	if not enabled:
		return {}
	if curve == null or curve.point_count < 2:
		push_warning("TerrainPath %s needs at least two points — skipped." % get_path())
		return {}
	var to_terrain := terrain.global_transform.affine_inverse() * global_transform
	var points := _resample(clampf(width * 0.25, 0.5, 4.0))
	for i in points.size():
		points[i] = to_terrain * points[i]
	return {
		"type": "path",
		"source": str(get_path()),
		"mode": int(mode),
		"points": points,
		"width": width,
		"falloff": falloff,
		"depth": depth,
		"follow_terrain": follow_terrain,
		"smoothing": smoothing,
		"paint": paint,
	}


## The curve as evenly spaced points, in this node's local space.
func _resample(spacing: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if curve == null:
		return out
	var length := curve.get_baked_length()
	var steps := maxi(ceili(length / spacing), 1)
	out.resize(steps + 1)
	for i in steps + 1:
		out[i] = curve.sample_baked(length * i / steps)
	return out


func _changed() -> void:
	if not is_inside_tree():
		return   # still loading; _ready draws the outline
	if Engine.is_editor_hint():
		_draw_outline()
		_notify_terrain()


func _notify_terrain() -> void:
	var n := get_parent()
	while n != null:
		if n.has_method(&"_on_terrain_modifier_changed"):
			n.call(&"_on_terrain_modifier_changed")
			return
		n = n.get_parent()
	if not _warned_orphan:
		_warned_orphan = true
		push_warning("TerrainPath %s is not under a GeneratedTerrain, so it has no effect." % name)


# Editor-only: the edges of the bed, so the width is visible while drawing.
func _draw_outline() -> void:
	for child in get_children():
		if child.has_meta(OUTLINE_META):
			remove_child(child)
			child.queue_free()
	if curve == null or curve.point_count < 2:
		return   # nothing to outline until the second point exists
	var pts := _resample(2.0)
	var im := ImmediateMesh.new()
	var colour := Color(0.3, 0.85, 1.0) if enabled else Color(0.5, 0.5, 0.5)
	for side in [-1.0, 1.0]:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		im.surface_set_color(colour)
		for i in pts.size():
			var ahead := pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
			var across: Vector3 = Vector3(-ahead.z, 0.0, ahead.x).normalized() * width * 0.5 * side
			im.surface_add_vertex(pts[i] + across + Vector3(0.0, 0.1, 0.0))
		im.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(OUTLINE_META, true)
	add_child(mi)
