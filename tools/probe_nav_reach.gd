extends SceneTree

# ─────────────────────────────────────────────
# CAN THE SQUAD ACTUALLY GET THERE?
#
#   LEVEL=res://maps/georgetown_level.tscn godot --path . \
#       --script res://tools/probe_nav_reach.gd
#
# NOT headless: a level with no renderer has no navmesh worth asking about,
# and this reads the one baked into the scene.
#
# WHY THIS EXISTS. move_and_slide has no step-up of its own, so a robot walks
# up anything under enemy.gd's step_height of 0.45 m and ANY vertical face
# above that is a wall wanting a ramp. A map built in terraces lives or dies
# on whether the stairs and ramps between them actually connect — and the way
# that fails is silent. The navmesh bakes, the level loads, every bench has
# navmesh on it, and the squad simply never goes anywhere because the bench it
# is standing on is an island.
#
# So this asks three things, in order of how badly each one hurts:
#
#   1. HOW MUCH OF THE MAP IS ONE PIECE. Sample a grid over the site, snap
#      each point to the navmesh, and path to it from the spawn. The number
#      that matters is the share that comes back reachable; islands are the
#      defect and they do not announce themselves.
#   2. IS EVERY OBJECTIVE REACHABLE. An objective on an island is a mission
#      that cannot be completed and nothing says so until someone plays it.
#   3. WHAT DID IT COST. Path length against straight-line distance. A ratio
#      near 1 on a terraced map means the squad is walking THROUGH the
#      terraces rather than round to a stair, which means a wall somewhere is
#      climbable and was not meant to be.
#
# It changes nothing on disk. Bake first with:
#   BAKE_ONLY=1 LEVEL=... godot --path . --script res://tools/probe_nav_hillfort.gd
#
# ── WHO IS IT ASKING ABOUT ───────────────────────────────────────────────────
#
# IT USED TO ASK ABOUT NOBODY, and that is the hole this closes. It read
# whatever mesh was baked into the scene, and a mesh baked at Godot's default
# agent_radius of 0.5 describes a cylinder 1.0 m across and 1.8 m tall. Nothing
# in the squad is that size: the Walker is 3.00 m tall, the Bulwark 2.26 m wide
# across its shield, the Rover 3.40 m long. So the probe reported Salient PASS
# at 75.2% coverage for a body half the width of everything that would walk it.
#
# A PATH QUERY TAKES NO RADIUS. Godot has no per-agent clearance — map_get_path
# routes a 2.26 m Bulwark through a gap sized for 0.5 m and never complains. The
# radius is decided once, at BAKE time, and is the only clearance the engine
# will ever enforce. Which means a reach probe that cannot be told a radius
# cannot answer the only question worth asking.
#
# So: name a chassis and it re-bakes the region in memory at that frame's real
# numbers before it sweeps. Nothing is written back; the scene on disk is
# untouched.
#
#   CHASSIS=walker   LEVEL=... godot --path . --script res://tools/probe_nav_reach.gd
#   CHASSIS=bulwark  ...
#   RADIUS=0.85 HEIGHT=3.0 CLIMB=0.45 ...      # or set them by hand
#   CHASSIS=walker COVERAGE=0 ...              # objectives only, and quick
#
# The frames come from tools/probe_chassis_size.gd, which measures them off the
# collision shapes. Do not type them in from memory — they have been wrong in
# the brief twice (the Bulwark's shield and the Rover's height).
#
# COVERAGE=0 SKIPS THE GRID SWEEP. map_get_closest_point walks every polygon in
# the map, and Salient has 59,000 of them, so a full sweep is minutes. The
# objective walk is eleven queries. When the question is "can this chassis reach
# the mission", that is the whole question, and it runs in seconds.
# ─────────────────────────────────────────────

## How far a path end may be from the point asked for and still count as
## arrived. Godot returns the closest reachable point rather than failing, so
## this threshold IS the reachability test.
const ARRIVED := 6.0
## Grid pitch for the coverage sweep.
const STEP := 16.0
## A sample further than this from any navmesh is not a hole in the map, it is
## off the edge of it, and is not counted either way.
const ON_MESH := 3.0

