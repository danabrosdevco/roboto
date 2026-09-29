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

## name, from (x, z, y), to (x, z, y), bed width. Vector3 is (x, z, y) here,
## not (x, y, z) — the two horizontals travel together everywhere in this file.
const FLIGHTS: Array = [
	["Trailhead→Cistern", Vector3(0.0, 380.0, 0.0), Vector3(-170.0, 258.0, 18.0), 14.0],
	["Cistern→Pillars", Vector3(-170.0, 258.0, 18.0), Vector3(150.0, 140.0, 38.0), 14.0],
	["Pillars→Gate", Vector3(150.0, 140.0, 38.0), Vector3(-140.0, 34.0, 58.0), 13.0],
	["Gate→Terrace", Vector3(-140.0, 34.0, 58.0), Vector3(140.0, -46.0, 82.0), 13.0],
	["Terrace→Shoulder", Vector3(140.0, -46.0, 82.0), Vector3(-90.0, -140.0, 102.0), 12.0],
	["Shoulder→Summit", Vector3(-90.0, -140.0, 102.0), Vector3(30.0, -270.0, 132.0), 11.0],
]

## Eye height, for the sightline check.
const EYE := 1.7
## What "see the fort" means. A flat plateau on a convex hill is ALWAYS hidden
## from below — the hill's own shoulder cuts the line to the ground up there,
## and that is true of every real hilltop. What has to be visible is what stands
## ON it, so the sightline is drawn to the top of a watchtower, not to the dirt.
## Aimed at the NEAREST MAST, on the plateau’s south lip, not at the middle of
## the summit. A mast at the back of a flat top is hidden by the front of it.
const TOP := Vector3(54.0, -224.0, 132.0)
## The tallest thing standing on the summit — the relay masts, not a watchtower.
const TOWER := 21.8
## The summit plateau's centre and its authored height.
const SUMMIT := Vector2(30.0, -270.0)
const PLATEAU := 132.0

## Ground this far off the authored height is not the bed.
const TOL := 1.5
## A walkable ribbon has to be at least this wide after the baker erodes it.
const WANT_WIDE := 6.0
## Must match RUNOUT in probe_build_ascent.gd: the level ground at each end.
const RUNOUT := 24.0
## Legs bent through via points, whose bed is not a straight line.
const BENT: Array = ["Trailhead→Cistern", "Cistern→Pillars", "Pillars→Gate",
		"Shoulder→Summit"]


func _initialize() -> void:
	var data: Resource = load(DATA)
	if data == null:
		print("FAIL  could not load %s" % DATA)
		quit(1)
		return
	print("   %-20s %6s %8s %8s %8s %8s" % [
			"flight", "steps", "on bed", "worst", "flat w", "narrowest"])
	for f: Array in FLIGHTS:
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
		var run: float = minf(RUNOUT, total * 0.3)
		var graded: float = maxf(total - run * 2.0, 0.001)
		# Skip the first and last sample. They sit exactly on a landing, where
		# the pad and two flights all meet, and measuring "how far either side
		# is the bed still flat" there reports the pad's edge, not the bed's.
		for i in range(1, steps):
			var t := float(i) / maxf(steps, 1)
			var p := Vector2(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t))
			var want := lerpf(a.z, b.z, clampf((t * total - run) / graded, 0.0, 1.0))
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
	quit()


## Can you see the fort from each station? A hilltop objective the squad only
## sees once it is on top of it is not a hilltop objective, and the thing that
## breaks it is never the summit — it is an ordinary hill on the approach that
## happens to stand higher than the plateau.
func _sightlines(data: Resource) -> void:
	print("")
	print("   line of sight to the summit, from an eye %.1f m above each station" % EYE)
	print("   %-12s %9s %9s %9s" % ["from", "range", "clear by", "lowest at"])
	for f: Array in FLIGHTS:
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
