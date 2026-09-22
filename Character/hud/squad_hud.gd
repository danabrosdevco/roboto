extends Control
class_name SquadHUD

# ─────────────────────────────────────────────
# SQUAD HUD
# Add as a child of the HUD Control. Builds itself in code — no scene wiring —
# so it can be dropped in and iterated on without touching hud.tscn.
#
# THREE LAYERS
#   1. Roster panel (bottom left): the squad you're commanding, one row per
#      robot — callsign, health, signal integrity, current state. With more
#      than one team in the field that is all of them, the ones you are not
#      ordering dimmed; switching (G) says ORDERS > ARMOR above the weapon bar.
#
# WHY THE ROLE COLUMN IS GONE
# Rows used to carry a role tag (SUP/ADV/FLK/FBK/OVW) AND a state
# (SUPPRESSING/COVER_SEEKING/BOUNDING/SUPPRESSED). Two columns of jargon, both
# describing how assign_roles() carved the squad up — bookkeeping, not anything
# the player can act on. Worse, SUPPRESSING and SUPPRESSED differ by one letter
# and mean opposite things, and bounding is inherently a PAIR taking turns while
# the roster showed each half as an isolated static label.
#
# Bounding should be something you see in the world — soldiers visibly
# alternating movement — not something you read in a list. So state collapses to
# the three things worth knowing, and PINNED is the only one that asks anything
# of you. The roles still exist and still drive the AI; they're just internal
# now. The debug overlay is the right place for them.
#   2. Squad strip (above roster): other squads in range and their posture, so
#      you can see who else is on the field before you cycle to them.
#   3. World markers: a chevron over each member of your teams (or the
#      selected squad), drawn through geometry at low alpha; quieter still for
#      the team you are not ordering.
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
@export var order_ux_sound: AudioStreamPlayer
@export var order_ux_sound_confirm: AudioStreamPlayer

# ── TEXT SIZE ─────────────────────────────────
@export var font_size_header: int = 24
@export var font_size_body: int = 20
@export var font_size_nearby: int = 18
@export var font_size_toast: int = 22
@export var font_size_marker: int = 16

# ── LAYOUT ────────────────────────────────────
## Gap from the bottom-left corner of the screen. **Y IS THE LIFT** — the whole
## panel hangs off its bottom edge, so this is the one number that moves it up
## or down as a unit. It was 20, which put the roster directly on top of the
## player's own health readout; that bottom strip needs roughly 200px.
@export var panel_margin: Vector2 = Vector2(24, 210)
## X is the panel width. Y is no longer used for height at all — the panel sizes
## itself to its contents. See min_panel_height.
@export var panel_size: Vector2 = Vector2(460, 420)
## Smallest the panel may shrink to. Only guards against the container
## reporting a zero minimum before its first layout, which blanked the HUD.
@export var min_panel_height: float = 90.0
# Wheel position, measured from the TOP-LEFT of the squad panel. Positive x
# pushes it right of the roster, negative y lifts it above the panel top.
@export var bar_size: Vector2 = Vector2(70, 12)

## Space between a toast and the top of the weapon bar it sits over.
@export var toast_gap: float = 8.0

@export var marker_range: float = 150.0

# ── MARKER HEALTH STATE ───────────────────────
# The chevron is colour-coded by health, using the same thresholds as the roster
# bars so the two readouts can never disagree. Below hurt_at it also grows a
# small bar underneath — quiet by default, so a healthy squad stays clean and a
# hurt one is immediately obvious across the map.
@export var marker_hurt_at: float = 0.6
@export var marker_critical_at: float = 0.3
# Critical markers pulse. Motion is the only channel that reads at distance once
# the chevron is a few pixels wide and colour alone stops being legible.
@export var marker_pulse_speed: float = 4.5
@export var marker_pulse_depth: float = 0.35
@export var marker_bar_width: float = 22.0
@export var marker_bar_height: float = 3.0
@export var nearby_radius: float = 120.0
## How many squads the IN RANGE strip will list. The panel is a fixed height
## holding this strip AND the roster, so an unbounded list used to push the
## roster off the bottom — the rows past the edge simply never appeared, which
## read as the strip refusing to update. Bounded explicitly and sorted nearest
## first, so what falls off the end is always the furthest squad.
@export var max_nearby: int = 12

