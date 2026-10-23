extends SceneTree

# ─────────────────────────────────────────────
# MOCK ORBIT — what the home base looks like if it stops being a train.
#
#   godot --audio-driver Dummy --path . --script res://tools/mock_orbit.gd \
#       -- docs/concepts
#
# Concept art for docs/briefs/ORBIT.md, built the way this project builds
# concept art: REAL GEOMETRY AT REAL SCALE, through the game's own screen
# filter, photographed from the eye height the player actually has. Nothing
# here is a painting and nothing is to-taste — every number below is a metre.
#
# MUST RUN HEADFUL, and it refuses to pretend otherwise. signal_filter
# samples hint_screen_texture; under --headless there is nothing to sample and
# every frame comes back flat, which looks exactly like a finished picture.
# The filter's uniforms are read out of Character/hud/hud.tscn rather than off
# the shader's declared defaults, because the scene's values are the ones the
# game runs — see mock_filter.gd, which established this and is the reason
# three separate "the lighting is broken" investigations stopped happening.
#
# THE EYE IS AT 1.50 m IN EVERY SHOT but the plan. That is the whole point of
# the exercise: the brief says "it should feel big", and big is not a number
# in a builder, it is what 18 m of ceiling does from 1.5 m off the deck.
#
# NOTHING IN THE STATION MOVES. The rotation is faked exactly the way the
# train faked its journey — Env/world_objects/tunnel_scroll.gdshader scrolls a
# bar of light along a wall 20 m outside eight window apertures, and the
# apertures turn that into motion. Repointed at a starfield it is rotation.
# We would be deleting the train and keeping its best trick. The two _spin
# frames are the same camera at two phases, which is the only way a PNG can
# argue about movement.
#
# WHAT IT IS NOT. No navmesh, no collision worth the name, no interactibles,
# no art. This is a massing study: volumes, sightlines and scale, to be looked
# at before TERRAIN spends a fortnight on a station.
# ─────────────────────────────────────────────

## The planet renders on its own visual layer so it can have its own sun and
## its own terminator without a second light falling on the deck.
const PLANET_LAYER := 1 << 4

const WIDTH := 1152
const HEIGHT := 648
const EYE := 1.50
const HUD_SCENE := "res://Character/hud/hud.tscn"
const FILTER_NODE := "SignalFilter"

# ── THE STATION, IN METRES ───────────────────
# A GALLERY, NOT A DRUM. The honest shape for a rotating station is a drum you
# stand inside with "down" pointing outward, and it is the wrong shape to
# build first: the horizon curves up in front of you, which is a famous image
# and an unreadable room. A gallery with the window wall on one side reads
# immediately and can be bent into a drum later if the look is wanted.
const DECK_LONG := 60.0        ## along Z, the walk from table to pod
const DECK_WIDE := 26.0        ## across X, window wall to inner wall
const CEILING := 18.0          ## 12 x the player's own height, overhead
const WINDOW_X := 13.0         ## the window wall, at +X
const APERTURE_W := 4.0
const APERTURE_H := 9.0
const SILL := 1.2              ## below the eye, so the floor of the view is sky
const PITCH := 8.0             ## seven apertures over the gallery

# THE WELL IS THE WHOLE IDEA. "Machinery underneath you" only reads if you can
# walk to an edge and look down it, so the deck has a hole in it and a
# handrail, and the drop is deep enough that the bottom is dim.
const WELL_X0 := -7.0
const WELL_X1 := 4.0
const WELL_Z0 := -16.0
const WELL_Z1 := 18.0
const WELL_DEPTH := 46.0

const TABLE_AT := Vector3(-9.5, 0.0, -22.0)
const TABLE_SIZE := Vector3(7.0, 0.95, 3.0)   ## fit_ops_table.gd's real slab
const POD_AT := Vector3(8.0, 0.0, 26.0)

