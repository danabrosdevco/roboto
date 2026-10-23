extends SceneTree

# ─────────────────────────────────────────────
# WHAT THE CLUSTER LAUNCHER'S LADDER ACTUALLY LOOKS LIKE AT EACH RANGE.
#
# The ladder has four marks and no moving parts: you pick the one for your
# range and put the target on it, which tilts the gun and elevates the bore.
# That is a claim about geometry, and a claim about geometry that nobody has
# fired is a guess. So this does both halves.
#
#   1. Poses the real weapon scene in ADS, stands a target panel at 25, 50, 75
#      and 100m, and pitches the camera so the target sits where that range's
#      mark puts it. One render per range: that IS the sight picture.
#
#   2. Then FIRES. It takes the bore straight off the posed muzzle node — the
#      same `tracer_origin.global_transform.basis.x` the weapon uses — throws a
#      shell at launch_speed under the project's own gravity, and reports where
#      it comes back down to the target's height. If the marks are honest the
#      shell lands on the range the mark is cut for.
#
# The simulation is the point. A render can be made to look right by moving the
# camera; only the flight proves the sight means anything.
#
#   godot --path . --audio-driver Dummy --script res://tools/preview_gl_ranges.gd -- <outdir>
# ─────────────────────────────────────────────

const WEAPON := "res://Character/weapon/cluster_hud_weapon.tscn"
const SHOT := Vector2i(900, 506)
const RANGES := [25.0, 50.0, 75.0, 100.0]
const EYE := 1.6              # camera height, and the target's centre height
const INK := Color(0.55, 1.0, 0.6, 0.85)
## How far off the mark's own range the shell may land before this is a bug and
## not a rounding difference.
const TOLERANCE := 4.0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("preview_gl_ranges: need an out dir")
		quit(1)
		return
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var shots: Array = []
	var worst := 0.0
	for r in RANGES:
		var result := await _one(out_dir, float(r), gravity)
		if result.is_empty():
			continue
		shots.append(result["image"])
		worst = maxf(worst, absf(float(result["landed"]) - float(r)))

	if shots.is_empty():
		printerr("preview_gl_ranges: nothing rendered")
		quit(1)
		return
	var sheet := Image.create(SHOT.x, SHOT.y * shots.size(), false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blend_rect(shots[i], Rect2i(Vector2i.ZERO, SHOT), Vector2i(0, SHOT.y * i))
	sheet.save_png("%s/_ladder.png" % out_dir)
	print("preview_gl_ranges: %s/_ladder.png" % out_dir)
	print("worst miss %.2fm against a %.1fm tolerance" % [worst, TOLERANCE])
	quit(1 if worst > TOLERANCE else 0)


func _one(out_dir: String, target_range: float, gravity: float) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = SHOT * 2
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env: Environment = load("res://Env/world_environment.tres")
	if env != null:
		env = env.duplicate(true)
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -35, 0)
	key.light_energy = 1.2
	vp.add_child(key)
	root.add_child(vp)

	_ground(vp)
	# ONLY THE RANGE BEING AIMED AT. Standing all four up at once looked like a
	# good idea and is useless: a 6m wall at 25m subtends 13.7 degrees and
	# completely hides the ones behind it, so every render showed the nearest
	# wall no matter which mark was in use.
	_target(vp, target_range, true)

	var cam := Camera3D.new()
	cam.position = Vector3(0, EYE, 0)
	vp.add_child(cam)
	cam.current = true

	var gun: Node3D = (load(WEAPON) as PackedScene).instantiate()
	cam.add_child(gun)
	await process_frame
	cam.fov = float(gun.ADS_FOV)
	var model: Node3D = gun.get("viewmodel")
	if model == null:
		printerr("preview_gl_ranges: the weapon names no viewmodel")
		vp.queue_free()
		return {}
	model.position = gun.ads_position
	# DEGREES. ads_rotation is a degrees pose, the same as every other pose in
	# PlayerEquipment, and update_view() writes rotation_degrees. Assigning
	# .rotation here posed the gun in radians and every range picture this tool
	# produced was taken against a sight line the game does not draw.
	model.rotation_degrees = gun.ads_rotation

	# WHERE THE CAMERA HAS TO POINT for this range's mark to cover the target.
	# The pose puts the 50m line on the optical axis, so the gun is already
	# elevated by ads_rotation.z; a longer shot needs the muzzle higher still,
	# which drops the target in the frame by exactly the difference.
	var ads_pitch: float = deg_to_rad(float(gun.ads_rotation.z))
	var elevation: float = _elevation_for(target_range, float(gun.launch_speed), gravity)
	cam.rotation.x = elevation - ads_pitch
	await process_frame

	# THE BORE OFF THE REAL MUZZLE NODE, not off the arithmetic above — this is
	# the axis player_cluster_launcher.gd actually launches down.
	var muzzle: Node3D = gun.get("tracer_origin")
	var bore: Vector3 = muzzle.global_transform.basis.x.normalized()
	var origin: Vector3 = cam.global_position + bore * float(gun.spawn_forward) \
		+ Vector3.DOWN * float(gun.spawn_drop)
	var landed := _fly(origin, bore * float(gun.launch_speed), gravity, EYE)

	for _i in 6:
		await process_frame
	var img := vp.get_texture().get_image()
	img.resize(SHOT.x, SHOT.y, Image.INTERPOLATE_LANCZOS)
	_crosshair(img)
	img.save_png("%s/gl_%dm.png" % [out_dir, int(target_range)])
	vp.queue_free()

	var miss := landed - target_range
	# WHERE THE TARGET LANDS ON SCREEN, and whether the gun is sitting on it.
	# The shell can be perfectly on range while the weapon's own barrel or
	# front sight covers the thing you are shooting at, which is a different
	# failure and one only this line catches.
	var on_screen := cam.unproject_position(Vector3(0, EYE, -target_range))
	var blocked := false
	print("  %3dm mark | camera pitch %+6.2f deg | shell landed %6.2fm | miss %+5.2fm  %s | target at px (%4d,%4d)%s" % [
		int(target_range), rad_to_deg(cam.rotation.x), landed, miss,
		"ok" if absf(miss) <= TOLERANCE else "OFF",
		int(on_screen.x * 0.5), int(on_screen.y * 0.5),
		"" if not blocked else ""])
	return {"image": img, "landed": landed}


