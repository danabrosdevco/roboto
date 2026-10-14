extends Control
class_name ScanEnemyMarker

@export var duration := 5.0
var time: float = 0

@export var base_size := Vector2(75, 75)
@export var color := Color(1, 0.1, 0.1, 0.8)
@export var height_offset := 1.005  # vertical offset above target origin
@export var min_scale := 0.6
@export var max_scale := 2.0

# These define the pixel range of the marker's on-screen height
@export var min_pixel_height := 20.0
@export var max_pixel_height := 200.0

var target: Node3D
# Do NOT cache this. The active camera changes (spectator toggle, level reload)
# and a stale Camera3D unprojects to nonsense screen positions.
var camera: Camera3D

# ─────────────────────────────────────────────
# THE SAME MARKER, PINNED TO GROUND INSTEAD OF TO A BODY.
#
# The scanner's marker rides a live target and dies with it, which is right for
# a scan: you are being shown a thing that is there.
#
# A CONTACT REPORT IS NOT THAT. A squadmate saw something somewhere, and what
# you are being shown is the REPORT — a place and a time, which stay true after
# the thing has moved or died. So in pinned mode the mark holds its world point
# and counts up, and the number beside it is how old the information is.
#
# Same scene, same art, one flag. The difference between "there it is" and
# "that is where it was" is the whole sensor layer.
# ─────────────────────────────────────────────

## Pinned to `world_point` rather than following `target`.
var pinned: bool = false
## Where the contact was reported. Only read when `pinned`.
var world_point: Vector3 = Vector3.ZERO
## Drawn beside a pinned mark as "12s". Off for live scanner marks, which are
## by definition current.
var show_age: bool = false
var _age_label: Label = null
## Measured once off the collision shape; see _subject_height.
var _height_cache: float = 0.0

## Pinned marks are drawn narrow and tall — see the sizing note in
## _physics_process. Multipliers on base_size, so the distance scaling still
## applies on top of them.
const PIN_WIDE: float = 0.52
const PIN_TALL: float = 1.70

## EVERY STROKE IS DRAWN TWICE, dark underneath. An amber bracket over an amber
## robot is invisible, which is exactly the case the mark exists for, and the
## faction tint made it worse rather than better — the thing you most need to
## see is the thing you are least likely to against its own colour. The halo is
## near-black with a little green in it so it sits in the CRT filter's world
## rather than reading as a hard drop shadow.
const HALO := Color(0.02, 0.06, 0.04, 0.72)

## The whole mark sits back from the scene. Applied as `modulate` rather than
## baked into the colours so the stroke and its halo fade together and keep
## their contrast with each other — a dimmed line over a full-strength black
## outline reads as a sticker, not as an overlay.
const MARK_ALPHA: float = 0.62

func _ready():
	modulate.a = MARK_ALPHA
	# The old bracket art is replaced by _draw below. Clearing the texture
	# rather than editing the scene keeps this a code change -- the .tscn stays
	# whatever it is, and a NinePatchRect with no texture draws nothing of its
	# own, leaving the canvas to _draw.
	# set() rather than a cast: the script says `extends Control`, so statically
	# this is not a NinePatchRect even though the scene root is one.
	set("texture", null)
	await get_tree().physics_frame
	visible = true

