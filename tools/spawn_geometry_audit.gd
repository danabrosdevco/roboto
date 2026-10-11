extends SceneTree

# ─────────────────────────────────────────────
# WHERE DID THEY ACTUALLY LAND?
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/spawn_geometry_audit.gd -- <mission id>
#   godot --headless --audio-driver Dummy --path . --script res://tools/spawn_geometry_audit.gd        (all of them)
#
# spawn_check.gd already answers "did the right NUMBER of bodies appear". This
# answers the question it cannot: are they standing anywhere sensible.
#
# Reported from play on Polaris — hostiles spawning INSIDE the ramp down to the
# basement. A body embedded in a brush counts fine, paths fine on the navmesh
# it was snapped to, and is invisible to every existing check.
#
# THREE THINGS GO WRONG AND THEY LOOK ALIKE FROM A DISTANCE:
#
#   BURIED    the body's own capsule overlaps solid geometry. It is in a wall,
#             in a ramp, or under a floor.
#   NO FLOOR  nothing solid within a couple of metres below it. It will fall,
#             which on a multi-storey structure means it arrives on the wrong
#             deck a second after the mission starts.
#   ADRIFT    far from the navmesh, so wherever it is standing it cannot walk
#             out of it.
#
# All three are measured against the REAL level and the REAL spawner, because
# the bug is in the interaction between a post authored at y = 0 and geometry
# that has more than one floor at that x/z.
# ─────────────────────────────────────────────

## How far below a body we look for something to stand on before calling it
## unsupported. Generous: a body legitimately sits a few cm above its surface.
const FLOOR_REACH := 2.5
## Distance from the navmesh past which a body cannot be said to be on it.
const ADRIFT_AT := 4.0

var _rows: Array = []


func _init() -> void:
	await process_frame
	var want: String = ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		want = args[0].strip_edges()

	var dir := DirAccess.open("res://Campaign/missions")
	var names := dir.get_files()
	names.sort()
	for f in names:
		if not f.ends_with(".tres"):
			continue
		var m = load("res://Campaign/missions/" + f)
		if m == null or m.level_scene == null:
			continue
		if want != "" and String(m.id) != want:
			continue
		await _audit(m)

	print("")
	if _rows.is_empty():
		print("NO BAD SPAWNS FOUND")
		quit(0)
		return
	print("── %d BODY/BODIES SPAWNED BADLY ──" % _rows.size())
	for r in _rows:
		print("  %s" % r)
	quit(1)


func _audit(m) -> void:
	var level: Node = m.level_scene.instantiate()
	root.add_child(level)
	# LET THE NAVIGATION MAP SYNC BEFORE DEPLOYING.
	#
	# NavigationServer3D commits regions on a physics step, so a force deployed
	# on the frame the level was added asks an EMPTY map: map_get_closest_point
	# returns Vector3.ZERO, _seat_is_clear refuses every candidate for want of
	# walkable ground, GroundSnap.stand skips its pull, and the spawner plants
	# the whole force on its raw ring offsets. That is not what the game does —
	# it is an artefact of the harness, and an audit that measures it reports
	# bad spawns the player will never see while hiding the ones they will.
	for _i in 6:
		await physics_frame
	var spawner = preload("res://Campaign/enemy_force_spawner.gd").new()
	root.add_child(spawner)
	spawner.deploy_force(level, m)
	# Several frames: the navmesh region bakes and the bodies settle.
	for _i in 8:
		await process_frame
	await physics_frame

	# AND THE RESERVES. A garrison is only the half of the force that is
	# standing there when you arrive; Polaris alone authors 57 specs, most of
	# them waves that land later on tags the player triggers. Auditing only the
	# deploy misses every reinforcement, and a wave arriving inside a structure
	# is WORSE than a garrison doing it — it happens mid-fight, with the player
	# watching, and nothing about it looks like a spawn bug from the outside.
	var tags := {}
	for spec in m.enemy_force:
		if spec != null and spec.posture == EnemySquadSpec.Posture.RESERVE:
			tags[spec.reinforcement_tag] = true
	for t in tags:
		spawner.wake(t)
	for _i in 8:
		await process_frame
	await physics_frame

	var world: World3D = (level as Node3D).get_world_3d()
	var bad := 0
	var total := 0
	for c in level.get_children():
		if not (c is Soldier):
			continue
		total += 1
		var problems := _inspect(c as Soldier, world)
		if problems.is_empty():
			continue
		bad += 1
		_rows.append("%-22s %-16s at (%.0f, %.1f, %.0f)  %s" % [
			m.id, c.soldier_name, c.global_position.x, c.global_position.y,
			c.global_position.z, ", ".join(problems)])
	print("%s %-22s %3d body/bodies, %d badly placed" % [
		"ok  " if bad == 0 else "BAD ", m.id, total, bad])

	spawner.queue_free()
	level.queue_free()
	await process_frame


