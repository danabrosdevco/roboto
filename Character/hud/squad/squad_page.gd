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
# Teams and bench share ONE scroll: the bench used to be pinned to the bottom,
# which cost a permanent slab of height to robots you had chosen to leave
# behind and hid the new ones under the fold.
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
## A frame's real speed lives on its SCENE. By path, not class_name — see the
## note in item_facts.gd.
const _Facts := preload("res://Campaign/item_facts.gd")
## Tops of the stat bars, FIXED so two robots can be compared by eye. Shared
## with the Factory's frame cards on purpose: the same stat should be the same
## length of bar wherever it is drawn.
const HULL_TOP := 400.0
const SPEED_TOP := 20.0
const SENSOR_TOP := 120.0
## What a dragged card carries: {DRAG_KEY: the robot's record}.
const DRAG_KEY := "squad_page_robot"

var ui   # the SquadManagerUI; untyped because it preloads this script
var selected: SoldierRecord

var _left: VBoxContainer
var _head: VBoxContainer
var _teams: VBoxContainer
var _bench_head: HBoxContainer
var _bench_panel: PanelContainer
var _bench: VBoxContainer
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
	# ONE SCROLL FOR THE WHOLE COLUMN, teams and bench together.
	#
	# The bench used to be pinned to the bottom with its own scroll, so it was
	# always on screen however long the teams ran. That sounds right and plays
	# wrong: the bench is usually one or two robots you have chosen to leave
	# behind, and it was holding ~150px of permanent height in front of the
	# thing you actually came to look at. Recruit your first Rover and it joins
	# ARMOR, ARMOR is the last team, and the new robot lands under the fold
	# behind a bench showing nobody you care about.
	#
	# The seats header above stays pinned — that is the number every move on
	# this page is spent against, and it is one line.
	_teams_scroll = _scroll()
	_left.add_child(_teams_scroll)
	var column := Kit.vbox(10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_teams_scroll.add_child(column)
	_teams = Kit.vbox(10)
	_teams.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_teams)
	_bench_head = Kit.hbox(10)
	column.add_child(_bench_head)
	_bench_panel = PanelContainer.new()
	_bench_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_drop_target(_bench_panel, {"kind": &"bench"})
	column.add_child(_bench_panel)
	# No inner scroll any more: the column's own scroll handles the overflow,
	# and a scroll inside a scroll eats the wheel wherever the pointer happens
	# to be sitting.
	_bench = Kit.vbox(8)
	_bench.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bench_panel.add_child(_bench)

	var side := PanelContainer.new()
	var line := StyleBoxFlat.new()
	line.bg_color = Color(0, 0, 0, 0)
	line.border_color = Kit.LINE
	line.border_width_left = 1
	line.content_margin_left = 20
	side.add_theme_stylebox_override("panel", line)
	side.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	add_child(side)
	# FIVE, NOT EIGHT. The detail column is exactly full at 544px: measured, its
	# children came to 448 and twelve eight-pixel gaps came to 96, which left the
	# stores list underneath 79 pixels — one and a half rows of a list you are
	# meant to choose from. Four pixels a gap is forty-eight back.
	_detail = Kit.vbox(4)
	side.add_child(_detail)


## Opening onto nobody selected costs a click every time; the player is who
## you most often came to change.
func on_open() -> void:
	if not _listed(selected):
		_select(ui.state.player_record, false)


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
	if announce:
		ui.play(&"select")
		rebuild()


# A click on a card selects it WHERE IT IS: the cards are re-lit and the panel
# on the right rebuilt, and the list is left standing. Rebuilding it freed the
# card under the mouse on the press, so the same press could never go on to
# become a drag.
func _pick(record: SoldierRecord) -> void:
	selected = record
	ui.play(&"select")
	for card in _cards:
		if is_instance_valid(card):
			_style_card(card, card == _lit_card)
	_rebuild_detail()


