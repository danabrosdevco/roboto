extends HBoxContainer

# ─────────────────────────────────────────────
# SQUAD — who goes, in which team, and what they carry.
#
# Every robot is a card: its frame, its name, its gear as icons, and one word
# that answers "is it ready?" — READY, NO WEAPON, DESTROYED. The DEPLOYING row
# up top has a seat for each point of supply; the BENCH takes none.
#
# TEAMS. The squad goes into the field as teams, each one ordered on its own
# (G picks which). Each is a section with its robots' cards under its name:
# click the name to rename it, click the rest of its header to fold it away.
# Drag a card to another team to move it, onto the strip under the teams to
# start a new one, or onto the bench to leave it at base. A team goes when the
# last robot leaves it. Nothing else: no buttons for making or deleting teams.
# The bench has its own scroll, so it is on screen however long the teams run.
#
# Select a card and its slots open on the right. Click a slot, and the list
# under it is what you have IN STORES that fits it — no prices on this page,
# buying is the Armorer's job. Click an item to fit it; right-click a slot to
# take off what is in it.
#
# No health bars: everyone who comes home standing is repaired at the end of
# the mission (CampaignState.heal_survivors), so the only damage there is to
# see is a destroyed robot, and that has its own REBUILD button.
# ─────────────────────────────────────────────

const Kit := preload("res://Character/hud/squad/ui_kit.gd")
const Icons := preload("res://Character/hud/icons/icons.gd")
const DETAIL_WIDTH := 400.0
const REPAIR_TOOL := &"repair_tool"
## What a dragged card carries: {DRAG_KEY: the robot's record}.
const DRAG_KEY := "squad_page_robot"

var ui   # the SquadManagerUI; untyped because it preloads this script
var selected: SoldierRecord
var slot_kind: int = ItemDefinition.Kind.WEAPON
var slot_index: int = 0

var _left: VBoxContainer
var _head: VBoxContainer
var _teams: VBoxContainer
var _bench_head: HBoxContainer
var _bench_panel: PanelContainer
var _bench: VBoxContainer
var _bench_scroll: ScrollContainer
var _teams_scroll: ScrollContainer
var _detail: VBoxContainer
# Every card on the page, so a click can re-light them in place (see _pick).
var _cards: Array[Control] = []
var _lit_card: Control = null
# Team id -> folded away. Kept while the game runs, not saved.
var _folded := {}
# What can take a dropped card, by _key(where), and the one lit up under it.
var _targets := {}
var _hot: Control = null
# Who the next operation takes, when it takes fewer than everyone.
var _op: MissionDefinition = null
var _capped := false
var _going: Array = []


func setup(owner_ui) -> void:
	ui = owner_ui
	add_theme_constant_override("separation", 22)
	_left = Kit.vbox(8)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_left)
	# Pinned: the seats are what every move on this page is spent against.
	_head = Kit.vbox(4)
	_left.add_child(_head)
	_teams_scroll = _scroll()
	# The teams take whatever the bench leaves: see _build_bench.
	_left.add_child(_teams_scroll)
	_teams = Kit.vbox(10)
	_teams.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_teams_scroll.add_child(_teams)
	_bench_head = Kit.hbox(10)
	_left.add_child(_bench_head)
	_bench_panel = PanelContainer.new()
	_bench_panel.size_flags_vertical = Control.SIZE_FILL
	_drop_target(_bench_panel, {"kind": &"bench"})
	_left.add_child(_bench_panel)
	_bench_scroll = _scroll()
	_bench_panel.add_child(_bench_scroll)
	_bench = Kit.vbox(8)
	_bench.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bench_scroll.add_child(_bench)

	var side := PanelContainer.new()
	var line := StyleBoxFlat.new()
	line.bg_color = Color(0, 0, 0, 0)
	line.border_color = Kit.LINE
	line.border_width_left = 1
	line.content_margin_left = 20
	side.add_theme_stylebox_override("panel", line)
	side.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	add_child(side)
	_detail = Kit.vbox(8)
	side.add_child(_detail)


## Opening onto nobody selected costs a click every time; the player is who
## you most often came to change.
func on_open() -> void:
	if not _listed(selected):
		_select(ui.state.player_record, false)


## Arriving from the Armorer's "fit it": land on the selected robot's first
## empty slot of that kind (or its first, if none is empty).
func focus_kind(kind: int) -> void:
	if not _listed(selected):
		_select(ui.state.player_record, false)
	var slots: Array = _slots(selected, kind)
	if slots.is_empty():
		return
	slot_kind = kind
	slot_index = maxi(slots.find(&""), 0)


func rebuild() -> void:
	if not _listed(selected):
		_select(ui.state.player_record, false)
	# Quiet, and nothing to do once every robot has a team: here for a roster
	# that gained robots some other way than the Factory (a test rig).
	ui.state.ensure_teams()
	for area in [_head, _teams, _bench_head, _bench]:
		Kit.clear(area)
	_cards.clear()
	_lit_card = null
	_targets.clear()
	_targets[_key({"kind": &"bench"})] = _bench_panel
	_hot = null
	_style_target(_bench_panel, false)
	_build_head()
	_build_teams()
	_build_bench()
	_rebuild_detail()


