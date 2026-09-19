extends HBoxContainer

# ─────────────────────────────────────────────
# SQUAD — who goes, and what they carry.
#
# Every robot is a card: its frame, its name, its gear as icons, and one word
# that answers "is it ready?" — READY, NO WEAPON, DESTROYED. The DEPLOYING row
# has a seat for each point of supply; the BENCH takes none.
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

var ui   # the SquadManagerUI; untyped because it preloads this script
var selected: SoldierRecord
var slot_kind: int = ItemDefinition.Kind.WEAPON
var slot_index: int = 0

var _left: VBoxContainer
var _detail: VBoxContainer


func setup(owner_ui) -> void:
	ui = owner_ui
	add_theme_constant_override("separation", 22)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_left = Kit.vbox(8)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_left)

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
	Kit.clear(_left)
	_build_roster()
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
	if selected.weapon_ids.has(&"") or selected.weapon_ids.is_empty():
		return
	for kind in [ItemDefinition.Kind.EQUIPMENT, ItemDefinition.Kind.MODULE]:
		var slots: Array = _slots(selected, kind)
		var empty := slots.find(&"")
		if empty >= 0:
			slot_kind = kind
			slot_index = empty
			return


# ─────────────────────────────────────────────
# ROSTER — the cards
# ─────────────────────────────────────────────
func _build_roster() -> void:
	var state: CampaignState = ui.state

	# The squad's name: the page's title, and editable. It is what the spawner
	# puts on the squad, so renaming it renames it everywhere.
	var name_edit := LineEdit.new()
	name_edit.text = state.squad_name
	name_edit.flat = true
	name_edit.max_length = 16
	name_edit.placeholder_text = "NAMELESS"
	name_edit.add_theme_font_override("font", Kit.FONT_BOLD)
	name_edit.add_theme_font_size_override("font_size", 28)
	name_edit.add_theme_color_override("font_color", Kit.BRIGHT)
	name_edit.custom_minimum_size = Vector2(320, 0)
	name_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	name_edit.tooltip_text = "Rename the squad"
	name_edit.text_submitted.connect(func(text: String): ui.rename_squad(text))
	name_edit.focus_exited.connect(func():
		if is_instance_valid(name_edit) and not ui.is_rebuilding():
			ui.rename_squad(name_edit.text))
	_left.add_child(name_edit)

	if ui.in_field():
		_left.add_child(Kit.label("IN THE FIELD: CHANGES TAKE EFFECT FROM THE NEXT DEPLOY", Kit.DIM, Kit.SMALL))

	# Who the next operation actually takes, when it caps the squad.
	var op: MissionDefinition = ui.next_op()
	var going: Array = []
	var capped := op != null and op.squad_size >= 0
	if capped:
		going = ui.campaign.squad_for(op)

	var head := Kit.hbox(10)
	head.add_child(Kit.heading("DEPLOYING"))
	head.add_child(Kit.seats(state.supply_used(), state.supply_cap))
	head.add_child(Kit.label("%d / %d SEATS" % [state.supply_used(), state.supply_cap], Kit.DIM, Kit.SMALL))
	if capped:
		head.add_child(Kit.fill())
		head.add_child(Kit.label("NEXT OP: %s" % (op.squad_label() if op.squad_label() != "" else "WHOLE SQUAD"),
			Kit.BRIGHT, Kit.SMALL, true))
	_left.add_child(head)

	var active := _grid()
	active.add_child(_card(state.player_record, going, capped, op))
	for r in state.roster:
		if not r.benched:
			active.add_child(_card(r, going, capped, op))
	_left.add_child(active)

	_left.add_child(Kit.spacer(0, 6))
	var bench_head := Kit.hbox(10)
	bench_head.add_child(Kit.heading("BENCH"))
	bench_head.add_child(Kit.label("TAKES NO SEATS", Kit.DIM, Kit.SMALL))
	_left.add_child(bench_head)
	var benched := _grid()
	var any := false
	for r in state.roster:
		if r.benched:
			benched.add_child(_card(r, going, capped, op))
			any = true
	if any:
		_left.add_child(benched)
	else:
		_left.add_child(Kit.label("NOBODY ON THE BENCH", Kit.DIM, Kit.SMALL))


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


