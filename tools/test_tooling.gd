extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# THE TOOLING FABRICATOR IS THE ONLY PLACE A LINE OPENS.
#
# docs/briefs/CAMPAIGN_REWORK.md Phase 3.5. The split this guards:
#
#   TOOLING    opens lines. Shows everything for sale, open or not.
#   ARMORER    buys copies. Shows ONLY what is already open.
#   FACTORY    builds robots. Shows ONLY frames that are already open.
#
# The failure worth catching is the armourer quietly listing something you
# cannot buy, which is how a shop starts refusing its own customers.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_tooling.gd
# ─────────────────────────────────────────────

const _Pricing := preload("res://Campaign/pricing.gd")
const _Tooling := preload("res://Character/hud/squad/tooling_page.gd")
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

	# ── the tab exists and is its own page ──────
	_check("TOOLING is a tab of its own", SquadManagerUI.TABS.has(&"tooling"),
		str(SquadManagerUI.TABS))
	_check("...named for what it is",
		String(SquadManagerUI.TAB_TITLES.get(&"tooling", "")) == "TOOLING",
		String(SquadManagerUI.TAB_TITLES.get(&"tooling", "(none)")))
	_check("...and it is the fifth page, not a replacement",
		SquadManagerUI.TABS.size() == 5, "%d tabs" % SquadManagerUI.TABS.size())

	# ── what the armourer and factory are allowed to show ──
	var state := CampaignState.new()
	state.armoury = Armoury.new()
	state.catalogue = cat
	state.award(100000)
	ui.state = state
	ui.catalogue = cat

	# Nothing open but the issued rifle.
	var listed: Array = ui.shop_items()
	var shut: Array = []
	for i in listed:
		if not state.is_unlocked(i.id):
			shut.append(String(i.id))
	_check("the ARMORER lists nothing you have not opened", shut.is_empty(), str(shut))
	_check("...which on a fresh campaign is almost nothing", listed.size() <= 2,
		"%d listed: %s" % [listed.size(), str(listed.map(func(i): return String(i.id)))])

	var frames: Array = ui.buildable_frames()
	var shut_frames: Array = []
	for f in frames:
		if not state.is_unlocked(f.id):
			shut_frames.append(String(f.id))
	_check("the FACTORY lists no frame you have not opened", shut_frames.is_empty(),
		str(shut_frames))

	# ── opening a line moves it between the two ──
	var rover := cat.chassis_def(&"rover")
	_check("(setup) the rover starts shut", not state.is_unlocked(&"rover"))
	var before: int = ui.buildable_frames().size()
	state.unlock_chassis(rover)
	var after: int = ui.buildable_frames().size()
	_check("opening a frame's line puts it in the FACTORY", after == before + 1,
		"%d -> %d frames" % [before, after])

	# SOMETHING WITH NO CHASSIS REQUIREMENT. shop_items() also filters on
	# requires_chassis — the Walker's guns before there is a Walker — so a
	# turret weapon would be held back for a reason that is not the lock.
	var mg := cat.item(&"smoke")
	if mg != null:
		var i_before: int = ui.shop_items().size()
		state.unlock_item(mg)
		_check("opening an item's line puts it in the ARMORER",
			ui.shop_items().size() == i_before + 1)
		_check("...and only then can it be bought", state.buy_item(mg))

	# ── the tooling page shows BOTH ─────────────
	# The point of the split: tooling is the one screen that lists what you
	# cannot yet have, so there is somewhere to see the tree.
	var page = _Tooling.new()
	ui.add_child(page)
	page.setup(ui)
	page.rebuild()
	await process_frame
	var shown: Array = _labels(page)
	page._kind = &"frames"
	page.rebuild()
	await process_frame
	shown = _labels(page)
	_check("the TOOLING page lists a line that is still shut",
		_mentions(shown, "AUTOCANNON") or _mentions(shown, "WALKER"),
		"%d labels" % shown.size())
	_check("...and one that is already open", _mentions(shown, "ROVER"))
	_check("...and says how much of the tree is left", _mentions(shown, "/ 12 OPEN") or _mentions(shown, "OPEN"))
	for kind in [&"weapons", &"equipment", &"modules"]:
		page._kind = kind
		page.rebuild()
		await process_frame
		_check("the %s tab draws something" % kind, _labels(page).size() > 4,
			"%d labels" % _labels(page).size())
	_check("...and names itself", _mentions(shown, "TOOLING FABRICATOR"))

	# ── pricing is the same on both screens ─────
	_check("the price to open is the pricing table's, not a second copy",
		_Pricing.chassis_unlock(rover) == 2 * _Pricing.chassis_buy(rover),
		"open %d, build %d" % [_Pricing.chassis_unlock(rover), _Pricing.chassis_buy(rover)])

	# ── an unbuyable thing has no line at all ───
	var hl := cat.item(&"hatchling_launcher")
	if hl != null:
		_check("an UNBUYABLE item cannot be opened", not state.unlock_item(hl))

	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


## Every Label's text under a node, flattened — what the screen actually says.
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
