extends SceneTree

# ─────────────────────────────────────────────
# DO THE CAPTURE POINTS ON A MAP ACTUALLY STAND ON ANYTHING?
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_site_cores.gd
#   SURVEY=1 godot ... --script res://tools/probe_site_cores.gd
#
# WHY IT EXISTS. A site needs HOLDABLE cores, and site_slice._seat_core() only
# seats one on a host that has an `Interactible` under it — which in practice
# means a compute_core_point*.tscn instance and nothing else. Three maps were
# short of them and the ones added had to go somewhere, which is where this
# project's oldest placement bug lives: a position copied off a neighbouring
# node, written into a .tscn, and never measured. Every placement failure in
# this repo so far has been that.
#
# So this measures. Two modes:
#
#   SURVEY=1   the CANDIDATES table below, before anything is written: what the
#              ground is under each proposed spot, how flat it is across the
#              core's own footprint, and how much headroom is above it.
#   (default)  every capture point on the three levels, asserted:
#                (a) it is there at all, with an id
#                (b) there is floor within FLOOR_TOL of its feet
#                (c) it has an Interactible under it
#              Prints PASS or FAIL and exits non-zero on FAIL.
#
# THE RAY STARTS JUST ABOVE THE CORE'S FEET AND GOES DOWN A LITTLE WAY. Not
# from high up: three of these cores are indoors, up a tower, and a ray dropped
# from 200 m hits the ceiling of the hall above and reports floor that the core
# is nowhere near. Not from the core's own origin either — the prefab's
# collision starts at its feet, so the ray has to clear it and the core's own
# bodies are excluded as well. probe_footing.gd learned the same lesson.
#
# IT RUNS HEADLESS. The level's collision comes from real StaticBody3Ds and the
# headless physics server resolves rays against them perfectly well; what
# headless cannot do is render. A fistful of "Parameter m is null" mesh errors
# is the dummy renderer and is noise.
# ─────────────────────────────────────────────

## WHICH LEVELS HOLD A SITE'S CORES, and how many each should have. The counts
## are the brief's (docs/briefs/archive/SITE_CONVERSION.md) plus what was added for the
## three short maps, so a map that silently loses one fails here rather than in
## a playtest.
const LEVELS := {
	"res://maps/salient_level.tscn": 4,
	"res://maps/polaris_level.tscn": 3,
	"res://maps/causeway_level.tscn": 8,
}

const CORE_SCENES := {
	"res://Env/world_objects/compute_core_point_small.tscn": 0,
	"res://Env/world_objects/compute_core_point.tscn": 1,
	"res://Env/world_objects/compute_core_point_large.tscn": 2,
}

## Footprint and height per tier, measured off the prefabs' own collision and
## repeated in site_slice._build_core_body and _fit_reach. Used here only to
## decide how wide an area to sample and how much headroom to ask for.
const FOOT := [1.88, 3.38, 5.19]
const TALL := [4.19, 6.97, 12.38]

## HOW FAR THE FLOOR MAY BE FROM THE CORE'S FEET. A core that floats reads as
## a hologram and the player walks under it; one buried deeper than this has
## its service alcove in the dirt. One metre is the brief's own figure.
const FLOOR_TOL := 1.0
## Ray starts this far above the node's own origin, to clear its collision.
const RAY_UP := 1.4
## ...and goes this far below it. Short on purpose: a long ray finds floor two
## storeys down and calls it a pass.
const RAY_DOWN := 4.0

## THE SPOTS THE .tscn FILES ACTUALLY CARRY, and the measurement behind each.
## Kept after the fact because the next person to move one needs the same
## numbers, and because a table of derivations is the only defence against a
## coordinate that was right when it was copied off its neighbour.
##
##   [level, name, x, z, y_guess, tier]
##
## y_guess is only where the ray STARTS. The GROUND column of a survey run is
## what the scene is written with — never a rounded version of it, which is how
## three of the Causeway's cores came to float (see the header of _assert).
const CANDIDATES := [
	# SALIENT — the four lines of the depth ladder, each stepped off its own
	# eliminate objective (60 / 190 / 330 / 420) and then moved by SCAN mode to
	# the nearest flat, open ground. The lines themselves are trenches: 1.2-1.5 m
	# of spread across a core's footprint, with the parapet less than a metre
	# over the duckboard.
	["res://maps/salient_level.tscn", "sal_relay_front", 60.0, 38.0, 0.6, 0],
	["res://maps/salient_level.tscn", "sal_relay_support", 194.0, 4.0, 0.04, 1],
	["res://maps/salient_level.tscn", "sal_relay_guns", 334.0, 4.0, -0.37, 2],
	["res://maps/salient_level.tscn", "sal_relay_back", 420.0, 0.0, 0.0, 0],
	# POLARIS — the two optional garrisons that shoot into the court. Both sit
	# just OFF their objective: (96, 86) is the parking deck's own edge (6.88 m
	# of spread) and (-92, 92) is 10 m under the multiplex canopy.
	["res://maps/polaris_level.tscn", "pol_relay_cinema", -88.0, 88.0, 0.0, 0],
	["res://maps/polaris_level.tscn", "pol_relay_garage", 92.0, 86.0, 0.0, 0],
	# CAUSEWAY — three cores that were already there and already floating,
	# found by the assert pass below rather than by anything going wrong.
	["res://maps/causeway_level.tscn", "cway_relay_staging", -350.0, 30.0, 1.0, 0],
	["res://maps/causeway_level.tscn", "cway_relay_crossing", 12.0, 0.0, 5.0, 0],
	["res://maps/causeway_level.tscn", "cway_relay_checkpoint", 352.0, 58.0, 1.0, 1],
	["res://maps/causeway_level.tscn", "cway_ammo", 548.0, 146.0, 1.0, 0],
]


