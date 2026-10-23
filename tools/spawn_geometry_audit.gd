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
# FIVE THINGS GO WRONG AND THEY LOOK ALIKE FROM A DISTANCE:
#
#   BURIED    the body's own capsule overlaps solid geometry. It is in a wall,
#             in a ramp, or under a floor.
#   NO FLOOR  nothing solid within a couple of metres below it. It will fall,
#             which on a multi-storey structure means it arrives on the wrong
#             deck a second after the mission starts.
#   ADRIFT    far from the navmesh, so wherever it is standing it cannot walk
#             out of it.
#   ON OBJ    standing on top of a capture objective: on its plinth, on the
#             bunker roof. Overlaps nothing, stands on a real surface, is on
#             the navmesh, and the objective itself screens it from every
#             approach. Added 2026-10-15 with the fix in EnemyForceSpawner.
#   ENCLOSED  walled in every horizontal direction at chest height. The body
#             overlaps nothing and stands on the floor, but it is inside ART
#             and no shot can reach it. Added 2026-10-15 after hostiles on
#             Hillfort were reported standing "in the capture objective" where
#             they could not be hit; the burial test called them clear, because
#             they were.
#
# All five are measured against the REAL level and the REAL spawner, because
# the bug is in the interaction between a post authored at y = 0 and geometry
# that has more than one floor at that x/z.
# ─────────────────────────────────────────────

## How far below a body we look for something to stand on before calling it
## unsupported. Generous: a body legitimately sits a few cm above its surface.
const FLOOR_REACH := 2.5
## Distance from the navmesh past which a body cannot be said to be on it.
const ADRIFT_AT := 4.0
## How close the walls have to be, in every horizontal direction at once,
## before a body counts as unreachable rather than merely in cover.
const ENCLOSED_AT := 2.0

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
	# AT THE SHAPE'S OWN TRANSFORM, NOT THE BODY'S ORIGIN. Most chassis author
	# their capsule at the origin, but a few offset it upward — and testing
	# those at the origin drops the capsule by that offset and pushes it
	# through the floor. That alone produced 39 BURIED rows across eight
	# missions, every one of them naming the terrain with the navmesh 0.0 m
	# away, and all 39 were the floor. _shape_of now returns the transform too.
	var pair := _shape_of(body)
	if not pair.is_empty():
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = pair[0]
		q.transform = pair[1]
		q.collide_with_bodies = true
		q.collide_with_areas = false
		for hit in world.direct_space_state.intersect_shape(q, 8):
			var other = hit.collider
			if other == body or other is CharacterBody3D or other is RigidBody3D:
				continue
			# AND ANYTHING HANGING OFF ANOTHER ROBOT. A Bulwark's ShieldBlocker
			# is a StaticBody on its arm, so the type test above looks straight
			# past it and reports a body standing behind a shield as buried in
			# the level. Two robots touching is a spacing problem and _spread_from
			# already owns it; this file is about geometry.
			if _worn_by_a_robot(other as Node):
				continue
			out.append("BURIED in %s" % other.name)
			break

	# ── ON THE OBJECTIVE ──────────────────────
	# STANDING ON THE FURNITURE, which is not an overlap and not an enclosure.
	# A body on top of a core's plinth or a bunker's roof collides with
	# nothing, stands on a real surface, is on the navmesh, and has a clear
	# shot out while its own objective screens it from every approach. All
	# three tests above call it fine; the player calls it unkillable.
	#
	# Found on Hillfort from play: DISH-1 dead centre on the relay core, 1.6 m
	# up. EnemyForceSpawner._on_objective_prop now pushes them off, and this is
	# what proves it stays that way.
	var under := _standing_on(at, world)
	if under != "":
		out.append("ON THE OBJECTIVE (%s)" % under)

	# ── ENCLOSED ──────────────────────────────
	# CAN ANYTHING SHOOT IT? This is the test the burial check above cannot do,
	# and it is the one the player reported: hostiles on Hillfort standing "in
	# the capture objective" that could not be hit.
	#
	# A body can be perfectly clear of every collider and still be unreachable,
	# because the thing enclosing it is ART — a core's housing, a gantry, a
	# machine casing — whose collision wraps a hollow the body is sitting in.
	# The capsule overlaps nothing, the floor is under it, the navmesh is at its
	# feet, and no bullet can reach it from anywhere.
	#
	# Twelve rays at chest height, every 30 degrees. Other bodies are looked
	# through: a robot behind cover is cover working, not a bug. ENCLOSED means
	# every single direction is walled within ENCLOSED_AT, which no legitimate
	# garrison post is — a body in a corner has two sides, in a doorway two, in
	# the tightest authored alcove three.
	var chest: Vector3 = at
	if not pair.is_empty():
		chest = (pair[1] as Transform3D).origin
	var walls := {}
	var boxed := 0
	for i in 12:
		var a: float = TAU * float(i) / 12.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var q3 := PhysicsRayQueryParameters3D.create(chest, chest + dir * ENCLOSED_AT)
		var skip3: Array[RID] = []
		for _k in 4:
			q3.exclude = skip3
			var h := world.direct_space_state.intersect_ray(q3)
			if h.is_empty():
				break
			if h.collider is CharacterBody3D or h.collider is RigidBody3D:
				skip3.append(h.rid)
				continue
			boxed += 1
			var n := String((h.collider as Node).name)
			walls[n] = int(walls.get(n, 0)) + 1
			break
	if boxed >= 12:
		# Name the thing it is inside, which is what makes the row actionable.
		var worst := "?"
		var most := 0
		for n in walls:
			if int(walls[n]) > most:
				most = int(walls[n])
				worst = n
		out.append("ENCLOSED within %.1fm on all sides (mostly %s)" % [ENCLOSED_AT, worst])

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


