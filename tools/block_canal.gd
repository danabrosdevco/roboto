extends "res://tools/block_suburbs.gd"

# ─────────────────────────────────────────────
# BLOCK CANAL — the C&O Canal in Georgetown and the hillside it is cut into,
# built off photographs of the drained prism between 30th and Thomas Jefferson.
#
#   maps/blocks/canal/canal_*.map — the prism, its bridges, a lock, the
#       towpath, a bulk-bag cofferdam and the terrace walls.
#   maps/blocks/canal/mill_*.map  — the brick mills that stand on its edge,
#       the stone warehouse, the modern office and the café terrace.
#   maps/blocks/canal/wharf_*.map — the waterfront below it and the river.
#
#   godot --headless --path . --script res://tools/block_canal.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_canal.gd -- maps/blocks --force [names]
#
# WHAT THE PLACE IS, AND WHY IT IS GOOD GROUND. Georgetown steps down to the
# Potomac in terraces, each held up by a stone wall, and the canal is a cut
# running ALONG one of those terraces rather than down the hill. So the site
# gives you, for free, the thing this project normally has to fake: real
# verticality on ground that is still flat enough to fight on. Every level is
# a flat bench; all the height is in built walls; the only ways between
# benches are stairs, ramped streets and the bridges over the canal.
#
# That is also the project's own rule about hills, arrived at from the other
# direction: painted slopes are unusable by bodies, and height should come
# from built assets. A terraced town is what that rule looks like when it is
# the design instead of a constraint.
#
# THE PRISM IS A TRENCH NOBODY CAN LEAVE EXCEPT WHERE YOU SAY. It is 9 m wide
# and 3 m deep with vertical stone both sides. A squad in it is committed
# until the next stair or the next bridge, and a squad on the towpath above it
# is shooting down into a slot. That is the whole map in one section, and
# every piece below keeps to it:
#
#   bed            z = -3.0, 9 m wide, y -4.5 .. 4.5
#   wall           0.8 m thick, y 4.5 .. 5.3, up to z = 0
#   towpath        y 5.3 .. 9.0 at z = 0, brick, granite coping at the edge
#   berm           y -9.0 .. -5.3 at z = 0, grass
#   upper wall     y -9.8 .. -9.0, up to z = 3.0, the next terrace
#
# Everything runs along the map's X and is 32 m long so the prism tiles.
# ─────────────────────────────────────────────

const RUBBLE_WALL := "PSX_Textures/stone_3"
const COPING := "PSX_Textures/concrete_1"
const TOW_BRICK := "PSX_Textures/brick_wall_tx_3@0.5"
const MILL_BRICK := "PSX_Textures/brick_wall_tx_1"
const WEED := "PSX_Textures/grass_4"
const RIVER := "PSX_Textures/water_2"
const IRON := "PSX_Textures/metal_rusty_tsk_2"
const BAG := "PSX_Textures/fabric_tx_1"
const HAZARD := "PSX_Textures/metal_wall_1"

const STONE_W := {"top": COPING, "side": RUBBLE_WALL, "bottom": CONCRETE}
const TOWPATH := {"top": TOW_BRICK, "side": RUBBLE_WALL, "bottom": CONCRETE}
const BED := {"top": WEED, "side": RUBBLE_WALL, "bottom": CONCRETE}
const BERM := {"top": WEED, "side": RUBBLE_WALL, "bottom": CONCRETE}

## The section. Changing any of these changes every piece in the file, which
## is the point of them being here.
const SEG := 32.0
const BED_Z := -3.0
const BED_HALF := 4.5
const WALL_T := 0.8
const TOW_W := 3.7
const BERM_W := 3.7
const TERRACE_Z := 3.0

## HOW FAR THE CANAL REACHES ACROSS THE SITE, from its centreline to the outer
## edge of a towpath: 9.0 m. build_georgetown.gd reads this to know where the
## bench ground must stop, so the bench and the prism butt on one line and the
## number is typed once. Nothing may widen the towpath without moving it.
const CANAL_HALF := BED_HALF + WALL_T + TOW_W

## THE TOP OF A BRIDGE DECK, 6 cm under the banks it joins. The decks run on
## over the towpaths and wall tops to bear on them, and a deck at exactly 0
## there is two horizontal faces at one height — the depth buffer cannot
## choose, so the bridge crawls as the camera moves. The clearance is made in
## the deck and not in the banks, for the same reason as the bench tops
## (block_ground.gd): the banks have everything else standing on them. 6 cm is
## under what the baker climbs and a twentieth of what a body calls a step, so
## the squad still walks straight on.
const DECK_TOP := -0.06

## Half the width of the gap in the coping where a bridge lands. The widest deck
## is the street bridge at +-3.5, so 4 clears them all.
const BRIDGE_MOUTH := 4.0

