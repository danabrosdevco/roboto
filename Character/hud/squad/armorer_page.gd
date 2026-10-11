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
	[ItemDefinition.Kind.EQUIPMENT, "EQUIPMENT"],
	[ItemDefinition.Kind.MODULE, "MODULES"],
]
## Gear figures, read off the gear's own scenes. By path: a brand-new class_name
## is not resolvable until the editor rescans.
const _Facts := preload("res://Campaign/item_facts.gd")
## Tops of the weapon bars. FIXED, and the same on every card, so two guns can be
## compared by eye — a bar scaled to its own row is a bar that cannot be read
## against the one above it. Damage is one impact, not a cluster round's whole
## 220: the bomblets are in the reading, because white on a bar means "a module
## added this" everywhere else on these screens and must not mean two things.
const DAMAGE_TOP := 80.0
const FIREPOWER_TOP := 200.0
const RANGE_TOP := 130.0
const MAGAZINE_TOP := 120.0

var ui
var selected_id: StringName = &""
## Which shelves are rolled up, by item kind. Same idea as the Squad page's
## teams: shopping for a module should not mean scrolling past every gun.
## DEFAULTS TO OPEN — a shop that greets you shut is a shop that looks empty.
var _folded: Dictionary = {}

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
		var stock: Array = []
		for item in items:
			if item.kind == kind:
				stock.append(item)
		if stock.is_empty():
			continue
		var open: bool = not _folded.get(kind, false)
		_left.add_child(_shelf_head(kind, str(entry[1]), stock.size(), open))
		if open:
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 8)
			row.add_theme_constant_override("v_separation", 8)
			for item in stock:
				row.add_child(_card(item))
			_left.add_child(row)
		_left.add_child(Kit.spacer(0, 4))
	_rebuild_detail()


## The clickable bar over a shelf. The COUNT stays when it is folded: a closed
## row showing only its name hides how much is behind it, which is what stops
## anybody opening it again.
func _shelf_head(kind: int, title: String, count: int, open: bool) -> Control:
	var head := Kit.hbox(8)
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	head.tooltip_text = "Fold these away" if open else "Show these"
	head.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			head.accept_event()
			_folded[kind] = open
			ui.play(&"select")
			rebuild())
	head.add_child(Kit.caret(open))
	head.add_child(Kit.heading(title))
	head.add_child(Kit.fill())
	head.add_child(Kit.label("%d IN THE SHOP" % count, Kit.DIM, Kit.SMALL))
	return head


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
	# Joined rather than formatted, because carriers() is empty for anything both
	# sides can use — which is most things — and a trailing separator on a card is
	# the kind of thing nobody files but everybody sees.
	var line := PackedStringArray([Kit.kind_text(item)])
	var who := Kit.carriers(item)
	if who != "":
		line.append(who)
	_detail.add_child(Kit.label(" · ".join(line), Kit.DIM, Kit.SMALL))
	# THREE SHAPES, ONE PANEL. Bars rank things on one scale, and two guns share
	# that scale — more damage is more damage. A smoke canister's fourteen
	# seconds and a frag's hundred points of blast do not, so gear gets a fact
	# list instead; a bar across those two would be decoration pretending to be
	# information. And a module is a single number, so it gets a single line: a
	# bar over one value is a bar with one entry.
	match item.kind:
		ItemDefinition.Kind.WEAPON:
			_weapon_bars(item)
		ItemDefinition.Kind.EQUIPMENT:
			_fact_list(item)
		_:
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


## WHAT A GUN DOES, in the four numbers that decide a fight.
##
## Damage is one round landing; firepower is damage times rate — what it takes
## off a hull per second while it is firing. A card showing only one of them
## lies: the Heavy MG does a third of the Autocannon's damage per round and half
## again its firepower.
##
## The figures come off the WEAPON SCENE, not the item. ItemDefinition's
## weapon_damage is 0 on all fourteen guns, and a launcher's damage was never on
## the launcher anyway — it is on the round, and a cluster round carries six more
## bomblets inside that. AIWeapon.shot_damage() is what knows.
func _weapon_bars(item: ItemDefinition) -> void:
	# NO MESSAGE WHEN THERE ARE NO FIGURES. It used to say "NO FIGURES: THIS ONE
	# HAS NO AI WEAPON SCENE", which is a sentence about the project's internals
	# printed at the player: ai_scene is not a thing they have, can get, or should
	# ever hear about. The Repair Lance is the one that hits this, and its own
	# description already says what it does — reach, damage, mends, recharge — so
	# the bars would have added nothing anyway.
	if item.ai_scene == null:
		return
	var node = item.ai_scene.instantiate()
	if not (node is AIWeapon):
		node.free()
		return
	var weapon := node as AIWeapon
	var shot: Dictionary = weapon.shot_damage()
	var impact := int(shot.get("impact", 0))
	var bomblets := int(shot.get("submunitions", 0))
	var total := int(shot.get("total", impact))
	var reading := str(impact)
	if bomblets > 0:
		reading = "%d+%dX%d" % [impact, bomblets, int(shot.get("each", 0))]
	var cooldown: float = weapon.fire_cooldown
	var firepower: float = (float(total) / cooldown) if cooldown > 0.0 else 0.0

	_detail.add_child(Kit.stat_bar("DAMAGE", impact, impact, DAMAGE_TOP, reading))
	_detail.add_child(Kit.stat_bar("FIREPOWER", firepower, firepower, FIREPOWER_TOP,
		"%d/S" % int(round(firepower))))
	_detail.add_child(Kit.stat_bar("RANGE", weapon.max_effective_range, weapon.max_effective_range,
		RANGE_TOP, "%d M" % int(round(weapon.max_effective_range))))
	_detail.add_child(Kit.stat_bar("MAGAZINE", weapon.magazine_size, weapon.magazine_size,
		MAGAZINE_TOP, str(weapon.magazine_size)))

	var tail: Array = []
	if weapon.reload_time > 0.0:
		tail.append("RELOAD %.1f S" % weapon.reload_time)
	if bomblets > 0:
		# The ceiling, said as a ceiling. All 220 only lands if every bomblet
		# finds something, and a card that prints it flat would be promising a
		# figure the gun rarely delivers.
		tail.append("%d A ROUND IF EVERY BOMBLET LANDS" % total)
	if not tail.is_empty():
		_detail.add_child(Kit.label(" · ".join(tail), Kit.DIM, Kit.SMALL))
	weapon.free()


## Gear, as the two or three figures that matter, read off its own scenes. An
## item whose scenes carry no numbers gets its effect line instead of a made-up
## one — see ItemFacts.
func _fact_list(item: ItemDefinition) -> void:
	var rows: Array = _Facts.of(item)
	if rows.is_empty():
		var effect := Kit.effect_text(item)
		if effect != "":
			_detail.add_child(Kit.label(effect, Kit.BRIGHT, Kit.HEADING, true))
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 2)
	for pair in rows:
		grid.add_child(Kit.label(str(pair[0]), Kit.DIM, Kit.SMALL))
		var value := Kit.label(str(pair[1]), Kit.BRIGHT, Kit.SMALL, true)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
	_detail.add_child(grid)
