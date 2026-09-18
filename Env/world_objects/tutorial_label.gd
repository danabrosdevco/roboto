extends Label3D
class_name TutorialLabel

# ─────────────────────────────────────────────
# TUTORIAL LABEL — world-space text you place in a level.
#
# A Label3D with the project's palette and the two behaviours a teaching sign
# actually needs: fade in when the player is close enough to read it, and
# optionally stop shouting once they have done the thing.
#
# Drop it in, type into `text`, done. Everything else has a working default and
# the proximity behaviour switches itself off if there is no player to measure
# against, so it is safe in any scene.
#
# Deliberately NOT tied to objectives. A sign that says "HOLD F TO CAPTURE" is
# teaching a verb, not tracking a mission — wire `hide_when` yourself if you
# want it to disappear on some condition.
#
# ── LEGIBILITY ────────────────────────────────
# These are read THROUGH the HUD's CRT/signal filter, which is the whole reason
# the defaults here are so aggressive. That filter adds scanlines and noise and
# eats exactly two things: saturated mid-tone colour, and thin strokes. The old
# defaults were a palette green at Godot's stock 12px outline, held at partial
# alpha for most of their visible range — three separate ways of being hard to
# read, stacked. Near-white, a hard black edge, unshaded, drawn over geometry,
# and at full brightness well before you are close enough to care.
# ─────────────────────────────────────────────

## Fade in within this distance. 0 disables proximity entirely and the label is
## simply always visible.
@export var reveal_distance: float = 34.0
## Full opacity by here. Between this and reveal_distance it fades. Kept close
## to reveal_distance on purpose: a sign spends its whole life either readable
## or absent, never at the half-alpha that made these unreadable.
@export var full_distance: float = 26.0
@export var fade_speed: float = 6.0

@export_group("Style")
## Sign colour. Near-white rather than a palette hue — see LEGIBILITY above.
@export var text_color: Color = Color(0.95, 1.0, 0.97)
## Black outline thickness, in font pixels. Godot's stock 12 vanishes against
## bright terrain; a hard edge is what keeps text readable over ANY background
## without needing a panel behind it.
@export var outline_px: int = 36
## Render over geometry. A tutorial sign half-buried in a wall teaches nothing,
## and these are the one thing in a level that should always be readable.
@export var draw_through_walls: bool = true
## Ignore scene lighting. A teaching sign in shadow is just a darker sign.
@export var unshaded: bool = true
## Legacy. Only consulted when custom_color and text_color are both left alone.
@export var palette_color: HUDPalette.HudColors = HUDPalette.HudColors.BRIGHT
## Overrides text_color when not fully transparent. For the odd sign that
## needs to be red.
@export var custom_color: Color = Color(0, 0, 0, 0)
## Faces the camera. Off for signs painted flat onto a surface.
@export var face_camera: bool = true

var _target_alpha: float = 1.0
var _player: Node3D = null


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED if face_camera else BaseMaterial3D.BILLBOARD_DISABLED
	no_depth_test = draw_through_walls
	shaded = not unshaded
	_apply_color()
	_apply_outline()
	if reveal_distance > 0.0:
		modulate.a = 0.0
		set_process(true)
	else:
		set_process(false)


# Applies the sign colour ONLY to a label that has not been coloured by hand.
#
# This used to overwrite modulate unconditionally in _ready, which meant any
# colour set in the inspector was thrown away the moment the scene ran — so the
# assignment got commented out, and with it the styling stopped working at all.
# Checking for untouched white keeps both: styling by default, inspector wins.
func _apply_color() -> void:
	if custom_color.a > 0.0:
		modulate = Color(custom_color.r, custom_color.g, custom_color.b, modulate.a)
		return
	# Pure white is Label3D's default, i.e. "nobody has picked a colour".
	if not modulate.is_equal_approx(Color.WHITE):
		return
	var col: Color = text_color
	modulate = Color(col.r, col.g, col.b, modulate.a)


# The outline is what does the actual work. Only applied when the label is
# still at Godot's stock 12, so a sign deliberately styled in the inspector
# keeps whatever it was given.
func _apply_outline() -> void:
	if outline_size == 12:
		outline_size = outline_px
	outline_modulate = Color(0, 0, 0, 1)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
		if _player == null:
			# Nothing to measure against — show it rather than leaving an
			# invisible sign in the level with no explanation.
			modulate.a = 1.0
			set_process(false)
			return

	var d: float = global_position.distance_to(_player.global_position)
	if d <= full_distance:
		_target_alpha = 1.0
	elif d >= reveal_distance:
		_target_alpha = 0.0
	else:
		_target_alpha = 1.0 - (d - full_distance) / maxf(reveal_distance - full_distance, 0.01)

	modulate.a = lerpf(modulate.a, _target_alpha, clampf(fade_speed * delta, 0.0, 1.0))
	visible = modulate.a > 0.01


func _find_player() -> Node3D:
	var p := get_tree().get_first_node_in_group("player")
	if p is Node3D:
		return p
	# The player is not reliably in a group; fall back to the camera, which is
	# where the reader's eyes are anyway.
	var cam := get_viewport().get_camera_3d()
	return cam


# Call from a signal — a BreakablePanel's `destroyed`, a DummyTerminal's `used`,
# an objective — to retire a sign once its lesson has landed.
func dismiss() -> void:
	reveal_distance = 0.0
	_target_alpha = 0.0
	set_process(false)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.tween_callback(func(): visible = false)


func set_line(new_text: String) -> void:
	text = new_text