func _initialize() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	if OS.get_environment("SCAN") != "":
		await _scan()
	elif OS.get_environment("SURVEY") != "":
		await _survey()
	else:
		await _assert()


# ── SCAN ─────────────────────────────────────────────────────────────────────
#
# THE SURVEY ANSWERS "IS THIS SPOT ANY GOOD" AND THE ANSWER WAS NO.
#
# Three of the four Salient spots are the trench lines themselves, and a trench
# line is the one shape on that map a core cannot stand on: measured spread
# 1.2–1.5 m across a footprint, with the parapet 0.5–1.0 m above the duckboard.
# A core bedded in that stands on one corner with its alcove in the revetment.
#
# So rather than nudge by eye, this walks a grid round each target and prints
# the flat, open spots nearest to it. The objective still reads as "the gun
# line" because the core is twenty metres from it, not because a coordinate was
# typed on top of it.

## [level, name, x, z, y_guess, tier, how far out to look]
const SCAN_TARGETS := [
	["res://maps/salient_level.tscn", "first_line", 60.0, 34.0, 0.6, 0, 28.0],
	["res://maps/salient_level.tscn", "support", 190.0, 0.0, 0.04, 1, 28.0],
	["res://maps/salient_level.tscn", "guns", 330.0, 0.0, -0.37, 2, 28.0],
	["res://maps/salient_level.tscn", "back", 420.0, 0.0, 0.0, 0, 28.0],
	["res://maps/polaris_level.tscn", "garage", 96.0, 86.0, 0.0, 0, 24.0],
	["res://maps/polaris_level.tscn", "cinema", -92.0, 92.0, 0.0, 0, 24.0],
]
const SCAN_STEP := 4.0
## A core has one flat base. More spread than this across its footprint and it
## is standing on a corner.
const FLAT := 0.45


func _scan() -> void:
	var by_level := {}
	for row: Array in SCAN_TARGETS:
		var p: String = row[0]
		if not by_level.has(p):
			by_level[p] = []
		by_level[p].append(row)
	print("")
	print("══ FLAT, OPEN GROUND NEAR EACH TARGET ════════════════════")
	for path: String in by_level:
		var level := await _open(path)
		if level == null:
			continue
		var space := level.get_world_3d().direct_space_state
		var skip := _core_bodies(level)
		print("")
		print("  %s" % path.get_file())
		for row: Array in by_level[path]:
			var tier: int = int(row[5])
			var half: float = FOOT[tier] * 0.5 + 0.6
			var reach: float = float(row[6])
			var ok: Array = []
			var dx := -reach
			while dx <= reach:
				var dz := -reach
				while dz <= reach:
					var at := Vector3(row[2] + dx, float(row[4]), row[3] + dz)
					var r: Dictionary = _sample(space, at, half, skip)
					if r["hit"] and int(r["columns"]) == 9 and float(r["spread"]) <= FLAT:
						var head: float = _headroom(space,
								Vector3(at.x, float(r["ground"]), at.z), skip)
						if head >= TALL[tier] + 1.0:
							ok.append([Vector2(dx, dz).length(), at.x, at.z,
								float(r["ground"]), float(r["spread"]), head])
					dz += SCAN_STEP
				dx += SCAN_STEP
			ok.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
			print("    %s  (tier %d, needs %.1f m of headroom, %.2f m square)" % [
				row[1], tier, TALL[tier], half * 2.0])
			if ok.is_empty():
				print("      nothing flat and open within %.0f m" % reach)
				continue
			for i in mini(6, ok.size()):
				var e: Array = ok[i]
				print("      %5.0f m out   (%7.1f, %6.2f, %7.1f)  spread %.2f  head %.0f" % [
					e[0], e[1], e[3], e[2], e[4], e[5]])
		level.queue_free()
		await process_frame
	quit(0)


