extends SceneTree
# BUCKET: frames

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
const _Pricing := preload("res://Campaign/pricing.gd")
## The UI kit, for its motion switch — see the MOTION block in ui_kit.gd.
const Kit := preload("res://Character/hud/squad/ui_kit.gd")

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
	# MOTION OFF. The squad manager counts its numbers up now, and a rolling
	# number is INTERMEDIATE for a third of a second — the two header checks
	# below read `_resources.text` and `_compute.text` directly, and were
	# passing only because neither value happened to change before them. Off,
	# every helper applies its end state at once.
	Kit.motion = false
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
	var b1 := _robot(cat, &"soldier", "Bravo-1", &"m4")
	var b2 := _robot(cat, &"soldier", "Bravo-2", &"m4")
	var b3 := _robot(cat, &"soldier", "Bravo-3", &"")
	var b4 := _robot(cat, &"soldier", "Bravo-4", &"m4")
	var mechanic := _robot(cat, &"mechanic", "Mechanic-1", &"")
	mechanic.benched = true
	var wreck := _robot(cat, &"leaper", "Hopper-1", &"")
	wreck.benched = true
	wreck.status = SoldierRecord.Status.DESTROYED
	wreck.damage = wreck.max_health
	var recl := _robot(cat, &"reclaimer", "Reclaimer-1", &"")
	recl.benched = true
	state.armoury.add(&"m4")
	state.armoury.add(&"frag")
	# OPEN THE LINES FOR THE KIT THIS TEST SHOPS FOR (Phase 3), same reason the
	# soldier line is opened further down: these setups predate the rule.
	# shop_items() hides anything whose fabrication line is shut UNLESS you hold
	# a spare, so the frag added above vanished from the Armorer the moment it
	# was fitted, and `optics` — the catalogue's only MODULE — was never listed
	# at all, which left "BUY AT THE ARMORER" landing on a rifle for a frame
	# with no weapon slot.
	state.grant_unlock(&"frag")
	state.grant_unlock(&"optics")

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
		and _Icons.item(cat.item(&"cluster_launcher"), "l") != null)
	_check("...for every frame", _Icons.chassis(cat.chassis_def(&"mechanic"), "l") != null)
	_check("...and for the repair tool", _Icons.item(cat.item(&"repair_tool"), "m") != null)

	# ── SQUAD ────────────────────────────────────
	_check("opens on the squad page, with you selected", ui._tab == &"squad" and squad.visible
		and squad.selected == state.player_record)
	_check("every robot has a card", _card("BRAVO-3") != null and _card("MECHANIC-1") != null)
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
	# THE KIT ON A CARD IS SHOWN AND NOT TOUCHED.
	#
	# It used to be clickable — "EDIT THIS SLOT" selected that robot and opened
	# the detail pane on the slot you pressed. A loadout belongs to a
	# production line now (docs/briefs/archive/MARK_SYSTEM_SPEC.md), so there is no
	# refitting one robot, and a tile that invited a click would be a control
	# that does nothing. That is worse than one never offered, which is what
	# this now checks.
	var other := _card("BRAVO-1")
	var tiles: Array = []
	_clickable_tiles(other, tiles)
	_check("the kit on a roster card is not clickable", tiles.is_empty(),
		"%d still take clicks" % tiles.size())

	# The robots on foot are one team until you make more, and you are IN it:
	# you lead from inside a team rather than standing above them all, so the
	# debrief can count your kills with the team you went in with.
	_check("the squad is one team to start, INFANTRY, with its robots' cards under its name",
		_team_names() == ["INFANTRY"] and _panel_with(_team_section("INFANTRY"), "BRAVO-1") != null)
	_check("...and your card sits in a team with them, not above the teams", _card("PLAYER") != null
		and _panel_with(_team_section("INFANTRY"), "PLAYER") != null)
	_check("...and the benched are on the bench, not in their team", _panel_with(squad._bench, "MECHANIC-1") != null
		and _panel_with(_team_section("INFANTRY"), "MECHANIC-1") == null)
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
	_drop({"kind": &"team", "id": t1}, mechanic)
	_check("a benched robot dropped on a team comes off the bench into it, taking the seat",
		not mechanic.benched and mechanic.team_id == t1 and state.supply_free() == 0)
	_check("...with no seat left, no team takes another from the bench", not _can({"kind": &"team", "id": t1}, recl)
		and not _can({"kind": &"new"}, recl))
	_check("...nor a wreck, which has to be rebuilt first", not _can({"kind": &"team", "id": t1}, wreck))
	_check("...and yours is no robot to move: you order every team", not _can({"kind": &"team", "id": t1}, state.player_record)
		and not _can({"kind": &"bench"}, state.player_record))
	# Back as it was, for everything below.
	_drop({"kind": &"bench"}, mechanic)
	_drop({"kind": &"team", "id": t1}, b1)
	_drop({"kind": &"team", "id": t1}, b2)
	_check("moving everyone out of a team ends it", _team_names() == ["INFANTRY"] and not b1.benched and mechanic.benched,
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

	# ── NOTHING ON THIS PAGE FITS ANYTHING ────
	#
	# What used to be here was the whole fitting flow: the stores list for the
	# selected slot, clicking a row to fit it, TAKE OFF to return it, and
	# right-clicking a tile to strip it. All of it went when a loadout stopped
	# belonging to a robot and started belonging to its line.
	#
	# THE CHECKS ARE KEPT, INVERTED, rather than deleted. "The squad page
	# cannot change a loadout" is a rule worth a test — if a stores list ever
	# comes back, something has quietly reintroduced per-robot fitting and the
	# Factory is no longer the only place a spec is decided.
	state.fit_item(b3, cat.item(&"m4"), 0)
	squad.rebuild()
	_check("the detail shows what the robot carries", _says(squad._detail, "RIFLE"),
		"a loadout you cannot see is worse than one you cannot change")
	_check("...and says where it came from", _says(squad._detail, "ISSUED BY"))
	_check("there is no stores list to fit from", not _says(squad._detail, "IN STORES"))
	_check("...and nothing to take off with", _panel_with(squad._detail, "TAKE OFF") == null)
	var kit_tiles: Array = []
	_clickable_tiles(squad._detail, kit_tiles)
	_check("...and no slot in the detail takes a click", kit_tiles.is_empty(),
		"%d clickable" % kit_tiles.size())
	_check("the kit itself is untouched by looking at it",
		b3.weapon_ids[0] == &"m4", str(b3.weapon_ids))

	_press(_card("BRAVO-4"), "BENCH")
	_check("BENCH on a card benches it", b4.benched)
	_check("...and frees a seat", state.supply_free() == 1, str(state.supply_free()))
	_press(_card("MECHANIC-1"), "DEPLOY")
	_check("DEPLOY brings one off the bench into the free seat", not mechanic.benched and state.supply_free() == 0)
	_press(_card("BRAVO-4"), "NO SEAT")
	_check("with no seat free, the bench refuses", b4.benched)
	_check("a wreck on the bench has no deploy switch", _button_in(_card("HOPPER-1"), "") == null)

	# ── A WRECK IS SCRAPPED, NOT REPAIRED ───────
	# This used to assert REBUILD, which is now off by default: a DESTROYED
	# frame is destroyed, and a 2x repair that quietly undoes that makes the
	# distinction the squad HUD draws between DOWNED and DESTROYED a lie. The
	# rebuild path still exists and is still covered — see below — it just is
	# not what the card offers unless the campaign opts in.
	var before := state.available()
	var wreck_id := wreck.id
	var expect_back := state.scrap_value(wreck)
	_click(_card("HOPPER-1"))
	_check("a wreck offers SCRAP", _button_in(squad._detail, "SCRAP") != null)
	_check("...and does NOT offer REBUILD by default",
		_button_in(squad._detail, "REBUILD") == null)
	_press(squad._detail, "SCRAP")
	var still_there := false
	for r in state.roster:
		if r.id == wreck_id:
			still_there = true
	_check("SCRAP takes the wreck off the roster", not still_there)
	_check("...and pays a third of the frame back",
		state.available() == before + expect_back,
		"%d -> %d, expected +%d" % [before, state.available(), expect_back])

	# The opt-in path, so turning allow_rebuild back on is covered too.
	# OPEN THE LINE FIRST (Phase 3): recruit() refuses a chassis whose line is
	# shut, and these setups predate that rule.
	state.grant_unlock(&"soldier")
	var wreck2 := state.recruit(state.catalogue.chassis_def(&"soldier"))
	if wreck2 != null:
		wreck2.status = SoldierRecord.Status.DESTROYED
		wreck2.damage = wreck2.max_health
		state.allow_rebuild = true
		squad.rebuild()
		_click(_card(wreck2.display_name.to_upper()))
		var cost_before := state.available()
		_press(squad._detail, "REBUILD")
		_check("with allow_rebuild on, REBUILD is offered and brings a wreck back",
			wreck2.status == SoldierRecord.Status.ACTIVE and wreck2.damage == 0)
		_check("...for its price", state.available() < cost_before)
		state.allow_rebuild = false

	# THE RECLAIMER'S SLOT IS ITS BOOM. Empty, the welder is on it — so an empty
	# slot there is not an unarmed robot, and the slot says what is in it.
	_check("a Reclaimer on its welder is not an unarmed robot", _card("RECLAIMER-1") != null
		and not _says(_card("RECLAIMER-1"), "NO WEAPON"))
	_click(_card("RECLAIMER-1"))
	# ARTICULATED ARM, not "TOOL". The slot is named for what it IS — a mount a
	# later frame could also have — rather than for the welder that happens to be
	# on it, and it matches the mount class the armorer card prints.
	_check("...its empty slot shows the welder, and is a slot to fill",
		_says(squad._detail, "WELDER") and _says(squad._detail, "ARTICULATED ARM"))
	_click(_card("MECHANIC-1"))
	_check("a mechanic has no weapon slot to pick, so it shows its built-in welder",
		_says(squad._detail, "WELDER"))
	# THERE IS NO SHOP LEFT TO SEND ANYONE TO (step 7b). "BUY AT THE ARMORER"
	# existed because buying and fitting were on different pages and something
	# had to carry you between them; a loadout comes from a LINE now, and the
	# player's own gun comes from MEMORY, so the Armorer had no customer left.
	# What has to stay true is that nothing still points at it.
	_check("nothing on the squad page sends you to the Armorer any more",
		_button_in(squad._detail, "BUY AT THE ARMORER") == null)
	_check("...and the Armorer is not a tab", not SquadManagerUI.TABS.has(&"armorer"),
		str(SquadManagerUI.TABS))
	_check("...leaving exactly three", SquadManagerUI.TABS.size() == 3, str(SquadManagerUI.TABS))
	# THE TRANSACTIONS SURVIVE THE PAGE. recover_kit and the campaign seed both
	# move stock, so the armoury is not gone with its shopfront; only the UI
	# that sold out of it is.
	var spare := state.armoury.spare(&"frag")
	state.armoury.add(&"frag")
	_check("stores still take stock with no shop on screen",
		state.armoury.spare(&"frag") == spare + 1)
	before = state.available()
	_check("...and selling one still pays", state.sell_item(cat.item(&"frag"))
		and state.armoury.spare(&"frag") == spare and state.available() > before)

	# ── FACTORY ──────────────────────────────────
	ui.show_tab(&"factory")
	var factory: Control = ui._pages[&"factory"]
	var roster := state.roster.size()
	_press(_panel_with(factory, "SOLDIER"), "BUILD")
	_check("BUILD makes a robot", state.roster.size() == roster + 1)
	var built: SoldierRecord = state.roster.back()
	_check("...a soldier comes with its Ancient Rifle", built.weapon_ids[0] == &"m4", str(built.weapon_ids))
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

	# ── THE UPGRADE IS A PAGE, NOT A PURCHASE ────
	# UPGRADE used to charge you from the card, off a price and a mark number
	# and nothing else. It opens the line's rail now and the money is spent
	# there, on a button that names the mark it is buying.
	#
	# THE SPEND CHECK IS THE POINT OF THIS BLOCK. A one-character slip back to
	# _advance in the corner would restore the old behaviour exactly, and
	# every other check on this page would still pass.
	state.award(5000)
	var purse := state.available()
	var soldier_frame: ChassisDefinition = cat.chassis_def(&"soldier")
	var mk_before: int = state.mark_of(&"soldier")
	_press(_panel_with(factory, "SOLDIER"), "UPGRADE")
	_check("UPGRADE opens the line rather than buying it",
		factory._detail == &"soldier", str(factory._detail))
	_check("...and has spent nothing", state.available() == purse
		and state.mark_of(&"soldier") == mk_before,
		"%d -> %d, mk %d" % [purse, state.available(), state.mark_of(&"soldier")])
	# THE WHOLE RAIL, which is what the page is for: every mark, not just the
	# one you are standing on and the one you are buying.
	for n in range(0, soldier_frame.top_mark() + 1):
		_check("...the rail shows MK %d" % n, _says(factory, "MK %d" % n))
	_check("...with what the next one ADDS marked out", _says(factory, "+ "),
		"a list repeated three times with one line different is a puzzle")
	_check("...and says what adopting would reach", _says(factory, "IN SERVICE"))

	var cost: int = _Pricing.mark_buy(soldier_frame, mk_before + 1)
	_press(factory, "ADOPT MK")
	_check("ADOPT is what spends", state.mark_of(&"soldier") == mk_before + 1
		and state.available() == purse - cost,
		"mk %d, %d spent, %d expected" % [state.mark_of(&"soldier"), purse - state.available(), cost])
	_check("...and it stays on the line it just moved", factory._detail == &"soldier")
	_press(factory, "← ALL LINES")
	_check("...until you leave it", factory._detail == &"")

	# ── MEMORY ───────────────────────────────────
	# Was SOFTWARE. Three tabs over one ledger: the player's own weapons and
	# equipment beside the branches, all on the same hold-and-refund rule.
	ui.show_tab(&"memory")
	var memory: Control = ui._pages[&"memory"]
	_check("the memory page shows compute in the header", ui._compute.visible)
	_check("it opens on WEAPONS", memory.tab == &"weapons", str(memory.tab))
	_check("...with the issued rifle marked ISSUED and no price on it",
		_says(memory._body, "ISSUED") and _button_in(memory._body, "LOAD 0") == null)
	_check("...and the ledger says where the compute is, in numbers",
		memory._ledger.text.contains("FREE OF"), memory._ledger.text)
	_check("...and the card carries the CATALOGUE'S words, not a second copy",
		_says(memory._body, "Antiquated"))
	_press(memory._body, "LOAD 1")
	_check("LOAD holds its compute", state.is_installed(&"carry_bolt") and state.compute == 0)
	_check("...and the card offers to carry it now", _says(memory._body, "CARRY"))
	_press(memory._body, "CARRY")
	_check("CARRY puts it in your hands and takes nothing from stores",
		state.player_record.weapon_ids[0] == &"bolt" and state.armoury.spare(&"bolt") == 0)
	_press(memory._body, "UNLOAD")
	_check("UNLOAD gives it all back", not state.is_installed(&"carry_bolt") and state.compute == 1)
	_check("...and puts the issued rifle back in your hands rather than nothing",
		state.player_record.weapon_ids[0] == CampaignState.ISSUED_WEAPON_ID,
		str(state.player_record.weapon_ids[0]))

	memory._show(&"kit")
	_check("EQUIPMENT counts the slots on the same line, not a second one",
		memory._ledger.text.contains("SLOTS CARRIED"), memory._ledger.text)
	_check("...and the free Frag is there, issued", _says(memory._body, "ISSUED"))

	memory._show(&"upgrades")
	var blank := 0
	var all_text := PackedStringArray()
	_texts(memory._body, all_text)
	for t in all_text:
		if t == "UNWRITTEN":
			blank += 1
	_check("UPGRADES lists every program, blank for now", blank == 24, "%d rows" % blank)
	_check("...with tier 2 shut until something stands under it",
		_button_in(memory._body, "LOAD 2").disabled)
	_press(memory._body, "LOAD 1")
	_check("LOAD holds its compute", state.is_installed(&"command_1a") and state.compute == 0)
	_press(memory._body, "UNLOAD")
	_check("UNLOAD gives it all back", not state.is_installed(&"command_1a") and state.compute == 1)
	ui.show_tab(&"squad")
	_check("compute is in the header on every page", ui._compute.visible and ui._compute.text == "COMPUTE %d" % state.compute)

	# ── MOTION ───────────────────────────────────
	# THE ONE THING A SCREENSHOT CANNOT SHOW. Every shot tool runs with
	# Kit.motion off so a grab cannot catch a card mid-fade, which means
	# nothing in the repo would notice if the entrance silently stopped
	# animating — a no-op looks exactly like a finished animation one frame
	# later. So this turns it on, opens the screen, and asks the cards.
	#
	# THIS CHECK ALREADY EARNED ITS KEEP. Every tween here was dead the first
	# time it ran: the screen holds a PauseHold, and bound tweens did not
	# advance under it even with PROCESS_MODE_ALWAYS and can_process() true.
	# ui_kit.gd sets TWEEN_PAUSE_PROCESS on all of them now. Nothing else in
	# the project would have caught that — in the game it looks like a screen
	# that simply never appears.
	Kit.motion = true
	ui.open()
	var page: Control = ui._pages[&"squad"]
	# WAITED FOR, NOT TIMED. A --script run has no frame cap and the frame
	# that builds a page is an expensive one, so a fixed 50 ms sample landed
	# inside it with every card still at zero — a working animation reported
	# as broken. This waits for the first card to actually start, then looks.
	var waited := 0
	while waited < 120 and _panels_in(page)[0].modulate.a <= 0.0:
		await process_frame
		waited += 1
	var alphas := {}
	for arriving in _panels_in(page):
		alphas[snappedf(arriving.modulate.a, 0.01)] = true
	_check("the cards arrive one after another, not all at once",
		alphas.size() > 1, "%d distinct alpha(s) once the first one moved" % alphas.size())
	# AND THEY ALL FINISH. A stagger that leaves a card at 0.4 forever is a
	# card you cannot read, and it would look like a rendering bug.
	await create_timer(0.80).timeout
	var unfinished := 0
	for settled in _panels_in(page):
		if settled.modulate.a < 0.999:
			unfinished += 1
	_check("...and every one of them finishes", unfinished == 0,
		"%d still faded 0.8 s in" % unfinished)
	# OFF AGAIN before anything else reads a label: a roll is intermediate.
	Kit.motion = false

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


## Every outermost PanelContainer under a node — the same set Kit.stagger
## animates, found the same way, so the two cannot drift apart.
func _panels_in(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is PanelContainer:
			out.append(c)
			continue
		out.append_array(_panels_in(c))
	return out
