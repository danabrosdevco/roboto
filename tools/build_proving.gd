extends "res://tools/block_fortress.gd"

# ─────────────────────────────────────────────
# BUILD PROVING — the proving ground, larger and more open.
#
#   maps/proving/proving_level.map
#
#   godot --headless --path . --script res://tools/build_proving.gd -- maps --force
#   SHOW=all ...                          every overlapping pair, not the first 30
#   WIDTH=0  ...                          skip the width survey (it is the slow part)
#
# THE OLD GENERATOR IS tools/block_arena.gd, and the brief for this job said
# there was none. There was: the map on disk is byte-identical to what
# block_arena.gd writes, which is how we know nothing had been hand-edited in
# TrenchBroom since and that regenerating it throws nothing away. That tool now
# refuses to write and points here; this file is the one generator for this map.
#
# WHAT IT IS FOR. Capture and extraction are being revised, and the revision
# needs room: an open bay behind the enemy blockhouse for a bunker to sit in,
# and an arena a Walker and a Rover can actually drive through. This builds the
# SPACE and nothing else — no capture volumes, no extraction areas, no
# objectives, no spawns. Those are gameplay nodes and live in the level scene;
# see the rebuild note at the bottom.
#
# ── AXES, which are the first thing to get wrong ─────────────────────────────
#
# FuncGodot turns Quake (x, y, z) into Godot (y, z, x). So in this file:
#
#   x  runs along the map, and is Godot Z — the spawn-to-bunker axis.
#   y  runs across it, and is Godot X.
#   z  is up, and is Godot Y. The playable floor is z 0.
#
# 32 units to the metre (the map settings' inverse_scale_factor); everything
# here is written in metres and snapped on the way out.
#
# ── THE SHAPE, west to east ──────────────────────────────────────────────────
#
#   the arena   x -45..45   the tower, the two blockhouses, the squad's end
#   the bay     x  45..90   out of the back of the enemy blockhouse: a
#                           30 x 30 m floor for the bunker and four edge blocks
#
# ONE FLOOR, ONE FENCE. The playable ground is a single rectangle,
# x -45..90 by y +/-35, and every edge of it is under a wall — the arena's
# ramparts on the west half, a revetment of the same height and section round
# the bay. So nothing can walk off the 1.5 m lip onto the apron and strand
# itself outside the bake, which is the failure the old map's open apron
# invited. The arena is 14 m wider than it was as well: at 54 m across, its
# north and south strips were 13 m deep, which is less than one piece of cover
# needs, so there was nowhere to put anything.
#
# ── THE RULE THAT SHAPED EVERYTHING: 8 m ─────────────────────────────────────
#
# No route narrower than 8 m. A Rover is 3.40 m long and 1.70 wide, so turning
# one needs a 3.80 m circle, and Godot's pathfinder cannot reverse: a lane it
# can enter and not leave is a lost robot. 8 m of built width survives any
# agent_radius anyone is likely to bake at.
#
# THE PRICE IS COVER DENSITY, and it is worth saying out loud because it is not
# obvious. A free-standing wall with 8 m clear on both sides occupies 17 m of
# ground. The old arena's north strip was 13 m deep, so nothing could stand in
# it at all. The old map had 56 pieces of cover; this one has 8, and the rest of
# the cover is the FACES of things — the bases, the tower, the four yard blocks,
# the four clearing blocks — which give a wall to stand behind without putting a
# slot anywhere. If the arena now reads as too bare, the lever is the 8 m rule,
# not the piece count: at 6 m it would take about twice as many.
#
# Everything else the navigation brief asks for, by construction:
#
#   * nothing solid stands between 0.25 m and 0.5 m — the baker will not climb
#     it and a body steps over it, so it bakes as a wall the squad walks
#     through. The lowest thing here is 1.0 m (the tower ramp's kerbs).
#   * the playable floor is dead flat. Every bit of height is a built asset.
#   * both ramps are 14 degrees. The tower's is 4.6 m over 18 m of run, each
#     base's 3.0 m over 12 m — under the 15 degree ceiling, where the old
#     tower ramp was 21.
#   * 3.0 m of headroom over every route. The old bases had a deck 2.6 m over
#     the ground with the level exit UNDER it, so a 3.00 m Walker could not
#     stand on the extraction point. The bases are solid now and the exit
#     stands in an open court.
#
# ── WHAT MUST NOT CHANGE ─────────────────────────────────────────────────────
#
# The level scene owns the spawn (-28, 0), both objective markers (+/-37, 0),
# the level exit (37, 0) and the training markers (30, 0) and (37, 0) — in this
# file's axes. Every one of them lands on flat, open, reachable floor here, and
# _anchors() asserts it rather than trusting that it still does.
#
# ── AFTER THIS RUNS ──────────────────────────────────────────────────────────
#
#   LEVEL=res://maps/proving_level.tscn godot --headless --path . \
#       --script res://tools/level_map_rebuild.gd
#   BAKE_ONLY=1 LEVEL=res://maps/proving_level.tscn godot --path . \
#       --script res://tools/probe_nav_hillfort.gd
#   LEVEL=res://maps/proving_level.tscn godot --path . \
#       --script res://tools/probe_cover_mutaha.gd
#
# in that order: the geometry, then the navmesh that is baked from it, then the
# cover points that are baked from the navmesh. The scene's NavigationMesh also
# needs filter_baking_aabb grown to cover this extent and agent_height raised
# to 3.0 — the bake is CLIPPED to that box, so a back area outside it bakes as
# nothing at all and reads as a map the squad refuses to walk on.
# ─────────────────────────────────────────────

# ── The arena (A) ──
const A_X := 44.0        ## half the length: 88 m, as it was
const A_Y := 34.0        ## half the width: 68 m, where it was 54
const WALL := 1.0
const WALL_Z := 3.5
const COPE := 0.35       ## the coping over every wall and revetment
const COPE_OUT := 0.15   ## how far it stands proud of the inside face

# ── The new ground: the bay behind the enemy blockhouse ──
const N_X1 := 90.0       ## the floor's east edge, under the east revetment
const PIER := 10.0       ## wall piers at this pitch, for something to measure by

# ── The gateway out of the enemy blockhouse ──
## 12 m clear, and the coping runs on over it as a lintel, so the arena still
## reads as an arena rather than as a wall somebody forgot to finish.
const GATE := 6.0
const GATE_LINTEL := 0.75

