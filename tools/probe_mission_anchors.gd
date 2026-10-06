extends SceneTree

# ─────────────────────────────────────────────
# CAN THE SQUAD REACH EVERY TAG A MISSION NAMES?
#
#   LEVEL=res://maps/causeway_level.tscn godot --headless --audio-driver Dummy \
#       --path . --script res://tools/probe_mission_anchors.gd
#
#   POINTS="420,10,0;530,0,0" LEVEL=... godot ... (same script)
#
# WHY THIS AND NOT probe_nav_reach.gd. That one sweeps the whole map and reads
# the TERRAIN-authored pins under NavigationRegion3D/Objectives, which is the
# right question while a map is being built. A MISSION asks a different one:
# every EnemySquadSpec resolves a post_tag, route_tag or spawn_tag through
# EnemyForceSpawner._find_point, which looks in the "squad_objective_points"
# group — and a garrison whose post is on an island stands there for the whole
# operation. So this reads the groups the SPAWNER reads, plus the mission
# objectives, plus whatever candidate coordinates you are thinking of using.
#
# POINTS is the scouting mode and the reason this exists as a separate tool:
# it answers "is this coordinate somewhere a robot can stand" BEFORE the number
# is written into a level, instead of after a playtest.
#
# It changes nothing and writes nothing. No save, no scene.
# ─────────────────────────────────────────────

## Same threshold probe_nav_reach uses: map_get_path returns the closest
## reachable point rather than failing, so the distance from what was asked for
## IS the reachability test.
const ARRIVED := 6.0
## Further than this from the mesh and the anchor is inside something, or in
## the air. Not fatal — a squad walks to the nearest floor — but a post that
## snaps this far is not where its author thinks it is.
const OFF_MESH_WARN := 4.0

var map: RID


