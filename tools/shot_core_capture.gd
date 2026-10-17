extends SceneTree

# ─────────────────────────────────────────────
# WHAT A CORE LOOKS LIKE BEFORE AND AFTER YOU TAKE IT.
#
#   RENDER_OUT=<dir> godot --path . --audio-driver Dummy \
#       --script res://tools/shot_core_capture.gd
#   RENDER_OUT=<dir> CORE=large godot --path . ...      # small | "" | large
#
# NOT HEADLESS, AND IT REFUSES TO BE. The dummy renderer returns blank
# textures, so a headless run of this writes two identical grey rectangles and
# they look exactly like proof that nothing changed — or, worse, like proof
# that something did.
#
# WHY IT CALLS complete() RATHER THAN set_faction_colour(). The setter is the
# easy thing to photograph and it proves almost nothing: it would pass just as
# happily with the signal unconnected, which is precisely the failure this
# change is about. So the shot drives the REAL path — InteractObjective
# completes, emits objective_completed, core_pulse hears it and retints — and
# the second image is evidence about the wiring rather than about the painter.
#
# NO SIGNAL FILTER HERE, deliberately, which is a departure from the other
# shot tools and needs saying. The filter quantises luma to ten levels; this
# is a question about HUE, and the honest picture of a hue change is the
# unfiltered one. For how it reads in the game, shoot it in a level.
# ─────────────────────────────────────────────

## EVERY OWNER A CORE CAN ADVERTISE, in the order the fiction puts them.
## Lifted from HUDPalette rather than retyped — these same constants drive the
## HUD's contact markers and the ops table, and a core that disagreed with the
## marker pointing at it would be worse than a core with no colour at all.
##
## "player" is HUDPalette.HELD, not a FAC_ constant: the palette models the
## player's own holdings as a STATE ("a site under your control") rather than
## as a faction, which is why there is no FAC_PLAYER to use here.
const PALETTE: Array = [
	["swarm", HUDPalette.FAC_ADVERSARY],
	["player", HUDPalette.HELD],
	["home_command", HUDPalette.FAC_HOME],
	["argus", HUDPalette.FAC_ARGUS],
	["unknown", HUDPalette.FAC_UNKNOWN],
]

