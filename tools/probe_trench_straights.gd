extends SceneTree

# ─────────────────────────────────────────────
# TRAVERSES — how long is the longest straight unbroken run in each line?
#
#   LEVEL=res://maps/salient_level.tscn \
#       godot --path . --script res://tools/probe_trench_straights.gd
#
#   TOL=8.0     degrees of turn that still counts as "straight"
#   EYE=1.0     height above the floor the sightline is cast from
#   GEOM=1      skip the raycasts and measure the centrelines only (headless OK)
#
# NOT headless unless GEOM=1: the sightline half of this casts against real
# collision.
#
# WHY IT EXISTS. A trench is traversed — stepped every few metres — for one
# reason: so that a gun firing along it cannot rake the whole run, and so a
# shell bursting in it kills one bay and not the line. block_trench.gd's own
# comment on _tr_traverse says exactly that, and adds the thing that makes it a
# game concern rather than a history note: it is what makes a trench fight
# READABLE, because no sightline is longer than a bay. A 60 m straight trench is
# a shooting gallery, and it is also historically wrong, and the kit holds
# trench_traverse and trench_traverse_r precisely so it need never happen.
#
# Two measurements, because they answer different halves of it:
#
#   CENTRELINE   the longest stretch of a line that does not turn by more than
#                TOL degrees. This is the shape of the line, and it applies to
#                every trench on the map including the terrain-cut fire lines,
#                which have no walls to cast against.
#   SIGHTLINE    stand on the floor of each laid kit piece at EYE height and
#                cast along the trench's own heading, both ways. How far before
#                earth stops you IS the enfilade question, and it is the only
#                one of the two a player experiences directly.
#
# The two disagree on purpose. A zigzag whose amplitude is small compared with
# its wavelength has short centreline segments and a long sightline, because
# the jog is not big enough to put earth in the way — which is the failure mode
# a centreline-only measurement would call a pass.
#
# AND ON SALIENT THAT DISAGREEMENT IS EXACTLY WHAT IT FOUND, which is the
# reason the sightline half exists at all: the communication trench's
# centreline never runs straight for more than 18.5 m, and a ray down its floor
# at 1.0 m goes 80 m.
#
# A CORRECTION, LEFT IN BECAUSE IT WAS PUBLISHED WRONG ONCE. The first version
# of this comment blamed the kit: it worked out that trench_traverse steps the
# centreline by (T_HALF * 2 + T_WALL * 2) / 2 = 2.3 m against a 3.0 m floor,
# called the 0.7 m difference an overlap, and concluded that a centred ray
# threads every traverse in the project. VERBOSE=1 says otherwise, and the
# geometry agrees with VERBOSE: the entry bay spans y -3.8 to -0.8 and the exit
# bay +0.8 to +3.8, so they do not overlap at all, and every traverse piece on
# Salient measures 3.0 m of total sightline — 1.5 m each way, which is the jog
# and nothing more. THE KIT'S TRAVERSE WORKS.
#
# The 80 m is a PLACEMENT fault instead: route C's recipe lays its four
# traverses as two adjacent pairs (traverse then traverse_r, which jogs left
# then back right and returns the line to its own centre), at x -101/-89 and
# -12/0 — leaving 77 m of dead straight trench between the pairs with nothing
# in it. Same number, opposite fix: spread the traverses through the run rather
# than pairing them. Which is why the per-station list exists at all; a summary
# line cannot tell a kit fault from a recipe fault.
# ─────────────────────────────────────────────

const LIB := preload("res://tools/probe_trench_lib.gd")

## A piece whose name contains one of these ENDS a straight, whatever its
## neighbours' positions say: it is a built turn. The traverse is the important
## one — its two bays are offset by 2.3 m, so three pieces in a row read as
## collinear from their origins while the floor between them is an S.
const BREAK_PIECES := ["traverse", "corner", "junction", "blown"]

## Where a straight stops mattering. 30 m is one bay of this map's fire lines
## (tools/mapdeck_data.gd traverses them at a 30 m step), so it is this map's
## own idea of a bay rather than an imported standard.
const BAY := 30.0

## Beyond this a sightline is not a trench, it is a view. The ray is given a
## finite length so "no hit" is a number and not an infinity.
const RAY := 400.0

## NOT A LENGTH OF ROUTE. A wire belt is laid as part of a route — it is the
## fence the route runs at, or the gate through it — but it is a fence standing
## in the open, and a sightline measured from on top of one is a view across
## no-man's-land. Left in, the four belts at the end of the crater chain
## reported it as a 456 m shooting gallery while the shell holes that ARE the
## route read 18.8 m. Measuring the obstacle instead of the trench is the
## single most misleading thing this probe did.
const NOT_A_RUN := ["wire_belt"]


