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
# BUYING AND SELLING live on the armoury rows themselves rather than in a
# separate shop tab: [-] sells one at half what it cost, [+] buys one. The list
# comes from the catalogue, so an item you own none of is still a row with a
# price on it.
#
# NOT DONE YET, deliberately: buying chassis (CampaignState.buy_chassis exists
# and works, it belongs in the soldier detail panel) and ammo as a priced
# service. Wanted the drag-drop core proven before stacking more on it.
# ─────────────────────────────────────────────

@export var open_action: StringName = &"squad_manager"
@export var panel_margin: float = 40.0
@export var font_size_header: int = 26
@export var font_size_body: int = 17
@export var slot_size: Vector2 = Vector2(58, 58)

# ── AUDIO ─────────────────────────────────────
# Assign AudioStreamPlayers in the inspector; every one is optional and the UI
# is silent rather than broken if you leave them blank.
@export var sfx_hover: AudioStreamPlayer
@export var sfx_pick_up: AudioStreamPlayer
@export var sfx_drop: AudioStreamPlayer
@export var sfx_denied: AudioStreamPlayer
@export var sfx_select: AudioStreamPlayer
@export var sfx_open: AudioStreamPlayer
@export var sfx_close: AudioStreamPlayer

# ── CURSORS ───────────────────────────────────
# Godot swaps to its own arrow and its own "forbidden" circle-with-a-slash
# during a drag, which is what you're seeing. Supplying textures replaces both.
# hotspot is the pixel in the texture that counts as the point.
@export var cursor_arrow: Texture2D
@export var cursor_drag: Texture2D
@export var cursor_forbidden: Texture2D
@export var cursor_hotspot: Vector2 = Vector2.ZERO

# ── WHAT TO HIDE WHILE OPEN ───────────────────
# Leave empty and every sibling Control under the HUD is hidden, which is
# usually what you want. Name specific nodes to keep something visible.
@export var hide_while_open: Array[Control] = []

var _hidden: Array[Control] = []

# Set on close, consumed by the player on its next physics frame, so the click
# that dismissed the menu is not inherited by the gun as a held trigger. It has
# to be a flag rather than an edge check on "is the menu open", because
# _physics_process does not run at all while the tree is paused — the player
# never gets a frame in which to observe the menu being up.
static var release_pending: bool = false

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
var _name_edit: LineEdit
var _repair_button: Button

# Rebuilding Controls underneath a stationary mouse can emit mouse_entered on
# the replacement Controls. Suppress hover SFX until the player actually moves
# the mouse again so a click only produces its confirm/select sound.
var _suppress_hover_until_mouse_moves: bool = false


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
		print("[SquadManager] ready, bound to '%s'" % open_action)


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
	# A real mouse movement re-arms hover audio after a rebuild.
	if event is InputEventMouseMotion:
		_suppress_hover_until_mouse_moves = false

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
	_apply_cursors()
	_hide_other_hud(true)
	_play(sfx_open)
	_rebuild()


func close() -> void:
	visible = false
	release_pending = true
	get_tree().paused = false
	_hide_other_hud(false)
	_clear_cursors()
	_play(sfx_close)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# The crosshair, ammo readout, squad roster and objective list are all noise
# behind a management screen — and the squad HUD keeps drawing world markers
# over the top of it, which looks like a bug.
func _hide_other_hud(hiding: bool) -> void:
	if hiding:
		_hidden.clear()
		var targets: Array[Control] = hide_while_open
		if targets.is_empty():
			for sibling in get_parent().get_children():
				if sibling is Control and sibling != self:
					targets.append(sibling)
		for c in targets:
			if c != null and is_instance_valid(c) and c.visible:
				c.visible = false
				_hidden.append(c)
		return
	for c in _hidden:
		if c != null and is_instance_valid(c):
			c.visible = true
	_hidden.clear()


func _apply_cursors() -> void:
	if cursor_arrow != null:
		Input.set_custom_mouse_cursor(cursor_arrow, Input.CURSOR_ARROW, cursor_hotspot)
	if cursor_drag != null:
		Input.set_custom_mouse_cursor(cursor_drag, Input.CURSOR_DRAG, cursor_hotspot)
		Input.set_custom_mouse_cursor(cursor_drag, Input.CURSOR_CAN_DROP, cursor_hotspot)
	if cursor_forbidden != null:
		Input.set_custom_mouse_cursor(cursor_forbidden, Input.CURSOR_FORBIDDEN, cursor_hotspot)


