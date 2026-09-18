extends Control

# ─────────────────────────────────────────────
# TUTORIAL LIBRARY — every homebase lesson, from the pause menu.
#
# Once the player has finished the tutorial the signs around the base retire (see
# TutorialLabel.completes_tutorial), so this is where the lessons go: one screen,
# reachable from anywhere, including mid-mission when the base is not loaded.
#
# READ STRAIGHT OUT OF THE HOMEBASE SCENE. The signs are still the one place a
# lesson is written. This opens the base's PackedScene state — no instancing,
# nothing added to the tree — and lifts the text off every TutorialLabel whose
# in_library is on, in scene order, duplicates dropped. Add a sign to the base
# and it appears here; reword one and this follows.
#
# Keys are expanded the same way the toasts do it, from the live bindings, so a
# rebound key reads correctly here too.
#
# Same frame as OptionsMenu, opened into the same overlay by Master, so it sits
# under the same filter and pause hold. ESC and BACK both return to the pause
# menu. Plain ASCII only: the UI font has no arrows or bullets.
# ─────────────────────────────────────────────

signal closed

const _Toast := preload("res://Character/hud/tutorial_toast.gd")
const LABEL_SCRIPT := "res://Env/world_objects/tutorial_label.gd"
const FALLBACK_BASE := "res://maps/homebase_level.tscn"

const COL_DIM    := HUDPalette.DIM
const COL_BRIGHT := HUDPalette.BRIGHT
const COL_BODY   := Color(0.95, 1.0, 0.97)
const COL_HOVER  := Color(0.86, 1.0, 0.88)

const PANEL_WIDTH := 780.0
const FONT_TITLE  := 40
const FONT_HEAD   := 26
const FONT_BODY   := 21
const FONT_HINT   := 16
const FONT_FOOTER := 26

## Handed over by Master so this screen clicks like the menus around it.
var hover_sound: AudioStreamPlayer
var confirm_sound: AudioStreamPlayer

var _scroll: ScrollContainer
var _suppress_hover: bool = true


## The lessons in a level, as {headline, body}: the sign's first line and the
## rest. Raw — keys are still {action} tokens.
static func collect(scene: PackedScene) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if scene == null:
		return out
	var state := scene.get_state()
	var seen := {}
	for n in state.get_node_count():
		var props := {}
		for p in state.get_node_property_count(n):
			props[state.get_node_property_name(n, p)] = state.get_node_property_value(n, p)
		var script = props.get("script")
		if not (script is Script) or (script as Script).resource_path != LABEL_SCRIPT:
			continue
		if not bool(props.get("in_library", true)):
			continue
		var raw := str(props.get("text", "")).strip_edges()
		if raw == "" or seen.has(raw):
			continue
		seen[raw] = true
		var lines := raw.split("\n")
		out.append({
			"headline": lines[0].strip_edges(),
			"body": "\n".join(lines.slice(1)).strip_edges(),
		})
	return out


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func back() -> void:
	closed.emit()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_suppress_hover = false


# ─────────────────────────────────────────────
# FRAME
# ─────────────────────────────────────────────
func _build() -> void:
	# Its own backing, as the options screen has: the base's draw-through-walls
	# markers otherwise sit right behind the text.
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_WIDTH * 0.5 - 24.0
	panel.offset_right = PANEL_WIDTH * 0.5 + 24.0
	panel.offset_top = 14.0
	panel.offset_bottom = -12.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.03, 0.03, 0.93)
	box.border_color = Color(COL_DIM, 0.3)
	box.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)

	var column := VBoxContainer.new()
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.anchor_top = 0.0
	column.anchor_bottom = 1.0
	column.offset_left = -PANEL_WIDTH * 0.5
	column.offset_right = PANEL_WIDTH * 0.5
	column.offset_top = 26.0
	column.offset_bottom = -22.0
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	column.add_child(_label("TUTORIALS", COL_BRIGHT, FONT_TITLE, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_rule())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)

	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 4)
	_scroll.add_child(page)

	var lessons := collect(_base_scene())
	if lessons.is_empty():
		page.add_child(_label("NO TUTORIALS FOUND", COL_DIM, FONT_BODY, HORIZONTAL_ALIGNMENT_CENTER))
	for i in lessons.size():
		if i > 0:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 14)
			page.add_child(gap)
		var head := _label(_Toast.expand_keys(lessons[i]["headline"]).to_upper(),
			COL_BRIGHT, FONT_HEAD, HORIZONTAL_ALIGNMENT_LEFT)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		page.add_child(head)
		var body_text: String = lessons[i]["body"]
		if body_text != "":
			var body := _label(_Toast.expand_keys(body_text).to_upper(),
				COL_BODY, FONT_BODY, HORIZONTAL_ALIGNMENT_LEFT)
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			page.add_child(body)

	column.add_child(_rule())
	var hint := _label("KEYS SHOWN ARE YOUR CURRENT BINDINGS.  CHANGE THEM IN OPTIONS.",
		COL_DIM, FONT_HINT, HORIZONTAL_ALIGNMENT_CENTER)
	hint.custom_minimum_size = Vector2(0, 30)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(hint)

	var back_button := Button.new()
	back_button.text = "BACK"
	back_button.flat = true
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.custom_minimum_size = Vector2(240, 0)
	back_button.add_theme_font_size_override("font_size", FONT_FOOTER)
	back_button.add_theme_color_override("font_color", COL_BRIGHT)
	back_button.add_theme_color_override("font_hover_color", COL_HOVER)
	back_button.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	back_button.add_theme_color_override("font_focus_color", COL_BRIGHT)
	back_button.mouse_entered.connect(func() -> void:
		if not _suppress_hover:
			_play(hover_sound))
	back_button.pressed.connect(func() -> void:
		_play(confirm_sound)
		back())
	column.add_child(back_button)


# The campaign's own base level when there is one, so a project that renames
# the homebase does not quietly empty this screen.
func _base_scene() -> PackedScene:
	var campaign := get_tree().get_first_node_in_group("campaign")
	if campaign != null and campaign.get("base_level") is PackedScene:
		return campaign.get("base_level")
	if ResourceLoader.exists(FALLBACK_BASE):
		return load(FALLBACK_BASE) as PackedScene
	return null


func _label(text: String, col: Color, size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(COL_DIM, 0.35)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _play(p: AudioStreamPlayer) -> void:
	if p != null and p.is_inside_tree():
		p.play()
