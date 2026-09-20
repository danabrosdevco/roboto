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

# The same two clips the squad manager uses, so the menus and the management
# screen sound like one interface rather than two. Preloaded rather than
# exported for the same reason everything else here is built in code: there is
# no inspector slot to leave blank.
const SFX_HOVER := preload("res://sounds/sfx/psx ui sfx/squad_manager/HoverG.ogg")
const SFX_CONFIRM := preload("res://sounds/sfx/psx ui sfx/ConfirmH.wav")
const SFX_DRONE := preload("res://sounds/sfx/darkdrone/Dark Drone_SI 03.wav")
# By path: a new class_name can be missing from an open editor's class list,
# and this script failing to compile takes the whole front end with it.
const _TutorialLibrary := preload("res://Character/hud/tutorial_library.gd")
const _Analytics := preload("res://Managers/analytics.gd")
const _Lab := preload("res://Managers/lab.gd")
const _LabResults := preload("res://Character/hud/lab_results.gd")
# Which export this is; tools/export.ps1 writes it.
const _Build := preload("res://Managers/build_version.gd")

@export_group("Skip")
# The switch asked for: straight to play, no splash and no menu.
@export var skip_splash: bool = false
## The PLAYTEST DATA entry in the main and pause menus. Off, so an exported
## build does not ship a button that opens a folder of logs. Running from the
## editor shows it anyway; tick this for a build going out to playtesters.
@export var show_playtest_data: bool = false
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

@export_group("Title music")
@export var title_music_volume_db: float = -6.0
## Seconds to fade out when the player starts the game.
@export var title_music_fade_out: float = 1.5

@export_group("Splash timing")
@export var company_seconds: float = 2.4
@export var title_seconds: float = 3.4
@export var fade_seconds: float = 0.45
## How long the suffix takes to fade up ("2109" on the title card, "presents" on
## the company card). It starts only after the headline has finished typing, and
## is clamped so it always completes before the card leaves — raise it past what
## a card has time for and you get that card's maximum rather than a fade that
## gets cut off mid-way.
@export var suffix_fade_seconds: float = 1.6

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

@export_group("Mission briefing")
## Show the baked map and objective list when deploying. Off falls straight
## into the level the way it always did.
@export var show_mission_briefing: bool = true
## Key that opens the map mid-mission. Defaults to M, registered at runtime if
## the project does not already define an action by this name.
@export var map_action: StringName = &"map"

@export_group("Laboratory")
## Skip the game and run AI-vs-AI fights in the arena instead, watched from a
## ghost camera, with the results on screen at the end. Nothing is saved.
## Only from the editor: an exported build ignores it, so it cannot ship on.
@export var lab_mode: bool = false
## Which fights: a LabPlan .tres from Campaign/lab/plans. Typed as Resource so
## this script never waits on the class list (see analytics.gd).
@export var lab_plan: Resource

# ── runtime ───────────────────────────────────
var _layer: CanvasLayer
var _backdrop: ColorRect
var _content: Control
var _filter: ColorRect
var _filter_material: ShaderMaterial

var _booting: bool = false
var _skip_requested: bool = false
var _paused_by_us: bool = false
# "", "main", "pause", "options", "tutorials", "dead" or "lab". ESC closes the
# pause screen but must NOT close the main menu — there is nothing behind it,
# and treating them the same meant ESC started the game. On "dead" and "lab"
# (the results screen) it does nothing.
var _menu: String = ""
var _options: OptionsMenu
var _tutorials: _TutorialLibrary
# The menu the options screen goes back to: "main" or "pause".
var _options_from: String = ""
var _sfx_hover: AudioStreamPlayer
var _sfx_confirm: AudioStreamPlayer
var _drone: AudioStreamPlayer
var _briefing: MissionBriefing
var _briefing_layer: CanvasLayer
var _campaign_hooked: bool = false
# Whether the drone is *meant* to be running. Checked by the finished handler,
# so a stop() never gets undone by a loop that was already in flight.
var _drone_wanted: bool = false
# Cleared by real mouse movement, so a menu appearing under the cursor does not
# chirp for a button you never moved to.
var _suppress_hover: bool = true
var _lab: Node = null