## NOFILTER=1 renders the same cameras with NO signal filter, and writes each
## file with a _raw suffix. It exists because the first pass of this mock was
## read as "the windows are full of stars" when the speckle was the filter's
## own dither (0.85) and grain (0.05) over every surface in the frame,
## including the deck. An A/B is the only way to tell those apart.
var _raw := OS.get_environment("NOFILTER") == "1"
var _out := "docs/concepts"
var _root: Node3D
var _sky: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://") + _out)
	Settings.path = "user://settings_probe_mock_orbit.json"
	await process_frame

	var mat := _hud_filter()
	if mat == null:
		printerr("mock_orbit: no %s ShaderMaterial in %s. These would be pictures of a different game — refusing rather than writing a flat PNG that looks like proof." % [FILTER_NODE, HUD_SCENE])
		quit(1)
		return

	_root = Node3D.new()
	root.add_child(_root)
	_build()

	# OVER THE WORLD IN THE ROOT VIEWPORT, where hud.tscn puts it. A
	# SubViewport is a different render target and a shader that reads the
	# screen is exactly the kind that can tell.
	if not _raw:
		var layer := CanvasLayer.new()
		layer.layer = 100
		var rect := ColorRect.new()
		rect.material = mat
		rect.anchor_right = 1.0
		rect.anchor_bottom = 1.0
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(rect)
		root.add_child(layer)

	DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))
	get_root().content_scale_size = Vector2i(WIDTH, HEIGHT)
	for _i in 30:
		await process_frame

	var cam := Camera3D.new()
	cam.far = 6000.0
	cam.fov = 75.0
	_root.add_child(cam)
	cam.make_current()

	# ── THE SHOTS ───────────────────────────────
	# Every one at 1.50 m except the plan, which says so in its own name.
	await _eye(cam, "orbit_gallery.png",
		Vector3(-2.5, EYE, -27.0), Vector3(7.0, 6.0, 24.0))
	await _eye(cam, "orbit_window.png",
		Vector3(7.0, EYE, -4.0), Vector3(WINDOW_X + 60.0, -9.5, 2.0))
	await _eye(cam, "orbit_well.png",
		Vector3(-7.05, EYE, -2.0), Vector3(3.5, -16.0, 5.0))
	await _eye(cam, "orbit_table.png",
		Vector3(-9.5, EYE, -29.0), Vector3(-7.0, 1.2, -20.0))
	await _eye(cam, "orbit_pod.png",
		Vector3(2.0, EYE, 16.0), Vector3(8.0, 4.0, 27.0))

	# ROTATION, AS TWO FRAMES OF ONE CAMERA. Nothing in the room moves between
	# them; the sky has turned 9 degrees.
	await _eye(cam, "orbit_spin_a.png",
		Vector3(6.0, EYE, -4.0), Vector3(WINDOW_X + 40.0, 7.0, -2.0))
	_sky.rotation.y += deg_to_rad(9.0)
	await _eye(cam, "orbit_spin_b.png",
		Vector3(6.0, EYE, -4.0), Vector3(WINDOW_X + 40.0, 7.0, -2.0))
	_sky.rotation.y -= deg_to_rad(9.0)

	# AND ONE THAT IS NOT A PICTURE OF THE GAME, labelled so nobody reads it
	# as one: the whole volume from outside, to argue about massing.
	await _eye(cam, "orbit_plan_not_eye_level.png",
		Vector3(-66.0, 42.0, -62.0), Vector3(0.0, 2.0, 2.0))

	print("")
	print("  deck %.0f x %.0f m, ceiling %.0f m, well %.0f m deep"
		% [DECK_LONG, DECK_WIDE, CEILING, WELL_DEPTH])
	print("  eye at %.2f m in every frame but the plan" % EYE)
	quit(0)


# ─────────────────────────────────────────────
# THE BUILD
# ─────────────────────────────────────────────
func _build() -> void:
	_light()
	_sky_and_planet()
	_deck()
	_window_wall()
	_machinery()
	_table()
	_pod()


## DIM, AND FROM ABOVE. Home Command's rule is no flicker, and a station lit
## like an office loses the one thing a window is for. The deck lamps are
## overhead at a Walker's working height, so 1.5 m is the dim band — the same
## trick block_railhead.gd used on the train and the reason the player's own
## altitude always reads as the gloom.
func _light() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.55
	sun.light_color = Color(0.72, 0.80, 0.95)
	sun.rotation_degrees = Vector3(-24.0, 36.0, 0.0)
	# THE STATION'S SUN STAYS OFF THE PLANET, which has its own.
	sun.light_cull_mask = 0xFFFFF & ~PLANET_LAYER
	_root.add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.004, 0.008, 0.012)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.38, 0.50, 0.60)
	e.ambient_light_energy = 0.75
	env.environment = e
	_root.add_child(env)

	for i in 8:
		var lamp := OmniLight3D.new()
		lamp.light_energy = 14.0
		lamp.light_color = Color(0.85, 0.95, 1.0)
		lamp.omni_range = 30.0
		lamp.position = Vector3(-2.0, 11.0, -30.0 + float(i) * 8.0)
		_root.add_child(lamp)


