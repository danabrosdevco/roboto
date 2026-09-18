extends Control
class_name CommsLog

# ─────────────────────────────────────────────
# COMMS LOG — what the squad is saying, in text.
#
# Distinct from SquadHUD's toast, which confirms things the PLAYER did (order
# issued, contact called, squad selected). This is the other direction: what
# your robots are reporting back, so a bark is something you can read as well
# as hear.
#
# Only friendly traffic appears. BarkDirector reports FRIENDLY and ORDERS and
# nothing else — subtitling hostiles would hand the player positions they have
# not earned, and this panel would become a wallhack.
#
# Built in code and self-wiring, same as the other HUDs: add it as a child of
# the HUD Control and it finds the director itself. There is no export to leave
# blank.
# ─────────────────────────────────────────────

@export var font_size_body: int = 15
@export var panel_margin: Vector2 = Vector2(28, 26)
@export var panel_width: float = 460.0
# BOTTOM RIGHT, not bottom left. The left column is already the squad roster and
# the scan readout, and the health/ammo bar runs across the bottom centre — the
# first placement put comms text straight through both. The four corners now
# divide cleanly: squad top-left, objectives top-right, comms bottom-right,
# health bottom-centre.
@export var bottom_offset: float = 150.0
@export var panel_height: float = 150.0
@export var max_lines: int = 5
@export var line_seconds: float = 7.0
@export var fade_seconds: float = 1.2

const COL_DIM    := HUDPalette.DIM
const COL_BRIGHT := HUDPalette.BRIGHT
const COL_WARN   := HUDPalette.WARN
const COL_CRIT   := HUDPalette.CRIT
const COL_SIGNAL := HUDPalette.SIGNAL

var _list: VBoxContainer
# Each entry: {"label": Label, "age": float}
var _entries: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 45
	_build_ui()
	BarkDirector.add_listener(_on_reported)
	Settings.add_listener(_on_setting_changed)


func _exit_tree() -> void:
	# The director holds callables across level loads; a freed log left
	# registered would be called on a dead object every time the squad spoke.
	BarkDirector.remove_listener(_on_reported)
	Settings.remove_listener(_on_setting_changed)


# Switching subtitles off mid-mission clears what is already up, rather than
# leaving five lines to fade out on their own.
func _on_setting_changed(key: String) -> void:
	if key != "audio.subtitles" or Settings.get_bool("audio.subtitles"):
		return
	for entry in _entries:
		var label: Label = entry["label"]
		if is_instance_valid(label):
			_list.remove_child(label)
			label.queue_free()
	_entries.clear()


func _build_ui() -> void:
	_list = VBoxContainer.new()
	_list.anchor_left = 1.0
	_list.anchor_right = 1.0
	_list.anchor_top = 1.0
	_list.anchor_bottom = 1.0
	_list.offset_left = -(panel_margin.x + panel_width)
	_list.offset_right = -panel_margin.x
	_list.offset_bottom = -bottom_offset
	_list.offset_top = -(bottom_offset + panel_height)
	# Anchored to the bottom-right corner, so the box grows leftward and upward
	# with the screen rather than drifting across the middle on an ultrawide.
	_list.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_list.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_list.alignment = BoxContainer.ALIGNMENT_END
	_list.add_theme_constant_override("separation", 2)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)


func _process(delta: float) -> void:
	if _entries.is_empty():
		return
	var i := _entries.size() - 1
	while i >= 0:
		var entry: Dictionary = _entries[i]
		var label: Label = entry["label"]
		if not is_instance_valid(label):
			_entries.remove_at(i)
			i -= 1
			continue
		entry["age"] = float(entry["age"]) + delta
		var age: float = entry["age"]
		if age >= line_seconds:
			_list.remove_child(label)
			label.queue_free()
			_entries.remove_at(i)
		elif age > line_seconds - fade_seconds:
			label.modulate.a = clampf((line_seconds - age) / fade_seconds, 0.0, 1.0)
		i -= 1


# BarkDirector calls this for every friendly line that actually won the channel
# — so the log shows exactly what was heard, never more. If a bark loses the
# election, it is not in the log either, which is what keeps text and audio
# telling the same story.
func _on_reported(who: String, line: int, context: String) -> void:
	# SUBTITLES in the options. This panel is the game's subtitles.
	if not Settings.get_bool("audio.subtitles"):
		return
	var text := _compose(who, line, context)
	if text == "":
		return
	_push(text, _colour_for(line))


func _compose(who: String, line: int, context: String) -> String:
	var speaker := who.to_upper() if who != "" else "SQUAD"
	var subject := context.to_upper() if context != "" else ""
	match line:
		BarkSet.Line.CONTACT:
			if subject != "":
				return "%s  ›  HOSTILE SPOTTED: %s" % [speaker, subject]
			return "%s  ›  HOSTILE CONTACT" % speaker
		BarkSet.Line.KILL:
			if subject != "":
				return "%s  ›  KILL CONFIRMED: %s" % [speaker, subject]
			return "%s  ›  KILL CONFIRMED" % speaker
		BarkSet.Line.ORDER_ACK:
			return "%s  ›  ACKNOWLEDGED, MOVING" % speaker
		BarkSet.Line.DOWNED:
			# Reads as the squad reporting a loss rather than the casualty
			# narrating their own collapse.
			return "%s IS DOWN" % speaker
		BarkSet.Line.HURT:
			return "%s  ›  TAKING FIRE" % speaker
		BarkSet.Line.SEARCH:
			return "%s  ›  LOST CONTACT, SEARCHING" % speaker
		BarkSet.Line.RELOAD:
			return "%s  ›  RELOADING" % speaker
	return ""


func _colour_for(line: int) -> Color:
	match line:
		BarkSet.Line.DOWNED: return COL_CRIT
		BarkSet.Line.HURT:   return COL_WARN
		BarkSet.Line.CONTACT: return COL_WARN
		BarkSet.Line.KILL:   return COL_SIGNAL
	return COL_BRIGHT


func _push(text: String, col: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", col)
	label.add_theme_font_size_override("font_size", font_size_body)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Right-aligned so the lines sit against the screen edge and read as a
	# column rather than a ragged block floating over the weapon.
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_list.add_child(label)
	_entries.append({"label": label, "age": 0.0})

	# Oldest first, so trimming from the front drops the stalest line. The
	# container is ALIGNMENT_END, so new lines push up from the bottom.
	while _entries.size() > max_lines:
		var oldest: Dictionary = _entries.pop_front()
		var old_label: Label = oldest["label"]
		if is_instance_valid(old_label):
			# remove_child before queue_free — queue_free is deferred and the
			# node would still be counted as a child this frame.
			_list.remove_child(old_label)
			old_label.queue_free()
