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
