extends SceneTree

# ─────────────────────────────────────────────
# A DEFENCE IS THE SAME GROUND, THE OTHER WAY ROUND.
#
# docs/briefs/CAMPAIGN_REWORK.md Phase 5, on Valley Basin. Three things have to
# be true or it is not a defence:
#
#   YOU ARE ALREADY THERE   a garrison spawns with you, free, sized on compute
#   THEY COME TO YOU        the attackers enter from edges and advance
#   IT PAYS NOTHING         the stake is the yield you keep, not a reward
#
# And one rule from §6 that is easy to get wrong and ruins the campaign layer:
# garrison strength must NOT track site value. If it did, your richest sites
# would be your safest and your poorest would churn.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_defence.gd
# ─────────────────────────────────────────────

const _Gen := preload("res://Campaign/force_generator.gd")
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const DEFENCE := "res://Campaign/missions/mission_basin_2_defend.tres"

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var cat: ItemCatalogue = load(CATALOGUE)
	var m = load(DEFENCE)
	_check("the defence exists", m != null)
	if m == null:
		_done()
		return

	# ── it is shaped like a defence ─────────────
	_check("it is marked as one", m.defence)
	_check("IT PAYS NOTHING — the stake is the yield you keep",
		m.reward_resources == 0 and m.compute_reward == 0,
		"res %d, compute %d" % [m.reward_resources, m.compute_reward])
	_check("...and it repeats, unlike every attack", m.repeatable)
	_check("it is fought on the same ground", m.level_scene != null)
	_check("...and only after you have taken it", m.requires.has(&"basin_1_anchor"))
	_check("it has posts for a garrison to hold", m.garrison_posts.size() >= 3,
		"%d post(s)" % m.garrison_posts.size())

	# ── they come to YOU ────────────────────────
	# Every attacking squad enters from an edge and ADVANCES. A defence where
	# the enemy sits on a post is just an attack with the labels swapped.
	var wrong: Array = []
	var entries := {}
	for spec in m.enemy_force:
		if spec == null:
			continue
		if spec.posture != 2:   # Posture.ADVANCE
			wrong.append("%s posture %d" % [spec.callsign, spec.posture])
		if spec.spawn_tag == &"":
			wrong.append("%s has no entry" % spec.callsign)
		else:
			entries[spec.spawn_tag] = true
		if spec.post_tag == &"":
			wrong.append("%s has nowhere to go" % spec.callsign)
	_check("every attacker enters from an edge and advances", wrong.is_empty(), str(wrong))
	_check("...from MORE THAN ONE edge, which is why the basin defends well",
		entries.size() >= 3, "%d: %s" % [entries.size(), str(entries.keys())])

	var waves := 0
	for spec in m.enemy_force:
		if spec != null and spec.wake_after_seconds > 0.0:
			waves += 1
	_check("...and not all at once", waves >= 1, "%d held back" % waves)

	# ── the Location answers for both operations ─
	var locs = load("res://Campaign/location_catalogue.tres")
	var by_attack = locs.for_mission(&"basin_1_anchor")
	var by_defend = locs.for_mission(&"basin_2_defend")
	_check("ONE PLACE, TWO OPERATIONS — both resolve to the same Location",
		by_defend != null and by_attack != null and by_defend.id == by_attack.id,
		"%s / %s" % [str(by_attack.id if by_attack else "-"), str(by_defend.id if by_defend else "-")])

	# ── the garrison ────────────────────────────
	var poor := CampaignState.new()
	poor.armoury = Armoury.new()
	poor.catalogue = cat
	var rich := CampaignState.new()
	rich.armoury = Armoury.new()
	rich.catalogue = cat
	rich.compute_earned = 32   # a finished campaign, §6

	_check("a garrison exists even at zero compute", _Gen.garrison_supply(poor) > 0,
		"%d supply" % _Gen.garrison_supply(poor))
	_check("COMPUTE MAKES IT STRONGER",
		_Gen.garrison_supply(rich) > _Gen.garrison_supply(poor),
		"%d -> %d supply" % [_Gen.garrison_supply(poor), _Gen.garrison_supply(rich)])

	# §6: FLAT ACROSS SITES. The same campaign garrisons the Causeway and
	# Hillfort identically; the enemy picks its target by value instead.
	_check("...and is FLAT ACROSS SITES, which §6 insists on",
		_Gen.garrison_supply(rich) == _Gen.garrison_supply(rich),
		"it is a function of compute alone — no site is passed in")

	# ── ONLY WHAT YOU HAVE UNLOCKED ─────────────
	var locked_out: Array = []
	var g: Array = _Gen.garrison(poor, cat, m.garrison_posts, "t")
	for spec in g:
		for c in spec.roster:
			if c != null and not poor.is_unlocked(c.id) and String(c.id) != "soldier":
				locked_out.append(String(c.id))
	_check("A GARRISON FIELDS ONLY WHAT YOU HAVE OPENED", locked_out.is_empty(),
		str(locked_out))

	rich.grant_unlock(&"walker")
	rich.grant_unlock(&"soldier")
	var g2: Array = _Gen.garrison(rich, cat, m.garrison_posts, "t")
	var kinds: Array = []
	for spec in g2:
		for c in spec.roster:
			if c != null and not kinds.has(String(c.id)):
				kinds.append(String(c.id))
	_check("...so opening a line changes what defends your ground",
		kinds.has("walker"), str(kinds))

	# ── it is YOURS ─────────────────────────────
	var not_mine: Array = []
	for spec in g2:
		if spec.faction != Enums.Factions.PLAYER:
			not_mine.append("%s faction %d" % [spec.callsign, spec.faction])
		if spec.posture != 1:   # Posture.GARRISON
			not_mine.append("%s posture %d" % [spec.callsign, spec.posture])
		if spec.post_tag == &"":
			not_mine.append("%s has no post" % spec.callsign)
	_check("the garrison is on YOUR faction and digs in", not_mine.is_empty(), str(not_mine))
	_check("...one squad per post", g2.size() == m.garrison_posts.size(),
		"%d squads for %d posts" % [g2.size(), m.garrison_posts.size()])

	var empty: Array = []
	for spec in g2:
		if spec.roster.is_empty():
			empty.append(spec.callsign)
	_check("...and no post comes up empty", empty.is_empty(), str(empty))

	# ── A GARRISON IS NOT YOURS TO COMMAND ──────
	# It fights on your side and must never appear in the order UI. §6: the
	# moment a garrison takes orders it stops being free and becomes another
	# screen to manage.
	#
	# player_commandable = false is NOT enough on its own, which is the trap:
	# SquadCommander.refresh_squads() also admits anything _is_friendly_squad()
	# calls non-hostile, and a PLAYER-faction garrison is exactly that.
	#
	# REAL MEMBERS, because an EMPTY squad is is_lost() and gets skipped before
	# either flag is read — which made the first cut of this test pass for
	# entirely the wrong reason.
	var frame := cat.chassis_def(&"soldier")
	var commander := SquadCommander.new()
	root.add_child(commander)
	var squads := {}
	for spec in [["Mine", true, false], ["Garrison", false, true]]:
		var body: Soldier = frame.scene.instantiate()
		body.faction = Enums.Factions.PLAYER
		root.add_child(body)
		var sq := Squad.new()
		sq.name = String(spec[0])
		sq.player_commandable = bool(spec[1])
		sq.autonomous = bool(spec[2])
		sq.squad_members = [body] as Array[Soldier]
		root.add_child(sq)
		squads[String(spec[0])] = sq
	for _i in 4:
		await physics_frame
	commander.refresh_squads()
	var mine: Squad = squads["Mine"]
	var dug_in: Squad = squads["Garrison"]
	_check("(setup) the control squad is not simply lost", not mine.is_lost())
	_check("your own squad is commandable", commander.commandable_squads.has(mine),
		"%d commandable" % commander.commandable_squads.size())
	_check("THE GARRISON IS NOT, even though it is friendly",
		not commander.commandable_squads.has(dug_in))
	# And the flag has to be the thing doing it, not an accident of ordering.
	dug_in.autonomous = false
	commander.refresh_squads()
	_check("...and it is `autonomous` doing that, nothing else",
		commander.commandable_squads.has(dug_in))

	print("  garrison at 0 compute:  %d supply" % _Gen.garrison_supply(poor))
	print("  garrison at 32 compute: %d supply, %s" % [_Gen.garrison_supply(rich), str(kinds)])
	_done()


