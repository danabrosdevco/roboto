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
# Index matches SquadCommander.Verb.
@export var verb_colors: Array[Color] = [
	Color(0.35, 0.62, 0.95),   # ADVANCE — blue, "go here and hold"
	Color(0.55, 0.85, 0.55),   # FOLLOW  — green, "stay with me"
	Color(0.90, 0.90, 0.90),   # CONTACT — white, a report not an order
]

@export var ring_radius: float = 1.1
@export var beam_height: float = 3.0
@export var bob_height: float = 0.18
@export var bob_speed: float = 2.0
@export var label_height: float = 3.35

# ── AGEING ────────────────────────────────────
# A freshly placed marker is loud, because you want to see where the order
# landed. Thirty seconds later the order is still standing but you already know
# about it, so the marker shrinking and dimming to a quiet pip keeps the
# information without the marker dominating the view.
#
# It does NOT delete itself — the objective is still active, and a marker that
# vanishes reads as "that order was cancelled". Set expire_after above zero if
# you'd rather it did go away.
@export var age_duration: float = 40.0
# Scale and alpha at the end of age_duration, as fractions of the fresh values.
@export var aged_scale: float = 0.3
@export var aged_alpha: float = 0.28
# The label goes first — text is the most visually noisy part and the least
# useful once you've read it once.
@export var label_fade_fraction: float = 0.35
# 0 disables. Seconds after placement before the marker frees itself.
@export var expire_after: float = 0.0

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
var _age: float = 0.0


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
	_label.fixed_size = false
	_label.pixel_size = 0.0022
	_label.font_size = 128
	_label.outline_size = 24
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
	# A new order on an existing marker is a new marker as far as the player is
	# concerned, so it goes back to full size and brightness.
	_age = 0.0
	_apply_color()


# 0 when fresh, 1 when fully aged.
func _age_fraction() -> float:
	if preview or age_duration <= 0.0:
		return 0.0
	return clampf(_age / age_duration, 0.0, 1.0)


func _apply_color() -> void:
	var aged := _age_fraction()
	var a: float = 0.45 if preview else lerpf(0.9, 0.9 * aged_alpha, aged)
	var col := Color(_color.r, _color.g, _color.b, a)
	if _mat_ring != null:
		_mat_ring.albedo_color = col
		_mat_ring.emission_enabled = true
		_mat_ring.emission = _color
	if _mat_beam != null:
		_mat_beam.albedo_color = Color(_color.r, _color.g, _color.b, a * 0.65)
	if _label != null:
		var label_a := 1.0
		if preview:
			label_a = 0.55
		else:
			# Fades over the first slice of the lifetime, then stays gone.
			label_a = clampf(1.0 - (aged / maxf(label_fade_fraction, 0.01)), 0.0, 1.0)
		_label.modulate = Color(_color.r, _color.g, _color.b, label_a)
		_label.visible = label_a > 0.01


func _process(delta: float) -> void:
	if _pivot == null:
		return
	if preview:
		_pivot.position.y = 0.0
		_pivot.rotation.y = 0.0
		scale = Vector3.ONE
		return

	_t += delta * bob_speed
	_pivot.position.y = sin(_t) * bob_height
	_pivot.rotate_y(delta * 0.8)

	if _age < age_duration:
		_age += delta
		var aged := _age_fraction()
		# Shrink and dim together. Scaling the whole node takes the beam and the
		# ring down with it; the Label3D is fixed_size so it's faded separately
		# rather than scaled.
		var s := lerpf(1.0, aged_scale, aged)
		scale = Vector3(s, s, s)
		_apply_color()

	if expire_after > 0.0 and _age >= expire_after:
		queue_free()
