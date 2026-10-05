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

const CANAL := {
	"canal_prism": "_prism",
	"canal_prism_open": "_prism_open",
	"canal_truss_bridge": "_truss_bridge",
	"canal_road_bridge": "_road_bridge",
	"canal_lock": "_lock",
	"canal_cofferdam": "_cofferdam",
	"canal_outfall": "_outfall",
	"canal_stair_down": "_stair_down",
	"canal_bench": "_bench",
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
func _towpath(x0: float, x1: float) -> void:
	var y0 := BED_HALF + WALL_T
	box(Vector3(x0, y0, -1.0), Vector3(x1, y0 + TOW_W, 0.0), TOWPATH)
	box(Vector3(x0, y0 - 0.1, 0.0), Vector3(x1, y0 + 0.55, 0.3), {"top": COPING, "side": COPING, "bottom": COPING})


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
		heap(Vector3(x, (_hash_f(int(x) * 7) - 0.5) * 6.0, BED_Z), 1.1, 0.9, 0.55, int(x) + 3, SPOIL)
		if posmod(int(x), 5) == 0:
			heap(Vector3(x, -(BED_HALF + 0.3), -0.4), 0.7, 0.4, 0.9, int(x) + 11, SPOIL)
		x += 2.5


## The same with a towpath BOTH sides and no terrace: for the stretch where
## the canal runs between two walks instead of under the mills.
func _prism_open() -> void:
	_channel(-SEG * 0.5, SEG * 0.5)
	_towpath(-SEG * 0.5, SEG * 0.5)
	# Mirrored, by hand rather than by a flag, because the coping sits on the
	# canal side of the path and a mirrored call would put it on the outside.
	var y0 := -(BED_HALF + WALL_T)
	box(Vector3(-SEG * 0.5, y0 - TOW_W, -1.0), Vector3(SEG * 0.5, y0, 0.0), TOWPATH)
	box(Vector3(-SEG * 0.5, y0, 0.0), Vector3(SEG * 0.5, y0 + 0.1 + 0.55, 0.3), {"top": COPING, "side": COPING, "bottom": COPING})
	no_collision()
	var x := -SEG * 0.5 + 2.0
	while x < SEG * 0.5 - 1.0:
		heap(Vector3(x, (_hash_f(int(x) * 11) - 0.5) * 6.0, BED_Z), 1.0, 0.9, 0.5, int(x) + 5, SPOIL)
		x += 3.0


## THE FOOTBRIDGE: a riveted pony truss with a curved top chord, a concrete
## deck laid over it, and chain link up both sides. The thing in the second
## photograph, and the piece that makes the canal crossable.
##
## The deck is 2.6 m wide and its surface is at z = 0, LEVEL WITH BOTH BANKS.
## A bridge that arrives a step above the towpath is a bridge half the squad
## stands in front of, and 0.3 m is all it takes.
func _truss_bridge() -> void:
	var half := BED_HALF + WALL_T + 1.0
	var w := 1.3
	# The deck and the beams under it.
	box(Vector3(-w - 0.25, -half - 1.5, -0.45), Vector3(w + 0.25, half + 1.5, 0.0), {"top": CONCRETE, "side": CONCRETE, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * w - 0.1, -half - 1.0, -0.75), Vector3(s * w + 0.1, half + 1.0, -0.45), IRON)
	# The truss: a bottom chord, a curved top chord in five chords, and the
	# verticals and diagonals between them.
	for s: float in [-1.0, 1.0]:
		var y := s * (w + 0.2)
		box(Vector3(-w - 0.3, -half - 0.6, -0.5), Vector3(-w - 0.1, half + 0.6, -0.2), IRON)
		var pts: Array = []
		for i in 6:
			var t := float(i) / 5.0
			pts.append(Vector3(0.0, lerpf(-half, half, t), -0.2 + sin(t * PI) * 1.5))
		for i in 5:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			beam(Vector3(y, a.y, a.z), Vector3(y, b.y, b.z), 0.2, IRON)
		for i in range(1, 5):
			var p: Vector3 = pts[i]
			box(Vector3(y - 0.08, p.y - 0.08, -0.4), Vector3(y + 0.08, p.y + 0.08, p.z), IRON)
			var q: Vector3 = pts[i + 1] if i < 4 else pts[4]
			beam(Vector3(y, p.y, -0.4), Vector3(y, q.y, q.z), 0.1, IRON)
		# Chain link over the deck. Mesh only — a 1.2 m fence either side of a
		# 2.6 m deck with collision narrows the crossing to a metre and a half
		# after the navmesh erodes it, and this is the only way over.
		box(Vector3(y - 0.05, -half - 0.6, -0.2), Vector3(y + 0.05, half + 0.6, 1.25), IRON)
	no_collision()
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * (w + 0.22), -half - 0.6, 0.0), Vector3(s * (w + 0.26), half + 0.6, 1.2), GRATING)


