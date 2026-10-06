extends "res://tools/block_suburban.gd"

# ─────────────────────────────────────────────
# BLOCK TRENCH — a trench-warfare kit: the trench proper, a sunken road, craters
# and wire for the ground between the lines. Built for SALIENT, where the
# middle of no-man's-land was bare mud and crossing it was a walk into fire.
#
#   maps/blocks/trench/trench_*.map     — the trench: runs, traverses, corners,
#       a T, a fire bay, a dugout, a sap head, a cave-in and the end ramps.
#   maps/blocks/trench/duckboard_run.map
#   maps/blocks/trench/sunken_road_*.map — the road cut, its ramps, the blown span.
#   maps/blocks/trench/crater_*.map, wire_belt_*.map — no-man's-land.
#   maps/blocks/trench/tank_ditched.map, op_tower_ruin.map — landmarks.
#   maps/blocks/trench/trench_kit.json  — what the level builder needs to know
#       about each piece (see MANIFEST, below). GENERATED. Never hand-edited.
#
#   godot --headless --path . --script res://tools/block_trench.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_trench.gd -- maps/blocks --force [names]
#   godot --path . --script res://tools/block_prefabs.gd -- maps/blocks/trench --force
#
# THE NUMBERS ARE NOT FREE. They fall out of the navmesh baker, and every one
# of them was worked through before a brush was drawn. (docs/ASSETS.md section 4
# and 5 are the source; salient bakes with agent_radius 0.5, agent_height 1.8,
# agent_max_climb 0.5, and the squad steps over 0.45.)
#
#   floor width 3.0   Recast erodes the agent radius off EACH side, so 3.0
#                     bakes a 2.0 m ribbon. Anything under 2.0 wide bakes
#                     nothing at all and the trench becomes a wall — the same
#                     arithmetic that stopped a 0.34 m stair tread baking.
#   depth 1.4         under the parapet line for a 1.8 m agent, and 2.8x the
#                     0.5 climb, so the mesh cannot spill over the lip.
#   parapet 0.6       NOT 0.3. 0.3 sits in the band the baker will not climb
#                     (over 0.25) and the body steps straight over (under 0.45)
#                     -- the mesh stops at it and the squad walks onto it and
#                     into a 1.4 m trench. That exact mistake is live in the
#                     canal coping. 0.6 is over the step-over AND over the
#                     baker's climb, so nobody crosses it by accident.
#   parapet 0.8 thick reads as spoil, and keeps the mesh edge well clear of the
#                     drop (the erosion alone is 0.5).
#   embrasure         the parapet cut down to GROUND LEVEL over 1.6 m, every
#                     8 m. Standing on the floor the eye is 1.65 and the floor
#                     is -1.4, so the eye is 0.25 m above ground: an embrasure
#                     top at 0.0 is 1.4 m above the floor and it can see out.
#                     With the parapet up it is 2.0 m above the floor and it
#                     cannot. THAT DIFFERENCE IS THE WHOLE POINT OF A TRENCH.
#   end ramps         1.4 m over 5.0 m, about 16 degrees, the full 3.0 wide.
#   duckboards        0.1 proud of the floor: under the baker's climb, so the
#                     mesh flows straight over them and they cost nothing.
#
# EVERY TRENCH PIECE CONNECTS. Floor -1.4, floor width 3.0, parapet 0.6 x 0.8,
# identical on every piece, so any two butt exactly. Touching faces are correct
# and interpenetration is the one forbidden thing, so every piece is built from
# a floor plan (see _body) and not from boxes that happen to meet.
#
# HOW THE GROUND COMES INTO IT. Salient's ground is a heightfield, and a brush
# cannot dig a heightfield: laid over it, a trench floor sits UNDER the terrain
# mesh and the trench is a sealed box. So each piece also says where the ground
# must be lowered ("dig") and the level builder turns that into terrain
# stamps. The slab and the walls are founded a metre below the floor so the
# lowered ground sits INSIDE them, never beside them. The dig stops 0.3 m
# outside each wall: far enough that the 1.25 m terrain samples cannot leave a
# sliver of ground standing up inside the trench, close enough that the moat
# against the wall's outer face stays a skirt and not a ditch.
#
# MANIFEST. Everything the builder must know about a piece -- where it joins
# the next one, how much ground it takes, where the ground must be dug -- is
# recorded HERE, as the piece is built, and written to trench_kit.json. The
# builder reads it. Typing "a run is 32 m long" into the builder as well would
# be the first coordinate to drift.
# ─────────────────────────────────────────────

# ── The section ──────────────────────────────────────────────────────────────

const T_FLOOR := -1.4
const T_HALF := 1.5            ## half the floor width
const T_WALL := 0.8            ## the revetted wall and the spoil above it
const T_OUT := T_HALF + T_WALL
const T_PARAPET := 0.6         ## wall top above ground
const T_FOOT := 1.0            ## slab and walls reach this far under the floor
const T_EMBR := 1.6            ## width of an embrasure
const T_EMBR_PITCH := 8.0
const T_RAMP := 5.0
## The dig stops this far outside a wall. See the header.
const T_MOAT := 0.3
## Terrain target under a trench floor: 0.6 under its top, so the slab (a metre
## thick) swallows the ground completely.
const T_SLOT_BELOW := 0.6
## An earthwork that meets the ground ends this far proud of it. Flush would be
## two surfaces at one height and the terrain crawls through the brush.
const T_PROUD := 0.05

## The sunken road. 8 m of floor, 2.5 m down.
const R_HALF := 4.0
const R_FLOOR := -2.5
const R_RAMP := 12.0
const R_BLOWN := 40.0
const R_BED := -0.5            ## the rubble bed the blown span is filled up to

## Roofed pieces: floor to underside is 2.2, over the agent's 1.8.
const T_ROOF_UNDER := 0.8
const T_ROOF_TOP := 1.3

const EARTH_FLOOR := {"top": DIRT, "side": DIRT, "bottom": DIRT}
const EARTH_WALL := {"top": DIRT, "side": PLANK, "bottom": DIRT}
const ROAD_FLOOR := {"top": DIRT, "side": DIRT, "bottom": DIRT}
const ROAD_WALL := {"top": DIRT, "side": "PSX_Textures/stone_3", "bottom": DIRT}
## Earth heaped over a roof, along a bank, or thrown up round a hole. dirt_4, the
## dark grey-brown, because Salient's ground is dead grey and the yellow-brown
## dirt_5 read from across the map as a patch of camouflage netting laid on it.
const MOUND := {"top": DIRT, "side": DIRT, "bottom": DIRT}
const BAG := {"top": SANDBAG, "side": SANDBAG, "bottom": SANDBAG}