## THE SKY IS A SINGLE INVERTED SPHERE, and the stars are pixels in an image
## rather than meshes. A thousand little billboards is a thousand draw calls
## for something that is never closer than a kilometre — and the screen filter
## would eat them anyway: docs/concepts/IMPACTS.md measured that the edge pass
## inverts anything thinner than 4-7 screen pixels to near-black, which is
## every star drawn as geometry.
##
## IT IS PARENTED TO ONE NODE ON PURPOSE. Rotation is this node's `rotation.y`
## and nothing else in the station is under it, which is the whole mechanism:
## the room is still and the sky turns.
func _sky_and_planet() -> void:
	_sky = Node3D.new()
	_root.add_child(_sky)

	var img := Image.create(2048, 1024, false, Image.FORMAT_RGB8)
	img.fill(Color(0.004, 0.006, 0.010))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261023
	for _i in 2600:
		var x := rng.randi_range(0, 2047)
		var y := rng.randi_range(0, 1023)
		# A FEW BRIGHT ONES AND A LOT OF FAINT, which is what a sky looks like
		# and also what survives a filter that quantises luma to ten levels.
		var v: float = pow(rng.randf(), 3.0)
		var tint := Color(0.78 + v * 0.22, 0.86 + v * 0.14, 1.0)
		img.set_pixel(x, y, tint * (0.25 + v * 0.75))
	var tex := ImageTexture.create_from_image(img)

	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 9000.0
	sphere.height = 18000.0
	sphere.radial_segments = 48
	sphere.rings = 24
	sphere.flip_faces = true
	dome.mesh = sphere
	var sky_mat := StandardMaterial3D.new()
	sky_mat.albedo_texture = tex
	sky_mat.emission_enabled = true
	sky_mat.emission_texture = tex
	sky_mat.emission_energy_multiplier = 1.6
	sky_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# CULLED, AND THIS IS NOT A TIDY-UP. With culling off, the NEAR wall of a
	# 1800 m sphere draws too — over the deck, the table and your own hands.
	# The first render was a star field with a room faintly behind it.
	sky_mat.cull_mode = BaseMaterial3D.CULL_BACK
	dome.mesh.surface_set_material(0, sky_mat)
	_sky.add_child(dome)

	# THE LIMB, NOT THE PLANET. You are in low orbit over a thing you are
	# fighting on, so it fills a window rather than sitting in one like a
	# marble — and it gives the drop somewhere to point.
	#
	# IT IS LIT, NOT GLOWING. The first pass made it a bright emissive ball in
	# a green I had picked, which the filter then pushed to high_tint and
	# turned into a pale green lamp. Two separate mistakes stacked: the
	# material was green to begin with, and anything bright becomes pale
	# yellow-green anyway because palette() ramps luma shadow -> mid -> high
	# and high_tint is (0.87, 0.94, 0.72).
	#
	# SO THE HUE HAS TO COME FROM CHROMA, NOT FROM BRIGHTNESS. The filter adds
	# the source's own chroma back on top of that ramp — `col += chroma *
	# saturation` — so a blue ocean reads blue even through a green palette,
	# as long as it is not so bright that it pins to the top band.
	#
	# AND IT GETS ITS OWN SUN ON ITS OWN VISUAL LAYER, so there is a
	# TERMINATOR. A fully lit disc is a shape; a lit crescent with a dark side
	# is a world, and it costs one light and one bitmask.
	var world := MeshInstance3D.new()
	var globe := SphereMesh.new()
	globe.radius = 5600.0
	globe.height = 11200.0
	globe.radial_segments = 64
	globe.rings = 32
	world.mesh = globe
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = _earth_texture()
	pm.roughness = 1.0
	pm.metallic = 0.0
	# Just enough that the night side is a dark globe rather than a hole.
	pm.emission_enabled = true
	# NO CITY LIGHTS. The night side is a dark globe and nothing else.
	pm.emission = Color(0.05, 0.045, 0.04)
	pm.emission_energy_multiplier = 0.30
	# Atmosphere, for free: a rim is what a limb looks like from above it.
	pm.rim_enabled = true
	pm.rim = 0.5
	pm.rim_tint = 0.65
	world.mesh.surface_set_material(0, pm)
	world.layers = PLANET_LAYER

	var psun := DirectionalLight3D.new()
	psun.light_energy = 0.95
	psun.light_color = Color(1.0, 0.97, 0.90)
	psun.light_cull_mask = PLANET_LAYER
	psun.rotation_degrees = Vector3(-28.0, 34.0, 0.0)
	_sky.add_child(psun)
	# FAR ENOUGH THAT THE STATION IS OUTSIDE IT. At 1300 m the sphere reached
	# past the deck and the plan shot was taken from inside the planet.
	world.position = Vector3(4000.0, -4600.0, 600.0)
	_sky.add_child(world)


