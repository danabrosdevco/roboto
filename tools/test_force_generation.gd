extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# THE SAME GROUND, A DIFFERENT ARMY.
#
# docs/briefs/CAMPAIGN_REWORK.md Phase 4. Its own done-when is the spine of
# this file: "the same site produces a visibly different force in act 1 and
# act 3, and the authored set-pieces still fire in the authored order."
#
# The second half is the one worth guarding. Generated encounters are reliably
# worse than authored ones, and the mitigation is that only the COMPOSITION is
# generated — every tag, posture and wake trigger the map author wrote has to
# survive untouched, or Coast Road stops being bombers-then-armour and becomes
# a pile of robots.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_force_generation.gd
# ─────────────────────────────────────────────

const _Gen := preload("res://Campaign/force_generator.gd")
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var cat: ItemCatalogue = load(CATALOGUE)
	var locs = load("res://Campaign/location_catalogue.tres")
	var basin = locs.for_mission(&"basin_1_anchor")
	var mission = load("res://Campaign/missions/mission_basin_1_anchor.tres")
	var authored: Array = []
	for s in mission.enemy_force:
		if s != null:
			authored.append(s)
	_check("the basin has an authored force to work from", authored.size() > 0,
		"%d spec(s)" % authored.size())

	# ── the budget ──────────────────────────────
	var a1: int = _Gen.budget(basin, 1, Enums.Factions.SWARM)
	var a3: int = _Gen.budget(basin, 3, Enums.Factions.SWARM)
	_check("ACT 1 IS THE AUTHORED NUMBER, so the shipped maps need no re-tuning",
		a1 == basin.resistance, "%d vs measured %d" % [a1, basin.resistance])
	_check("...and act 3 is harder", a3 > a1, "%d -> %d supply" % [a1, a3])
	_check("Home Command garrisons harder than the Swarm",
		_Gen.budget(basin, 2, Enums.Factions.HOME) > _Gen.budget(basin, 2, Enums.Factions.SWARM))

	# ── the tiers ───────────────────────────────
	_check("act 1 fields only tier 1", _Gen.tiers_for(1) == [1], str(_Gen.tiers_for(1)))
	_check("act 3 fields everything", _Gen.tiers_for(3).size() == 3)

	# ── THE AUTHORED SHAPE SURVIVES ─────────────
	var made: Array = _Gen.compose(authored, basin, 1, Enums.Factions.SWARM, cat, "t/1")
	_check("every authored squad is still there", made.size() == authored.size(),
		"%d -> %d" % [authored.size(), made.size()])

	var drift: Array = []
	for i in authored.size():
		var a = authored[i]
		var b = made[i]
		if a.callsign != b.callsign: drift.append("%s callsign" % a.callsign)
		if a.posture != b.posture: drift.append("%s posture" % a.callsign)
		if a.post_tag != b.post_tag: drift.append("%s post_tag" % a.callsign)
		if a.route_tag != b.route_tag: drift.append("%s route_tag" % a.callsign)
		if a.spawn_tag != b.spawn_tag: drift.append("%s spawn_tag" % a.callsign)
		if a.wake_after_kills != b.wake_after_kills: drift.append("%s wake_kills" % a.callsign)
		if a.wake_after_seconds != b.wake_after_seconds: drift.append("%s wake_secs" % a.callsign)
		if a.always_active != b.always_active: drift.append("%s always_active" % a.callsign)
	_check("THE MAP'S OWN SHAPE IS UNTOUCHED — tags, postures, wake triggers",
		drift.is_empty(), str(drift))

	# AND THE AUTHORED RESOURCE IS NOT MUTATED. A MissionDefinition is a .tres
	# shared by every play of that operation; writing a generated roster into it
	# would persist into the next one and into the editor.
	var still_authored := true
	for i in authored.size():
		if authored[i] == made[i]:
			still_authored = false
	_check("...and the authored specs are not the same objects", still_authored)

	# ── the composition DOES change ─────────────
	var act3: Array = _Gen.compose(authored, basin, 3, Enums.Factions.SWARM, cat, "t/1")
	var s1 := _supply(made)
	var s3 := _supply(act3)
	_check("ACT 3 PUTS MORE ON THE GROUND", s3 > s1, "%d -> %d supply" % [s1, s3])
	_check("...and roughly what the budget asked for",
		absi(s1 - a1) <= maxi(4, a1 / 8), "%d fielded against a budget of %d" % [s1, a1])

	var kinds1 := _kinds(made)
	var kinds3 := _kinds(act3)
	_check("...with frames act 1 never sees", kinds3.size() > kinds1.size()
		or kinds3 != kinds1, "act1 %s | act3 %s" % [str(kinds1), str(kinds3)])

	# ── the proportions hold ────────────────────
	# A spec authored small stays small. Scaling every squad to the same size
	# would flatten the map's own pacing, which is the other way this breaks.
	var big_a := 0
	var small_a := 0
	var big_m := 0
	var small_m := 0
	var order: Array = []
	for i in authored.size():
		order.append([_spec_supply(authored[i]), i])
	order.sort_custom(func(x, y): return int(x[0]) < int(y[0]))
	if order.size() >= 2:
		small_a = int(order[0][0])
		big_a = int(order[order.size() - 1][0])
		small_m = _spec_supply(made[int(order[0][1])])
		big_m = _spec_supply(made[int(order[order.size() - 1][1])])
		_check("the biggest authored squad is still the biggest", big_m >= small_m,
			"smallest %d->%d, biggest %d->%d" % [small_a, small_m, big_a, big_m])

	# ── HOME COMMAND FIELDS YOUR OWN FRAMES ─────
	var home: Array = _Gen.compose(authored, basin, 2, Enums.Factions.HOME, cat, "t/1")
	var player_frames: Array = []
	var swarm_only: Array = []
	for spec in home:
		for c in spec.roster:
			if c == null:
				continue
			if c.purchasable:
				if not player_frames.has(String(c.id)):
					player_frames.append(String(c.id))
			elif not swarm_only.has(String(c.id)):
				swarm_only.append(String(c.id))
	_check("Home Command fields frames the PLAYER can build", not player_frames.is_empty(),
		str(player_frames))
	_check("...and nothing the Swarm fields", swarm_only.is_empty(), str(swarm_only))

	# ── nothing comes up empty ──────────────────
	var empties: Array = []
	for spec in made:
		if spec.roster.is_empty():
			empties.append(spec.callsign)
	_check("no post the map says is defended comes up empty", empties.is_empty(), str(empties))
	_check("...and body_count() agrees with the roster, with nothing else to ask",
		_counts_agree(made), "body_count() and roster.size() must not disagree")

	# ── seeded ──────────────────────────────────
	var again: Array = _Gen.compose(authored, basin, 1, Enums.Factions.SWARM, cat, "t/1")
	_check("the same seed builds the same force", _supply(again) == s1,
		"%d vs %d" % [_supply(again), s1])

	# ── no location, no harm ────────────────────
	var none: Array = _Gen.compose(authored, null, 1, Enums.Factions.SWARM, cat, "t/1")
	_check("a site with no Location keeps its authored force untouched",
		none.size() == authored.size() and none[0] == authored[0])

	print("")
	print("  act 1: %d supply, %s" % [s1, str(_kinds(made))])
	print("  act 3: %d supply, %s" % [s3, str(_kinds(act3))])
	print("  home2: %d supply, %s" % [_supply(home), str(_kinds(home))])
	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _spec_supply(spec) -> int:
	var n := 0
	for c in spec.roster:
		if c != null:
			n += int(c.supply)
	return n


func _supply(specs: Array) -> int:
	var n := 0
	for s in specs:
		n += _spec_supply(s)
	return n


func _kinds(specs: Array) -> Array:
	var seen := {}
	for s in specs:
		for c in s.roster:
			if c != null:
				seen[String(c.id)] = true
	var k: Array = seen.keys()
	k.sort()
	return k


## Was `s.count != s.roster.size()`, guarding a generated spec against leaving
## the legacy `count` field disagreeing with the roster beside it. The field
## went with H9, so the question became the weaker but still real one: the one
## remaining way to ask "how many bodies" has to answer off the roster.
func _counts_agree(specs: Array) -> bool:
	for s in specs:
		if s.body_count() != s.roster.size():
			return false
	return true
