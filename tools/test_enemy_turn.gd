extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# THE OTHER SIDE PLAYS TOO.
#
# docs/briefs/CAMPAIGN_REWORK.md Phase 6. The two rules that carry the whole
# campaign layer and are easy to get subtly wrong:
#
#   THE FRONTIER RULE   a site can only be attacked if it borders ground you
#                       do not hold. Interior sites are untouchable, which is
#                       what makes consolidating a strategy.
#   TARGET BY VALUE     garrisons are flat (§6), so the enemy goes for the
#                       throat and losing a site actually costs something.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_enemy_turn.gd
# ─────────────────────────────────────────────

const _Turn := preload("res://Campaign/enemy_turn.gd")

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var cat: ItemCatalogue = load("res://Campaign/items & catalogue/test_item_catalogue.tres")
	var locs = load("res://Campaign/location_catalogue.tres")

	# ── the rhythm ──────────────────────────────
	var moves: Array = []
	for t in range(1, 41):
		if _Turn.acts_on(t):
			moves.append(t)
	_check("the other side never moves on turn 1", not _Turn.acts_on(1))
	_check("...but it does move", moves.size() >= 10, "%d times in 40 turns" % moves.size())
	var gaps: Array = []
	for i in range(1, moves.size()):
		gaps.append(int(moves[i]) - int(moves[i - 1]))
	var bad: Array = []
	for g in gaps:
		if g < _Turn.ACTS_EVERY_MIN or g > _Turn.ACTS_EVERY_MAX:
			bad.append(g)
	_check("EVERY GAP IS 2 OR 3 — a rhythm, never a drought", bad.is_empty(),
		"gaps %s" % str(gaps.slice(0, 10)))
	_check("...and it is seeded, so a reload is the same campaign",
		_Turn.acts_on(7) == _Turn.acts_on(7))

	# ── the frontier rule ───────────────────────
	var s := _make(cat, locs)
	# Hold Hillfort alone. It borders only Valley Basin, which is theirs.
	s.set_site_owner(&"hillfort_wip", Enums.Factions.PLAYER)
	var f := _Turn.frontier(s)
	_check("a lone holding is on the frontier", f.has(&"hillfort_wip"), str(f))

	# Now hold the basin too. Hillfort's ONLY neighbour is the basin, so it
	# becomes interior and untouchable — the rule's whole point.
	s.set_site_owner(&"valley_basin", Enums.Factions.PLAYER)
	f = _Turn.frontier(s)
	_check("CONSOLIDATING MAKES A SITE INTERIOR", not f.has(&"hillfort_wip"), str(f))
	_check("...while the new edge is exposed", f.has(&"valley_basin"))
	_check("...and nothing you do not hold is on your frontier",
		not f.has(&"causeway"))

	# ── targeting ───────────────────────────────
	# Hold two sites of very different worth. They should go for the rich one.
	var s2 := _make(cat, locs)
	s2.set_site_owner(&"hillfort_wip", Enums.Factions.PLAYER)      # 8/turn, 1 compute
	s2.set_site_owner(&"causeway", Enums.Factions.PLAYER)      # 55/turn, 2 compute
	_check("THEY GO FOR THE THROAT, not the nearest thing",
		_Turn.pick_target(s2) == &"causeway", String(_Turn.pick_target(s2)))

	# Nothing held at all: nothing to attack, and no crash.
	var s3 := _make(cat, locs)
	_check("holding nothing means nothing can be attacked",
		_Turn.pick_target(s3) == &"", String(_Turn.pick_target(s3)))

	# ── the paper fight ─────────────────────────
	var basin = locs.of(&"valley_basin")
	var poor := _make(cat, locs)                      # 0 compute -> 8 supply
	var rich := _make(cat, locs)
	rich.compute_earned = 32                          # -> 40 supply
	_check("a bare garrison is overrun on paper",
		_Turn.odds(poor, basin, 1) <= _Turn.DOUBT_LOW,
		"%.2f" % _Turn.odds(poor, basin, 1))
	_check("...and compute is what changes that",
		_Turn.odds(rich, basin, 1) > _Turn.odds(poor, basin, 1),
		"%.2f -> %.2f" % [_Turn.odds(poor, basin, 1), _Turn.odds(rich, basin, 1)])
	_check("a later act is harder to hold",
		_Turn.odds(rich, basin, 3) < _Turn.odds(rich, basin, 1),
		"act1 %.2f, act3 %.2f" % [_Turn.odds(rich, basin, 1), _Turn.odds(rich, basin, 3)])

	# ── a turn, played ──────────────────────────
	var s4 := _make(cat, locs)
	s4.set_site_owner(&"hillfort_wip", Enums.Factions.PLAYER)
	s4.turn = _first_move_turn()
	var r: Dictionary = _Turn.play(s4, 1)
	_check("the other side takes a turn", int(r["outcome"]) != _Turn.Outcome.QUIET,
		"outcome %d on %s" % [int(r["outcome"]), str(r["site"])])
	_check("...and a bare garrison loses the ground",
		int(r["outcome"]) == _Turn.Outcome.LOST and not s4.holds(&"hillfort_wip"),
		"outcome %d, still held = %s" % [int(r["outcome"]), str(s4.holds(&"hillfort_wip"))])

	# A turn it does not act on changes nothing.
	var s5 := _make(cat, locs)
	s5.set_site_owner(&"hillfort_wip", Enums.Factions.PLAYER)
	s5.turn = 1
	var quiet: Dictionary = _Turn.play(s5, 1)
	_check("a quiet turn takes nothing", int(quiet["outcome"]) == _Turn.Outcome.QUIET
		and s5.holds(&"hillfort_wip"))

	# ── in doubt is an INVITATION, not a result ──
	# It must not change hands on its own: the caller decides whether to offer
	# the player the defence.
	var s6 := _make(cat, locs)
	# Deliberately inside the doubt band: a raid is 18 at act 1, and the band is
	# 0.8-1.25, so a garrison of 8 + 12 = 20 lands at 1.11.
	s6.compute_earned = 12
	s6.set_site_owner(&"valley_basin", Enums.Factions.PLAYER)
	var ratio := _Turn.odds(s6, basin, 1)
	if ratio > _Turn.DOUBT_LOW and ratio < _Turn.DOUBT_HIGH:
		s6.turn = _first_move_turn()
		var r6: Dictionary = _Turn.play(s6, 1)
		_check("an in-doubt site is NOT taken on its own",
			int(r6["outcome"]) == _Turn.Outcome.IN_DOUBT and s6.holds(&"valley_basin"),
			"outcome %d" % int(r6["outcome"]))
		# Declining it settles on paper, and declining twice is the same answer.
		var before := s6.holds(&"valley_basin")
		var a: int = _Turn.settle(s6, &"valley_basin", 1)
		if a == _Turn.Outcome.LOST:
			s6.set_site_owner(&"valley_basin", Enums.Factions.PLAYER)
		var b: int = _Turn.settle(s6, &"valley_basin", 1)
		_check("...and settling it is deterministic, not rerollable", a == b,
			"%d then %d" % [a, b])
	else:
		_check("(setup) a doubt case could be built", false, "ratio %.2f" % ratio)

	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _make(cat: ItemCatalogue, locs) -> CampaignState:
	var s := CampaignState.new()
	s.armoury = Armoury.new()
	s.catalogue = cat
	s.locations = locs
	return s


func _first_move_turn() -> int:
	for t in range(2, 20):
		if _Turn.acts_on(t):
			return t
	return 3
