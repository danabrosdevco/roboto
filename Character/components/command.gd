extends Node3D
class_name CommandMarker

# ─────────────────────────────────────────────
# COMMAND MARKER — visual only.
#
# This used to do the dispatch itself: a 600m SphereShape3D overlap query on
# every placement, calling on_command_marker_nearby() on everything it touched.
# All of that is gone; SquadCommander sends orders straight to the selected
# squad and this node just shows where an order landed and what it was.
#
# It also used to depend on three @export node references (marker / label /
# mesh) that were never assigned in command.tscn, so set_order() silently did
# nothing and _process() returned on the first line. And the scene's only child
# was a kenney pine tree. It now builds its own geometry in _ready(), so there
# is nothing left to forget to wire up.
#
# Everything is unshaded with depth testing OFF, so the marker reads through
# terrain — you need to see where you sent a squad even when a hill is in the
# way. That's deliberate, not an oversight.
# ─────────────────────────────────────────────

# Tint per verb — index matches SquadCommander.Verb ordering.
@export var verb_colors: Array[Color] = [
	Color(0.55, 0.85, 0.55),   # MOVE
	Color(0.45, 0.70, 0.95),   # DEFEND
	Color(0.95, 0.45, 0.35),   # ATTACK
	Color(0.95, 0.80, 0.35),   # WITHDRAW
	Color(0.90, 0.90, 0.90),   # CONTACT
]

@export var ring_radius: float = 1.1
@export var beam_height: float = 3.0
@export var bob_height: float = 0.18
@export var bob_speed: float = 2.0
@export var label_height: float = 3.35

# Preview markers (shown live while the verb wheel is open) sit at lower alpha
# and don't animate, so a committed order still reads as the louder thing.
var preview: bool = false:
	set(value):
		preview = value
		_apply_color()

var _pivot: Node3D
var _ring: MeshInstance3D
var _beam: MeshInstance3D
var _label: Label3D
var _mat_ring: StandardMaterial3D
var _mat_beam: StandardMaterial3D

var _color: Color = Color.WHITE
var _t: float = 0.0


func _ready() -> void:
	_build()
	_apply_color()


func _build() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)

	_mat_ring = _make_material()
	_mat_beam = _make_material()

	# Flat ring on the deck.
	var torus := TorusMesh.new()
	torus.inner_radius = ring_radius * 0.78
	torus.outer_radius = ring_radius
	torus.rings = 24
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _mat_ring
	_ring.position.y = 0.05
	_pivot.add_child(_ring)

	# Vertical beam so the marker is findable from across the map.
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.09
	cyl.height = beam_height
	cyl.radial_segments = 8
	cyl.rings = 1
	_beam = MeshInstance3D.new()
	_beam.mesh = cyl
	_beam.material_override = _mat_beam
	_beam.position.y = beam_height * 0.5
	_pivot.add_child(_beam)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0022
	_label.font_size = 64
	_label.outline_size = 12
	_label.outline_modulate = Color(0, 0, 0, 0.7)
	_label.position.y = label_height
	_label.text = ""
	add_child(_label)


func _make_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 1
	return m


# verb is a SquadCommander.Verb. text is the label to show above the marker.
func set_order(verb: int, text: String = "") -> void:
	if verb >= 0 and verb < verb_colors.size():
		_color = verb_colors[verb]
	else:
		_color = Color.WHITE
	if _label != null:
		_label.text = text
	_apply_color()


func _apply_color() -> void:
	var a: float = 0.45 if preview else 0.9
	var col := Color(_color.r, _color.g, _color.b, a)
	if _mat_ring != null:
		_mat_ring.albedo_color = col
		_mat_ring.emission_enabled = true
		_mat_ring.emission = _color
	if _mat_beam != null:
		_mat_beam.albedo_color = Color(_color.r, _color.g, _color.b, a * 0.65)
	if _label != null:
		_label.modulate = Color(_color.r, _color.g, _color.b, 0.55 if preview else 1.0)


func _process(delta: float) -> void:
	if _pivot == null:
		return
	if preview:
		_pivot.position.y = 0.0
		_pivot.rotation.y = 0.0
		return
	_t += delta * bob_speed
	_pivot.position.y = sin(_t) * bob_height
	_pivot.rotate_y(delta * 0.8)