# ── The tower ──
const TOW_HALF := 6.0
const TOW_DECK := 4.6    ## over every piece of cover on the map
const TOW_TOP := 12.0    ## the derrick above it is the thing you steer by
const TOW_RAMP := 24.0   ## the ramps run in from y +/-24: 18 m of run, 14 deg
const RAMP_HALF := 3.0   ## 6 m wide, where it was 4 — a Rover must turn on it
const RAMP_KERB := 1.0   ## and not walk off the side of it
const DERRICK_W := 0.35

# ── The bases ──
## TWO WINGS AND AN OPEN COURT, not a deck on posts. The level exit stands at
## (37, 0), which was under the old deck with 2.6 m of headroom over it; the
## court is open to the sky.
const BASE_IN := 32.0
const BASE_OUT := 44.0   ## flush with the rampart, so no 2 m slot behind it
const BASE_DECK := 3.0   ## unchanged: the objective markers sit at z 3.2
const COURT := 6.0       ## the court is y +/-6, and the wings start here
const WING := 14.0
const BR_IN := 20.0      ## the wing ramp: 12 m of run for 3.0 m, 14 deg

# ── The bay ──
const B_X0 := 45.0       ## it starts at the arena wall's outer face
## The edge blocks' inner face. 25, so the band between them and the bunker
## floor is 10 m deep and a 1.5 m buttress still leaves 8.5.
const BLOCK_IN := 25.0
## THE BUNKER FLOOR: 30 x 30 m, flat, completely clear, and flush with the east
## revetment so there is no slot behind it. Open ground on three sides — 14 m
## west between it and the gateway, 19 m north, 19 m south — so a Bulwark walks
## right round whatever gets dropped in it.
const PAD_RECT := Rect2(59.0, -15.0, 30.0, 30.0)

# ── Textures, as the arena chose them ──
## The grass is the one thing about the old arena that already looked right, and
## the rest of the palette is picked to sit against it.
const TURF := "textures_pack/Grass_19-256x256"
## Dark earth for the routes. Not green is the whole trick: you can read the
## map's shape while standing in it. Paler sand clipped to white under this sun.
const PATH := "textures_pack/Dirt_04-256x256"
## Blue-grey for anything you do not get past.
const RAMPART := "PSX_Textures/concrete_wall_12_1"
const TREAD := "PSX_Textures/metal_floor_1@0.5"
const CHALK := "PSX_Textures/concrete_tx_5"
const BLOCK := "PSX_Textures/concrete_wall_12_1"
const OXIDE := "PSX_Textures/metal_wall_5"

const GROUND := {"top": TURF, "side": RAMPART, "bottom": RAMPART}
const PAVED := {"top": PATH, "side": RAMPART, "bottom": RAMPART}

## 1.3 m, not 1.0: CoverPointSpawner probes for a wall at 1.2 m, so anything
## shorter generates no cover point at all and the AI never uses it.
const LOW := 1.3
const MID := 1.9
const TALL := 3.0

## Cover, written once and stamped twice — the second time rotated 180 degrees
## about the centre, so neither end of the arena has the better ground.
## [x, y, length, thickness, height, along_x, texture]
##
## FOUR PIECES, not twenty-eight. Each one butts a ramp's flank at y 14 so it
## grows out of something rather than standing in a lane; every gap between them
## is 8.1 m; and each stops 8.6 m short of the rampart, because a wall pier
## stands 0.4 m proud of it and 8 m to the wall is 7.6 m to the pier. See the
## note on cover density at the top.
const COVER := [
	[30.0, 19.5, 11.0, 1.0, TALL, false, BLOCK],   # x 29.5..30.5, y 14..25
	[21.0, 18.5, 9.0, 0.8, MID, false, CHALK],     # x 20.6..21.4, y 14..23
	[12.0, 19.5, 11.0, 1.0, TALL, false, BLOCK],   # x 11.5..12.5, y 14..25
	[-26.0, 18.0, 8.0, 4.0, TALL, false, BLOCK],   # x -28..-24,  y 14..22
]

## The bay's edge blocks: [x0, x1, y_outer_sign, height]. Each butts the
## perimeter revetment, so none leaves a sliver behind it, and the gaps between
## them along x — 10 m to the arena wall, 10 m between the pair, 10 m to the
## east revetment — are the flanking ways round the bunker floor.
##
## Four heights between 3 and 6 m on purpose. A distance-legibility pass on
## another map measured tall mid-ground mass as the single thing that makes
## terrain readable, and a bay of identical boxes reads as one box.
const BLOCKS := [
	[55.0, 62.0, 1.0, 5.0], [72.0, 79.0, 1.0, 4.0],
	[55.0, 62.0, -1.0, 3.0], [72.0, 79.0, -1.0, 6.0],
]

## Where the level scene's own nodes stand, in this file's axes. Checked, not
## assumed: a generator that quietly buries the level exit in a wall is the
## expensive kind of mistake.
const ANCHORS := [
	["spawn", -28.0, 0.0], ["objective west", -37.0, 0.0],
	["objective east", 37.0, 0.0], ["level exit", 37.0, 0.0],
	["training core", 30.0, 0.0], ["training bunker", 37.0, 0.0],
]

var _stages: Array = []      ## [first brush index, what built it]
var _coll: Array = []        ## per brush: does it have collision
var _collides := true


