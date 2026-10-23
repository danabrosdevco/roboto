extends SceneTree

# ─────────────────────────────────────────────
# CANDIDATE RELOAD POSES, FROM THE PLAYER'S EYE, SIDE BY SIDE.
#
#   godot --audio-driver Dummy --path . \
#       --script res://tools/probe_reload_pose.gd -- \
#       <out dir> <weapon.tscn> <beats, comma separated> <x,y,z|rx,ry,rz>...
#
# IT NEEDS A WINDOW. It is a camera; run it WITHOUT --headless.
#
# WHY THIS EXISTS. A weapon's working pose is a const in its script, so trying
# one means an edit, a reload and a render — and the Squad Automatic's own
# header records three such passes, each one correcting the last into a new way
# of being wrong. This overrides the pose from OUTSIDE instead, so a dozen can
# be looked at in one run and the one that works gets written down once.
#
# It drives the real _reload_frame for each beat — so the parts are posed by the
# authored animation, not by hand — and then THROWS AWAY the body pose that
# comes back and substitutes the candidate. The parts are therefore exactly
# where the game would put them, and only the gun's own place in the hand is
# the variable.
#
# The beats are what you want to be able to SEE. For a belt gun: 0.30 is the box
# falling, 0.65 is the new box coming up, 0.79 is the belt laid into the tray.
# A pose that frames one and loses the others is not an answer.
#
# AND IT MEASURES. The render says whether it looks right; the printed box says
# whether the moving part is actually on screen, in viewport fractions, which a
# still at the edge of frame cannot be trusted to show.
# ─────────────────────────────────────────────

const SHOT := Vector2i(900, 506)
## The part the pose has to keep in frame, per weapon. Named rather than guessed
## because "the thing that moves" is not something a tool can work out.
const WATCH := {
	# Stock and ButtPlate are watched to be pushed OUT, not kept in. "Too much
	# stock" is the commonest note on a viewmodel and the hardest to act on by
	# eye, because the butt is the nearest thing to the camera and therefore the
	# largest whatever the pose; a number says how far past the edge it has gone.
	"squad_auto_hud_weapon.tscn": ["AmmoBox", "FeedCover", "Stock", "ButtPlate"],
}


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("probe_reload_pose: this is a camera. Run it without --headless.")
		quit(1)
		return
	Settings.path = "user://settings_probe.json"
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		printerr("probe_reload_pose: need an out dir, a weapon scene, the beats and at least one pose")
		quit(1)
		return
	var out: String = args[0]
	var path: String = args[1]
	var beats: Array = []
	for b in args[2].split(","):
		beats.append(float(b))
	var poses: Array = args.slice(3)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))

	for pi in poses.size():
		var pose: Array = _parse(poses[pi])
		if pose.is_empty():
			printerr("probe_reload_pose: cannot read pose '%s' — want x,y,z|rx,ry,rz" % poses[pi])
			continue
		print("pose %d  pos %s  rot %s" % [pi, pose[0], pose[1]])
		for bi in beats.size():
			await _shot(path, pose, beats[bi], "%s/p%02d_b%02d.png" % [out, pi, bi])
	print("done")
	quit(0)


func _parse(text: String) -> Array:
	var halves := text.split("|")
	if halves.size() != 2:
		return []
	var p := halves[0].split(",")
	var r := halves[1].split(",")
	if p.size() != 3 or r.size() != 3:
		return []
	return [Vector3(float(p[0]), float(p[1]), float(p[2])),
		Vector3(float(r[0]), float(r[1]), float(r[2]))]


