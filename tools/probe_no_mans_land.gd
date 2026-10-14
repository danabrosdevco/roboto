extends SceneTree

# ─────────────────────────────────────────────
# IS NO-MAN'S-LAND DANGEROUS? Sightline coverage from the enemy line across the
# ground you have to cross.
#
#   LEVEL=res://maps/salient_level.tscn \
#       godot --path . --script res://tools/probe_no_mans_land.gd
#
#   WHO=soldier     whose head is being looked for (default soldier, the frame
#                   the squad's riflemen and the enemy's both use)
#   STEP=10.0       grid pitch over the crossing ground, metres
#   EYE_Z=25.0      spacing of the sampled enemy front-line eyes, metres
#   Z=200.0         how much of the frontage to sweep, either side of zero
#
# NOT headless: every sample is a raycast against real collision and a dummy
# renderer has none.
#
# WHY IT EXISTS. The trenches either side of a crossing only mean something
# because of what happens between them. If you can stroll no-man's-land
# unobserved, then the parapet you climbed, the wire you cut and the sap you
# started from were all decoration, and the map would play exactly the same with
# the trenches deleted. The claim "the crossing is dangerous" is a claim about
# SIGHT, and sight is measurable.
#
# WHAT IT MEASURES. A grid over the ground between the two front lines. At every
# cell, a head at WHO's height above the collision, and the question put to
# every enemy firing position: can you see this? Out of that:
#
#   observed share   cells at least one enemy eye can see. Under half and the
#                    crossing is a stroll.
#   mean eyes        how many see an observed cell. One is a risk, six is a
#                    killing ground, and a map of ones is a map where you only
#                    ever have one thing to suppress.
#   dead ground      the largest connected patch NOTHING can see, in square
#                    metres and as a share. THE MOST USEFUL NUMBER HERE: dead
#                    ground is not a defect, it is the covered approach the
#                    attacker is supposed to find, and a crossing with no dead
#                    ground at all is a wall rather than a problem. What is
#                    wrong is dead ground so large it is simply the way across.
#
# It also prints the observed share BY BAND of distance from our own line, so
# "the last 40 m is the bad part" can be seen rather than guessed at.
# ─────────────────────────────────────────────

const LIB := preload("res://tools/probe_trench_lib.gd")

## Bands of the crossing, as a share of the way over from our line to theirs.
const BANDS := [0.0, 0.25, 0.5, 0.75, 1.0]