func _clear_cursors() -> void:
	for shape in [Input.CURSOR_ARROW, Input.CURSOR_DRAG, Input.CURSOR_CAN_DROP, Input.CURSOR_FORBIDDEN]:
		Input.set_custom_mouse_cursor(null, shape)


func _play(player: AudioStreamPlayer) -> void:
	if player != null:
		player.play()


func _play_hover() -> void:
	if _suppress_hover_until_mouse_moves:
		return
	_play(sfx_hover)


# A drag preview that reads. The default was a bare Label, which inherits the
# theme's dim font colour and gets lost against the backdrop — and it showed the
# raw id because that's what the payload carries.
func make_drag_preview(item: ItemDefinition) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.09, 0.95)
	style.border_color = COL_BRIGHT
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = item.display_name if item != null else "?"
	label.add_theme_color_override("font_color", COL_BRIGHT)
	label.add_theme_font_size_override("font_size", font_size_body)
	panel.add_child(label)
	# Offset so the panel sits beside the pointer rather than under it.
	panel.position = Vector2(14, 10)
	return panel


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
	# Editable, and the source of truth — CampaignState.squad_name is what the
	# spawner puts on the Squad node, so renaming here renames you everywhere.
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(260, 0)
	_name_edit.add_theme_font_size_override("font_size", font_size_header)
	_name_edit.add_theme_color_override("font_color", COL_BRIGHT)
	_name_edit.flat = true
	_name_edit.placeholder_text = "NAMELESS"
	_name_edit.max_length = 16
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.focus_exited.connect(func():
		if is_instance_valid(_name_edit) and not _rebuilding:
			_on_name_submitted(_name_edit.text))
	header.add_child(_name_edit)
	_resource_label = _label("", COL_WARN, font_size_header)
	header.add_child(_resource_label)

	_root = HBoxContainer.new()
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 18)
	column.add_child(_root)

	_roster_list = _make_column("ROSTER", 2)
	_detail = _make_column("SOLDIER", 2)
	# Widened from 1. The armoury rows carry a price and two buttons now, and at
	# the old ratio there was not room for them beside the name.
	_armoury_list = _make_column("ARMOURY", 2)

	var hint := _label("drag from ARMOURY onto a slot  ·  right-click a slot to remove  ·  click the name to rename the squad", COL_DIM, font_size_body)
	column.add_child(hint)


func _make_column(title: String, stretch: int) -> VBoxContainer:
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_stretch_ratio = float(stretch)
	wrapper.add_theme_constant_override("separation", 6)
	wrapper.add_child(_label(title, COL_DIM, font_size_body))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Horizontal scrolling off. With it on, a row wider than the column is
	# simply scrolled off to the right instead of being constrained — which is
	# how the armoury's [+] button ended up somewhere you could not see or
	# click. Off, the row is held to the column width and its labels clip.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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


# remove_child BEFORE queue_free. queue_free is deferred — the node stays a
# child until the end of the frame — so a second _rebuild in the same frame
# found the old rows still parented and added a fresh set alongside them. That
# is the duplicated WEAPON / EQUIPMENT / MODULES blocks: two rebuilds, one
# frame, nothing actually removed in between.
func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# ─────────────────────────────────────────────
# REBUILD
# ─────────────────────────────────────────────
func _on_name_submitted(new_name: String) -> void:
	if state == null:
		return
	var cleaned := new_name.strip_edges().to_upper()
	if cleaned == "":
		cleaned = "NAMELESS"
	if cleaned == state.squad_name:
		return   # nothing changed; don't churn the panel
	state.squad_name = cleaned
	_name_edit.text = state.squad_name
	# Push it to any squad already in the world. The spawner reads squad_name at
	# deploy, but at base the squad is standing right there — renaming and not
	# seeing it change until the next mission reads as the rename not working.
	for squad in get_tree().get_nodes_in_group("squads"):
		if squad is Squad and (squad as Squad).player_commandable:
			(squad as Squad).callsign = state.squad_name
			(squad as Squad).notify_roster_changed()
	_rebuild()   # squad_name isn't on a record, so nothing else triggers this
	_name_edit.release_focus()
	_play(sfx_select)


var _rebuilding: bool = false


func _rebuild() -> void:
	if state == null or _roster_list == null:
		return
	# Renames emit roster_changed, which is already wired to _rebuild. Callers
	# that ALSO rebuild by hand would otherwise run the whole thing twice.
	if _rebuilding:
		return
	_rebuilding = true
	_do_rebuild()
	_rebuilding = false