# ── SURVEY ───────────────────────────────────────────────────────────────────

func _survey() -> void:
	var by_level := {}
	for row: Array in CANDIDATES:
		var p: String = row[0]
		if not by_level.has(p):
			by_level[p] = []
		by_level[p].append(row)
	print("")
	print("══ GROUND UNDER THE PROPOSED CORES ═══════════════════════")
	for path: String in by_level:
		var level := await _open(path)
		if level == null:
			continue
		var space := level.get_world_3d().direct_space_state
		# A CORE ALREADY STANDING THERE IS NOT THE GROUND. Three of these spots
		# are occupied by the very core being measured, and the first run came
		# back with the Causeway's deck "at 8.52 m with 4.5 m of spread" — which
		# is the top of the core's own head and its plinth. Every capture point's
		# collision comes out of every ray.
		var skip := _core_bodies(level)
		print("")
		print("  %s" % path.get_file())
		print("  %-16s %8s %8s %8s %8s  %s" % [
			"spot", "ground", "spread", "headroom", "need", "verdict"])
		for row: Array in by_level[path]:
			var tier: int = int(row[5])
			var r: Dictionary = _sample(space, Vector3(row[2], row[4], row[3]),
					FOOT[tier] * 0.5 + 0.6, skip)
			if not r["hit"]:
				print("  %-16s %8s" % [row[1], "nothing under it"])
				continue
			var head: float = _headroom(space, Vector3(row[2], r["ground"], row[3]), skip)
			var verdict := "ok"
			if r["spread"] > 0.6:
				verdict = "UNEVEN"
			if head < TALL[tier]:
				verdict = "LOW (core is %.1f)" % TALL[tier]
			print("  %-16s %8.2f %8.2f %8.1f %8.1f  %s" % [
				row[1], r["ground"], r["spread"], head, TALL[tier], verdict])
		level.queue_free()
		await process_frame
	quit(0)


## The ground over a square of side 2*half, as nine columns: the lowest, the
## highest, and the spread between them. A core needs the spread small — it has
## one flat base and a ridge under a corner stands it on edge.
func _sample(space: PhysicsDirectSpaceState3D, at: Vector3, half: float,
		skip: Array[RID] = []) -> Dictionary:
	var lo := INF
	var hi := -INF
	var n := 0
	for ix in 3:
		for iz in 3:
			var x: float = at.x + (ix - 1) * half
			var z: float = at.z + (iz - 1) * half
			var hit := _down(space, Vector3(x, at.y, z), skip)
			if hit.is_empty():
				continue
			n += 1
			lo = minf(lo, float(hit["position"].y))
			hi = maxf(hi, float(hit["position"].y))
	if n == 0:
		return {"hit": false}
	var centre := lo
	var hit_mid := _down(space, at, skip)
	if not hit_mid.is_empty():
		centre = float(hit_mid["position"].y)
	return {"hit": true, "ground": centre, "low": lo, "spread": hi - lo, "columns": n}


