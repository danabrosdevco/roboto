extends Node
class_name Master

# ─────────────────────────────────────────────
# MASTER — the boot flow, and the only thing above World.
#
#   splash (company card -> title card) -> optional FPO main menu -> play
#   ESC at any time during play -> pause menu -> continue or quit
#
# Built in code and self-wiring, same as the HUDs, so there is no inspector slot
# to leave blank and nothing fails silently if a node gets renamed.
#
# THE OVERLAY COVERS THE WORLD RATHER THAN DEFERRING IT. World is still a child
# of master.tscn and still readies at startup; the splash is a CanvasLayer at a
# high layer painted over the top. Instantiating World after the splash instead
# would be the tidier "load after" — but it moves when every node in the game
# readies, and this project already has a documented ready-order hazard in
# world.tscn. Covering cannot break booting. If the splash misbehaves, tick
# skip_splash and the game is exactly as it was.
#
# The whole sequence runs on the same signal_filter shader the HUD uses, so the
# splash is inside the CRT rather than sitting in front of it.
# ─────────────────────────────────────────────

const FILTER_SHADER := preload("res://Character/hud/signal_filter.gdshader")

@export_group("Skip")
# The switch asked for: straight to play, no splash and no menu.
@export var skip_splash: bool = false
# Let a key or click cut the splash short. Independent of skip_splash so you can
# keep the splash but not be trapped in it while iterating.
@export var allow_input_skip: bool = true

@export_group("Splash text")
# NOTE: the brief spelled this "DANA ENERTAINMENT PRODUCTS". Corrected to
# ENTERTAINMENT on the assumption it was a typo — if it was deliberate, this is
# the one line to change and nothing else needs touching.
# Newlines are deliberate: the company card stacks vertically.
@export_multiline var company_text: String = "DANA\nENTERTAINMENT\nPRODUCTS"
@export var title_text: String = "DATA CENTER WARS"
@export var title_suffix: String = "2109"
@export var presents_text: String = "presents"

@export_group("Splash timing")
@export var company_seconds: float = 2.4
@export var title_seconds: float = 3.4
@export var fade_seconds: float = 0.45

@export_group("Splash filter")
# The splash runs a GENTLER version of the HUD's filter. At the HUD's own
# settings the artefacts sit on top of large text and eat it — fine over a 3D
# scene you are reading as an image, bad over words you are reading as words.
# Raising signal_height and dropping the noise keeps the look without costing
# legibility.
@export var splash_signal_height: float = 540.0
@export_range(0.0, 1.5) var splash_dither: float = 0.3
@export_range(0.0, 0.3) var splash_grain: float = 0.02
@export_range(0.0, 1.0) var splash_block_glitch: float = 0.03
@export_range(0.0, 0.2) var splash_dropout: float = 0.0
@export_range(0.0, 1.0) var splash_palette_strength: float = 0.6
@export_range(0.0, 2.0) var splash_edge_strength: float = 0.35

@export_group("Menus")
# FPO main menu between the splash and play. Off means the splash hands
# straight over to the game.
@export var show_main_menu: bool = true
@export var menu_title_text: String = "DATA CENTER WARS"
@export var pause_enabled: bool = true

# ── runtime ───────────────────────────────────
var _layer: CanvasLayer
var _backdrop: ColorRect
var _content: Control
var _filter: ColorRect
var _filter_material: ShaderMaterial

var _booting: bool = false
var _skip_requested: bool = false
var _paused_by_us: bool = false
# "", "main" or "pause". ESC closes the pause screen but must NOT close the main
# menu — there is nothing behind it, and treating them the same meant ESC
# started the game.
var _menu: String = ""


func _ready() -> void:
	# Survives get_tree().paused, which the splash and the pause menu both set.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pin_children_pausable()
	_build_overlay()
	if skip_splash:
		_teardown_overlay()
		return
	_run_boot()


# ─────────────────────────────────────────────
# OVERLAY
# One CanvasLayer holding: black backdrop, content, filter. The filter is LAST
# because signal_filter samples the screen texture — it has to be drawn after
# the thing it is meant to be filtering.
# ─────────────────────────────────────────────
# PROCESS_MODE_ALWAYS IS INHERITED. Every node under World uses the default
# PROCESS_MODE_INHERIT, and World is a child of Master — so setting ALWAYS on
# Master alone handed it to the entire game and nothing could be paused again.
# The squad manager, level loading in world.gd and this script's own pause menu
# all set get_tree().paused and all of them silently stopped working.
#
# Master has to be ALWAYS so ESC and F still answer while paused. World is
# pinned back to PAUSABLE so the exemption stops at Master and its overlay.
# Anything under World that genuinely needs to run while paused sets ALWAYS on
# itself, as the squad manager already does.
func _pin_children_pausable() -> void:
	for child in get_children():
		child.process_mode = Node.PROCESS_MODE_PAUSABLE


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	# Above the HUD, which is a plain Control in the default layer.
	_layer.layer = 128
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.02, 0.03, 0.03)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_backdrop)

	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_content)

	_filter = ColorRect.new()
	_filter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter_material = _make_filter_material()
	_filter.material = _filter_material
	_layer.add_child(_filter)


