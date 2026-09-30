extends SceneTree

# ─────────────────────────────────────────────
# WEAPON SCALE — how big should a soldier's gun be?
#
# Every AI weapon in the game is drawn at 0.25, baked into the WeaponMount's
# transform in soldier_chassis.tscn (and the same number again on the frames
# that carry their gun in the scene). The complaint is that they are tiny and
# hard to see. This lines the same soldier up at several scales and measures
# the gun against the body, so the choice is made by looking rather than by
# picking a number.
#
#   godot --audio-driver Dummy --path . --script res://tools/mockup_gun.gd -- <out dir>
# ─────────────────────────────────────────────

const SOLDIER := "res://Character/characters/ai/soldier_chassis.tscn"
const RIFLE := "res://Character/weapon/ai-wep_m4.tscn"
const LEVEL := "res://maps/depot_level.tscn"
const STAGE := Vector3(0.0, 1.2, 0.0)
const SPACING := 2.2
const SCALES := [0.25, 0.32, 0.40, 0.48]

var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("mockup_gun: this photographs the game, so it needs a window.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 and args[0].strip_edges() != "" else "user://mockups"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	root.add_child(_cam)
	_cam.current = true
	for _i in 30:
		await process_frame

	# ONE SHOT PER SCALE, FROM AN IDENTICAL CAMERA. Lined up in a row they are
	# at different distances and different angles to the lens, and perspective
	# swamps the thing being compared — the smallest gun looked the largest.
	for s in SCALES:
		var bot := _soldier(float(s), STAGE)
		await process_frame
		await process_frame
		var gun := _gun_length(bot)
		print("mockup_gun: scale %.2f -> gun %.2f m long, %.0f%% of the body's height" % [
			s, gun, gun / 2.0 * 100.0])
		_cam.global_position = STAGE + Vector3(-2.10, 0.85, -3.40)
		_cam.look_at(STAGE + Vector3(0, -0.10, 0), Vector3.UP)
		var flat := Vector3(_cam.global_position.x, bot.global_position.y, _cam.global_position.z)
		bot.look_at(flat, Vector3.UP)
		bot.rotate_y(deg_to_rad(40.0))
		await _shoot("%s/gun_%03d.png" % [out_dir, int(float(s) * 100.0)])
		bot.free()
	print("mockup_gun: written to %s" % out_dir)
	quit(0)


func _soldier(mount_scale: float, at: Vector3) -> Node3D:
	var bot: Node3D = load(SOLDIER).instantiate()
	bot.faction = Enums.Factions.PLAYER
	root.add_child(bot)
	var mount = bot.get("weapon_mount")
	if mount != null and mount is Node3D:
		# The .tscn bakes the scale into the mount's basis alongside a 90° turn,
		# so this rescales without disturbing the rotation.
		(mount as Node3D).scale = Vector3.ONE * mount_scale
		(mount as Node3D).add_child(load(RIFLE).instantiate())
	bot.set_physics_process(false)
	bot.set_process(false)
	bot.global_position = at


	return bot


# The longest side of everything drawn under the weapon mount.
func _gun_length(bot: Node3D) -> float:
	var mount = bot.get("weapon_mount")
	if mount == null:
		return 0.0
	var box := AABB()
	var first := true
	for m in _meshes(mount as Node):
		var b: AABB = (m as VisualInstance3D).global_transform * (m as VisualInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return maxf(box.size.x, maxf(box.size.y, box.size.z))


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D or n is CSGShape3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _shoot(file: String) -> void:
	for _i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var err := get_root().get_texture().get_image().save_png(file)
	if err != OK:
		printerr("mockup_gun: could not write %s (%s)" % [file, error_string(err)])
