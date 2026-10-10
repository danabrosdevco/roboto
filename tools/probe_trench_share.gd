extends "res://tools/probe_nav_reach.gd"

# ─────────────────────────────────────────────
# DOES THE SQUAD ACTUALLY USE THE TRENCHES?
#
#   LEVEL=res://maps/salient_level.tscn CHASSIS=walker,bulwark,rover,reclaimer,drone \
#       godot --path . --script res://tools/probe_trench_share.gd
#
#   FROM=Salient_Jumpoff   where the advance starts (default; SpawnPoint if the
#                          anchor does not exist)
#   STEP=2.0               sample pitch along the path, metres
#   ONLY=FrontLine         just the objectives whose name contains this
#   SUNKEN=1.0             a cut this deep or more counts as "in a cut"
#
# NOT headless. The navmesh is re-baked in memory per chassis (that machinery is
# probe_nav_reach.gd's, which is why this inherits it) and the depth test
# raycasts against real collision; a dummy renderer gives both an empty world.
#
# WHY IT EXISTS. On a trench map the fantasy is that you go forward BELOW GRADE
# and the ground above you is where the dying happens. Nothing in this project
# measured whether that is what the squad does. Two things can quietly break it:
#
#   1. A trench narrower than the bake radius is not a route at all. Godot has
#      no per-agent clearance, so clearance is decided once at bake time: a
#      3.0 m trench floor baked at agent_radius 1.0 leaves a 1.0 m ribbon, and
#      at 1.13 (the Bulwark, across its shield) it leaves nothing. The mesh then
#      has no polygons down the trench and the path goes round — ACROSS THE
#      OPEN — and every reachability probe still says PASS, because the open
#      ground either side is reachable.
#   2. A trench that IS navigable can still be slower than walking over the top,
#      and a path query minimises length, not risk. Nothing in Godot's
#      pathfinder knows that earth is worth a detour.
#
# Either way the lived experience is the same and it is the thing to disprove:
# THE PLAYER MOVES UP THE COMMUNICATION TRENCH WHILE THE SQUAD WALKS ACROSS THE
# OPEN BESIDE THEM. So this walks the real path each chassis would take to each
# objective and classifies every sample along it three ways:
#
#   in a cut     the ground beside it is SUNKEN=1.0 m or more higher. Any cut:
#                kit trench, terrain fire line, shell hole. The squad does not
#                care which.
#   covered      that cut, plus the parapet standing on its lip, is taller than
#                this chassis. THE NUMBER THAT MATTERS, and it is per chassis:
#                the same trench covers a Reclaimer and leaves a Walker's top
#                metre in the air.
#   in the works the sample is inside the footprint of a laid kit piece — the
#                built trench system rather than any old hole. The difference
#                between "in a cut" and "in the works" is how much of the
#                cover the squad gets is DESIGN and how much is shell damage.
#
# The verdict is the covered share. Everything else is there to explain it.
# ─────────────────────────────────────────────

const LIB := preload("res://tools/probe_trench_lib.gd")

## Default roster: the four the honest bake was proved against, plus the player
## so the comparison the suspicion is about — squad versus player — is in one
## table rather than two runs.
const ROSTER := ["drone", "walker", "bulwark", "rover", "reclaimer"]

## What stands on the lip of a cut, by what dug it. These are the two parapets
## on this map and they are nearly the same height, which is why the covered
## share barely moves between a kit trench and a fire line:
##   kit wall top      +0.60 above grade (block_trench.gd T_PARAPET)
##   revetment parapet +0.59 above grade (feature_trench_revetment, as measured
##                     in tools/mapdeck_data.gd's own comment)
## Read from the kit manifest where it can be; the dressing number has no
## manifest, so it is named and sourced rather than silently assumed.
const PARAPET_FALLBACK := 0.60

## How close to a laid kit piece's origin counts as "in the works". The kit's
## own spans are in the manifest but the pieces are placed with a transform this
## probe would have to re-derive; the widest piece is the 9.6 m sunken road and
## half of that plus a metre is an honest radius.
const WORKS_NEAR := 6.0

var _level: Node3D = null
var _space: PhysicsDirectSpaceState3D = null
var _works: Array = []
var _parapet := PARAPET_FALLBACK


