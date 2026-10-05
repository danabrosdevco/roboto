extends SceneTree

# ─────────────────────────────────────────────
# BUILD GEORGETOWN — assembles maps/georgetown_art.tscn and
# maps/georgetown_level.tscn: the C&O Canal on its terrace, the mills along
# it, the town above, the waterfront below and the Potomac with Arlington
# across it.
#
#   godot --headless --path . --script res://tools/build_georgetown.gd
#   godot --headless --path . --script res://tools/build_georgetown.gd -- --force
#
# THE HILL IS FOUR FLAT BENCHES, NOT A SLOPE. The brief was a map on a hill
# running down to the river, and this project already knows what a painted
# hill does to a squad: bodies cannot use jagged ground, and height is
# supposed to come from built assets. Georgetown happens to be exactly that
# already — a town that steps down to the Potomac in terraces, each held up by
# a stone wall. So the hill here is:
#
#   UPPER TOWN   z = +7.0   the streets above, where a map starts
#   CANAL        z =  0.0   the towpath, the prism cut 3 m into it
#   LOWER YARDS  z = -4.0   the old industrial level between canal and river
#   WATERFRONT   z = -7.0   the esplanade, and the river 2.4 m under that
#
# Fourteen metres of fall across about 150 m, every metre of it in a wall you
# can see, and the only ways between benches are the stairs, the ramped
# streets and the bridges. That is the map: a player can always tell which
# level they are on and what is above them, and a squad can always be ordered
# somewhere without being asked to walk up a slope it cannot use.
#
# THE CANAL IS THE SPINE. It runs the whole width of the map on the middle
# bench, 9 m wide and 3 m deep with vertical stone both sides. A squad in it
# is committed until the next stair or bridge; a squad on the towpath is
# shooting down into a slot. Everything else is arranged around who holds the
# crossings.
#
# WHAT IT DOES NOT DO: bake the navmesh.
#
#   BAKE_ONLY=1 LEVEL=res://maps/georgetown_level.tscn godot --path . \
#       --script res://tools/probe_nav_hillfort.gd
# ─────────────────────────────────────────────

const ART := "res://maps/georgetown_art.tscn"
const LEVEL := "res://maps/georgetown_level.tscn"
const B := "res://maps/blocks/canal/%s.tscn"
const B_STREETS := "res://maps/blocks/streets/%s.tscn"
const B_SUBURBAN := "res://maps/blocks/suburban/%s.tscn"
const B_PROPS := "res://maps/blocks/props/%s.tscn"
const B_POLARIS := "res://maps/blocks/polaris/%s.tscn"

## The canal's own cross-section, read from the block that draws it, so the
## bench ground and the prism butt on ONE line and the number is typed once.
## A hand-typed second copy of where the canal is, is the bug that cost the
## Polaris ground two failed attempts.
const CANAL_BLOCK := preload("res://tools/block_canal.gd")
## Metres from the canal's centreline to the outer edge of its towpaths. Every
## canal bay (prism, open prism, lock) is exactly this wide on each side.
const CANAL_HALF: float = CANAL_BLOCK.CANAL_HALF

# ── Which way round everything goes ──────────────────────────────────────────
#
# FUNCGODOT MAPS QUAKE (x, y, z) TO GODOT (y, z, x), so a block built along
# its map X runs along GODOT'S Z, and a block whose front is its map +Y faces
# GODOT'S +X. Written here once; the Polaris build learned this the hard way.
#
# On this map the CANAL runs east-west along the site's X, and the hill falls
# toward +Z, which is south, toward the river.
const ALONG_X := 90.0
const ALONG_Z := 0.0
const FACE_EAST := 0.0
const FACE_NORTH := 90.0
const FACE_WEST := 180.0
const FACE_SOUTH := 270.0

## The benches. Every height in this file is one of these.
# EVERY DROP IS EXACTLY 4.0 M, because canal_terrace_wall, canal_terrace_stair
# and canal_street_ramp are all 4 m pieces. They were 7, 4 and 3 m apart to
# start with and the stairs could not physically reach: the probe came back
# with 36.9%% of the map reachable and every objective cut off, because the
# squad was standing on the top bench with no way down. A terrace kit has one
# height in it and the benches have to use it.
const Z_TOWN := 4.0
const Z_CANAL := 0.0
const Z_YARDS := -4.0
const Z_WHARF := -8.0

## Where each bench sits across the site, in Godot Z. The canal's own
## cross-section is 9 m of prism plus a towpath and a berm, so the bench it
## sits on is about 26 m deep and the others take what is left.
const S_TOWN := -96.0
const S_CANAL := 0.0
const S_YARDS := 54.0
const S_WHARF := 116.0

## How far the map runs east-west. The prism tiles in 32 m pieces.
const RUN := 14

