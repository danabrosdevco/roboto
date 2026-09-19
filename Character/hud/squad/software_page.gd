extends HBoxContainer

# ─────────────────────────────────────────────
# SOFTWARE — the player's upgrades, run on compute (Campaign/software_tree.gd).
#
# One row per branch, tiers left to right: 1 compute, 2, 3. A program holds its
# compute while installed and gives all of it back when uninstalled, any time,
# so this page is a set of switches rather than a shop. Every program is blank
# for now; the costs, gating and refunds are real.
#
# Compute is also what seats run on (the Factory): the header shows how much is
# free for either.
# ─────────────────────────────────────────────

const Kit := preload("res://Character/hud/squad/ui_kit.gd")
const Programs := preload("res://Campaign/software_tree.gd")
const DETAIL_WIDTH := 360.0
const CARD := Vector2(86, 58)

var ui
var selected_id: StringName = &""

var _left: VBoxContainer
var _detail: VBoxContainer


func setup(owner_ui) -> void:
	ui = owner_ui
	add_theme_constant_override("separation", 22)
	_left = Kit.vbox(10)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_left)
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


func on_open() -> void:
	pass


func rebuild() -> void:
	if Programs.node(selected_id).is_empty():
		selected_id = Programs.nodes()[0]["id"]
	Kit.clear(_left)
	_left.add_child(Kit.label("PROGRAMS HOLD COMPUTE WHILE INSTALLED · UNINSTALL ANY TIME FOR ALL OF IT BACK",
		Kit.DIM, Kit.SMALL))

	# Tier headings over the columns: what each costs, in the compute colour.
	var heads := Kit.hbox(0)
	heads.add_child(Kit.spacer(BRANCH_WIDTH, 0))
	for tier in [1, 2, 3]:
		var slots: int = Programs.TIER_SLOTS[tier]
		var w: float = slots * CARD.x + (slots - 1) * GAP
		var l := Kit.label("TIER %d · %d COMPUTE" % [tier, Programs.TIER_COST[tier]], Kit.COMPUTE, 12, true)
		l.custom_minimum_size = Vector2(w, 0)
		heads.add_child(l)
		heads.add_child(Kit.spacer(TIER_GAP, 0))
	_left.add_child(heads)

	for branch in Programs.BRANCHES:
		_left.add_child(_branch_row(branch))
	_rebuild_detail()


const BRANCH_WIDTH := 124.0
const GAP := 6.0
const TIER_GAP := 16.0


func _branch_row(branch: Dictionary) -> Control:
	var row := Kit.hbox(0)
	var name_col := Kit.vbox(0)
	name_col.custom_minimum_size = Vector2(BRANCH_WIDTH, 0)
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_col.add_child(Kit.label(branch["title"], Kit.BRIGHT, Kit.HEADING, true))
	var about := Kit.text_block(branch["about"], Kit.DIM, 11)
	about.custom_minimum_size = Vector2(BRANCH_WIDTH - 8, 0)
	name_col.add_child(about)
	row.add_child(name_col)
	for tier in [1, 2, 3]:
		var group := Kit.hbox(int(GAP))
		for n in Programs.nodes():
			if n["branch"] == branch["id"] and n["tier"] == tier:
				group.add_child(_card(n))
		row.add_child(group)
		row.add_child(Kit.spacer(TIER_GAP, 0))
	return row


func _card(n: Dictionary) -> Control:
	var state: CampaignState = ui.state
	var installed := state.is_installed(n["id"])
	var block := Programs.install_block(state, n["id"])
	var locked := not installed and block.begins_with("NEEDS A TIER")
	var border := Kit.BRIGHT if n["id"] == selected_id else (Kit.BRIGHT.darkened(0.25) if installed else (Kit.FAINT if locked else Kit.LINE))
	var pick := func():
		selected_id = n["id"]
		ui.play(&"select")
		rebuild()
	var card := Kit.card(border, pick, ui.hover, 5.0)
	card.custom_minimum_size = CARD
	card.tooltip_text = n["title"]
	var col := Kit.vbox(1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(col)
	var code := Kit.label("%d%s" % [n["tier"], String(n["id"]).right(1).to_upper()], Kit.COMPUTE if installed else Kit.DIM, 11, true)
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(code)
	var title := Kit.label(n["title"], Kit.BRIGHT if installed else Kit.DIM, 12, installed)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	col.add_child(title)
	var state_label := Kit.label("INSTALLED" if installed else ("LOCKED" if locked else ""), Kit.BRIGHT if installed else Kit.DIM, 10)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(state_label)
	if locked:
		card.modulate = Color(1, 1, 1, 0.55)
	return card


func _rebuild_detail() -> void:
	Kit.clear(_detail)
	var n := Programs.node(selected_id)
	if n.is_empty():
		return
	var state: CampaignState = ui.state
	var installed := state.is_installed(n["id"])
	_detail.add_child(Kit.label(n["title"], Kit.BRIGHT, 24, true))
	_detail.add_child(Kit.label("%s · TIER %d" % [Programs.branch_title(n["branch"]), n["tier"]], Kit.DIM, Kit.SMALL))
	_detail.add_child(Kit.text_block(n["about"] if n["about"] != "" else "Not written yet: installing it holds the compute and does nothing else.",
		Kit.DIM, Kit.BODY))
	_detail.add_child(Kit.spacer(0, 6))

	var row := Kit.hbox(10)
	if installed:
		var reason := Programs.uninstall_block(state, n["id"])
		var off := Kit.button("UNINSTALL", Kit.BRIGHT if reason == "" else Kit.DIM)
		off.disabled = reason != ""
		off.mouse_entered.connect(ui.hover)
		off.pressed.connect(func(): ui.play(&"remove" if Programs.uninstall(state, n["id"]) else &"denied"))
		row.add_child(off)
		row.add_child(Kit.label("GIVES BACK %d COMPUTE" % n["cost"], Kit.COMPUTE, Kit.BODY, true))
		_detail.add_child(row)
		if reason != "":
			_detail.add_child(Kit.text_block(reason, Kit.PROBLEM, Kit.SMALL))
	else:
		var reason := Programs.install_block(state, n["id"])
		var on := Kit.button("INSTALL", Kit.BRIGHT if reason == "" else Kit.DIM)
		on.disabled = reason != ""
		on.mouse_entered.connect(ui.hover)
		on.pressed.connect(func(): ui.play(&"fit" if Programs.install(state, n["id"]) else &"denied"))
		row.add_child(on)
		row.add_child(Kit.label("HOLDS %d COMPUTE" % n["cost"], Kit.COMPUTE, Kit.BODY, true))
		_detail.add_child(row)
		if reason != "":
			_detail.add_child(Kit.text_block(reason, Kit.PROBLEM, Kit.SMALL))