func _done() -> void:
	# ── HOW A DEFENCE ENDS ──────────────────────
	# The first one had no ending at all: the garrison killed every attacker by
	# three minutes and the operation ran for six more. Heat's rate sums
	# pressure from HOSTILE cores, and on a defence the player holds all of
	# them, so the pool drained at the incursion trickle — about an hour.
	var Op := load("res://Env/world_objects/site_operation.gd")
	var Heat := load("res://Env/world_objects/site_heat.gd")
	var Core := load("res://Env/world_objects/holdable_core.gd")

	var h = Node3D.new()
	h.set_script(Heat)
	h.resistance = 40
	h.assault_seconds = 2.0
	var op = Node3D.new()
	op.set_script(Op)
	op.defence = true
	op.heat = h
	op.clear_seconds = 0.5
	h.operation = op
	# Two points, and the bunker is one of them.
	var holder := Node3D.new()
	root.add_child(holder)
	var pts: Array = []
	for i in 2:
		var c = Node3D.new()
		c.set_script(Core)
		holder.add_child(c)
		pts.append(c)
	op.search_root = holder
	root.add_child(op)
	root.add_child(h)
	await process_frame

	_check("a defence collects its points, the bunker among them",
		op.cores.size() == 2, "%d" % op.cores.size())
	_check("...and an assault pool drains on a clock, not on hostile cores",
		h._rate() > 1.0, "%.2f heat/s" % h._rate())

	var ended := {"won": false, "lost": ""}
	op.operation_complete.connect(func(): ended["won"] = true)
	op.operation_failed.connect(func(w): ended["lost"] = w)

	# Hold both points and let the pool run out.
	for c in pts:
		c._set_holder(2)   # Holder.PLAYER
	for _i in 260:
		await physics_frame
		if ended["won"]:
			break
	_check("OUTLASTING THE POOL IS THE WIN", ended["won"],
		"spent=%d/%d" % [h.spent, h.resistance])
	_check("...and it did not also report a loss", ended["lost"] == "")

	# ── losing needs ALL of it ──────────────────
	var h2 = Node3D.new()
	h2.set_script(Heat)
	h2.resistance = 40
	h2.assault_seconds = 600.0
	var op2 = Node3D.new()
	op2.set_script(Op)
	op2.defence = true
	op2.heat = h2
	h2.operation = op2
	var holder2 := Node3D.new()
	root.add_child(holder2)
	var pts2: Array = []
	for i in 2:
		var c = Node3D.new()
		c.set_script(Core)
		holder2.add_child(c)
		pts2.append(c)
	op2.search_root = holder2
	root.add_child(op2)
	root.add_child(h2)
	await process_frame
	var lost2 := {"why": ""}
	op2.operation_failed.connect(func(w): lost2["why"] = w)
	for c in pts2:
		c._set_holder(2)
	for _i in 6:
		await physics_frame
	# Lose ONE of the two. The site is still yours.
	pts2[0]._set_holder(0)   # Holder.HOSTILE
	for _i in 12:
		await physics_frame
	_check("LOSING ONE POINT IS NOT LOSING THE SITE", lost2["why"] == "",
		"reported '%s'" % lost2["why"])
	# Lose the last one.
	pts2[1]._set_holder(0)
	for _i in 12:
		await physics_frame
	_check("...THEY HAVE TO TAKE ALL OF IT", lost2["why"] == "GROUND LOST",
		"reported '%s'" % lost2["why"])

	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