# The slot most worth looking at: the weapon if there is none, then the first
# empty gear or module slot, else the weapon.
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
	# You are IN a team — `members_of` puts your card in it — and `team_of`
	# picks one for you the first time, the same way it does for a robot. The
	# loose card above the teams is only for a campaign that somehow has none.
	var yours := state.team_of(state.player_record) if state.player_record != null else &""
	if not state.has_team(yours):
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
		_bench.add_child(Kit.label("NOBODY ON THE BENCH. DRAG A ROBOT HERE TO LEAVE IT AT BASE", Kit.DIM, Kit.SMALL))
		return
	var grid := _grid()
	for r in resting:
		grid.add_child(_card(r, {"kind": &"bench"}))
	_bench.add_child(grid)
	# As tall as what is on it, full stop. The two-row cap and the measured
	# height it needed went with the inner scroll: the bench is the last thing
	# in the column now, so a long one simply runs on and the column scrolls.


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
	card.tooltip_text = "%s\nDrag to another team." % _frame_line(record) if is_player \
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
	# You go wherever the squad goes — but you go WITH a team, so your card
	# moves between them like any other. The bench is what it cannot reach.
	card.set_drag_forwarding(func(_at: Vector2) -> Variant: return _drag(record, card),
		_can_drop_fn(where), _drop_fn(where))
	_cards.append(card)

	var row := Kit.hbox(10)
	card.add_child(row)
	var tint := Kit.PROBLEM if destroyed else Kit.BRIGHT
	# Under the icon, what the frame and its modules add up to: the number you
	# are actually comparing when you pick who goes.
	var mugshot := Kit.vbox(2)
	mugshot.add_child(Kit.icon(Icons.chassis(frame, "s", record.cosmetic_id), tint, Vector2(40, 40)))
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
	row.add_child(Kit.icon(Icons.chassis(_frame(record), "s", record.cosmetic_id), Kit.BRIGHT, Vector2(28, 28), true))
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
	if not (record is SoldierRecord):
		return null
	# You are draggable too — into a team, never onto the bench — and you are
	# not on the roster, so the roster test alone would drop your card.
	return record if ui.state.roster.has(record) or ui.state.is_player_record(record) else null


