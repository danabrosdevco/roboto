extends VBoxContainer

# ─────────────────────────────────────────────
# FACTORY — build new robots, and add seats to the squad.
#
# HANGAR along the top: the seats (supply), how many are taken, and the thing
# COMPUTE buys here, another seat. (The header shows compute on every page;
# Software is the other place it goes.)
#
# Under it, one card per frame you can build: its picture, what it is for, the
# slots it comes with, its price and a BUILD button that says where the new
# robot will go — into the squad if a seat is free, onto the bench if not.
# Building is never blocked by seats, only fielding is.
# ─────────────────────────────────────────────

const Kit := preload("res://Character/hud/squad/ui_kit.gd")
const Icons := preload("res://Character/hud/icons/icons.gd")

## Every card the same width, so the row reads as one object however many
## frames are unlocked — and so a card is never squeezed to fit.
const CARD_WIDTH: float = 300.0
## Pixels per wheel notch along the row: about one card.
const WHEEL_STEP: int = 320

var ui
## What the last BUILD made, said under the cards until the next rebuild of
## something else.
var _last_built := ""
## Where along the row you were. Building a frame rebuilds this page from
## scratch, and a row that jumps back to the left every time loses your place
## right after the click that needed it.
var _scroll_x := 0
var _restore_x := 0


func setup(owner_ui) -> void:
	ui = owner_ui
	add_theme_constant_override("separation", 14)


func on_open() -> void:
	_last_built = ""


func rebuild() -> void:
	_restore_x = _scroll_x
	Kit.clear(self)
	var state: CampaignState = ui.state
	add_child(_hangar(state))

	var frames := HBoxContainer.new()
	frames.add_theme_constant_override("separation", 14)
	for frame in ui.buildable_frames():
		frames.add_child(_frame_card(frame))
	add_child(_scroller(frames))

	if _last_built != "":
		add_child(Kit.label(_last_built, Kit.BRIGHT, Kit.HEADING, true))


# A row you run along, rather than a row that runs off the screen. Every frame
# built so far fitted across; the sixth did not, and a row that does not fit is
# one with a card cut in half at the edge and no way to reach it. The HANGAR
# strip stays above it, so the seats and their buttons never scroll away — and
# with the row at its left end, the first card lines up under them.
func _scroller(row: Control) -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	# The wheel moves it sideways. There is nothing to scroll downward here, and
	# a wheel that does nothing reads as a page that is stuck.
	scroll.gui_input.connect(func(event: InputEvent) -> void: _wheel(scroll, event))
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(row)
	var bar := scroll.get_h_scroll_bar()
	bar.value_changed.connect(func(v: float) -> void: _scroll_x = int(v))
	# Put the row back where it was — but only once the bar knows how far it
	# reaches. Set any earlier and scroll_horizontal clamps to a range the
	# freshly built row does not have yet, which is the same as not setting it.
	bar.changed.connect(func() -> void:
		if _restore_x > 0:
			scroll.scroll_horizontal = _restore_x
			_restore_x = 0)
	return scroll


