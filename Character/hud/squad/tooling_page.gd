extends VBoxContainer

# ─────────────────────────────────────────────
# TOOLING FABRICATOR — the only place a line is OPENED.
#
# docs/briefs/CAMPAIGN_REWORK.md Phase 3.5. Buying a copy and opening a line
# are two different decisions, and mixing them on one screen made the armourer
# read as a shop that sometimes refused to sell to you. So they are split:
#
#   TOOLING    opens lines. Everything for sale, open or not, and what it costs
#   ARMORER    buys copies. Shows ONLY what is already open
#   FACTORY    builds robots. Shows ONLY frames that are already open
#
# FOUR KINDS, FOUR TABS, CARDS NOT ROWS. The first cut was one long scrolling
# list of text rows with every kind stacked into it, and it read as a
# spreadsheet — you could not tell a Walker from a frag grenade without
# reading the line. The armourer and the factory had already solved this: a
# grid of cards carrying the thing's own icon, with the detail on the right.
# This is the same furniture, so the three screens look like one tool.
#
# WHAT IS OPEN STAYS LISTED, dimmed rather than removed, with an n/m count in
# the header. A catalogue that silently shrinks as you buy from it gives you no
# sense of how much tree is left, and no way to see what a chain is waiting on.
# ─────────────────────────────────────────────

const Kit := preload("res://Character/hud/squad/ui_kit.gd")
const Icons := preload("res://Character/hud/icons/icons.gd")
## One price table — Campaign/pricing.gd. Preloaded rather than named, because
## a new `class_name` is not visible until the editor rescans.
const _Pricing := preload("res://Campaign/pricing.gd")
const DETAIL_WIDTH := 400.0

## FRAMES FIRST, because a frame is the purchase everything else hangs off —
## there is no point owning a turret with nothing to bolt it to.
const KINDS := [
	[&"frames", "FRAMES"],
	[&"weapons", "WEAPONS"],
	[&"equipment", "EQUIPMENT"],
	[&"modules", "MODULES"],
]

var ui: Control
var _kind: StringName = &"frames"
var _kind_buttons := {}
var _grid: HFlowContainer
var _detail: VBoxContainer
var _counts: Label
var selected_id: StringName = &""


func setup(owner: Control) -> void:
	ui = owner

	var head := Kit.hbox(10)
	add_child(head)
	head.add_child(Kit.label("TOOLING FABRICATOR", Kit.BRIGHT, Kit.HEADING, true))
	head.add_child(Kit.label("OPEN A LINE ONCE. COPIES ARE BOUGHT IN THE ARMORER.",
		Kit.DIM, Kit.SMALL))
	head.add_child(Kit.fill())
	_counts = Kit.label("", Kit.DIM, Kit.SMALL, true)
	head.add_child(_counts)

	var tabs := Kit.hbox(6)
	add_child(tabs)
	for spec in KINDS:
		var id: StringName = spec[0]
		var b := Kit.button(String(spec[1]), Kit.DIM, Kit.SMALL)
		b.mouse_entered.connect(ui.hover)
		b.pressed.connect(func(): _show_kind(id))
		tabs.add_child(b)
		_kind_buttons[id] = b

	var row := Kit.hbox(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)

	var left := ScrollContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(left)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	left.add_child(_grid)

	var right := ScrollContainer.new()
	right.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(right)
	_detail = Kit.vbox(6)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_detail)


func on_open() -> void:
	_kind = &"frames"
	selected_id = &""


func _show_kind(kind: StringName) -> void:
	_kind = kind
	# NOT KEPT ACROSS TABS. A frame selected on FRAMES has no business filling
	# the detail panel while you are looking at MODULES — the right-hand side
	# would be describing something not on screen.
	selected_id = &""
	ui.play(&"select")
	rebuild()


# ── The grid ─────────────────────────────────────────────────────────────────

