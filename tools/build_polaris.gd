extends SceneTree

# ─────────────────────────────────────────────
# BUILD POLARIS — assembles maps/polaris_art.tscn and maps/polaris_level.tscn
# from the suburban, street, suburbs and polaris block families.
#
#   godot --headless --path . --script res://tools/build_polaris.gd
#   godot --headless --path . --script res://tools/build_polaris.gd -- --force
#
# THE LAYOUT IS THIS FILE AND NOTHING ELSE. There is no painted sketch and no
# terrain recipe, because the site has no terrain: a mall is a graded slab,
# and the only ground feature on the real one is the detention basin, which is
# a block. That makes this the one level in the project whose shape is
# entirely in a list of transforms, and the reason it can be is that the
# geometry was built as a kit first.
#
# IT IS MODELLED ON POLARIS FASHION PLACE, COLUMBUS, and the four things that
# were worth copying off it are:
#
#   - the mall is ONE MASS with the anchors as lobes, not a row of buildings;
#   - a CLOSED RING ROAD loops round it as a rounded rectangle, so there is no
#     corner of the site a vehicle cannot reach and no straight longer than
#     about 150 m;
#   - the parking between them is A FAN OF AISLES, each with an island its
#     whole length, which is the only thing breaking up 400 m of asphalt;
#   - THE RESTAURANTS ARE OUTSIDE THE LOOP in a row of detached pads with open
#     ground between them. That row is the best infantry ground on the site
#     and it is the reason this is a map and not a car park.
#
# WHAT IT DOES NOT DO: bake the navmesh. Nothing here does.
#
#   BAKE_ONLY=1 LEVEL=res://maps/polaris_level.tscn godot --path . \
#       --script res://tools/probe_nav_hillfort.gd
# ─────────────────────────────────────────────

const ART := "res://maps/polaris_art.tscn"
const LEVEL := "res://maps/polaris_level.tscn"

const B_SUBURBAN := "res://maps/blocks/suburban/%s.tscn"
const B_STREETS := "res://maps/blocks/streets/%s.tscn"
const B_SUBURBS := "res://maps/blocks/suburbs/%s.tscn"
const B_POLARIS := "res://maps/blocks/polaris/%s.tscn"

## The ring road's rounded rectangle. The corner piece is 90° on a 50 m
## centreline with its origin AT THE CIRCLE CENTRE, so the four corners go in
## at the four corners of this rectangle and the straights fill between them.
# 144 and not 150: the straights are laid as whole 32 m pieces, and 2 x 150 is
# 9.375 of them. Rounding to 9 gave a 33.3 m pitch for a 32 m piece, so the
# kerb broke by 1.3 m sixteen times round the ring. 2 x 144 is exactly 9.
const RING_X := 144.0
## 112 and not 110: the straights are 32 m pieces and 2 x 112 is seven of them
## exactly. At 110 it is 220 m, seven pieces laid on a 31.4 m pitch overlapped
## each other and the corners by half a metre each.
const RING_Y := 112.0
const RING_R := 50.0

## Half-widths of the pieces that have to be laid side by side, MEASURED from
## their collision (6.31, 11.41, 7.06, 32.06) and rounded UP to a tenth, so two
## pieces placed edge to edge touch and never share a sliver.
const ROAD2_HALF := 6.4
const ROAD4_HALF := 11.5
const AISLE_HALF_W := 7.1
const AISLE_HALF_L := 32.1
## The lot-entry throat is 18 m across the road it meets (measured); a throat
## meets a road as a junction, so it starts at the carriageway's edge and
## not 3 m inside it, which is where it stood.
const THROAT_HALF_Z := 9.1
## The end aisles stand INSIDE the ring road's straights, which are at x = +-200
## and 6.4 wide each side. 152 + 2 x 17 puts the outermost one's outer edge at
## 193.1; at the old pitch of 20 it was 199.1, inside the road.
const END_PITCH := 17.0

var _cache := {}