## A LATER ROAD BRIDGE over the canal: a heavy concrete deck on the old iron,
## 7 m wide, carrying a street across. Dark underneath, which is the one piece
## of cover in a 300 m trench.
func _road_bridge() -> void:
	var half := BED_HALF + WALL_T + 1.6
	var w := 3.5
	box(Vector3(-w, -half - 2.0, -0.9), Vector3(w, half + 2.0, 0.0), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * w - 0.45, -half - 2.0, 0.0), Vector3(s * w, half + 2.0, 0.55), {"top": COPING, "side": COPING, "bottom": COPING})
		box(Vector3(s * w - 0.3, -half - 1.6, -1.25), Vector3(s * w - 0.1, half + 1.6, -0.9), IRON)
	# The abutments, carried down into the canal wall so the bridge and the
	# prism are one piece of masonry and not two things meeting.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-w - 0.4, s * (half + 0.4), BED_Z - 1.0), Vector3(w + 0.4, s * (half + 2.0), 0.0), STONE_W)
	no_collision()
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * (w - 0.22), -half - 1.8, 0.55), Vector3(s * (w - 0.18), half + 1.8, 1.65), GRATING)


## A LOCK CHAMBER, 28 m: the chamber narrowed to 5 m between its coped walls,
## a sill at each end, and the gates standing open against the recesses. The
## one place the prism has a floor a body can be surprised on.
func _lock() -> void:
	var half := 14.0
	var ch := 2.5
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
			box(Vector3(s * (half - 2.2), e * (ch - 0.45), BED_Z + 0.55), Vector3(s * (half - 6.4), e * ch, 0.6), {"top": WOOD_DARK, "side": WOOD, "bottom": WOOD_DARK})
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
	# The membrane behind it and the barrier on top.
	box(Vector3(-3.0, 0.6, BED_Z), Vector3(3.0, 0.75, BED_Z + 2.8), {"top": RUBBER, "side": RUBBER, "bottom": RUBBER})
	var top: float = BED_Z + rows * 0.9
	box(Vector3(-2.6, -0.4, top), Vector3(2.6, -0.3, top + 1.1), HAZARD)
	for i in 4:
		var x := lerpf(-2.5, 2.5, float(i) / 3.0)
		box(Vector3(x - 0.06, -0.42, top), Vector3(x + 0.06, -0.28, top + 1.15), HAZARD)


## A culvert mouth in the canal wall, with its apron and the stain below it.
func _outfall() -> void:
	box(Vector3(-1.6, BED_HALF - 0.1, BED_Z - 1.0), Vector3(1.6, BED_HALF + WALL_T, BED_Z + 1.9), STONE_W)
	_culvert_mouth(Vector3(0.0, BED_HALF + WALL_T, BED_Z + 0.75), 0.75, 0.6, 1.2, 8)
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


## STONE STEPS from the towpath down into the bed, set into the wall. The
## thing that decides where a fight in the prism can start and end, so it is
## its own piece and gets placed deliberately.
func _stair_down() -> void:
	var y0 := BED_HALF
	var steps := 16
	for i in steps:
		var z: float = BED_Z + (i + 1) * (0.0 - BED_Z) / steps
		var x := -2.6 + i * 0.33
		box(Vector3(x, y0 - 0.2, z - 0.4), Vector3(x + 0.34, y0 + WALL_T + 0.6, z), {"top": COPING, "side": RUBBLE_WALL, "bottom": CONCRETE})
	box(Vector3(-3.0, y0 - 0.3, BED_Z - 1.0), Vector3(-2.6, y0 + WALL_T + 0.7, 0.4), STONE_W)
	box(Vector3(3.1, y0 - 0.3, BED_Z - 1.0), Vector3(3.5, y0 + WALL_T + 0.7, 0.4), STONE_W)