func _initialize() -> void:
	var base := ""
	var force := false
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
	if base == "":
		print("usage: godot --headless --path . --script res://tools/build_proving.gd -- maps [--force]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("proving")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var path := dir.path_join("proving_level.map")
	if FileAccess.file_exists(path) and not force:
		print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
		quit()
		return
	_brushes = []
	_ghost_from = -1
	_entities = []
	_stages = []
	_coll = []
	_collides = true
	_build()
	if not _check():
		quit(1)
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string(_map_text())
	f.close()
	print("      %-22s %3d brushes  %s" % ["proving_level", _brushes.size(), _extent_text()])
	print("BUILD PROVING DONE")
	print("      REBUILD THE LEVEL and re-bake: see the header of this file.")
	quit()


## Each stage names itself, so an overlapping pair reads as "yard/clearing"
## rather than as two brush numbers nobody can place.
func _build() -> void:
	_stage("apron")
	_apron()
	_stage("floor")
	_floor()
	_stage("rampart")
	_rampart()
	_stage("tower")
	_tower()
	for s: float in [1.0, -1.0]:
		_stage("base %s" % ("east" if s > 0.0 else "west"))
		_base(s)
	for i in COVER.size():
		_stage("cover %d" % i)
		_cover(COVER[i], 1.0)
		_cover(COVER[i], -1.0)
	_stage("bay")
	entity("func_detail")
	_bay()
	_stage("silhouette")
	no_collision()
	_derrick()
	_skyline()


# ── Ground ───────────────────────────────────────────────────────────────────

## BARE GROUND OUT TO THE SILHOUETTE, 1.5 m below the playable floor. Without it
## the tanks and pylons outside the wall hang in the air. It reaches further east
## than west because the map does: the clearing pushed the east end out.
func _apron() -> void:
	box(Vector3(-100.0, -70.0, -3.5), Vector3(130.0, 70.0, -1.5), PAVED)


## THE PLAYABLE FLOOR AND THE ROUTES IN IT, AS ONE SURFACE — one rectangle from
## the west rampart to the east revetment, cut at every route edge and coloured
## cell by cell.
##
## IT IS NOT PLATES LAID ON THE GRASS. That is how the old map did it, 0.06 m
## proud with a bevelled edge, and it was a fifth of its overlapping brushes:
## every route crossing another, and every piece of cover standing on one, sank
## into the plate beneath. Six centimetres nobody could see in a game where the
## colour is doing all the work.
##
## So: cut the floor at every route edge, colour each cell by whether a route
## covers it, and merge the runs back along x. No plate, no bevel, no lip to
## catch a robot, and it reads the same from eye height and from the minimap.
func _floor() -> void:
	# The route network, as rectangles. Colour only — none of this is geometry.
	var lanes: Array = [
		Rect2(-A_X, -COURT, N_X1 - 1.0 + A_X, COURT * 2.0),              # the long way through
		Rect2(-40.0, 17.0, 80.0, 10.0), Rect2(-40.0, -27.0, 80.0, 10.0), # the arena's side lanes
		Rect2(-BASE_OUT, -WING, BASE_OUT - BASE_IN, WING * 2.0),         # the base courts
		Rect2(BASE_IN, -WING, BASE_OUT - BASE_IN, WING * 2.0),
		Rect2(B_X0, 15.0, N_X1 - 1.0 - B_X0, 9.0),                       # the flanking tracks
		Rect2(B_X0, -24.0, N_X1 - 1.0 - B_X0, 9.0),
		Rect2(PAD_RECT.position, PAD_RECT.size),                         # the bunker floor
	]
	var xs := _cuts(-A_X - WALL, N_X1, lanes, true)
	var ys := _cuts(-A_Y - WALL, A_Y + WALL, lanes, false)
	for r in ys.size() - 1:
		var y0: float = ys[r]
		var y1: float = ys[r + 1]
		var run := 0
		for c in xs.size() - 1:
			# Hold the run open while the next cell is the same surface, so a
			# row of grass is one brush and not eleven.
			var last: bool = c == xs.size() - 2
			var same: bool = not last and _is_lane(lanes, xs[c + 1], xs[c + 2], y0, y1) \
					== _is_lane(lanes, xs[c], xs[c + 1], y0, y1)
			if same:
				continue
			var paved: bool = _is_lane(lanes, xs[run], xs[c + 1], y0, y1)
			box(Vector3(xs[run], y0, -1.5), Vector3(xs[c + 1], y1, 0.0),
					PAVED if paved else GROUND)
			run = c + 1


## Every distinct edge the routes put in one axis, plus the floor's own, sorted.
func _cuts(lo: float, hi: float, lanes: Array, along_x: bool) -> Array:
	var seen := {lo: true, hi: true}
	for r: Rect2 in lanes:
		for v: float in ([r.position.x, r.end.x] if along_x else [r.position.y, r.end.y]):
			if v > lo and v < hi:
				seen[v] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## Cells are cut AT every route edge, so a cell lies wholly inside one or wholly
## outside, and its centre answers for all of it.
func _is_lane(lanes: Array, x0: float, x1: float, y0: float, y1: float) -> bool:
	var c := Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5)
	for r: Rect2 in lanes:
		if r.has_point(c):
			return true
	return false