# Whether letting go here would change anything that is allowed. A benched
# robot takes a seat to come off the bench, so without one no team takes it —
# and a wreck on the bench has to be rebuilt first, as with its DEPLOY button.
func _accepts(record: SoldierRecord, where: Dictionary) -> bool:
	var state: CampaignState = ui.state
	match where.get("kind", &""):
		&"bench":
			return not record.benched and not state.is_player_record(record)   # you always go
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
		# NAMES THE ACTION, unlike the squad HUD's version of this state. In
		# the field a destroyed frame is inert and is drawn that way — there is
		# nothing to be done about it while you are out there. At base it is
		# the one thing on the card you CAN act on, so it says so.
		return ["DESTROYED · SCRAP IT", Kit.PROBLEM]
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
func _mini(item: ItemDefinition, wide: bool, text: String = "", fixed: bool = false,
		missing: bool = false, record: SoldierRecord = null, kind: int = -1, index: int = -1) -> Control:
	var tile := PanelContainer.new()
	var border := Kit.PROBLEM if missing else (Kit.LINE if item != null or text != "" else Kit.FAINT)
	tile.add_theme_stylebox_override("panel", Kit.box(border, Color(0, 0, 0, 0.25), 1, 1.0))
	tile.custom_minimum_size = Vector2(46 if wide else 22, 21)
	# ALWAYS IGNORE. These were clickable — "EDIT THIS SLOT" jumped the detail
	# pane to that slot so it could be refitted. There is no refitting a single
	# robot any more, so a tile that invited a click would be a control that
	# does nothing, which is worse than one that was never offered.
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	# 48, not 64. The name, the frame line and the history sit beside it and are
	# what the block is actually for; the portrait is identification, and it only
	# has to be big enough to tell a Walker from a soldier at a glance.
	head.add_child(Kit.icon(Icons.chassis(frame, "m", r.cosmetic_id), Kit.PROBLEM if destroyed else Kit.BRIGHT, Vector2(48, 48)))
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
	# Health used to sit beside the name as the one number a refit changed that
	# the slot tiles did not show. It is in the STATS block now, with the four
	# others a refit changes and with the part the modules bought drawn in white —
	# which is the thing a lone "75 HP" could never say.
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(name_edit)
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
		# A DESTROYED FRAME IS NOT A REPAIR JOB. The only decision left is what
		# you get for the metal, so SCRAP is the button — REBUILD only appears
		# when the campaign has been told to allow it (CampaignState.
		# allow_rebuild), because offering both makes the distinction the squad
		# HUD now draws between DOWNED and DESTROYED meaningless.
		var row := Kit.hbox(10)
		row.add_child(Kit.label("DESTROYED", Kit.DIM, Kit.HEADING, true))
		row.add_child(Kit.fill())

		var back := state.scrap_value(r)
		# Scrapping and rebuilding are both refused in the field (Backlog K12),
		# so they say so rather than looking available and playing "denied".
		var afield: bool = ui.in_field()
		var can_scrap: bool = state.can_scrap(r)
		var scrap_btn := Kit.button("SCRAP", Kit.spend_colour(can_scrap, afield, Kit.BRIGHT))
		# WHAT IT ACTUALLY PAYS, not what the rule says it pays. This read "a
		# third of the frame and half of everything fitted to it" against a kit
		# payout that is always 0 in the shipped game — nothing has bought an
		# item since the shops went, and only a bought item has an allocation
		# to refund. See CampaignState.scrap_kit_value(). Backlog S8.
		var kit_back: int = state.scrap_kit_value(r)
		var scrap_tip := "Break %s for parts: a third of the frame, %d. Nothing it carries pays — issued kit is already inside the frame's price. The kit does not come back." \
			% [r.display_name, back]
		if kit_back > 0:
			scrap_tip = "Break %s for parts: a third of the frame and half of what was bought for it, %d in all. The kit does not come back." \
				% [r.display_name, back]
		Kit.gate_spend(scrap_btn, can_scrap, afield, scrap_tip)
		scrap_btn.mouse_entered.connect(ui.hover)
		scrap_btn.pressed.connect(func():
			# -1 is a refusal, 0 is a worthless wreck scrapped successfully.
			ui.play(&"denied" if state.scrap_soldier(record) < 0 else &"fit"))
		row.add_child(scrap_btn)
		row.add_child(Kit.label("+%d" % back, Kit.MONEY, Kit.HEADING, true))
		_detail.add_child(row)

		if state.allow_rebuild:
			var rebuild_row := Kit.hbox(10)
			rebuild_row.add_child(Kit.fill())
			var cost := state.repair_cost(r)
			var can_rebuild: bool = state.can_afford(cost)
			var rebuild_btn := Kit.button("REBUILD",
				Kit.spend_colour(can_rebuild, afield, Kit.BRIGHT))
			Kit.gate_spend(rebuild_btn, can_rebuild, afield,
				"Rebuild %s at full health." % r.display_name)
			rebuild_btn.mouse_entered.connect(ui.hover)
			rebuild_btn.pressed.connect(func():
				ui.play(&"fit" if state.repair_soldier(record) else &"denied"))
			rebuild_row.add_child(rebuild_btn)
			rebuild_row.add_child(Kit.label(str(cost), Kit.MONEY, Kit.HEADING, true))
			_detail.add_child(rebuild_row)
	elif not is_player:
		var row := Kit.hbox(10)
		row.add_child(_bench_button(r, false))
		if r.benched:
			row.add_child(Kit.label("STAYS AT BASE · EARNS NO XP", Kit.DIM, Kit.SMALL))
		_detail.add_child(row)
		_cosmetic_row(r)
		_pauldron_row(r)

	_stat_block(r, frame)

	# The weapon (and the player's built-in repair tool) on one row, gear and
	# modules side by side on the next: stacked, they left the stores list
	# below room for barely one row.
	var weapon_row := Kit.hbox(12)
	if frame != null and frame.weapon_slots == 0:
		weapon_row.add_child(_group("WEAPON", [_fixed_tile(null, frame.built_in)]))
	else:
		# Named for what it takes, so a rifle refused by a rover reads as a rule.
		# THE SAME THREE WORDS THE ARMORER CARD USES. A weapon's card names its
		# mount class — TURRET, INFANTRY, ARTICULATED ARM (see Kit.mount_class)
		# — and the slot it drops into has to be called the same thing, or the
		# player is matching two vocabularies for one idea.
		#
		# This said "TOOL", which named the Reclaimer's boom by what happens to
		# be on it rather than by what it is. An arm is a mount: the welder is
		# what it holds today and a mortar is what it holds instead, and nothing
		# stops a later frame having one.
		var slot_name := "WEAPON"
		if frame != null and frame.turret:
			slot_name = "TURRET"
		elif frame != null and frame.weapon_replaces_built_in:
			slot_name = "ARTICULATED ARM"
		weapon_row.add_child(_group(slot_name, _tiles(ItemDefinition.Kind.WEAPON, r.weapon_ids)))
	if is_player and ui.item(REPAIR_TOOL) != null:
		weapon_row.add_child(_group("BUILT IN · KEY 3", [_fixed_tile(ui.item(REPAIR_TOOL), "")]))
	_detail.add_child(weapon_row)
	var kit_row := Kit.hbox(18)
	if not r.equipment_ids.is_empty():
		kit_row.add_child(_group("EQUIPMENT", _tiles(ItemDefinition.Kind.EQUIPMENT, r.equipment_ids)))
	if not r.module_ids.is_empty():
		kit_row.add_child(_group("MODULES", _tiles(ItemDefinition.Kind.MODULE, r.module_ids)))
	_detail.add_child(kit_row)

	# WHERE THE STORES LIST USED TO BE. A robot's kit comes from its production
	# line now, so there is nothing here to pick from — the line's spec is set
	# on the Factory page and reaches every robot on it at once. Saying so
	# beats an empty column where a list used to be.
	var frame_now := _frame(r)
	if frame_now != null and frame_now.purchasable:
		_detail.add_child(Kit.label("ISSUED BY THE %s LINE" % Kit.frame_word(frame_now).to_upper(),
			Kit.DIM, Kit.SMALL))