func _initialize() -> void:
	await process_frame
	var level_path := OS.get_environment("LEVEL")
	if level_path == "":
		print("usage: LEVEL=res://maps/salient_level.tscn godot --path . --script res://tools/probe_no_mans_land.gd")
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
	var space := level.get_world_3d().direct_space_state

	var ours: Vector3 = LIB.objective(level, "Salient_Jumpoff")
	var theirs: Vector3 = LIB.objective(level, "Salient_FrontLine")
	if is_nan(ours.x) or is_nan(theirs.x):
		print("FAIL  this level has no Salient_Jumpoff and Salient_FrontLine anchors,")
		print("      so there is no telling where the crossing ground is. Nothing")
		print("      measured — a sightline sweep over a guessed rectangle is noise.")
		quit(1)
		return
	var who := OS.get_environment("WHO") if OS.get_environment("WHO") != "" else "soldier"
	var head: float = LIB.head_of(who)
	if head <= 0.3:
		print("FAIL  no chassis called %s — nothing to measure a head height from" % who)
		quit(1)
		return
	var step := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 10.0
	var z_half := float(OS.get_environment("Z")) if OS.get_environment("Z") != "" else 200.0
	var eye_z := float(OS.get_environment("EYE_Z")) if OS.get_environment("EYE_Z") != "" else 25.0

	print("   crossing from x %.0f (ours) to x %.0f (theirs) — %.0f m, over %.0f m of frontage" % [
			ours.x, theirs.x, theirs.x - ours.x, z_half * 2.0])
	print("   looking for a %s's head at %.2f m, grid %.0f m" % [who, head, step])
	var eyes: Array = LIB.firing_positions(level, space, theirs.x, -z_half, z_half, eye_z)
	if eyes.is_empty():
		print("FAIL  no enemy firing positions — there is nobody to be dangerous")
		quit(1)
		return

	# The grid. Kept a step clear of both front lines so the samples are the
	# CROSSING and not the trenches either side of it: a cell in their own front
	# trench is seen by definition and would flatter the number.
	var x0 := ours.x + step
	var x1 := theirs.x - step
	var nx := int((x1 - x0) / step) + 1
	var nz := int((z_half * 2.0) / step) + 1
	var seen_grid: Array = []
	var total := 0
	var observed := 0
	var eye_sum := 0
	var band_on: Array[int] = []
	var band_n: Array[int] = []
	for _b in BANDS.size() - 1:
		band_on.append(0)
		band_n.append(0)
	var misses := 0
	for ix in nx:
		var col: Array[int] = []
		for iz in nz:
			var x := x0 + float(ix) * step
			var z := -z_half + float(iz) * step
			var g: float = LIB.ground(space, x, z)
			if is_nan(g):
				# EVERY SKIP SAYS WHY: a cell with no collision under it is off
				# the built map, and counting it either way would move the share.
				misses += 1
				col.append(-1)
				continue
			var n: int = LIB.seen_by(space, eyes, Vector3(x, g + head, z))
			col.append(n)
			total += 1
			var t := (x - ours.x) / (theirs.x - ours.x)
			for b in BANDS.size() - 1:
				if t >= float(BANDS[b]) and t <= float(BANDS[b + 1]):
					band_n[b] += 1
					if n > 0:
						band_on[b] += 1
					break
			if n > 0:
				observed += 1
				eye_sum += n
		seen_grid.append(col)
	if total == 0:
		print("FAIL  not one grid cell had collision under it — is this the right level?")
		quit(1)
		return
	if misses > 0:
		print("   note: %d cell(s) had no collision under them and are not counted" % misses)

	var share := 100.0 * float(observed) / float(total)
	print("")
	print("   OBSERVED  %d of %d cells — %.1f%% of the crossing ground" % [observed, total, share])
	print("   eyes on an observed cell: %.1f on average" % (float(eye_sum) / maxf(float(observed), 1.0)))
	print("")
	print("   by band, from our line to theirs:")
	for b in BANDS.size() - 1:
		if band_n[b] == 0:
			continue
		print("      %3.0f-%-3.0f%% of the way over   %5.1f%% observed" % [
				float(BANDS[b]) * 100.0, float(BANDS[b + 1]) * 100.0,
				100.0 * float(band_on[b]) / float(band_n[b])])

	var patch := _largest_dead(seen_grid, nx, nz)
	var cell_area := step * step
	print("")
	print("   DEAD GROUND: largest unobserved patch %d cell(s) = %.0f m2 (%.1f%% of the crossing)" % [
			patch, float(patch) * cell_area, 100.0 * float(patch) / float(total)])
	if patch > 0:
		print("   at this grid that is roughly %.0f m across if it were square." % sqrt(float(patch) * cell_area))

	# THE VERDICT. Two ways this fails and they are opposite, so both are said:
	# a crossing nobody can see is a stroll, and a crossing with no dead ground
	# anywhere is not a problem to solve but a wall to be killed against.
	var ok := true
	if share < 50.0:
		print("   STROLL: over half the crossing is unobserved. The trenches either")
		print("   side are decoration — the squad can walk over without being seen.")
		ok = false
	if patch >= total / 4:
		print("   AND one unobserved patch is a quarter of the whole crossing, which")
		print("   means there is a single safe way across rather than a choice of bad ones.")
		ok = false
	if share >= 95.0 and patch <= total / 100:
		print("   NO DEAD GROUND: almost every cell is observed, so there is no")
		print("   covered approach to find. That plays as a wall, not as a problem.")
		ok = false
	print("NO MAN'S LAND %s — %.1f%% observed, largest dead patch %.0f m2" % [
			"PASS" if ok else "FAIL", share, float(patch) * cell_area])
	quit(0 if ok else 1)


## The largest 4-connected run of cells nothing can see. -1 cells (no collision)
## are not dead ground, they are off the map, and they break a patch.
func _largest_dead(grid: Array, nx: int, nz: int) -> int:
	var seen := {}
	var best := 0
	for ix in nx:
		for iz in nz:
			if int((grid[ix] as Array)[iz]) != 0 or seen.has(Vector2i(ix, iz)):
				continue
			var stack: Array[Vector2i] = [Vector2i(ix, iz)]
			seen[Vector2i(ix, iz)] = true
			var n := 0
			while stack.size() > 0:
				var at: Vector2i = stack.pop_back()
				n += 1
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q := at + d
					if q.x < 0 or q.y < 0 or q.x >= nx or q.y >= nz:
						continue
					if seen.has(q) or int((grid[q.x] as Array)[q.y]) != 0:
						continue
					seen[q] = true
					stack.append(q)
			best = maxi(best, n)
	return best