const CANAL := {
	"canal_prism": "_prism",
	"canal_prism_open": "_prism_open",
	"canal_prism_open_bridge": "_prism_open_bridge",
	"canal_truss_bridge": "_truss_bridge",
	"canal_road_bridge": "_road_bridge",
	"canal_lock": "_lock",
	"canal_cofferdam": "_cofferdam",
	"canal_outfall": "_outfall",
	"canal_stair_down": "_stair_down",
	"canal_bench": "_bench",
	"canal_bench_16": "_bench_16",
	"canal_bench_4": "_bench_4",
	"canal_bench_grass": "_bench_grass",
	"canal_bench_grass_16": "_bench_grass_16",
	"canal_bench_grass_4": "_bench_grass_4",
	"canal_bench_2": "_bench_2",
	"canal_bench_1": "_bench_1",
	"canal_bench_grass_2": "_bench_grass_2",
	"canal_bench_grass_1": "_bench_grass_1",
	"canal_terrace_wall": "_terrace_wall",
	"canal_terrace_stair": "_terrace_stair",
	"canal_street_ramp": "_street_ramp",
	"mill_brick_long": "_mill_brick_long",
	"mill_brick_tall": "_mill_brick_tall",
	"mill_warehouse_stone": "_warehouse_stone",
	"mill_office_modern": "_office_modern",
	"mill_cafe_terrace": "_cafe_terrace",
	"wharf_esplanade": "_esplanade",
	"wharf_pier": "_pier",
	"wharf_river": "_river",
	"wharf_far_shore": "_far_shore",
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
		print("usage: godot --headless --path . --script res://tools/block_canal.gd -- maps/blocks [--force] [names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("canal")
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [dir, error_string(err)])
			quit(1)
			return
	var written := 0
	var skipped := 0
	for name: String in CANAL:
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
		call(CANAL[name])
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		written += 1
		print("      %-28s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
	print("BLOCK CANAL DONE: %d written%s" % [written, (" (%d skipped)" % skipped) if skipped > 0 else ""])
	quit()


# ── The prism ────────────────────────────────────────────────────────────────

## The bed and the two walls, from x0 to x1. Shared by the prism, the lock and
## both bridges so the channel never steps where two pieces meet.
func _channel(x0: float, x1: float) -> void:
	box(Vector3(x0, -BED_HALF, BED_Z - 1.0), Vector3(x1, BED_HALF, BED_Z), BED)
	for s: float in [-1.0, 1.0]:
		var a := s * BED_HALF
		var b := s * (BED_HALF + WALL_T)
		box(Vector3(x0, minf(a, b), BED_Z - 1.0), Vector3(x1, maxf(a, b), 0.0), STONE_W)


## The brick towpath on the +Y side, with its granite coping at the canal
## edge. The coping is 0.3 m proud: under the 0.45 a body steps over, so it
## is a line you can see and not a kerb anyone has to climb.
func _towpath(x0: float, x1: float, mouth: float = 0.0) -> void:
	var y0 := BED_HALF + WALL_T
	box(Vector3(x0, y0, -1.0), Vector3(x1, y0 + TOW_W, 0.0), TOWPATH)
	_coping(x0, x1, y0 - 0.1, y0 + 0.55, mouth)


## A RUN OF COPING 0.3 m proud, with a gap `mouth` either side of x = 0 where a
## bridge lands. THE COPING USED TO RUN STRAIGHT ACROSS EVERY BRIDGE, a 0.3 m
## lip over the deck at both ends. The navmesh baker climbs 0.25, and 0.3 only
## got over because the deck and the coping top happened to round to
## neighbouring voxels; the moment the deck sank 6 cm (DECK_TOP) they were two
## apart and all four bridges closed -- the squad could not cross the canal.
## A lip across a bridge mouth was never what a bridge is, so it is gone and
## the crossing is level, not lucky.
func _coping(x0: float, x1: float, ya: float, yb: float, mouth: float) -> void:
	var tex := {"top": COPING, "side": COPING, "bottom": COPING}
	if mouth <= 0.0:
		box(Vector3(x0, ya, 0.0), Vector3(x1, yb, 0.3), tex)
		return
	box(Vector3(x0, ya, 0.0), Vector3(-mouth, yb, 0.3), tex)
	box(Vector3(mouth, ya, 0.0), Vector3(x1, yb, 0.3), tex)


## The grass berm on the -Y side and the wall up to the next terrace. This is
## the stepped section in the photographs: a low wall out of the bed, a bench
## of grass, then a taller wall holding the mills up.
func _canal_berm(x0: float, x1: float) -> void:
	var y1 := -(BED_HALF + WALL_T)
	box(Vector3(x0, y1 - BERM_W, -1.0), Vector3(x1, y1, 0.0), BERM)
	var y2 := y1 - BERM_W
	box(Vector3(x0, y2 - 0.8, -1.0), Vector3(x1, y2, TERRACE_Z), STONE_W)


## 32 M OF CANAL: bed, both walls, towpath on one side, berm and terrace wall
## on the other. The piece the map is built out of.
func _prism() -> void:
	_channel(-SEG * 0.5, SEG * 0.5)
	_towpath(-SEG * 0.5, SEG * 0.5)
	_canal_berm(-SEG * 0.5, SEG * 0.5)
	# Weeds in the bed and ivy down the walls. Mesh only: the bed has to stay
	# one clean walkable floor, and a trench full of 0.6 m collision bushes is
	# a trench the squad refuses to walk down.
	no_collision()
	var x := -SEG * 0.5 + 1.5
	while x < SEG * 0.5 - 1.0:
		_heap_on(Vector3(x, (_hash_f(int(x) * 7) - 0.5) * 6.0, BED_Z), 1.1, 0.9, 0.55, int(x) + 3, SPOIL)
		if posmod(int(x), 5) == 0:
			# Clear of the wall, not buried in it: at -(BED_HALF + 0.3) the ivy sat
			# inside the stone and shared its volume, where nothing could see it.
			_heap_on(Vector3(x, -(BED_HALF - 0.5), -0.4), 0.7, 0.4, 0.9, int(x) + 11, SPOIL)
		x += 2.5


## A TOWPATH ON EACH SIDE OF THE CHANNEL, from x0 to x1. Shared by the open
## prism and the lock so that every bay of the canal is the same width: the
## bench ground butts the outside edge of the towpaths at +-CANAL_HALF, and a
## bay that stopped at the wall left a hole beside it that the level-fault
## probe found as the only empty ground on the map.
func _towpaths(x0: float, x1: float, mouth: float = 0.0) -> void:
	_towpath(x0, x1, mouth)
	# Mirrored, by hand rather than by a flag, because the coping sits on the
	# canal side of the path and a mirrored call would put it on the outside.
	var y0 := -(BED_HALF + WALL_T)
	box(Vector3(x0, y0 - TOW_W, -1.0), Vector3(x1, y0, 0.0), TOWPATH)
	_coping(x0, x1, y0, y0 + 0.1 + 0.55, mouth)


## The same with a towpath BOTH sides and no terrace: for the stretch where
## the canal runs between two walks instead of under the mills.
func _prism_open() -> void:
	_prism_open_with(0.0)


## THE OPEN PRISM FOR A BAY A BRIDGE CROSSES: the same, with the coping left
## off the mouth of the bridge (see _coping). The gap is wider than any deck,
## so the one constant serves all three bridges.
func _prism_open_bridge() -> void:
	_prism_open_with(BRIDGE_MOUTH)


func _prism_open_with(mouth: float) -> void:
	_channel(-SEG * 0.5, SEG * 0.5)
	_towpaths(-SEG * 0.5, SEG * 0.5, mouth)
	no_collision()
	var x := -SEG * 0.5 + 2.0
	while x < SEG * 0.5 - 1.0:
		_heap_on(Vector3(x, (_hash_f(int(x) * 11) - 0.5) * 6.0, BED_Z), 1.0, 0.9, 0.5, int(x) + 5, SPOIL)
		x += 3.0


## THE FOOTBRIDGE: a riveted pony truss with a curved top chord, a concrete
## deck laid over it, and chain link up both sides. The thing in the second
## photograph, and the piece that makes the canal crossable.
##
## The deck is 2.6 m wide and its surface is at DECK_TOP, 6 cm under both banks:
## level to a body, and not the same plane as the towpath it runs onto.
## A bridge that arrives a step above the towpath is a bridge half the squad
## stands in front of, and 0.3 m is all it takes.
func _truss_bridge() -> void:
	var half := BED_HALF + WALL_T + 1.0
	var w := 1.3
	# The deck and the beams under it.
	box(Vector3(-w - 0.25, -half - 1.5, -0.45), Vector3(w + 0.25, half + 1.5, DECK_TOP), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * w - 0.1, -half - 1.0, -0.75), Vector3(s * w + 0.1, half + 1.0, -0.45), IRON)
	# THE TRUSS STANDS BESIDE THE DECK, NOT ON ITS EDGE. Its plane used to be
	# 0.05 m inside the deck edge, so the bottom chord, every vertical and the
	# chain link all shared volume with the concrete, and the chord was also
	# built at the -X side twice (once per s) and never at +X. The plane moves
	# out 0.15 m so the members butt the deck's side face instead.
	var hd := 0.1                         # half the depth of the top chord
	var base_z := -0.2
	# The curved top chord's centreline, raised so the underside of its first
	# and last chord rests on the bottom chord and does not dip into it.
	var slope0: float = sin(PI / 5.0) * 1.5 / (2.0 * half / 5.0)
	var lift: float = hd * sqrt(1.0 + slope0 * slope0)
	var pts: Array = []
	for i in 6:
		var t := float(i) / 5.0
		pts.append(Vector2(lerpf(-half, half, t), base_z + lift + sin(t * PI) * 1.5))
	# Mitre the joints. Five straight bars end to end overlap on the inside of
	# every bend and open on the outside; cutting each end on the bisector of
	# the two bars means neighbours share one face and not a wedge of volume.
	var ups: Array = []
	var lows: Array = []
	var normals: Array = []
	for k in 5:
		var dir: Vector2 = (pts[k + 1] - pts[k]).normalized()
		normals.append(Vector2(-dir.y, dir.x))
	for i in 6:
		var m: Vector2
		var scale: float
		if i == 0:
			m = normals[0]
			scale = hd
		elif i == 5:
			m = normals[4]
			scale = hd
		else:
			m = normals[i - 1] + normals[i]
			scale = hd / (1.0 + normals[i - 1].dot(normals[i]))
		ups.append(pts[i] + m * scale)
		lows.append(pts[i] - m * scale)
	for s: float in [-1.0, 1.0]:
		var px := s * (w + 0.35)
		# The bottom chord, and the top chord in five mitred bars.
		box(Vector3(px - hd, -half - 0.6, -0.5), Vector3(px + hd, half + 0.6, base_z), IRON)
		for k in 5:
			var hull: Array = []
			for x: float in [px - hd, px + hd]:
				for q: Vector2 in [lows[k], ups[k], lows[k + 1], ups[k + 1]]:
					hull.append(Vector3(x, q.x, q.y))
			solid(hull, IRON)
		# Verticals from the bottom chord up to the underside of the top one,
		# stopping 0.03 short of it: a sloped face snapped to the grid would
		# otherwise land a unit inside the chord.
		for i in range(1, 5):
			var p: Vector2 = pts[i]
			var za: float = _chord_under(lows, p.x - 0.08) - 0.03
			var zb: float = _chord_under(lows, p.x + 0.08) - 0.03
			var hull: Array = []
			for x: float in [px - 0.08, px + 0.08]:
				hull.append(Vector3(x, p.x - 0.08, base_z))
				hull.append(Vector3(x, p.x + 0.08, base_z))
				hull.append(Vector3(x, p.x - 0.08, za))
				hull.append(Vector3(x, p.x + 0.08, zb))
			solid(hull, IRON)
		# The diagonals, each a parallelogram between two verticals with its
		# foot on the bottom chord and its head just under the top one. They
		# used to run from the middle of one vertical to the middle of the
		# next, through both; the last one went from a vertical to itself.
		for i in range(1, 4):
			var ya: float = (pts[i] as Vector2).x + 0.08
			var yb: float = (pts[i + 1] as Vector2).x - 0.08
			var head: float = _chord_under(lows, yb) - 0.03
			var hv := 0.14
			for _n in 3:
				hv = 0.1 * sqrt(1.0 + pow((head - hv - base_z) / (yb - ya), 2.0))
			var hull: Array = []
			for x: float in [px - 0.05, px + 0.05]:
				hull.append(Vector3(x, ya, base_z))
				hull.append(Vector3(x, ya, base_z + hv))
				hull.append(Vector3(x, yb, head - hv))
				hull.append(Vector3(x, yb, head))
			solid(hull, IRON)
		# Chain link over the deck, on the deck side of the truss and above the
		# deck's top face, so it stands on the concrete rather than in it.
		# Collision, as it always was; the lattice beside it is the mesh.
		box(Vector3(s * (w + 0.2), -half - 0.6, DECK_TOP), Vector3(s * (w + 0.25), half + 0.6, 1.25), IRON)
	no_collision()
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * (w + 0.15), -half - 0.6, DECK_TOP), Vector3(s * (w + 0.2), half + 0.6, 1.2), GRATING)


