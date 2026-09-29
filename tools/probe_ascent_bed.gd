extends SceneTree

# ─────────────────────────────────────────────
# ASCENT BED — walk the centreline of every flight and say whether the ground
# is actually at the height the road asked for, and how wide the flat is.
#
#   godot --headless --path . --script res://tools/probe_ascent_bed.gd
#
# WHY. probe_nav_ascent.gd says a flight is cut off; it cannot say why. A bed
# that is not where it was authored is a cut that lost a fight with something
# applied after it, and a bed that is there but two metres wide is a bed the
# navmesh will not carry. This tells the two apart.
# ─────────────────────────────────────────────

const DATA := "res://maps/terrain_data/ascent_level_terrain.res"

## Mirrors STATIONS in probe_build_ascent.gd: name, x, z, y, pad x, pad z,
## falloff. The run-out at each end of a leg is DERIVED from these, the same way
## the generator derives it — a hard-coded run-out here went stale the moment
## the pads changed and started reporting breaks that were not there.
const STATIONS: Array = [
	["Trailhead", 0.0, 430.0, 0.0, 100.0, 70.0, 18.0],
	["Cistern", -170.0, 258.0, 10.0, 56.0, 40.0, 16.0],
	["Pillars", 150.0, 140.0, 34.0, 56.0, 40.0, 16.0],
	["Gate", -140.0, 34.0, 46.0, 56.0, 40.0, 16.0],
	["Terrace", 140.0, -46.0, 76.0, 56.0, 40.0, 16.0],
	["Shoulder", -205.0, -46.0, 62.0, 56.0, 40.0, 16.0],
	["Summit", 30.0, -270.0, 132.0, 150.0, 120.0, 14.0],
]
const RUNOUT := 24.0

## Eye height, for the sightline check.
const EYE := 1.7
## What "see the fort" means. A flat plateau on a convex hill is ALWAYS hidden
## from below — the hill's own shoulder cuts the line to the ground up there,
## and that is true of every real hilltop. What has to be visible is what stands
## ON it, so the sightline is drawn to the top of a watchtower, not to the dirt.
## Aimed at the NEAREST MAST, on the plateau’s south lip, not at the middle of
## at 25.3 m. It sits at the BACK of the plateau, which makes this the hard
## version of the question: a thing at the back of a flat top is hidden by the
## front of it, so if the dish clears the brow everything else does too.
const TOP := Vector3(-4.0, -286.0, 132.0)
## The tallest thing standing on the summit — the relay masts, not a watchtower.
const TOWER := 25.3
## The summit plateau's centre and its authored height.
const SUMMIT := Vector2(30.0, -270.0)
const PLATEAU := 132.0

## Mirrors SUMMIT_PIECES in probe_build_ascent.gd: name, x, z (from the summit),
## then the footprint to sample the corners of.
const RELAY: Array = [
	["compute_data_hall", 12.0, -6.0, 29.0, 19.0],
	["landmark_relay_dish", -34.0, -16.0, 30.0, 28.0],
	["compute_satellite_dish", -28.0, -27.0, 4.0, 3.3],
	["compute_satellite_dish", 20.0, -27.0, 4.0, 3.3],
	["compute_generator", 28.0, 12.0, 12.3, 4.6],
	["compute_transformer", 14.0, 14.0, 3.6, 4.4],
	["compute_cable_run", -6.0, -8.0, 3.3, 12.6],
	["compute_network_cabinet", 4.0, 10.0, 1.4, 2.1],
	["feature_watchtower", -34.0, 18.0, 4.9, 14.9],
	["feature_watchtower", -4.0, 30.0, 14.9, 4.9],
	["fort_hesco_sangar", -22.0, 20.0, 10.3, 5.0],
	["fort_sentry_turret", -24.0, 6.0, 1.6, 3.8],
	["fort_floodlight_mast", -36.0, -8.0, 3.2, 4.5],
	["feature_power_pylon", 56.0, -30.0, 9.6, 7.4],
	["feature_power_pylon", -40.0, 44.0, 9.6, 7.4],
	["feature_power_pylon", 24.0, 46.0, 9.6, 7.4],
]