# ── STATUS RECENCY ────────────────────────────
# FIRING and the equipment callout are recent EVENTS, not states — there is no
# "currently shooting" flag to read, and equipment use is instantaneous. These
# are how long each one stays on the readout after it happens. Long enough to
# catch the eye, short enough that it always clears itself.
@export var firing_state_seconds: float = 1.0
@export var equipment_state_seconds: float = 2.0
## Print hostile squad sizes as a number instead of LIGHT/SQUAD/HEAVY/MASSED.
## Your own squads always show an exact count either way.
@export var exact_hostile_counts: bool = false
@export var refresh_interval: float = 0.15

# Pulled from HUDPalette so the player's own bars in ui.gd stay in step.
const COL_DIM     := HUDPalette.DIM
const COL_BRIGHT  := HUDPalette.BRIGHT
const COL_WARN    := HUDPalette.WARN
const COL_CRIT    := HUDPalette.CRIT
const COL_SIGNAL  := HUDPalette.SIGNAL

# The three states a player can act on. Everything the AI does maps onto one of
# them; the distinctions it drops were never actionable.
const STATE_MOVING := "MOVING"
const STATE_FIRING := "FIRING"
const STATE_PINNED := "PINNED"
const STATE_HOLDING := "HOLDING"
const STATE_RELOADING := "RELOADING"
const STATE_DOWN := "DOWN"
const STATE_REPAIRING := "REPAIRING"
const STATE_SALVAGING := "SALVAGING"

var _panel: VBoxContainer
var _squad_header: Label
var _roster: VBoxContainer
var _nearby: VBoxContainer
var _toast: Label

var _timer: float = 0.0
var _toast_time: float = 0.0
var _pulse: float = 0.0


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
	# Order clicks are interface sounds: the INTERFACE slider, not EFFECTS.
	for p in [order_ux_sound, order_ux_sound_confirm]:
		if p != null:
			p.bus = AudioBuses.INTERFACE
	_autowire()
	_build_ui()

	# Renames and losses should land at once rather than waiting up to
	# refresh_interval for the next poll.
	for squad in get_tree().get_nodes_in_group("squads"):
		if squad is Squad and not (squad as Squad).roster_changed.is_connected(_on_roster_changed):
			(squad as Squad).roster_changed.connect(_on_roster_changed)

	if commander != null:
		commander.squad_selected.connect(_on_squad_selected)
		commander.order_issued.connect(_on_order_issued)
		commander.contact_called.connect(_on_contact_called)
		commander.team_selected.connect(_on_team_selected)
		commander.no_team_to_switch.connect(_on_no_team_to_switch)


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
	_size_panel_to_content()


# THE PANEL GROWS UPWARD. Its bottom edge is pinned at panel_margin.y above the
# screen bottom and the top edge rises to fit whatever is in it.
#
# It used to have a fixed height, with the IN RANGE strip as the FIRST child of
# the VBox — so every extra squad in range pushed the roster DOWNWARD, out of
# the panel and into the player's own health readout. Walk into a fight with
# eight squads nearby and the thing you actually needed, your own squad, was the
# thing that got shoved off the bottom.
#
# Sizing to content instead means new rows can only ever extend into empty
# screen above, and the roster never moves.
func _size_panel_to_content() -> void:
	if _panel == null:
		return
	var needed: float = _panel.get_combined_minimum_size().y
	# A SMALL floor, not panel_size.y.
	#
	# Sizing purely to content made the whole HUD vanish, because
	# get_combined_minimum_size() reports 0 before the container has ever been
	# laid out and again whenever the roster is empty. But flooring at
	# panel_size.y (420) was the opposite mistake: the panel then ALWAYS
	# occupied 420px, and since it hangs from its bottom edge, lifting it clear
	# of the health readout pushed its top up to the top of the screen. It only
	# needs to be tall enough that it cannot disappear.
	var h: float = maxf(min_panel_height, needed)
	# And never taller than the screen it has to fit on.
	h = minf(h, maxf(min_panel_height, size.y - panel_margin.y - 20.0))
	_panel.offset_top = -(panel_margin.y + h)
	_panel.offset_bottom = -panel_margin.y


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


	# Command feedback (ORDERS > ARMOR, INFANTRY : ADVANCE) sits directly above
	# the weapon bar: bottom-centre, where the eye goes on a switch, and out of
	# the middle of the screen, where it covered what you were aiming at.
	_toast = _make_label("", COL_BRIGHT, font_size_toast)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = -320
	_toast.offset_right = 320
	_toast.offset_bottom = -(_weapon_bar_lift() + toast_gap)
	_toast.offset_top = _toast.offset_bottom - 30
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	# Down there it sits over the ground, not the sky: a dark edge keeps the pale
	# green readable on pale terrain, as the order markers' labels have.
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	_toast.visible = false
	add_child(_toast)