func _initialize() -> void:
	await process_frame
	var level_path := OS.get_environment("LEVEL")
	if level_path == "":
		print("usage: LEVEL=res://maps/<name>_level.tscn [POINTS=x,y,z;x,y,z] godot --headless --path . --script res://tools/probe_mission_anchors.gd")
		quit(2)
		return
	var packed := ResourceLoader.load(level_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed == null:
		print("FAIL  could not load %s" % level_path)
		quit(1)
		return
	var level: Node3D = packed.instantiate()
	root.add_child(level)
	# The groups are joined in _ready, and the navigation map needs a few
	# physics frames to synchronise before map_get_path answers anything.
	for _i in 40:
		await physics_frame

	var region: NavigationRegion3D = _find_region(level)
	if region == null:
		print("FAIL  %s has no NavigationRegion3D" % level_path.get_file())
		quit(1)
		return
	var nav := region.navigation_mesh
	if nav == null or nav.get_polygon_count() == 0:
		print("FAIL  the navmesh in %s is empty — bake it first" % level_path.get_file())
		quit(1)
		return
	map = region.get_navigation_map()
	print("   %s — %d polygons" % [level_path.get_file(), nav.get_polygon_count()])

	var spawn := _spawn(level)
	if spawn == Vector3.INF:
		print("FAIL  no player spawn: the level root exports no spawn_point, and there is no SpawnPoint or PlayerSpawn node")
		quit(1)
		return
	var from := _snap(spawn)
	print("   spawn at %s (asked for %s)" % [_s(from), _s(spawn)])

	var bad := 0
	bad += _report("SQUAD POSTS (what post_tag / spawn_tag resolve to)",
			_tagged("squad_objective_points"), from)
	bad += _report("PATROL ROUTES (what route_tag resolves to)", _routes(), from)
	var objectives := _tagged_by_id("mission_objectives")
	bad += _report("MISSION OBJECTIVES", objectives, from)
	bad += _report("CANDIDATES (POINTS=)", _candidates(), from)
	_core_fit(objectives)
	_core_fit(_candidates())

	print("ANCHORS %s" % ("PASS" if bad == 0 else "FAIL — %d unreachable" % bad))
	quit(1 if bad > 0 else 0)


# ── WHAT SIZE OF CAPTURE CORE FITS HERE ──────────────────────────────────────
#
# compute_core_point comes in three sizes and every map in the project used the
# smallest for everything, including the objective the whole operation is about.
# Choosing a bigger one is not a taste question, because a core goes in AFTER
# the navmesh is baked: the baker knows nothing about it, so the squad paths
# straight at it and a core wider than the lane it stands in is a doorway full
# of robots. And a core taller than the room comes up through the ceiling.
#
# So this measures the two things that decide it, rather than leaving them to
# be guessed at from a screenshot:
#
#   CEILING   one ray straight up. Nothing overhead reads as open sky.
#   CLEARANCE eight rays out at chest height, and the SHORTEST one is the
#             answer — a core needs room on its narrow side, not its wide one.
#
# Measured collision footprints, which are not the heights docs/BLOCKS.md
# quotes (those include the lit crown, which has no collider):
#   small   1.88 square,  4.19 tall
#   medium  3.38 square,  6.97 tall
#   large   5.19 square, 12.38 tall
#
# A core also has to leave room to WALK PAST, so the bar is the footprint plus
# a body either side rather than the footprint alone.
const CORES := [
	["large", 5.19, 12.38],
	["medium", 3.38, 6.97],
	["small", 1.88, 4.19],
]
## Clear ground wanted either side of a core before it counts as fitting. A
## soldier is about 0.8 m across and needs somewhere to stand while it channels.
const PASS_BY := 2.5
## Ray length for the clearance sweep. Beyond this the answer is "plenty".
const CLEAR_REACH := 24.0
## How high to sweep. Chest height, where a body actually collides.
const CLEAR_HEIGHT := 1.2


func _core_fit(items: Array) -> void:
	if items.is_empty():
		return
	var space := root.world_3d.direct_space_state
	print("   ── CORE CLEARANCE (biggest capture core that fits) ──")
	for item: Array in items:
		var at: Vector3 = _snap(item[1])
		var skip := _bodies_under(item[2] if item.size() > 2 else null)
		var ceiling := _ceiling(space, at, skip)
		var clear := _clearance(space, at, skip)
		var fits := "none"
		for c: Array in CORES:
			if clear >= float(c[1]) * 0.5 + PASS_BY and ceiling >= float(c[2]) + 0.5:
				fits = String(c[0])
				break
		print("   %-28s ceiling %s  clearance %5.1f m   -> %s" % [
				item[0],
				"open " if ceiling > 900.0 else "%5.1f m" % ceiling,
				clear, fits])


## Every collision body belonging to this objective, as RIDs the ray queries
## can be told to ignore. Null (a POINTS candidate, which is a place nothing
## stands yet) excludes nothing, which is exactly right.
func _bodies_under(n) -> Array[RID]:
	var out: Array[RID] = []
	if n == null or not (n is Node):
		return out
	if n is CollisionObject3D:
		out.append((n as CollisionObject3D).get_rid())
	for c in (n as Node).find_children("*", "CollisionObject3D", true, false):
		out.append((c as CollisionObject3D).get_rid())
	return out


## Distance to whatever is overhead, from just above the floor. Large when
## there is nothing, which is what outdoors looks like.
func _ceiling(space: PhysicsDirectSpaceState3D, at: Vector3, skip: Array[RID]) -> float:
	var from := at + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 60.0)
	q.exclude = skip
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 9999.0
	return (hit["position"] as Vector3).distance_to(from) + 0.3


## The SHORTEST of eight rays out at chest height. The shortest and not the
## average: a core in a corridor has plenty of room along it and none across,
## and it is the across that decides.
func _clearance(space: PhysicsDirectSpaceState3D, at: Vector3, skip: Array[RID]) -> float:
	var from := at + Vector3.UP * CLEAR_HEIGHT
	var worst := CLEAR_REACH
	for i in 8:
		var a := TAU * i / 8.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * CLEAR_REACH)
		q.exclude = skip
		var hit := space.intersect_ray(q)
		var d := CLEAR_REACH if hit.is_empty() else (hit["position"] as Vector3).distance_to(from)
		worst = minf(worst, d)
	return worst


## The nav region wherever it sits. Hand-built levels put it under the root;
## nothing in the project nests it deeper, but finding it rather than assuming
## the path means a renamed root does not read as "no navmesh".
func _find_region(level: Node) -> NavigationRegion3D:
	if level is NavigationRegion3D:
		return level as NavigationRegion3D
	for c in level.find_children("*", "NavigationRegion3D", true, false):
		return c as NavigationRegion3D
	return null


