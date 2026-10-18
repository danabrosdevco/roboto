extends SceneTree

# ─────────────────────────────────────────────
# WHAT A SQUAD SEES WHEN IT COMES UP OUT OF THE GROUND.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_bunker_arrival.gd -- <level> <slice node> [out dir] [yaw,yaw,...]
#
#   e.g. ... -- res://maps/hillfort_wip_level.tscn HillfortWipSlice shots 0,90
#
# shot_bunkers.gd photographs the entrance from OUTSIDE, which answers "does it
# sit on the ground properly". It cannot answer the question TERRAIN actually
# asked in HILLFORT_WIP_HANDOVER.md §4, which is about the other direction:
# §12.8 is "you come up out of the ground and turn round to hold the ground in
# front of them", and on Hillfort Redoubt the relay dish's pedestal stands 17 m
# in front of the doors. The arrival shot was the back of a 62 m dish.
#
# So this stands the camera IN the mouth at the real 1.50 m eye and looks out
# along whatever way the doors are facing. Pass several yaws and it renders one
# frame each, which is the only honest way to compare the options — a sightline
# is a thing you look at, not a thing you measure.
#
# HEADFUL, because the dummy renderer returns blank textures and a flat frame
# looks exactly like proof. Loads no campaign and writes none.
# ─────────────────────────────────────────────

## Eye height, and how far FORWARD of the host origin the camera stands. The
## kit's origin sits about a metre behind the door plane, so a couple of metres
## out puts the eye in the mouth itself — which is where a squad arrives.
const EYE_HEIGHT := 1.5
const OUT := 2.0

var _out: String = ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("FAIL  give a level path and a slice node name")
		quit(1)
		return
	var level_path := String(args[0])
	var slice_name := String(args[1])
	_out = String(args[2]) if args.size() > 2 else "res://docs/marketing/wip"
	var yaws: Array[float] = []
	if args.size() > 3:
		for part in String(args[3]).split(","):
			yaws.append(float(part))
	if yaws.is_empty():
		yaws.append(NAN)   # NAN means "whatever the slice already says"

	DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	if DisplayServer.get_name() == "headless":
		print("FAIL  headless renders nothing. Run without --headless.")
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1152, 648))
	DisplayServer.window_set_position(Vector2i(50, 40))

	for yaw in yaws:
		await _one(level_path, slice_name, yaw)
	print("ARRIVAL SHOTS DONE")
	quit()


func _one(level_path: String, slice_name: String, yaw: float) -> void:
	var packed := load(level_path) as PackedScene
	if packed == null:
		print("FAIL  no scene at %s" % level_path)
		return
	var level: Node = packed.instantiate()

	# THE YAW GOES ON BEFORE _ready, because that is when site_slice reads it
	# and builds the entrance. Setting it afterwards would rotate a host whose
	# clearance has already been measured against the old facing.
	if not is_nan(yaw):
		var slice := level.get_node_or_null(NodePath(slice_name))
		if slice == null:
			print("FAIL  %s has no %s" % [level_path, slice_name])
			return
		slice.bunker_yaw = yaw

	root.add_child(level)
	# Long enough for FuncGodot to build collision and the slice to raise the
	# entrance and seat its cores.
	for _i in 70:
		await physics_frame

	var slice2 := level.get_node_or_null(NodePath(slice_name))
	var bunker = slice2.get_node_or_null(^"SiteBunker") if slice2 != null else null
	if bunker == null:
		print("FAIL  %s built no bunker" % slice_name)
		level.queue_free()
		await process_frame
		return

	# OUT THROUGH THE DOORS. The kit is authored facing +Z, so the host's own
	# forward is the way a squad walks out — taking it off the transform rather
	# than off the yaw means this keeps working if the kit is ever re-authored.
	var at: Vector3 = (bunker as Node3D).global_position
	var fwd: Vector3 = (bunker as Node3D).global_transform.basis.z.normalized()

	# OPEN, because the doors are shut until a stand-down drives them and a
	# photograph of the inside of a shut door says nothing about a sightline.
	# Driven through the slice's own handler, so this is the same path the real
	# stand-down uses rather than a pose set for the camera.
	slice2._on_doors(1.0)
	await process_frame

	var cam := Camera3D.new()
	level.add_child(cam)
	cam.current = true
	cam.global_position = at + fwd * OUT + Vector3.UP * EYE_HEIGHT
	cam.look_at(at + fwd * 40.0 + Vector3.UP * EYE_HEIGHT)
	for _i in 4:
		await process_frame

	var img := root.get_viewport().get_texture().get_image()
	var label: String = "asbuilt" if is_nan(yaw) else "yaw%03d" % int(yaw)
	var path: String = "%s/arrival_%s_%s.png" % [_out, slice_name.to_lower(), label]
	img.save_png(path)

	# AND WHAT IS IN THE WAY, measured as well as photographed: a ray straight
	# out of the doorway at chest height, so the picture has a number beside it.
	var space := (level as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		cam.global_position, cam.global_position + fwd * 60.0)
	var hit := space.intersect_ray(q)
	var reach: String = "clear for 60m"
	if not hit.is_empty():
		reach = "blocked at %.1fm by %s" % [
			cam.global_position.distance_to(hit.position as Vector3),
			String((hit.collider as Node).name)]
	print("OK    %-10s doors face %+.2f,%+.2f  %s -> %s" % [label, fwd.x, fwd.z, reach, path])

	level.queue_free()
	await process_frame
