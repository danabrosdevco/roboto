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
