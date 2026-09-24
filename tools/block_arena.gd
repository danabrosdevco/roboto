extends "res://tools/block_fortress.gd"

# ─────────────────────────────────────────────
# BLOCK ARENA — the proving ground: a replacement for the arena, as one map.
#
#   maps/proving/proving_level.map
#
#   godot --headless --path . --script res://tools/block_arena.gd -- maps
#   godot --headless --path . --script res://tools/block_arena.gd -- maps --force
#
# WHAT WAS WRONG WITH THE ARENA. It is 88 x 54 m of grass with eighty-odd
# blocks on it, and three things made it hard to read:
#
#   1. EVERYTHING WAS 4 m TALL. Every cover wall, every pillar. Nothing could
#      be seen over, so the whole map was one height and you could not tell a
#      thing you shoot over from a thing you hide behind.
#   2. THE COVER WAS THE SAME COLOUR AS THE GROUND. All of it was
#      Metal_04, a mossy green-grey, on green grass. It vanished.
#   3. NOTHING TO NAVIGATE BY. Eighty-one near-identical blocks in a
#      near-uniform field. No landmark, so no way to say where you are.
#
# SO: same footprint, three heights, cover that contrasts with the grass, and
# three landmarks — a tower in the middle and a base at each end.
#
#   LOW  1.3 m   shoot over it standing. Most of the map.
#   MID  1.9 m   full cover standing. You cannot see over it.
#   TALL 3.0 m   a sight-line blocker. Used at four places only.
#
# Nothing is thicker than 1.4 m. The old map had 3.5 m square pillars, which
# is not cover, it is a building.
#
# MOBA READ. Three lanes run the length of it, cut into the grass as sand so
# you can see them from anywhere, with a rough strip between each pair to
# flank through. Cover is placed once and stamped twice, rotated 180 degrees
# about the centre, so the two halves are identical to play.
# ─────────────────────────────────────────────

# ── The field ──
const FIELD_X := 44.0    # half the length: 88 m, as the arena is
const FIELD_Y := 27.0    # half the width: 54 m
const WALL := 1.0
const WALL_Z := 3.5      # was 4.5, and you could see nothing over it

# ── Lanes ──
const LANE_END := 40.0
const MID_HALF := 4.0    # the middle lane is 8 m wide
const SIDE_MID := 17.0   # the side lanes are centred here, 10 m wide
const SIDE_HALF := 3.0   # the side lanes are 6 m wide
const CROSS := 18.0      # the two cross-lanes, 8 m wide, at x +/- 18

# ── The tower ──
const TOW_HALF := 6.0    # 12 m square
const TOW_DECK := 4.6    # you stand here, over every piece of cover below
const TOW_TOP := 12.0    # and the derrick above it is the thing you steer by
const TOW_RAMP := 18.0   # the ramps run in from x +/- 18
const RAMP_HALF := 2.0   # 4 m wide

# ── The bases ──
const BASE_IN := 32.0    # the base is x 32..42
const BASE_OUT := 42.0
const BASE_HALF := 8.0   # and y -8..8
const BASE_DECK := 3.0
const BR_IN := 36.0      # its ramp: x 36..40, coming in from the side lane
const BR_OUT := 40.0
const BR_FAR := 18.0

# ── Textures ──
## The grass stays. It is the one thing about the arena that already looked
## right, and the whole palette below is chosen to sit against it.
const TURF := "textures_pack/Grass_19-256x256"
## A worn track, for the lanes. Not green is the whole trick — you can see the
## map's shape while standing in it. It started as Dirt_12, a pale sand, and
## under this sun every lane and every apron clipped to white paper. Khaki was
## no better. Dark earth carries the same contrast against grass and is the
## only end of the range this environment does not blow out.
const PATH := "textures_pack/Dirt_04-256x256"
## Blue-grey for the boundary, same as the sight-line blockers: one colour
## for "you do not get past this". Stone_05 was here first and its inner face
## burned out white, which put a bright band round the whole horizon.
const RAMPART := "PSX_Textures/concrete_wall_12_1"
## Dark riveted plate for anything you stand on that is not the ground. The
## bright treadplate this was first went the same way as the sand.
const TREAD := "PSX_Textures/metal_floor_1@0.5"
## Grey concrete for cover and blue-grey for the four sight-line blockers, so
## the thing you cannot shoot past is a different colour from the thing you
## can. The point of both is that they are NOT green: the arena's cover was
## mossy metal on grass and it disappeared.
const CHALK := "PSX_Textures/concrete_tx_5"
const BLOCK := "PSX_Textures/concrete_wall_12_1"
const OXIDE := "PSX_Textures/metal_wall_5"