func _deck() -> void:
	# THE FLOOR IS FOUR SLABS AROUND A HOLE. One slab with a hole in it is a
	# CSG operation and a mock does not need one.
	var half_w := DECK_WIDE * 0.5
	var z0 := -DECK_LONG * 0.5
	var z1 := DECK_LONG * 0.5
	_slab(Vector3(-half_w, -0.4, z0), Vector3(WELL_X0, 0.0, z1), _deck_mat())
	_slab(Vector3(WELL_X1, -0.4, z0), Vector3(half_w, 0.0, z1), _deck_mat())
	_slab(Vector3(WELL_X0, -0.4, z0), Vector3(WELL_X1, 0.0, WELL_Z0), _deck_mat())
	_slab(Vector3(WELL_X0, -0.4, WELL_Z1), Vector3(WELL_X1, 0.0, z1), _deck_mat())

	# Ceiling and the inner wall. The window wall is _window_wall().
	_slab(Vector3(-half_w, CEILING, z0), Vector3(half_w, CEILING + 0.6, z1), _hull_mat())
	_slab(Vector3(-half_w - 0.8, 0.0, z0), Vector3(-half_w, CEILING, z1), _hull_mat())
	_slab(Vector3(-half_w, 0.0, z0 - 0.8), Vector3(half_w, CEILING, z0), _hull_mat())
	_slab(Vector3(-half_w, 0.0, z1), Vector3(half_w, CEILING, z1 + 0.8), _hull_mat())

	# THE WELL NEEDS A SHAFT, and this is not decoration. The deck is 0.4 m
	# of slab with open space under it, so from anywhere down the gallery you
	# looked through the hole, UNDER THE DECK, and straight out at the stars —
	# the floor had a window in it. Eighteen metres of wall closes that and
	# turns the hole into a shaft you are looking down.
	var shaft := _hull_mat()
	shaft.albedo_color = Color(0.20, 0.23, 0.23)
	_slab(Vector3(WELL_X0 - 0.6, -18.0, WELL_Z0 - 0.6), Vector3(WELL_X0, 0.0, WELL_Z1 + 0.6), shaft)
	_slab(Vector3(WELL_X1, -18.0, WELL_Z0 - 0.6), Vector3(WELL_X1 + 0.6, 0.0, WELL_Z1 + 0.6), shaft)
	_slab(Vector3(WELL_X0 - 0.6, -18.0, WELL_Z0 - 0.6), Vector3(WELL_X1 + 0.6, 0.0, WELL_Z0), shaft)
	_slab(Vector3(WELL_X0 - 0.6, -18.0, WELL_Z1), Vector3(WELL_X1 + 0.6, 0.0, WELL_Z1 + 0.6), shaft)

	# THE HANDRAIL IS WHAT MAKES THE DROP READ. Without an edge you can stand
	# at, a hole in the floor is a dark rectangle.
	var rail := _hull_mat()
	rail.albedo_color = Color(0.18, 0.22, 0.20)
	for z in [WELL_Z0, WELL_Z1]:
		_slab(Vector3(WELL_X0, 1.0, z - 0.08), Vector3(WELL_X1, 1.1, z + 0.08), rail)
	for x in [WELL_X0, WELL_X1]:
		_slab(Vector3(x - 0.08, 1.0, WELL_Z0), Vector3(x + 0.08, 1.1, WELL_Z1), rail)


