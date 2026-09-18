extends Control
class_name OptionsMenu

# ─────────────────────────────────────────────
# OPTIONS — the screen over Settings. Four tabs: DISPLAY, AUDIO, CONTROLS, KEYS.
#
# Master opens it from the main menu and the pause menu, into the same overlay
# those menus are built in, so it sits under the same CRT filter and reads as
# one interface with them. ESC and BACK both return to whichever menu opened it.
#
# CHANGES APPLY AS YOU MAKE THEM. You hear a volume while you drag it and see a
# window mode the moment you pick it; there is no APPLY button to forget. The
# file is written when the screen closes (Master does that), so dragging a
# slider is not a disk write per frame.
#
# DEFAULTS resets the CURRENT tab only, and asks once first — resetting your
# volume should not also throw away the keys you spent five minutes rebinding.
#
# Mouse-driven, like every other menu here. Built in code and self-wiring, like
# the HUDs: there is nothing to leave blank in an inspector.
#
# The UI font (DS-Digital) has no arrows, bullets or degree sign, so everything
# on this screen is plain ASCII on purpose. The level bars are drawn, not typed.
# ─────────────────────────────────────────────

signal closed

const COL_DIM    := HUDPalette.DIM
const COL_BRIGHT := HUDPalette.BRIGHT
const COL_WARN   := HUDPalette.WARN
const COL_HOVER  := Color(0.86, 1.0, 0.88)

const TABS := ["DISPLAY", "AUDIO", "CONTROLS", "KEYS"]
const TAB_HINTS := [
	"CHANGES APPLY AS YOU MAKE THEM.  POINT AT A SETTING FOR DETAILS.",
	"CHANGES APPLY AS YOU MAKE THEM.  POINT AT A SETTING FOR DETAILS.",
	"CHANGES APPLY AS YOU MAKE THEM.  POINT AT A SETTING FOR DETAILS.",
	"CLICK A BINDING, THEN PRESS THE NEW KEY OR MOUSE BUTTON.  ESC CANCELS.",
]

const PANEL_WIDTH := 780.0
const ROW_HEIGHT  := 32.0
const FONT_TITLE  := 40
const FONT_TAB    := 24
const FONT_ROW    := 20
const FONT_HINT   := 16
const FONT_FOOTER := 26
const ARROW_W     := 28.0
const VALUE_W     := 230.0
const READOUT_W   := 70.0

## Handed over by Master so this screen clicks like the menus around it.
## Either can be left null; the screen is simply silent.
var hover_sound: AudioStreamPlayer
var confirm_sound: AudioStreamPlayer

var _tab: int = 0
var _tab_buttons: Array[Button] = []
var _scroll: ScrollContainer
var _page: VBoxContainer
var _hint: Label
var _defaults_button: Button
var _defaults_armed: float = 0.0
# One entry per setting row: root, wash, name, line, hint, refresh, enabled,
# controls. See _new_row.
var _rows: Array[Dictionary] = []
var _hovered: int = -1
var _capturing: StringName = &""
var _capture_button: Button
var _blink: float = 0.0
var _flash_left: float = 0.0
var _preview: AudioStreamPlayer
var _preview_cooldown: float = 0.0
# Same guard as Master and the squad manager: a screen built under a still
# cursor must not chirp for a button nobody moved to.
var _suppress_hover: bool = true
var _last_mouse: Vector2 = Vector2(-1, -1)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The sample a volume slider plays so you can hear the level you set. Its
	# bus is picked per slider in _preview_bus.
	_preview = AudioStreamPlayer.new()
	_preview.max_polyphony = 2
	add_child(_preview)
	_build()
	Settings.add_listener(_on_setting_changed)
	show_tab(0)


func _exit_tree() -> void:
	Settings.remove_listener(_on_setting_changed)


