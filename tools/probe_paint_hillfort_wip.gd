extends SceneTree

# ─────────────────────────────────────────────
# PAINT HILLFORT WIP — the sketch for maps/hillfort_wip_level.tscn. A new file;
# it reads nothing and overwrites nothing but its own output. In particular it
# does NOT touch Env/terrain/sketches/hillfort.png, which the shipped level is
# built on.
#
#   godot --headless --path . --script res://tools/probe_paint_hillfort_wip.gd
#
# WHAT THE SKETCH IS FOR, AND WHAT IT IS NOT. Same division of labour as
# probe_paint_hillfort.gd, and it matters more here because the map is a
# quarter of the size: a white mask is BINARY and gets blurred by
# sketch_blend, so painted height cannot be a number you build against, and it
# is laid down before erosion and before the floor shift. So white does the two
# jobs it is good at —
#   1. the ROCK ZONE: zone[] comes straight off this mask, so the material on
#      the upper hill and the fort's plateau is stone and not the valley grass,
#      which is most of what tells you how far up you are;
#   2. a few metres of crag on the ground nobody fights on.
# Every surface the squad stands on is a TerrainStamp or a TerrainPath in
# tools/probe_build_hillfort_wip.gd, which run LAST, at authored heights.
#
# SMALLER MAP, SMALLER WOBBLE. The original roughens its edges by 42 m on a
# 896 x 1024 map. The same 42 m here is a third of the distance from the
# trailhead to the fort, so the rock zone's edge would swing across two whole
# stations. 14 m at a higher frequency gives the same "no clean arcs" read at
# a quarter of the scale.
#
# Yellow is the broken rock of the mid slopes. Green is the approach ground in
# the south, so it stays smooth under the spawn. No blue: water_level is ONE
# global height, so a tarn on the plateau would flood the trailhead to match.
# ─────────────────────────────────────────────

const DST := "D:/Godot Games/roboto/Env/terrain/sketches/hillfort_wip.png"

## Must match the recipe in probe_build_hillfort_wip.gd.
const SIZE_X := 384.0
const SIZE_Z := 256.0
const MPP := 4.0

## Where the fort stands. Everything here is laid out about it, because that is
## what the whole map is laid out about.
const SUMMIT := Vector2(0.0, -66.0)

const WHITE := Color(1, 1, 1)
const YELLOW := Color(1, 1, 0)
const GREEN := Color(0, 1, 0)
const BLACK := Color(0, 0, 0)

var wob := FastNoiseLite.new()


func _initialize() -> void:
	wob.seed = 2311
	wob.frequency = 0.008
	var w := int(SIZE_X / MPP)
	var h := int(SIZE_Z / MPP)
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(BLACK)
	var counts := {"white": 0, "yellow": 0, "green": 0}
	for r in h:
		var z := -SIZE_Z * 0.5 + r * MPP + MPP * 0.5
		for c in w:
			var x := -SIZE_X * 0.5 + c * MPP + MPP * 0.5
			var n := wob.get_noise_2d(x, z) * 14.0
			if _rock(x, z, n):
				im.set_pixel(c, r, WHITE)
				counts.white += 1
			elif _rough(x, z, n):
				im.set_pixel(c, r, YELLOW)
				counts.yellow += 1
			elif z > 54.0 + n:
				im.set_pixel(c, r, GREEN)
				counts.green += 1
	print("   %d x %d px at %.0f m/px — white %d, yellow %d, green %d" % [
			w, h, MPP, counts.white, counts.yellow, counts.green])
	var err := im.save_png(DST)
	print("   %s %s" % ["wrote" if err == OK else "FAILED to write", DST])
	quit(0 if err == OK else 1)


## The high ground: the plateau and the upper third of the hill. It stops short
## of the flanking stations on purpose — the progression grass → brown upland →
## grey rock is the only thing on a map this small that reads as altitude, and
## it only reads if the three bands are actually in different places.
func _rock(x: float, z: float, n: float) -> bool:
	if _disc(x, z, SUMMIT.x, SUMMIT.y - 14.0, 96.0 + n):
		return true
	# Two spurs, so the rock does not end on a circle.
	if _disc(x, z, -112.0, -112.0, 46.0 + n):
		return true
	if _disc(x, z, 118.0, -116.0, 44.0 + n):
		return true
	return false


## The mid slopes, so the stone does not stop at a line.
func _rough(x: float, z: float, n: float) -> bool:
	if _ellipse(x, z, SUMMIT.x, SUMMIT.y + 10.0, 168.0 + n, 150.0 + n):
		return true
	return false


func _disc(x: float, z: float, cx: float, cz: float, r: float) -> bool:
	return Vector2(x - cx, z - cz).length() < r


func _ellipse(x: float, z: float, cx: float, cz: float, rx: float, rz: float) -> bool:
	return Vector2((x - cx) / maxf(rx, 1.0), (z - cz) / maxf(rz, 1.0)).length() < 1.0
