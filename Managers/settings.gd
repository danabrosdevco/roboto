class_name Settings

# ─────────────────────────────────────────────
# SETTINGS — every player-facing option, and the one file they live in.
#
# Saved to user://settings.json. On Windows that is
#   %APPDATA%\Godot\app_userdata\Roboto\settings.json
# JSON rather than a ConfigFile so anyone with a broken setting can fix it in
# Notepad.
#
# Static, like PauseHold and BarkDirector: no autoload, no ready order. It loads
# itself the first time anything asks, which matters here — World is a CHILD of
# Master, so the player readies (and wants its field of view) before
# Master._ready has run. Master still calls apply_display() from _enter_tree,
# the earliest point in the boot, so the window is right before World loads.
#
# WHO DOES WHAT
#   Settings     the values, the file, and anything the ENGINE owns: the
#                window, vsync, frame cap, bus volumes and key bindings.
#   OptionsMenu  the screen. Holds no state of its own.
#   Everyone else reads what they need when they need it (the player's FOV and
#   sensitivity) or listens for changes (the HUD's filter and FPS counter, the
#   comms log).
#
# THE FILE CAN NEVER BREAK THE GAME. Nothing is read that SPEC does not list,
# nothing listed comes back out of range, and a file that will not parse is
# moved aside to settings.json.bad and replaced with defaults. A hand-edited
# file, an old one or a half-written one all still boot.
# ─────────────────────────────────────────────

const VERSION := 1

## Every setting, its default, and what counts as valid. A key's section is the
## part before the dot, and is also its section in the file.
##   choices   — the value must be one of these
##   min / max — clamped into range
const SPEC := {
	# ── DISPLAY ──────────────────────────────────
	# "windowed" keeps the project's own launch behaviour (a maximised window);
	# "borderless" is Godot's FULLSCREEN, "exclusive" its EXCLUSIVE_FULLSCREEN.
	"display.window_mode":  {"default": "windowed", "choices": ["windowed", "borderless", "exclusive"]},
	# "maximised" or "WIDTHxHEIGHT". Only used while windowed. The game always
	# RENDERS at 1152x648 and scales up (stretch mode "viewport"), so this is the
	# size of the window, not a render resolution.
	"display.window_size":  {"default": "maximised"},
	# Which monitor the window goes on, 0-based. -1 leaves it wherever the OS
	# opened it, which is what the game did before this existed. A monitor that
	# has since been unplugged is ignored rather than trusted.
	"display.monitor":      {"default": -1, "min": -1, "max": 15},
	"display.vsync":        {"default": true},
	"display.max_fps":      {"default": 0, "choices": [0, 30, 60, 120, 144, 165, 240]},
	# Vertical degrees, as Camera3D takes it. 70 was the player's HIP_FOV.
	"display.fov":          {"default": 70.0, "min": 60.0, "max": 90.0},
	# Gamma on the signal filter. 1.0 is the game as authored.
	"display.brightness":   {"default": 1.0, "min": 0.5, "max": 1.5},
	# Scales the filter's grain, dropout and block glitch. 0 is a clean signal.
	"display.screen_noise": {"default": 1.0, "min": 0.0, "max": 1.0},
	"display.show_fps":     {"default": false},

	# ── AUDIO ────────────────────────────────────
	# Slider positions, 0..1. AudioBuses shapes them into dB.
	"audio.master":         {"default": 1.0, "min": 0.0, "max": 1.0},
	"audio.music":          {"default": 1.0, "min": 0.0, "max": 1.0},
	"audio.effects":        {"default": 1.0, "min": 0.0, "max": 1.0},
	"audio.voice":          {"default": 1.0, "min": 0.0, "max": 1.0},
	"audio.interface":      {"default": 1.0, "min": 0.0, "max": 1.0},
	"audio.mute_unfocused": {"default": false},
	# The comms log is the game's subtitles: squad chatter as text.
	"audio.subtitles":      {"default": true},

	# ── CONTROLS ─────────────────────────────────
	# Multiplies the player's MOUSE_SENS.
	"controls.mouse_sensitivity": {"default": 1.0, "min": 0.1, "max": 3.0},
	# Multiplies mouse_sensitivity while aiming down sights.
	"controls.aim_sensitivity":   {"default": 1.0, "min": 0.2, "max": 1.5},
	"controls.invert_y":          {"default": false},
	"controls.toggle_aim":        {"default": false},
}

