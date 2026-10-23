extends SceneTree

# ─────────────────────────────────────────────
# JAMMER DEAD ZONES — the mockup.
#
# Four frames of walking into one:
#   01  from outside, at range. A column you can see and go around.
#   02  at the boundary. Integrity has started to go.
#   03  inside. Roster veiled, contact marks refused, orders refused.
#   04  back out, five seconds later. It comes back, slowly.
#
# It prints integrity and signal state at each step, and asks the commander
# whether it would accept an order — which is the thing the player actually
# loses.
#
# HEADFUL, because Godot cannot render in --headless. Takes the screen.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_jammer.gd -- <out dir>
# ─────────────────────────────────────────────

const LEVEL := "res://maps/mutaha_wip_level.tscn"
const JAMMER := "res://Env/world_objects/jammer_field.gd"
const STATES := ["CLEAN", "FUZZED", "DEGRADED", "CRITICAL", "EKILL"]

var _player: Node3D = null
var _cmd: Node = null
var _jammer: Area3D = null


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = String(args[0]) if args.size() > 0 else "res://docs/marketing/wip"
	DirAccess.make_dir_recursive_absolute(out_dir)

	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false   # never write the real save
	root.add_child(world)
	for _i in 90:
		await physics_frame
	_player = world.player
	var level: Node = _player.get_parent()
	level.add_child(load(LEVEL).instantiate())
	for _i in 150:
		await physics_frame
	for who in PauseHold.holders():
		PauseHold.release(who)

	var nmap: RID = _player.get_world_3d().navigation_map
	var centre: Vector3 = NavigationServer3D.map_get_closest_point(nmap, Vector3(300, 0, 250))
	_cmd = _player.get("commander")

	# The emitter's footprint, 34 m up the sightline from where the player
	# stands, so frame 01 is genuinely a view of it from outside.
	var at: Vector3 = NavigationServer3D.map_get_closest_point(nmap, centre + Vector3(0, 0, -34))
	_jammer = load(JAMMER).new()
	_jammer.radius = 18.0
	_jammer.height = 16.0
	level.add_child(_jammer)
	_jammer.global_position = at
	await physics_frame

	_player.global_position = centre + Vector3.UP * 1.2
	_player.look_at(at + Vector3(0.0, 4.0, 0.0), Vector3.UP)
	for _i in 60:
		await physics_frame

	print("")
	print("    jammer at %.0f m, radius %.0f m, drain %.2f/s"
		% [_player.global_position.distance_to(at), _jammer.radius, _jammer.drain_per_second])
	await _step("%s/jammer_01_outside.png" % out_dir, "outside, at range — a column you can walk around")

	# ── 02 the boundary ─────────────────────────
	_player.global_position = at + Vector3(0, 1.2, 1) * 1.0 + Vector3(0.0, 0.0, _jammer.radius - 1.0)
	for _i in 40:
		await physics_frame
	await _step("%s/jammer_02_boundary.png" % out_dir, "one metre inside the wall")

	# ── 03 well inside ──────────────────────────
	_player.global_position = at + Vector3.UP * 1.2
	for _i in 150:
		await physics_frame
	await _step("%s/jammer_03_inside.png" % out_dir, "in the middle of it")

	# ── 04 back out ─────────────────────────────
	_player.global_position = centre + Vector3.UP * 1.2
	for _i in 300:
		await physics_frame
	await _step("%s/jammer_04_recovered.png" % out_dir, "five seconds back outside")

	print("")
	quit(0)


## Photograph, then print what the signal layer is doing — integrity, the
## state it maps to, and whether the squad would take an order. The last one
## is the only number that matters to a player: everything else is bookkeeping
## behind "can I still command".
func _step(path: String, note: String) -> void:
	await _grab(path, note)
	var s: int = int(_player.get_signal_state())
	var orders: String = "refused"
	if _cmd != null and _cmd.has_method("link_down"):
		orders = "refused" if _cmd.link_down() else "accepted"
	print("      integrity %.2f   %-9s   orders %s"
		% [_player.signal_integrity, STATES[s], orders])


func _grab(path: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var err := img.save_png(path)
	if err == OK:
		print("    %-28s  %s" % [path.get_file(), note])
	else:
		printerr("    could not write %s (%s)" % [path, error_string(err)])