# Values copied from the SignalFilter material in hud.tscn rather than left to
# the shader's own defaults, which differ (palette_strength 0.55 vs 1.0,
# signal_fps 15 vs 8). Matching them is what makes the splash look like the game
# instead of merely similar to it.
func _make_filter_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FILTER_SHADER
	mat.set_shader_parameter("quantize_resolution", true)
	mat.set_shader_parameter("signal_height", splash_signal_height)
	mat.set_shader_parameter("cell_average", true)
	mat.set_shader_parameter("chroma_divisor", 2.0)
	mat.set_shader_parameter("exposure", 1.05)
	mat.set_shader_parameter("contrast", 1.12)
	mat.set_shader_parameter("black_lift", 0.05)
	mat.set_shader_parameter("luma_levels", 10.0)
	mat.set_shader_parameter("chroma_levels", 5.0)
	mat.set_shader_parameter("saturation", 0.9)
	mat.set_shader_parameter("shadow_tint", Color(0.05, 0.11, 0.12))
	mat.set_shader_parameter("mid_tint", Color(0.3, 0.46, 0.38))
	mat.set_shader_parameter("high_tint", Color(0.87, 0.94, 0.72))
	mat.set_shader_parameter("palette_strength", splash_palette_strength)
	mat.set_shader_parameter("edge_color", Color(0.02, 0.06, 0.06))
	mat.set_shader_parameter("edge_strength", splash_edge_strength)
	mat.set_shader_parameter("edge_threshold", 0.06)
	mat.set_shader_parameter("dither_strength", splash_dither)
	mat.set_shader_parameter("signal_fps", 8.0)
	mat.set_shader_parameter("grain", splash_grain)
	mat.set_shader_parameter("dropout", splash_dropout)
	mat.set_shader_parameter("block_glitch", splash_block_glitch)
	mat.set_shader_parameter("block_size", 8.0)
	mat.set_shader_parameter("damage", 0.0)
	mat.set_shader_parameter("boot", 0.0)
	return mat


func _teardown_overlay() -> void:
	_clear_content()
	if is_instance_valid(_layer):
		# remove_child before queue_free: queue_free is deferred and the node
		# stays a child until end of frame. Same reason the squad manager does
		# it — a rebuild in the same frame otherwise finds the old nodes still
		# parented.
		remove_child(_layer)
		_layer.queue_free()
	_layer = null
	_backdrop = null
	_content = null
	_filter = null
	_menu = ""
	_release_pause()
	_capture_mouse()


func _clear_content() -> void:
	if not is_instance_valid(_content):
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()


# ─────────────────────────────────────────────
# BOOT SEQUENCE
# ─────────────────────────────────────────────
func _run_boot() -> void:
	_booting = true
	_hold_pause()
	_show_mouse()

	await _play_card(presents_text, company_text, "", company_seconds, HUDPalette.DIM, HUDPalette.BRIGHT)
	if _booting:
		await _play_card("", title_text, title_suffix, title_seconds, HUDPalette.BRIGHT, HUDPalette.WARN)

	_booting = false
	_skip_requested = false

	if show_main_menu:
		_show_main_menu()
	else:
		_start_play()


# One card: an optional small line above, a headline, an optional suffix in a
# second colour. Returns when its time is up or the player skipped.
func _play_card(above: String, headline: String, suffix: String, seconds: float,
		above_col: Color, suffix_col: Color) -> void:
	_clear_content()

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(box)

	if above != "":
		box.add_child(_centred_label(above, above_col, 22))

	# visible_ratio drives a terminal-style character reveal. If a tween ever
	# fails to run, the worst case is the text simply appearing at once.
	var head := _centred_label(headline, HUDPalette.BRIGHT, 64)
	head.visible_ratio = 0.0
	box.add_child(head)

	var tail: Label = null
	if suffix != "":
		tail = _centred_label(suffix, suffix_col, 40)
		tail.modulate.a = 0.0
		box.add_child(tail)

	# CRT power-on: the shader's own boot uniform ramps 1 -> 0.
	_filter_material.set_shader_parameter("boot", 1.0)
	var boot_tween := create_tween()
	boot_tween.tween_method(
		func(v: float): _filter_material.set_shader_parameter("boot", v),
		1.0, 0.0, minf(0.8, seconds * 0.4))

	var reveal := maxf(0.35, seconds * 0.35)
	var type_tween := create_tween()
	type_tween.tween_property(head, "visible_ratio", 1.0, reveal)
	if tail != null:
		type_tween.tween_property(tail, "modulate:a", 1.0, 0.35)

	await _wait(seconds)

	# Fade the card out, unless the player is skipping — then cut.
	if not _skip_requested:
		var fade := create_tween()
		fade.tween_property(_content, "modulate:a", 0.0, fade_seconds)
		await _wait(fade_seconds)
	_content.modulate.a = 1.0
	_clear_content()