## Measured off the collision shapes by tools/probe_chassis_size.gd:
## radius, height, climb. The radius is HALF THE NARROW AXIS of the body's own
## collision — for the Bulwark that includes the shield, which is the half of
## it that actually jams in a trench.
##
## "squad" is the envelope: the widest, tallest and least-climbing of everything
## that walks, which is the one honest setting for a map with a single navmesh.
const FRAMES := {
	"squad": [1.13, 3.00, 0.45],
	"walker": [0.85, 3.00, 0.45],
	"bulwark": [1.13, 2.82, 0.45],
	"rover": [0.85, 1.70, 0.75],
	"reclaimer": [0.75, 0.80, 0.45],
	"soldier": [0.50, 2.00, 0.45],
	"drone": [0.25, 1.70, 0.45],
}

## Where a level keeps its objective anchors. THERE IS NO ONE PLACE, which is
## why this is a list and not a path: the hillfort and Mutaha put them under the
## navigation region, Salient puts them in EnemySquadObjs beside it. Salient's
## baseline run printed "(no Objectives group — skipping)" and so never asked
## the question the whole probe is for — eleven objectives, none of them tested.
const OBJ_HOLDERS := [
	"NavigationRegion3D/Objectives", "Objectives", "EnemySquadObjs",
	"NavigationRegion3D/EnemySquadObjs", "SquadObjectives",
]

var map: RID
var _who := ""