const POINT := "res://Env/world_objects/compute_core_point%s.tscn"
const WIDTH := 900
const HEIGHT := 760


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("FAIL  this is a shot tool — run it WITHOUT --headless or both")
		print("      images come back blank and look like a result.")
		quit(1)
		return
	var out := OS.get_environment("RENDER_OUT")
	if out.is_empty():
		print("FAIL  set RENDER_OUT to a directory")
		quit(1)
		return
	var which := OS.get_environment("CORE")
	if not which.is_empty():
		which = "_" + which
	var path := POINT % which

	var packed: PackedScene = load(path)
	if packed == null:
		print("FAIL  could not load %s" % path)
		quit(1)
		return

	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.11, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.32, 0.36, 0.40)
	e.ambient_light_energy = 1.0
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_energy = 0.7
	stage.add_child(sun)

	var core := packed.instantiate()
	stage.add_child(core)

	# POINT THE CAMERA AT THE LIT FACE, don't guess a corner. The first version
	# of this tool stood at (7.4, 4.6, 7.4) because that is a nice three-quarter
	# angle, and photographed the BACK of the machine: one 12-pixel indicator
	# changed colour and the rest of the frame was identical in both shots. The
	# core is asymmetric — build_core_relay.gd puts the slots and fins on one
	# side — so the only camera that can answer the question is one derived
	# from where those pieces actually are.
	var aim := _lit_centroid(core)
	var flat := Vector3(aim.x, 0.0, aim.z)
	if flat.length() < 0.2:
		flat = Vector3(1.0, 0.0, 1.0)   # a symmetric core; any corner will do
	var dir := flat.normalized()
	# AND IT STANDS BACK BY THE MODEL'S OWN HEIGHT. A fixed 9 m frames the 7 m
	# core and crops the 12.4 m one to a wall of fins — which is what the first
	# large-core shot came back as, and a photograph that cannot show the
	# silhouette cannot answer a question about the silhouette.
	var tall := _height(core)
	var cam := Camera3D.new()
	cam.position = dir * maxf(9.0, tall * 1.45) + Vector3(0.0, tall * 0.62, 0.0)
	cam.look_at_from_position(cam.position, Vector3(0.0, tall * 0.42, 0.0), Vector3.UP)
	cam.fov = 48.0
	stage.add_child(cam)
	cam.make_current()
	get_root().content_scale_size = Vector2i(WIDTH, HEIGHT)
	DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))

	# THE PULSE IS A TWEEN, so an immediate grab catches whatever energy the
	# first frame happens to hold and the two images differ in BRIGHTNESS as
	# well as hue, which muddies exactly the comparison being made. Freeze it:
	# set_faction_colour touches emission only, so holding energy still is safe
	# and makes the pair differ in one variable.
	for _i in 8:
		await process_frame

	var pulse := _find_pulse(core)
	if pulse == null:
		print("FAIL  no core_pulse under %s — nothing would recolour" % path)
		quit(1)
		return

	# FACTIONS=1 — ONE FRAME PER OWNER, for judging the palette rather than the
	# wiring. It drives set_faction_colour directly, which is the honest thing
	# to do here: only two of these five are reachable through gameplay today
	# (amber at spawn, blue on capture), so completing an objective cannot
	# produce the other three and pretending otherwise would be a staged photo.
	# The capture path is what the default run proves.
	if OS.get_environment("FACTIONS") != "":
		for row: Array in PALETTE:
			pulse.call(&"set_faction_colour", row[1])
			for _i in 3:
				await process_frame
			print("   %-10s %s" % [row[0], row[1]])
			await _grab(out, "core_faction_%s" % row[0])
		print("PASS  %d faction(s) rendered" % PALETTE.size())
		quit(0)
		return

	print("   before: %s" % pulse.call(&"faction_colour"))
	await _grab(out, "core_1_before")

	# THE REAL PATH. If objective_completed is not wired to core_pulse, this
	# shot comes back amber and the change is not done.
	if not core.has_method(&"complete"):
		print("FAIL  %s is not an objective — cannot complete it" % path)
		quit(1)
		return
	core.call(&"complete")
	for _i in 4:
		await process_frame

	var after: Color = pulse.call(&"faction_colour")
	print("   after:  %s" % after)
	await _grab(out, "core_2_after")

	# A PRINTED VERDICT AS WELL AS A PICTURE. Somebody will run this in a
	# terminal and not open the images, and a silent pair of PNGs cannot say
	# whether the hue actually moved.
	if after.is_equal_approx(Color(0.91, 0.63, 0.23)):
		print("FAIL  the core is still adversary amber after complete() — the signal is not wired")
		quit(1)
		return
	print("PASS  the core recoloured on capture")
	quit(0)


func _find_pulse(n: Node) -> Node:
	if n.has_method(&"set_faction_colour"):
		return n
	for c in n.get_children():
		var found := _find_pulse(c)
		if found != null:
			return found
	return null


func _grab(out: String, name: String) -> void:
	await process_frame
	await process_frame
	var img := get_root().get_texture().get_image()
	var p := out.path_join("%s.png" % name)
	img.save_png(p)
	print("   wrote %s" % p)


## The mean position of every lit piece, in the core's own space. Used only to
## decide which way to stand; see the note at the camera.
func _lit_centroid(core: Node) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for group in ["Lit", "Paint"]:
		for node in core.find_children(group, "", true, false):
			for child in node.get_children():
				var mi := child as MeshInstance3D
				if mi == null:
					continue
				sum += mi.position
				n += 1
	if n == 0:
		return Vector3.ZERO
	return sum / float(n)


## How tall the model actually is, from the visual AABBs of its meshes. Asked
## rather than tabled: the three core sizes are generated, and a table of their
## heights is a fourth place for 12.41 to be written down and go stale.
func _height(core: Node) -> float:
	var top := 0.0
	for mi in core.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		var ab := m.get_aabb()
		top = maxf(top, m.position.y + ab.position.y + ab.size.y)
	return maxf(top, 4.0)
