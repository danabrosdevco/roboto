extends SceneTree

# ─────────────────────────────────────────────
# DOES THE NAVMESH STILL RUN THROUGH THE NEW ART?
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_nav_vs_art.gd
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_nav_vs_art.gd -- hillfort_1_relay
#
# THE QUESTION BEHIND A PLAYTEST REPORT. Hostiles on Hillfort were standing "in
# the capture objective" where they could not be shot. spawn_geometry_audit.gd
# says every body on every map is clear of geometry and clear of enclosure, so
# the bodies are not the fault — which leaves the one thing that changed under
# them.
#
# THE CORES AND THE BUNKER ENTRANCES ARE RUNTIME NODES. SiteSlice builds them
# when the level loads. The navmesh in each level .tscn was baked BEFORE they
# existed, so it has walkable polygon straight through where they now stand.
# Every body is ground-snapped onto that navmesh, so bodies are pulled to
# points inside the new art — and the art then stops the player's shot.
#
# This measures exactly that and nothing else: for every core and every bunker
# built by the slice, is there walkable navmesh inside its footprint? A YES is
# a rebake, not a code change — which is why this prints a list of maps rather
# than trying to fix anything.
# ─────────────────────────────────────────────

## How far in from a solid's own edge we sample, so a navmesh that merely
## touches the art is not reported. Only polygon genuinely UNDER it counts.
const INSET := 0.35


func _init() -> void:
	Engine.max_fps = 60
	await process_frame
	var want: String = ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		want = args[0].strip_edges()

	var dir := DirAccess.open("res://Campaign/missions")
	var names := dir.get_files()
	names.sort()
	var bad := 0
	for f in names:
		if not f.ends_with(".tres"):
			continue
		var m = load("res://Campaign/missions/" + f)
		if m == null or m.level_scene == null:
			continue
		if want != "" and String(m.id) != want:
			continue
		bad += await _check(m)
	print("")
	if bad == 0:
		print("NO NAVMESH UNDER ANY SLICE-BUILT SOLID")
		quit(0)
		return
	print("%d SOLID(S) WITH WALKABLE NAVMESH INSIDE THEM — these maps need a rebake" % bad)
	quit(1)


func _check(m) -> int:
	var level: Node = m.level_scene.instantiate()
	root.add_child(level)
	for _i in 10:
		await process_frame
	await physics_frame

	var world: World3D = (level as Node3D).get_world_3d()
	# EVERY SOLID THE SLICE PUT THERE. Found by walking the slice's own
	# subtree rather than by name, because the core prefabs, the bunker kit and
	# the generated placeholder bodies are three different shapes of thing.
	var solids: Array[CollisionShape3D] = []
	for slice in _slices(level):
		_shapes(slice, solids)
	var bad := 0
	var rows: Array = []
	for cs in solids:
		var box := _extent(cs)
		if box == Vector3.ZERO:
			continue
		var at: Vector3 = cs.global_position
		# NINE SAMPLES ACROSS THE FOOTPRINT, inset from the edges, at the
		# solid's own mid height. One sample at the centre would miss a navmesh
		# edge that clips a corner, which is the common case under a wide base.
		var hx: float = maxf(box.x * 0.5 - INSET, 0.0)
		var hz: float = maxf(box.z * 0.5 - INSET, 0.0)
		if hx <= 0.0 or hz <= 0.0:
			continue   # too small to hide anything inside
		var inside := 0
		var steps: Array[float] = [-1.0, 0.0, 1.0]
		for ix: float in steps:
			for iz: float in steps:
				var p := at + Vector3(hx * ix, 0.0, hz * iz)
				var mesh_pt := NavigationServer3D.map_get_closest_point(world.navigation_map, p)
				if mesh_pt == Vector3.ZERO:
					continue
				# Walkable ground directly under the sample, at roughly the
				# solid's own base height — not the floor outside it.
				var flat: float = Vector2(mesh_pt.x - p.x, mesh_pt.z - p.z).length()
				if flat < INSET and absf(mesh_pt.y - (at.y - box.y * 0.5)) < 1.5:
					inside += 1
		if inside > 0:
			bad += 1
			rows.append("    %-28s %4.1f x %4.1f at (%.0f, %.1f, %.0f)  %d/9 samples walkable" % [
				_label(cs), box.x, box.z, at.x, at.y, at.z, inside])
	print("%s %-22s %2d slice solid(s), %d with navmesh inside" % [
		"ok  " if bad == 0 else "BAD ", m.id, solids.size(), bad])
	for r in rows:
		print(r)

	level.queue_free()
	await process_frame
	return bad


## A readable name for a collision shape buried a few levels down a prefab.
func _label(cs: Node) -> String:
	var parts: Array[String] = []
	var n: Node = cs
	for _i in 4:
		if n == null:
			break
		parts.push_front(String(n.name))
		n = n.get_parent()
	return "/".join(parts)


func _slices(n: Node, out: Array[Node] = []) -> Array[Node]:
	var s = n.get_script()
	if s != null and String(s.resource_path).ends_with("_slice.gd"):
		out.append(n)
	for c in n.get_children():
		_slices(c, out)
	return out


## SOLIDS ONLY. The first cut collected every CollisionShape3D under a slice,
## which flagged the bunker's own Interactible on all eight maps — an Area3D on
## layer 3 whose whole job is to sit on walkable ground so the player can stand
## in it and press F. Walkable navmesh inside THAT is the feature.
##
## So anything owned by an Area3D is skipped. What is left is what can stop a
## bullet or a body.
func _shapes(n: Node, out: Array[CollisionShape3D]) -> void:
	if n is Area3D:
		return
	if n is CollisionShape3D and (n as CollisionShape3D).shape != null:
		out.append(n as CollisionShape3D)
	for c in n.get_children():
		_shapes(c, out)


## The solid's size in world units. Only the shapes big enough to hide a robot
## matter, so anything without a real footprint returns zero and is skipped.
func _extent(cs: CollisionShape3D) -> Vector3:
	var s: Shape3D = cs.shape
	var sc: Vector3 = cs.global_transform.basis.get_scale()
	if s is BoxShape3D:
		return (s as BoxShape3D).size * sc
	if s is CylinderShape3D:
		var c := s as CylinderShape3D
		return Vector3(c.radius * 2.0 * sc.x, c.height * sc.y, c.radius * 2.0 * sc.z)
	if s is CapsuleShape3D:
		var k := s as CapsuleShape3D
		return Vector3(k.radius * 2.0 * sc.x, k.height * sc.y, k.radius * 2.0 * sc.z)
	if s is SphereShape3D:
		var r: float = (s as SphereShape3D).radius
		return Vector3(r * 2.0 * sc.x, r * 2.0 * sc.y, r * 2.0 * sc.z)
	if s is ConvexPolygonShape3D:
		var pts: PackedVector3Array = (s as ConvexPolygonShape3D).points
		if pts.is_empty():
			return Vector3.ZERO
		var lo: Vector3 = pts[0]
		var hi: Vector3 = pts[0]
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		return (hi - lo) * sc
	return Vector3.ZERO
