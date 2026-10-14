extends "res://tools/probe_nav_reach.gd"

# ─────────────────────────────────────────────
# IS THERE MORE THAN ONE WAY FORWARD, AND DOES THE CHOICE COST SOMETHING?
#
#   LEVEL=res://maps/salient_level.tscn CHASSIS=drone,walker,bulwark \
#       godot --path . --script res://tools/probe_route_choice.gd
#
#   FROM=Salient_Jumpoff   where the advance starts (default)
#   STEP=4.0               sample pitch for the exposure half, metres
#   SPREAD=25              per cent within the cheapest that still counts as a
#                          real alternative rather than a detour
#   NOEXPOSE=1             skip the exposure half (much faster, half the answer)
#
# NOT headless: the navmesh is re-baked per chassis (probe_nav_reach.gd's
# machinery, which is why this inherits it) and the exposure half raycasts.
#
# WHY IT EXISTS. "Interesting" is not "pretty" and it is not "reachable". The
# question a level either answers or does not is: from where I am standing, are
# there several ways on, and do they differ in a way I would weigh? A map where
# every path is the same length and equally safe is a corridor with scenery, and
# probe_nav_reach.gd cannot tell the two apart — it reports PASS on both,
# because both are reachable.
#
# So this prices the alternatives instead of counting them. For every objective
# it walks the path the squad would actually take, and then walks the SAME
# objective again forced through each built corridor in turn — entry anchor, far
# end, on to the objective. Out of that, per objective and per chassis:
#
#   direct        metres the pathfinder chooses on its own, and how exposed
#   via A/B/C     metres through that corridor, as a multiplier on direct, and
#                 how exposed THAT is
#   choices       how many corridors come within SPREAD per cent of the
#                 cheapest way there. THE NUMBER THE PROBE IS FOR: one choice
#                 is a corridor, three choices at the same price is a shrug,
#                 and three choices at different prices is a decision.
#
# WHY COST IS TWO NUMBERS AND NOT ONE. Length alone says the corridors are
# detours, which is true and useless: a 20% longer route that is 60% less
# exposed is the trade the whole map is built to offer. A difference in metres
# with no difference in exposure is the shrug. Both columns, always, and never
# averaged across chassis — a walker and the player are offered different maps
# by the same geometry.
# ─────────────────────────────────────────────

const LIB := preload("res://tools/probe_trench_lib.gd")

const ROSTER := ["drone", "walker", "bulwark"]

## The far end of a corridor, in order of preference. Not every route has an
## _exit: the crater chain dead-ends at an uncut wire belt on purpose.
const END_NAMES := ["exit", "wire", "last_crater", "dugout", "blown"]

var _level: Node3D = null
var _space: PhysicsDirectSpaceState3D = null
var _eyes: Array = []
var _step := 4.0