func _weapon_bar_lift() -> float:
	return WeaponBar.lift_beside(self)


func _make_label(text: String, col: Color, font_px: int = -1) -> Label:
	if font_px < 0:
		font_px = font_size_body
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", font_px)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# remove_child BEFORE queue_free. queue_free is deferred to the end of the
# frame, so a container cleared and immediately refilled still holds the dying
# children while the new ones go in — the roster and the IN RANGE strip both
# render doubled for that frame, and at a 0.15s refresh that is most of them.
# Same bug that duplicated equipment rows in the squad manager.
func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
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


	_pulse += delta

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
	var shown := _shown_squads()
	if shown.is_empty():
		_squad_header.text = "NO SQUAD IN COMMAND"
		_squad_header.add_theme_color_override("font_color", COL_DIM)
		return

	# One block per team, the one you are not ordering dimmed. The first header
	# is the panel's own; the rest go in with the rows.
	var selected := commander.get_selected_squad()
	for i in shown.size():
		var squad: Squad = shown[i]
		var quiet := shown.size() > 1 and squad != selected
		var header: Label = _squad_header
		if i > 0:
			header = _make_label("", COL_BRIGHT, font_size_header)
			_roster.add_child(header)
		_fill_header(header, squad, quiet)
		var seen := {}
		for m in squad.squad_members:
			if m == null or not is_instance_valid(m):
				continue
			if seen.has(m.get_instance_id()):
				continue
			seen[m.get_instance_id()] = true
			var row := _make_member_row(m)
			if quiet:
				row.modulate.a = 0.45
			_roster.add_child(row)


func _fill_header(header: Label, squad: Squad, quiet: bool) -> void:
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

	header.text = "%s  [%d/%d]  %s  %s" % [
		squad.get_display_name().to_upper(), living, total, obj, ctx]
	header.add_theme_color_override("font_color", Color(ctx_col, 0.45) if quiet else ctx_col)


# Your teams, all of them, whichever you are ordering: the others dimmed.
# Someone else's squad, picked by aiming at one of its robots, shows on its own;
# so does a hand-placed squad in a level that deployed no teams.
func _shown_squads() -> Array:
	var selected := commander.get_selected_squad()
	var teams := commander.team_squads()
	if not teams.is_empty() and (selected == null or selected.team != &""):
		return teams
	return [selected] if selected != null else []


func _make_member_row(m: Soldier) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_col := COL_CRIT if not m.alive else COL_BRIGHT
	row.add_child(_make_label(" %-10s" % m.soldier_name.left(10), name_col))

	if not m.alive:
		# A wreck you can bring back reads very differently from one you can't,
		# and it's the difference between walking over there and not.
		var is_down: bool = "downed" in m and m.downed
		row.add_child(_make_label("DOWNED" if is_down else "DESTROYED",
			COL_WARN if is_down else COL_CRIT))
		return row

	row.add_child(_make_bar(float(m.health) / float(maxi(1, m.max_health)), _health_color(m)))
	row.add_child(_make_bar(m.signal_integrity, COL_SIGNAL))
	var state := _state_text(m)
	# PINNED is the only state that's a request rather than a report, so it's
	# the only one that gets to be loud.
	row.add_child(_make_label(state, COL_WARN if state == STATE_PINNED else COL_DIM))
	return row


func _health_color(m: Soldier) -> Color:
	return HUDPalette.health_color(float(m.health) / float(maxi(1, m.max_health)))


