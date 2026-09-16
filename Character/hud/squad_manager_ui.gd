extends Control
class_name SquadManagerUI

# ─────────────────────────────────────────────
# SQUAD MANAGER — roster on the left, armoury on the right, drag between them.
#
# Built in code for the same reason the HUDs are: it self-wires, so there's no
# inspector slot to leave blank and no silent failure. Toggle with the
# `squad_manager` action, or call open()/close().
#
# EVERY MUTATION GOES THROUGH CampaignState. The panel never touches the armoury
# dictionary or a record's slot array directly — fit_item/unfit_item move an
# item between exactly two places in one call, so the pool and the slots cannot
# drift apart no matter what the UI does.
#
# NOT DONE YET, deliberately: the shop tab and the per-soldier upgrade detail.
# CampaignState.buy_item/buy_chassis/sell_item exist and work; they just have no
# screen. Wanted the drag-drop core proven before stacking more on it.
# ─────────────────────────────────────────────

@export var open_action: StringName = &"squad_manager"
@export var panel_margin: float = 40.0
@export var font_size_header: int = 26
@export var font_size_body: int = 17
@export var slot_size: Vector2 = Vector2(58, 58)

const COL_DIM    := HUDPalette.DIM
const COL_BRIGHT := HUDPalette.BRIGHT
const COL_WARN   := HUDPalette.WARN
const COL_CRIT   := HUDPalette.CRIT

var campaign: Node
var state: CampaignState
var catalogue: ItemCatalogue

var _root: HBoxContainer
var _roster_list: VBoxContainer
var _armoury_list: VBoxContainer
var _resource_label: Label
var _detail: VBoxContainer
var _selected: SoldierRecord


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Build FIRST, unconditionally. The previous version bailed out here when it
	# couldn't find the campaign, which is guaranteed at this point: in
	# world.tscn the HUD is declared above CampaignManager, and children ready
	# in declaration order — so this node's _ready runs before the campaign node
	# exists in its group. The panel was never built, and the key did nothing.
	_build_ui()
	_resolve_campaign()

	if not InputMap.has_action(open_action):
		push_warning("SquadManagerUI: no input action '%s'. Add it in Project Settings > Input Map." % open_action)
	else:
		pass
		#print("[SquadManager] ready, bound to '%s'" % open_action)


# Deferred and retried, because the campaign node readies after this one.
func _resolve_campaign() -> bool:
	if state != null:
		return true
	campaign = get_tree().get_first_node_in_group("campaign")
	if campaign == null:
		return false
	state = campaign.state
	catalogue = campaign.get("catalogue")
	if state != null:
		if not state.roster_changed.is_connected(_rebuild):
			state.roster_changed.connect(_rebuild)
			state.ledger_changed.connect(_rebuild)
	return state != null


# _input, not _unhandled_input. Tab is bound to ui_focus_next by default and the
# UI layer eats it before unhandled input ever runs — which is exactly the key
# you picked. Consuming the event here also stops it double-firing into whatever
# else shares the binding.
func _input(event: InputEvent) -> void:
	if not InputMap.has_action(open_action):
		return
	if event.is_action_pressed(open_action):
		get_viewport().set_input_as_handled()
		toggle()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if not _resolve_campaign():
		push_warning("SquadManagerUI: no CampaignManager yet — cannot open.")
		return
	visible = true
	# A management screen with the mouse captured is unusable.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true
	_rebuild()


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ─────────────────────────────────────────────
# LAYOUT
# ─────────────────────────────────────────────
func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.05, 0.06, 0.92)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = panel_margin
	column.offset_right = -panel_margin
	column.offset_top = panel_margin
	column.offset_bottom = -panel_margin
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	column.add_child(header)
	header.add_child(_label("SQUAD", COL_BRIGHT, font_size_header))
	_resource_label = _label("", COL_WARN, font_size_header)
	header.add_child(_resource_label)

	_root = HBoxContainer.new()
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 18)
	column.add_child(_root)

	_roster_list = _make_column("ROSTER", 2)
	_detail = _make_column("SOLDIER", 2)
	_armoury_list = _make_column("ARMOURY", 1)

	var hint := _label("drag from ARMOURY onto a slot  ·  drag a slot back to ARMOURY to remove", COL_DIM, font_size_body)
	column.add_child(hint)


