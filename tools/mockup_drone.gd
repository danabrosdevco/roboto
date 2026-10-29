extends SceneTree

# ─────────────────────────────────────────────
# DRONE SOLDIER MOCK-UP — photographs the proposed anatomical body beside the
# shipped one, bare and with kit on it.
#
# Nothing here touches soldier_chassis.tscn. The new body is built in code
# (mockup_parts.drone_body) and only ever exists inside this render.
#
#   godot --audio-driver Dummy --path . --script res://tools/mockup_drone.gd -- <out dir>
# ─────────────────────────────────────────────

const _Parts := preload("res://tools/mockup_parts.gd")
const SOLDIER := "res://Character/characters/ai/soldier_chassis.tscn"
const RIFLE := "res://Character/weapon/ai-wep_m4.tscn"
## THE LIVE BASE. This used to be depot_level, which was retired on 2026-10-24
## (vault Backlog H15) — the railhead is the base world.tscn actually loads.
## The light came across unchanged: both levels instance the same
## Env/world_environment.tscn, so there is one sun and this is still under it.
## The FLOOR did not, which is why the stage height is probed below.
const LEVEL := "res://maps/railhead_level.tscn"

## Where the bodies stand, in x and z only. THE HEIGHT IS DERIVED — see
## _deck(). It was a typed 1.2, which was the depot's inner floor plus the
## metre from a 2 m capsule's centre to its feet. The railhead's floor at the
## same x/z is 1.19, so keeping the number would have sunk both robots to the
## waist and the shot would still have looked like a shot.
const STAGE_XZ := Vector3(0.0, 0.0, 0.0)

## Centre of a 2 m capsule above the floor it stands on.
const FEET := 1.01

var _cam: Camera3D
var _stage := STAGE_XZ


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("mockup_drone: this photographs the game, so it needs a window.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 and args[0].strip_edges() != "" else "user://mockups"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_cam.current = true
	for _i in 30:
		await process_frame
	_stage = STAGE_XZ + Vector3(0, _deck(STAGE_XZ) + FEET, 0)

	# Old and new, side by side, so the difference is the subject of the shot.
	var old := _old_soldier(_stage + Vector3(-0.95, 0, 0))
	var new_bare := _drone(_stage + Vector3(0.95, 0, 0), func(_b): pass)
	await _frame(_stage, 4.8, 1.1)
	_face(old, 38.0)
	_face(new_bare, 38.0)
	await _shoot(out_dir + "/drone_vs_capsule.png")
	old.free()
	new_bare.free()

	# The new body on its own, and wearing each of the fittings that matter.
	var want := {"bare": func(_b): pass}
	for entry in _Parts.drone_kit_list():
		if true:
			want[_slug(str(entry[0]))] = entry[1]
	for entry in _Parts.drone_hat_list():
		if str(entry[0]) != "BARE":
			want["hat_" + _slug(str(entry[0]))] = entry[1]
	for key in want:
		var bot := _drone(_stage, want[key])
		await _frame(_stage, 4.2, 0.85)
		_face(bot, 38.0)
		await _shoot("%s/drone_%s.png" % [out_dir, key])
		bot.free()
	print("mockup_drone: written to %s" % out_dir)
	quit(0)


func _slug(s: String) -> String:
	return s.to_lower().replace(" ", "_")


## THE DECK THE BODIES STAND ON, measured, not assumed — and the ray is
## dropped from ABOVE the building on purpose, so it lands on the railhead's
## open upper deck at y=11.00 rather than the platform floor at 1.19 inside it.
##
## Both were rendered and looked at on 2026-10-24. This shot is a SILHOUETTE
## comparison — the proposed body beside the shipped capsule — and the platform
## floor puts carriage sides and track behind both of them, which is the one
## backdrop that cannot answer it. The roof is open sky under the same sun, and
## it is where mockup_shots.gd photographs the shipped body, so the two sets
## are comparable.
func _deck(at: Vector3) -> float:
	var space := root.world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 60, 0), at + Vector3(0, -40, 0))
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		push_warning("mockup_drone: no floor under %s in %s, so the bodies are parked at y=0 and may float."
				% [str(at), LEVEL.get_file()])
		return 0.0
	return (hit["position"] as Vector3).y


# Camera three-quarters on to the robot's right, which is the side kit goes on.
func _frame(at: Vector3, back: float, up: float) -> void:
	_cam.global_position = at + Vector3(-back * 0.52, up, -back * 0.85)
	_cam.look_at(at + Vector3(0, -0.05, 0), Vector3.UP)
	await process_frame


func _drone(at: Vector3, build: Callable) -> Node3D:
	var bot := _Parts.drone_body()
	var mount := _Parts.drone_mount(bot)
	mount.add_child(load(RIFLE).instantiate())
	root.add_child(bot)
	bot.global_position = at
	bot.rotation.y = deg_to_rad(212.0)
	build.call(bot)
	# Kit in its OWN colour, not the hull's. Painting fitted hardware the same
	# blue as the body is what made the armour disappear last time.
	var kit := _Parts.kit_material()
	for child in bot.get_children():
		if child is CSGShape3D and (child as CSGShape3D).material == null:
			(child as CSGShape3D).material = kit
	return bot


func _old_soldier(at: Vector3) -> Node3D:
	var bot: Node3D = load(SOLDIER).instantiate()
	bot.faction = Enums.Factions.PLAYER
	var mount = bot.get("weapon_mount")
	if mount != null and mount is Node3D:
		(mount as Node3D).add_child(load(RIFLE).instantiate())
	root.add_child(bot)
	bot.set_physics_process(false)
	bot.set_process(false)
	bot.global_position = at
	bot.rotation.y = deg_to_rad(212.0)
	return bot


func _shoot(file: String) -> void:
	# CSG rebuilds its mesh the frame after it enters the tree.
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var err := get_root().get_texture().get_image().save_png(file)
	if err != OK:
		printerr("mockup_drone: could not write %s (%s)" % [file, error_string(err)])


# Turn a robot to face the camera on the flat, then yaw a little further so the
# side kit hangs on comes toward us. Aiming with look_at straight at a camera
# that is above it would pitch the robot forward onto its face.
func _face(bot: Node3D, extra_yaw: float) -> void:
	var flat := Vector3(_cam.global_position.x, bot.global_position.y, _cam.global_position.z)
	bot.look_at(flat, Vector3.UP)
	bot.rotate_y(deg_to_rad(extra_yaw))
