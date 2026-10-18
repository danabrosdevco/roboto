extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# THE CAMPAIGN SPINE — turns, ownership, and ground that pays.
#
# docs/briefs/CAMPAIGN_REWORK.md Phases 1 and 2. Phase 2's own done-when is the
# spine of this file: "holding a site for three turns pays three times, taking
# it pays compute once, and the board's numbers match the ledger."
#
# THE THING MOST WORTH GUARDING is that ownership is never derived from
# completed_missions. campaign_state.gd warned about that before any of this
# was written — "completed_missions only answers 'ever', which is not enough" —
# and the whole territory layer is meaningless the moment somebody shortcuts it.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_campaign_spine.gd
# ─────────────────────────────────────────────

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var cat = load("res://Campaign/location_catalogue.tres")
	_check("the location catalogue loads", cat != null)
	if cat == null:
		print("")
		print("%d failure(s)" % _fails)
		quit(1)
		return

	var all: Array = cat.all()
	_check("...with the nine places that exist", all.size() == 9, "%d" % all.size())

	# ── the board is a real graph ───────────────
	# Every edge both ways. A one-way connection is a site you can attack but
	# never be attacked from, which breaks the frontier rule in one direction
	# only — the kind of thing nobody notices until Act 2.
	var oneway: Array = []
	for l in all:
		for n in l.connects_to:
			var other = cat.of(n)
			if other == null:
				oneway.append("%s -> %s missing" % [l.id, n])
			elif not other.connects_to.has(l.id):
				oneway.append("%s -> %s" % [l.id, n])
	_check("every connection is mutual", oneway.is_empty(), str(oneway))

	# No island: you must be able to walk the board from the opening site.
	var seen := {}
	var queue: Array = [&"hillfort_wip"]
	while not queue.is_empty():
		var id = queue.pop_front()
		if seen.has(id):
			continue
		seen[id] = true
		var l = cat.of(id)
		if l != null:
			for n in l.connects_to:
				queue.append(n)
	_check("...and every place is reachable from the opening site",
		seen.size() == all.size(), "%d of %d" % [seen.size(), all.size()])

	# ── the numbers are the ones §2 specifies ───
	var res := 0
	var comp := 0
	for l in all:
		res += l.resources_per_turn
		comp += l.compute
	_check("all nine pay what §2 says", res == 230 and comp == 12,
		"%d res/turn, %d compute" % [res, comp])

	# RESISTANCE IS MEASURED, NOT TYPED. Valley Basin's authored force totals
	# 82 supply, which is independently where basin_slice.gd's hardcoded 82
	# came from — two different routes to the same number.
	var basin = cat.for_mission(&"basin_1_anchor")
	_check("a location resolves from its operation", basin != null)
	if basin != null:
		_check("...and its resistance is the measured force", basin.resistance == 82,
			"%d" % basin.resistance)
		_check("...and its degree matches its authored edge markers",
			basin.connects_to.size() == 5, "%d" % basin.connects_to.size())

	# ── state: ownership ────────────────────────
	var s := CampaignState.new()
	s.locations = cat

	_check("a fresh campaign holds nothing", s.held_sites().is_empty(),
		str(s.held_sites()))
	_check("...and every place starts theirs",
		s.site_owner(&"hillfort_wip") == int(Enums.Factions.SWARM),
		"owner = %d" % s.site_owner(&"hillfort_wip"))
	_check("...so it earns nothing per turn", s.income_per_turn() == 0)

	s.set_site_owner(&"hillfort_wip", Enums.Factions.PLAYER)
	_check("taking a place makes it yours", s.holds(&"hillfort_wip"))
	_check("...recorded against the turn it was taken",
		s.site_since(&"hillfort_wip") == 0, "turn %d" % s.site_since(&"hillfort_wip"))
	_check("...and it pays its rate", s.income_per_turn() == 8,
		"%d/turn" % s.income_per_turn())
	_check("...and its compute is yours, derived not banked",
		s.site_compute() == 1, "%d" % s.site_compute())

	# ── PHASE 2's done-when, exactly ────────────
	# "holding a site for three turns pays three times"
	var before := s.available()
	for _i in 3:
		s.advance_turn()
	_check("holding a site for three turns pays three times",
		s.available() - before == 24, "%d earned over 3 turns" % (s.available() - before))
	_check("...and the turn counter moved three", s.turn == 3, "turn %d" % s.turn)

	# Losing it stops the income AND takes the compute back, in full.
	s.set_site_owner(&"hillfort_wip", Enums.Factions.SWARM)
	_check("losing it stops the income", s.income_per_turn() == 0)
	_check("...and takes the compute with it, all of it", s.site_compute() == 0)
	var after_loss := s.available()
	s.advance_turn()
	_check("...so a turn after losing it pays nothing",
		s.available() == after_loss, "%d -> %d" % [after_loss, s.available()])

	# ── ownership is NOT completed_missions ─────
	# The trap Phase 1 names outright. A cleared operation whose site was lost
	# again must read as theirs, or the whole layer is decoration.
	s.completed_missions.append(&"hfw_1_fort")
	_check("a cleared operation does NOT mean you hold the ground",
		not s.holds(&"hillfort_wip"),
		"completed_missions has it; sites says owner %d" % s.site_owner(&"hillfort_wip"))

	# ── it survives the save ────────────────────
	s.set_site_owner(&"valley_basin", Enums.Factions.PLAYER)
	s.set_site_owner(&"coast_road", Enums.Factions.HOME)
	var round_trip := CampaignState.from_dict(s.to_dict())
	round_trip.locations = cat
	_check("turn survives a save round-trip", round_trip.turn == s.turn,
		"%d vs %d" % [round_trip.turn, s.turn])
	_check("...and so does who holds what",
		round_trip.holds(&"valley_basin")
		and round_trip.site_owner(&"coast_road") == int(Enums.Factions.HOME)
		and not round_trip.holds(&"hillfort_wip"),
		str(round_trip.sites))
	_check("...and the income it implies", round_trip.income_per_turn() == 13,
		"%d/turn" % round_trip.income_per_turn())

	# A SAVE FROM BEFORE ANY OF THIS loads with an empty board and reads every
	# place as its authored owner, which is why no migration was needed.
	var old := s.to_dict()
	old.erase("sites")
	old.erase("turn")
	var legacy := CampaignState.from_dict(old)
	legacy.locations = cat
	_check("a save with no territory at all still loads",
		legacy.turn == 0 and legacy.sites.is_empty())
	_check("...and reads every place as its authored owner",
		legacy.site_owner(&"valley_basin") == int(Enums.Factions.SWARM)
		and legacy.income_per_turn() == 0)

	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