## 1.3 m, not the 1.0 m this started at. CoverPointSpawner probes for a wall
## at 1.2 m in its very first test, so anything shorter than that generates no
## cover point at all and the AI never uses it — see the note in the report.
const LOW := 1.3
const MID := 1.9
const TALL := 3.0

## Cover, written once for one half and stamped twice — the second time
## rotated 180 degrees about the centre, so neither end has the better ground.
## [x, y, length, thickness, height, along_x, texture]
const COVER := [
	# The middle lane, from the base out to the tower.
	# Two blockers with a four-metre gap on the centreline rather than one slab
	# across it: you want to SEE the tower from your own end and have somewhere
	# to step out of the shot, not to have the view bricked up.
	[30.0, 5.0, 6.0, 1.0, TALL, false, BLOCK],
	[30.0, -5.0, 6.0, 1.0, TALL, false, BLOCK],
	[24.0, 5.0, 7.0, 0.6, LOW, true, CHALK],
	[24.0, -5.0, 7.0, 0.6, LOW, true, CHALK],
	[17.0, 3.4, 4.0, 1.4, 1.4, true, OXIDE],
	[17.0, -3.4, 4.0, 1.4, 1.4, true, OXIDE],
	[11.0, 4.5, 3.0, 0.6, MID, false, CHALK],
	[11.0, -4.5, 3.0, 0.6, MID, false, CHALK],
	# The rough strip between the middle lane and the north lane.
	[30.0, 9.0, 6.0, 0.6, MID, true, CHALK],
	[24.0, 8.0, 5.0, 0.6, LOW, false, CHALK],
	[16.0, 10.0, 5.0, 1.2, 1.2, true, OXIDE],
	[9.0, 8.0, 4.0, 0.6, MID, false, CHALK],
	# The north lane.
	[30.0, 17.0, 6.0, 0.8, TALL, false, BLOCK],
	[22.0, 13.5, 8.0, 0.6, LOW, true, CHALK],
	[22.0, 20.5, 8.0, 0.6, LOW, true, CHALK],
	[14.0, 17.0, 5.0, 1.2, 2.4, false, OXIDE],
	[7.0, 13.5, 6.0, 0.6, MID, true, CHALK],
	[7.0, 20.5, 6.0, 0.6, LOW, true, CHALK],
	# The rough strip on the other side of the middle lane.
	[30.0, -9.0, 6.0, 0.6, LOW, true, CHALK],
	[24.0, -8.0, 5.0, 0.6, MID, false, CHALK],
	[16.0, -10.0, 5.0, 1.2, 1.2, true, OXIDE],
	[9.0, -8.0, 4.0, 0.6, LOW, false, CHALK],
	# The south lane.
	[30.0, -17.0, 6.0, 0.8, TALL, false, BLOCK],
	[22.0, -13.5, 8.0, 0.6, LOW, true, CHALK],
	[22.0, -20.5, 8.0, 0.6, MID, true, CHALK],
	[14.0, -17.0, 5.0, 1.2, 2.4, false, OXIDE],
	[7.0, -13.5, 6.0, 0.6, LOW, true, CHALK],
	[7.0, -20.5, 6.0, 0.6, MID, true, CHALK],
]

var _boxes: Array = []   # every cover footprint, for the overlap check


func _initialize() -> void:
	var base := ""
	var force := false
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
	if base == "":
		print("usage: godot --headless --path . --script res://tools/block_arena.gd -- maps [--force]")
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
	_boxes = []
	_proving()
	if not _check_clearance():
		quit(1)
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string(_map_text())
	f.close()
	print("      %-24s %3d brushes  %s" % ["proving_level", _brushes.size(), _extent_text()])
	print("BLOCK ARENA DONE")
	quit()


func _proving() -> void:
	_ground()
	_lanes()
	_tower()
	for s: float in [1.0, -1.0]:
		_base(s)
	for piece: Array in COVER:
		_cover(piece, 1.0)
		_cover(piece, -1.0)
	_skyline()