# The earliest point in the boot: _enter_tree runs parent-first, so this lands
# before anything under World has entered the tree. The saved window mode is
# up before the splash, and AudioBuses' routing is already listening when the
# level's sounds arrive.
func _enter_tree() -> void:
	Settings.apply_display()
	Settings.add_listener(_on_setting_changed)


func _exit_tree() -> void:
	Settings.remove_listener(_on_setting_changed)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			Settings.set_window_focused(false)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			Settings.set_window_focused(true)
		NOTIFICATION_WM_CLOSE_REQUEST:
			# Closing the window with the options screen still open.
			Settings.save_if_dirty()


func _ready() -> void:
	# Survives get_tree().paused, which the splash and the pause menu both set.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The build on the taskbar and in the log. The window title would otherwise
	# be the project's name, "Roboto" — and renaming the project instead would
	# move user:// and lose everyone's save.
	get_window().title = "%s %s  %s" % [title_text, title_suffix, _Build.label()]
	print("[Build] %s" % _Build.label())
	_pin_children_pausable()
	_build_audio()
	_build_briefing()
	# Editor runs only. The flag is saved into master.tscn, and a build sent
	# out with it still ticked would boot testers straight into the lab.
	if lab_mode and not OS.has_feature("editor"):
		push_warning("Master: lab_mode is ticked but this is an exported build; starting the game normally.")
		lab_mode = false
	if lab_mode:
		# Lab sessions keep their data apart from playtest sessions.
		if _Analytics.dir_override == "":
			_Analytics.dir_override = "user://lab"
	_build_analytics()
	_hook_world()
	_build_overlay()
	if lab_mode:
		_teardown_overlay()
		_start_lab.call_deferred()
		return
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


# Only here to connect the briefing to Campaign, which loads after Master.
# Stops doing anything at all the moment it succeeds.
func _process(_delta: float) -> void:
	if not _campaign_hooked:
		_hook_campaign()


# Parented to MASTER, not to the overlay. Pressing START tears the overlay down
# in the same frame the confirm plays, and a freed AudioStreamPlayer stops dead
# — the click would be cut off exactly when it should be landing.
func _build_audio() -> void:
	# Buses set BEFORE add_child, so AudioBuses' default routing sees them
	# already claimed and leaves them alone.
	_sfx_hover = AudioStreamPlayer.new()
	_sfx_hover.stream = SFX_HOVER
	_sfx_hover.max_polyphony = 2
	_sfx_hover.bus = AudioBuses.INTERFACE
	_sfx_hover.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sfx_hover)

	_sfx_confirm = AudioStreamPlayer.new()
	_sfx_confirm.stream = SFX_CONFIRM
	_sfx_confirm.bus = AudioBuses.INTERFACE
	_sfx_confirm.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sfx_confirm)

	_drone = AudioStreamPlayer.new()
	_drone.stream = SFX_DRONE
	_drone.bus = AudioBuses.MUSIC
	_drone.volume_db = title_music_volume_db
	# ALWAYS for the same reason as the click sounds: the splash and the menu
	# both run with the tree paused.
	_drone.process_mode = Node.PROCESS_MODE_ALWAYS
	# The clip is ~22s and a player can sit on the menu indefinitely. The WAV is
	# imported with loop_mode=Forward so this should never fire, but a reimport
	# that resets loop_mode would otherwise silently kill the music partway
	# through the menu — and that is a hard thing to notice.
	_drone.finished.connect(func() -> void:
		if _drone_wanted:
			_drone.play())
	add_child(_drone)