func _group(title: String, tiles: Array) -> Control:
	var col := Kit.vbox(4)
	col.add_child(Kit.heading(title))
	var row := Kit.hbox(6)
	for t in tiles:
		row.add_child(t)
	col.add_child(row)
	return col


## WHAT THIS ROBOT CARRIES, SHOWN AND NOT TOUCHED.
##
## These used to be the fitting UI: click a tile to select the slot, pick from
## the stores list below, right-click to take it off. All of that moved to the
## Factory when a loadout stopped belonging to a robot and started belonging to
## its production line — a Rover carries what the Rover line builds, and
## changing it one robot at a time is no longer a thing the game can express.
##
## The tiles stay because WHAT IT CARRIES is still the first thing you want to
## know about a robot you are looking at. They are just read-only now, which is
## what _fixed_tile has always drawn for a wreck.
func _tiles(kind: int, ids: Array) -> Array:
	var out: Array = []
	var wide: bool = kind == ItemDefinition.Kind.WEAPON
	# AN EMPTY MOUNT IS NOT ALWAYS AN EMPTY MOUNT. On a frame whose weapon
	# REPLACES a built-in — the Reclaimer's boom, the Drayman's — nothing
	# fitted means the built-in is on it, so the tile says WELDER rather than
	# EMPTY. Reading that slot as "unarmed" is the exact mistake the Reclaimer
	# card was changed to stop making.
	var frame := _frame(selected)
	var built_in: String = frame.built_in if frame != null \
		and frame.weapon_replaces_built_in and kind == ItemDefinition.Kind.WEAPON else ""
	for i in ids.size():
		var item: ItemDefinition = ui.item(ids[i]) if ids[i] != &"" else null
		var blank: String = built_in if built_in != "" else "EMPTY"
		out.append(_fixed_tile(item, "" if item != null else blank, wide))
	return out