const TRENCH := {
	"trench_run_32": "_tr_run_32",
	"trench_run_16": "_tr_run_16",
	"trench_traverse": "_tr_traverse_l",
	"trench_traverse_r": "_tr_traverse_r",
	"trench_corner": "_tr_corner_l",
	"trench_corner_r": "_tr_corner_r",
	"trench_junction_t": "_tr_junction",
	"trench_firebay": "_tr_firebay",
	"trench_ramp_end": "_tr_ramp_end",
	"trench_dugout": "_tr_dugout",
	"trench_sap_head": "_tr_sap_head",
	"trench_collapsed": "_tr_collapsed",
	"duckboard_run": "_tr_duckboard",
	"crater_linked": "_tr_crater_linked",
	"crater_single_deep": "_tr_crater_single",
	"wire_belt_run": "_tr_wire_run",
	"wire_belt_gap": "_tr_wire_gap",
	"sunken_road_run": "_tr_road_run",
	"sunken_road_ramp": "_tr_road_ramp",
	"sunken_road_corner": "_tr_road_corner_l",
	"sunken_road_corner_r": "_tr_road_corner_r",
	"sunken_road_blown": "_tr_road_blown",
	"tank_ditched": "_tr_tank",
	"op_tower_ruin": "_tr_tower",
}