## APERTURES CUT BY WHAT IS BETWEEN THEM. Seven windows 4 m wide and 9 m tall
## on an 8 m pitch, sill at 1.2 m — below the eye, so the bottom of what you
## see out of them is sky rather than wall. The train used eight a side at 2 m
## and they were portholes by comparison; these are the reason the room is
## supposed to feel like it is somewhere.
func _window_wall() -> void:
	var z0 := -DECK_LONG * 0.5
	var mat := _hull_mat()
	var head: float = SILL + APERTURE_H
	var n := int(DECK_LONG / PITCH)
	for i in n + 1:
		var centre: float = z0 + float(i) * PITCH + PITCH * 0.5
		var mull_a: float = centre - APERTURE_W * 0.5
		if i == 0:
			_slab(Vector3(WINDOW_X, 0.0, z0), Vector3(WINDOW_X + 0.7, CEILING, mull_a), mat)
		var mull_b: float = centre + APERTURE_W * 0.5
		var next_a: float = centre + PITCH - APERTURE_W * 0.5
		var upto: float = minf(next_a, z0 + DECK_LONG)
		if mull_b < upto:
			_slab(Vector3(WINDOW_X, 0.0, mull_b), Vector3(WINDOW_X + 0.7, CEILING, upto), mat)
		# Sill and head, across the aperture.
		_slab(Vector3(WINDOW_X, 0.0, mull_a), Vector3(WINDOW_X + 0.7, SILL, mull_b), mat)
		_slab(Vector3(WINDOW_X, head, mull_a), Vector3(WINDOW_X + 0.7, CEILING, mull_b), mat)


## WHAT YOU ARE STANDING OVER. Refinery massing: stacks, drums and a lot of
## pipe, lit from inside itself so the bottom of the well glows rather than
## going black. It is 46 m down, which is far enough that the detail dies and
## near enough that the scale of the pieces still reads.
func _machinery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 713
	var mm := _hull_mat()
	mm.albedo_color = Color(0.09, 0.11, 0.11)
	for _i in 46:
		var x: float = rng.randf_range(WELL_X0 - 14.0, WELL_X1 + 14.0)
		var z: float = rng.randf_range(WELL_Z0 - 14.0, WELL_Z1 + 14.0)
		var w: float = rng.randf_range(1.6, 5.0)
		var d: float = rng.randf_range(1.6, 5.0)
		var top: float = rng.randf_range(-34.0, -6.0)
		_slab(Vector3(x - w, -WELL_DEPTH, z - d), Vector3(x + w, top, z + d), mm)
	# The floor of it, so the well has a bottom.
	_slab(Vector3(WELL_X0 - 20.0, -WELL_DEPTH - 1.0, WELL_Z0 - 20.0),
		Vector3(WELL_X1 + 20.0, -WELL_DEPTH, WELL_Z1 + 20.0), mm)
	# AND THE LIGHTS IN IT. Orange against the deck's blue-white: the one
	# colour in the station that is not Home Command's, because the machinery
	# predates it and is running unattended, which is the whole of lore.txt.
	for i in 10:
		var glow := OmniLight3D.new()
		glow.light_energy = 11.0
		glow.light_color = Color(1.0, 0.56, 0.22)
		glow.omni_range = 26.0
		glow.position = Vector3(rng.randf_range(WELL_X0, WELL_X1),
			rng.randf_range(-40.0, -14.0), rng.randf_range(WELL_Z0, WELL_Z1))
		_root.add_child(glow)


## The operations table at fit_ops_table.gd's real slab: 7.0 x 3.0 m, top at
## 0.95. It is here to be stood next to, not redesigned — the point of
## including it is that it is BIG, and a station has to be built around a
## 7 m table rather than having one dropped in afterwards.
func _table() -> void:
	var m := _hull_mat()
	m.albedo_color = Color(0.13, 0.17, 0.17)
	_slab(TABLE_AT + Vector3(-TABLE_SIZE.x * 0.5, 0.0, -TABLE_SIZE.z * 0.5),
		TABLE_AT + Vector3(TABLE_SIZE.x * 0.5, TABLE_SIZE.y, TABLE_SIZE.z * 0.5), m)
	# The projection over it, as a flat glow at the real 6.6 x 2.7 m.
	var plate := _hull_mat()
	plate.albedo_color = Color(0.20, 0.85, 0.55)
	plate.emission_enabled = true
	plate.emission = Color(0.25, 1.0, 0.62)
	plate.emission_energy_multiplier = 2.2
	plate.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_slab(TABLE_AT + Vector3(-3.3, TABLE_SIZE.y + 0.04, -1.35),
		TABLE_AT + Vector3(3.3, TABLE_SIZE.y + 0.09, 1.35), plate)