func _rebuild_detail() -> void:
	Kit.clear(_detail)
	if selected != null:
		_build_detail()


func _listed(record: SoldierRecord) -> bool:
	return record != null and (record == ui.state.player_record or ui.state.roster.has(record))


func _select(record: SoldierRecord, announce: bool = true) -> void:
	selected = record
	_default_slot()
	if announce:
		ui.play(&"select")
		rebuild()


# A click on a card selects it WHERE IT IS: the cards are re-lit and the panel
# on the right rebuilt, and the list is left standing. Rebuilding it freed the
# card under the mouse on the press, so the same press could never go on to
# become a drag.
func _pick(record: SoldierRecord) -> void:
	selected = record
	_default_slot()
	ui.play(&"select")
	for card in _cards:
		if is_instance_valid(card):
			_style_card(card, card == _lit_card)
	_rebuild_detail()


# The slot most worth looking at: the weapon if there is none, then the first
# empty gear or module slot, else the weapon.
func _default_slot() -> void:
	slot_kind = ItemDefinition.Kind.WEAPON
	slot_index = 0
	if selected == null:
		return
	var frame := _frame(selected)
	if frame != null and frame.weapon_slots == 0:
		slot_kind = ItemDefinition.Kind.MODULE
		return
	# An empty slot that falls back to a built-in (the Reclaimer's welder) is
	# not a gap to point at first.
	var gap := selected.weapon_ids.has(&"") and not (frame != null and frame.weapon_replaces_built_in)
	if gap or selected.weapon_ids.is_empty():
		return
	for kind in [ItemDefinition.Kind.EQUIPMENT, ItemDefinition.Kind.MODULE]:
		var slots: Array = _slots(selected, kind)
		var empty := slots.find(&"")
		if empty >= 0:
			slot_kind = kind
			slot_index = empty
			return


# ─────────────────────────────────────────────
# ROSTER — the seats, the teams, the bench
# ─────────────────────────────────────────────
func _build_head() -> void:
	var state: CampaignState = ui.state
	if ui.in_field():
		_head.add_child(Kit.text_block(
			"IN THE FIELD: TEAM MOVES TAKE EFFECT NOW, EVERYTHING ELSE FROM THE NEXT DEPLOY", Kit.DIM, Kit.SMALL))

	# Who the next operation actually takes, when it caps the squad.
	_op = ui.next_op()
	_capped = _op != null and _op.squad_size >= 0
	_going = ui.campaign.squad_for(_op) if _capped else []

	var head := Kit.hbox(10)
	head.add_child(Kit.heading("DEPLOYING"))
	head.add_child(Kit.seats(state.supply_used(), state.supply_cap))
	head.add_child(Kit.label("%d / %d SEATS" % [state.supply_used(), state.supply_cap], Kit.DIM, Kit.SMALL))
	if _capped:
		head.add_child(Kit.fill())
		head.add_child(Kit.label("NEXT OP: %s" % (_op.squad_label() if _op.squad_label() != "" else "WHOLE SQUAD"),
			Kit.BRIGHT, Kit.SMALL, true))
	_head.add_child(head)


func _build_teams() -> void:
	var state: CampaignState = ui.state
	# You are in no team: you order all of them.
	var you := _grid()
	you.add_child(_card(state.player_record))
	_teams.add_child(you)
	for id in state.team_ids():
		_teams.add_child(_team_section(id))
	if state.teams.size() < CampaignState.MAX_TEAMS:
		_teams.add_child(_new_team_strip())


# A team: its name and how many are in it, and under that their cards. The
# whole of it takes a dropped card, folded or open.
func _team_section(id: StringName) -> Control:
	var state: CampaignState = ui.state
	var where := {"kind": &"team", "id": id}
	var section := PanelContainer.new()
	_drop_target(section, where)
	var col := Kit.vbox(8)
	section.add_child(col)

	var going := state.members_of(id, false)
	var resting := state.members_of(id).size() - going.size()
	var open: bool = not _folded.get(id, false)
	# The header folds and opens the team, except the name, which is for
	# renaming it. A dropped card lands in the team wherever it lets go.
	var head := Kit.hbox(8)
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	head.tooltip_text = "Fold this team away" if open else "Show this team"
	head.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			head.accept_event()
			_folded[id] = open
			ui.play(&"select")
			rebuild())
	head.set_drag_forwarding(Callable(), _can_drop_fn(where), _drop_fn(where))
	head.add_child(Kit.caret(open))
	head.add_child(_team_name_edit(id, where))
	var count := "%d ROBOT%s" % [going.size(), "" if going.size() == 1 else "S"]
	if resting > 0:
		count += " · %d BENCHED" % resting
	head.add_child(Kit.label(count, Kit.DIM, Kit.SMALL))
	head.add_child(Kit.fill())
	col.add_child(head)

	if open:
		if going.is_empty():
			col.add_child(Kit.label("EVERYONE IN THIS TEAM IS ON THE BENCH", Kit.DIM, Kit.SMALL))
		else:
			var grid := _grid()
			for r in going:
				grid.add_child(_card(r, where))
			col.add_child(grid)
	return section


