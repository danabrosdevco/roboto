extends SceneTree
# Concept sheet for Design Drop 1. One camera scale across the row so the
# weapons are comparable; the 1m bar is the reference.
const DIR := "res://Character/weapon/concepts"
const OUT := "user://concepts"
const CELL := Vector2i(560, 480)
const FRAME := 1.3
const BG := Color(0.07, 0.09, 0.09)
var OPTS := []

func _init() -> void:
	Settings.path = "user://settings_probe.json"
	var arg := OS.get_cmdline_user_args()
	var which: String = arg[0] if arg.size() > 0 else "guns"
	if which == "guns":
		OPTS = [["sa_boxfed", "SQUAD AUTOMATIC"], ["cluster_mgl", "CLUSTER LAUNCHER"]]
	elif which == "mines":
		OPTS = [["mine_heavy", "HEAVY MINE"], ["mine_cluster", "CLUSTER MINE"]]
	elif which == "drop":
		# EVERYTHING IN DESIGN DROP 1 THAT IS STILL ONLY A MODEL, on one sheet,
		# at one camera scale so their sizes are comparable to each other.
		OPTS = [["repair_lance", "REPAIR LANCE"], ["diver", "DIVER"],
			["mine_heavy", "HEAVY MINE"], ["mine_cluster", "CLUSTER MINE"]]
	else:
		# Anything else is taken as a list of scene basenames, so a single
		# concept can be looked at without editing this file to do it.
		for name in arg:
			OPTS.append([name, name.to_upper().replace("_", " ")])
	await process_frame
	var shots: Array = []
	for o in OPTS:
		# A full res:// path renders anything, not just the concepts folder.
		var p: String = o[0] if String(o[0]).begins_with("res://") else "%s/%s.tscn" % [DIR, o[0]]
		if not ResourceLoader.exists(p):
			printerr("missing %s" % p); continue
		var m: Node3D = (load(p) as PackedScene).instantiate()
		var img := await _shot(m, String(o[1]))
		if img != null:
			shots.append(img)
			print("OK    %-18s" % o[0])
	if shots.is_empty():
		quit(1); return
	var sheet := Image.create(CELL.x * shots.size(), CELL.y, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * i, 0))
	DirAccess.make_dir_recursive_absolute(OUT)
	# The sheet name comes from the argument, which may be a res:// path — slashes
	# and colons in a filename produce a save that silently goes nowhere.
	var safe := which.get_file().get_basename() if which.begins_with("res://") else which
	var pth := ProjectSettings.globalize_path("%s/%s.png" % [OUT, safe])
	sheet.save_png(pth)
	print("SHEET %s" % pth)
	quit(0)

func _shot(model: Node3D, label: String) -> Image:
	var vp := SubViewport.new()
	vp.size = CELL * 2
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.58, 0.56)
	env.ambient_light_energy = 0.95
	var we := WorldEnvironment.new(); we.environment = env; vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34, -46, 0); key.light_energy = 1.8; vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 130, 0); fill.light_energy = 0.55; vp.add_child(fill)
	var stage := Node3D.new()
	stage.add_child(model)
	stage.add_child(_bar())
	stage.add_child(_cap(label))
	vp.add_child(stage)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = FRAME
	cam.position = Vector3(1.4, 1.5, 3.2)
	vp.add_child(cam); root.add_child(vp)
	cam.look_at(Vector3(0, 0.05, 0), Vector3.UP)
	await process_frame
	await process_frame
	var t := vp.get_texture()
	if t == null: vp.queue_free(); return null
	var img := t.get_image()
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
	vp.queue_free()
	return img

func _bar() -> Node3D:
	var n := Node3D.new(); n.position = Vector3(0, -0.95, 0)
	var m := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = Vector3(0.5, 0.02, 0.02); m.mesh = b
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.5, 0.55, 0.52)
	m.material_override = mat; n.add_child(m)
	var l := Label3D.new(); l.text = "50cm"; l.font_size = 64; l.pixel_size = 0.0022
	l.modulate = Color(0.62, 0.95, 0.66); l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, -0.16, 0); n.add_child(l)
	return n

func _cap(t: String) -> Label3D:
	var l := Label3D.new(); l.text = t; l.font_size = 96; l.pixel_size = FRAME * 0.0016
	l.modulate = Color(0.86, 1.0, 0.88); l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = Vector3(0, FRAME * 0.4, 0)
	return l