## The grass and the wall round it. The wall is a metre lower than the arena's
## and capped, so from inside you read a built edge and a sky above it rather
## than a grey band with nothing beyond.
func _ground() -> void:
	# The apron first: bare ground out to the skyline, two metres below the
	# field. Without it the tanks and pylons outside the wall hang in the air,
	# which is exactly how the first build came out.
	box(Vector3(-100.0, -70.0, -3.5), Vector3(100.0, 70.0, -1.5), {"top": PATH, "side": RAMPART, "bottom": RAMPART})
	box(Vector3(-FIELD_X - WALL, -FIELD_Y - WALL, -1.5), Vector3(FIELD_X + WALL, FIELD_Y + WALL, 0.0),
			{"top": TURF, "side": RAMPART, "bottom": RAMPART})
	for s: float in [-1.0, 1.0]:
		box(Vector3(-FIELD_X - WALL, s * FIELD_Y, 0.0), Vector3(FIELD_X + WALL, s * (FIELD_Y + WALL), WALL_Z), RAMPART)
		box(Vector3(s * FIELD_X, -FIELD_Y, 0.0), Vector3(s * (FIELD_X + WALL), FIELD_Y, WALL_Z), RAMPART)
		# The cap, and piers to give the wall a rhythm to measure it against.
		box(Vector3(-FIELD_X - WALL, s * FIELD_Y - s * 0.15, WALL_Z),
				Vector3(FIELD_X + WALL, s * (FIELD_Y + WALL), WALL_Z + 0.35), OXIDE)
		box(Vector3(s * FIELD_X - s * 0.15, -FIELD_Y, WALL_Z),
				Vector3(s * (FIELD_X + WALL), FIELD_Y, WALL_Z + 0.35), OXIDE)
	for k in 9:
		var x := -40.0 + k * 10.0
		for s: float in [-1.0, 1.0]:
			box(Vector3(x - 0.5, s * FIELD_Y, 0.0), Vector3(x + 0.5, s * (FIELD_Y - 0.4), WALL_Z + 0.35), OXIDE)
	for k in 5:
		var y := -20.0 + k * 10.0
		for s: float in [-1.0, 1.0]:
			box(Vector3(s * FIELD_X, y - 0.5, 0.0), Vector3(s * (FIELD_X - 0.4), y + 0.5, WALL_Z + 0.35), OXIDE)


## THE LANES, cut into the grass as sand. This is the thing the arena did not
## have: standing anywhere on the map you can see where the routes go, because
## they are a different colour under your feet. Three down the length, two
## across, and an apron at each base.
##
## The grass is the field and the lanes are paths through it, not the other
## way round: at twelve and ten metres wide the sand ate the ground and left
## the grass as edging, which is backwards for the one texture here that was
## already right.
##
## They are plates 0.06 m proud, which is nothing to walk over and nothing to
## the navmesh, but reads as a worn path rather than as paint.
func _lanes() -> void:
	# Sloped to the grass, not stepped onto it. A 0.06 m lip is nothing to look
	# at and a wall to a robot: move_and_slide has no step-up, so a vertical
	# face of any height stops a body dead however low it is.
	for y: float in [0.0, SIDE_MID, -SIDE_MID]:
		var h: float = MID_HALF if y == 0.0 else SIDE_HALF
		slope_slab(-LANE_END, y - h, LANE_END, y + h, 0.06, 0.4, PATH)
	for s: float in [-1.0, 1.0]:
		slope_slab(s * CROSS - 2.5, -SIDE_MID - SIDE_HALF, s * CROSS + 2.5,
				SIDE_MID + SIDE_HALF, 0.06, 0.4, PATH)
		slope_slab(minf(s * BASE_IN - s * 3.0, s * BASE_OUT), -BASE_HALF + 2.0,
				maxf(s * BASE_IN - s * 3.0, s * BASE_OUT), BASE_HALF - 2.0, 0.06, 0.4, PATH)