## Windowed sizes offered, smallest first. Only the ones that fit the screen are
## shown — see window_size_choices().
const WINDOW_SIZES := ["1152x648", "1280x720", "1600x900", "1920x1080", "2560x1440", "3200x1800", "3840x2160"]

## The rebindable actions, in the order the menu shows them: [action, label,
## group]. Anything not listed keeps its project.godot binding and cannot be
## changed. Each action has ONE rebindable input — its first key or mouse
## button. Everything else on it (the arrow keys on the ui_ actions, joypad
## input, fire's second key) is left exactly as authored.
const BINDINGS := [
	[&"ui_up",         "MOVE FORWARD",  "MOVEMENT"],
	[&"ui_down",       "MOVE BACK",     "MOVEMENT"],
	[&"ui_left",       "STRAFE LEFT",   "MOVEMENT"],
	[&"ui_right",      "STRAFE RIGHT",  "MOVEMENT"],
	[&"jump",          "JUMP",          "MOVEMENT"],
	[&"lean_left",     "LEAN LEFT",     "MOVEMENT"],
	[&"lean_right",    "LEAN RIGHT",    "MOVEMENT"],
	[&"fire",          "FIRE",          "COMBAT"],
	[&"aim",           "AIM",           "COMBAT"],
	[&"zoom",          "ZOOM",          "COMBAT"],
	[&"reload",        "RELOAD",        "COMBAT"],
	[&"interact",      "INTERACT",      "COMBAT"],
	[&"scan",          "SCAN",          "COMBAT"],
	[&"1",             "SLOT 1",        "EQUIPMENT"],
	[&"2",             "SLOT 2",        "EQUIPMENT"],
	[&"3",             "SLOT 3",        "EQUIPMENT"],
	[&"4",             "SLOT 4",        "EQUIPMENT"],
	[&"5",             "SLOT 5",        "EQUIPMENT"],
	[&"6",             "SLOT 6",        "EQUIPMENT"],
	[&"command",       "SQUAD ORDER",   "SQUAD"],
	[&"squad_manager", "SQUAD MANAGER", "SQUAD"],
	[&"map",           "MAP",           "SQUAD"],
	[&"fullscreen",    "FULLSCREEN",    "SYSTEM"],
]

# Key names that OS.get_keycode_string spells out in a way that reads badly on
# the HUD ("QuoteLeft", "Windows", "Kp 1" are handled below).
const KEY_NAMES := {
	KEY_QUOTELEFT: "`", KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]",
	KEY_SEMICOLON: ";", KEY_APOSTROPHE: "'", KEY_COMMA: ",", KEY_PERIOD: ".",
	KEY_SLASH: "/", KEY_MINUS: "-", KEY_EQUAL: "=", KEY_META: "WIN",
	KEY_CAPSLOCK: "CAPS LOCK", KEY_PAGEUP: "PAGE UP", KEY_PAGEDOWN: "PAGE DOWN",
}

const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "LEFT MOUSE", MOUSE_BUTTON_RIGHT: "RIGHT MOUSE",
	MOUSE_BUTTON_MIDDLE: "MIDDLE MOUSE", MOUSE_BUTTON_WHEEL_UP: "WHEEL UP",
	MOUSE_BUTTON_WHEEL_DOWN: "WHEEL DOWN", MOUSE_BUTTON_WHEEL_LEFT: "WHEEL LEFT",
	MOUSE_BUTTON_WHEEL_RIGHT: "WHEEL RIGHT", MOUSE_BUTTON_XBUTTON1: "MOUSE 4",
	MOUSE_BUTTON_XBUTTON2: "MOUSE 5",
}

## Where the file lives. A var, not a const, so the tests can point it at a
## scratch file rather than trample the real one.
static var path: String = "user://settings.json"

static var _values: Dictionary = {}
static var _loaded: bool = false
static var _dirty: bool = false
static var _focused: bool = true
static var _listeners: Array[Callable] = []

# BINDINGS. Only differences from project.godot are stored, so changing a
# default in the Input Map later still reaches everyone who never rebound it.
static var _bind_overrides: Dictionary = {}   # String(action) -> {"key": int} | {"mouse": int}
static var _default_binds: Dictionary = {}    # action -> InputEvent, as authored
static var _extra_events: Dictionary = {}     # action -> Array of the events left alone


