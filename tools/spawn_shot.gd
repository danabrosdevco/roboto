extends SceneTree

# ─────────────────────────────────────────────
# PHOTOGRAPH A MISSION'S FORCE WHERE IT LANDS.
#
#   godot --audio-driver Dummy --path . --script res://tools/spawn_shot.gd -- <mission id> <x> <y> <z> <out dir>
#
# IT NEEDS A WINDOW — it is a camera. Run it WITHOUT --headless.
#
# spawn_geometry_audit.gd says a body is or is not inside a brush, which is a
# yes/no about a capsule overlap. It cannot say "half of this squad is standing
# in the ramp and it looks ridiculous", and that is the report that came in.
# A number and a picture disagree often enough in this project that the picture
# gets taken.
#
# Deploys the real force through the real spawner on the real level, including
# reinforcement waves, then puts a camera where you ask and looks at the point
# you name.
# ─────────────────────────────────────────────

var _out: String = "."


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("spawn_shot: this is a camera. Run it without --headless.")
		quit(1)
		return
	var a := OS.get_cmdline_user_args()
	if a.size() < 5:
		printerr("spawn_shot: need <mission id> <x> <y> <z> <out dir>")
		quit(1)
		return
	var want := a[0]
	var look := Vector3(float(a[1]), float(a[2]), float(a[3]))
	_out = a[4]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))

	var m = null
	var dir := DirAccess.open("res://Campaign/missions")
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var cand = load("res://Campaign/missions/" + f)
		if cand != null and String(cand.id) == want:
			m = cand
			break
	if m == null or m.level_scene == null:
		printerr("spawn_shot: no mission '%s' with a level." % want)
		quit(1)
		return

	var level: Node = m.level_scene.instantiate()
	root.add_child(level)
	await process_frame   # what world.gd does before deploying
	var spawner = preload("res://Campaign/enemy_force_spawner.gd").new()
	root.add_child(spawner)
	spawner.deploy_force(level, m)
	var tags := {}
	for spec in m.enemy_force:
		if spec != null and spec.posture == EnemySquadSpec.Posture.RESERVE:
			tags[spec.reinforcement_tag] = true
	for t in tags:
		spawner.wake(t)
	# Let everything settle onto whatever it is going to settle onto. A body
	# that spawned embedded gets shoved somewhere by the physics within a
	# second, and where it ENDS UP is what the player sees.
	for _i in 90:
		await process_frame

	# Four points of the compass at a shallow angle, because a structure hides
	# its own interior from every direction but one and there is no telling in
	# advance which.
	for i in 4:
		var angle := TAU * float(i) / 4.0
		var eye := look + Vector3(cos(angle), 0.0, sin(angle)) * 26.0 + Vector3.UP * 11.0
		await _shoot(eye, look, "spawn_%s_%d" % [want, int(rad_to_deg(angle))])

	print("spawn_shot: written to %s" % ProjectSettings.globalize_path(_out))
	quit(0)


func _shoot(eye: Vector3, look: Vector3, name: String) -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = eye
	cam.look_at(look, Vector3.UP)
	cam.current = true
	cam.far = 900.0
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var file := "%s/%s.png" % [_out, name]
	var err := img.save_png(file)
	if err != OK:
		printerr("spawn_shot: could not write %s (%s)" % [file, error_string(err)])
	else:
		print("  %s" % file.get_file())
	cam.queue_free()