## THE POD IS THE COMMIT AND IT HAS TO LOOK LIKE A DOOR YOU WALK INTO, not a
## vehicle you drive. A cradle, a hatch in the deck under it, and a throat
## going down and out through the hull — you step in, it drops away from the
## station and the station is what you watch leave.
func _pod() -> void:
	var cm := _hull_mat()
	cm.albedo_color = Color(0.16, 0.19, 0.18)
	# Cradle legs and the collar the pod sits in.
	_slab(POD_AT + Vector3(-3.2, 0.0, -3.2), POD_AT + Vector3(-2.6, 4.0, -2.6), cm)
	_slab(POD_AT + Vector3(2.6, 0.0, -3.2), POD_AT + Vector3(3.2, 4.0, -2.6), cm)
	_slab(POD_AT + Vector3(-3.2, 0.0, 2.6), POD_AT + Vector3(-2.6, 4.0, 3.2), cm)
	_slab(POD_AT + Vector3(2.6, 0.0, 2.6), POD_AT + Vector3(3.2, 4.0, 3.2), cm)
	_slab(POD_AT + Vector3(-3.6, 4.0, -3.6), POD_AT + Vector3(3.6, 4.6, 3.6), cm)

	var pod := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 1.5
	body.height = 5.2
	body.radial_segments = 16
	pod.mesh = body
	var pm := _hull_mat()
	pm.albedo_color = Color(0.22, 0.24, 0.22)
	pod.mesh.surface_set_material(0, pm)
	pod.position = POD_AT + Vector3(0.0, 2.3, 0.0)
	_root.add_child(pod)

	# The open hatch, lit from inside: the one warm doorway on the deck.
	var mouth := _hull_mat()
	mouth.albedo_color = Color(0.9, 0.62, 0.30)
	mouth.emission_enabled = true
	mouth.emission = Color(1.0, 0.66, 0.32)
	mouth.emission_energy_multiplier = 2.0
	mouth.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_slab(POD_AT + Vector3(-1.1, 0.6, -1.52), POD_AT + Vector3(1.1, 2.9, -1.46), mouth)
	var lamp := OmniLight3D.new()
	lamp.light_energy = 3.0
	lamp.light_color = Color(1.0, 0.70, 0.38)
	lamp.omni_range = 12.0
	lamp.position = POD_AT + Vector3(0.0, 2.0, -2.4)
	_root.add_child(lamp)


# ─────────────────────────────────────────────
# PLUMBING
# ─────────────────────────────────────────────
## An axis-aligned box from `a` to `b`, in metres. Every piece of this mock is
## one of these, which is deliberate: a massing study that needs a modeller is
## a study nobody will redo after the first note.
func _slab(a: Vector3, b: Vector3, mat: StandardMaterial3D) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = (b - a).abs()
	m.mesh = box
	m.mesh.surface_set_material(0, mat)
	m.position = (a + b) * 0.5
	_root.add_child(m)


func _deck_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.26, 0.30, 0.29)
	m.roughness = 0.9
	return m


func _hull_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 0.34, 0.33)
	m.roughness = 0.85
	return m