# ─────────────────────────────────────────────
# READING
# ─────────────────────────────────────────────
static func get_value(key: String) -> Variant:
	_ensure()
	if _values.has(key):
		return _values[key]
	if SPEC.has(key):
		return SPEC[key]["default"]
	push_warning("Settings: no setting called '%s'" % key)
	return null


static func get_float(key: String) -> float:
	return float(get_value(key))


static func get_int(key: String) -> int:
	return int(get_value(key))


static func get_bool(key: String) -> bool:
	return bool(get_value(key))


static func get_string(key: String) -> String:
	return str(get_value(key))


static func default_of(key: String) -> Variant:
	return SPEC[key]["default"] if SPEC.has(key) else null


## Look speed as a multiplier on the player's base sensitivity. Aim
## sensitivity only applies while aiming down sights.
static func look_scale(aiming: bool) -> float:
	var s := get_float("controls.mouse_sensitivity")
	if aiming:
		s *= get_float("controls.aim_sensitivity")
	return s


# ─────────────────────────────────────────────
# WRITING
# Applies at once and tells the listeners. Does NOT write the file — call
# save() when the player is done (the options screen closing), so dragging a
# slider is not a disk write per frame.
# ─────────────────────────────────────────────
static func set_value(key: String, value: Variant) -> void:
	_ensure()
	if not SPEC.has(key):
		push_warning("Settings: no setting called '%s'" % key)
		return
	var v: Variant = _sanitize(key, value)
	if typeof(_values.get(key)) == typeof(v) and _values.get(key) == v:
		return
	_values[key] = v
	_dirty = true
	_apply(key)
	_changed(key)


## Everything in one section back to its default: "display", "audio" or
## "controls". Key bindings are reset_bindings().
static func reset_section(section: String) -> void:
	_ensure()
	for key in SPEC:
		if key.begins_with(section + "."):
			set_value(key, SPEC[key]["default"])


static func add_listener(cb: Callable) -> void:
	if not _listeners.has(cb):
		_listeners.append(cb)


static func remove_listener(cb: Callable) -> void:
	_listeners.erase(cb)


