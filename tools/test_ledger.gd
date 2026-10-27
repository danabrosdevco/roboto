extends SceneTree
# BUCKET: campaign

## Prices come from the band table now (Campaign/pricing.gd), NOT from the
## `cost` a fixture sets — make_item()'s cost argument is inert for anything
## the player buys. Expectations below derive from here so a rebalance does
## not rewrite the suite.
const _Pricing := preload("res://Campaign/pricing.gd")

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

## The two enemy frames the recruiting and supply tests are built on: no weapon
## mount, no equipment slot, one and two module slots. Held by path because they
## are deliberately absent from the player catalogue — see enemy_frame().
const CHASER := "res://Campaign/chassis/chassis_chaser.tres"
const HOPPER := "res://Campaign/chassis/chassis_hopper.tres"

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	# PACE THE LOOP — see the note in tools/test.sh. Without this a
	# --script run has no frame cap, _process spins flat out and starves
	# physics, and every await physics_frame below takes far longer in
	# wall clock than the 1/60 s it is written as.
	Engine.max_fps = 60
	# A PROBE FILE, NOT THE PLAYER'S SETTINGS. locked_by() consults the DEBUG
	# "unlock all gear" switch, which lives in settings.json — so with that
	# ticked on the machine running the suite, every unlock check here failed and
	# the code was entirely correct. A test must not read state the player can
	# toggle from a menu.
	Settings.path = "user://settings_probe.json"
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
	test_unlocks_are_things_you_can_buy()
	test_recruiting()
	test_supply_caps_the_active_squad()
	test_compute_buys_supply()
	test_supply_survives_save()
	test_old_saves_are_not_paid_for_past_clears()
	test_utility_harness()
	test_everyone_standing_comes_home_repaired()
	test_compute_is_capacity()
	test_software_is_held_compute()
	test_old_compute_saves_become_a_ledger()
	test_kills_by_kind()
	test_unlocks_are_bought_not_granted()
	test_issued_lines_need_no_unlock()
	test_old_unlocks_migrate_as_free()
	test_rank_gates_nothing()
	test_nothing_is_bought_in_the_field()

	print("")
	# ZERO CHECKS IS NOT ZERO FAILURES. `_failures == 0` and `_checks == 0` are
	# the same number and mean opposite things: a suite that aborts before it
	# asserts anything — a compile error in the code under test will do it —
	# used to print "PASS 0 checks" and exit 0, which is the one result a suite
	# must never give. Caught on 2026-10-26 while A/B-ing a new suite.
	if _checks == 0:
		print("FAILED  nothing ran — no check was reached, which is not a pass")
		_failures += 1
	elif _failures == 0:
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


## THE LEDGER TESTS ARE ABOUT MONEY, NOT GATING.
##
## buy_item and buy_chassis now refuse anything whose line is shut (Phase 3),
## so a fixture that wants to test arithmetic has to open the lines first.
## Gating has its own tests — test_unlocks_are_bought_not_granted and friends —
## and granting here keeps the two from testing each other by accident.
func make_state(starting: int = 100) -> CampaignState:
	var state := CampaignState.new()
	state.armoury = Armoury.new()
	state.award(starting)
	return state


## Open every line in a catalogue, free. For fixtures only.
func open_everything(state: CampaignState, cat: ItemCatalogue) -> void:
	if cat == null:
		return
	for i in cat.items:
		if i != null:
			state.grant_unlock(i.id)
	for c in cat.chassis:
		if c != null:
			state.grant_unlock(c.id)


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
	state.grant_unlock(rifle.id)
	var price: int = _Pricing.item_buy(rifle)
	check("buy succeeds when affordable", state.buy_item(rifle))
	check("available drops by the BAND price", state.available() == 100 - price,
		"got %d, expected %d" % [state.available(), 100 - price])
	check("item reaches stores", state.armoury.spare(&"rifle") == 1,
		"got %d" % state.armoury.spare(&"rifle"))
	check("a line that was never opened cannot be bought",
		not state.buy_item(make_item(&"never_opened", 10)))
	invariant(state, "after buy")