func _eye(cam: Camera3D, file: String, from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	for _i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := "res://%s/%s" % [_out, file.replace(".png", "_raw.png") if _raw else file]
	var err := img.save_png(path)
	print("wrote %s" % path if err == OK else "FAILED %s (%s)" % [path, error_string(err)])


## The filter the GAME runs, lifted out of hud.tscn with its scene values.
func _hud_filter() -> ShaderMaterial:
	var packed := load(HUD_SCENE) as PackedScene
	if packed == null:
		return null
	var hud := packed.instantiate()
	var found := _filter_in(hud)
	hud.queue_free()
	return found


func _filter_in(n: Node) -> ShaderMaterial:
	if n.name == FILTER_NODE and n is CanvasItem:
		var m := (n as CanvasItem).material
		if m is ShaderMaterial:
			return (m as ShaderMaterial).duplicate()
	for c in n.get_children():
		var f := _filter_in(c)
		if f != null:
			return f
	return null


## EARTH, AS AN EQUIRECTANGULAR TEXTURE RATHER THAN A COLOUR.
##
## A flat albedo makes a disc. What reads as a world through ten luma levels
## is STRUCTURE — a coastline, an ice cap, a band of cloud — because the
## quantiser keeps hard boundaries and throws away smooth gradients, which is
## the same reason the edge pass is what makes low-poly geometry legible at
## all (see the strategy note at the top of signal_filter.gdshader).
##
## IT IS DEAD, which is what lore.txt describes: GUBI ended, the cyberspace
## regions went dark, and humanity and its robots fell into disrepair. A blue
## marble is a world worth defending and that is not the world this is. Ash
## land, leaden water, a dust layer instead of weather, and ice the colour of
## old snow.
##
## AND YOU CANNOT GET THERE BY REMOVING COLOUR — that is the trap, and I fell
## in it once. `col = mix(vec3(lq), palette(lq), 0.6)` then `col += chroma *
## saturation`: a NEUTRAL grey has no chroma to add back, so it is 60% of a
## palette whose mid tint is (0.30, 0.46, 0.38), and it comes out GREEN. The
## deadest thing you can paint is the one the filter colours in most.
##
## So every grey here carries a slight WARM bias — a few hundredths of red
## over blue — which the green ramp then cancels. **To read as grey in this
## game a thing has to be faintly brown to begin with.**
##
## 1024 x 512 and generated once. Poles smear, as they do on every
## equirectangular map, and at this distance the smear is two pixels.
func _earth_texture() -> ImageTexture:
	var w := 1024
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var land := FastNoiseLite.new()
	land.seed = 9
	land.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# HIGHER FREQUENCY THAN A REAL MAP WANTS. You only ever see a crescent of
	# this through a 4 m aperture, and large smooth landmasses put no edge in
	# that crop at all — the filter keeps hard boundaries and throws smooth
	# gradients away, so coastline per square metre IS the detail budget.
	land.frequency = 0.0075
	land.fractal_octaves = 6
	# BURN SCARS: a low-frequency layer that drops whole regions nearly black.
	# Large-scale structure is the only kind that survives at this distance.
	var scar := FastNoiseLite.new()
	scar.seed = 77
	scar.noise_type = FastNoiseLite.TYPE_SIMPLEX
	scar.frequency = 0.0022
	scar.fractal_octaves = 2
	var cloud := FastNoiseLite.new()
	cloud.seed = 41
	cloud.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cloud.frequency = 0.006
	cloud.fractal_octaves = 4
	for y in h:
		var lat: float = float(y) / float(h - 1) * 2.0 - 1.0
		var polar: float = smoothstep(0.70, 0.94, absf(lat))
		# Cloud sits in bands rather than evenly, which is most of what makes
		# a noise sphere look like weather instead of static.
		var band: float = 0.45 + 0.55 * cos(lat * PI * 3.0)
		for x in w:
			var e: float = land.get_noise_2d(float(x), float(y))
			var c: Color
			if e < -0.02:
				# Leaden, not blue. Still a touch warm so it does not green.
				var deep: float = clampf((-0.02 - e) * 3.0, 0.0, 1.0)
				c = Color(0.155, 0.147, 0.142).lerp(Color(0.035, 0.035, 0.040), deep)
			elif e < 0.06:
				c = Color(0.33, 0.29, 0.25)   # dry shelf
			elif e < 0.18:
				c = Color(0.42, 0.37, 0.32)   # dust plain
			else:
				c = Color(0.54, 0.50, 0.45)   # high ground, ash pale
			c = c.lerp(Color(0.63, 0.61, 0.58), polar)   # old snow, not ice
			var burn: float = clampf((scar.get_noise_2d(float(x), float(y)) - 0.12) * 3.2, 0.0, 1.0)
			c = c.lerp(Color(0.075, 0.068, 0.062), burn * 0.80)
			var cl: float = cloud.get_noise_2d(float(x) * 0.6, float(y) * 1.6)
			var cover: float = clampf((cl + 0.10) * 2.0, 0.0, 1.0) * band
			# DUST, NOT WEATHER. Heavier than cloud and the colour of what is
			# under it, so the atmosphere reads as something the planet threw
			# up rather than something passing over it.
			c = c.lerp(Color(0.50, 0.46, 0.41), cover * 0.28)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