# ─────────────────────────────────────────────
# FILE
# ─────────────────────────────────────────────
static func save() -> bool:
	_ensure()
	var data := {"version": VERSION}
	for key in SPEC:
		var dot: int = key.find(".")
		var section: String = key.substr(0, dot)
		if not data.has(section):
			data[section] = {}
		data[section][key.substr(dot + 1)] = _values[key]
	data["bindings"] = _bind_overrides.duplicate(true)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Settings: could not write %s (%s)"
			% [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_dirty = false
	return true


static func save_if_dirty() -> void:
	if _loaded and _dirty:
		save()


## Throws away what is in memory and reads the file again. The tests use it;
## nothing in the game needs to.
static func reload_from_disk() -> void:
	_loaded = false
	_ensure()
	apply_display()
	_changed("*")


static func _ensure() -> void:
	if _loaded:
		return
	# Set FIRST. Everything below can end up calling a getter, and a getter
	# calls this.
	_loaded = true
	_dirty = false
	_values.clear()
	for key in SPEC:
		_values[key] = SPEC[key]["default"]
	_bind_overrides.clear()
	_read_file()
	AudioBuses.ensure()
	_apply_audio()
	_capture_default_bindings()
	_apply_bindings()


static func _read_file() -> void:
	if not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		# Kept rather than deleted, so a file someone hand-edited into a typo is
		# still there to be fixed.
		push_warning("Settings: %s would not parse. Moved to %s.bad; using defaults." % [path, path])
		if FileAccess.file_exists(path + ".bad"):
			DirAccess.remove_absolute(path + ".bad")
		DirAccess.rename_absolute(path, path + ".bad")
		return
	for key in SPEC:
		var dot: int = key.find(".")
		var section: Variant = data.get(key.substr(0, dot))
		var name: String = key.substr(dot + 1)
		if typeof(section) == TYPE_DICTIONARY and section.has(name):
			_values[key] = _sanitize(key, section[name])
	var binds: Variant = data.get("bindings")
	if typeof(binds) == TYPE_DICTIONARY:
		for action in binds:
			if _is_listed(StringName(str(action))) and _event_from(binds[action]) != null:
				_bind_overrides[str(action)] = binds[action]


# Brings any value back to something the menu could have produced.
static func _sanitize(key: String, value: Variant) -> Variant:
	var spec: Dictionary = SPEC[key]
	var def: Variant = spec["default"]
	match typeof(def):
		TYPE_BOOL:
			return value if typeof(value) == TYPE_BOOL else def
		TYPE_INT, TYPE_FLOAT:
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return def
			if spec.has("choices"):
				# JSON has no ints; 60 comes back as 60.0.
				var n := int(value)
				return n if spec["choices"].has(n) else def
			var f := clampf(float(value), float(spec["min"]), float(spec["max"]))
			f = snappedf(f, 0.001)
			return int(f) if typeof(def) == TYPE_INT else f
		TYPE_STRING:
			if typeof(value) != TYPE_STRING:
				return def
			if spec.has("choices"):
				return value if spec["choices"].has(value) else def
			if key == "display.window_size":
				return value if (value == "maximised" or parse_size(value) != Vector2i.ZERO) else def
			return value
	return def


# ─────────────────────────────────────────────
# APPLYING
# ─────────────────────────────────────────────
## The window, vsync and frame cap. Master calls this once at boot.
static func apply_display() -> void:
	_ensure()
	_apply_window()
	_apply_vsync()
	Engine.max_fps = get_int("display.max_fps")


## Master forwards focus changes, for "mute in background".
static func set_window_focused(focused: bool) -> void:
	_focused = focused
	_apply_audio()


static func _apply(key: String) -> void:
	if key.begins_with("audio."):
		_apply_audio()
	elif key == "display.window_mode" or key == "display.window_size" or key == "display.monitor":
		_apply_window()
	elif key == "display.vsync":
		_apply_vsync()
	elif key == "display.max_fps":
		Engine.max_fps = get_int(key)


static func _apply_audio() -> void:
	var master := get_float("audio.master")
	if not _focused and get_bool("audio.mute_unfocused"):
		master = 0.0
	AudioBuses.set_volume(AudioBuses.MASTER, master)
	AudioBuses.set_volume(AudioBuses.MUSIC, get_float("audio.music"))
	AudioBuses.set_volume(AudioBuses.EFFECTS, get_float("audio.effects"))
	AudioBuses.set_volume(AudioBuses.VOICE, get_float("audio.voice"))
	AudioBuses.set_volume(AudioBuses.INTERFACE, get_float("audio.interface"))


static func _has_window() -> bool:
	return DisplayServer.get_name() != "headless"


static func _apply_window() -> void:
	if not _has_window():
		return
	# Monitor first, so every mode below — the windowed size and centring
	# especially — is worked out on the screen the window ends up on.
	_move_to_monitor()
	match get_string("display.window_mode"):
		"exclusive":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			# The borderless flag as well as the mode, same as Master's old
			# toggle, so dropping back to windowed can never leave a window
			# with no frame.
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			var size := parse_size(get_string("display.window_size"))
			var current := DisplayServer.window_get_mode()
			# Already maximised and asked to be: touch nothing. project.godot
			# launches maximised, and bouncing it through WINDOWED to get back
			# to MAXIMIZED is a visible flicker on every boot.
			if size == Vector2i.ZERO and current == DisplayServer.WINDOW_MODE_MAXIMIZED:
				return
			if current == DisplayServer.WINDOW_MODE_FULLSCREEN \
					or current == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			if size == Vector2i.ZERO:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
			else:
				if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				_place_window(size)


# Moves the window to the chosen monitor, keeping its mode. A maximised window
# is dropped to windowed for the move and maximised again on arrival: Windows
# otherwise carries the old monitor's maximised size across.
static func _move_to_monitor() -> void:
	var target := get_int("display.monitor")
	if target < 0 or target >= DisplayServer.get_screen_count():
		return
	if DisplayServer.window_get_current_screen() == target:
		return
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_current_screen(target)
	if mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


## AUTO (-1), then every monitor attached right now. The saved one stays in the
## list even if it is unplugged, so cycling starts from where the setting is.
static func monitor_choices() -> Array:
	var out: Array = [-1]
	var count := DisplayServer.get_screen_count() if _has_window() else 1
	for i in count:
		out.append(i)
	var current := get_int("display.monitor")
	if not out.has(current):
		out.append(current)
	return out


## "1 - 2560 X 1440" for the options screen. Numbered from 1, as Windows does.
static func monitor_label(index: int) -> String:
	if index < 0:
		return "AUTO"
	if not _has_window() or index >= DisplayServer.get_screen_count():
		return "%d - NOT FOUND" % (index + 1)
	var size := DisplayServer.screen_get_size(index)
	return "%d - %d X %d" % [index + 1, size.x, size.y]


# Sized and centred on whichever screen the window is on. A saved size bigger
# than this screen (a file carried over from a bigger monitor) is clamped
# rather than trusted.
static func _place_window(size: Vector2i) -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x > 0 and usable.size.y > 0:
		size = size.clamp(Vector2i(640, 360), usable.size)
	DisplayServer.window_set_size(size)
	if usable.size.x > 0:
		DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


static func _apply_vsync() -> void:
	if not _has_window():
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED
		if get_bool("display.vsync") else DisplayServer.VSYNC_DISABLED)


