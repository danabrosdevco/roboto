extends SceneTree

# ─────────────────────────────────────────────
# PHOTOGRAPH THE CAPTURE DRONE, so somebody can model the real one.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_drone.gd -- <out dir>
#
# Env/world_objects/capture_tap.gd generates its body in code — placeholder
# geometry, the same way the departure lever's handle is — and says so at
# length. Nobody has looked at it: it only ever appears for four seconds,
# descending, at the moment the player is being shot at.
#
# Four angles with a one-metre grid under it, so its proportions can be read
# off the picture rather than off the source. SPAN is the number that matters:
# 3.4 m across the rotors, against the 1.0 m core it lands on.
#
# HEADFUL, because the dummy renderer returns blank textures. It opens a window
# for a few seconds. It loads no campaign and writes none.
# ─────────────────────────────────────────────

const _Tap := preload("res://Env/world_objects/capture_tap.gd")

var _out: String = ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = String(args[0]) if args.size() > 0 else "res://docs/marketing/wip"
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = "user://settings_probe.json"
	await process_frame
	if DisplayServer.get_name() == "headless":
		print("FAIL  headless renders nothing. Run without --headless.")
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1100, 800))
	DisplayServer.window_set_position(Vector2i(60, 40))

	var scene := Node3D.new()
	root.add_child(scene)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.07, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.6, 0.7)
	e.ambient_light_energy = 0.7
	env.environment = e
	scene.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_energy = 1.4
	scene.add_child(sun)

	# A ONE-METRE GRID, so the thing can be measured off the picture.
	var grid := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.25, 0.45, 0.42)
	gm.vertex_color_use_as_albedo = true
	im.surface_begin(Mesh.PRIMITIVE_LINES, gm)
	for i in range(-4, 5):
		var f := float(i)
		im.surface_add_vertex(Vector3(f, 0.0, -4.0))
		im.surface_add_vertex(Vector3(f, 0.0, 4.0))
		im.surface_add_vertex(Vector3(-4.0, 0.0, f))
		im.surface_add_vertex(Vector3(4.0, 0.0, f))
	im.surface_end()
	grid.mesh = im
	scene.add_child(grid)

	# THE CORE IT LANDS ON, for scale: the 1.0 m post training_core.gd builds.
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.0, 4.2, 1.0)
	post.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.17, 0.19, 0.20)
	post.material_override = pmat
	post.position = Vector3(0.0, 2.1, 0.0)
	scene.add_child(post)

	# The drone itself. _ready builds the body and starts its descent tween; it
	# is parked here instead so it holds still to be photographed.
	var tap = _Tap.new()
	tap.set_script(_Tap)
	scene.add_child(tap)
	# CLEAR OF THE POST, not docked on it: docked, the hull disappears behind
	# the 1 m column and only the rotors read. This is a reference sheet, so it
	# hovers one body-height above where it would actually land.
	tap.global_position = Vector3(0.0, 6.4, 0.0)
	for _i in 30:
		await process_frame

	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.current = true

	var shots := {
		"drone_side":    Vector3(5.2, 6.4, 0.0),
		"drone_front":   Vector3(0.0, 6.4, 5.2),
		"drone_above":   Vector3(3.0, 10.5, 3.0),
		"drone_eye":     Vector3(5.0, 1.7, 5.0),
	}
	for name in shots:
		cam.global_position = shots[name]
		cam.look_at(Vector3(0.0, 5.6, 0.0))
		await process_frame
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path: String = "%s/%s.png" % [_out, name]
		img.save_png(path)
		print("OK    %s -> %s" % [name, path])

	print("DRONE SHOTS DONE")
	quit()
