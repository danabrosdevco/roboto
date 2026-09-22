extends RefCounted

# ─────────────────────────────────────────────
# GROUND SNAP — where a robot spawned at a spot should stand: pulled onto
# walkable ground, with its LOWEST point on the real surface there.
#
# A BODY THAT STARTS UNDER THE GENERATED TERRAIN FALLS THROUGH IT. A heightfield
# only pushes things out upward, from above. Spawn spots are laid out flat — a
# ring round a navmesh point, an arc behind a spawn marker — and the navmesh
# itself sits anywhere within its detail error of the real ground, so on a
# slope part of a squad starts underground; and a soldier's origin is the
# middle of its capsule, a metre above its feet. Ten robots of the Coast Road's
# first deploy dropped out of the world.
#
# The spot is pulled onto the navmesh first — never onto a wall top, which a
# straight drop through a compound could find — and the surface is only looked
# for close above that, for the same reason. Both spawners go through here, so
# a squad and the force it meets always land the same way.
# ─────────────────────────────────────────────

## How far above and below its spot on the navmesh a body looks for the real
## surface. Above is kept short so nobody lands on a wall.
const LOOK_UP := 1.5
const LOOK_DOWN := 2.5


## Where `body` should be put to stand at `p`, in the world `place` is in.
static func stand(p: Vector3, body: Node3D, place: Node) -> Vector3:
	var world: World3D = (place as Node3D).get_world_3d() if place is Node3D and place.is_inside_tree() else null
	if world == null:
		return p   # not in a world yet (a test rig): nothing to stand on
	var foot := foot_depth(body)
	var spot := p
	var on_mesh := NavigationServer3D.map_get_closest_point(world.navigation_map, p)
	if on_mesh != Vector3.ZERO and Vector2(on_mesh.x - p.x, on_mesh.z - p.z).length() < 3.0:
		spot = on_mesh
	var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * LOOK_UP, spot + Vector3.DOWN * LOOK_DOWN)
	var skip: Array[RID] = []
	for _i in 4:
		q.exclude = skip
		var hit := world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			break   # no surface close to the navmesh here: trust the navmesh
		if hit.collider is CharacterBody3D or hit.collider is RigidBody3D:
			skip.append(hit.rid)   # a robot spawned a moment ago, or a round: the ground is under it
			continue
		return hit.position + Vector3.UP * (foot + 0.05)
	return spot + Vector3.UP * (foot + 0.3)


## How far below its origin a body reaches — its feet, tracks, wheels or base.
## A soldier's capsule is centred on its origin, so its feet are a metre down.
static func foot_depth(body: Node3D) -> float:
	var lowest := 0.0
	for child in body.get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.shape == null or cs.disabled:
			continue
		lowest = minf(lowest, (cs.transform * _shape_box(cs.shape)).position.y)
	return -lowest


static func _shape_box(s: Shape3D) -> AABB:
	if s is CapsuleShape3D:
		var c := s as CapsuleShape3D
		return AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius), Vector3(c.radius * 2.0, c.height, c.radius * 2.0))
	if s is CylinderShape3D:
		var y := s as CylinderShape3D
		return AABB(Vector3(-y.radius, -y.height * 0.5, -y.radius), Vector3(y.radius * 2.0, y.height, y.radius * 2.0))
	if s is BoxShape3D:
		var b := s as BoxShape3D
		return AABB(-b.size * 0.5, b.size)
	if s is SphereShape3D:
		var r := (s as SphereShape3D).radius
		return AABB(Vector3.ONE * -r, Vector3.ONE * r * 2.0)
	if s is ConvexPolygonShape3D:
		var pts := (s as ConvexPolygonShape3D).points
		if not pts.is_empty():
			var box := AABB(pts[0], Vector3.ZERO)
			for pt in pts:
				box = box.expand(pt)
			return box
	return AABB()   # a shape this does not size: taken to reach no lower than its origin