## THE TOWER. One landmark in the middle of the map, tall enough to see from
## every corner of it and open enough to fight under. It is what the arena was
## missing: somewhere to point at.
##
## The deck is 4.6 m, which is over every piece of cover on the map, so it
## trades a commanding view for standing in the open on top of it. A ramp
## comes in from each side along the middle lane, and both arrive on a deck
## EDGE, four metres wide — a ramp that meets its landing at a corner leaves a
## navmesh the squad will not use.
func _tower() -> void:
	# Legs, and the deck they carry.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			box(Vector3(sx * (TOW_HALF - 1.4), sy * (TOW_HALF - 1.4), 0.0),
					Vector3(sx * (TOW_HALF - 0.4), sy * (TOW_HALF - 0.4), TOW_DECK), OXIDE)
	box(Vector3(-TOW_HALF, -TOW_HALF, TOW_DECK - 0.4), Vector3(TOW_HALF, TOW_HALF, TOW_DECK),
			{"top": TREAD, "side": OXIDE, "bottom": OXIDE})
	# A parapet, with the two ramp mouths left open.
	for sx: float in [-1.0, 1.0]:
		box(Vector3(sx * (TOW_HALF - 0.3), -TOW_HALF, TOW_DECK), Vector3(sx * TOW_HALF, TOW_HALF, TOW_DECK + 1.0), OXIDE)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			box(Vector3(sx * RAMP_HALF, sy * (TOW_HALF - 0.3), TOW_DECK),
					Vector3(sx * TOW_HALF, sy * TOW_HALF, TOW_DECK + 1.0), OXIDE)
	# THE RAMPS COME UP THE SIDES, not along the middle lane. A twelve-metre
	# ramp lying in the lane you are meant to read the map down is, from eye
	# height at the foot of it, a five-metre brown wall across the middle of
	# everything — which is exactly how the first build came out. Off to the
	# flanks they leave the lane running clean underneath the tower.
	for s: float in [-1.0, 1.0]:
		var run := "-y" if s > 0.0 else "+y"
		ramp(-RAMP_HALF, s * TOW_HALF, RAMP_HALF, s * TOW_RAMP, -0.2, 0.0, TOW_DECK, run, {"top": TREAD, "side": OXIDE, "bottom": OXIDE})
		# A rail each side so nobody walks off it. 0.25 m proud, not the 1.1 m
		# it started at: a kerb that tall on a climbing ramp becomes a two-metre
		# wall down the middle of the map, and walled off the one lane the whole
		# layout is meant to be read from.
		for sx: float in [-1.0, 1.0]:
			var pts: Array = []
			for pair: Array in [[s * TOW_RAMP, 0.0], [s * TOW_HALF, TOW_DECK]]:
				for x: float in [sx * RAMP_HALF, sx * (RAMP_HALF + 0.3)]:
					pts.append(Vector3(x, pair[0], pair[1] - 0.45))
					pts.append(Vector3(x, pair[0], pair[1] + 0.25))
			solid(pts, OXIDE)
	# The derrick over the deck: silhouette only, and no collision, because a
	# lattice with collision is a navmesh full of holes.
	no_collision()
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			beam(Vector3(sx * (TOW_HALF - 1.0), sy * (TOW_HALF - 1.0), TOW_DECK + 1.0),
					Vector3(sx * 1.2, sy * 1.2, TOW_TOP), 0.35, OXIDE)
	for k in 4:
		var z: float = TOW_DECK + 1.6 + k * 1.6
		var t: float = float(k + 1) / 5.0
		var r: float = lerpf(TOW_HALF - 1.0, 1.2, t)
		for sx: float in [-1.0, 1.0]:
			beam(Vector3(-r, sx * r, z), Vector3(r, sx * r, z), 0.22, OXIDE)
			beam(Vector3(sx * r, -r, z), Vector3(sx * r, r, z), 0.22, OXIDE)
	box(Vector3(-1.6, -1.6, TOW_TOP), Vector3(1.6, 1.6, TOW_TOP + 1.2), TREAD)
	beam(Vector3(0.0, 0.0, TOW_TOP + 1.2), Vector3(0.0, 0.0, TOW_TOP + 4.0), 0.25, OXIDE)
	entity("func_detail")


## ONE BASE. Both ends are the same shape at the same heights — a deck at 3 m
## on posts, open underneath, with a ramp up from one side lane — so neither
## end is the better ground. They differ only in what they are made of, which
## is how you tell which end you are at.
##
## The ramp comes in off the SIDE lane rather than the middle, so taking the
## high ground at a base is a flank rather than a frontal walk.
func _base(s: float) -> void:
	var tex: Variant = BLOCK if s > 0.0 else OXIDE
	var deck_tex := {"top": TREAD, "side": tex, "bottom": tex}
	var i: float = s * BASE_IN
	var o: float = s * BASE_OUT
	# Posts, a back wall, and the deck over them.
	for sy: float in [-1.0, 1.0]:
		for x: float in [BASE_IN + 1.0, BASE_OUT - 1.0]:
			box(Vector3(s * x - 0.5, sy * (BASE_HALF - 1.0) - 0.5, 0.0),
					Vector3(s * x + 0.5, sy * (BASE_HALF - 1.0) + 0.5, BASE_DECK), tex)
	box(Vector3(o, -BASE_HALF, 0.0), Vector3(s * (BASE_OUT - 0.8), BASE_HALF, BASE_DECK + 1.2), tex)
	box(Vector3(i, -BASE_HALF, BASE_DECK - 0.4), Vector3(o, BASE_HALF, BASE_DECK), deck_tex)
	# The parapet round the deck, open where the ramp arrives.
	box(Vector3(i, -BASE_HALF, BASE_DECK), Vector3(s * (BASE_IN + 0.4), BASE_HALF, BASE_DECK + 1.1), tex)
	box(Vector3(i, -BASE_HALF, BASE_DECK), Vector3(o, -(BASE_HALF - 0.4), BASE_DECK + 1.1), tex)
	box(Vector3(i, BASE_HALF - 0.4, BASE_DECK), Vector3(s * BR_IN, BASE_HALF, BASE_DECK + 1.1), tex)
	box(Vector3(s * BR_OUT, BASE_HALF - 0.4, BASE_DECK), Vector3(o, BASE_HALF, BASE_DECK + 1.1), tex)
	# The ramp, out into the side lane. It arrives on a four-metre edge of the
	# deck, not on a corner of it.
	ramp(s * BR_IN, BASE_HALF, s * BR_OUT, BR_FAR, -0.2, BASE_DECK, 0.0, "+y", {"top": TREAD, "side": tex, "bottom": tex})
	for sx: float in [0.0, 1.0]:
		var x: float = s * (BR_IN + (BR_OUT - BR_IN) * sx)
		var pts: Array = []
		for pair: Array in [[BASE_HALF, BASE_DECK], [BR_FAR, 0.0]]:
			for d: float in [0.0, s * 0.3]:
				pts.append(Vector3(x - s * 0.3 * sx + d, pair[0], pair[1] - 0.45))
				pts.append(Vector3(x - s * 0.3 * sx + d, pair[0], pair[1] + 0.25))
		solid(pts, tex)


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
	box(Vector3(x - hx, y - hy, 0.0), Vector3(x + hx, y + hy, h), p[6])
	# A cap in a second material, so a 1 m wall and a 1.9 m wall do not read
	# as the same thing at fifty metres.
	box(Vector3(x - hx, y - hy, h - 0.12), Vector3(x + hx, y + hy, h), OXIDE if p[6] != OXIDE else CHALK)
	_boxes.append([x - hx, y - hy, x + hx, y + hy, h])