func _physics_process(delta: float) -> void:
	time += delta
	if time >= duration:
		queue_free()
		return

	# A PINNED MARK OUTLIVES WHAT IT REPORTED. That is the point of it: the
	# report stays true after the thing has moved on or been destroyed, and a
	# mark that vanished the instant the contact died would quietly tell the
	# player something they have not earned.
	if not pinned:
		if not is_instance_valid(target):
			queue_free()
			return

		# Drop the marker the moment the robot dies rather than hanging on the
		# corpse for the rest of the duration.
		if "alive" in target and not target.alive:
			queue_free()
			return

	camera = get_viewport().get_camera_3d()
	if camera == null:
		visible = false
		return

	# ─────────────────────────────────────────────
	# THE BRACKET NOW ACTUALLY FITS WHAT IT IS BRACKETING.
	#
	# This read `top_pos = bottom_pos`, two identical points, so pixel_height
	# below was ALWAYS zero, `t` always clamped to 0, and scale_factor always
	# min_scale. The bracket was a fixed small square at every range, which is
	# why it never sat over the target. `height_offset` was exported and never
	# read once — the comment described an intent nobody finished.
	#
	# The top now comes off the body's own collision capsule where there is
	# one, so a 3 m Walker gets a bracket three times the height of a soldier's
	# and both shrink correctly with distance.
	# ─────────────────────────────────────────────
	var bottom_pos: Vector3 = world_point if pinned else target.global_position
	var top_pos: Vector3 = bottom_pos + Vector3.UP * _subject_height()

	# Convert to screen space
	var screen_top = camera.unproject_position(top_pos)
	var screen_bottom = camera.unproject_position(bottom_pos)

	# Check if target is behind camera
	var to_target = top_pos - camera.global_position
	var cam_forward = -camera.global_transform.basis.z
	if to_target.dot(cam_forward) <= 0.0:
		visible = false
		return

	# CENTRED ON THE BODY, not perched on its head. It used screen_top, so the
	# bracket sat above the target rather than around it.
	var screen_pos = (screen_top + screen_bottom) * 0.5
	var viewport_rect = get_viewport_rect()
	if not viewport_rect.has_point(screen_pos):
		visible = false
		return
	visible = true

	# --- On-screen height scaling (FOV-aware) ---
	var pixel_height = abs(screen_top.y - screen_bottom.y)
	var t = clamp((pixel_height - min_pixel_height) / (max_pixel_height - min_pixel_height), 0.0, 1.0)
	var scale_factor = lerp(min_scale, max_scale, t)

	# A PINNED MARK IS A PIN, NOT A BOX. The reported point is wherever the
	# reporter said it was — for a body that is its origin, which sits at the
	# waist, not the feet. A short glyph planted there lands in the middle of
	# the thing and reads as impaled rather than as a position.
	#
	# So the pinned form gets its own proportions: narrow, and tall enough that
	# the stem lifts the head clear of a standing robot. The tip is still
	# exactly on the point; the part you read is above the silhouette.
	var scaled_size = base_size * scale_factor
	if pinned:
		scaled_size = Vector2(base_size.x * PIN_WIDE, base_size.y * PIN_TALL) * scale_factor
	size = scaled_size

	# ANCHORED, NOT CENTRED, AND THE TWO KINDS ANCHOR DIFFERENTLY.
	#
	# A pinned report is about a PLACE, so its glyph stands on the ground point
	# with its foot exactly there — bottom-centre of the control on
	# screen_bottom. Nothing is computed from a midpoint, so there is no
	# half-height of anything to be wrong by, which is what made the old mark
	# float off its subject.
	#
	# A live scan is about a BODY, so it still centres on it.
	if pinned:
		position = screen_bottom - Vector2(size.x * 0.5, size.y)
	else:
		position = screen_pos - size * 0.5
	queue_redraw()
	_tick_age()


# ─────────────────────────────────────────────
# DRAWN, NOT TEXTURED.
#
# The scene root is a NinePatchRect and its art was a thin bracket that did not
# survive being scaled down: at range it came out as a few stray amber bars
# floating near the subject rather than anything readable. The texture is
# cleared in _ready and the glyph is drawn here instead — crisp at any size,
# no asset to maintain, and the faction tint is just the colour it draws in.
#
# TWO GLYPHS, because they mean different things and the player has to be able
# to tell at a glance:
#
#   LIVE SCAN   four corner ticks around the body. "There it is."
#   PINNED      a pin: a tip on the reported point, a long stem, and a hollow
#               diamond held above the silhouette. "That is where it was."
#
# The stem is the whole distinction, and it has to be LONG. A short glyph
# planted on a body's origin lands at its waist and reads as part of the robot;
# a long one puts the head in clear air above it, where the eye finds it and
# where it can be counted at a glance across a treeline.
# ─────────────────────────────────────────────
func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if pinned:
		var line: float = clampf(w * 0.14, 1.5, 4.0)
		var cx: float = w * 0.5
		var r: float = w * 0.40
		var cy: float = r + line
		# The tip: a short bar across the reported point, so the glyph reads as
		# touching the ground rather than hovering over it.
		_stroke(Vector2(cx - w * 0.30, h), Vector2(cx + w * 0.30, h), line)
		# The stem, running the whole way up to the head.
		_stroke(Vector2(cx, h), Vector2(cx, cy + r), line)
		# The head: a hollow diamond, open so terrain reads through it, with the
		# datum dotted at its centre.
		_stroke_poly(PackedVector2Array([
			Vector2(cx, cy - r), Vector2(cx + r, cy),
			Vector2(cx, cy + r), Vector2(cx - r, cy), Vector2(cx, cy - r)]), line)
		draw_circle(Vector2(cx, cy), maxf(1.0, line * 0.7), color)
		return
	# Live scan: corner ticks, inset so the body is not boxed in tightly.
	var tick: float = clampf(w * 0.045, 1.5, 4.0)
	var leg: float = w * 0.26
	for corner in [Vector2(0, 0), Vector2(w, 0), Vector2(0, h), Vector2(w, h)]:
		var sx: float = 1.0 if corner.x < w * 0.5 else -1.0
		var sy: float = 1.0 if corner.y < h * 0.5 else -1.0
		_stroke(corner, corner + Vector2(leg * sx, 0.0), tick)
		_stroke(corner, corner + Vector2(0.0, leg * sy), tick)