# ─────────────────────────────────────────────
# MISSION BRIEFING
#
# On its OWN CanvasLayer rather than inside the splash overlay, because
# _teardown_overlay() frees that one the moment play starts — and the briefing
# has to survive to be shown on every later deploy, not just the first.
# ─────────────────────────────────────────────
func _build_briefing() -> void:
	_briefing_layer = CanvasLayer.new()
	_briefing_layer.layer = 90
	_briefing_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_briefing_layer)

	_briefing = MissionBriefing.new()
	# The blip is the menu hover click. It is short, dry and already in the
	# project's voice, which is all a radar return needs to be.
	_briefing.blip_sound = _sfx_hover
	_briefing_layer.add_child(_briefing)
	_briefing.finished.connect(_on_briefing_finished)

	# Registered at runtime rather than authored into project.godot: an
	# InputMap entry there is a wall of serialised InputEventKey and getting one
	# character wrong breaks input silently. A real action of the same name in
	# project.godot still wins, so this is only a default. Settings registers
	# &"map" too, because it must exist before key bindings load — whichever
	# runs first makes it, and this then finds it already there.
	if not InputMap.has_action(map_action):
		InputMap.add_action(map_action)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_M
		InputMap.action_add_event(map_action, ev)


# Campaign lives under World, which is loaded after Master, so there is nothing
# to connect to in _ready. Polled until it answers rather than relying on a
# one-shot deferred call that would silently miss if World took a frame longer.
func _hook_campaign() -> void:
	if _campaign_hooked:
		return
	var c := get_tree().get_first_node_in_group("campaign")
	if c == null or not c.has_signal("deployed"):
		return
	if not c.is_connected("deployed", _on_deployed):
		c.connect("deployed", _on_deployed)
	_campaign_hooked = true


func _on_deployed(mission) -> void:
	if not show_mission_briefing or _briefing == null:
		return
	# ITS OWN named hold. This fires from inside world.gd's level load, which
	# holds "level_load" and releases it once the level is in — and that
	# release used to unpause the game while the briefing was still waiting
	# for a keypress. With separate holds the tree stays paused until BOTH are
	# gone, so the level can finish loading behind a briefing that is still up.
	PauseHold.take(&"briefing")
	_show_mouse()
	_briefing.brief(mission)


func _on_briefing_finished() -> void:
	PauseHold.release(&"briefing")
	_capture_mouse()


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
	# Scaled by the SCREEN NOISE option, same as the HUD's filter — see
	# _apply_screen_noise.
	var noise := Settings.get_float("display.screen_noise")
	mat.set_shader_parameter("grain", splash_grain * noise)
	mat.set_shader_parameter("dropout", splash_dropout * noise)
	mat.set_shader_parameter("block_glitch", splash_block_glitch * noise)
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
	# The options screen lives in here too; whatever clears it, it is gone.
	_options = null
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
	# From the company card onward — it carries the whole sequence through the
	# title and under the main menu, and only lets go when the player starts.
	_start_title_music()

	# "presents" goes in the SUFFIX slot, not the `above` slot — the studio name
	# is the headline and "presents" is the thing it does, so it reads
	# "DANA ENTERTAINMENT PRODUCTS presents" top to bottom. In the `above` slot
	# it read as "presents DANA ENTERTAINMENT PRODUCTS", which is backwards.
	await _play_card("", company_text, presents_text, company_seconds, HUDPalette.DIM, HUDPalette.DIM)
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

	# Tweens are created FROM the node they animate, not from Master. A tween
	# bound to a node dies with it; one owned by Master outlived the card's
	# labels and logged "Target object freed before starting" every transition.
	#
	# CRT power-on: the shader's own boot uniform ramps 1 -> 0.
	_filter_material.set_shader_parameter("boot", 1.0)
	var boot_tween := _filter.create_tween()
	boot_tween.tween_method(
		func(v: float): _filter_material.set_shader_parameter("boot", v),
		1.0, 0.0, minf(0.8, seconds * 0.4))

	var reveal := maxf(0.35, seconds * 0.35)
	var type_tween := head.create_tween()
	type_tween.tween_property(head, "visible_ratio", 1.0, reveal)
	if tail != null:
		# Chained AFTER the headline types, so the time still available is
		# `seconds` minus the reveal. Clamped to that, less a little headroom,
		# because the company card is the short one: an unclamped 1.6s fade
		# there would still be climbing when the card started fading out, and
		# "presents" would never reach full brightness.
		var suffix_fade := minf(suffix_fade_seconds, maxf(0.15, seconds - reveal - 0.15))
		type_tween.tween_property(tail, "modulate:a", 1.0, suffix_fade)

	await _wait(seconds)

	# Fade the card out, unless the player is skipping — then cut.
	if not _skip_requested:
		var fade := _content.create_tween()
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
	var items: Array = [{"text": "START", "action": _start_play}]
	if _playtest_data_shown():
		items.append({"text": "PLAYTEST DATA", "action": _open_playtest_data})
	items.append({"text": "OPTIONS", "action": _open_options})
	items.append({"text": "QUIT", "action": _quit})
	_build_menu(menu_title_text, items, HUDPalette.BRIGHT, title_suffix)