# ─────────────────────────────────────────────
# PUBLIC
# ─────────────────────────────────────────────
func show_tab(i: int) -> void:
	_cancel_capture()
	_tab = clampi(i, 0, TABS.size() - 1)
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()
	_rows.clear()
	_hovered = -1
	match _tab:
		0: _build_display()
		1: _build_audio()
		2: _build_controls()
		3: _build_keys()
	for j in _tab_buttons.size():
		var on := j == _tab
		_tab_buttons[j].add_theme_color_override("font_color", COL_BRIGHT if on else COL_DIM)
		_tab_buttons[j].get_node("Underline").visible = on
	_scroll.scroll_vertical = 0
	_disarm_defaults()
	_refresh()
	_show_hint()


## ESC. Backs out of a key capture if one is running, otherwise closes.
func back() -> void:
	if is_capturing():
		_end_capture()
		_flash("CANCELLED", COL_DIM)
		return
	close()


func close() -> void:
	_cancel_capture()
	closed.emit()


## True while waiting for the key to bind. Master checks this so the key you
## want (the fullscreen key, M) is not acted on instead of being captured.
func is_capturing() -> bool:
	return _capturing != &""


# ─────────────────────────────────────────────
# FRAME
# ─────────────────────────────────────────────
func _build() -> void:
	# ITS OWN BACKING. From the pause menu the game shows through Master's wash,
	# and the homebase's huge draw-through-walls tutorial lettering sat right
	# behind the rows and fought them. The pause menu's big buttons survive that;
	# 20px option text did not. Same colour as Master's backdrop, so over the
	# main menu's solid black only the thin frame shows.
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

	column.add_child(_label("OPTIONS", COL_BRIGHT, FONT_TITLE, HORIZONTAL_ALIGNMENT_CENTER))

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 40)
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tabs)
	for i in TABS.size():
		var b := _flat_button(TABS[i], FONT_TAB)
		b.mouse_entered.connect(_on_button_hover)
		b.pressed.connect(func() -> void:
			_play(confirm_sound)
			show_tab(i))
		var underline := ColorRect.new()
		underline.name = "Underline"
		underline.color = COL_BRIGHT
		underline.anchor_left = 0.0
		underline.anchor_right = 1.0
		underline.anchor_top = 1.0
		underline.anchor_bottom = 1.0
		underline.offset_top = -3.0
		underline.offset_bottom = -1.0
		underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(underline)
		tabs.add_child(b)
		_tab_buttons.append(b)

	column.add_child(_rule())

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scrollbar(_scroll.get_v_scroll_bar())
	column.add_child(_scroll)

	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 2)
	_scroll.add_child(_page)

	column.add_child(_rule())

	_hint = _label("", COL_DIM, FONT_HINT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.custom_minimum_size = Vector2(0, 42)
	column.add_child(_hint)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 90)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(footer)

	_defaults_button = _flat_button("DEFAULTS", FONT_FOOTER)
	_defaults_button.custom_minimum_size = Vector2(240, 0)
	_defaults_button.mouse_entered.connect(_on_button_hover)
	_defaults_button.pressed.connect(_on_defaults_pressed)
	footer.add_child(_defaults_button)

	var back_button := _flat_button("BACK", FONT_FOOTER)
	back_button.custom_minimum_size = Vector2(240, 0)
	back_button.mouse_entered.connect(_on_button_hover)
	back_button.pressed.connect(func() -> void:
		_play(confirm_sound)
		close())
	footer.add_child(back_button)


