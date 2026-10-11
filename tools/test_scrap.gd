extends SceneTree

# ─────────────────────────────────────────────
# SCRAPPING A WRECK, AND THE LEDGER SURVIVING IT.
#
# A destroyed frame is not a repair job: you break it for a third of what it
# cost and it leaves the roster. That touches the ledger, which is the one
# thing in this campaign that must never drift, so:
#
#   1. only a DESTROYED record can be scrapped — not an active one, not a
#      wounded one, and never the player's own
#   2. it pays a third of the recruit price, rounded DOWN
#   3. the purse rises by exactly that and not a credit more
#   4. available() still equals earned - sum(allocations) afterwards: the
#      two thirds that did not come back are still booked, not evaporated
#   5. the fitted kit comes back to stores whole
#   6. the record is off the roster
#   7. scrap, re-recruit, scrap again is a LOSS — there is no laundering loop
#
#   godot --headless --audio-driver Dummy --path . --script tools/test_scrap.gd
# ─────────────────────────────────────────────

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fail += 1


func _init() -> void:
	await process_frame
	var cat: ItemCatalogue = load("res://Campaign/items & catalogue/test_item_catalogue.tres")
	if cat == null:
		print("FAIL  no catalogue to test against")
		quit(1)
		return

	var frame: ChassisDefinition = null
	for c in cat.chassis:
		if c != null and c.purchasable and c.cost > 0:
			frame = c
			break
	if frame == null:
		print("FAIL  no purchasable chassis with a price in the catalogue")
		quit(1)
		return

	var s := CampaignState.new()
	s.catalogue = cat
	s.earned = 10000

	var rec := s.recruit(frame)
	_check("(setup) recruited a %s for %d" % [frame.display_name, frame.cost], rec != null)
	if rec == null:
		quit(1)
		return
	# AND SOMETHING BOUGHT AND FITTED. Without this the only kit on the robot
	# is the rifle it was issued with, which correctly pays nothing — so the
	# half-price-for-kit path would never be exercised at all and the suite
	# would pass while testing the wrong half of the rule.
	var module: ItemDefinition = null
	for it in cat.items_of_kind(ItemDefinition.Kind.MODULE):
		if it != null and it.cost > 0:
			module = it
			break
	if module != null and s.buy_item(module):
		_check("(setup) bought and fitted a %s for %d" % [module.display_name, module.cost],
			s.fit_item(rec, module, 0))
	var purse_after_buy := s.available()

	# ── 1. only a wreck ─────────────────────────
	_check("an ACTIVE record cannot be scrapped", not s.can_scrap(rec))
	_check("...and trying anyway is refused, not silently ignored",
		s.scrap_soldier(rec) == -1)
	rec.status = SoldierRecord.Status.WOUNDED
	_check("a WOUNDED record cannot be scrapped either", not s.can_scrap(rec))

	# ── 2 & 3. a third, rounded down ────────────
	rec.status = SoldierRecord.Status.DESTROYED
	_check("a DESTROYED record can be scrapped", s.can_scrap(rec))
	# A third of the frame PLUS half of everything fitted to it.
	var frame_third: int = int(frame.cost / 3)
	# ONLY KIT THAT WAS BOUGHT. The rifle a Soldier is issued with has no
	# allocation and must pay nothing -- its price is already inside the
	# frame's. Paying for it too was a money printer; see the laundering check.
	var kit_half := 0
	for pair in s._kit_payout(rec):
		kit_half += int(pair[2])
	var expect: int = frame_third + kit_half
	_check("scrap_value is a third of the frame plus half its kit",
		s.scrap_value(rec) == expect,
		"frame %d/3 = %d, kit half = %d, total %d, got %d"
			% [frame.cost, frame_third, kit_half, expect, s.scrap_value(rec)])
	_check("...and the kit really is part of it, not a rounding accident",
		kit_half > 0 or rec.all_fitted_ids().is_empty(),
		"fitted: %s" % str(rec.all_fitted_ids()))

	var fitted := rec.all_fitted_ids().duplicate()
	var paid_back := s.scrap_soldier(rec)
	_check("scrapping pays what it advertised", paid_back == expect,
		"paid %d, advertised %d" % [paid_back, expect])
	_check("the purse rose by exactly that",
		s.available() == purse_after_buy + expect,
		"%d -> %d, expected +%d" % [purse_after_buy, s.available(), expect])

	# ── 4. the books still balance ──────────────
	var booked := 0
	for cost in s.allocations.values():
		booked += int(cost)
	_check("available() is still earned minus everything booked",
		s.available() == s.earned - booked,
		"available %d, earned %d, booked %d" % [s.available(), s.earned, booked])
	# What was spent and NOT handed back has to still be committed, or the loss
	# has quietly evaporated and available() is lying. Written against the
	# whole outlay — frame plus bought kit — rather than the frame alone: with
	# kit in the payout, "frame.cost - expect" went negative and the assertion
	# became one that nothing could fail.
	var outlay: int = frame.cost + (module.cost if module != null else 0)
	_check("...and everything that did not come back is still booked",
		booked == outlay - expect,
		"booked %d, outlay %d, paid back %d" % [booked, outlay, expect])

	# ── 5. the kit is DESTROYED, not recovered ──
	# It used to go back to stores. That was meaningless while the player could
	# right-click it off the wreck first, so now it dies with the frame and
	# pays half instead.
	var kit_in_stores := false
	var found := ""
	for id in fitted:
		if id == &"":
			continue
		if s.armoury.spare(id) > 0:
			kit_in_stores = true
			found = str(id)
			break
	_check("fitted kit did NOT come back to stores", not kit_in_stores,
		"" if not kit_in_stores else "%s is on the shelf" % found)

	# ── 6. off the roster ───────────────────────
	_check("the record is off the roster", not s.roster.has(rec))

	# ── 7. no laundering ────────────────────────
	# Buy and scrap the same frame repeatedly. If a third ever came back as
	# more than was paid, this walks upward.
	var before_loop := s.available()
	for _i in 5:
		var r2 := s.recruit(frame)
		if r2 == null:
			break
		r2.status = SoldierRecord.Status.DESTROYED
		s.scrap_soldier(r2)
	_check("five buy-and-scrap cycles lose money, never gain",
		s.available() < before_loop,
		"%d -> %d" % [before_loop, s.available()])

	# ── the player is not scrap ─────────────────
	if s.player_record != null:
		s.player_record.status = SoldierRecord.Status.DESTROYED
		_check("the player's own record can never be scrapped",
			not s.can_scrap(s.player_record) and s.scrap_soldier(s.player_record) == -1)

	print("")
	print("%d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