func _initialize() -> void:
	await process_frame
	var level_path := OS.get_environment("LEVEL")
	if level_path == "":
		print("usage: LEVEL=res://maps/salient_level.tscn CHASSIS=walker,bulwark godot --path . --script res://tools/probe_trench_share.gd")
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

	var sect := LIB.section()
	if sect.has("parapet"):
		_parapet = float(sect.parapet)
	else:
		print("   NOTE  no kit manifest section — parapet taken as %.2f m" % _parapet)
	print("   section as built: floor %.2f, parapet +%.2f  (cover %.2f m in the kit trench)" % [
			float(sect.get("floor", -1.4)), _parapet,
			_parapet - float(sect.get("floor", -1.4))])
	if sect.has("road_floor"):
		print("   sunken road:      floor %.2f, parapet +%.2f  (cover %.2f m, floor %.1f m wide)" % [
				float(sect.road_floor), _parapet,
				_parapet - float(sect.road_floor), float(sect.get("road_half", 4.0)) * 2.0])

	_works = _kit_pieces()
	print("   %d laid kit piece(s) under Trenchworks" % _works.size())

	var step := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 2.0
	var sunken := float(OS.get_environment("SUNKEN")) if OS.get_environment("SUNKEN") != "" else 1.0
	var only := OS.get_environment("ONLY")
	var who_list := _roster()
	var start_node := OS.get_environment("FROM") if OS.get_environment("FROM") != "" else "Salient_Jumpoff"

	var fails := 0
	var summary: Array = []
	for who: String in who_list:
		var f: Array = LIB.frame(who)
		if f.is_empty():
			print("   %s — NOT MEASURED, no such chassis in the frame table" % who)
			fails += 1
			continue
		# Re-bake at this body's real numbers. _refit reads CHASSIS from the
		# environment, so the environment is what gets set: the alternative is a
		# second copy of the bake code, and a second copy of the bake code is
		# the thing probe_nav_reach.gd's comment block is about.
		OS.set_environment("CHASSIS", who)
		var nav := await _refit(region, region.navigation_mesh)
		if nav == null:
			# Not a probe failure and the honest answer for that body: it does
			# not fit anywhere on this map. _refit has already said so.
			print("   %s — the bake came back empty; no path to measure" % who)
			summary.append([who, -1.0, -1.0, -1.0, 0.0])
			continue
		map = region.get_navigation_map()
		var from := _start(start_node)
		if is_nan(from.x):
			print("FAIL  no %s anchor and no SpawnPoint — nowhere to start the advance" % start_node)
			quit(1)
			return
		print("")
		print("── %s   body %.2f m tall, bake radius %.2f (%.2f m wide)" % [
				who.to_upper(), LIB.height_of(who), float(f[0]), float(f[0]) * 2.0])
		print("   starting from %s at %s" % [start_node, _s(from)])
		print("   %-18s %7s  %7s %7s %7s  %s" % [
				"objective", "walk", "in cut", "covered", "works", ""])
		var walked := 0.0
		var cut_m := 0.0
		var cov_m := 0.0
		var works_m := 0.0
		for o in _anchors():
			var nm := str(o.name)
			if only != "" and not nm.contains(only):
				continue
			var to := _snap((o as Node3D).global_position)
			# THE OBJECTIVE YOU ARE STANDING ON IS NOT UNREACHABLE. The advance
			# starts at the jump-off trench, which is itself an objective anchor,
			# and map_get_path returns fewer than two points for a zero-length
			# walk — which the first run of this counted as a failure, once per
			# chassis, and reported FAIL on a map where everything was fine.
			if from.distance_to(to) <= ARRIVED:
				print("   %-18s  the start line — nothing walked" % nm)
				continue
			var r := _measure(from, to, step, sunken, who)
			if float(r.len) <= 0.0:
				print("   %-18s  no path — UNREACHABLE at this bake" % nm)
				fails += 1
				continue
			walked += float(r.len)
			cut_m += float(r.cut)
			cov_m += float(r.cov)
			works_m += float(r.works)
			print("   %-18s %6.0fm  %6.1f%% %6.1f%% %6.1f%%  longest open stretch %.0f m" % [
					nm, float(r.len),
					100.0 * float(r.cut) / float(r.len),
					100.0 * float(r.cov) / float(r.len),
					100.0 * float(r.works) / float(r.len),
					float(r.open_run)])
		if walked <= 0.0:
			print("   nothing walked — every objective was skipped or unreachable")
			fails += 1
			continue
		var cut_share := 100.0 * cut_m / walked
		var cov_share := 100.0 * cov_m / walked
		var works_share := 100.0 * works_m / walked
		print("   ALL OBJECTIVES   %6.0fm  %6.1f%% %6.1f%% %6.1f%%" % [
				walked, cut_share, cov_share, works_share])
		summary.append([who, cut_share, cov_share, works_share, walked])

	print("")
	print("   %-12s %8s %8s %8s   %s" % ["chassis", "in cut", "covered", "works", "verdict"])
	for row: Array in summary:
		if float(row[1]) < 0.0:
			print("   %-12s %8s %8s %8s   does not fit this map at all" % [row[0], "-", "-", "-"])
			continue
		# 50% is not a standard, it is a reading: half an advance below grade is
		# a trench map, a tenth of one is open ground with trenches drawn on it.
		var verdict := "fights from below grade"
		if float(row[2]) < 10.0:
			verdict = "WALKS IN THE OPEN — the trenches are scenery to it"
		elif float(row[2]) < 35.0:
			verdict = "mostly in the open"
		elif float(row[2]) < 60.0:
			verdict = "mixed"
		print("   %-12s %7.1f%% %7.1f%% %7.1f%%   %s" % [row[0], row[1], row[2], row[3], verdict])
	print("TRENCH SHARE %s" % ["PASS" if fails == 0 else "FAIL — %d problem(s)" % fails])
	quit(1 if fails > 0 else 0)


