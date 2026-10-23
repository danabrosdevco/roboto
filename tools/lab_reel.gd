extends SceneTree

# ─────────────────────────────────────────────
# PHOTOGRAPH A LABORATORY FIGHT.
#
#   godot --audio-driver Dummy --path . --script res://tools/lab_reel.gd -- bulwark_screen [speed] [seconds]
#
# NO --headless. It grabs the viewport, so there has to be one.
#
# tools/lab_watch.gd shows you the fight live and then the window is gone.
# This leaves a contact sheet behind, which is the difference between "I saw
# it" and "look at frame 6". Same plan, same arena, same ghost camera — it
# just takes a picture every `interval` seconds and lays them out in order.
#
# RUN IT SLOW. The default plan speed finishes a fight in eight to fourteen
# seconds and a sheet of twelve frames across that is a slideshow of a blur.
# 0.35 is about right for watching an arm track.
# ─────────────────────────────────────────────

const PLAN_DIR := "res://Campaign/lab/plans"
const SHOTS := 12
const COLS := 4
const CELL := Vector2i(360, 230)
const SHEET_BG := Color(0.043, 0.071, 0.063)

var _out: String = "."
## Our own camera, made current over the lab's ghost. See _follow.
var _cam: Camera3D = null
## Where the subject last projected to. The frame is CROPPED around this, not
## downscaled whole: a 1152-wide grab squeezed into a 360-wide cell turned two
## rust-coloured mechs into mud against rust-coloured ground, and I read three
## sheets as "the camera is pointing at scenery" when it was pointing straight
## at them. Crop, then scale.
var _subject_at: Vector2 = Vector2(576, 324)



func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("lab_reel: this grabs the viewport, so drop --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("lab_reel: <out dir> <plan> [speed] [seconds]")
		quit(1)
		return
	_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var name: String = args[1]
	if not name.ends_with(".tres"):
		name += ".tres"
	var plan: Resource = load("%s/%s" % [PLAN_DIR, name])
	if plan == null:
		printerr("lab_reel: no plan %s" % name)
		quit(1)
		return
	if args.size() > 2:
		plan.speed = maxf(float(args[2]), 0.1)
	var window: float = float(args[3]) if args.size() > 3 else 26.0

	var master: Node = load("res://Managers/master.tscn").instantiate()
	master.lab_mode = true
	master.lab_plan = plan
	var cm: Node = master.find_child("CampaignManager", true, false)
	if cm != null and "autosave" in cm:
		cm.autosave = false
	root.add_child(master)

	# WAIT FOR THE LAB NODE, not for _menu.
	#
	# `_menu == "lab"` is the RESULTS SCREEN — Master sets it in
	# _show_lab_results, after every fight is over. Waiting on it, as
	# tools/test_lab.gd correctly does when it wants the numbers, means waiting
	# for the thing to finish and then photographing an empty arena. The Lab
	# node existing is what says the fights have started.
	var waited := 0.0
	while waited < 90.0 and master.get_node_or_null("Lab") == null:
		await process_frame
		waited += 1.0 / 60.0
	if master.get_node_or_null("Lab") == null:
		printerr("lab_reel: the arena never came up (waited %.0fs)." % waited)
		quit(1)
		return
	# ...and then a moment more, so the robots are placed and walking rather
	# than standing in their spawn poses.
	await _hold(1.2)

	# FOLLOW THE BULWARK, rather than take the lab's own shot.
	#
	# Lab._frame_camera parks the ghost at distance * 0.9 to the side and 24 m
	# up, which frames the whole arena — right for watching a line advance and
	# useless for watching an arm. The ghost IS world.player, so it can simply
	# be moved; this puts it nine metres off whichever Bulwark is still alive.
	var lab := master.get_node_or_null("Lab")
	var ghost = lab.world.player if lab != null and "world" in lab else null
	var shots: Array = []
	var interval: float = window / float(SHOTS)
	for i in SHOTS:
		await _hold(interval)
		_follow(ghost)
		await _hold(0.1)
		_follow(ghost)   # again, after the physics step has run once
		shots.append(["%.1fs" % (float(i + 1) * interval), await _grab()])
	_save(await _sheet(shots), "%s/lab_fight.png" % _out)
	print("lab_reel: %s" % ProjectSettings.globalize_path("%s/lab_fight.png" % _out))
	quit(0)


func _hold(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		t += 1.0 / 60.0


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var full := get_root().get_texture().get_image()
	var w: int = full.get_width()
	var h: int = full.get_height()
	# A window about a third of the frame, centred on the subject and clamped
	# inside the image.
	var cw: int = int(w / 2.6)
	var ch: int = int(float(cw) * float(CELL.y - 22) / float(CELL.x))
	var x: int = clampi(int(_subject_at.x) - cw / 2, 0, maxi(w - cw, 0))
	var y: int = clampi(int(_subject_at.y) - ch / 2, 0, maxi(h - ch, 0))
	var crop := Image.create(cw, ch, false, full.get_format())
	crop.blit_rect(full, Rect2i(x, y, cw, ch), Vector2i.ZERO)
	crop.resize(CELL.x, CELL.y - 22, Image.INTERPOLATE_BILINEAR)
	if crop.get_format() != Image.FORMAT_RGBA8:
		crop.convert(Image.FORMAT_RGBA8)
	return crop


func _label(text: String) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL.x, 22)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
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
				Vector2i(col * CELL.x, row * CELL.y + CELL.y - 20))
	return sheet


