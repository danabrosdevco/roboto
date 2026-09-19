extends Control
class_name ObjectiveHUD

# ─────────────────────────────────────────────
# OBJECTIVE HUD — what am I supposed to be doing.
#
# Built in code and self-wiring, same as SquadHUD, for the same reason: an
# unassigned export fails silently and costs an afternoon. Add it as a child of
# the HUD Control and it finds the tracker itself.
#
# Top right, deliberately opposite the squad roster. Quiet by default: a
# completed objective dims and strikes through rather than disappearing, so the
# player can see progress rather than watching the list shrink for no visible
# reason.
#
# Hidden entirely at base. There are no objectives there and an empty panel
# reads as broken.
# ─────────────────────────────────────────────

@export var font_size_header: int = 20
@export var font_size_body: int = 18
@export var panel_margin: Vector2 = Vector2(28, 26)
@export var panel_width: float = 380.0
@export var refresh_interval: float = 0.2
# The payout card stays up longer than an objective ping — it is the last thing
# you see before the level unloads, and it is the only place the mission's
# reward is ever shown.
@export var reward_toast_seconds: float = 6.0

const COL_DIM    := HUDPalette.DIM
const COL_BRIGHT := HUDPalette.BRIGHT
const COL_WARN   := HUDPalette.WARN
const COL_DONE   := HUDPalette.SIGNAL
const _Debrief := preload("res://Character/hud/debrief_screen.gd")
const _Wallet := preload("res://Character/hud/wallet_hud.gd")

var tracker: ObjectiveTracker
# Same reasoning as LevelExit: resolved by path so hud.tscn stays loadable
# without the campaign autoload present.
var _campaign: Node

var _panel: VBoxContainer
var _header: Label
var _list: VBoxContainer
var _toast: Label
var _timer: float = 0.0
var _toast_time: float = 0.0
# Toasts waiting for the one on screen to finish: YOU WON follows MISSION
# COMPLETE rather than replacing it before it can be read.
var _toast_queue: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_full_rect()
	z_index = 50
	_build_ui()
	_campaign = get_tree().get_first_node_in_group("campaign")
	_bind_tracker()
	# Re-bind on every level load; the tracker persists but its contents don't.
	if _campaign != null:
		_campaign.deployed.connect(func(_m): _bind_tracker())
		_campaign.returned_to_base.connect(func(): _bind_tracker())
	# The debrief (mission complete / failed) and, at base, the resources and
	# compute in this corner: both built here rather than placed in hud.tscn.
	# Deferred, because the HUD is still readying its children.
	var host := get_parent()
	if host != null:
		var debrief := _Debrief.new()
		debrief.name = "DebriefScreen"
		host.add_child.call_deferred(debrief)
		var wallet := _Wallet.new()
		wallet.name = "WalletHUD"
		host.add_child.call_deferred(wallet)
	else:
		push_warning("ObjectiveHUD: no parent to put the debrief and wallet in.")


func _bind_tracker() -> void:
	if tracker == null and _campaign != null:
		tracker = _campaign.objectives
	if tracker == null:
		return
	if not tracker.objectives_refreshed.is_connected(_on_refreshed):
		tracker.objectives_refreshed.connect(_on_refreshed)
		tracker.objective_changed.connect(_on_changed)
		tracker.required_objectives_complete.connect(_on_all_complete)
	_rebuild()


func _ensure_full_rect() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0


func _build_ui() -> void:
	_panel = VBoxContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -(panel_margin.x + panel_width)
	_panel.offset_right = -panel_margin.x
	_panel.offset_top = panel_margin.y
	_panel.offset_bottom = panel_margin.y + 300.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.add_theme_constant_override("separation", 3)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_header = _make_label("OBJECTIVES", COL_BRIGHT, font_size_header)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_panel.add_child(_header)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_list)

	_toast = _make_label("", COL_WARN, font_size_header)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -360
	_toast.offset_right = 360
	# Tall enough for the multi-line payout card, not just a one-line ping. At
	# the old 30px the extraction summary was clipped to its first line.
	_toast.offset_top = 140
	_toast.offset_bottom = 300
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_toast.visible = false
	add_child(_toast)


func _make_label(text: String, col: Color, font_px: int = -1) -> Label:
	if font_px < 0:
		font_px = font_size_body
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", font_px)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ─────────────────────────────────────────────
# EXTRACTION MARKER
# A shaft of light with a chevron on the end, hanging over the exit once the
# work is done. Drawn rather than modelled so it needs no art and cannot be
# left unassigned in a scene.
#
# It appears ONLY when every required objective is complete. Before that the
# exit is not where you should be going, and pointing at it would be telling
# the player to leave.
# ─────────────────────────────────────────────
@export var extract_marker_enabled: bool = true
## Metres above the exit the arrow floats.
@export var extract_marker_height: float = 14.0
@export var extract_marker_size: float = 34.0

var _extract_objective: MissionObjective = null


func _find_extraction() -> MissionObjective:
	if tracker == null:
		return null
	for objective in tracker.objectives():
		if objective != null and objective.is_extraction:
			return objective
	return null