func rebuild() -> void:
	if _grid == null:
		push_warning("ToolingPage: rebuild before setup, so the fabricator draws nothing and no line can be opened.")
		return
	Kit.clear(_grid)
	Kit.clear(_detail)
	for id in _kind_buttons:
		var b: Button = _kind_buttons[id]
		b.add_theme_color_override("font_color", Kit.BRIGHT if id == _kind else Kit.DIM)

	var state: CampaignState = ui.state
	if state == null or ui.catalogue == null:
		_grid.add_child(Kit.label("NO CAMPAIGN", Kit.PROBLEM, Kit.HEADING, true))
		return

	var entries := _entries()
	var open_count := 0
	for e in entries:
		if state.is_unlocked(e.id):
			open_count += 1
	_counts.text = "%d / %d OPEN" % [open_count, entries.size()]

	if entries.is_empty():
		_grid.add_child(Kit.label("NOTHING OF THIS KIND IS FOR SALE", Kit.DIM, Kit.SMALL))
		return
	for e in entries:
		_grid.add_child(_card(e))
	if selected_id != &"":
		_build_detail()


## What this tab lists. CHEAPEST TO OPEN FIRST, so the ladder runs one way and
## the next thing you can afford is always near the top.
func _entries() -> Array:
	var cat: ItemCatalogue = ui.catalogue
	var out: Array = []
	if _kind == &"frames":
		for f in cat.chassis:
			if f != null and _Pricing.chassis_for_sale(f):
				out.append(f)
		out.sort_custom(func(a, b): return _Pricing.chassis_unlock(a) < _Pricing.chassis_unlock(b))
		return out
	var want: int = {
		&"weapons": ItemDefinition.Kind.WEAPON,
		&"equipment": ItemDefinition.Kind.EQUIPMENT,
		&"modules": ItemDefinition.Kind.MODULE,
	}.get(_kind, ItemDefinition.Kind.EQUIPMENT)
	for i in cat.items:
		if i != null and i.kind == want and _Pricing.for_sale(i):
			out.append(i)
	out.sort_custom(func(a, b): return _Pricing.item_unlock(a) < _Pricing.item_unlock(b))
	return out