func test_sell_bought_refunds_half() -> void:
	var state := make_state(100)
	var rifle := make_item(&"rifle", 20)
	state.grant_unlock(rifle.id)
	var price: int = _Pricing.item_buy(rifle)
	state.buy_item(rifle)
	check("sell succeeds", state.sell_item(rifle))
	# Half the BAND price comes back, not half the fixture's cost argument.
	check("half the price comes back", state.available() == 100 - price + state.sale_value(price),
		"got %d" % state.available())
	check("stores are empty again", state.armoury.spare(&"rifle") == 0)
	invariant(state, "after sell")


func test_sell_issued_stock() -> void:
	# starting_stock puts items straight into the armoury — they were issued,
	# not bought, so there is no allocation to shrink. Refusing these was the bug.
	var state := make_state(100)
	var kit := make_item(&"repair_tool", 45)
	state.armoury.add(&"repair_tool")
	check("issued stock can be sold", state.sell_item(kit))
	check("credits half the catalogue price",
		state.available() == 100 + state.sale_value(_Pricing.item_buy(kit)),
		"expected %d, got %d" % [100 + state.sale_value(_Pricing.item_buy(kit)), state.available()])
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
	# refunded. Detectable only when the price CHANGED between purchases.
	#
	# Prices come from a band table now, so two buys of the same id always cost
	# the same and the fixture can no longer create that gap by buying twice.
	# The real scenario it guards is a save carrying purchases made BEFORE a
	# rebalance, so the old ones are written straight into the ledger.
	var state := make_state(10000)
	var rifle := make_item(&"rifle", 10)
	state.grant_unlock(rifle.id)
	for i in 10:
		state.allocations["item:rifle:%d" % state._next_purchase()] = 10
		state.armoury.add(&"rifle")
	state.buy_item(rifle)
	var price: int = _Pricing.item_buy(rifle)

	var before := state.available()
	state.sell_item(rifle)
	var refunded := state.available() - before
	# Half of today's price. Picking the wrong allocation would refund half of
	# the old 10 instead.
	var want: int = state.sale_value(price)
	check("refunds the newest purchase, not the lexicographically largest",
		refunded == want, "refunded %d, expected %d" % [refunded, want])
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
	# Lines must be open before anything can be recruited or bought (Phase 3);
	# gating has its own tests, so the fixtures simply open everything.
	open_everything(state, cat)
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


# The campaign's pacing, as data: follow the unlock chain from the first op.
# The first one is alone; from then on the ally cap is off (-1) and benching is
# how you choose who goes.
func test_the_ally_ramp() -> void:
	# THE CHAIN AS IT IS NOW: two exercises, then the war.
	#
	# `arena_5_proving` used to sit between the Firing Line and the Hillfort.
	# The arenas were cut to two — the third is off the campaign's mission list
	# in world.tscn and the Hillfort requires arena_3_firing_line directly — but
	# its .tres is still on disk, so this list went on loading it and the chain
	# broke at a link nothing walks any more. Retired rather than deleted,
	# because deleting authored content is the human's call.
	var files := ["arena_3_firing_line",
		"hfw_1_fort",
		"basin_1_anchor", "coast_1_road", "pitt_1_rivers"]
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
	check("each op unlocks the next, arena 1 through the hillfort and the basin to the three rivers", chained)
	# NOBODY GOES ALONE ANY MORE. arena_1_contact was the one solo operation
	# (squad_size 0) and it was cut on 2026-10-22, so every op in the chain
	# now takes -1: no cap from the mission at all, and it is your supply,
	# bought with compute at the Factory, that decides how many go in with you.
	# FIVE, NOT SIX: arena_5_proving left the chain when the arenas were cut
	# to two, and arena_1_contact when they were cut to one.
	check("everyone you can supply, from the first op on",
		sizes == [-1, -1, -1, -1, -1], str(sizes))


func names(records: Array) -> Array:
	var out: Array = []
	for r in records:
		out.append(r.display_name)
	return out


