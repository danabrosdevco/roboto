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
var slot_kind: int = ItemDefinition.Kind.WEAPON
var slot_index: int = 0

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
	var stands_in: bool = frame != null and frame.weapon_replaces_built_in
	var gap: int = -1 if stands_in else selected.weapon_ids.find(&"")
	if gap >= 0:
		# POINT AT THE GAP, NOT AT SLOT ONE. A two-mount frame is bought with its
		# coax empty and its main gun already fitted, so opening on the first slot
		# would land on the gun it came with and hide the only decision there is.
		slot_index = gap
		return
	if selected.weapon_ids.is_empty():
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
		var scrap_btn := Kit.button("SCRAP", Kit.BRIGHT)
		scrap_btn.disabled = not state.can_scrap(r)
		scrap_btn.tooltip_text = \
			"Break %s for parts: a third of the frame and half of everything fitted to it, %d in all. The kit does not come back." \
			% [r.display_name, back]
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
			var rebuild_btn := Kit.button("REBUILD", Kit.BRIGHT if state.can_afford(cost) else Kit.PROBLEM)
			rebuild_btn.disabled = not state.can_afford(cost)
			rebuild_btn.tooltip_text = "Rebuild %s at full health." % r.display_name
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

	# The spacer that used to sit here is gone. It separated the slot tiles from
	# the stores list, which the "IN STORES" heading already does, and seven
	# pixels of column was the difference between that list showing two rows and
	# three.
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
	tile.custom_minimum_size = Vector2(120, 44)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := Kit.vbox(2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(col)
	if item != null:
		col.add_child(Kit.icon(Icons.item(item, "m"), Kit.DIM, Vector2(80, 28)))
		text = item.short_label().to_upper()
	var l := Kit.label(text, Kit.DIM, 11)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	return tile


# A slot you can click: its item's icon and short name, or empty. Selected,
# its border is bright and the stores list below is for it.
func _slot_tile(kind: int, index: int, item_id: StringName) -> Control:
	var item: ItemDefinition = ui.item(item_id)
	# A WRECK'S SLOTS ARE WELDED SHUT. Its kit was destroyed with it and pays
	# out through SCRAP at half price — but only if the player cannot simply
	# right-click every module off first and keep the lot. Left open, the
	# scrap value was a tax on not knowing the trick.
	#
	# A fixed tile rather than a disabled one: same picture, no click target,
	# no hover, nothing to wonder about.
	if selected != null and selected.status == SoldierRecord.Status.DESTROYED:
		return _fixed_tile(item, "EMPTY" if item == null else "")
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
	# 44 tall rather than 56. Two rows of these sit between the stats and the
	# stores list, so twelve pixels off each is twenty-four back for the list —
	# and the tile still holds its icon and its name.
	tile.custom_minimum_size = Vector2(120, 44) if wide else Vector2(56, 44)
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
		col.add_child(Kit.icon(Icons.item(item, "m"), Kit.BRIGHT, Vector2(80, 28) if wide else Vector2(28, 28)))
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
	var elsewhere := 0
	for item in ui.shop_items():
		if item.kind != slot_kind or state.armoury.spare(item.id) <= 0:
			continue
		if _never_fits(r, item):
			elsewhere += 1
			continue
		var reason := _cannot_fit(r, item)
		list.add_child(_store_row(item, reason))
		offered += 1
	if offered == 0:
		list.add_child(Kit.label("NOTHING IN STORES FOR THIS SLOT", Kit.DIM, Kit.SMALL))
	if elsewhere > 0:
		# WHAT WAS HIDDEN, COUNTED. Silence here would make a gun you own look
		# lost, which is the exact thing the dim rows were there to prevent.
		list.add_child(Kit.label("%d MORE IN STORES, FOR OTHER FRAMES" % elsewhere,
			Kit.DIM, Kit.SMALL))
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
	# Matched to the slot tiles above, which is both consistent and the last
	# twenty pixels needed: at 36 the rows were 48 tall and the list showed two
	# and a half of them, which is the worst possible number for a list you pick
	# from — enough to look complete, not enough to be.
	row.add_child(Kit.icon(Icons.item(item, "m"), tint, Vector2(80, 28) if wide else Vector2(28, 28)))
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


## REFUSALS THAT CAN NEVER BECOME YESES ARE NOT LISTED AT ALL.
##
## A dim row with a reason is the right answer for something you could fit
## later: "needs rank 3" is a goal, and "one per robot" is a thing you have
## already done once. But a turret gun will never go on a soldier and a rifle
## will never go on a Rover, and listing those is a list of what this robot is
## NOT — which on a frame with three slots was most of what you scrolled past.
##
## The rows do not vanish without a word: _stores() counts them and says how
## many are in stores for other frames, so a gun you own never looks lost.
func _never_fits(record: SoldierRecord, item: ItemDefinition) -> bool:
	var state: CampaignState = ui.state
	# The player is a special case in the other direction: a squad-only item is
	# permanently not theirs.
	if state.is_player_record(record):
		return not item.fits_player()
	if not item.fits_ai():
		return true
	if not item.fits_chassis(record.chassis_id):
		return true
	var frame := _frame(record)
	# frame.takes() is the one place that knows a turret takes only what was made
	# for it, and that a frame which drives has no use for kit written for legs.
	return frame != null and not frame.takes(item)


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