static func _changed(key: String) -> void:
	for cb in _listeners.duplicate():
		if cb.is_valid():
			cb.call(key)
		else:
			_listeners.erase(cb)


# ─────────────────────────────────────────────
# WINDOW SIZES
# ─────────────────────────────────────────────
## "1600x900" -> Vector2i(1600, 900). Anything else, or anything silly, is ZERO.
static func parse_size(s: String) -> Vector2i:
	var parts := s.split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var v := Vector2i(parts[0].to_int(), parts[1].to_int())
	if v.x < 640 or v.y < 360 or v.x > 7680 or v.y > 4320:
		return Vector2i.ZERO
	return v


## What the WINDOW SIZE row offers: maximised, then every listed size that fits
## this screen with room for a title bar. The current value always stays in the
## list, so the row can never show something it cannot cycle back to.
static func window_size_choices() -> Array:
	var out: Array = ["maximised"]
	var usable := Vector2i.ZERO
	if _has_window():
		usable = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	for s in WINDOW_SIZES:
		var v := parse_size(s)
		if usable == Vector2i.ZERO or (v.x <= usable.x and v.y <= usable.y - 40):
			out.append(s)
	var current := get_string("display.window_size")
	if not out.has(current):
		out.append(current)
	return out


# ─────────────────────────────────────────────
# KEY BINDINGS
# ─────────────────────────────────────────────
## The one rebindable input on an action — always its FIRST event, because
## _set_primary rebuilds every listed action with the primary at the front.
static func binding_event(action: StringName) -> InputEvent:
	_ensure()
	if not InputMap.has_action(action):
		return null
	var events := InputMap.action_get_events(action)
	return events[0] if not events.is_empty() else null


static func binding_text(action: StringName) -> String:
	return event_text(binding_event(action))


static func binding_label(action: StringName) -> String:
	for row in BINDINGS:
		if row[0] == action:
			return row[1]
	return String(action).to_upper()


## Whether this event can be bound at all. ESC is the menu key and is kept.
static func can_bind(ev: InputEvent) -> bool:
	return _normalise(ev) != null


## Binds `action` to `ev`. If another listed action already had that input,
## the two SWAP — nothing is ever left unbound, which matters most for FIRE.
## Returns the action it swapped with, or &"" if it took a free key.
static func rebind(action: StringName, ev: InputEvent) -> StringName:
	_ensure()
	if not _default_binds.has(action):
		return &""
	var incoming := _normalise(ev)
	if incoming == null:
		return &""
	var old := binding_event(action)
	if _same_input(old, incoming):
		return &""
	var swapped: StringName = &""
	for other in _default_binds:
		if other != action and _same_input(binding_event(other), incoming):
			_store(other, old)
			swapped = other
			break
	_store(action, incoming)
	_dirty = true
	_changed("bindings")
	return swapped


static func reset_bindings() -> void:
	_ensure()
	if _bind_overrides.is_empty():
		return
	_bind_overrides.clear()
	_apply_bindings()
	_dirty = true
	_changed("bindings")


static func is_default_binding(action: StringName) -> bool:
	return not _bind_overrides.has(String(action))


static func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var code: Key = (ev as InputEventKey).physical_keycode
		if code == KEY_NONE:
			code = (ev as InputEventKey).keycode
		if KEY_NAMES.has(code):
			return KEY_NAMES[code]
		# What is PRINTED on this player's key, not the US-layout name — the
		# physical W on an AZERTY board is labelled Z.
		var shown: Key = code
		if _has_window():
			shown = DisplayServer.keyboard_get_keycode_from_physical(code)
		if KEY_NAMES.has(shown):
			return KEY_NAMES[shown]
		var s := OS.get_keycode_string(shown).to_upper()
		if s.begins_with("KP "):
			s = "NUM " + s.substr(3)
		return s if s != "" else "KEY %d" % code
	if ev is InputEventMouseButton:
		var b: int = (ev as InputEventMouseButton).button_index
		return MOUSE_NAMES.get(b, "MOUSE %d" % b)
	return "---"


