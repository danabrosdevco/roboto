extends SceneTree

# ─────────────────────────────────────────────
# A RELOAD, SEEN FROM OUTSIDE THE PLAYER'S HEAD.
#
#   godot --audio-driver Dummy --path . \
#       --script res://tools/probe_reload_outside.gd -- <out dir> <weapon.tscn> [frames]
#
# IT NEEDS A WINDOW. It is a camera; run it WITHOUT --headless.
#
# preview_viewmodel renders from the player's eye, which is the right place to
# ask "does this read in play" and a useless one for asking "does this part move
# at all". The Squad Automatic opens its feed cover and drops its ammunition
# box, and from the eye you used to see the side of the barrel and none of it.
# So this parks a camera beside the weapon instead.
#
# THE GUN BODY IS HELD STILL ON PURPOSE. _reload_frame returns a pose for the
# whole weapon AND poses its parts on the way past; this throws the body pose
# away and keeps only the parts. The frame then stays put between shots, so
# anything that moves is a part moving and not the camera losing the gun.
# ─────────────────────────────────────────────


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("probe_reload_outside: this is a camera. Run it without --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("probe_reload_outside: need an out dir and a weapon scene")
		quit(1)
		return
	var out: String = args[0]
	var path: String = args[1]
	var frames: int = int(args[2]) if args.size() > 2 else 9
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))

	var gun: Node3D = (load(path) as PackedScene).instantiate()
	root.add_child(gun)
	for _i in 4:
		await process_frame
	if not gun.has_method("_reload_frame"):
		printerr("probe_reload_outside: %s has no _reload_frame to drive." % path.get_file())
		quit(1)
		return
	# A WEAPON THE PLAYER HOLDS IS LOADED — same reason preview_viewmodel does
	# this. A drum or a belt rendered empty is a still of the gun having no
	# ammunition, not a still of the reload.
	if gun.get("magazine_size") != null and int(gun.get("loaded")) == 0:
		gun.set("loaded", int(gun.get("magazine_size")))

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, 35, 0)
	light.light_energy = 1.3
	root.add_child(light)
	var env := WorldEnvironment.new()
	var e: Environment = load("res://Env/world_environment.tres")
	env.environment = e if e != null else Environment.new()
	root.add_child(env)

	# FRAMED ONCE, AT REST, off the weapon's own bounding box — so the camera is
	# the same in every frame and the parts are the only thing that changes.
	var aabb := _bounds(gun)
	var centre := aabb.get_center()
	var span: float = maxf(aabb.size.length(), 1.0)
	var long_axis := _axis(aabb.size, true)
	var side_axis := _axis(aabb.size, false)
	var up_axis := (Vector3(1, 1, 1) - long_axis - side_axis).normalized()
	# Side on, and a three-quarter from above-front, because a part that moves
	# straight along the camera's own axis does not appear to move at all.
	var eyes := {
		"side": centre + side_axis * span * 0.70,
		"quarter": centre + side_axis * span * 0.45 + up_axis * span * 0.30
				+ long_axis * span * 0.30,
	}
	for i in frames:
		var t: float = float(i) / float(maxi(frames - 1, 1))
		gun._reload_frame(t)
		await process_frame
		for name_text in eyes:
			await _shoot(eyes[name_text], centre, out,
				"%s_%s_%02d" % [path.get_file().get_basename(), name_text, i], t)
	print("done — %d frame(s)" % frames)
	quit(0)


func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


func _shoot(eye: Vector3, look: Vector3, out: String, name_text: String, t: float) -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = eye
	cam.look_at(look, Vector3.UP)
	cam.current = true
	cam.near = 0.01
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("%s/%s.png" % [out, name_text])
	print("  %s.png   t=%.3f" % [name_text, t])
	cam.queue_free()


## The unit axis of `v`'s largest (or smallest) component.
func _axis(v: Vector3, largest: bool) -> Vector3:
	var a := absf(v.x)
	var b := absf(v.y)
	var c := absf(v.z)
	if largest:
		if a >= b and a >= c: return Vector3(1, 0, 0)
		return Vector3(0, 1, 0) if b >= c else Vector3(0, 0, 1)
	if a <= b and a <= c: return Vector3(1, 0, 0)
	return Vector3(0, 1, 0) if b <= c else Vector3(0, 0, 1)
