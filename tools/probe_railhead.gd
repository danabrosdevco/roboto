extends SceneTree

# ─────────────────────────────────────────────
# IS ANYTHING IN THE DEPOT STANDING IN THE WRONG PLACE?
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_railhead.gd
#
# The railhead art was rebuilt to shorten the walk between the things you use
# between missions. Every gameplay node in here is placed off a NAMED MARKER in
# that art (railhead_level.gd, the M_* constants), which is the right design —
# move the marker and the gameplay follows. What it does not survive is a
# marker being RENAMED or DROPPED: the level warns and then simply has no
# operations table, and a warning in a 400-line boot log is not a thing anyone
# sees.
#
# So this loads the real level, lets it settle, and reports what is actually in
# the tree, where, and how far apart. The distances are the point: "the walk
# out the door was way too long" is a measurement, and it should be possible to
# check it without playing.
# ─────────────────────────────────────────────

const WANT := {
	"OpsTable": "the operations table",
	"DepartureLever": "the lever that calls the train",
}

var _fails := 0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	var level = load("res://maps/railhead_level.tscn").instantiate()
	root.add_child(level)
	for _i in 120:
		await physics_frame

	print("── WHAT IS IN THE DEPOT ──")
	var at := {}
	for name in WANT:
		var n = _find(level, name)
		if n == null:
			print("MISSING  %s (%s)" % [name, WANT[name]])
			_fails += 1
			continue
		at[name] = (n as Node3D).global_position
		print("  %-16s %s   %v" % [name, WANT[name], at[name]])

	# The door you leave by, and the pad the train stops at.
	for group in ["levelexit", "departure_exits"]:
		for e in level.get_tree().get_nodes_in_group(group):
			if is_instance_valid(e) and e is Node3D:
				at[e.name] = e.global_position
				print("  %-16s %s   %v" % [e.name, "(%s)" % group, e.global_position])

	# THE LEVEL'S OWN NODES, through its exported paths, NOT by name. The art
	# still carries markers called "SquadMuster" and "PlatformDoor_Outside" at
	# the old end of the train, and a name search finds those first: this
	# reported the muster 60 m away minutes after it had been moved to 34.
	for pair in [["muster", "where the squad forms up"], ["departure", "the way out"]]:
		var n = level.get(pair[0])
		if n == null or not (n is Node3D):
			print("MISSING  %s (%s)" % [pair[0], pair[1]])
			_fails += 1
			continue
		at[String((n as Node3D).name)] = (n as Node3D).global_position
		print("  %-16s %s   %v" % [(n as Node3D).name, pair[1], (n as Node3D).global_position])

	var spawn = _find(level, "SpawnPoint")
	if spawn != null:
		print("  %-16s %s   %v" % ["SpawnPoint", "where you arrive", (spawn as Node3D).global_position])
	if spawn != null:
		at["SpawnPoint"] = (spawn as Node3D).global_position

	# ── THE WALK, which is what was complained about ──
	print("")
	print("── THE WALK ──")
	_leg(at, "SpawnPoint", "OpsTable", "arrive -> choose an operation")
	_leg(at, "OpsTable", "DepartureLever", "choose -> call the train")
	_leg(at, "OpsTable", "SquadMuster", "choose -> your squad")
	_leg(at, "SpawnPoint", "DepartureExit", "arrive -> out the door")


	# ── CAN YOU ACTUALLY GET THERE ──────────────
	# Distance is only half of it: a point 34 m away on the far side of a wall
	# is further than one 60 m away down a corridor. The navmesh is the only
	# clearance this project enforces, so the walk is measured on it.
	print("")
	print("── ON THE NAVMESH ──")
	var region = _find(level, "NavigationRegion3D")
	var baked := false
	if region != null:
		var m: RID = (region as NavigationRegion3D).get_navigation_map()
		# THE DEPOT IS DELIBERATELY NOT BAKED. Only the player moves at base:
		# the squad is posted to its barracks racks and stands there, so there
		# is nothing to path and no bake to keep up to date. Detected rather
		# than assumed so this prints a plain note instead of five NO ROUTE
		# lines that look like a regression.
		#
		# An empty map answers every query with the origin, which is why an
		# unbaked region reads as "32 m off the bake" for a point at z -32.
		var probe := NavigationServer3D.map_get_closest_point(m, Vector3(0, 1.19, -32))
		baked = probe.distance_to(Vector3(0, 1.19, -32)) < 5.0
	if region == null:
		print("  (no NavigationRegion3D, so nothing can be path-checked)")
	elif not baked:
		print("  Not baked, which is correct: only the player moves at base, so")
		print("  there is nothing here to path. Distances above are the measure.")
	else:
		var map: RID = (region as NavigationRegion3D).get_navigation_map()
		var from: Vector3 = at.get("SpawnPoint", Vector3.ZERO)
		for name in at:
			if name == "SpawnPoint":
				continue
			var to: Vector3 = at[name]
			var on := NavigationServer3D.map_get_closest_point(map, to)
			var path := NavigationServer3D.map_get_path(map, from, to, true)
			var walked := 0.0
			for i in range(1, path.size()):
				walked += path[i - 1].distance_to(path[i])
			var lands: bool = path.size() > 1 and path[-1].distance_to(to) <= 6.0
			print("  %-22s %s  %5.1f m walked  (%.1f m off the bake)%s" % [
				name, "reachable" if lands else "NO ROUTE",
				walked, to.distance_to(on), "" if lands else "   <<<"])
			if not lands:
				_fails += 1

	# ── AND THAT EVERYTHING STANDS ON SOMETHING ──
	print("")
	print("── FOOTING ──")
	var space := root.world_3d.direct_space_state
	for name in at:
		var p: Vector3 = at[name]
		# FROM JUST ABOVE THE NODE, not 8 m up: these are inside a train car and a
		# cast that starts above the roof measures the roof. Cost one reading of
		# "4.30 m above the floor" for a table sitting flat on it.
		var q := PhysicsRayQueryParameters3D.create(
			p + Vector3(0, 0.4, 0), p - Vector3(0, 8, 0))
		var h := space.intersect_ray(q)
		if h.is_empty():
			print("  NO FLOOR under %s at %v — it is standing in the air" % [name, p])
			_fails += 1
		else:
			var drop: float = p.y - h.position.y
			print("  %-16s floor %.2f m %s" % [name, absf(drop),
				"below" if drop >= 0.0 else "ABOVE IT (sunk)"])

	print("")
	print("%d problem(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _leg(at: Dictionary, a: String, b: String, what: String) -> void:
	if not at.has(a) or not at.has(b):
		print("  (cannot measure %s: %s)" % [what,
			"no " + (a if not at.has(a) else b)])
		return
	var d: float = Vector3(at[a]).distance_to(at[b])
	print("  %5.1f m  %s" % [d, what])


func _find(n: Node, named: String) -> Node:
	if n.name == named:
		return n
	for c in n.get_children():
		var hit := _find(c, named)
		if hit != null:
			return hit
	return null
