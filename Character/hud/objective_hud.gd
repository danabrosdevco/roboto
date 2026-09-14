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

const COL_DIM    := HUDPalette.DIM
const COL_BRIGHT := HUDPalette.BRIGHT
const COL_WARN   := HUDPalette.WARN
const COL_DONE   := HUDPalette.SIGNAL

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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_full_rect()
	z_index = 50
	_build_ui()
	_campaign = get_node_or_null("/root/Campaign")
	_bind_tracker()
	# Re-bind on every level load; the tracker persists but its contents don't.
	if _campaign != null:
		_campaign.deployed.connect(func(_m): _bind_tracker())
		_campaign.returned_to_base.connect(func(): _bind_tracker())


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
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_top = 150
	_toast.offset_bottom = 180
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	add_child(_toast)


func _make_label(text: String, col: Color, size: int = -1) -> Label:
	if size < 0:
		size = font_size_body
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	_ensure_full_rect()
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.visible = false

	# Channel progress and kill counts change between signals, so poll the
	# numbers rather than rebuilding the whole list every frame.
	_timer += delta
	if _timer >= refresh_interval:
		_timer = 0.0
		_rebuild()


func _rebuild() -> void:
	if tracker == null and _campaign != null:
		tracker = _campaign.objectives
	# At base there are no objectives and an empty panel looks like a bug.
	var in_mission: bool = _campaign != null and _campaign.in_mission
	var showing: bool = in_mission and tracker != null and not tracker.objectives().is_empty()
	_panel.visible = showing
	if not showing:
		return

	for c in _list.get_children():
		c.queue_free()

	var progress: Array = tracker.required_progress()
	var ready_to_leave: bool = tracker.all_required_complete()
	_header.text = "EXTRACT" if ready_to_leave else "OBJECTIVES  %d/%d" % [progress[0], progress[1]]
	_header.add_theme_color_override("font_color", COL_DONE if ready_to_leave else COL_BRIGHT)

	for objective in tracker.objectives():
		if not objective.active and not objective.completed:
			continue   # prerequisites not met — don't spoil it
		_list.add_child(_make_row(objective))


func _make_row(objective: MissionObjective) -> Control:
	var counts: Array = objective.progress()
	var current: int = counts[0]
	var target: int = counts[1]

	var name := objective.display_name
	if objective.optional:
		name = "(%s)" % name
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

	var row := _make_label("%s  %s%s" % [mark, name, suffix], col)
	if objective.completed:
		# Struck through rather than removed, so progress is legible.
		row.add_theme_constant_override("line_spacing", 0)
	return row


func _on_refreshed(_objectives: Array) -> void:
	_rebuild()


func _on_changed(objective: MissionObjective) -> void:
	if objective.completed:
		_show_toast("OBJECTIVE COMPLETE : %s" % objective.display_name.to_upper(), COL_DONE)
	elif objective.failed:
		_show_toast("OBJECTIVE FAILED : %s" % objective.display_name.to_upper(), COL_WARN)
	_rebuild()


func _on_all_complete() -> void:
	_show_toast("ALL OBJECTIVES COMPLETE — EXTRACT", COL_DONE)
	_rebuild()


func _show_toast(text: String, col: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", col)
	_toast.visible = true
	_toast_time = 3.0