func _state_text(m: Soldier) -> String:
	var sig := m.get_signal_state()
	if sig == Enemy.SignalState.EKILL:
		return "E-KILL"
	if sig == Enemy.SignalState.CRITICAL:
		return "NO LINK"

	# ORDERED BY WHAT THE PLAYER WOULD ACT ON, most urgent first.
	#
	# The old version read `ai_state == COMBAT` as FIRING. COMBAT means "has a
	# target", not "is shooting" — so a soldier who acquired someone and then
	# spent ten seconds walking, reloading or waiting for a firing line still
	# read FIRING the entire time. It was a state that latched on and never let
	# go, which is why it looked broken.
	#
	# Everything below is either a live fact (reloading right now) or a recent
	# event (a round left the barrel in the last second), so every line can go
	# away on its own.
	if "downed" in m and m.downed:
		return STATE_DOWN

	# What they just did beats what they are doing: throwing a grenade is the
	# single most useful thing to know about a squadmate in the moment.
	if m.seconds_since_equipment() <= equipment_state_seconds:
		return m.last_equipment_label().to_upper().left(9)

	if m.weapon != null and m.weapon.is_reloading:
		return STATE_RELOADING

	if m.soldier_state == Soldier.SoldierState.SUPPRESSED:
		return STATE_PINNED

	# A Mechanic at work. Standing still over a wreck otherwise reads HOLDING,
	# which is the one thing it is not doing.
	if m.has_method("is_repairing") and m.is_repairing():
		return STATE_REPAIRING
	# A Reclaimer with its drum in a wreck: working, not holding.
	if m.has_method("is_salvaging") and m.is_salvaging():
		return STATE_SALVAGING

	if m.weapon != null and m.weapon.seconds_since_fired() <= firing_state_seconds:
		return STATE_FIRING

	if m.movement_state != Enemy.MovementState.NONE:
		return STATE_MOVING
	return STATE_HOLDING


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
	var squads := commander.get_nearby_squads(nearby_radius)
	if squads.is_empty():
		return

	var shown: int = squads.size() if max_nearby <= 0 else mini(squads.size(), max_nearby)
	var header := "IN RANGE" if shown >= squads.size() else "IN RANGE (%d/%d)" % [shown, squads.size()]
	_nearby.add_child(_make_label(header, COL_DIM, font_size_nearby))
	# Starred and bright: whoever the next order goes to.
	var selected := commander.get_selected_squad()
	var by_team := commander.has_teams()
	for i in shown:
		var s = squads[i]
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
		# Yours go by team name, ten letters at most (CampaignState.TEAM_NAME_MAX)
		# so none is cut short.
		var who: String = squad.team_name() if by_team and squad.team != &"" else squad.get_display_name().to_upper()
		_nearby.add_child(_make_label(
			"%s%-10s %-8s %3dm  %s" % [
				mark, who.left(10), side,
				int(dist), _strength_text(squad, hostile)],
			col, font_size_nearby))


# You know your own squad exactly. You ESTIMATE theirs.
#
# An exact headcount on a hostile squad is a lot of certainty to hand the player
# for free, and it reads as a spreadsheet rather than a contact report. A
# sensor return that says "something heavy, 60m that way" is the same decision
# with better texture — and it is what a robot picking up signatures through
# terrain would plausibly get.
func _strength_text(squad: Squad, hostile: bool) -> String:
	var n: int = squad.get_living_members().size()
	if not hostile or exact_hostile_counts:
		return str(n)
	if n <= 2:
		return "LIGHT"
	if n <= 5:
		return "SQUAD"
	if n <= 9:
		return "HEAVY"
	return "MASSED"


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
	var shown := _shown_squads()
	if shown.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	# One chevron per body. squad_members can hold the same Soldier twice after
	# an add_ai_to_squad/roster shuffle, and a body that has died still sits in
	# the world as a corpse — both produced doubled arrows.
	var drawn := {}
	var selected := commander.get_selected_squad()
	for squad: Squad in shown:
		# The team you are not ordering right now: still marked, quieter.
		_draw_squad(squad, camera, drawn, shown.size() > 1 and squad != selected)