## What is wrong with where this body is standing, if anything.
func _inspect(body: Soldier, world: World3D) -> Array:
	var out: Array = []
	var at: Vector3 = body.global_position

	# ── BURIED ────────────────────────────────
	# The body's own collision shape, tested where it stands, against static
	# geometry only. Its own collider is excluded, and so is every other body:
	# two robots overlapping is a spacing problem, not a geometry one, and
	# _spread_from already owns that.
	var shape := _shape_of(body)
	if shape != null:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis(), at)
		q.collide_with_bodies = true
		q.collide_with_areas = false
		for hit in world.direct_space_state.intersect_shape(q, 8):
			var other = hit.collider
			if other == body or other is CharacterBody3D or other is RigidBody3D:
				continue
			out.append("BURIED in %s" % other.name)
			break

	# ── AIRBORNE? ─────────────────────────────
	# An air arrival is SUPPOSED to have nothing under it and to be off the
	# navmesh: spawn_offset.y is what makes it an air arrival, and the spawner
	# skips ground-snapping entirely for those (see the spawn_offset.y <= 0.0
	# gate). Flagging them produced 49 NO FLOOR and 48 ADRIFT rows that were all
	# helicopters doing exactly the right thing, which buried the 75 rows that
	# were real. The body does not carry its spec, so height above the nearest
	# walkable ground is the test.
	var mesh_pt := NavigationServer3D.map_get_closest_point(world.navigation_map, at)
	var airborne: bool = mesh_pt != Vector3.ZERO and at.y - mesh_pt.y > 6.0
	if airborne:
		return out   # the burial test above still applies; these two do not

	# ── NO FLOOR ──────────────────────────────
	# Straight down from just inside the body. Other bodies are looked
	# through, the same way GroundSnap._surface does it.
	var q2 := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.2, at + Vector3.DOWN * FLOOR_REACH)
	var skip: Array[RID] = []
	var floor_y := NAN
	for _i in 4:
		q2.exclude = skip
		var hit := world.direct_space_state.intersect_ray(q2)
		if hit.is_empty():
			break
		if hit.collider is CharacterBody3D or hit.collider is RigidBody3D:
			skip.append(hit.rid)
			continue
		floor_y = (hit.position as Vector3).y
		break
	if is_nan(floor_y):
		out.append("NO FLOOR within %.1fm" % FLOOR_REACH)

	# ── ADRIFT ────────────────────────────────
	var on_mesh := NavigationServer3D.map_get_closest_point(world.navigation_map, at)
	if on_mesh != Vector3.ZERO and not out.is_empty():
		var flat: float = Vector2(on_mesh.x - at.x, on_mesh.z - at.z).length()
		out.append("navmesh %.1fm away flat (%.1fm in 3D)" % [flat, at.distance_to(on_mesh)])
	if on_mesh != Vector3.ZERO:
		var d: float = at.distance_to(on_mesh)
		if d > ADRIFT_AT:
			out.append("ADRIFT")
	return out


## The body's own collision shape, shrunk slightly. Full size would report a
## body merely standing against a wall, which is where a garrison belongs.
func _shape_of(body: Node3D) -> Shape3D:
	for c in body.get_children():
		if c is CollisionShape3D and c.shape != null:
			var s: Shape3D = c.shape
			if s is CapsuleShape3D:
				var cap := CapsuleShape3D.new()
				cap.radius = maxf((s as CapsuleShape3D).radius * 0.6, 0.1)
				cap.height = maxf((s as CapsuleShape3D).height * 0.7, 0.3)
				return cap
			if s is BoxShape3D:
				var box := BoxShape3D.new()
				box.size = (s as BoxShape3D).size * 0.6
				return box
	return null
