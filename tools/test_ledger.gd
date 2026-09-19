extends SceneTree

# ─────────────────────────────────────────────
# LEDGER TESTS
#
# Run with:  bash tools/test.sh
# Directly:  godot --headless --path . --script res://tools/test_ledger.gd
#
# WHY THIS FILE EXISTS. Four separate ledger bugs shipped in two days — a sell
# that refused issued stock, two buys that announced themselves before the goods
# arrived, and a "newest purchase" lookup that compared keys as strings. None of
# them were visible to the parse check, and all of them were found by a human
# clicking a button. This runs the same sequences in a second.
#
# THE INVARIANT under everything here:  available() == earned - sum(allocations)
# If that holds after an arbitrary sequence of operations, the ledger cannot
# drift. Every test asserts it as well as whatever it is actually checking.
# ─────────────────────────────────────────────

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	test_invariant_on_fresh_state()
	test_buy_deducts_and_stocks()
	test_sell_bought_refunds_half()
	test_sell_issued_stock()
	test_selling_is_never_profitable()
	test_newest_purchase_is_numeric()
	test_armoury_not_shared_between_states()
	test_cannot_overspend()
	test_bench()
	test_bench_survives_save()
	test_xp_only_for_those_who_went()
	test_old_save_repair_tool_comes_off_the_player()
	test_squad_size_caps_the_deploy()
	test_the_ally_ramp()
	test_recruiting()
	test_supply_caps_the_active_squad()
	test_compute_buys_supply()
	test_supply_survives_save()
	test_old_saves_are_paid_for_past_clears()
	test_utility_harness_adds_a_slot()
	test_everyone_standing_comes_home_repaired()
	test_compute_is_capacity()
	test_software_is_held_compute()
	test_old_compute_saves_become_a_ledger()
	test_kills_by_kind()
	test_unlocks_wait_for_their_operation()
	test_the_player_has_no_rank()

	print("")
	if _failures == 0:
		print("PASS  %d checks" % _checks)
	else:
		print("FAILED  %d of %d checks" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


# ── helpers ───────────────────────────────────
func check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	var suffix := ("  — " + detail) if detail != "" else ""
	print("FAIL  %s%s" % [label, suffix])


func invariant(state: CampaignState, label: String) -> void:
	var total := 0
	for cost in state.allocations.values():
		total += int(cost)
	check("%s: available == earned - allocations" % label,
		state.available() == state.earned - total,
		"available=%d earned=%d allocated=%d" % [state.available(), state.earned, total])


func make_state(starting: int = 100) -> CampaignState:
	var state := CampaignState.new()
	state.armoury = Armoury.new()
	state.award(starting)
	return state


func make_item(id: StringName, cost: int) -> ItemDefinition:
	var item := ItemDefinition.new()
	item.id = id
	item.display_name = String(id)
	item.cost = cost
	return item


# ── tests ─────────────────────────────────────
func test_invariant_on_fresh_state() -> void:
	var state := make_state(250)
	check("fresh state has full balance", state.available() == 250)
	invariant(state, "fresh")


func test_buy_deducts_and_stocks() -> void:
	var state := make_state(100)
	var rifle := make_item(&"rifle", 20)
	check("buy succeeds when affordable", state.buy_item(rifle))
	check("available drops by cost", state.available() == 80, "got %d" % state.available())
	check("item reaches stores", state.armoury.spare(&"rifle") == 1,
		"got %d" % state.armoury.spare(&"rifle"))
	invariant(state, "after buy")


func test_sell_bought_refunds_half() -> void:
	var state := make_state(100)
	var rifle := make_item(&"rifle", 20)
	state.buy_item(rifle)
	check("sell succeeds", state.sell_item(rifle))
	# Paid 20, half back = 10. 100 - 20 + 10 = 90.
	check("half the price comes back", state.available() == 90, "got %d" % state.available())
	check("stores are empty again", state.armoury.spare(&"rifle") == 0)
	invariant(state, "after sell")


func test_sell_issued_stock() -> void:
	# starting_stock puts items straight into the armoury — they were issued,
	# not bought, so there is no allocation to shrink. Refusing these was the bug.
	var state := make_state(100)
	var kit := make_item(&"repair_tool", 45)
	state.armoury.add(&"repair_tool")
	check("issued stock can be sold", state.sell_item(kit))
	check("credits half the catalogue price", state.available() == 122,
		"expected 122, got %d" % state.available())
	check("issued item leaves stores", state.armoury.spare(&"repair_tool") == 0)
	invariant(state, "after selling issued stock")


func test_selling_is_never_profitable() -> void:
	# The reason crediting `earned` for issued stock is safe: anything BOUGHT
	# carries an allocation, so its sale takes the half-refund path. There must
	# be no cycle that ends richer than it started.
	var state := make_state(100)
	var rifle := make_item(&"rifle", 20)
	var before := state.available()
	for i in 5:
		if not state.buy_item(rifle):
			break
		state.sell_item(rifle)
		check("cycle %d never gains" % i, state.available() < before,
			"available=%d start=%d" % [state.available(), before])
		before = state.available()
	invariant(state, "after buy/sell cycles")


func test_newest_purchase_is_numeric() -> void:
	# Keys are "item:<id>:<counter>". Compared as strings, "item:rifle:9" sorts
	# above "item:rifle:10", so past nine purchases the wrong allocation was
	# refunded. Detectable only when the price changed between purchases.
	var state := make_state(10000)
	var cheap := make_item(&"rifle", 10)
	for i in 10:
		state.buy_item(cheap)
	var pricey := make_item(&"rifle", 50)
	state.buy_item(pricey)

	var before := state.available()
	state.sell_item(pricey)
	var refunded := state.available() - before
	# The 11th purchase cost 50, so half of that is 25. Picking the wrong
	# allocation would refund 5.
	check("refunds the newest purchase, not the lexicographically largest",
		refunded == 25, "refunded %d, expected 25" % refunded)
	invariant(state, "after out-of-order sell")


func test_armoury_not_shared_between_states() -> void:
	# `@export var armoury: Armoury = Armoury.new()` evaluates per instance, but
	# shared Resource defaults are a documented trap in this project, and a
	# shared armoury would mean two saves writing to one pool.
	var a := CampaignState.new()
	var b := CampaignState.new()
	a.armoury.add(&"rifle")
	check("a fresh state does not inherit another's stores",
		b.armoury.spare(&"rifle") == 0,
		"second state saw %d" % b.armoury.spare(&"rifle"))


func test_cannot_overspend() -> void:
	var state := make_state(10)
	var pricey := make_item(&"cannon", 500)
	check("buying what you cannot afford fails", not state.buy_item(pricey))
	check("nothing was stocked", state.armoury.spare(&"cannon") == 0)
	check("balance untouched", state.available() == 10)
	invariant(state, "after refused buy")


# ── THE BENCH ────────────────────────────────
# Not ledger arithmetic, but it lives on the same CampaignState and is pure
# data, so this is where it is cheapest to pin down.
func make_soldier(state: CampaignState, soldier_name: String) -> SoldierRecord:
	var r := SoldierRecord.new()
	r.display_name = soldier_name
	state.add_soldier(r)
	return r


func test_bench() -> void:
	var state := make_state()
	var a := make_soldier(state, "ALPHA")
	var b := make_soldier(state, "BRAVO")
	var changes := [0]
	state.roster_changed.connect(func(): changes[0] += 1)

	state.set_benched(b, true)
	check("a benched robot is left out of the deploy", not state.deployable().has(b))
	check("...everyone else still goes", state.deployable().has(a))
	check("...but it is still fit to fight (repairs and revives go by that)", b.is_deployable())
	check("benching announces itself, so the squad manager rebuilds and base saves", changes[0] == 1)
	state.set_benched(b, true)
	check("benching twice is not a second change", changes[0] == 1)

	state.set_benched(state.player_record, true)
	check("the player cannot be benched", not state.player_record.benched)

	b.damage = b.max_health
	b.status = SoldierRecord.Status.DESTROYED
	state.set_benched(b, false)
	check("a wreck does not deploy just because it is off the bench", not state.deployable().has(b))

	state.set_benched(a, true)
	check("benching everyone leaves nobody to deploy (a solo run)", state.deployable().is_empty())


func test_bench_survives_save() -> void:
	var r := SoldierRecord.new()
	r.display_name = "CHARLIE"
	r.benched = true
	var back := SoldierRecord.from_dict(r.to_dict())
	check("the bench survives a save", back.benched)
	var old_save := r.to_dict()
	old_save.erase("benched")
	check("a save from before the bench loads with everyone going",
		not SoldierRecord.from_dict(old_save).benched)


func test_xp_only_for_those_who_went() -> void:
	var state := make_state()
	var went := make_soldier(state, "DELTA")
	var stayed := make_soldier(state, "ECHO")
	state.set_benched(stayed, true)

	var campaign := CampaignManager.new()
	campaign.state = state
	var spawner := SquadSpawner.new()
	var body := Node.new()
	# What deploy_into records for each robot it builds: body -> record.
	spawner._spawned[body] = went
	campaign.spawner = spawner

	campaign._award_experience(true)
	check("the robot that deployed earns XP", went.xp > 0, "xp=%d" % went.xp)
	check("the benched robot earns nothing for a mission it sat out", stayed.xp == 0, "xp=%d" % stayed.xp)

	body.free()
	spawner.free()
	campaign.free()


# ── BUILT-IN REPAIR TOOL, OLD SAVES ──────────
# The Repair Tool is permanent on key 3 now. A save with one fitted in an
# equipment slot would build a second copy on 4 or 5, so loading moves it back
# to stores — without saving, since loading should not write the save by itself.
func test_old_save_repair_tool_comes_off_the_player() -> void:
	var cat: ItemCatalogue = load("res://Campaign/items & catalogue/test_item_catalogue.tres")
	var state := make_state()
	state.catalogue = cat
	var rec := state.player_record
	rec.equipment_ids = [&"repair_tool", &"frag"] as Array[StringName]
	var saves := [0]
	state.roster_changed.connect(func(): saves[0] += 1)

	var campaign := CampaignManager.new()
	campaign.state = state
	campaign.catalogue = cat
	campaign._return_unusable_player_kit()
	check("an old save's player repair tool comes off", rec.equipment_ids[0] == &"")
	check("...and goes back to stores, not into the void", state.armoury.spare(&"repair_tool") == 1)
	check("...while everything the player can still use stays fitted", rec.equipment_ids[1] == &"frag")
	check("...and loading does not announce a change (no save on load)", saves[0] == 0)
	campaign.free()


# ── SQUAD SIZE PER MISSION ───────────────────
func test_squad_size_caps_the_deploy() -> void:
	var state := make_state()
	var a := make_soldier(state, "A")
	var b := make_soldier(state, "B")
	var c := make_soldier(state, "C")
	var d := make_soldier(state, "D")
	var campaign := CampaignManager.new()
	campaign.state = state
	var op := MissionDefinition.new()

	op.squad_size = 0
	check("a solo op deploys nobody", campaign.squad_for(op).is_empty())
	check("...and says so", op.squad_label() == "SOLO", op.squad_label())
	op.squad_size = 1
	check("a one-ally op takes the first active robot", names(campaign.squad_for(op)) == ["A"], str(names(campaign.squad_for(op))))
	check("...and says so", op.squad_label() == "MAX 1 ALLY", op.squad_label())
	state.set_benched(a, true)
	check("benching the first hands its place to the next", names(campaign.squad_for(op)) == ["B"], str(names(campaign.squad_for(op))))
	op.squad_size = 4
	check("a cap bigger than the active roster takes everyone active",
		names(campaign.squad_for(op)) == ["B", "C", "D"], str(names(campaign.squad_for(op))))
	op.squad_size = -1
	check("no cap means the whole active squad, and no label", campaign.squad_for(op).size() == 3 and op.squad_label() == "")
	check("a base visit (no mission) is never capped", campaign.squad_for(null).size() == 3)
	campaign.free()


# The campaign's pacing, as data: follow the unlock chain from the first op and
# the ally cap should climb 0, 0, 2, 2, 3 and then come off entirely (-1) once
# the roster is full and benching is how you choose who goes.
func test_the_ally_ramp() -> void:
	var files := ["arena_1_contact", "arena_2_mixed", "arena_3_firing_line",
		"arena_4_pack_hunt", "arena_5_proving", "valley_3_push"]
	var by_id: Dictionary = {}
	for f in files:
		var m: MissionDefinition = load("res://Campaign/missions/mission_%s.tres" % f)
		by_id[m.id] = m
	var sizes: Array = []
	var chained := true
	var prev: StringName = &""
	for f in files:
		var m: MissionDefinition = by_id[StringName(f)]
		sizes.append(m.squad_size)
		if prev != &"" and not m.requires.has(prev):
			chained = false
		prev = m.id
	check("each op unlocks the next, arena 1 through the first valley op", chained)
	check("allies ramp 0, 0, 2, 2, 3, then uncapped from the first valley op", sizes == [0, 0, 2, 2, 3, -1], str(sizes))


func names(records: Array) -> Array:
	var out: Array = []
	for r in records:
		out.append(r.display_name)
	return out


# ── RECRUITING, SUPPLY, COMPUTE ──────────────
# Robots are bought in their own frames, for resources. SUPPLY caps how many
# are ACTIVE (benched ones take none), and COMPUTE buys more supply.
func real_catalogue() -> ItemCatalogue:
	return load("res://Campaign/items & catalogue/test_item_catalogue.tres")


func test_recruiting() -> void:
	var cat := real_catalogue()
	var state := make_state(500)
	state.catalogue = cat
	var soldier_frame := cat.chassis_def(&"soldier")
	var chaser_frame := cat.chassis_def(&"chaser")
	var hopper_frame := cat.chassis_def(&"hopper")
	var soldier := state.recruit(soldier_frame)
	var chaser := state.recruit(chaser_frame)
	var hopper := state.recruit(hopper_frame)
	check("recruits are paid for", state.available() == 500 - soldier_frame.cost - chaser_frame.cost - hopper_frame.cost,
		str(state.available()))
	invariant(state, "after recruiting")
	check("recruits join the roster", state.roster.size() == 3)
	check("recruits are named for their frame", names([soldier, chaser, hopper]) == ["Soldier-1", "Chaser-1", "Hopper-1"],
		str(names([soldier, chaser, hopper])))
	check("...and numbered", state.recruit(chaser_frame).display_name == "Chaser-2")
	check("a soldier arrives with its pistol and otherwise empty slots",
		soldier.weapon_ids.size() == 1 and soldier.equipment_ids.size() == 2 and soldier.module_ids.size() == 2
		and soldier.all_fitted_ids() == [&"pistol"], str(soldier.all_fitted_ids()))
	check("...issued with the frame, not taken from stores", state.armoury.spare(&"pistol") == 0)
	check("a chaser has no weapon or equipment slots, one module",
		chaser.weapon_ids.is_empty() and chaser.equipment_ids.is_empty() and chaser.module_ids.size() == 1)
	check("...a hopper, two modules",
		hopper.weapon_ids.is_empty() and hopper.equipment_ids.is_empty() and hopper.module_ids.size() == 2)
	check("...and nothing can hand a chaser a gun", not state.fit_item(chaser, cat.item(&"m4"), 0))
	check("each fights in its own body", chaser.chassis_scene == chaser_frame.scene and hopper.chassis_scene == hopper_frame.scene
		and chaser.chassis_scene != null and hopper.chassis_scene != null)
	check("each frame's health is its own", chaser.max_health == chaser_frame.base_health
		and hopper.max_health == hopper_frame.base_health, "%d %d" % [chaser.max_health, hopper.max_health])

	var poor := make_state(20)
	poor.catalogue = cat
	check("a recruit you cannot afford is refused", poor.recruit(soldier_frame) == null and poor.roster.is_empty())
	invariant(poor, "after a refused recruit")
	var not_for_sale := ChassisDefinition.new()
	not_for_sale.id = &"gunship"
	check("a frame that is not for sale cannot be recruited", state.recruit(not_for_sale) == null)


func test_supply_caps_the_active_squad() -> void:
	var cat := real_catalogue()
	var state := make_state(1000)
	state.catalogue = cat
	state.supply_cap = 2
	var a := state.recruit(cat.chassis_def(&"soldier"))
	var b := state.recruit(cat.chassis_def(&"chaser"))
	check("recruits join the squad while there is supply", not a.benched and not b.benched)
	check("...each taking its frame's supply", state.supply_used() == 2 and state.supply_free() == 0,
		"used=%d free=%d" % [state.supply_used(), state.supply_free()])
	var c := state.recruit(cat.chassis_def(&"hopper"))
	check("buying is never blocked by supply: the next joins the bench", c != null and c.benched)
	check("...where it takes none", state.supply_used() == 2)
	check("coming off the bench with no supply free is refused", not state.set_benched(c, false) and c.benched)
	check("benching someone frees theirs", state.set_benched(a, true) and state.supply_free() == 1)
	check("...which the bench can then use", state.set_benched(c, false) and not c.benched and state.supply_free() == 0)
	check("benching is never refused", state.set_benched(b, true) and b.benched)
	check("the player takes no supply", state.player_record != null and not state.roster.has(state.player_record)
		and state.supply_used() == 1)


func test_compute_buys_supply() -> void:
	var state := make_state()
	var changes := [0]
	state.ledger_changed.connect(func(): changes[0] += 1)
	var cap := state.supply_cap
	check("no compute, no supply", not state.buy_supply() and state.supply_cap == cap)
	state.award_compute(2)
	check("compute is awarded, and announced", state.compute == 2 and changes[0] == 1)
	check("compute buys supply", state.buy_supply() and state.supply_cap == cap + 1
		and state.compute == 2 - CampaignState.SUPPLY_COMPUTE_COST)
	check("...announced, so the header updates", changes[0] == 2)
	state.award_compute(0)
	check("awarding nothing is not a change", changes[0] == 2)
	invariant(state, "compute never touches resources")


func test_supply_survives_save() -> void:
	var state := make_state()
	state.award_compute(5)
	state.buy_supply()
	state.buy_supply()
	state.supply_cap = 6
	state.compute_claimed.append("valley_3_push:hidden_cache")
	var back := CampaignState.from_dict(state.to_dict())
	check("compute, supply and claimed objectives survive a save", back.compute == 3 and back.supply_cap == 6
		and back.compute_claimed.size() == 1 and back.compute_claimed.has("valley_3_push:hidden_cache"))

	# A save from before supply: five active robots must all stay active.
	var old_state := make_state()
	for n in ["A", "B", "C", "D", "E"]:
		make_soldier(old_state, n)
	var old_save := old_state.to_dict()
	for key in ["compute_earned", "compute_held", "supply_cap", "compute_claimed"]:
		old_save.erase(key)
	var loaded := CampaignState.from_dict(old_save)
	check("an old save gets supply for everyone it had active", loaded.supply_cap == 5 and loaded.supply_free() == 0,
		"cap=%d used=%d" % [loaded.supply_cap, loaded.supply_used()])
	check("...and no compute", loaded.compute == 0)


# The end of a mission, won or lost: everyone still standing is repaired for
# nothing; the destroyed wait for a paid rebuild.
func test_everyone_standing_comes_home_repaired() -> void:
	var state := make_state()
	var dented := make_soldier(state, "DENTED")
	dented.damage = 40
	dented.status = SoldierRecord.Status.WOUNDED
	dented.signal_integrity = 0.3
	var wreck := make_soldier(state, "WRECK")
	wreck.damage = wreck.max_health
	wreck.status = SoldierRecord.Status.DESTROYED
	state.player_record.damage = 25
	var before := state.available()
	state.heal_survivors()
	check("a damaged robot comes home repaired", dented.damage == 0 and dented.status == SoldierRecord.Status.ACTIVE
		and is_equal_approx(dented.signal_integrity, 1.0))
	check("...and so do you", state.player_record.damage == 0)
	check("a destroyed one stays destroyed", wreck.status == SoldierRecord.Status.DESTROYED and wreck.damage == wreck.max_health)
	check("...still with a rebuild to pay for", state.repair_cost(wreck) > 0)
	check("repairing the rest costs nothing", state.available() == before)
	invariant(state, "after the end-of-mission repair")


# COMPUTE IS CAPACITY. Seats and software HOLD it; giving either back frees all
# of it, any time. The compute twin of the resource invariant:
#   compute_free() == compute_earned - sum(compute_held)
func compute_invariant(state: CampaignState, label: String) -> void:
	var held := 0
	for v in state.compute_held.values():
		held += int(v)
	check("%s: compute free == earned - held" % label, state.compute_free() == state.compute_earned - held,
		"free=%d earned=%d held=%d" % [state.compute_free(), state.compute_earned, held])


func test_compute_is_capacity() -> void:
	var state := make_state()
	state.award_compute(3)
	check("compute won is compute free", state.compute_free() == 3 and state.compute_earned == 3)
	check("a seat holds compute", state.buy_supply() and state.compute_free() == 2 and state.supply_cap == 5
		and state.seats_held() == 1)
	check("...and gives all of it back", state.refund_supply() and state.compute_free() == 3 and state.supply_cap == 4)
	check("the starting seats were never held, so they stay", not state.refund_supply() and state.supply_cap == 4)
	state.buy_supply()
	for n in ["A", "B", "C", "D", "E"]:
		make_soldier(state, n)
	check("a seat with a robot in it cannot be given back", not state.refund_supply() and state.supply_cap == 5,
		"free=%d" % state.supply_free())
	state.set_benched(state.roster[4], true)
	check("...until someone is benched", state.refund_supply() and state.supply_cap == 4)
	check("giving compute back never touches what was won", state.compute_earned == 3)
	compute_invariant(state, "after seats")
	invariant(state, "compute never touches resources")


func test_software_is_held_compute() -> void:
	var T = load("res://Campaign/software_tree.gd")
	var state := make_state()
	state.award_compute(4)
	check("the tree has four branches of six programs", T.ids().size() == 24, str(T.ids().size()))
	check("a tier 2 program needs a tier 1 in its branch first",
		T.install_block(state, &"command_2a").begins_with("NEEDS A TIER 1") and not T.install(state, &"command_2a"))
	check("a tier 1 program installs, holding 1", T.install(state, &"command_1a") and state.compute_free() == 3)
	check("...which opens tier 2, holding 2", T.install(state, &"command_2a") and state.compute_free() == 1)
	check("a tier 1 in another branch opens nothing here", T.install_block(state, &"signal_2a").begins_with("NEEDS A TIER 1"))
	check("tier 3 needs tier 2, and 3 compute", T.install_block(state, &"command_3a") == "NEEDS 3 COMPUTE")
	check("the program a higher tier stands on cannot be uninstalled",
		not T.uninstall(state, &"command_1a") and state.is_installed(&"command_1a"))
	check("...until the higher one comes out, and each gives back all it held",
		T.uninstall(state, &"command_2a") and T.uninstall(state, &"command_1a") and state.compute_free() == 4)
	T.install(state, &"combat_1b")
	state.buy_supply()
	var back := CampaignState.from_dict(state.to_dict())
	check("installed programs and held seats survive a save", back.is_installed(&"combat_1b")
		and back.seats_held() == 1 and back.compute_free() == state.compute_free(),
		"free %d vs %d" % [back.compute_free(), state.compute_free()])
	back.compute_held["software:cut_in_a_patch"] = 2
	var dropped := back.release_unknown_software(T.ids())
	check("a program the tree no longer has gives its compute back",
		dropped.size() == 1 and dropped[0] == &"cut_in_a_patch" and back.compute_free() == state.compute_free())
	compute_invariant(state, "after software")
	compute_invariant(back, "after a reload")


func test_old_compute_saves_become_a_ledger() -> void:
	# Before compute was capacity, a save kept a balance and a seat count.
	var state := make_state()
	var old_save := state.to_dict()
	old_save.erase("compute_earned")
	old_save.erase("compute_held")
	old_save["compute"] = 2
	old_save["supply_cap"] = 6
	var loaded := CampaignState.from_dict(old_save)
	check("an old save's two bought seats become held seats", loaded.seats_held() == 2 and loaded.supply_cap == 6)
	check("...its balance stays free", loaded.compute_free() == 2)
	check("...and what the seats held is counted as won", loaded.compute_earned == 4)
	check("...so a seat given back returns its compute", loaded.refund_supply() and loaded.compute_free() == 3)
	compute_invariant(loaded, "after converting an old save")


# WHAT they killed, not just how many: the debrief's "2 CHASERS" comes from here.
func test_kills_by_kind() -> void:
	var r := SoldierRecord.new()
	var body := {&"chaser": 2, &"rifleman": 1}
	r.take_kills_by_kind(body)
	check("a mission's kills by kind are kept for the debrief",
		int(r.kills_by_kind_this_mission.get(&"chaser", 0)) == 2 and int(r.kills_by_kind_this_mission.get(&"rifleman", 0)) == 1)
	check("...added to the career, and cleared on the body", int(r.kills_by_kind.get(&"chaser", 0)) == 2 and body.is_empty())
	r.take_kills_by_kind({&"chaser": 1})
	check("the career adds up across missions", int(r.kills_by_kind[&"chaser"]) == 3 and int(r.kills_by_kind[&"rifleman"]) == 1)
	check("...while the debrief shows only this one", int(r.kills_by_kind_this_mission.get(&"rifleman", 0)) == 0)
	var back := SoldierRecord.from_dict(r.to_dict())
	check("career kills by kind survive a save", int(back.kills_by_kind.get(&"chaser", 0)) == 3
		and int(back.kills_by_kind.get(&"rifleman", 0)) == 1, str(back.kills_by_kind))
	var kinds = load("res://Campaign/kill_kinds.gd")
	check("a kind reads as its frame, without the word chassis",
		kinds.name_of(&"chaser") == "CHASER" and kinds.name_of(&"rifleman") == "RIFLE TROOPER", kinds.name_of(&"chaser"))


func test_unlocks_wait_for_their_operation() -> void:
	var state := make_state()
	var campaign := CampaignManager.new()
	campaign.state = state
	var op := MissionDefinition.new()
	op.id = &"op_pack"
	op.unlocks = [&"hopper"] as Array[StringName]
	campaign.missions = [op] as Array[MissionDefinition]
	check("a frame an operation unlocks is locked until it is cleared", campaign.locked_by(&"hopper") == op)
	check("anything no operation unlocks is never locked", campaign.locked_by(&"soldier") == null)
	state.completed_missions.append(&"op_pack")
	campaign._grant_owed_unlocks()
	check("a save that already cleared it is handed the unlock on load",
		campaign.locked_by(&"hopper") == null and state.unlocked.has(&"hopper"))
	campaign.free()


# You spend the resources and the compute; you don't earn rank.
func test_the_player_has_no_rank() -> void:
	var cat := real_catalogue()
	var state := make_state()
	state.catalogue = cat
	var gated := make_item(&"veterans_only", 10)
	gated.kind = ItemDefinition.Kind.MODULE
	gated.required_rank = 2
	state.armoury.add(&"veterans_only")
	state.player_record.set_chassis(cat.chassis_def(&"soldier"), cat)
	var squaddie := make_soldier(state, "NEW")
	squaddie.set_chassis(cat.chassis_def(&"soldier"), cat)
	check("rank never gates you", state.can_fit(state.player_record, gated))
	check("...it still gates a squadmate", not state.can_fit(squaddie, gated))


# Compute arrived after people had saves. An op cleared before it paid compute
# pays it when the save loads — once, and without writing the save.
func test_old_saves_are_paid_for_past_clears() -> void:
	var state := make_state()
	var paid_op := MissionDefinition.new()
	paid_op.id = &"op_paid"
	paid_op.compute_reward = 2
	var free_op := MissionDefinition.new()
	free_op.id = &"op_free"
	var later_op := MissionDefinition.new()
	later_op.id = &"op_later"
	later_op.compute_reward = 1
	state.completed_missions = [&"op_paid", &"op_free"] as Array[StringName]
	var campaign := CampaignManager.new()
	campaign.state = state
	campaign.missions = [paid_op, free_op, later_op] as Array[MissionDefinition]
	var announced := [0]
	state.ledger_changed.connect(func(): announced[0] += 1)
	campaign._pay_compute_owed()
	check("a save that cleared an op before it paid compute is paid on load", state.compute == 2, str(state.compute))
	check("...only for what it cleared", state.clear_compute_paid(&"op_paid") and not state.clear_compute_paid(&"op_later"))
	check("...without announcing it (no save on load)", announced[0] == 0)
	campaign._pay_compute_owed()
	check("...and only once", state.compute == 2, str(state.compute))
	var again := CampaignManager.new()
	again.state = CampaignState.from_dict(state.to_dict())
	again.missions = campaign.missions
	again._pay_compute_owed()
	check("...even across a save and reload", again.state.compute == 2, str(again.state.compute))
	campaign.free()
	again.free()


func test_utility_harness_adds_a_slot() -> void:
	var cat := real_catalogue()
	var state := make_state(1000)
	state.catalogue = cat
	var s := state.recruit(cat.chassis_def(&"soldier"))
	for id in [&"utility_harness", &"emp", &"frag", &"hatchling"]:
		state.buy_item(cat.item(id))
	check("a soldier has two equipment slots", s.equipment_ids.size() == 2)
	check("the harness fits", state.fit_item(s, cat.item(&"utility_harness"), 0))
	check("...and adds a third slot", s.equipment_ids.size() == 3, str(s.equipment_ids.size()))
	state.fit_item(s, cat.item(&"frag"), 0)
	state.fit_item(s, cat.item(&"hatchling"), 1)
	check("...which takes kit like the others", state.fit_item(s, cat.item(&"emp"), 2) and s.equipment_ids[2] == &"emp")
	check("taking the harness off takes the slot away", state.unfit_item(s, ItemDefinition.Kind.MODULE, 0)
		and s.equipment_ids.size() == 2)
	check("...and what hung there goes back to stores", state.armoury.spare(&"emp") == 1
		and state.armoury.spare(&"utility_harness") == 1)
	check("...while the other two stay fitted", s.equipment_ids[0] == &"frag" and s.equipment_ids[1] == &"hatchling")
	invariant(state, "after the harness comes off")
	var chaser := state.recruit(cat.chassis_def(&"chaser"))
	check("a chaser cannot wear a harness", not state.fit_item(chaser, cat.item(&"utility_harness"), 0))

	# A frame the catalogue does not know gives no base to add to, so the row
	# must stay put rather than grow on every settle.
	var stray := SoldierRecord.new()
	stray.chassis_id = &"not_in_the_catalogue"
	stray.equipment_ids.resize(2)
	stray.module_ids = [&"utility_harness"] as Array[StringName]
	stray.fit_equipment_capacity(cat)
	stray.fit_equipment_capacity(cat)
	check("an unknown frame's equipment row never grows", stray.equipment_ids.size() == 2, str(stray.equipment_ids.size()))
	# And with no catalogue at all a frame still sizes the row, as it always did.
	var bare := SoldierRecord.new()
	bare.set_chassis(cat.chassis_def(&"soldier"), null)
	check("set_chassis sizes equipment without a catalogue", bare.equipment_ids.size() == 2, str(bare.equipment_ids.size()))