# ── RECRUITING, SUPPLY, COMPUTE ──────────────
# Robots are bought in their own frames, for resources. SUPPLY caps how many
# A frame the player cannot buy, made buyable for the ledger's sake. Chasers and
# leapers are ENEMY frames — you meet them, you do not field them — but they are
# still the shapes these tests need: no weapon slot, no equipment slot, a
# different supply cost each. Duplicating leaves the catalogue's own copy alone,
# which matters because resources are shared.
## A fixture frame the shop will take: purchasable, and its LINE OPEN.
##
## Opening it here rather than at each call site, because recruiting is gated on
## the unlock now (Phase 3) and a fixture frame that is purchasable but shut
## returns null from recruit() — which showed up as "Invalid access to property
## 'benched' on Nil" three tests later rather than as a failed check.
func buyable(state: CampaignState, frame: ChassisDefinition) -> ChassisDefinition:
	var copy: ChassisDefinition = frame.duplicate()
	copy.purchasable = true
	if state != null:
		state.grant_unlock(copy.id)
	return copy


## An enemy frame, loaded BY PATH rather than out of the catalogue.
##
## These used to come from `cat.chassis_def(&"chaser")`. They were taken out of
## the player catalogue when the shop stopped listing things you only ever
## fight — and `chassis_def` then returned null, `buyable()` called duplicate()
## on it, and the script error aborted the COROUTINE without failing the run. So
## test_recruiting and test_supply_caps_the_active_squad stopped executing
## entirely and the suite went on reporting PASS. That is the second time this
## project has been bitten by a coroutine swallowing its own abort.
##
## By path is also the honest way to say it: the point of these two is that they
## are NOT in the player's catalogue, so reaching for them through it was always
## the wrong door.
func enemy_frame(path: String) -> ChassisDefinition:
	var frame: ChassisDefinition = load(path)
	if frame == null:
		push_error("test_ledger: no chassis at %s — the ledger tests need a frame with no weapon and no equipment slot." % path)
	return frame
# are ACTIVE (benched ones take none), and COMPUTE buys more supply.
func real_catalogue() -> ItemCatalogue:
	return load("res://Campaign/items & catalogue/test_item_catalogue.tres")


