extends Node3D
class_name CommandMarker

# ─────────────────────────────────────────────
# COMMAND MARKER — visual only.
#
# This used to do the dispatch itself: a 600m SphereShape3D overlap query on
# every placement, calling on_command_marker_nearby() on everything it touched.
# Three problems with that, all now moot because SquadCommander sends orders
# straight to the selected squad:
#
#   - the query transform was never assigned. `transform.origin = global_position`
#     set the MARKER's transform, not `new_transform`, so the sphere sat at world
#     origin with a 600m radius and swept the entire level every press.
#   - the faction check was commented out, so it hit friend and foe alike.
#   - nothing implemented on_command_marker_nearby() except archived appx code.
#
# All this node does now is show where an order was placed and what it was.
# ─────────────────────────────────────────────

@export var marker: Node3D
@export var label: Label3D
@export var mesh: MeshInstance3D

# Tint per verb — matches SquadCommander.Verb ordering.
@export var verb_colors: Array[Color] = [
	Color(0.55, 0.85, 0.55),   # MOVE
	Color(0.45, 0.70, 0.95),   # DEFEND
	Color(0.95, 0.45, 0.35),   # ATTACK
	Color(0.95, 0.80, 0.35),   # WITHDRAW
	Color(0.90, 0.90, 0.90),   # CONTACT
]

@export var bob_height: float = 0.25
@export var bob_speed: float = 2.0

var _t: float = 0.0
var _base_y: float = 0.0


func _ready() -> void:
	_base_y = global_position.y


func set_order(verb: int, text: String = "") -> void:
	_base_y = global_position.y
	if label != null:
		label.text = text
	var col: Color = Color.WHITE
	if verb >= 0 and verb < verb_colors.size():
		col = verb_colors[verb]
	if label != null:
		label.modulate = col
	if mesh != null and mesh.get_surface_override_material(0) != null:
		var mat = mesh.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			mat.albedo_color = col


func _process(delta: float) -> void:
	if marker == null:
		return
	_t += delta * bob_speed
	marker.position.y = sin(_t) * bob_height
	marker.rotate_y(delta * 0.8)