func _show_pause_menu() -> void:
	if _layer == null:
		_build_overlay()
	_menu = "pause"
	# The pause screen sits over the game, so the backdrop is a wash rather than
	# the splash's solid black.
	_backdrop.color = Color(0.02, 0.03, 0.03, 0.82)
	_hold_pause()
	_show_mouse()
	var items: Array = [{"text": "CONTINUE", "action": _resume_from_pause},
		{"text": "TUTORIALS", "action": _open_tutorials}]
	if _playtest_data_shown():
		items.append({"text": "PLAYTEST DATA", "action": _open_playtest_data})
	items.append({"text": "OPTIONS", "action": _open_options})
	items.append({"text": "QUIT", "action": _quit})
	_build_menu("PAUSED", items, HUDPalette.WARN)


# ─────────────────────────────────────────────
# DEATH
# YOU DIED, then CONTINUE or EXIT. The same overlay, filter and pause hold as
# the pause menu, so the world freezes behind it exactly as it does there. ESC
# does nothing on this screen: there is no game to go back to until you pick.
# ─────────────────────────────────────────────
# Shown when this build is meant to collect data: an editor run always, an
# export only if it was built for playtesting.
func _playtest_data_shown() -> bool:
	return show_playtest_data or OS.is_debug_build()


# ─────────────────────────────────────────────
# PLAYTEST DATA
# The recorder lives here, above World, so it outlives every level load. It
# switches itself off for headless and --script runs. The menu button opens its
# folder, so a playtester can find the files to send back without being told
# where Godot keeps user data.
# ─────────────────────────────────────────────
func _build_analytics() -> void:
	var recorder := _Analytics.new()
	recorder.name = "Analytics"
	add_child(recorder)


func _open_playtest_data() -> void:
	DirAccess.make_dir_recursive_absolute(_Analytics.ROOT)
	OS.shell_open(_Analytics.folder())


# ─────────────────────────────────────────────
# LABORATORY
# lab_mode replaces the game with Lab: AI-vs-AI fights from lab_plan, watched
# from a ghost camera, scored by the analytics recorder, and summed up on the
# results screen below. ESC still pauses; QUIT ends it.
# ─────────────────────────────────────────────
func _start_lab() -> void:
	# World finishes its own boot a frame or two after ours (it awaits a frame
	# in _ready, then loads the base); the lab takes over from there.
	for _i in 10:
		await get_tree().process_frame
	if lab_plan == null:
		push_warning("Master: lab_mode is on but no lab_plan is set. Pick one from Campaign/lab/plans.")
		return
	_lab = _Lab.new()
	_lab.name = "Lab"
	_lab.plan = lab_plan
	_lab.world = _world()
	_lab.recorder = get_node_or_null("Analytics")
	add_child(_lab)
	_lab.finished.connect(_show_lab_results)
	_capture_mouse()
	_lab.run()


func _show_lab_results(report_path: String) -> void:
	if _layer == null:
		_build_overlay()
	_menu = "lab"
	_backdrop.color = Color(0.02, 0.03, 0.03, 0.82)
	_hold_pause()
	_show_mouse()
	_clear_content()
	var screen = _LabResults.new()
	screen.title = str(lab_plan.get("title"))
	screen.rows = _lab.summary()
	screen.report_path = report_path
	screen.hover_sound = _sfx_hover
	screen.confirm_sound = _sfx_confirm
	screen.run_again.connect(func() -> void:
		_teardown_overlay()
		_lab.run(), CONNECT_DEFERRED)
	screen.open_report.connect(func() -> void:
		if report_path != "":
			OS.shell_open(report_path.get_base_dir()))
	screen.quit_game.connect(_quit)
	_content.add_child(screen)