func _card(record: SoldierRecord, going: Array, capped: bool, op: MissionDefinition) -> Control:
	var state: CampaignState = ui.state
	var frame := _frame(record)
	var status := _status(record, going, capped, op)
	var destroyed := record.status == SoldierRecord.Status.DESTROYED
	var border := Kit.BRIGHT if record == selected else (Kit.PROBLEM if destroyed else Kit.LINE)
	var card := Kit.card(border, func(): _select(record), ui.hover)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 76)
	card.tooltip_text = _frame_line(record)

	var row := Kit.hbox(10)
	card.add_child(row)
	var tint := Kit.PROBLEM if destroyed else Kit.BRIGHT
	row.add_child(Kit.icon(Icons.chassis(frame, "s"), tint, Vector2(40, 40)))

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
	if not state.is_player_record(record) and not (destroyed and record.benched):
		row.add_child(_bench_button(record, true))
	if record.benched:
		card.modulate = Color(1, 1, 1, 0.62)
	return card


# One word for "can this robot do its job?"
func _status(record: SoldierRecord, going: Array, capped: bool, op: MissionDefinition) -> Array:
	var state: CampaignState = ui.state
	if record.status == SoldierRecord.Status.DESTROYED:
		return ["DESTROYED", Kit.PROBLEM]
	if not _armed(record):
		return ["NO WEAPON", Kit.PROBLEM]
	if state.is_player_record(record):
		return ["ALWAYS GOES", Kit.DIM]
	if record.benched:
		return ["BENCHED", Kit.DIM]
	if capped and not going.has(record):
		return ["STAYS BEHIND: NEXT OP TAKES %d" % op.squad_size, Kit.DIM]
	return ["READY", Kit.BRIGHT]


func _armed(record: SoldierRecord) -> bool:
	var frame := _frame(record)
	if frame != null and frame.weapon_slots == 0:
		return true   # claws
	for id in record.weapon_ids:
		if id != &"":
			return true
	return false


# The card's gear as small icons, in slot order. Built-in things (the player's
# repair tool, a chaser's claws) sit in the row too, marked as fixed.
func _strip(record: SoldierRecord, frame: ChassisDefinition) -> Control:
	var row := Kit.hbox(3)
	if frame != null and frame.weapon_slots == 0:
		row.add_child(_mini(null, true, "CLAWS", true))
	for id in record.weapon_ids:
		row.add_child(_mini(ui.item(id), true, "", false, id == &""))
	if ui.state.is_player_record(record):
		row.add_child(_mini(ui.item(REPAIR_TOOL), true, "", true))
	for id in record.equipment_ids:
		row.add_child(_mini(ui.item(id), false))
	for id in record.module_ids:
		row.add_child(_mini(ui.item(id), false))
	return row


func _mini(item: ItemDefinition, wide: bool, text: String = "", fixed: bool = false,
		missing: bool = false) -> Control:
	var tile := PanelContainer.new()
	var border := Kit.PROBLEM if missing else (Kit.LINE if item != null or text != "" else Kit.FAINT)
	tile.add_theme_stylebox_override("panel", Kit.box(border, Color(0, 0, 0, 0.25), 1, 1.0))
	tile.custom_minimum_size = Vector2(46 if wide else 22, 21)
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
		b.tooltip_text = "Bring %s back into the squad." % record.display_name
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
	who.add_child(name_edit)
	var rank_row := Kit.hbox(6)
	rank_row.add_child(Kit.label(_frame_line(r), Kit.DIM, Kit.SMALL))
	if not is_player:
		rank_row.add_child(Kit.chevrons(r.rank))
	who.add_child(rank_row)
	who.add_child(Kit.label("%d KILLS · %d OPS" % [r.confirmed_kills, r.missions_survived], Kit.DIM, Kit.SMALL))
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
		weapon_row.add_child(_group("WEAPON", [_fixed_tile(null, "CLAWS")]))
	else:
		# Named for what it takes, so a rifle refused by a rover reads as a rule.
		var slot_name := "TURRET" if frame != null and frame.turret else "WEAPON"
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
		var l := Kit.label("EMPTY", Kit.PROBLEM if missing else Kit.DIM, 12)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		tile.tooltip_text = "Empty. Pick something from stores below."
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
	var frame := _frame(record)
	if frame != null and not frame.takes(item):
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