func _team_name_edit(id: StringName, where: Dictionary) -> LineEdit:
	var state: CampaignState = ui.state
	var edit := LineEdit.new()
	edit.text = state.team_name(id)
	edit.flat = true
	edit.max_length = CampaignState.TEAM_NAME_MAX
	edit.select_all_on_focus = true
	edit.add_theme_font_override("font", Kit.FONT_BOLD)
	edit.add_theme_font_size_override("font_size", 20)
	edit.add_theme_color_override("font_color", Kit.BRIGHT)
	# As wide as its name, so the count sits right after it.
	edit.custom_minimum_size = Vector2(40, 0)
	edit.expand_to_text_length = true
	edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	edit.tooltip_text = "Rename this team"
	var commit := func(text: String):
		if text.strip_edges().to_upper() == state.team_name(id):
			return   # unchanged
		if state.rename_team(id, text):
			ui.play(&"select")
		elif is_instance_valid(edit):
			# Blank: a team has to be called something in the field.
			edit.text = state.team_name(id)
			ui.play(&"denied")
	edit.text_submitted.connect(commit)
	edit.focus_exited.connect(func():
		if is_instance_valid(edit) and not ui.is_rebuilding():
			commit.call(edit.text))
	# A card let go over the name still lands in the team.
	edit.set_drag_forwarding(Callable(), _can_drop_fn(where), _drop_fn(where))
	return edit


# Under the teams: where a robot goes to start a team of its own. Only while
# there is room for another.
func _new_team_strip() -> Control:
	var strip := PanelContainer.new()
	_drop_target(strip, {"kind": &"new"})
	strip.custom_minimum_size = Vector2(0, 44)
	var l := Kit.label("DRAG A ROBOT HERE TO START A NEW TEAM", Kit.DIM, Kit.SMALL)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(l)
	return strip


func _build_bench() -> void:
	var state: CampaignState = ui.state
	_bench_head.add_child(Kit.heading("BENCH"))
	_bench_head.add_child(Kit.label("TAKES NO SEATS", Kit.DIM, Kit.SMALL))
	var resting: Array[SoldierRecord] = []
	for r in state.roster:
		if r.benched:
			resting.append(r)
	if resting.is_empty():
		_bench_scroll.custom_minimum_size = Vector2(0, 22)
		_bench.add_child(Kit.label("NOBODY ON THE BENCH. DRAG A ROBOT HERE TO LEAVE IT AT BASE", Kit.DIM, Kit.SMALL))
		return
	var grid := _grid()
	for r in resting:
		grid.add_child(_card(r, {"kind": &"bench"}))
	_bench.add_child(grid)
	# As tall as what is on it, up to two rows of cards: past that it scrolls,
	# and the teams above keep the rest of the page. Measured, not guessed —
	# a card is as tall as what is on it too.
	var rows := ceili(resting.size() / 2.0)
	var tall := grid.get_combined_minimum_size().y
	var gap := float(grid.get_theme_constant("v_separation"))
	_bench_scroll.custom_minimum_size = Vector2(0, tall if rows <= 2 else (tall + gap) * 2.0 / rows - gap)


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


func _scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s


# A robot's card. `where` is the team or the bench it sits in: a card let go
# over another card lands wherever that one is.
func _card(record: SoldierRecord, where: Dictionary = {}) -> Control:
	var state: CampaignState = ui.state
	var frame := _frame(record)
	var status := _status(record)
	var destroyed := record.status == SoldierRecord.Status.DESTROYED
	var is_player := state.is_player_record(record)
	var card := PanelContainer.new()
	card.set_meta(&"record", record)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 76)
	card.tooltip_text = _frame_line(record) if is_player \
		else "%s\nDrag to another team, or to the bench." % _frame_line(record)
	_style_card(card, false)
	card.mouse_entered.connect(func():
		_lit_card = card
		_style_card(card, true)
		ui.hover())
	card.mouse_exited.connect(func():
		if _lit_card == card:
			_lit_card = null
		_style_card(card, false))
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			card.accept_event()
			_pick(record))
	# You go wherever the squad goes: yours is the one card that does not move.
	if not is_player:
		card.set_drag_forwarding(func(_at: Vector2) -> Variant: return _drag(record, card),
			_can_drop_fn(where), _drop_fn(where))
	_cards.append(card)

	var row := Kit.hbox(10)
	card.add_child(row)
	var tint := Kit.PROBLEM if destroyed else Kit.BRIGHT
	# Under the icon, what the frame and its modules add up to: the number you
	# are actually comparing when you pick who goes.
	var mugshot := Kit.vbox(2)
	mugshot.add_child(Kit.icon(Icons.chassis(frame, "s"), tint, Vector2(40, 40)))
	var hp := Kit.label("%d HP" % record.max_health, Kit.DIM, 11)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mugshot.add_child(hp)
	row.add_child(mugshot)

	var mid := Kit.vbox(4)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	var top := Kit.hbox(6)
	top.add_child(Kit.label(record.display_name.to_upper(), Kit.PROBLEM if destroyed else Kit.BRIGHT, 18, true))
	top.add_child(Kit.chevrons(record.rank))
	mid.add_child(top)
	mid.add_child(_strip(record, frame))
	mid.add_child(Kit.label(status[0], status[1], Kit.SMALL, status[1] == Kit.PROBLEM))

	# Choosing who goes is one pass down the list, so the switch is on the card.
	# A wreck on the bench has nothing to deploy with until it is rebuilt.
	if not is_player and not (destroyed and record.benched):
		row.add_child(_bench_button(record, true))
	if record.benched:
		card.modulate = Color(1, 1, 1, 0.62)
	return card