func _shot(path: String, pose: Array, beat: float, out_file: String) -> void:
	var vp := SubViewport.new()
	vp.size = SHOT * 2
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The game's own environment — a flat one has no radiance map and every
	# metal reads near black. See the long note in preview_viewmodel.gd.
	var env: Environment = load("res://Env/world_environment.tres")
	var we := WorldEnvironment.new()
	we.environment = env if env != null else Environment.new()
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -38, 0)
	key.light_energy = 1.4
	vp.add_child(key)
	root.add_child(vp)

	var player: Node3D = load("res://Character/characters/player/test_character.tscn").instantiate()
	vp.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	await process_frame
	var cam: Camera3D = player.get_node_or_null("Camera3D")
	if cam == null:
		vp.queue_free()
		return
	cam.current = true
	var gun: Node3D = (load(path) as PackedScene).instantiate()
	cam.add_child(gun)
	# THE ITEM MOVES THE GUN. EquipmentLoadout rewrites the weapon's transform
	# from the catalogue after add_child, so a preview that skips this renders a
	# gun the game never shows.
	var mount := _mount_for(path)
	gun.position = mount[0]
	gun.rotation_degrees = mount[1]
	await process_frame
	var hip_fov = gun.get("HIP_FOV")
	cam.fov = float(hip_fov) if hip_fov != null else 70.0
	var model := _viewmodel(gun)
	if model == null:
		printerr("probe_reload_pose: %s names no viewmodel." % path.get_file())
		vp.queue_free()
		return
	if gun.get("magazine_size") != null and int(gun.get("loaded")) == 0:
		gun.set("loaded", int(gun.get("magazine_size")))
	# The authored rest pose, copied in exactly as PlayerEquipment does during
	# init — anything built on top of base_position is wrong without it.
	if gun.get("use_default_position") == false:
		gun.base_position = model.position
		gun.base_rotation = model.rotation_degrees
	# THE PARTS FROM THE REAL ANIMATION, THE BODY FROM THE CANDIDATE.
	if gun.has_method("_reload_frame"):
		gun._reload_frame(beat)
	model.position = pose[0]
	model.rotation_degrees = pose[1]
	for _i in 6:
		await process_frame
	_measure(cam, model, path.get_file(), beat)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.resize(SHOT.x, SHOT.y, Image.INTERPOLATE_LANCZOS)
	img.save_png(out_file)
	vp.queue_free()


## WHERE THE MOVING PART IS, IN SCREEN FRACTIONS. 0..1 is on screen; anything
## outside is the reason the player never sees it. unproject_position gives
## pixels, so this divides by the viewport to stay resolution-free.
func _measure(cam: Camera3D, model: Node3D, scene_file: String, beat: float) -> void:
	var watch: Array = WATCH.get(scene_file, [])
	if watch.is_empty():
		return
	var size := Vector2(cam.get_viewport().size)
	var line := "    t=%.2f " % beat
	for want in watch:
		var n := model.find_child(want, true, false) as Node3D
		if n == null:
			line += " %s=<missing>" % want
			continue
		# BEHIND THE CAMERA IS NOT OFF TO ONE SIDE. unproject_position mirrors a
		# point behind the eye back into frame, so it reports a part that is
		# literally at your shoulder as centre screen.
		var local: Vector3 = cam.to_local(n.global_position)
		if local.z > 0.0:
			line += "  %s=BEHIND" % want
			continue
		var p: Vector2 = cam.unproject_position(n.global_position) / size
		# DEPTH TOO. A part can be dead centre of frame and invisible because the
		# receiver is in front of it — which is exactly how the first pass of this
		# sweep produced numbers that all looked good and renders that showed a
		# wall of green. Screen position says where it would be drawn; distance
		# says whether the gun is close enough to be the thing drawn over it.
		line += "  %s=(%+.2f,%+.2f)@%.2fm%s" % [want, p.x, p.y, -local.z,
			"" if (p.x >= 0.0 and p.x <= 1.0 and p.y >= 0.0 and p.y <= 1.0) else " OFF"]
	print(line)


func _viewmodel(gun: Node) -> Node3D:
	var vm = gun.get("viewmodel")
	if vm is Node3D:
		return vm
	var wm = gun.get("weapon_model")
	return wm if wm is Node3D else null


func _mount_for(scene_path: String) -> Array:
	var catalogue: ItemCatalogue = load("res://Campaign/items & catalogue/test_item_catalogue.tres")
	if catalogue == null:
		return [Vector3.ZERO, Vector3.ZERO]
	for item in catalogue.items:
		if item == null or item.player_scene == null:
			continue
		if item.player_scene.resource_path == scene_path:
			return [item.player_mount_offset, item.player_mount_rotation_degrees]
	printerr("probe_reload_pose: no catalogue item uses %s, so no mount offset is applied." % scene_path.get_file())
	return [Vector3.ZERO, Vector3.ZERO]
