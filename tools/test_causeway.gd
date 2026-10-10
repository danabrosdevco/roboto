extends SceneTree

# ─────────────────────────────────────────────
# CAUSEWAY AND FORT TESTS
#
# The causeway is the map: if the squad cannot walk it, there is no mission.
# Its sections butt end to end rather than carrying ramps of their own, so
# nothing about one section on its own proves anything — the join is what
# breaks. A section 1/32 m out leaves a lip the navmesh will not climb, and a
# broken span with its lane too narrow leaves a gap that looks crossable and
# is not.
#
# So this lays a whole causeway — ramp, three spans including the cracked and
# the broken one, ramp — bakes a navmesh over it, and walks it end to end. Then
# it does the same for the keep: in through the gate, across the yard, down the
# pit to the portal, all of it wide enough for the rover.
#
# Agent settings match the levels: 0.6 m radius, 1.5 m tall, 0.25 m climb.
# ─────────────────────────────────────────────

const CAUSEWAY_DIR := "res://maps/blocks/causeway"
const FORT := "res://maps/blocks/fortress/fort_keep.tscn"
## The section length the pieces are built to. Sections sit this far apart.
const SECTION := 48.0
## How wide a way through has to be for the rover and anything larger.
const ROVER_W := 6.0
## A script error inside a check ends that coroutine without reaching quit(),
## and a headless SceneTree then idles for ever. The watchdog makes that loud.
const WATCHDOG_S := 300

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_fails += 1


