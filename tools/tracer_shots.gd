extends SceneTree

# ─────────────────────────────────────────────
# PHOTOGRAPH BOTH TRACER COLOURS THROUGH THE SIGNAL FILTER.
#
#   godot --audio-driver Dummy --path . --script res://tools/tracer_shots.gd -- <out dir>
#
# IT NEEDS A WINDOW. signal_filter samples the screen texture, so there is
# nothing to sample headless — run it WITHOUT --headless.
#
# WHY THIS EXISTS RATHER THAN TRUSTING THE HEX VALUES. The filter subsamples
# chroma on a coarse grid and quantises it to five levels, so two colours that
# are plainly different in an image editor can land on the same quantised value
# on screen. Tracers are also near-white hot down their centre, which leaves
# little chroma to survive the rounding in the first place. Whether yellow and
# red read as two different things here is a question about the renderer, not
# about the palette, and the only way to answer it is to look.
#
# Shoots the same frame three ways: filtered (what the player sees), unfiltered
# (what was authored), and at a distance (where the tracer is only a few pixels
# wide and the quantiser has the least to work with).
# ─────────────────────────────────────────────

const WORLD := "res://Env/world.tscn"
const TRACER := "res://Character/weapon/tracer.tscn"

var _out: String = "."
var _world: Node = null


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("tracer_shots: signal_filter samples the screen, so this needs a window.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 and args[0].strip_edges() != "" else "."
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))

	_world = load(WORLD).instantiate()
	root.add_child(_world)
	for _i in 40:
		await process_frame

	await _volley(10.0, "close")
	await _volley(35.0, "far")
	await _unfiltered()

	print("tracer_shots: written to %s" % ProjectSettings.globalize_path(_out))
	quit(0)


## A rank of tracers across the view at `depth` metres: hostile on the left,
## friendly on the right, so the two are in one frame under one exposure.
func _volley(depth: float, label: String) -> void:
	var cam := root.get_camera_3d()
	if cam == null:
		printerr("tracer_shots: no camera.")
		return
	var scene: PackedScene = load(TRACER)
	var basis := cam.global_transform.basis
	var fwd: Vector3 = -basis.z
	var right: Vector3 = basis.x
	var up: Vector3 = basis.y
	var origin: Vector3 = cam.global_position

	# Four of each, stacked vertically so a single quantiser cell cannot be
	# blamed for one of them looking wrong.
	for i in 4:
		var y: float = 1.2 - float(i) * 0.8
		_place(scene, origin + fwd * depth + right * -4.0 + up * y,
				origin + fwd * depth + right * -1.0 + up * y, Enums.Factions.ENEMY)
		_place(scene, origin + fwd * depth + right * 1.0 + up * y,
				origin + fwd * depth + right * 4.0 + up * y, Enums.Factions.PLAYER)
	await _shoot("tracers_%s" % label)
	_clear()


## The same volley with the filter switched off, as the control. If the two
## colours separate here and not in the filtered shot, the filter is the
## problem and no amount of palette work fixes it.
func _unfiltered() -> void:
	var hud := _world.get_node_or_null("HUD")
	var filter := hud.get_node_or_null("SignalFilter") if hud != null else null
	if filter == null:
		printerr("tracer_shots: no SignalFilter to switch off.")
		return
	filter.visible = false
	await _volley(10.0, "close_unfiltered")
	filter.visible = true


func _place(scene: PackedScene, from: Vector3, to: Vector3, faction) -> void:
	var t: Node = scene.instantiate()
	_world.add_child(t)
	if t.has_method("set_side"):
		t.set_side(faction)
	# Parked, not launched: launch() starts it travelling and it frees itself
	# the moment it arrives, which is a race against the shutter.
	(t as Node3D).global_position = from
	(t as Node3D).look_at(to, Vector3.UP)
	t.set_physics_process(false)
	t.set_meta(&"shot_prop", true)


func _clear() -> void:
	for n in _world.get_children():
		if n.has_meta(&"shot_prop"):
			n.free()


func _shoot(name: String) -> void:
	for _i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var file := "%s/%s.png" % [_out, name]
	var err := img.save_png(file)
	if err != OK:
		printerr("tracer_shots: could not write %s (%s)" % [file, error_string(err)])
	else:
		print("  %s" % file.get_file())