## THE FENCE ROUND THE WHOLE FLOOR. The arena's four ramparts, and a revetment
## of the same height and section round B and C, so the two halves read as one
## compound and the floor has no unguarded edge anywhere.
##
## The coping stands 0.15 m proud of the inside face, so a wall reads as built
## rather than as a slab. Each run's coping takes the corner its wall does;
## they are written as four straight runs that meet rather than four that cross,
## because taken to the corner they share a block of the same space.
func _rampart() -> void:
	var east: float = N_X1
	# North and south, the full length.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-A_X - WALL, s * A_Y, 0.0), Vector3(east, s * (A_Y + WALL), WALL_Z), RAMPART)
		box(Vector3(-A_X - WALL, s * (A_Y - COPE_OUT), WALL_Z),
				Vector3(east, s * (A_Y + WALL), WALL_Z + COPE), OXIDE)
	# West, and the east revetment behind the clearing. Both run between the
	# north and south walls' inside faces.
	for run: Array in [[-A_X - WALL, -A_X], [east - WALL, east]]:
		box(Vector3(run[0], -A_Y, 0.0), Vector3(run[1], A_Y, WALL_Z), RAMPART)
	box(Vector3(-A_X - WALL, -A_Y + COPE_OUT, WALL_Z),
			Vector3(-A_X + COPE_OUT, A_Y - COPE_OUT, WALL_Z + COPE), OXIDE)
	box(Vector3(east - WALL - COPE_OUT, -A_Y + COPE_OUT, WALL_Z),
			Vector3(east, A_Y - COPE_OUT, WALL_Z + COPE), OXIDE)
	# THE ARENA'S EAST WALL, WITH THE GATEWAY IN IT. A breach, not a removed
	# wall: the coping runs on over the opening as a lintel, which leaves
	# 3.85 m of clear height — a Walker is 3.00 m tall.
	for s: float in [-1.0, 1.0]:
		box(Vector3(A_X, s * GATE, 0.0), Vector3(A_X + WALL, s * A_Y, WALL_Z), RAMPART)
		# Stopping at the long walls' coping, not at the wall: run both to the
		# corner and they share a 1.15 x 0.15 m block of the same space.
		box(Vector3(A_X - COPE_OUT, s * GATE, WALL_Z),
				Vector3(A_X + WALL, s * (A_Y - COPE_OUT), WALL_Z + COPE), OXIDE)
	box(Vector3(A_X - COPE_OUT, -GATE, WALL_Z + COPE),
			Vector3(A_X + WALL, GATE, WALL_Z + COPE + GATE_LINTEL), OXIDE)
	# PIERS, for a rhythm to measure the wall against. They stop UNDER the
	# coping and let it run over them: taken to the coping's own height they
	# stood through its 0.15 m overhang, which on the old map was 28 of its 32
	# wall overlaps and the one nobody would ever have seen.
	#
	# A PIER IS 1 m WIDE AND SITS AGAINST A WALL, so it makes a slot with
	# anything that comes near that wall — and a slot is the one thing the 8 m
	# rule cannot tolerate. So each run skips the stretches where something
	# butts the wall: the base wings, the gateway, and all eight edge blocks.
	var skip_ns: Array = []
	for b: Array in BLOCKS:
		skip_ns.append([b[0], b[1]])
	# ONLY ALONG THE ARENA. The revetment round B and C gets none: its rhythm is
	# the eight edge blocks standing against it, and a pier between two of them
	# would put a 3.5 m slot in the middle of an 8 m pocket.
	for k in 9:
		var x: float = -40.0 + k * PIER
		if _skipped(skip_ns, x):
			continue
		for s: float in [-1.0, 1.0]:
			box(Vector3(x - 0.5, s * A_Y, 0.0), Vector3(x + 0.5, s * (A_Y - 0.4), WALL_Z), OXIDE)
	# The end walls. Both base ends skip |y| 6..14 for the wings; the east end
	# skips the gateway as well.
	for k in 7:
		var y: float = -30.0 + k * PIER
		for s: float in [-1.0, 1.0]:
			if absf(y) + 0.5 > COURT and absf(y) - 0.5 < WING:
				continue
			if s > 0.0 and absf(y) - 0.5 < GATE:
				continue
			box(Vector3(s * A_X, y - 0.5, 0.0), Vector3(s * (A_X - 0.4), y + 0.5, WALL_Z), OXIDE)
	# The east revetment's piers, clear of the pad, which is flush against it.
	# The east revetment's, clear of the bunker floor — which is flush against
	# that wall and has to stay completely clear, so nothing may stand on it.
	for y: float in [20.0, 30.0]:
		for sy: float in [-1.0, 1.0]:
			box(Vector3(N_X1 - WALL - 0.4, sy * y - 0.5, 0.0),
					Vector3(N_X1 - WALL, sy * y + 0.5, WALL_Z), OXIDE)


func _skipped(ranges: Array, x: float) -> bool:
	for r: Array in ranges:
		if x + 0.5 > float(r[0]) and x - 0.5 < float(r[1]):
			return true
	return false


# ── The tower ───────────────────────────────────────────────────────────────

## ONE LANDMARK IN THE MIDDLE, tall enough to see from every corner and open
## enough to fight under. The deck is 4.6 m, over every piece of cover on the
## map, so it trades a commanding view for standing in the open on top of it.
##
## THE LANE RUNS CLEAN UNDERNEATH IT: 9.2 m between the legs and 4.2 m of
## headroom, so a Walker walks through the middle of the landmark rather than
## round it.
##
## The ramps come up the SIDES, not along the middle lane. A ramp lying in the
## lane you are meant to read the map down is, from eye height at the foot of
## it, a five-metre brown wall across the middle of everything. They are 6 m
## wide now and 18 m long — 14 degrees, where the old 12 m run was 21 — and
## they arrive on a deck EDGE rather than a corner, because a ramp that meets
## its landing at a corner leaves a navmesh the squad will not use.
func _tower() -> void:
	# The legs carry the deck, so they stop at its underside. Run them to the
	# deck's top and the deck is threaded onto four posts.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			box(Vector3(sx * (TOW_HALF - 1.4), sy * (TOW_HALF - 1.4), 0.0),
					Vector3(sx * (TOW_HALF - 0.4), sy * (TOW_HALF - 0.4), TOW_DECK - 0.4), OXIDE)
	box(Vector3(-TOW_HALF, -TOW_HALF, TOW_DECK - 0.4), Vector3(TOW_HALF, TOW_HALF, TOW_DECK),
			{"top": TREAD, "side": OXIDE, "bottom": OXIDE})
	# A parapet with the two ramp mouths left open. The x runs take the corners
	# and the y runs stop short of them.
	for sx: float in [-1.0, 1.0]:
		box(Vector3(sx * (TOW_HALF - 0.3), -TOW_HALF, TOW_DECK),
				Vector3(sx * TOW_HALF, TOW_HALF, TOW_DECK + 1.0), OXIDE)
		for sy: float in [-1.0, 1.0]:
			box(Vector3(sx * RAMP_HALF, sy * (TOW_HALF - 0.3), TOW_DECK),
					Vector3(sx * (TOW_HALF - 0.3), sy * TOW_HALF, TOW_DECK + 1.0), OXIDE)
	for s: float in [-1.0, 1.0]:
		# A WEDGE ON THE GROUND, not a slab sunk into it. solid() dedupes, so
		# the same shape as a six-point prism sits ON the floor instead of
		# 0.2 m through it, and walks identically.
		var far: float = s * TOW_RAMP
		var near: float = s * TOW_HALF
		solid([Vector3(-RAMP_HALF, far, 0.0), Vector3(RAMP_HALF, far, 0.0),
				Vector3(-RAMP_HALF, near, 0.0), Vector3(RAMP_HALF, near, 0.0),
				Vector3(-RAMP_HALF, near, TOW_DECK), Vector3(RAMP_HALF, near, TOW_DECK)],
				{"top": TREAD, "side": OXIDE, "bottom": OXIDE})
		# A KERB EACH SIDE so nothing walks off a 4.6 m drop. Its top follows
		# the ramp and its BOTTOM SITS ON THE FLOOR — follow the slope with both
		# and the kerb floats at the deck end with nothing under it. 1.0 m, not
		# the old 0.25: a quarter of a metre is inside the baker's climb and
		# inside a body's step, which is the one band of heights that bakes as a
		# wall the squad then walks through.
		for sx: float in [-1.0, 1.0]:
			var a: float = sx * RAMP_HALF
			var b: float = sx * (RAMP_HALF + 0.3)
			solid([Vector3(a, far, 0.0), Vector3(b, far, 0.0),
					Vector3(a, far, RAMP_KERB), Vector3(b, far, RAMP_KERB),
					Vector3(a, near, 0.0), Vector3(b, near, 0.0),
					Vector3(a, near, TOW_DECK + RAMP_KERB),
					Vector3(b, near, TOW_DECK + RAMP_KERB)], OXIDE)


