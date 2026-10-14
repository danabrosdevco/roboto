extends SceneTree

# ─────────────────────────────────────────────
# THE BULWARK IN MOTION — contact sheets of the walk cycle and the split aim.
#
#   godot --audio-driver Dummy --path . --script res://tools/bulwark_reel.gd -- <out dir>
#
# IT NEEDS A WINDOW. This grabs the viewport, so run it WITHOUT --headless.
#
# WHY A FILMSTRIP AND NOT A VIDEO. Godot writes no GIF and this machine has no
# encoder, so a sheet of evenly spaced frames is what a still medium can carry.
# It is also easier to judge: a walk cycle is wrong in ways you catch by
# comparing frame 2 against frame 6, which a video shows you once at speed and
# a strip shows you side by side.
#
# TWO REELS, because this frame has two things worth watching:
#
#   walk   driven by MOVING THE BODY, because Walker's gait keys off distance
#          travelled, not off a timer. A reel made by advancing _gait directly
#          would animate a mech that is standing still, and would not catch a
#          stride that is out of step with the ground.
#
#   aim    a target swung from straight ahead round past the arm's cone, with
#          the BODY HELD. Held because the arm is independent of the torso and
#          not of the body — see the note in bulwark.gd. Free, the frame just
#          turns to face the target and there is nothing to see.
# ─────────────────────────────────────────────

const BULWARK := "res://Character/characters/ai/bulwark.tscn"
const GUN := "res://Character/weapon/ai-wep_heavy_mg.tscn"

const FRAMES := 8
const CELL := Vector2i(300, 330)
const COLS := 4
const SHEET_BG := Color(0.043, 0.071, 0.063)

var _out: String = "."
var _world: Node3D
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("bulwark_reel: this grabs the viewport, so it needs a window.")
		quit(1)
		return
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_stage()
	await _walk_reel()
	await _aim_reel()
	print("bulwark_reel: written to %s" % ProjectSettings.globalize_path(_out))
	quit(0)


func _stage() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = SHEET_BG
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.66)
	e.ambient_light_energy = 1.5
	env.environment = e
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-36), deg_to_rad(40), 0)
	sun.light_energy = 2.1
	_world.add_child(sun)
	_cam = Camera3D.new()
	_world.add_child(_cam)
	_cam.current = true


func _make() -> Node:
	var b: Node = load(BULWARK).instantiate()
	_world.add_child(b)
	b.set_physics_process(false)
	b.set_process(false)
	var mount = b.get("weapon_mount")
	if mount != null:
		mount.add_child(load(GUN).instantiate())
	return b


## THE WALK, seen from the side, which is the only view a stride reads from.
func _walk_reel() -> void:
	var b := _make()
	for _i in 20:
		await process_frame
	# Warm the gait up to full amplitude first, so frame 1 is mid-stride
	# rather than the frame it started settling on.
	for _i in 90:
		(b as Node3D).global_position += Vector3(0, 0, -0.06)
		b._tick_gait(1.0 / 60.0)
	var shots: Array = []
	# One full cycle. Walker advances _gait by travelled/stride_length * TAU,
	# so a whole cycle is stride_length of ground — split evenly into FRAMES.
	var step: float = float(b.stride_length) / float(FRAMES) / 6.0
	for f in FRAMES:
		for _i in 6:
			(b as Node3D).global_position += Vector3(0, 0, -step)
			b._tick_gait(1.0 / 60.0)
		var at: Vector3 = (b as Node3D).global_position
		_cam.global_position = at + Vector3(6.2, 1.5, 0.2)
		_cam.look_at(at + Vector3(0, 0.9, 0), Vector3.UP)
		shots.append(["%d" % (f + 1), await _grab()])
	_save(await _sheet(shots), "%s/bulwark_walk.png" % _out)
	b.free()
	await process_frame


## THE SPLIT AIM, seen from above and in front so both the arm's bearing and
## the shield's are legible in one frame.
func _aim_reel() -> void:
	var b := _make()
	for _i in 20:
		await process_frame
	b.ai_state = b.AIState.COMBAT
	var held: float = (b as Node3D).rotation.y
	var shots: Array = []
	var cone: float = float(b.arm_yaw_cone_degrees)
	# From dead ahead out to half again the cone, so the sheet shows the arm
	# taking it alone, reaching its limit, and the torso starting to help.
	for f in FRAMES:
		var deg: float = lerpf(0.0, cone * 1.6, float(f) / float(FRAMES - 1))
		var a := deg_to_rad(deg)
		b.weapon_target = Vector3(sin(a) * 26.0, 0.6, -cos(a) * 26.0)
		# Long enough to settle at each bearing, so the sheet shows where it
		# ENDS UP rather than where it happened to be passing.
		for _i in 70:
			b._update_facing(1.0 / 60.0)
			(b as Node3D).rotation.y = held
			b._pose_arms(1.0 / 60.0)
		_cam.global_position = Vector3(1.4, 5.6, -4.4)
		_cam.look_at(Vector3(0, 1.0, -0.2), Vector3.UP)
		var arm_deg: float = rad_to_deg(b.arm_yaw.rotation.y)
		var torso_deg: float = rad_to_deg(b.turret.rotation.y)
		shots.append(["target %d  arm %d  torso %d" % [int(deg), int(-arm_deg), int(-torso_deg)],
				await _grab()])
	_save(await _sheet(shots), "%s/bulwark_aim.png" % _out)
	b.free()
	await process_frame


func _grab() -> Image:
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var full := get_root().get_texture().get_image()
	# Centre crop: the window is wide and the mech is a tall thing in the
	# middle of it, so most of a full grab is empty ground.
	var w: int = full.get_width()
	var h: int = full.get_height()
	var cw: int = mini(w, int(h * 0.82))
	var crop := Image.create(cw, h, false, full.get_format())
	crop.blit_rect(full, Rect2i((w - cw) / 2, 0, cw, h), Vector2i.ZERO)
	crop.resize(CELL.x, CELL.y - 26, Image.INTERPOLATE_BILINEAR)
	if crop.get_format() != Image.FORMAT_RGBA8:
		crop.convert(Image.FORMAT_RGBA8)
	return crop


func _label(text: String) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL.x, 26)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.62, 0.95, 0.66))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(l)
	root.add_child(vp)
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _sheet(shots: Array) -> Image:
	var rows := int(ceil(shots.size() / float(COLS)))
	var sheet := Image.create(CELL.x * COLS, CELL.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(SHEET_BG)
	for i in shots.size():
		var col: int = i % COLS
		var row: int = i / COLS
		var img: Image = shots[i][1]
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
				Vector2i(col * CELL.x, row * CELL.y))
		var lab: Image = await _label(str(shots[i][0]))
		sheet.blend_rect(lab, Rect2i(Vector2i.ZERO, lab.get_size()),
				Vector2i(col * CELL.x, row * CELL.y + CELL.y - 24))
	return sheet


func _save(img: Image, path: String) -> void:
	var err := img.save_png(path)
	if err != OK:
		printerr("bulwark_reel: could not write %s (%s)" % [path, error_string(err)])
	else:
		print("  %s" % path.get_file())