func _initialize() -> void:
	await process_frame
	var level_path := OS.get_environment("LEVEL")
	if level_path == "":
		print("usage: LEVEL=res://maps/salient_level.tscn godot --path . --script res://tools/probe_route_choice.gd")
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
	_step = float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 4.0
	var spread := float(OS.get_environment("SPREAD")) if OS.get_environment("SPREAD") != "" else 25.0
	var expose := OS.get_environment("NOEXPOSE") == ""

	if expose:
		var front: Vector3 = LIB.objective(_level, "Salient_FrontLine")
		if is_nan(front.x):
			print("   WARN  no Salient_FrontLine anchor, so there is no enemy side to")
			print("         measure exposure against. Lengths only below, and a route")
			print("         choice priced in metres alone is the half that misleads.")
			expose = false
		else:
			_eyes = LIB.firing_positions(_level, _space, front.x, -200.0, 200.0, 25.0)
			if _eyes.is_empty():
				print("   WARN  no enemy firing positions found — exposure not measured")
				expose = false

	var corridors := _corridors()
	if corridors.is_empty():
		print("FAIL  no route anchors under Trenchworks/Anchors — there are no")
		print("      built alternatives to price, so this probe has nothing to say.")
		quit(1)
		return
	var names: Array = []
	for c: Array in corridors:
		names.append(str(c[0]))
	print("   corridors: %s" % ", ".join(names))

	var start_node := OS.get_environment("FROM") if OS.get_environment("FROM") != "" else "Salient_Jumpoff"
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
			print("   %s — the bake came back empty; nothing to price" % who)
			continue
		map = region.get_navigation_map()
		var from: Vector3 = LIB.objective(_level, start_node)
		if is_nan(from.x):
			var spawn: Node3D = _level.get_node_or_null("SpawnPoint")
			if spawn == null:
				print("FAIL  no %s anchor and no SpawnPoint — nowhere to start" % start_node)
				quit(1)
				return
			print("   NOTE  no %s anchor; starting from SpawnPoint, which is the level" % start_node)
			print("         entry and not the jump-off.")
			from = spawn.global_position
		from = _snap(LIB.at_floor(_space, from))
		print("")
		print("── %s   from %s at %s%s" % [who.to_upper(), start_node, _s(from),
				"" if expose else "   (lengths only)"])
		var head_line := "   %-18s %16s" % ["objective", "direct"]
		for c: Array in corridors:
			head_line += " %16s" % ("via " + str(c[0]))
		print(head_line + "  choices")
		var one_choice := 0
		var measured := 0
		for o in _anchors():
			var nm := str(o.name)
			var to := _snap(LIB.at_floor(_space, (o as Node3D).global_position))
			if from.distance_to(to) <= ARRIVED:
				print("   %-18s the start line — nothing to choose yet" % nm)
				continue
			var direct := _leg(from, to, expose)
			if float(direct[0]) <= 0.0:
				print("   %-18s UNREACHABLE at this bake" % nm)
				fails += 1
				continue
			measured += 1
			var row := "   %-18s %7.0fm %6s" % [nm, float(direct[0]),
					("%.0f%%" % (100.0 * float(direct[1]))) if expose else "-"]
			var best: float = float(direct[0])
			var costs: Array = []
			for c: Array in corridors:
				var legs := _via(from, c[1] as Vector3, c[2] as Vector3, to, expose)
				costs.append(legs)
				if float(legs[0]) <= 0.0:
					row += " %16s" % ("no: " + str(legs[2]) if legs.size() > 2 else "no path")
					continue
				best = minf(best, float(legs[0]))
				row += " %7.0fm %6s" % [float(legs[0]),
						("%.0f%%" % (100.0 * float(legs[1]))) if expose else "-"]
			# WHAT COUNTS AS A CHOICE. Anything — including walking straight at
			# it — whose cost is within SPREAD per cent of the cheapest way
			# there. The direct line is always one of the options on offer and
			# pretending otherwise is how a map gets credit for corridors
			# nobody would use.
			var choices := 0
			var all: Array = [direct] + costs
			for k: Array in all:
				if float(k[0]) > 0.0 and float(k[0]) <= best * (1.0 + spread * 0.01):
					choices += 1
			if choices <= 1:
				one_choice += 1
			print("%s  %d" % [row, choices])
		if measured > 0:
			print("   %d of %d objective(s) offer ONE way forward at this bake (within %.0f%%)" % [
					one_choice, measured, spread])
	print("ROUTE CHOICE %s" % ["PASS" if fails == 0 else "FAIL — %d problem(s)" % fails])
	quit(1 if fails > 0 else 0)