func _make_column(title: String, stretch: int) -> VBoxContainer:
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_stretch_ratio = float(stretch)
	wrapper.add_theme_constant_override("separation", 6)
	wrapper.add_child(_label(title, COL_DIM, font_size_body))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	_root.add_child(wrapper)
	return list


func _label(text: String, col: Color, size: int = -1) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size if size > 0 else font_size_body)
	return l


func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()


# ─────────────────────────────────────────────
# REBUILD
# ─────────────────────────────────────────────
func _rebuild() -> void:
	if state == null or _roster_list == null:
		return
	_resource_label.text = "RESOURCES  %d" % state.available()

	_clear(_roster_list)
	for record in state.roster:
		_roster_list.add_child(_make_roster_row(record))

	_clear(_armoury_list)
	var ids: Array = state.armoury.stock.keys()
	ids.sort()
	if ids.is_empty():
		_armoury_list.add_child(_label("nothing in stores", COL_DIM))
	for item_id in ids:
		var item := _item(item_id)
		if item != null:
			_armoury_list.add_child(_make_armoury_row(item, state.armoury.spare(item_id)))

	_rebuild_detail()


func _make_roster_row(record: SoldierRecord) -> Control:
	var row := Button.new()
	row.flat = true
	row.custom_minimum_size = Vector2(0, 34)
	var hp := record.current_health()
	var state_tag := ""
	if record.status == SoldierRecord.Status.DESTROYED:
		state_tag = "  [LOST]"
	elif record.status == SoldierRecord.Status.WOUNDED:
		state_tag = "  [HURT]"
	row.text = "%-12s %-10s %d/%d%s" % [
		record.display_name, record.rank_title(), hp, record.max_health, state_tag]
	row.add_theme_font_size_override("font_size", font_size_body)
	row.add_theme_color_override("font_color",
		COL_BRIGHT if record == _selected else COL_DIM)
	row.pressed.connect(func():
		_selected = record
		_rebuild())
	return row


func _make_armoury_row(item: ItemDefinition, count: int) -> Control:
	var row := _ArmouryRow.new()
	row.item_id = item.id
	row.owner_ui = self
	row.custom_minimum_size = Vector2(0, 40)
	row.add_theme_constant_override("separation", 8)
	row.add_child(_label("%dx" % count, COL_WARN))
	row.add_child(_label(item.display_name, COL_BRIGHT))
	var summary := item.effect_summary()
	if summary != "":
		row.add_child(_label(summary, COL_DIM))
	# A player-only weapon sitting in stores that won't drop onto a squadmate
	# looks like a bug unless it says so.
	var tag := item.carrier_tag()
	if tag != "":
		row.add_child(_label(tag, COL_WARN if tag == "[YOU]" else COL_DIM))
	return row


func _rebuild_detail() -> void:
	_clear(_detail)
	if _selected == null:
		_detail.add_child(_label("select a soldier", COL_DIM))
		return

	var chassis := _chassis(_selected.chassis_id)
	_detail.add_child(_label(_selected.display_name, COL_BRIGHT, font_size_header))
	_detail.add_child(_label("%s  ·  %s  ·  XP %d/%d" % [
		_selected.rank_title(),
		chassis.display_name if chassis != null else "no chassis",
		_selected.xp, _selected.xp_per_rank], COL_DIM))

	_add_slot_group("WEAPON", ItemDefinition.Kind.WEAPON, _selected.weapon_ids)
	_add_slot_group("EQUIPMENT", ItemDefinition.Kind.EQUIPMENT, _selected.equipment_ids)
	_add_slot_group("MODULES", ItemDefinition.Kind.MODULE, _selected.module_ids)


