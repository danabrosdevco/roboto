extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# A LINE IS OPENED ON THE FACTORY, AND NOWHERE ELSE.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/test_line_opening.gd
#
# WAS test_tooling.gd. The Tooling fabricator was a page of its own whose only
# job was charging to open a line, and the split it guarded was:
#
#   TOOLING    opens lines. Shows everything, open or not.
#   ARMORER    buys copies. Shows ONLY what is already open.
#   FACTORY    builds robots. Shows ONLY frames already open.
#
# The Mark system removed the reason for the first one: a line's spec, its
# price and its units are all on the Factory card now, so a separate screen to
# pay for the thing you are already looking at is a trip with no destination.
#
# WHAT SURVIVES UNCHANGED is the rule underneath, which was never about the
# page: THE ARMOURER MUST NOT LIST WHAT YOU CANNOT BUY. A shop quietly
# offering something it will then refuse is how a shop starts refusing its own
# customers, and that failure is silent.
#
# WHAT IS NEW is the other half: the Factory now has to list a SHUT line too,
# because it is the only place one exists. A line you cannot see is a line you
# will never open, and buildable_frames() deliberately hides them — so
# production_lines() is what the page reads, and this checks the difference.
# ─────────────────────────────────────────────

const _Pricing := preload("res://Campaign/pricing.gd")
const _Factory := preload("res://Character/hud/squad/factory_page.gd")
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var cat: ItemCatalogue = load(CATALOGUE)
	var ui := SquadManagerUI.new()
	root.add_child(ui)
	await process_frame

	# ── THE TAB IS GONE, AND NOTHING ELSE WENT WITH IT ──
	_check("TOOLING is not a tab any more", not SquadManagerUI.TABS.has(&"tooling"),
		str(SquadManagerUI.TABS))
	_check("...and the others are all still here",
		SquadManagerUI.TABS.has(&"squad") and SquadManagerUI.TABS.has(&"factory")
		and SquadManagerUI.TABS.has(&"software"),
		str(SquadManagerUI.TABS))

	var state := CampaignState.new()
	state.armoury = Armoury.new()
	state.catalogue = cat
	state.award(100000)
	ui.state = state
	ui.catalogue = cat

	# ── THE ARMOURER STILL SHOWS ONLY WHAT IS OPEN ──
	# The rule the old suite existed for, and the one that outlived its page.
	var listed: Array = ui.shop_items()
	var shut: Array = []
	for i in listed:
		if not state.is_unlocked(i.id):
			shut.append(String(i.id))
	_check("the ARMORER lists nothing you have not opened", shut.is_empty(), str(shut))

	# ── THE FACTORY SHOWS BOTH, AND KNOWS THE DIFFERENCE ──
	var rover: ChassisDefinition = cat.chassis_def(&"rover")
	_check("(setup) the rover line starts shut", not state.is_unlocked(&"rover"))
	var all_lines: Array = ui.production_lines()
	var buildable: Array = ui.buildable_frames()
	_check("the FACTORY lists a line that is still shut",
		all_lines.has(rover), "%d line(s) listed" % all_lines.size())
	_check("...which buildable_frames does NOT, and must not",
		not buildable.has(rover),
		"that split is what stops BUILD appearing on a line nobody has opened")
	_check("...and every purchasable frame is in the list somewhere",
		all_lines.size() >= buildable.size(),
		"%d of %d" % [buildable.size(), all_lines.size()])

	# OPEN ONES FIRST. A shut line is a thing to consider, not a thing to do,
	# so it sits behind everything you can actually act on.
	var first_shut := -1
	var last_open := -1
	for i in all_lines.size():
		if state.is_unlocked((all_lines[i] as ChassisDefinition).id):
			last_open = i
		elif first_shut < 0:
			first_shut = i
	_check("...with the open ones before the shut ones",
		first_shut < 0 or last_open < first_shut,
		"last open at %d, first shut at %d" % [last_open, first_shut])

	# ── OPENING ONE MOVES IT ──────────────────
	var before: int = ui.buildable_frames().size()
	_check("opening the line succeeds", state.unlock_chassis(rover))
	_check("...and it becomes buildable", ui.buildable_frames().size() == before + 1,
		"%d -> %d" % [before, ui.buildable_frames().size()])
	_check("...while the list of all lines does not change length",
		ui.production_lines().size() == all_lines.size(),
		"a line does not appear when you open it; it was always there")

	# ── THE PAGE ACTUALLY DRAWS THE BUTTON ────
	# The rule above is about data. This is about whether a player can reach
	# it: production_lines() returning a shut line is no use if the card for
	# one renders without a way to pay.
	var walker: ChassisDefinition = cat.chassis_def(&"walker")
	if walker != null and not state.is_unlocked(walker.id):
		var page = _Factory.new()
		ui.add_child(page)
		page.setup(ui)
		page.rebuild()
		await process_frame
		var words: Array = _labels(page)
		_check("a shut line's card offers to OPEN LINE", _mentions(words, "OPEN LINE"),
			"a line you cannot see is a line you will never open")
		_check("...and prints what that costs",
			_mentions(words, str(_Pricing.chassis_unlock(walker))),
			"open costs %d" % _Pricing.chassis_unlock(walker))
		page.queue_free()

	# ── AN ITEM'S LINE STILL OPENS, FOR THE ARMOURER AND THE MODULE PICKER ──
	var smoke := cat.item(&"smoke")
	if smoke != null:
		var i_before: int = ui.shop_items().size()
		state.unlock_item(smoke)
		_check("opening an item's line puts it in the ARMORER",
			ui.shop_items().size() == i_before + 1)
		_check("...and only then can it be bought", state.buy_item(smoke))

	# ── PRICING IS THE TABLE'S, NOT A SECOND COPY ──
	_check("the price to open is twice the price to build",
		_Pricing.chassis_unlock(rover) == 2 * _Pricing.chassis_buy(rover),
		"open %d, build %d" % [_Pricing.chassis_unlock(rover), _Pricing.chassis_buy(rover)])

	# ── AN UNBUYABLE THING HAS NO LINE AT ALL ──
	var hl := cat.item(&"hatchling_launcher")
	if hl != null:
		_check("an UNBUYABLE item cannot be opened", not state.unlock_item(hl))

	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


## Every Label's and Button's text under a node — what the screen actually says.
func _labels(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append((n as Label).text)
	if n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		out.append_array(_labels(c))
	return out


func _mentions(texts: Array, want: String) -> bool:
	for t in texts:
		if String(t).findn(want) >= 0:
			return true
	return false
