extends SceneTree

# ─────────────────────────────────────────────
# THE FIRST-PERSON VIEW, rendered from the player's own camera, in both poses.
#
# A viewmodel can only be judged from where the player sits. This builds the
# player, hangs a weapon off the camera the way the loadout does, poses it at
# base_position and then ads_position, and renders each — at the FOV the game
# actually uses for that pose, at the project's viewport aspect.
#
# A crosshair is drawn at dead centre, because "do the sights line up" means
# "do they sit on that cross".
#
#   godot --audio-driver Dummy --path . --script res://tools/preview_viewmodel.gd -- <outdir> <weapon.tscn> ...
# ─────────────────────────────────────────────

const SHOT := Vector2i(900, 506)   # the project's 16:9 viewport, halved
const BG := Color(0.09, 0.12, 0.13)
const INK := Color(0.55, 1.0, 0.6, 0.85)


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("preview_viewmodel: need an out dir and a weapon scene")
		quit(1)
		return
	var out_dir: String = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var shots: Array = []
	for path in args.slice(1):
		if not ResourceLoader.exists(path):
			printerr("preview_viewmodel: no such scene %s" % path)
			continue
		for aiming in [false, true]:
			var img := await _shot(path, aiming)
			if img != null:
				img.save_png("%s/%s_%s.png" % [
					out_dir, path.get_file().get_basename(), "ads" if aiming else "hip"])
				shots.append(img)
				print("  %s %s" % [path.get_file(), "ADS" if aiming else "hip"])
	if shots.is_empty():
		quit(1)
		return
	var sheet := Image.create(SHOT.x, SHOT.y * shots.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(BG)
	for i in shots.size():
		sheet.blend_rect(shots[i], Rect2i(Vector2i.ZERO, SHOT), Vector2i(0, SHOT.y * i))
	sheet.save_png("%s/_view.png" % out_dir)
	print("preview_viewmodel: %s/_view.png" % out_dir)
	quit(0)


func _shot(path: String, aiming: bool) -> Image:
	var vp := SubViewport.new()
	vp.size = SHOT * 2
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.64)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
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
		return null
	cam.current = true
	var gun: Node3D = (load(path) as PackedScene).instantiate()
	cam.add_child(gun)
	await process_frame
	cam.fov = float(gun.ADS_FOV if aiming else gun.HIP_FOV)
	var model := _viewmodel(gun)
	if model == null:
		printerr("preview_viewmodel: %s names no `viewmodel`, so there is no pose to render." % path.get_file())
		vp.queue_free()
		return null
	model.position = gun.ads_position if aiming else gun.base_position
	# RADIANS, because player_equipment.gd lerps viewmodel.ROTATION, not
	# rotation_degrees — posing this in degrees showed a pose the game never uses.
	model.rotation = gun.ads_rotation if aiming else gun.base_rotation
	for _i in 6:
		await process_frame
	var img := vp.get_texture().get_image()
	img.resize(SHOT.x, SHOT.y, Image.INTERPOLATE_LANCZOS)
	_crosshair(img)
	vp.queue_free()
	return img


# ONLY WEAPONS THAT NAME THEIR VIEWMODEL. Without one there is nothing this
# can pose, and guessing at a node produced a render of the whole gun scene at
# the wrong scale that looked like a broken weapon rather than a skipped one.
func _viewmodel(gun: Node) -> Node3D:
	var vm = gun.get("viewmodel")
	return vm if vm is Node3D else null


## Dead centre, where the crosshair is. The sights have to sit on this.
func _crosshair(img: Image) -> void:
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	for d in range(-14, 15):
		if absi(d) > 3:
			img.set_pixel(cx + d, cy, INK)
			img.set_pixel(cx, cy + d, INK)
