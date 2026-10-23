extends Control
class_name DamageDirections

# ─────────────────────────────────────────────
# WHERE IT CAME FROM
#
# An arc around the centre of the screen for each recent hit, at the bearing of
# whatever dealt it. Fades over `life` seconds.
#
# WHY NOT THE TWO THINGS ALREADY IN THE FOLDER. hit_indicator.gdshader is a CRT
# mask — aperture grille, curvature, colour offset — not a damage indicator, and
# farcry2_health_marker.tscn is a forty-pixel ProgressBar. Neither is this, and
# naming is the only reason they look like they might be.
#
# BEARING IS YAW ONLY, in the camera's frame rather than the body's. You turn
# with the camera, so an arc placed from the body's facing drifts off whenever
# the two disagree — which on this character is most of the time.
#
# DRAWN RATHER THAN TEXTURED so it costs nothing to retune: the whole look is
# six numbers at the top of this file, and a programmer can change the feel of
# being shot without opening an image editor.
# ─────────────────────────────────────────────

## Radius of the ring the arcs sit on, as a fraction of the SHORTER screen edge,
## so it holds its shape on any aspect.
@export var radius_frac: float = 0.31
## How wide one hit reads, in degrees.
@export var arc_degrees: float = 58.0
@export var thickness: float = 12.0
## Seconds from full to gone.
@export var life: float = 1.5
## The arc's own colour. Alpha is driven by the fade, not by this.
@export var tint: Color = Color(0.88, 0.22, 0.14)
## A hit this size or bigger draws at full width. Smaller ones are thinner, so
## a graze and a shell do not look the same.
@export var full_hit: float = 25.0

var _hits: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)


## Called from the player when it takes a hit. `from` is world space; a null
## source means we cannot know a bearing, so nothing is drawn rather than an
## arc pointing somewhere arbitrary.
func add_hit(from: Vector3, amount: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Flattened: an arc on a ring around the crosshair is a compass, and a
	# compass has no pitch. A shot from directly above would otherwise swing
	# the bearing wildly for a sub-metre change in position.
	var to_src: Vector3 = from - cam.global_position
	to_src.y = 0.0
	if to_src.length_squared() < 0.0001:
		return
	to_src = to_src.normalized()
	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return
	fwd = fwd.normalized()
	var right: Vector3 = cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	# atan2 of the source in the camera's own frame: 0 is dead ahead, positive
	# is to the right, and it wraps correctly behind you — which a dot product
	# alone cannot do.
	var bearing: float = atan2(to_src.dot(right), to_src.dot(fwd))

	_hits.append({
		"bearing": bearing,
		"left": life,
		"weight": clampf(amount / maxf(full_hit, 1.0), 0.35, 1.0),
	})
	set_process(true)
	queue_redraw()


func clear_hits() -> void:
	_hits.clear()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	var alive: Array = []
	for h in _hits:
		h["left"] = float(h["left"]) - delta
		if float(h["left"]) > 0.0:
			alive.append(h)
	_hits = alive
	if _hits.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _hits.is_empty():
		return
	var mid: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * radius_frac
	for h in _hits:
		var t: float = clampf(float(h["left"]) / maxf(life, 0.01), 0.0, 1.0)
		# Squared so it sits bright and then drops away, rather than spending
		# half its life as a faint smear.
		var a: float = t * t
		var w: float = float(h["weight"])
		var col := Color(tint.r, tint.g, tint.b, a)
		# -PI/2 puts bearing 0 at the TOP of the ring. Screen y grows downward,
		# so without it "ahead" draws to the right.
		var centre: float = float(h["bearing"]) - PI * 0.5
		var half: float = deg_to_rad(arc_degrees * w) * 0.5
		# A HALO FIRST. A single stroke vanished into the signal filter's grain
		# — photographed at 1152x648 the first pass read as a faint scratch and
		# not as a direction. A wider, dimmer arc behind the main one gives it
		# an edge to sit against, which survives both the quantiser and a busy
		# background.
		draw_arc(mid, r, centre - half * 1.25, centre + half * 1.25, 28,
				Color(tint.r * 0.45, tint.g * 0.1, tint.b * 0.08, a * 0.45),
				thickness * w * 2.4, true)
		draw_arc(mid, r, centre - half, centre + half, 24,
				col, thickness * w, true)