func _card(def) -> Control:
	var state: CampaignState = ui.state
	var is_frame: bool = _kind == &"frames"
	var wide: bool = is_frame or (not is_frame and def.kind == ItemDefinition.Kind.WEAPON)
	var id: StringName = def.id
	var line: int = state.line_state(def)

	var edge: Color = Kit.LINE
	if id == selected_id:
		edge = Kit.BRIGHT
	elif line == CampaignState.Line.AFFORDABLE:
		edge = Kit.MONEY

	var pick := func():
		selected_id = id
		ui.play(&"select")
		rebuild()
	var card := Kit.card(edge, pick, ui.hover, 6.0)
	card.custom_minimum_size = Vector2(160, 118) if wide else Vector2(108, 118)
	card.tooltip_text = def.display_name
	# ALREADY OPEN READS AS DONE, not as unavailable: dimmed, still selectable,
	# still showing what a copy costs. It is the record of what you built
	# towards, and removing it would make the tree look shorter than it is.
	if line == CampaignState.Line.OPEN:
		card.modulate = Color(1, 1, 1, 0.5)
	elif line == CampaignState.Line.BLOCKED:
		card.modulate = Color(1, 1, 1, 0.4)

	var col := Kit.vbox(4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(col)
	var art: Texture2D = Icons.chassis(def, "m") if is_frame else Icons.item(def, "m")
	col.add_child(Kit.icon(art, Kit.BRIGHT, Vector2(96, 44) if wide else Vector2(36, 36)))

	var title := Kit.label(_short(def).to_upper(), Kit.BRIGHT, Kit.BODY, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	col.add_child(title)

	var foot := Kit.hbox(4)
	var price: int = _Pricing.chassis_unlock(def) if is_frame else _Pricing.item_unlock(def)
	match line:
		CampaignState.Line.OPEN:
			foot.add_child(Kit.label("OPEN", Kit.BRIGHT, Kit.SMALL, true))
		CampaignState.Line.BLOCKED:
			foot.add_child(Kit.label("LOCKED", Kit.DIM, Kit.SMALL, true))
		CampaignState.Line.SHORT:
			foot.add_child(Kit.label(str(price), Kit.PROBLEM, Kit.BODY, true))
		CampaignState.Line.AFFORDABLE:
			foot.add_child(Kit.label(str(price), Kit.MONEY, Kit.BODY, true))
	foot.add_child(Kit.fill())
	col.add_child(foot)
	return card


func _short(def) -> String:
	if def.has_method("short_label"):
		return def.short_label()
	return def.display_name


# ── The detail ───────────────────────────────────────────────────────────────

func _build_detail() -> void:
	var cat: ItemCatalogue = ui.catalogue
	var state: CampaignState = ui.state
	var is_frame: bool = _kind == &"frames"
	var def = cat.chassis_def(selected_id) if is_frame else cat.item(selected_id)
	if def == null:
		push_warning("ToolingPage: '%s' is selected but is not in the catalogue, so its detail panel is blank." % selected_id)
		selected_id = &""
		return

	var wide: bool = not is_frame and def.kind == ItemDefinition.Kind.WEAPON
	var art: Texture2D = Icons.chassis(def, "l") if is_frame else Icons.item(def, "l")
	var pic := Kit.icon(art, Kit.BRIGHT,
		Vector2(128, 128) if is_frame else (Vector2(256, 96) if wide else Vector2(96, 96)))
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail.add_child(pic)
	_detail.add_child(Kit.label(def.display_name.to_upper(), Kit.BRIGHT, 24, true))

	# What KIND of thing this is, in the vocabulary the other screens use.
	var band: String = "FRAME · SUPPLY %d" % def.supply if is_frame \
		else "%s · %s LINE" % [Kit.kind_text(def), _Pricing.band_of(def).to_upper()]
	_detail.add_child(Kit.label(band, Kit.DIM, Kit.SMALL))
	if def.description != "":
		_detail.add_child(Kit.text_block(def.description, Kit.DIM, Kit.BODY))
	_detail.add_child(Kit.spacer(0, 6))

	var price: int = _Pricing.chassis_unlock(def) if is_frame else _Pricing.item_unlock(def)
	var per_copy: int = _Pricing.chassis_buy(def) if is_frame else _Pricing.item_buy(def)

	# THE TWO PRICES, TOGETHER AND LABELLED. The decision here is not "can I
	# afford this", it is "is this line worth opening" — and that is only
	# answerable with both numbers side by side.
	var prices := Kit.hbox(8)
	prices.add_child(Kit.label("OPEN", Kit.DIM, Kit.SMALL))
	prices.add_child(Kit.label(str(price), Kit.MONEY, 22, true))
	prices.add_child(Kit.label("THEN", Kit.DIM, Kit.SMALL))
	prices.add_child(Kit.label("%d EACH" % per_copy, Kit.MONEY, Kit.HEADING, true))
	_detail.add_child(prices)
	_detail.add_child(Kit.spacer(0, 6))

	match state.line_state(def):
		CampaignState.Line.OPEN:
			_detail.add_child(Kit.label("LINE OPEN", Kit.BRIGHT, Kit.HEADING, true))
			_detail.add_child(Kit.label(
				"Build it in the %s." % ("FACTORY" if is_frame else "ARMORER"),
				Kit.DIM, Kit.SMALL))
		CampaignState.Line.BLOCKED:
			_detail.add_child(Kit.label("NEEDS ANOTHER LINE FIRST", Kit.DIM, Kit.BODY, true))
			for req in state.missing_unlock_requirements(def):
				var r = cat.item(req)
				if r == null:
					r = cat.chassis_def(req)
				_detail.add_child(Kit.label(
					"- %s" % (r.display_name.to_upper() if r != null else String(req).to_upper()),
					Kit.PROBLEM, Kit.SMALL))
		CampaignState.Line.SHORT:
			_detail.add_child(Kit.label("NEED %d MORE" % (price - state.available()),
				Kit.PROBLEM, Kit.HEADING, true))
		CampaignState.Line.AFFORDABLE:
			var open := Kit.button("OPEN LINE", Kit.BRIGHT, 18)
			open.tooltip_text = "Pay %d once. Each one then costs %d." % [price, per_copy]
			open.mouse_entered.connect(ui.hover)
			open.pressed.connect(func(): _open(def, is_frame))
			_detail.add_child(open)


func _open(def, is_frame: bool) -> void:
	var ok: bool = ui.state.unlock_chassis(def) if is_frame else ui.state.unlock_item(def)
	ui.play(&"select" if ok else &"denied")
	# ledger_changed drives the rebuild, but a REFUSED unlock changes nothing
	# and announces nothing — so redraw here rather than assume it.
	if not ok:
		rebuild()
