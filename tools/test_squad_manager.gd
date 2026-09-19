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
	var wreck := _robot(cat, &"hopper", "Hopper-1", &"")
	wreck.benched = true
	wreck.status = SoldierRecord.Status.DESTROYED
	wreck.damage = wreck.max_health
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

	# ── NAME ─────────────────────────────────────
	ui.rename_squad("  hammer  ")
	_check("renaming the squad sticks, upper case", state.squad_name == "HAMMER")

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


func _card(robot_name: String) -> Control:
	return _panel_with(ui._pages[&"squad"]._left, robot_name)


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
