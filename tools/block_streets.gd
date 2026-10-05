extends "res://tools/block_suburban.gd"

# ─────────────────────────────────────────────
# BLOCK STREETS — the road network and everything standing beside it, for the
# suburban retail map the block_suburban pieces are for:
#
#   maps/blocks/streets/street_*.map — carriageways, junctions, crossings,
#       sidewalks and an alley; the parking lot's rows, aisle caps and entry
#       throat; and the furniture: signals, cobra lights, signs, guardrail,
#       bollards, a hydrant, cabinets and a storm inlet.
#
#   godot --headless --path . --script res://tools/block_streets.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_streets.gd -- maps/blocks --force [piece names]
#
# Built on block_suburban.gd, which this extends: the same brush kit, the same
# retail textures, the same no-overwrite rule. Build prefabs with
# block_prefabs.gd.
#
# EVERYTHING RUNS ALONG X AND IS SEG LONG. A road piece nobody can butt up
# against another one is a decoration, not a kit, so every carriageway and
# sidewalk here is exactly 32 m end to end with its section centred on y = 0.
# That also puts them on the same axis as the bridges, which run along their
# prefab's Z — map X — so a road meets a bridge without anybody rotating
# anything.
#
# THE ROAD SURFACE IS AT Z = 0 AND THE KERB IS THE ONLY THING ABOVE IT. The
# slab runs from -0.3 up to 0, so it beds into terrain rather than standing on
# it; the kerb and the sidewalk behind it are 0.15. That is under the 0.45 m a
# body steps over and well under the 0.5 m the navmesh baker climbs, so a kerb
# is never a wall by accident and never a step the bake calls walkable that
# move_and_slide then refuses. Nothing in this file is between 0.2 and 0.5 m.
#
# MARKINGS ARE 1/16 M PROUD. Thin enough that nothing notices them underfoot,
# thick enough that the brush does not collapse on the 1/32 m grid.
# ─────────────────────────────────────────────

## One lane. 3.6 m is the American standard and it is also about three times a
## body, which is the number that matters when a squad is crossing one.
const LANE := 3.6
## Every road and sidewalk piece is this long, so they tile.
const SEG := 32.0
## Sidewalk width behind the kerb.
const WALK_W := 2.4
## How proud a painted line sits.
const MARK := 0.0625

const STREETS := {
	# Carriageways and junctions
	"street_road_two_lane": "_road_two_lane",
	"street_road_two_lane_inlay": "_road_two_lane_inlay",
	"street_road_four_lane": "_road_four_lane",
	"street_road_four_lane_inlay": "_road_four_lane_inlay",
	"street_road_turn_lane": "_road_turn_lane",
	"street_road_turn_lane_inlay": "_road_turn_lane_inlay",
	"street_junction_cross": "_junction_cross",
	"street_junction_t": "_junction_t",
	"street_road_bend": "_road_bend",
	"street_crosswalk": "_crosswalk",
	"street_curb_cut": "_curb_cut",
	"street_median_island": "_median_island",
	"street_speed_table": "_speed_table",
	"street_road_shoulder": "_road_shoulder",
	"street_alley": "_alley",
	# Footways
	"street_sidewalk_run": "_sidewalk_run",
	"street_sidewalk_corner": "_sidewalk_corner",
	# The car park
	"street_lot_parking_row": "_lot_parking_row",
	"street_lot_aisle_cap": "_lot_aisle_cap",
	"street_lot_accessible": "_lot_accessible",
	"street_lot_wheel_stops": "_lot_wheel_stops",
	"street_lot_entry_throat": "_lot_entry_throat",
	"street_lot_entry_throat_inlay": "_lot_entry_throat_inlay",
	"street_lot_cart_shelter": "_lot_cart_shelter",
	# Furniture
	"street_signal_mast": "_signal_mast",
	"street_light_cobra": "_light_cobra",
	"street_sign_stop": "_sign_stop",
	"street_sign_gantry": "_sign_gantry",
	"street_guardrail": "_guardrail",
	"street_bollard_row": "_bollard_row",
	"street_hydrant": "_hydrant",
	"street_utility_cabinet": "_utility_cabinet",
	"street_transformer_pad": "_transformer_pad",
	"street_storm_inlet": "_storm_inlet",
}


