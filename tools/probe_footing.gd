extends SceneTree

# ─────────────────────────────────────────────
# FOOTING — which placed pieces are standing in the air, and which are buried.
#
#   LEVEL=res://maps/hillfort_level.tscn godot --path . --script res://tools/probe_footing.gd
#
# NOT headless: it raycasts, and the collision comes from the level's own
# bodies, which need a real physics world to be there.
#
# WHY IT EXISTS. A piece is placed by a table of x, z and a yaw, and its height
# comes from whatever the table thinks the ground is at that point. Get that
# number from the wrong stage of the terrain build — before the floor is
# shifted, off the pad rather than on it, or off a pad that a later modifier
# moved — and the piece hangs in the air. Nothing warns: it builds, it bakes,
# it reports reachable, and you only find it by walking round the back of it.
#
# So: take each piece's lowest geometry, sample the ground under its footprint,
# and print the gap. The piece's OWN collision is excluded from the ray, which
# is the whole trick — a ray dropped through a building hits the building.
# ─────────────────────────────────────────────

## GAP IS GROUND MINUS THE PIECE'S LOWEST POINT, so a POSITIVE gap means the
## piece is bedded into the ground and a NEGATIVE one means it is standing off
## it. Worth saying out loud: written the other way round, this tool called
## thirty-five correctly bedded pieces floating and found none of the ones that
## were.
##
## A gap this small either way is how a piece is meant to sit — a foot pressed
## a few centimetres in so no seam shows.
const SNUG := 0.25
## A piece can legitimately stand on a deck or a roof rather than the ground,
## and saying so every time would drown the ones that matter.
const ABSURD := 40.0
## Bedded deeper than this everywhere and the piece has lost its own feet.
const DROWNED := 2.5
## How many columns across the footprint the piece is measured in.
const GRID := 16


func _initialize() -> void:
	await process_frame
	var path := OS.get_environment("LEVEL")
	if path == "":
		path = "res://maps/hillfort_level.tscn"
	var packed := load(path) as PackedScene
	if packed == null:
		print("FAIL  %s will not load" % path)
		quit(1)
		return
	var level := packed.instantiate() as Node3D
	root.add_child(level)
	for _i in 40:
		await physics_frame
	var space := level.get_world_3d().direct_space_state
	var pieces: Array = level.find_children("*", "Node3D", true, false).filter(
			func(n: Node) -> bool: return n.scene_file_path.begins_with("res://maps/blocks/"))
	print("   %s" % path)
	print("   %d placed piece(s)" % pieces.size())
	var flying: Array = []
	var sunk: Array = []
	var blind := 0
	for p: Node3D in pieces:
		var box := _visual_aabb(p)
		if box.size == Vector3.ZERO:
			continue
		var skip: Array[RID] = []
		for c: CollisionObject3D in p.find_children("*", "CollisionObject3D", true, false):
			skip.append(c.get_rid())
		var floor_y := _columns(p, box)
		var gaps: Array = []
		for key: Vector2i in floor_y:
			var x: float = box.position.x + (key.x + 0.5) * box.size.x / GRID
			var z: float = box.position.z + (key.y + 0.5) * box.size.z / GRID
			var q := PhysicsRayQueryParameters3D.create(
					Vector3(x, box.end.y + 4.0, z), Vector3(x, box.position.y - 120.0, z))
			q.exclude = skip
			var hit := space.intersect_ray(q)
			if not hit.has("position"):
				continue
			gaps.append(float(hit["position"].y) - float(floor_y[key]))
		if gaps.is_empty():
			blind += 1
			print("   %-38s nothing under it at all — off the terrain?" % p.name)
			continue
		# THE MIDDLE COLUMN IS THE HONEST ONE, and the worst is not.
		#
		# A dish 40 m across on a pedestal has most of its area hanging over
		# open ground, so its worst column is 40 m off the deck and it is not
		# floating at all. A hall hovering a metre up has EVERY column a metre
		# off. The median tells those apart and the minimum cannot, which is
		# why this reads a piece column by column rather than as one box.
		gaps.sort()
		var mid: float = gaps[gaps.size() / 2]
		var worst: float = gaps[0]
		if mid < -SNUG and mid > -ABSURD:
			flying.append([mid, worst, p, box])
		elif mid > DROWNED:
			sunk.append([mid, worst, p, box])
	flying.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	sunk.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	if not flying.is_empty():
		print("")
		print("   STANDING OFF THE GROUND — typical column, then the worst one")
		for row: Array in flying:
			_say(row)
	if not sunk.is_empty():
		print("")
		print("   BEDDED DEEP — every corner this far under the ground")
		for row: Array in sunk:
			_say(row)
	print("")
	print("   %d standing off the ground, %d bedded deep, %d with nothing under them" % [
			flying.size(), sunk.size(), blind])
	quit(1 if flying.size() + blind > 0 else 0)


func _say(row: Array) -> void:
	var p: Node3D = row[2]
	var box: AABB = row[3]
	print("   %-38s %6.2f m / %6.2f m   base y %.1f at (%.0f, %.0f)" % [
			p.name, float(row[0]), float(row[1]), box.position.y,
			box.get_center().x, box.get_center().z])


## The lowest the piece's geometry gets in each column of a GRID x GRID net
## over its footprint, as {cell -> y}. Columns the piece does not cover are
## left out, so a courtyard or the space between two legs is not measured.
##
## A triangle claims every cell its own footprint touches, and hands that cell
## its lowest corner. That reads a sloped underside as lower than it is, which
## is the safe way round: it under-reports floating and never invents it.
func _columns(p: Node3D, box: AABB) -> Dictionary:
	var out := {}
	var cell := Vector2(box.size.x / GRID, box.size.z / GRID)
	if cell.x <= 0.0 or cell.y <= 0.0:
		return out
	for mi: MeshInstance3D in p.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var to_world := mi.global_transform
		var tris := mi.mesh.get_faces()
		for t in tris.size() / 3:
			var a := to_world * tris[t * 3]
			var b := to_world * tris[t * 3 + 1]
			var c := to_world * tris[t * 3 + 2]
			var low := minf(a.y, minf(b.y, c.y))
			var x0 := int((minf(a.x, minf(b.x, c.x)) - box.position.x) / cell.x)
			var x1 := int((maxf(a.x, maxf(b.x, c.x)) - box.position.x) / cell.x)
			var z0 := int((minf(a.z, minf(b.z, c.z)) - box.position.z) / cell.y)
			var z1 := int((maxf(a.z, maxf(b.z, c.z)) - box.position.z) / cell.y)
			for ix in range(maxi(x0, 0), mini(x1, GRID - 1) + 1):
				for iz in range(maxi(z0, 0), mini(z1, GRID - 1) + 1):
					var key := Vector2i(ix, iz)
					if not out.has(key) or low < float(out[key]):
						out[key] = low
	return out


## Every mesh the piece draws, in world space. The MESH, not the collision: a
## piece can have a clip block below its floor, and a gap you cannot see is not
## the thing being looked for here.
func _visual_aabb(p: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in p.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var box := mi.global_transform * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out
