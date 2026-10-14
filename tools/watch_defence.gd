extends SceneTree

# ─────────────────────────────────────────────
# WATCH A DEFENCE HAPPEN, WITHOUT PLAYING IT.
#
# Phase 5 built the Valley Basin defence and nothing about it can be judged
# from a test: whether the garrison is in sensible places, whether three
# columns converging actually reads as three columns, whether 40 supply of
# dug-in robots is a lot or nothing. That is a thing you look at.
#
# So this is the Laboratory's trick (Managers/lab.gd) pointed at an operation
# instead of a matchup: load the map, deploy the real force through the real
# spawner, put the player in SPECTATOR mode so they cannot be shot and cannot
# interfere, and let it run.
#
#   godot --audio-driver Dummy --path . --script res://tools/watch_defence.gd
#   godot --audio-driver Dummy --path . --script res://tools/watch_defence.gd -- 32 walker
#
# The user args are the campaign to pretend you have: a compute total, then any
# number of line ids to treat as unlocked. Both change what your garrison is
# made of — that is the whole point of watching it.
#
# HEADFUL AND WINDOWED, on request. Everything else in tools/ runs headless;
# this one has to be looked at.
#
# IT NEVER WRITES THE CAMPAIGN. autosave is off and the state is built here.
# ─────────────────────────────────────────────

const DEFENCE := "res://Campaign/missions/mission_basin_2_defend.tres"
const _Gen := preload("res://Campaign/force_generator.gd")

var _world: Node = null


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var compute: int = int(args[0]) if args.size() > 0 else 12
	var unlocks: Array = []
	for i in range(1, args.size()):
		unlocks.append(StringName(String(args[i])))

	Settings.path = "user://settings_probe.json"
	await process_frame

	# ── THE WINDOW, FIRST AND EXPLICITLY ────────────────────────────────
	#
	# A --script run creates a real rendering context (you can see the GL
	# device line in the log) but it does NOT necessarily put a window where
	# you can see it: the project opens borderless fullscreen, and this was
	# setting the mode two and a half seconds in, after the whole world had
	# loaded, without ever sizing, placing or raising it. The run was working
	# and invisible.
	#
	# So: before anything is loaded, make it an ordinary window, give it a
	# size, put it on screen and bring it to the front.
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		DisplayServer.window_set_size(Vector2i(1600, 900))
		DisplayServer.window_set_position(Vector2i(100, 60))
		DisplayServer.window_set_title("WATCHING: Valley Basin — Hold")
		DisplayServer.window_move_to_foreground()
		print("  window: 1600x900 at (100, 60)")

	# ── 1X SPEED ────────────────────────────────────────────────────────
	#
	# A --script run has no frame cap: the engine runs the loop as fast as the
	# machine manages, so the fight plays at several times normal speed and
	# nothing about it can be judged. The project's own benches hit this and
	# the fix is the same one — pace the loop.
	#
	# time_scale as well as max_fps, because they are different things: max_fps
	# limits how often the loop runs, time_scale is how much game time each
	# step represents. Both have to be right or it is still not 1x.
	Engine.max_fps = 60
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60

	_world = load("res://Env/world.tscn").instantiate()
	var cm = _world.get_node("CampaignManager")
	# NEVER WRITE THE PLAYER'S CAMPAIGN.
	cm.autosave = false
	root.add_child(_world)
	for _i in 150:
		await physics_frame

	var state = cm.state
	if state == null:
		printerr("no campaign state")
		quit(1)
		return

	# ── the campaign you are pretending to have ──
	state.compute_earned = compute
	# The starting frame is always open, or the garrison has nothing at all.
	state.grant_unlock(&"soldier")
	for id in unlocks:
		state.grant_unlock(id)
	print("")
	print("  pretending: %d compute, unlocked %s" % [compute, str(unlocks)])
	print("  garrison will be worth %d supply" % _Gen.garrison_supply(state))

	# ── the map, THE WAY THE GAME LOADS ONE ─────
	#
	# world.load_next_level() is the real path: it deloads the home base,
	# instantiates the level, places the player at its spawn point and calls
	# Campaign.on_level_loaded, which is what deploys the force.
	#
	# The first cut instantiated the basin ALONGSIDE the base instead, so the
	# world had two levels in it and the player was standing in the wrong one.
	var mission = load(DEFENCE)
	cm.select_mission(&"basin_2_defend")
	_world.load_next_level(mission.level_scene)
	for _i in 300:
		await physics_frame
	var level = _world.current_level
	if level == null:
		printerr("the basin did not load")
		quit(1)
		return
	print("  in: %s" % level.name)

	# ── say how it ends ─────────────────────────
	# The thing the first fifteen-minute watch could not tell us: whether a
	# defence ever concludes. Printed loudly because it is the whole question.
	var slice = level.get_node_or_null(^"BasinSlice")
	if slice != null and slice.operation != null:
		slice.operation.operation_complete.connect(func() -> void:
			print("")
			print("  ========  HELD. The attack is spent.  ========")
			print(""))
		slice.operation.operation_failed.connect(func(why: String) -> void:
			print("")
			print("  ========  LOST: %s  ========" % why)
			print(""))
		if slice.heat != null:
			slice.heat.pool_spent.connect(func() -> void:
				print("  -- the attacker's pool is spent; clear the field to hold --"))
	else:
		push_warning("watch_defence: no BasinSlice, so there is nothing to report the end of.")


	# ── the ghost ───────────────────────────────
	# The Laboratory's own trick: spectator mode so the watcher cannot be shot
	# and cannot shoot, and damage scaled to nothing so a stray frag does not
	# end the thing with a YOU DIED screen.
	var p = _world.player if "player" in _world else null
	if p != null:
		if "spectator_mode" in p and not p.spectator_mode:
			p._toggle_spectator()
		if "damage_taken_scale" in p:
			p.damage_taken_scale = 0.0
		var anchor := _tagged(level, &"obj_basin_anchor")
		if anchor != Vector3.ZERO:
			# Above and back from the anchor, looking down into the bowl, so
			# all three approaches are in frame at once.
			p.global_position = anchor + Vector3(-30.0, 26.0, -30.0)
		print("  you are a ghost: fly with the usual controls, nothing can hit you")
	else:
		push_warning("watch_defence: no player, so there is nobody to watch through.")

	_report()
	# Hands off from here. Quit it yourself when you have seen enough.


## Count what is actually standing, by side, every few seconds.
func _report() -> void:
	var t := Timer.new()
	t.wait_time = 5.0
	t.autostart = true
	root.add_child(t)
	t.timeout.connect(func() -> void:
		var mine := 0
		var theirs := 0
		for ai in get_nodes_in_group("enemies"):
			if ai == null or not is_instance_valid(ai):
				continue
			if "alive" in ai and not ai.alive:
				continue
			if "faction" in ai and Enums.are_hostile(Enums.Factions.PLAYER, ai.faction):
				theirs += 1
			else:
				mine += 1
		print("  [%4.0fs] garrison %d   attackers %d" % [
			Time.get_ticks_msec() / 1000.0, mine, theirs]))


func _tagged(n: Node, tag: StringName) -> Vector3:
	if "tag" in n and n.tag == tag and n is Node3D:
		return (n as Node3D).global_position
	for c in n.get_children():
		var f := _tagged(c, tag)
		if f != Vector3.ZERO:
			return f
	return Vector3.ZERO
