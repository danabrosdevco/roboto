extends SceneTree

# ─────────────────────────────────────────────
# THE SIM ARENA, WITH AN OPERATION ACTUALLY DEPLOYED ON IT.
#
#   godot --audio-driver Dummy --path . \
#       --script res://tools/shot_arena_ops.gd -- <out dir> [mission id]
#
# MUST RUN HEADFUL. --headless has no renderer: it writes flat grey and the
# flat grey looks like proof.
#
# WHY A DEPLOYED LEVEL AND NOT THE PACKED SCENE. Every objective in the
# proving ground is RAISED AT RUNTIME — TrainingCore instances the real core
# prefab or the bunker entrance kit, MissionObjective._ready frees whichever
# of the five ids this operation did not ask for, and LevelExit._ready frees
# the gate paired with the one that went. A render of maps/proving_level.tscn
# is a picture of the room, not of the mission.
#
# IT ALSO PRINTS THE GEOMETRY, because a picture of a capture point cannot
# tell you where the drone will dock — that is a number, and the number is
# the thing that has been wrong.
#
# THE PLAN VIEW IS DELIBERATELY UNFILTERED AND IS NOT A PICTURE OF THE GAME.
# It is a map, drawn from 150 m up, for deciding where things should stand.
# The eye-level shots are the ones that show how it reads: 1.50 m, the height
# the player's camera sits at, through whatever the HUD is doing.
# ─────────────────────────────────────────────

const SHOT := Vector2i(1152, 648)
const EYE := 1.5

var _out := "docs/marketing/wip"
var _mission: StringName = &"arena_3_firing_line"
var _cm: CampaignManager
var _world: World
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_mission = StringName(args[1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://") + _out)

	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = true
	master.show_mission_briefing = false
	_cm = master.find_child("CampaignManager", true, false)
	# NEVER THE PLAYER'S SAVE.
	_cm.autosave = false
	root.add_child(master)
	for _i in 90:
		await physics_frame
	_world = master._world()
	_cm.reset_campaign()
	await _deploy(_mission)

	DisplayServer.window_set_size(SHOT)
	get_root().content_scale_size = SHOT

	# ── WHAT IS ACTUALLY STANDING THERE ─────────
	print("")
	print("── %s ──" % String(_mission))
	var spawn := _spawn()
	print("player spawn        %s" % _vs(spawn))
	for o in _cm.objectives.objectives():
		if o == null or not is_instance_valid(o):
			continue
		print("objective %-22s %s" % [String(o.id), _vs((o as Node3D).global_position)])
		var hold := _find(o, "Hold")
		if hold != null:
			var dock = hold.call("dock_point") if hold.has_method("dock_point") else null
			print("   %-22s dock %s  tier %s" % ["HoldableCore", str(dock), str(hold.get("size_tier"))])
		var inter := _interactible(o)
		if inter != null:
			var at: Vector3 = (inter as Node3D).global_position
			print("   %-22s %s  %.2f m over the floor, layer %d" % [
				"press F here", _vs(at), at.y - _ground(at), inter.collision_layer])
		else:
			print("   %-22s NONE — nothing to press" % "press F here")

	# ── THE MAP, FROM ABOVE ─────────────────────
	_camera()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 130.0
	_cam.global_position = Vector3(0, 150, 20)
	_cam.rotation_degrees = Vector3(-90, 0, 0)
	await _grab("arena_plan.png")

	# ── AND FROM THE FLOOR ──────────────────────
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 75.0
	await _eye("arena_from_spawn.png", spawn + Vector3(0, EYE, 0), Vector3(0, EYE, 40))
	for o in _cm.objectives.objectives():
		if o == null or not is_instance_valid(o):
			continue
		var at: Vector3 = (o as Node3D).global_position
		# BACKED OFF ALONG THE APPROACH, which on this map is +z: a shot taken
		# standing on the thing is a shot of its base and proves nothing about
		# whether you can see it coming.
		await _eye("arena_%s.png" % String(o.id),
			Vector3(at.x, _ground(at) + EYE, at.z - 14.0), at + Vector3(0, 3, 0))
	quit(0)


func _deploy(id: StringName) -> void:
	var m = _cm.get_mission(id)
	if m == null:
		printerr("shot_arena_ops: no mission '%s'" % String(id))
		quit(1)
		return
	_cm.in_mission = false
	_cm.debug_mission = m
	_cm.select_mission(id)
	await _world.load_next_level(m.level_scene)
	_cm.on_level_loaded(_world.current_level)
	for _i in 90:
		await physics_frame


func _camera() -> void:
	if _cam != null:
		return
	_cam = Camera3D.new()
	_cam.far = 600.0
	_world.add_child(_cam)
	_cam.make_current()


func _eye(file: String, from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)
	await _grab(file)


func _grab(file: String) -> void:
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := "res://%s/%s" % [_out, file]
	var err := img.save_png(path)
	print("wrote %s" % path if err == OK else "FAILED %s (%s)" % [path, error_string(err)])


func _spawn() -> Vector3:
	var sp := _world.current_level.get_node_or_null("SpawnPoint") if _world.current_level != null else null
	return (sp as Node3D).global_position if sp != null else Vector3.ZERO


## The floor under a point, or the point's own y when nothing is under it.
func _ground(at: Vector3) -> float:
	var space := _world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 40, 0), at - Vector3(0, 40, 0))
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if hit.has("position") else at.y


func _find(n: Node, named: String) -> Node:
	if n.name == named:
		return n
	for c in n.get_children():
		var f := _find(c, named)
		if f != null:
			return f
	return null


func _interactible(n: Node) -> Interactible:
	if n is Interactible:
		return n as Interactible
	for c in n.get_children():
		var f := _interactible(c)
		if f != null:
			return f
	return null


func _vs(v: Vector3) -> String:
	return "(%7.1f, %5.1f, %7.1f)" % [v.x, v.y, v.z]