func _initialize() -> void:
	await process_frame
	var level_path := OS.get_environment("LEVEL")
	if level_path == "":
		print("usage: LEVEL=res://maps/<name>_level.tscn godot --path . --script res://tools/probe_nav_reach.gd")
		quit(2)
		return
	var packed := ResourceLoader.load(level_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed == null:
		print("FAIL  could not load %s" % level_path)
		quit(1)
		return
	var level: Node3D = packed.instantiate()
	root.add_child(level)
	for _i in 40:
		await physics_frame
	var region: NavigationRegion3D = level.get_node_or_null("NavigationRegion3D")
	if region == null:
		print("FAIL  %s has no NavigationRegion3D" % level_path.get_file())
		quit(1)
		return
	var nav := region.navigation_mesh
	print("   %s — %d vertices, %d polygons" % [level_path.get_file(),
			nav.get_vertices().size(), nav.get_polygon_count()])
	nav = await _refit(region, nav)
	if nav == null:
		quit(1)
		return
	if nav.get_polygon_count() == 0:
		print("FAIL  the navmesh in the scene is empty — bake it first")
		quit(1)
		return
	map = region.get_navigation_map()
	var spawn: Node3D = level.get_node_or_null("SpawnPoint")
	if spawn == null:
		print("FAIL  %s has no SpawnPoint" % level_path.get_file())
		quit(1)
		return
	var from := _snap(spawn.global_position)
	print("   spawn at %s" % _s(from))

	var fails := 0
	if OS.get_environment("COVERAGE") == "0":
		print("   (COVERAGE=0 — grid sweep skipped, objectives only)")
	else:
		fails += _coverage(nav, from)
	fails += _objectives(level, from)
	fails += _routes(level)
	print("REACH %s%s" % ["PASS" if fails == 0 else "FAIL — %d problem(s)" % fails,
			"  [%s]" % _who if _who != "" else ""])
	quit(1 if fails > 0 else 0)


## RE-BAKE IN MEMORY AT A REAL BODY'S NUMBERS, if asked. Returns the mesh the
## sweep should use, or null if the bake collapsed.
##
## Nothing is saved. The region's own NavigationMesh is swapped for a duplicate
## so the PackedScene's sub-resource is never touched — this probe has to be
## safe to run against a level another lane is editing.
func _refit(region: NavigationRegion3D, nav: NavigationMesh) -> NavigationMesh:
	var frame := OS.get_environment("CHASSIS").to_lower()
	var want := [-1.0, -1.0, -1.0]
	if frame != "":
		if not FRAMES.has(frame):
			print("FAIL  no chassis called %s — try one of %s" % [frame, ", ".join(FRAMES.keys())])
			return null
		want = (FRAMES[frame] as Array).duplicate()
		_who = frame
	for i in 3:
		var e := OS.get_environment(["RADIUS", "HEIGHT", "CLIMB"][i])
		if e != "":
			want[i] = float(e)
			_who = "custom" if _who == "" else _who + "+custom"
	var cell_e := OS.get_environment("CELL")
	var cellh_e := OS.get_environment("CELL_H")
	if want[0] < 0.0 and want[1] < 0.0 and want[2] < 0.0 and cell_e == "" and cellh_e == "":
		# NOT AN ERROR, but it must say so. The mesh on disk was baked for
		# whatever its author put in it, and on most maps that is Godot's 0.5 m
		# default — which is the trap this option exists to make visible.
		print("   asking about the mesh AS BAKED: radius %.2f, height %.2f, climb %.2f" % [
				nav.agent_radius, nav.agent_height, nav.agent_max_climb])
		print("   (no CHASSIS= given, so this is a claim about a %.2f m wide body)" % (nav.agent_radius * 2.0))
		return nav
	var baked: NavigationMesh = nav.duplicate(true)
	if cell_e != "":
		baked.cell_size = float(cell_e)
	if cellh_e != "":
		baked.cell_height = float(cellh_e)
	# THE VERTICAL NUMBERS ARE QUANTISED AND THE BAKER SAYS SO IN A WARNING
	# NOBODY READS. agent_height is CEILED to whole cell_height voxels and
	# agent_max_climb is FLOORED to them. At the default cell_height of 0.25 a
	# climb of 0.45 floors to 0.25 — it does not get 0.45, it gets the bottom of
	# the band the squad walks over, and the mesh comes apart at every 0.3 m lip
	# for no reason anyone can see. Say so rather than let it happen quietly.
	if want[2] >= 0.0:
		var eff_climb: float = floorf(want[2] / baked.cell_height) * baked.cell_height
		if absf(eff_climb - want[2]) > 0.001:
			print("   NOTE  climb %.2f floors to %.2f at cell_height %.2f." % [
					want[2], eff_climb, baked.cell_height])
			print("         Set CELL_H to a divisor of the climb to get the climb asked for.")
	if want[0] >= 0.0:
		# agent_radius finer than the grid the mesh is rasterised on cannot be
		# represented, and asking for it erodes the surface away instead.
		baked.agent_radius = maxf(want[0], baked.cell_size)
	if want[1] >= 0.0:
		baked.agent_height = want[1]
	if want[2] >= 0.0:
		baked.agent_max_climb = want[2]
	print("   re-baking for %s: radius %.2f, height %.2f, climb %.2f, cell %.2f x %.2f" % [
			_who, baked.agent_radius, baked.agent_height, baked.agent_max_climb,
			baked.cell_size, baked.cell_height])
	region.navigation_mesh = baked
	# The navigation MAP has a cell_size of its own and the two must agree, or
	# the server refuses to merge the edges that meet across a cell boundary and
	# every seam becomes something agents catch on. trench_broom_level.gd does
	# this in _enter_tree off the mesh as shipped; changing the mesh after that
	# means doing it again.
	#
	# AND cell_height, which is the one that caught this out. The server checks
	# BOTH against the map and trench_broom_level.gd only syncs cell_size, so a
	# mesh shipped with a non-default cell_height errors on every load with
	# "Attempted to update a navigation region with a navigation mesh that uses
	# a cell_height of X while assigned to a navigation map set to 0.25".
	var m := region.get_navigation_map()
	if m.is_valid():
		NavigationServer3D.map_set_cell_size(m, baked.cell_size)
		NavigationServer3D.map_set_cell_height(m, baked.cell_height)
	region.bake_navigation_mesh(false)
	for _i in 120:
		await physics_frame
	print("   re-baked: %d vertices, %d polygons" % [
			baked.get_vertices().size(), baked.get_polygon_count()])
	if baked.get_polygon_count() == 0:
		print("FAIL  the bake came back EMPTY at radius %.2f / height %.2f." % [
				baked.agent_radius, baked.agent_height])
		print("      That is the honest answer for this body: there is nowhere on")
		print("      this map it fits. It is not a probe failure.")
		return null
	return baked


func _snap(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(map, p)


func _s(p: Vector3) -> String:
	return "(%.0f, %.0f, %.0f)" % [p.x, p.y, p.z]


## Path from `from` to `to`, and where it actually ended up.
func _walk(from: Vector3, to: Vector3) -> Dictionary:
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.size() < 2:
		return {"ok": false, "end": from, "len": 0.0}
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	var end: Vector3 = path[path.size() - 1]
	return {"ok": end.distance_to(to) <= ARRIVED, "end": end, "len": total}


## THE ONE THAT MATTERS. Sweep a grid over the navmesh's own bounds, keep the
## samples that are actually on it, and path to each from the spawn. Anything
## that will not path is on an island.
func _coverage(nav: NavigationMesh, from: Vector3) -> int:
	var verts := nav.get_vertices()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v: Vector3 in verts:
		lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
		hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))
	var on := 0
	var reached := 0
	var stranded: Array = []
	# Keep off the outer edge. The last row of samples sits exactly on the rim
	# of the ground slabs, where the baker has already eroded the walkable
	# area away by the agent radius — they come back unreachable on every map
	# and they are the edge of the world, not an island in it.
	lo += Vector3(STEP, 0.0, STEP)
	hi -= Vector3(STEP, 0.0, STEP)
	var x := lo.x
	while x <= hi.x:
		var z := lo.z
		while z <= hi.z:
			# ASK AT THREE HEIGHTS AND KEEP THE ONE THAT LANDS NEAREST IN PLAN.
			#
			# map_get_closest_point is a 3D query and this sweep is a 2D
			# question — "is (x, z) a place on the walkable map?" — so one
			# query height silently decides the answer with geometry that has
			# nothing to do with the ground under the sample.
			#
			# It was asking at the MIDDLE of the navmesh's own bounding box,
			# and on Salient the valley walls put that box's top at 148 m, so
			# the question was being put from 70 m in the air. From up there
			# the nearest navmesh to a point over the valley floor is whatever
			# ELEVATED surface is closest in 3D — a valley wall, a roof —
			# rather than the floor directly below, and a sample whose snap
			# lands 40 m sideways is then thrown out as "off the mesh". The
			# sweep was counting 284 of 2112 grid points on a map that is
			# walkable nearly everywhere, and the share it reported was a share
			# of that 13%.
			#
			# What made it visible: putting fourteen tall buildings on Salient
			# baked fourteen roofs at y 27-46, each one close enough to the
			# 70 m query plane to steal the snap from a 60 m circle of ground
			# around it. Coverage "fell" 74.8% -> 68.7% and tripped the FAIL,
			# while the ground itself had not changed at all — measured with
			# this fix, 89.8% -> 89.6%. A probe that reports a map coming apart
			# because someone put a building on it is worse than no probe.
			#
			# Bottom, middle and top covers it: the bottom finds the floor
			# under a roof, the top finds a summit, the middle is what it
			# always did. Three closest-point queries per sample is nothing
			# next to the path walk each one then costs.
			var p := _snap(Vector3(x, (lo.y + hi.y) * 0.5, z))
			for y: float in [lo.y, hi.y]:
				var q := _snap(Vector3(x, y, z))
				if Vector2(q.x - x, q.z - z).length() < Vector2(p.x - x, p.z - z).length():
					p = q
			# Only count a sample that is really standing on the mesh: the
			# closest point to somewhere off the edge is the edge itself, and
			# counting those would call the map 100% reachable every time.
			if Vector2(p.x - x, p.z - z).length() <= ON_MESH:
				on += 1
				if _walk(from, p).ok:
					reached += 1
				elif stranded.size() < 8:
					stranded.append(p)
			z += STEP
		x += STEP
	if on == 0:
		print("   FAIL  no sample landed on the navmesh at all")
		return 1
	var share := 100.0 * reached / float(on)
	print("   coverage: %d of %d samples reachable from the spawn — %.1f%%" % [reached, on, share])
	for p: Vector3 in stranded:
		print("      stranded near %s" % _s(p))
	# WHAT COUNTS AS A FAILURE HERE. Flat roofs bake as walkable and most have
	# no way up, so a map with buildings on it never reads 100% — and chasing
	# that number means either giving every roof a stair or stopping roofs
	# baking at all, and neither is worth it. An unreachable ROOF is not a
	# broken map; an unreachable OBJECTIVE is, and that is what fails below.
	# This only fires when the ground itself has come apart.
	if share < 70.0:
		print("   FAIL  only %.1f%% of the walkable map is reachable — the ground is in pieces" % share)
		return 1
	if share < 95.0:
		print("   note: the rest should be roofs — check the stranded list for any at ground height")
	return 0


