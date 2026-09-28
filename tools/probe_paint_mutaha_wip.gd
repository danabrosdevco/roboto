extends SceneTree
# Scratch: paint mutaha_wip.png from mutaha.png. A COPY — the original sketch is
# never written. Two edits, and nothing else:
#
#   1. GREY over the south-west plain, so the west bank's town carries on south
#      instead of stopping level with the island's middle. Existing blue (water)
#      and magenta (road) pixels are left alone, so the west ring road stays and
#      becomes the new quarter's main street.
#   2. A MAGENTA crossing at z = 312, joining the southern approach road to the
#      west plain road where the channel is a clean 24 m wide. Without it the
#      extended town is unreachable from the spawn once the island's south
#      bridge is gone: the west bank has no other route in from the south.
#      Further north the two channels braid into a confluence 70 m across with
#      a tributary in it, and a road through that digs holes in the plain.
#
# The island's south road and its water crossing are left exactly as they are.
# The bridge NODE comes out of the level instead, which leaves the generator's
# gap in place — a road that runs up to the water on both banks and no span
# across it. That is what a bridge that has been dropped looks like.

const SRC := "D:/Godot Games/roboto/Env/terrain/sketches/mutaha.png"
const DST := "D:/Godot Games/roboto/Env/terrain/sketches/mutaha_wip.png"
const MPP := 8.0

const GREY := Color(0.502, 0.502, 0.502)
const MAGENTA := Color(1, 0, 1)

## Where the new quarter's west edge sits. South of the town the ground lifts
## towards the range, and a block levelled into a rise leaves a step nothing can
## climb, so the edge steps back as it goes south to stay on the flat.
func west_edge(z: float) -> float:
	if z < 172.0:
		return -392.0
	if z < 196.0:
		return -384.0
	return -372.0


func _initialize() -> void:
	var im := Image.load_from_file(SRC)
	if im == null:
		print("FAIL  could not read %s" % SRC)
		quit(1)
		return
	im.convert(Image.FORMAT_RGBA8)
	var painted := 0
	var skipped := 0
	for r in im.get_height():
		var zc := -512.0 + r * MPP + MPP * 0.5
		if zc < 88.0 or zc > 240.0:
			continue
		for c in im.get_width():
			var xc := -512.0 + c * MPP + MPP * 0.5
			if xc < west_edge(zc) or xc > -164.0:
				continue
			var was := im.get_pixel(c, r)
			# Blue is the river and magenta is a road: both outrank the town.
			if was.b > 0.6 and was.r < 0.4:
				skipped += 1
				continue
			im.set_pixel(c, r, GREY)
			painted += 1
	print("   grey: %d pixel(s) painted, %d left as river or road" % [painted, skipped])

	# The crossing, two pixels thick so it reads as a main road (10 m) like the
	# island's two bridges rather than the 5 m track in the north. Both ends land
	# on a road pixel that is already there, so the junctions are real junctions.
	var line: Array[Vector2i] = [Vector2i(71, 103), Vector2i(34, 103)]
	var road := 0
	for pass_i in 2:
		for i in line.size() - 1:
			road += _pencil(im, line[i] + Vector2i(0, pass_i), line[i + 1] + Vector2i(0, pass_i), MAGENTA)
	print("   road: %d pixel(s) drawn at z = 312 .. 328" % road)

	var err := im.save_png(DST)
	print("   %s %s" % ["wrote" if err == OK else "FAILED to write", DST])
	quit(0 if err == OK else 1)


## A hard one-pixel line, the way the docs tell you to draw a road by hand.
func _pencil(im: Image, a: Vector2i, b: Vector2i, col: Color) -> int:
	var d := b - a
	var n: int = maxi(absi(d.x), absi(d.y))
	var n_set := 0
	for i in n + 1:
		var t := 0.0 if n == 0 else float(i) / n
		var p := Vector2i(roundi(a.x + d.x * t), roundi(a.y + d.y * t))
		if p.x < 0 or p.y < 0 or p.x >= im.get_width() or p.y >= im.get_height():
			continue
		im.set_pixel(p.x, p.y, col)
		n_set += 1
	return n_set
