extends SceneTree

# ─────────────────────────────────────────────
# PAINT HILLFORT — the sketch for maps/hillfort_level.tscn. A new file; it reads
# nothing and overwrites nothing but its own output.
#
#   godot --headless --path . --script res://tools/probe_paint_hillfort.gd
#
# WHAT THE SKETCH IS FOR HERE, AND WHAT IT IS NOT. On a climb the sketch
# CANNOT carry the height: a white mask is binary, blurred by sketch_blend, so
# a broad painted massif saturates in the middle and comes out a MESA at
# sketch_mountain_height, not a peak. Worse, painted height is laid down before
# erosion and before the floor shift, so nothing about it is a number you can
# build against.
#
# So white does two other jobs, both of which it is good at:
#   1. the ROCK ZONE — zone[] comes straight off this mask, so the material
#      under the whole massif is stone instead of the valley's grass;
#   2. thirty metres of crags and relief for free, on ground nothing walks.
# The massif's real 250 m and every flat the squad stands on are TerrainStamps
# and TerrainPaths in the level, which run last, after the floor shift, at
# heights that are authored numbers. See tools/probe_build_hillfort.gd.
#
# Yellow is the broken rock at the foot of the face and along the flanks.
# Green is the trailhead plain, so the low ground stays smooth under the spawn.
# No blue: water_level is one global height, and a tarn on a shelf 150 m up
# would flood the valley to match.
# ─────────────────────────────────────────────

const DST := "D:/Godot Games/roboto/Env/terrain/sketches/hillfort.png"

## Must match the recipe in probe_build_hillfort.gd.
const SIZE_X := 896.0
const SIZE_Z := 1024.0
const MPP := 4.0

const WHITE := Color(1, 1, 1)
const YELLOW := Color(1, 1, 0)
const GREEN := Color(0, 1, 0)
const BLACK := Color(0, 0, 0)

## Wobble, so no edge on the map is a clean arc. sketch_edge_noise roughens the
## mask further; this roughens the paint itself, at a coarser scale.
var wob := FastNoiseLite.new()


func _initialize() -> void:
	wob.seed = 1471
	wob.frequency = 0.0035
	var w := int(SIZE_X / MPP)
	var h := int(SIZE_Z / MPP)
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(BLACK)
	var counts := {"white": 0, "yellow": 0, "green": 0}
	for r in h:
		var z := -SIZE_Z * 0.5 + r * MPP + MPP * 0.5
		for c in w:
			var x := -SIZE_X * 0.5 + c * MPP + MPP * 0.5
			var n := wob.get_noise_2d(x, z) * 42.0
			if _massif(x, z, n):
				im.set_pixel(c, r, WHITE)
				counts.white += 1
			elif _rough(x, z, n):
				im.set_pixel(c, r, YELLOW)
				counts.yellow += 1
			elif z > 176.0 + n:
				im.set_pixel(c, r, GREEN)
				counts.green += 1
	print("   %d x %d px at %.0f m/px — white %d, yellow %d, green %d" % [
			w, h, MPP, counts.white, counts.yellow, counts.green])
	var err := im.save_png(DST)
	print("   %s %s" % ["wrote" if err == OK else "FAILED to write", DST])
	quit(0 if err == OK else 1)


## The high ground: the tor and the upland around it. White is the bare rock at
## the top of the map, and it stops well short of the hills — the progression
## from grass valley to brown upland to grey rock is most of what tells you how
## far up you are.
func _massif(x: float, z: float, n: float) -> bool:
	if _disc(x, z, 30.0, -278.0, 168.0 + n):
		return true
	if _ellipse(x, z, 24.0, -196.0, 150.0 + n, 190.0 + n):
		return true
	if _disc(x, z, -186.0, -258.0, 96.0 + n):
		return true
	if _disc(x, z, 216.0, -264.0, 92.0 + n):
		return true
	return false


## the hills so the stone does not stop at a line.
func _rough(x: float, z: float, n: float) -> bool:
	if _ellipse(x, z, 20.0, -150.0, 300.0 + n, 330.0 + n):
		return true
	if _disc(x, z, -200.0, 60.0, 130.0 + n):
		return true
	if _disc(x, z, 190.0, 118.0, 120.0 + n):
		return true
	return false



func _disc(x: float, z: float, cx: float, cz: float, r: float) -> bool:
	return Vector2(x - cx, z - cz).length() < r


func _ellipse(x: float, z: float, cx: float, cz: float, rx: float, rz: float) -> bool:
	return Vector2((x - cx) / maxf(rx, 1.0), (z - cz) / maxf(rz, 1.0)).length() < 1.0
