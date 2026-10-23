extends SceneTree

# ─────────────────────────────────────────────
# PHOTOGRAPH A CAPTURE OBJECTIVE WITH ITS GARRISON STANDING ON IT.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_objective_crowd.gd -- <mission id> [out dir]
#
# REPORTED FROM PLAY ON HILLFORT: hostiles "within the capture objective" that
# could not be shot. Three structural probes disagree —
# spawn_geometry_audit.gd says no body on any map overlaps geometry or is
# enclosed, and probe_nav_vs_art.gd says no slice-built solid has walkable
# navmesh inside it. When the measurements say clean and the player says
# otherwise, the measurements are asking the wrong question, so this asks the
# only question left: WHAT DOES IT LOOK LIKE.
#
# It loads the real level, lets the slice seat its cores, deploys the real
# garrison through the real spawner, and takes one frame from the player's own
# approach height at each core.
#
# HEADFUL — the dummy renderer returns blank textures. Loads no campaign and
# writes none.
# ─────────────────────────────────────────────

## Where the camera stands relative to a core and what it aims at. Eye height
## of a robot standing 18 m off, which is the range you first see a core from
## and the range the shot that cannot connect is taken from.
const EYE := Vector3(13.0, 2.2, 13.0)
const AIM := Vector3(0.0, 2.0, 0.0)

var _out: String = ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var want: String = String(args[0]).strip_edges() if args.size() > 0 else ""
	_out = String(args[1]) if args.size() > 1 else "res://docs/marketing/wip"
	if want == "":
		print("FAIL  give a mission id")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	if DisplayServer.get_name() == "headless":
		print("FAIL  headless renders nothing. Run without --headless.")
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_position(Vector2i(50, 40))

	var m = null
	var dir := DirAccess.open("res://Campaign/missions")
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var c = load("res://Campaign/missions/" + f)
		if c != null and String(c.id) == want:
			m = c
			break
	if m == null or m.level_scene == null:
		print("FAIL  no mission '%s' with a level" % want)
		quit(1)
		return

	var level: Node = m.level_scene.instantiate()
	root.add_child(level)
	for _i in 70:
		await physics_frame

	# THE REAL SPAWNER, the same way spawn_geometry_audit does it, so the
	# bodies in the frame are the bodies the player meets.
	var spawner = preload("res://Campaign/enemy_force_spawner.gd").new()
	root.add_child(spawner)
	spawner.deploy_force(level, m)
	for _i in 30:
		await physics_frame

	var cores := _cores(level)
	if cores.is_empty():
		print("FAIL  %s built no cores to photograph" % want)
		quit(1)
		return

	var cam := Camera3D.new()
	level.add_child(cam)
	cam.current = true
	var n := 0
	for core in cores:
		var at: Vector3 = core.global_position
		cam.global_position = at + EYE
		cam.look_at(at + AIM)
		for _i in 4:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path: String = "%s/crowd_%s_%d_%s.png" % [_out, want, n, core.name]
		img.save_png(path)
		# HOW MANY BODIES ARE ACTUALLY IN THERE, printed beside the frame so a
		# clean-looking picture can be told from a core nobody is standing at.
		var near := 0
		var who: Array[String] = []
		for c in level.get_children():
			if not (c is Soldier):
				continue
			var d: float = (c as Node3D).global_position.distance_to(at)
			if d >= 6.0:
				continue
			near += 1
			var off: Vector3 = (c as Node3D).global_position - at
			who.append("%s %.1fm off at %+.1f,%+.1f,%+.1f" % [c.soldier_name, d, off.x, off.y, off.z])
		print("OK    %-22s at %v  %d body/bodies within 6m -> %s" % [core.name, at, near, path])
		for w in who:
			print("        %s" % w)
		n += 1
	print("CROWD SHOTS DONE")
	quit()


## The holdable cores the slice seated, found by script rather than by name —
## every map names them differently and the bunker is one of them.
func _cores(n: Node, out: Array[Node3D] = []) -> Array[Node3D]:
	var s = n.get_script()
	if s != null and String(s.resource_path).ends_with("holdable_core.gd"):
		var p := n.get_parent()
		if p is Node3D:
			out.append(p as Node3D)
	for c in n.get_children():
		_cores(c, out)
	return out
