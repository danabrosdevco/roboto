extends Control
class_name SquadHUD

# ─────────────────────────────────────────────
# SQUAD HUD
# Add as a child of the HUD Control. Builds itself in code — no scene wiring —
# so it can be dropped in and iterated on without touching hud.tscn.
#
# THREE LAYERS
#   1. Roster panel (bottom left): the squad you're commanding, one row per
#      robot — callsign, role, health, signal integrity, current state.
#   2. Squad strip (above roster): other squads in range and their posture, so
#      you can see who else is on the field before you cycle to them.
#   3. World markers: a chevron over each member of the selected squad, drawn
#      through geometry at low alpha.
#
# NOTE ON THE MARKERS — this is what put the chevrons under the terrain:
# unproject_position() returns VIEWPORT coordinates, but _draw() paints in this
# Control's LOCAL space. If the node isn't at (0,0) at full-screen size the two
# disagree and every chevron lands offset by the node's position. In hud.tscn
# this node was saved at anchors_preset = 0, offset_top = 508 — so the arrows
# drew 508px below the robots, which reads as "beneath them, under the map".
# The draw pass now subtracts global_position and the rect is re-asserted every
# frame, so the markers are correct however the node ends up anchored.
# ─────────────────────────────────────────────

@export var commander: SquadCommander
@export var player: Player

# ── TEXT SIZE ─────────────────────────────────
@export var font_size_header: int = 24
@export var font_size_body: int = 20
@export var font_size_nearby: int = 18
@export var font_size_wheel: int = 22
@export var font_size_toast: int = 22
@export var font_size_marker: int = 16

# ── LAYOUT ────────────────────────────────────
@export var panel_margin: Vector2 = Vector2(24, 20)   # from bottom-left corner
@export var panel_size: Vector2 = Vector2(460, 420)
# Wheel position, measured from the TOP-LEFT of the squad panel. Positive x
# pushes it right of the roster, negative y lifts it above the panel top.
@export var wheel_offset: Vector2 = Vector2(500, -40)
@export var wheel_size: Vector2 = Vector2(560, 60)
@export var bar_size: Vector2 = Vector2(70, 12)

@export var marker_range: float = 150.0
@export var nearby_radius: float = 120.0
@export var refresh_interval: float = 0.15

# Pulled from HUDPalette so the player's own bars in ui.gd stay in step.
const COL_DIM     := HUDPalette.DIM
const COL_BRIGHT  := HUDPalette.BRIGHT
const COL_WARN    := HUDPalette.WARN
const COL_CRIT    := HUDPalette.CRIT
const COL_SIGNAL  := HUDPalette.SIGNAL

const ROLE_TAG := {
	Soldier.SoldierRole.NONE:       "--",
	Soldier.SoldierRole.SUPPRESSOR: "SUP",
	Soldier.SoldierRole.ADVANCER:   "ADV",
	Soldier.SoldierRole.FLANKER:    "FLK",
	Soldier.SoldierRole.FALLBACK:   "FBK",
	Soldier.SoldierRole.OVERWATCH:  "OVW",
}

var _panel: VBoxContainer
var _squad_header: Label
var _roster: VBoxContainer
var _nearby: VBoxContainer
var _wheel: HBoxContainer
var _toast: Label

var _timer: float = 0.0
var _toast_time: float = 0.0
var _wheel_labels: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Don't hard-assume the HUD's grandparent exposes `player` — a null here
	# aborted _ready() before _build_ui() and left the whole panel missing.
	# _autowire() covers it properly.
	var gp: Node = get_parent().get_parent() if get_parent() != null else null
	if gp != null and player == null:
		player = gp.get("player")
	_ensure_full_rect()
	# The HUD's SignalFilter ColorRect is a full-screen sibling; later siblings
	# draw on top, so sit above it or the filter buries the panel.
	z_index = 50
	_autowire()
	_build_ui()

	if commander != null:
		commander.squad_selected.connect(_on_squad_selected)
		commander.order_issued.connect(_on_order_issued)
		commander.contact_called.connect(_on_contact_called)
		commander.wheel_opened.connect(_on_wheel_opened)
		commander.wheel_moved.connect(_on_wheel_moved)
		commander.wheel_closed.connect(_on_wheel_closed)