# ── The terraces ─────────────────────────────────────────────────────────────

## A STRIP OF BENCH, 448 x 32. The benches were one 460 x 360 slab each to
## start with, four of them at four heights — and they overlapped so hard that
## the town's bench lay on top of the canal and buried it. A bench is only as
## deep as it is; tile these to the depth it actually needs and nothing covers
## anything.
func _bench() -> void:
	box(Vector3(-224.0, -16.0, -4.0), Vector3(224.0, 16.0, 0.0), {"top": ASPHALT, "side": RUBBLE_WALL, "bottom": CONCRETE})


## 32 m of coursed rubble retaining wall, 4 m, with ground behind it at the
## top. The piece every change of level on the map is made of.
func _terrace_wall() -> void:
	box(Vector3(-SEG * 0.5, -0.9, -2.0), Vector3(SEG * 0.5, 0.0, 4.0), STONE_W)
	box(Vector3(-SEG * 0.5, -0.9, 4.0), Vector3(SEG * 0.5, 0.15, 4.35), {"top": COPING, "side": COPING, "bottom": COPING})
	box(Vector3(-SEG * 0.5, -9.0, -2.0), Vector3(SEG * 0.5, -0.9, 4.0), {"top": WALK, "side": CONCRETE, "bottom": CONCRETE})
	no_collision()
	var x := -SEG * 0.5 + 2.0
	while x < SEG * 0.5 - 1.0:
		heap(Vector3(x, 0.05, 2.4), 0.5, 0.25, 1.4, int(x) * 3 + 7, SPOIL)
		x += 4.0


## A PUBLIC STAIR up a 4 m terrace, 2.8 m wide with a half landing and a wall
## both sides. Nineteen risers at 0.21, which is a stair a body climbs rather
## than a ramp pretending to be one.
func _terrace_stair() -> void:
	var steps := 19
	var rise := 4.0 / steps
	var tread := 0.34
	for i in steps:
		var y := -float(i) * tread - (2.2 if i >= steps / 2 else 0.0)
		box(Vector3(-1.4, y - tread, -1.0), Vector3(1.4, y, (i + 1) * rise), {"top": COPING, "side": RUBBLE_WALL, "bottom": CONCRETE})
	var total := -float(steps) * tread - 2.2
	box(Vector3(-1.4, total - 2.4, -1.0), Vector3(1.4, total, 4.0), {"top": COPING, "side": RUBBLE_WALL, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * 1.4, total - 2.4, -1.0), Vector3(s * 2.0, 0.6, 4.0), STONE_W)


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
	# The footway on one side, stepped so it keeps up with the road.
	for i in 16:
		var x := -run * 0.5 + i * 2.0
		var z := lerpf(4.0, 0.0, float(i) / 15.0)
		box(Vector3(x, 3.5, z - 0.6), Vector3(x + 2.0, 4.4, z + 0.15), {"top": TOW_BRICK, "side": COPING, "bottom": CONCRETE})


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
		box(Vector3(-half - 0.18, -d - 0.18, z), Vector3(half + 0.18, d + 0.18, z + 0.35), MILL_BRICK)
	box(Vector3(-half - 0.25, -d - 0.25, top), Vector3(half + 0.25, d + 0.25, top + 1.0), {"top": COPING, "side": MILL_BRICK, "bottom": MILL_BRICK})
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
				window("y", s * d, x - 0.55, z, 1.1, 1.9, true, DARK_GLASS)
				# The arch over each: three stepped boxes, which at this size
				# is a segmental arch and costs three brushes instead of ten.
				box(Vector3(x - 0.62, s * d - s * 0.12, z + 1.9), Vector3(x + 0.62, s * (d + 0.08), z + 2.05), MILL_BRICK)
	# The downpipe, which every photograph of one of these has down its face.
	box(Vector3(-4.0, d, -4.0), Vector3(-3.78, d + 0.22, top - 0.5), IRON)
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
		box(Vector3(-half - 0.18, -d - 0.18, z), Vector3(half + 0.18, d + 0.18, z + 0.4), MILL_BRICK)
	no_collision()
	for lvl in 4:
		var z: float = 1.2 + lvl * 3.2
		for i in 8:
			var x := lerpf(-half + 2.4, half - 2.4, float(i) / 7.0)
			for s: float in [-1.0, 1.0]:
				window("y", s * d, x - 0.7, z, 1.4, 2.1, true, DARK_GLASS)
	# The added floor: steel and glass set back from the brick, with a
	# shallow hipped lantern over it.
	box(Vector3(-half + 1.2, -d + 1.2, top), Vector3(half - 1.2, d - 1.2, top + 3.4), STORE_GLASS)
	for i in 9:
		var x := lerpf(-half + 1.2, half - 1.2, float(i) / 8.0)
		for s: float in [-1.0, 1.0]:
			box(Vector3(x - 0.12, s * (d - 1.3), top), Vector3(x + 0.12, s * (d - 1.1), top + 3.4), METAL)
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
		box(Vector3(-1.4, d - 0.3, z), Vector3(1.4, d + 0.1, z + 2.4), WOOD_DARK)
		box(Vector3(-1.6, d - 0.1, z + 2.4), Vector3(1.6, d + 0.18, z + 2.6), MILL_BRICK)
		for i in 3:
			var x := lerpf(-half + 3.0, half - 3.0, float(i) / 2.0)
			if absf(x) < 3.0:
				continue
			window("y", d, x - 0.6, z, 1.2, 1.8, true, DARK_GLASS)
			window("y", -d, x - 0.6, z, 1.2, 1.8, true, DARK_GLASS)
	# The hoist beam over the top door.
	box(Vector3(-0.22, d, top - 1.6), Vector3(0.22, d + 2.2, top - 1.2), WOOD_DARK)
	box(Vector3(-0.35, d + 1.8, top - 2.6), Vector3(0.35, d + 2.1, top - 1.2), IRON)


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
			box(Vector3(-half + 1.2, s * d - s * 0.22, z), Vector3(half - 1.2, s * d, z + 1.7), DARK_GLASS)
			box(Vector3(s * half - s * 0.22, -d + 1.2, z), Vector3(s * half, d - 1.2, z + 1.7), DARK_GLASS)
		for i in 9:
			var x := lerpf(-half + 1.2, half - 1.2, float(i) / 8.0)
			for s: float in [-1.0, 1.0]:
				box(Vector3(x - 0.14, s * d - s * 0.26, z), Vector3(x + 0.14, s * d + s * 0.02, z + 1.7), MILL_BRICK)
	_rooftop_plant(-half + 4.0, -d + 4.0, half - 4.0, d - 4.0, top + 3.2, 311)