## Where the stack stands, east-west. The park lights keep clear of it.
const STACK_X := 86.0

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
	art.name = "GeorgetownArt"
	root.add_child(art)

	_benches(art)
	_canal(art)
	_mills(art)
	_upper_town(art)
	_lower_yards(art)
	_waterfront(art)

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
	print("      %s  %d pieces%s" % [ART.get_file(), placed,
			"" if _clashes == 0 else "  — %d PLACEMENT CLASH(ES), see the warnings" % _clashes])
	_write_level()
	print("      %s" % LEVEL.get_file())
	print("BUILD GEORGETOWN DONE")
	quit()


## Instance ROOTS are owned by the art root and nothing inside them is: a
## packed scene writes what its root owns, and owning an instance's internals
## writes them out as declared nodes and quietly stops edits to the block
## reaching the level that instances it.
func _own(node: Node, root_node: Node) -> int:
	var n := 0
	for c in node.get_children():
		c.owner = root_node
		if c.scene_file_path != "":
			n += 1
			continue
		n += _own(c, root_node)
	return n


## WHERE EACH TERRACE IS CROSSED. One list, used BOTH to skip the wall bay and
## to place the stair or ramp in it, because when those were two separate lists
## they drifted the first time a ramp moved and the wall closed over it again.
## wall z -> bays with a crossing in them.
# Yards crossings are all ODD bays: the service alleys sit on the even ones.
const CROSSINGS := {-46.0: [3, 6, 11], 46.0: [1, 5, 9], 106.0: [4, 11]}

## PAIRS THAT ARE SUPPOSED TO SHARE SPACE, as name prefixes. A guard that
## cries about the same six intentional things every build is a guard people
## stop reading, and the whole value of this one is that a new line in its
## output means a new mistake.
##
##   Debris / Prism       the silt and fallen coping lie IN the bed
##   CanalStair / Prism   the stair is cut INTO the canal wall, which is what
##                        a stair down a quay is
##   Bridge / Prism       the bridges carry their own abutments down into the
##                        wall so the two read as one piece of masonry
##   LockGear / Lock      the beams and winches sit on the lock
##   Cofferdam / Prism    it is built in the bed
## Each of these is an AABB envelope sharing, not two solids crossing.
const EXPECTED: Array = [["Debris", "Prism"], ["CanalStair", "Prism"], ["Bridge", "Prism"],
		["LockGear", "Lock"], ["Cofferdam", "Prism"], ["Outfall", "Prism"],
		# A house front meets the pavement outside it. Its foundation runs four
		# metres down and the walk slab is 0.45 thick, so their envelopes share
		# a sliver — which is what a building on a street looks like.
		["Row", "TownWalk"], ["Row", "MStreet"]]


func _expected(a: String, b: String) -> bool:
	for e: Array in EXPECTED:
		if (a.begins_with(e[0]) and b.begins_with(e[1])) or (b.begins_with(e[0]) and a.begins_with(e[1])):
			return true
	return false


## Pieces that are ground, and which everything else is MEANT to sit inside.
const GROUND_NAMES: Array = ["canal_bench", "polaris_lot_main", "polaris_ground_grass"]

var _placed: Array = []
## The same threshold tools/probe_level_faults.gd reports at. The guard used to
## say 40 m3, which let eighteen pairs through that the probe then found
## afterwards — a guard that is quieter than the probe is not guarding.
const SHARED_M3 := 12.0
var _clashes := 0


func _put(parent: Node3D, path: String, x: float, z: float, yaw: float = 0.0, y: float = 0.0, name := "") -> Node3D:
	if not _cache.has(path):
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("build_georgetown: no prefab at %s — nothing placed" % path)
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
	_guard(inst, path)
	return inst


## EVERY PLACEMENT IS CHECKED AGAINST EVERY PREVIOUS ONE AS IT GOES IN.
##
## Laying two hundred and fifty pieces at hand-chosen coordinates and checking
## afterwards is whack-a-mole: each piece you move to clear one clash lands on
## something else, and it took four passes to get from seventy clashes to
## fifty. The builder knows the footprints — it should say so at the moment it
## puts a piece down, naming both pieces, so the fix is one edit and not a
## search.
##
## Ground plates are exempt in both directions: a building is MEANT to be
## founded four metres into the slab it stands on.
func _guard(inst: Node3D, path: String) -> void:
	var box := _bounds_of(inst)
	if box.size.length() < 0.01:
		return
	var ground := _is_ground(path)
	if not ground:
		for p: Dictionary in _placed:
			if p.ground:
				continue
			var a: AABB = p.box
			if not a.intersects(box):
				continue
			var s := a.intersection(box)
			var vol := s.size.x * s.size.y * s.size.z
			if vol > SHARED_M3 and not _expected(String(inst.name), p.name):
				_clashes += 1
				push_warning("build_georgetown: %s is inside %s — %.0f m3 at (%.0f, %.0f, %.0f)" % [
						inst.name, p.name, vol, s.get_center().x, s.get_center().y, s.get_center().z])
	_placed.append({"name": String(inst.name), "box": box, "ground": ground})