# Unassigned exports are the single most likely reason nothing shows up, and
# they fail silently. Find the components ourselves if the inspector is blank.
func _autowire() -> void:
	if commander == null:
		commander = _find_first(get_tree().root, "SquadCommander")
	if player == null and commander != null:
		player = commander.player
	if commander == null:
		push_warning("SquadHUD: no SquadCommander found — roster will stay empty.")


# The scene file had this node at offset_top = 508 with anchors_preset = 0, so
# every _draw() coordinate was 508px low. Rather than rely on the .tscn being
# right, pin the rect here — it's a no-op once the values already match.
func _ensure_full_rect() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0


func _find_first(node: Node, cls: String):
	if node.is_class(cls) or (node.get_script() != null and node.get_script().get_global_name() == cls):
		return node
	for c in node.get_children():
		var found = _find_first(c, cls)
		if found != null:
			return found
	return null


# ─────────────────────────────────────────────
# UI CONSTRUCTION
# ─────────────────────────────────────────────
func _build_ui() -> void:
	_panel = VBoxContainer.new()
	# Explicit anchors + offsets rather than a preset plus position — presets
	# don't touch offsets, which is what left this pinned off-screen.
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = panel_margin.x
	_panel.offset_right = panel_margin.x + panel_size.x
	_panel.offset_top = -(panel_margin.y + panel_size.y)
	_panel.offset_bottom = -panel_margin.y
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.add_theme_constant_override("separation", 2)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_nearby = VBoxContainer.new()
	_nearby.add_theme_constant_override("separation", 0)
	_panel.add_child(_nearby)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_panel.add_child(spacer)

	_squad_header = _make_label("NO SQUAD", COL_BRIGHT, font_size_header)
	_panel.add_child(_squad_header)

	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 1)
	_panel.add_child(_roster)

	# Verb wheel. Anchored to the same bottom-left corner as the roster panel
	# and then offset from the panel's top-left, so wheel_offset shifts it
	# relative to the roster rather than relative to screen centre.
	_wheel = HBoxContainer.new()
	_wheel.anchor_left = 0.0
	_wheel.anchor_right = 0.0
	_wheel.anchor_top = 1.0
	_wheel.anchor_bottom = 1.0
	_wheel.alignment = BoxContainer.ALIGNMENT_BEGIN
	_wheel.add_theme_constant_override("separation", 14)
	_wheel.visible = false
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wheel)
	_layout_wheel()

	_toast = _make_label("", COL_BRIGHT, font_size_toast)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 0.0
	_toast.anchor_bottom = 0.0
	_toast.offset_left = -320
	_toast.offset_right = 320
	_toast.offset_top = 110
	_toast.offset_bottom = 140
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	add_child(_toast)


func _layout_wheel() -> void:
	if _wheel == null:
		return
	var panel_top := -(panel_margin.y + panel_size.y)
	_wheel.offset_left = panel_margin.x + wheel_offset.x
	_wheel.offset_right = panel_margin.x + wheel_offset.x + wheel_size.x
	_wheel.offset_top = panel_top + wheel_offset.y
	_wheel.offset_bottom = panel_top + wheel_offset.y + wheel_size.y


func _make_label(text: String, col: Color, size: int = -1) -> Label:
	if size < 0:
		size = font_size_body
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()


# ─────────────────────────────────────────────
# REFRESH
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	_ensure_full_rect()

	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.visible = false

	if _wheel != null and _wheel.visible:
		_layout_wheel()

	_timer += delta
	if _timer >= refresh_interval:
		_timer = 0.0
		_refresh_roster()
		_refresh_nearby()

	queue_redraw()   # world markers