func _initialize() -> void:
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("FAIL  watchdog: the suite did not finish within %d s — a check probably crashed (see SCRIPT ERROR above)" % WATCHDOG_S)
		quit(2))
	await process_frame
	await _causeway()
	await _ramp_mount()
	await _keep()
	await _tower()
	print("")
	print("ALL CAUSEWAY CHECKS PASS" if _fails == 0 else "%d CAUSEWAY CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


## A region with the levels' agent, ready to have pieces put in it.
func _stage() -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.6
	nm.agent_height = 1.5
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	nm.region_min_size = 8.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	region.navigation_mesh = nm
	root.add_child(region)
	return region


func _place(region: NavigationRegion3D, path: String, pos: Vector3, yaw: float = 0.0) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		_check("%s loads" % path.get_file(), false, "load() returned null")
		return null
	var node := packed.instantiate() as Node3D
	region.add_child(node)
	node.position = pos
	node.rotation.y = deg_to_rad(yaw)
	return node


## Flat ground to stand on, `top` high, so a ramp has something to meet.
func _ground(region: NavigationRegion3D, centre: Vector3, size: Vector2, top: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 4.0, size.y)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(centre.x, top - 2.0, centre.z)
	region.add_child(body)


## The pieces run along their own Z, so a causeway is laid out along Z.
func _causeway() -> void:
	var region := _stage()
	# Land at each end, and the two ramps up onto the deck.
	_ground(region, Vector3(0.0, 0.0, -44.0), Vector2(90.0, 40.0), 0.0)
	_ground(region, Vector3(0.0, 0.0, 188.0), Vector2(90.0, 40.0), 0.0)
	_place(region, CAUSEWAY_DIR.path_join("causeway_ramp.tscn"), Vector3.ZERO)
	_place(region, CAUSEWAY_DIR.path_join("causeway_ramp.tscn"), Vector3(0.0, 0.0, 144.0), 180.0)
	# Three sections between them: sound, cracked, shelled.
	var kinds := ["causeway_span", "causeway_span_cracked", "causeway_span_broken"]
	for i in kinds.size():
		_place(region, CAUSEWAY_DIR.path_join(kinds[i] + ".tscn"), Vector3(0.0, 0.0, SECTION * (i + 0.5)))
	region.bake_navigation_mesh(false)
	for _i in 3:
		await physics_frame
	var map := region.get_navigation_map()
	var start := NavigationServer3D.map_get_closest_point(map, Vector3(0.0, 0.0, -40.0))
	var finish := NavigationServer3D.map_get_closest_point(map, Vector3(0.0, 0.0, 184.0))
	var route := NavigationServer3D.map_get_path(map, start, finish, true)
	var miss: float = (route[route.size() - 1] as Vector3).distance_to(finish) if route.size() > 0 else 999.0
	var walked := 0.0
	var high := -100.0
	for i in route.size() - 1:
		walked += route[i].distance_to(route[i + 1])
		high = maxf(high, route[i].y)
	_check("the squad walks the whole causeway, bank to bank", miss < 2.0,
			"stops %.0f m short after %.0f m" % [miss, walked])
	_check("...and over it rather than round it", high > 3.0,
			"the way found never rose above %.1f m, so it is not using the deck" % high)
	# Every section's middle has to carry it, including the shelled one, and
	# the way across has to be wide enough for the rover.
	for i in 3:
		var z: float = SECTION * (i + 0.5)
		var on := NavigationServer3D.map_get_closest_point(map, Vector3(0.0, 4.4, z))
		var flat := Vector2(on.x, on.z - z).length()
		_check("%s carries the squad over its middle" % kinds[i], flat < 5.0 and on.y > 3.0,
				"nearest navmesh %.1f m away at y %.2f" % [flat, on.y])
		var widest := 0.0
		for y in range(-16, 17):
			var q := Vector3(y * 0.5, 4.4, z)
			var near := NavigationServer3D.map_get_closest_point(map, q)
			widest += 0.5 if Vector2(near.x - q.x, near.z - q.z).length() < 0.5 else 0.0
		_check("%s is wide enough for the rover" % kinds[i], widest >= ROVER_W,
				"only %.1f m of walkable deck across it" % widest)
	root.remove_child(region)
	region.free()


## GETTING ON TO THE RAMP, which is a different question from walking the deck
## and nothing above asks it. The report was "the squad can't get onto the
## first ramp": the approach was one 16 m strip with a wall down each side, so
## a body coming at it from off to the side met the flank — a 1.6 m step up —
## and had to walk back out and funnel in at the end. The mouth flares to fix
## that, and the human asked for the flare specifically.
##
## Nothing guarded it, so a fix for something else nearly took it out: the
## flare's own parapet ended a metre short of the span's, and that wall end
## put two navmesh boundary vertices 0.19 m apart in the deck's contour. The
## navigation map keys points into 0.25 m cells, so it read them as one point,
## refused to merge the edge a third time and dropped the deck into a single
## degenerate polygon. The walk above failed 109 m away, which pointed at
## everything except the ramp.
##
## So: measure the approach, not just the crossing. Measured on the bake, the
## pre-flare piece gives 15.0 m walkable at the mouth, 17.0 m at mid-climb and
## a worst detour of x1.18; flared it gives 29.3 m, 21.8 m and x1.10. The
## thresholds below sit between the two pairs, so losing the flare fails here
## and breaking it fails above. If one of them starts flickering, read it as
## the bake having moved and measure again before moving the number.
func _ramp_mount() -> void:
	var region := _stage()
	# A bank wide enough to come at the ramp from well off to one side.
	_ground(region, Vector3(0.0, 0.0, -54.0), Vector2(160.0, 60.0), 0.0)
	_place(region, CAUSEWAY_DIR.path_join("causeway_ramp.tscn"), Vector3.ZERO)
	_place(region, CAUSEWAY_DIR.path_join("causeway_span.tscn"), Vector3(0.0, 0.0, 24.0))
	region.bake_navigation_mesh(false)
	for _i in 3:
		await physics_frame
	var map := region.get_navigation_map()
	# One unbroken surface, not two with a ridge between them, so the width
	# that counts is the longest run without a gap rather than the total.
	for pair: Array in [["the mouth", -23.0, 24.0], ["mid-climb", -12.0, 19.0]]:
		var z: float = pair[1]
		# The ramp's own surface at z, since a query from far above it can
		# answer with the ground beside the ramp instead.
		var y: float = 4.0 * (z + 24.0) / 24.0 + 0.1
		var run := 0.0
		var best := 0.0
		for i in range(-72, 73):
			var x: float = i * 0.25
			var near := NavigationServer3D.map_get_closest_point(map, Vector3(x, y, z))
			if Vector2(near.x - x, near.z - z).length() < 0.25:
				run += 0.25
				best = maxf(best, run)
			else:
				run = 0.0
		_check("the ramp is continuously walkable across %s" % pair[0], best >= float(pair[2]),
				"the widest unbroken stretch is %.1f m, under the %.0f m the flare gives" % [best, pair[2]])
	# And a body off to the side walks on where it stands, instead of walking
	# back out to the centre line first.
	var deck := NavigationServer3D.map_get_closest_point(map, Vector3(0.0, 4.5, 20.0))
	var worst := 0.0
	var worst_at := 0.0
	var stranded := 0
	for dx: float in [-40.0, -24.0, -16.0, -8.0, 0.0, 8.0, 16.0, 24.0, 40.0]:
		var from := NavigationServer3D.map_get_closest_point(map, Vector3(dx, 0.5, -34.0))
		var route := NavigationServer3D.map_get_path(map, from, deck, true)
		var walked := 0.0
		for i in route.size() - 1:
			walked += route[i].distance_to(route[i + 1])
		if route.size() == 0 or (route[route.size() - 1] as Vector3).distance_to(deck) > 2.0:
			stranded += 1
			continue
		var direct := from.distance_to(deck)
		if direct > 0.0 and walked / direct > worst:
			worst = walked / direct
			worst_at = dx
	_check("the squad gets onto the ramp from off to the side", stranded == 0 and worst < 1.15,
			"%d of 9 approaches never arrive, and the worst walks x%.2f the direct distance (from x %+.0f)"
			% [stranded, worst, worst_at])
	root.remove_child(region)
	region.free()


## The tower: in at the foot and all the way up the inside. A hundred metres
## of ramp is worth nothing if one flight in twenty is too steep or too narrow,
## and nothing outside the tower would ever show it.
func _tower() -> void:
	var region := _stage()
	_ground(region, Vector3.ZERO, Vector2(600.0, 600.0), 0.0)
	if _place(region, "res://maps/blocks/fortress/fort_tower.tscn", Vector3.ZERO) == null:
		root.remove_child(region)
		region.free()
		return
	region.bake_navigation_mesh(false)
	for _i in 3:
		await physics_frame
	var map := region.get_navigation_map()
	# The fort's gate faces the prefab's -Z, with 60 m of ramp outside it.
	var outside := NavigationServer3D.map_get_closest_point(map, Vector3(0.0, 0.0, -175.0))
	_check("the squad reaches the foot of the fort's ramp", outside.z < -150.0 and outside.y < 2.0,
			"the nearest navmesh outside is at %v" % outside)
	# The way in and down, before the way up.
	for stop: Array in [["through the gate onto the yard", Vector3(0.0, 10.0, -95.0), 10.0],
			["down the pit to the tower's door", Vector3(0.0, 0.0, 30.0), 0.0],
			["onto the wall walk", Vector3(95.0, 14.0, 0.0), 14.0],
			["onto a corner bastion", Vector3(89.0, 18.0, 89.0), 18.0]]:
		var at := NavigationServer3D.map_get_closest_point(map, stop[1])
		_check("there is navmesh %s" % stop[0], absf(at.y - float(stop[2])) < 2.5,
				"the nearest navmesh is at %v" % at)
	# Existing is not the same as reachable. The wall and the bastions were
	# scenery before: navmesh on them the whole time, and no way up from the
	# yard to any of it.
	for target: Array in [["the wall walk", Vector3(95.0, 14.0, 0.0)],
			["the north-east bastion", Vector3(89.0, 18.0, 89.0)],
			["the south-west bastion", Vector3(-89.0, 18.0, -89.0)],
			["the north-west bastion", Vector3(-89.0, 18.0, 89.0)],
			["the south-east bastion", Vector3(89.0, 18.0, -89.0)],
			["the foot of the pit", Vector3(0.0, 0.0, 30.0)]]:
		var goal := NavigationServer3D.map_get_closest_point(map, target[1])
		var route := NavigationServer3D.map_get_path(map, outside, goal, true)
		var miss: float = (route[route.size() - 1] as Vector3).distance_to(goal) if route.size() > 0 else 999.0
		_check("the squad can walk to %s" % target[0], miss < 4.0,
				"it stops %.0f m short of it" % miss)
	# Every ramp onto the walk has to have its FOOT on the yard. A ramp given
	# its ends the wrong way round climbs from the wall down to the yard: from
	# above it looks identical, and both of its ends are a 4 m step. Half of
	# them were built that way.
	var upside_down := 0
	for s: float in [-1.0, 1.0]:
		for o: float in [-40.0, 40.0]:
			for foot: Vector3 in [Vector3(s * 68.0, 10.0, o), Vector3(o, 10.0, s * 68.0)]:
				var at := NavigationServer3D.map_get_closest_point(map, foot)
				if absf(at.y - 10.0) > 1.5:
					upside_down += 1
	_check("all eight ramps onto the walk start on the yard", upside_down == 0,
			"%d of 8 have their foot in the air" % upside_down)
	# The top data hall, twenty-three floors up at 6 m a floor.
	var want := Vector3(0.0, 138.0, 0.0)
	var goal := NavigationServer3D.map_get_closest_point(map, want)
	_check("there is navmesh on the command floor at the top", absf(goal.y - want.y) < 3.0,
			"the nearest navmesh to the top is at %v" % goal)
	var route := NavigationServer3D.map_get_path(map, outside, goal, true)
	var miss: float = (route[route.size() - 1] as Vector3).distance_to(goal) if route.size() > 0 else 999.0
	var walked := 0.0
	var climbed := -100.0
	for i in route.size() - 1:
		walked += route[i].distance_to(route[i + 1])
		climbed = maxf(climbed, route[i].y)
	_check("the squad climbs the inside of the tower to the top", miss < 4.0,
			"it gets %.0f m up after walking %.0f m, and stops %.0f m short" % [climbed, walked, miss])
	# Every landing on the way up has to exist, or the climb stops halfway.
	# Every floor has to be a floor: navmesh somewhere on the lane round the
	# outside of it, clear of the racks down the middle and of the well.
	var missing: Array = []
	for level in 24:
		var z: float = 6.0 * level
		var found := false
		for probe: Vector3 in [Vector3(0.0, 0.0, 17.0), Vector3(17.0, 0.0, 0.0),
				Vector3(0.0, 0.0, -17.0), Vector3(-17.0, 0.0, 0.0)]:
			var at := NavigationServer3D.map_get_closest_point(map, Vector3(probe.x, z, probe.z))
			if absf(at.y - z) < 2.0 and Vector2(at.x - probe.x, at.z - probe.z).length() < 4.0:
				found = true
				break
		if not found:
			missing.append(level)
	_check("all twenty-four floors have navmesh on them", missing.is_empty(),
			"no navmesh found on floor(s) %s" % str(missing))
	# And the squad has to be able to work round the racks on a floor, not
	# just stand at the top of the ramp.
	var lane := 0.0
	for i in range(-15, 16):
		var q := Vector3(float(i), 30.0, 17.0)
		var near := NavigationServer3D.map_get_closest_point(map, q)
		lane += 1.0 if Vector2(near.x - q.x, near.z - q.z).length() < 0.6 else 0.0
	_check("there is a lane round the racks on a floor", lane >= 20.0,
			"only %.0f m of the fifth floor's north lane is walkable" % lane)
	root.remove_child(region)
	region.free()


## The keep: in through the gate, across the yard and down to the portal.
func _keep() -> void:
	var region := _stage()
	_ground(region, Vector3(0.0, 0.0, 0.0), Vector2(300.0, 300.0), 0.0)
	if _place(region, FORT, Vector3.ZERO) == null:
		root.remove_child(region)
		region.free()
		return
	region.bake_navigation_mesh(false)
	for _i in 3:
		await physics_frame
	var map := region.get_navigation_map()
	# The fort's gate faces -X in the map, which is the prefab's -Z.
	var outside := NavigationServer3D.map_get_closest_point(map, Vector3(0.0, 0.0, -90.0))
	for target: Array in [["the yard", Vector3(-10.0, 4.0, 0.0)], ["the portal at the foot of the pit", Vector3(0.0, 0.0, 38.0)]]:
		var want: Vector3 = target[1]
		var goal := NavigationServer3D.map_get_closest_point(map, want)
		var route := NavigationServer3D.map_get_path(map, outside, goal, true)
		var miss: float = (route[route.size() - 1] as Vector3).distance_to(goal) if route.size() > 0 else 999.0
		var snapped_to: float = Vector2(goal.x - want.x, goal.z - want.z).length()
		_check("the squad gets from the causeway to %s" % target[0], miss < 3.0 and snapped_to < 6.0,
				"stops %.0f m short, and the nearest navmesh to it is %.0f m away" % [miss, snapped_to])
	# The pit has to stay wide: this is how anything big gets underground.
	var widest := 0.0
	for x in range(-24, 25):
		var q := Vector3(x * 0.5, 0.0, 30.0)
		var near := NavigationServer3D.map_get_closest_point(map, q)
		widest += 0.5 if Vector2(near.x - q.x, near.z - q.z).length() < 0.5 else 0.0
	_check("the ramp down to the data halls is wide", widest >= 12.0,
			"only %.1f m of it is walkable" % widest)
	root.remove_child(region)
	region.free()
