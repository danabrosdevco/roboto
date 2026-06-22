extends Control
class_name DebugOverlay

# ─────────────────────────────────────────────
# DEBUG OVERLAY
# Toggle with ~ (backtick / tilde key).
# Add as a child of your HUD Control node.
# Wire up references in the inspector or via
# GameManager after _ready().
# ─────────────────────────────────────────────

@export var player: Player
@export var squads: Array[Squad] = []

# Auto-discover squads if not set in inspector
@export var auto_discover_squads: bool = true

var _visible: bool = false
var _panel: PanelContainer
var _scroll: ScrollContainer
var _vbox: VBoxContainer

# Sections
var _player_section: VBoxContainer
var _squad_section: VBoxContainer
var _perf_section: VBoxContainer
var _nav_section: VBoxContainer

# Timing
var _refresh_timer: float = 0.0
const REFRESH_RATE: float = 0.15  # seconds between updates

func _ready() -> void:
	_build_ui()
	visible = false

	if auto_discover_squads:
		await get_tree().process_frame
		_discover_squads()

func _discover_squads() -> void:
	var found = get_tree().get_nodes_in_group("squads")
	for s in found:
		if s is Squad and not squads.has(s):
			squads.append(s)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_U:  # ~ key
			_toggle()

func _toggle() -> void:
	_visible = !_visible
	visible = _visible

func _process(delta: float) -> void:
	if not _visible:
		return
	_refresh_timer += delta
	if _refresh_timer >= REFRESH_RATE:
		_refresh_timer = 0.0
		_refresh()

# ─────────────────────────────────────────────
# UI BUILD
# ─────────────────────────────────────────────
func _build_ui() -> void:
	# Root panel — top-right corner, semi-transparent
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -420
	_panel.offset_top = 10
	_panel.offset_right = -10
	_panel.offset_bottom = 10
	_panel.custom_minimum_size = Vector2(410, 0)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.78)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(390, 700)
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_panel.add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	_scroll.add_child(_vbox)

	# Title
	_vbox.add_child(_make_header("── DEBUG OVERLAY ──", Color(1.0, 0.9, 0.2)))

	# Sections
	_perf_section   = _make_section("PERFORMANCE")
	_player_section = _make_section("PLAYER")
	_nav_section    = _make_section("NAVIGATION")
	_squad_section  = _make_section("SQUADS")

	add_child(_panel)

func _make_header(text: String, color: Color = Color.WHITE) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 11)
	return l

func _make_section(title: String) -> VBoxContainer:
	var sep = HSeparator.new()
	_vbox.add_child(sep)
	var header = _make_header(title, Color(0.6, 0.9, 1.0))
	_vbox.add_child(header)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_vbox.add_child(box)
	return box

func _make_row(text: String, color: Color = Color(0.9, 0.9, 0.9)) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 10)
	return l

func _clear_section(section: VBoxContainer) -> void:
	for child in section.get_children():
		child.queue_free()

# ─────────────────────────────────────────────
# REFRESH
# ─────────────────────────────────────────────
func _refresh() -> void:
	_refresh_perf()
	_refresh_player()
	_refresh_nav()
	_refresh_squads()

func _refresh_perf() -> void:
	_clear_section(_perf_section)
	var fps = Engine.get_frames_per_second()
	var fps_color = Color.GREEN if fps >= 55 else (Color.YELLOW if fps >= 30 else Color.RED)
	_perf_section.add_child(_make_row("FPS: %d" % fps, fps_color))
	_perf_section.add_child(_make_row("Physics: %d bodies" % PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS)))
	_perf_section.add_child(_make_row("Draw calls: %d" % RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))

