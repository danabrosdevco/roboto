extends SceneTree

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

	print("")
	print("%d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)


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