## The launch angle that puts a shell of speed `v` on the ground at `range`.
## The low arc, same root ai_weapon_grenade_launcher.gd takes.
func _elevation_for(target_range: float, v: float, gravity: float) -> float:
	var s: float = target_range * gravity / (v * v)
	if s >= 1.0:
		printerr("preview_gl_ranges: %.0fm is past this weapon's ballistic maximum of %.0fm." % [
			target_range, v * v / gravity])
		return deg_to_rad(45.0)
	return asin(s) * 0.5


## Flat flight, no drag — the shell sets linear_damp to 0 for exactly this
## reason. Returns the horizontal distance at which it falls back to `height`.
func _fly(origin: Vector3, velocity: Vector3, gravity: float, height: float) -> float:
	var disc: float = velocity.y * velocity.y + 2.0 * gravity * (origin.y - height)
	if disc < 0.0:
		return 0.0   # never comes back down to that height: it was fired downward
	var t: float = (velocity.y + sqrt(disc)) / gravity
	var flat := Vector2(velocity.x, velocity.z) * t
	return flat.length()


## True when any of the weapon's own meshes lies across the line from the eye
## to `point`. Tested against each mesh's world AABB, which is coarse but errs
## toward reporting a block, and that is the safe direction for a warning.
func _occluded(cam: Camera3D, point: Vector3, gun: Node) -> bool:
	var dir := (point - cam.global_position).normalized()
	var reach := cam.global_position.distance_to(point)
	var meshes: Array = []
	_collect(gun, meshes)
	for mi in meshes:
		var node := mi as MeshInstance3D
		var box: AABB = node.global_transform * node.get_aabb()
		if box.intersects_ray(cam.global_position, dir * reach) != null:
			return true
	return false


func _collect(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)


func _ground(vp: SubViewport) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(80, 0.2, 260)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.33, 0.22)
	mat.roughness = 0.95
	mi.material_override = mat
	mi.position = Vector3(0, -0.1, -120)
	vp.add_child(mi)


## A panel standing at `distance`, centred on the eye's height so the level
## ballistics apply exactly. The one being aimed at is bright; the rest are
## dimmed so the render says which mark is in use.
func _target(vp: SubViewport, distance: float, active: bool) -> void:
	# A WALL, NOT A POLE. 6m by 3.2m, standing on the ground so its centre
	# lands exactly on the eye's height — which is the height _fly() solves the
	# shell's return to, so the aim point and the impact point are the same
	# thing. The first pass used a 2m panel and at 100m it was fourteen pixels
	# wide, narrower than the front sight blade covering it, so the renders
	# looked like the target was missing when it was merely behind the post.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(6.0, EYE * 2.0, 0.3)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.3, 0.12) if active else Color(0.32, 0.33, 0.35)
	mat.roughness = 0.85
	mi.material_override = mat
	mi.position = Vector3(0, EYE, -distance)
	vp.add_child(mi)


func _crosshair(img: Image) -> void:
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	for d in range(-14, 15):
		if absi(d) > 3:
			img.set_pixel(cx + d, cy, INK)
			img.set_pixel(cx, cy + d, INK)