## The body's own collision shape, shrunk slightly, AND WHERE IT ACTUALLY SITS.
## Full size would report a body merely standing against a wall, which is where
## a garrison belongs.
##
## Returns [shape, global_transform] or []. The transform is the half that was
## missing: an offset capsule tested at the body origin reads as buried in the
## floor it is standing on. tools/probe_spawn_sink.gd measures the difference.
func _shape_of(body: Node3D) -> Array:
	for c in body.get_children():
		if c is CollisionShape3D and c.shape != null:
			var s: Shape3D = c.shape
			var at: Transform3D = (c as CollisionShape3D).global_transform
			if s is CapsuleShape3D:
				var cap := CapsuleShape3D.new()
				cap.radius = maxf((s as CapsuleShape3D).radius * 0.6, 0.1)
				cap.height = maxf((s as CapsuleShape3D).height * 0.7, 0.3)
				return [cap, at]
			if s is BoxShape3D:
				var box := BoxShape3D.new()
				box.size = (s as BoxShape3D).size * 0.6
				return [box, at]
	return []


## The name of the capture objective this body is standing on, or "". Cast
## down, look through other bodies, then walk up from whatever it landed on
## looking for a HoldableCore or the bunker. Mirrors
## EnemyForceSpawner._on_objective_prop deliberately — the audit and the fix
## have to agree on what "on the objective" means or one of them is lying.
func _standing_on(at: Vector3, world: World3D) -> String:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, at + Vector3.DOWN * 2.5)
	var skip: Array[RID] = []
	for _i in 4:
		q.exclude = skip
		var hit := world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return ""
		if hit.collider is CharacterBody3D or hit.collider is RigidBody3D:
			skip.append(hit.rid)
			continue
		return _objective_above(hit.collider as Node)
	return ""


func _objective_above(n: Node) -> String:
	var up: Node = n
	for _i in 6:
		if up == null:
			return ""
		if String(up.name) == "SiteBunker":
			return "SiteBunker"
		var s = up.get_script()
		if s != null and String(s.resource_path).ends_with("holdable_core.gd"):
			return String(up.name)
		for c in up.get_children():
			var cs = c.get_script()
			if cs != null and String(cs.resource_path).ends_with("holdable_core.gd"):
				return String(up.name)
		up = up.get_parent()
	return ""


## Is this collider part of a robot rather than part of the level? Walked up
## rather than type-tested, because the pieces that catch a shape query are
## mounted deep in a rig — ShieldBlocker sits six nodes down a Bulwark's arm.
func _worn_by_a_robot(n: Node) -> bool:
	var up: Node = n
	for _i in 10:
		if up == null:
			return false
		if up is CharacterBody3D or up is RigidBody3D:
			return true
		up = up.get_parent()
	return false
