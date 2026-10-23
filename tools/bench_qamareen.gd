extends SceneTree
# ─────────────────────────────────────────────
# WHAT IS QAMAREEN ACTUALLY SPENDING ITS FRAME ON?
#
# Reported slow after the garrison went from 142 robots to 215 and patrolling
# hostiles were exempted from distance culling. Two candidates, and guessing
# between them is how you optimise the wrong one. This counts how many robots
# are AWAKE (not AIState.PASSIVE) and times the physics frame.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/bench_qamareen.gd
# ─────────────────────────────────────────────

func _find(n: Node, cls: String) -> Node:
	var s: Script = n.get_script() as Script
	if s != null and s.get_global_name() == StringName(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null

func _all(n: Node, cls: String, out: Array) -> void:
	var s: Script = n.get_script() as Script
	if s != null and s.get_global_name() == StringName(cls):
		out.append(n)
	for c in n.get_children():
		_all(c, cls, out)


func _init() -> void:
	# PACE THE LOOP. Headless runs _process as fast as it can, and Squad ticks
	# six functions in _process — 66 squads of them on Qamareen. Unthrottled,
	# that saturates the core and every physics number measured beside it is
	# really measuring _process starving it. At 60 fps the frame has the same
	# shape it has in the game.
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 120:
		await physics_frame

	var cm: Node = world.get_node("CampaignManager")
	var mission = null
	for m in cm.missions:
		if m != null and str(m.id) == "mutaha_2_city":
			mission = m
	# --bare strips the enemy force, to separate the level's own physics cost
	# from what the garrison adds.
	if OS.get_cmdline_user_args().has("--bare"):
		# .clear(), not = []: enemy_force is Array[EnemySquadSpec] and a plain
		# untyped array is refused outright.
		mission.enemy_force.clear()
		print("  (bare run: enemy force stripped)")
	cm.state.selected_mission_id = mission.id
	_find(root, "World").load_next_level(mission.level_scene, true)
	for _i in 420:
		await physics_frame

	var bots: Array = []
	_all(root, "Soldier", bots)
	var rovers: Array = []
	_all(root, "Rover", rovers)
	bots.append_array(rovers)

	# PASSIVE is what the cull sets. Anything else is a robot running a brain.
	var awake := 0
	var awake_patrol := 0
	var hostile := 0
	for b in bots:
		if b.get("faction") != Enums.Factions.ENEMY:
			continue
		hostile += 1
		if int(b.get("ai_state")) != 5:   # 5 = AIState.PASSIVE, which is what the cull sets
			awake += 1
			if bool(b.get("on_patrol")):
				awake_patrol += 1
	var patrollers := 0
	for b in bots:
		if bool(b.get("on_patrol")):
			patrollers += 1

	# --freeze: switch _physics_process OFF on every culled robot, rather than
	# letting them early-return out of it. If the cost collapses, what we are
	# paying for is the callback itself across 186 nodes — which is what
	# CLAUDE.md already asks for ("disable it when idle") and the cull does not do.
	if OS.get_cmdline_user_args().has("--freeze"):
		var froze := 0
		for b in bots:
			if b.get("faction") == Enums.Factions.ENEMY and int(b.get("ai_state")) == 5:
				b.set_physics_process(false)
				froze += 1
		print("  froze _physics_process on %d culled robots" % froze)
		for _i in 60:
			await physics_frame

	# CPU SPENT IN _physics_process, not wall clock between frames. Headless
	# Godot still paces physics to 60 Hz, so timing the await loop measures the
	# 16.6 ms interval and nothing about the work — which is exactly the wrong
	# answer, and a confident-looking one.
	# Zeroed here so the squad figure describes the measured window, not the
	# deploy burst that precedes it.
	Squad._squad_spent_us = 0
	Squad._squad_ticks = 0
	var ms := 0.0
	for _i in 600:
		await physics_frame
		ms += float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	ms /= 600.0

	print("")
	print("  hostiles in level        %d" % hostile)
	print("  on a patrol route        %d" % patrollers)
	print("  AWAKE (brain running)    %d   of which patrolling %d" % [awake, awake_patrol])
	print("  culled                   %d" % (hostile - awake))
	print("  physics CPU              %.2f ms per frame, averaged over 600" % ms)
	# THE SQUAD LAYER, which runs in _process and is therefore absent from the
	# physics figure above and from every other measurement on this project.
	print("  squad layer              %.2f ms per frame   (%d Squad ticks over 600 frames)" % [
		float(Squad._squad_spent_us) / 1000.0 / 600.0, Squad._squad_ticks])

	# THE CHEAP-OUT IN _apply_motion ONLY FIRES FOR A SETTLED BODY: PASSIVE,
	# on the floor, and velocity under 0.01. A culled robot that never settles
	# runs a full move_and_slide every frame for the whole mission, and there is
	# nothing in the script profile to show for it.
	var settled := 0
	var unsettled := 0
	# AND HOW MANY OF THEM ARE ACTUALLY SWITCHED OFF. The cull now takes the
	# callback away as well as the brain (Enemy.cull_frozen), and the whole
	# saving depends on that landing for every culled robot rather than most of
	# them — a figure below `culled` means something in _can_freeze_for_cull is
	# refusing, and the ms number above is measuring a partial fix.
	var frozen := 0
	for b in bots:
		if b.get("faction") != Enums.Factions.ENEMY:
			continue
		if int(b.get("ai_state")) != 5:
			continue
		if bool(b.get("cull_frozen")) and not bool(b.call("is_physics_processing")):
			frozen += 1
		if bool(b.call("is_on_floor")) and (b.get("velocity") as Vector3).length_squared() < 0.01:
			settled += 1
		else:
			unsettled += 1
	print("  culled AND settled       %d  (cheap: skips move_and_slide)" % settled)
	print("  culled but NOT settled   %d  (pays a full move_and_slide every frame)" % unsettled)
	print("  culled AND frozen        %d  (no _physics_process call at all)" % frozen)
	print("  jolt active bodies       %d" % int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)))
	print("  total collision pairs    %d" % int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
	quit(0)