func _save(img: Image, path: String) -> void:
	var err := img.save_png(path)
	if err != OK:
		printerr("lab_reel: could not write %s (%s)" % [path, error_string(err)])


## Put a camera on the nearest living Bulwark, off its right shoulder so the
## shield, the gun arm and whatever it is shooting at are all in frame.
##
## ITS OWN CAMERA, NOT THE LAB'S GHOST. The ghost is world.player, and three
## attempts to drive it ended up looking at the far wall: it is a character
## controller with a spectator branch, a look_direction that lerps and a camera
## child with its own transform, and all three get a say every physics frame.
## A plain Camera3D made current answers to nobody.
func _follow(ghost) -> void:
	if ghost == null or not is_instance_valid(ghost):
		return
	var subject: Node3D = null
	for n in ghost.get_tree().get_nodes_in_group("enemies"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if "alive" in n and not n.alive:
			continue
		# BY TYPE, NOT BY NAME. soldier_name is "Bulwark" in the scene but the
		# spawner replaces it with a callsign, so matching the string found
		# nothing at all and the reel quietly kept the arena shot.
		if n is Bulwark:
			subject = n
			break
	if subject == null:
		return
	var at: Vector3 = subject.global_position
	# BEHIND AND ABOVE, over its left shoulder.
	#
	# The first version sat 5 m in FRONT of the subject, looking back at it —
	# geometrically perfect and visually useless: the projection put the mech
	# dead centre of frame every time, and every frame came back as a wall,
	# because in this arena five metres toward the enemy is inside a cover
	# block. The camera was never mis-aimed; it was buried. Over the shoulder
	# there is nothing between the lens and the subject, and it also shows what
	# the frame is shooting AT.
	var fwd: Vector3 = -subject.global_transform.basis.z
	var side: Vector3 = subject.global_transform.basis.x
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		subject.get_tree().get_root().add_child(_cam)
	# SIX METRES BACK AND FOUR UP, over its left shoulder.
	#
	# Tuned by looking, eight times. Two things that cost most of that:
	# anything IN FRONT of the subject is inside a cover block in this arena,
	# so the frame comes back as a wall; and pulling back past about eight
	# metres puts the lens through the arena boundary and the frame comes back
	# as the outside of it. This sits between the two.
	_cam.global_position = at + fwd * -6.0 + side * -2.6 + Vector3.UP * 4.2
	_cam.look_at(at + fwd * 3.0 + Vector3.UP * 1.0, Vector3.UP)
	_cam.current = true
	# Remember where the subject lands, so the crop can be centred on it.
	_subject_at = _cam.unproject_position(at + Vector3.UP * 1.6)