func _initialize() -> void:
	var base := ""
	var force := false
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
		else:
			only.append(a)
	if base == "":
		print("usage: godot --headless --path . --script res://tools/block_streets.gd -- maps/blocks [--force] [piece names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("streets")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var written := 0
	var skipped := 0
	for name: String in STREETS:
		if not only.is_empty() and not only.has(name):
			continue
		var path := dir.path_join(name + ".map")
		if FileAccess.file_exists(path) and not force:
			print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
			skipped += 1
			continue
		_brushes = []
		_ghost_from = -1
		_entities = []
		call(STREETS[name])
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		written += 1
		print("      %-30s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
		# Brushes may touch but never share volume — it z-fights, ghosts included.
		var shared := brush_overlaps()
		if not shared.is_empty():
			print("      !! %s: %d overlapping brush pair(s)" % [name, shared.size()])
	print("BLOCK STREETS DONE: %d written%s" % [written, (" (%d skipped)" % skipped) if skipped > 0 else ""])
	quit()


# ── Road parts ───────────────────────────────────────────────────────────────

## The carriageway slab: asphalt from -0.3 to 0, `half` either side of centre.
func _bed(x0: float, x1: float, half: float) -> void:
	box(Vector3(x0, -half, -0.3), Vector3(x1, half, 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})


## The carriageway slab with a strip left out of the middle for a median that
## stands there: asphalt under a median is a second solid in the same space.
func _bed_around(x0: float, x1: float, half: float, gap: float) -> void:
	for s: float in [-1.0, 1.0]:
		box(Vector3(x0, minf(s * gap, s * half), -0.3), Vector3(x1, maxf(s * gap, s * half), 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})


## fence_run, but with the rails running BETWEEN the posts, which is how the
## one in block_industrial would be if its rails did not pass through every
## post they cross. Axis-aligned runs only.
func _fence_clean(a: Vector2, b: Vector2, z0: float = -0.2, h: float = 2.2) -> void:
	var n := maxi(1, int(ceil(a.distance_to(b) / 2.5)))
	var post_w := 0.08
	var dir := (b - a).normalized()
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		post(p.x, p.y, z0, z0 + h + 0.1, post_w, METAL)
	for z: float in [z0 + 1.0, z0 + h]:
		for i in n:
			var p := a.lerp(b, float(i) / n) + dir * post_w * 0.5
			var q := a.lerp(b, float(i + 1) / n) - dir * post_w * 0.5
			beam(Vector3(p.x, p.y, z), Vector3(q.x, q.y, z), 0.05, METAL)


## Kerb and the sidewalk behind it, on the side `s` of a carriageway `half`
## wide. The kerb face is the only vertical in a street and it is 0.15 m.
func _kerb_walk(x0: float, x1: float, half: float, s: float, walk: float = WALK_W) -> void:
	var a := s * half
	var b := s * (half + 0.3)
	box(Vector3(x0, minf(a, b), -0.3), Vector3(x1, maxf(a, b), KERB_H), {"top": WALK, "side": KERB, "bottom": CONCRETE})
	var c := s * (half + 0.3)
	var d := s * (half + 0.3 + walk)
	box(Vector3(x0, minf(c, d), -0.3), Vector3(x1, maxf(c, d), KERB_H), {"top": WALK, "side": KERB, "bottom": CONCRETE})


## A solid painted line along x at y.
func _line_x(x0: float, x1: float, y: float, t: float = 0.075, gaps: Array = []) -> void:
	# `gaps` is where something else is painted across the line (a crossing, a
	# stop bar): a line drawn through it is two paint brushes in the same space.
	wall_run("y", Vector2(y - t, y + t), x0, x1, 0.0, MARK, gaps, PAINT)


## A dashed line along x at y: `on` metres of paint every `pitch`.
func _dash_x(x0: float, x1: float, y: float, on: float = 3.0, pitch: float = 9.0) -> void:
	var x := x0
	while x + on <= x1:
		_line_x(x, x + on, y)
		x += pitch


## A ladder crossing across the carriageway at x, `half` either side.
func _ladder(x: float, half: float, bars: int = 9, z: float = 0.0) -> void:
	for i in bars:
		var y := lerpf(-half + 0.6, half - 0.6, float(i) / float(bars - 1))
		box(Vector3(x - 1.4, y - 0.25, z), Vector3(x + 1.4, y + 0.25, z + MARK), PAINT)


## The stop bar short of a crossing.
func _stop_bar(x: float, y0: float, y1: float) -> void:
	box(Vector3(x - 0.3, y0, 0.0), Vector3(x + 0.3, y1, MARK), PAINT)


# ── Carriageways ─────────────────────────────────────────────────────────────

## A RESIDENTIAL STREET: two lanes, kerbs and sidewalks both sides, 32 m long
## and 12 m kerb to kerb with the footways. The default piece — lay these end
## to end and put the junctions in where they meet.
func _road_two_lane() -> void:
	var half := LANE
	_bed(-SEG * 0.5, SEG * 0.5, half)
	for s: float in [-1.0, 1.0]:
		_kerb_walk(-SEG * 0.5, SEG * 0.5, half, s)
		_line_x(-SEG * 0.5, SEG * 0.5, s * (half - 0.35))
	_dash_x(-SEG * 0.5, SEG * 0.5, 0.0)


## THE SAME ROAD WITH NO BED, for laying into ground that is already hard —
## the ring road round a car park is asphalt on asphalt. Its kerbs and
## footways still sink into whatever is there, which is invisible, but it
## brings no second road surface at the same height as the one underneath.
##
## Two horizontal faces at one height is the fault that makes a surface crawl,
## and on Polaris the ring road laid over the car park was a hundred and
## thirty columns of it.
func _road_two_lane_inlay() -> void:
	var half := LANE
	for s: float in [-1.0, 1.0]:
		_kerb_walk(-SEG * 0.5, SEG * 0.5, half, s)
		_line_x(-SEG * 0.5, SEG * 0.5, s * (half - 0.35))
	_dash_x(-SEG * 0.5, SEG * 0.5, 0.0)


## AN ARTERIAL: four lanes with a raised planted median, which is the road the
## mall's ring road meets. The median is a 0.15 kerb like everything else, so
## a squad crosses it without a thought — it is a sightline break and a bit of
## cover from vehicles, not a wall.
func _road_four_lane() -> void:
	var half := LANE * 2.0 + 1.5
	_bed_around(-SEG * 0.5, SEG * 0.5, half, 1.5)
	box(Vector3(-SEG * 0.5, -1.5, -0.3), Vector3(SEG * 0.5, 1.5, KERB_H), ISLAND)
	for s: float in [-1.0, 1.0]:
		_kerb_walk(-SEG * 0.5, SEG * 0.5, half, s)
		_line_x(-SEG * 0.5, SEG * 0.5, s * (half - 0.35))
		_dash_x(-SEG * 0.5, SEG * 0.5, s * (1.5 + LANE))
	# Shrubs down the median, mesh only: a 0.9 m bush with collision is a
	# chain of obstacles the baker cuts the median into, and the median is
	# meant to be crossable.
	no_collision()
	var x := -SEG * 0.5 + 3.0
	while x < SEG * 0.5 - 2.0:
		# A heap's lowest ring is 0.3 below its centre and snaps to a 1/8 m grid,
		# so on a 0.15 kerb the ring lands at 0.25: 0.1 clear of the median, not
		# 0.025 into it. Same crown height as before.
		heap(Vector3(x, 0.0, 0.55), 0.9, 0.9, 0.45, int(x) + 7, SPOIL)
		x += 6.0


## THE FIVE-LANE: two each way and a continuous centre turn lane, which is the
## road every one of these malls is actually on. The hatched centre is the
## widest piece of open ground on a street map and worth knowing about before
## a squad is ordered across one.
func _road_turn_lane() -> void:
	var half := LANE * 2.5
	_bed(-SEG * 0.5, SEG * 0.5, half)
	for s: float in [-1.0, 1.0]:
		_kerb_walk(-SEG * 0.5, SEG * 0.5, half, s)
		_line_x(-SEG * 0.5, SEG * 0.5, s * (half - 0.35))
		_dash_x(-SEG * 0.5, SEG * 0.5, s * LANE)
		_line_x(-SEG * 0.5, SEG * 0.5, s * LANE * 0.5)
	# The chevrons inside the turn lane.
	var x := -SEG * 0.5 + 2.0
	while x < SEG * 0.5 - 2.0:
		# Once: this sat in a loop over both sides and drew the same chevron
		# twice, on itself.
		box(Vector3(x, -0.1, 0.0), Vector3(x + 2.4, 0.1, MARK), PAINT)
		x += 5.0


## A SIGNALISED CROSSROADS, 24 m square: both carriageways, crossings on all
## four arms, stop bars, and the corner radii kerbed. The piece that joins two
## runs of _road_two_lane at right angles.
func _junction_cross() -> void:
	var half := LANE
	var reach := 12.0
	_bed(-reach, reach, half)
	# The cross arm in two, either side of the carriageway bed it crosses.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-half, minf(s * half, s * reach), -0.3), Vector3(half, maxf(s * half, s * reach), 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	# The four corner islands, with their kerb radius faked as a 45° cut —
	# a true radius costs a dozen brushes a corner and reads the same.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			solid([Vector3(sx * half, sy * half, -0.3), Vector3(sx * reach, sy * half, -0.3),
					Vector3(sx * reach, sy * reach, -0.3), Vector3(sx * half, sy * reach, -0.3),
					Vector3(sx * (half + 2.2), sy * half, KERB_H), Vector3(sx * reach, sy * half, KERB_H),
					Vector3(sx * reach, sy * reach, KERB_H), Vector3(sx * half, sy * (half + 2.2), KERB_H)],
					{"top": WALK, "side": KERB, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		_ladder(s * (half + 2.6), half, 7)
		_stop_bar(s * (half + 5.4), minf(0.0, s * half), maxf(0.0, s * half))
		# The crossings on the other two arms, drawn across y instead.
		for i in 7:
			var x := lerpf(-half + 0.6, half - 0.6, float(i) / 6.0)
			box(Vector3(x - 0.25, s * (half + 1.2), 0.0), Vector3(x + 0.25, s * (half + 4.0), MARK), PAINT)


## A T JUNCTION: the side street meeting the through road, which is how every
## outlot and every lot entrance actually connects.
func _junction_t() -> void:
	var half := LANE
	var reach := 12.0
	_bed(-reach, reach, half)
	box(Vector3(-half, -reach, -0.3), Vector3(half, -half, 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	# The footway across the top of the T, once: these two sat inside the loop
	# and were drawn twice, each on top of itself.
	_kerb_walk(-reach, -half - 2.2, half, 1.0)
	_kerb_walk(half + 2.2, reach, half, 1.0)
	for s: float in [-1.0, 1.0]:
		solid([Vector3(s * half, -half, -0.3), Vector3(s * reach, -half, -0.3),
				Vector3(s * reach, -reach, -0.3), Vector3(s * half, -reach, -0.3),
				Vector3(s * (half + 2.2), -half, KERB_H), Vector3(s * reach, -half, KERB_H),
				Vector3(s * reach, -reach, KERB_H), Vector3(s * half, -half - 2.2, KERB_H)],
				{"top": WALK, "side": KERB, "bottom": CONCRETE})
	_line_x(-reach, -half - 2.2, half - 0.35)
	_line_x(half + 2.2, reach, half - 0.35)
	# The side street's stop bar goes ACROSS the side street, on the lane that
	# approaches the junction. It was drawn along it, down the middle, through
	# the crossing it is meant to stop short of.
	box(Vector3(0.0, -reach + 0.3, 0.0), Vector3(half, -reach + 0.9, MARK), PAINT)
	_ladder(0.0, half, 7)


## A 90° BEND, 24 m square. The outer kerb is cut at 45° like the junction's
## corners, for the same reason.
func _road_bend() -> void:
	var half := LANE
	var reach := 12.0
	_bed(-reach, half, half)
	box(Vector3(-half, half, -0.3), Vector3(half, reach, 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	# Inside of the bend.
	solid([Vector3(half, -half, -0.3), Vector3(reach, -half, -0.3), Vector3(reach, -reach, -0.3), Vector3(half, -reach, -0.3),
			Vector3(half + 2.2, -half, KERB_H), Vector3(reach, -half, KERB_H),
			Vector3(reach, -reach, KERB_H), Vector3(half, -half - 2.2, KERB_H)],
			{"top": WALK, "side": KERB, "bottom": CONCRETE})
	# Outside of it, which is just two straight footways meeting.
	_kerb_walk(-reach, -half, half, -1.0)
	# The kerb sits OUTSIDE the carriageway edge (-half), as in _kerb_walk, and
	# the footway behind it; the kerb was drawn 0.3 m onto the road.
	box(Vector3(-half - 0.3 - WALK_W, half, -0.3), Vector3(-half - 0.3, reach, KERB_H), {"top": WALK, "side": KERB, "bottom": CONCRETE})
	box(Vector3(-half - 0.3, half, -0.3), Vector3(-half, reach, KERB_H), {"top": WALK, "side": KERB, "bottom": CONCRETE})
	_dash_x(-reach, -2.0, 0.0, 2.0, 6.0)


## A mid-block crossing with its stop bars and the advance markings, for
## dropping into a run of _road_two_lane where a squad is meant to cross.
func _crosswalk() -> void:
	var half := LANE
	_bed(-7.0, 7.0, half)
	for s: float in [-1.0, 1.0]:
		_kerb_walk(-7.0, 7.0, half, s)
		# The edge line stops for the ladder and for its own stop bar.
		_line_x(-7.0, 7.0, s * (half - 0.35), 0.075, [[-1.4, 1.4], [s * 3.0 - 0.3, s * 3.0 + 0.3]])
		_stop_bar(s * 3.0, minf(0.0, s * half), maxf(0.0, s * half))
	_ladder(0.0, half, 9)


## THE CURB CUT: the driveway into a lot. The kerb drops to nothing across the
## opening and the apron flares, which is both what they look like and the
## only way a vehicle gets off the road without a 0.15 m step.
func _curb_cut() -> void:
	var half := LANE
	_bed(-9.0, 9.0, half)
	_line_x(-9.0, 9.0, -(half - 0.35))
	# The kerb runs out where the wedges below start, at 7, not at 5: carried
	# on to 5 it was inside them.
	_kerb_walk(-9.0, -7.0, half, 1.0)
	_kerb_walk(7.0, 9.0, half, 1.0)
	_kerb_walk(-9.0, 9.0, half, -1.0)
	# The apron: asphalt from the carriageway out past the footway line, with
	# the dropped kerb either side of it cut as a wedge.
	box(Vector3(-5.0, half, -0.3), Vector3(5.0, half + 0.3 + WALK_W, 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		solid([Vector3(s * 5.0, half, -0.3), Vector3(s * 7.0, half, -0.3),
				Vector3(s * 7.0, half + 0.3 + WALK_W, -0.3), Vector3(s * 5.0, half + 0.3 + WALK_W, -0.3),
				Vector3(s * 7.0, half, KERB_H), Vector3(s * 7.0, half + 0.3 + WALK_W, KERB_H)],
				{"top": WALK, "side": KERB, "bottom": CONCRETE})


## A planted median island on its own, for dropping between carriageways or
## splitting a lot entrance. Nose cut at both ends.
func _median_island() -> void:
	var half := 1.8
	box(Vector3(-11.0, -half, -0.3), Vector3(11.0, half, KERB_H), ISLAND)
	for s: float in [-1.0, 1.0]:
		solid([Vector3(s * 11.0, -half, -0.3), Vector3(s * 14.0, -0.3, -0.3), Vector3(s * 14.0, 0.3, -0.3), Vector3(s * 11.0, half, -0.3),
				Vector3(s * 11.0, -half, KERB_H), Vector3(s * 14.0, -0.3, KERB_H), Vector3(s * 14.0, 0.3, KERB_H), Vector3(s * 11.0, half, KERB_H)],
				ISLAND)
	no_collision()
	for i in 4:
		var x := lerpf(-8.0, 8.0, float(i) / 3.0)
		# Raised to clear the island (see _road_four_lane): ring at 0.25.
		heap(Vector3(x, 0.0, 0.55), 1.0, 1.0, 0.4, i * 13 + 2, SPOIL)


## A RAISED TABLE: the whole crossing lifted to kerb height on 1 in 15 ramps.
## 0.15 m again, and the ramps are long enough that nothing reads them as a
## step at all — the point of it here is that it is a visible line across the
## road, not that it slows anything down.
func _speed_table() -> void:
	var half := LANE
	# The carriageway stops where the table starts: it is the table that is the
	# road between 3 and 5.3, and a slab under it would be a second solid there.
	_bed(-9.0, -5.3, half)
	_bed(5.3, 9.0, half)
	for s: float in [-1.0, 1.0]:
		_kerb_walk(-9.0, 9.0, half, s)
	box(Vector3(-3.0, -half, -0.3), Vector3(3.0, half, KERB_H), {"top": WALK, "side": KERB, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		ramp(minf(s * 3.0, s * 5.3), -half, maxf(s * 3.0, s * 5.3), half, -0.3, 0.0, KERB_H,
				"-x" if s > 0.0 else "+x", {"top": WALK, "side": KERB, "bottom": CONCRETE})
	# On the table's top, which is 0.15 up.
	_ladder(0.0, half, 9, KERB_H)


## A rural edge: carriageway, a gravel shoulder and W-beam guardrail on one
## side, open on the other. For where the ring road leaves the development.
func _road_shoulder() -> void:
	var half := LANE
	_bed(-SEG * 0.5, SEG * 0.5, half)
	_line_x(-SEG * 0.5, SEG * 0.5, half - 0.35)
	_line_x(-SEG * 0.5, SEG * 0.5, -(half - 0.35))
	_dash_x(-SEG * 0.5, SEG * 0.5, 0.0)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-SEG * 0.5, s * half, -0.3), Vector3(SEG * 0.5, s * (half + 2.4), -0.05), {"top": BALLAST, "side": CONCRETE, "bottom": CONCRETE})
	_rail_run(-SEG * 0.5, SEG * 0.5, half + 2.0, -0.05)


## W-beam on posts. The beam is one box because a real W section at this
## distance is one box, and the posts are 1.9 m apart as they are on the road.
func _rail_run(x0: float, x1: float, y: float, foot: float = -0.3) -> void:
	box(Vector3(x0, y - 0.09, 0.45), Vector3(x1, y + 0.09, 0.78), METAL)
	var x := x0 + 0.9
	while x < x1:
		# The post stops under the beam it carries, and starts on `foot`, the
		# ground it stands on (the gravel shoulder is -0.05, not -0.3).
		box(Vector3(x - 0.09, y - 0.05, foot), Vector3(x + 0.09, y + 0.12, 0.45), METAL)
		x += 1.9


## A SERVICE ALLEY: 6 m of asphalt between two blind walls, no kerbs. The one
## piece of street in the kit that is a corridor, and so the one a squad can
## be ambushed in.
func _alley() -> void:
	# The slab in two with the drain trench left between, and a thin bed under
	# the drain: the drain sits IN the slab, so the slab goes round it.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-SEG * 0.5, minf(s * 0.25, s * 3.0), -0.3), Vector3(SEG * 0.5, maxf(s * 0.25, s * 3.0), 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-SEG * 0.5, -0.25, -0.3), Vector3(SEG * 0.5, 0.25, -0.1), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(-SEG * 0.5, s * 3.0, -0.4), Vector3(SEG * 0.5, s * 3.4, 4.2), {"top": CONCRETE, "side": RETAIL_BRICK, "bottom": CONCRETE})
	# A strip drain down the middle, which is the only detail an alley has.
	box(Vector3(-SEG * 0.5, -0.25, -0.1), Vector3(SEG * 0.5, 0.25, -0.03), GRATING)


# ── Footways ─────────────────────────────────────────────────────────────────

## 32 m of sidewalk with its kerb, scored into bays, and tree pits. Free
# standing, for running along a lot frontage where there is no carriageway.
func _sidewalk_run() -> void:
	# The tree pits are holes in the slab, so the slab is cut round them: four
	# lengths between the pits, and a pit column of two strips and the soil
	# between. Still 32 m, end to end.
	var tile := {"top": WALK, "side": KERB, "bottom": CONCRETE}
	var from := -SEG * 0.5
	for i in 4:
		var tx := lerpf(-12.0, 12.0, float(i) / 3.0)
		box(Vector3(from, -0.3, -0.3), Vector3(tx - 0.8, WALK_W, KERB_H), tile)
		box(Vector3(tx - 0.8, -0.3, -0.3), Vector3(tx + 0.8, 0.2, KERB_H), tile)
		box(Vector3(tx - 0.8, 1.8, -0.3), Vector3(tx + 0.8, WALK_W, KERB_H), tile)
		box(Vector3(tx - 0.8, 0.2, -0.3), Vector3(tx + 0.8, 1.8, KERB_H - 0.1), {"top": DIRT, "side": KERB, "bottom": CONCRETE})
		from = tx + 0.8
	box(Vector3(from, -0.3, -0.3), Vector3(SEG * 0.5, WALK_W, KERB_H), tile)
	# Scoring: the joints every 1.5 m, standing one sixteenth of a metre PROUD
	# of the slab rather than cut into it (a cut is a hole, and the slab is
	# solid). Nothing to anything underfoot, and it is what stops 32 m of
	# concrete reading as one enormous tile. None over a tree pit.
	var x := -SEG * 0.5 + 1.5
	while x < SEG * 0.5:
		var over_pit := false
		for i in 4:
			if absf(x - lerpf(-12.0, 12.0, float(i) / 3.0)) < 0.85:
				over_pit = true
		if not over_pit:
			box(Vector3(x - 0.04, -0.3, KERB_H), Vector3(x + 0.04, WALK_W, KERB_H + MARK), KERB)
		x += 1.5
	no_collision()
	for i in 4:
		var tx := lerpf(-12.0, 12.0, float(i) / 3.0)
		# The trunk runs from the soil to the underside of the crown, where the
		# heap's lowest ring is (0.3 below its centre, on the heap's 1/8 m grid).
		cylinder(Vector3(tx, 1.0, KERB_H - 0.1), 0.22, 2.075, 6, SPOIL, 0.16)
		heap(Vector3(tx, 1.0, 2.425), 1.5, 1.5, 1.6, i * 7 + 3, SPOIL)


## The corner of two footways, with the dropped ramps onto both crossings.
func _sidewalk_corner() -> void:
	var r := 8.0
	var tile := {"top": WALK, "side": KERB, "bottom": CONCRETE}
	# The two arms start where the corner square ends (WALK_W), so they run out
	# from it and not through it.
	box(Vector3(WALK_W, -0.3, -0.3), Vector3(r, WALK_W, KERB_H), tile)
	box(Vector3(-0.3, WALK_W, -0.3), Vector3(WALK_W, r, KERB_H), tile)
	# The corner square, cut on the diagonal: the half toward the origin is the
	# ramp down to the crossing, the half away from it is level footway. This is
	# the piece of a street a body uses most and the one that is wrong most often.
	solid([Vector3(-0.3, -0.3, -0.3), Vector3(WALK_W, -0.3, -0.3), Vector3(-0.3, WALK_W, -0.3),
			Vector3(-0.3, -0.3, 0.0), Vector3(WALK_W, -0.3, KERB_H), Vector3(-0.3, WALK_W, KERB_H)],
			tile)
	solid([Vector3(WALK_W, -0.3, -0.3), Vector3(WALK_W, WALK_W, -0.3), Vector3(-0.3, WALK_W, -0.3),
			Vector3(WALK_W, -0.3, KERB_H), Vector3(WALK_W, WALK_W, KERB_H), Vector3(-0.3, WALK_W, KERB_H)],
			tile)


# ── The car park ─────────────────────────────────────────────────────────────

## A DOUBLE ROW OF BAYS either side of a kerbed island, 36 m long, with the
## aisle marked out at both edges. Lay these in parallel 18 m apart and the
## result is a car park.
func _lot_parking_row() -> void:
	var half := 18.0
	# The asphalt either side of the island, not under it.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-half, minf(s * 1.4, s * 7.2), -0.3), Vector3(half, maxf(s * 1.4, s * 7.2), 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-half, -1.4, -0.3), Vector3(half, 1.4, KERB_H), ISLAND)
	for s: float in [-1.0, 1.0]:
		# The bays stop at the edge of the boundary line, not under it.
		_bays(-half, half, s * 1.4, s * 6.94, 2.7, 0.0)
		box(Vector3(-half, s * 7.0 - 0.06, 0.0), Vector3(half, s * 7.0 + 0.06, MARK), PAINT)
	no_collision()
	for i in 4:
		var x := lerpf(-half + 4.0, half - 4.0, float(i) / 3.0)
		cylinder(Vector3(x, 0.0, KERB_H), 0.5, 0.3, 7, SPOIL, 0.38)
		cylinder(Vector3(x, 0.0, KERB_H + 0.3), 0.2, 2.2, 6, SPOIL, 0.14)


## The island that caps an aisle, with the lot light standing on it. The thing
## a squad crossing a car park actually uses, so it is a piece of its own.
func _lot_aisle_cap() -> void:
	box(Vector3(-2.6, -1.4, -0.3), Vector3(2.6, 1.4, KERB_H), ISLAND)
	for s: float in [-1.0, 1.0]:
		solid([Vector3(s * 2.6, -1.4, -0.3), Vector3(s * 4.4, -0.4, -0.3), Vector3(s * 4.4, 0.4, -0.3), Vector3(s * 2.6, 1.4, -0.3),
				Vector3(s * 2.6, -1.4, KERB_H), Vector3(s * 4.4, -0.4, KERB_H), Vector3(s * 4.4, 0.4, KERB_H), Vector3(s * 2.6, 1.4, KERB_H)],
				ISLAND)
	box(Vector3(-0.55, -0.55, KERB_H), Vector3(0.55, 0.55, 0.75), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-0.26, -0.26, 0.75), Vector3(0.26, 0.26, 9.0), METAL)
	for s: float in [-1.0, 1.0]:
		# The arm starts at the pole and the lamp hangs from it: neither is
		# drawn through the other.
		box(Vector3(s * 0.26, -0.22, 8.6), Vector3(s * 2.2, 0.22, 8.9), METAL)
		box(Vector3(s * 1.5, -0.75, 8.25), Vector3(s * 2.6, 0.75, 8.6), {"top": METAL, "side": METAL, "bottom": SIGN_BAND})


## Accessible bays: the wide ones by the door, their hatching, and the signs
## on posts at the head of each.
func _lot_accessible() -> void:
	# The asphalt stops at the footway (y 0), which stands on its own slab.
	box(Vector3(-9.0, -6.0, -0.3), Vector3(9.0, 0.0, 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-9.0, 0.0, -0.3), Vector3(9.0, 0.6, KERB_H), {"top": WALK, "side": KERB, "bottom": CONCRETE})
	for i in 3:
		var x := -9.0 + i * 6.0
		# Every line starts at the foot line (-5.94), which is painted last and
		# along the whole row: lines running down to -6.0 crossed it.
		box(Vector3(x - 0.06, -5.94, 0.0), Vector3(x + 0.06, 0.0, MARK), PAINT)
		box(Vector3(x + 3.5 - 0.06, -5.94, 0.0), Vector3(x + 3.5 + 0.06, 0.0, MARK), PAINT)
		# The hatched aisle beside each bay, clear of the bay lines either side.
		var h := x + 3.5
		for k in 6:
			var t := float(k) / 5.0
			var y0 := -5.94 + t * 5.34
			box(Vector3(h + 0.2 + t * 2.0 - 0.07, y0, 0.0), Vector3(h + 0.2 + t * 2.0 + 0.07, y0 + 0.6, MARK), PAINT)
		# The sign post stands on the footway, and its plate hangs off its face
		# over the bay (-y), rather than the two passing through each other.
		box(Vector3(x + 1.6, 0.0, KERB_H), Vector3(x + 1.75, 0.2, 2.1), METAL)
		box(Vector3(x + 1.35, -0.12, 1.5), Vector3(x + 2.0, 0.0, 2.05), SIGN_BAND)
	box(Vector3(-9.0, -6.0, 0.0), Vector3(9.0, -5.94, MARK), PAINT)


## A row of precast wheel stops. 0.12 m, so they are under everything that
## matters and a body walks over them — which is the point, a car park full of
## 0.3 m blocks is a car park the squad picks its way across.
func _lot_wheel_stops() -> void:
	for i in 7:
		var x := -8.1 + i * 2.7
		box(Vector3(x - 0.85, -0.22, -0.1), Vector3(x + 0.85, 0.22, 0.12), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})


## THE ENTRANCE THROAT: the splitter island, the flared apron and the stop bar
## where a lot meets the road. One of the two or three places a whole map's
## traffic has to funnel, and so worth building properly.
func _lot_entry_throat() -> void:
	# The asphalt round the splitter island, not under it: a slab either side
	# and the two short lengths at the island's ends.
	for s: float in [-1.0, 1.0]:
		box(Vector3(minf(s * 1.6, s * 11.0), -14.0, -0.3), Vector3(maxf(s * 1.6, s * 11.0), 0.0, 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-1.6, -14.0, -0.3), Vector3(1.6, -12.0, 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-1.6, -2.0, -0.3), Vector3(1.6, 0.0, 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		solid([Vector3(s * 11.0, -14.0, -0.3), Vector3(s * 18.0, -14.0, -0.3), Vector3(s * 11.0, 0.0, -0.3),
				Vector3(s * 11.0, -14.0, 0.0), Vector3(s * 18.0, -14.0, 0.0), Vector3(s * 11.0, 0.0, 0.0)],
				{"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	# The island is the body between the noses, and the noses are what taper it
	# at each end. The noses used to be built pointing INTO the body (tip at
	# y + s * -2.4), buried in it; they now point out, so the island still runs
	# -12 to -2 and has the pointed ends it was written to have.
	box(Vector3(-1.6, -9.6, -0.3), Vector3(1.6, -4.4, KERB_H), ISLAND)
	for s: float in [-1.0, 1.0]:
		var base: float = -9.6 if s < 0.0 else -4.4
		var tip: float = -12.0 if s < 0.0 else -2.0
		solid([Vector3(-1.6, base, -0.3), Vector3(1.6, base, -0.3), Vector3(0.0, tip, -0.3),
				Vector3(-1.6, base, KERB_H), Vector3(1.6, base, KERB_H), Vector3(0.0, tip, KERB_H)],
				ISLAND)
	_stop_bar(0.0, 1.9, 9.0)
	box(Vector3(2.0, -3.0, 0.0), Vector3(9.0, -2.88, MARK), PAINT)
	box(Vector3(-9.0, -3.0, 0.0), Vector3(-2.0, -2.88, MARK), PAINT)


## A bigger trolley shelter than the corral: a roof over a pen for two rows,
## at the head of an aisle. Cover in the middle of a car park, which that
## ground badly needs.
func _lot_cart_shelter() -> void:
	box(Vector3(-5.0, -2.0, -0.3), Vector3(5.0, 2.0, 0.05), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		# The panels stand on the slab (0.05), and the end panels run between
		# the side panels, not through them.
		box(Vector3(-5.0, minf(s * 2.0 - s * 0.14, s * 2.0), 0.05), Vector3(5.0, maxf(s * 2.0 - s * 0.14, s * 2.0), COVER_H), {"top": METAL, "side": SHUTTER, "bottom": METAL})
	box(Vector3(-5.0, -1.86, 0.05), Vector3(-4.86, 1.86, COVER_H), {"top": METAL, "side": SHUTTER, "bottom": METAL})
	box(Vector3(4.86, -1.86, 0.05), Vector3(5.0, 1.86, COVER_H), {"top": METAL, "side": SHUTTER, "bottom": METAL})
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			post(sx * 4.6, sy * 1.7, 0.05, 3.0, 0.2)
	box(Vector3(-5.6, -2.5, 3.0), Vector3(5.6, 2.5, 3.25), {"top": ROOF_MEMBRANE, "side": SIGN_BAND, "bottom": METAL})


# ── Furniture ────────────────────────────────────────────────────────────────

## A signal on a mast arm reaching over the carriageway, 7.5 m to the arm.
## The tallest thing at a junction and what tells you where one is from a
## distance.
func _signal_mast() -> void:
	box(Vector3(-0.6, -0.6, -0.5), Vector3(0.6, 0.6, 0.35), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-0.24, -0.24, 0.35), Vector3(0.24, 0.24, 7.8), METAL)
	# The arm starts at the mast's face, not at its axis.
	box(Vector3(0.24, -0.16, 7.5), Vector3(9.0, 0.16, 7.8), METAL)
	for x: float in [3.2, 6.2, 8.4]:
		box(Vector3(x - 0.22, -0.3, 6.5), Vector3(x + 0.22, 0.3, 7.5), {"top": METAL, "side": GREEN, "bottom": METAL})
	# The pedestrian head and the push button, down at the kerb.
	box(Vector3(0.3, -0.26, 2.4), Vector3(0.72, 0.26, 3.1), {"top": METAL, "side": GREEN, "bottom": METAL})
	box(Vector3(0.26, -0.12, 1.0), Vector3(0.44, 0.12, 1.25), METAL)


## A cobra-head street light, 9 m, on the kerb. Steel column, curved arm
## faked as two boxes, which at this distance is a curve.
func _light_cobra() -> void:
	box(Vector3(-0.45, -0.45, -0.5), Vector3(0.45, 0.45, 0.25), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-0.2, -0.2, 0.25), Vector3(0.2, 0.2, 8.4), METAL)
	# The bracket leaves the column's face (0.2), not its axis, and the arm
	# starts where the bracket ends: three bars in a row, not overlapping.
	beam(Vector3(0.35, 0.0, 8.2), Vector3(1.15, 0.0, 9.0), 0.26, METAL)
	box(Vector3(1.25, -0.16, 8.9), Vector3(2.3, 0.16, 9.1), METAL)
	box(Vector3(2.3, -0.4, 8.7), Vector3(3.4, 0.4, 9.0), {"top": METAL, "side": METAL, "bottom": SIGN_BAND})


## A stop sign on its post, and the street name blade over it.
func _sign_stop() -> void:
	box(Vector3(-0.07, -0.07, -0.4), Vector3(0.07, 0.07, 3.0), METAL)
	# The face on the post's face, the blade on its top.
	box(Vector3(-0.5, 0.07, 1.7), Vector3(0.5, 0.15, 2.7), SIGN_BAND)
	box(Vector3(-0.04, -0.75, 3.0), Vector3(0.04, 0.75, 3.3), SIGN_BAND)


## An overhead sign gantry across two lanes: a truss on two columns with the
## panels hung under it. 5.8 m clear so everything drives under.
func _sign_gantry() -> void:
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 7.0 - 0.45, -0.45, -0.5), Vector3(s * 7.0 + 0.45, 0.45, 6.6), {"top": METAL, "side": CONCRETE, "bottom": CONCRETE})
	# The chords run between the columns, not through them.
	for z: float in [6.1, 6.9]:
		box(Vector3(-6.55, -0.2, z - 0.14), Vector3(6.55, 0.2, z + 0.14), METAL)
	# The web members are slanted prisms that start on the lower chord's top
	# and end on the upper one's underside, so they touch both and run through
	# neither. The last one would have left the truss past the column; it is
	# dropped.
	for i in 8:
		var x := lerpf(-6.4, 6.4, float(i) / 8.0)
		solid([Vector3(x - 0.1, -0.07, 6.24), Vector3(x + 0.1, -0.07, 6.24), Vector3(x - 0.1, 0.07, 6.24), Vector3(x + 0.1, 0.07, 6.24),
				Vector3(x + 1.3, -0.07, 6.76), Vector3(x + 1.5, -0.07, 6.76), Vector3(x + 1.3, 0.07, 6.76), Vector3(x + 1.5, 0.07, 6.76)],
				METAL)
	# The panels hang from the lower chord's underside.
	box(Vector3(-5.2, -0.3, 4.4), Vector3(0.6, -0.1, 5.96), {"top": METAL, "side": GREEN, "bottom": METAL})
	box(Vector3(1.4, -0.3, 4.8), Vector3(5.4, -0.1, 5.96), {"top": METAL, "side": GREEN, "bottom": METAL})


## 16 m of W-beam on its own, for a lot edge or a drop.
func _guardrail() -> void:
	_rail_run(-8.0, 8.0, 0.0)


## Bollards across a frontage, at 1.5 m — close enough that a vehicle cannot
## pass and a body walks straight through, which is exactly what they are for
## and a useful thing to have in a kit.
func _bollard_row() -> void:
	for i in 9:
		var x := -6.0 + i * 1.5
		cylinder(Vector3(x, 0.0, -0.3), 0.14, 1.2, 8, METAL)
		cylinder(Vector3(x, 0.0, 0.9), 0.16, 0.1, 8, SIGN_BAND)


func _hydrant() -> void:
	cylinder(Vector3(0.0, 0.0, -0.3), 0.3, 0.25, 8, CONCRETE)
	cylinder(Vector3(0.0, 0.0, -0.05), 0.17, 0.75, 8, SIGN_BAND)
	cylinder(Vector3(0.0, 0.0, 0.7), 0.21, 0.12, 8, SIGN_BAND)
	cylinder(Vector3(0.0, 0.0, 0.82), 0.12, 0.16, 8, SIGN_BAND)
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 0.17, -0.1, 0.3), Vector3(s * 0.3, 0.1, 0.5), METAL)


## The green boxes on every suburban verge. Waist high, which makes them the
## only cover on a stretch of footway.
func _utility_cabinet() -> void:
	box(Vector3(-1.1, -0.5, -0.3), Vector3(1.1, 0.5, 0.1), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-0.95, -0.38, 0.1), Vector3(0.95, 0.38, COVER_H), {"top": METAL, "side": GREEN, "bottom": METAL})
	box(Vector3(-1.02, -0.44, COVER_H), Vector3(1.02, 0.44, COVER_H + 0.1), METAL)
	box(Vector3(-0.5, -0.4, 0.5), Vector3(0.5, -0.36, 1.0), METAL)


## A pad-mount transformer on its slab, with the clearance fence behind it.
func _transformer_pad() -> void:
	box(Vector3(-1.9, -1.6, -0.4), Vector3(1.9, 1.6, 0.15), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	box(Vector3(-1.4, -1.1, 0.15), Vector3(1.4, 1.1, 1.75), {"top": METAL, "side": GREEN, "bottom": METAL})
	box(Vector3(-1.5, -1.2, 1.75), Vector3(1.5, 1.2, 1.9), METAL)
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 0.9 - 0.14, -1.2, 1.9), Vector3(s * 0.9 + 0.14, -0.92, 2.5), METAL)
	_fence_clean(Vector2(-2.6, 2.3), Vector2(2.6, 2.3), -0.3, 2.1)


## A kerb inlet and its gutter pan. The grate is mesh only — a 0.1 m lip in a
## gutter is nothing to look at and a thing for a body to catch on, and this
## project has been caught by exactly that before.
func _storm_inlet() -> void:
	box(Vector3(-1.2, 0.0, -0.3), Vector3(1.2, 0.3, KERB_H), {"top": WALK, "side": KERB, "bottom": CONCRETE})
	# (There was a second CONCRETE box here, 0.02 inside the kerb on every side:
	# wholly buried, invisible, and a second solid in the same space.)
	box(Vector3(-1.6, -0.6, -0.3), Vector3(1.6, 0.0, -0.06), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	no_collision()
	box(Vector3(-0.85, -0.5, -0.06), Vector3(0.85, -0.05, -0.0), GRATING)


## THE ARTERIAL AND THE FIVE-LANE WITH NO BED, to lay into ground that is
## already hard. Same argument as _road_two_lane_inlay: a carriageway laid on
## a surface that is already there is two floors in one place, and the ground
## tiles under these are asphalt for exactly that reason.
func _road_four_lane_inlay() -> void:
	var half := LANE * 2.0 + 1.5
	box(Vector3(-SEG * 0.5, -1.5, -0.3), Vector3(SEG * 0.5, 1.5, KERB_H), ISLAND)
	for s: float in [-1.0, 1.0]:
		_kerb_walk(-SEG * 0.5, SEG * 0.5, half, s)
		_line_x(-SEG * 0.5, SEG * 0.5, s * (half - 0.35))
		_dash_x(-SEG * 0.5, SEG * 0.5, s * (1.5 + LANE))
	no_collision()
	var x := -SEG * 0.5 + 3.0
	while x < SEG * 0.5 - 2.0:
		# Same offsets as _road_four_lane: the heap ring snaps to a 1/8 m grid
		# and lands 0.1 m clear of a 0.15 kerb rather than 0.025 m into it.
		heap(Vector3(x, 0.0, 0.55), 0.9, 0.9, 0.45, int(x) + 7, SPOIL)
		x += 6.0


func _road_turn_lane_inlay() -> void:
	var half := LANE * 2.5
	for s: float in [-1.0, 1.0]:
		_kerb_walk(-SEG * 0.5, SEG * 0.5, half, s)
		_line_x(-SEG * 0.5, SEG * 0.5, s * (half - 0.35))
		_dash_x(-SEG * 0.5, SEG * 0.5, s * LANE)
		_line_x(-SEG * 0.5, SEG * 0.5, s * LANE * 0.5)
	# ONE chevron per step. I copied this loop with a `for s in [-1, 1]` round
	# it that never used s, so it drew every chevron twice in the same place —
	# the exact duplicate-in-a-loop bug that had already been fixed in the
	# piece I copied from.
	var x := -SEG * 0.5 + 2.0
	while x < SEG * 0.5 - 2.0:
		box(Vector3(x, -0.1, 0.0), Vector3(x + 2.4, 0.1, MARK), PAINT)
		x += 5.0


## THE ENTRY THROAT WITH NO APRON, for a lot that is already asphalt. The
## splitter island and the markings are the whole piece; the apron underneath
## is the car park.
func _lot_entry_throat_inlay() -> void:
	box(Vector3(-1.6, -12.0, -0.3), Vector3(1.6, -2.0, KERB_H), ISLAND)
	for s: float in [-1.0, 1.0]:
		var y: float = -12.0 if s < 0.0 else -2.0
		# The apex goes BEYOND the island end, not back into it. With s * -2.4
		# both noses pointed inwards and each one lay 2.4 m inside the island it
		# was supposed to be the end of.
		solid([Vector3(-1.6, y, -0.3), Vector3(1.6, y, -0.3), Vector3(0.0, y + s * 2.4, -0.3),
				Vector3(-1.6, y, KERB_H), Vector3(1.6, y, KERB_H), Vector3(0.0, y + s * 2.4, KERB_H)],
				ISLAND)
	_stop_bar(0.0, 1.9, 9.0)
	box(Vector3(2.0, -3.0, 0.0), Vector3(9.0, -2.88, MARK), PAINT)
	box(Vector3(-9.0, -3.0, 0.0), Vector3(-2.0, -2.88, MARK), PAINT)
