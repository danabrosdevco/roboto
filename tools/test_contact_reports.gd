extends SceneTree
# BUCKET: frames

# ─────────────────────────────────────────────
# THE SQUAD'S SIGHTINGS REACH THE SCREEN.
#
# The pinned contact mark was written against SquadCommander._call_contact,
# which is only reached by Verb.CONTACT — and NOTHING ISSUES THAT VERB. The
# player's vocabulary was cut to ADVANCE and FOLLOW and CONTACT lost its input
# along with it, so the entire report layer was unreachable: no mark ever
# appeared in a real mission, however well it rendered when a tool called it
# by hand.
#
# That is exactly the class of bug a shot script cannot catch, because a shot
# script calls the function. This one never calls it. It puts a hostile in
# front of the squad and waits to see whether a mark appears on its own.
#
#   1. a squadmate seeing a hostile produces a pinned mark
#   2. ONE mark per body, however long it stays in view — not one per frame
#   3. the mark sits on the hostile's position, not at the origin
#   4. it is pinned and ages, rather than being a live tracking bracket
#
#   godot --headless --audio-driver Dummy --path . --script tools/test_contact_reports.gd -- --no-save
# ─────────────────────────────────────────────

const LEVEL := "res://maps/mutaha_wip_level.tscn"
const HOSTILE := "res://Character/characters/ai/soldier_rifle.tscn"

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fail += 1