func test_recruiting() -> void:
	var cat := real_catalogue()
	var state := make_state(500)
	state.catalogue = cat
	# Lines must be open before anything can be recruited or bought (Phase 3);
	# gating has its own tests, so the fixtures simply open everything.
	open_everything(state, cat)
	var soldier_frame := cat.chassis_def(&"soldier")
	var chaser_frame := buyable(state, enemy_frame(CHASER))
	var hopper_frame := buyable(state, enemy_frame(HOPPER))
	# Recruiting is gated on the line being open (Phase 3), and these tests are
	# about the arithmetic. open_everything only covers the catalogue, so the
	# two ad-hoc frames are granted by hand.
	open_everything(state, cat)
	var bill: int = _Pricing.chassis_buy(soldier_frame) \
		+ _Pricing.chassis_buy(chaser_frame) + _Pricing.chassis_buy(hopper_frame)
	var soldier := state.recruit(soldier_frame)
	var chaser := state.recruit(chaser_frame)
	var hopper := state.recruit(hopper_frame)
	check("recruits are paid for", state.available() == 500 - bill,
		"%d, expected %d" % [state.available(), 500 - bill])
	invariant(state, "after recruiting")
	check("recruits join the roster", state.roster.size() == 3)
	check("recruits are named for their frame", names([soldier, chaser, hopper]) == ["Soldier-1", "Chaser-1", "Leaper-1"],
		str(names([soldier, chaser, hopper])))
	check("...and numbered", state.recruit(chaser_frame).display_name == "Chaser-2")
	# AN ANCIENT RIFLE, not the pistol it used to be. The pistol is out of the
	# player's game entirely; the soldier frame issues an m4 now.
	check("a soldier arrives with its rifle and otherwise empty slots",
		soldier.weapon_ids.size() == 1 and soldier.equipment_ids.size() == 2 and soldier.module_ids.size() == 2
		and soldier.all_fitted_ids() == [&"m4"], str(soldier.all_fitted_ids()))
	check("...issued with the frame, not taken from stores", state.armoury.spare(&"m4") == 0)
	check("a chaser has no weapon or equipment slots, one module",
		chaser.weapon_ids.is_empty() and chaser.equipment_ids.is_empty() and chaser.module_ids.size() == 1)
	check("...a hopper, two modules",
		hopper.weapon_ids.is_empty() and hopper.equipment_ids.is_empty() and hopper.module_ids.size() == 2)
	check("...and nothing can hand a chaser a gun", not state.fit_item(chaser, cat.item(&"m4"), 0))
	check("each fights in its own body", chaser.chassis_scene == chaser_frame.scene and hopper.chassis_scene == hopper_frame.scene
		and chaser.chassis_scene != null and hopper.chassis_scene != null)
	# HEALTH COMES OUT OF THE CATALOGUE, not off the frame you passed in:
	# recompute_stats() looks the chassis up by id. So this is asked of frames
	# the catalogue actually carries — asking it of a chaser measured
	# SoldierRecord's own 100 for both and called that "its own health".
	var recl := state.recruit(cat.chassis_def(&"reclaimer"))
	check("each frame's health is its own",
		soldier.max_health == cat.chassis_def(&"soldier").base_health
		and recl.max_health == cat.chassis_def(&"reclaimer").base_health
		and soldier.max_health != recl.max_health,
		"soldier %d, reclaimer %d" % [soldier.max_health, recl.max_health])
	# ...AND A FRAME THE CATALOGUE DOES NOT CARRY FALLS BACK, LOUDLY. The record
	# keeps its class defaults and recompute_stats() pushes a warning, which is
	# the behaviour that used to be silent and read as "a chaser has 100 health".
	check("...and a frame outside the catalogue falls back to class defaults",
		chaser.max_health == 100 and chaser.max_health != chaser_frame.base_health,
		"%d, frame says %d" % [chaser.max_health, chaser_frame.base_health])

	# ENEMY FRAMES ARE NOT STOCK. A chaser and a leaper are things you fight,
	# not things you field: they have no weapon mount and no equipment slot, so
	# bought they were a worse soldier with a melee attack, and their presence
	# in the shop said the catalogue was a list of everything in the game rather
	# than a list of what you can build.
	#
	# They used to be IN the catalogue and merely unpurchasable. They are out of
	# it entirely now, which is the stronger claim and the one worth pinning:
	# `locked_by()` only gates what a mission NAMES, so a frame left in the
	# catalogue and named by nothing is on sale from the first minute.
	for enemy_only in [&"chaser", &"leaper"]:
		check("%s is not in the player's catalogue at all" % enemy_only,
			cat.chassis_def(enemy_only) == null)
	for path in [CHASER, HOPPER]:
		var frame := enemy_frame(path)
		check("%s is not sold to the player" % frame.id, not frame.purchasable)
		check("...and recruiting one is refused outright",
			make_state(9999).recruit(frame) == null)

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
	# Lines must be open before anything can be recruited or bought (Phase 3);
	# gating has its own tests, so the fixtures simply open everything.
	open_everything(state, cat)
	state.supply_cap = 2
	var a := state.recruit(cat.chassis_def(&"soldier"))
	var b := state.recruit(buyable(state, enemy_frame(CHASER)))
	check("recruits join the squad while there is supply", not a.benched and not b.benched)
	check("...each taking its frame's supply", state.supply_used() == 2 and state.supply_free() == 0,
		"used=%d free=%d" % [state.supply_used(), state.supply_free()])
	var c := state.recruit(buyable(state, enemy_frame(HOPPER)))
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
#   compute_free() == compute_earned + site_compute() - sum(compute_held)
#
# site_compute() is in the sum since Backlog K11: holding a Location pays its
# compute for as long as you hold it. It reads 0 for every state here, because
# these fixtures have no LocationCatalogue and so hold no ground — which is
# exactly why this invariant did NOT go red when the term was added, and why
# the check that ground pays at all lives in test_campaign_spine, which has a
# real board. Written out in full anyway: an invariant that is only accidentally
# true is one nobody can rely on.
func compute_invariant(state: CampaignState, label: String) -> void:
	var held := 0
	for v in state.compute_held.values():
		held += int(v)
	check("%s: compute free == earned + ground - held" % label,
		state.compute_free() == state.compute_earned + state.site_compute() - held,
		"free=%d earned=%d ground=%d held=%d" % [
			state.compute_free(), state.compute_earned, state.site_compute(), held])


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
	# nodes() is the BRANCHES. ids() is everything the ledger may hold, which
	# since MEMORY also includes the player's carry list — so counting ids()
	# here was counting two things and would move every time a gun does.
	check("the tree has four branches of six programs", T.nodes().size() == 24, str(T.nodes().size()))
	check("...and ids() knows the carry list as well, or a load unloads itself on reload",
		T.ids().size() == T.nodes().size() + T.CARRY.size(), str(T.ids().size()))
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