## Ground this far off the authored height is not the bed.
const TOL := 1.5
## A walkable ribbon has to be at least this wide after the baker erodes it.
const WANT_WIDE := 6.0
## Legs bent through via points, whose bed is not a straight line between ends.
const BENT: Array = ["Trailhead to Cistern", "Cistern to Pillars", "Pillars to Gate",
		"Shoulder to Summit"]


## Same rule as the generator: level ground at each end, long enough to cross
## that station's own pad.
func _runout(station: Array, dir: Vector2) -> float:
	var half := Vector2(float(station[4]), float(station[5])) * 0.5
	var reach: float = minf(half.x / maxf(absf(dir.x), 0.0001),
			half.y / maxf(absf(dir.y), 0.0001))
	return maxf(RUNOUT, reach + float(station[6]))


func _initialize() -> void:
	var data: Resource = load(DATA)
	if data == null:
		print("FAIL  could not load %s" % DATA)
		quit(1)
		return
	print("   %-20s %6s %8s %8s %8s %8s" % [
			"flight", "steps", "on bed", "worst", "flat w", "narrowest"])
	for li in range(STATIONS.size() - 1):
		var sa: Array = STATIONS[li]
		var sb: Array = STATIONS[li + 1]
		var f: Array = ["%s to %s" % [sa[0], sb[0]],
				Vector3(float(sa[1]), float(sa[2]), float(sa[3])),
				Vector3(float(sb[1]), float(sb[2]), float(sb[3])), sa, sb]
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		# Four of the six legs are bent through via points (see _vias in
		# probe_build_ascent.gd), so a straight line between their ends is not
		# where the bed is and walking it reports a break that is not there.
		if str(f[0]) in BENT:
			print("   %-20s bent through vias — bed not walked" % f[0])
			continue
		var steps := int((Vector2(b.x - a.x, b.y - a.y)).length() / 4.0)
		var on := 0
		var worst := 0.0
		var worst_at := Vector2.ZERO
		var narrowest := 999.0
		var narrow_at := Vector2.ZERO
		var wide_sum := 0.0
		# The bed's normal in plan, to measure across it.
		var dir := Vector2(b.x - a.x, b.y - a.y).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var total := Vector2(b.x - a.x, b.y - a.y).length()
		var ldir := Vector2(b.x - a.x, b.y - a.y).normalized()
		var r0: float = minf(_runout(f[3], ldir), total * 0.45)
		var r1: float = minf(_runout(f[4], ldir), total * 0.45)
		var graded: float = maxf(total - r0 - r1, 0.001)
		# Skip the first and last sample. They sit exactly on a landing, where
		# the pad and two flights all meet, and measuring "how far either side
		# is the bed still flat" there reports the pad's edge, not the bed's.
		for i in range(1, steps):
			var t := float(i) / maxf(steps, 1)
			var p := Vector2(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t))
			var want := lerpf(a.z, b.z, clampf((t * total - r0) / graded, 0.0, 1.0))
			var got: float = data.height_at_local(p.x, p.y)
			var err := absf(got - want)
			if err <= TOL:
				on += 1
			if err > worst:
				worst = err
				worst_at = p
			# How far either side the ground stays within tolerance of the bed.
			var wide := 0.0
			for side: float in [-1.0, 1.0]:
				var d := 0.0
				while d < 20.0:
					d += 0.5
					var q := p + nrm * d * side
					if absf(float(data.height_at_local(q.x, q.y)) - want) > TOL:
						break
				wide += d
			wide_sum += wide
			if wide < narrowest:
				narrowest = wide
				narrow_at = p
		var n := maxf(steps - 1, 1)
		print("   %-20s %6d %7.0f%% %7.1fm %7.1fm %7.1fm" % [
				f[0], steps - 1, 100.0 * on / n, worst,
				wide_sum / n, narrowest])
		if worst > TOL:
			print("       worst at (%.0f, %.0f)" % [worst_at.x, worst_at.y])
		if narrowest < WANT_WIDE:
			print("       narrowest at (%.0f, %.0f) — under %.0f m, the baker will drop it" % [
					narrow_at.x, narrow_at.y, WANT_WIDE])
	_sightlines(data)
	_summit_section(data)
	_relay_feet(data)
	_station_cuts(data)
	quit()


