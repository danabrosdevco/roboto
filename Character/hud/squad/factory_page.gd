extends VBoxContainer

## One price table — Campaign/pricing.gd. Preloaded rather than named,
## because a new `class_name` is not visible until the editor rescans.
const _Pricing := preload("res://Campaign/pricing.gd")

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
## A frame's real speed lives on its SCENE, as move_speed: base_speed on the
## definition is 1.00 for all six, because it is a multiplier modules scale
## rather than a speed. By path, not class_name — see the note in item_facts.gd.
const _Facts := preload("res://Campaign/item_facts.gd")
## Tops of the three bars. FIXED across the row and generous enough that a frame
## added later still fits inside them: a bar that rescales per card cannot be
## compared with the card beside it, which is the whole reason to draw bars.
const HULL_TOP := 400.0
const SPEED_TOP := 20.0
const SENSOR_TOP := 120.0
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
## Which line's rail is open, or &"" for the row of cards.
var _detail: StringName = &""


func setup(owner_ui) -> void:
	ui = owner_ui
	add_theme_constant_override("separation", 14)


func on_open() -> void:
	_last_built = ""
	# Always onto the row. Opening the manager to find yourself inside one
	# line's rail is the screen remembering something you did not ask it to.
	_detail = &""


func rebuild() -> void:
	_restore_x = _scroll_x
	Kit.clear(self)
	var state: CampaignState = ui.state
	# SAY SO BEFORE ANY OF IT IS OFFERED. Every spending call on this page is
	# refused while the squad is out (Backlog K12) — the refusal is in
	# CampaignState, because a gate that exists only in the UI is not a gate,
	# but a button that silently plays "denied" is a bug as far as the player is
	# concerned. The squad page has carried its own version of this line for a
	# while; the Factory never asked where the squad was at all.
	if ui.in_field():
		add_child(Kit.text_block(
			"IN THE FIELD: THE LINES ARE SHUT. BUILDING, SEATS AND MARKS WAIT FOR BASE",
			Kit.DIM, Kit.SMALL))
	add_child(_hangar(state))

	# ONE LINE, OR ALL OF THEM. The detail is the same page rather than a tab
	# of its own: advancing a line is a thing you do WHILE looking at what you
	# are building, and sending the player somewhere else to do it is the trip
	# this whole system exists to remove.
	if _detail != &"":
		var frame: ChassisDefinition = ui.catalogue.chassis_def(_detail) \
			if ui.catalogue != null else null
		if frame != null:
			add_child(_line_detail(frame))
			return
		_detail = &""   # the frame went away under us; fall back to the row

	var frames := HBoxContainer.new()
	frames.add_theme_constant_override("separation", 14)
	for frame in ui.production_lines():
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
	# `enough` IS ABOUT THE PRICE AND NOTHING ELSE, because the label at the end
	# of this row says which it is. Folding "we are in the field" into it made
	# the button read "NEEDS 1 COMPUTE" with COMPUTE 4 in the header a hand's
	# width away — caught in a render, and a structural check would never have
	# seen it. The field is a separate reason and gets its own words.
	var enough: bool = state.compute_free() >= cost
	# `: bool` spelled out: ui is untyped, so an `and`/`not` on ui.in_field()
	# infers nothing and := is a parse error.
	var afield: bool = ui.in_field()
	# A seat only HOLDS compute, so it can be given back in full — the
	# newest one, and only while it is empty.
	if state.seats_held() > 0:
		var can_free: bool = state.supply_free() >= 1 and not afield
		var remove := Kit.button("REMOVE A SEAT", Kit.DIM)
		remove.disabled = not can_free
		remove.tooltip_text = "Give back a seat you added, for all its compute." if can_free \
			else ("The squad is in the field: seats change at base." if afield \
			else "Every seat has a robot in it: bench one first.")
		remove.mouse_entered.connect(ui.hover)
		remove.pressed.connect(func(): ui.play(&"remove" if state.refund_supply() else &"denied"))
		row.add_child(remove)
		row.add_child(Kit.spacer(10, 0))
	var add := Kit.button("ADD A SEAT", Kit.BRIGHT if (enough and not afield) else Kit.DIM)
	add.disabled = not enough or afield
	# "...and bonus objectives" until 2026-10-26: objectives stopped paying in
	# either currency (Backlog K9) and held Locations started paying compute
	# (K11), so the sentence named the one source that had gone and missed the
	# one that had arrived.
	add.tooltip_text = "One more seat: one more robot can deploy.\nCompute comes from first clears and from the places you hold."
	add.mouse_entered.connect(ui.hover)
	add.pressed.connect(func(): ui.play(&"select" if state.buy_supply() else &"denied"))
	row.add_child(add)
	# THE REASON, IN THE RIGHT ORDER. In the field the price is beside the
	# point, so it does not get mentioned: "NEEDS 1 COMPUTE" under a header
	# reading COMPUTE 4 is the screen telling the player something untrue.
	var why := "NOT IN THE FIELD" if afield \
		else ("HOLDS %d COMPUTE" % cost if enough else "NEEDS %d COMPUTE" % cost)
	var why_colour = Kit.DIM if afield else (Kit.COMPUTE if enough else Kit.PROBLEM)
	row.add_child(Kit.label(why, why_colour, Kit.BODY, true))
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

	# ── THE LINE'S CONTROLS, IN THE CORNER ────
	# On the card rather than behind a click, because advancing a line is the
	# thing this page is FOR and a control you have to go looking for is one
	# nobody finds. MODULE is drawn even while it is locked: a player should
	# learn the keystone exists long before they can afford it.
	col.add_child(_line_corner(frame))

	var art := Kit.icon(Icons.chassis(frame, "l"), Kit.BRIGHT, Vector2(128, 128))
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(art)
	var title := Kit.label(Kit.frame_word(frame), Kit.BRIGHT, 26, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	# NO DESCRIPTION. A paragraph per card was the only thing on these cards whose
	# length varied, so six cards side by side had their bars starting at six
	# different heights and nothing lined up to compare. The badges, the bars and
	# the mount line say the same things in a fixed number of rows.

	# WHAT IT IS, as badges. Every one is a rule over fields the chassis already
	# carries, so a frame added later gets its badges by being defined and
	# nobody has to remember to tick a box. Positives only: a frame with no
	# turret says nothing about turrets.
	col.add_child(_badges(frame))

	# The three figures you choose a frame on. Bars rather than a sentence,
	# because choosing is comparing and "180 HP" against "320 HP" is two numbers
	# to subtract while two bars is a glance. Each scale is FIXED across the row,
	# never per card — a bar scaled to its own value cannot be read against the
	# one beside it.
	col.add_child(Kit.stat_bar("HULL", frame.base_health, frame.base_health, HULL_TOP,
		str(frame.base_health), 52.0, 48.0))
	var speed := _Facts.chassis_speed(frame)
	if speed > 0.0:
		col.add_child(Kit.stat_bar("SPEED", speed, speed, SPEED_TOP, "%.1f" % speed, 52.0, 48.0))
	col.add_child(Kit.stat_bar("SENSOR", frame.base_sensor_range, frame.base_sensor_range,
		SENSOR_TOP, "%d M" % int(round(frame.base_sensor_range)), 52.0, 48.0))

	# What goes on it, named by the MOUNT rather than by the frame's own class —
	# "SMALL ARMS", not "INFANTRY", because infantry is what the frame is and the
	# slot is a pair of hands.
	var mount := _mount_line(frame)
	if mount != "":
		var m := Kit.label(mount, Kit.DIM, Kit.SMALL)
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(m)
	col.add_child(_slot_layout(frame))
	var starting: ItemDefinition = ui.item(frame.starting_weapon_id)
	if starting != null:
		var comes := Kit.label("COMES WITH %s" % _with_article(starting.short_label().to_upper()),
			Kit.BRIGHT, Kit.SMALL)
		comes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		comes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(comes)

	col.add_child(Kit.fill())
	# OPENING A LINE HAPPENS HERE NOW. This used to read "OPEN THIS LINE IN
	# TOOLING" and send the player to a page of its own — a whole screen whose
	# only job was charging for a thing you were already looking at. Tooling is
	# gone and the button is on the card.
	if not ui.state.is_unlocked(frame.id):
		var open_cost: int = _Pricing.chassis_unlock(frame)
		var can_open: bool = state.can_afford(open_cost) \
			and state.unlock_requirements_met(frame)
		var row := Kit.hbox(10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var ob := Kit.button("OPEN LINE", Kit.MONEY if can_open else Kit.PROBLEM, 18)
		ob.disabled = not can_open
		ob.tooltip_text = "Pay once to open the line. Each unit then costs %d." \
			% _Pricing.chassis_buy(frame)
		ob.mouse_entered.connect(ui.hover)
		ob.pressed.connect(func(): _open_production(frame))
		row.add_child(ob)
		row.add_child(Kit.label(str(open_cost), Kit.MONEY, 18, true))
		col.add_child(row)
		if not state.unlock_requirements_met(frame):
			col.add_child(Kit.label("ANOTHER LINE COMES FIRST", Kit.PROBLEM, Kit.SMALL))
		card.modulate = Color(1, 1, 1, 0.75)
		return card
	var price: int = _Pricing.chassis_buy(frame)
	var affordable := state.can_afford(price)
	var buy_row := Kit.hbox(10)
	buy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var build := Kit.button("BUILD", Kit.BRIGHT if affordable else Kit.PROBLEM, 18)
	build.disabled = not affordable
	build.mouse_entered.connect(ui.hover)
	build.pressed.connect(func(): _build(frame))
	buy_row.add_child(build)
	buy_row.add_child(Kit.label(str(price), Kit.MONEY, 18, true))
	# A frame has TWO prices and they are different currencies: resources, and
	# the seats its supply holds — compute is what pays for seats. Amber and
	# blue say which is which without a word of explanation, and it belongs here
	# beside the other price rather than down among the badges, where it read as
	# just another trait.
	buy_row.add_child(Kit.label("%d SEAT%s" % [frame.supply, "" if frame.supply == 1 else "S"],
		Kit.COMPUTE, Kit.SMALL, true))
	col.add_child(buy_row)
	var seat := frame.supply <= state.supply_free()
	var where := Kit.label("JOINS THE SQUAD" if seat else "%s: WAITS ON THE BENCH" % _seat_shortfall(frame.supply),
		Kit.DIM, Kit.SMALL)
	if not affordable:
		where.text = "NEED %d MORE" % (price - state.available())
		where.add_theme_color_override("font_color", Kit.PROBLEM)
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(where)
	return card


# The frame's slots as empty tiles: what you are buying room for.
func _slot_layout(frame: ChassisDefinition) -> Control:
	var row := Kit.hbox(4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	# A frame with no weapon slot shows its built-in instead, which IS the thing
	# in that position: a Mechanic's welder, a Spotter's optics.
	if frame.weapon_slots == 0:
		row.add_child(_tile(frame.built_in, 56))
	# WEP / EQUIP / MOD: three kinds of slot, not five words for them. The mount
	# line directly above already says which kind of weapon it takes, so spelling
	# TURRET or WELDER again on the tile spent a word saying it twice.
	for i in frame.weapon_slots:
		row.add_child(_tile("WEP", 52))
	for i in frame.equipment_slots:
		row.add_child(_tile("EQUIP", 44))
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


## WHAT A FRAME IS, as badges — each one a rule over fields the chassis already
## carries, so nothing is authored twice and a frame added later classifies
## itself. POSITIVES ONLY: a card listing what a frame is NOT is the longest way
## to say nothing.
func _badges(frame: ChassisDefinition) -> Control:
	var words: Array[String] = []
	if frame.turret:
		words.append("TURRET")
	if frame.vehicle:
		words.append("VEHICLE FRAME")
	if not frame.vehicle and not frame.drives and not frame.turret:
		words.append("INFANTRY")
	if frame.built_in == "WELDER" and frame.weapon_replaces_built_in:
		words.append("ARTICULATED ARM")
	# THE DRAYMAN'S BOOM IS AN ARM AND NOT A WELDER, and the distinction is the
	# whole reason it has a built-in word of its own: on "WELDER" the rule below
	# would label a supply truck a MEDIC, because it starts with nothing fitted.
	if frame.built_in == "BOOM":
		words.append("ARTICULATED ARM")
	# A welder it still HAS. The enemy mortar track carries one and starts with
	# the mortar in its place, so it is not a medic.
	if frame.built_in == "WELDER" and frame.starting_weapon_id == &"":
		words.append("MEDIC")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 3)
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	for w in words:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", Kit.box(Kit.FAINT, Color(0, 0, 0, 0), 1, 3.0))
		chip.add_child(Kit.label(w, Kit.BRIGHT, 11))
		flow.add_child(chip)
	return flow


## The kind of mounting a frame offers, named after the MOUNT. "SMALL ARMS" and
## not "INFANTRY": infantry is what the frame is, and the slot is a pair of
## hands — the Soldier card was saying the word twice, once as its class and
## again as its mount.
func _mount_line(frame: ChassisDefinition) -> String:
	if frame.weapon_slots == 0:
		return "BUILT-IN %s" % frame.built_in if frame.built_in != "" else ""
	if frame.turret:
		return "%d X TURRET" % frame.weapon_slots
	if frame.weapon_replaces_built_in and frame.built_in == "WELDER":
		return "%d X ARM" % frame.weapon_slots
	return "%d X SMALL ARMS" % frame.weapon_slots


# ─────────────────────────────────────────────
# PRODUCTION LINES
# ─────────────────────────────────────────────

## The mark badge and the two line controls, along the top of a card.
##
## NO BUTTON ONCE A THING IS DONE. A disabled control reading "MK 2 ADOPTED"
## is the screen talking about itself; the badge beside it already says what
## the line builds. MODULE is the exception while it is locked — it is drawn
## greyed so the keystone is discoverable before it is reachable.
func _line_corner(frame: ChassisDefinition) -> Control:
	var state: CampaignState = ui.state
	var row := Kit.hbox(6)
	var mk := state.mark_of(frame.id)
	# A SHUT LINE HAS NOTHING TO ADVANCE. UPGRADE and MODULE on a card whose
	# only live control is OPEN LINE is three buttons where one applies, and
	# the two dead ones are the louder pair. The mark badge goes too: "MK 0" on
	# a line that builds nothing is a fact about nothing.
	if not state.is_unlocked(frame.id):
		return row
	row.add_child(Kit.label("MK %d" % mk, Kit.BRIGHT, Kit.SMALL, true))
	var mod_id := state.module_of(frame.id)
	if mod_id != &"":
		var mod_def: ItemDefinition = ui.item(mod_id)
		row.add_child(Kit.label("◆ %s" % (mod_def.short_label().to_upper()
			if mod_def != null else String(mod_id).to_upper()), Kit.COMPUTE, Kit.SMALL))
	row.add_child(Kit.fill())

	# NEITHER OF THESE SPENDS ANYTHING. Both open the line's own page, where
	# the whole rail is laid out and the money is committed on a button that
	# says what it is buying.
	#
	# UPGRADE USED TO CHARGE YOU ON THE SPOT, off a card that showed a price
	# and a mark number and nothing else: no way to see what Mk 2 carried
	# until you owned it, and no way to see the rail AT ALL on a Mk 0 line,
	# because the only route to it was the MODULE button and that was locked
	# until the top. The one decision this system asks for was the one thing
	# you could not look at first.
	#
	# AND NEITHER IS DISABLED ANY MORE, which is the other half. LOOKING is
	# always allowed — a line you cannot afford yet is exactly the line you
	# want to read — so the colour carries affordability and the page behind
	# carries the refusal.
	if mk < frame.top_mark():
		var cost: int = _Pricing.mark_buy(frame, mk + 1)
		var up := Kit.button("UPGRADE %d ▸" % cost,
			Kit.MONEY if state.can_afford(cost) else Kit.DIM, Kit.SMALL)
		up.tooltip_text = "See the whole rail. Nothing is spent until you adopt."
		up.mouse_entered.connect(ui.hover)
		up.pressed.connect(func(): _open_line(frame))
		row.add_child(up)
	if mod_id == &"":
		var mcost: int = _Pricing.module_buy(frame)
		var ready: bool = mk >= frame.top_mark() and state.can_afford(mcost)
		var mb := Kit.button("MODULE %d ▸" % mcost, Kit.COMPUTE if ready else Kit.DIM, Kit.SMALL)
		mb.tooltip_text = "Open at Mk %d." % frame.top_mark() if mk < frame.top_mark() \
			else "One module, for the whole line, chosen once."
		mb.mouse_entered.connect(ui.hover)
		mb.pressed.connect(func(): _open_line(frame))
		row.add_child(mb)
	return row


func _advance(frame: ChassisDefinition) -> void:
	var state: CampaignState = ui.state
	var n: int = state.mark_of(frame.id) + 1
	var built: int = _in_service(frame)
	if not state.adopt_mark(frame):
		ui.play(&"denied")
		return
	ui.play(&"select")
	# WHAT IT DID TO THE ROBOTS YOU ALREADY HAVE, said out loud. The whole
	# point of a line upgrade is that it reaches them, and a toast that only
	# said "Mk 2" would leave the player to guess whether it had.
	_last_built = "%s LINE AT MK %d%s" % [Kit.frame_word(frame).to_upper(), n,
		"" if built == 0 else " — %d IN SERVICE REVISED" % built]


func _open_line(frame: ChassisDefinition) -> void:
	ui.play(&"select")
	_detail = frame.id
	rebuild()   # only this page changes; the ledger did not move


func _in_service(frame: ChassisDefinition) -> int:
	var n := 0
	for r in ui.state.roster:
		if r != null and r.chassis_id == frame.id:
			n += 1
	return n


## ONE LINE'S RAIL: where it is, what the next mark costs, and what that does
## to the robots you already have.
##
## THE BARS ARE THE POINT. Kit.stat_bar draws anything beyond `base` in the
## UPGRADE colour, so passing the CURRENT value as base and the NEXT MARK's as
## total shows the gain as a ghost extension on the same bar. A tier whose
## only description is a sentence is a tier the player cannot judge before
## paying for it — and four of the twelve lines progress by tuning alone, so
## for those this is the entire readout.
func _line_detail(frame: ChassisDefinition) -> Control:
	var state: CampaignState = ui.state
	var col := Kit.vbox(10)

	var back := Kit.button("← ALL LINES", Kit.DIM, Kit.SMALL)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.mouse_entered.connect(ui.hover)
	back.pressed.connect(func():
		ui.play(&"select")
		_detail = &""
		rebuild())
	col.add_child(back)

	var head := Kit.hbox(10)
	head.add_child(Kit.icon(Icons.chassis(frame, "m"), Kit.BRIGHT, Vector2(48, 48)))
	var words := Kit.vbox(2)
	words.add_child(Kit.label(Kit.frame_word(frame).to_upper(), Kit.BRIGHT, 24, true))
	var served: int = _in_service(frame)
	words.add_child(Kit.label("%d IN SERVICE%s" % [served,
		"" if served == 0 else " · EVERY ONE REVISED ON ADOPTION"], Kit.DIM, Kit.SMALL))
	head.add_child(words)
	col.add_child(head)

	# WHAT JUST HAPPENED, ON THE PAGE IT HAPPENED ON. rebuild() prints
	# _last_built under the row of all lines and returns before it for a
	# detail, so adopting from here used to confirm itself onto a screen the
	# player was not looking at.
	if _last_built != "":
		col.add_child(Kit.label(_last_built, Kit.BRIGHT, Kit.HEADING, true))

	# ── THE RAIL ──────────────────────────────
	var mk: int = state.mark_of(frame.id)
	var rail := Kit.hbox(8)
	for n in range(0, frame.top_mark() + 1):
		rail.add_child(_mark_step(frame, n, mk))
	col.add_child(rail)

	# ── WHAT THE NEXT ONE DOES ────────────────
	if mk < frame.top_mark():
		var next = frame.mark_spec(mk + 1)
		var now = frame.mark_spec(mk)
		# BOUNDED, AND NOT BECAUSE IT LOOKS NEATER. A stat bar fills the width
		# it is given and this column is the whole screen, so HULL 200 -> 220
		# was drawn as 1800 px of bar with a 90 px ghost on the end: a gain
		# you have to hunt for on a readout that exists to make it obvious.
		# Same width as the rail above it, so the two line up.
		var deltas := Kit.vbox(4)
		deltas.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		deltas.custom_minimum_size.x = 606.0
		deltas.add_child(Kit.label("NEXT MARK", Kit.DIM, Kit.SMALL, true))
		deltas.add_child(_delta_bar("HULL", frame.base_health + now.health_bonus,
			frame.base_health + next.health_bonus, HULL_TOP))
		deltas.add_child(_delta_bar("SENSOR", frame.base_sensor_range + now.sensor_bonus,
			frame.base_sensor_range + next.sensor_bonus, SENSOR_TOP))
		var sp := _Facts.chassis_speed(frame)
		if sp > 0.0:
			deltas.add_child(_delta_bar("SPEED", sp * now.speed_multiplier,
				sp * next.speed_multiplier, SPEED_TOP, 1))
		deltas.add_child(_adopt_row(frame, mk))
		col.add_child(deltas)
	else:
		col.add_child(Kit.label("AT THE TOP OF THE RAIL", Kit.BRIGHT, Kit.SMALL, true))

	# ── THE MODULE ────────────────────────────
	col.add_child(Kit.label("MODULE", Kit.BRIGHT, Kit.HEADING, true))
	var offered: Array[ItemDefinition] = state.modules_for(frame)
	if offered.is_empty():
		# Not currently reachable — every frame takes something — but an empty
		# heading with nothing under it reads as a page that failed to load,
		# and a line with no keystone is a thing the catalogue could produce.
		col.add_child(Kit.label("NOTHING IN THE CATALOGUE FITS THIS FRAME",
			Kit.DIM, Kit.SMALL))
		return col
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for item in offered:
		grid.add_child(_module_card(frame, item))
	col.add_child(grid)
	return col


## THE ONE CONTROL ON THIS SCREEN THAT SPENDS MONEY, and it says what it is
## buying and what that does to the robots you already own.
##
## IT NAMES THE MARK. "UPGRADE 400" on a card told you a price and nothing
## about what arrived for it; "ADOPT MK 2" sits under a rail that shows
## exactly what a Mk 2 carries, which is the whole reason this page is the
## step between the button and the money.
##
## REFUSAL IS A SENTENCE, NOT A GREYED BUTTON. You reached this page
## deliberately, so being told nothing at the end of it is worse than being
## told you are short.
func _adopt_row(frame: ChassisDefinition, mk: int) -> Control:
	var state: CampaignState = ui.state
	var cost: int = _Pricing.mark_buy(frame, mk + 1)
	var can: bool = state.can_afford(cost)
	var served: int = _in_service(frame)
	var row := Kit.hbox(10)
	var go := Kit.button("ADOPT MK %d  %d" % [mk + 1, cost],
		Kit.MONEY if can else Kit.DIM, Kit.BODY)
	go.disabled = not can
	go.mouse_entered.connect(ui.hover)
	go.pressed.connect(func(): _advance(frame))
	row.add_child(go)
	if not can:
		row.add_child(Kit.label("SHORT %d" % (cost - state.available()), Kit.PROBLEM, Kit.SMALL))
	elif served > 0:
		# The whole point of a LINE upgrade is that it reaches what you have.
		row.add_child(Kit.label("REVISES %d IN SERVICE" % served, Kit.BRIGHT, Kit.SMALL))
	else:
		row.add_child(Kit.label("NOTHING IN SERVICE TO REVISE", Kit.DIM, Kit.SMALL))
	return row


## One tier on the rail. Reads the same vocabulary as every other: what it
## builds, and either a price, IN SERVICE, SUPERSEDED or LOCKED.
func _mark_step(frame: ChassisDefinition, n: int, current: int) -> Control:
	var spec = frame.mark_spec(n)
	var edge := Kit.BRIGHT if n == current else (Kit.LINE if n < current else Kit.FAINT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Kit.box(edge, Kit.PANEL, 1, 10.0))
	panel.custom_minimum_size.x = 190.0
	var col := Kit.vbox(4)
	panel.add_child(col)
	col.add_child(Kit.label("MK %d" % n, edge, Kit.SMALL, true))
	if spec != null:
		# EVERY MARK LISTS ITS WHOLE KIT, and what it ADDS is marked with a +.
		#
		# The full list is what makes three panels comparable at a glance —
		# the question is "what does a Mk 2 carry", not "what did the patch
		# notes say". But a list repeated three times with one line different
		# is a spot-the-difference puzzle, so the additions are called out.
		#
		# BY A PREFIX RATHER THAN BY COLOUR. Dimming the carried-over rows was
		# the first version and it read as though they were DISABLED, which is
		# the opposite of true: they are the kit the mark actually has.
		#
		# MK 0 TAKES NO PREFIXES. It is the baseline, so everything on it is
		# new by definition and a column of plus signs says nothing.
		var carried_w: Array = _ids_at(frame, n - 1, "weapon_ids") if n > 0 else []
		for wid in _ids_at(frame, n, "weapon_ids"):
			var w: ItemDefinition = ui.item(wid)
			col.add_child(Kit.label(_kit_line(wid, w, carried_w, n), Kit.BRIGHT, Kit.SMALL))
		var carried_e: Array = _ids_at(frame, n - 1, "equipment_ids") if n > 0 else []
		for eid in _ids_at(frame, n, "equipment_ids"):
			var e: ItemDefinition = ui.item(eid)
			col.add_child(Kit.label(_kit_line(eid, e, carried_e, n), Kit.MONEY, Kit.SMALL))
		if _ids_at(frame, n, "weapon_ids").is_empty() \
				and _ids_at(frame, n, "equipment_ids").is_empty() and n == 0:
			col.add_child(Kit.label(frame.built_in if frame.built_in != "" else "—",
				Kit.DIM, Kit.SMALL))
	col.add_child(Kit.fill())
	var state: CampaignState = ui.state
	var note := "SUPERSEDED" if n < current else ("IN SERVICE" if n == current
		else (str(_Pricing.mark_buy(frame, n)) if n == current + 1 else "LOCKED"))
	col.add_child(Kit.label(note, Kit.BRIGHT if n == current else Kit.DIM, Kit.SMALL))
	return panel


## What one mark carries in one slot group, blanks dropped. `field` is
## "weapon_ids" or "equipment_ids" on the ChassisMark.
##
## RETURNS A FRESH ARRAY EVERY TIME, which _kit_line relies on: it consumes
## entries out of the carried list as it matches them, and handing it the
## resource's own array would empty the saved mark.
func _ids_at(frame: ChassisDefinition, n: int, field: String) -> Array:
	var out: Array = []
	if n < 0:
		return out
	var spec = frame.mark_spec(n)
	if spec == null:
		return out
	for id_value in spec.get(field):
		if id_value != &"":
			out.append(id_value)
	return out


## One kit row: its name, with a + when this mark is what adds it.
##
## MATCHED AS A MULTISET, not with `has`. A mark that goes from one frag to
## two is adding one frag, and a plain membership test would call the second
## one carried-over and show no change at all for something you paid for.
func _kit_line(id_value: StringName, def: ItemDefinition, carried: Array, n: int) -> String:
	var name_text: String = def.short_label().to_upper() if def != null \
		else String(id_value).to_upper()
	if n <= 0:
		return name_text
	if carried.has(id_value):
		carried.erase(id_value)   # consumed, so a second copy reads as new
		return name_text
	return "+ %s" % name_text


## Current value, with the next mark's gain drawn beyond it.
##
## `dp` because SPEED is a number like 6.8 and HULL is a number like 200, and
## one format for both printed the Rover's speed as "7" — a reading that is
## wrong in the only digit that distinguishes one frame from another. The card
## row has always used %.1f for speed; this matches it rather than inventing a
## second convention on the same screen.
func _delta_bar(name: String, now: float, next: float, top: float, dp: int = 0) -> Control:
	var fmt := "%%.%df" % dp
	var reading: String = fmt % now
	if next > now:
		reading = "%s +%s" % [fmt % now, fmt % (next - now)]
	return Kit.stat_bar(name, now, next, top, reading, 64.0, 72.0)


## One module the line could take.
##
## ELIGIBILITY IS NOT TESTED HERE. modules_for only returns what this frame
## takes, so anything reaching this function can go on it — the states left to
## draw are all about the PLAYER's progress rather than the frame's rules:
## fitted, affordable, not researched yet, or not at the top of the rail.
func _module_card(frame: ChassisDefinition, item: ItemDefinition) -> Control:
	var state: CampaignState = ui.state
	var taken: bool = state.module_of(frame.id) == item.id
	var researched: bool = state.is_unlocked(item.id)
	var cost: int = _Pricing.module_buy(frame)
	var ready: bool = researched and state.module_of(frame.id) == &"" \
		and state.mark_of(frame.id) >= frame.top_mark() and state.can_afford(cost)

	var edge := Kit.COMPUTE if taken else (Kit.LINE if ready else Kit.FAINT)
	var pick := func():
		if not ready:
			ui.play(&"denied")
			return
		ui.play(&"fit" if state.adopt_module(frame, item) else &"denied")
	var card := Kit.card(edge, pick, ui.hover, 8.0)
	card.custom_minimum_size.x = 210.0
	var col := Kit.vbox(3)
	card.add_child(col)
	col.add_child(Kit.label(item.display_name.to_upper(),
		Kit.COMPUTE if (taken or ready) else Kit.DIM, Kit.SMALL, true))
	var eff := item.effect_summary()
	if eff != "":
		col.add_child(Kit.label(eff, Kit.BRIGHT if ready or taken else Kit.DIM, Kit.SMALL))
	if taken:
		col.add_child(Kit.label("FITTED", Kit.COMPUTE, Kit.SMALL, true))
	elif not researched:
		# A BUTTON, NOT A STATEMENT. "NOT RESEARCHED" was true while the
		# Tooling page existed to do something about it; with that gone it
		# would be a dead end on the only build decision the system asks for.
		var ucost: int = _Pricing.item_unlock(item)
		var rb := Kit.button("RESEARCH %d" % ucost,
			Kit.MONEY if state.can_afford(ucost) else Kit.PROBLEM, Kit.SMALL)
		rb.disabled = not state.can_afford(ucost)
		rb.tooltip_text = "Opens this module for every line, not just this one."
		rb.mouse_entered.connect(ui.hover)
		rb.pressed.connect(func(): _research(item))
		col.add_child(rb)
	elif state.module_of(frame.id) != &"":
		col.add_child(Kit.label("THIS LINE HAS ONE", Kit.DIM, Kit.SMALL))
	elif state.mark_of(frame.id) < frame.top_mark():
		col.add_child(Kit.label("AT MK %d" % frame.top_mark(), Kit.DIM, Kit.SMALL))
	else:
		col.add_child(Kit.label(str(cost), Kit.MONEY, Kit.SMALL, true))
	return card




func _open_production(frame: ChassisDefinition) -> void:
	if not ui.state.unlock_chassis(frame):
		ui.play(&"denied")
		return
	ui.play(&"select")
	_last_built = "%s LINE OPEN" % Kit.frame_word(frame).to_upper()


## RESEARCH A MODULE FROM THE CARD THAT OFFERS IT.
##
## Opening an item's line was the Tooling fabricator's other job. With that
## page gone there would be no way to research a module at all, and the
## keystone — the one build decision this system asks for — would be
## permanently out of reach. So the module card does it, on the card the
## player is already looking at.
##
## STILL TWO PAYMENTS, NOT ONE. Opening the line is what makes a module
## available to EVERY line; adopting it is what puts it on THIS one. Rolling
## them into a single price would hide the fact that the first one is already
## paid for the next frame that wants it.
func _research(item: ItemDefinition) -> void:
	if not ui.state.unlock_item(item):
		ui.play(&"denied")
		return
	ui.play(&"select")