func _draw() -> void:
	if not extract_marker_enabled:
		return
	if tracker == null or not tracker.all_required_complete():
		return
	if _extract_objective == null or not is_instance_valid(_extract_objective):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var world_top: Vector3 = _extract_objective.global_position + Vector3.UP * extract_marker_height
	# Behind the camera unprojects to a mirrored on-screen point, which would
	# draw an arrow pointing at empty sky behind the player.
	if cam.is_position_behind(world_top):
		return

	var tip: Vector2 = cam.unproject_position(_extract_objective.global_position + Vector3.UP * 2.0)
	var top: Vector2 = cam.unproject_position(world_top)

	# Pulse so it reads as a signal rather than scenery.
	var pulse: float = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 260.0)
	var col: Color = COL_DONE
	col.a = pulse

	var size: float = maxf(10.0, extract_marker_size * clampf(
		1.0 - (top.distance_to(tip) / 900.0), 0.35, 1.0))

	draw_line(top, tip, col, 3.0)
	draw_polyline(PackedVector2Array([
		tip + Vector2(-size, -size),
		tip,
		tip + Vector2(size, -size),
	]), col, 4.0)
	var label_pos: Vector2 = top - Vector2(38.0, 12.0)
	draw_string(ThemeDB.fallback_font, label_pos, "EXTRACT",
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_body, col)


func _process(delta: float) -> void:
	_ensure_full_rect()
	# Cheap, and the tracker's contents change on every level load.
	if extract_marker_enabled:
		_extract_objective = _find_extraction()
		queue_redraw()
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.visible = false
			if not _toast_queue.is_empty():
				var next: Array = _toast_queue.pop_front()
				_show_toast(next[0], next[1], next[2])

	# Channel progress and kill counts change between signals, so poll the
	# numbers rather than rebuilding the whole list every frame.
	_timer += delta
	if _timer >= refresh_interval:
		_timer = 0.0
		_rebuild()


func _rebuild() -> void:
	if tracker == null and _campaign != null:
		tracker = _campaign.objectives
	# At base there genuinely are no objectives, so hide. But "in a mission with
	# zero objectives" is a SETUP PROBLEM, not a normal state — hiding there is
	# what made this look like a broken HUD instead of an empty level.
	var in_mission: bool = _campaign != null and _campaign.in_mission
	_panel.visible = in_mission
	if not in_mission:
		return

	if tracker == null or tracker.objectives().is_empty():
		for c in _list.get_children():
			c.queue_free()
		_header.text = "NO OBJECTIVES"
		_header.add_theme_color_override("font_color", COL_WARN)
		_list.add_child(_make_label("no MissionObjective nodes in level", COL_DIM))
		return

	for c in _list.get_children():
		c.queue_free()

	var progress: Array = tracker.required_progress()
	var ready_to_leave: bool = tracker.all_required_complete()
	# The header used to become "EXTRACT" once everything was done. It sat
	# directly above the list in the same right-aligned style, so it read as a
	# list row — and with the extraction objective ALSO listed, the panel showed
	# EXTRACT twice and in the wrong order. The header stays a header now; the
	# extraction row speaks for itself.
	_header.text = "OBJECTIVES  %d/%d" % [progress[0], progress[1]]
	_header.add_theme_color_override("font_color", COL_DONE if ready_to_leave else COL_BRIGHT)

	for objective in tracker.objectives():
		if not objective.active and not objective.completed:
			continue   # prerequisites not met — don't spoil it
		_list.add_child(_make_row(objective))


func _make_row(objective: MissionObjective) -> Control:
	var counts: Array = objective.progress()
	var current: int = counts[0]
	var target: int = counts[1]

	# label(), not display_name — carries the verb and never renders the bare
	# placeholder "Objective" for a node whose name was never authored.
	var label_text := objective.label()
	if objective.optional:
		label_text = "(%s)" % label_text
	var suffix := ""
	if target > 1:
		suffix = "  %d/%d" % [current, target]

	var col := COL_DIM
	var mark := "□"
	if objective.completed:
		col = COL_DONE
		mark = "■"
	elif objective.failed:
		col = COL_WARN
		mark = "✕"
	elif not objective.optional:
		col = COL_BRIGHT

	var row := _make_label("%s  %s%s" % [mark, label_text, suffix], col)
	if objective.completed:
		# Struck through rather than removed, so progress is legible.
		row.add_theme_constant_override("line_spacing", 0)
	return row


func _on_refreshed(_objectives: Array) -> void:
	_rebuild()


func _on_changed(objective: MissionObjective) -> void:
	# The extraction objective is not worth announcing on its own: completing it
	# IS the end of the mission, and _on_extracted puts the payout on screen a
	# moment later. Two toasts in a row, the first saying nothing useful, buried
	# the one that mattered.
	if objective.is_extraction:
		_rebuild()
		return
	if objective.completed:
		_show_toast("OBJECTIVE COMPLETE : %s" % objective.label().to_upper(), COL_DONE)
	elif objective.failed:
		_show_toast("OBJECTIVE FAILED : %s" % objective.label().to_upper(), COL_WARN)
	_rebuild()


# The payout used to be a toast here. It is the debrief screen now
# (debrief_screen.gd), which this HUD adds beside itself in _ready: the squad,
# what each robot killed, XP, resources and compute counting up, and unlocks.


func _on_all_complete() -> void:
	_show_toast("ALL OBJECTIVES COMPLETE — EXTRACT", COL_DONE)
	_rebuild()


func _show_toast(text: String, col: Color, seconds: float = 3.0) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", col)
	_toast.visible = true
	_toast_time = seconds