func _refresh_roster() -> void:
	_clear(_roster)
	if commander == null:
		return
	var squad := commander.get_selected_squad()
	if squad == null:
		_squad_header.text = "NO SQUAD IN COMMAND"
		_squad_header.add_theme_color_override("font_color", COL_DIM)
		return

	# Read live contact rather than `context`. Three states, not two — "CLEAR"
	# on its own covered both "nothing has happened yet" and "the shooting just
	# stopped", which is why it looked stuck.
	var shooting: bool = squad.has_live_contact()
	var ctx := "CLEAR"
	var ctx_col := COL_BRIGHT
	if shooting:
		ctx = "CONTACT"
		ctx_col = COL_CRIT
	elif squad.is_in_contact():
		ctx = "BREAK %ds" % int(ceil(Squad.CONTACT_GRACE - squad.seconds_since_contact()))
		ctx_col = COL_WARN

	var obj: String = str(Squad.SquadObjective.keys()[squad.objective])
	var living := squad.get_living_members().size()
	var total := squad.squad_members.size()

	_squad_header.text = "%s  [%d/%d]  %s  %s" % [
		squad.get_display_name().to_upper(), living, total, obj, ctx]
	_squad_header.add_theme_color_override("font_color", ctx_col)

	var seen := {}
	for m in squad.squad_members:
		if m == null or not is_instance_valid(m):
			continue
		if seen.has(m.get_instance_id()):
			continue
		seen[m.get_instance_id()] = true
		_roster.add_child(_make_member_row(m))


func _make_member_row(m: Soldier) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_col := COL_CRIT if not m.alive else COL_BRIGHT
	row.add_child(_make_label(" %-10s" % m.soldier_name.left(10), name_col))

	var role_text: String = str(ROLE_TAG.get(m.squad_role, "--"))
	row.add_child(_make_label(role_text, COL_DIM))

	if not m.alive:
		row.add_child(_make_label("DESTROYED", COL_CRIT))
		return row

	row.add_child(_make_bar(float(m.health) / float(maxi(1, m.max_health)), _health_color(m)))
	row.add_child(_make_bar(m.signal_integrity, COL_SIGNAL))
	row.add_child(_make_label(_state_text(m), COL_DIM))
	return row


func _health_color(m: Soldier) -> Color:
	return HUDPalette.health_color(float(m.health) / float(maxi(1, m.max_health)))


func _state_text(m: Soldier) -> String:
	var sig := m.get_signal_state()
	if sig == Enemy.SignalState.EKILL:
		return "E-KILL"
	if sig == Enemy.SignalState.CRITICAL:
		return "NO LINK"
	if m.soldier_state != Soldier.SoldierState.NONE:
		return str(Soldier.SoldierState.keys()[m.soldier_state])
	return str(Enemy.AIState.keys()[m.ai_state])