## The derrick over the deck: silhouette only, and NO COLLISION, because a
## lattice with collision is a navmesh full of holes.
##
## A LATTICE IS MEMBERS MEETING AT NODES, and in brush geometry exactly one
## member at a node can be the one that runs through. Here it is the ring,
## because a ring is horizontal: the legs are cut at every ring and butt its
## level faces exactly, and the ring fills the node like a gusset. Drawn the
## obvious way — four legs straight up through four rings — this derrick alone
## was 44 of the old map's 248 overlapping pairs.
func _derrick() -> void:
	var foot := Vector3(TOW_HALF - 1.0, TOW_HALF - 1.0, TOW_DECK + 1.0)
	var head := Vector3(1.2, 1.2, TOW_TOP)
	var half: float = DERRICK_W * 0.5
	var rings: Array = []
	for k in 4:
		rings.append(TOW_DECK + 1.6 + k * 1.6)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var from: float = foot.z
			for k in rings.size() + 1:
				var to: float = (float(rings[k]) - half) if k < rings.size() else head.z
				var a := _on_leg(foot, head, from)
				var b := _on_leg(foot, head, to)
				slant_post(Vector3(sx * a.x, sy * a.y, a.z), Vector3(sx * b.x, sy * b.y, b.z),
						DERRICK_W, OXIDE)
				if k < rings.size():
					from = float(rings[k]) + half
	for z: float in rings:
		var r: float = _on_leg(foot, head, z).x
		for sx: float in [-1.0, 1.0]:
			beam(Vector3(-r, sx * r, z), Vector3(r, sx * r, z), DERRICK_W, OXIDE)
			# Short of the corners, which the run above already fills.
			beam(Vector3(sx * r, -r + DERRICK_W, z), Vector3(sx * r, r - DERRICK_W, z),
					DERRICK_W, OXIDE)
	box(Vector3(-1.6, -1.6, TOW_TOP), Vector3(1.6, 1.6, TOW_TOP + 1.2), TREAD)
	beam(Vector3(0.0, 0.0, TOW_TOP + 1.2), Vector3(0.0, 0.0, TOW_TOP + 4.0), 0.25, OXIDE)


## Where a derrick leg is at height z, for the one quadrant it is written in.
func _on_leg(foot: Vector3, head: Vector3, z: float) -> Vector3:
	return foot.lerp(head, (z - foot.z) / (head.z - foot.z))


# ── The bases ───────────────────────────────────────────────────────────────

## ONE BASE: two solid wings with a deck on top, an open court between them, and
## a ramp onto each wing from inboard. Both ends are the same shape at the same
## heights, so neither end is the better ground; they differ only in what they
## are made of, which is how you tell which end you are at.
##
## WHY NOT A DECK ON POSTS, as it was. Because the level exit stands at (37, 0)
## and the old deck put 2.6 m of ceiling over it, which a 3.00 m Walker cannot
## stand under — the squad's extraction point was unreachable by a third of the
## roster and nothing said so. The court is 12 m wide and open to the sky, and
## the wings are solid, so there is no low ceiling anywhere on this map.
##
## The wings reach the rampart. Stopped 2 m short, as they were, they left a
## 2 m slot running the full width of the arena behind them — a corridor a Rover
## can drive into and never turn round in.
func _base(s: float) -> void:
	var tex: Variant = BLOCK if s > 0.0 else OXIDE
	var i: float = s * BASE_IN
	var o: float = s * BASE_OUT
	for sy: float in [-1.0, 1.0]:
		box(Vector3(i, sy * COURT, 0.0), Vector3(o, sy * WING, BASE_DECK - 0.4), tex)
		box(Vector3(i, sy * COURT, BASE_DECK - 0.4), Vector3(o, sy * WING, BASE_DECK),
				{"top": TREAD, "side": tex, "bottom": tex})
		# The parapet round the deck, open where the ramp arrives. It stops
		# short of the rampart's coping, which overhangs 0.15 m into the wing.
		var back: float = s * (BASE_OUT - 0.5)
		for edge: float in [COURT, WING]:
			var near: float = sy * edge
			var far: float = sy * (edge - 0.3) if edge == WING else sy * (edge + 0.3)
			box(Vector3(i, minf(near, far), BASE_DECK),
					Vector3(back, maxf(near, far), BASE_DECK + 1.1), tex)
		# The ramp: 12 m of run for 3.0 m, arriving on the full 8 m width of
		# the wing's inner edge rather than on a corner of it.
		solid([Vector3(s * BR_IN, sy * COURT, 0.0), Vector3(s * BR_IN, sy * WING, 0.0),
				Vector3(i, sy * COURT, 0.0), Vector3(i, sy * WING, 0.0),
				Vector3(i, sy * COURT, BASE_DECK), Vector3(i, sy * WING, BASE_DECK)],
				{"top": TREAD, "side": tex, "bottom": tex})


## One piece of cover, and its twin half a map away. `s` is 1 for the piece as
## written and -1 for the same piece rotated 180 degrees about the centre.
func _cover(p: Array, s: float) -> void:
	var x: float = s * float(p[0])
	var y: float = s * float(p[1])
	var half_len: float = float(p[2]) * 0.5
	var half_thick: float = float(p[3]) * 0.5
	var h: float = float(p[4])
	var along_x: bool = p[5]
	var hx: float = half_len if along_x else half_thick
	var hy: float = half_thick if along_x else half_len
	# The wall stops where its cap starts. Built to full height with the cap
	# laid over the top, every piece on the old map had 0.12 m of two solids in
	# the same place — 56 of its 248 overlapping pairs, from one line.
	box(Vector3(x - hx, y - hy, 0.0), Vector3(x + hx, y + hy, h - 0.12), p[6])
	# A cap in a second material, so a 1.9 m wall and a 3.0 m wall do not read
	# as the same thing at fifty metres.
	box(Vector3(x - hx, y - hy, h - 0.12), Vector3(x + hx, y + hy, h),
			OXIDE if p[6] != OXIDE else CHALK)


