extends SceneTree

# ─────────────────────────────────────────────
# IS THE BODY IN THE WALL, OR IS THE AUDIT IN THE FLOOR?
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_spawn_sink.gd -- hillfort_1_relay
#
# spawn_geometry_audit.gd called 39 bodies BURIED across eight missions, and
# every single row named the terrain itself (entity_0_worldspawn, Collision)
# with the navmesh 0.0 m away flat. A body genuinely inside a building is not
# standing dead on the walkable surface, so the shape of that result says the
# test is wrong before it says the spawns are.
#
# Two candidate faults, and they are told apart by ONE number — how far the
# body's capsule bottom sits below the floor under it:
#
#   > 0      the body really is sunk, and the question is whether it settles
#   = 0      the audit's own shrunken capsule is reaching through the floor
#
# So this prints the geometry instead of a verdict: shape extents, where the
# shape sits relative to the body origin, the floor beneath, and what the
# overlap test says at one physics frame and again after thirty.
# ─────────────────────────────────────────────

func _init() -> void:
	Engine.max_fps = 60
	await process_frame
	var want: String = ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		want = args[0].strip_edges()
	if want == "":
		print("give a mission id")
		quit(1)
		return

	var m = load("res://Campaign/missions/mission_%s.tres" % want)
	if m == null:
		# the file is not named after the id on every mission
		var dir := DirAccess.open("res://Campaign/missions")
		for f in dir.get_files():
			if not f.ends_with(".tres"):
				continue
			var c = load("res://Campaign/missions/" + f)
			if c != null and String(c.id) == want:
				m = c
				break
	if m == null or m.level_scene == null:
		print("no mission '%s' with a level" % want)
		quit(1)
		return

	var level: Node = m.level_scene.instantiate()
	root.add_child(level)
	for _i in 30:
		await process_frame
	await physics_frame

	var spawner = preload("res://Campaign/enemy_force_spawner.gd").new()
	root.add_child(spawner)
	spawner.deploy_force(level, m)
	for _i in 8:
		await process_frame
	await physics_frame

	var world: World3D = (level as Node3D).get_world_3d()
	print("── AT ONE PHYSICS FRAME ──")
	_report(level, world)
	for _i in 30:
		await physics_frame
	print("")
	print("── AFTER THIRTY MORE ──")
	_report(level, world)
	quit(0)



func _report(level: Node, world: World3D) -> void:
	for c in level.get_children():
		if not (c is Soldier):
			continue
		var body := c as Soldier
		var cs: CollisionShape3D = null
		for k in body.get_children():
			if k is CollisionShape3D and k.shape != null:
				cs = k
				break
		if cs == null:
			continue
		var at: Vector3 = body.global_position
		var mid: Vector3 = cs.global_position
		var half := 0.0
		if cs.shape is CapsuleShape3D:
			half = (cs.shape as CapsuleShape3D).height * 0.5
		elif cs.shape is BoxShape3D:
			half = (cs.shape as BoxShape3D).size.y * 0.5
		elif cs.shape is SphereShape3D:
			half = (cs.shape as SphereShape3D).radius

		# The floor, looked for from above the capsule so the ray cannot start
		# inside the thing it is trying to find.
		var q := PhysicsRayQueryParameters3D.create(mid + Vector3.UP * (half + 0.5), mid + Vector3.DOWN * 6.0)
		var skip: Array[RID] = []
		var floor_y := NAN
		var floor_name := "-"
		for _i in 6:
			q.exclude = skip
			var hit := world.direct_space_state.intersect_ray(q)
			if hit.is_empty():
				break
			if hit.collider is CharacterBody3D or hit.collider is RigidBody3D:
				skip.append(hit.rid)
				continue
			floor_y = (hit.position as Vector3).y
			floor_name = String((hit.collider as Node).name)
			break

		# What the audit's own test reports, and what a test placed at the
		# shape's REAL transform reports, side by side.
		var audit_hit := _overlap(world, body, _shrunk(cs.shape), Transform3D(Basis(), at))
		var true_hit := _overlap(world, body, _shrunk(cs.shape), cs.global_transform)

		print("  %-16s y %6.2f  shape mid y %6.2f half %4.2f  bottom %6.2f  floor %6.2f (%s)  sunk %5.2f  audit:%-22s real:%s" % [
			body.soldier_name, at.y, mid.y, half, mid.y - half,
			floor_y, floor_name,
			(floor_y - (mid.y - half)) if not is_nan(floor_y) else NAN,
			audit_hit, true_hit])


func _shrunk(s: Shape3D) -> Shape3D:
	if s is CapsuleShape3D:
		var cap := CapsuleShape3D.new()
		cap.radius = maxf((s as CapsuleShape3D).radius * 0.6, 0.1)
		cap.height = maxf((s as CapsuleShape3D).height * 0.7, 0.3)
		return cap
	if s is BoxShape3D:
		var box := BoxShape3D.new()
		box.size = (s as BoxShape3D).size * 0.6
		return box
	return s


func _overlap(world: World3D, body: Node, shape: Shape3D, xform: Transform3D) -> String:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = xform
	q.collide_with_bodies = true
	q.collide_with_areas = false
	for hit in world.direct_space_state.intersect_shape(q, 8):
		var other = hit.collider
		if other == body or other is CharacterBody3D or other is RigidBody3D:
			continue
		return String((other as Node).name)
	return "clear"