## Can you see the fort from each station? A hilltop objective the squad only
## sees once it is on top of it is not a hilltop objective, and the thing that
## breaks it is never the summit — it is an ordinary hill on the approach that
## happens to stand higher than the plateau.
func _sightlines(data: Resource) -> void:
	print("")
	print("   line of sight to the summit, from an eye %.1f m above each station" % EYE)
	print("   %-12s %9s %9s %9s" % ["from", "range", "clear by", "lowest at"])
	for li in range(STATIONS.size() - 1):
		var sa: Array = STATIONS[li]
		var sb: Array = STATIONS[li + 1]
		var f: Array = ["%s to %s" % [sa[0], sb[0]],
				Vector3(float(sa[1]), float(sa[2]), float(sa[3])),
				Vector3(float(sb[1]), float(sb[2]), float(sb[3])), sa, sb]
		var a: Vector3 = f[1]
		var from := Vector3(a.x, a.z + EYE, a.y)
		var to := Vector3(TOP.x, TOP.z + TOWER, TOP.y)
		var span := Vector2(to.x - from.x, to.z - from.z).length()
		if span < 1.0:
			continue
		var worst := INF
		var worst_at := Vector2.ZERO
		var steps := int(span / 4.0)
		for i in range(1, steps):
			var t := float(i) / steps
			var p := Vector2(lerpf(from.x, to.x, t), lerpf(from.z, to.z, t))
			# Clearance: how far the sightline passes ABOVE the ground here.
			var clear: float = lerpf(from.y, to.y, t) - float(data.height_at_local(p.x, p.y))
			if clear < worst:
				worst = clear
				worst_at = p
		print("   %-12s %8.0fm %8.1fm %s" % [str(f[0]).split("→")[0], span, worst,
				"(%.0f, %.0f)%s" % [worst_at.x, worst_at.y,
						"  BLOCKED" if worst < 0.0 else ""]])


## A cross-section through each landing along the flight's own direction. A
## landing is where two flights hand over; if the ground there is not the pad's
## height the handover is a step, and a step is a wall.
## Cross-sections through the summit, out past the plateau on all four
## bearings. THE ONE QUESTION THIS ANSWERS: is the fort on a top or in a bowl.
## Anything out there higher than the plateau is a rim, and a rim is what makes
## a hilltop read as a crater however gently it rises.
func _summit_section(data: Resource) -> void:
	var pad := Vector2(75.0, 60.0)
	print("")
	print("   cross-sections through the summit at (%.0f, %.0f), plateau %.0f m" % [
			SUMMIT.x, SUMMIT.y, PLATEAU])
	print("   %-8s %s" % ["out", "  0   20   40   60   80  100  120  140  160  200  240 m"])
	for dir: Array in [["east", Vector2(1, 0)], ["west", Vector2(-1, 0)],
			["south", Vector2(0, 1)], ["north", Vector2(0, -1)]]:
		var d: Vector2 = dir[1]
		var row: PackedStringArray = []
		var rim := -INF
		var rim_at := 0.0
		for out: float in [0.0, 20.0, 40.0, 60.0, 80.0, 100.0, 120.0, 140.0, 160.0, 200.0, 240.0]:
			var p := SUMMIT + d * out
			var h: float = data.height_at_local(p.x, p.y)
			row.append("%5.0f" % h)
			# Only count ground OUTSIDE the plateau: the pad itself is level and
			# is not a rim however it reads.
			if out > maxf(pad.x * absf(d.x), pad.y * absf(d.y)) and h > rim:
				rim = h
				rim_at = out
		var note := ""
		if rim > PLATEAU + 1.0:
			note = "   RIM +%.0f m at %.0f m out" % [rim - PLATEAU, rim_at]
		print("   %-8s %s%s" % [dir[0], "".join(row), note])


