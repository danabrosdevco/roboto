extends VBoxContainer

# ─────────────────────────────────────────────
# MEMORY — everything the player keeps loaded. Was SOFTWARE.
#
# Three tabs over ONE ledger:
#
#   WEAPONS     the guns you may carry      software_tree.gd CARRY
#   EQUIPMENT   the kit you may carry       software_tree.gd CARRY
#   UPGRADES    the branches                software_tree.gd BRANCHES
#
# The name changed with the shape. SOFTWARE described a tree of upgrades, so a
# gun rack beside it was a tree of upgrades with a gun rack beside it; MEMORY
# is what all three tabs actually are, and it says the rule out loud — a thing
# in memory is HELD, not bought. It costs compute for exactly as long as it is
# loaded and returns all of it when unloaded, so this is a set of switches
# rather than a shop.
#
# Compute is also seats (the Factory), so the real question on every tab is
# the same one: arm yourself, or field another robot.
#
# NO PER-CARD EXPLANATION. The first draft printed "2 compute while racked,
# all of it back on removal" under every card, which is the screen explaining
# its own rule nine times to someone already looking at the button. The ledger
# at the top says it once in numbers, and a card you cannot afford greys its
# own button — that is the explanation, in the place the player is looking.
#
# LOADED IS NOT CARRIED. One weapon slot and two equipment slots; what is
# loaded is what you may CHOOSE from, and choosing is free and reversible.
# ─────────────────────────────────────────────

const Kit := preload("res://Character/hud/squad/ui_kit.gd")
const Icons := preload("res://Character/hud/icons/icons.gd")
const Programs := preload("res://Campaign/software_tree.gd")

const TABS := [&"weapons", &"kit", &"upgrades"]
const TAB_TITLES := {&"weapons": "WEAPONS", &"kit": "EQUIPMENT", &"upgrades": "UPGRADES"}
const CARD_WIDTH := 330.0
const ICON := Vector2(40, 40)

var ui
var tab: StringName = &"weapons"

var _tabs: HBoxContainer
var _ledger: Label
var _body: VBoxContainer


func setup(owner_ui) -> void:
	ui = owner_ui
	add_theme_constant_override("separation", 10)

	_tabs = Kit.hbox(0)
	add_child(_tabs)
	var rule := ColorRect.new()
	rule.color = Kit.FAINT
	rule.custom_minimum_size = Vector2(0, 1)
	add_child(rule)

	_ledger = Kit.label("", Kit.DIM, Kit.SMALL)
	add_child(_ledger)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = Kit.vbox(10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)


func on_open() -> void:
	pass


func rebuild() -> void:
	_rebuild_tabs()
	_rebuild_ledger()
	Kit.clear(_body)
	match tab:
		&"weapons":
			_rebuild_carry(Programs.CARRY_WEAPON)
		&"kit":
			_rebuild_carry(Programs.CARRY_KIT)
		_:
			_rebuild_upgrades()


func _show(which: StringName) -> void:
	tab = which
	ui.play(&"select")
	rebuild()


func _rebuild_tabs() -> void:
	Kit.clear(_tabs)
	for id in TABS:
		var on: bool = id == tab
		var b := Kit.button(TAB_TITLES[id], Kit.COMPUTE if on else Kit.DIM, Kit.SMALL, on)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = Kit.COMPUTE
		style.border_width_bottom = 2 if on else 0
		style.set_content_margin_all(6)
		style.content_margin_left = 14
		style.content_margin_right = 14
		for s in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(s, style)
		b.mouse_entered.connect(ui.hover)
		b.pressed.connect(_show.bind(id))
		_tabs.add_child(b)


# THE LEDGER, SAID ONCE AND IN NUMBERS, ABOVE ALL THREE TABS.
func _rebuild_ledger() -> void:
	var state: CampaignState = ui.state
	var free := state.compute_free()
	var seats := _seats_held(state)
	var loaded := state.compute_earned - free - seats
	var text := "%d LOADED · %d IN SEATS · %d FREE OF %d COMPUTE" % [
		loaded, seats, free, state.compute_earned]
	if tab == &"kit":
		text += " · %d OF %d SLOTS CARRIED" % [_carried_count(state), state.player_record.equipment_ids.size()]
	_ledger.text = text
	_ledger.add_theme_color_override("font_color", Kit.PROBLEM if free < 0 else Kit.DIM)


func _seats_held(state: CampaignState) -> int:
	var n := 0
	for key in state.compute_held:
		if str(key).begins_with("seat:"):
			n += int(state.compute_held[key])
	return n