## One path, classified.
func _measure(from: Vector3, to: Vector3, step: float, sunken: float, who: String) -> Dictionary:
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.size() < 2:
		return {"len": 0.0, "cut": 0.0, "cov": 0.0, "works": 0.0, "open_run": 0.0}
	var samples: Array = LIB.densify(path, step)
	var head: float = LIB.height_of(who)
	var total := 0.0
	var cut := 0.0
	var cov := 0.0
	var works := 0.0
	var open_run := 0.0
	var open_best := 0.0
	for i in samples.size():
		var p: Vector3 = samples[i]
		# A sample's share of the walk: half the leg behind it and half ahead,
		# so the ends are not double counted and the shares add to the length.
		var span := 0.0
		if i > 0:
			span += (samples[i] as Vector3).distance_to(samples[i - 1] as Vector3) * 0.5
		if i < samples.size() - 1:
			span += (samples[i] as Vector3).distance_to(samples[i + 1] as Vector3) * 0.5
		total += span
		var d: float = LIB.cut_depth(_space, p.x, p.z)
		var in_cut := not is_nan(d) and d >= sunken
		if in_cut:
			cut += span
		# THE PARAPET IS ONLY CREDITED WHERE THERE IS A LIP TO STAND ON. The
		# first run of this added it to every sample and so reported a 0.80 m
		# Reclaimer "covered" for 37.6% of its walk — most of that was open
		# field with an imaginary 0.6 m of sandbags on it. Earth below grade is
		# cover anywhere; a parapet exists only on the edge of a cut.
		var cover := d
		if in_cut:
			cover += _parapet
		if not is_nan(d) and cover >= head:
			cov += span
			open_run = 0.0
		else:
			open_run += span
			open_best = maxf(open_best, open_run)
		if _near_works(p):
			works += span
	return {"len": total, "cut": cut, "cov": cov, "works": works, "open_run": open_best}


## Every laid kit piece's world position, from the art scene's Trenchworks
## groups. Anchors are markers and Landmarks are a tank and a tower, so neither
## is a piece of trench; everything else under Trenchworks is.
func _kit_pieces() -> Array:
	var out: Array = []
	var works: Node = null
	for n in _level.find_children("Trenchworks", "Node3D", true, false):
		works = n
		break
	if works == null:
		print("   WARN  no Trenchworks node — the 'works' column below will read 0% everywhere")
		print("         and that is a missing node, not a map without a trench system.")
		return out
	for group in works.get_children():
		if str(group.name) in ["Anchors", "Landmarks"]:
			continue
		for piece in group.get_children():
			if piece is Node3D:
				out.append((piece as Node3D).global_position)
	return out


func _near_works(p: Vector3) -> bool:
	for w: Vector3 in _works:
		if Vector2(w.x - p.x, w.z - p.z).length() <= WORKS_NEAR:
			return true
	return false


## Where the advance starts: the named anchor, else the level's SpawnPoint.
func _start(node_name: String) -> Vector3:
	var at: Vector3 = LIB.objective(_level, node_name)
	if not is_nan(at.x):
		return _snap(at)
	var spawn: Node3D = _level.get_node_or_null("SpawnPoint")
	if spawn == null:
		return Vector3(NAN, NAN, NAN)
	print("   NOTE  no %s anchor; starting from SpawnPoint instead, which is" % node_name)
	print("         the level entry and not the jump-off — the first few hundred")
	print("         metres of every walk below are rear-area approach march.")
	return _snap(spawn.global_position)


## The objective anchors, from wherever this level keeps them.
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