func _centred_label(text: String, col: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", col)
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# Waits real seconds even though the tree is paused, and returns the moment a
# skip lands. Accumulates frame deltas rather than using a SceneTreeTimer,
# because a timer cannot be cut short — a skip would start the next card while
# the previous one's timer was still pending.
func _wait(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		if _skip_requested:
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()


# ─────────────────────────────────────────────
# MENUS
# ─────────────────────────────────────────────
func _show_main_menu() -> void:
	_menu = "main"
	_hold_pause()
	_show_mouse()
	_build_menu(menu_title_text, [
		{"text": "START", "action": _start_play},
		{"text": "QUIT", "action": _quit},
	], HUDPalette.BRIGHT)


func _show_pause_menu() -> void:
	if _layer == null:
		_build_overlay()
	_menu = "pause"
	# The pause screen sits over the game, so the backdrop is a wash rather than
	# the splash's solid black.
	_backdrop.color = Color(0.02, 0.03, 0.03, 0.82)
	_hold_pause()
	_show_mouse()
	_build_menu("PAUSED", [
		{"text": "CONTINUE", "action": _resume_from_pause},
		{"text": "QUIT", "action": _quit},
	], HUDPalette.WARN)


func _build_menu(title: String, entries: Array, title_col: Color) -> void:
	_clear_content()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	_content.add_child(box)

	box.add_child(_centred_label(title, title_col, 56))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	box.add_child(spacer)

	for entry in entries:
		var button := Button.new()
		button.text = entry["text"]
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 44)
		button.add_theme_font_size_override("font_size", 34)
		# Bright at rest. DIM is for labels you are not meant to act on, and
		# these are the only two things on the screen you can act on.
		button.add_theme_color_override("font_color", HUDPalette.BRIGHT)
		button.add_theme_color_override("font_hover_color", Color(0.86, 1.0, 0.88))
		button.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
		button.add_theme_color_override("font_focus_color", HUDPalette.BRIGHT)
		button.pressed.connect(entry["action"])
		box.add_child(button)


func _start_play() -> void:
	_teardown_overlay()


func _resume_from_pause() -> void:
	_teardown_overlay()


func _quit() -> void:
	get_tree().quit()


# ─────────────────────────────────────────────
# INPUT
# _input rather than _unhandled_input, and the event is marked handled, so ESC
# does not also reach test_character._unhandled_input — which frees the mouse
# and would otherwise fire alongside the pause menu.
# ─────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	# Fullscreen lives HERE, not on the player. It used to be polled in
	# test_character.handle_input, which runs from _physics_process — so it was
	# dead whenever the tree was paused (squad manager open, splash, pause menu)
	# or the player was in spectator mode. Master runs on PROCESS_MODE_ALWAYS,
	# so F works everywhere.
	if event.is_action_pressed("fullscreen") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_toggle_fullscreen()
		return

	if _booting:
		if not allow_input_skip:
			return
		var skip: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed)
		if skip:
			get_viewport().set_input_as_handled()
			_skip_requested = true
		return

	if not pause_enabled:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_ESCAPE:
		return

	# The main menu deliberately ignores ESC: there is no game behind it yet, so
	# closing it would drop the player into an unstarted world.
	if _menu == "main":
		return
	if _menu == "pause":
		get_viewport().set_input_as_handled()
		_resume_from_pause()
		return

	# Something else already paused — the squad manager, or a level load. Do not
	# stack a second pause on top of it.
	if get_tree().paused:
		return

	get_viewport().set_input_as_handled()
	_show_pause_menu()


# ─────────────────────────────────────────────
# PAUSE / MOUSE
# Tracked with a flag so we only ever unpause a pause we caused. world.gd pauses
# during level loads and the squad manager pauses while it is open; clearing
# those from here would resume the game underneath them.
# ─────────────────────────────────────────────
func _hold_pause() -> void:
	if _paused_by_us:
		return
	_paused_by_us = true
	get_tree().paused = true


func _release_pause() -> void:
	if not _paused_by_us:
		return
	_paused_by_us = false
	get_tree().paused = false


# Borderless fullscreen, explicitly. WINDOW_MODE_FULLSCREEN is already the
# borderless one in Godot 4 (EXCLUSIVE_FULLSCREEN is the other), but the
# BORDERLESS flag is set as well so returning to windowed cannot leave the
# window without its frame.
func _toggle_fullscreen() -> void:
	var is_full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	else:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _show_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
