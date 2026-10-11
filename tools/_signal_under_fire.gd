extends SceneTree

# ─────────────────────────────────────────────
# HOW FAST DOES BEING SHOT AT TAKE YOUR LINK DOWN?
#
# shot_signal_ramp.gd asked this and got it wrong: it measured AFTER four
# seconds of incoming fire, found the signal flat at 0.005, and reported that
# suppression does not affect it. The signal had already hit the floor before
# the window opened.
#
# This logs from the first frame of contact, headless, so the curve is the
# whole curve. It matters for balance rather than for the feature: if four
# rifles e-kill the player's command link in a few seconds, the signal veil is
# not a rare dramatic moment, it is the normal condition of a firefight.
#
#   godot --headless --audio-driver Dummy --path . --script tools/_signal_under_fire.gd
# ─────────────────────────────────────────────

const LEVEL := "res://maps/mutaha_wip_level.tscn"
const HOSTILE := "res://Character/characters/ai/soldier_rifle.tscn"


func _init() -> void:
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 90:
		await physics_frame
	var player: Node3D = world.player
	var level: Node = player.get_parent()
	level.add_child(load(LEVEL).instantiate())
	for _i in 150:
		await physics_frame
	for who in PauseHold.holders():
		PauseHold.release(who)

	var nmap: RID = player.get_world_3d().navigation_map
	var centre: Vector3 = NavigationServer3D.map_get_closest_point(nmap, Vector3(300, 0, 250))
	player.global_position = centre + Vector3.UP * 1.2
	for _i in 30:
		await physics_frame

	# Topped up every frame rather than given a huge max_health: the drone must
	# not die, but inflating max_health turns its own health bar into a strip
	# across the screen and changes what the HUD looks like.
	var cap: int = player.max_health
	player.health = cap
	player.signal_integrity = 1.0

	var bots: Array = []
	for p in [Vector3(-6, 0, -13), Vector3(5.5, 0, -15), Vector3(-11, 0, -9), Vector3(10, 0, -10.5)]:
		var b = load(HOSTILE).instantiate()
		level.add_child(b)
		await process_frame
		b.global_position = centre + p
		b.faction = Enums.Factions.ENEMY
		b.player = player
		b.ai_manager = world.ai_manager
		if world.ai_manager != null and world.ai_manager.has_method("register_enemy"):
			world.ai_manager.register_enemy(b)
		b.exempt_from_culling(10000.0)
		b.health = 100000000
		b.max_health = 100000000
		bots.append(b)
	player.look_at(centre + Vector3(0, 1, -13), Vector3.UP)

	# Reset the clock the moment the cast is up: everything before this is
	# staging, and charging it to the firefight is how the last one went wrong.
	player.signal_integrity = 1.0
	print("")
	print("  FOUR RIFLES ON ONE DRONE. Signal from the first frame of contact.")
	print("  %6s  %8s   %s" % ["t", "signal", "rung"])
	var t := 0.0
	var floor_at := -1.0
	for i in 1200:                     # 20 seconds
		await physics_frame
		t += 1.0 / 60.0
		player.health = cap            # never dies, so this is only about signal
		var s: float = float(player.signal_integrity)
		if floor_at < 0.0 and s <= AI.SIGNAL_EKILL:
			floor_at = t
		if i % 30 == 0:
			print("  %5.1fs  %8.3f   %s" % [t, s, _rung(s)])
	print("")
	if floor_at >= 0.0:
		print("  Reached e-kill in %.1f s of being shot at." % floor_at)
	else:
		print("  Never reached e-kill in 20 s. Lowest rung: %s" % _rung(float(player.signal_integrity)))
	print("")
	quit(0)


func _rung(s: float) -> String:
	if s <= AI.SIGNAL_EKILL:
		return "EKILL      squad layer gone"
	if s <= AI.SIGNAL_CRITICAL:
		return "CRITICAL   callsign gone"
	if s <= AI.SIGNAL_DEGRADED:
		return "DEGRADED   state gone"
	if s <= AI.SIGNAL_FUZZED:
		return "FUZZED     health gone"
	return "CLEAN"