func _initialize() -> void:
	await process_frame
	var level_path := OS.get_environment("LEVEL")
	if level_path == "":
		print("usage: LEVEL=res://maps/salient_level.tscn godot --path . --script res://tools/probe_trench_straights.gd")
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
	var geom_only := OS.get_environment("GEOM") != ""
	var space: PhysicsDirectSpaceState3D = null
	if not geom_only:
		space = level.get_world_3d().direct_space_state
	var tol := float(OS.get_environment("TOL")) if OS.get_environment("TOL") != "" else 8.0
	var eye := float(OS.get_environment("EYE")) if OS.get_environment("EYE") != "" else 1.0
	if geom_only:
		print("   GEOM=1 — centrelines only; the sightline half is NOT measured,")
		print("   and the sightline half is the one a player feels.")

	var worst := 0.0
	var worst_who := ""

	print("")
	print("── THE LAID KIT ROUTES, by centreline")
	var routes := _kit_routes(level)
	if routes.is_empty():
		print("   no Trenchworks groups in this level — no built routes to measure")
	for key: String in routes:
		var pieces: Array = routes[key]
		var longest := _longest_straight(pieces, tol)
		var note := "" if float(longest[0]) <= BAY else "  <- longer than a %.0f m bay" % BAY
		print("   %-14s %2d piece(s), longest straight %6.1f m (%s to %s)%s" % [
				key, pieces.size(), float(longest[0]), longest[1], longest[2], note])
		if float(longest[0]) > worst:
			worst = float(longest[0])
			worst_who = key + " centreline"

	print("")
	print("── THE TERRAIN-CUT FIRE LINES, by centreline")
	var cuts := _terrain_cuts(level)
	if cuts.is_empty():
		print("   no Path3D trench cuts under Terrain — if this map's fire lines are")
		print("   terrain paths, they are NOT being measured and this section is blind.")
	for row: Array in cuts:
		var note := "" if float(row[1]) <= BAY else "  <- longer than a %.0f m bay" % BAY
		print("   %-14s %4.0f m long, longest straight %6.1f m%s" % [
				row[0], float(row[2]), float(row[1]), note])
		if float(row[1]) > worst:
			worst = float(row[1])
			worst_who = str(row[0]) + " centreline"

	if not geom_only:
		print("")
		print("── SIGHTLINES DOWN THE LAID WORKS, at %.2f m over the floor" % eye)
		var rows: Array = []
		for key: String in routes:
			var pieces: Array = routes[key]
			var best := 0.0
			var best_at := Vector3.ZERO
			var total := 0.0
			var n := 0
			var open_ended := 0
			var skipped_fence := 0
			for i in pieces.size():
				var at: Vector3 = (pieces[i] as Array)[1]
				var fence := false
				for p: String in NOT_A_RUN:
					if str((pieces[i] as Array)[0]).contains(p):
						fence = true
				if fence:
					skipped_fence += 1
					continue
				var dir := _heading(pieces, i)
				if dir == Vector3.ZERO:
					continue
				var g: float = LIB.ground(space, at.x, at.z)
				if is_nan(g):
					push_warning("probe_trench_straights: no collision under %s — no sightline from it" % (pieces[i] as Array)[0])
					continue
				var from := Vector3(at.x, g + eye, at.z)
				var verbose := OS.get_environment("VERBOSE") != ""
				var fwd := _clear(space, from, dir)
				var back := _clear(space, from, -dir)
				var d: float = float(fwd[0]) + float(back[0])
				# A DIRECTION THAT HITS NOTHING IN RAY METRES IS NOT A SIGHTLINE
				# DOWN A TRENCH, it is a view out of one, and saying so is the
				# difference between a measurement and a number. It happens where
				# the "trench" is a shallow scrape whose lip is below the eye.
				if not bool(fwd[1]) or not bool(back[1]):
					open_ended += 1
				# VERBOSE=1 prints every station. WHICH piece a long sightline
				# is measured from is the whole diagnosis: a long run between
				# two traverses is a placement fault in the route's recipe, and
				# a long run THROUGH a traverse would be a fault in the kit.
				# Those want opposite fixes and the summary cannot tell them
				# apart.
				if verbose:
					print("      %-28s %6.1f m fwd + %6.1f m back = %6.1f m" % [
							(pieces[i] as Array)[0], float(fwd[0]), float(back[0]), d])
				best = maxf(best, d)
				if is_equal_approx(best, d):
					best_at = at
				total += d
				n += 1
			if skipped_fence > 0:
				print("   %-14s %d wire-belt piece(s) left out: a fence across the route" % [
						key, skipped_fence])
			if n == 0:
				print("   %-14s nothing measurable — every piece of it is a fence" % key)
				continue
			rows.append([key, best, total / float(n), best_at, open_ended, n])
		for r: Array in rows:
			var note := "" if float(r[1]) <= BAY else "  <- a gun on this line rakes %.0f m of it" % float(r[1])
			print("   %-14s longest %6.1f m (near %.0f, %.0f), mean %5.1f m%s" % [
					r[0], float(r[1]), (r[3] as Vector3).x, (r[3] as Vector3).z,
					float(r[2]), note])
			if int(r[4]) > 0:
				print("                  %d of %d position(s) had an open direction — nothing" % [int(r[4]), int(r[5])])
				print("                  within %.0f m that way, so this line does not enclose you." % RAY)
			if float(r[1]) > worst:
				worst = float(r[1])
				worst_who = str(r[0]) + " sightline"

	print("")
	# THE VERDICT IS THE WORST NUMBER ON THE MAP, not an average. An average
	# hides the one 90 m straight that is the shooting gallery.
	var ok := worst <= BAY * 2.0
	print("TRAVERSES %s — longest unbroken run anywhere: %.0f m (%s), bay is %.0f m" % [
			"PASS" if ok else "FAIL", worst, worst_who, BAY])
	quit(0 if ok else 1)