## WHERE THE PLAYER COMES IN, in the three ways this project spells it: the
## level script's exported spawn_point (what World actually reads), a node
## called SpawnPoint (the generated levels, which have no script yet), and
## PlayerSpawn (causeway). Checked in that order so the authoritative one wins.
func _spawn(level: Node3D) -> Vector3:
	var sp: Variant = level.get("spawn_point")
	if sp is Node3D and (sp as Node3D).is_inside_tree():
		return (sp as Node3D).global_position
	for n_name: String in ["SpawnPoint", "PlayerSpawn"]:
		var n := level.get_node_or_null(n_name) as Node3D
		if n != null:
			return n.global_position
	return Vector3.INF


## [label, position] for everything in a group, labelled by its tag where it
## has one — the tag is what a mission writes, so the tag is what a failure
## here has to be reported against.
func _tagged(group: String) -> Array:
	var out: Array = []
	for n in get_nodes_in_group(group):
		if not (n is Node3D):
			continue
		var tag: Variant = n.get("tag")
		var label := String(tag) if tag != null and String(tag) != "" else String(n.name)
		out.append([label, (n as Node3D).global_position])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


## Objectives are named by id, not tag — that is the name a mission's
## active_objectives writes and so the name a failure has to carry.
## The NODE rides along as a third element. _core_fit() has to exclude an
## objective's own collider from its clearance sweep: a capture core is a solid
## 4-to-12 m post standing exactly on the point being measured, so without the
## exclusion every objective reports a ceiling of 0.3 m and no core fits
## anywhere, including the ones already standing there.
func _tagged_by_id(group: String) -> Array:
	var out: Array = []
	for n in get_nodes_in_group(group):
		if not (n is Node3D):
			continue
		var id: Variant = n.get("id")
		var label := String(id) if id != null and String(id) != "" else String(n.name)
		out.append([label, (n as Node3D).global_position, n])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


## Every point of every patrol route, because a route is only walkable if all
## of it is: one leg across a canal and the squad stops at the water.
func _routes() -> Array:
	var out: Array = []
	for n in get_nodes_in_group("patrol_paths"):
		var tag: Variant = n.get("tag")
		var label := String(tag) if tag != null and String(tag) != "" else String(n.name)
		var points: Variant = n.get("points")
		if points == null:
			continue
		var i := 0
		for p in points:
			if p is Node3D:
				out.append(["%s[%d]" % [label, i], (p as Node3D).global_position])
			i += 1
	return out


func _candidates() -> Array:
	var raw := OS.get_environment("POINTS")
	if raw == "":
		return []
	var out: Array = []
	var n := 0
	for chunk: String in raw.split(";", false):
		var bits := chunk.split(",", false)
		if bits.size() != 3:
			print("   (ignoring POINTS entry %s — wanted x,y,z)" % chunk)
			continue
		out.append(["#%d" % n, Vector3(float(bits[0]), float(bits[1]), float(bits[2]))])
		n += 1
	return out


func _report(heading: String, items: Array, from: Vector3) -> int:
	# A heading with nothing under it reads as a fault. An empty group is the
	# normal state for a level nobody has put gameplay nodes into yet, which is
	# exactly when this probe gets run, so say which one was empty.
	if items.is_empty():
		print("   ── %s ── none" % heading)
		return 0
	print("   ── %s ──" % heading)
	var bad := 0
	for item: Array in items:
		var want: Vector3 = item[1]
		var p := _snap(want)
		var off := want.distance_to(p)
		var r := _walk(from, p)
		var direct := from.distance_to(p)
		var note := ""
		if not r.ok:
			note = "  UNREACHABLE, got to %s" % _s(r.end)
			bad += 1
		elif off > OFF_MESH_WARN:
			note = "  (%.1f m off the mesh — snaps to %s)" % [off, _s(p)]
		print("   %-28s %6.0f m walk / %5.0f m direct  x%.2f%s" % [
				item[0], r.len, direct, (r.len / direct if direct > 0.5 else 1.0), note])
	return bad


func _snap(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(map, p)


func _s(p: Vector3) -> String:
	return "(%.0f, %.0f, %.0f)" % [p.x, p.y, p.z]


func _walk(from: Vector3, to: Vector3) -> Dictionary:
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.size() < 2:
		return {"ok": false, "end": from, "len": 0.0}
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i].distance_to(path[i - 1])
	var end: Vector3 = path[path.size() - 1]
	return {"ok": end.distance_to(to) <= ARRIVED, "end": end, "len": total}