# Selected: a bright, heavier border. Under the mouse: bright. A wreck keeps
# its red either way, so hovering one never reads as it being ready.
func _style_card(card: Control, lit: bool) -> void:
	var record: SoldierRecord = card.get_meta(&"record")
	var mine := record == selected
	var border := Kit.BRIGHT if mine else (Kit.PROBLEM if record.status == SoldierRecord.Status.DESTROYED else Kit.LINE)
	if lit and border != Kit.PROBLEM:
		border = Kit.BRIGHT
	card.add_theme_stylebox_override("panel", Kit.box(border, Kit.PANEL, 2 if mine else 1, 8.0))


# ─────────────────────────────────────────────
# DRAG AND DROP — the only way a robot changes team
# ─────────────────────────────────────────────
func _drag(record: SoldierRecord, card: Control) -> Variant:
	var ghost := PanelContainer.new()
	ghost.add_theme_stylebox_override("panel", Kit.box(Kit.BRIGHT, Kit.PANEL, 2, 8.0))
	var row := Kit.hbox(8)
	row.add_child(Kit.icon(Icons.chassis(_frame(record), "s"), Kit.BRIGHT, Vector2(28, 28), true))
	row.add_child(Kit.label(record.display_name.to_upper(), Kit.BRIGHT, 18, true))
	ghost.add_child(row)
	ghost.modulate.a = 0.85
	card.set_drag_preview(ghost)
	return {DRAG_KEY: record}


# The robot a drag is carrying, or null for anything else being dragged (a word
# out of a name field) or a robot no longer on the roster.
func _dragged(data: Variant) -> SoldierRecord:
	if not (data is Dictionary) or not (data as Dictionary).has(DRAG_KEY):
		return null
	var record = data[DRAG_KEY]
	return record if record is SoldierRecord and ui.state.roster.has(record) else null


# Whether letting go here would change anything that is allowed. A benched
# robot takes a seat to come off the bench, so without one no team takes it —
# and a wreck on the bench has to be rebuilt first, as with its DEPLOY button.
func _accepts(record: SoldierRecord, where: Dictionary) -> bool:
	var state: CampaignState = ui.state
	match where.get("kind", &""):
		&"bench":
			return not record.benched
		&"team":
			return state.can_field(record) if record.benched else record.team_id != where["id"]
		&"new":
			return state.teams.size() < CampaignState.MAX_TEAMS and (not record.benched or state.can_field(record))
	return false


func _can_drop_fn(where: Dictionary) -> Callable:
	return func(_at: Vector2, data: Variant) -> bool:
		var record := _dragged(data)
		var ok := record != null and _accepts(record, where)
		_light(_targets.get(_key(where)) if ok else null)
		return ok


func _drop_fn(where: Dictionary) -> Callable:
	return func(_at: Vector2, data: Variant) -> void:
		_light(null)
		var record := _dragged(data)
		if record == null or not _accepts(record, where):
			ui.play(&"denied")
			return
		var state: CampaignState = ui.state
		var done := false
		match where.get("kind", &""):
			&"bench":
				done = state.set_benched(record, true)
			&"team":
				done = state.move_to_team(record, where["id"])
			&"new":
				done = state.move_to_new_team(record)
		ui.play(&"fit" if done else &"denied")


# Registers something that takes a dropped card, and gives it the box it wears
# at rest and while a card is held over it.
func _drop_target(target: Control, where: Dictionary) -> void:
	target.set_drag_forwarding(Callable(), _can_drop_fn(where), _drop_fn(where))
	target.set_meta(&"where", where)
	_targets[_key(where)] = target
	_style_target(target, false)


func _style_target(target: Control, lit: bool) -> void:
	var kind: StringName = (target.get_meta(&"where", {}) as Dictionary).get("kind", &"")
	var rest_line := Kit.LINE if kind == &"team" else Kit.FAINT
	var fill := Color(0, 0, 0, 0.18) if kind == &"team" else Color(0, 0, 0, 0)
	var box := Kit.box(Kit.BRIGHT if lit else rest_line, Color(Kit.BRIGHT, 0.06) if lit else fill, 2 if lit else 1, 10.0)
	target.add_theme_stylebox_override("panel", box)