# ─────────────────────────────────────────────
# TABS
# ─────────────────────────────────────────────
func _build_display() -> void:
	_choice("display.window_mode", "WINDOW MODE",
		"BORDERLESS FILLS THE SCREEN AND ALT-TABS INSTANTLY.  FULLSCREEN TAKES EXCLUSIVE CONTROL OF THE DISPLAY.  %s SWITCHES BETWEEN WINDOWED AND BORDERLESS IN GAME."
			% Settings.binding_text(&"fullscreen"),
		func() -> Array: return Settings.SPEC["display.window_mode"]["choices"],
		func(v) -> String: return {"windowed": "WINDOWED", "borderless": "BORDERLESS",
			"exclusive": "FULLSCREEN"}.get(v, str(v).to_upper()))
	_choice("display.monitor", "MONITOR",
		"WHICH SCREEN THE GAME OPENS ON.  AUTO LEAVES IT WHEREVER WINDOWS PUTS IT.  WORKS IN EVERY WINDOW MODE.",
		func() -> Array: return Settings.monitor_choices(),
		func(v) -> String: return Settings.monitor_label(int(v)))
	_choice("display.window_size", "WINDOW SIZE",
		"SIZE OF THE GAME WINDOW, IN WINDOWED MODE ONLY.  THE GAME ALWAYS DRAWS AT ITS OWN LOW RESOLUTION AND SCALES UP, SO THIS DOES NOT CHANGE PERFORMANCE.",
		func() -> Array: return Settings.window_size_choices(),
		func(v) -> String: return "MAXIMISED" if v == "maximised" else str(v).replace("x", " X "),
		func() -> bool: return Settings.get_string("display.window_mode") == "windowed")
	_toggle("display.vsync", "VSYNC",
		"LOCKS THE FRAME RATE TO YOUR MONITOR SO THE PICTURE DOES NOT TEAR.  OFF GIVES THE LOWEST INPUT LAG.")
	_choice("display.max_fps", "FRAME LIMIT",
		"CAPS FRAMES PER SECOND.  WORTH SETTING ON A LAPTOP TO SAVE HEAT AND BATTERY.",
		func() -> Array: return Settings.SPEC["display.max_fps"]["choices"],
		func(v) -> String: return "UNLIMITED" if int(v) == 0 else "%d FPS" % int(v))
	_bar("display.fov", "FIELD OF VIEW",
		"VERTICAL DEGREES.  70 IS THE DEFAULT, ABOUT 102 HORIZONTAL ON A 16:9 SCREEN.  AIMING STILL ZOOMS IN FROM WHATEVER YOU SET.",
		1.0, func(v: float) -> String: return "%d" % roundi(v))
	_bar("display.brightness", "BRIGHTNESS",
		"LIFTS OR DEEPENS THE SHADOWS.  RAISE IT IF DARK CORNERS HIDE TOO MUCH.",
		0.05, _percent)
	_bar("display.screen_noise", "SCREEN NOISE",
		"GRAIN, DROPOUTS AND GLITCH BLOCKS ON THE SIGNAL.  TURN IT DOWN IF THE FLICKER BOTHERS YOU.",
		0.05, _percent)
	_toggle("display.show_fps", "SHOW FPS",
		"FRAME COUNTER IN THE TOP LEFT CORNER.")


func _build_audio() -> void:
	_bar("audio.master", "MASTER VOLUME", "EVERYTHING.", 0.05, _percent)
	_bar("audio.music", "MUSIC", "THE TITLE THEME.", 0.05, _percent)
	_bar("audio.effects", "EFFECTS",
		"WEAPONS, EXPLOSIONS, MACHINES AND EVERYTHING ELSE IN THE WORLD.", 0.05, _percent)
	_bar("audio.voice", "VOICE", "YOUR SQUAD'S RADIO CHATTER.", 0.05, _percent)
	_bar("audio.interface", "INTERFACE",
		"MENU, ORDER AND SQUAD MANAGER CLICKS.", 0.05, _percent)
	_toggle("audio.mute_unfocused", "MUTE IN BACKGROUND",
		"SILENCE THE GAME WHILE ITS WINDOW IS NOT IN FOCUS.")
	_toggle("audio.subtitles", "SUBTITLES",
		"SHOW YOUR SQUAD'S RADIO CHATTER AS TEXT IN THE COMMS LOG, BOTTOM RIGHT.")