func _wheel(scroll: ScrollContainer, event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return   # not a wheel notch
	var step := 0
	match button.button_index:
		MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
			step = 1
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
			step = -1
		_:
			return   # a click, not the wheel: leave it for the cards
	scroll.scroll_horizontal += step * WHEEL_STEP
	scroll.accept_event()


func _hangar(state: CampaignState) -> Control:
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", Kit.box(Kit.LINE, Kit.PANEL, 1, 10.0))
	var row := Kit.hbox(12)
	strip.add_child(row)
	row.add_child(Kit.label("HANGAR", Kit.BRIGHT, 20, true))
	row.add_child(Kit.seats(state.supply_used(), state.supply_cap))
	var free := state.supply_free()
	row.add_child(Kit.label("%d SEATS · %s" % [state.supply_cap,
		"%d FREE" % free if free > 0 else "ALL IN USE"], Kit.DIM, Kit.BODY))
	row.add_child(Kit.fill())
	# The action and its price, the same shape as BUILD 50 below: what you
	# HAVE is in the header beside the resources, not in this row, where
	# "COMPUTE 2 [+1 SEAT] 1 COMPUTE" read as three numbers about one thing.
	var cost := CampaignState.SUPPLY_COMPUTE_COST
	var enough := state.compute_free() >= cost
	# A seat only HOLDS compute, so it can be given back in full — the
	# newest one, and only while it is empty.
	if state.seats_held() > 0:
		var can_free := state.supply_free() >= 1
		var remove := Kit.button("REMOVE A SEAT", Kit.DIM)
		remove.disabled = not can_free
		remove.tooltip_text = "Give back a seat you added, for all its compute." if can_free \
			else "Every seat has a robot in it: bench one first."
		remove.mouse_entered.connect(ui.hover)
		remove.pressed.connect(func(): ui.play(&"remove" if state.refund_supply() else &"denied"))
		row.add_child(remove)
		row.add_child(Kit.spacer(10, 0))
	var add := Kit.button("ADD A SEAT", Kit.BRIGHT if enough else Kit.DIM)
	add.disabled = not enough
	add.tooltip_text = "One more seat: one more robot can deploy.\nCompute comes from first clears and bonus objectives."
	add.mouse_entered.connect(ui.hover)
	add.pressed.connect(func(): ui.play(&"select" if state.buy_supply() else &"denied"))
	row.add_child(add)
	row.add_child(Kit.label("HOLDS %d COMPUTE" % cost if enough else "NEEDS %d COMPUTE" % cost,
		Kit.COMPUTE if enough else Kit.PROBLEM, Kit.BODY, true))
	return strip


func _frame_card(frame: ChassisDefinition) -> Control:
	var state: CampaignState = ui.state
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Kit.box(Kit.LINE, Kit.PANEL, 1, 12.0))
	# Fixed width, not EXPAND_FILL: inside the scroller the row is as wide as
	# its cards, and expanding ones would stretch to the viewport and never let
	# it scroll.
	card.size_flags_horizontal = Control.SIZE_FILL
	card.custom_minimum_size.x = CARD_WIDTH
	var col := Kit.vbox(8)
	card.add_child(col)

	var art := Kit.icon(Icons.chassis(frame, "l"), Kit.BRIGHT, Vector2(128, 128))
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(art)
	var title := Kit.label(Kit.frame_word(frame), Kit.BRIGHT, 26, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	if frame.description != "":
		var about := Kit.text_block(frame.description, Kit.DIM, Kit.SMALL)
		about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(about)

	col.add_child(_slot_layout(frame))
	var facts := PackedStringArray(["%d HP" % frame.base_health])
	# Every frame took one seat until the rover; say so when it is more.
	if frame.supply > 1:
		facts.append("TAKES %d SEATS" % frame.supply)
	var starting: ItemDefinition = ui.item(frame.starting_weapon_id)
	if starting != null:
		facts.append("COMES WITH %s" % _with_article(starting.short_label().to_upper()))
	var fact_label := Kit.label(" · ".join(facts), Kit.BRIGHT, Kit.BODY)
	fact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(fact_label)

	col.add_child(Kit.fill())
	# A frame an operation unlocks waits for it: beat the mission where you
	# first meet them, and the factory can build them.
	var locked: MissionDefinition = ui.locked_by(frame.id)
	if locked != null:
		var lock := Kit.label("LOCKED · CLEAR %s" % locked.display_name.to_upper(), Kit.DIM, Kit.SMALL, true)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(lock)
		card.modulate = Color(1, 1, 1, 0.6)
		return card
	var affordable := state.can_afford(frame.cost)
	var buy_row := Kit.hbox(10)
	buy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var build := Kit.button("BUILD", Kit.BRIGHT if affordable else Kit.PROBLEM, 18)
	build.disabled = not affordable
	build.mouse_entered.connect(ui.hover)
	build.pressed.connect(func(): _build(frame))
	buy_row.add_child(build)
	buy_row.add_child(Kit.label(str(frame.cost), Kit.MONEY, 18, true))
	col.add_child(buy_row)
	var seat := frame.supply <= state.supply_free()
	var where := Kit.label("JOINS THE SQUAD" if seat else "%s: WAITS ON THE BENCH" % _seat_shortfall(frame.supply),
		Kit.DIM, Kit.SMALL)
	if not affordable:
		where.text = "NEED %d MORE" % (frame.cost - state.available())
		where.add_theme_color_override("font_color", Kit.PROBLEM)
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(where)
	return card


# The frame's slots as empty tiles: what you are buying room for.
func _slot_layout(frame: ChassisDefinition) -> Control:
	var row := Kit.hbox(4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if frame.weapon_slots == 0:
		row.add_child(_tile(frame.built_in, 52))
	for i in frame.weapon_slots:
		var what := "TURRET" if frame.turret else "GUN"
		if frame.weapon_replaces_built_in:
			what = frame.built_in   # comes with it, and the slot can swap it out
		row.add_child(_tile(what, 64 if frame.turret else 52))
	for i in frame.equipment_slots:
		row.add_child(_tile("GEAR", 38))
	for i in frame.module_slots:
		row.add_child(_tile("MOD", 38))
	return row


func _tile(text: String, width: float) -> Control:
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", Kit.box(Kit.FAINT, Color(0, 0, 0, 0.25), 1, 2.0))
	tile.custom_minimum_size = Vector2(width, 26)
	var l := Kit.label(text, Kit.DIM, 11)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.add_child(l)
	return tile


func _build(frame: ChassisDefinition) -> void:
	var record: SoldierRecord = ui.state.recruit(frame)
	if record == null:
		ui.play(&"denied")
		return
	ui.play(&"fit")
	# Which team it went into, since that is the one it will take orders with.
	_last_built = "%s BUILT · %s" % [record.display_name.to_upper(),
		"ON THE BENCH: %s" % _seat_shortfall(frame.supply) if record.benched
			else "JOINED %s" % ui.state.team_name(record.team_id)]
	rebuild()


# "A PISTOL", "AN MG". An initialism is said letter by letter, so it takes the
# article of its first letter's name: "an M-G", "a G-L".
static func _with_article(word: String) -> String:
	if word == "":
		return word
	var sounds_like_a_vowel := "AEFHILMNORSX" if word.length() <= 3 else "AEIOU"
	return ("AN %s" if sounds_like_a_vowel.contains(word[0]) else "A %s") % word


# Why it waits on the bench. "No free seat" is wrong for a two-seat frame when
# one seat is free.
static func _seat_shortfall(seats: int) -> String:
	return "NO FREE SEAT" if seats <= 1 else "NEEDS %d FREE SEATS" % seats
