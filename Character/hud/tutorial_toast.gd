extends CanvasLayer
class_name TutorialToast

# ─────────────────────────────────────────────
# TUTORIAL TOAST — the tutorial signs, read off the screen instead of the world.
#
# A 3D sign is read THROUGH the CRT filter, and no outline or colour made a
# paragraph legible that way. So a TutorialLabel now marks a SPOT: stand near
# one and its text takes the top of the screen, big and crisp. This is its own
# CanvasLayer, drawn after the HUD and its filter, so it is never filtered.
# Walk away and it lingers a moment, then fades.
#
# ONE AT A TIME. The nearest sign you are standing within wins, with a little
# hysteresis, so the cluster of signs along the shooting range hands over
# cleanly as you walk it instead of stacking or flickering.
#
# KEYS ARE THE PLAYER'S KEYS. Write {reload} in a sign and it shows whatever
# reload is bound to right now — any InputMap action name works, {1}..{6}
# included. A sign that says "R - RELOAD" to someone who rebound reload to
# mouse 4 teaches the wrong thing.
#
# Self-creating, like the other HUD pieces: the first sign to register makes one
# under the tree root, and it lives across level loads. Signs from a level that
# unloads unregister themselves on the way out.
# ─────────────────────────────────────────────

const NODE_NAME := "TutorialToast"
const SFX_SHOW := preload("res://sounds/sfx/psx ui sfx/squad_manager/HoverG.ogg")

const COL_HEAD := HUDPalette.BRIGHT
const COL_BODY := Color(0.95, 1.0, 0.97)
## Added under the sign that finishes the tutorial, the one time it does.
const FINISHED_LINE := "TUTORIAL COMPLETE. EVERY LESSON IS NOW IN THE PAUSE MENU:\nESC, THEN TUTORIALS."

## Headline (the sign's first line) and body sizes. Big on purpose: this is the
## one piece of text in the game that has to be read on the move.
@export var headline_size: int = 46
@export var body_size: int = 30
@export var panel_width: float = 880.0
## From the top of the screen, as a fraction of its height. High enough to stay
## off the crosshair, low enough to clear the squad and objective panels.
@export var top_fraction: float = 0.07
## Seconds the text stays after you step away, before it fades.
@export var linger_seconds: float = 0.9
@export var fade_speed: float = 7.0

static var _signs: Array = []

var _panel: PanelContainer
var _headline: Label
var _body: Label
var _current: Node3D = null
var _linger: float = 0.0
var _target_alpha: float = 0.0
var _blip: AudioStreamPlayer


## Signs call this from _ready. Creates the toast the first time it is needed.
static func register(sign_node: Node3D) -> void:
	if not _signs.has(sign_node):
		_signs.append(sign_node)
	var tree := sign_node.get_tree()
	if tree != null and tree.root.get_node_or_null(NODE_NAME) == null:
		var toast := TutorialToast.new()
		toast.name = NODE_NAME
		# Deferred: the first sign registers inside its own _ready, while the
		# tree is still busy adding the level.
		tree.root.add_child.call_deferred(toast)


static func unregister(sign_node: Node3D) -> void:
	_signs.erase(sign_node)


## "{reload} - RELOAD" -> "R - RELOAD", from the live bindings.
static func expand_keys(raw: String) -> String:
	var re := RegEx.new()
	re.compile("\\{([A-Za-z0-9_]+)\\}")
	var out := raw
	for m in re.search_all(raw):
		var action := StringName(m.get_string(1))
		if InputMap.has_action(action):
			out = out.replace(m.get_string(0), Settings.binding_text(action))
	return out


func _ready() -> void:
	# Above the HUD and its filter, below the mission briefing (90) and the
	# menus (128).
	layer = 40
	# ALWAYS so it can fade itself out when something pauses the game — the
	# squad manager, the pause menu — rather than hanging over them.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_blip = AudioStreamPlayer.new()
	_blip.stream = SFX_SHOW
	_blip.bus = AudioBuses.INTERFACE
	_blip.volume_db = -8.0
	add_child(_blip)
	_build()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = top_fraction
	_panel.anchor_bottom = top_fraction
	_panel.offset_left = -panel_width * 0.5
	_panel.offset_right = panel_width * 0.5
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.03, 0.03, 0.74)
	box.border_color = Color(HUDPalette.DIM.r, HUDPalette.DIM.g, HUDPalette.DIM.b, 0.5)
	box.set_border_width_all(2)
	box.content_margin_left = 26.0
	box.content_margin_right = 26.0
	box.content_margin_top = 14.0
	box.content_margin_bottom = 18.0
	_panel.add_theme_stylebox_override("panel", box)
	_panel.modulate.a = 0.0
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)
	_headline = _make_label(headline_size, COL_HEAD)
	col.add_child(_headline)
	_body = _make_label(body_size, COL_BODY)
	col.add_child(_body)


func _make_label(font_size: int, colour: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	# Something paused the game — squad manager, pause menu, briefing. Clear
	# out at once rather than lingering over it.
	if get_tree().paused:
		_current = null
		_target_alpha = 0.0
		_panel.modulate.a = 0.0
		_panel.visible = false
		return
	var want := _pick_sign()
	if want != _current:
		if want != null:
			_show(want)
		elif _current != null:
			# Stepped away: keep it up a moment, so drifting to the edge of a
			# sign's circle does not blink it off and on.
			_linger -= delta
			if _linger <= 0.0:
				_current = null
				_target_alpha = 0.0
	else:
		_linger = linger_seconds
	_panel.modulate.a = lerpf(_panel.modulate.a, _target_alpha, clampf(fade_speed * delta, 0.0, 1.0))
	_panel.visible = _panel.modulate.a > 0.01


func _pick_sign() -> Node3D:
	var tree := get_tree()
	if tree.paused:
		return null
	var player := _player()
	if player == null:
		return null
	var best: Node3D = null
	var best_d := INF
	for s in _signs.duplicate():
		if not is_instance_valid(s) or not s.is_inside_tree():
			_signs.erase(s)
			continue
		var r: float = s.trigger_radius
		# Hysteresis: the sign already up keeps the screen a little longer, so
		# standing on the border between two signs does not flicker them.
		if s == _current:
			r *= 1.25
		var d := Vector2(s.global_position.x - player.global_position.x,
			s.global_position.z - player.global_position.z).length()
		if d <= r and d < best_d:
			best_d = d
			best = s
	return best


func _show(sign_node: Node3D) -> void:
	_current = sign_node
	_linger = linger_seconds
	# The last sign of the walkthrough records that the tutorial is done — and
	# on that one showing, and never again, says where the lessons went.
	var just_finished: bool = sign_node.has_method("mark_read") and sign_node.mark_read()
	var raw: String = expand_keys(str(sign_node.toast_text)).strip_edges()
	if just_finished:
		raw += "\n\n" + FINISHED_LINE
	var lines := raw.split("\n")
	_headline.text = lines[0].strip_edges().to_upper()
	var rest: PackedStringArray = []
	for i in range(1, lines.size()):
		rest.append(lines[i].strip_edges())
	_body.text = "\n".join(rest).strip_edges().to_upper()
	_body.visible = _body.text != ""
	# A small pop on each new sign, so the change registers even mid-stride.
	_panel.modulate.a = minf(_panel.modulate.a, 0.35)
	_target_alpha = 1.0
	if _blip != null:
		_blip.play()


func _player() -> Node3D:
	var p := get_tree().get_first_node_in_group("player")
	if p is Node3D:
		return p
	var cam := get_viewport().get_camera_3d()
	return cam
