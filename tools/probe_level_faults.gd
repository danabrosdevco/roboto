extends SceneTree

# ─────────────────────────────────────────────
# HOLES, FLOATERS AND COLLISIONS AT LEVEL SCALE
#
#   LEVEL=res://maps/georgetown_level.tscn godot --path . \
#       --script res://tools/probe_level_faults.gd
#
# NOT headless: some pieces only build their collision with a renderer up, and
# a probe that reports "no ground" because nothing loaded is worse than none.
#
# WHY THIS EXISTS. tools/probe_map_overlap.gd checks ONE .map against itself,
# and tools/probe_nav_reach.gd checks whether the squad can get places. Between
# those two there is a gap big enough to drive a map through: a level is
# hundreds of correctly-built pieces placed at coordinates, and the faults are
# in the ARRANGEMENT, not in any piece.
#
# Three of them, and all three shipped in Georgetown unnoticed:
#
#   1. HOLES. A piece 28 m long dropped into a 32 m bay leaves 2 m of nothing
#      at each end. From above it is invisible; from inside it is a void the
#      squad stops at. Found by raycasting a grid down over the whole site.
#   2. FLOATERS. A piece placed at the wrong height hangs in the air or sinks
#      into the ground. Found by casting down from under each instance and
#      measuring the gap.
#   3. COLLISIONS. Two instances occupying the same space — not two walls
#      touching, which is fine, but a building standing inside another one.
#      Found by intersecting their collision bounds.
#
# It reports and changes nothing. The numbers are a starting point for looking,
# not a verdict: a canopy SHOULD float and two abutting terraces SHOULD share a
# boundary, so read the list rather than counting it.
# ─────────────────────────────────────────────

## Grid pitch for the hole sweep.
const STEP := 8.0
## Cast from this high and down to this low, in level coordinates.
const SKY := 200.0
const ABYSS := -60.0
## A floater is reported when its lowest collision sits this far above what is
## under it. Generous, because bridges, canopies and decks are meant to.
const FLOAT_GAP := 2.5
## Two instances are reported when they share more than this much volume.
const SHARED_M3 := 12.0


func _initialize() -> void:
	await process_frame
	var level_path := OS.get_environment("LEVEL")
	if level_path == "":
		print("usage: LEVEL=res://maps/<name>_level.tscn godot --path . --script res://tools/probe_level_faults.gd")
		quit(2)
		return
	var packed := ResourceLoader.load(level_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed == null:
		print("FAIL  could not load %s" % level_path)
		quit(1)
		return
	var level: Node3D = packed.instantiate()
	root.add_child(level)
	for _i in 50:
		await physics_frame
	var space := level.get_world_3d().direct_space_state

	var pieces: Array = []
	_gather(level, pieces)
	print("   %s — %d placed piece(s)" % [level_path.get_file(), pieces.size()])
	if pieces.is_empty():
		print("FAIL  nothing instanced in this level")
		quit(1)
		return

	var bounds := _bounds(pieces)
	print("   site %.0f x %.0f m centred (%.0f, %.0f)" % [bounds.size.x, bounds.size.z,
			bounds.get_center().x, bounds.get_center().z])
	_holes(space, bounds)
	_floaters(space, pieces)
	_collisions(pieces)
	_coplanar(space, bounds)
	print("LEVEL FAULTS DONE — read the lists, do not count them")
	quit()


## Every instanced prefab under the level, with the bounds of its collision.
## RECURSE THROUGH INSTANCES, not just up to them. A level instances ONE art
## scene and the art scene instances the three hundred blocks, so stopping at
## the first node with a scene_file_path finds exactly one piece and reports
## the whole map as a single floating object — which is what it did first time.
## A block is anything instanced out of maps/blocks; everything else is
## scaffolding to walk through.
func _gather(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Node3D and c.scene_file_path.contains("/maps/blocks/"):
			var b := _collision_bounds(c)
			if b.size.length() > 0.01:
				out.append({"node": c, "name": String(c.name), "path": c.scene_file_path, "box": b})
			continue
		_gather(c, out)


## The world-space AABB of everything that collides under `n`. Collision and
## not mesh, deliberately: a mesh-only canopy is scenery and a mesh-only river
## is 600 m wide, and neither is a thing the arrangement can be wrong about.
func _collision_bounds(n: Node) -> AABB:
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


## Every physics body under a node, so a downward cast can ignore the piece
## it is testing.
func _bodies(n: Node) -> Array:
	var out: Array = []
	for b: CollisionObject3D in n.find_children("*", "CollisionObject3D", true, false):
		out.append(b.get_rid())
	if n is CollisionObject3D:
		out.append((n as CollisionObject3D).get_rid())
	return out


func _bounds(pieces: Array) -> AABB:
	var box: AABB = pieces[0].box
	for p: Dictionary in pieces:
		box = box.merge(p.box)
	return box


func _down(space: PhysicsDirectSpaceState3D, x: float, z: float, from_y: float, to_y: float) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, to_y, z)))


