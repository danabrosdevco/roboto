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
const SIZE_X := 640.0
const SIZE_Z := 640.0
## Must match SOUTH_SHIFT in probe_build_hillfort_wip.gd. The sketch is sampled
## in WORLD coordinates but written into a rectangle centred on the Terrain
## node, so without this every mask would land 64 m north of the ground it was
## painted for — the lanes masked onto the wrong strip, silently.
const SOUTH_SHIFT := 64.0
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
		var z := SOUTH_SHIFT - SIZE_Z * 0.5 + r * MPP + MPP * 0.5
		for c in w:
			var x := -SIZE_X * 0.5 + c * MPP + MPP * 0.5
			var n := wob.get_noise_2d(x, z) * 14.0
			if _rock(x, z, n):
				im.set_pixel(c, r, WHITE)
				counts.white += 1
			elif _rough(x, z, n):
				im.set_pixel(c, r, YELLOW)
				counts.yellow += 1
			else:
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
## THE WHITE MASK IS NOW A SCATTER MASK, not a mountain.
##
## `zone` comes straight off this channel and it is the ONLY per-place lever
## the scatter system has: a TerrainScatterLayer can be filtered by slope,
## height, paint, water and zone, and by nothing else. There is no way to say
## "more dead wood on the west lane" — so this says it, by painting the lanes
## that should be bare and leaving the one that should not.
##
##   WHITE  → zone 1 → the CENTRE lane, the EAST lane and the fort. Swept
##            ground and held ground: the hfw_deadwood and hfw_snags layers
##            are capped at max_mountain 0.25 and do not go here, so neither
##            lane grows a copse that could be fought from.
##   GREEN  → zone 0 → the WEST lane. The screened route, and the one that
##            carries the dead trees, the fallen wood and the brush.
##
## sketch_mountain_height IS ZERO in the recipe, so none of this adds height.
## It used to add 2.5 m of crag, which was texture on a hill that no longer
## exists and would now be bumps on ground the whole redesign flattened.
## White here paints material and gates scatter; it does not shape anything.
func _rock(x: float, _z: float, n: float) -> bool:
	return x > -68.0 + n


## The fade between the two, so the vegetation thins rather than stopping on a
## line. Yellow is broken ground; it reads as the lane's edge.
func _rough(x: float, _z: float, n: float) -> bool:
	return x > -92.0 + n


func _disc(x: float, z: float, cx: float, cz: float, r: float) -> bool:
	return Vector2(x - cx, z - cz).length() < r


func _ellipse(x: float, z: float, cx: float, cz: float, rx: float, rz: float) -> bool:
	return Vector2((x - cx) / maxf(rx, 1.0), (z - cz) / maxf(rz, 1.0)).length() < 1.0