func _do_rebuild() -> void:

	# The rebuild may replace a hovered Control while the cursor has not moved.
	# Any mouse_entered caused by that replacement should be silent.
	_suppress_hover_until_mouse_moves = true

	_resource_label.text = "RESOURCES  %d" % state.available()
	# Don't stomp what they're mid-way through typing.
	if not _name_edit.has_focus():
		_name_edit.text = state.squad_name

	_clear(_roster_list)
	# The player is one more row. Their slots come from their chassis exactly as
	# a squadmate's do; only fits_player() vs fits_ai() differs.
	if state.player_record != null:
		# "YOU" is also caught, so an existing save that already stored the old
		# placeholder picks up the new designator instead of keeping it forever.
		var player_name := state.player_record.display_name
		if player_name == "Unnamed" or player_name == "" or player_name == "YOU":
			state.player_record.display_name = CampaignState.PLAYER_DEFAULT_NAME
		_roster_list.add_child(_make_roster_row(state.player_record))
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 10)
		_roster_list.add_child(spacer)
	for record in state.roster:
		_roster_list.add_child(_make_roster_row(record))

	_clear(_armoury_list)
	# Driven by the CATALOGUE, not by what is in stock. Armoury.take() erases
	# the key when the last spare goes, so a stock-driven list deleted the row
	# the moment you sold your last one — taking its [+] with it, and leaving no
	# way to ever buy that item again. Rows at zero stay, dimmed.
	var shown: Array[ItemDefinition] = []
	if catalogue != null:
		for entry in catalogue.items:
			if entry != null:
				shown.append(entry)
		shown.sort_custom(func(a, b): return a.display_name < b.display_name)
	else:
		# Catalogue unresolved. Fall back to stock so the panel still shows what
		# you own, but say why the buyable-but-unowned rows are missing rather
		# than looking like an empty shop.
		push_warning("SquadManagerUI: no catalogue resolved; armoury falls back to stock only, so items you own none of are not listed.")
		var ids: Array = state.armoury.stock.keys()
		ids.sort()
		for item_id in ids:
			var owned := _item(item_id)
			if owned != null:
				shown.append(owned)
	if shown.is_empty():
		_armoury_list.add_child(_label("nothing in stores", COL_DIM))
	for def in shown:
		_armoury_list.add_child(_make_armoury_row(def, state.armoury.spare(def.id)))

	_rebuild_detail()


func _make_roster_row(record: SoldierRecord) -> Control:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 34)
	# flat = true still draws hover, pressed and focus styleboxes — those are
	# the horizontal lines lighting up the whole row. Blanking all five leaves
	# only the font colour to carry selection, which is what you want.
	_strip_button_styles(row)
	var hp := record.current_health()
	var state_tag := ""
	if record.status == SoldierRecord.Status.DESTROYED:
		state_tag = "  [WRECKED]"
	elif record.status == SoldierRecord.Status.WOUNDED:
		state_tag = "  [HURT]"
	elif record.damage > 0:
		state_tag = "  [DAMAGED]"
	row.text = "%-12s %-10s %d/%d%s" % [
		record.display_name, record.rank_title(), hp, record.max_health, state_tag]
	row.add_theme_font_size_override("font_size", font_size_body)
	row.add_theme_color_override("font_color",
		COL_BRIGHT if record == _selected else COL_DIM)
	row.pressed.connect(func():
		_selected = record
		_play(sfx_select)
		_rebuild())
	row.mouse_entered.connect(func(): _play_hover())
	return row