func _is_ground(path: String) -> bool:
	for g: String in GROUND_NAMES:
		if path.contains(g):
			return true
	return false


## The world AABB of everything that collides under `n`. Collision and not
## mesh: a mesh-only canopy is scenery and a mesh-only river is 600 m wide,
## and neither is something the arrangement can be wrong about.
func _bounds_of(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for cs: CollisionShape3D in n.find_children("*", "CollisionShape3D", true, false):
		if cs.shape == null:
			continue
		var r := cs.shape.get_debug_mesh()
		if r == null:
			continue
		var b := cs.global_transform * r.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

func _group(parent: Node3D, name: String) -> Node3D:
	var g := Node3D.new()
	g.name = name
	parent.add_child(g)
	return g


## The X of the i-th 32 m bay, so every row on the map lines up with the
## canal instead of drifting out of step with it.
func _bay(i: int) -> float:
	return (i - RUN * 0.5 + 0.5) * 32.0


# ── The benches ──────────────────────────────────────────────────────────────

## The four flat levels and the walls between them.
##
## EACH BENCH IS TILED TO AN EXACT DEPTH, from 32, 16 and 4 m pieces, and the
## canal bench has a hole in it where the prism goes. Getting this wrong is
## invisible and expensive, and it was wrong twice:
##
##   - one 460 x 360 plate per bench overlapped the next by two hundred metres
##     and the town's plate buried the canal completely;
##   - then 32 m tiles anchored at the far end overshot each boundary by the
##     remainder, so the town bench lay 8 m over the canal bench and buried the
##     top of every stair inside 4 m of slab.
##
## The probe read the same 43.8%% through three separate fixes before I stopped
## blaming the stairs and looked at what they were climbing into. A bench slab
## is 4 m thick and you cannot see the top of it from inside the editor, which
## is why it keeps being the thing that is wrong.
##
## RULE: ranges are whole metres, they BUTT and never overlap, and the canal
## bench stops where the prism's own ground starts.
func _benches(art: Node3D) -> void:
	var g := _group(art, "Benches")
	# name, bench height, from Z, to Z. The prism brings its own towpaths, bed
	# and walls and is the ground from -CANAL_HALF to +CANAL_HALF, so the canal
	# bench is a VOID there: it stops on the towpath's outer edge and starts
	# again on the other side. The two bench strips and the prism are driven by
	# the same constant, so they butt and neither lies under the other.
	var strips: Array = [
		["Town", Z_TOWN, -264.0, -48.0],
		["CanalN", Z_CANAL, -48.0, -CANAL_HALF],
		["CanalS", Z_CANAL, CANAL_HALF, 46.0],
		["Yards", Z_YARDS, 46.0, 106.0],
		["Wharf", Z_WHARF, 106.0, 226.0],
	]
	for s: Array in strips:
		_tile_bench(g, s[0], s[1], s[2], s[3], s[0] == "Wharf")
	# The retaining wall at the front of each bench, standing on the LOWER one
	# and climbing 4 m to the ground it retains. Yaw 270 puts its backing slab
	# to the north, which is the side the higher bench is on.
	var walls: Array = [
		[Z_CANAL, -46.0],
		[Z_YARDS, 46.0],
		[Z_WHARF, 106.0],
	]
	# THE WALL SKIPS THE BAYS A STAIR OR RAMP CROSSES. A stair up a terrace is
	# a GAP in the wall, not a thing that passes through it — placed over the
	# whole run the wall shared 500 m3 with the ramp and another 378 with the
	# houses above it. The bays below are the ones _upper_town, _lower_yards
	# and _waterfront put a crossing in; keep them in step.
	for w: Array in walls:
		for i in RUN:
			if (CROSSINGS[w[1]] as Array).has(i):
				continue
			_put(g, B % "canal_terrace_wall", _bay(i), w[1], ALONG_X + 180.0, w[0], "Wall_%.0f_%d" % [w[1], i])


## Fill `from`..`to` exactly with 32, 16, 4, 2 and 1 m bench pieces, laid from
## the `from` edge. Any depth that is a whole number of metres comes out flush
## at both ends; the 2 and the 1 exist for the 9 m from the canal's centreline
## to its towpath edge, which no multiple of 4 reaches.
func _tile_bench(g: Node3D, name: String, y: float, from: float, to: float, grass := false) -> void:
	var at := from
	var n := 0
	for size: float in [32.0, 16.0, 4.0, 2.0, 1.0]:
		var piece: String = {32.0: "canal_bench", 16.0: "canal_bench_16", 4.0: "canal_bench_4", 2.0: "canal_bench_2", 1.0: "canal_bench_1"}[size]
		if grass:
			piece = {32.0: "canal_bench_grass", 16.0: "canal_bench_grass_16", 4.0: "canal_bench_grass_4", 2.0: "canal_bench_grass_2", 1.0: "canal_bench_grass_1"}[size]
		while to - at >= size - 0.01:
			_put(g, B % piece, 0.0, at + size * 0.5, ALONG_X, y, "%s_%d" % [name, n])
			at += size
			n += 1
	if absf(to - at) > 0.01:
		# Say it rather than leaving a hole: a gap in a bench is a hole in the
		# floor, and the squad simply stops at the edge of it.
		push_warning("build_georgetown: %s leaves %.2f m unfilled — make the range a whole number of metres" % [name, to - at])


# ── The canal ────────────────────────────────────────────────────────────────

## THE PRISM, bay by bay, with the bridges, the lock and what is in the bed.
##
## FOUR CROSSINGS IN 450 M, of three different kinds: two riveted footbridges,
## one street bridge heavy enough to fight under, and one plank. They are far
## enough apart that holding one matters and the plank is deliberately the
## worst of them — 1.2 m wide, no cover, and it reads as temporary, which
## tells a player what it will cost before they step on it.
##
## AND THE BED IS NOT CLEAN NOW. Silt, fallen coping, a trolley, barriers
## round the holes and a compound where the work is. In a 3 m trench with
## vertical sides that debris is the only cover there is, so it decides
## whether the prism is a corridor or a place to fight.
func _canal(art: Node3D) -> void:
	var g := _group(art, "Canal")
	var w := _group(art, "CanalWorks")
	const BRIDGES := {2: "truss", 6: "road", 11: "truss", 9: "plank"}
	for i in RUN:
		if i == 8:
			_put(g, B % "canal_lock", _bay(i), S_CANAL, ALONG_X, Z_CANAL, "Lock")
			_put(w, B % "works_lock_gear", _bay(i), S_CANAL, ALONG_X, Z_CANAL, "LockGear")
			continue
		# canal_prism_open the whole way, not canal_prism. The latter carries a
		# 3 m terrace wall on its berm side, which is right when the mills stand
		# above it and wrong here — the benches are at the SAME height both
		# sides of this canal, so that wall sealed the south bank off from the
		# bridges entirely and the squad could never cross.
		# A bay a bridge crosses gets the prism with no coping across the bridge
		# mouth, so the deck lands level with the towpath and not behind a lip.
		_put(g, B % ("canal_prism_open_bridge" if BRIDGES.has(i) else "canal_prism_open"), _bay(i), S_CANAL,
				ALONG_X, Z_CANAL, "Prism_%d" % i)
	for i: int in BRIDGES:
		var kind: String = BRIDGES[i]
		var name: String = {"truss": "canal_truss_bridge", "road": "canal_road_bridge", "plank": "works_plank_bridge"}[kind]
		_put(g, B % name, _bay(i), S_CANAL, ALONG_X, Z_CANAL, "Bridge_%d" % i)
	for i: int in [3, 4, 12]:
		# YAW 180, not ALONG_X. The stair descends along its map X, so at 90 it
		# ran ALONG the canal inside the wall instead of down into the bed, and
		# the only two ways into the prism went nowhere. 180 points its foot at
		# the bed and its head at the towpath.
		_put(g, B % "canal_stair_down", _bay(i) + 9.0, S_CANAL, 180.0, Z_CANAL, "CanalStair_%d" % i)
	for i: int in [3, 9]:
		_put(g, B % "canal_cofferdam", _bay(i) - 6.0, S_CANAL + 1.5, ALONG_X, Z_CANAL, "Cofferdam_%d" % i)
	for i: int in [1, 7, 13]:
		_put(g, B % "canal_outfall", _bay(i) + 4.0, S_CANAL, ALONG_X, Z_CANAL, "Outfall_%d" % i)
	# What is lying in the bed, and the barriers round the holes.
	# Bays 0, 2, 5, 10 and 11: a heap spans 28 m of the bed, so it cannot share a
	# bay with a stair cut into the wall (3, 4, 12), the cofferdam (3, 9) or the
	# street bridge (6), whose abutments reach the bed. It
	# was in 4 and 12 and lay across both stairs.
	for i: int in [0, 2, 5, 10, 11]:
		# The +7 in the seed only picks a scatter whose pipes do not lie with a
		# rim within 3 cm of the bed at a probe sample: a round pipe on a floor has
		# a thin band that reads as two floors, and the old offset put one there.
		_put(w, B % "works_bed_debris", _bay(i), S_CANAL + (_hash(i + 7) - 0.5) * 3.0, ALONG_X, Z_CANAL - 3.0,
				"Debris_%d" % i)
	for i: int in [3, 6, 9, 13]:
		_put(w, B % "works_barrier_run", _bay(i) + 7.0, S_CANAL - 6.0, ALONG_X, Z_CANAL, "Barrier_%d" % i)
	# The works compound on the towpath, at the lock, where the job is.
	_put(w, B % "works_site_compound", _bay(7) + 14.0, S_CANAL - 34.0, ALONG_X, Z_CANAL, "Compound")
	# Market along the towpath at the open end, where the canal is a place
	# rather than a cut.
	# On the bench just BEYOND the towpath, not on it. At -7.5 its 3.8 m of depth
	# sat inside the prism's own envelope and across the bay-11 bridge, whose
	# truss runs out to -7.8. The prism ends at -CANAL_HALF and the stalls start
	# 2 m past it.
	_put(w, B % "works_market_stalls", _bay(11) + 6.0, S_CANAL - CANAL_HALF - 2.0, ALONG_X, Z_CANAL, "Market")
	for i in RUN:
		if posmod(i, 3) != 0:
			continue
		_put(g, B_STREETS % "street_light_cobra", _bay(i), S_CANAL + 11.0, FACE_NORTH, Z_CANAL, "TowLight_%d" % i)


## A deterministic 0..1 from an integer, so the dressing is scattered the same
## way every build.
func _hash(n: int) -> float:
	var h: int = n * 374761393 + 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


## THE MILLS along the canal, now in three sizes with scaffold up one of them.
## A row of one building repeated is a wall; a row of three sizes is a street.
func _mills(art: Node3D) -> void:
	var g := _group(art, "Mills")
	var z := S_CANAL - 22.0
	var kinds: Array = ["mill_brick_long", "mill_brick_short", "mill_warehouse_stone",
			"mill_brick_tall", "mill_brick_short", "mill_brick_long", "mill_warehouse_stone"]
	for i in 7:
		_put(g, B % kinds[i], -212.0 + i * 68.0, z, FACE_SOUTH, Z_CANAL, "Mill_%d" % i)
	# Scaffold on the face of one of them, over the berm: a way up a building
	# that has no other, and a thing to be shot off.
	_put(g, B % "works_scaffold", -144.0, S_CANAL - 12.6, ALONG_X, Z_CANAL, "Scaffold")
	# The stack, on the yards bench behind the mills: 44 m, which clears them
	# by 28 and the office block by 16. The thing the whole map is read
	# against, and the only piece on it visible from every bench.
	_put(g, B % "mark_stack", STACK_X, S_YARDS + 70.0, 0.0, Z_YARDS, "Stack")
	for i: int in [0, 1]:
		_put(g, B % "mill_cafe_terrace", -170.0 + i * 204.0, S_CANAL - 14.0, ALONG_X, Z_CANAL + 3.0, "Cafe_%d" % i)
	# Clear of the terrace wall at z = 46: it was at z 30 with a 13 m depth,
	# so its south face ran straight through the wall for 665 m3.
	# On the town bench at the west end, not over the canal. It is 32 m deep
	# and the gap between the prism and the terrace wall is 28 — it never fit
	# there, and every z I tried traded an overlap with one for the other.
	_put(g, B % "mill_office_modern", -150.0, S_TOWN - 84.0, FACE_SOUTH, Z_TOWN, "OfficeBlock")


## THE TOWN ABOVE, in federal rowhouses rather than the suburban townhouses
## the first pass borrowed — those were the wrong country entirely. Flat brick
## fronts straight onto the pavement with a stoop, which makes the top bench
## the tightest ground on the map. The open stuff is all below it.
func _upper_town(art: Node3D) -> void:
	var g := _group(art, "UpperTown")
	for i in RUN:
		_put(g, B_STREETS % "street_road_two_lane", _bay(i), S_TOWN, ALONG_X, Z_TOWN, "MStreet_%d" % i)
		if posmod(i, 2) == 0:
			_put(g, B_STREETS % "street_sidewalk_run", _bay(i), S_TOWN - 22.0, ALONG_X, Z_TOWN, "TownWalk_%d" % i)
	# Two facing terraces, so the street between them is a corridor with
	# doors on both sides.
	for i in 5:
		var x := -164.0 + i * 82.0
		_put(g, B % "mill_rowhouse_run", x, S_TOWN - 32.0, FACE_SOUTH, Z_TOWN, "RowN_%d" % i)
		_put(g, B % "mill_rowhouse_run", x + 20.0, S_TOWN + 30.0, FACE_NORTH, Z_TOWN, "RowS_%d" % i)
	# East of the last rowhouse terrace, not inside it.
	_put(g, B % "mill_brick_short", 224.0, S_TOWN - 30.0, FACE_SOUTH, Z_TOWN, "TownMill")
	for i in 5:
		_put(g, B_STREETS % "street_light_cobra", -150.0 + i * 76.0, S_TOWN - 12.0, FACE_SOUTH, Z_TOWN, "TownLight_%d" % i)
	for i in 3:
		_put(g, B_STREETS % "street_sign_stop", -120.0 + i * 120.0, S_TOWN - 11.0, 0.0, Z_TOWN, "TownStop_%d" % i)
	# Down to the canal: two public stairs and one ramped street, which are
	# the only three ways off this bench.
	# YAW 270, NOT 0. The stair runs along its own map Y, not its map X, so
	# ALONG_Z — which is for a piece that runs along its X — laid it across the
	# terrace instead of up it. Every stair on this map climbs NORTH, from the
	# lower bench onto the higher one, and sits at the lower bench height
	# because its origin is the bottom step.
	for i: int in [3, 11]:
		_put(g, B % "canal_terrace_stair", _bay(i), -37.0, 270.0, Z_CANAL, "TownStair_%d" % i)
	# At bay 7 the ramp ran straight through the south terrace of rowhouses.
	# It is between two terraces now, which is also where a street would be.
	_put(g, B % "canal_street_ramp", _bay(6), S_TOWN + 46.0, ALONG_Z, Z_CANAL, "TownRamp")


## THE LOWER YARDS between canal and river, with the viaduct carrying a street
## across them. The viaduct is two levels for the price of one: a roofed route
## under it and a street over it.
func _lower_yards(art: Node3D) -> void:
	var g := _group(art, "LowerYards")
	for i in RUN:
		if posmod(i, 2) != 0:
			continue
		_put(g, B_STREETS % "street_alley", _bay(i), 54.0, ALONG_X, Z_YARDS, "YardAlley_%d" % i)
	for i in 4:
		# z 85.5, not 86: its back runs 11.2 m to the south and the terrace wall
		# at 106 has a backing slab from 97, so at 86 the two shared 20 m3.
		_put(g, B % "mill_warehouse_stone", -170.0 + i * 108.0, 85.5, FACE_SOUTH, Z_YARDS, "Yard_%d" % i)
	for i in 3:
		_put(g, B % "mill_brick_short", -124.0 + i * 118.0, 68.0, FACE_NORTH, Z_YARDS, "YardMill_%d" % i)
	for i: int in [0, 1]:
		# At the ends of the bench. In the middle they landed on the warehouses,
		# the mills and the terrace wall in turn — the yards bench is 60 m deep
		# and a 28 m viaduct crossing it leaves no room for anything else.
		_put(g, B % "works_arch_viaduct", -206.0 + i * 412.0, 72.0, ALONG_Z, Z_YARDS, "Viaduct_%d" % i)
	_put(g, B % "works_site_compound", 0.0, 86.0, ALONG_X, Z_YARDS, "YardCompound")
	for i: int in [1, 9]:
		_put(g, B % "canal_terrace_stair", _bay(i), 55.0, 270.0, Z_YARDS, "YardStair_%d" % i)
	_put(g, B % "canal_street_ramp", _bay(5), S_YARDS - 2.0, ALONG_Z, Z_YARDS, "YardRamp")
	for i in RUN:
		if posmod(i, 4) != 0:
			continue
		_put(g, B_STREETS % "street_utility_cabinet", _bay(i) + 8.0, 62.0, FACE_SOUTH, Z_YARDS, "Cab_%d" % i)
	for i in 5:
		_put(g, B_STREETS % "street_light_cobra", -160.0 + i * 82.0, 49.0, FACE_SOUTH, Z_YARDS, "YardLight_%d" % i)


## THE WATERFRONT, now a derelict park rather than 450 m of bare esplanade.
##
## The bench was paving, a rail and a 3 m drop to the water — the most exposed
## ground on the map with nothing on it. A park is the other kind of space:
## paths that go round rather than through, beds and hedges that break sight
## without stopping fire, a tennis court that is a room outdoors with two ways
## in, a bandstand that is a roof in the open. The esplanade stays, but only
## along the water's edge where it belongs.
##
## Everything here was built to the rules the reachability probe taught, and
## the probe is run on this map after every change to it for that reason.
func _waterfront(art: Node3D) -> void:
	var g := _group(art, "Waterfront")
	var p := _group(art, "Park")
	for i in 10:
		_put(g, B % "wharf_esplanade", -216.0 + i * 48.0, S_WHARF + 46.0, ALONG_X, Z_WHARF, "Esplanade_%d" % i)
	for i: int in [0, 1, 2]:
		# Out past the esplanade, not through it. The piers and the boathouse
		# were set 14 m inboard of the river wall and shared 400-1,700 m3 with
		# it each.
		_put(g, B % "wharf_pier", -140.0 + i * 140.0, S_WHARF + 72.0, ALONG_X, Z_WHARF, "Pier_%d" % i)
	_put(g, B % "wharf_boathouse", -56.0, S_WHARF + 70.0, ALONG_X, Z_WHARF, "Boathouse")
	_put(g, B % "wharf_barge", 72.0, S_WHARF + 66.0, ALONG_X + 4.0, Z_WHARF, "Barge")
	for i: int in [4, 11]:
		_put(g, B % "canal_terrace_stair", _bay(i) + 6.0, 115.0, 270.0, Z_WHARF, "WharfStair_%d" % i)

	# THE PARK, between the stairs and the water's edge. Two path spines with
	# the set pieces hung off them, because a park a squad crosses is a park
	# with a route through it.
	# THE PARK IN FOUR BANDS, so nothing sits on a path and nothing sits on the
	# river wall. Beds 108, north path 118, the set pieces 132, south path 150,
	# esplanade 162. Every one of these was somewhere else first and the
	# builder's own placement guard named each collision as it happened.
	for i in 13:
		_put(p, B % "park_path_run", -192.0 + i * 32.0, 118.0, ALONG_X, Z_WHARF, "PathN_%d" % i)
	for i in 9:
		_put(p, B % "park_path_run", -128.0 + i * 32.0, 150.0, ALONG_X, Z_WHARF, "PathS_%d" % i)
	_put(p, B % "park_tennis_court", -148.0, 132.0, ALONG_X, Z_WHARF, "TennisCourt")
	_put(p, B % "park_pavilion", -34.0, 132.0, 0.0, Z_WHARF, "Bandstand")
	_put(p, B % "park_fountain_dry", 44.0, 132.0, 0.0, Z_WHARF, "Fountain")
	_put(p, B % "park_playground", 124.0, 132.0, ALONG_X, Z_WHARF, "Playground")
	_put(p, B % "park_pergola_ruin", -94.0, 132.0, ALONG_X, Z_WHARF, "Pergola")
	# In the set-piece band with the rest, not in the beds. At z 108 its plinth
	# (6.4 m across) ran back into the terrace wall's lip, and 108 is where the
	# wall's backing slab ends.
	_put(p, B % "mark_statue", 4.0, 132.0, 0.0, Z_WHARF, "Statue")
	# z 110: a bed is 6 m deep and the wall at 106 has a lip to 106.6, so at 108
	# the beds ran into it. x kept out of the WharfStairs (-74 and 150, 4 m
	# wide): beds 2 and 6 moved 12 m clear of them.
	var bed_x: Array = [-180.0, -124.0, -56.0, -12.0, 44.0, 100.0, 168.0]
	for i in bed_x.size():
		_put(p, B % "park_overgrown_bed", bed_x[i], 110.0, ALONG_X, Z_WHARF, "Bed_%d" % i)
	for i in 6:
		_put(p, B % "park_bench_row", -150.0 + i * 62.0, 143.0, ALONG_X, Z_WHARF, "Benches_%d" % i)
	# Every 58 m, except where that lands on a set piece: light 1 stood inside
	# the tennis court (x -166..-130) and light 5 inside the stack (x 81..91).
	var light_x: Array = [-200.0, -174.0, -84.0, -26.0, 32.0, STACK_X + 12.0, 148.0, 206.0]
	for i in light_x.size():
		_put(p, B_STREETS % "street_light_cobra", light_x[i], 125.0, FACE_SOUTH, Z_WHARF,
				"ParkLight_%d" % i)

	_put(g, B % "works_market_stalls", 8.0, S_WHARF + 44.0, ALONG_X, Z_WHARF, "WharfMarket")
	_put(g, B % "wharf_river", 0.0, S_WHARF + 52.0, ALONG_X, Z_WHARF, "Potomac")
	# The piers of the bridge that used to cross here, standing in the water.
	_put(g, B % "mark_aqueduct_piers", -176.0, S_WHARF + 62.0, ALONG_X + 180.0, Z_WHARF, "AqueductPiers")
	# Arlington, across the water. Mesh only and never walked on: it is a
	# horizon, and the moment anything can reach it, it has to be a map.
	_put(g, B % "wharf_far_shore", 0.0, S_WHARF + 380.0, ALONG_X, Z_WHARF + 1.0, "Arlington")


# ── The level ────────────────────────────────────────────────────────────────

## Objective anchors. TERRAIN puts the pins in and names them; what a mission
## does with them is GAMEPLAY's, which is why these are places and not tasks.
## node, tag, label, x, y, z
const OBJECTIVES: Array = [
	# AT THE REAL BAY POSITIONS. These were written before the bay layout
	# moved and then stayed put: the probe called half of them unreachable
	# because they were sitting in the middle of the canal 32 m from the
	# bridge they were named after. An anchor nothing can reach is a mission
	# that cannot be finished, and nothing says so until someone plays it.
	# At the coping, not on the chamber floor: the lock sills are 0.55 m, over
	# the 0.5 the baker climbs, so the chamber is deliberately its own place
	# and an anchor down there is one nothing can walk to.
	["GT_Lock", "obj_gt_lock", "The Lock", 48.0, 0.0, -6.0],
	["GT_TrussWest", "obj_gt_truss_west", "West Footbridge", -144.0, 0.0, 0.0],
	["GT_RoadBridge", "obj_gt_road_bridge", "The Street Bridge", -16.0, 0.0, 0.0],
	# On the bed BESIDE the bags, not on top of them: the stack is a stepped
	# climb and its top is its own little island, so an anchor up there snapped
	# to the one surface in the prism nothing can walk onto.
	["GT_Cofferdam", "obj_gt_cofferdam", "The Cofferdam", -112.0, -3.0, -2.0],
	["GT_Mill", "obj_gt_mill", "The Long Mill", -212.0, 0.0, -12.0],
	["GT_Ramp", "obj_gt_ramp", "The Ramped Street", 132.0, 2.0, -50.0],
	# Was at z 88, which is inside a warehouse.
	["GT_Yards", "obj_gt_yards", "The Lower Yards", -62.0, -4.0, 70.0],
	["GT_Esplanade", "obj_gt_esplanade", "The Esplanade", 40.0, -8.0, 162.0],
	["GT_Pier", "obj_gt_pier", "The Centre Pier", 0.0, -8.0, 166.0],
	["GT_Park", "obj_gt_park", "The Tennis Court", -148.0, -8.0, 148.0],
	["GT_Stack", "obj_gt_stack", "The Stack", 86.0, -4.0, 112.0],
]


## The level scene, written as text: a handful of nodes with an ext_resource
## list. The art scene is packed instead, because it is hundreds of instances.
func _write_level() -> void:
	var objs := PackedStringArray()
	for o: Array in OBJECTIVES:
		objs.append(('[node name="%s" type="Node3D" parent="NavigationRegion3D/Objectives"]\n'
				+ 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)') % [o[0], o[3], o[4], o[5]])
	var text := """[gd_scene load_steps=7 format=3]

[ext_resource type="PackedScene" path="%s" id="1_art"]
[ext_resource type="PackedScene" uid="uid://g7fmy28elpah" path="res://Env/world_objects/spawn_point.tscn" id="2_spawn"]

[sub_resource type="ProceduralSkyMaterial" id="Sky_mat"]
sky_top_color = Color(0.52, 0.55, 0.58, 1)
sky_horizon_color = Color(0.68, 0.69, 0.69, 1)
ground_bottom_color = Color(0.45, 0.46, 0.47, 1)
ground_horizon_color = Color(0.68, 0.69, 0.69, 1)

[sub_resource type="Sky" id="Sky_gt"]
sky_material = SubResource("Sky_mat")

[sub_resource type="Environment" id="Env_gt"]
background_mode = 2
sky = SubResource("Sky_gt")
ambient_light_source = 3
ambient_light_color = Color(0.46, 0.47, 0.49, 1)
ambient_light_sky_contribution = 0.7
ambient_light_energy = 0.85
tonemap_mode = 2
fog_enabled = true
fog_light_color = Color(0.68, 0.69, 0.7, 1)
fog_density = 0.0006

[sub_resource type="NavigationMesh" id="NavigationMesh_gt"]
vertices = PackedVector3Array()
polygons = []
cell_size = 0.25
agent_radius = 0.5
agent_height = 1.8
agent_max_climb = 0.25
region_min_size = 16.0
edge_max_error = 1.3
detail_sample_distance = 6.0
geometry_parsed_geometry_type = 1
filter_baking_aabb = AABB(-260, -16, -140, 520, 48, 300)

[node name="GeorgetownLevel" type="Node3D"]

[node name="NavigationRegion3D" type="NavigationRegion3D" parent="."]
navigation_mesh = SubResource("NavigationMesh_gt")

[node name="GeorgetownArt" parent="NavigationRegion3D" instance=ExtResource("1_art")]

[node name="Objectives" type="Node3D" parent="NavigationRegion3D"]

%s

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Env_gt")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.82, 0.33, -0.46, 0, 0.81, 0.58, 0.57, -0.48, 0.67, 0, 80, 0)
light_energy = 0.9
light_color = Color(1, 0.98, 0.95, 1)
shadow_enabled = true
directional_shadow_max_distance = 260.0

[node name="SpawnPoint" parent="." instance=ExtResource("2_spawn")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -170, 7, -118)
""" % [ART, "\n\n".join(objs)]
	var f := FileAccess.open(LEVEL, FileAccess.WRITE)
	if f == null:
		print("FAIL  could not write %s (%s)" % [LEVEL, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string(text)
	f.close()