# Lights the target a held card would land in; null puts the last one out.
func _light(target: Control) -> void:
	if target == _hot:
		return
	if _hot != null and is_instance_valid(_hot):
		_style_target(_hot, false)
	_hot = target if target != null and is_instance_valid(target) else null
	if _hot != null:
		_style_target(_hot, true)


func _key(where: Dictionary) -> String:
	return "%s:%s" % [where.get("kind", &""), where.get("id", &"")]


# However a drag ends — dropped, let go over nothing, cancelled — nothing is
# left lit.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_light(null)



# One word for "can this robot do its job?"
func _status(record: SoldierRecord) -> Array:
	var state: CampaignState = ui.state
	if record.status == SoldierRecord.Status.DESTROYED:
		return ["DESTROYED", Kit.PROBLEM]
	if not _armed(record):
		return ["NO WEAPON", Kit.PROBLEM]
	if state.is_player_record(record):
		return ["ALWAYS GOES", Kit.DIM]
	if record.benched:
		return ["BENCHED", Kit.DIM]
	if _capped and not _going.has(record):
		return ["STAYS BEHIND: NEXT OP TAKES %d" % _op.squad_size, Kit.DIM]
	return ["READY", Kit.BRIGHT]


func _armed(record: SoldierRecord) -> bool:
	var frame := _frame(record)
	if frame != null and (frame.weapon_slots == 0 or frame.weapon_replaces_built_in):
		return true   # claws, a welder: built in, and the Reclaimer's until a mortar replaces it
	for id in record.weapon_ids:
		if id != &"":
			return true
	return false


# The card's gear as small icons, in slot order. Built-in things (the player's
# repair tool, a chaser's claws, a mechanic's welder) sit in the row too,
# marked as fixed.
# THE KIT ON A CARD IS A WAY IN, not a picture of one.
#
# These tiles show exactly what the detail panel edits, and they used to ignore
# the mouse entirely â so the route to "change this robot's grenade" was click
# the robot, then find the grenade again on the right. Clicking the tile does
# both: it selects the robot AND lands on that slot, whatever kind it is.
#
# Fixed tiles (a turret's built-in gun, your own repair tool) stay dead,
# because there is nothing on the other side of that click to change.
func _strip(record: SoldierRecord, frame: ChassisDefinition) -> Control:
	var row := Kit.hbox(3)
	if frame != null and frame.weapon_slots == 0:
		row.add_child(_mini(null, true, frame.built_in, true))
	# An empty slot a built-in stands in for shows the built-in, and is still a
	# way in: click it to put something in the built-in's place.
	var stand_in := frame.built_in if frame != null and frame.weapon_replaces_built_in else ""
	for i in record.weapon_ids.size():
		var id: StringName = record.weapon_ids[i]
		row.add_child(_mini(ui.item(id), true, stand_in, false, id == &"" and stand_in == "",
			record, ItemDefinition.Kind.WEAPON, i))
	if ui.state.is_player_record(record):
		row.add_child(_mini(ui.item(REPAIR_TOOL), true, "", true))
	for i in record.equipment_ids.size():
		row.add_child(_mini(ui.item(record.equipment_ids[i]), false, "", false, false,
			record, ItemDefinition.Kind.EQUIPMENT, i))
	for i in record.module_ids.size():
		row.add_child(_mini(ui.item(record.module_ids[i]), false, "", false, false,
			record, ItemDefinition.Kind.MODULE, i))
	return row


## Select `record` and land on one of its slots, from a click on a roster card.
func open_at(record: SoldierRecord, kind: int, index: int) -> void:
	if record == null:
		return
	if selected != record:
		_select(record, false)
	slot_kind = kind
	slot_index = maxi(index, 0)
	ui.play(&"select")
	rebuild()


func _mini(item: ItemDefinition, wide: bool, text: String = "", fixed: bool = false,
		missing: bool = false, record: SoldierRecord = null, kind: int = -1, index: int = -1) -> Control:
	var tile := PanelContainer.new()
	var border := Kit.PROBLEM if missing else (Kit.LINE if item != null or text != "" else Kit.FAINT)
	tile.add_theme_stylebox_override("panel", Kit.box(border, Color(0, 0, 0, 0.25), 1, 1.0))
	tile.custom_minimum_size = Vector2(46 if wide else 22, 21)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if record != null and kind >= 0 and not fixed:
		tile.mouse_filter = Control.MOUSE_FILTER_STOP
		tile.tooltip_text = "EDIT THIS SLOT"
		tile.mouse_entered.connect(ui.hover)
		tile.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				accept_event()
				open_at(record, kind, index))
	var tint := Kit.DIM if fixed else Kit.BRIGHT
	if item != null:
		var tex := Icons.item(item, "s")
		if tex != null:
			tile.add_child(Kit.icon(tex, tint, Vector2(40, 15) if wide else Vector2(16, 16)))
		else:
			tile.add_child(Kit.label(item.short_label().left(4), tint, 11))
	elif text != "":
		var l := Kit.label(text, Kit.DIM, 11)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.add_child(l)
	return tile