## What the level builder reads. Filled as each piece is built.
var _manifest: Dictionary = {}
var _ports: Dictionary = {}
var _dig: Array = []
var _span: Array = []


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
		print("usage: godot --headless --path . --script res://tools/block_trench.gd -- maps/blocks [--force] [names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("trench")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var written := 0
	var skipped := 0
	var clashes := 0
	for name: String in TRENCH:
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
		_ports = {}
		_dig = []
		_span = []
		call(TRENCH[name])
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		_manifest[name] = {"ports": _ports.duplicate(true), "dig": _dig.duplicate(true), "span": _span.duplicate()}
		written += 1
		# Checked here, where the brushes are, not afterwards in the level: a
		# piece that overlaps itself is wrong in every place it is put down.
		var hits := brush_overlaps()
		clashes += hits.size()
		print("      %-24s %3d brushes  %s%s" % [name, _brushes.size(), _extent_text(),
				"" if hits.is_empty() else "  OVERLAPS %d" % hits.size()])
	if written > 0:
		_write_manifest(dir, only.is_empty())
	print("BLOCK TRENCH DONE: %d written%s%s" % [written, (" (%d skipped)" % skipped) if skipped > 0 else "",
			(" — %d OVERLAPPING PAIR(S)" % clashes) if clashes > 0 else ""])
	quit()


## The manifest is merged into what is already on disk when only some pieces
## were rebuilt, so a --force of one name does not forget the other twenty.
func _write_manifest(dir: String, whole: bool) -> void:
	var path := dir.path_join("trench_kit.json")
	var out: Dictionary = {}
	if not whole and FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			out = (parsed as Dictionary).get("pieces", {})
	for k: String in _manifest:
		out[k] = _manifest[k]
	var doc := {
		"note": "GENERATED by tools/block_trench.gd. Never hand-edit.",
		"section": {"floor": T_FLOOR, "half": T_HALF, "wall": T_WALL, "parapet": T_PARAPET,
				"foot": T_FOOT, "moat": T_MOAT, "slot_below": T_SLOT_BELOW,
				"road_floor": R_FLOOR, "road_half": R_HALF,
				"hole_rim": HOLE_RIM, "scrape_y": SCRAPE_Y, "scrape_half": SCRAPE_HALF, "ramp_falloff": 0.6},
		"pieces": out,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()


# ── Recording what the builder needs ─────────────────────────────────────────

## A place a neighbour joins: `x`, `y` on the centreline, and how many degrees
## the route turns LEFT after it (negative for right). Heading 0 is the piece's
## own +X.
func _port(name: String, x: float, y: float, turn: float = 0.0) -> void:
	_ports[name] = {"x": x, "y": y, "turn": turn}


## Ground that must be lowered (or raised) to `y`, as a rectangle of the piece's
## own plan. Terrain stamps are exact rectangles with square corners, which is
## why this is not a path: a path's rounded end caps dig a pit beside whatever
## is narrower than the piece it joins.
func _dig_rect(x0: float, y0: float, x1: float, y1: float, y: float, falloff: float = 0.6) -> void:
	_dig.append({"k": "rect", "x0": x0, "y0": y0, "x1": x1, "y1": y1, "y": y, "f": falloff})


## The same, a disc: a shell hole.
func _dig_disc(cx: float, cy: float, r: float, y: float, falloff: float) -> void:
	_dig.append({"k": "disc", "x": cx, "y0": cy, "r": r, "y": y, "f": falloff})


## A slope: the ground under a ramp. A road-mode terrain path with its own
## heights, which is the one thing a flat stamp cannot be.
func _dig_ramp(x0: float, x1: float, half: float, y_a: float, y_b: float) -> void:
	_dig.append({"k": "ramp", "x0": x0, "x1": x1, "half": half, "ya": y_a, "yb": y_b})


# ── The body of a trench, from its floor plan ────────────────────────────────

## A TRENCH FROM A FLOOR PLAN. `floors` are the rectangles [x0, y0, x1, y1] of
## open floor; the walls are everything within T_WALL of a floor and inside
## `bounds`; the floor is left open to the neighbour on any side listed in
## `opens`.
##
## WHY NOT BOXES. A corner, a T or a zigzag bay is a place where several walls
## meet, and built as boxes each one needs the previous one's thickness worked
## out by hand -- the first version of every such piece in this project has had
## two walls sharing a corner. Here the plan is cut into cells on every edge
## that matters and each cell is exactly one thing, so two brushes cannot
## overlap and cannot leave a gap. Neighbouring cells of the same kind are then
## merged, so a straight run is still one slab and two walls.
##
## `cuts` are [x0, y0, x1, y1, top]: wall cells whose centre lies inside one
## are built to `top` instead of the parapet. That is how an embrasure is made.
## Ground level (0.0) is what makes it one.
func _body(floors: Array, bounds: Array, opens: Array, floor_z: float = T_FLOOR, cuts: Array = [],
		slab: bool = true, wall_top: float = T_PARAPET, floor_tex: Variant = EARTH_FLOOR,
		wall_tex: Variant = EARTH_WALL, foot: float = T_FOOT) -> void:
	_span = bounds.duplicate()
	var xs: Array = []
	var ys: Array = []
	for r: Array in floors:
		xs.append_array([r[0], r[2], r[0] - T_WALL, r[2] + T_WALL])
		ys.append_array([r[1], r[3], r[1] - T_WALL, r[3] + T_WALL])
	xs.append_array([bounds[0], bounds[2]])
	ys.append_array([bounds[1], bounds[3]])
	for c: Array in cuts:
		xs.append_array([c[0], c[2]])
		ys.append_array([c[1], c[3]])
	xs = _breaks(xs, bounds[0], bounds[2])
	ys = _breaks(ys, bounds[1], bounds[3])
	var nx := xs.size() - 1
	var ny := ys.size() - 1
	var kind: Array = []
	for i in nx:
		var col: Array = []
		for j in ny:
			var cx: float = (xs[i] + xs[i + 1]) * 0.5
			var cy: float = (ys[j] + ys[j + 1]) * 0.5
			var k := ""
			if _inside(floors, cx, cy, 0.0):
				k = "F" if slab else ""
			elif _inside(floors, cx, cy, T_WALL):
				var top := wall_top
				for c: Array in cuts:
					if cx > c[0] and cx < c[2] and cy > c[1] and cy < c[3]:
						top = c[4]
						break
				k = "W%.3f" % top
			col.append(k)
		kind.append(col)
	# Merge along x within a row, then down the rows.
	var open: Dictionary = {}
	for j in ny + 1:
		var now: Dictionary = {}
		if j < ny:
			var i := 0
			while i < nx:
				var k: String = kind[i][j]
				if k == "":
					i += 1
					continue
				var i1 := i
				while i1 + 1 < nx and kind[i1 + 1][j] == k:
					i1 += 1
				var key := "%d:%d:%s" % [i, i1, k]
				now[key] = open[key] if open.has(key) else j
				i = i1 + 1
		for key: String in open:
			if not now.has(key):
				_emit_cell(key, open[key], j - 1, xs, ys, floor_z, foot, floor_tex, wall_tex)
		open = now


func _emit_cell(key: String, j0: int, j1: int, xs: Array, ys: Array, floor_z: float, foot: float,
		floor_tex: Variant, wall_tex: Variant) -> void:
	var p := key.split(":")
	var x0: float = xs[int(p[0])]
	var x1: float = xs[int(p[1]) + 1]
	var y0: float = ys[j0]
	var y1: float = ys[j1 + 1]
	if p[2] == "F":
		box(Vector3(x0, y0, floor_z - foot), Vector3(x1, y1, floor_z), floor_tex)
	else:
		box(Vector3(x0, y0, floor_z - foot), Vector3(x1, y1, float((p[2] as String).substr(1))), wall_tex)


## Sorted, distinct, clipped to [lo, hi].
func _breaks(v: Array, lo: float, hi: float) -> Array:
	v.sort()
	var out: Array = []
	for f: float in v:
		if f < lo - 0.0001 or f > hi + 0.0001:
			continue
		if out.is_empty() or f - float(out[out.size() - 1]) > 0.0001:
			out.append(f)
	return out


func _inside(rects: Array, x: float, y: float, grow: float) -> bool:
	for r: Array in rects:
		if x > r[0] - grow and x < r[2] + grow and y > r[1] - grow and y < r[3] + grow:
			return true
	return false


## The ground to lower for a floor plan: every floor rectangle grown by a wall
## and a moat, flush at the open ends so a neighbour's dig is the same dig.
func _dig_floors(floors: Array, bounds: Array, opens: Array, y: float) -> void:
	for r: Array in floors:
		var g := T_WALL + T_MOAT
		var x0: float = r[0] - g
		var x1: float = r[2] + g
		var y0: float = r[1] - g
		var y1: float = r[3] + g
		if opens.has("-x") and r[0] <= bounds[0] + 0.001:
			x0 = r[0]
		if opens.has("+x") and r[2] >= bounds[2] - 0.001:
			x1 = r[2]
		if opens.has("-y") and r[1] <= bounds[1] + 0.001:
			y0 = r[1]
		if opens.has("+y") and r[3] >= bounds[3] - 0.001:
			y1 = r[3]
		# Never past the walls' own bounds plus the moat.
		_dig_rect(maxf(x0, bounds[0] - T_MOAT), maxf(y0, bounds[1] - T_MOAT),
				minf(x1, bounds[2] + T_MOAT), minf(y1, bounds[3] + T_MOAT), y)


## Ghost posts on the inner face of a wall, every `pitch`. Mesh only: they are
## a handspan proud of a wall, and a collider that size would erode a trench 3 m
## wide to a ribbon too narrow to bake. Posts stand ON the floor and AGAINST the
## wall face, touching both and sharing volume with neither.
func _posts(x0: float, x1: float, side: float, skip: Array = [], pitch: float = 4.0, offset: float = 2.0,
		half: float = T_HALF, z0: float = T_FLOOR, top: float = 0.4) -> void:
	var x := x0 + offset
	while x < x1 - 0.5:
		var near := false
		for c: float in skip:
			if absf(x - c) < T_EMBR * 0.5 + 0.2:
				near = true
		if not near:
			var ya := side * (half - 0.2)
			var yb := side * half
			box(Vector3(x - 0.1, minf(ya, yb), z0), Vector3(x + 0.1, maxf(ya, yb), top), WOOD_DARK)
		x += pitch


# ── The trench proper ────────────────────────────────────────────────────────

func _embrasures(centres: Array, side: float = 1.0) -> Array:
	var out: Array = []
	for c: float in centres:
		var ya := side * T_HALF
		var yb := side * T_OUT
		out.append([c - T_EMBR * 0.5, minf(ya, yb), c + T_EMBR * 0.5, maxf(ya, yb), 0.0])
	return out


## A straight run. Embrasures on the +Y wall, one every 8 m, so two runs end to
## end keep the pitch across the joint (the last of one is 4 m from its end, the
## first of the next is 4 m from its start).
func _tr_run(length: float) -> void:
	var h := length * 0.5
	var floors := [[-h, -T_HALF, h, T_HALF]]
	var bounds := [-h, -T_OUT, h, T_OUT]
	var centres: Array = []
	var c := -h + T_EMBR_PITCH * 0.5
	while c < h - 1.0:
		centres.append(c)
		c += T_EMBR_PITCH
	_body(floors, bounds, ["-x", "+x"], T_FLOOR, _embrasures(centres))
	no_collision()
	_posts(-h, h, 1.0, centres, 4.0, 2.0)
	_posts(-h, h, -1.0, [], 4.0, 2.0)
	_dig_floors(floors, bounds, ["-x", "+x"], T_FLOOR - T_SLOT_BELOW)
	_port("in", -h, 0.0)
	_port("out", h, 0.0)


func _tr_run_32() -> void:
	_tr_run(32.0)


func _tr_run_16() -> void:
	_tr_run(16.0)


## THE ZIGZAG BAY. A real trench is traversed: it never runs straight for more
## than a few metres, so a shell bursting in it kills one bay and not the line,
## and a man who gets in at one end cannot fire down all of it. For this game
## that is what makes a trench fight READABLE -- no sightline is longer than a
## bay. The floor is an S: a bay, a 1.6 m jog across the traverse, a second bay.
## The traverse itself is two walls thick and nothing more (offset 4.6 = 3.0 of
## floor + 2 x 0.8 of wall), so there is no strip of bare ground between the
## bays for the terrain to dip into.
##
## The piece's origin is the middle of the S: it enters at (-6, -2.3) and
## leaves at (6, +2.3). `s` is +1 for a jog to the left, -1 to the right, so a
## route can alternate and stay on course.
func _tr_traverse(s: float) -> void:
	var off := (T_HALF * 2.0 + T_WALL * 2.0) * 0.5      # 2.3: half the centreline step
	var a := [-6.0, -off - T_HALF, 1.5, -off + T_HALF]      # entry bay
	var b := [-1.5, off - T_HALF, 6.0, off + T_HALF]        # exit bay
	var j := [-1.5, -off + T_HALF, 1.5, off - T_HALF]       # the jog between them
	var floors: Array = [_flip(a, s), _flip(j, s), _flip(b, s)]
	var bounds := _flip([-6.0, -off - T_OUT, 6.0, off + T_OUT], s)
	var cuts: Array = []
	# One embrasure on each bay's outer wall, facing across no-man's-land.
	cuts.append_array(_cut_at(-3.0, _flip([0, -off - T_HALF, 0, -off - T_OUT], s)))
	cuts.append_array(_cut_at(3.0, _flip([0, off + T_HALF, 0, off + T_OUT], s)))
	_body(floors, bounds, ["-x", "+x"], T_FLOOR, cuts)
	_dig_floors(floors, bounds, ["-x", "+x"], T_FLOOR - T_SLOT_BELOW)
	_port("in", -6.0, -off * s)
	_port("out", 6.0, off * s)


func _tr_traverse_l() -> void:
	_tr_traverse(1.0)


func _tr_traverse_r() -> void:
	_tr_traverse(-1.0)


## `r` with its Y mirrored when s is negative, kept in [lo, hi] order.
func _flip(r: Array, s: float) -> Array:
	if s > 0.0:
		return r.duplicate()
	return [r[0], -r[3], r[2], -r[1]]


## An embrasure centred at x on the wall strip [_, y0, _, y1] given (already
## flipped).
func _cut_at(x: float, strip: Array) -> Array:
	var y0: float = minf(strip[1], strip[3])
	var y1: float = maxf(strip[1], strip[3])
	return [[x - T_EMBR * 0.5, y0, x + T_EMBR * 0.5, y1, 0.0]]


## A 90 degree turn, left for s = +1. Both arms are 4.5 m long and meet in the
## square the corner is made of.
func _tr_corner(s: float) -> void:
	var a := [-4.5, -T_HALF, T_HALF, T_HALF]
	var b := [-T_HALF, T_HALF, T_HALF, 4.5]
	var floors: Array = [_flip(a, s), _flip(b, s)]
	var bounds := _flip([-4.5, -T_OUT, T_OUT, 4.5], s)
	var cuts: Array = []
	# One embrasure on the outside of each arm.
	cuts.append_array(_cut_at(-3.0, _flip([0, -T_HALF, 0, -T_OUT], s)))
	var strip := _flip([0, 2.2, 0, 3.8], s)
	cuts.append([T_HALF, minf(strip[1], strip[3]), T_OUT, maxf(strip[1], strip[3]), 0.0])
	var opens: Array = ["-x", "+y" if s > 0.0 else "-y"]
	_body(floors, bounds, opens, T_FLOOR, cuts)
	_dig_floors(floors, bounds, opens, T_FLOOR - T_SLOT_BELOW)
	_port("in", -4.5, 0.0)
	_port("out", 0.0, 4.5 * s, 90.0 * s)


func _tr_corner_l() -> void:
	_tr_corner(1.0)


func _tr_corner_r() -> void:
	_tr_corner(-1.0)


## A T: the main trench carries on, and a branch leaves to the left. Where a
## communication trench joins a fire trench, or where a sap is dug off one.
func _tr_junction() -> void:
	var floors := [[-4.5, -T_HALF, 4.5, T_HALF], [-T_HALF, T_HALF, T_HALF, 6.0]]
	var bounds := [-4.5, -T_OUT, 4.5, 6.0]
	var cuts := _cut_at(0.0, [0, -T_HALF, 0, -T_OUT])
	_body(floors, bounds, ["-x", "+x", "+y"], T_FLOOR, cuts)
	no_collision()
	_dig_floors(floors, bounds, ["-x", "+x", "+y"], T_FLOOR - T_SLOT_BELOW)
	_port("in", -4.5, 0.0)
	_port("out", 4.5, 0.0)
	_port("branch", 0.0, 6.0, 90.0)


## A WIDENED BAY with embrasures along its whole face. Only the +Y wall moves
## out (1.2 m), and it is closed at each end by a short return, so the 3.0 m
## floor either side joins the neighbouring runs untouched. Three embrasures
## with 0.8 m merlons between them: a place to stand and shoot from, as against
## the run's one window in eight metres.
func _tr_firebay() -> void:
	var floors := [[-4.0, -T_HALF, 4.0, T_HALF], [-3.2, T_HALF, 3.2, 2.7]]
	var bounds := [-4.0, -T_OUT, 4.0, 2.7 + T_WALL]
	var cuts: Array = []
	for c: float in [-2.4, 0.0, 2.4]:
		cuts.append([c - T_EMBR * 0.5, 2.7, c + T_EMBR * 0.5, 2.7 + T_WALL, 0.0])
	_body(floors, bounds, ["-x", "+x"], T_FLOOR, cuts)
	no_collision()
	_posts(-4.0, 4.0, -1.0, [], 4.0, 2.0)
	_dig_floors(floors, bounds, ["-x", "+x"], T_FLOOR - T_SLOT_BELOW)
	_port("in", -4.0, 0.0)
	_port("out", 4.0, 0.0)


## THE WAY UP. 1.4 m over 5.0 m is 15.6 degrees: comfortably walkable, and the
## whole 3.0 m wide so it bakes. The parapet runs on at 0.6 above ground to the
## ramp's end rather than tapering to nothing: a wall tapering through
## 0.25-0.5 above the ground is a step the baker will not climb and the squad
## will, which is the one thing this kit exists not to have.
##
## Local +X is the ground end, -X the trench end. There is no slab: the ramp is
## the floor.
func _tr_ramp_end() -> void:
	var h := T_RAMP * 0.5
	var floors := [[-h, -T_HALF, h, T_HALF]]
	var bounds := [-h, -T_OUT, h, T_OUT]
	_body(floors, bounds, ["-x", "+x"], T_FLOOR, [], false)
	ramp(-h, -T_HALF, h, T_HALF, T_FLOOR - T_FOOT, T_FLOOR, T_PROUD, "+x", EARTH_FLOOR)
	# The terrain under the ramp climbs with it, 0.6 below its surface and
	# meeting the ground at the top, where the ramp ends 5 cm proud of it (flush
	# would be two surfaces at one height, and the ground would crawl through).
	_dig_ramp(-h, h, T_OUT + T_MOAT, T_FLOOR - T_SLOT_BELOW, 0.0)
	_port("trench", -h, 0.0)
	_port("ground", h, 0.0)


## A DUGOUT: a roofed chamber cut into the +Y wall, somewhere to be that is not
## the line. The entrance is 2.0 m clear (the squad can actually get in) and
## the roof's underside is 2.2 m over the floor. The roof is a slab with an
## earth skirt down three sides at 18 degrees, so the whole is a hillock that
## bakes and can be walked over, not a flat-topped box that bakes an island on
## its roof that nothing can reach.
func _tr_dugout() -> void:
	var floors := [[-8.0, -T_HALF, 8.0, T_HALF], [-1.0, T_HALF, 1.0, T_OUT], [-2.5, T_OUT, 2.5, 6.3]]
	var bounds := [-8.0, -T_OUT, 8.0, 6.3 + T_WALL]
	# The chamber's walls go up to the roof. They start at the run's wall face
	# (y = T_OUT), so the run's own wall keeps its parapet.
	var cuts: Array = _embrasures([-4.0, 4.0], -1.0)
	cuts.append([-3.3, T_OUT, 3.3, 6.3 + T_WALL, T_ROOF_UNDER])
	_body(floors, bounds, ["-x", "+x"], T_FLOOR, cuts)
	var roof_y0 := T_OUT
	var roof_y1 := 6.3 + T_WALL
	box(Vector3(-3.3, roof_y0, T_ROOF_UNDER), Vector3(3.3, roof_y1, T_ROOF_TOP), MOUND)
	# The skirts: west, east and north. Their far edges are 0.05 above the
	# ground they meet.
	var base := T_FLOOR - T_FOOT
	ramp(-7.3, roof_y0, -3.3, roof_y1, base, T_PROUD, T_ROOF_TOP, "+x", MOUND)
	ramp(3.3, roof_y0, 7.3, roof_y1, base, T_PROUD, T_ROOF_TOP, "-x", MOUND)
	ramp(-3.3, roof_y1, 3.3, roof_y1 + 4.0, base, T_PROUD, T_ROOF_TOP, "-y", MOUND)
	no_collision()
	_posts(-8.0, 8.0, -1.0, [-4.0, 4.0], 4.0, 2.0)
	_dig_floors(floors, bounds, ["-x", "+x"], T_FLOOR - T_SLOT_BELOW)
	# NO DIG UNDER THE SKIRTS. They are wedges founded 1 m under the floor, so the
	# ground simply stands inside them; digging there would leave their thin
	# outer edge standing over a pit.
	_port("in", -8.0, 0.0)
	_port("out", 8.0, 0.0)
	_port("chamber", 0.0, 4.3)


## A SAP HEAD: a dead-end spur poking into no-man's-land with a listening post
## at the tip, the sniper's hole. The post is roofed (underside 0.8 over the
## ground, so a man standing on the floor has his eyes at 0.25 and the 0.8 m slit
## in the front wall is exactly eye level) and the roof is skirted on its
## flanks, but NOT in front: a skirt there would bury the slit.
func _tr_sap_head() -> void:
	var floors := [[-6.0, -T_HALF, 3.0, T_HALF], [3.0, -2.2, 6.0, 2.2]]
	var bounds := [-6.0, -2.2 - T_WALL, 6.0 + T_WALL, 2.2 + T_WALL]
	var cuts: Array = [[2.2, bounds[1], bounds[2], bounds[3], T_ROOF_UNDER],
			[6.0, -0.8, 6.0 + T_WALL, 0.8, 0.0]]
	# The slit goes first in the list so it wins over the roof-height wall it
	# is cut out of.
	cuts = [cuts[1], cuts[0]]
	_body(floors, bounds, ["-x"], T_FLOOR, cuts)
	box(Vector3(2.2, bounds[1], T_ROOF_UNDER), Vector3(bounds[2], bounds[3], T_ROOF_TOP), MOUND)
	var base := T_FLOOR - T_FOOT
	ramp(2.2, bounds[3], bounds[2], bounds[3] + 3.5, base, T_PROUD, T_ROOF_TOP, "-y", MOUND)
	ramp(2.2, bounds[1] - 3.5, bounds[2], bounds[1], base, T_PROUD, T_ROOF_TOP, "+y", MOUND)
	no_collision()
	_dig_floors(floors, bounds, ["-x"], T_FLOOR - T_SLOT_BELOW)
	_port("in", -6.0, 0.0)
	_port("post", 4.5, 0.0)


## A CAVE-IN: the parapet has slumped to ground level and two heaps of earth
## lie in the floor, one against each wall, in turn. 2.0 m of floor stays clear
## past each, which after erosion leaves a 1.0 m ribbon the baker keeps. It
## breaks the line, and the heaps break the sightline down it.
##
## The heaps are real colliders (cover is the point, and being stopped by one is
## the point), they stand ON the floor and keep inside the walls, and their
## tops are under the ground so nothing here is in the 0.25-0.5 band.
func _tr_collapsed() -> void:
	var floors := [[-8.0, -T_HALF, 8.0, T_HALF]]
	var bounds := [-8.0, -T_OUT, 8.0, T_OUT]
	var cuts: Array = [[-5.0, T_HALF, 5.0, T_OUT, 0.0], [-5.0, -T_OUT, 5.0, -T_HALF, 0.0]]
	_body(floors, bounds, ["-x", "+x"], T_FLOOR, cuts)
	heap(Vector3(-2.5, 1.0, T_FLOOR + 0.3), 1.9, 0.45, 1.15, 4101, DIRT)
	heap(Vector3(2.5, -1.0, T_FLOOR + 0.3), 1.9, 0.45, 1.15, 4102, DIRT)
	no_collision()
	# Splintered revetment planks, lying across the heaps' feet.
	for p: Array in [[-5.5, 0.9, 12.0], [5.5, -0.9, -15.0]]:
		chunk(Vector3(p[0], p[1], T_FLOOR), Vector3(1.4, 0.18, 0.05), p[2], PLANK)
	_dig_floors(floors, bounds, ["-x", "+x"], T_FLOOR - T_SLOT_BELOW)
	_port("in", -8.0, 0.0)
	_port("out", 8.0, 0.0)


## DUCKBOARDS: the one thing down there that looks maintained. 0.1 m proud of
## the floor, so under the baker's climb and the mesh flows straight over them.
## The deck is one collider; the cross-slats are mesh only and stand on it.
func _tr_duckboard() -> void:
	box(Vector3(-8.0, -0.7, T_FLOOR), Vector3(8.0, 0.7, T_FLOOR + 0.1), {"top": PLANK, "side": WOOD_DARK, "bottom": WOOD_DARK})
	no_collision()
	var x := -7.8
	while x < 7.8:
		box(Vector3(x, -0.7, T_FLOOR + 0.1), Vector3(x + 0.12, 0.7, T_FLOOR + 0.1 + 0.03125), WOOD)
		x += 0.5
	_span = [-8.0, -0.7, 8.0, 0.7]


# ── No-man's-land ────────────────────────────────────────────────────────────

## A LIP, hipped on every side so there is no vertical face anywhere on it: a
## spoil heap thrown up by the shell, `h` high at the ridge. Lips are directional
## (see _tr_crater_single), and every one of them is a slope the baker walks
## and a body walks, so none of them is a wall -- cover is a reason to stop,
## not a thing that stops you. The faces are about 30 degrees on the 0.7 lip and
## 25 on the 0.2.
func _lip(cx: float, cy: float, along: float, across: float, h: float, ridge_along: float, ridge_across: float) -> void:
	var pts: Array = []
	# The foot is 0.45 UNDER the ground, not 0.15. A flat bottom a hair under a
	# ground that wobbles by centimetres crosses it somewhere, and the level probe
	# calls the column where it does two floors in one place.
	var z0 := -0.45
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			pts.append(Vector3(cx + sx * along, cy + sy * across, z0))
			pts.append(Vector3(cx + sx * ridge_along, cy + sy * ridge_across, h))
	solid(pts, DIRT, 2)


## Lip heights, and why these two. 0.7 is the cover you fire over and 0.2 is the
## way in. Nothing lies between 0.25 and 0.5, the band the baker will not climb
## and the body steps over (docs/ASSETS.md section 5), and the ridge is the only
## place a lip reaches its height -- the faces on either side are slopes.
const LIP_ENEMY := 0.7
const LIP_FRIEND := 0.2
## A shell hole's rim, and where its lips sit. The terrain bowl is a flat floor
## of HOLE_FLOOR_R and then a smoothstep to the rim over HOLE_FALL, so it is back
## at ground level at HOLE_RIM and the lips begin there.
const HOLE_FLOOR_R := 1.8
const HOLE_FALL := 3.8
const HOLE_RIM := HOLE_FLOOR_R + HOLE_FALL
const HOLE_DEPTH := -1.4
const LIP_AT := HOLE_RIM + 1.6
## The scrape between two holes: 0.9 m down, 2.4 m wide, 24 degree sides.
const SCRAPE_Y := -0.9
const SCRAPE_HALF := 1.2
## Where the two holes of a linked pair sit, either side of the piece's middle.
## 10 m, so the high lip of one and the low lip of the other, 5.6 m from the
## middle, do not share a metre between them.
const LINK_HOLE := 10.0


## Lips for a shell hole at (cx, 0): the enemy side (+X) high, the friendly side
## (-X) low. `gap_front` is a gap across the middle of the high one so a scrape
## can run through it. The low lip needs none; it is under the baker's climb.
func _lips(cx: float, gap_front: float) -> void:
	if gap_front > 0.0:
		for s: float in [-1.0, 1.0]:
			_lip(cx + LIP_AT, s * (gap_front * 0.5 + 1.8), 2.4, 1.8, LIP_ENEMY, 0.45, 0.9)
	else:
		_lip(cx + LIP_AT, 0.0, 2.4, 3.8, LIP_ENEMY, 0.45, 2.2)
	_lip(cx - LIP_AT, 0.0, 1.8, 3.8, LIP_FRIEND, 0.4, 2.4)


func _hole(cx: float, cy: float) -> void:
	_dig_disc(cx, cy, HOLE_FLOOR_R, HOLE_DEPTH, HOLE_FALL)


## ONE BIG HOLE. Terrain digs the bowl (a smooth S profile reads as ground and
## bakes as ground, which eight brush sectors do not) and the kit supplies what
## stands on it: the lips, one high on the enemy side and one low on the
## friendly, and a little ghost debris. `feature_crater_rim` made the same split.
func _tr_crater_single() -> void:
	_hole(0.0, 0.0)
	_lips(0.0, 0.0)
	no_collision()
	_debris(LIP_AT + 3.4, 0.0, 17)
	_span = [-LIP_AT - 1.8, -5.6, LIP_AT + 4.2, 5.6]
	_port("in", _span[0], 0.0)
	_port("out", _span[2], 0.0)
	_port("hole_in", 0.0, 0.0)
	_port("hole_out", 0.0, 0.0)


## TWO SHELL HOLES AND THE SCRAPE BETWEEN THEM, the thing a squad crawls along
## because it is the only ground that is not under fire. The scrape is a 0.9 m
## cut with 24 degree sides: shallow enough to climb out of anywhere and deep
## enough that a man lying in it is under the lip of the ground.
func _tr_crater_linked() -> void:
	var gap := 3.0
	_hole(-LINK_HOLE, 0.0)
	_hole(LINK_HOLE, 0.0)
	# The scrape runs from floor edge to floor edge, so it joins both bowls where
	# they are flat and the sides of each fall into it.
	_dig_rect(-LINK_HOLE + HOLE_FLOOR_R, -SCRAPE_HALF, LINK_HOLE - HOLE_FLOOR_R, SCRAPE_HALF, SCRAPE_Y, 2.0)
	_lips(-LINK_HOLE, gap)
	_lips(LINK_HOLE, gap)
	no_collision()
	_debris(LINK_HOLE + LIP_AT + 3.4, 0.0, 37)
	_span = [-LINK_HOLE - LIP_AT - 1.8, -5.6, LINK_HOLE + LIP_AT + 4.2, 5.6]
	_port("in", _span[0], 0.0)
	_port("out", _span[2], 0.0)
	_port("hole_in", -LINK_HOLE, 0.0)
	_port("hole_out", LINK_HOLE, 0.0)


## Splinters beyond the far lip. Mesh only and on the ground (a plank 0.06 thick
## sunk 2 cm, so it neither floats nor shares a face with the terrain).
func _debris(x: float, y: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for k in 5:
		var px := x + rng.randf_range(-0.8, 0.8)
		var py := y + rng.randf_range(-3.0, 3.0)
		chunk(Vector3(px, py, -0.02), Vector3(0.7, 0.12, 0.08), rng.randf_range(0.0, 180.0), WOOD_DARK)


## A BELT OF CONCERTINA WIRE: three rolls side by side, 1.0 m tall and solid.
## This is the one piece in the kit that is MEANT to stop people, so it
## collides, and at 1.0 m it is cleanly over the band. An octagonal prism's top
## is only 0.46 m across, which erodes to nothing, so no walkable island forms on
## top of a roll.
##
## The rolls are 0.05 m apart: touching, to the grid, but a 1/32 m snap can put
## two faces over each other, and an overlap is the one forbidden thing.
const WIRE_R := 0.595
const WIRE_PITCH := 1.15


func _wire_rolls(x0: float, x1: float) -> void:
	for row in [-1, 0, 1]:
		log_x(Vector3((x0 + x1) * 0.5, row * WIRE_PITCH, -0.1 - WIRE_R * (1.0 - 0.9239)), WIRE_R, x1 - x0, 8, METAL, "x")


## Pickets and the strands between them, mesh only, standing clear of the rolls.
func _wire_pickets(x0: float, x1: float) -> void:
	no_collision()
	var edge := WIRE_PITCH + 1.0
	for s: float in [-1.0, 1.0]:
		var x := x0 + 0.5
		while x <= x1 - 0.4:
			post(x, s * edge, 0.0, 1.5, 0.12, WOOD_DARK)
			x += 2.0
		# The strands run just INSIDE the pickets, touching their faces: threaded
		# through them they would share volume with every one.
		for z: float in [0.45, 1.0]:
			var inner := s * (edge - 0.06)
			box(Vector3(x0 + 0.5, minf(inner, inner - s * 0.04), z), Vector3(x1 - 0.4, maxf(inner, inner - s * 0.04), z + 0.04), METAL)


func _tr_wire_run() -> void:
	_wire_rolls(-8.0, 8.0)
	_wire_pickets(-8.0, 8.0)
	_span = [-8.0, -WIRE_PITCH - 1.0, 8.0, WIRE_PITCH + 1.0]
	_port("in", -8.0, 0.0)
	_port("out", 8.0, 0.0)


## THE SAME BELT WITH A 4 m GAP IN IT. A gap in wire is a funnel and a funnel is
## a killing ground, so this is a gameplay piece and not scenery: it is where
## every man on a front is told to go.
func _tr_wire_gap() -> void:
	var gap := 2.0
	_wire_rolls(-16.0, -gap)
	_wire_rolls(gap, 16.0)
	_wire_pickets(-16.0, -gap)
	_wire_pickets(gap, 16.0)
	_span = [-16.0, -WIRE_PITCH - 1.0, 16.0, WIRE_PITCH + 1.0]
	_port("in", -16.0, 0.0)
	_port("out", 16.0, 0.0)


# ── The sunken road ──────────────────────────────────────────────────────────

## 32 m OF ROAD CUT: an 8 m floor 2.5 m down between revetted banks, with the
## same 0.6 m parapet on top as the trench has. Fast and covered, which is its
## whole offer; the cost is that it is the one place on the map the enemy can
## plan for.
func _tr_road_run() -> void:
	var floors := [[-16.0, -R_HALF, 16.0, R_HALF]]
	var bounds := [-16.0, -R_HALF - T_WALL, 16.0, R_HALF + T_WALL]
	_body(floors, bounds, ["-x", "+x"], R_FLOOR, [], true, T_PARAPET, ROAD_FLOOR, ROAD_WALL)
	_dig_floors(floors, bounds, ["-x", "+x"], R_FLOOR - T_SLOT_BELOW)
	_port("in", -16.0, 0.0)
	_port("out", 16.0, 0.0)


## A BEND IN THE ROAD, 90 degrees, left for s = +1. Every piece in this kit is
## laid square to the map (see build_salient.gd, which lays routes in whole
## right angles) so a bend is a piece, and a sunken road that crosses the map
## on a diagonal does it as a staircase of straights and bends -- which is how
## a lane between fields is laid out anyway. Each arm is 8 m past the corner.
func _tr_road_corner(s: float) -> void:
	var a := [-8.0, -R_HALF, R_HALF, R_HALF]
	var b := [-R_HALF, R_HALF, R_HALF, 8.0]
	var floors: Array = [_flip(a, s), _flip(b, s)]
	var bounds := _flip([-8.0, -R_HALF - T_WALL, R_HALF + T_WALL, 8.0], s)
	var opens: Array = ["-x", "+y" if s > 0.0 else "-y"]
	_body(floors, bounds, opens, R_FLOOR, [], true, T_PARAPET, ROAD_FLOOR, ROAD_WALL)
	_dig_floors(floors, bounds, opens, R_FLOOR - T_SLOT_BELOW)
	_port("in", -8.0, 0.0)
	_port("out", 0.0, 8.0 * s, 90.0 * s)


func _tr_road_corner_l() -> void:
	_tr_road_corner(1.0)


func _tr_road_corner_r() -> void:
	_tr_road_corner(-1.0)


## The road's way up: 2.5 m over 12 m, 11.8 degrees, the whole 8 m wide.
func _tr_road_ramp() -> void:
	var h := R_RAMP * 0.5
	var floors := [[-h, -R_HALF, h, R_HALF]]
	var bounds := [-h, -R_HALF - T_WALL, h, R_HALF + T_WALL]
	_body(floors, bounds, ["-x", "+x"], R_FLOOR, [], false, T_PARAPET, ROAD_FLOOR, ROAD_WALL)
	ramp(-h, -R_HALF, h, R_HALF, R_FLOOR - T_FOOT, R_FLOOR, T_PROUD, "+x", ROAD_FLOOR)
	_dig_ramp(-h, h, R_HALF + T_WALL + T_MOAT, R_FLOOR - T_SLOT_BELOW, 0.0)
	_port("trench", -h, 0.0)
	_port("ground", h, 0.0)


## THE BLOWN SPAN: 40 m where the road is gone. A shell has brought the banks
## down and filled the cut, so for the middle 20 m the road is a rubble bed only
## 0.5 m under the field with 15 degree banks and no cover at all, and a rubble
## ramp climbs to it and drops from it at each end. It stays passable, which is
## the point; it is the 40 m in the middle of the road where everything can see
## you, which is the other point.
##
## The ramps keep their walls, at the same 0.6 parapet and ending square, so a
## wall never tapers through the 0.25-0.5 band against the ground.
func _tr_road_blown() -> void:
	var h := R_BLOWN * 0.5
	var ramp_len := 10.0
	var bed_h := h - ramp_len
	var floors := [[-h, -R_HALF, -bed_h, R_HALF], [bed_h, -R_HALF, h, R_HALF]]
	var bounds_a := [-h, -R_HALF - T_WALL, -bed_h, R_HALF + T_WALL]
	var bounds_b := [bed_h, -R_HALF - T_WALL, h, R_HALF + T_WALL]
	var base := R_FLOOR - T_FOOT
	_span = [-h, -R_HALF - T_WALL, h, R_HALF + T_WALL]
	# The two ramps, each with its walls.
	_body([floors[0]], bounds_a, ["-x"], R_FLOOR, [], false, T_PARAPET, ROAD_FLOOR, ROAD_WALL)
	_span = [-h, -R_HALF - T_WALL, h, R_HALF + T_WALL]
	_body([floors[1]], bounds_b, ["+x"], R_FLOOR, [], false, T_PARAPET, ROAD_FLOOR, ROAD_WALL)
	_span = [-h, -R_HALF - T_WALL, h, R_HALF + T_WALL]
	ramp(-h, -R_HALF, -bed_h, R_HALF, base, R_FLOOR, R_BED, "+x", ROAD_FLOOR)
	ramp(bed_h, -R_HALF, h, R_HALF, base, R_FLOOR, R_BED, "-x", ROAD_FLOOR)
	# The rubble bed and its banks.
	var bed_base := R_BED - T_FOOT
	box(Vector3(-bed_h, -R_HALF, bed_base), Vector3(bed_h, R_HALF, R_BED), {"top": DIRT, "side": DIRT, "bottom": DIRT})
	var bank := 2.4
	for s: float in [-1.0, 1.0]:
		var ya := s * R_HALF
		var yb := s * (R_HALF + bank)
		ramp(-bed_h, minf(ya, yb), bed_h, maxf(ya, yb), bed_base, R_BED, T_PROUD, "+y" if s > 0.0 else "-y", MOUND)
	no_collision()
	# Rubble on the bed and what is left of the banks: mesh only, at every
	# height, because a collider ankle-high on a bed 8 m wide is a hole in the
	# navmesh 1.3 m across and a line of them is a closed road.
	# One chunk per 4 x 4 m cell, jittered inside it by less than the chunk is
	# long, so no two can touch: scattered at random they overlapped each other.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var cx := -bed_h + 2.0
	while cx < bed_h - 1.0:
		for cy: float in [-2.0, 2.0]:
			var px := cx + rng.randf_range(-0.6, 0.6)
			var py := cy + rng.randf_range(-0.6, 0.6)
			chunk(Vector3(px, py, R_BED), Vector3(rng.randf_range(0.5, 1.2), rng.randf_range(0.4, 0.8), rng.randf_range(0.15, 0.3)),
					rng.randf_range(0.0, 180.0), RUBBLE)
		cx += 4.0
	# The dig: the ramps climb, the bed is level.
	_dig_ramp(-h, -bed_h, R_HALF + T_WALL + T_MOAT, R_FLOOR - T_SLOT_BELOW, R_BED - T_SLOT_BELOW)
	_dig_ramp(bed_h, h, R_HALF + T_WALL + T_MOAT, R_BED - T_SLOT_BELOW, R_FLOOR - T_SLOT_BELOW)
	_dig_rect(-bed_h, -R_HALF - 0.2, bed_h, R_HALF + 0.2, R_BED - T_SLOT_BELOW, bank - 0.2)
	_port("in", -h, 0.0)
	_port("out", h, 0.0)


# ── Landmarks ────────────────────────────────────────────────────────────────

## A TANK NOSE-DOWN IN A SHELL HOLE: the thing you give directions by. The hull
## is climbable, and the way up is an actual ramp: the tail deck rises from
## ground level at 22 degrees to a flat roof, and that is a slope, not a step.
## The turret is a cover block on the roof and the gun a ghost barrel (a 14 cm
## barrel is not a thing a squad can be stopped by). The nose dips into the hole
## the terrain digs under it.
func _tr_tank() -> void:
	_dig_disc(2.6, 0.0, 2.6, -1.5, 3.0)
	var hull := {"top": RUST_PANEL, "side": RUST, "bottom": RUST}
	# The tail deck, a wedge from the ground to the roof.
	solid([Vector3(-4.0, -1.5, -0.2), Vector3(-4.0, 1.5, -0.2), Vector3(-4.0, -1.5, T_PROUD), Vector3(-4.0, 1.5, T_PROUD),
			Vector3(-1.0, -1.5, 1.3), Vector3(-1.0, 1.5, 1.3), Vector3(-1.0, -1.5, -0.2), Vector3(-1.0, 1.5, -0.2)], hull, 2)
	# The roof, level.
	box(Vector3(-1.0, -1.5, -0.2), Vector3(1.0, 1.5, 1.3), hull)
	# The nose, dipping into the hole.
	solid([Vector3(1.0, -1.5, 1.3), Vector3(1.0, 1.5, 1.3), Vector3(1.0, -1.5, -1.0), Vector3(1.0, 1.5, -1.0),
			Vector3(3.6, -1.5, 0.1), Vector3(3.6, 1.5, 0.1), Vector3(3.6, -1.5, -1.4), Vector3(3.6, 1.5, -1.4)], hull, 2)
	# The turret stands on the roof, touching it.
	box(Vector3(-0.8, -0.9, 1.3), Vector3(0.8, 0.9, 1.9), hull)
	no_collision()
	beam(Vector3(1.0, 0.0, 1.6), Vector3(4.4, 0.0, 0.6), 0.14, METAL)
	_span = [-4.0, -3.4, 4.4, 3.4]
	_port("in", -4.0, 0.0)


## A RUINED OBSERVATION POST ON THE SKYLINE: a brick shaft with its top blown
## off into a steep broken roof, and the charred rafters still standing over it.
## Visible from across the map, which is its whole function. It is a solid shaft
## with no interior, so there is no floor inside it to bake an island on, and
## the roof is steeper than anything walks.
func _tr_tower() -> void:
	var brick := {"top": BRICK, "side": BRICK, "bottom": BRICK}
	box(Vector3(-2.2, -2.2, -3.0), Vector3(2.2, 2.2, 6.0), brick)
	# The broken crown: a hull from the shaft's top to a ragged apex, 63 degrees.
	solid([Vector3(-2.2, -2.2, 6.0), Vector3(2.2, -2.2, 6.0), Vector3(-2.2, 2.2, 6.0), Vector3(2.2, 2.2, 6.0),
			Vector3(-0.4, -0.4, 10.0), Vector3(0.4, -0.4, 10.0), Vector3(-0.4, 0.4, 10.0), Vector3(0.4, 0.4, 10.0)], brick, 2)
	no_collision()
	# A charred mast standing on the apex, touching it.
	beam(Vector3(0.0, 0.0, 10.0), Vector3(0.1, 0.0, 13.2), 0.22, WOOD_DARK)
	_span = [-2.2, -2.2, 2.2, 2.2]