## DOES THE ROUTE MEAN ANYTHING. For every pair of anchors named X_entry and
## X_exit, walk one to the other and compare it with the straight line.
##
## WHY THIS AND NOT REACHABILITY. Both ends of a route are reachable whether the
## route works or not — there is open ground round everything on this map — so
## "can it get there" cannot tell a working trench from a blocked one. Only the
## COST can. A route that carries the walk comes back near x1.0; a route that is
## severed, or eroded to nothing at this radius, sends the walk out round the
## end of it and the ratio jumps.
##
## That is the same shape of test as the dropped bridge on the Mutaha copy and
## the switchbacks on the hillfort, and it is the one that found both.
func _routes(level: Node3D) -> int:
	var holder := level.get_node_or_null("NavigationRegion3D/SalientArt/Trenchworks/Anchors")
	if holder == null:
		for n: Node in level.find_children("Anchors", "Node3D", true, false):
			holder = n
			break
	if holder == null:
		return 0                       # not every level lays routes; not a fault
	var ends := {}
	for a in holder.get_children():
		var nm := str(a.name)
		for suffix: String in ["_entry", "_exit"]:
			if nm.ends_with(suffix):
				var key := nm.substr(0, nm.length() - suffix.length())
				if not ends.has(key):
					ends[key] = {}
				ends[key][suffix] = (a as Node3D).global_position
	var keys: Array = ends.keys()
	keys.sort()
	var bad := 0
	for k: String in keys:
		var pair: Dictionary = ends[k]
		if not (pair.has("_entry") and pair.has("_exit")):
			continue
		var from := _snap(pair["_entry"])
		var to := _snap(pair["_exit"])
		var r := _walk(from, to)
		var direct := from.distance_to(to)
		var ratio: float = r.len / direct if direct > 0.5 else 1.0
		var note := ""
		if not r.ok:
			note = "  SEVERED — the walk never arrives"
			bad += 1
		elif ratio > 1.6:
			# 1.6 is generous for a route that is meant to BE the way through.
			# A trench traverses, so even a working one reads a little over 1.0.
			note = "  the walk goes ROUND, not along — too narrow at this radius?"
			bad += 1
		print("   route %-4s %6.0f m along / %5.0f m direct  x%.2f%s" % [
				k, r.len, direct, ratio, note])
	return bad