func _build_controls() -> void:
	_bar("controls.mouse_sensitivity", "MOUSE SENSITIVITY",
		"HOW FAR THE VIEW TURNS FOR EACH INCH OF MOUSE.", 0.05,
		func(v: float) -> String: return "%.2f" % v)
	_bar("controls.aim_sensitivity", "AIM SENSITIVITY",
		"LOOK SPEED WHILE AIMING, AS A SHARE OF MOUSE SENSITIVITY.  LOWER IT FOR STEADIER LONG SHOTS.",
		0.05, _percent)
	_toggle("controls.invert_y", "INVERT LOOK",
		"MOUSE FORWARD LOOKS DOWN.")
	_choice("controls.toggle_aim", "AIM MODE",
		"HOLD: AIM WHILE THE BUTTON IS DOWN.  TOGGLE: CLICK ONCE TO AIM, AGAIN TO STOP.",
		func() -> Array: return [false, true],
		func(v) -> String: return "TOGGLE" if v else "HOLD")


func _build_keys() -> void:
	var group := ""
	for row in Settings.BINDINGS:
		if not InputMap.has_action(row[0]):
			continue
		if row[2] != group:
			group = row[2]
			_header(group)
		_binding(row[0], row[1])


# ─────────────────────────────────────────────
# ROWS
# ─────────────────────────────────────────────
# A name on the left, a fixed-width control on the right, and a faint wash
# behind the whole line while the mouse is over it. Every control lines up in
# the same column whatever kind it is — choices leave an empty readout slot so
# their value sits exactly over a bar's.
func _new_row(label: String, hint: String) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(root)

	var wash := ColorRect.new()
	wash.color = Color(COL_BRIGHT, 0.0)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wash)

	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 14.0
	line.offset_right = -14.0
	line.add_theme_constant_override("separation", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(line)

	var name_label := _label(label, COL_DIM, FONT_ROW, HORIZONTAL_ALIGNMENT_LEFT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(name_label)

	var entry := {
		"root": root, "wash": wash, "name": name_label, "line": line, "hint": hint,
		"refresh": Callable(), "enabled": Callable(), "controls": [],
	}
	_rows.append(entry)
	return entry


# < VALUE > — steps through `choices`. Clicking the value itself steps forward,
# which is what most people try first.
func _choice(key: String, label: String, hint: String, choices: Callable,
		name_of: Callable, enabled: Callable = Callable()) -> void:
	var row := _new_row(label, hint)
	var line: HBoxContainer = row["line"]
	var left := _arrow("<")
	var value := _flat_button("", FONT_ROW)
	value.custom_minimum_size = Vector2(VALUE_W, 0)
	var right := _arrow(">")
	line.add_child(left)
	line.add_child(value)
	line.add_child(right)
	line.add_child(_gap(READOUT_W))

	var cycle := func(dir: int) -> void:
		var list: Array = choices.call()
		if list.is_empty():
			return
		var i := list.find(Settings.get_value(key))
		i = posmod(i + dir, list.size()) if i != -1 else 0
		_play(confirm_sound)
		Settings.set_value(key, list[i])
	left.pressed.connect(cycle.bind(-1))
	right.pressed.connect(cycle.bind(1))
	value.pressed.connect(cycle.bind(1))

	var refresh := func() -> void:
		value.text = name_of.call(Settings.get_value(key))
	row["refresh"] = refresh
	row["enabled"] = enabled
	row["controls"] = [left, value, right]


func _toggle(key: String, label: String, hint: String) -> void:
	_choice(key, label, hint,
		func() -> Array: return [false, true],
		func(v) -> String: return "ON" if v else "OFF")


# < [########------] > 75%
func _bar(key: String, label: String, hint: String, step: float, fmt: Callable) -> void:
	var row := _new_row(label, hint)
	var line: HBoxContainer = row["line"]
	var spec: Dictionary = Settings.SPEC[key]
	var bar := _Bar.new()
	bar.min_value = float(spec["min"])
	bar.max_value = float(spec["max"])
	bar.step = step
	bar.custom_minimum_size = Vector2(VALUE_W, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var left := _arrow("<")
	var right := _arrow(">")
	var readout := _label("", COL_BRIGHT, FONT_ROW, HORIZONTAL_ALIGNMENT_RIGHT)
	readout.custom_minimum_size = Vector2(READOUT_W, 0)
	readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(left)
	line.add_child(bar)
	line.add_child(right)
	line.add_child(readout)

	var set_to := func(v: float) -> void:
		Settings.set_value(key, bar.snap(v))
		_preview_bus(key)
	bar.picked.connect(set_to)
	left.pressed.connect(func() -> void: set_to.call(Settings.get_float(key) - step))
	right.pressed.connect(func() -> void: set_to.call(Settings.get_float(key) + step))

	var refresh := func() -> void:
		var v := Settings.get_float(key)
		bar.show_value(v)
		readout.text = fmt.call(v)
	row["refresh"] = refresh
	row["controls"] = [left, bar, right]


func _binding(action: StringName, label: String) -> void:
	var row := _new_row(label,
		"CLICK, THEN PRESS THE NEW KEY OR MOUSE BUTTON.  A KEY ALREADY IN USE SWAPS OVER, SO NOTHING IS LEFT UNBOUND.")
	var line: HBoxContainer = row["line"]
	var b := _flat_button("", FONT_ROW)
	# The width of < VALUE >, so bindings line up with every other tab.
	b.custom_minimum_size = Vector2(ARROW_W * 2.0 + VALUE_W + 8.0, 0)
	line.add_child(b)
	line.add_child(_gap(READOUT_W))
	b.pressed.connect(func() -> void: _begin_capture(action, b))

	var refresh := func() -> void:
		if _capturing == action:
			return
		b.text = Settings.binding_text(action)
	row["refresh"] = refresh
	row["controls"] = [b]


func _header(text: String) -> void:
	var l := _label("  " + text, COL_WARN, FONT_HINT, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(0, 26)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_page.add_child(l)


func _refresh() -> void:
	for row in _rows:
		var refresh: Callable = row["refresh"]
		if refresh.is_valid():
			refresh.call()
		var enabled_cb: Callable = row["enabled"]
		var on: bool = true if not enabled_cb.is_valid() else bool(enabled_cb.call())
		var root: Control = row["root"]
		root.modulate.a = 1.0 if on else 0.35
		for c in row["controls"]:
			if c is BaseButton:
				var button: BaseButton = c
				button.disabled = not on
			elif c is _Bar:
				var bar: _Bar = c
				bar.enabled = on


func _on_setting_changed(_key: String) -> void:
	_refresh()


# ─────────────────────────────────────────────
# KEY CAPTURE
# ─────────────────────────────────────────────
func _begin_capture(action: StringName, b: Button) -> void:
	_cancel_capture()
	_play(confirm_sound)
	_capturing = action
	_capture_button = b
	_blink = 0.0
	b.text = "PRESS A KEY"
	b.add_theme_color_override("font_color", COL_WARN)
	_set_hint("PRESS THE NEW KEY OR MOUSE BUTTON FOR %s.  ESC CANCELS."
		% Settings.binding_label(action), COL_WARN)


func _cancel_capture() -> void:
	if _capturing != &"":
		_end_capture()


func _end_capture() -> void:
	_capturing = &""
	if is_instance_valid(_capture_button):
		_capture_button.modulate.a = 1.0
		_capture_button.add_theme_color_override("font_color", COL_BRIGHT)
	_capture_button = null
	_refresh()
	_show_hint()


# Sees input before Master and before anything under World — it is deeper in
# the tree, and _input runs deepest-first. While capturing, every key and
# button stops here, releases included, so the key being bound never reaches
# the game behind the menu or toggles fullscreen on its way past.
func _input(event: InputEvent) -> void:
	if _capturing == &"":
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	get_viewport().set_input_as_handled()
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and ((event as InputEventKey).keycode == KEY_ESCAPE
			or (event as InputEventKey).physical_keycode == KEY_ESCAPE):
		back()
		return
	if not Settings.can_bind(event):
		_flash("THAT KEY CANNOT BE BOUND", COL_WARN)
		return
	var action := _capturing
	var swapped := Settings.rebind(action, event)
	_end_capture()
	_play(confirm_sound)
	if swapped != &"":
		_flash("%s IS NOW %s.  SWAPPED: %s IS NOW %s." % [
			Settings.binding_label(action), Settings.binding_text(action),
			Settings.binding_label(swapped), Settings.binding_text(swapped)], COL_WARN, 4.0)
	else:
		_flash("%s IS NOW %s." % [Settings.binding_label(action),
			Settings.binding_text(action)], COL_BRIGHT)


# ─────────────────────────────────────────────
# HOVER, HINT, DEFAULTS
# Hover is found by testing row rects every frame rather than from
# mouse_entered/exited, which fire on the row whenever the pointer crosses onto
# one of its own buttons.
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	var mouse := get_global_mouse_position()
	if mouse != _last_mouse:
		if _last_mouse.x >= 0.0:
			_suppress_hover = false
		_last_mouse = mouse
	_update_hover(mouse)

	if _capturing != &"" and is_instance_valid(_capture_button):
		_blink += delta
		_capture_button.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * cos(_blink * 7.0))
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_show_hint()
	if _defaults_armed > 0.0:
		_defaults_armed -= delta
		if _defaults_armed <= 0.0:
			_disarm_defaults()
	if _preview_cooldown > 0.0:
		_preview_cooldown -= delta


func _update_hover(mouse: Vector2) -> void:
	var found := -1
	# Only inside the scroll area: a row scrolled out of sight still has a
	# rect, and it sits right under the hint and the footer.
	if _scroll.get_global_rect().has_point(mouse):
		for i in _rows.size():
			if (_rows[i]["root"] as Control).get_global_rect().has_point(mouse):
				found = i
				break
	if found == _hovered:
		return
	if _hovered >= 0 and _hovered < _rows.size():
		_rows[_hovered]["wash"].color = Color(COL_BRIGHT, 0.0)
		_rows[_hovered]["name"].add_theme_color_override("font_color", COL_DIM)
	_hovered = found
	if _hovered >= 0:
		_rows[_hovered]["wash"].color = Color(COL_BRIGHT, 0.07)
		_rows[_hovered]["name"].add_theme_color_override("font_color", COL_BRIGHT)
	_show_hint()


func _set_hint(text: String, col: Color) -> void:
	_hint.text = text
	_hint.add_theme_color_override("font_color", col)


func _flash(text: String, col: Color, seconds: float = 2.6) -> void:
	_set_hint(text, col)
	_flash_left = seconds


func _show_hint() -> void:
	if _capturing != &"" or _flash_left > 0.0:
		return
	if _hovered >= 0 and _hovered < _rows.size():
		_set_hint(_rows[_hovered]["hint"], COL_DIM)
	else:
		_set_hint(TAB_HINTS[_tab], COL_DIM)


func _on_defaults_pressed() -> void:
	_play(confirm_sound)
	if _defaults_armed <= 0.0:
		_defaults_armed = 3.0
		_defaults_button.text = "RESET %s?" % TABS[_tab]
		_defaults_button.add_theme_color_override("font_color", COL_WARN)
		return
	_disarm_defaults()
	match _tab:
		0: Settings.reset_section("display")
		1: Settings.reset_section("audio")
		2: Settings.reset_section("controls")
		3: Settings.reset_bindings()
	_flash("%s RESET TO DEFAULTS." % TABS[_tab], COL_BRIGHT)


func _disarm_defaults() -> void:
	_defaults_armed = 0.0
	if _defaults_button != null:
		_defaults_button.text = "DEFAULTS"
		_defaults_button.add_theme_color_override("font_color", COL_BRIGHT)


# ─────────────────────────────────────────────
# SOUND
# ─────────────────────────────────────────────
func _on_button_hover() -> void:
	if not _suppress_hover:
		_play(hover_sound)


func _play(p: AudioStreamPlayer) -> void:
	if p != null and is_instance_valid(p):
		p.play()


# A click on the bus a volume slider controls, so the level can be heard as it
# is set. Music has none: under the main menu the title theme IS the preview,
# and a click on the music bus would only mislead.
func _preview_bus(key: String) -> void:
	if _preview_cooldown > 0.0 or confirm_sound == null or confirm_sound.stream == null:
		return
	var buses := {
		"audio.master": AudioBuses.MASTER, "audio.effects": AudioBuses.EFFECTS,
		"audio.voice": AudioBuses.VOICE, "audio.interface": AudioBuses.INTERFACE,
	}
	if not buses.has(key):
		return
	_preview_cooldown = 0.12
	_preview.stream = confirm_sound.stream
	_preview.bus = buses[key]
	_preview.play()


# ─────────────────────────────────────────────
# PIECES
# ─────────────────────────────────────────────
func _percent(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)


func _label(text: String, col: Color, font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# PASS rather than STOP, so the mouse wheel over a button still scrolls the
# KEYS list instead of dying on the button.
func _flat_button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", COL_BRIGHT)
	b.add_theme_color_override("font_hover_color", COL_HOVER)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", COL_BRIGHT)
	# Disabled rows are dimmed as a whole by modulate; the default grey would
	# dim these twice and in the wrong colour.
	b.add_theme_color_override("font_disabled_color", COL_BRIGHT)
	return b


func _arrow(text: String) -> Button:
	var b := _flat_button(text, FONT_ROW)
	b.custom_minimum_size = Vector2(ARROW_W, 0)
	return b


func _gap(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(COL_DIM, 0.35)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _style_scrollbar(bar: VScrollBar) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(COL_DIM, 0.12)
	track.content_margin_left = 3.0
	track.content_margin_right = 3.0
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(COL_DIM, 0.75)
	var grab_hot := StyleBoxFlat.new()
	grab_hot.bg_color = COL_BRIGHT
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab_hot)
	bar.add_theme_stylebox_override("grabber_pressed", grab_hot)
	bar.custom_minimum_size = Vector2(8, 0)


# ─────────────────────────────────────────────
# LEVEL BAR — a row of blocks, lit up to the value. Click or drag to set,
# wheel to nudge. Drawn rather than a themed HSlider: the default slider is a
# grey desktop widget, and blocks read as the same telemetry as the HUD's bars.
# ─────────────────────────────────────────────
class _Bar extends Control:
	signal picked(value: float)

	var min_value: float = 0.0
	var max_value: float = 1.0
	var step: float = 0.05
	var value: float = 0.0
	var segments: int = 20
	var enabled: bool = true
	var _dragging: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func show_value(v: float) -> void:
		value = v
		queue_redraw()

	func snap(v: float) -> float:
		if step > 0.0:
			v = min_value + roundf((v - min_value) / step) * step
		return clampf(v, min_value, max_value)

	func _draw() -> void:
		var gap := 2.0
		var seg_w := (size.x - gap * float(segments - 1)) / float(segments)
		var frac := clampf((value - min_value) / maxf(max_value - min_value, 0.0001), 0.0, 1.0)
		var lit := int(roundf(frac * segments))
		# Anything above the minimum lights at least one block, so 5% never
		# looks like off.
		if lit == 0 and value > min_value + 0.0001:
			lit = 1
		for i in segments:
			var r := Rect2(float(i) * (seg_w + gap), 0.0, seg_w, size.y)
			draw_rect(r, HUDPalette.BRIGHT if i < lit else Color(HUDPalette.DIM, 0.28))

	func _gui_input(e: InputEvent) -> void:
		if not enabled:
			return
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed
				if mb.pressed:
					_pick_at(mb.position.x)
				accept_event()
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				picked.emit(snap(value + step))
				accept_event()
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				picked.emit(snap(value - step))
				accept_event()
		elif e is InputEventMouseMotion and _dragging:
			_pick_at((e as InputEventMouseMotion).position.x)
			accept_event()

	func _pick_at(x: float) -> void:
		var frac := clampf(x / maxf(size.x, 1.0), 0.0, 1.0)
		picked.emit(snap(lerpf(min_value, max_value, frac)))