## HOLES. Sweep the site and report every column with nothing under it. The
## edges are trimmed by one step, because the rim of the ground slabs is the
## edge of the world and always reads empty just past it.
func _holes(space: PhysicsDirectSpaceState3D, bounds: AABB) -> void:
	print("\n   ── holes in the ground ──")
	# Two steps in from the bounds. The bounds include the river and the far
	# shore, which reach well past the ground, so one step still sampled open
	# space along the whole rim and reported it as holes.
	# OFFSET OFF THE GRID. Ground tiles butt on whole-metre lines and this sweep
	# steps in whole metres, so samples landed exactly on the seams — and a ray
	# straight down a seam hits BOTH neighbours at the same height and calls it
	# two floors. Touching is not overlapping. 0.37 m misses every boundary the
	# kit can produce.
	var lo := bounds.position + Vector3(STEP * 2.0 + 0.37, 0.0, STEP * 2.0 + 0.37)
	var hi := bounds.end - Vector3(STEP * 2.0, 0.0, STEP * 2.0)
	var checked := 0
	var found: Array = []
	var x := lo.x
	while x <= hi.x:
		var z := lo.z
		while z <= hi.z:
			checked += 1
			if _down(space, x, z, SKY, ABYSS).is_empty():
				found.append(Vector2(x, z))
			z += STEP
		x += STEP
	if found.is_empty():
		print("      none in %d column(s)" % checked)
		return
	# Cluster them, because one 4 m void reads as four samples and a list of
	# four hundred coordinates is not a thing anybody acts on.
	var clusters: Array = []
	for p: Vector2 in found:
		var joined := false
		for c: Array in clusters:
			if (c[0] as Vector2).distance_to(p) <= STEP * 2.1:
				c[0] = ((c[0] as Vector2) * float(c[1]) + p) / float(int(c[1]) + 1)
				c[1] = int(c[1]) + 1
				joined = true
				break
		if not joined:
			clusters.append([p, 1])
	clusters.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	print("      %d empty column(s) of %d, in %d area(s):" % [found.size(), checked, clusters.size()])
	for i in mini(clusters.size(), 12):
		var c: Array = clusters[i]
		var p: Vector2 = c[0]
		print("      near (%.0f, %.0f)  about %.0f m2" % [p.x, p.y, float(c[1]) * STEP * STEP])