func _init() -> void:
	# PACE THE LOOP — see the note in tools/test.sh. Without this a
	# --script run has no frame cap, _process spins flat out and starves
	# physics, and every await physics_frame below takes far longer in
	# wall clock than the 1/60 s it is written as.
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 90:
		await physics_frame
	var player: Node3D = world.player
	var level: Node = player.get_parent()
	level.add_child(load(LEVEL).instantiate())
	for _i in 150:
		await physics_frame
	for who in PauseHold.holders():
		PauseHold.release(who)

	var hud := _find_hud(root)
	if hud == null:
		print("FAIL  no HUD to report to")
		quit(1)
		return
	_check("(setup) the HUD is listening for contacts",
		world.ai_manager != null and world.ai_manager.contact_seen.get_connections().size() > 0,
		"%d listener(s)" % (world.ai_manager.contact_seen.get_connections().size() if world.ai_manager != null else 0))

	var nmap: RID = player.get_world_3d().navigation_map
	var centre: Vector3 = NavigationServer3D.map_get_closest_point(nmap, Vector3(300, 0, 250))
	player.global_position = centre + Vector3.UP * 1.2
	for _i in 20:
		await physics_frame

	# Put the squad where it can see, and a hostile in front of it. Nothing
	# below calls mark_contact — if a mark appears, the squad reported it.
	var squads := root.get_tree().get_nodes_in_group("squads")
	var mates: Array = []
	for s in squads:
		for m in s.squad_members:
			if m != null and is_instance_valid(m) and m.alive:
				mates.append(m)
	_check("(setup) there is a squad to do the seeing", mates.size() > 0,
		"%d alive" % mates.size())
	for i in mates.size():
		mates[i].global_position = centre + Vector3(float(i) * 2.0 - 3.0, 0.0, 2.0)

	var bot = load(HOSTILE).instantiate()
	level.add_child(bot)
	await process_frame
	var where: Vector3 = centre + Vector3(0.0, 0.0, -14.0)
	bot.global_position = where
	bot.faction = Enums.Factions.ENEMY
	bot.player = player
	bot.ai_manager = world.ai_manager
	if world.ai_manager.has_method("register_enemy"):
		world.ai_manager.register_enemy(bot)
	bot.exempt_from_culling(10000.0)
	bot.health = 100000000
	bot.max_health = 100000000
	bot.change_ai_state(Enemy.AIState.IDLE)
	bot.exit_passive_mode()

	# Waited until a mark appears rather than for a fixed window, and the
	# position is read AT THAT MOMENT. These hostiles walk: seven seconds
	# after being sighted this one was 12 m from where the report was filed,
	# and the first cut of this test called that a failure. It is the feature
	# — a report is a place and a time, and it stops following the thing the
	# instant the squad loses it.
	var before := _marks(hud).size()
	var marks: Array = []
	var waited := 0
	var seen_at := Vector3.ZERO
	while waited < 420:
		await physics_frame
		waited += 1
		marks = _marks(hud)
		if marks.size() > before:
			seen_at = bot.global_position
			break
	var settle := waited

	# ── 1 & 2 ───────────────────────────────────
	_check("a squadmate seeing a hostile puts a mark on screen", marks.size() > before,
		"%d before, %d after, took %d frames" % [before, marks.size(), settle])
	# Keep watching while it stays in view. Without the dedupe this grows by
	# one Control per sighting, which on a hostile standing in the open is one
	# per frame.
	for _i in 300:
		await physics_frame
	var later := _marks(hud)
	_check("...and still exactly one five seconds later, not one per frame",
		later.size() - before <= 1,
		"%d marks after five more seconds in view" % (later.size() - before))
	marks = later

	if marks.is_empty():
		print("")
		print("%d failure(s)" % _fail)
		quit(1)
		return

	# ── 3 & 4 ───────────────────────────────────
	var m = marks[marks.size() - 1]
	_check("the mark is pinned, not a live tracking bracket", bool(m.pinned))
	# Against where the hostile WAS when the report was filed, not where it is
	# now. A real position rather than the origin is what this is testing.
	var off: float = (m.world_point as Vector3).distance_to(seen_at)
	_check("...and it was filed at the hostile's real position", off < 6.0,
		"%.1f m from where it stood when reported" % off)
	_check("...and it is NOT at the world origin, which is what a missing position looks like",
		(m.world_point as Vector3).length() > 1.0)
	_check("...and it is showing its age", bool(m.show_age))

	_check_sky_callout_pays(world, player)

	print("")
	print("%d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────
# A CALLOUT COSTS THE SAME WHICHEVER ROUTE IT TOOK (Backlog OA7).
#
# There are two. _issue_order(Verb.CONTACT, …) is one; the other is
# _issue_contextual_order() with the aim ray on open sky, which called
# _call_contact() DIRECTLY — past the link check, past _transmit(), so no
# integrity spent, no wavefront, no hostile told. A free callout, in the same
# function as a comment reading "EVERY VERB PAYS".
#
# Measured as integrity spent, because that is the cost the player feels and
# the one _transmit() is the only source of.
# ─────────────────────────────────────────────
func _check_sky_callout_pays(world: Node, player: Node3D) -> void:
	var cmd: SquadCommander = null
	for c in player.get_children():
		if c is SquadCommander:
			cmd = c as SquadCommander
			break
	if cmd == null:
		_check("(setup) the player has a SquadCommander to call contacts with", false)
		return
	if cmd.tx_signal_cost <= 0.0:
		_check("(setup) a transmission costs something, or this measures nothing",
			false, "tx_signal_cost %.3f" % cmd.tx_signal_cost)
		return

	# Full link both times: link_down() now refuses a sky callout as well, and a
	# refusal would read as "costs nothing" and pass for the wrong reason.
	player.signal_integrity = 1.0
	var at: Vector3 = player.global_position + Vector3(0, 0, 40)
	cmd._call_contact(at, null)
	var sky_spent: float = 1.0 - player.signal_integrity

	player.signal_integrity = 1.0
	cmd._transmit(SquadCommander.Verb.CONTACT, at)
	var ordered_spent: float = 1.0 - player.signal_integrity

	_check("a callout at open sky costs integrity, like any other transmission",
		sky_spent > 0.0, "spent %.4f" % sky_spent)
	_check("...and exactly what the ordered route costs, not a discount",
		absf(sky_spent - ordered_spent) < 0.0001,
		"sky %.4f vs ordered %.4f" % [sky_spent, ordered_spent])

	# MOVING THE CHARGE MUST NOT DOUBLE IT. _issue_order now skips _transmit for
	# CONTACT and lets _call_contact do it; if the skip were ever dropped, this
	# route would pay twice and nothing else would notice.
	if cmd.get_selected_squad() != null:
		player.signal_integrity = 1.0
		cmd._issue_order(SquadCommander.Verb.CONTACT, at, null)
		var ordered_route: float = 1.0 - player.signal_integrity
		_check("the ordered route charges once, not once per _transmit call",
			absf(ordered_route - ordered_spent) < 0.0001,
			"spent %.4f, one transmission is %.4f" % [ordered_route, ordered_spent])
	else:
		_check("(skipped) no squad selected, so the ordered route is not measured here",
			true, "select a squad in this rig to cover it")

	# And it is refused outright on a dead link, which the sky branch also used
	# to walk straight past.
	player.signal_integrity = 1.0
	cmd._resync_t = 5.0
	cmd._call_contact(at, null)
	_check("...and a dead link refuses it rather than charging for it",
		is_equal_approx(player.signal_integrity, 1.0),
		"integrity %.4f" % player.signal_integrity)
	cmd._resync_t = 0.0


func _marks(hud: Node) -> Array:
	var out: Array = []
	for c in hud.get_children():
		if c is ScanEnemyMarker and c.pinned:
			out.append(c)
	return out


func _find_hud(n: Node) -> Node:
	if n.has_method("set_signal") and n.has_method("register_hit"):
		return n
	for c in n.get_children():
		var f := _find_hud(c)
		if f != null:
			return f
	return null
