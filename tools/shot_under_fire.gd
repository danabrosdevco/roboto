extends SceneTree

# ─────────────────────────────────────────────
# THE PLAYER, UNDER FIRE, AT EVERY RUNG OF THE SIGNAL LADDER.
#
# Same rig idea as tools/mockup_shots.gd — stage it in the real game, grab the
# real viewport — but the subject here is the HUD rather than the robots, so
# the staging is inverted: the cast exists to put rounds past the camera, and
# the thing being photographed is what is left of the readout.
#
# HEADFUL, because Godot cannot render in --headless. This takes the screen for
# as long as it runs.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_under_fire.gd -- <out dir>
#
# SIGNAL IS RE-PINNED EVERY FRAME. Integrity recovers at 0.08/s on its own, so
# a value set once and then left for a 24-frame settle has climbed a rung by
# the time the shutter opens — the first version of this photographed five
# frames of CLEAN and looked like the feature did not work.
#
# NEVER WRITES THE CAMPAIGN. autosave off before anything else, same as every
# other probe in this folder.
# ─────────────────────────────────────────────

const LEVEL := "res://maps/mutaha_wip_level.tscn"
const HOSTILE := "res://Character/characters/ai/soldier_rifle.tscn"

## Each rung, with an integrity comfortably inside it rather than on the edge.
const RUNGS := [
	{"file": "01_clean",    "sig": 1.00, "note": "full link"},
	{"file": "02_fuzzed",   "sig": 0.68, "note": "health gone"},
	{"file": "03_degraded", "sig": 0.42, "note": "state gone"},
	{"file": "04_critical", "sig": 0.18, "note": "callsign gone"},
	{"file": "05_ekill",    "sig": 0.00, "note": "squad layer gone"},
]

var _player: Node3D = null
var _hud: Node = null
var _hostiles: Array = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = String(args[0]) if args.size() > 0 else "res://docs/marketing/wip"
	DirAccess.make_dir_recursive_absolute(out_dir)

	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 90:
		await physics_frame

	_player = world.player
	if _player == null:
		push_warning("shot_under_fire: no player in world.tscn, so there is nothing to shoot at.")
		quit(1)
		return

	var level: Node = _player.get_parent()
	level.add_child(load(LEVEL).instantiate())
	for _i in 150:
		await physics_frame
	for who in PauseHold.holders():
		PauseHold.release(who)

	# Put the player somewhere with ground under it and room in front.
	var nmap: RID = _player.get_world_3d().navigation_map
	var centre: Vector3 = NavigationServer3D.map_get_closest_point(nmap, Vector3(300, 0, 250))
	_player.global_position = centre + Vector3.UP * 1.2
	for _i in 20:
		await physics_frame

	_hud = _find_hud(root)
	if _hud == null:
		push_warning("shot_under_fire: no HUD in the tree — the frames would show the level and nothing else.")

	# THE CAST EXISTS TO SHOOT AT THE CAMERA. Close enough to be in frame and
	# firing, spread so the hit arcs come from more than one bearing.
	var places := [
		Vector3(-6.0, 0.0, -13.0), Vector3(5.5, 0.0, -15.0),
		Vector3(-11.0, 0.0, -9.0), Vector3(10.0, 0.0, -10.5),
	]
	for p in places:
		var bot = load(HOSTILE).instantiate()
		level.add_child(bot)
		await process_frame
		bot.global_position = centre + p
		bot.faction = Enums.Factions.ENEMY
		bot.player = _player
		bot.ai_manager = world.ai_manager
		if world.ai_manager != null and world.ai_manager.has_method("register_enemy"):
			world.ai_manager.register_enemy(bot)
		bot.exempt_from_culling(10000.0)
		bot.health = 100000000
		bot.max_health = 100000000
		bot.look_at(_player.global_position, Vector3.UP)
		_hostiles.append(bot)

	# Face the trouble.
	var look: Vector3 = centre + Vector3(0.0, 1.0, -13.0)
	_player.look_at(look, Vector3.UP)
	# Bloodied but standing: a full health bar under fire reads as a screenshot
	# of nothing happening.
	_player.health = int(_player.max_health * 0.42)

	# Let the fight actually start, so there are tracers and flashes in the air
	# rather than four robots standing politely.
	for _i in 180:
		await physics_frame

	print("")
	print("  Shooting %d frames into %s" % [RUNGS.size(), out_dir])
	for rung in RUNGS:
		await _shoot_rung(out_dir, rung)
	print("")
	print("  Done. Thresholds: FUZZED %.2f  DEGRADED %.2f  CRITICAL %.2f  EKILL %.2f"
		% [AI.SIGNAL_FUZZED, AI.SIGNAL_DEGRADED, AI.SIGNAL_CRITICAL, AI.SIGNAL_EKILL])
	quit(0)


func _shoot_rung(out_dir: String, rung: Dictionary) -> void:
	var sig: float = float(rung["sig"])
	# Settle WITH the value pinned, so recovery cannot climb out of the rung
	# between setting it and the grab.
	for _i in 30:
		await process_frame
		_pin(sig)
	# Fresh hit arcs right before the shutter: they fade, so one registered
	# thirty frames ago is gone by the time the image is taken.
	for h in _hostiles:
		if is_instance_valid(h) and _hud != null and _hud.has_method("register_hit"):
			_hud.register_hit(7.0, h)
	for _i in 3:
		await process_frame
		_pin(sig)
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := "%s/signal_%s.png" % [out_dir, rung["file"]]
	var err := img.save_png(path)
	if err == OK:
		print("    %-26s  signal %.2f   %s" % [path.get_file(), sig, rung["note"]])
	else:
		printerr("    could not write %s (%s)" % [path, error_string(err)])


## Hold the drone at this integrity. Writing the field is not enough at the
## floor — the e-kill latch is what the readout actually reads — so the state
## is driven through the same call the game uses.
func _pin(sig: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.signal_integrity = sig
	if sig <= AI.SIGNAL_EKILL and _player.has_method("receive_signal_damage"):
		# Through the real call, so the e-kill LATCH is set. The readout reads
		# the latch, not the float, and a drone pinned at 0.0 without it is
		# still reported as merely critical.
		_player.receive_signal_damage(1.0)
		_player.lock_signal(30.0)
	if _hud != null and _hud.has_method("set_signal"):
		_hud.set_signal(sig)


func _find_hud(n: Node) -> Node:
	if n.has_method("set_signal") and n.has_method("register_hit"):
		return n
	for c in n.get_children():
		var f := _find_hud(c)
		if f != null:
			return f
	return null
