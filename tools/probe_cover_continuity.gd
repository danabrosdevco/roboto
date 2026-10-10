extends "res://tools/probe_nav_reach.gd"

# ─────────────────────────────────────────────
# COVER CONTINUITY — what share of the advance is EXPOSED?
#
#   LEVEL=res://maps/salient_level.tscn CHASSIS=drone,walker,bulwark \
#       godot --path . --script res://tools/probe_cover_continuity.gd
#
#   ROUTES=A,B,C   which routes to walk (default: every pair of anchors found)
#   STEP=2.0       sample pitch along the route, metres
#   EYE_Z=25.0     spacing of the sampled enemy front-line eyes, metres
#
# NOT headless. The path is walked on a navmesh re-baked for the chassis (that
# machinery is probe_nav_reach.gd's, which is why this inherits it) and every
# sample is a raycast against real collision.
#
# WHY IT EXISTS. "There is a trench" and "you are covered going up it" are
# different claims, and only the second one is the experience. A communication
# trench that leaves you visible for half its length is not a communication
# trench; a 2.0 m trench with a 3.0 m body in it is a man walking behind a wall
# holding his head over the top of it, continuously, for 200 m.
#
# So this does not measure depth — probe_trench_share.gd does that. It measures
# SIGHT: it walks each route at the chassis's own head height and asks every
# known enemy firing position whether it can see that head. The numbers are
#
#   exposed share   samples at least one enemy eye can see
#   worst stretch   the longest unbroken run of exposed samples, in metres.
#                   THE ONE THAT DECIDES WHETHER A ROUTE IS USABLE: 20% exposure
#                   spread as a metre every five is cover with gaps in it, and
#                   the same 20% in one 40 m stretch is a crossing under fire.
#   eyes            how many of them see you at the median exposed sample, which
#                   is the difference between a risk and a killing ground
#
# WHERE THE ENEMY EYES COME FROM. Derived, not typed: every pillbox, sangar, gun
# pit and mortar pit on the enemy side, plus the enemy front trench itself
# sampled along its frontage, because that trench is a terrain cut with no node
# of its own and would otherwise be left out of a sightline measurement of a map
# whose whole subject is that trench. See probe_trench_lib.gd.
# ─────────────────────────────────────────────

const LIB := preload("res://tools/probe_trench_lib.gd")

const ROSTER := ["drone", "walker", "bulwark", "soldier"]

## Route anchors are named <route>_entry / <route>_exit, and some routes do not
## have an _exit because they deliberately dead-end — the crater chain stops at
## an uncut wire belt. These are the ends to accept, in order of preference, so
## a dead-ending route is still measured as far as it goes instead of being
## silently dropped.
const END_NAMES := ["exit", "wire", "last_crater", "dugout", "blown"]


var _level: Node3D = null
var _space: PhysicsDirectSpaceState3D = null
var _eyes: Array = []


