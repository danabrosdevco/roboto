extends SceneTree

# ─────────────────────────────────────────────
# SQUAD MANAGER — the three pages, driven the way a player drives them: find
# the card or button by what it says on it, and click it. Every click goes
# through the page's own wiring into CampaignState, so this catches a button
# that looks right and does nothing.
#
# Uses a made-up campaign (no CampaignManager, no save file) so it can never
# touch campaign.json.
# ─────────────────────────────────────────────

const CAT := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const _SOLDIER := preload("res://Character/characters/ai/soldier.gd")
const _Icons := preload("res://Character/hud/icons/icons.gd")

var _fails := 0
var ui: SquadManagerUI
var state: CampaignState


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cat: ItemCatalogue = load(CAT)
	state = CampaignState.new()
	state.armoury = Armoury.new()
	state.catalogue = cat
	state.award(500)
	state.award_compute(1)
	state.supply_cap = 4
	var p := state.player_record
	p.display_name = "PLAYER"
	p.set_chassis(cat.chassis_def(&"soldier"), cat)
	p.weapon_ids[0] = &"m4"
	var b1 := _robot(cat, &"soldier", "Bravo-1", &"shotgun")
	var b2 := _robot(cat, &"soldier", "Bravo-2", &"pistol")
	var b3 := _robot(cat, &"soldier", "Bravo-3", &"")
	var b4 := _robot(cat, &"soldier", "Bravo-4", &"pistol")
	var chaser := _robot(cat, &"chaser", "Chaser-1", &"")
	chaser.benched = true
	var wreck := _robot(cat, &"leaper", "Hopper-1", &"")
	wreck.benched = true
	wreck.status = SoldierRecord.Status.DESTROYED
	wreck.damage = wreck.max_health
	var recl := _robot(cat, &"reclaimer", "Reclaimer-1", &"")
	recl.benched = true
	state.armoury.add(&"m4")
	state.armoury.add(&"frag")

	var s := GDScript.new()
	s.source_code = "extends Node\nvar state\nvar catalogue\nvar in_mission = false\nfunc selected_mission():\n\treturn null\n"
	s.reload()
	var campaign := Node.new()
	campaign.set_script(s)
	campaign.set("state", state)
	campaign.set("catalogue", cat)
	campaign.add_to_group("campaign")
	root.add_child(campaign)
	ui = SquadManagerUI.new()
	root.add_child(ui)
	await process_frame
	ui.open()
	await process_frame
	var squad: Control = ui._pages[&"squad"]

	# ── ICONS ────────────────────────────────────
	_check("icons are baked for every gun, and load",
		_Icons.item(cat.item(&"m4"), "m") != null and _Icons.item(cat.item(&"shotgun"), "s") != null
		and _Icons.item(cat.item(&"pistol"), "l") != null)
	_check("...for every frame", _Icons.chassis(cat.chassis_def(&"chaser"), "l") != null)
	_check("...and for the repair tool", _Icons.item(cat.item(&"repair_tool"), "m") != null)

	# ── SQUAD ────────────────────────────────────
	_check("opens on the squad page, with you selected", ui._tab == &"squad" and squad.visible
		and squad.selected == state.player_record)
	_check("every robot has a card", _card("BRAVO-3") != null and _card("CHASER-1") != null)
	_check("an unarmed robot says so on its card", _says(_card("BRAVO-3"), "NO WEAPON"))
	_check("...an armed one that it is ready", _says(_card("BRAVO-1"), "READY"))
	_check("...and a wreck that it is destroyed", _says(_card("HOPPER-1"), "DESTROYED"))

	# ── TEAMS ────────────────────────────────────
	# A CARD'S KIT IS A WAY IN.
	# Clicking the gear on someone else's card should select them AND open that
	# slot, rather than making you find it again in the panel on the right.
	squad._select(state.player_record, false)
	squad.rebuild()
	await process_frame
	var other := _card("BRAVO-1")
	var tiles: Array = []
	_clickable_tiles(other, tiles)
	_check("the kit on a roster card takes clicks", not tiles.is_empty(), "%d clickable" % tiles.size())
	if not tiles.is_empty():
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		tiles[0].gui_input.emit(press)
		await process_frame
		_check("...and opens that robot on the slot you clicked",
			squad.selected != null and squad.selected.display_name.to_upper().begins_with("BRAVO-1")
			and squad.slot_kind == ItemDefinition.Kind.WEAPON,
			"selected %s, kind %d" % [squad.selected.display_name if squad.selected else "-", squad.slot_kind])

	# The robots on foot are one team until you make more. You are in none: you
	# order them all.
	_check("the squad is one team to start, INFANTRY, with its robots' cards under its name",
		_team_names() == ["INFANTRY"] and _panel_with(_team_section("INFANTRY"), "BRAVO-1") != null)
	_check("...your card stands above the teams, in none of them", _card("PLAYER") != null
		and _panel_with(_team_section("INFANTRY"), "PLAYER") == null)
	_check("...and the benched are on the bench, not in their team", _panel_with(squad._bench, "CHASER-1") != null
		and _panel_with(_team_section("INFANTRY"), "CHASER-1") == null)
	_check("...nothing on a card names a team: where it sits says it", not _says(_card("BRAVO-1"), "INFANTRY"))
	var rover := _robot(cat, &"rover", "Rover-1", &"machine_gun")
	rover.benched = true
	squad.rebuild()
	await process_frame
	_check("a rover joins a team of vehicles, ARMOR, made for it", _team_names() == ["INFANTRY", "ARMOR"])
	_check("...benched, it keeps that team, which says so", _says(_team_section("ARMOR"), "EVERYONE IN THIS TEAM IS ON THE BENCH")
		and _panel_with(squad._bench, "ROVER-1") != null)
	state.roster.erase(rover)
	squad.rebuild()
	_check("...and a team nobody is in any more is gone", _team_names() == ["INFANTRY"])

	# ── DRAG AND DROP ────────────────────────────
	# Through the same calls the cards and targets are wired to for a drag.
	var card := _card("BRAVO-3")
	_click(card)
	_check("clicking a card selects it where it is, so the same press can go on to drag it",
		squad.selected == b3 and is_instance_valid(card) and card.is_inside_tree())
	_check("under the teams, a strip to drop a robot on for a new team",
		_panel_with(squad._teams, "DRAG A ROBOT HERE TO START A NEW TEAM") != null)
	_drop({"kind": &"new"}, b2)
	_check("dropping one there starts TEAM 2 with it", _team_names() == ["INFANTRY", "TEAM 2"]
		and _panel_with(_team_section("TEAM 2"), "BRAVO-2") != null and _panel_with(_team_section("INFANTRY"), "BRAVO-2") == null)
	var t1: StringName = state.teams[0]["id"]
	var t2: StringName = state.teams[1]["id"]
	_check("a robot is not offered back to the team it is in", not _can({"kind": &"team", "id": t2}, b2))
	_check("...any other team takes it", _can({"kind": &"team", "id": t1}, b2))
	_drop({"kind": &"team", "id": t2}, b1)
	_check("dropping one on a team moves it there", b1.team_id == t2 and _panel_with(_team_section("TEAM 2"), "BRAVO-1") != null)
	_check("...and the team says how many are in it", _says(_team_section("TEAM 2"), "2 ROBOTS"))
	_drop({"kind": &"bench"}, b1)
	_check("dropping one on the bench benches it, still in its team", b1.benched and b1.team_id == t2
		and _panel_with(squad._bench, "BRAVO-1") != null and _says(_team_section("TEAM 2"), "1 BENCHED"))
	_check("...which frees its seat", state.supply_free() == 1, str(state.supply_free()))
	_drop({"kind": &"team", "id": t1}, chaser)
	_check("a benched robot dropped on a team comes off the bench into it, taking the seat",
		not chaser.benched and chaser.team_id == t1 and state.supply_free() == 0)
	_check("...with no seat left, no team takes another from the bench", not _can({"kind": &"team", "id": t1}, recl)
		and not _can({"kind": &"new"}, recl))
	_check("...nor a wreck, which has to be rebuilt first", not _can({"kind": &"team", "id": t1}, wreck))
	_check("...and yours is no robot to move: you order every team", not _can({"kind": &"team", "id": t1}, state.player_record)
		and not _can({"kind": &"bench"}, state.player_record))
	# Back as it was, for everything below.
	_drop({"kind": &"bench"}, chaser)
	_drop({"kind": &"team", "id": t1}, b1)
	_drop({"kind": &"team", "id": t1}, b2)
	_check("moving everyone out of a team ends it", _team_names() == ["INFANTRY"] and not b1.benched and chaser.benched,
		str(_team_names()))

	# ── FOLDING AND NAMING ───────────────────────
	_click(_name_edit("INFANTRY").get_parent())
	_check("clicking a team's header folds it: name and count stay, the cards go",
		_team_section("INFANTRY") != null and _says(_team_section("INFANTRY"), "ROBOTS")
		and _panel_with(_team_section("INFANTRY"), "BRAVO-3") == null)
	_click(_name_edit("INFANTRY").get_parent())
	_check("...and again opens it", _panel_with(_team_section("INFANTRY"), "BRAVO-3") != null)
	var edit := _name_edit("INFANTRY")
	edit.text = "rifles"
	edit.text_submitted.emit(edit.text)
	_check("typing a team's name renames it, upper case", state.team_name(t1) == "RIFLES" and _team_section("RIFLES") != null)
	edit = _name_edit("RIFLES")
	edit.text = "   "
	edit.text_submitted.emit(edit.text)
	_check("...a blank name is refused, and the old one stays", state.team_name(t1) == "RIFLES"
		and _name_edit("RIFLES") != null)
	state.rename_team(t1, "INFANTRY")
	squad.rebuild()
	_check("no prices anywhere on the squad page", not _says(squad, str(cat.item(&"m4").cost)))

	_click(_card("BRAVO-3"))
	_check("clicking a card selects it", squad.selected == b3)
	_check("...on its empty weapon slot", squad.slot_kind == ItemDefinition.Kind.WEAPON and squad.slot_index == 0)
	_check("the list under it is what is in stores for that slot", _says(squad._detail, "ANCIENT RIFLE")
		and not _says(squad._detail, "FRAG"))
	_click(_panel_with(squad._detail, "ANCIENT RIFLE"))
	_check("clicking it fits it", b3.weapon_ids[0] == &"m4", str(b3.weapon_ids))
	_check("...out of stores", state.armoury.spare(&"m4") == 0)
	_check("...and the card now reads READY", _says(_card("BRAVO-3"), "READY"))
	_click(_panel_with(squad._detail, "TAKE OFF"))
	_check("TAKE OFF puts it back in stores", b3.weapon_ids[0] == &"" and state.armoury.spare(&"m4") == 1)
	state.fit_item(b3, cat.item(&"m4"), 0)
	_right_click(_panel_with(squad._detail, "RIFLE"))
	_check("right-clicking a slot takes its item off", b3.weapon_ids[0] == &"", str(b3.weapon_ids))

	_click(_card("BRAVO-3"))
	squad.slot_kind = ItemDefinition.Kind.EQUIPMENT
	squad.slot_index = 0
	squad._rebuild_detail()
	_click(_panel_with(squad._detail, "FRAG"))
	_check("gear fits the same way", b3.equipment_ids[0] == &"frag", str(b3.equipment_ids))

	_press(_card("BRAVO-4"), "BENCH")
	_check("BENCH on a card benches it", b4.benched)
	_check("...and frees a seat", state.supply_free() == 1, str(state.supply_free()))
	_press(_card("CHASER-1"), "DEPLOY")
	_check("DEPLOY brings one off the bench into the free seat", not chaser.benched and state.supply_free() == 0)
	_press(_card("BRAVO-4"), "NO SEAT")
	_check("with no seat free, the bench refuses", b4.benched)
	_check("a wreck on the bench has no deploy switch", _button_in(_card("HOPPER-1"), "") == null)

	var before := state.available()
	_click(_card("HOPPER-1"))
	_press(squad._detail, "REBUILD")
	_check("REBUILD brings a wreck back", wreck.status == SoldierRecord.Status.ACTIVE and wreck.damage == 0)
	_check("...for its price", state.available() < before)

	# THE RECLAIMER'S SLOT IS ITS BOOM. Empty, the welder is on it — so an empty
	# slot there is not an unarmed robot, and the slot says what is in it.
	_check("a Reclaimer on its welder is not an unarmed robot", _card("RECLAIMER-1") != null
		and not _says(_card("RECLAIMER-1"), "NO WEAPON"))
	_click(_card("RECLAIMER-1"))
	_check("...its empty slot shows the welder, and is a slot to fill",
		_says(squad._detail, "WELDER") and _says(squad._detail, "TOOL"))

	_click(_card("CHASER-1"))
	_check("a chaser has no weapon slot to pick", _says(squad._detail, "CLAWS"))
	_press(squad._detail, "BUY AT THE ARMORER")
	_check("with nothing in stores for a slot, the button goes to the Armorer",
		ui._tab == &"armorer" and ui._pages[&"armorer"].visible)
	var picked: ItemDefinition = ui.item(ui._pages[&"armorer"].selected_id)
	_check("...already on that kind of gear", picked != null and picked.kind == ItemDefinition.Kind.MODULE,
		str(picked.id if picked != null else null))

	# ── ARMORER ──────────────────────────────────
	var armorer: Control = ui._pages[&"armorer"]
	var shown := 0
	for item in ui.shop_items():
		if _panel_with(armorer._left, item.short_label().to_upper()) != null:
			shown += 1
	_check("the armorer lists everything for sale", shown == ui.shop_items().size(),
		"%d of %d" % [shown, ui.shop_items().size()])
	_click(_panel_with(armorer._left, "FRAG"))
	_check("clicking an item shows it", armorer.selected_id == &"frag" and _says(armorer._detail, "FRAG"))
	_check("...with what it does, in words", _says(armorer._detail, "PER MISSION"))
	var spare := state.armoury.spare(&"frag")
	before = state.available()
	_press(armorer._detail, "BUY")
	_check("BUY puts one in stores", state.armoury.spare(&"frag") == spare + 1)
	_check("...for its price", before - state.available() == cat.item(&"frag").cost)
	_press(armorer._detail, "SELL ONE")
	_check("SELL ONE takes one back out", state.armoury.spare(&"frag") == spare)

	# ── FACTORY ──────────────────────────────────
	ui.show_tab(&"factory")
	var factory: Control = ui._pages[&"factory"]
	var roster := state.roster.size()
	_press(_panel_with(factory, "SOLDIER"), "BUILD")
	_check("BUILD makes a robot", state.roster.size() == roster + 1)
	var built: SoldierRecord = state.roster.back()
	_check("...a soldier comes with its pistol", built.weapon_ids[0] == &"pistol", str(built.weapon_ids))
	_check("...and says where it went", _says(factory, "BUILT"))
	_check("with no seat free it waits on the bench", built.benched)
	var cap := state.supply_cap
	_check("the factory shows your compute beside the resources", ui._compute.visible
		and ui._compute.text == "COMPUTE %d" % state.compute)
	_check("...and what a seat holds on its button row", _says(factory, "HOLDS 1 COMPUTE"))
	_check("with no seat added there is none to remove", _button_in(factory, "REMOVE A SEAT") == null)
	_press(factory, "ADD A SEAT")
	_check("ADD A SEAT puts compute into a seat", state.supply_cap == cap + 1 and state.compute == 0)
	_check("...and says so when there is none left for another", _says(factory, "NEEDS 1 COMPUTE"))
	_press(factory, "REMOVE A SEAT")
	_check("REMOVE A SEAT gives all of it back", state.supply_cap == cap and state.compute == 1)

	# ── SOFTWARE ─────────────────────────────────
	ui.show_tab(&"software")
	var software: Control = ui._pages[&"software"]
	_check("the software page shows compute in the header", ui._compute.visible)
	var blank := 0
	var all_text := PackedStringArray()
	_texts(software._left, all_text)
	for t in all_text:
		if t == "UNWRITTEN":
			blank += 1
	_check("it lists every program, blank for now", blank == 24, "%d cards" % blank)
	_click(_panel_with(software._left, "UNWRITTEN"))
	_check("clicking a program selects it", software.selected_id == &"command_1a", str(software.selected_id))
	_press(software._detail, "INSTALL")
	_check("INSTALL holds its compute", state.is_installed(&"command_1a") and state.compute == 0)
	_check("...and the card says so", _says(software._left, "INSTALLED"))
	_press(software._detail, "UNINSTALL")
	_check("UNINSTALL gives it all back", not state.is_installed(&"command_1a") and state.compute == 1)
	software.selected_id = &"command_2a"
	software.rebuild()
	_check("a tier 2 program says what it needs first", _says(software._detail, "NEEDS A TIER 1"))
	ui.show_tab(&"squad")
	_check("compute is in the header on every page", ui._compute.visible and ui._compute.text == "COMPUTE %d" % state.compute)

	ui.close()
	_check("closing releases the pause", not PauseHold.is_held(&"squad_manager"))
	ui.queue_free()
	campaign.queue_free()
	await process_frame
	print("")
	print("ALL SQUAD MANAGER CHECKS PASS" if _fails == 0 else "%d SQUAD MANAGER CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


func _robot(cat: ItemCatalogue, frame: StringName, name: String, weapon: StringName) -> SoldierRecord:
	var r := SoldierRecord.new()
	r.display_name = name
	r.set_chassis(cat.chassis_def(frame), cat)
	if not r.weapon_ids.is_empty():
		r.weapon_ids[0] = weapon
	r.recompute_stats(cat)
	state.add_soldier(r)
	return r


# ── finding things by what they say ──────────
func _texts(node: Node, out: PackedStringArray) -> void:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	elif node is LineEdit:
		out.append((node as LineEdit).text)
	for c in node.get_children():
		_texts(c, out)


func _says(node: Node, text: String) -> bool:
	if node == null:
		return false
	var all := PackedStringArray()
	_texts(node, all)
	for t in all:
		if t.contains(text):
			return true
	return false


# The nearest clickable block (a PanelContainer) round a label saying `text`.
func _panel_with(node: Node, text: String) -> Control:
	if node == null:
		return null
	if node is Label and (node as Label).text.contains(text):
		var up := node.get_parent()
		while up != null and not (up is PanelContainer):
			up = up.get_parent()
		return up as Control
	for c in node.get_children():
		var found := _panel_with(c, text)
		if found != null:
			return found
	return null


func _label_in(node: Node, text: String) -> Label:
	if node == null:
		return null
	if node is Label and (node as Label).text == text:
		return node
	for c in node.get_children():
		var found := _label_in(c, text)
		if found != null:
			return found
	return null


func _card(robot_name: String) -> Control:
	return _panel_with(ui._pages[&"squad"]._left, robot_name)


func _team_names() -> Array:
	return state.teams.map(func(t: Dictionary) -> String: return t["name"])


# The name field heading a team's section on the squad page.
func _name_edit(team: String, node: Node = null) -> LineEdit:
	if node == null:
		node = ui._pages[&"squad"]._teams
	if node is LineEdit and (node as LineEdit).text == team:
		return node
	for c in node.get_children():
		var found := _name_edit(team, c)
		if found != null:
			return found
	return null


# A team's whole section: the box its name heads.
func _team_section(team: String) -> Control:
	var up: Node = _name_edit(team)
	while up != null and not (up is PanelContainer):
		up = up.get_parent()
	return up as Control


# What letting go of a dragged card over `where` does, and whether it would be
# taken there: the calls the cards and the targets are wired to.
func _drop(where: Dictionary, record: SoldierRecord) -> void:
	var page = ui._pages[&"squad"]
	page._drop_fn(where).call(Vector2.ZERO, {page.DRAG_KEY: record})


func _can(where: Dictionary, record: SoldierRecord) -> bool:
	var page = ui._pages[&"squad"]
	return page._can_drop_fn(where).call(Vector2.ZERO, {page.DRAG_KEY: record})


func _button_in(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and (text == "" or (node as Button).text.begins_with(text)):
		return node
	for c in node.get_children():
		var found := _button_in(c, text)
		if found != null:
			return found
	return null


func _press(node: Node, text: String) -> void:
	var b := _button_in(node, text)
	if b == null:
		_check("(found a '%s' button to press)" % text, false)
		return
	b.pressed.emit()


func _click(target: Control, button: int = MOUSE_BUTTON_LEFT) -> void:
	if target == null:
		_check("(found something to click)", false)
		return
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	target.gui_input.emit(e)


func _right_click(target: Control) -> void:
	_click(target, MOUSE_BUTTON_RIGHT)


# Every kit tile on a card that is wired for clicks, in order.
func _clickable_tiles(node: Node, out: Array) -> void:
	if node == null:
		return
	if node is PanelContainer and (node as Control).mouse_filter == Control.MOUSE_FILTER_STOP \
			and (node as Control).tooltip_text == "EDIT THIS SLOT":
		out.append(node)
	for c in node.get_children():
		_clickable_tiles(c, out)
