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

## name, from (x, z, y), to (x, z, y), bed width
const FLIGHTS: Array = [
	["Gate→Landing1", Vector3(-150.0, 80.0, 88.0), Vector3(150.0, 36.0, 158.0), 11.0],
	["Landing1→Landing2", Vector3(150.0, 36.0, 158.0), Vector3(-150.0, -8.0, 228.0), 11.0],
	["Landing2→Landing3", Vector3(-150.0, -8.0, 228.0), Vector3(150.0, -52.0, 298.0), 11.0],
	["Landing3→Landing4", Vector3(150.0, -52.0, 298.0), Vector3(-150.0, -96.0, 368.0), 11.0],
	["Landing4→Shoulder", Vector3(-150.0, -96.0, 368.0), Vector3(150.0, -140.0, 438.0), 11.0],
	["Shoulder→Sanctum", Vector3(150.0, -140.0, 438.0), Vector3(0.0, -360.0, 500.0), 13.0],
]

## Ground this far off the authored height is not the bed.
const TOL := 1.5
## A walkable ribbon has to be at least this wide after the baker erodes it.
const WANT_WIDE := 6.0
## Must match RUNOUT in probe_build_ascent.gd: the level ground at each end.
const RUNOUT := 24.0


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
	_landings(data)
	quit()


## A cross-section through each landing along the flight's own direction. A
## landing is where two flights hand over; if the ground there is not the pad's
## height the handover is a step, and a step is a wall.
func _landings(data: Resource) -> void:
	print("")
	print("   landings, sampled along X through the pad centre (pad height in brackets)")
	for f: Array in FLIGHTS:
		var b: Vector3 = f[2]
		var row: PackedStringArray = []
		for d in [-60.0, -40.0, -28.0, -20.0, -12.0, 0.0, 12.0, 20.0]:
			var x: float = b.x + (d if b.x < 0.0 else -d)
			row.append("%.0f" % float(data.height_at_local(x, b.y)))
		print("   %-20s (%3.0f)  %s" % [str(f[0]).split("→")[1], b.z, " ".join(row)])
	print("   offsets -60 -40 -28 -20 -12 0 +12 +20 m from the pad centre, outward first")