## FLOATERS. Cast down from just under each piece and measure the drop. A
## piece whose own collision is what the ray hits is standing on itself, which
## is what most of them do, so the cast starts below its bottom face.
func _floaters(space: PhysicsDirectSpaceState3D, pieces: Array) -> void:
	print("\n   ── floating and sunken pieces ──")
	var worst: Array = []
	for p: Dictionary in pieces:
		var b: AABB = p.box
		var c := b.get_center()
		# FROM ABOVE, WITH THE PIECE ITSELF EXCLUDED. Cast from just under its
		# bottom face and the ray starts INSIDE the 4 m ground slab it is
		# standing on, which registers no hit at all — so the first run of this
		# reported 255 of 260 pieces as floating in a void.
		# FROM ABOVE THE PIECE, not from just under it. Every building in this
		# kit is founded four metres below its floor so it never floats on
		# uneven fill, which means a cast starting at its base starts inside the
		# slab it is founded in and hits nothing. From over the top, the first
		# thing under it is the ground, and a NEGATIVE gap just means founded.
		var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, b.end.y + 1.0, c.z), Vector3(c.x, ABYSS, c.z))
		q.exclude = _bodies(p.node)
		var hit := space.intersect_ray(q)
		# NOTHING UNDERNEATH IS NOT A FAULT. The ground plates, the prism and
		# anything over water have nothing beneath them by definition, and
		# reporting those drowned the list. Only a measurable gap ABOVE a real
		# surface is a floater.
		if hit.is_empty():
			continue
		var gap: float = b.position.y - (hit["position"] as Vector3).y
		if gap > FLOAT_GAP:
			worst.append({"n": p.name, "gap": gap, "y": b.position.y})
	if worst.is_empty():
		print("      none above %.1f m" % FLOAT_GAP)
		return
	worst.sort_custom(func(a, b): return a.gap > b.gap)
	print("      %d piece(s) sitting more than %.1f m above what is under them:" % [worst.size(), FLOAT_GAP])
	for i in mini(worst.size(), 14):
		var w: Dictionary = worst[i]
		if is_inf(w.gap):
			print("      %-28s nothing underneath at all, bottom y %.1f" % [w.n, w.y])
		else:
			print("      %-28s %.1f m of air under it, bottom y %.1f" % [w.n, w.gap, w.y])


## GROUND PLATES. A building is MEANT to sink into the ground it stands on —
## every one of these pieces has its base four metres below its floor so it
## never floats on uneven fill. Pairing those against the slab gave 416 hits
## led by a bench against a terrace of houses at 7,661 m3, which is not a
## fault, it is the houses being founded. Ground is excluded from the pair
## test; everything else is fair game.

## TWO SURFACES AT THE SAME HEIGHT IN THE SAME PLACE — the thing that actually
## flickers, and the one fault none of the other checks can see.
##
## probe_map_overlap catches brushes sharing volume inside ONE block. The pair
## test above catches two pieces occupying the same space. Neither sees a road
## bed lying flat on a car park: they share almost no volume, they are two
## separate .map files so no brush probe compares them, and the only thing
## wrong is that both have a horizontal face at y = 0 over the same ground.
## The depth buffer cannot choose between them and the surface crawls.
##
## Measured by casting down, then casting again from a hair above whatever was
## hit with that collider excluded. A second surface within SAME_PLANE of the
## first is two floors in one place.
const SAME_PLANE := 0.03


func _coplanar(space: PhysicsDirectSpaceState3D, bounds: AABB) -> void:
	print("\n   ── two floors in the same place ──")
	# OFFSET OFF THE GRID. Ground tiles butt on whole-metre lines and this sweep
	# steps in whole metres, so samples landed exactly on the seams — and a ray
	# straight down a seam hits BOTH neighbours at the same height and calls it
	# two floors. Touching is not overlapping. 0.37 m misses every boundary the
	# kit can produce.
	var lo := bounds.position + Vector3(STEP * 2.0 + 0.37, 0.0, STEP * 2.0 + 0.37)
	var hi := bounds.end - Vector3(STEP * 2.0, 0.0, STEP * 2.0)
	var checked := 0
	var found: Array = []
	var x := lo.x
	while x <= hi.x:
		var z := lo.z
		while z <= hi.z:
			var first := _down(space, x, z, SKY, ABYSS)
			if not first.is_empty():
				checked += 1
				var y: float = (first["position"] as Vector3).y
				var q := PhysicsRayQueryParameters3D.create(Vector3(x, y + 0.002, z), Vector3(x, ABYSS, z))
				q.exclude = [first["rid"]]
				var second := space.intersect_ray(q)
				if not second.is_empty():
					var y2: float = (second["position"] as Vector3).y
					if absf(y - y2) <= SAME_PLANE:
						found.append({"p": Vector2(x, z), "y": y,
								"a": _owner_of(first["collider"]), "b": _owner_of(second["collider"])})
			z += STEP
		x += STEP
	if found.is_empty():
		print("      none in %d column(s)" % checked)
		return
	# Count by which two pieces are doing it, because one bad placement loop
	# shows up as two hundred samples and the fix is one line.
	var byname := {}
	for f: Dictionary in found:
		var k: String = "%s  +  %s" % [f.a, f.b]
		byname[k] = int(byname.get(k, 0)) + 1
	var keys: Array = byname.keys()
	keys.sort_custom(func(a, b): return int(byname[a]) > int(byname[b]))
	print("      %d of %d column(s) have two floors — by piece pair:" % [found.size(), checked])
	for i in mini(keys.size(), 12):
		print("      %5d x  %s" % [byname[keys[i]], keys[i]])


