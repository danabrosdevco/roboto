@tool
@icon("res://addons/plenticons/icons/64x-hidpi/objects/pickaxe-yellow.png")
class_name TerrainStamp
extends Node3D

# ─────────────────────────────────────────────
# TERRAIN STAMP — hand-authored ground shaping, applied on Generate.
#
# Put it anywhere under a GeneratedTerrain (folders are fine). The one you will
# use most is FLATTEN with a RECTANGLE footprint: drop it where a building goes,
# size it to the building, and the ground under it comes out level at the
# stamp's own height with a graded bank around it. Buildings placed on a stamp
# stay put across regenerates, because the stamp — not the noise — decides the
# ground there.
#
# Stamps apply after the noise, erosion and craters, in Scene-dock order: a
# stamp lower in the dock wins where two overlap.
#
# ENUMS ARE APPEND-ONLY and mirror TerrainGenerator's STAMP_* / FOOTPRINT_* /
# PAINT_* constants; tools/test_terrain.gd fails if they drift apart.
#
# The outline you see in the editor is drawn by a child built here with no
# owner, so it is never saved and never shows up in the game.
# ─────────────────────────────────────────────

enum Shape { FLATTEN, RAISE, LOWER, CRATER }
enum Footprint { CIRCLE, RECTANGLE }
enum Paint { NONE, PAD, ROAD, SCORCH, RUBBLE }

const OUTLINE_META := &"_terrain_stamp_outline"

var _warned_orphan := false

@export var enabled: bool = true:
	set(value):
		enabled = value
		_changed()
## FLATTEN levels the ground to this node's height. RAISE / LOWER push it up or
## down by `amount`. CRATER digs a blast crater `amount` deep.
@export var shape: Shape = Shape.FLATTEN:
	set(value):
		shape = value
		_changed()
## RECTANGLE follows this node's Y rotation — turn the stamp to match the building.
@export var footprint: Footprint = Footprint.CIRCLE:
	set(value):
		footprint = value
		_changed()
## CIRCLE footprint, and CRATER size.
@export_range(0.5, 500.0, 0.1, "suffix:m") var radius: float = 12.0:
	set(value):
		radius = value
		_changed()
## RECTANGLE footprint: full width (X) and depth (Z).
@export var size: Vector2 = Vector2(24.0, 16.0):
	set(value):
		size = value
		_changed()
## Width of the bank that blends the stamp into the ground around it.
@export_range(0.0, 200.0, 0.1, "suffix:m") var falloff: float = 8.0:
	set(value):
		falloff = value
		_changed()
## RAISE / LOWER height, CRATER depth. Unused by FLATTEN.
@export_range(0.0, 200.0, 0.1, "suffix:m") var amount: float = 4.0:
	set(value):
		amount = value
		_changed()
@export_range(0.0, 1.0, 0.01) var strength: float = 1.0:
	set(value):
		strength = value
		_changed()
## Ground paint under the footprint. PAD reads as compacted ground for a
## building; SCORCH as burnt earth; RUBBLE as broken, dark ground.
@export var paint: Paint = Paint.PAD:
	set(value):
		paint = value
		_changed()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
		_draw_outline()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_notify_terrain()


## The dictionary TerrainGenerator applies. Positions are converted into the
## terrain's local space here, so a moved or rotated terrain still lines up.
func to_terrain_modifier(terrain: Node3D) -> Dictionary:
	if not enabled:
		return {}
	var to_terrain := terrain.global_transform.affine_inverse() * global_transform
	var centre := to_terrain.origin
	var ax := Vector2(to_terrain.basis.x.x, to_terrain.basis.x.z)
	var az := Vector2(to_terrain.basis.z.x, to_terrain.basis.z.z)
	if ax.length() < 0.001 or az.length() < 0.001:
		push_warning("TerrainStamp %s is tipped on its side; its rectangle is measured as if it were level." % get_path())
		ax = Vector2(1.0, 0.0)
		az = Vector2(0.0, 1.0)
	return {
		"type": "stamp",
		"source": str(get_path()),
		"shape": int(shape),
		"footprint": int(footprint),
		"centre": Vector2(centre.x, centre.z),
		"y": centre.y,
		"radius": radius,
		"half_size": size * 0.5,
		"axis_x": ax.normalized(),
		"axis_z": az.normalized(),
		"falloff": falloff,
		"amount": amount,
		"strength": strength,
		"paint": int(paint),
	}


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
	# Not under a terrain at all: the stamp does nothing, so say so — once, not
	# on every frame of a drag.
	if not _warned_orphan:
		_warned_orphan = true
		push_warning("TerrainStamp %s is not under a GeneratedTerrain, so it has no effect." % name)


# Editor-only outline: the footprint (bright) and the outer edge of the bank (dim).
func _draw_outline() -> void:
	for child in get_children():
		if child.has_meta(OUTLINE_META):
			remove_child(child)
			child.queue_free()
	var im := ImmediateMesh.new()
	var colour := Color(1.0, 0.8, 0.2) if enabled else Color(0.5, 0.5, 0.5)
	var inner := radius if footprint == Footprint.CIRCLE or shape == Shape.CRATER else 0.0
	if shape == Shape.CRATER:
		_ring(im, radius, colour)
		_ring(im, radius * 1.8, colour * Color(1, 1, 1, 0.4))
	elif footprint == Footprint.CIRCLE:
		_ring(im, inner, colour)
		if falloff > 0.0:
			_ring(im, inner + falloff, colour * Color(1, 1, 1, 0.4))
	else:
		_box(im, size * 0.5, colour)
		if falloff > 0.0:
			_box(im, size * 0.5 + Vector2(falloff, falloff), colour * Color(1, 1, 1, 0.4))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(OUTLINE_META, true)
	add_child(mi)


func _ring(im: ImmediateMesh, r: float, colour: Color) -> void:
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	im.surface_set_color(colour)
	for i in 65:
		var a := TAU * i / 64.0
		im.surface_add_vertex(Vector3(cos(a) * r, 0.05, sin(a) * r))
	im.surface_end()


func _box(im: ImmediateMesh, half: Vector2, colour: Color) -> void:
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	im.surface_set_color(colour)
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
		im.surface_add_vertex(Vector3(c.x * half.x, 0.05, c.y * half.y))
	im.surface_end()