func _bench_button(record: SoldierRecord, compact: bool) -> Button:
	var state: CampaignState = ui.state
	var b: Button
	if not record.benched:
		b = Kit.button("BENCH" if compact else "SEND TO BENCH", Kit.DIM, Kit.SMALL)
		b.tooltip_text = "Leave %s at base when the squad deploys." % record.display_name
	elif state.supply_of(record) > state.supply_free():
		var need := state.supply_of(record)
		if need > 1:
			# A rover takes two, so one free seat is still "no".
			b = Kit.button(("%d SEATS" if compact else "NEEDS %d SEATS") % need, Kit.PROBLEM, Kit.SMALL)
			b.tooltip_text = "%s takes %d seats and %d are free. Bench someone, or add a seat at the Factory." % [
				record.display_name, need, state.supply_free()]
		else:
			b = Kit.button("NO SEAT" if compact else "NO FREE SEAT", Kit.PROBLEM, Kit.SMALL)
			b.tooltip_text = "Every seat is taken. Bench someone, or add a seat at the Factory."
	else:
		b = Kit.button("DEPLOY", Kit.BRIGHT, Kit.SMALL)
		b.tooltip_text = "Bring %s back into %s." % [record.display_name, state.team_name(state.team_of(record))]
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_entered.connect(ui.hover)
	b.pressed.connect(func():
		ui.play(&"select" if state.set_benched(record, not record.benched) else &"denied"))
	return b


# ─────────────────────────────────────────────
# DETAIL — the selected robot's slots, and what fits them
# ─────────────────────────────────────────────
func _build_detail() -> void:
	var state: CampaignState = ui.state
	var r := selected
	var frame := _frame(r)
	var is_player := state.is_player_record(r)
	var destroyed := r.status == SoldierRecord.Status.DESTROYED

	var head := Kit.hbox(12)
	head.add_child(Kit.icon(Icons.chassis(frame, "m"), Kit.PROBLEM if destroyed else Kit.BRIGHT, Vector2(64, 64)))
	var who := Kit.vbox(2)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	var name_edit := LineEdit.new()
	name_edit.text = r.display_name
	name_edit.flat = true
	name_edit.max_length = 14
	name_edit.placeholder_text = "UNNAMED"
	name_edit.add_theme_font_override("font", Kit.FONT_BOLD)
	name_edit.add_theme_font_size_override("font_size", 24)
	name_edit.add_theme_color_override("font_color", Kit.BRIGHT)
	name_edit.tooltip_text = "Rename"
	var record := r
	var commit := func(text: String):
		var cleaned := text.strip_edges()
		if cleaned != "" and cleaned != record.display_name:
			state.rename_soldier(record, cleaned, get_tree())
			ui.play(&"select")
	name_edit.text_submitted.connect(commit)
	name_edit.focus_exited.connect(func():
		if is_instance_valid(name_edit) and not ui.is_rebuilding():
			commit.call(name_edit.text))
	# The frame's health beside the name: the one number a refit changes that
	# the slot tiles below do not show.
	var name_row := Kit.hbox(10)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)
	name_row.add_child(Kit.label("%d HP" % r.max_health, Kit.DIM, 18, true))
	who.add_child(name_row)
	var rank_row := Kit.hbox(6)
	rank_row.add_child(Kit.label(_frame_line(r), Kit.DIM, Kit.SMALL))
	if not is_player:
		rank_row.add_child(Kit.chevrons(r.rank))
	who.add_child(rank_row)
	# Revives only appear once there are some. A repair tool that has never been
	# used would otherwise put "0 REVIVES" on every rifleman in the squad, which
	# is a line of noise on the frames that can't do it in the first place.
	var history := "%d KILLS · %d OPS" % [r.confirmed_kills, r.missions_survived]
	if r.revives > 0:
		history += " · %d REVIVES" % r.revives
	who.add_child(Kit.label(history, Kit.DIM, Kit.SMALL))
	_detail.add_child(head)

	if destroyed:
		var row := Kit.hbox(10)
		row.add_child(Kit.label("DESTROYED", Kit.PROBLEM, Kit.HEADING, true))
		row.add_child(Kit.fill())
		var cost := state.repair_cost(r)
		var rebuild_btn := Kit.button("REBUILD", Kit.BRIGHT if state.can_afford(cost) else Kit.PROBLEM)
		rebuild_btn.disabled = not state.can_afford(cost)
		rebuild_btn.tooltip_text = "Rebuild %s at full health." % r.display_name
		rebuild_btn.mouse_entered.connect(ui.hover)
		rebuild_btn.pressed.connect(func():
			ui.play(&"fit" if state.repair_soldier(record) else &"denied"))
		row.add_child(rebuild_btn)
		row.add_child(Kit.label(str(cost), Kit.MONEY, Kit.HEADING, true))
		_detail.add_child(row)
	elif not is_player:
		var row := Kit.hbox(10)
		row.add_child(_bench_button(r, false))
		if r.benched:
			row.add_child(Kit.label("STAYS AT BASE · EARNS NO XP", Kit.DIM, Kit.SMALL))
		_detail.add_child(row)

	# The weapon (and the player's built-in repair tool) on one row, gear and
	# modules side by side on the next: stacked, they left the stores list
	# below room for barely one row.
	var weapon_row := Kit.hbox(12)
	if frame != null and frame.weapon_slots == 0:
		weapon_row.add_child(_group("WEAPON", [_fixed_tile(null, frame.built_in)]))
	else:
		# Named for what it takes, so a rifle refused by a rover reads as a rule.
		var slot_name := "WEAPON"
		if frame != null and frame.turret:
			slot_name = "TURRET"
		elif frame != null and frame.weapon_replaces_built_in:
			slot_name = "TOOL"   # the Reclaimer's boom: the welder, or a mortar in its place
		weapon_row.add_child(_group(slot_name, _tiles(ItemDefinition.Kind.WEAPON, r.weapon_ids)))
	if is_player and ui.item(REPAIR_TOOL) != null:
		weapon_row.add_child(_group("BUILT IN · KEY 3", [_fixed_tile(ui.item(REPAIR_TOOL), "")]))
	_detail.add_child(weapon_row)
	var kit_row := Kit.hbox(18)
	if not r.equipment_ids.is_empty():
		kit_row.add_child(_group("GEAR", _tiles(ItemDefinition.Kind.EQUIPMENT, r.equipment_ids)))
	if not r.module_ids.is_empty():
		kit_row.add_child(_group("MODULES", _tiles(ItemDefinition.Kind.MODULE, r.module_ids)))
	_detail.add_child(kit_row)

	_detail.add_child(Kit.spacer(0, 2))
	_stores()