## The instanced block a collider belongs to, walking up to the first ancestor
## that came out of maps/blocks.
func _owner_of(collider: Object) -> String:
	var n := collider as Node
	while n != null:
		if n is Node3D and n.scene_file_path.contains("/maps/blocks/"):
			return n.scene_file_path.get_file().get_basename()
		n = n.get_parent()
	return "?"

const GROUND_PIECES: Array = ["canal_bench", "polaris_lot_main", "polaris_lot_field",
		"polaris_ground_grass", "ground/tile_"]


## Pairs that are MEANT to share an envelope, as name prefixes. Without this
## the list is led every run by the same six intentional things — silt lying in
## a canal bed, a stair cut into its wall — and a report people learn to skim
## is a report that hides the seventh.
const EXPECTED: Array = [["Debris", "Prism"], ["CanalStair", "Prism"], ["Bridge", "Prism"],
		["LockGear", "Lock"], ["Cofferdam", "Prism"], ["Outfall", "Prism"],
		["Row", "TownWalk"], ["Row", "MStreet"], ["Car", "Aisle"], ["Cars", "Aisle"]]


func _expected(a: String, b: String) -> bool:
	for e: Array in EXPECTED:
		if (a.begins_with(e[0]) and b.begins_with(e[1])) or (b.begins_with(e[0]) and a.begins_with(e[1])):
			return true
	return false


func _is_ground(path: String) -> bool:
	for g: String in GROUND_PIECES:
		if path.contains(g):
			return true
	return false


## COLLISIONS. Instances whose collision bounds share real volume. Touching
## scores nothing, which is the point — the fault is a building inside another
## building, not two walls meeting.
func _collisions(pieces: Array) -> void:
	print("\n   ── pieces inside each other ──")
	var hits: Array = []
	for i in pieces.size():
		for j in range(i + 1, pieces.size()):
			if _is_ground(pieces[i].path) or _is_ground(pieces[j].path):
				continue
			var a: AABB = pieces[i].box
			var b: AABB = pieces[j].box
			if not a.intersects(b):
				continue
			var s := a.intersection(b)
			var vol := s.size.x * s.size.y * s.size.z
			if vol > SHARED_M3 and not _expected(pieces[i].name, pieces[j].name):
				hits.append({"a": pieces[i].name, "b": pieces[j].name, "v": vol, "c": s.get_center()})
	if hits.is_empty():
		print("      none sharing more than %.0f m3" % SHARED_M3)
		return
	hits.sort_custom(func(x, y): return x.v > y.v)
	print("      %d pair(s) sharing more than %.0f m3:" % [hits.size(), SHARED_M3])
	for i in mini(hits.size(), int(OS.get_environment("FAULT_LIST")) if OS.get_environment("FAULT_LIST") != "" else 14):
		var h: Dictionary = hits[i]
		print("      %-24s %-24s %7.0f m3 at (%.0f, %.0f, %.0f)" % [h.a, h.b, h.v, h.c.x, h.c.y, h.c.z])