## Every objective anchor, and what the walk to it cost.
func _objectives(level: Node3D, from: Vector3) -> int:
	var holder: Node = null
	for p: String in OBJ_HOLDERS:
		holder = level.get_node_or_null(p)
		if holder != null:
			break
	if holder == null:
		print("   WARN  no objective group found under any of %s" % ", ".join(OBJ_HOLDERS))
		print("         Reachability to the things the squad is SENT to was not tested,")
		print("         which is the only part of this probe a mission depends on.")
		return 0
	print("   objectives under %s" % holder.name)
	var bad := 0
	for o in holder.get_children():
		if not (o is Node3D):
			continue
		var want: Vector3 = (o as Node3D).global_position
		var p := _snap(want)
		var off := want.distance_to(p)
		var r := _walk(from, p)
		var direct := from.distance_to(p)
		var ratio: float = r.len / direct if direct > 0.5 else 1.0
		var note := ""
		if not r.ok:
			note = "  UNREACHABLE, got to %s" % _s(r.end)
			bad += 1
		elif off > 4.0:
			# The anchor is in the air or inside something. Not fatal — the
			# squad walks to the nearest floor — but it is worth saying,
			# because an objective that snaps 10 m away is in a wall.
			note = "  (anchor is %.1f m off the mesh)" % off
		print("   %-16s %6.0f m walk / %5.0f m direct  x%.2f%s" % [o.name, r.len, direct, ratio, note])
	return bad