func _initialize() -> void:
	await process_frame
	var force := OS.get_cmdline_user_args().has("--force")
	for p: String in [ART, LEVEL]:
		if FileAccess.file_exists(ProjectSettings.globalize_path(p)) and not force:
			print("SKIP  %s exists — pass --force to rebuild it." % p)
			quit()
			return

	var art := Node3D.new()
	art.name = "PolarisArt"
	root.add_child(art)
	art.owner = null

	_ring_road(art)
	_mall(art)
	_parking(art)
	_outlots(art)
	_power_centre(art)
	_housing(art)
	# LAST, not first: it is built from what the others placed.
	_ground(art)

	var placed := _own(art, art)
	var packed := PackedScene.new()
	var err := packed.pack(art)
	if err != OK:
		print("FAIL  could not pack the art scene (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, ART)
	if err != OK:
		print("FAIL  could not save %s (%s)" % [ART, error_string(err)])
		quit(1)
		return
	print("      %s  %d pieces" % [ART.get_file(), placed])

	_write_level()
	print("      %s" % LEVEL.get_file())
	if _clashes > 0:
		print("      PLACEMENT GUARD: %d clash(es) — see the warnings above" % _clashes)
	else:
		print("      PLACEMENT GUARD: clean")
	print("BUILD POLARIS DONE")
	quit()


## Instance ROOTS are owned by the art root and nothing inside them is.
##
## This is the rule that was learned the expensive way on the art/level split:
## a packed scene writes every node its root owns, so setting the owner of an
## instance's INTERNALS writes them out as declared nodes, pins them, and
## quietly stops edits to the block in maps/blocks reaching the level that
## instances it. Hillfort's 96 prefabs became 2353 node entries that way.
func _own(node: Node, root_node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if c.scene_file_path != "":
			c.owner = root_node
			n += 1
			continue
		c.owner = root_node
		n += _own(c, root_node)
	return n


## One instance of `path`, at x,z metres, yawed `yaw` degrees, under `parent`.
func _put(parent: Node3D, path: String, x: float, z: float, yaw: float = 0.0, y: float = 0.0, name := "") -> Node3D:
	if not _cache.has(path):
		var packed := load(path) as PackedScene
		if packed == null:
			# Say which one and keep going: a layout that silently loses a
			# building is worse than one that is loudly missing it.
			push_warning("build_polaris: no prefab at %s — nothing placed" % path)
			_cache[path] = null
			return null
		_cache[path] = packed
	if _cache[path] == null:
		return null
	var inst := (_cache[path] as PackedScene).instantiate() as Node3D
	inst.name = name if name != "" else path.get_file().get_basename()
	parent.add_child(inst)
	inst.position = Vector3(x, y, z)
	inst.rotation_degrees = Vector3(0.0, yaw, 0.0)
	# Anything that brings its own walking surface is recorded here and the
	# ground is laid from the record at the end. See _ground: three earlier
	# attempts described the ground by hand and every one of them drifted from
	# where the roads actually went.
	for part: String in SURFACE_PARTS:
		if path.contains(part):
			_surfaces.append(_footprint(inst))
			break
	_guard(inst, path)
	return inst


# ── The placement guard ──────────────────────────────────────────────────────
#
# THE BUILDER KNOWS EVERY FOOTPRINT AT THE MOMENT IT PUTS A PIECE DOWN, so it
# says so then. The alternative — build, probe, move one piece to clear one
# clash, probe again — is whack-a-mole: each piece moved lands on something
# else, and Georgetown took four passes to get from seventy clashes to fifty
# that way. Here the warning names both pieces and the volume they share, and
# the fix is one edit.
#
# THE STANDING RULE: pieces may touch, they may not overlap. A face shared
# exactly, back to back, is fine; interpenetration of any depth flickers.
#
# MEASURED SHAPE AGAINST SHAPE, NOT PIECE AGAINST PIECE. A piece's envelope is
# a box round everything it collides with, and a car park aisle's envelope is
# 64 x 14 m even though the aisle itself is a few kerbs and islands. Two
# envelopes sharing a corner is not a fault; two COLLIDERS sharing volume is.
# So the envelopes are a cheap first cut and the answer is the sum over every
# pair of colliders inside them.
#
# Colliders only, which is what the level probe measures too. A mesh-only
# piece (a sign face, a hedge) has nothing for the guard to compare.

## Paths that are the site's ground. A building is MEANT to be founded into its
## slab, so a ground piece is never compared with anything.
const GROUND_PIECES: Array = ["ground/tile_", "polaris_lot_main", "polaris_lot_field", "polaris_ground_grass"]
## Volume two pieces must share before it is called a clash. Below this is the
## rounding of a rotated box's own envelope, not a fault.
const PLACEMENT_M3 := 0.25

var _placed: Array = []
var _clashes := 0


func _is_ground(path: String) -> bool:
	for p: String in GROUND_PIECES:
		if path.contains(p):
			return true
	return false


## Pairs of piece names (as prefixes) that are MEANT to share volume. EMPTY, and
## it should stay that way unless something genuinely founds into something.
##
## The car rows are not in it, and the brief for this pass expected them to be:
## a row and its aisle share an ENVELOPE (a 64 x 14 m box round the aisle's
## kerbs and islands holds the cars parked beside them), which is what the
## level probe counts, so the probe lists about 38 of them. Measured collider
## against collider there is NO shared volume at all: switching this list off
## and building again gave zero car-row warnings. Suppressing them would only
## have blinded the guard to a car parked ON an island, which is a real fault.
const EXPECTED: Array = []


func _expected(a: String, b: String) -> bool:
	for e: Array in EXPECTED:
		if (a.begins_with(e[0]) and b.begins_with(e[1])) or (b.begins_with(e[0]) and a.begins_with(e[1])):
			return true
	return false


## World AABB of every collider under `n`, one per shape.
func _shape_boxes(n: Node3D) -> Array:
	var out: Array = []
	for cs: CollisionShape3D in n.find_children("*", "CollisionShape3D", true, false):
		if cs.shape == null:
			continue
		var m := cs.shape.get_debug_mesh()
		if m == null:
			continue
		out.append(cs.global_transform * m.get_aabb())
	return out


func _guard(inst: Node3D, path: String) -> void:
	if _is_ground(path):
		return
	var shapes := _shape_boxes(inst)
	if shapes.is_empty():
		return
	var box: AABB = shapes[0]
	for s: AABB in shapes:
		box = box.merge(s)
	for other: Dictionary in _placed:
		if not box.intersects(other.box) or _expected(inst.name, other.name):
			continue
		var shared := 0.0
		var where := AABB()
		var first := true
		for a: AABB in shapes:
			for b: AABB in other.shapes:
				if not a.intersects(b):
					continue
				var s := a.intersection(b)
				shared += s.size.x * s.size.y * s.size.z
				where = s if first else where.merge(s)
				first = false
		if shared > PLACEMENT_M3:
			_clashes += 1
			var c := where.get_center()
			push_warning("build_polaris: %s overlaps %s by %.1f m3 around (%.0f, %.0f, %.0f) — move one of them" % [
					inst.name, other.name, shared, c.x, c.y, c.z])
	_placed.append({"name": String(inst.name), "box": box, "shapes": shapes})


func _group(parent: Node3D, name: String) -> Node3D:
	var g := Node3D.new()
	g.name = name
	parent.add_child(g)
	return g


# ── Which way round everything goes ──────────────────────────────────────────
#
# FUNCGODOT MAPS QUAKE (x, y, z) TO GODOT (y, z, x). Every consequence of that
# is written here once, because guessing it at each of two hundred call sites
# is how the first assembly of this map came out with its ring road at right
# angles to its own corners.
#
#   - a block built ALONG ITS MAP X runs along GODOT'S Z. So a road laid with
#     no rotation runs north-south on this site, not east-west.
#   - a block whose FRONT is its map +Y faces GODOT'S +X, which is east here.
#
# +Z is south on this site, because the frontage and the restaurant row are
# on the +Z side and that is the way a player arrives.

## A piece that runs along its own map X, laid along the site's X or Z.
const ALONG_X := 90.0
const ALONG_Z := 0.0
## A piece whose front is its map +Y, turned to face each way.
const FACE_EAST := 0.0
const FACE_NORTH := 90.0
const FACE_WEST := 180.0
const FACE_SOUTH := 270.0


# ── The site ─────────────────────────────────────────────────────────────────

## THE GROUND, ONE TILE PER CELL, DERIVED FROM WHAT WAS ACTUALLY PLACED.
##
## Four goes at this, and the first three were all the same mistake in
## different clothes: the ground was described BY HAND and the things standing
## on it were described somewhere else, so the two drifted.
##
##   - one plate per material, everything laid on top: 1,231 of 8,119 columns
##     with two floors at the same height. 15% of the map crawling, because the
##     depth buffer cannot choose between a road bed and the slab under it.
##   - holes cut for the roads: the flicker went, and 451 empty columns
##     arrived, because a tile is dropped if it so much as touches a hole and
##     so every road had a gap beside it.
##   - tile-aligned asphalt corridors under the roads, typed out as three
##     rectangles: 3,528 empty columns. The rectangles were wrong. _corridor()
##     takes a CENTRE and I passed it the left edge, so the frontage corridor
##     ran from x -768 to 0 — three hundred metres of asphalt off the west side
##     of the map and bare dirt under the eastern half of its own road.
##
## That last one is the lesson. A hand-typed rectangle describing where a road
## is will be wrong the first time the road moves, and nothing will say so.
##
## So the ground is built LAST and it is built from the record: _put() measures
## anything whose prefab brings its own walking surface, _ground() asks for
## those footprints, and every 32 m cell of the site gets EXACTLY ONE tile —
## asphalt where a surface lands on it, dirt everywhere else. One tile per cell
## is what rules out both faults at once: no cell can be empty and no cell can
## be covered twice. Then 2 x 2 blocks of one kind merge into a 64 m tile, which
## is only an instance count, not a correctness matter.
const B_GROUND := "res://maps/blocks/ground/%s.tscn"
## The whole site, a whole number of cells each way: 26 x 24.
const SITE := Rect2(-416.0, -384.0, 832.0, 768.0)
const CELL := 32.0
## The car park, which is asphalt whether or not anything is parked on it.
const LOT := Rect2(-224.0, -192.0, 448.0, 384.0)
## Prefabs that bring their own walking surface, and so need asphalt under
## them rather than dirt. Matched as substrings of the prefab path.
const SURFACE_PARTS: Array = [
	"street_road", "street_lot_entry", "street_sidewalk", "street_kerb",
	"polaris_aisle", "polaris_ring_corner", "polaris_entry",
]

## THE HOLES IN THE GROUND, AND THE BASINS THAT FILL THEM, ARE ONE LIST.
##
## Each entry is a 64 m block of the site, counted in blocks from SITE's
## north-west corner (so (0, 0) is x -416..-352, z -384..-320). _ground() lays
## no tile in a void and puts a suburb_retention_basin_64 in it, whose outer
## footprint is exactly 64 x 64 m. They cannot drift apart because there is
## only this list: the lesson of the whole ground rewrite is that a second,
## hand-typed set of rectangles is the bug.
##
## WHERE, AND WHY. Both are in the dirt EAST of the car park, one beside each
## of the ring road's eastern corners, at x 224..288. A real detention basin is
## on the perimeter at the low corner of a site, not in the middle of the
## parking; the east side is the one with nothing on it (the west has the
## power centre and the north has the houses), and a squad crossing the ring
## road on that flank gets a hole to fight round in place of more asphalt.
## Blocks (10, 3) and (10, 8) are x 224..288, z -192..-128 and 128..192.
const VOIDS: Array = [Vector2i(10, 3), Vector2i(10, 8)]
const BLOCK := 64.0
const B_BASIN := "res://maps/blocks/suburbs/suburb_retention_basin_64.tscn"

## Objective positions recorded at placement time, which override OBJECTIVES.
var _anchors: Dictionary = {}
var _tiles := 0
## World-space XZ footprints of every surface piece placed so far.
var _surfaces: Array = []


func _ground(art: Node3D) -> void:
	var g := _group(art, "Ground")
	# Ground first in the tree even though it is built last: in the editor the
	# order is the only clue to what is scenery and what is the site.
	art.move_child(g, 0)
	var nx := int(SITE.size.x / CELL)
	var nz := int(SITE.size.y / CELL)
	var asphalt := {}
	var strays := 0
	for r: Rect2 in _surfaces:
		strays += _mark(asphalt, r, nx, nz)
	_mark(asphalt, LOT, nx, nz)
	if strays > 0:
		# Not fatal, but it means a road has moved off the site and the ground
		# cannot follow it. Say which way to grow SITE.
		push_warning("build_polaris: %d surface piece(s) lie outside SITE — the ground stops at the site edge" % strays)
	# A void is checked against the record before anything is laid in it: a
	# road, aisle or lot that reached into a hole would be paved over by the
	# basin and nobody would be told.
	for v: Vector2i in VOIDS:
		var vr := _block_rect(v)
		for r: Rect2 in _surfaces:
			if r.size.x > 0.0 and vr.grow(-0.01).intersects(r):
				push_warning("build_polaris: a surface piece reaches into the void at block %s — move it or move the void" % v)
				break
		if vr.intersection(LOT).has_area():
			push_warning("build_polaris: the void at block %s lies on the car park — the basin would replace asphalt" % v)
	# 2 x 2 cells of one kind become one 64 m tile; the rest stay 32s.
	for bx in nx / 2:
		for bz in nz / 2:
			if VOIDS.has(Vector2i(bx, bz)):
				var vr := _block_rect(Vector2i(bx, bz))
				_put(g, B_BASIN, vr.get_center().x, vr.get_center().y, 0.0, 0.0, "Basin_%d_%d" % [bx, bz])
				continue
			var kinds: Array = []
			for i in 2:
				for j in 2:
					kinds.append("asphalt" if asphalt.has(Vector2i(bx * 2 + i, bz * 2 + j)) else "dirt")
			if kinds[0] == kinds[1] and kinds[1] == kinds[2] and kinds[2] == kinds[3]:
				_tile(g, kinds[0], 64.0,
						SITE.position.x + bx * 64.0 + 32.0, SITE.position.y + bz * 64.0 + 32.0)
			else:
				for i in 2:
					for j in 2:
						var ix := bx * 2 + i
						var iz := bz * 2 + j
						_tile(g, kinds[i * 2 + j], CELL,
								SITE.position.x + ix * CELL + CELL * 0.5,
								SITE.position.y + iz * CELL + CELL * 0.5)
	print("      ground: %d tile(s) over %d cell(s), %d asphalt" % [_tiles, nx * nz, asphalt.size()])


## Mark every cell `r` touches. Returns 1 if it reached outside the site.
func _mark(cells: Dictionary, r: Rect2, nx: int, nz: int) -> int:
	# A hair inside each edge, so a piece that ENDS exactly on a cell line does
	# not claim the cell beyond it. Road runs are 32 m long and land on the
	# lines, and without this every one of them paved a spare cell each way.
	var x0 := int(floorf((r.position.x - SITE.position.x + 0.01) / CELL))
	var z0 := int(floorf((r.position.y - SITE.position.y + 0.01) / CELL))
	var x1 := int(ceilf((r.end.x - SITE.position.x - 0.01) / CELL)) - 1
	var z1 := int(ceilf((r.end.y - SITE.position.y - 0.01) / CELL)) - 1
	var stray := 1 if x0 < 0 or z0 < 0 or x1 >= nx or z1 >= nz else 0
	for ix in range(maxi(x0, 0), mini(x1, nx - 1) + 1):
		for iz in range(maxi(z0, 0), mini(z1, nz - 1) + 1):
			cells[Vector2i(ix, iz)] = true
	return stray


## The 64 m block `b` of the site, as a rectangle in world XZ.
func _block_rect(b: Vector2i) -> Rect2:
	return Rect2(SITE.position.x + b.x * BLOCK, SITE.position.y + b.y * BLOCK, BLOCK, BLOCK)


func _tile(g: Node3D, kind: String, size: float, cx: float, cz: float) -> void:
	_put(g, B_GROUND % ("tile_%s_%d" % [kind, int(size)]), cx, cz, 0.0, 0.0,
			"Ground_%s_%d" % [kind.substr(0, 3).to_upper(), _tiles])
	_tiles += 1


## The XZ footprint of everything under `n`, MESH INCLUDED.
##
## Mesh and not just collision, because a road inlay is exactly the piece that
## has no collision of its own any more — it is kerbs, islands and markings on
## ground somebody else brings. Measuring its colliders would give the kerbs
## and miss the carriageway between them.
func _footprint(n: Node3D) -> Rect2:
	var box := AABB()
	var first := true
	for m: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if m.mesh == null:
			continue
		var b := m.global_transform * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	for cs: CollisionShape3D in n.find_children("*", "CollisionShape3D", true, false):
		if cs.shape == null:
			continue
		var r := cs.shape.get_debug_mesh()
		if r == null:
			continue
		var b := cs.global_transform * r.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return Rect2(n.position.x, n.position.z, 0.0, 0.0)
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


## Godot sends +X +Z to +X -Z and not to -X +Z.
func _ring_road(art: Node3D) -> void:
	var g := _group(art, "RingRoad")
	var corners: Array = [
		[RING_X, RING_Y, 0.0],
		[-RING_X, RING_Y, 270.0],
		[-RING_X, -RING_Y, 180.0],
		[RING_X, -RING_Y, 90.0],
	]
	for i in corners.size():
		var c: Array = corners[i]
		_put(g, B_POLARIS % "polaris_ring_corner", c[0], c[1], c[2], 0.0, "Corner_%d" % i)
	# The straights. The two that run across the site's X are turned ALONG_X;
	# the two that run up its Z are left alone.
	var along_x := int(round((RING_X * 2.0) / 32.0))
	for s: float in [-1.0, 1.0]:
		for i in along_x:
			var x := -RING_X + (i + 0.5) * (RING_X * 2.0 / along_x)
			_put(g, B_STREETS % "street_road_two_lane_inlay", x, s * (RING_Y + RING_R), ALONG_X, 0.0,
					"RingX_%s_%d" % ["S" if s > 0.0 else "N", i])
	var along_z := int(round((RING_Y * 2.0) / 32.0))
	for s: float in [-1.0, 1.0]:
		for i in along_z:
			var z := -RING_Y + (i + 0.5) * (RING_Y * 2.0 / along_z)
			_put(g, B_STREETS % "street_road_two_lane_inlay", s * (RING_X + RING_R), z, ALONG_Z, 0.0,
					"RingZ_%s_%d" % ["E" if s > 0.0 else "W", i])
	_ring_lights(g)


## THE RING ROAD'S LIGHTS, standing outside the carriageway on its own lines.
##
## They used to be sixteen points on an ellipse, which is not the road's shape:
## a rounded rectangle is straight for most of its length, and an ellipse
## drawn through its corners crosses the straights, so four of them stood in
## the kerb. Each straight now gets its own, and the corners get one on the
## arc. The west straight gets none: the power centre's boulevard runs right
## beside it and a light there would stand on that carriageway.
func _ring_lights(g: Node3D) -> void:
	var off := ROAD2_HALF + 3.0
	var n := 0
	for s: float in [-1.0, 1.0]:
		for x: float in [-105.0, -45.0, 45.0, 105.0]:
			_put(g, B_SUBURBAN % "suburban_lot_light", x, s * (RING_Y + RING_R + off), 0.0, 0.0, "RingLight_%d" % n)
			n += 1
	for z: float in [-56.0, 56.0]:
		_put(g, B_SUBURBAN % "suburban_lot_light", RING_X + RING_R + off, z, 0.0, 0.0, "RingLight_%d" % n)
		n += 1
	var d := (RING_R + off) * 0.7071
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_put(g, B_SUBURBAN % "suburban_lot_light", sx * (RING_X + d), sz * (RING_Y + d), 0.0, 0.0, "RingLight_%d" % n)
			n += 1


## THE MALL: two wings side by side along the site's X with an anchor pushed
## out of each end, the glazed court facing the car park to the south, and the
## service docks on the north where nobody arrives. One mass.
func _mall(art: Node3D) -> void:
	var g := _group(art, "Mall")
	_put(g, B_POLARIS % "polaris_mall_wing", -38.0, 0.0, ALONG_X, 0.0, "WingWest")
	_put(g, B_POLARIS % "polaris_mall_wing", 38.0, 0.0, ALONG_X, 0.0, "WingEast")
	_put(g, B_SUBURBAN % "suburban_mall_anchor", -108.0, 0.0, FACE_WEST, 0.0, "AnchorWest")
	_put(g, B_SUBURBAN % "suburban_mall_anchor", 108.0, 0.0, FACE_EAST, 0.0, "AnchorEast")
	_put(g, B_SUBURBAN % "suburban_mall_entry", 0.0, 34.0, FACE_SOUTH, 0.0, "EntryCourt")
	_put(g, B_SUBURBAN % "suburban_service_dock", -40.0, -30.0, FACE_NORTH, 0.0, "ServiceDock")
	_put(g, B_SUBURBAN % "suburban_service_dock", 51.0, -30.0, FACE_NORTH, 0.0, "ServiceDockEast")
	# The cinema and the deck, inside the loop at the two free corners.
	_put(g, B_POLARIS % "polaris_cinema", -120.0, 84.0, FACE_SOUTH, 0.0, "Cinema")
	_put(g, B_POLARIS % "polaris_parking_garage", 128.0, 74.0, ALONG_X, 0.0, "Garage")
	_put(g, B_SUBURBAN % "suburban_big_box", 112.0, -74.0, FACE_NORTH, 0.0, "Fieldhouse")


## THE PARKING FAN, and the cars in it.
##
## THE CAR ROWS ARE THE POINT OF THIS PASS. The first assembly gave the mall
## four hundred metres of flat asphalt with nothing on it taller than a kerb,
## and a squad crossing that had no decision to make and nowhere to make it.
## A parked car is 1.45 m: over the 1.2 m a standing cover point probes at and
## under a head, so a row of them is cover you fire over from a crouch and get
## shot over from a stand. The lot nearest the doors is packed, the far corners
## are emptying, and the gradient between those is the map telling a player
## where it is safe to cross.
func _parking(art: Node3D) -> void:
	var g := _group(art, "Parking")
	var cars := _group(art, "ParkedCars")
	for i in 5:
		var z := 58.0 + i * 20.0
		# 1.2 degrees, not 2.5: at 2.5 the outer aisles in a fan of five crossed
		# their neighbours at the ends, two asphalt surfaces in one place.
		var fan := (i - 2) * 1.2
		for s: float in [-1.0, 1.0]:
			var yaw: float = ALONG_X + s * fan
			_put(g, B_POLARIS % "polaris_aisle_long", s * 34.0, z, yaw, 0.0,
					"SouthAisle_%d_%s" % [i, "E" if s > 0.0 else "W"])
			# A row of cars down each side of every aisle. The near aisles are
			# full and the far ones are not, which is what a car park does.
			var full: bool = i < 3
			for e: float in [-1.0, 1.0]:
				_put(cars, B_POLARIS % ("lot_car_row" if full else "lot_car_row_sparse"),
						s * 34.0 + e * 0.0, z + e * 4.3, yaw, 0.0,
						"SouthCars_%d_%s_%s" % [i, "E" if s > 0.0 else "W", "a" if e > 0.0 else "b"])
	for i in 3:
		var z := -58.0 - i * 20.0
		for s: float in [-1.0, 1.0]:
			var yaw: float = ALONG_X - s * (i - 1) * 3.0
			_put(g, B_POLARIS % "polaris_aisle_long", s * 36.0, z, yaw, 0.0,
					"NorthAisle_%d_%s" % [i, "E" if s > 0.0 else "W"])
			for e: float in [-1.0, 1.0]:
				_put(cars, B_POLARIS % "lot_car_row_sparse", s * 36.0, z + e * 4.3, yaw, 0.0,
						"NorthCars_%d_%s_%s" % [i, "E" if s > 0.0 else "W", "a" if e > 0.0 else "b"])
	for s: float in [-1.0, 1.0]:
		for i in 3:
			_put(g, B_POLARIS % "polaris_aisle_long", s * (146.0 + i * END_PITCH), 0.0, ALONG_Z, 0.0,
					"EndAisle_%s_%d" % ["E" if s > 0.0 else "W", i])
			for e: float in [-1.0, 1.0]:
				_put(cars, B_POLARIS % "lot_car_row_sparse", s * (146.0 + i * END_PITCH) + e * 4.3, 0.0, ALONG_Z, 0.0,
						"EndCars_%s_%d_%s" % ["E" if s > 0.0 else "W", i, "a" if e > 0.0 else "b"])
	# Things in the lot that are neither a car nor a kerb. Every one of these
	# is between waist and head height on purpose: a car park's real cover is
	# all accidental, and this is the accident.
	# Not the two at x +-16: the entry court stands there, down to z 48.
	for i: int in [0, 1, 4, 5]:
		_put(g, B_SUBURBAN % "suburban_cart_corral", -80.0 + i * 32.0, 48.0, ALONG_X, 0.0, "Corral_%d" % i)
	# Three, not five: the outer two stood in the cinema and the garage.
	for i in 3:
		_put(g, B_POLARIS % "lot_planter_bed", -56.0 + i * 56.0, 74.0, ALONG_X, 0.0, "Planter_%d" % i)
	for i in 4:
		_put(g, B_POLARIS % "lot_planter_bed", -96.0 + i * 64.0, 128.0, ALONG_X, 0.0, "PlanterS_%d" % i)
	for i in 3:
		_put(g, B_POLARIS % "lot_sign_cluster", -92.0 + i * 92.0, 96.0, 0.0, 0.0, "AisleSign_%d" % i)
	# The marquee: a building-sized thing in the middle of open ground, which
	# makes it the obvious objective and the obvious ambush at the same time.
	_put(g, B_POLARIS % "lot_event_marquee", 124.0, 124.0, ALONG_X + 6.0, 0.0, "Marquee")
	_put(g, B_POLARIS % "lot_food_pavilion", -118.0, 52.0, ALONG_X, 0.0, "FoodPavilion")
	_put(g, B_POLARIS % "lot_charging_bank", 77.0, 56.0, ALONG_X, 0.0, "Chargers")
	_put(g, B_POLARIS % "lot_garden_centre", 160.0, -49.0, FACE_WEST, 0.0, "GardenCentre")
	for i: int in [0, 1]:
		_put(g, B_POLARIS % "lot_snow_pile", -180.0 + i * 360.0, 96.0 - i * 190.0, 0.0, 0.0, "Heap_%d" % i)
	for i in 2:
		_put(g, B_POLARIS % "lot_dumpster_corral", -70.0 + i * 120.0, -46.0, FACE_SOUTH, 0.0, "Bins_%d" % i)
	# The third was beside the fieldhouse's garden centre; it is behind it now.
	_put(g, B_POLARIS % "lot_dumpster_corral", 170.0, -84.0, FACE_SOUTH, 0.0, "Bins_2")
	_put(g, B_POLARIS % "lot_valet_canopy", -26.0, 44.0, FACE_SOUTH, 0.0, "Valet")
	_lot_lights(g)
	for i in 4:
		_put(g, B_POLARIS % "lot_transit_shelter", -120.0 + i * 80.0, RING_Y + RING_R + 10.0, FACE_NORTH, 0.0,
				"Shelter_%d" % i)


## THE CAR PARK'S LIGHTS, in the gaps between aisles and nowhere else.
##
## They were twelve points on an ellipse, which put half of them inside the
## mall wings, the cinema and the garage. The aisles are on a 20 m pitch and
## 14.1 m wide, which leaves a 5.9 m strip between each pair, and a light is
## 1.5 m across. x is each aisle's own centre, where a fanned aisle has not
## swung away from the strip.
func _lot_lights(g: Node3D) -> void:
	var n := 0
	for z: float in [68.0, 88.0, 108.0]:
		for x: float in [-34.0, 34.0]:
			_put(g, B_SUBURBAN % "suburban_lot_light", x, z, 0.0, 0.0, "LotLight_%d" % n)
			n += 1
	for z: float in [-68.0, -88.0]:
		for x: float in [-36.0, 36.0]:
			_put(g, B_SUBURBAN % "suburban_lot_light", x, z, 0.0, 0.0, "LotLight_%d" % n)
			n += 1


## THE RESTAURANT ROW and the other outlots, OUTSIDE the loop along the south
## frontage, each a detached pad with open ground between. All of them face
## north, back at the mall, because that is where their car parks are — which
## means a squad coming off the frontage arrives at the BACK of the row.
func _outlots(art: Node3D) -> void:
	var g := _group(art, "Outlots")
	var z := RING_Y + RING_R + 52.0
	_put(g, B_POLARIS % "polaris_restaurant_casual", -150.0, z, FACE_NORTH, 0.0, "Fridays")
	_put(g, B_POLARIS % "polaris_restaurant_upscale", -72.0, z + 4.0, FACE_NORTH, 0.0, "Steakhouse")
	_put(g, B_POLARIS % "polaris_restaurant_fast", -8.0, z, FACE_NORTH, 0.0, "FastA")
	_put(g, B_POLARIS % "polaris_restaurant_fast", 28.0, z, FACE_NORTH, 0.0, "FastB")
	_put(g, B_POLARIS % "polaris_patio", 52.0, z - 12.0, ALONG_X, 0.0, "Patio")
	_put(g, B_POLARIS % "polaris_bank_outlot", 104.0, z, FACE_NORTH, 0.0, "Bank")
	_put(g, B_SUBURBAN % "suburban_drive_thru", 162.0, z - 2.0, FACE_NORTH, 0.0, "DriveThru")
	_put(g, B_SUBURBAN % "suburban_gas_canopy", -216.0, z + 6.0, ALONG_X, 0.0, "Fuel")
	# The frontage arterial beyond them, and the walk along the row.
	for i in 14:
		_put(g, B_STREETS % "street_road_turn_lane_inlay", -208.0 + i * 32.0, z + 44.0, ALONG_X, 0.0, "Frontage_%d" % i)
	for i in 8:
		_put(g, B_STREETS % "street_sidewalk_run", -176.0 + i * 32.0, z - 26.0, ALONG_X, 0.0, "RowWalk_%d" % i)
	for i in 5:
		_put(g, B_STREETS % "street_lot_entry_throat_inlay", -140.0 + i * 70.0, RING_Y + RING_R + ROAD2_HALF + THROAT_HALF_Z, 180.0, 0.0, "Throat_%d" % i)
	_put(g, B_SUBURBAN % "suburban_pylon_sign", -4.0, z + 30.0, FACE_NORTH, 0.0, "Pylon")
	_put(g, B_SUBURBAN % "suburban_entry_monument", 60.0, RING_Y + RING_R + 16.0, ALONG_X, 0.0, "Monument")
	_put(g, B_SUBURBS % "suburb_billboard", 206.0, z + 36.0, ALONG_X, 0.0, "Billboard")
	for i in 5:
		_put(g, B_STREETS % "street_signal_mast", -160.0 + i * 70.0, z + 36.0, FACE_NORTH, 0.0, "Signal_%d" % i)


## The power centre across the arterial to the west: the big boxes, a strip,
## the storage lanes and an office. Everything here faces east, back toward
## the mall, for the same reason the row faces north.
func _power_centre(art: Node3D) -> void:
	var g := _group(art, "PowerCentre")
	# THE BOULEVARD, THEN THE AISLES, THEN THE BUILDINGS, outward from the ring
	# road, each placed from the one inside it. The boulevard used to be hand-
	# typed at x + 92 = -204, which is 4 m from the ring road's west straight at
	# -200 when both are wider than that, so it was laid straight through it.
	# The aisles run east-west and are 64 m long; they sit between the boulevard
	# and the building fronts, and the buildings (the nearest front is 19 m east
	# of its origin) are placed last, from the aisles, with 1 m clear.
	var x_blvd := -(RING_X + RING_R + ROAD2_HALF + ROAD4_HALF)
	var x_aisle := x_blvd - ROAD4_HALF - AISLE_HALF_L
	var x := x_aisle - AISLE_HALF_L - 20.0
	_put(g, B_SUBURBAN % "suburban_big_box", x, -46.0, FACE_EAST, 0.0, "BigBoxNorth")
	_put(g, B_SUBURBAN % "suburban_retail_strip", x - 12.0, 64.0, FACE_EAST, 0.0, "Strip")
	_put(g, B_SUBURBS % "suburb_self_storage", x - 6.0, -158.0, ALONG_X, 0.0, "Storage")
	# The yard between the two unit rows, which is where the objective belongs
	# and where a squad can actually stand. Registered rather than typed.
	_anchors["Polaris_Storage"] = Vector2(x - 6.0, -158.0)
	_put(g, B_SUBURBS % "suburb_office_lowrise", x + 2.0, 168.0, FACE_EAST, 0.0, "Office")
	# ACROSS the strip, not along it. These were ALONG_Z — 64 m long pieces
	# running up the Z axis while being spaced 40 m apart ON THAT SAME AXIS, so
	# each one lay 24 m inside its neighbour. Turned to run east-west they are
	# spaced across their own width and clear each other by 26 m, and they end
	# 0.1 m short of the boulevard kerb.
	for i in 4:
		_put(g, B_POLARIS % "polaris_aisle_long", x_aisle, -96.0 + i * 40.0, ALONG_X, 0.0, "PCAisle_%d" % i)
	for i in 10:
		_put(g, B_STREETS % "street_road_four_lane_inlay", x_blvd, -128.0 + i * 32.0, ALONG_Z, 0.0, "Sancus_%d" % i)


## The subdivision behind the mall to the north, which is where the map stops
## being a car park: head-high fences, 6 m gaps and no sightline longer than
## a street. The two rows face each other across their street and their back
## fences meet in the middle.
func _housing(art: Node3D) -> void:
	var g := _group(art, "Housing")
	var z := -(RING_Y + RING_R + 62.0)
	for i in 8:
		var x := -130.0 + i * 34.0
		var kind: String = ["suburb_house_ranch", "suburb_house_two_story", "suburb_house_split"][i % 3]
		_put(g, B_SUBURBS % kind, x, z - 22.5, FACE_SOUTH, 0.0, "House_%d" % i)
		_put(g, B_SUBURBS % kind, x + 17.0, z - 72.0, FACE_NORTH, 0.0, "HouseBack_%d" % i)
		_put(g, B_SUBURBS % "suburb_fence_privacy", x, z - 47.0, ALONG_X, 0.0, "Fence_%d" % i)
	for i in 9:
		_put(g, B_STREETS % "street_road_two_lane_inlay", -144.0 + i * 32.0, z, ALONG_X, 0.0, "HouseStreet_%d" % i)
	_put(g, B_SUBURBS % "suburb_townhouse_row", 162.0, z - 36.0, FACE_WEST, 0.0, "Townhouses")
	_put(g, B_SUBURBS % "suburb_garden_apartment", 162.0, z - 96.0, FACE_WEST, 0.0, "Apartments")
	_put(g, B_SUBURBS % "suburb_church", -184.0, z - 52.0, FACE_SOUTH, 0.0, "Church")
	_put(g, B_SUBURBS % "suburb_school_wing", -44.0, z - 120.0, ALONG_X, 0.0, "School")


# ── The level ────────────────────────────────────────────────────────────────

## Objective anchors. TERRAIN puts the pins in and names them; what a mission
## does with them is GAMEPLAY's, which is why these are places and not tasks.
## node, tag, label, x, z
const OBJECTIVES: Array = [
	# In front of the row, not inside the steakhouse.
	["Polaris_Row", "obj_polaris_row", "The Restaurant Row", -70.0, 190.0],
	["Polaris_Court", "obj_polaris_court", "The Entry Court", 0.0, 48.0],
	["Polaris_Dock", "obj_polaris_dock", "Mall Service Dock", -30.0, -30.0],
	["Polaris_Garage", "obj_polaris_garage", "The Parking Deck", 96.0, 86.0],
	["Polaris_Cinema", "obj_polaris_cinema", "The Multiplex", -92.0, 92.0],
	["Polaris_Storage", "obj_polaris_storage", "The Storage Lanes", -314.0, -150.0],
	["Polaris_Basin", "obj_polaris_basin", "The East Basin", 256.0, 124.0],
	["Polaris_Houses", "obj_polaris_houses", "The Subdivision", -40.0, -196.0],
]


## The level scene: the art under a NavigationRegion3D, a spawn out on the
## frontage, an exit on the far side, and the objective anchors.
##
## Written as text rather than packed, because a level is a handful of nodes
## with scripts on them and an ext_resource list, and building that tree in
## memory to pack it means loading every script this file does not otherwise
## need. The art scene is packed, because it is four hundred instances.
func _write_level() -> void:
	var lines := PackedStringArray()
	var objs := PackedStringArray()
	for o: Array in OBJECTIVES:
		# AN ANCHOR BEATS THE TYPED COORDINATE. Anything standing on a piece whose
		# position is derived has to be derived too, or it drifts silently the
		# first time the thing it names moves. The storage objective was typed at
		# (-314, -150); RING_X changed by 6 m, the power centre moved with it, and
		# the marker ended up inside the north unit row — unreachable, and nothing
		# said so until the navmesh was baked and walked.
		var at := Vector2(o[3], o[4])
		if _anchors.has(o[0]):
			at = _anchors[o[0]]
		objs.append("""
[node name="%s" type="Node3D" parent="NavigationRegion3D/Objectives"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, 0, %s)
""".strip_edges() % [o[0], at.x, at.y])
	lines.append("""[gd_scene load_steps=7 format=3]

[ext_resource type="PackedScene" path="%s" id="1_art"]
[ext_resource type="PackedScene" uid="uid://g7fmy28elpah" path="res://Env/world_objects/spawn_point.tscn" id="2_spawn"]

[sub_resource type="ProceduralSkyMaterial" id="Sky_mat"]
sky_horizon_color = Color(0.64, 0.66, 0.67, 1)
ground_horizon_color = Color(0.64, 0.66, 0.67, 1)

[sub_resource type="Sky" id="Sky_polaris"]
sky_material = SubResource("Sky_mat")

[sub_resource type="Environment" id="Env_polaris"]
background_mode = 2
sky = SubResource("Sky_polaris")
ambient_light_source = 3
ambient_light_color = Color(0.44, 0.45, 0.47, 1)
ambient_light_sky_contribution = 0.55
ambient_light_energy = 0.7
tonemap_mode = 2

[sub_resource type="NavigationMesh" id="NavigationMesh_polaris"]
vertices = PackedVector3Array()
polygons = []
cell_size = 0.25
agent_radius = 0.5
agent_height = 1.8
agent_max_climb = 0.25
region_min_size = 24.0
edge_max_error = 1.3
detail_sample_distance = 6.0
geometry_parsed_geometry_type = 1
filter_baking_aabb = AABB(-320, -12, -320, 640, 48, 640)

[node name="PolarisLevel" type="Node3D"]

[node name="NavigationRegion3D" type="NavigationRegion3D" parent="."]
navigation_mesh = SubResource("NavigationMesh_polaris")

[node name="PolarisArt" parent="NavigationRegion3D" instance=ExtResource("1_art")]

[node name="Objectives" type="Node3D" parent="NavigationRegion3D"]

%s

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Env_polaris")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.77, 0.41, -0.49, 0, 0.77, 0.64, 0.64, -0.49, 0.59, 0, 120, 0)
light_energy = 1.25
shadow_enabled = true
directional_shadow_max_distance = 420.0

[node name="SpawnPoint" parent="." instance=ExtResource("2_spawn")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -210, 0, 244)
""" % [ART, "\n\n".join(objs)])
	var f := FileAccess.open(LEVEL, FileAccess.WRITE)
	if f == null:
		print("FAIL  could not write %s (%s)" % [LEVEL, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string("\n".join(lines))
	f.close()