# A LINE IS OPENED BY PAYING FOR IT, not by clearing an operation (Phase 3).
func test_unlocks_are_bought_not_granted() -> void:
	var cat := real_catalogue()
	var state := make_state()
	state.catalogue = cat
	var campaign := CampaignManager.new()
	campaign.state = state
	# A PURCHASABLE frame. The leaper is enemy-only (purchasable = false), so
	# Pricing.chassis_for_sale refuses it and no line can be opened at all.
	var frame := cat.chassis_def(&"rover")
	check("a frame nobody has opened is locked", campaign.is_locked(&"rover"))
	check("...and cannot be bought while it is", not state.buy_chassis(frame))
	state.earned = 100000
	check("opening the line works", state.unlock_chassis(frame))
	check("...and it is no longer locked", not campaign.is_locked(&"rover"))
	check("...and now it can be bought", state.buy_chassis(frame))
	check("...and opening it twice is refused, not charged twice",
		not state.unlock_chassis(frame))
	# An unlock is CAPITAL: it stays in allocations and is never refunded.
	check("the unlock is still held against the ledger",
		state.allocations.has(CampaignState.unlock_key(&"rover")))
	campaign.free()


# The Ancient Rifle is issued, not bought: open from the start with no
# allocation written anywhere.
func test_issued_lines_need_no_unlock() -> void:
	var cat := real_catalogue()
	var state := make_state()
	state.catalogue = cat
	check("the issued rifle is open from the start", state.is_unlocked(&"m4"))
	check("...without an allocation to its name",
		not state.allocations.has(CampaignState.unlock_key(&"m4")))
	check("...while anything else is shut", not state.is_unlocked(&"autocannon"))


# A save from before unlocks were ledger keys keeps everything it had earned.
func test_old_unlocks_migrate_as_free() -> void:
	var state := make_state()
	state.catalogue = real_catalogue()
	var raw := state.to_dict()
	raw["unlocked"] = ["autocannon", "walker"]
	var loaded := CampaignState.from_dict(raw)
	loaded.catalogue = state.catalogue
	check("what a save had unlocked is still unlocked", loaded.is_unlocked(&"autocannon")
		and loaded.is_unlocked(&"walker"))
	check("...and it cost them nothing", loaded.spent() == state.spent())

# RANK NO LONGER GATES ANYTHING (Phase 3.7). It still exists and still drives
# stats; it just stopped being a second answer to "can this robot have this",
# which the catalogue now answers on its own.
func test_rank_gates_nothing() -> void:
	var cat := real_catalogue()
	var state := make_state()
	state.catalogue = cat
	# Lines must be open before anything can be recruited or bought (Phase 3);
	# gating has its own tests, so the fixtures simply open everything.
	open_everything(state, cat)
	var item := make_item(&"anything", 10)
	item.kind = ItemDefinition.Kind.MODULE
	state.armoury.add(&"anything")
	state.player_record.set_chassis(cat.chassis_def(&"soldier"), cat)
	var squaddie := make_soldier(state, "NEW")
	squaddie.set_chassis(cat.chassis_def(&"soldier"), cat)
	check("a rank-0 squadmate is refused nothing", state.can_fit(squaddie, item))
	check("...and neither are you", state.can_fit(state.player_record, item))