## Silhouettes outside the wall. The arena was a box with nothing beyond it,
## which is what made 54 m feel like a corridor. None of this is solid and
## none of it is reachable; it is there to give the sky an edge.
func _skyline() -> void:
	no_collision()
	var far: float = FIELD_X + 14.0
	# Everything here stands on the apron at -1.5 m, not on the field.
	var side: float = FIELD_Y + 14.0
	# Two tanks and a chimney off one end, a gantry and a shed off the other.
	for s: float in [-1.0, 1.0]:
		cylinder(Vector3(s * far, s * 16.0, -1.5), 7.0, 11.0, 12, OXIDE)
		cylinder(Vector3(s * far, s * 16.0, 9.5), 7.4, 0.8, 12, TREAD)
		cylinder(Vector3(s * (far + 16.0), -s * 6.0, -1.5), 3.0, 26.0, 10, BLOCK)
		box(Vector3(s * (far - 6.0), -s * 22.0, -1.5), Vector3(s * (far + 10.0), -s * 34.0, 7.5), BLOCK)
		box(Vector3(s * (far - 7.0), -s * 21.0, 7.5), Vector3(s * (far + 11.0), -s * 35.0, 8.7), OXIDE)
		# A pylon out past the long wall.
		for k in 3:
			var x: float = -24.0 + k * 24.0
			beam(Vector3(x, s * side, -1.5), Vector3(x, s * side, 15.5), 0.7, OXIDE)
			beam(Vector3(x - 4.0, s * side, 11.5), Vector3(x + 4.0, s * side, 11.5), 0.5, OXIDE)
			beam(Vector3(x - 2.6, s * side, 14.5), Vector3(x + 2.6, s * side, 14.5), 0.5, OXIDE)


## Every piece of cover against every other. Measured, not eyeballed: the last
## time a placement pass went out without this it put bridges through each
## other. Cover that touches is fine; cover that overlaps is a modelling error
## and shows as a seam.
func _check_clearance() -> bool:
	var bad := 0
	for i in _boxes.size():
		for j in range(i + 1, _boxes.size()):
			var a: Array = _boxes[i]
			var b: Array = _boxes[j]
			var ox: float = minf(a[2], b[2]) - maxf(a[0], b[0])
			var oy: float = minf(a[3], b[3]) - maxf(a[1], b[1])
			if ox > 0.01 and oy > 0.01:
				bad += 1
				print("FAIL  cover at (%.1f, %.1f) and (%.1f, %.1f) overlap by %.2f x %.2f m" % [
						(a[0] + a[2]) * 0.5, (a[1] + a[3]) * 0.5,
						(b[0] + b[2]) * 0.5, (b[1] + b[3]) * 0.5, ox, oy])
	if bad > 0:
		print("FAIL  %d overlapping pair(s) — nothing written" % bad)
		return false
	print("      %d cover pieces, none overlapping" % _boxes.size())
	return true
