extends SceneTree

# ─────────────────────────────────────────────
# SPLASH — hero shots of the environments, lit for pictures rather than for
# play. For key art, a title screen, a briefing background, a store page.
#
#   RENDER_OUT=<dir> godot --path . --script res://tools/probe_splash.gd
#   RENDER_OUT=<dir> ONLY=dusk godot --path . --script res://tools/probe_splash.gd
#
# NOT headless: the dummy renderer returns blank images.
#
# IT NEVER SAVES A LEVEL. The mood is made by overriding the WorldEnvironment
# and the sun on the INSTANCE, after the level is in the tree — the scene files
# are not touched and nothing here changes how the game looks in play.
#
# WHAT MAKES THESE DIFFERENT from the survey shots in probe_shots_*.gd: a low
# sun so everything has a long shadow and an edge, heavy graded fog so distance
# reads as depth, a tighter lens from lower down so the buildings tower, and
# glow turned up so the machines' seams carry in the dark. Composition is hand
# picked per shot — a landmark against the sky, something in the near ground,
# and a line that leads between them.
# ─────────────────────────────────────────────

const EYE := 1.7

## name: [sky, fog colour, fog density, sun pitch, sun yaw, sun energy,
##        sun colour, ambient, glow, exposure, machine glow]
const MOODS := {
	"dusk": [Color(0.34, 0.20, 0.15), Color(0.46, 0.27, 0.18), 0.0060,
			-7.0, 118.0, 2.6, Color(1.0, 0.68, 0.42), Color(0.20, 0.17, 0.20), 0.9, 0.62, 0.9],
	"cold": [Color(0.22, 0.26, 0.33), Color(0.34, 0.39, 0.47), 0.0080,
			-13.0, -54.0, 1.5, Color(0.80, 0.87, 1.0), Color(0.24, 0.28, 0.34), 0.8, 0.70, 0.0],
	"night": [Color(0.07, 0.08, 0.12), Color(0.10, 0.12, 0.18), 0.0125,
			-26.0, 200.0, 0.35, Color(0.55, 0.65, 0.95), Color(0.07, 0.09, 0.14), 1.5, 1.10, 2.6],
}

## mood, level, name, camera, look at, fov
const SHOTS: Array = [
	["dusk", "mutaha_wip", "01_the_core", Vector3(-44.5, 2.2, 34.0), Vector3(-44.0, 12.0, -22.0), 55.0],
	["night", "mutaha_wip", "02_the_core_dark", Vector3(-30.0, 1.9, 16.0), Vector3(-45.0, 11.0, -20.0), 50.0],
	["dusk", "mutaha_wip", "03_the_dropped_span", Vector3(20.0, 2.0, 200.0), Vector3(-40.0, 9.0, 150.0), 58.0],
	["cold", "mutaha_wip", "04_estates_street", Vector3(-283.0, 1.8, 128.5), Vector3(-372.0, 12.0, 128.5), 60.0],
	["dusk", "mutaha_wip", "05_west_bridge", Vector3(-88.0, 3.0, -22.0), Vector3(-180.0, 7.0, -52.0), 55.0],
	["cold", "mutaha_wip", "06_quarter_skyline", Vector3(-180.0, 3.2, 272.0), Vector3(-300.0, 18.0, 150.0), 52.0],
	["night", "mutaha_wip", "07_under_the_canopy", Vector3(-42.0, 1.8, 74.0), Vector3(-10.0, 5.0, 36.0), 62.0],
	["dusk", "mutaha_wip", "08_clock_over_the_river", Vector3(-150.0, 2.4, -150.0), Vector3(-231.0, 24.0, -217.0), 48.0],
	["cold", "mutaha_wip", "09_the_wheel", Vector3(60.0, 2.6, -120.0), Vector3(181.0, 22.0, -185.0), 46.0],
	["dusk", "mutaha_wip", "10_avenue_north", Vector3(-44.5, 1.8, 120.0), Vector3(-44.5, 8.0, -140.0), 44.0],
	["night", "mutaha_wip", "11_island_from_the_water", Vector3(40.0, 0.4, 60.0), Vector3(-40.0, 9.0, -30.0), 54.0],
	["dusk", "mutaha_wip", "12_the_frame", Vector3(-208.0, 1.8, 196.0), Vector3(-250.0, 10.0, 162.0), 58.0],
	["cold", "heliostat", "13_mirror_field", Vector3(190.0, 46.0, 190.0), Vector3(-30.0, 10.0, -30.0), 44.0],
	["dusk", "heliostat", "14_the_tower", Vector3(96.0, 6.0, 70.0), Vector3(-10.0, 34.0, -30.0), 42.0],
	["dusk", "coastal-road", "15_coast_road", Vector3(-120.0, 3.0, 140.0), Vector3(60.0, 14.0, -40.0), 50.0],
	["night", "pittsburgh", "16_three_rivers", Vector3(-160.0, 4.0, 180.0), Vector3(60.0, 20.0, -60.0), 52.0],
]