## THE CAFÉ TERRACE above the canal wall: a railed deck with parasols, the
## blue ones over the wall in both photographs. A balcony overlooking a
## trench, which is a firing position with tables on it.
func _cafe_terrace() -> void:
	box(Vector3(-9.0, -5.0, -2.0), Vector3(9.0, 5.0, 0.0), {"top": TOW_BRICK, "side": RUBBLE_WALL, "bottom": CONCRETE})
	for e: Array in [[-9.0, 5.0, 9.0, 5.0], [-9.0, -5.0, -9.0, 5.0], [9.0, -5.0, 9.0, 5.0]]:
		box(Vector3(e[0] - 0.06, e[1] - 0.06, 0.0), Vector3(e[2] + 0.06, e[3] + 0.06, 1.05), IRON)
	for i in 7:
		var x := lerpf(-8.6, 8.6, float(i) / 6.0)
		box(Vector3(x - 0.05, 4.9, 0.0), Vector3(x + 0.05, 5.1, 1.1), IRON)
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
	for z: float in [0.95, 1.42]:
		box(Vector3(-half + 1.0, -0.33, z), Vector3(half - 1.0, -0.25, z + 0.08), IRON)


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
	for i in 14:
		var x := -270.0 + i * 40.0 + _hash_f(i * 17) * 14.0
		var w := 9.0 + _hash_f(i * 5) * 13.0
		var h := 12.0 + _hash_f(i * 23) * 26.0
		box(Vector3(x - w, -14.0 - _hash_f(i) * 30.0, 0.0), Vector3(x + w, -14.0, h),
				{"top": CONCRETE, "side": PALE, "bottom": CONCRETE})
	for i in 30:
		var x := -290.0 + i * 20.0
		heap(Vector3(x, -10.0, 1.5), 7.0, 5.0, 7.0, i * 13 + 3, SPOIL)