func _add_slot_group(title: String, kind: int, ids: Array) -> void:
	_detail.add_child(_label(title, COL_DIM))
	if ids.is_empty():
		_detail.add_child(_label("  no slots on this chassis", COL_DIM))
		return
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 6)
	_detail.add_child(strip)
	for i in ids.size():
		strip.add_child(_make_slot(kind, i, ids[i]))


func _make_slot(kind: int, index: int, item_id: StringName) -> Control:
	var slot := _SlotButton.new()
	slot.owner_ui = self
	slot.kind = kind
	slot.slot_index = index
	slot.item_id = item_id
	slot.custom_minimum_size = slot_size
	slot.flat = false
	var item := _item(item_id)
	slot.text = item.display_name.substr(0, 8) if item != null else "—"
	slot.add_theme_font_size_override("font_size", font_size_body - 3)
	slot.tooltip_text = item.effect_summary() if item != null else "empty slot"
	return slot


# ─────────────────────────────────────────────
# TRANSACTIONS — thin wrappers, all the logic is in CampaignState
# ─────────────────────────────────────────────
func fit(item_id: StringName, kind: int, slot_index: int) -> void:
	var item := _item(item_id)
	if item == null or _selected == null:
		return
	if item.kind != kind:
		return   # a module doesn't go in a weapon slot
	state.fit_item(_selected, item, slot_index)


func unfit(kind: int, slot_index: int) -> void:
	if _selected == null:
		return
	state.unfit_item(_selected, kind, slot_index)


func _item(id: StringName) -> ItemDefinition:
	return catalogue.item(id) if catalogue != null else null


func _chassis(id: StringName) -> ChassisDefinition:
	return catalogue.chassis_def(id) if catalogue != null else null


# ─────────────────────────────────────────────
# DRAG SOURCES AND TARGETS
# Godot routes drag-and-drop through these three virtuals on Control. Kept as
# tiny inner classes so the payload shape is defined right next to the thing
# that produces it.
# ─────────────────────────────────────────────
class _ArmouryRow extends HBoxContainer:
	var item_id: StringName
	var owner_ui: SquadManagerUI

	func _get_drag_data(_at: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = String(item_id)
		set_drag_preview(preview)
		return {"source": "armoury", "item_id": item_id}

	# Dropping a fitted item here removes it.
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("source") == "slot"

	func _drop_data(_at: Vector2, data: Variant) -> void:
		owner_ui.unfit(int(data["kind"]), int(data["slot_index"]))


class _SlotButton extends Button:
	var owner_ui: SquadManagerUI
	var kind: int
	var slot_index: int
	var item_id: StringName

	func _get_drag_data(_at: Vector2) -> Variant:
		if item_id == &"":
			return null
		var preview := Label.new()
		preview.text = String(item_id)
		set_drag_preview(preview)
		return {"source": "slot", "item_id": item_id, "kind": kind, "slot_index": slot_index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if not (data is Dictionary):
			return false
		if data.get("source") == "armoury":
			var item: ItemDefinition = owner_ui._item(data["item_id"])
			return item != null and item.kind == kind
		# Slot-to-slot within the same group is a swap.
		return data.get("source") == "slot" and int(data.get("kind", -1)) == kind

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if data.get("source") == "armoury":
			owner_ui.fit(data["item_id"], kind, slot_index)
			return
		# Swap: pull both out, put them back the other way round.
		var from_index := int(data["slot_index"])
		if from_index == slot_index:
			return
		var moving: StringName = data["item_id"]
		owner_ui.unfit(kind, from_index)
		if item_id != &"":
			owner_ui.unfit(kind, slot_index)
			owner_ui.fit(item_id, kind, from_index)
		owner_ui.fit(moving, kind, slot_index)
