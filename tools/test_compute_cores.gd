extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# A CAPTURE POINT YOU CANNOT PRESS IS WORSE THAN NO CAPTURE POINT.
#
# These three put the interactive volume around a compute core instead of a
# console box, and the sizing is not free choice. The player's InteractRaycast:
#
#   * is 2 m long
#   * masks collision layer 2 ONLY, so it goes straight through the core's solid
#     body and only ever reports Interactible areas
#   * has hit_from_inside off, so a ray that STARTS inside the volume reports
#     nothing at all
#
# Which means the volume has to be small enough that the player — stopped by the
# core's own collision at their own body radius — is still OUTSIDE it. Sized to
# the footprint that works out at about half a metre of clearance. Make the
# volume generous "to be safe" and it stops working entirely, silently, and only
# in game.
#
# So this stands a real player against a real core and presses it.
#
#   godot --headless --path . --script res://tools/test_compute_cores.gd
# ─────────────────────────────────────────────

const VARIANTS := [
	# MEASURED OFF THE 2026-10-14 ART, which is bigger than the models these
	# numbers were first written against and is no longer SQUARE in plan — so
	# the footprint is now two numbers, not one.
	{"scene": "res://Env/world_objects/compute_core_point_small.tscn",
		"foot": 3.56, "deep": 5.56, "tall": 4.50},
	{"scene": "res://Env/world_objects/compute_core_point.tscn",
		"foot": 4.81, "deep": 6.31, "tall": 7.31},
	{"scene": "res://Env/world_objects/compute_core_point_large.tscn",
		"foot": 6.56, "deep": 8.25, "tall": 12.72},
]
## What the player's own InteractRaycast can reach, read from the scene so this
## test fails loudly if someone shortens it.
const RAY_LEN := 2.0