static func _is_listed(action: StringName) -> bool:
	for row in BINDINGS:
		if row[0] == action:
			return true
	return false


# The map key is registered in code by Master rather than authored in
# project.godot. It has to exist before the defaults are captured, and Settings
# can be first touched before Master._ready, so it is made here too. Whoever is
# first wins; the other finds it already there.
static func _ensure_runtime_actions() -> void:
	if not InputMap.has_action(&"map"):
		InputMap.add_action(&"map")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_M
		InputMap.action_add_event(&"map", ev)


# Once per run. The InputMap as project.godot authored it IS the defaults, so
# this must see it before any override has been applied — and never again after.
static func _capture_default_bindings() -> void:
	if not _default_binds.is_empty():
		return
	_ensure_runtime_actions()
	for row in BINDINGS:
		var action: StringName = row[0]
		if not InputMap.has_action(action):
			continue
		var primary: InputEvent = null
		var extras: Array = []
		for ev in InputMap.action_get_events(action):
			# PHYSICAL keys and mouse buttons only. The ui_ actions list their
			# arrow key first, as a plain keycode — that stays an extra, and the
			# WASD key after it is the one you rebind.
			var candidate: bool = ev is InputEventMouseButton \
				or (ev is InputEventKey and (ev as InputEventKey).physical_keycode != KEY_NONE)
			if primary == null and candidate:
				primary = _normalise(ev)
			else:
				extras.append(ev)
		if primary == null:
			continue
		_default_binds[action] = primary
		_extra_events[action] = extras


static func _apply_bindings() -> void:
	for action in _default_binds:
		var ev: InputEvent = null
		if _bind_overrides.has(String(action)):
			ev = _event_from(_bind_overrides[String(action)])
		if ev == null:
			ev = _default_binds[action]
		_set_primary(action, ev)


static func _store(action: StringName, ev: InputEvent) -> void:
	if _same_input(ev, _default_binds[action]):
		_bind_overrides.erase(String(action))
	else:
		_bind_overrides[String(action)] = _serialise(ev)
	_set_primary(action, ev)


# Rebuilt in a fixed order — primary first, then everything left alone — so
# the primary is always findable as events[0].
static func _set_primary(action: StringName, ev: InputEvent) -> void:
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, ev.duplicate())
	for extra in _extra_events.get(action, []):
		InputMap.action_add_event(action, extra)


# A clean event carrying only the key or button. The captured press can carry
# modifier flags (Shift held while pressing it), and an action event WITH a
# modifier only fires while that modifier is also held.
static func _normalise(ev: InputEvent) -> InputEvent:
	if ev is InputEventKey:
		var code: Key = (ev as InputEventKey).physical_keycode
		if code == KEY_NONE:
			code = (ev as InputEventKey).keycode
		if code == KEY_NONE or code == KEY_ESCAPE:
			return null
		var k := InputEventKey.new()
		k.physical_keycode = code
		return k
	if ev is InputEventMouseButton:
		var m := InputEventMouseButton.new()
		m.button_index = (ev as InputEventMouseButton).button_index
		return m
	return null


static func _same_input(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return (a as InputEventKey).physical_keycode == (b as InputEventKey).physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false


static func _serialise(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"key": int((ev as InputEventKey).physical_keycode)}
	if ev is InputEventMouseButton:
		return {"mouse": int((ev as InputEventMouseButton).button_index)}
	return {}


static func _event_from(d: Variant) -> InputEvent:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	if d.has("key") and (typeof(d["key"]) == TYPE_FLOAT or typeof(d["key"]) == TYPE_INT):
		var code := int(d["key"])
		if code <= 0 or code == KEY_ESCAPE or code > 0x7FFFFF:
			return null
		var k := InputEventKey.new()
		k.physical_keycode = code as Key
		return k
	if d.has("mouse") and (typeof(d["mouse"]) == TYPE_FLOAT or typeof(d["mouse"]) == TYPE_INT):
		var b := int(d["mouse"])
		if b < 1 or b > 9:
			return null
		var m := InputEventMouseButton.new()
		m.button_index = b as MouseButton
		return m
	return null