# Compute arrived after people had saves. An op cleared before it paid compute
# pays it when the save loads — once, and without writing the save.
# ─────────────────────────────────────────────
# WAS `test_old_saves_are_paid_for_past_clears`, AND IT ASSERTED THE OPPOSITE.
#
# `_pay_compute_owed()` walked every completed mission on load and claimed its
# first-clear compute — a migration for saves older than the compute economy.
# First clears stopped paying on 2026-10-26 (Backlog K11b: lose the location,
# lose the compute), so back-paying one would hand an old save up to 29 compute
# that nothing can ever take away. The function is now
# `_release_orphaned_software()` and pays nothing at all.
#
# HOW THE OLD VERSION FAILED IS WORTH MORE THAN THE TEST. It did not go red: it
# called a method that no longer exists, which on an untyped local is a runtime
# error that does NOT stop the suite — so its five checks simply stopped
# running and `test_ledger` still printed **PASS, with five fewer checks than
# the run before**. Only comparing the counts caught it (191 → 186), and
# `bucket.sh` cannot: its guard fires on ZERO checks, not on fewer than last
# time. Read the number, not just the word.
# ─────────────────────────────────────────────
func test_old_saves_are_not_paid_for_past_clears() -> void:
	var state := make_state()
	var paid_op := MissionDefinition.new()
	paid_op.id = &"op_paid"
	paid_op.compute_reward = 2
	var free_op := MissionDefinition.new()
	free_op.id = &"op_free"
	state.completed_missions = [&"op_paid", &"op_free"] as Array[StringName]
	var campaign := CampaignManager.new()
	campaign.state = state
	campaign.missions = [paid_op, free_op] as Array[MissionDefinition]
	var before: int = state.compute
	campaign._release_orphaned_software()
	check("loading a save with cleared ops pays no compute for them",
		state.compute == before, "%d -> %d" % [before, state.compute])
	check("...and claims nothing, so a capture bonus could still be added later",
		not state.clear_compute_paid(&"op_paid"))

	# THE HALF THAT SURVIVED, and the only test that it is still on the load
	# path: compute held by a program the tree has dropped is handed back.
	var orphan := make_state()
	orphan.award_compute(4)
	orphan.compute_held["software:cut_in_a_patch"] = 2
	var c2 := CampaignManager.new()
	c2.state = orphan
	c2.missions = [] as Array[MissionDefinition]
	var free_before: int = orphan.compute_free()
	c2._release_orphaned_software()
	check("...while a program the tree no longer has still gives its compute back",
		orphan.compute_free() == free_before + 2,
		"%d -> %d" % [free_before, orphan.compute_free()])
	campaign.free()
	c2.free()