func _refresh_player() -> void:
	_clear_section(_player_section)
	if player == null:
		_player_section.add_child(_make_row("No player reference", Color.RED))
		return
	_player_section.add_child(_make_row("Health: %d / %d" % [player.health, player.max_health]))
	_player_section.add_child(_make_row("Position: %s" % _fmt_vec(player.global_position)))
	_player_section.add_child(_make_row("Velocity: %s  |  Speed: %.1f" % [_fmt_vec(player.velocity), player.velocity.length()]))
	_player_section.add_child(_make_row("Grounded: %s" % str(player.is_on_floor())))
	_player_section.add_child(_make_row("Bits: %d  |  Shards: %d" % [player.bits, player.shards]))
	if player.hud_weapon:
		_player_section.add_child(_make_row("Weapon: %s  |  Ammo: %d / %d" % [
			player.hud_weapon.name,
			player.hud_weapon.magazine_capacity,
			player.hud_weapon.magazine_size
		]))
	_player_section.add_child(_make_row("ADS: %s  |  Alive: %s" % [str(player.is_ads), str(player.alive)]))

func _refresh_nav() -> void:
	_clear_section(_nav_section)
	var cover_points = get_tree().get_nodes_in_group("cover_points")
	var occupied = cover_points.filter(func(cp): return cp.is_occupied()).size()
	_nav_section.add_child(_make_row("Cover points: %d total  |  %d occupied" % [cover_points.size(), occupied]))
	var obj_points = get_tree().get_nodes_in_group("squad_objective_points")
	_nav_section.add_child(_make_row("Objective points: %d" % obj_points.size()))

func _refresh_squads() -> void:
	_clear_section(_squad_section)

	if squads.is_empty():
		_discover_squads()

	if squads.is_empty():
		_squad_section.add_child(_make_row("No squads found. Add to 'squads' group.", Color.YELLOW))
		return

	for squad in squads:
		if squad == null:
			continue

		# Squad header
		var ctx_str = Squad.SquadContext.keys()[squad.context]
		var obj_str = Squad.SquadObjective.keys()[squad.objective]
		var living = squad.get_living_members().size()
		var total  = squad.squad_members.size()
		var nco_str = "NCO: %s" % (squad.nco.name if squad.nco and squad.nco.alive else "DEAD/NONE")

		var squad_color = Color(1.0, 0.5, 0.3) if squad.context == Squad.SquadContext.ENGAGED else Color(0.5, 1.0, 0.5)
		_squad_section.add_child(_make_row(
			"[%s]  %s  |  %s  |  %d/%d alive  |  %s" % [squad.name, ctx_str, obj_str, living, total, nco_str],
			squad_color
		))

		# Each member
		for ai in squad.squad_members:
			if ai == null:
				continue
			var row = _format_member_row(ai)
			var color = Color(0.5, 0.5, 0.5) if not ai.alive else Color(0.85, 0.85, 0.85)
			_squad_section.add_child(_make_row("  " + row, color))

		# Bound pairs
		if not squad.bound_pairs.is_empty():
			_squad_section.add_child(_make_row("  Bound pairs: %d active" % squad.bound_pairs.size(), Color(0.8, 0.7, 1.0)))

func _format_member_row(ai: AI) -> String:
	var alive_str = "✓" if ai.alive else "✗"
	var ai_state_str = Enemy.AIState.keys()[ai.ai_state] if ai is Enemy else "?"
	var pos_str = _fmt_vec(ai.global_position)

	if ai is Soldier:
		var s_state_str = Soldier.SoldierState.keys()[ai.soldier_state]
		var role_str    = Soldier.SoldierRole.keys()[ai.squad_role]
		var cover_str   = "IN COVER" if ai.at_cover else "exposed"
		return "%s %s  |  %s  |  %s  |  %s  |  %s  |  HP:%d" % [
			alive_str, ai.name, ai_state_str, s_state_str, role_str, cover_str, ai.health
		]
	else:
		return "%s %s  |  %s  |  %s  |  HP:%d" % [
			alive_str, ai.name, ai_state_str, pos_str, ai.health
		]

# ─────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────
func _fmt_vec(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]