var _fails: int = 0
var _player: Node3D = null
var _level: Node = null


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _init() -> void:
	# PACE THE LOOP — see the note in tools/test.sh. Without this a
	# --script run has no frame cap, _process spins flat out and starves
	# physics, and every await physics_frame below takes far longer in
	# wall clock than the 1/60 s it is written as.
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 100:
		await physics_frame
	_player = _find(root, "Player")
	_level = _player.get_parent()

	var ray: RayCast3D = _player.get("interact_raycast")
	_check("the player's interact ray is still %.1f m, masking only interactibles" % RAY_LEN,
		ray != null and is_equal_approx(absf(ray.target_position.z), RAY_LEN) and ray.collision_mask == 2
			and ray.collide_with_areas and not ray.collide_with_bodies,
		"len %.2f mask %d areas %s bodies %s" % [absf(ray.target_position.z), ray.collision_mask,
			str(ray.collide_with_areas), str(ray.collide_with_bodies)])
	# WITHOUT THIS NONE OF THE CORES CAN BE PRESSED. The player steps onto a
	# core's base plate and ends up standing INSIDE its reach volume, and a ray
	# that starts inside a shape reports nothing unless this is set. It also
	# fixes the console terminals, whose prompt used to vanish if you walked
	# right up to them.
	_check("...and it registers a volume it is standing inside", ray != null and ray.hit_from_inside)

	for v in VARIANTS:
		await _test(v)

	print("")
	print("ALL COMPUTE CORE CHECKS PASS" if _fails == 0 else "%d COMPUTE CORE CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


func _test(v: Dictionary) -> void:
	var name: String = String(v["scene"]).get_file()
	var foot: float = v["foot"]
	var point: Node3D = load(v["scene"]).instantiate()
	_level.add_child(point)
	point.global_position = Vector3(0, 0, 0)
	for _i in 20:
		await physics_frame

	print("")
	print("  %s" % name)

	# ── THE CORE IS THERE AND THE RIGHT SIZE ──
	var core := point.get_node_or_null("Core")
	var box := _bounds(core)
	_check("   the core is %.1f m tall on a %.2f m footprint" % [v["tall"], foot],
		core != null and absf(box.size.y - v["tall"]) < 0.1 and absf(box.size.x - foot) < 0.1,
		"%.2f x %.2f x %.2f" % [box.size.x, box.size.y, box.size.z])

	# ── THE REACH MATCHES THE FOOTPRINT ──
	var inter: Node3D = point.get_node_or_null("Terminal/Interactible")
	var cs := inter.get_node_or_null("CollisionShape3D") as CollisionShape3D if inter != null else null
	var shape := cs.shape as BoxShape3D if cs != null else null
	# NOT BIGGER THAN THE CORE, which is the whole point: a reach volume that
	# overhangs its core is one the player ends up standing INSIDE, where the
	# interact ray reports nothing at all. Asserted as a bound now rather than
	# an exact match — the prefabs author their own inset and it differs per
	# axis, because the cores are not square.
	_check("   its reach is inside the core, not bigger",
		shape != null and shape.size.x <= foot + 0.05 and shape.size.z <= v["deep"] + 0.05,
		"reach %s vs core %.2f x %.2f" % [str(shape.size) if shape != null else "none", foot, float(v["deep"])])

	# ── AND THE CONSOLE CASING IS GONE ──
	var term := point.get_node_or_null("Terminal")
	var body := term.get_node_or_null("Body") if term != null else null
	_check("   the console casing is hidden, so the core is what you see",
		body != null and not (body as Node3D).visible)

	# ── THE PLAYER CAN ACTUALLY PRESS IT ──
	# Walked into the core from the south until its own collision stops them.
	var cam: Camera3D = _player.get("cam")
	_player.global_position = Vector3(0, 0, foot * 0.5 + 6.0)
	for _i in 10:
		await physics_frame
	# Drive them in rather than teleporting to a guessed distance: the stopping
	# point is whatever the core's collision decides, which is the number that
	# matters.
	for _i in 90:
		_player.velocity = Vector3(0, _player.velocity.y, -4.0)
		_player.move_and_slide()
		await physics_frame
	var stood: float = _player.global_position.z
	# PINNED. The player's own _physics_process re-lerps the camera every frame,
	# so an aim set here is gone again before the ray is fired.
	_player.set_physics_process(false)
	_player.look_direction = Vector3.ZERO
	_player.rotation.y = 0.0
	cam.rotation = Vector3.ZERO
	for _i in 4:
		await physics_frame

	var ray: RayCast3D = _player.get("interact_raycast")
	ray.force_raycast_update()
	var hit = ray.get_collider()
	if hit == null:
		var cs2 := inter.get_node_or_null("CollisionShape3D") as CollisionShape3D
		print("        ray from %s to %s | interactible at %s layer %d monitorable %s | shape disabled %s" % [
			str(ray.global_position.snapped(Vector3.ONE * 0.01)),
			str((ray.global_position + ray.global_transform.basis * ray.target_position).snapped(Vector3.ONE * 0.01)),
			str(inter.global_position.snapped(Vector3.ONE * 0.01)),
			inter.collision_layer, str(inter.monitorable), str(cs2.disabled if cs2 != null else "no shape")])
	_check("   a player who walks into it stops at %.2f m and the ray reaches" % stood,
		hit != null and hit is Interactible,
		"ray hit %s" % (str(hit.get_parent().name) + "/" + str(hit.name) if hit != null else "NOTHING"))

	# ── AND channel_range CLEARS WHERE THEY ARE STANDING ──
	var dist: float = _player.global_position.distance_to(inter.global_position)
	_check("   channel_range %.1f clears the %.2f m they stand at" % [point.channel_range, dist],
		point.channel_range > dist + 0.5, "%.2f m of slack" % (point.channel_range - dist))

	_player.set_physics_process(true)
	point.free()
	for _i in 4:
		await physics_frame


func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	if n == null:
		return out
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		for k in c.get_children():
			stack.append(k)
		if c is VisualInstance3D:
			var a: AABB = (c as VisualInstance3D).get_aabb()
			a = (c as Node3D).global_transform * a
			if first:
				out = a; first = false
			else:
				out = out.merge(a)
	return out
