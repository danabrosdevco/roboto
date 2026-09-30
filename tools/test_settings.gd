extends SceneTree

# ─────────────────────────────────────────────
# SETTINGS & OPTIONS — does every option actually reach the thing it controls,
# and does the file survive being saved, reloaded, hand-edited and corrupted?
#
# Boots the real master.tscn (splash skipped), so this is the same Settings,
# the same HUD, the same player and the same menus the game runs. Points
# Settings at a scratch file FIRST, before anything can touch it, so a test run
# never overwrites the settings.json you actually play with.
# ─────────────────────────────────────────────

const TEST_PATH := "user://settings_test.json"

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_fails += 1


func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _key(code: Key, shift: bool = false) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.pressed = true
	k.shift_pressed = shift
	return k


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var m := InputEventMouseButton.new()
	m.button_index = button
	m.pressed = true
	return m


func _write(text: String) -> void:
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _wipe() -> void:
	for p in [TEST_PATH, TEST_PATH + ".bad"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _init() -> void:
	# BEFORE anything else — Master's _enter_tree is Settings' first touch.
	Settings.path = TEST_PATH
	_wipe()
	await process_frame

	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = true
	# Autosave off: this reads the save on this machine but must never write it.
	(master.find_child("CampaignManager", true, false) as CampaignManager).autosave = false
	root.add_child(master)
	for _i in 90:
		await physics_frame

	# ── DEFAULTS ─────────────────────────────────
	_check("no file means defaults",
		Settings.get_float("display.fov") == 70.0 and Settings.get_bool("audio.subtitles")
		and not Settings.get_bool("display.show_fps") and Settings.get_string("display.window_mode") == "windowed")

	# ── AUDIO BUSES ──────────────────────────────
	for b in AudioBuses.CHILDREN:
		_check("bus %s exists" % b, AudioServer.get_bus_index(b) != -1)
	var music_i := AudioServer.get_bus_index(AudioBuses.MUSIC)
	Settings.set_value("audio.music", 0.5)
	_check("music at 50% sits about -12dB", absf(AudioServer.get_bus_volume_db(music_i) - linear_to_db(0.25)) < 0.05,
		"%.2fdB" % AudioServer.get_bus_volume_db(music_i))
	Settings.set_value("audio.music", 0.0)
	_check("music at 0 is muted outright", AudioServer.is_bus_mute(music_i))
	Settings.set_value("audio.music", 1.0)
	_check("...and back up unmutes", not AudioServer.is_bus_mute(music_i))
	Settings.set_value("audio.mute_unfocused", true)
	Settings.set_window_focused(false)
	_check("mute in background mutes Master when focus goes",
		AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioBuses.MASTER)))
	Settings.set_window_focused(true)
	_check("...and restores it when focus comes back",
		not AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioBuses.MASTER)))
	Settings.set_value("audio.mute_unfocused", false)

	# ── ROUTING ──────────────────────────────────
	var fx := AudioStreamPlayer3D.new()
	root.add_child(fx)
	_check("a player that names no bus lands on Effects", fx.bus == AudioBuses.EFFECTS, str(fx.bus))
	var claimed := AudioStreamPlayer.new()
	claimed.bus = AudioBuses.MUSIC
	root.add_child(claimed)
	_check("a player that names its bus keeps it", claimed.bus == AudioBuses.MUSIC)
	var drone: AudioStreamPlayer = master.get("_drone")
	_check("the title theme is on Music", drone != null and drone.bus == AudioBuses.MUSIC)
	var menu_click: AudioStreamPlayer = master.get("_sfx_confirm")
	_check("menu clicks are on Interface", menu_click != null and menu_click.bus == AudioBuses.INTERFACE)
	var smui := _find(root, "SquadManagerUI")
	_check("squad manager clicks are on Interface",
		smui != null and smui.sfx_hover != null and smui.sfx_hover.bus == AudioBuses.INTERFACE)
	var any_bark: Bark = _find(root, "Bark")
	if any_bark != null:
		_check("radio chatter is on Voice", any_bark.audio_player.bus == AudioBuses.VOICE)

	# ── VALIDATION ───────────────────────────────
	Settings.set_value("display.fov", 500.0)
	_check("out-of-range clamps", Settings.get_float("display.fov") == 90.0)
	Settings.set_value("display.max_fps", 77)
	_check("a frame limit that is not on the list falls back", Settings.get_int("display.max_fps") == 0)
	Settings.set_value("display.window_mode", "potato")
	_check("an unknown window mode falls back", Settings.get_string("display.window_mode") == "windowed")
	Settings.set_value("display.window_size", "12x5")
	_check("a silly window size falls back", Settings.get_string("display.window_size") == "maximised")
	Settings.set_value("display.window_size", "1600x900")
	_check("a real window size sticks", Settings.get_string("display.window_size") == "1600x900")
	_check("the monitor starts on AUTO", Settings.get_int("display.monitor") == -1
		and Settings.monitor_label(-1) == "AUTO")
	Settings.set_value("display.monitor", "left")
	_check("a nonsense monitor falls back to AUTO", Settings.get_int("display.monitor") == -1)
	Settings.set_value("display.monitor", 3)
	_check("an unplugged monitor is kept, listed, and says so",
		Settings.get_int("display.monitor") == 3 and Settings.monitor_choices().has(3)
		and Settings.monitor_label(3).contains("NOT FOUND"), Settings.monitor_label(3))
	Settings.set_value("display.monitor", -1)

	# ── ROUND TRIP ───────────────────────────────
	Settings.set_value("display.fov", 82.0)
	Settings.set_value("audio.effects", 0.35)
	Settings.set_value("controls.invert_y", true)
	Settings.set_value("display.max_fps", 144)
	_check("save writes the file", Settings.save() and FileAccess.file_exists(TEST_PATH))
	Settings.set_value("display.fov", 60.0)   # dirty it in memory
	Settings.reload_from_disk()
	_check("reload brings back what was saved",
		Settings.get_float("display.fov") == 82.0 and is_equal_approx(Settings.get_float("audio.effects"), 0.35)
		and Settings.get_bool("controls.invert_y") and Settings.get_int("display.max_fps") == 144,
		"fov=%s fx=%s inv=%s fps=%s" % [Settings.get_value("display.fov"), Settings.get_value("audio.effects"),
			Settings.get_value("controls.invert_y"), Settings.get_value("display.max_fps")])
	var saved := FileAccess.get_file_as_string(TEST_PATH)
	_check("the file is sectioned JSON a person can read",
		saved.contains("\"display\"") and saved.contains("\"fov\": 82"))

	# ── HAND-EDITED FILE ─────────────────────────
	_write(JSON.stringify({
		"version": 1,
		"display": {"fov": "wide", "brightness": 9.0, "vsync": "yes", "show_fps": true},
		"audio": {"music": -3, "voice": 0.4},
		"nonsense": {"a": 1},
		"bindings": {"jump": {"key": "space"}, "not_an_action": {"key": 75}, "reload": {"mouse": 99}},
	}))
	Settings.reload_from_disk()
	_check("a wrong type is ignored", Settings.get_float("display.fov") == 70.0)
	_check("an out-of-range number is clamped", Settings.get_float("display.brightness") == 1.5)
	_check("a string where a bool belongs is ignored", Settings.get_bool("display.vsync"))
	_check("good values in a bad file still load",
		Settings.get_bool("display.show_fps") and is_equal_approx(Settings.get_float("audio.voice"), 0.4))
	_check("a negative volume clamps to silent", Settings.get_float("audio.music") == 0.0)
	_check("junk bindings are dropped", Settings.binding_text(&"jump") == "SPACE"
		and Settings.binding_text(&"reload") == "R", "%s / %s" % [Settings.binding_text(&"jump"), Settings.binding_text(&"reload")])

	# ── CORRUPT FILE ─────────────────────────────
	_write("{ this is not json")
	Settings.reload_from_disk()
	_check("a corrupt file boots on defaults", Settings.get_float("display.brightness") == 1.0)
	_check("...and is kept aside as .bad, not deleted", FileAccess.file_exists(TEST_PATH + ".bad")
		and not FileAccess.file_exists(TEST_PATH))

	# ── KEY BINDINGS ─────────────────────────────
	_check("defaults read as the keys on the board",
		Settings.binding_text(&"ui_up") == "W" and Settings.binding_text(&"fire") == "LEFT MOUSE"
		and Settings.binding_text(&"map") == "M",
		"%s / %s / %s" % [Settings.binding_text(&"ui_up"), Settings.binding_text(&"fire"), Settings.binding_text(&"map")])
	Settings.rebind(&"jump", _key(KEY_K))
	_check("jump rebinds to K", InputMap.event_is_action(_key(KEY_K), &"jump"))
	_check("...and SPACE no longer jumps", not InputMap.event_is_action(_key(KEY_SPACE), &"jump"))
	var swapped := Settings.rebind(&"jump", _key(KEY_R))
	_check("taking RELOAD's key swaps the two", swapped == &"reload"
		and InputMap.event_is_action(_key(KEY_R), &"jump") and InputMap.event_is_action(_key(KEY_K), &"reload"))
	Settings.rebind(&"ui_up", _key(KEY_I))
	var arrow := InputEventKey.new()
	arrow.keycode = KEY_UP
	arrow.pressed = true
	_check("rebinding forward leaves the arrow key working", InputMap.event_is_action(arrow, &"ui_up")
		and InputMap.event_is_action(_key(KEY_I), &"ui_up") and not InputMap.event_is_action(_key(KEY_W), &"ui_up"))
	Settings.rebind(&"lean_left", _key(KEY_Z, true))
	_check("a key captured with SHIFT held binds without needing SHIFT",
		InputMap.event_is_action(_key(KEY_Z), &"lean_left"))
	_check("ESC cannot be bound", not Settings.can_bind(_key(KEY_ESCAPE)))
	Settings.rebind(&"scan", _mouse(MOUSE_BUTTON_XBUTTON1))
	_check("mouse buttons bind", InputMap.event_is_action(_mouse(MOUSE_BUTTON_XBUTTON1), &"scan")
		and Settings.binding_text(&"scan") == "MOUSE 4")
	Settings.save()
	Settings.reload_from_disk()
	_check("bindings survive save and reload", InputMap.event_is_action(_key(KEY_R), &"jump")
		and InputMap.event_is_action(_key(KEY_I), &"ui_up") and Settings.binding_text(&"scan") == "MOUSE 4")
	var on_disk := FileAccess.get_file_as_string(TEST_PATH)
	_check("only CHANGED bindings are written", not on_disk.contains("\"fire\"") and on_disk.contains("\"jump\""))
	Settings.reset_bindings()
	_check("reset puts every key back", Settings.binding_text(&"jump") == "SPACE"
		and Settings.binding_text(&"reload") == "R" and Settings.binding_text(&"ui_up") == "W"
		and Settings.binding_text(&"scan") == "X")

	# ── THE PLAYER ───────────────────────────────
	Settings.reset_section("display")
	Settings.reset_section("controls")
	var player: Node3D = _find(root, "Player")
	if player == null:
		_check("found the player", false)
	else:
		Settings.set_value("display.fov", 85.0)
		for _i in 90:
			await physics_frame
		_check("FIELD OF VIEW reaches the camera", absf(player.cam.fov - 85.0) < 1.0, "fov=%.1f" % player.cam.fov)

		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(100, 0)
		var before: float = player.look_direction.y
		player._unhandled_input(motion)
		var base_turn: float = before - player.look_direction.y
		Settings.set_value("controls.mouse_sensitivity", 2.0)
		before = player.look_direction.y
		player._unhandled_input(motion)
		var fast_turn: float = before - player.look_direction.y
		_check("MOUSE SENSITIVITY scales the turn", absf(fast_turn - base_turn * 2.0) < 0.0001,
			"%.4f vs %.4f" % [fast_turn, base_turn])

		var nod := InputEventMouseMotion.new()
		nod.relative = Vector2(0, 20)
		player.look_direction.x = 0.0
		player._unhandled_input(nod)
		var normal_pitch: float = player.look_direction.x
		Settings.set_value("controls.invert_y", true)
		player.look_direction.x = 0.0
		player._unhandled_input(nod)
		_check("INVERT LOOK flips the pitch", signf(player.look_direction.x) == -signf(normal_pitch)
			and normal_pitch != 0.0, "%.3f vs %.3f" % [normal_pitch, player.look_direction.x])
		Settings.set_value("controls.invert_y", false)

		# Aim sensitivity only while aiming.
		Settings.set_value("controls.aim_sensitivity", 0.5)
		player.is_ads = true
		before = player.look_direction.y
		player._unhandled_input(motion)
		var aim_turn: float = before - player.look_direction.y
		player.is_ads = false
		_check("AIM SENSITIVITY applies while aiming", absf(aim_turn - fast_turn * 0.5) < 0.0001,
			"%.4f vs %.4f" % [aim_turn, fast_turn * 0.5])

		# Toggle aim: one press latches, a second releases.
		Settings.set_value("controls.toggle_aim", true)
		Input.action_press(&"aim")
		await physics_frame
		await physics_frame
		Input.action_release(&"aim")
		for _i in 3:
			await physics_frame
		var latched: bool = player.is_ads
		Input.action_press(&"aim")
		await physics_frame
		await physics_frame
		Input.action_release(&"aim")
		for _i in 3:
			await physics_frame
		_check("TOGGLE aim latches on a click and releases on the next", latched and not player.is_ads)
		Settings.set_value("controls.toggle_aim", false)
		Settings.reset_section("controls")
		Settings.reset_section("display")

	# ── THE HUD ──────────────────────────────────
	var hud := _find(root, "HUD")
	var filter_mat: ShaderMaterial = hud.get_node("SignalFilter").material if hud != null else null
	if filter_mat == null:
		_check("found the HUD filter", false)
	else:
		var grain_full: float = filter_mat.get_shader_parameter("grain")
		Settings.set_value("display.brightness", 1.3)
		_check("BRIGHTNESS reaches the filter", is_equal_approx(float(filter_mat.get_shader_parameter("gamma")), 1.3))
		Settings.set_value("display.screen_noise", 0.0)
		_check("SCREEN NOISE at 0 silences the grain and glitch",
			float(filter_mat.get_shader_parameter("grain")) == 0.0
			and float(filter_mat.get_shader_parameter("block_glitch")) == 0.0)
		Settings.set_value("display.screen_noise", 1.0)
		_check("...and at 100% puts back exactly what hud.tscn authored",
			is_equal_approx(float(filter_mat.get_shader_parameter("grain")), grain_full) and grain_full > 0.0)
		var fps: CanvasItem = hud.get_node("FPS")
		_check("the FPS counter is off by default", not fps.visible)
		Settings.set_value("display.show_fps", true)
		_check("SHOW FPS turns it on", fps.visible)
		Settings.reset_section("display")

	# ── SUBTITLES ────────────────────────────────
	var comms := _find(root, "CommsLog")
	if comms != null:
		var n0: int = comms._entries.size()
		comms._on_reported("RIVET", BarkSet.Line.HURT, "")
		var n1: int = comms._entries.size()
		Settings.set_value("audio.subtitles", false)
		_check("turning SUBTITLES off clears the log", comms._entries.is_empty())
		comms._on_reported("RIVET", BarkSet.Line.HURT, "")
		_check("...and keeps it clear", comms._entries.is_empty() and n1 == n0 + 1)
		Settings.set_value("audio.subtitles", true)

	# ── MENUS ────────────────────────────────────
	master._show_pause_menu()
	await process_frame
	_check("pause menu is up", master._menu == "pause")
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.keycode = KEY_TAB
	tab.pressed = true
	smui._input(tab)
	_check("TAB does not open the squad manager behind the pause menu", not smui.visible)

	master._open_options()
	await process_frame
	var menu: OptionsMenu = master._options
	_check("OPTIONS opens the options screen", master._menu == "options" and menu != null)
	if menu != null:
		var counts := []
		for i in OptionsMenu.TABS.size():
			menu.show_tab(i)
			await process_frame
			counts.append(menu._rows.size())
		_check("every tab builds its rows", counts[0] == 9 and counts[1] == 7 and counts[2] == 4
			and counts[3] == Settings.BINDINGS.size(), str(counts))

		# Click SHOW FPS's value.
		menu.show_tab(0)
		await process_frame
		var fps_row: Dictionary = _row(menu, "SHOW FPS")
		(fps_row["controls"][1] as Button).pressed.emit()
		_check("clicking a toggle changes the setting", Settings.get_bool("display.show_fps"))
		_check("...and the row shows it", (fps_row["controls"][1] as Button).text == "ON")
		(fps_row["controls"][0] as Button).pressed.emit()

		# WINDOW SIZE only while windowed.
		var size_row: Dictionary = _row(menu, "WINDOW SIZE")
		Settings.set_value("display.window_mode", "borderless")
		_check("WINDOW SIZE is disabled outside windowed mode", (size_row["controls"][1] as Button).disabled)
		Settings.set_value("display.window_mode", "windowed")
		_check("...and enabled in it", not (size_row["controls"][1] as Button).disabled)

		# Drag a bar.
		menu.show_tab(1)
		await process_frame
		var bar = _row(menu, "EFFECTS")["controls"][1]
		bar.picked.emit(0.25)
		_check("a level bar sets the volume", is_equal_approx(Settings.get_float("audio.effects"), 0.25))
		Settings.reset_section("audio")

		# Rebind through the screen.
		menu.show_tab(3)
		await process_frame
		var reload_row: Dictionary = {}
		for r in menu._rows:
			if (r["name"] as Label).text == "RELOAD":
				reload_row = r
		(reload_row["controls"][0] as Button).pressed.emit()
		_check("clicking a binding starts listening", menu.is_capturing())
		menu._input(_key(KEY_T))
		_check("the next key press is bound", not menu.is_capturing()
			and Settings.binding_text(&"reload") == "T" and Settings.binding_text(&"command") == "R",
			"%s / %s" % [Settings.binding_text(&"reload"), Settings.binding_text(&"command")])
		(reload_row["controls"][0] as Button).pressed.emit()
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = true
		menu._input(esc)
		_check("ESC cancels listening without binding anything", not menu.is_capturing()
			and Settings.binding_text(&"reload") == "T")
		_check("...and does not close the screen", master._menu == "options")

		# DEFAULTS asks once first.
		menu._on_defaults_pressed()
		_check("DEFAULTS asks before it resets", Settings.binding_text(&"reload") == "T")
		menu._on_defaults_pressed()
		_check("...and resets on the second press", Settings.binding_text(&"reload") == "R")

		# ESC backs out to the menu that opened it.
		master._input(esc)
		for _i in 3:
			await process_frame
		_check("ESC returns to the pause menu", master._menu == "pause" and master._options == null)

	master._resume_from_pause()
	await process_frame

	# ── TIDY ─────────────────────────────────────
	Settings.reset_bindings()
	_wipe()
	print("")
	print("ALL SETTINGS CHECKS PASS" if _fails == 0 else "%d SETTINGS CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


# A row by its label, not its position: inserting a setting (MONITOR did)
# shifted every index after it, and a bar cast to a Button is null — the
# script error stopped this coroutine and the test hung instead of failing.
func _row(menu: OptionsMenu, label: String) -> Dictionary:
	for r in menu._rows:
		if (r["name"] as Label).text == label:
			return r
	push_error("no row labelled %s" % label)
	return {}