# ── The bay behind the enemy blockhouse ─────────────────────────────────────

## ONE MORE BLOCK OF SPACE, out of the back of the enemy blockhouse. The squad
## enters the arena at x -28 facing east, fights up to the blockhouse at x 32..44
## — which is where the eliminate objective and the level exit are — and the
## gateway opens out of the back of its court into this: a 45 x 68 m bay with a
## 30 x 30 m floor for the bunker and four blocks round the edge of it.
##
## IT IS ONE SPACE, NOT TWO. The brief it was built from asked for a capture
## yard and a bunker clearing as separate compounds with a backstop between
## them; the human then asked for "just another block", and nothing in the
## gameplay needs the division — a capture node and an extraction point in the
## same bay is what the bunker is. If they ever do want separating, the wall
## goes at x 59, on the bunker floor's west edge, and takes 14 m off the
## approach.
##
## THE WAYS IN. The gateway on the centreline, and round either flank: the north
## and south bands, between the edge blocks' inner face at y 25 and the bunker
## floor's edge at y 15, are 10 m deep and run the length of the bay. The three
## 10 m slots between the arena wall, the two blocks and the east revetment are
## a fourth and fifth way to arrive, from behind the cover rather than across
## the open.
##
## EVERYTHING IS AT THE EDGE AND BUTTS THE REVETMENT. An 8 m rule means a
## free-standing wall needs 17 m of ground, and these bands are 10; a block hard
## against the fence leaves no sliver behind it and no slot beside it. Each
## block's face is the cover.
func _bay() -> void:
	for b: Array in BLOCKS:
		_edge_block(b)


## One block at the bay's edge: solid, flat-topped, butting the revetment so its
## back is not a place.
func _edge_block(b: Array) -> void:
	var x0: float = b[0]
	var x1: float = b[1]
	var sy: float = b[2]
	var h: float = b[3]
	# It stops at the revetment's COPING, not at the revetment: the coping
	# overhangs 0.15 m into the bay, and a block taken the whole way stands
	# through it.
	var back: float = sy * (A_Y - COPE_OUT)
	box(Vector3(x0, sy * BLOCK_IN, 0.0), Vector3(x1, back, h - 0.3), BLOCK)
	box(Vector3(x0, sy * BLOCK_IN, h - 0.3), Vector3(x1, back, h), OXIDE)
	# A buttress on the inner face: cover to stand behind that costs no width,
	# because it grows out of a solid rather than standing clear of one.
	var m: float = (x0 + x1) * 0.5
	box(Vector3(m - 1.5, sy * (BLOCK_IN - 1.5), 0.0), Vector3(m + 1.5, sy * BLOCK_IN, MID), CHALK)



# ── Silhouettes ─────────────────────────────────────────────────────────────

## Outside the fence, and none of it solid or reachable: it is there to give the
## sky an edge. The old arena was a box with nothing beyond it, which is what
## made 54 m feel like a corridor.
##
## THE EAST GROUP MOVED 46 m OUT. It stood at x 58 and 74, which is now the
## bunker floor — the one thing in this build that the new ground walked
## straight into.
func _skyline() -> void:
	var west: float = -A_X - 14.0
	var east: float = N_X1 + 14.0
	var side: float = A_Y + 14.0
	# Two tanks and a chimney off one end, a gantry and a shed off the other.
	for pair: Array in [[west, -1.0], [east, 1.0]]:
		var far: float = pair[0]
		var s: float = pair[1]
		cylinder(Vector3(far, s * 16.0, -1.5), 7.0, 11.0, 12, OXIDE)
		cylinder(Vector3(far, s * 16.0, 9.5), 7.4, 0.8, 12, TREAD)
		cylinder(Vector3(far + s * 16.0, -s * 6.0, -1.5), 3.0, 26.0, 10, BLOCK)
		box(Vector3(far - s * 6.0, -s * 22.0, -1.5), Vector3(far + s * 10.0, -s * 34.0, 7.5), BLOCK)
		box(Vector3(far - s * 7.0, -s * 21.0, 7.5), Vector3(far + s * 11.0, -s * 35.0, 8.7), OXIDE)
	# Pylons down both long sides, the length of the map. The post is the member
	# that runs through and each crossarm is two arms hung off it — run whole,
	# they crossed it inside the mast, which was all twelve of the old
	# silhouette's overlaps.
	for k in 6:
		var x: float = -24.0 + k * 24.0
		for s: float in [-1.0, 1.0]:
			beam(Vector3(x, s * side, -1.5), Vector3(x, s * side, 15.5), 0.7, OXIDE)
			for arm: Array in [[11.5, 4.0], [14.5, 2.6]]:
				for sx: float in [-1.0, 1.0]:
					beam(Vector3(x + sx * 0.35, s * side, arm[0]),
							Vector3(x + sx * float(arm[1]), s * side, arm[0]), 0.5, OXIDE)


# ── Bookkeeping, so a fault can be named ────────────────────────────────────

func _stage(what: String) -> void:
	_stages.append([_brushes.size(), what])


func _stage_of(b: int) -> String:
	var what := "?"
	for s: Array in _stages:
		if int(s[0]) > b:
			break
		what = s[1]
	return what


## Which brushes have collision, which is the only kind the squad can bump into
## and the only kind the width survey may count. Tracked here rather than
## guessed from the entity order, because a piece can have both: the tower is
## worldspawn with an illusionary derrick on top of it.
func brush(verts: Array, faces: Array, tex: Variant) -> void:
	super(verts, faces, tex)
	while _coll.size() < _brushes.size():
		_coll.append(_collides)


func entity(classname: String) -> void:
	super(classname)
	_collides = classname != "func_detail_illusionary" and classname != "func_illusionary"


# ── Nothing is written unless it is clean ───────────────────────────────────