func test_utility_harness() -> void:
	var cat := real_catalogue()
	var state := make_state(4000)
	state.catalogue = cat
	# Lines must be open before anything can be recruited or bought (Phase 3);
	# gating has its own tests, so the fixtures simply open everything.
	open_everything(state, cat)
	var s := state.recruit(cat.chassis_def(&"soldier"))
	for id in [&"utility_harness", &"emp", &"frag", &"hatchling"]:
		state.buy_item(cat.item(id))
	check("a soldier has two equipment slots", s.equipment_ids.size() == 2)
	check("the harness fits", state.fit_item(s, cat.item(&"utility_harness"), 0))
	# IT USED TO ADD A THIRD SLOT. Since 2026-10-18 it multiplies the charges
	# on the slots the frame already has instead — an extra mount is a module
	# that asks the player a second question, and more of what they already
	# chose is an answer.
	#
	# equipment_slot_bonus still EXISTS on ItemDefinition and SoldierRecord
	# still reads it; no shipped item uses it any more. The "what hung in the
	# bonus slot goes back to stores" path is therefore no longer covered by
	# anything, which is a known gap rather than an oversight: the first item
	# to use that field again should bring this test back with it.
	check("...and does not add a third slot", s.equipment_ids.size() == 2, str(s.equipment_ids.size()))
	s.recompute_stats(cat)
	check("...it multiplies the charges instead",
		is_equal_approx(s.effective_equipment_multiplier,
			cat.item(&"utility_harness").equipment_quantity_multiplier),
		str(s.effective_equipment_multiplier))
	state.fit_item(s, cat.item(&"frag"), 0)
	state.fit_item(s, cat.item(&"hatchling"), 1)
	check("...and the two real slots still take kit",
		s.equipment_ids[0] == &"frag" and s.equipment_ids[1] == &"hatchling")
	check("taking the harness off returns it to stores",
		state.unfit_item(s, ItemDefinition.Kind.MODULE, 0)
		and state.armoury.spare(&"utility_harness") == 1)
	s.recompute_stats(cat)
	check("...and the charges go back to normal",
		is_equal_approx(s.effective_equipment_multiplier, 1.0),
		str(s.effective_equipment_multiplier))
	check("...while the kit stays fitted", s.equipment_ids[0] == &"frag" and s.equipment_ids[1] == &"hatchling")
	invariant(state, "after the harness comes off")
	var chaser := state.recruit(buyable(state, enemy_frame(CHASER)))
	check("a chaser cannot wear a harness", not state.fit_item(chaser, cat.item(&"utility_harness"), 0))

	# ONE PER ROBOT. Two Sensor Relays added their range together; a second
	# Cyclic Feed did nothing at all. Neither goes on twice.
	var relay := cat.item(&"optics")
	var feed := cat.item(&"cyclic_feed")
	check("(setup) the Sensor Relay and Cyclic Feed are one per robot", relay.one_per_robot and feed.one_per_robot)
	var a := state.recruit(cat.chassis_def(&"soldier"))
	var b := state.recruit(cat.chassis_def(&"soldier"))
	for id in [&"optics", &"optics", &"optics", &"cyclic_feed", &"cyclic_feed"]:
		state.buy_item(cat.item(id))
	# THE PURSE HAS TO COVER THE SHOPPING, OR THIS TESTS NOTHING. Raising the
	# Sensor Relay from 70 to 125 took the three of them past what the fixture
	# was funded with; buy_item quietly failed, fit_item had nothing to fit, and
	# the run died on a null a few lines down — while still printing PASS,
	# because a suite that aborts has simply run fewer checks. Assert the stock
	# landed, so the next price change fails loudly instead of shrinking the run.
	check("(setup) the fixture could afford the shopping",
		state.armoury.spare(&"optics") == 3 and state.armoury.spare(&"cyclic_feed") == 2,
		"optics=%d feeds=%d purse=%d" % [state.armoury.spare(&"optics"),
			state.armoury.spare(&"cyclic_feed"), state.available()])
	check("a Sensor Relay fits", state.fit_item(a, relay, 0))
	check("...but not a second on the same robot", not state.fit_item(a, relay, 1) and a.module_ids[1] == &"",
		str(a.module_ids))
	check("...while another robot can have its own", state.fit_item(b, relay, 0))
	check("refitting the slot it is in is a swap, not a second copy", state.fit_item(a, relay, 0)
		and state.armoury.spare(&"optics") == 1)
	check("one Cyclic Feed per robot too", state.fit_item(a, feed, 1) and not state.fit_item(a, feed, 0)
		and a.module_ids[0] == &"optics")
	invariant(state, "after the one-per-robot fits")

	# A save from before the rule: the second copy comes off on load, into stores.
	var doubled := state.recruit(cat.chassis_def(&"soldier"))
	doubled.module_ids = [&"optics", &"optics"] as Array[StringName]
	var campaign := CampaignManager.new()
	campaign.state = state
	campaign.catalogue = cat
	var spare_before := state.armoury.spare(&"optics")
	campaign._return_unfittable_squad_kit()
	check("an old save's second Sensor Relay comes off on load", doubled.module_ids[0] == &"optics"
		and doubled.module_ids[1] == &"", str(doubled.module_ids))
	check("...and goes back to stores", state.armoury.spare(&"optics") == spare_before + 1)
	campaign.free()

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


# EVERY UNLOCK HAS TO BE SOMETHING THE SHOP WILL SELL.
#
# The debrief announces each one on a tile reading "AT THE ARMORER", so an
# unlock whose item has in_shop off sends the player to a shelf that does not
# stock it. The debrief filters those out now; this catches the authoring
# mistake that puts one in a mission's unlock list in the first place.
#
# Chassis are exempt: ChassisDefinition has no in_shop, and the Factory offers
# whatever the catalogue holds.
func test_unlocks_are_things_you_can_buy() -> void:
	var catalogue: ItemCatalogue = load("res://Campaign/items & catalogue/test_item_catalogue.tres")
	var world: PackedScene = load("res://Env/world.tscn")
	var missions: Array = []
	var st := world.get_state()
	for i in st.get_node_count():
		if st.get_node_name(i) != "CampaignManager":
			continue
		for j in st.get_node_property_count(i):
			if String(st.get_node_property_name(i, j)) == "missions":
				missions = st.get_node_property_value(i, j)
	var bad: Array = []
	for m in missions:
		if m == null:
			continue
		for id in m.unlocks:
			var item: ItemDefinition = catalogue.item(id)
			if item != null and not item.in_shop:
				bad.append("%s unlocks %s, which the armoury will not sell" % [m.id, id])
			elif item == null and catalogue.chassis_def(id) == null:
				bad.append("%s unlocks %s, which is in neither list" % [m.id, id])
	check("every mission unlock is something the player can actually buy", bad.is_empty(), str(bad))


