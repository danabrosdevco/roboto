extends HBoxContainer

# ─────────────────────────────────────────────
# ARMORER — buy and sell gear. The only page with prices on it.
#
# Everything in the catalogue that is for sale (or that you still own one of),
# in rows by kind: WEAPONS, GEAR, MODULES. Each is a card with its icon, its
# price in amber, and how many you have in stores. Select one and the right
# side has room for what it actually does, who can carry it, where your
# copies are, and BUY / SELL.
#
# Buying puts it in stores; fitting it is the Squad page's job. Selling takes
# a spare from stores for half what it cost — something fitted to a robot has
# to come off first, so nobody is disarmed by a mis-click here.
# ─────────────────────────────────────────────

const Kit := preload("res://Character/hud/squad/ui_kit.gd")
const Icons := preload("res://Character/hud/icons/icons.gd")
const DETAIL_WIDTH := 400.0
const ROWS := [
	[ItemDefinition.Kind.WEAPON, "WEAPONS"],
	[ItemDefinition.Kind.EQUIPMENT, "GEAR"],
	[ItemDefinition.Kind.MODULE, "MODULES"],
]

var ui
var selected_id: StringName = &""

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


## Arriving from the Squad page's "buy at the Armorer": start on that kind.
func focus_kind(kind: int) -> void:
	for item in ui.shop_items():
		if item.kind == kind:
			selected_id = item.id
			return


func on_open() -> void:
	pass


func rebuild() -> void:
	var items: Array = ui.shop_items()
	if ui.item(selected_id) == null or not items.has(ui.item(selected_id)):
		selected_id = items[0].id if not items.is_empty() else &""
	Kit.clear(_left)
	for entry in ROWS:
		var kind: int = entry[0]
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 8)
		for item in items:
			if item.kind == kind:
				row.add_child(_card(item))
		if row.get_child_count() == 0:
			row.queue_free()
			continue
		_left.add_child(Kit.heading(entry[1]))
		_left.add_child(row)
		_left.add_child(Kit.spacer(0, 4))
	_rebuild_detail()


func _rebuild_detail() -> void:
	Kit.clear(_detail)
	var item: ItemDefinition = ui.item(selected_id)
	if item != null:
		_build_detail(item)


func _card(item: ItemDefinition) -> Control:
	var state: CampaignState = ui.state
	var wide := item.kind == ItemDefinition.Kind.WEAPON
	var pick := func():
		selected_id = item.id
		ui.play(&"select")
		rebuild()
	var card := Kit.card(Kit.BRIGHT if item.id == selected_id else Kit.LINE, pick, ui.hover, 6.0)
	card.custom_minimum_size = Vector2(160, 104) if wide else Vector2(108, 104)
	card.tooltip_text = item.display_name
	var col := Kit.vbox(4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(col)
	col.add_child(Kit.icon(Icons.item(item, "m"), Kit.BRIGHT, Vector2(96, 36) if wide else Vector2(36, 36)))
	var title := Kit.label(item.short_label().to_upper(), Kit.BRIGHT, Kit.BODY, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	col.add_child(title)
	var foot := Kit.hbox(4)
	var locked: MissionDefinition = ui.locked_by(item.id)
	if locked != null:
		foot.add_child(Kit.label("LOCKED", Kit.DIM, Kit.SMALL, true))
		card.modulate = Color(1, 1, 1, 0.55)
	elif item.in_shop:
		foot.add_child(Kit.label(str(item.cost), Kit.MONEY if state.can_afford(item.cost) else Kit.PROBLEM,
			Kit.BODY, true))
	foot.add_child(Kit.fill())
	var spare := state.armoury.spare(item.id)
	foot.add_child(Kit.label("X%d" % spare if spare > 0 else "", Kit.BRIGHT, Kit.BODY, true))
	col.add_child(foot)
	return card


func _build_detail(item: ItemDefinition) -> void:
	var state: CampaignState = ui.state
	var wide := item.kind == ItemDefinition.Kind.WEAPON
	var art := Kit.icon(Icons.item(item, "l"), Kit.BRIGHT, Vector2(256, 96) if wide else Vector2(96, 96))
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail.add_child(art)
	_detail.add_child(Kit.label(item.display_name.to_upper(), Kit.BRIGHT, 24, true))
	_detail.add_child(Kit.label("%s · %s" % [Kit.KIND_NAMES.get(item.kind, ""), Kit.carriers(item)], Kit.DIM, Kit.SMALL))
	var effect := Kit.effect_text(item)
	if effect != "":
		_detail.add_child(Kit.label(effect, Kit.BRIGHT, Kit.HEADING, true))
	if item.description != "":
		_detail.add_child(Kit.text_block(item.description, Kit.DIM, Kit.BODY))
	if item.required_rank > 0:
		_detail.add_child(Kit.label("NEEDS RANK %d" % item.required_rank, Kit.DIM, Kit.SMALL))

	_detail.add_child(Kit.spacer(0, 4))
	var spare := state.armoury.spare(item.id)
	var carriers: PackedStringArray = ui.carriers_of(item.id)
	var owned := "IN STORES %d" % spare
	if not carriers.is_empty():
		owned += " · FITTED: %s" % ", ".join(carriers)
	_detail.add_child(Kit.text_block(owned, Kit.DIM, Kit.SMALL))

	var buy_row := Kit.hbox(10)
	var locked: MissionDefinition = ui.locked_by(item.id)
	if locked != null:
		buy_row.add_child(Kit.label("LOCKED · CLEAR %s" % locked.display_name.to_upper(), Kit.DIM, Kit.SMALL, true))
	elif item.in_shop:
		var affordable := state.can_afford(item.cost)
		var buy := Kit.button("BUY", Kit.BRIGHT if affordable else Kit.PROBLEM)
		buy.disabled = not affordable
		buy.tooltip_text = "Buy one %s into stores." % item.display_name
		buy.mouse_entered.connect(ui.hover)
		buy.pressed.connect(func(): ui.play(&"select" if state.buy_item(item) else &"denied"))
		buy_row.add_child(buy)
		buy_row.add_child(Kit.label(str(item.cost), Kit.MONEY, Kit.HEADING, true))
		if not affordable:
			buy_row.add_child(Kit.label("NEED %d MORE" % (item.cost - state.available()), Kit.PROBLEM, Kit.SMALL))
	else:
		buy_row.add_child(Kit.label("NO LONGER SOLD", Kit.DIM, Kit.SMALL))
	_detail.add_child(buy_row)
	if spare > 0:
		# Buying and fitting are on different pages; this is the way between
		# them, landing on the matching slot of whoever the Squad page has
		# selected.
		var fit := Kit.button("FIT IT ON THE SQUAD PAGE", Kit.BRIGHT, Kit.SMALL)
		fit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		fit.mouse_entered.connect(ui.hover)
		var kind := item.kind
		fit.pressed.connect(func(): ui.show_tab(&"squad", {"kind": kind}))
		_detail.add_child(fit)
		var sell_row := Kit.hbox(10)
		var sell := Kit.button("SELL ONE", Kit.DIM)
		sell.tooltip_text = "Sell a spare from stores."
		sell.mouse_entered.connect(ui.hover)
		sell.pressed.connect(func(): ui.play(&"remove" if state.sell_item(item) else &"denied"))
		sell_row.add_child(sell)
		sell_row.add_child(Kit.label("+%d" % state.sale_value_of(item), Kit.MONEY, Kit.HEADING, true))
		_detail.add_child(sell_row)