func _check() -> bool:
	var ok := _anchors()
	var pairs := brush_overlaps()
	# SHOW=all when you are working through them; thirty is enough to see the
	# families without burying the summary.
	var show := 30 if OS.get_environment("SHOW") != "all" else pairs.size()
	for k in mini(pairs.size(), show):
		var row: Array = pairs[k]
		var s: AABB = row[2]
		print("FAIL  brush %d (%s) and %d (%s) share %.2f x %.2f x %.2f m at (%.1f, %.1f, %.1f)" % [
				row[0], _stage_of(row[0]), row[1], _stage_of(row[1]),
				s.size.x / UPM, s.size.y / UPM, s.size.z / UPM,
				s.get_center().x / UPM, s.get_center().y / UPM, s.get_center().z / UPM])
	if pairs.size() > show:
		print("FAIL  ... and %d more" % (pairs.size() - show))
	if pairs.size() > 0:
		print("FAIL  %d overlapping brush pair(s) — nothing written" % pairs.size())
		return false
	print("      %d brushes, none overlapping" % _brushes.size())
	if OS.get_environment("WIDTH") != "0":
		ok = _width() and ok
	return ok


## EVERY GAMEPLAY NODE THE LEVEL SCENE OWNS STANDS ON OPEN FLOOR. The scene is
## not this tool's to edit, so the only thing it can do about a spawn inside a
## wall is refuse to write the wall.
func _anchors() -> bool:
	var bad := 0
	for a: Array in ANCHORS:
		var p := Vector2(float(a[1]), float(a[2]))
		var hit := _solid_at(p, 1.5)
		if hit >= 0:
			print("FAIL  the %s at (%.0f, %.0f) is inside %s" % [a[0], p.x, p.y, _stage_of(hit)])
			bad += 1
	if bad > 0:
		print("FAIL  %d of the level's own nodes would be buried — nothing written" % bad)
		return false
	print("      %d level anchors, all on open floor" % ANCHORS.size())
	return true


## Which colliding brush, if any, holds the point (x, y) at height z. -1 for
## none. Metres in, brush index out.
func _solid_at(p: Vector2, z: float) -> int:
	var q := Vector3(p.x, p.y, z) * UPM
	for b in _brushes.size():
		if not bool(_coll[b]):
			continue
		var inside := true
		for face: Dictionary in _brushes[b]:
			var n: Vector3 = face.n
			if n.dot(q) - n.dot(face.poly[0]) > 0.0:
				inside = false
				break
		if inside:
			return b
	return -1


# ── The width survey ────────────────────────────────────────────────────────

## HOW WIDE IS THE NARROWEST ROUTE, MEASURED RATHER THAN INTENDED.
##
## Reachability cannot answer this. A path query takes no radius — Godot has no
## per-agent clearance, so map_get_path will route a 3.40 m Rover down a gap
## sized for a cat and never complain — and a corridor a Rover can enter and
## not turn round in reports as perfectly reachable. The only honest way to
## answer it is geometric, before the bake.
##
## So: rasterise every COLLIDING brush that stands between knee and head height
## onto a quarter-metre grid of the floor, measure each free cell's distance to
## the nearest solid, and then ask the question the right way round — not "how
## wide is this gap" but "how wide is the WIDEST route between these two
## places". That is a bottleneck problem, and the clean answer is to add cells
## to a union-find in order of decreasing clearance: the clearance at which two
## places first join is the widest bottleneck between them, and twice it is the
## width of the narrowest pinch on the best route there.
##
## Reported per destination, with two thresholds called out:
##   4.00 m of clearance  = an 8 m route, what the brief asks for everywhere.
##   1.90 m of clearance  = a 3.80 m circle, the least a 3.40 x 1.70 m Rover
##                          needs to turn round on the spot.
##
## THE DISTANCE TRANSFORM IS EXACT, not a chamfer. It was a 5 x 5 chamfer first
## and it read 3.675 m for a gap that is 4.000 by construction — 8% low, which
## at these thresholds is the difference between a pass and a failure, and a
## survey that cries wolf gets switched off. Half a cell is then taken off every
## reading, because the grid measures centre to centre and the solid's face is
## half a cell nearer than its centre.
const CELL := 0.25
const ROVER_TURN := 1.90
const WANT := 4.00

## Knee to head. A thing that blocks at none of these heights is not in the way:
## the floor's top is z 0 and a ramp's thin end is under the knee, which is
## right — you walk up it.
const AT := [0.6, 1.2, 1.8, 2.4, 3.0]

## Where the survey walks from, and what it has to reach. All in this file's
## axes.
##
## EVERY POINT SITS AT THE MIDDLE OF THE SPACE IT NAMES, because a destination's
## own clearance caps the route to it: the first run of this put the bunker
## floor's corner 2 m from the revetment and the survey reported a 4 m route to
## a 30 m square. A survey point 2 m from a wall measures the wall.
const WALKS := [
	["spawn", -28.0, 0.0], ["west court", -37.0, 0.0], ["under the tower", 0.0, 0.0],
	["arena north band", 0.0, 29.0], ["arena south band", -20.0, -29.0],
	["arena mid lane", 16.0, 0.0], ["east court", 37.0, 0.0],
	["the gateway", 45.0, 0.0], ["bay approach", 50.0, 0.0],
	["bay north band", 67.0, 20.0], ["bay south band", 67.0, -20.0],
	["bay west slot", 50.0, 29.0], ["bay north slot", 67.0, 29.0],
	["bay east slot", 84.0, -29.0], ["bunker floor centre", 74.0, 0.0],
	["bunker floor north-west", 63.0, 11.0], ["bunker floor south-east", 84.0, -10.0],
]