func _hook_world() -> void:
	var world := _world()
	if world != null and not world.player_killed.is_connected(_show_death_menu):
		world.player_killed.connect(_show_death_menu)


func _world() -> World:
	for child in get_children():
		if child is World:
			return child
	return null


func _show_death_menu() -> void:
	if _layer == null:
		_build_overlay()
	_menu = "dead"
	_backdrop.color = Color(0.06, 0.01, 0.01, 0.86)
	_hold_pause()
	_show_mouse()
	_build_menu("YOU DIED", [
		{"text": "CONTINUE", "action": _continue_after_death},
		{"text": "EXIT", "action": _quit},
	], HUDPalette.CRIT)


# Back to base: a failed extraction if you were on an operation, a fresh start
# at the spawn point if you were already home.
func _continue_after_death() -> void:
	_teardown_overlay()
	var world := _world()
	if world != null:
		world.return_home_after_death()


# ─────────────────────────────────────────────
# TUTORIALS
# Every homebase lesson on one screen. Pause menu only: it is where the base's
# one remaining sign sends a returning player, and it has to work mid-mission,
# when the signs themselves are not loaded.
# ─────────────────────────────────────────────
func _open_tutorials() -> void:
	if not is_instance_valid(_content):
		return
	_menu = "tutorials"
	_clear_content()
	_tutorials = _TutorialLibrary.new()
	_tutorials.hover_sound = _sfx_hover
	_tutorials.confirm_sound = _sfx_confirm
	# Deferred for the same reason as the options screen: BACK closes it from
	# inside its own button's pressed signal.
	_tutorials.closed.connect(_close_tutorials, CONNECT_DEFERRED)
	_content.add_child(_tutorials)


func _close_tutorials() -> void:
	if _menu != "tutorials":
		return
	_tutorials = null
	_show_pause_menu()


# ─────────────────────────────────────────────
# OPTIONS
# Built into the same overlay as the menu that opened it, so it is under the
# same filter and the same pause hold. The pause hold is already taken by the
# menu; the options screen changes nothing about it. Returning rebuilds that
# menu from scratch, exactly as ESC-ing into it would.
# ─────────────────────────────────────────────
func _open_options() -> void:
	if not is_instance_valid(_content):
		return
	_options_from = _menu
	_menu = "options"
	_clear_content()
	_options = OptionsMenu.new()
	_options.hover_sound = _sfx_hover
	_options.confirm_sound = _sfx_confirm
	# DEFERRED. BACK closes this screen from inside its own button's pressed
	# signal, and rebuilding the menu frees that button mid-emit.
	_options.closed.connect(_close_options, CONNECT_DEFERRED)
	_content.add_child(_options)


func _close_options() -> void:
	if _menu != "options":
		return
	_options = null
	Settings.save_if_dirty()
	if _options_from == "pause":
		_show_pause_menu()
	else:
		_show_main_menu()


# SCREEN NOISE reaches this overlay's filter live, so turning it down in the
# options screen visibly calms the screen you are looking at.
func _on_setting_changed(key: String) -> void:
	if key != "display.screen_noise" and key != "*":
		return
	if _filter_material == null:
		return
	var noise := Settings.get_float("display.screen_noise")
	_filter_material.set_shader_parameter("grain", splash_grain * noise)
	_filter_material.set_shader_parameter("dropout", splash_dropout * noise)
	_filter_material.set_shader_parameter("block_glitch", splash_block_glitch * noise)


func _build_menu(title: String, entries: Array, title_col: Color,
		subtitle: String = "") -> void:
	_clear_content()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	_content.add_child(box)

	box.add_child(_centred_label(title, title_col, 56))
	# The year, carried over from the title card so the menu is the same
	# wordmark rather than a different one. WARN is the colour it uses there.
	if subtitle != "":
		box.add_child(_centred_label(subtitle, HUDPalette.WARN, 40))

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
		button.mouse_entered.connect(_on_menu_hover)
		# Confirm BEFORE the action: START and CONTINUE both tear the overlay
		# down, and the sound has to be away before its button stops existing.
		var action: Callable = entry["action"]
		button.pressed.connect(func():
			_sfx_confirm.play()
			action.call())
		box.add_child(button)

	# Which build this is, in the corner of every menu, so a playtester's
	# screenshot or bug report says which export it came from.
	var build := _centred_label(_Build.label(), HUDPalette.DIM, 20)
	_content.add_child(build)
	build.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 18)

	# A menu built under a stationary cursor fires mouse_entered on whatever
	# happens to be beneath it, which chirps at you for a button you did not
	# move to. Same guard the squad manager uses.
	_suppress_hover = true