## The height of a top chord's underside at `y`, read off the polyline of its
## lower mitre points.
func _chord_under(lows: Array, y: float) -> float:
	for k in lows.size() - 1:
		var a: Vector2 = lows[k]
		var b: Vector2 = lows[k + 1]
		if y >= a.x and y <= b.x:
			return lerpf(a.y, b.y, (y - a.x) / (b.x - a.x))
	push_warning("block_canal: no chord under y = %.2f — the verticals will be placed at the chord's end height" % y)
	return (lows[0] as Vector2).y


## A LATER ROAD BRIDGE over the canal: a heavy concrete deck on the old iron,
## 7 m wide, carrying a street across. Dark underneath, which is the one piece
## of cover in a 300 m trench.
func _road_bridge() -> void:
	var half := BED_HALF + WALL_T + 1.6
	var w := 3.5
	# The deck runs the full length and the abutments are cut round it: the
	# stone sits UNDER the deck at each end (up to its soffit) and beside it
	# (full height), never through it. They used to be one slab each and the
	# deck was carried 1.6 m into them, so the two shared that volume.
	box(Vector3(-w, -half - 2.0, -0.9), Vector3(w, half + 2.0, DECK_TOP), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * w - 0.45, -half - 2.0, DECK_TOP), Vector3(s * w, half + 2.0, 0.55), {"top": COPING, "side": COPING, "bottom": COPING})
		# The iron stops at the abutment face: past it, it was inside the stone.
		box(Vector3(s * w - 0.3, -half - 0.4, -1.25), Vector3(s * w - 0.1, half + 0.4, -0.9), IRON)
	# The abutments, carried down into the canal wall so the bridge and the
	# prism are one piece of masonry and not two things meeting.
	for s: float in [-1.0, 1.0]:
		var y0: float = s * (half + 0.4)
		var y1: float = s * (half + 2.0)
		box(Vector3(-w, minf(y0, y1), BED_Z - 1.0), Vector3(w, maxf(y0, y1), -0.9), STONE_W)
		for e: float in [-1.0, 1.0]:
			var x0: float = e * w
			var x1: float = e * (w + 0.4)
			box(Vector3(minf(x0, x1), minf(y0, y1), BED_Z - 1.0), Vector3(maxf(x0, x1), maxf(y0, y1), DECK_TOP), STONE_W)
	no_collision()
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * (w - 0.22), -half - 1.8, 0.55), Vector3(s * (w - 0.18), half + 1.8, 1.65), GRATING)