func _draw_squad(squad: Squad, camera: Camera3D, drawn: Dictionary, quiet: bool) -> void:
	# unproject_position() is viewport space, _draw() is local space.
	# Subtracting global_position converts between the two — this is the fix for
	# chevrons landing far below their robots.
	var origin := global_position
	var view_rect := Rect2(Vector2.ZERO, get_viewport_rect().size)

	# Living members PLUS anyone downed — a wreck you can revive is exactly the
	# thing you most need to be able to find across a map.
	var markable: Array = squad.get_living_members()
	for m in squad.squad_members:
		if m != null and is_instance_valid(m) and "downed" in m and m.downed:
			if not markable.has(m):
				markable.append(m)

	for m in markable:
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
		if quiet:
			alpha *= 0.4

		# Same helper the roster bars use, so the chevron and the bar can never
		# disagree about whether someone is in trouble.
		var hp: float = float(m.health) / float(maxi(1, m.max_health))
		var is_downed: bool = "downed" in m and m.downed
		var col: Color = HUDPalette.health_color(hp)
		var critical: bool = is_downed or hp <= marker_critical_at
		var hurt: bool = hp <= marker_hurt_at

		if critical:
			# Pulse toward full opacity rather than away from it, so a critical
			# marker is never dimmer than a healthy one.
			var beat: float = (sin(_pulse * marker_pulse_speed) + 1.0) * 0.5
			alpha = clampf(alpha + beat * marker_pulse_depth, 0.0, 1.0)
		col.a = alpha

		# Hurt markers are drawn slightly heavier as well as recoloured —
		# colour alone is a poor signal for anyone red/green colourblind.
		var width: float = 2.6 if critical else (2.0 if hurt else 1.5)

		# Chevron
		var marker_size := clampf(10.0 - dist * 0.03, 4.0, 10.0)
		var pts := PackedVector2Array([
			p + Vector2(-marker_size, -marker_size * 0.7),
			p + Vector2(0, marker_size * 0.5),
			p + Vector2(marker_size, -marker_size * 0.7),
		])
		draw_polyline(pts, col, width)

		# Critical gets a second, larger chevron behind it — a halo that reads
		# as urgency at distances where the pulse is too small to notice.
		if critical:
			var halo: Color = col
			halo.a = alpha * 0.35
			var hs: float = marker_size * 1.6
			draw_polyline(PackedVector2Array([
				p + Vector2(-hs, -hs * 0.7),
				p + Vector2(0, hs * 0.5),
				p + Vector2(hs, -hs * 0.7),
			]), halo, width)

		# Health bar, only once they're hurt. A bar over every healthy squadmate
		# is noise you have to read past to find the one that matters.
		if hurt and dist < 90.0:
			var bar_w: float = marker_bar_width * clampf(1.0 - dist / 160.0, 0.45, 1.0)
			var bar_h: float = marker_bar_height
			var bar_top: float = p.y - marker_size * 1.05 - bar_h - 2.0
			var back: Color = COL_DIM
			back.a = alpha * 0.45
			draw_rect(Rect2(p.x - bar_w * 0.5, bar_top, bar_w, bar_h), back, true)
			var fill: Color = col
			fill.a = alpha
			draw_rect(Rect2(p.x - bar_w * 0.5, bar_top, bar_w * clampf(hp, 0.0, 1.0), bar_h), fill, true)

		# Only a pinned squadmate gets text in the world. Tagging every robot
		# with its role was noise you had to read past to find the one that
		# mattered.
		if is_downed and dist < 90.0:
			var down_col := COL_CRIT
			down_col.a = alpha
			draw_string(ThemeDB.fallback_font, p + Vector2(marker_size + 3, 2),
				"DOWNED", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_marker, down_col)
		elif dist < 60.0 and m.soldier_state == Soldier.SoldierState.SUPPRESSED:
			var warn := COL_WARN
			warn.a = alpha
			draw_string(ThemeDB.fallback_font, p + Vector2(marker_size + 3, 2),
				STATE_PINNED, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_marker, warn)


# ─────────────────────────────────────────────
# SIGNAL HANDLERS
# ─────────────────────────────────────────────
func _on_roster_changed(_squad: Squad) -> void:
	_refresh_roster()


func _on_squad_selected(squad: Squad) -> void:
	# With teams, team_selected follows and says who the orders go to — one
	# toast rather than two landing on top of each other.
	if squad != null and not commander.has_teams():
		_show_toast("COMMANDING %s" % squad.get_display_name().to_upper(), COL_BRIGHT)
	_refresh_roster()
	_refresh_nearby()


# G.
func _on_team_selected(label: String) -> void:
	if commander.has_teams():
		_show_toast("ORDERS > %s" % label, COL_BRIGHT)
	_refresh_roster()
	_refresh_nearby()


func _on_no_team_to_switch() -> void:
	_show_toast("NO OTHER TEAM", COL_DIM)


func _on_order_issued(squad: Squad, verb: int, _position: Vector3, target: Node) -> void:
	var verb_text: String = str(SquadCommander.VERB_LABELS.get(verb, "ORDER"))
	var suffix := ""
	if target != null and target is Enemy:
		suffix = " > %s" % (target as Enemy).soldier_name.to_upper()
	# Who it went to: with two teams, the team.
	var who := squad.team_name() if commander.has_teams() else squad.get_display_name().to_upper()
	_show_toast("%s : %s%s" % [who, verb_text, suffix], COL_BRIGHT)
	order_ux_sound_confirm.play()


func _on_contact_called(_position: Vector3, target: Node) -> void:
	var what := "CONTACT"
	if target != null and target is Enemy:
		what = "CONTACT: %s" % (target as Enemy).soldier_name.to_upper()
	_show_toast(what, COL_WARN)


func _show_toast(text: String, col: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", col)
	_toast.visible = true
	_toast_time = 2.2
