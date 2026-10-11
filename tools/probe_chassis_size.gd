extends SceneTree

# ─────────────────────────────────────────────
# CHASSIS SIZE — what every frame in the armoury actually measures, from its
# COLLISION, not from its art.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_chassis_size.gd
#
# WHY IT EXISTS. Every navmesh in this project is baked against three numbers —
# agent_radius, agent_height, agent_max_climb — and all three are a claim about
# the bodies that will walk on it. The claim has been wrong on every map so far
# in the same direction: the mesh is baked for something half the size of the
# squad, reports PASS, and the squad then jams in a gap the mesh said was open.
# Godot has no per-agent clearance (a path query takes no radius), so the ONLY
# defence is baking against the real widest and tallest body — and that number
# has to be measured, because an @export default in a chassis script says
# nothing about the capsule in the scene (scene values beat script defaults).
#
# It reads the CollisionShape3D under each chassis scene and prints the half
# width, the full width, the height and the length, plus the step the mover
# will actually take. Those are the numbers that go into a bake.
# ─────────────────────────────────────────────

const CHASSIS_DIR := "res://Campaign/chassis"


func _initialize() -> void:
	await process_frame
	var dir := DirAccess.open(CHASSIS_DIR)
	if dir == null:
		print("FAIL  %s will not open" % CHASSIS_DIR)
		quit(1)
		return
	var names := dir.get_files()
	names.sort()
	var rows: Array = []
	for f: String in names:
		if not f.ends_with(".tres"):
			continue
		var def := load("%s/%s" % [CHASSIS_DIR, f])
		if def == null or def.scene == null:
			# EVERY EARLY RETURN WARNS. A chassis with no scene cannot be sized
			# and silently skipping it is how a frame nobody measured ends up
			# being the one that does not fit.
			print("   %-24s no scene on the definition — NOT MEASURED" % f.get_basename())
			continue
		var body := (def.scene as PackedScene).instantiate()
		root.add_child(body)
		await process_frame
		var box := _collision_aabb(body)
		var step: float = _num(body, "step_height", -1.0)
		var fwd: float = _num(body, "step_forward", -1.0)
		rows.append([str(def.id), box, step, fwd, bool(def.get("vehicle")), bool(def.get("drives"))])
		body.queue_free()
		await process_frame

	print("")
	print("   %-18s %7s %7s %7s %7s  %6s %6s  %s" % [
			"chassis", "half-w", "width", "height", "length", "step", "fwd", "kind"])
	var widest := 0.0
	var tallest := 0.0
	var longest := 0.0
	var least_step := INF
	for r: Array in rows:
		var b: AABB = r[1]
		var w: float = maxf(b.size.x, b.size.z)
		var l: float = maxf(b.size.x, b.size.z)
		var narrow: float = minf(b.size.x, b.size.z)
		# A capsule is round, so width and length are the same number and the
		# only honest thing to print is the footprint both ways round. A hull is
		# not: its long axis is the one that has to turn a corner.
		print("   %-18s %7.2f %7.2f %7.2f %7.2f  %6.2f %6.2f  %s" % [
				r[0], w * 0.5, narrow, b.size.y, l,
				float(r[2]), float(r[3]),
				("vehicle" if r[4] else "legs") + (" drives" if r[5] else "")])
		# THE NEST IS NOT A MOVER. It is an enemy structure that does not walk
		# (ruled 2026-09-28), so its 2.60 m footprint is not a claim on any
		# navmesh — and left in, it is the widest thing in the armoury and would
		# set the bake radius for every map.
		if str(r[0]) == "nest":
			continue
		widest = maxf(widest, narrow)
		tallest = maxf(tallest, b.size.y)
		longest = maxf(longest, l)
		if float(r[2]) >= 0.0:
			least_step = minf(least_step, float(r[2]))
	print("")
	print("   WHAT A HONEST BAKE WOULD USE")
	print("      agent_radius    >= %.2f   (half the widest body, %.2f m)" % [widest * 0.5, widest])
	print("      agent_height    >= %.2f   (the tallest body)" % tallest)
	print("      agent_max_climb <= %.2f   (the SMALLEST step any body takes)" % least_step)
	print("      turning radius  >= %.2f   (half the longest hull, for a corner)" % (longest * 0.5))
	print("   agent_max_climb ABOVE the smallest step is the inverted band rule:")
	print("   the mesh crosses a lip the body then refuses, and the squad stops.")
	print("CHASSIS SIZE DONE")
	quit(0)


## A property if the script has it, else the fallback. Chassis bodies do not all
## derive from the same script, so asking blind is the only way.
func _num(n: Node, prop: String, fallback: float) -> float:
	var v: Variant = n.get(prop)
	return float(v) if v != null else fallback


## The union of every CollisionShape3D under the body, in the body's own space.
## THE COLLISION AND NOT THE MESH: the art overhangs (a gun barrel, an aerial)
## and the navmesh cares about what the physics engine will refuse to push
## through, which is the shape.
##
## PHYSICS BODIES ONLY. Every robot also carries Area3D sensors — sight, hearing,
## the shove field — and those are spheres 50 to 120 m across. Counted in, they
## made the first run of this probe report a 50 m wide Walker and a bake radius
## of 60 m, which is wrong by a factor of thirty and wrong in the dangerous
## direction: it looks like a measurement.
func _collision_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for cs: CollisionShape3D in n.find_children("*", "CollisionShape3D", true, false):
		if cs.shape == null or cs.disabled:
			continue
		if not (cs.get_parent() is PhysicsBody3D):
			continue
		var local := cs.shape.get_debug_mesh()
		if local == null:
			continue
		var xf: Transform3D = (n as Node3D).global_transform.affine_inverse() * cs.global_transform
		var box := xf * local.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out