## One leg: metres, and the share of it an enemy eye can see. Zero metres means
## the leg does not exist.
##
## IT HAS TO CHECK THAT THE WALK ARRIVED, and the first run of this probe did
## not — which is how it came back reporting "via B 366 m" for all ten
## objectives and "via C 227 m" for all ten at the Bulwark's radius. map_get_path
## never fails: given an unreachable target it returns the walk to the nearest
## point it CAN get to, so a corridor whose far end snaps onto an island returns
## the length of that island, identically, for every objective on the map. The
## giveaway was that the number did not move; the fix is probe_nav_reach.gd's
## ARRIVED threshold, which is the same test its own reachability sweep uses.
func _leg(from: Vector3, to: Vector3, expose: bool) -> Array:
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.size() < 2:
		return [0.0, 0.0]
	if (path[path.size() - 1] as Vector3).distance_to(to) > ARRIVED:
		return [0.0, 0.0]
	var samples: Array = LIB.densify(path, _step)
	var total: float = LIB.run_length(samples)
	if not expose or total <= 0.0:
		return [total, 0.0]
	var seen := 0.0
	var head: float = LIB.head_of(_who.split("+")[0])
	for i in samples.size():
		var p: Vector3 = samples[i]
		var span := 0.0
		if i > 0:
			span += (samples[i] as Vector3).distance_to(samples[i - 1] as Vector3) * 0.5
		if i < samples.size() - 1:
			span += (samples[i] as Vector3).distance_to(samples[i + 1] as Vector3) * 0.5
		var g: float = LIB.ground(_space, p.x, p.z)
		if is_nan(g):
			# EVERY SKIP SAYS WHY: no collision under a path sample means the
			# navmesh and the physics world disagree there, and the sample is
			# counted as neither seen nor hidden.
			push_warning("probe_route_choice: no collision under a path sample at (%.0f, %.0f) — not classified" % [p.x, p.z])
			continue
		if LIB.seen_by(_space, _eyes, Vector3(p.x, g + head, p.z)) > 0:
			seen += span
	return [total, seen / total]


## The same objective, forced through a corridor: to its entry, along it, on.
## Three legs and not one query, because map_get_path has no waypoints — and
## the sum IS the cost of insisting on that corridor, which is the number the
## choice is being priced on.
func _via(from: Vector3, entry: Vector3, out: Vector3, to: Vector3, expose: bool) -> Array:
	var a := _leg(from, _ground_snap(entry), expose)
	var b := _leg(_ground_snap(entry), _ground_snap(out), expose)
	var c := _leg(_ground_snap(out), to, expose)
	# WHICH LEG FAILED IS THE WHOLE DIAGNOSIS. "to entry" means the corridor's
	# mouth cannot be reached at this radius, "along" means the corridor itself
	# is severed, and "to obj" means it delivers you somewhere you cannot leave.
	if float(a[0]) <= 0.0:
		return [0.0, 0.0, "to entry"]
	if float(b[0]) <= 0.0:
		return [0.0, 0.0, "along"]
	if float(c[0]) <= 0.0:
		return [0.0, 0.0, "to obj"]
	var total: float = float(a[0]) + float(b[0]) + float(c[0])
	var seen: float = float(a[0]) * float(a[1]) + float(b[0]) * float(b[1]) + float(c[0]) * float(c[1])
	return [total, seen / total]


## An anchor put on the ground first, then snapped to the navmesh. See
## probe_trench_lib.gd's at_floor(): the Trenchworks anchors are written at
## y = 0 and a 3D snap from there lands on the parapet, which is an island.
func _ground_snap(p: Vector3) -> Vector3:
	return _snap(LIB.at_floor(_space, p))


## Corridor name, entry, far end — from the builder's own anchors.
func _corridors() -> Array:
	var holder: Node = null
	for n in _level.find_children("Anchors", "Node3D", true, false):
		holder = n
		break
	if holder == null:
		return []
	var entry := {}
	var ends := {}
	for a in holder.get_children():
		var parts := str(a.name).split("_", false, 1)
		if parts.size() < 2:
			continue
		if parts[1] == "entry":
			entry[parts[0]] = (a as Node3D).global_position
		elif END_NAMES.has(parts[1]):
			if not ends.has(parts[0]):
				ends[parts[0]] = {}
			ends[parts[0]][parts[1]] = (a as Node3D).global_position
	var out: Array = []
	var keys: Array = entry.keys()
	keys.sort()
	for k: String in keys:
		if not ends.has(k):
			print("   note: corridor %s has an entry and no far end — not priced" % k)
			continue
		for tail: String in END_NAMES:
			if (ends[k] as Dictionary).has(tail):
				out.append([k, entry[k], (ends[k] as Dictionary)[tail]])
				break
	return out


func _anchors() -> Array:
	for p: String in OBJ_HOLDERS:
		var h := _level.get_node_or_null(p)
		if h != null:
			var out: Array = []
			for c in h.get_children():
				if c is Node3D:
					out.append(c)
			return out
	print("   WARN  no objective group under any of %s — nothing to walk to" % ", ".join(OBJ_HOLDERS))
	return []


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
