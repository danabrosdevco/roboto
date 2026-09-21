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


func _find_named(n: Node, node_name: String) -> Node:
	if n.name == node_name:
		return n
	for c in n.get_children():
		var f := _find_named(c, node_name)
		if f != null:
			return f
	return null


# Whether any label or button under `n` says `text`.
func _says(n: Node, text: String) -> bool:
	if (n is Label and (n as Label).text.contains(text)) or (n is Button and (n as Button).text.contains(text)):
		return true
	for c in n.get_children():
		if _says(c, text):
			return true
	return false


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

	# ── DEPLOY ───────────────────────────────────
	var op: MissionDefinition = cm.get_mission(&"arena_1_contact")
	var clears_before: int = cm.state.clears_of(op.id)
	cm.select_mission(op.id)
	await world.load_next_level(op.level_scene)
	for _i in 30:
		await physics_frame
	_check("(setup) deployed to the arena", cm.in_mission
		and world.current_level.scene_file_path == op.level_scene.resource_path)

	# ── SOMETHING TO LOSE ────────────────────────
	# The rollback needs damage to undo. This operation deploys no squad
	# (squad_size 0), so rather than lose a body it stages what losing one does
	# to the campaign — a record written off and the wallet moved — which is
	# exactly the state a real extraction would leave behind. What proves the
	# rewind is the field-for-field comparison further down, not this staging.
	var before_deploy := JSON.stringify(cm.state.to_dict())
	var before_cash: int = cm.state.available()
	var victim: SoldierRecord = cm.state.roster[0] if not cm.state.roster.is_empty() else null
	if victim != null:
		victim.status = SoldierRecord.Status.DESTROYED
		victim.damage = victim.max_health
		victim.confirmed_kills += 7
	cm.state.award(500)
	for _i in 10:
		await physics_frame
	_check("(setup) a squadmate is written off and 500 came in",
		victim != null and victim.status == SoldierRecord.Status.DESTROYED
		and cm.state.available() == before_cash + 500,
		"victim=%s cash=%d" % [victim, cm.state.available()])

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
	# Home, and the debrief is up over it: MISSION FAILED, paused until read.
	var debrief = _find_named(root, "DebriefScreen")
	_check("home to the debrief, saying the mission failed", debrief != null and debrief.visible
		and _says(debrief, "MISSION FAILED"), "debrief=%s" % debrief)
	_check("...with the game paused behind it", paused)
	# Read while it is still up; the checks that use it come after it closes.
	var said_voided: bool = debrief != null and _says(debrief, "RUN VOIDED")
	if debrief != null:
		debrief.close()
	await process_frame
	_check("...and CONTINUE lets you go, off the operation", not cm.in_mission and not paused and master._menu == "")
	_check("...alive, on full health", player.alive and int(player.health) == int(player.max_health),
		"alive=%s hp=%s/%s" % [player.alive, player.health, player.max_health])
	_check("...and the mission was not counted as cleared", cm.state.clears_of(op.id) == clears_before)

	# ── THE RUN IS VOIDED ────────────────────────
	# Dying costs the time, not the squad: the campaign goes back to the
	# dictionary taken at deployment. The DEBRIEF still reports the wreck,
	# because that is what happened out there — it just did not stick.
	var written_off := 0
	for r in cm.state.roster:
		if r != null and r.status == SoldierRecord.Status.DESTROYED:
			written_off += 1
	_check("dying voids the run: nobody is written off", written_off == 0,
		"%d destroyed" % written_off)
	_check("...and the stores are as they were at deployment", cm.state.available() == before_cash,
		"%d, deployed with %d" % [cm.state.available(), before_cash])
	# Everything but the two fields that legitimately change on the way home:
	# the selection, which extract() clears, and the lessons, which are marked
	# when you walk back in and are not part of the run's ledger.
	var after := cm.state.to_dict()
	var before_dict: Dictionary = JSON.parse_string(before_deploy)
	for changes_at_home in ["selected_mission_id", "lessons_seen"]:
		after.erase(changes_at_home)
		before_dict.erase(changes_at_home)
	_check("...the whole campaign is what deployed, field for field",
		JSON.stringify(after) == JSON.stringify(before_dict))
	_check("...and the debrief said so rather than showing empty payouts", said_voided)

	# The rewind copies fields across by hand. This is what catches one being
	# missed when a field is added to to_dict() later.
	var snap := cm.state.to_dict()
	cm.state.award(777)
	cm.state.squad_name = "SCRATCH"
	cm.state.restore_from(snap)
	_check("restore_from puts a campaign back exactly as it was",
		JSON.stringify(cm.state.to_dict()) == JSON.stringify(snap),
		"squad_name=%s" % cm.state.squad_name)

	# ── WIN ──────────────────────────────────────
	var final_op: MissionDefinition = cm.missions.back()
	cm.state.campaign_won = false
	# COMPUTE: a first clear pays the mission's, and a completed hidden
	# objective pays its own — each once per campaign. The save on this machine
	# may have cleared the last op already, so make this its first clear.
	cm.state.completed_missions.erase(final_op.id)
	cm.state.compute_claimed.erase(CampaignState.clear_compute_key(final_op.id))
	cm.state.compute_claimed.erase("%s:compute_test_bonus" % final_op.id)
	var bonus := MissionObjective.new()
	bonus.id = &"compute_test_bonus"
	bonus.optional = true
	bonus.compute_reward = 1
	bonus.completed = true
	cm.objectives._objectives.append(bonus)
	var compute_before: int = cm.state.compute
	cm.current_mission = final_op
	cm.in_mission = true
	var result: Dictionary = cm.extract(true)
	var paid: int = final_op.compute_reward + 1
	_check("the last op pays compute for its first clear and the hidden objective",
		int(result.get("compute", 0)) == paid and cm.state.compute == compute_before + paid,
		"result=%s compute %d -> %d, expected +%d" % [result.get("compute"), compute_before, cm.state.compute, paid])
	var all_missions := cm.missions.filter(func(m): return m != null).size()
	_check("clearing the last operation wins the campaign", bool(result.get("won", false)) and cm.state.campaign_won)
	_check("...and opens every operation at the terminal", cm.available_missions().size() == all_missions,
		"%d of %d" % [cm.available_missions().size(), all_missions])
	cm.on_returned_to_base()
	await process_frame
	_check("back at base, the debrief says MISSION COMPLETE", debrief != null and debrief.visible
		and _says(debrief, "MISSION COMPLETE"))
	_check("...shows the compute it paid", debrief != null and _says(debrief, "+%d" % paid))
	_check("...with a card for you", debrief != null and _says(debrief, "YOU"))
	# The end of the campaign is its own screen now, after the results and
	# after anything the operation unlocked: CONTINUE walks them.
	var walked := 0
	while debrief != null and debrief.visible and not _says(debrief, "CAMPAIGN WON") and walked < 4:
		debrief.advance()
		await process_frame
		walked += 1
	_check("...and CONTINUE reaches a screen that says the campaign is won",
		debrief != null and debrief.visible and _says(debrief, "CAMPAIGN WON"),
		"after %d presses" % walked)
	_check("...which tells you the terminal is open", debrief != null and _says(debrief, "TERMINAL"))
	if debrief != null:
		debrief.close()
	cm.current_mission = final_op
	cm.in_mission = true
	result = cm.extract(true)
	_check("...and a second clear does not announce it again", not result.has("won"))
	_check("...nor pay its compute again, mission or objective", int(result.get("compute", -1)) == 0,
		"compute=%s" % result.get("compute"))
	cm.objectives._objectives.erase(bonus)
	bonus.free()

	master.queue_free()
	for _i in 5:
		await process_frame
	if FileAccess.file_exists("user://settings_endings_test.json"):
		DirAccess.remove_absolute("user://settings_endings_test.json")
	print("")
	print("ALL ENDINGS CHECKS PASS" if _fails == 0 else "%d ENDINGS CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
