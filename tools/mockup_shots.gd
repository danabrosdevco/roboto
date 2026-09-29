extends SceneTree

# ─────────────────────────────────────────────
# KIT SCREENSHOTS — the same fittings as mockup_kit.gd, but photographed IN THE
# GAME rather than drawn as line art.
#
# Why both exist: the icon sheet answers "does this read as a silhouette at
# 40 pixels", which is a UI question. This answers "does it look like part of
# the machine when it is lit, painted in faction blue and standing in a level",
# which is the question you actually care about. A shape can pass one and fail
# the other — a flat slab reads fine in outline and looks like cardboard the
# moment a light hits it.
#
# Loads a real level for its environment and lighting, lines the soldiers up,
# parks a camera in front of them and writes the viewport out.
#
#   godot --audio-driver Dummy --path . --script res://tools/mockup_shots.gd -- <out dir>
# ─────────────────────────────────────────────

const _Parts := preload("res://tools/mockup_parts.gd")
const SOLDIER := "res://Character/characters/ai/soldier_chassis.tscn"
const RIFLE := "res://Character/weapon/ai-wep_m4.tscn"
const LEVEL := "res://maps/depot_level.tscn"
## Where the soldiers stand, in a level the camera can see all of.
const STAGE := Vector3(0.0, 1.2, 0.0)
const SPACING := 2.0

var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("mockup_shots: this photographs the game, so it needs a window.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 and args[0].strip_edges() != "" else "user://mockups"
	DirAccess.make_dir_recursive_absolute(out_dir)

	# A real level, for its WorldEnvironment and its sun. Without one the robots
	# are lit by nothing and every screenshot is a black rectangle.
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	root.add_child(_cam)
	_cam.current = true
	for _i in 30:
		await process_frame

	# One wide line-up of every fitting, then a portrait of each.
	var kit: Array = _Parts.capsule_kit_list()
	await _group(kit, out_dir + "/ingame_kit_lineup.png")
	for entry in kit:
		await _portrait(entry[1], "%s/ingame_%s.png" % [out_dir, _slug(entry[0])])
	# The promotion, on its own: a blue soldier with an Ancient Rifle and a cap.
	for entry in _Parts.hat_list():
		if str(entry[0]) == "PEAKED CAP":
			await _portrait(entry[1], out_dir + "/ingame_nco_peaked_cap.png")
	print("mockup_shots: written to %s" % out_dir)
	quit(0)


func _slug(s: String) -> String:
	return s.to_lower().replace(" ", "_")


# A row of soldiers, one per fitting, seen together so they can be compared.
func _group(entries: Array, file: String) -> void:
	var made: Array[Node3D] = []
	var span := float(entries.size() - 1) * SPACING
	for i in entries.size():
		var at := STAGE + Vector3(-span * 0.5 + float(i) * SPACING, 0, 0)
		made.append(_soldier((entries[i] as Array)[1], at))
	_cam.global_position = STAGE + Vector3(0, 1.4, -span * 0.62 - 6.0)
	_cam.look_at(STAGE + Vector3(0, 0.1, 0), Vector3.UP)
	await _shoot(file)
	for n in made:
		n.free()


# One soldier, close, turned three-quarter on so the fitted side is toward the
# camera — the same angle the icons use, for the same reason.
func _portrait(build: Callable, file: String) -> void:
	var bot := _soldier(build, STAGE)
	_cam.global_position = STAGE + Vector3(-2.30, 1.05, -3.80)
	_cam.look_at(STAGE + Vector3(0, 0.05, 0), Vector3.UP)
	# TURNED BY MEASUREMENT, NOT BY GUESSWORK — but on the FLAT only. look_at to
	# a camera that is above the robot pitches the robot forward to meet it, and
	# the photograph comes back of a soldier falling over. Aim at the camera's
	# ground position and the yaw is all that changes.
	var flat := Vector3(_cam.global_position.x, bot.global_position.y, _cam.global_position.z)
	bot.look_at(flat, Vector3.UP)
	# The extra yaw swings its right side into view, which is the side
	# everything is fitted to.
	bot.rotate_y(deg_to_rad(42.0))
	await _shoot(file)
	bot.free()


func _soldier(build: Callable, at: Vector3) -> Node3D:
	var bot: Node3D = load(SOLDIER).instantiate()
	# Blue. FactionLivery reads this off its parent in _ready, so it has to be
	# set BEFORE the node enters the tree or the robot comes out enemy amber.
	bot.faction = Enums.Factions.PLAYER
	var mount = bot.get("weapon_mount")
	if mount != null and mount is Node3D:
		(mount as Node3D).add_child(load(RIFLE).instantiate())
	# IN THE TREE FIRST, THEN BOLT THINGS ON, THEN PAINT. The livery runs in
	# _ready and only ever walks the pieces the scene lists, so anything added
	# afterwards keeps Godot's default white — the first pass came back with
	# lavender shoulder plates on a blue robot.
	root.add_child(bot)
	# ONLY WHAT WE ADDED gets repainted: the robot's own hull and its eye are
	# already its children, and painting those rust turned its one facial
	# feature into a scab.
	var before := bot.get_child_count()
	build.call(bot)
	_paint(bot, before)
	# Standing still and not thinking: this is a photograph, not a fight, and a
	# soldier left to its own devices walks out of shot looking for a target.
	bot.set_physics_process(false)
	bot.set_process(false)
	bot.global_position = at
	bot.rotation.y = deg_to_rad(200.0)
	return bot



# Hand every bolted-on piece its OWN material. Kit is bought hardware, not part
# of the hull, and painting it faction blue is what made the armour vanish into
# the body. It is also RUSTED rather than flat matte: the hull it bolts to is
# a rusted texture was tried and read as varnished wood at this scale, and as
# tweed once the noise was fine enough not to.
func _paint(bot: Node3D, from: int) -> void:
	var armor := _Parts.armor_material()
	for i in range(from, bot.get_child_count()):
		var child := bot.get_child(i)
		if child is CSGCombiner3D:
			(child as CSGCombiner3D).material_override = armor
		elif child is CSGShape3D:
			(child as CSGShape3D).material = armor


func _shoot(file: String) -> void:
	# CSG rebuilds its mesh the frame after it enters the tree, so an immediate
	# grab catches half-built armour.
	for _i in 24:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var err := img.save_png(file)
	if err != OK:
		printerr("mockup_shots: could not write %s (%s)" % [file, error_string(err)])
