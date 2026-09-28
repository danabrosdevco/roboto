extends SceneTree
# Scratch: compare two baked terrains. A sketch edit is supposed to be LOCAL —
# the generator's noise is positional and the urbaniser hashes its block keys —
# but "supposed to be" is not a check, and a copy of a level whose untouched
# ground had moved would be worse than useless.
#
#   A=res://...res B=res://...res godot --headless --path . --script res://tools/probe_terrain_diff.gd
#
# The histogram matters more than the count. Erosion is iterative, so a change
# anywhere jitters the whole field by a hair; what must stay put is anything a
# building or a body stands on, and that means differences over about 0.15 m.

## Differences under this are erosion jitter and not worth a bound.
const REAL := 0.15


func _initialize() -> void:
	var a: TerrainData = load(OS.get_environment("A"))
	var b: TerrainData = load(OS.get_environment("B"))
	if a == null or b == null or a.cells_x != b.cells_x:
		print("FAIL  could not compare")
		quit(1)
		return
	var n: int = a.cells_x + 1
	var half := a.cells_x * a.cell_size * 0.5
	var buckets := PackedInt32Array([0, 0, 0, 0, 0])
	var worst := 0.0
	var wp := Vector2.ZERO
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for j in n:
		for i in n:
			var k := j * n + i
			var d: float = absf(a.heights[k] - b.heights[k])
			if d <= 0.02:
				continue
			buckets[0 if d < 0.05 else (1 if d < REAL else (2 if d < 0.5 else (3 if d < 1.5 else 4)))] += 1
			var p := Vector2(i * a.cell_size - half, j * a.cell_size - half)
			if d > worst:
				worst = d
				wp = p
			if d >= REAL:
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var total: int = buckets[0] + buckets[1] + buckets[2] + buckets[3] + buckets[4]
	print("   %d of %d samples moved at all (%.1f%%), worst %.2f m at (%.0f, %.0f)" % [
			total, n * n, 100.0 * total / (n * n), worst, wp.x, wp.y])
	print("   under 0.05 m: %d    under %.2f: %d    under 0.5: %d    under 1.5: %d    over: %d" % [
			buckets[0], REAL, buckets[1], buckets[2], buckets[3], buckets[4]])
	var real: int = buckets[2] + buckets[3] + buckets[4]
	if real > 0:
		print("   everything over %.2f m is inside x %.0f .. %.0f, z %.0f .. %.0f (%d samples)" % [
				REAL, lo.x, hi.x, lo.y, hi.y, real])
	else:
		print("   nothing moved by more than %.2f m" % REAL)

	# Where the changes are, as 32 m tiles: . under 0.15 m  - 0.3  + 0.5  ^ 1  # more.
	var tile := int(32.0 / a.cell_size)
	print("   worst change per 32 m tile: . under 0.15 m  - 0.3  + 0.5  ^ 1  # more")
	for tz in range(0, a.cells_z / tile):
		var row := ""
		for tx in range(0, a.cells_x / tile):
			var w := 0.0
			for j in range(tz * tile, (tz + 1) * tile + 1):
				for i in range(tx * tile, (tx + 1) * tile + 1):
					var k := j * n + i
					w = maxf(w, absf(a.heights[k] - b.heights[k]))
			row += "." if w < 0.15 else ("-" if w < 0.3 else ("+" if w < 0.5 else ("^" if w < 1.0 else "#")))
		print("%6d %s" % [int(-512.0 + tz * 32.0), row])

	print("   lots %d -> %d, bridges %d -> %d" % [a.lots.size(), b.lots.size(), a.bridges.size(), b.bridges.size()])
	var old := {}
	for l in a.lots:
		old[Vector2i(roundi(l.centre.x), roundi(l.centre.y))] = l
	var added := 0
	for l in b.lots:
		var key := Vector2i(roundi(l.centre.x), roundi(l.centre.y))
		if not old.has(key):
			added += 1
			print("   NEW lot   (%5.0f, %5.0f)  h %6.2f  %s" % [l.centre.x, l.centre.y, l.height,
					"ruined" if l.ruined else ""])
		else:
			var was: float = old[key].height
			if absf(was - float(l.height)) > 0.01 or bool(old[key].ruined) != bool(l.ruined):
				print("   MOVED lot (%5.0f, %5.0f)  h %6.2f -> %6.2f" % [l.centre.x, l.centre.y, was, l.height])
			old.erase(key)
	for key: Vector2i in old:
		print("   LOST lot  (%5d, %5d)" % [key.x, key.y])
	print("   %d lot(s) added" % added)
	print("   -- bridges in B --")
	for br in b.bridges:
		var span: float = (br.start as Vector3).distance_to(br.end)
		var mid: Vector3 = ((br.start as Vector3) + (br.end as Vector3)) * 0.5
		var dir: Vector3 = (br.end as Vector3) - (br.start as Vector3)
		print("      mid (%7.1f, %6.2f, %7.1f)  span %5.1f m  width %4.1f  heading %6.1f deg" % [
				mid.x, mid.y, mid.z, span, br.width, rad_to_deg(atan2(dir.x, dir.z))])
	quit()