func _initialize() -> void:
	await process_frame
	var out := OS.get_environment("RENDER_OUT")
	if out == "":
		print("FAIL  set RENDER_OUT to a directory")
		quit(1)
		return
	var only := OS.get_environment("ONLY")
	var loaded := ""
	var level: Node3D = null
	var cam: Camera3D = null
	var done := 0
	for s: Array in SHOTS:
		var mood := str(s[0])
		var level_name := str(s[1])
		if only != "" and not (only == mood or only == level_name or only in str(s[2])):
			continue
		if level_name != loaded:
			if level != null:
				level.queue_free()
				await process_frame
			var path := "res://maps/%s_level.tscn" % level_name
			var packed := load(path) as PackedScene
			if packed == null:
				print("   skipped %s — will not load" % path)
				continue
			level = packed.instantiate() as Node3D
			root.add_child(level)
			for _i in 30:
				await physics_frame
			loaded = level_name
			cam = Camera3D.new()
			cam.far = 2400.0
			level.add_child(cam)
			cam.make_current()
		# Heliostat is a 1 km mirror field under its own very bright sky: at the
		# exposure the town wants, its horizon goes to paper.
		_set_mood(level, mood, 0.42 if level_name == "heliostat" else 1.0)
		cam.fov = float(s[5])
		cam.position = s[3]
		cam.look_at(s[4], Vector3.UP)
		# The first frame of a fresh run comes back blank while the renderer
		# warms up, and a mood change takes a frame or two to settle.
		for pass_i in 2:
			for _i in 10:
				await process_frame
			if pass_i == 1:
				root.get_texture().get_image().save_png(
						out.path_join("splash_%s_%s.png" % [s[2], mood]))
		done += 1
		print("   %s  %s  %s" % [level_name, mood, s[2]])
	print("   wrote %d splash shot(s) to %s" % [done, out])
	quit()


## Re-light the instance for a picture. Nothing here is saved.
func _set_mood(level: Node3D, mood: String, exposure_scale: float = 1.0) -> void:
	var m: Array = MOODS[mood]
	for node in level.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (node as WorldEnvironment).environment
		if env == null:
			continue
		env = env.duplicate()
		(node as WorldEnvironment).environment = env
		env.background_mode = Environment.BG_COLOR
		env.background_color = m[0]
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = m[7]
		env.ambient_light_energy = 1.0
		env.fog_enabled = true
		env.fog_light_color = m[1]
		env.fog_density = m[2]
		env.fog_sky_affect = 0.45
		env.fog_height = -20.0
		env.fog_height_density = 0.04
		env.glow_enabled = true
		env.glow_intensity = m[8]
		env.glow_bloom = 0.05
		env.glow_strength = 1.05
		env.glow_hdr_threshold = 1.1
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		# Filmic with a high white point and a low exposure: without it the haze
		# plus the bloom takes the sky to flat paper and the heliostat field with
		# it. These are pictures; the sky has to hold a colour.
		env.tonemap_exposure = m[9] * exposure_scale
		env.background_energy_multiplier = 1.0
		env.tonemap_white = 9.0
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.14
		env.adjustment_saturation = 1.18 if mood != "night" else 0.85
	# The machines' seams light up. glitch_tx_1 carries no emission of its own
	# (see docs/BLOCKS.md), so a night shot has black obelisks and black
	# monoliths in it. Set here, in memory, never saved: this is the picture's
	# lighting, not the game's.
	var seam: Material = load("res://textures/PSX_Textures/glitch_tx_1.tres")
	if seam is StandardMaterial3D:
		var sm := seam as StandardMaterial3D
		sm.emission_enabled = float(m[10]) > 0.0
		sm.emission = Color(0.45, 1.0, 0.60)
		sm.emission_energy_multiplier = float(m[10])
	for node in level.find_children("*", "DirectionalLight3D", true, false):
		var sun := node as DirectionalLight3D
		sun.rotation_degrees = Vector3(float(m[3]), float(m[4]), 0.0)
		sun.light_energy = float(m[5])
		sun.light_color = m[6]
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 400.0