# Something that is part of the body, not a slot: shown, never swapped.
# `wide` is the WEAPON width, and it has to match _slot_tile's: a wreck draws
# fixed tiles in place of clickable ones, and a fixed tile that is always the
# weapon width made every equipment and module slot on a destroyed robot more
# than twice as wide as the same slot on a live one.
#
# Four slots at 120 instead of 56 took the kit row from 254px to 510, which is
# over DETAIL_WIDTH (400) — and `side.custom_minimum_size` is a MINIMUM, so the
# whole detail column grew to fit and pushed its right-hand content off the
# screen. That is the "selecting a destroyed robot runs off the end" report:
# nothing to do with the DESTROYED label, everything to do with this default.
func _fixed_tile(item: ItemDefinition, text: String, wide: bool = true) -> Control:
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", Kit.box(Kit.FAINT, Color(0, 0, 0, 0.2), 1, 4.0))
	tile.custom_minimum_size = Vector2(120, 44) if wide else Vector2(56, 44)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := Kit.vbox(2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(col)
	if item != null:
		col.add_child(Kit.icon(Icons.item(item, "m"), Kit.DIM, Vector2(80, 28) if wide else Vector2(28, 28)))
		text = item.short_label().to_upper()
	var l := Kit.label(text, Kit.DIM, 11)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	return tile


# A slot you can click: its item's icon and short name, or empty. Selected,
# its border is bright and the stores list below is for it.
func _frame(record: SoldierRecord) -> ChassisDefinition:
	return ui.frame_of(record)


# "SOLDIER · REGULAR"
func _frame_line(record: SoldierRecord) -> String:
	# You have no rank: you spend the resources and compute, you don't earn XP.
	if ui.state.is_player_record(record):
		return "%s FRAME · YOU" % Kit.frame_word(_frame(record))
	return "%s · %s" % [Kit.frame_word(_frame(record)), record.rank_title().to_upper()]


## WHAT THIS ROBOT IS NOW, and how much of that you bought.
##
## The page used to show one number — max_health beside the name — and it was
## the FINISHED figure, so a Walker with armour plating read 335 and nothing
## said that 15 of it came out of a module slot. Everything else a module
## changed was invisible: a Sensor Relay adds thirty metres of sight and the
## page never mentioned sensors at all.
##
## Each bar is drawn twice over: the frame's own figure in BRIGHT, and the part
## the modules added continuing it in UPGRADE white. No attribution text — the
## module tiles are a few rows below, and a line reading "+15 ARMOUR PLATE" says
## in words what the white already says in place.
##
## Nothing was added to the data for this. recompute_stats() already folds every
## module into these fields and the base sits on the chassis, so the block is a
## reader.
func _stat_block(r: SoldierRecord, frame: ChassisDefinition) -> void:
	if frame == null:
		# EVERY EARLY RETURN WARNS. A record naming a frame the catalogue has
		# dropped has no base to compare against, so a block here would be
		# comparing its stats with nothing and drawing everything as a bonus.
		push_warning("SquadPage: '%s' has no chassis in the catalogue, so its stats block is skipped." % r.display_name)
		return
	_detail.add_child(Kit.heading("STATS"))
	_detail.add_child(Kit.stat_bar("HULL", frame.base_health, r.max_health, HULL_TOP,
		str(r.max_health)))
	# effective_speed is a MULTIPLIER — base_speed is 1.00 on every frame — so
	# the metres per second only exist on the chassis scene.
	var base_speed := _Facts.chassis_speed(frame)
	if base_speed > 0.0:
		var now := base_speed * r.effective_speed
		_detail.add_child(Kit.stat_bar("SPEED", base_speed, now, SPEED_TOP, "%.1f M/S" % now))
	_detail.add_child(Kit.stat_bar("SENSOR", frame.base_sensor_range, r.effective_sensor_range,
		SENSOR_TOP, "%d M" % int(round(r.effective_sensor_range))))
	_detail.add_child(Kit.stat_bar("ACCURACY", frame.base_accuracy * 100.0,
		r.effective_accuracy * 100.0, 100.0, "%d%%" % int(round(r.effective_accuracy * 100.0))))
	if r.effective_signal_resistance_bonus > 0.0:
		# Shown as the reduction you actually get, not the raw divisor: "+100%
		# RES" means nothing, "-50% JAM" means something.
		var cut: float = 1.0 - 1.0 / (1.0 + r.effective_signal_resistance_bonus)
		_detail.add_child(Kit.stat_bar("JAM RES", 0.0, cut * 100.0, 100.0,
			"-%d%%" % int(round(cut * 100.0))))

	# POSITIVES ONLY. A frame without suppressive fire says nothing about
	# suppressive fire: a row of NO THIS and NO THAT is a panel telling you what
	# a robot is not, which is the longest way to say nothing.
	var extras: Array[String] = []
	if r.effective_suppressive:
		extras.append("SUPPRESSIVE FIRE")
	if r.effective_self_revive > 0.0:
		extras.append("SELF-REVIVE %ds" % int(round(r.effective_self_revive)))
	if not extras.is_empty():
		_detail.add_child(Kit.label(" · ".join(extras), Kit.BRIGHT, Kit.SMALL, true))


## THE HAT. One button that cycles whatever this frame can wear, with the name
## of what it has on beside it.
##
## A cycle rather than a list because there are at most three per frame and the
## detail column is already dense — a dropdown would cost a row and a popup to
## say the same thing. The icon beside the name redraws with it, so the choice
## is visible from the card as well as from here.
##
## NOTHING IS SHOWN FOR A FRAME WITH NO KIT. Cosmetics.for_frame always returns
## NONE, so a size of one means there is genuinely nothing to pick and a control
## would be dead the moment it was drawn.
func _cosmetic_row(r: SoldierRecord) -> void:
	var options := Cosmetics.for_frame(r.chassis_id)
	if options.size() <= 1:
		return
	var state: CampaignState = ui.state
	var row := Kit.hbox(10)
	row.add_child(Kit.label("DRESS", Kit.DIM, Kit.SMALL))
	var button := Kit.button(Cosmetics.display_name(r.cosmetic_id), Kit.BRIGHT, Kit.SMALL)
	button.tooltip_text = "Headgear for %s. Appearance only — it changes no stat, and earns and costs nothing." % r.display_name
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_entered.connect(ui.hover)
	var record := r
	button.pressed.connect(func():
		var next := Cosmetics.next_for_frame(record.chassis_id, record.cosmetic_id)
		ui.play(&"fit" if state.set_cosmetic(record, next) else &"denied"))
	row.add_child(button)
	row.add_child(Kit.label("%d OF %d" % [maxi(options.find(r.cosmetic_id), 0) + 1, options.size()],
			Kit.DIM, Kit.SMALL))
	row.add_child(Kit.fill())
	_detail.add_child(row)


## PAULDRONS, as their own tick rather than another hat.
##
## They are not headgear and do not compete with it — a Captain wears both — so
## putting them in the DRESS cycle meant the only way to have both was a third
## combined entry, FULL DRESS, which said nothing the two separate things did
## not. The tick replaces it.
##
## Shown greyed below Captain rather than hidden, because a locked thing you can
## see is a reason to keep promoting and a thing you cannot see is not.
func _pauldron_row(r: SoldierRecord) -> void:
	if not Cosmetics.pauldrons_fit(r.chassis_id):
		return
	var state: CampaignState = ui.state
	var earned := r.rank >= Cosmetics.PAULDRONS_RANK
	var row := Kit.hbox(10)
	row.add_child(Kit.label("PAULDRONS", Kit.DIM, Kit.SMALL))
	var button := Kit.button("ON" if r.pauldrons else "OFF",
			Kit.BRIGHT if earned else Kit.DIM, Kit.SMALL)
	button.disabled = not earned
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.tooltip_text = ("Shoulder plates for %s. Appearance only." % r.display_name) \
			if earned else "Earned at %s." % SoldierRecord.rank_title_at(Cosmetics.PAULDRONS_RANK)
	button.mouse_entered.connect(ui.hover)
	var record := r
	button.pressed.connect(func():
		ui.play(&"fit" if state.set_pauldrons(record, not record.pauldrons) else &"denied"))
	row.add_child(button)
	if not earned:
		row.add_child(Kit.label("LOCKED · %s" % SoldierRecord.rank_title_at(Cosmetics.PAULDRONS_RANK).to_upper(),
				Kit.DIM, Kit.SMALL))
	row.add_child(Kit.fill())
	_detail.add_child(row)