## The ground under every summit piece, against the height it was placed at.
## A piece standing on a number the ground does not agree with is either buried
## or on stilts, and on a flat plateau the second one is very visible.
func _relay_feet(data: Resource) -> void:
	print("")
	print("   ground under the relay, against the plateau at %.0f m" % PLATEAU)
	var worst := 0.0
	for p: Array in RELAY:
		var at := SUMMIT + Vector2(float(p[1]), float(p[2]))
		var lo := INF
		var hi := -INF
		# Four corners of the piece's footprint, not just its origin: a long
		# piece can sit level on its middle and hang off one end.
		for dx: float in [-1.0, 1.0]:
			for dz: float in [-1.0, 1.0]:
				var q := at + Vector2(float(p[3]) * 0.5 * dx, float(p[4]) * 0.5 * dz)
				var h: float = data.height_at_local(q.x, q.y)
				lo = minf(lo, h)
				hi = maxf(hi, h)
		var drop := PLATEAU - lo
		worst = maxf(worst, absf(drop))
		var note := ""
		if drop > 0.3:
			note = "   ON STILTS — ground %.2f m below its feet" % drop
		elif drop < -0.3:
			note = "   BURIED %.2f m" % -drop
		print("   %-32s %7.2f .. %7.2f m%s" % [p[0], lo, hi, note])
	print("   worst %.2f m" % worst)


## How each station's pad meets the ground around it.
##
## THE FAILURE THIS FINDS. A FLATTEN pad cut deep into a hill is ringed by a
## bank as steep as the cut is deep, and a bank over the navmesh's 45° turns
## the pad into an ISLAND — navmesh on it, navmesh off it, no route between.
## When it happened here every one of the seven stations came back cut off at
## once, which looks like a broken bake and is really a terracing problem.
func _station_cuts(data: Resource) -> void:
	print("")
	print("   how each pad meets the ground, and the bank that makes")
	print("   %-12s %8s %9s %9s" % ["station", "pad", "outside", "bank"])
	for s: Array in STATIONS:
		var at := Vector2(float(s[1]), float(s[2]))
		var half := Vector2(float(s[4]), float(s[5])) * 0.5
		var fall := float(s[6])
		var worst := 0.0
		var worst_dir := ""
		# The EASIEST way on also matters, and matters more. A pad with a drop
		# off one edge is a hilltop; a pad with a bank over 45° on every edge is
		# an island, whatever the navmesh shows sitting on it. An earlier
		# version of this reported the worst side only and called the summit
		# itself broken for having a hillside beneath it.
		var best := 90.0
		var best_dir := ""
		for dir: Array in [["E", Vector2(1, 0)], ["W", Vector2(-1, 0)],
				["S", Vector2(0, 1)], ["N", Vector2(0, -1)]]:
			var d: Vector2 = dir[1]
			var edge: float = half.x * absf(d.x) + half.y * absf(d.y)
			var outside: float = data.height_at_local(
					at.x + d.x * (edge + fall), at.y + d.y * (edge + fall))
			var bank := rad_to_deg(atan2(absf(outside - float(s[3])), fall))
			if bank > worst:
				worst = bank
				worst_dir = "%s %+.0f m" % [dir[0], outside - float(s[3])]
			if bank < best:
				best = bank
				best_dir = dir[0]
		var note := "   walk on from the %s at %.0f°" % [best_dir, best]
		if best > 45.0:
			note = "   ISLAND — every side over agent_max_slope"
		elif worst > 50.0:
			note += ", %s side is a %.0f° drop" % [worst_dir, worst]
		print("   %-12s %7.0fm %8s %8.0f°%s" % [s[0], float(s[3]), worst_dir, worst, note])
