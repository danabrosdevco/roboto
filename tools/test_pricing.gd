extends SceneTree

# ─────────────────────────────────────────────
# THE PRICE TABLE SAYS WHAT IT WAS TOLD TO SAY.
#
# docs/briefs/CAMPAIGN_REWORK.md §3a and §16.2. Every number below was set by
# the human on 2026-10-12, as multiples of a base of 50. This suite exists so
# that a later refactor of pricing.gd cannot quietly change what things cost —
# the one kind of regression nobody notices until a playthrough feels wrong.
#
# IT CHECKS THE MULTIPLES, NOT THE ABSOLUTE PRICES, wherever it can. BASE is
# meant to be turned; the RATIOS are the design. A test that hardcoded 150
# would fail the moment somebody legitimately moved BASE to 60.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_pricing.gd
# ─────────────────────────────────────────────

const _Pricing := preload("res://Campaign/pricing.gd")

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	# THE ONE THE GAME ACTUALLY USES. Env/world.tscn:94 wires the CampaignManager
	# to "test_item_catalogue.tres" — 34 items and 12 chassis — and the file
	# called Campaign/item_catalogue.tres is a 10-item leftover nothing loads.
	var cat: ItemCatalogue = load("res://Campaign/items & catalogue/test_item_catalogue.tres")
	if cat == null:
		printerr("no item catalogue")
		quit(1)
		return
	var b := float(_Pricing.BASE)

	# ── the bands, as multiples ─────────────────
	var want := {
		_Pricing.ISSUED: [0.0, 1.0],
		_Pricing.STANDARD: [2.0, 1.0],
		_Pricing.UPGRADED: [3.0, 1.5],
		_Pricing.CREW: [3.0, 2.0],
		_Pricing.ADVANCED: [4.0, 2.0],
	}
	var wrong: Array = []
	for band in want:
		var got: Array = _Pricing.BANDS[band]
		if not is_equal_approx(got[0], want[band][0]) or not is_equal_approx(got[1], want[band][1]):
			wrong.append("%s is %sx/%sx, should be %sx/%sx" % [band, got[0], got[1],
				want[band][0], want[band][1]])
	_check("the five bands are the multiples that were asked for", wrong.is_empty(), str(wrong))

	# ── a worked example of each band ───────────
	# One item per band, named, so a reader can see what the band MEANS rather
	# than only what it costs.
	var examples := [
		[&"m4", _Pricing.ISSUED, 0.0, 1.0, "Ancient Rifle — issued, never bought"],
		[&"frag", _Pricing.STANDARD, 2.0, 1.0, "Frag — regular equipment"],
		[&"grenade_launcher", _Pricing.STANDARD, 2.0, 1.0, "Grenade Launcher"],
		[&"mine_heavy", _Pricing.UPGRADED, 3.0, 1.5, "Heavy Mine — upgraded"],
		[&"squad_auto", _Pricing.CREW, 3.0, 2.0, "Squad Automatic — crew weapon"],
		[&"cluster_launcher", _Pricing.CREW, 3.0, 2.0, "Cluster Launcher — same as squad auto"],
		[&"autocannon", _Pricing.ADVANCED, 4.0, 2.0, "Autocannon — the top of the line"],
		[&"optics", _Pricing.ADVANCED, 4.0, 2.0, "Sensor Relay — higher tier"],
	]
	for e in examples:
		var item := cat.item(e[0])
		if item == null:
			_check("%s exists in the catalogue" % e[0], false)
			continue
		var ok_band: bool = _Pricing.band_of(item) == e[1]
		var ok_unlock: bool = _Pricing.item_unlock(item) == int(round(float(e[2]) * b))
		var ok_buy: bool = _Pricing.item_buy(item) == int(round(float(e[3]) * b))
		_check("%s" % e[4], ok_band and ok_unlock and ok_buy,
			"%s, open %d buy %d" % [_Pricing.band_of(item),
				_Pricing.item_unlock(item), _Pricing.item_buy(item)])

	# ── the things that are NOT for sale ────────
	var hl := cat.item(&"hatchling_launcher")
	_check("the hatchling launcher is unbuyable", hl != null and not _Pricing.for_sale(hl))

	# The four old guns the human called "old and unused in the new system".
	# They were ALREADY in_shop = false, which is the stronger statement and
	# predates all of this — so nothing had to be retired.
	var retired: Array = []
	for id in [&"dmr", &"carbine", &"shotgun", &"pistol"]:
		var it := cat.item(id)
		if it != null and _Pricing.for_sale(it):
			retired.append(String(id))
	_check("the four old guns stay out of the shop", retired.is_empty(), str(retired))

	# ── nothing in the shop is unpriced ─────────
	# The real guard. An item added later with no band falls back to STANDARD,
	# which is a price — but a WEAPON or a frame landing there silently is how
	# a 240-resource autocannon ends up costing 50.
	var unbanded: Array = []
	for i in cat.items:
		if i == null or not i.in_shop:
			continue
		if not _Pricing.ITEM_BAND.has(i.id):
			unbanded.append(String(i.id))
	_check("every item in the shop has a band of its own", unbanded.is_empty(),
		"unbanded: %s" % str(unbanded))

	# ── chassis price by supply ─────────────────
	var frames := {&"soldier": 1, &"rover": 2, &"walker": 3}
	for id in frames:
		var f := cat.chassis_def(id)
		if f == null:
			continue
		var mult: float = float(_Pricing.CHASSIS_BUY[frames[id]])
		_check("a supply-%d frame costs %sx base" % [frames[id], mult],
			_Pricing.chassis_buy(f) == int(round(mult * b)),
			"%s = %d" % [id, _Pricing.chassis_buy(f)])

	# UNIFORM WITHIN A TIER. The whole point of §3a: two frames of the same
	# supply cost the same, so a new one prices itself by existing.
	var by_supply := {}
	var mismatched: Array = []
	for f in cat.chassis:
		if f == null or not _Pricing.chassis_for_sale(f):
			continue
		var p: int = _Pricing.chassis_buy(f)
		if by_supply.has(f.supply) and by_supply[f.supply] != p:
			mismatched.append("%s (supply %d) is %d, not %d" % [f.id, f.supply, p, by_supply[f.supply]])
		by_supply[f.supply] = p
	_check("every frame of the same supply costs the same", mismatched.is_empty(), str(mismatched))

	_check("opening a frame costs twice buying one",
		_Pricing.chassis_unlock(cat.chassis_def(&"rover"))
			== 2 * _Pricing.chassis_buy(cat.chassis_def(&"rover")))

	# ── the Diver, which is not for sale ────────
	var diver := load("res://Campaign/chassis/chassis_diver.tres")
	_check("the Diver cannot be bought", diver == null or not _Pricing.chassis_for_sale(diver))

	# ── super-linear, which is the design ───────
	# Supply measures ROOM, cost measures CAPABILITY. Flat pricing per point of
	# supply would make big frames strictly efficient and collapse the roster.
	var per1: float = float(_Pricing.CHASSIS_BUY[1]) / 1.0
	var per3: float = float(_Pricing.CHASSIS_BUY[3]) / 3.0
	_check("a big frame costs MORE per point of supply than a small one",
		per3 > per1, "%.2f vs %.2f per supply" % [per3, per1])

	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
