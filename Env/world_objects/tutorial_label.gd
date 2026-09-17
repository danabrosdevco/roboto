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
# ─────────────────────────────────────────────

## Fade in within this distance. 0 disables proximity entirely and the label is
## simply always visible.
@export var reveal_distance: float = 12
## Full opacity by here. Between this and reveal_distance it fades.
@export var full_distance: float = 8
@export var fade_speed: float = 6.0

@export_group("Style")
@export var palette_color: HUDPalette.HudColors = HUDPalette.HudColors.BRIGHT
## Overrides palette_color when not fully transparent. For the odd sign that
## needs to be red.
@export var custom_color: Color = Color(0, 0, 0, 0)
## Faces the camera. Off for signs painted flat onto a surface.
@export var face_camera: bool = true

var _target_alpha: float = 1.0
var _player: Node3D = null


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED if face_camera else BaseMaterial3D.BILLBOARD_DISABLED
	# Signs are read through walls more often than not in a tutorial, and a
	# label z-fighting with the wall it is mounted on reads as a bug.
	no_depth_test = false
	_apply_color()
	if reveal_distance > 0.0:
		modulate.a = 0.0
		set_process(true)
	else:
		set_process(false)


# Applies the palette ONLY to a label that has not been coloured by hand.
#
# This used to overwrite modulate unconditionally in _ready, which meant any
# colour set in the inspector was thrown away the moment the scene ran — so the
# assignment got commented out, and with it the palette stopped working at all.
# Checking for untouched white keeps both: palette by default, inspector wins.
func _apply_color() -> void:
	if custom_color.a > 0.0:
		modulate = Color(custom_color.r, custom_color.g, custom_color.b, modulate.a)
		return
	# Pure white is Label3D's default, i.e. "nobody has picked a colour".
	if not modulate.is_equal_approx(Color.WHITE):
		return
	var col: Color = HUDPalette.get_hud_color(palette_color)
	modulate = Color(col.r, col.g, col.b, modulate.a)


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