## A LOCK CHAMBER, 28 m: the chamber narrowed to 5 m between its coped walls,
## a sill at each end, and the gates standing open against the recesses. The
## one place the prism has a floor a body can be surprised on.
## A FULL BAY LONG — 32 m, matching SEG — because the prism tiles in 32 m bays
## and the builder drops the lock in place of one. At 28 m it left two metres
## of nothing at each end of its bay: a void the squad walks up to and stops
## at, and the only interior hole the level-fault probe could find on the
## whole map. A piece that replaces a tile has to be the size of the tile.
func _lock() -> void:
	var half := SEG * 0.5
	var ch := 2.5
	_towpaths(-half, half)
	box(Vector3(-half, -ch, BED_Z - 1.2), Vector3(half, ch, BED_Z), {"top": CONCRETE, "side": RUBBLE_WALL, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(-half, s * ch, BED_Z - 1.2), Vector3(half, s * (BED_HALF + WALL_T), 0.0), STONE_W)
		box(Vector3(-half, s * ch - s * 0.1, 0.0), Vector3(half, s * (ch + 0.6), 0.35), {"top": COPING, "side": COPING, "bottom": COPING})
	for s: float in [-1.0, 1.0]:
		# The sill: a step up out of the chamber floor at each end. 0.55 m, so
		# it is over the 0.5 the baker climbs and reads as a wall, not as a
		# trip — the chamber floor is its own place.
		box(Vector3(s * (half - 2.0), -ch, BED_Z), Vector3(s * half, ch, BED_Z + 0.55), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
		for e: float in [-1.0, 1.0]:
			# A gate leaf, open, lying back along the chamber wall.
			# The leaf stops at the coping's inner lip: it stands up past z = 0, and
			# carried out to the wall face it ran through the coping beside it.
			box(Vector3(s * (half - 2.2), e * (ch - 0.45), BED_Z + 0.55), Vector3(s * (half - 6.4), e * (ch - 0.1), 0.6), {"top": WOOD_DARK, "side": WOOD, "bottom": WOOD_DARK})
			box(Vector3(s * (half - 2.2), e * (ch - 0.5), 0.6), Vector3(s * (half - 6.4), e * ch, 0.75), IRON)


## THE COFFERDAM: bulk bags stacked three high against a black membrane, with
## a yellow barrier on the top. Dewatering work left in the bed, and the only
## climbable thing in the prism — which makes it a route and not a prop.
##
## Each course steps back 0.2 m, so the stack is a stair the navmesh can take:
## three 0.9 m lifts is not climbable by anything, three 0.9 m lifts with a
## 0.7 m tread each is a way up onto the bank for a body that can manage one
## at a time. Whether the squad SHOULD be able to is a question for whoever
## places it; the piece makes it possible and says so here.
func _cofferdam() -> void:
	var rows := 3
	for r in rows:
		var z: float = BED_Z + r * 0.9
		var back: float = r * 0.2
		var n: int = 5 - r
		for i in n:
			var x := -2.2 + i * 1.0 + r * 0.1
			box(Vector3(x - 0.46, -1.1 + back, z), Vector3(x + 0.46, -0.2 + back, z + 0.88), {"top": BAG, "side": BAG, "bottom": BAG})
			if r < rows - 1:
				box(Vector3(x - 0.46, -0.2 + back, z), Vector3(x + 0.46, 0.7 + back, z + 0.88), {"top": BAG, "side": BAG, "bottom": BAG})
	# The membrane behind it and the barrier on top. It starts behind the
	# furthest-back course (0.9), not at 0.6, where it ran through the bags.
	box(Vector3(-3.0, 0.9, BED_Z), Vector3(3.0, 1.05, BED_Z + 2.8), {"top": RUBBER, "side": RUBBER, "bottom": RUBBER})
	var top: float = BED_Z + rows * 0.9
	# The rail runs BETWEEN the posts and not through them: a rail and a post
	# sharing a volume is two surfaces fighting over the same pixels.
	var post_x: Array = []
	for i in 4:
		post_x.append(lerpf(-2.5, 2.5, float(i) / 3.0))
		box(Vector3(post_x[i] - 0.06, -0.42, top), Vector3(post_x[i] + 0.06, -0.28, top + 1.15), HAZARD)
	for i in 3:
		box(Vector3(post_x[i] + 0.06, -0.4, top), Vector3(post_x[i + 1] - 0.06, -0.3, top + 1.1), HAZARD)


## A culvert mouth in the canal wall, with its apron and the stain below it.
func _outfall() -> void:
	# The mouth stands proud of the wall face. It used to start at the back of
	# the block and run through it, which put a pipe inside solid stone; the
	# 0.4 m that showed is the 0.4 m it still shows. Raised 0.1 so it clears
	# the apron it discharges onto.
	box(Vector3(-1.6, BED_HALF, BED_Z - 1.0), Vector3(1.6, BED_HALF + WALL_T, BED_Z + 1.9), STONE_W)
	_culvert_mouth(Vector3(0.0, BED_HALF, BED_Z + 0.85), 0.75, 0.6, 0.4, 8)
	box(Vector3(-1.1, BED_HALF - 2.2, BED_Z - 0.05), Vector3(1.1, BED_HALF, BED_Z + 0.08), CONCRETE)


## A ring of 8 segments between two radii, lying along -Y: a pipe mouth.
func _culvert_mouth(c: Vector3, outer: float, inner: float, length: float, sides: int) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		solid([Vector3(c.x + cos(a0) * inner, c.y, c.z + sin(a0) * inner),
				Vector3(c.x + cos(a0) * outer, c.y, c.z + sin(a0) * outer),
				Vector3(c.x + cos(a1) * outer, c.y, c.z + sin(a1) * outer),
				Vector3(c.x + cos(a1) * inner, c.y, c.z + sin(a1) * inner),
				Vector3(c.x + cos(a0) * inner, c.y - length, c.z + sin(a0) * inner),
				Vector3(c.x + cos(a0) * outer, c.y - length, c.z + sin(a0) * outer),
				Vector3(c.x + cos(a1) * outer, c.y - length, c.z + sin(a1) * outer),
				Vector3(c.x + cos(a1) * inner, c.y - length, c.z + sin(a1) * inner)], RUBBLE_WALL)


# ── The terraces ─────────────────────────────────────────────────────────────

## EVERY BENCH TOP IS AT z = -0.06, NOT 0. The benches ARE the ground on this
## map, and every road, path, esplanade, court and wall laid on them brings its
## own surface at exactly 0 — two horizontal faces at one height, which the
## depth buffer cannot choose between, so the ground crawls as the camera
## moves (399 of 3243 columns before this). The clearance is made HERE and not
## in the pieces: lifting them drives them up into the kerbs, shutters and
## walls standing on them. See the same note at the top of block_ground.gd.
## 6 cm is twice what the coplanar check calls one plane and a twentieth of
## what anything in the game calls a step. The 4 m thickness is unchanged.
## A STRIP OF BENCH, 448 x 32. The benches were one 460 x 360 slab each to
## start with, four of them at four heights — and they overlapped so hard that
## the town's bench lay on top of the canal and buried it. A bench is only as
## deep as it is; tile these to the depth it actually needs and nothing covers
## anything.
func _bench() -> void:
	box(Vector3(-224.0, -16.0, -4.0), Vector3(224.0, 16.0, -0.06), {"top": ASPHALT, "side": RUBBLE_WALL, "bottom": CONCRETE})


## 16 m and 4 m of the same, so a bench can be tiled to an EXACT depth. At 32 m
## only, a bench whose depth is not a multiple of 32 either overshot its
## boundary and lay on top of the next bench down, or stopped short and left a
## hole nothing could cross. Both of those cost a full debugging pass each.
func _bench_16() -> void:
	box(Vector3(-224.0, -8.0, -4.0), Vector3(224.0, 8.0, -0.06), {"top": ASPHALT, "side": RUBBLE_WALL, "bottom": CONCRETE})


func _bench_4() -> void:
	box(Vector3(-224.0, -2.0, -4.0), Vector3(224.0, 2.0, -0.06), {"top": ASPHALT, "side": RUBBLE_WALL, "bottom": CONCRETE})


## The same in grass, for the park bench. The ground under a thing is most of
## what tells you what kind of place it is, and park furniture standing on
## asphalt reads as a car park with benches in it.
func _bench_grass() -> void:
	box(Vector3(-224.0, -16.0, -4.0), Vector3(224.0, 16.0, -0.06), {"top": WEED, "side": RUBBLE_WALL, "bottom": SPOIL})


func _bench_grass_16() -> void:
	box(Vector3(-224.0, -8.0, -4.0), Vector3(224.0, 8.0, -0.06), {"top": WEED, "side": RUBBLE_WALL, "bottom": SPOIL})


func _bench_grass_4() -> void:
	box(Vector3(-224.0, -2.0, -4.0), Vector3(224.0, 2.0, -0.06), {"top": WEED, "side": RUBBLE_WALL, "bottom": SPOIL})


## 2 m and 1 m OF THE SAME, because the canal is 18 m wide: its towpaths end 9 m
## either side of the centreline, and the bench has to END THERE, on the same
## line, or it lies under the towpath (and, where it stopped short, leaves a
## hole). 9 m from a bench boundary that is a multiple of 4 is never a multiple
## of 4, so the tiling needs a 2 and a 1 to land on it exactly.
func _bench_2() -> void:
	box(Vector3(-224.0, -1.0, -4.0), Vector3(224.0, 1.0, -0.06), {"top": ASPHALT, "side": RUBBLE_WALL, "bottom": CONCRETE})


func _bench_1() -> void:
	box(Vector3(-224.0, -0.5, -4.0), Vector3(224.0, 0.5, -0.06), {"top": ASPHALT, "side": RUBBLE_WALL, "bottom": CONCRETE})


func _bench_grass_2() -> void:
	box(Vector3(-224.0, -1.0, -4.0), Vector3(224.0, 1.0, -0.06), {"top": WEED, "side": RUBBLE_WALL, "bottom": SPOIL})


func _bench_grass_1() -> void:
	box(Vector3(-224.0, -0.5, -4.0), Vector3(224.0, 0.5, -0.06), {"top": WEED, "side": RUBBLE_WALL, "bottom": SPOIL})


## 32 m of coursed rubble retaining wall, 4 m, with ground behind it at the
## top. The piece every change of level on the map is made of.
func _terrace_wall() -> void:
	box(Vector3(-SEG * 0.5, -0.9, -2.0), Vector3(SEG * 0.5, 0.0, 4.0), STONE_W)
	box(Vector3(-SEG * 0.5, -0.9, 4.0), Vector3(SEG * 0.5, 0.15, 4.35), {"top": COPING, "side": COPING, "bottom": COPING})
	box(Vector3(-SEG * 0.5, -9.0, -2.0), Vector3(SEG * 0.5, -0.9, 4.0), {"top": WALK, "side": CONCRETE, "bottom": CONCRETE})
	no_collision()
	var x := -SEG * 0.5 + 2.0
	while x < SEG * 0.5 - 1.0:
		# Standing off the wall face (y = 0) by its own depth: centred ON the face
		# it sat half inside the stone.
		_heap_on(Vector3(x, 0.35, 2.4), 0.5, 0.25, 1.4, int(x) * 3 + 7, SPOIL)
		x += 4.0


## A PUBLIC STAIR up a 4 m terrace, 2.8 m wide with a wall both sides.
##
## THE COLLISION IS A RAMP AND THE STEPS ARE A PICTURE OF STEPS. Built as
## nineteen separate treads it baked no navmesh at all and the reachability
## probe came back with every objective on the map cut off — a 0.34 m tread
## cannot hold a 0.5 m agent radius, so Recast erodes each one to nothing and
## there is no walkable surface anywhere on the flight. The riser height was
## never the problem; the tread depth was.
##
## So the solid is one 20° ramp, which the baker sees and a body walks, and
## the treads are laid on it as mesh only. From the outside it is a stair.
## This is what enemy.gd means in its note about every level having had to
## have a ramp built onto everything.
func _terrace_stair() -> void:
	var steps := 19
	var tread := 0.34
	var total := -float(steps) * tread - 2.2
	var run: float = -total
	ramp(-1.4, total, 1.4, 0.0, -1.0, 0.0, 4.0, "-y", {"top": COPING, "side": RUBBLE_WALL, "bottom": CONCRETE})
	# A FIVE METRE LANDING, not 2.4. The bench slabs are 4 m thick, so a ramp
	# that reaches full height anywhere under one surfaces along a single line
	# and connects to nothing — which is what happened, and why the probe found
	# every objective cut off twice running. The ramp now tops out clear of the
	# bench and the landing BRIDGES onto it, overlapping its top face.
	box(Vector3(-1.4, total - 5.0, -1.0), Vector3(1.4, total, 4.0), {"top": COPING, "side": RUBBLE_WALL, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 1.4, total - 5.0, -1.0), Vector3(s * 2.0, 0.6, 4.0), STONE_W)
	no_collision()
	# THE TREADS FOLLOW THE RAMP, which climbs toward -Y. They used to take
	# their height from the other end (4 m at y = 0), so the picture of the
	# stair ran the opposite way to the collision under it: the lower treads
	# floated and the upper ones were buried in the ramp. Each is now a wedge
	# whose underside lies on the ramp's own surface.
	for i in steps:
		var y := -float(i) * tread
		var z_near: float = 4.0 * absf(y) / run
		var z_far: float = 4.0 * (absf(y) + tread) / run
		_tread_wedge(-1.4, 1.4, y, z_near, y - tread, z_far, {"top": COPING, "side": COPING, "bottom": COPING})


## STONE STEPS from the towpath down into the bed, set into the wall. The
## thing that decides where a fight in the prism can start and end, so it is
## its own piece and gets placed deliberately.
##
## Same construction as the terrace stair and for the same reason: the ramp is
## the collision, the treads are mesh. A 0.33 m tread holds nobody.
func _stair_down() -> void:
	var y0 := BED_HALF
	var steps := 16
	# 4.3 M OF CUT, not 1.6. The first version was a slot the thickness of the
	# wall, which the baker erodes by the agent radius from both sides until
	# the landings at each end are nothing at all — so it baked a strip with no
	# way on or off, and the canal bed stayed unreachable. A stair has to reach
	# WELL into the ground at both ends, not just touch it.
	var lo := BED_HALF - 1.2
	var hi := BED_HALF + WALL_T + 1.8
	# IT DESCENDS ACROSS THE CANAL, not along it. Cut as a flight running
	# parallel to the wall it is set into, the ramp only met the towpath along
	# one short edge at its top and the bed along another at its bottom, and
	# the baker erodes both of those away — so it baked a surface with no way
	# on or off and the bed stayed an island through three attempts at it.
	# Across, the whole top edge is on the towpath and the whole bottom edge is
	# in the bed.
	ramp(-2.2, lo, 2.2, hi, BED_Z - 1.2, BED_Z, 0.0, "+y",
			{"top": COPING, "side": RUBBLE_WALL, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 2.2, lo, BED_Z - 1.2), Vector3(s * 2.8, hi, 0.4), STONE_W)
	no_collision()
	# Each tread is a wedge whose underside lies on the ramp. A flat box over a
	# sloped surface has to sink into it somewhere, and that sunk wedge is
	# volume shared with the ramp. The last treads run past the top of the
	# ramp onto the towpath and stay plain slabs.
	var slope: float = (0.0 - BED_Z) / (hi - lo)
	for i in steps:
		var y := BED_HALF - 1.2 + i * 0.2625
		var y_hi: float = y + 0.2625
		if y >= hi:
			box(Vector3(-2.2, y, -0.12), Vector3(2.2, y_hi, 0.0), {"top": COPING, "side": COPING, "bottom": COPING})
			continue
		y_hi = minf(y_hi, hi)
		_tread_wedge(-2.2, 2.2, y, BED_Z + (y - lo) * slope, y_hi, BED_Z + (y_hi - lo) * slope, {"top": COPING, "side": COPING, "bottom": COPING})


## A STREET RAMPED DOWN A TERRACE at 1 in 8, 7 m wide between stone walls.
## The only way a vehicle gets between two levels on this map, which makes it
## worth defending and worth knowing where it is.
func _street_ramp() -> void:
	var run := 32.0
	ramp(-run * 0.5, -3.5, run * 0.5, 3.5, -2.0, 0.0, 4.0, "-x", {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		var y0 := s * 3.5
		var y1 := s * 4.4
		box(Vector3(-run * 0.5, minf(y0, y1), -2.0), Vector3(run * 0.5, maxf(y0, y1), 4.6), STONE_W)
	# There used to be a stepped footway here, y 3.5 to 4.4 along the +Y side.
	# That is exactly where the +Y wall stands, so all sixteen brushes were
	# buried in the stone and shared its volume without ever being seen. Left
	# out rather than uncovered: its steps ran 0.4 m off the road surface, and
	# a footway that is not on the surface is a ledge in the baker's 0.25 to
	# 0.45 m band beside the only vehicle route between levels.


# ── The buildings on the canal ───────────────────────────────────────────────

## A BRICK MILL, 44 x 16 and four storeys, standing straight on the canal's
## terrace wall so its ground floor IS the wall. Segmental-arched windows in a
## regular bay, a corbelled eaves band, and a flat roof behind a low parapet.
## The building in the first photograph.
func _mill_brick_long() -> void:
	var half := 22.0
	var d := 8.0
	var top := 13.5
	box(Vector3(-half, -d, -4.0), Vector3(half, d, top), {"top": ROOF_MEMBRANE, "side": MILL_BRICK, "bottom": CONCRETE})
	# The corbel under the eaves: two courses standing proud, which is the one
	# piece of ornament these buildings have and what makes the top read.
	for z: float in [top - 0.9, top - 0.45]:
		_rim(-half, -d, half, d, 0.18, 0.0, z, z + 0.35, MILL_BRICK)
	# The parapet is a collar round the roof edge, not a 1 m slab over all of
	# it: as a slab it buried the rooftop plant, and as a collar it is what the
	# comment on this function says it is, a flat roof behind a low parapet.
	_rim(-half, -d, half, d, 0.25, 0.3, top, top + 1.0, {"top": COPING, "side": MILL_BRICK, "bottom": MILL_BRICK})
	# EVERYTHING BELOW IS MESH ONLY. The first cut of this building was 451
	# brushes and every one of them a collision shape, for a wall with some
	# window reveals on it — the wall is the collision, the reveals are a
	# picture of one. The roof plant goes the same way: these stand 13 m up
	# off a canal with no way onto them.
	no_collision()
	for lvl in 4:
		var z: float = 1.1 + lvl * 3.0
		for i in 8:
			var x := lerpf(-half + 2.2, half - 2.2, float(i) / 7.0)
			for s: float in [-1.0, 1.0]:
				# The face is named for the side it is on: "y" always builds
				# toward +Y, so on the -Y wall the windows were going up inside
				# the brick, in the same volume as the wall.
				window("y" if s > 0.0 else "-y", s * d, x, z, 1.1, 1.9, true, DARK_GLASS)
				# The arch over each, standing on the lintel and on the wall
				# face: it used to sink 0.12 into the wall and run through the
				# lintel's height, which is two overlaps per window. Three
				# stepped boxes at this size is a segmental arch and costs three
				# brushes instead of ten.
				box(Vector3(x - 0.62, s * d, z + 2.15), Vector3(x + 0.62, s * (d + 0.2), z + 2.3), MILL_BRICK)
	# The downpipe, which every photograph of one of these has down its face.
	# It stops under the first corbel course: carried up past it, it ran
	# through the corbel.
	box(Vector3(-4.0, d, -4.0), Vector3(-3.78, d + 0.22, top - 0.9), IRON)
	_rooftop_plant(-half + 4.0, -d + 3.0, half - 4.0, d - 3.0, top, 211)


## A TALLER MILL with a glazed top floor added over it — the one with the
## lantern roof behind the trees in both photographs. Nine metres longer and
## four metres taller than the last, so a row of the two has a skyline.
func _mill_brick_tall() -> void:
	var half := 18.0
	var d := 11.0
	var top := 16.0
	box(Vector3(-half, -d, -4.0), Vector3(half, d, top), {"top": CONCRETE, "side": MILL_BRICK, "bottom": CONCRETE})
	for z: float in [top - 1.0, top - 0.5]:
		_rim(-half, -d, half, d, 0.18, 0.0, z, z + 0.4, MILL_BRICK)
	no_collision()
	for lvl in 4:
		var z: float = 1.2 + lvl * 3.2
		for i in 8:
			var x := lerpf(-half + 2.4, half - 2.4, float(i) / 7.0)
			for s: float in [-1.0, 1.0]:
				window("y" if s > 0.0 else "-y", s * d, x, z, 1.4, 2.1, true, DARK_GLASS)
	# The added floor: steel and glass set back from the brick, with a
	# shallow hipped lantern over it.
	box(Vector3(-half + 1.2, -d + 1.2, top), Vector3(half - 1.2, d - 1.2, top + 3.4), STORE_GLASS)
	for i in 9:
		var x := lerpf(-half + 1.2, half - 1.2, float(i) / 8.0)
		for s: float in [-1.0, 1.0]:
			# Outside the glazing, on its face: centred on the face it ran half
			# through the glass.
			box(Vector3(x - 0.12, s * (d - 1.2), top), Vector3(x + 0.12, s * (d - 1.0), top + 3.4), METAL)
	_hip(-half + 0.9, -d + 0.9, half - 0.9, d - 0.9, top + 3.4, top + 5.2, 0.5)


## A STONE WAREHOUSE: rough squared rubble with brick heads, three storeys and
## a loading door on each, with the hoist beam still over the top one.
func _warehouse_stone() -> void:
	var half := 14.0
	var d := 9.0
	var top := 11.0
	box(Vector3(-half, -d, -4.0), Vector3(half, d, top), {"top": ROOF_MEMBRANE, "side": RUBBLE_WALL, "bottom": CONCRETE})
	box(Vector3(-half - 0.22, -d - 0.22, top), Vector3(half + 0.22, d + 0.22, top + 0.9), {"top": COPING, "side": RUBBLE_WALL, "bottom": RUBBLE_WALL})
	for lvl in 3:
		var z: float = 1.0 + lvl * 3.2
		# Door and head stand ON the wall face (y = d), proud of it; they used
		# to start 0.3 and 0.1 inside it.
		box(Vector3(-1.4, d, z), Vector3(1.4, d + 0.1, z + 2.4), WOOD_DARK)
		box(Vector3(-1.6, d, z + 2.4), Vector3(1.6, d + 0.18, z + 2.6), MILL_BRICK)
		for i in 3:
			var x := lerpf(-half + 3.0, half - 3.0, float(i) / 2.0)
			if absf(x) < 3.0:
				continue
			window("y", d, x, z, 1.2, 1.8, true, DARK_GLASS)
			window("-y", -d, x, z, 1.2, 1.8, true, DARK_GLASS)
	# The hoist beam over the top door, standing on its head instead of
	# running back through the door leaf, and the pulley bracket hung from it
	# instead of through it.
	box(Vector3(-0.22, d, top - 1.0), Vector3(0.22, d + 2.2, top - 0.6), WOOD_DARK)
	box(Vector3(-0.35, d + 1.8, top - 2.0), Vector3(0.35, d + 2.1, top - 1.0), IRON)


## THE MODERN BLOCK: eight storeys of dark brick and ribbon glazing set back
## at the top, the one on the right of the first photograph. It is here for
## the shadow it throws into the canal and because a map of one period reads
## as a film set.
func _office_modern() -> void:
	var half := 16.0
	var d := 13.0
	var top := 24.0
	box(Vector3(-half, -d, -4.0), Vector3(half, d, top), {"top": ROOF_MEMBRANE, "side": MILL_BRICK, "bottom": CONCRETE})
	box(Vector3(-half + 2.2, -d + 2.2, top), Vector3(half - 2.2, d - 2.2, top + 3.2), {"top": ROOF_MEMBRANE, "side": MILL_BRICK, "bottom": CONCRETE})
	no_collision()
	for lvl in 8:
		var z: float = 1.4 + lvl * 2.8
		for s: float in [-1.0, 1.0]:
			# EVERYTHING HERE STANDS ON THE WALL FACE, not in it. The glazing and
			# the mullions were sunk 0.22 and 0.26 m into the brick and the
			# mullions through the glass as well — 224 of this piece's 320
			# overlaps were that one line. Glazing is 0.06 proud, the mullions a
			# further 0.14 over it.
			box(Vector3(-half + 1.2, s * d, z), Vector3(half - 1.2, s * (d + 0.06), z + 1.7), DARK_GLASS)
			box(Vector3(s * half, -d + 1.2, z), Vector3(s * (half + 0.06), d - 1.2, z + 1.7), DARK_GLASS)
		for i in 9:
			var x := lerpf(-half + 1.2, half - 1.2, float(i) / 8.0)
			for s: float in [-1.0, 1.0]:
				box(Vector3(x - 0.14, s * (d + 0.06), z), Vector3(x + 0.14, s * (d + 0.2), z + 1.7), MILL_BRICK)
	_rooftop_plant(-half + 4.0, -d + 4.0, half - 4.0, d - 4.0, top + 3.2, 311)


## THE CAFÉ TERRACE above the canal wall: a railed deck with parasols, the
## blue ones over the wall in both photographs. A balcony overlooking a
## trench, which is a firing position with tables on it.
func _cafe_terrace() -> void:
	box(Vector3(-9.0, -5.0, -2.0), Vector3(9.0, 5.0, 0.0), {"top": TOW_BRICK, "side": RUBBLE_WALL, "bottom": CONCRETE})
	# The two end rails stop where the long rail begins (4.94) and do not run
	# on through its end.
	for e: Array in [[-9.0, 5.0, 9.0, 5.0], [-9.0, -5.0, -9.0, 4.88], [9.0, -5.0, 9.0, 4.88]]:
		box(Vector3(e[0] - 0.06, e[1] - 0.06, 0.0), Vector3(e[2] + 0.06, e[3] + 0.06, 1.05), IRON)
	for i in 7:
		var x := lerpf(-8.6, 8.6, float(i) / 6.0)
		# On the inside face of the rail, not through it.
		box(Vector3(x - 0.05, 4.84, 0.0), Vector3(x + 0.05, 4.94, 1.1), IRON)
	no_collision()
	for i in 3:
		for j in 2:
			var x := lerpf(-6.0, 6.0, float(i) / 2.0)
			var y := lerpf(-2.6, 2.4, float(j))
			cylinder(Vector3(x, y, 0.0), 0.72, 0.74, 8, {"top": COPING, "side": METAL, "bottom": METAL})
			cylinder(Vector3(x, y, 0.74), 0.06, 1.5, 6, METAL)
			cylinder(Vector3(x, y, 2.24), 1.85, 0.32, 8, BLUE, 0.3)


# ── The waterfront ───────────────────────────────────────────────────────────

## 48 m of river wall and esplanade: granite coping, a railing, and the paving
## behind it. The bottom terrace, and the only place on the map with the
## Potomac on one side and nothing to hide behind.
func _esplanade() -> void:
	var half := 24.0
	box(Vector3(-half, -2.0, -5.0), Vector3(half, 0.0, 0.0), {"top": COPING, "side": RUBBLE_WALL, "bottom": CONCRETE})
	box(Vector3(-half, -12.0, -5.0), Vector3(half, -2.0, 0.0), {"top": TOW_BRICK, "side": RUBBLE_WALL, "bottom": CONCRETE})
	box(Vector3(-half, -0.5, 0.0), Vector3(half, 0.0, 0.42), {"top": COPING, "side": COPING, "bottom": COPING})
	# The rail: posts and two bars. Mesh only, because a continuous collider
	# along an esplanade is a wall between the squad and the one open flank
	# the map has, and the drop behind it is the real edge.
	no_collision()
	for i in 17:
		var x := lerpf(-half + 1.0, half - 1.0, float(i) / 16.0)
		box(Vector3(x - 0.06, -0.35, 0.42), Vector3(x + 0.06, -0.23, 1.5), IRON)
	# The bars run along the FACE of the posts, not through them.
	for z: float in [0.95, 1.42]:
		box(Vector3(-half + 1.0, -0.23, z), Vector3(half - 1.0, -0.15, z + 0.08), IRON)


## A timber pier out over the water on its piles, 26 m. Somewhere to be
## caught on, and the only ground on the map the river is under.
func _pier() -> void:
	box(Vector3(-3.5, -13.0, -0.35), Vector3(3.5, 13.0, 0.0), {"top": WOOD, "side": WOOD_DARK, "bottom": WOOD_DARK})
	for i in 7:
		var y := lerpf(-12.0, 12.0, float(i) / 6.0)
		for s: float in [-1.0, 1.0]:
			cylinder(Vector3(s * 3.0, y, -5.0), 0.26, 4.65, 7, WOOD_DARK)
	for s: float in [-1.0, 1.0]:
		for i in 9:
			var y := lerpf(-12.4, 12.4, float(i) / 8.0)
			box(Vector3(s * 3.5 - s * 0.14, y - 0.12, 0.0), Vector3(s * 3.5, y + 0.12, 0.95), WOOD_DARK)


## THE POTOMAC: one plane, 600 x 320, 2.4 m below the esplanade. Visual only,
## as water is everywhere else in this project — nothing swims and nothing
## wades, and the far bank is scenery.
func _river() -> void:
	no_collision()
	box(Vector3(-300.0, -320.0, -2.6), Vector3(300.0, 0.0, -2.4), RIVER)


## ARLINGTON ACROSS THE WATER: a low silhouette of slabs on the far bank, at
## the distance the real one sits. Mesh only and never walked on — it is a
## horizon, and the moment anything can get to it, it has to be a map.
func _far_shore() -> void:
	no_collision()
	box(Vector3(-300.0, -14.0, -2.6), Vector3(300.0, 0.0, 1.5), {"top": DIRT, "side": RUBBLE_WALL, "bottom": CONCRETE})
	# Laid end to end with a gap between them, not on a fixed 40 m pitch with a
	# 22 m half-width: neighbours then overlapped by up to 4 m, and the heavier
	# the hash the deeper they went through each other.
	var cursor := -290.0
	for i in 14:
		var w := 9.0 + _hash_f(i * 5) * 13.0
		var x := cursor + w
		cursor = x + w + 3.0 + _hash_f(i * 17) * 6.0
		if cursor > 300.0:
			push_warning("block_canal: far shore ran out of room at slab %d — the rest are left off" % i)
			break
		var h := 12.0 + _hash_f(i * 23) * 26.0
		box(Vector3(x - w, -14.0 - _hash_f(i) * 30.0, 0.0), Vector3(x + w, -14.0, h),
				{"top": CONCRETE, "side": PALE, "bottom": CONCRETE})
	for i in 30:
		var x := -290.0 + i * 20.0
		# Held at y = -8.5 so the footprint (5 m deep) stays on the bank and does
		# not reach out over the slabs standing at its foot.
		_heap_on(Vector3(x, -8.5, 1.5), 7.0, 5.0, 7.0, i * 13 + 3, SPOIL)


# ── Ground dressing that sits ON the ground ──────────────────────────────────

## heap() from block_industrial, with the bottom ring at c.z instead of 0.3 m
## under it. heap() sinks its skirt into whatever it stands on, which is right
## for a prop on terrain and wrong in a brush file: the skirt then shares
## volume with the slab beneath it, and two brushes with a shared volume
## z-fight where they cross. The same hull shape, the same seed, just seated on
## the surface instead of through it. Mesh only, as every caller here is.
func _heap_on(c: Vector3, rx: float, ry: float, h: float, seed: int, tex: Variant) -> void:
	c.z = _up_to_hull_grid(c.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts: Array = []
	for ring: Vector3 in [Vector3(0.0, 1.0, 8), Vector3(0.65, 0.6, 8), Vector3(1.0, 0.25, 6)]:
		var count := int(ring.z)
		var turn := rng.randf_range(0.0, TAU)
		for i in count:
			var a := turn + TAU * (i + rng.randf_range(-0.15, 0.15)) / count
			var j := rng.randf_range(0.94, 1.04)
			pts.append(c + Vector3(cos(a) * rx * ring.y * j, sin(a) * ry * ring.y * j, h * ring.x))
	solid(pts, tex, 4)


## mound() from block_doodads, seated the same way and for the same reason.
func _mound_on(c: Vector3, rx: float, ry: float, h: float, seed: int, tex: Variant) -> void:
	c.z = _up_to_hull_grid(c.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts: Array = []
	for ring in [[0.0, 1.0], [0.45, 0.8], [0.8, 0.5], [1.0, 0.15]]:
		var t: float = ring[0]
		var k: float = ring[1]
		var count := 9 if k > 0.3 else 4
		for i in count:
			var a := TAU * i / count + rng.randf_range(-0.25, 0.25)
			var j := rng.randf_range(0.92, 1.05)
			pts.append(c + Vector3(cos(a) * rx * k * j, sin(a) * ry * k * j, t * h))
	solid(pts, tex, 4)


## A wedge of tread lying on a slope: its underside parallels the surface
## through (y_low, z_low) and (y_high, z_high), its top is flat at the high end
## and its riser faces the low end. Held 0.04 m off the surface, because a
## coincident sloped face snapped to a 1/32 m grid lands a unit on the wrong
## side of the plane it is meant to touch, and that unit is volume.
func _tread_wedge(x0: float, x1: float, y_low: float, z_low: float, y_high: float, z_high: float, tex: Variant) -> void:
	var e := 0.04
	var pts: Array = []
	for x: float in [x0, x1]:
		pts.append(Vector3(x, y_low, z_low + e))
		pts.append(Vector3(x, y_high, z_high + e))
		pts.append(Vector3(x, y_low, z_high + e))
	solid(pts, tex)


## A collar round a rectangular mass: `out` proud of its faces and `inn` back
## over its top, from z0 to z1, as four strips that butt at the corners. The
## corbels and the parapets on these buildings were each ONE solid slab the
## size of the whole footprint, which put the slab inside the mass it was
## meant to wrap and, for the parapet, buried everything standing on the roof.
func _rim(x0: float, y0: float, x1: float, y1: float, out: float, inn: float, z0: float, z1: float, tex: Variant) -> void:
	# The long sides take the corners.
	for s: float in [-1.0, 1.0]:
		var ya: float = (y1 if s > 0.0 else y0) - s * inn
		var yb: float = (y1 if s > 0.0 else y0) + s * out
		box(Vector3(x0 - out, minf(ya, yb), z0), Vector3(x1 + out, maxf(ya, yb), z1), tex)
	for s: float in [-1.0, 1.0]:
		var xa: float = (x1 if s > 0.0 else x0) - s * inn
		var xb: float = (x1 if s > 0.0 else x0) + s * out
		box(Vector3(minf(xa, xb), y0 + inn, z0), Vector3(maxf(xa, xb), y1 - inn, z1), tex)


# ── Scatter that keeps off what is already there ─────────────────────────────

## Footprints already spoken for in the piece being built, as 2D rectangles.
## Random scatter (heaps, rubbish, stones) was placed from a hash with no idea
## what else stood there, so it landed on top of the pieces beside it — and in
## a brush file two brushes sharing a volume z-fight where they cross. Anything
## scattered now claims its footprint first and is dropped if it is taken.
var _taken: Array = []


func _claim_reset() -> void:
	_taken = []


## True, and the footprint is recorded, if the rectangle about `c` is free.
## Rectangles that only touch are free: butting is what brush files are for.
func _claim(c: Vector2, rx: float, ry: float) -> bool:
	var r := Rect2(c.x - rx, c.y - ry, rx * 2.0, ry * 2.0)
	for t: Rect2 in _taken:
		if t.intersects(r):
			return false
	_taken.append(r)
	return true


## A seated heap that gives way to whatever already holds the ground. Its
## footprint is padded by one snap cell (0.125 m, the hull grid) so rounding
## cannot walk it into a neighbour. Returns whether it was placed; a skip is
## reported by the caller's count, not silently.
func _scatter_heap(c: Vector3, rx: float, ry: float, h: float, seed: int, tex: Variant) -> bool:
	if not _claim(Vector2(c.x, c.y), rx * 1.05 + 0.13, ry * 1.05 + 0.13):
		return false
	_heap_on(c, rx, ry, h, seed, tex)
	return true


## Claim a footprint that is NOT optional — a piece placed by hand. A refusal
## here means two fixed things overlap in the design, so it is a warning and
## not a quiet skip.
func _reserve(c: Vector2, rx: float, ry: float, what: String) -> void:
	if not _claim(c, rx, ry):
		push_warning("block_canal: %s at %s overlaps something already placed" % [what, c])


## A gabled roof between two party walls, ridge along x: the same hull as
## _gable but with NO overhang at the ends, only along the eaves. _gable
## overhangs on all four sides by one figure, which in a terrace pushes each
## roof 0.35 m into its neighbour's.
func _gable_run(x0: float, x1: float, y0: float, y1: float, eaves: float, ridge: float, over_y: float) -> void:
	var mid := (y0 + y1) * 0.5
	solid([Vector3(x0, y0 - over_y, eaves), Vector3(x1, y0 - over_y, eaves),
			Vector3(x1, y1 + over_y, eaves), Vector3(x0, y1 + over_y, eaves),
			Vector3(x0, mid, ridge), Vector3(x1, mid, ridge)], SHINGLE)


## `z` raised to the next multiple of 0.125 m (4 units), never lowered. solid()
## snaps these hulls to a 4-unit grid, so a base resting on a surface at some
## other height rounds to either side of it, and half the time that is the
## side inside the surface. A gap of a few centimetres under a bush is
## invisible; a shared volume is not.
func _up_to_hull_grid(z: float) -> float:
	return ceilf(z * UPM / 4.0 - 0.001) * 4.0 / UPM