func _width() -> bool:
	var x0 := -A_X - WALL
	var y0 := -A_Y - WALL
	var w := int(ceilf((N_X1 - x0) / CELL))
	var h := int(ceilf(((A_Y + WALL) - y0) / CELL))
	# Buckets of candidate brushes, four metres a side, so a cell tests a
	# handful of brushes instead of four hundred.
	var bucket := {}
	var step := 4.0
	for b in _brushes.size():
		if not bool(_coll[b]):
			continue
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for face: Dictionary in _brushes[b]:
			for p: Vector3 in face.poly:
				lo = lo.min(p / UPM)
				hi = hi.max(p / UPM)
		if hi.z < AT[0] or lo.z > AT[AT.size() - 1]:
			continue
		for bx in range(int(floorf(lo.x / step)), int(floorf(hi.x / step)) + 1):
			for by in range(int(floorf(lo.y / step)), int(floorf(hi.y / step)) + 1):
				var key := Vector2i(bx, by)
				if not bucket.has(key):
					bucket[key] = []
				bucket[key].append(b)
	var blocked := PackedByteArray()
	blocked.resize(w * h)
	for j in h:
		var y: float = y0 + (j + 0.5) * CELL
		for i in w:
			var x: float = x0 + (i + 0.5) * CELL
			var near: Array = bucket.get(Vector2i(int(floorf(x / step)), int(floorf(y / step))), [])
			blocked[j * w + i] = 1 if _blocked(near, x, y) else 0
	var dist := _edt(blocked, w, h)
	# Union-find over the free cells in order of decreasing clearance: the
	# clearance at which two cells first join is the widest bottleneck between
	# them, which is what "the narrowest route I built" actually means.
	var order: Array = []
	for c in w * h:
		if blocked[c] == 0:
			order.append(c)
	order.sort_custom(func(a: int, b: int) -> bool: return dist[a] > dist[b])
	var parent := PackedInt32Array()
	parent.resize(w * h)
	for c in w * h:
		parent[c] = -1
	var start := -1
	var want := {}
	for k in WALKS.size():
		var a: Array = WALKS[k]
		var i := int((float(a[1]) - x0) / CELL)
		var j := int((float(a[2]) - y0) / CELL)
		var c := j * w + i
		if i < 0 or i >= w or j < 0 or j >= h or blocked[c] == 1:
			print("FAIL  the survey point '%s' at (%.0f, %.0f) is inside something" % [a[0], a[1], a[2]])
			return false
		if a[0] == "spawn":
			start = c
		else:
			want[c] = a[0]
	var got: Array = []
	for c: int in order:
		parent[c] = c
		for d: int in [c - 1, c + 1, c - w, c + w]:
			if d < 0 or d >= w * h or parent[d] < 0:
				continue
			if (d == c - 1 and c % w == 0) or (d == c + 1 and d % w == 0):
				continue
			_union(parent, c, d)
		if start < 0 or parent[start] < 0:
			continue
		var root := _find(parent, start)
		for q: int in want.keys():
			if parent[q] >= 0 and _find(parent, q) == root:
				got.append([want[q], dist[c]])
				want.erase(q)
	print("")
	print("      THE WIDEST ROUTE FROM THE SPAWN — twice the clearance is the")
	print("      width of the narrowest pinch on it. 8.00 m is the target and")
	print("      3.80 m is the least a Rover can turn round in.")
	print("      %-22s %10s %9s" % ["to", "route", "verdict"])
	var worst := INF
	for r: Array in got:
		var width: float = float(r[1]) * 2.0
		worst = minf(worst, width)
		print("      %-22s %8.2f m %9s" % [r[0], width,
				"ok" if width >= WANT * 2.0 - 0.01 else ("TURN" if width >= ROVER_TURN * 2.0 else "TIGHT")])
	for q: int in want.keys():
		print("FAIL  %s is not reachable on foot at all" % want[q])
	if not want.is_empty():
		return false
	print("      the narrowest route anywhere in the survey is %.2f m" % worst)
	if worst < ROVER_TURN * 2.0:
		print("FAIL  a Rover cannot turn round on that — nothing written")
		return false
	if worst < WANT * 2.0 - 0.01:
		print("      WARN  under the 8 m the brief asks for; see the table above")
	return true


func _blocked(near: Array, x: float, y: float) -> bool:
	for b: int in near:
		for z: float in AT:
			var q := Vector3(x, y, z) * UPM
			var inside := true
			for face: Dictionary in _brushes[b]:
				var n: Vector3 = face.n
				if n.dot(q) - n.dot(face.poly[0]) > 0.0:
					inside = false
					break
			if inside:
				return true
	return false




func _find(parent: PackedInt32Array, c: int) -> int:
	var r := c
	while parent[r] != r:
		r = parent[r]
	while parent[c] != r:
		var up := parent[c]
		parent[c] = r
		c = up
	return r


func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra


## EXACT EUCLIDEAN DISTANCE from each free cell to the nearest blocked one, in
## metres, less half a cell. Felzenszwalb's separable transform: the squared
## distance along each row first, then the lower envelope of those parabolas
## down each column. Exact, and linear in the number of cells.
##
## Outside the grid never arises: the grid is exactly the playable floor and
## every edge of that floor is under a wall, so the border cells are blocked.
func _edt(blocked: PackedByteArray, w: int, h: int) -> PackedFloat32Array:
	var big := 1.0e6
	var gx := PackedFloat32Array()
	gx.resize(w * h)
	for j in h:
		var row: int = j * w
		var best := big
		for i in w:
			best = 0.0 if blocked[row + i] == 1 else best + 1.0
			gx[row + i] = best
		best = big
		for i in range(w - 1, -1, -1):
			best = 0.0 if blocked[row + i] == 1 else best + 1.0
			gx[row + i] = minf(gx[row + i], best)
	var out := PackedFloat32Array()
	out.resize(w * h)
	var f := PackedFloat32Array()
	f.resize(h)
	var v := PackedInt32Array()
	v.resize(h)
	var z := PackedFloat32Array()
	z.resize(h + 1)
	for i in w:
		for j in h:
			var g: float = gx[j * w + i]
			f[j] = g * g
		var k := 0
		v[0] = 0
		z[0] = -INF
		z[1] = INF
		for q in range(1, h):
			var s: float = _cross(f, v, q, k)
			while s <= z[k]:
				k -= 1
				s = _cross(f, v, q, k)
			k += 1
			v[k] = q
			z[k] = s
			z[k + 1] = INF
		k = 0
		for q in h:
			while z[k + 1] < float(q):
				k += 1
			var dy: float = float(q - v[k])
			out[q * w + i] = maxf(0.0, sqrt(f[v[k]] + dy * dy) - 0.5) * CELL
	return out


## Where the parabolas rooted at q and at v[k] cross.
func _cross(f: PackedFloat32Array, v: PackedInt32Array, q: int, k: int) -> float:
	var p: int = v[k]
	return ((f[q] + float(q * q)) - (f[p] + float(p * p))) / float(2 * q - 2 * p)
