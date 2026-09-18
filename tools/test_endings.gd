extends SceneTree

# ─────────────────────────────────────────────
# ENDINGS — dying on an operation, and winning the campaign.
#
# Death used to run a souls-style respawn that reset enemies GameManager had
# listed at boot, most of them long freed, and the game crashed. Now it is a
# YOU DIED screen: CONTINUE goes home as a failed mission, EXIT quits. This
# walks the real flow — deploy, die, continue — and then clears the final
# operation to check the win.
#
# Boots the real master.tscn. The campaign's autosave is off before anything
# runs, so this reads the save on this machine but never writes it.
# ─────────────────────────────────────────────

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_fails += 1


func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _init() -> void:
	Settings.path = "user://settings_endings_test.json"
	await process_frame
	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = true
	# The briefing waits for a key press, which a script cannot give it.
	master.show_mission_briefing = false
	var cm: CampaignManager = master.find_child("CampaignManager", true, false)
	cm.autosave = false
	root.add_child(master)
	for _i in 90:
		await physics_frame
	var world: World = master._world()
	var player: Player = world.player
	var hud: ObjectiveHUD = _find(root, "ObjectiveHUD")

	# ── DEPLOY ───────────────────────────────────
	var op: MissionDefinition = cm.get_mission(&"arena_1_contact")
	var clears_before: int = cm.state.clears_of(op.id)
	cm.select_mission(op.id)
	await world.load_next_level(op.level_scene)
	for _i in 30:
		await physics_frame
	_check("(setup) deployed to the arena", cm.in_mission
		and world.current_level.scene_file_path == op.level_scene.resource_path)

	# ── DIE ──────────────────────────────────────
	player.apply_damage(100000, null)
	# die() waits half a REAL second for its effects before announcing. Headless
	# frames run far faster than that, so wait on the clock, not on frames.
	await create_timer(1.0).timeout
	await process_frame
	_check("dying puts up YOU DIED", master._menu == "dead", "menu=%s" % master._menu)
	_check("...with the game paused behind it", paused)

	# ── CONTINUE ─────────────────────────────────
	master._continue_after_death()
	for _i in 60:
		await physics_frame
	_check("CONTINUE goes home", world.current_level.scene_file_path == cm.base_level.resource_path,
		world.current_level.scene_file_path)
	_check("...off the operation, unpaused", not cm.in_mission and not paused and master._menu == "")
	_check("...alive, on full health", player.alive and int(player.health) == int(player.max_health),
		"alive=%s hp=%s/%s" % [player.alive, player.health, player.max_health])
	_check("...and the mission was not counted as cleared", cm.state.clears_of(op.id) == clears_before)
	_check("...and the HUD says it failed", hud != null and hud._toast.text.contains("MISSION FAILED"),
		hud._toast.text if hud != null else "no hud")

	# ── WIN ──────────────────────────────────────
	var final_op: MissionDefinition = cm.missions.back()
	cm.state.campaign_won = false
	cm.current_mission = final_op
	cm.in_mission = true
	var result: Dictionary = cm.extract(true)
	var all_missions := cm.missions.filter(func(m): return m != null).size()
	_check("clearing the last operation wins the campaign", bool(result.get("won", false)) and cm.state.campaign_won)
	_check("...and opens every operation at the terminal", cm.available_missions().size() == all_missions,
		"%d of %d" % [cm.available_missions().size(), all_missions])
	_check("...with YOU WON queued behind MISSION COMPLETE", hud != null
		and hud._toast.text.contains("MISSION COMPLETE") and hud._toast_queue.size() == 1
		and str(hud._toast_queue[0][0]).contains("YOU WON"))
	cm.current_mission = final_op
	cm.in_mission = true
	result = cm.extract(true)
	_check("...and a second clear does not announce it again", not result.has("won"))

	master.queue_free()
	for _i in 5:
		await process_frame
	if FileAccess.file_exists("user://settings_endings_test.json"):
		DirAccess.remove_absolute("user://settings_endings_test.json")
	print("")
	print("ALL ENDINGS CHECKS PASS" if _fails == 0 else "%d ENDINGS CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