func _initialize() -> void:
	await process_frame
	var level_path := OS.get_environment("LEVEL")
	if level_path == "":
		print("usage: LEVEL=res://maps/salient_level.tscn godot --path . --script res://tools/probe_cover_continuity.gd")
		quit(2)
		return
	var packed := ResourceLoader.load(level_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed == null:
		print("FAIL  could not load %s" % level_path)
		quit(1)
		return
	_level = packed.instantiate()
	root.add_child(_level)
	for _i in 40:
		await physics_frame
	var region: NavigationRegion3D = _level.get_node_or_null("NavigationRegion3D")
	if region == null:
		print("FAIL  %s has no NavigationRegion3D" % level_path.get_file())
		quit(1)
		return
	_space = _level.get_world_3d().direct_space_state

	var front: Vector3 = LIB.objective(_level, "Salient_FrontLine")
	if is_nan(front.x):
		print("FAIL  no Salient_FrontLine anchor — without the enemy front line's x")
		print("      there is no way to tell their emplacements from ours, and an")
		print("      exposure number measured against our own pillboxes is a lie.")
		quit(1)
		return
	var eye_z := float(OS.get_environment("EYE_Z")) if OS.get_environment("EYE_Z") != "" else 25.0
	_eyes = LIB.firing_positions(_level, _space, front.x, -200.0, 200.0, eye_z)
	if _eyes.is_empty():
		print("FAIL  no enemy firing positions — nothing to be exposed to")
		quit(1)
		return

	var routes := _routes_to_walk()
	if routes.is_empty():
		print("FAIL  no route anchors under Trenchworks/Anchors — nothing to walk")
		quit(1)
		return
	var step := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 2.0
	var fails := 0
	for who: String in _roster():
		var f: Array = LIB.frame(who)
		if f.is_empty():
			print("   %s — NOT MEASURED, no such chassis in the frame table" % who)
			fails += 1
			continue
		OS.set_environment("CHASSIS", who)
		var nav := await _refit(region, region.navigation_mesh)
		if nav == null:
			print("   %s — the bake came back empty; no route to walk" % who)
			continue
		map = region.get_navigation_map()
		print("")
		print("── %s   head at %.2f m" % [who.to_upper(), LIB.head_of(who)])
		print("   %-6s %7s %9s %9s  %s" % ["route", "walk", "exposed", "worst", "eyes on you"])
		for r: Array in routes:
			var from := _snap(r[1] as Vector3)
			var to := _snap(r[2] as Vector3)
			var m := _walk_exposed(from, to, step, who)
			if float(m.len) <= 0.0:
				print("   %-6s  no path at this bake — this body cannot use this route" % r[0])
				continue
			var share := 100.0 * float(m.seen) / float(m.len)
			var note := ""
			# A route whose POINT is cover, exposing a third of itself, is not
			# doing the job it was built for. Said as a note and not a failure:
			# the crater chain is meant to be slow and shallow and the sunken
			# road is meant to have a blown span in the middle of it.
			if share > 33.0:
				note = "  <- more exposed than covered in thirds"
			print("   %-6s %6.0fm %8.1f%% %8.0fm  median %.1f, worst %d%s" % [
					r[0], float(m.len), share, float(m.worst),
					float(m.median_eyes), int(m.max_eyes), note])
	print("COVER CONTINUITY %s" % ["PASS" if fails == 0 else "FAIL — %d problem(s)" % fails])
	quit(1 if fails > 0 else 0)


## Walk one route and ask the enemy about every sample.
func _walk_exposed(from: Vector3, to: Vector3, step: float, who: String) -> Dictionary:
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.size() < 2:
		return {"len": 0.0, "seen": 0.0, "worst": 0.0, "median_eyes": 0.0, "max_eyes": 0}
	var samples: Array = LIB.densify(path, step)
	var head: float = LIB.head_of(who)
	var total := 0.0
	var seen := 0.0
	var run := 0.0
	var worst := 0.0
	var max_eyes := 0
	var counts: Array[int] = []
	for i in samples.size():
		var p: Vector3 = samples[i]
		var span := 0.0
		if i > 0:
			span += (samples[i] as Vector3).distance_to(samples[i - 1] as Vector3) * 0.5
		if i < samples.size() - 1:
			span += (samples[i] as Vector3).distance_to(samples[i + 1] as Vector3) * 0.5
		total += span
		# The head is measured off the collision under the sample, not off the
		# path's own y: a navmesh polygon floats agent_height/2 over its floor on
		# some bakes, and a head measured from there is a head in the air.
		var g: float = LIB.ground(_space, p.x, p.z)
		if is_nan(g):
			# EVERY SKIP SAYS WHY. No collision under a path sample means the
			# navmesh and the physics world disagree, which is worth knowing on
			# its own, and it is counted as neither exposed nor covered.
			push_warning("probe_cover_continuity: no collision under a path sample at (%.0f, %.0f) — not classified" % [p.x, p.z])
			continue
		var n: int = LIB.seen_by(_space, _eyes, Vector3(p.x, g + head, p.z))
		if n > 0:
			seen += span
			run += span
			worst = maxf(worst, run)
			counts.append(n)
			max_eyes = maxi(max_eyes, n)
		else:
			run = 0.0
	counts.sort()
	return {
		"len": total, "seen": seen, "worst": worst,
		"median_eyes": float(counts[counts.size() / 2]) if counts.size() > 0 else 0.0,
		"max_eyes": max_eyes,
	}


## Route name, start, end — from the Trenchworks anchors the builder wrote.
func _routes_to_walk() -> Array:
	var holder: Node = null
	for n in _level.find_children("Anchors", "Node3D", true, false):
		holder = n
		break
	if holder == null:
		return []
	var entry := {}
	var ends := {}
	for a in holder.get_children():
		var nm := str(a.name)
		var parts := nm.split("_", false, 1)
		if parts.size() < 2:
			continue
		var key: String = parts[0]
		var tail: String = parts[1]
		if tail == "entry":
			entry[key] = (a as Node3D).global_position
		elif END_NAMES.has(tail):
			if not ends.has(key):
				ends[key] = {}
			ends[key][tail] = (a as Node3D).global_position
	var want := OS.get_environment("ROUTES")
	var out: Array = []
	var keys: Array = entry.keys()
	keys.sort()
	for k: String in keys:
		if want != "" and not want.split(",").has(k):
			continue
		if not ends.has(k):
			print("   note: route %s has an entry anchor and no end anchor of any of %s — not walked" % [
					k, ", ".join(END_NAMES)])
			continue
		for tail: String in END_NAMES:
			if (ends[k] as Dictionary).has(tail):
				out.append([k, entry[k], (ends[k] as Dictionary)[tail], tail])
				break
	for r: Array in out:
		if str(r[3]) != "exit":
			print("   note: route %s is walked entry -> %s; it has no _exit anchor because" % [r[0], r[3]])
			print("         it dead-ends by design, so its exposure covers only as far as it goes.")
	return out


func _roster() -> Array:
	var e := OS.get_environment("CHASSIS")
	if e == "":
		return ROSTER.duplicate()
	var out: Array = []
	for part: String in e.split(","):
		var s := part.strip_edges().to_lower()
		if s != "":
			out.append(s)
	return out