## One stroke, dark backing first. See HALO.
func _stroke(a: Vector2, b: Vector2, width: float) -> void:
	draw_line(a, b, HALO, width + 2.0)
	draw_line(a, b, color, width)


func _stroke_poly(pts: PackedVector2Array, width: float) -> void:
	draw_polyline(pts, HALO, width + 2.0)
	draw_polyline(pts, color, width)


## "14s" under the mark. Built lazily so a live scanner mark allocates nothing.
func _tick_age() -> void:
	if not show_age:
		return
	if _age_label == null:
		_age_label = Label.new()
		_age_label.add_theme_font_size_override("font_size", 14)
		_age_label.add_theme_color_override("font_color", color)
		# Same halo as the strokes, for the same reason — a bare amber "14s"
		# over a bare amber robot is not a reading.
		_age_label.add_theme_constant_override("outline_size", 3)
		_age_label.add_theme_color_override("font_outline_color", HALO)
		_age_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_age_label)
	_age_label.text = "%ds" % int(time)
	# BESIDE THE HEAD, not under the foot. The foot is down in the clutter the
	# contact is standing in; the head is the part held up in clear air, and
	# the age belongs with the part you can actually read.
	#
	# Levelled with the diamond's centre rather than the control's top edge, so
	# it stays attached to the head as the glyph scales with range instead of
	# drifting off above it.
	_age_label.position = Vector2(size.x * 0.82, size.x * 0.40 - 9.0)

	# Optional: draw debug rect
	# update()

# Optional: If drawing manually, you can override _draw
# func _draw():
#     draw_rect(Rect2(Vector2.ZERO, size), color)


## How tall the thing being marked is, in metres.
##
## Measured off the body's own collision capsule so a Walker (3.0 m) and a
## soldier (2.0 m) get brackets that fit them, rather than one size for
## everything. Cached: the shape does not change and this runs every frame.
##
## A PINNED MARK HAS NO BODY, so it takes height_offset — it is a point on the
## ground, and all it needs is enough vertical extent to scale with distance
## instead of collapsing to zero the way the old code did for everything.
func _subject_height() -> float:
	if _height_cache > 0.0:
		return _height_cache
	_height_cache = height_offset
	if not pinned and is_instance_valid(target):
		for c in target.get_children():
			if c is CollisionShape3D and c.shape is CapsuleShape3D:
				_height_cache = maxf(0.2, (c.shape as CapsuleShape3D).height)
				break
	return _height_cache


## Paint the bracket and its age for whoever the contact is about.
func set_faction(faction) -> void:
	color = HUDPalette.faction_color(faction)
	# NO self_modulate. It was set here back when the glyph was a white bracket
	# texture that needed tinting. _draw paints in `color` already, so leaving
	# the modulate on multiplied the colour by itself — amber squared, which is
	# a dark brown almost exactly the Swarm hull's own colour. The mark was
	# being hidden by the thing it marked.
	if _age_label != null:
		_age_label.add_theme_color_override("font_color", color)
	queue_redraw()