func _on_menu_hover() -> void:
	if _suppress_hover:
		return
	_sfx_hover.play()


func _start_play() -> void:
	_stop_title_music()
	_teardown_overlay()


func _start_title_music() -> void:
	if _drone == null:
		return
	_drone_wanted = true
	_drone.volume_db = title_music_volume_db
	_drone.play()


# Fades rather than cuts. The drone is still going under the menu when the
# player presses START, and killing it on the same frame the world appears
# reads as a glitch rather than a transition.
func _stop_title_music() -> void:
	if _drone == null or not _drone_wanted:
		return
	_drone_wanted = false
	if title_music_fade_out <= 0.0:
		_drone.stop()
		return
	var tween := create_tween()
	tween.tween_property(_drone, "volume_db", -60.0, title_music_fade_out)
	tween.tween_callback(_drone.stop)


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
	# A real mouse movement re-arms hover audio after a menu is built underneath
	# a stationary cursor.
	if event is InputEventMouseMotion:
		_suppress_hover = false

	# Rebinding a key: whatever is pressed next belongs to the options screen,
	# even if it is the fullscreen key or ESC. OptionsMenu sees input first
	# (deeper in the tree) and takes it; this is the brace to that belt.
	if is_instance_valid(_options) and _options.is_capturing():
		return

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

	# THE MAP. Checked before the pause handling below, and only while actually
	# on an operation — there is nothing to show at base, and the briefing
	# screen must not be openable on top of itself.
	if event.is_action_pressed(map_action) and not _booting and _menu == "":
		if _briefing != null and _briefing.is_open():
			get_viewport().set_input_as_handled()
			return
		var c := get_tree().get_first_node_in_group("campaign")
		if c != null and bool(c.get("in_mission")) and _briefing != null:
			get_viewport().set_input_as_handled()
			# Same hold as the briefing: they are one screen in two modes, and
			# _on_briefing_finished releases it whichever one closed.
			PauseHold.take(&"briefing")
			_show_mouse()
			_briefing.open_map(c.get("current_mission"))
			return

	var esc: bool = event is InputEventKey and event.pressed and not event.echo \
		and event.keycode == KEY_ESCAPE

	# ESC in the options screen is BACK, to whichever menu opened it. Ahead of
	# the pause_enabled check: the main menu's options screen still needs a way
	# out with pausing switched off.
	if esc and _menu == "options":
		get_viewport().set_input_as_handled()
		if is_instance_valid(_options):
			_options.back()
		return
	if esc and _menu == "tutorials":
		get_viewport().set_input_as_handled()
		if is_instance_valid(_tutorials):
			_tutorials.back()
		return

	if not pause_enabled:
		return
	if not esc:
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
# The splash, main menu and pause menu share one hold, because only one of
# them is ever up at a time. The briefing and map take their OWN (see
# _on_deployed) — sharing this one meant closing either would release both.
func _hold_pause() -> void:
	if _paused_by_us:
		return
	_paused_by_us = true
	PauseHold.take(&"master")


func _release_pause() -> void:
	if not _paused_by_us:
		return
	_paused_by_us = false
	PauseHold.release(&"master")


# Windowed <-> borderless, through Settings so the choice is remembered and the
# options screen shows it. Settings does the actual window work (flag and mode
# together, so returning to windowed cannot leave a window with no frame).
# Saved immediately: nobody expects a hotkey to need an options screen to stick.
func _toggle_fullscreen() -> void:
	var windowed := Settings.get_string("display.window_mode") == "windowed"
	Settings.set_value("display.window_mode", "borderless" if windowed else "windowed")
	Settings.save()


func _show_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
