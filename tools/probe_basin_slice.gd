extends SceneTree
# Boots Valley Basin for real and asks whether the slice assembled itself.
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_basin_slice.gd
var _fail := 0
func _c(l: String, ok: bool, d: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", l, ("  " + d) if d != "" else ""])
	if not ok:
		_fail += 1
func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var lvl: Node = load("res://maps/valley_basin_level.tscn").instantiate()
	root.add_child(lvl)
	for _i in 60:
		await physics_frame
	var slice := lvl.get_node_or_null(^"BasinSlice")
	_c("the slice node is in the level", slice != null)
	if slice == null:
		print("")
		quit(1)
		return
	_c("it seated four holdable cores", slice.cores.size() == 4, "%d" % slice.cores.size())
	_c("...each with a terminal it can read", _all_wired(slice.cores))
	_c("the operation exists", slice.operation != null)
	_c("...and found the bunker", slice.operation != null and slice.operation.bunker != null)
	# PLACEMENT IS PART OF THE WIRING. A bunker in the air or off the navmesh is
	# a test that fails for a reason that has nothing to do with the design.
	var bh := slice.get_node_or_null(^"BasinBunker")
	if bh != null:
		var at: Vector3 = bh.global_position
		var maps := NavigationServer3D.get_maps()
		var off := 999.0
		if not maps.is_empty():
			off = NavigationServer3D.map_get_closest_point(maps[0], at).distance_to(at)
		_c("...and the bunker is on reachable ground", off < 2.0,
			"%v, %.2f m off the navmesh" % [at, off])
	_c("...and counts the four cores, bunker excluded",
		slice.operation != null and slice.operation.cores.size() == 4,
		"%d" % (slice.operation.cores.size() if slice.operation != null else -1))
	_c("...with all of them hostile at the start",
		slice.operation != null and slice.operation.hostile_cores() == 4)
	_c("heat exists and is pooled from the authored force",
		slice.heat != null and int(slice.heat.resistance) == 82,
		"%d supply" % (slice.heat.resistance if slice.heat != null else -1))
	_c("...and is emitting hard, because every core is theirs",
		slice.heat != null and slice.heat._rate() > 1.0,
		"%.2f a second" % (slice.heat._rate() if slice.heat != null else 0.0))
	var took_over := true
	for c in slice.cores:
		if c.interactible == null or int(c.interactible.collision_layer) != 3:
			took_over = false
	_c("...and the cores took their terminals over on layer 3", took_over)
	# THE ONE THAT MATTERS. If the authored InteractObjective is still connected,
	# the old mission completes underneath the new one and the map plays exactly
	# as it always did.
	var sole := true
	var others := 0
	for c in slice.cores:
		if c.interactible == null:
			continue
		for conn in c.interactible.interacted.get_connections():
			if conn["callable"].get_object() != c:
				sole = false
				others += 1
	_c("...and NOTHING ELSE is still listening to those terminals", sole,
		"%d foreign handler(s)" % others)

	# VISIBLE, AND WIRED TO THE HUD. The first playtest found neither.
	var bodied := 0
	for c in slice.cores:
		if c.get_parent().get_node_or_null(^"CoreBody") != null:
			bodied += 1
	_c("every core has geometry to walk up to", bodied == slice.cores.size(),
		"%d of %d" % [bodied, slice.cores.size()])

	# REACH. A volume that stops 3 m up on a 12.4 m core is one you can see and
	# cannot use — which is what the second playtest hit on the anchor.
	var reach_ok := true
	var worst := ""
	for c in slice.cores:
		var cs: CollisionShape3D = null
		for ch in c.interactible.get_children():
			if ch is CollisionShape3D:
				cs = ch
		if cs == null or not (cs.shape is BoxShape3D):
			reach_ok = false
			continue
		var tall: float = [4.19, 6.97, 12.38][clampi(int(c.size_tier), 0, 2)]
		if (cs.shape as BoxShape3D).size.y < tall - 0.1:
			reach_ok = false
			worst = "%s: box %.1f m vs core %.1f m" % [c.get_parent().name, (cs.shape as BoxShape3D).size.y, tall]
	_c("...and an interact volume that covers its full height", reach_ok, worst)

	# ── DOES THE BUNKER TAP ACTUALLY ARRIVE ──────
	var bhold = slice.operation.bunker
	_c("the bunker starts hostile and untapped",
		not bhold.is_held_by_player() and bhold._tap == null)
	bhold._call_tap()
	await physics_frame
	var tap = bhold._tap
	_c("...calling a tap spawns one", tap != null)
	if tap != null:
		var start: Vector3 = tap.global_position
		var dock: Vector3 = bhold.global_position + Vector3(0.0, bhold.dock_height, 0.0)
		_c("...which starts ABOVE and ACROSS, not directly overhead",
			start.y > dock.y + 5.0 and Vector2(start.x - dock.x, start.z - dock.z).length() > 4.0,
			"starts %.1f m up, %.1f m out" % [start.y - dock.y,
				Vector2(start.x - dock.x, start.z - dock.z).length()])
		var moved := false
		var prev: Vector3 = start
		for _i in 20:
			await physics_frame
			if is_instance_valid(tap) and tap.global_position.distance_to(prev) > 0.01:
				moved = true
			if is_instance_valid(tap):
				prev = tap.global_position
		_c("...and it is MOVING, not parked", moved)
		# The pod frees itself on landing and leaves a CaptureAnchor, so what is
		# checked from here is the structure, not the delivery.
		for _i in 400:
			await physics_frame
			if bhold.is_held_by_player():
				break
		_c("...and it lands, leaving an anchor",
			bhold._anchor != null and is_instance_valid(bhold._anchor))
		if bhold._anchor != null and is_instance_valid(bhold._anchor):
			# AT THE FOOT OF THE CORE, WHERE IT CAN BE SHOT.
			#
			# This used to assert the anchor sat on the DOCK POINT, on the
			# core's head — 4 to 12 metres up. That is where the tap lands and
			# it is the wrong place for the structure: ground units stand at
			# the base looking almost vertically up, outside their aim cone,
			# and melee cannot reach at all. Watched on a defence: eighty-three
			# attackers stood around four objectives they could not take.
			var lift: float = bhold._anchor.global_position.y - bhold.global_position.y
			_c("the anchor stands at the FOOT of the core, not on its head",
				lift < 2.0, "%.2f m above the deck (dock is %.2f)" % [lift, bhold._dock_y()])
			_c("...which is where a ground unit can actually shoot it",
				lift < bhold._dock_y())
			_c("...and it is a body the AI can target",
				bhold._anchor is CharacterBody3D and int(bhold._anchor.faction) == int(Enums.Factions.PLAYER))
		_c("...and the bunker is then HELD", bhold.is_held_by_player())

	# The bunker as a HUD line.
	var bobj := slice.get_node_or_null(^"BunkerObjective")
	_c("the bunker has an objective row", bobj != null)
	if bobj != null:
		_c("...in the tracker group, so the HUD and minimap see it",
			bobj.is_in_group("mission_objectives"))
		_c("...reporting the stand-down as its progress",
			bobj.progress() == [0, 100], str(bobj.progress()))

	var first = slice.cores[0]
	var authored = first.get_parent()
	_c("the authored objective starts incomplete", not authored.completed)
	first._set_holder(first.Holder.PLAYER)
	await physics_frame
	_c("...holding the core COMPLETES it, so the HUD ticks", authored.completed)
	first._set_holder(first.Holder.NEUTRAL)
	await physics_frame
	_c("...and LOSING it un-completes it, which nothing in this game could do",
		not authored.completed and authored.active)
	# HEAT NOW HAS TEETH. Without a commander it drained its reserve and nothing
	# arrived, which is exactly how the first playtest ran.
	var cmd = slice.commander
	_c("an enemy commander is fitted", cmd != null)
	if cmd != null:
		_c("...wired to heat, so commitments reach it", cmd.heat == slice.heat)
		_c("...with entry points away from the fight",
			cmd.entry_markers.size() > 0, "%d marker(s)" % cmd.entry_markers.size())
		# The spawner is a child of World, and this probe instantiates the level
		# alone — so there is nothing to find here and that is correct. Whether a
		# commitment actually puts bodies on the map is tested in
		# tools/test_enemy_commander.gd, which boots the whole game.
		_c("...and it picks a squad for a 6-supply commitment",
			not cmd._pick(6).is_empty(), str(cmd._pick(6).get("label", "-")))

	print("")
	print("%d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)
func _all_wired(cores: Array) -> bool:
	for c in cores:
		if c.interactible == null:
			return false
	return true