# Godot draws a stylebox for each state whether or not the button is flat.
func _strip_button_styles(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.focus_mode = Control.FOCUS_NONE


func _make_armoury_row(item: ItemDefinition, count: int) -> Control:
	var row := _ArmouryRow.new()
	row.item_id = item.id
	row.owner_ui = self
	# The row is a drag source; at zero there is nothing to pick up and it has
	# to refuse, or you drag a phantom onto a slot.
	row.spare_count = count
	row.custom_minimum_size = Vector2(0, 40)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	# SELL on the left, BUY on the right, so the destructive one is never where
	# a repeated buy-click lands.
	var refund_value := state.sale_value_of(item)
	row.add_child(_make_shop_button("-", count > 0,
		"Sell one %s for %d" % [item.display_name, refund_value],
		func(): _on_sell(item)))

	# Armoury rows are Containers rather than Buttons, so they do not get a
	# Button's automatic hover font colour. Store each label's resting colour
	# and explicitly brighten the whole row while hovered.
	row.add_child(_armoury_label("%dx" % count, COL_WARN if count > 0 else COL_DIM))

	# The NAME is the only thing allowed to grow, and it clips rather than
	# pushing. The armoury is the narrowest column, and a row whose labels add up
	# to more than its width does not wrap or shrink — it just overflows, and
	# everything after it (the price, the [+]) ends up outside the visible area.
	# That is why the buy button could not be seen.
	var name_label := _armoury_label(item.display_name, COL_DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)

	var summary := item.effect_summary()
	if summary != "":
		var summary_label := _armoury_label(summary, COL_DIM)
		summary_label.clip_text = true
		summary_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(summary_label)
	# A player-only weapon sitting in stores that won't drop onto a squadmate
	# looks like a bug unless it says so.
	var tag := item.carrier_tag()
	if tag != "":
		row.add_child(_armoury_label(tag, COL_WARN if tag == "[YOU]" else COL_DIM))

	var affordable := state.can_afford(item.cost)
	row.add_child(_armoury_label(str(item.cost), COL_WARN if affordable else COL_CRIT))
	row.add_child(_make_shop_button("+", affordable,
		"Buy one %s for %d" % [item.display_name, item.cost],
		func(): _on_buy(item)))

	row.mouse_entered.connect(func():
		_set_armoury_row_hover(row, true)
		_play_hover())
	row.mouse_exited.connect(func(): _set_armoury_row_hover(row, false))
	return row


func _armoury_label(text: String, col: Color) -> Label:
	var label := _label(text, col)
	label.set_meta("armoury_rest_color", col)
	return label


# Square +/- button for an armoury row. A button you cannot use is DISABLED
# rather than absent, so the row keeps its width and the [+] does not jump
# sideways under the cursor the moment you can no longer afford it.
func _make_shop_button(text: String, enabled: bool, tip: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(30, 30)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = tip
	button.disabled = not enabled
	button.add_theme_font_size_override("font_size", font_size_body)
	button.add_theme_color_override("font_color", COL_BRIGHT)
	button.add_theme_color_override("font_disabled_color", COL_DIM)
	if enabled:
		button.pressed.connect(on_press)
		button.mouse_entered.connect(_play_hover)
	return button


# Both of these lean on ledger_changed -> _rebuild, already wired in
# _resolve_campaign. Rebuilding by hand here would run it twice per click.
func _on_buy(item: ItemDefinition) -> void:
	if state == null or item == null:
		return
	_play(sfx_select if state.buy_item(item) else sfx_denied)


func _on_sell(item: ItemDefinition) -> void:
	if state == null or item == null:
		return
	_play(sfx_drop if state.sell_item(item) else sfx_denied)


func _set_armoury_row_hover(row: Control, hovered: bool) -> void:
	for child in row.get_children():
		if child is Label:
			var label := child as Label
			var col := COL_BRIGHT
			if not hovered:
				col = label.get_meta("armoury_rest_color", COL_DIM) as Color
			label.add_theme_color_override("font_color", col)


func _rebuild_detail() -> void:
	_clear(_detail)
	if _selected == null:
		_detail.add_child(_label("select a soldier", COL_DIM))
		return

	var chassis := _chassis(_selected.chassis_id)

	# Editable, same as the squad name. Soldiers you can name are soldiers you
	# notice losing, which is most of what the roster is for.
	var name_field := LineEdit.new()
	name_field.text = _selected.display_name
	name_field.flat = true
	name_field.max_length = 14
	name_field.placeholder_text = "UNNAMED"
	name_field.add_theme_font_size_override("font_size", font_size_header)
	name_field.add_theme_color_override("font_color", COL_BRIGHT)
	var record := _selected
	var commit := func(text: String):
		# Goes through CampaignState so the live body is renamed too, not just
		# the record — otherwise the squad HUD keeps the old name until the
		# next deploy.
		# rename_soldier emits roster_changed, which rebuilds. Calling it here
		# too was the second rebuild in the same frame.
		var cleaned: String = text.strip_edges()
		if cleaned == record.display_name:
			return
		state.rename_soldier(record, cleaned, get_tree())
		_play(sfx_select)
	name_field.text_submitted.connect(commit)
	# Only on a real focus loss. The rebuild frees this field, which fires
	# focus_exited, which would commit again and rebuild again.
	name_field.focus_exited.connect(func():
		if is_instance_valid(name_field) and not _rebuilding:
			commit.call(name_field.text))
	_detail.add_child(name_field)
	_detail.add_child(_label("%s  ·  %s  ·  XP %d/%d" % [
		_selected.rank_title(),
		chassis.display_name if chassis != null else "no chassis",
		_selected.xp, _selected.xp_per_rank], COL_DIM))

	# Repair is just resources. A wrecked 0/60 frame costs more per point than a
	# dented one, but it's the same transaction — nobody is permanently lost
	# while you can still afford to rebuild them.
	if _selected.damage > 0:
		var cost := state.repair_cost(_selected)
		var affordable := state.can_afford(cost)
		_repair_button = Button.new()
		_repair_button.text = "REPAIR  %d/%d  —  %d res" % [
			_selected.current_health(), _selected.max_health, cost]
		_repair_button.custom_minimum_size = Vector2(0, 32)
		_repair_button.add_theme_font_size_override("font_size", font_size_body)
		_strip_button_styles(_repair_button)
		_repair_button.add_theme_color_override("font_color", COL_WARN if affordable else COL_CRIT)
		_repair_button.disabled = not affordable
		_repair_button.pressed.connect(func():
			if state.repair_soldier(_selected):
				_play(sfx_drop)
			else:
				_play(sfx_denied))
		_repair_button.mouse_entered.connect(func(): _play_hover())
		_detail.add_child(_repair_button)

	_add_slot_group("WEAPON", ItemDefinition.Kind.WEAPON, _selected.weapon_ids)
	_add_slot_group("EQUIPMENT", ItemDefinition.Kind.EQUIPMENT, _selected.equipment_ids)
	_add_slot_group("MODULES", ItemDefinition.Kind.MODULE, _selected.module_ids)


func _add_slot_group(title: String, kind: int, ids: Array) -> void:
	await get_tree().process_frame
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
	_strip_button_styles(slot)
	# Slots keep a visible outline so an empty one still reads as a slot.
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(0.09, 0.11, 0.12, 0.85)
	outline.border_color = COL_DIM
	outline.set_border_width_all(1)
	slot.add_theme_stylebox_override("normal", outline)
	var lit := outline.duplicate() as StyleBoxFlat
	lit.border_color = COL_BRIGHT
	slot.add_theme_stylebox_override("hover", lit)
	slot.mouse_entered.connect(func(): _play_hover())
	slot.kind = kind
	slot.slot_index = index
	slot.item_id = item_id
	slot.custom_minimum_size = slot_size
	slot.flat = false
	var item := _item(item_id)
	slot.text = item.short_label() if item != null else "—"
	slot.add_theme_font_size_override("font_size", font_size_body - 3)
	slot.tooltip_text = "%s\n%s\n\nright-click to remove" % [
		item.display_name, item.effect_summary()] if item != null else "empty slot"
	return slot


# ─────────────────────────────────────────────
# TRANSACTIONS — thin wrappers, all the logic is in CampaignState
# ─────────────────────────────────────────────
func fit(item_id: StringName, kind: int, slot_index: int) -> void:
	var item := _item(item_id)
	if item == null or _selected == null:
		return
	if item.kind != kind:
		_play(sfx_denied)
		return   # a module doesn't go in a weapon slot
	if not state.fit_item(_selected, item, slot_index):
		_play(sfx_denied)


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
	# Rows for items you own none of are still listed so they can be bought.
	var spare_count: int = 0

	func _get_drag_data(_at: Vector2) -> Variant:
		# Refuse rather than handing out a phantom: this row is showing a buy
		# price, not stock. Without this you can drag a zero-count item onto a
		# slot and fit something you do not have.
		if spare_count <= 0:
			return null
		set_drag_preview(owner_ui.make_drag_preview(owner_ui._item(item_id)))
		owner_ui._play(owner_ui.sfx_pick_up)
		return {"source": "armoury", "item_id": item_id}

	# Dropping a fitted item here removes it.
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("source") == "slot"

	func _drop_data(_at: Vector2, data: Variant) -> void:
		owner_ui.unfit(int(data["kind"]), int(data["slot_index"]))
		owner_ui._play(owner_ui.sfx_drop)


class _SlotButton extends Button:
	var owner_ui: SquadManagerUI
	var kind: int
	var slot_index: int
	var item_id: StringName

	# Dragging a slot back to the armoury works, but it's four times the effort
	# for the common case of "take that off".
	func _gui_input(event: InputEvent) -> void:
		if item_id == &"":
			return
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			owner_ui.unfit(kind, slot_index)
			owner_ui._play(owner_ui.sfx_drop)

	func _get_drag_data(_at: Vector2) -> Variant:
		if item_id == &"":
			return null
		set_drag_preview(owner_ui.make_drag_preview(owner_ui._item(item_id)))
		owner_ui._play(owner_ui.sfx_pick_up)
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
		owner_ui._play(owner_ui.sfx_drop)
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
