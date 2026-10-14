extends SceneTree

# ─────────────────────────────────────────────
# PHOTOGRAPH THE ROVER AND THE SOLDIER, WEARING EACH HAT.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_frames.gd -- <out dir>
#
# The rank headgear is authored as CSG in tools/mockup_parts.gd, baked to
# meshes by tools/bake_hats.gd, and bolted on at spawn by RankKit. Eight rounds
# of iteration went into shapes that are only ever seen on a robot that is
# moving, at range, shooting at you.
#
# One frame per hat, from a fixed three-quarter angle with a one-metre grid, so
# the shapes can be compared against each other rather than remembered.
#
# RankKit reads a `cosmetic_id` meta off the body BEFORE it enters the tree —
# that is how a squad robot wears what you picked on its card — so setting the
# meta first is exactly the game's own path, not a special case for this tool.
#
# HEADFUL: the dummy renderer returns blank textures. It opens a window.
# It loads no campaign and writes none.
# ─────────────────────────────────────────────

const FRAMES := {
	"rover": {
		"scene": "res://Character/characters/ai/vehicle_rover.tscn",
		"hats": ["", "rover_beret", "rover_slouch"],
		"cam": Vector3(3.0, 1.9, 3.0),
		"look": Vector3(0.0, 0.85, 0.0),
	},
	"soldier": {
		"scene": "res://Character/characters/ai/soldier_chassis.tscn",
		"hats": ["", "soldier_cap", "soldier_brodie", "soldier_pickelhaube"],
		"cam": Vector3(1.7, 1.45, 1.7),
		"look": Vector3(0.0, 0.80, 0.0),
	},
}

const FILTER := preload("res://Character/hud/signal_filter.gdshader")

## THE HUD'S OWN SETTINGS, copied from the ShaderMaterial in hud.tscn rather
## than left at the shader's defaults — they differ in three places (palette
## 0.6, 8 fps of artefact, dropout 0.003) and the look is the point of the
## picture. If hud.tscn is retuned, retune these with it.
const FILTER_PARAMS := {
	"quantize_resolution": true, "signal_height": 360.0, "cell_average": true,
	"chroma_divisor": 2.0, "exposure": 1.05, "gamma": 1.0, "contrast": 1.12,
	"black_lift": 0.05, "luma_levels": 10.0, "chroma_levels": 5.0,
	"saturation": 0.9,
	"shadow_tint": Color(0.05, 0.11, 0.12), "mid_tint": Color(0.3, 0.46, 0.38),
	"high_tint": Color(0.87, 0.94, 0.72), "palette_strength": 0.6,
	"edge_color": Color(0.02, 0.06, 0.06), "edge_strength": 0.75,
	"edge_threshold": 0.06, "dither_strength": 0.85,
	"signal_fps": 8.0, "grain": 0.05, "dropout": 0.003,
	"block_glitch": 0.12, "block_size": 8.0, "damage": 0.0, "boot": 0.0,
}


## The screen filter the whole game is seen through — signal_filter.gdshader,
## the same one hud.tscn puts over everything. Without it these are pictures of
## assets; with it they are pictures of the game.
func _filter() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = FILTER
	for k in FILTER_PARAMS:
		mat.set_shader_parameter(k, FILTER_PARAMS[k])
	rect.material = mat
	layer.add_child(rect)

var _out: String = ""
var _scene: Node3D = null


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
	DisplayServer.window_set_size(Vector2i(1000, 1000))
	DisplayServer.window_set_position(Vector2i(60, 40))

	_scene = Node3D.new()
	root.add_child(_scene)
	_stage()
	_filter()

	var cam := Camera3D.new()
	_scene.add_child(cam)
	cam.current = true

	for frame in FRAMES:
		var spec: Dictionary = FRAMES[frame]
		for hat in spec["hats"]:
			var body = load(spec["scene"]).instantiate()
			# BEFORE add_child, which is the whole point: RankKit reads this in
			# _ready and an empty string means "chose none", not "never asked".
			if String(hat) != "":
				body.set_meta("cosmetic_id", StringName(hat))
			_scene.add_child(body)
			(body as Node3D).global_position = Vector3.ZERO
			cam.global_position = spec["cam"]
			cam.look_at(spec["look"])
			# EYE TO CAMERA. Forward is -Z — on the soldier the sensor nub sits
			# at z -0.40 — and look_at points -Z at its target, so this turns
			# the frame's face to us. Flattened to the body's own height or a
			# camera above eye level would tip the whole robot back.
			(body as Node3D).look_at(Vector3(
				cam.global_position.x, (body as Node3D).global_position.y,
				cam.global_position.z))
			# Let RankKit's deferred refit land and the livery dress it.
			for _i in 25:
				await process_frame
			# PLAYER COLOURS, applied after the refit so the hat is in the
			# livery's piece list by then — RankKit registers it by hand in
			# _dress, and a hat added after an apply() keeps the stock material.
			_paint(body)
			for _i in 4:
				await process_frame
			await process_frame
			var img := root.get_viewport().get_texture().get_image()
			var label: String = String(hat) if String(hat) != "" else "%s_bare" % frame
			var path: String = "%s/frame_%s.png" % [_out, label]
			img.save_png(path)
			print("OK    %-22s -> %s" % [label, path])
			body.queue_free()
			await process_frame

	print("FRAME SHOTS DONE")
	quit()


## Paint the frame in the player's colours. The livery is a plain Node child,
## and apply() is what the spawner calls; nothing here is a special case.
func _paint(body: Node) -> void:
	var livery = body.get_node_or_null("FactionLivery")
	if livery == null or not livery.has_method("apply"):
		push_warning("shot_frames: %s has no FactionLivery, so it stays in stock colours." % body.name)
		return
	livery.apply(Enums.Factions.PLAYER)


func _stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.08, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.62, 0.70)
	e.ambient_light_energy = 0.8
	env.environment = e
	_scene.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 42.0, 0.0)
	key.light_energy = 1.5
	_scene.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, -130.0, 0.0)
	fill.light_energy = 0.5
	_scene.add_child(fill)

	# A ONE-METRE GRID, so proportions can be read off the picture.
	var grid := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.22, 0.40, 0.38)
	im.surface_begin(Mesh.PRIMITIVE_LINES, gm)
	for i in range(-3, 4):
		var f := float(i)
		im.surface_add_vertex(Vector3(f, 0.0, -3.0))
		im.surface_add_vertex(Vector3(f, 0.0, 3.0))
		im.surface_add_vertex(Vector3(-3.0, 0.0, f))
		im.surface_add_vertex(Vector3(3.0, 0.0, f))
	im.surface_end()
	grid.mesh = im
	_scene.add_child(grid)