func _carried_count(state: CampaignState) -> int:
	var n := 0
	for id_value in state.player_record.equipment_ids:
		if id_value != &"":
			n += 1
	return n


# ─────────────────────────────────────────────
# WEAPONS AND EQUIPMENT
# ─────────────────────────────────────────────
func _rebuild_carry(kind: StringName) -> void:
	var state: CampaignState = ui.state
	var grid := _grid()
	for entry in Programs.carry(kind):
		var item: ItemDefinition = state.catalogue.item(entry["item"]) if state.catalogue != null else null
		if item == null:
			# A carry entry with no catalogue item is a typo in the list, and a
			# card that silently does not appear is how it stays a typo.
			push_warning("MemoryPage: no catalogue item '%s' for %s." % [entry["item"], entry["id"]])
			continue
		grid.add_child(_carry_card(entry, item))
	_body.add_child(grid)


func _grid() -> HFlowContainer:
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return grid


func _carry_card(entry: Dictionary, item: ItemDefinition) -> Control:
	var state: CampaignState = ui.state
	var loaded: bool = Programs.is_loaded(state, item.id)
	var issued: bool = Programs.is_issued(item.id)
	var carried := _is_carried(state, item)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		Kit.box(Kit.COMPUTE if carried else (Kit.LINE if loaded else Kit.FAINT), Kit.PANEL, 1, 11.0))
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)

	var col := Kit.vbox(7)
	card.add_child(col)

	var head := Kit.hbox(10)
	head.add_child(Kit.icon(Icons.item(item, "m"), Kit.BRIGHT if loaded else Kit.DIM, ICON, true))
	var words := Kit.vbox(2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(Kit.label(item.display_name.to_upper(), Kit.BRIGHT if loaded else Kit.DIM, Kit.BODY, true))
	# THE CATALOGUE'S OWN WORDS. Never a second copy written here.
	var about := Kit.text_block(item.description, Kit.DIM, Kit.SMALL)
	about.custom_minimum_size = Vector2(CARD_WIDTH - 110, 0)
	words.add_child(about)
	if item.kind == ItemDefinition.Kind.EQUIPMENT and item.quantity > 0:
		words.add_child(Kit.label("x%d A MISSION" % item.quantity, Kit.COMPUTE, Kit.SMALL))
	head.add_child(words)
	head.add_child(_load_control(entry, item, loaded, issued))
	col.add_child(head)

	var action := _carry_control(item, loaded, carried)
	if action != null:
		# SHRINK, not fill. A button stretched to the card's width reads as a
		# bar the card is made of rather than as a thing to press.
		action.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(action)
	return card


## ISSUED / LOAD n / UNLOAD, in the corner. The cost lives on the button, so
## the card never has to say what loading costs in a sentence.
func _load_control(entry: Dictionary, item: ItemDefinition, loaded: bool, issued: bool) -> Control:
	var state: CampaignState = ui.state
	if issued:
		var tag := Kit.label("ISSUED", Kit.MONEY, Kit.SMALL, true)
		tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		return tag
	if loaded:
		var off := Kit.button("UNLOAD", Kit.DIM, Kit.SMALL)
		off.tooltip_text = "Returns all %d compute." % int(entry["cost"])
		off.mouse_entered.connect(ui.hover)
		off.pressed.connect(func() -> void:
			ui.play(&"remove" if Programs.unload_item(state, item.id) else &"denied"))
		off.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		return off
	var reason := Programs.load_block(state, item.id)
	var on := Kit.button("LOAD %d" % int(entry["cost"]), Kit.COMPUTE if reason == "" else Kit.DIM, Kit.SMALL)
	on.disabled = reason != ""
	on.tooltip_text = reason if reason != "" else "Holds %d compute until unloaded." % int(entry["cost"])
	on.mouse_entered.connect(ui.hover)
	on.pressed.connect(func() -> void:
		ui.play(&"fit" if Programs.load_item(state, item.id) else &"denied"))
	on.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return on


## CARRY / CARRYING, under the card. Nothing at all on a card that is not
## loaded: there is only one thing to do with it and it is in the corner.
func _carry_control(item: ItemDefinition, loaded: bool, carried: bool) -> Control:
	if not loaded:
		return null
	var state: CampaignState = ui.state
	if item.kind == ItemDefinition.Kind.WEAPON:
		if carried:
			return Kit.label("CARRYING", Kit.COMPUTE, Kit.SMALL, true)
		var pick := Kit.button("CARRY", Kit.BRIGHT, Kit.SMALL)
		pick.mouse_entered.connect(ui.hover)
		pick.pressed.connect(func() -> void:
			ui.play(&"fit" if state.carry_weapon(item) else &"denied"))
		return pick
	if carried:
		var drop := Kit.button("CARRYING - DROP", Kit.COMPUTE, Kit.SMALL)
		drop.mouse_entered.connect(ui.hover)
		drop.pressed.connect(func() -> void:
			var at: int = state.player_record.equipment_ids.find(item.id)
			ui.play(&"remove" if state.drop_equipment(at) else &"denied"))
		return drop
	# THE SLOTS ARE THE LIMIT, not memory. Loading buys the option; two is what
	# you can actually take into a mission.
	var full := _carried_count(state) >= state.player_record.equipment_ids.size()
	var take := Kit.button("CARRY", Kit.DIM if full else Kit.BRIGHT, Kit.SMALL)
	take.disabled = full
	if full:
		take.tooltip_text = "Every slot is full. Drop one first."
	take.mouse_entered.connect(ui.hover)
	take.pressed.connect(func() -> void:
		ui.play(&"fit" if state.carry_equipment(item) else &"denied"))
	return take


func _is_carried(state: CampaignState, item: ItemDefinition) -> bool:
	if state.player_record == null:
		return false
	if item.kind == ItemDefinition.Kind.WEAPON:
		return state.player_record.weapon_ids.has(item.id)
	return state.player_record.equipment_ids.has(item.id)


# ─────────────────────────────────────────────
# UPGRADES
# ─────────────────────────────────────────────
# One panel per branch, programs down it by tier, each with its own button —
# the same shape as the other two tabs, because they are the same mechanic.
# Every program is still a blank placeholder; the costs, the gating and the
# refunds are real. See software_tree.gd.
func _rebuild_upgrades() -> void:
	var grid := _grid()
	for branch in Programs.BRANCHES:
		grid.add_child(_branch_panel(branch))
	_body.add_child(grid)


func _branch_panel(branch: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Kit.box(Kit.FAINT, Kit.PANEL, 1, 11.0))
	panel.custom_minimum_size = Vector2(CARD_WIDTH + 40, 0)
	var col := Kit.vbox(0)
	panel.add_child(col)
	col.add_child(Kit.label(branch["title"], Kit.BRIGHT, Kit.BODY, true))
	col.add_child(Kit.label(branch["about"], Kit.DIM, Kit.SMALL))
	col.add_child(Kit.spacer(0, 6))
	for tier in [1, 2, 3]:
		for n in Programs.nodes():
			if n["branch"] == branch["id"] and n["tier"] == tier:
				col.add_child(_program_row(n))
	return panel


func _program_row(n: Dictionary) -> Control:
	var state: CampaignState = ui.state
	var installed: bool = state.is_installed(n["id"])
	var block: String = Programs.install_block(state, n["id"])
	var locked := not installed and block.begins_with("NEEDS A TIER")

	var row := Kit.hbox(10)
	row.add_child(Kit.label("T%d" % n["tier"], Kit.COMPUTE if installed else Kit.DIM, Kit.SMALL, true))
	var words := Kit.vbox(1)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(Kit.label(n["title"], Kit.COMPUTE if installed else Kit.DIM, Kit.SMALL, installed))
	if n["about"] != "":
		var about := Kit.text_block(n["about"], Kit.DIM, Kit.SMALL)
		about.custom_minimum_size = Vector2(CARD_WIDTH - 90, 0)
		words.add_child(about)
	row.add_child(words)

	if installed:
		var reason := Programs.uninstall_block(state, n["id"])
		var off := Kit.button("UNLOAD", Kit.DIM, Kit.SMALL)
		off.disabled = reason != ""
		off.tooltip_text = reason if reason != "" else "Returns all %d compute." % n["cost"]
		off.mouse_entered.connect(ui.hover)
		off.pressed.connect(func() -> void:
			ui.play(&"remove" if Programs.uninstall(state, n["id"]) else &"denied"))
		row.add_child(off)
	else:
		var on := Kit.button("LOAD %d" % n["cost"], Kit.COMPUTE if block == "" else Kit.DIM, Kit.SMALL)
		on.disabled = block != ""
		on.tooltip_text = block if block != "" else "Holds %d compute until unloaded." % n["cost"]
		on.mouse_entered.connect(ui.hover)
		on.pressed.connect(func() -> void:
			ui.play(&"fit" if Programs.install(state, n["id"]) else &"denied"))
		row.add_child(on)
	if locked:
		row.modulate = Color(1, 1, 1, 0.55)
	return row