func _group(title: String, tiles: Array) -> Control:
	var col := Kit.vbox(4)
	col.add_child(Kit.heading(title))
	var row := Kit.hbox(6)
	for t in tiles:
		row.add_child(t)
	col.add_child(row)
	return col


func _tiles(kind: int, ids: Array) -> Array:
	var out: Array = []
	for i in ids.size():
		out.append(_slot_tile(kind, i, ids[i]))
	return out


# Something that is part of the body, not a slot: shown, never swapped.
func _fixed_tile(item: ItemDefinition, text: String) -> Control:
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", Kit.box(Kit.FAINT, Color(0, 0, 0, 0.2), 1, 4.0))
	tile.custom_minimum_size = Vector2(120, 56)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := Kit.vbox(2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(col)
	if item != null:
		col.add_child(Kit.icon(Icons.item(item, "m"), Kit.DIM, Vector2(96, 36)))
		text = item.short_label().to_upper()
	var l := Kit.label(text, Kit.DIM, 11)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	return tile


# A slot you can click: its item's icon and short name, or empty. Selected,
# its border is bright and the stores list below is for it.
func _slot_tile(kind: int, index: int, item_id: StringName) -> Control:
	var item: ItemDefinition = ui.item(item_id)
	var wide := kind == ItemDefinition.Kind.WEAPON
	var is_sel := kind == slot_kind and index == slot_index
	var missing := wide and item == null and not _armed(selected)
	var border := Kit.BRIGHT if is_sel else (Kit.PROBLEM if missing else (Kit.LINE if item != null else Kit.FAINT))
	var pick := func():
		slot_kind = kind
		slot_index = index
		ui.play(&"select")
		_rebuild_detail()
	var tile := Kit.card(border, pick, ui.hover, 4.0)
	tile.custom_minimum_size = Vector2(120, 56) if wide else Vector2(56, 56)
	# Right-click takes it off: the commonest thing to do to a full slot.
	tile.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT \
				and item_id != &"":
			tile.accept_event()
			_take_off(kind, index))
	var col := Kit.vbox(2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(col)
	if item != null:
		col.add_child(Kit.icon(Icons.item(item, "m"), Kit.BRIGHT, Vector2(96, 36) if wide else Vector2(36, 36)))
		var l := Kit.label(item.short_label().to_upper(), Kit.DIM, 11)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.clip_text = true
		col.add_child(l)
		tile.tooltip_text = "%s\n%s\nRight-click to take it off." % [item.display_name, item.effect_summary()]
	else:
		var frame := _frame(selected)
		var stand_in := frame.built_in if wide and frame != null and frame.weapon_replaces_built_in else ""
		var l := Kit.label(stand_in if stand_in != "" else "EMPTY", Kit.PROBLEM if missing else Kit.DIM, 12)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		tile.tooltip_text = "Empty. Pick something from stores below." if stand_in == "" \
			else "The %s, built in. Anything fitted here takes its place." % stand_in.to_lower()
	return tile


# What is in stores for the selected slot. Fits on a click; what cannot go on
# this robot is listed dim with the reason, so a rifle in stores never looks
# lost.
func _stores() -> void:
	var state: CampaignState = ui.state
	var r := selected
	var slots: Array = _slots(r, slot_kind)
	_detail.add_child(Kit.heading("IN STORES · %s" % Kit.KIND_NAMES.get(slot_kind, "")))
	if slot_index >= slots.size():
		_detail.add_child(Kit.label("NO SLOT FOR THIS ON THIS FRAME", Kit.DIM, Kit.SMALL))
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail.add_child(scroll)
	var list := Kit.vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var current: StringName = slots[slot_index]
	if current != &"":
		var on: ItemDefinition = ui.item(current)
		var off := Kit.card(Kit.LINE, func(): _take_off(slot_kind, slot_index), ui.hover, 6.0)
		var row := Kit.hbox(10)
		row.add_child(Kit.label("TAKE OFF", Kit.BRIGHT, Kit.BODY, true))
		row.add_child(Kit.label(on.display_name.to_upper() if on != null else "?", Kit.DIM, Kit.BODY))
		row.add_child(Kit.fill())
		row.add_child(Kit.label("BACK TO STORES", Kit.DIM, Kit.SMALL))
		off.add_child(row)
		list.add_child(off)

	var offered := 0
	for item in ui.shop_items():
		if item.kind != slot_kind or state.armoury.spare(item.id) <= 0:
			continue
		var reason := _cannot_fit(r, item)
		list.add_child(_store_row(item, reason))
		offered += 1
	if offered == 0:
		list.add_child(Kit.label("NOTHING IN STORES FOR THIS SLOT", Kit.DIM, Kit.SMALL))
	# THE WAY TO THE SHOP IS ALWAYS THERE. It used to appear only when stores
	# were empty for this slot, which is exactly backwards: having one spare
	# rifle is the moment you are most likely to want a second, and the button
	# vanished the instant you owned anything at all.
	var go := Kit.button("BUY AT THE ARMORER", Kit.BRIGHT, Kit.SMALL)
	go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	go.mouse_entered.connect(ui.hover)
	var kind := slot_kind
	go.pressed.connect(func(): ui.show_tab(&"armorer", {"kind": kind}))
	list.add_child(go)


func _store_row(item: ItemDefinition, reason: String) -> Control:
	var state: CampaignState = ui.state
	var wide := item.kind == ItemDefinition.Kind.WEAPON
	var usable := reason == ""
	var fit := func():
		if not usable:
			ui.play(&"denied")
			return
		ui.play(&"fit" if state.fit_item(selected, item, slot_index) else &"denied")
	var row_box := Kit.card(Kit.LINE, fit, ui.hover, 6.0)
	var row := Kit.hbox(10)
	row_box.add_child(row)
	var tint := Kit.BRIGHT if usable else Kit.DIM
	row.add_child(Kit.icon(Icons.item(item, "m"), tint, Vector2(96, 36) if wide else Vector2(36, 36)))
	var words := Kit.vbox(1)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(Kit.label(item.display_name.to_upper(), tint, Kit.BODY, true))
	var sub := Kit.effect_text(item) if usable else reason.to_upper()
	if sub != "":
		words.add_child(Kit.label(sub, Kit.DIM if usable else Kit.PROBLEM, 12))
	row.add_child(words)
	row.add_child(Kit.label("X%d" % state.armoury.spare(item.id), tint, Kit.BODY, true))
	row_box.tooltip_text = "Fit to %s" % selected.display_name if usable else reason
	if not usable:
		row_box.modulate = Color(1, 1, 1, 0.7)
	return row_box


# Why an item in stores cannot go on this robot, in words; "" if it can.
func _cannot_fit(record: SoldierRecord, item: ItemDefinition) -> String:
	var state: CampaignState = ui.state
	if not state.is_player_record(record) and record.rank < item.required_rank:
		return "needs rank %d" % item.required_rank
	if state.is_player_record(record) and not item.fits_player():
		return "squadmates only"
	if not state.is_player_record(record) and not item.fits_ai():
		return "you only"
	if not item.fits_chassis(record.chassis_id):
		return "not on this frame"
	if item.one_per_robot and state.holds_elsewhere(record, item, slot_index):
		return "one per robot"
	var frame := _frame(record)
	if frame != null and not frame.takes(item):
		# Two rules end up here, and they are not the same refusal: a turret
		# takes weapons made for it, and a frame that drives has no use for kit
		# written for legs (nanites). Say which one stopped it.
		if frame.drives and not item.fits_vehicles:
			return "not on this frame"
		return "turret weapons only"
	return ""


func _take_off(kind: int, index: int) -> void:
	if selected == null:
		return
	ui.play(&"remove" if ui.state.unfit_item(selected, kind, index) else &"denied")


func _slots(record: SoldierRecord, kind: int) -> Array:
	match kind:
		ItemDefinition.Kind.WEAPON:
			return record.weapon_ids
		ItemDefinition.Kind.EQUIPMENT:
			return record.equipment_ids
		ItemDefinition.Kind.MODULE:
			return record.module_ids
	return []


func _frame(record: SoldierRecord) -> ChassisDefinition:
	return ui.frame_of(record)


# "SOLDIER · REGULAR"
func _frame_line(record: SoldierRecord) -> String:
	# You have no rank: you spend the resources and compute, you don't earn XP.
	if ui.state.is_player_record(record):
		return "%s FRAME · YOU" % Kit.frame_word(_frame(record))
	return "%s · %s" % [Kit.frame_word(_frame(record)), record.rank_title().to_upper()]