# ─────────────────────────────────────────────
# NO SHOPPING IN THE FIELD (Backlog K12)
#
# TAB opens the squad manager mid-mission and the Factory never asked where the
# squad was, so a firefight was a shop: you could build a robot, open a line,
# adopt a mark or a module, install a program or buy a seat from out there.
#
# A/B, BOTH WAYS ROUND, which is the whole point of this test. "Refused in the
# field" proves nothing on its own — recruit() also returns null for a line
# that is not open, buy_supply() for no compute, buy_item() for an item nobody
# has unlocked. So every call is made TWICE, once out there and once at base,
# and what is being tested is the DIFFERENCE between them.
# ─────────────────────────────────────────────
func test_nothing_is_bought_in_the_field() -> void:
	var cat := real_catalogue()
	var state := make_state(10000)
	state.catalogue = cat
	state.award_compute(10)
	var frame := cat.chassis_def(&"soldier")
	var module := cat.item(&"armor_plating")
	# EVERYTHING THE REFUSALS BELOW NEED, SET UP BEFORE WE LEAVE — so each one
	# is refused for being in the field rather than for having no seat to give
	# back, no program to uninstall and nothing to mend.
	check("(setup) a seat is held before the squad leaves", state.buy_supply())
	check("(setup) ...and a program is installed", state.install_software(&"held_before", 1))
	var wreck := SoldierRecord.new()
	wreck.id = state.mint_id()
	wreck.display_name = "DENTED"
	wreck.set_chassis(frame, cat)
	wreck.damage = 20
	state.roster.append(wreck)
	check("(setup) ...and a damaged robot is on the roster, worth mending",
		state.repair_cost(wreck) > 0 and state.can_repair(wreck),
		"cost %d" % state.repair_cost(wreck))

	state.in_field = true
	var cash := state.available()
	var roster := state.roster.size()
	var cap := state.supply_cap
	check("in the field: opening a frame's line is refused", not state.unlock_chassis(frame))
	check("in the field: opening an item's line is refused", not state.unlock_item(module))
	check("in the field: building a robot is refused", state.recruit(frame) == null)
	check("in the field: adopting a mark is refused", not state.adopt_mark(frame))
	check("in the field: fitting a module to a line is refused", not state.adopt_module(frame, module))
	check("in the field: buying a seat is refused", not state.buy_supply())
	check("in the field: giving a seat back is refused", not state.refund_supply())
	check("in the field: buying kit is refused", not state.buy_item(module))
	check("in the field: installing a program is refused", not state.install_software(&"command_1a", 1))
	check("in the field: uninstalling one is refused too", not state.uninstall_software(&"held_before"))
	check("in the field: a paid rebuild is refused", not state.repair_soldier(wreck))
	check("...so not a resource moved, and nobody joined",
		state.available() == cash and state.roster.size() == roster and state.supply_cap == cap,
		"cash %d->%d roster %d->%d cap %d->%d" % [cash, state.available(),
			roster, state.roster.size(), cap, state.supply_cap])

	# The other half. Without it, every check above would also pass on a
	# campaign that simply could not afford any of this.
	state.in_field = false
	check("at base: the same program uninstalls", state.uninstall_software(&"held_before"))
	check("at base: the same rebuild goes through", state.repair_soldier(wreck))
	check("at base: the same seat is given back", state.refund_supply())
	check("at base: the same frame line opens", state.unlock_chassis(frame))
	check("at base: the same item line opens", state.unlock_item(module))
	check("at base: the same build goes through", state.recruit(frame) != null)
	check("at base: the same mark is adopted", state.adopt_mark(frame))
	check("at base: the same module is fitted", state.adopt_module(frame, module))
	check("at base: the same seat is bought again", state.buy_supply())
	check("at base: the same kit is bought", state.buy_item(module))
	check("at base: the same program installs", state.install_software(&"command_1a", 1))
	check("...so every refusal above was the gate and not the price",
		state.available() < cash and state.roster.size() == roster + 1,
		"cash %d->%d roster %d->%d" % [cash, state.available(), roster, state.roster.size()])