func _make_bar(fraction: float, col: Color) -> Control:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = bar_size
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(fraction, 0.0, 1.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HUDPalette.style_bar(bar, col)
	return bar


func _refresh_nearby() -> void:
	_clear(_nearby)
	if commander == null:
		return
	var selected := commander.get_selected_squad()
	var squads := commander.get_nearby_squads(nearby_radius)
	if squads.is_empty():
		return

	_nearby.add_child(_make_label("IN RANGE", COL_DIM, font_size_nearby))
	for s in squads:
		var squad := s as Squad
		var hostile := _is_hostile_squad(squad)
		var col := COL_CRIT if hostile else COL_DIM
		if squad == selected:
			col = COL_BRIGHT
		var dist := 0.0
		if player != null:
			dist = player.global_position.distance_to(squad.get_center())
		var mark := "*" if squad == selected else " "
		var side := "HOSTILE" if hostile else "FRIENDLY"
		_nearby.add_child(_make_label(
			"%s%-8s %-8s %3dm  %d" % [
				mark, squad.get_display_name().left(8).to_upper(), side,
				int(dist), squad.get_living_members().size()],
			col, font_size_nearby))


func _is_hostile_squad(squad: Squad) -> bool:
	for m in squad.get_living_members():
		return Enums.are_hostile(Enums.Factions.PLAYER, m.faction)
	return false


# ─────────────────────────────────────────────
# WORLD MARKERS
# ─────────────────────────────────────────────
func _draw() -> void:
	if commander == null or player == null:
		return
	var squad := commander.get_selected_squad()
	if squad == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	# unproject_position() is viewport space, _draw() is local space.
	# Subtracting global_position converts between the two — this is the fix for
	# chevrons landing far below their robots.
	var origin := global_position
	var view_rect := Rect2(Vector2.ZERO, get_viewport_rect().size)

	# One chevron per body. squad_members can hold the same Soldier twice after
	# an add_ai_to_squad/roster shuffle, and a body that has died still sits in
	# the world as a corpse — both produced doubled arrows.
	var drawn := {}

	for m in squad.get_living_members():
		if m == null or not is_instance_valid(m):
			continue
		var id: int = m.get_instance_id()
		if drawn.has(id):
			continue
		drawn[id] = true

		var world_pos: Vector3 = m.global_position + Vector3.UP * 2.1
		if camera.is_position_behind(world_pos):
			continue
		var dist := camera.global_position.distance_to(world_pos)
		if dist > marker_range:
			continue

		var p := camera.unproject_position(world_pos)
		if not view_rect.has_point(p):
			continue
		p -= origin

		var alpha: float = clampf(1.0 - (dist / marker_range), 0.25, 0.9)
		var col := COL_BRIGHT
		col.a = alpha

		# Chevron
		var size := clampf(10.0 - dist * 0.03, 4.0, 10.0)
		var pts := PackedVector2Array([
			p + Vector2(-size, -size * 0.7),
			p + Vector2(0, size * 0.5),
			p + Vector2(size, -size * 0.7),
		])
		draw_polyline(pts, col, 1.5)

		if dist < 45.0:
			var tag: String = str(ROLE_TAG.get(m.squad_role, ""))
			if tag != "" and tag != "--":
				draw_string(ThemeDB.fallback_font, p + Vector2(size + 3, 2),
					tag, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_marker, col)


# ─────────────────────────────────────────────
# SIGNAL HANDLERS
# ─────────────────────────────────────────────
func _on_squad_selected(squad: Squad) -> void:
	if squad != null:
		_show_toast("COMMANDING %s" % squad.get_display_name().to_upper(), COL_BRIGHT)
	_refresh_roster()


func _on_order_issued(squad: Squad, verb: int, _position: Vector3, target: Node) -> void:
	var verb_text: String = str(SquadCommander.VERB_LABELS.get(verb, "ORDER"))
	var suffix := ""
	if target != null and target is Enemy:
		suffix = " > %s" % (target as Enemy).soldier_name.to_upper()
	_show_toast("%s : %s%s" % [squad.get_display_name().to_upper(), verb_text, suffix], COL_BRIGHT)


func _on_contact_called(_position: Vector3, target: Node) -> void:
	var what := "CONTACT"
	if target != null and target is Enemy:
		what = "CONTACT: %s" % (target as Enemy).soldier_name.to_upper()
	_show_toast(what, COL_WARN)


func _on_wheel_opened(labels: Array, index: int) -> void:
	_clear(_wheel)
	_wheel_labels.clear()
	for i in labels.size():
		var l := _make_label(labels[i], COL_DIM, font_size_wheel)
		_wheel.add_child(l)
		_wheel_labels.append(l)
	_wheel.visible = true
	_on_wheel_moved(index)


func _on_wheel_moved(index: int) -> void:
	for i in _wheel_labels.size():
		var l: Label = _wheel_labels[i]
		l.add_theme_color_override("font_color", COL_BRIGHT if i == index else COL_DIM)
		l.add_theme_font_size_override("font_size",
			font_size_wheel + 3 if i == index else font_size_wheel)


func _on_wheel_closed() -> void:
	_wheel.visible = false


func _show_toast(text: String, col: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", col)
	_toast.visible = true
	_toast_time = 2.2