## Laid pieces by route group: [[name, position], ...] in laid order.
func _kit_routes(level: Node3D) -> Dictionary:
	var out := {}
	var works: Node = null
	for n in level.find_children("Trenchworks", "Node3D", true, false):
		works = n
		break
	if works == null:
		return out
	for group in works.get_children():
		if str(group.name) in ["Anchors", "Landmarks"]:
			continue
		var list: Array = []
		for piece in group.get_children():
			if piece is Node3D:
				list.append([str(piece.name), (piece as Node3D).global_position])
		# Laid order is the name order: the builder numbers them A00, A01, ...
		list.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
		if list.size() > 0:
			out[str(group.name)] = list
	return out


## The longest run of pieces that neither turns more than `tol` nor crosses a
## built turn. Returns [metres, from name, to name].
func _longest_straight(pieces: Array, tol: float) -> Array:
	var best := 0.0
	var best_from := "-"
	var best_to := "-"
	var run := 0.0
	var start := 0
	for i in range(1, pieces.size()):
		var a: Vector3 = (pieces[i - 1] as Array)[1]
		var b: Vector3 = (pieces[i] as Array)[1]
		var leg := Vector2(b.x - a.x, b.z - a.z)
		var broke := false
		for p: String in BREAK_PIECES:
			if str((pieces[i] as Array)[0]).contains(p) or str((pieces[i - 1] as Array)[0]).contains(p):
				broke = true
		if not broke and i >= 2:
			var prev: Vector3 = (pieces[i - 2] as Array)[1]
			var was := Vector2(a.x - prev.x, a.z - prev.z)
			if was.length() > 0.5 and leg.length() > 0.5:
				if absf(rad_to_deg(was.angle_to(leg))) > tol:
					broke = true
		if broke:
			if run > best:
				best = run
				best_from = str((pieces[start] as Array)[0])
				best_to = str((pieces[maxi(i - 1, start)] as Array)[0])
			run = 0.0
			start = i
			continue
		run += leg.length()
	if run > best:
		best = run
		best_from = str((pieces[start] as Array)[0])
		best_to = str((pieces[pieces.size() - 1] as Array)[0])
	return [best, best_from, best_to]


## The terrain path cuts: [name, longest straight, total length].
func _terrain_cuts(level: Node3D) -> Array:
	var out: Array = []
	var other := 0
	for n in level.find_children("*", "Path3D", true, false):
		var path := n as Path3D
		# TERRAIN PATHS ARE NOT ALL TRENCHES. Env/terrain/terrain_path.gd's
		# `mode` is 1 for a cut and something else for a road or a river, and
		# this map has both — a road's centreline measured as a trench would
		# report a 900 m straight and bury the real answer.
		var mode: Variant = path.get("mode")
		if mode != null and int(mode) != 1 and not str(path.get_parent().name).containsn("trench"):
			other += 1
			continue
		if path.curve == null or path.curve.point_count < 2:
			push_warning("probe_trench_straights: %s is a Path3D with no usable curve — skipped" % path.name)
			continue
		var pts: Array = []
		for i in path.curve.point_count:
			var p: Vector3 = path.global_transform * path.curve.get_point_position(i)
			pts.append([str(i), p])
		var longest := _longest_straight(pts, float(OS.get_environment("TOL")) if OS.get_environment("TOL") != "" else 8.0)
		var total := 0.0
		for i in range(1, pts.size()):
			total += ((pts[i] as Array)[1] as Vector3).distance_to((pts[i - 1] as Array)[1] as Vector3)
		out.append([str(path.name), float(longest[0]), total])
	if other > 0:
		print("   (%d Path3D(s) skipped: roads, rivers and other non-cut paths)" % other)
	return out


## Which way the trench runs at piece i, from its neighbours. Horizontal only:
## a sightline down a trench is not interested in the floor's slope.
func _heading(pieces: Array, i: int) -> Vector3:
	var a: Vector3
	var b: Vector3
	if i == 0:
		if pieces.size() < 2:
			return Vector3.ZERO
		a = (pieces[0] as Array)[1]
		b = (pieces[1] as Array)[1]
	elif i == pieces.size() - 1:
		a = (pieces[i - 1] as Array)[1]
		b = (pieces[i] as Array)[1]
	else:
		a = (pieces[i - 1] as Array)[1]
		b = (pieces[i + 1] as Array)[1]
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	return d.normalized() if d.length() > 0.5 else Vector3.ZERO


## How far a ray gets before earth stops it, and whether it was stopped at all.
func _clear(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3) -> Array:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * RAY))
	if hit.is_empty():
		return [RAY, false]
	return [from.distance_to(hit["position"] as Vector3), true]