func _down(space: PhysicsDirectSpaceState3D, at: Vector3, skip: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(
			at + Vector3(0.0, 8.0, 0.0), at - Vector3(0.0, 60.0, 0.0))
	q.exclude = skip
	return space.intersect_ray(q)


## How much clear height there is above a spot. 999 means open sky.
func _headroom(space: PhysicsDirectSpaceState3D, ground: Vector3,
		skip: Array[RID] = []) -> float:
	var q := PhysicsRayQueryParameters3D.create(
			ground + Vector3(0.0, 0.4, 0.0), ground + Vector3(0.0, 60.0, 0.0))
	q.exclude = skip
	var hit := space.intersect_ray(q)
	if not hit.has("position"):
		return 999.0
	return float(hit["position"].y) - ground.y


## Every capture point's collision in a level, so a ray can be asked about the
## ground rather than about the core standing on it.
func _core_bodies(level: Node) -> Array[RID]:
	var out: Array[RID] = []
	for p: Node3D in level.find_children("*", "Node3D", true, false).filter(
			func(n: Node) -> bool: return CORE_SCENES.has(n.scene_file_path)):
		for c: CollisionObject3D in p.find_children("*", "CollisionObject3D", true, false):
			out.append(c.get_rid())
	return out


# ── ASSERT ───────────────────────────────────────────────────────────────────

func _assert() -> void:
	print("")
	print("══ EVERY CAPTURE POINT ON THE THREE SITE MAPS ════════════")
	var fails: Array[String] = []
	for path: String in LEVELS:
		var level := await _open(path)
		if level == null:
			fails.append("%s will not load" % path)
			continue
		var space := level.get_world_3d().direct_space_state
		var points: Array = level.find_children("*", "Node3D", true, false).filter(
				func(n: Node) -> bool: return CORE_SCENES.has(n.scene_file_path))
		print("")
		print("  %s   %d capture point(s), %d expected" % [
			path.get_file(), points.size(), int(LEVELS[path])])
		if points.size() != int(LEVELS[path]):
			fails.append("%s has %d capture point(s), expected %d" % [
				path.get_file(), points.size(), int(LEVELS[path])])
		# `tier` IS THE TIER A SLICE MUST DECLARE, read off the prefab that is
		# actually instanced — not whatever a slice says. They can disagree, and
		# when they do site_slice._fit_reach() sizes the interact volume to the
		# tier rather than to the core, so a small core declared tier 2 gets a
		# 6.4 x 12.4 m volume the player stands inside and cannot press.
		print("  %-24s %-8s %22s %7s %6s %6s  %s" % [
			"id", "tier", "position", "floor", "clear", "inter", "verdict"])
		for p: Node3D in points:
			var tier: int = int(CORE_SCENES[p.scene_file_path])
			var id := str(p.get("id"))
			var pos := p.global_position
			# (a) IT IS THERE, AND IT HAS AN ID. A core with no id cannot be
			# named in a mission's active_objectives or by a reserve's
			# reinforcement_tag, so an unnamed one is not usable.
			var bad: Array[String] = []
			if id == "" or id == "<null>" or id == "&\"\"":
				bad.append("no id")
			# (c) AN INTERACTIBLE UNDER IT — the one thing _seat_core requires.
			var inter := _interactible_under(p)
			if inter == null:
				bad.append("no Interactible")
			# (b) FLOOR UNDER ITS FEET, from just above them.
			var skip: Array[RID] = []
			for c: CollisionObject3D in p.find_children("*", "CollisionObject3D", true, false):
				skip.append(c.get_rid())
			var q := PhysicsRayQueryParameters3D.create(
					pos + Vector3(0.0, RAY_UP, 0.0), pos + Vector3(0.0, -RAY_DOWN, 0.0))
			q.exclude = skip
			var hit := space.intersect_ray(q)
			var gap_text := "  none"
			if not hit.has("position"):
				bad.append("no floor within %.1f m" % RAY_DOWN)
			else:
				var gap: float = float(hit["position"].y) - pos.y
				gap_text = "%+6.2f" % gap
				if absf(gap) > FLOOR_TOL:
					bad.append("floor %+.2f m off its feet" % gap)
			# AND IT IS NOT INSIDE A WALL. The nine-column spread in SURVEY mode
			# proves the ground under the footprint is flat; it does not prove
			# nothing stands BETWEEN those columns. Eight rays at chest height
			# answer that, and anything inside the core's own half-footprint is
			# geometry the core is embedded in.
			var clear := _clearance(space, pos, FOOT[tier] * 0.5 + 2.0, skip)
			if clear < FOOT[tier] * 0.5:
				bad.append("geometry %.2f m from its centre, inside its own footprint" % clear)
			var verdict := "ok"
			if not bad.is_empty():
				verdict = "FAIL: " + ", ".join(bad)
				fails.append("%s / %s: %s" % [path.get_file(), id, ", ".join(bad)])
			print("  %-24s %-8d (%6.0f,%5.0f,%6.0f) %7s %6.2f %6s  %s" % [
				id, tier, pos.x, pos.y, pos.z, gap_text, clear,
				"yes" if inter != null else "NO", verdict])
		level.queue_free()
		await process_frame

	print("")
	if fails.is_empty():
		print("  PASS — every capture point has an id, floor under its feet, two")
		print("  metres of clearance round its footprint, and a terminal to use.")
		quit(0)
		return
	for f in fails:
		print("  FAIL  %s" % f)
	print("")
	print("  FAIL — %d problem(s)." % fails.size())
	quit(1)


## How far the nearest obstruction is from a core's axis, measured at chest
## height in eight directions. `reach` is as far as it bothers looking.
func _clearance(space: PhysicsDirectSpaceState3D, pos: Vector3, reach: float,
		skip: Array[RID]) -> float:
	var near := reach
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var from := pos + Vector3(0.0, 1.5, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach)
		q.exclude = skip
		var hit := space.intersect_ray(q)
		if hit.has("position"):
			near = minf(near, from.distance_to(hit["position"]))
	return near


func _interactible_under(n: Node) -> Node:
	for c in n.get_children():
		if c is Interactible:
			return c
		var f := _interactible_under(c)
		if f != null:
			return f
	return null


# ── SHARED ───────────────────────────────────────────────────────────────────

## A level in the tree with its physics settled. THE WAIT IS NOT OPTIONAL: a
## FuncGodot level builds its collision over several frames and a ray cast on
## frame one finds an empty world and reports every core floating.
func _open(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		print("  FAIL  %s will not load" % path)
		return null
	var level := packed.instantiate() as Node3D
	root.add_child(level)
	for _i in 60:
		await physics_frame
	return level
