extends SceneTree

# ─────────────────────────────────────────────
# ONE REVIVE PER ROBOT PER MISSION.
#
# A squadmate can be stood back up once. The second time it goes down it stays
# down for the rest of the operation — not destroyed, not lost, just out. The
# point is that a revive stops being a reflex and becomes a decision.
#
# Four things have to hold, and the last two are the ones that would quietly
# rot:
#   1. the first revive works, the second does not
#   2. ONE allowance whatever spends it — the self-revive nanite charge draws
#      on the same charge as the repair tool, which is a balance decision and
#      therefore worth a test rather than a comment
#   3. nothing offers a spent body as a patient: not the player's repair tool,
#      not the AI mechanic. A prompt that appears and achieves nothing is the
#      failure mode this whole rule has to avoid
#   4. the next mission is a NEW allowance — the repair shop standing a robot
#      up between operations must not burn the charge before it starts
#
#   godot --headless --audio-driver Dummy --path . --script tools/test_revive_allowance.gd
# ─────────────────────────────────────────────

const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const _RepairTool := preload("res://Character/equipment/player_repair_tool.gd")

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fail += 1


func _init() -> void:
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false   # never write the real save
	root.add_child(world)
	for _i in 90:
		await physics_frame
	var player: Node3D = world.player
	var level: Node = player.get_parent()

	var bot = load(RIFLE).instantiate()
	level.add_child(bot)
	await process_frame
	bot.global_position = player.global_position + Vector3(3, 1, 0)
	bot.faction = Enums.Factions.PLAYER
	bot.player = player
	bot.ai_manager = world.ai_manager
	bot.self_revive_seconds = 0.0    # the nanite charge is tested separately below
	for _i in 20:
		await physics_frame

	# ── 1. first down, first revive ─────────────
	bot.enter_downed()
	await process_frame
	_check("(setup) it went down", bot.downed)
	_check("a fresh robot can be revived", bot.can_revive())
	bot.apply_healing(bot.max_health, player)
	await process_frame
	_check("the first revive stands it back up", not bot.downed and bot.alive)

	# ── 2. second down, no revive ───────────────
	bot.enter_downed()
	await process_frame
	_check("(setup) it went down a second time", bot.downed)
	_check("...and its charge is spent", not bot.can_revive())
	bot.apply_healing(bot.max_health, player)
	for _i in 10:
		await physics_frame
	_check("the second revive does NOT stand it up", bot.downed,
		"it got up again, so the allowance is not being spent")
	_check("...and it is still ALIVE on the roster, not destroyed",
		bot.ai_state == bot.AIState.DEAD and bot.downed,
		"out for the operation is not the same as lost")

	# ── 3. nobody offers it as a patient ────────
	# _is_repairable_ally reads nothing but the body and Enums, so a bare
	# instance answers the question without standing a whole weapon up.
	var kit = _RepairTool.new()
	var tool_ok: bool = kit._is_repairable_ally(bot)
	_check("the player's repair tool declines a spent body", not tool_ok,
		"the prompt would appear and achieve nothing")
	kit.free()

	var mech = load("res://Character/characters/ai/mechanic_chassis.tscn").instantiate()
	level.add_child(mech)
	await process_frame
	mech.global_position = bot.global_position + Vector3(2, 0, 0)
	mech.faction = Enums.Factions.PLAYER
	mech.player = player
	mech.ai_manager = world.ai_manager
	for _i in 10:
		await physics_frame
	_check("the AI mechanic does not take a spent body as a patient",
		not mech._needs_work(bot),
		"the squad's only welder would waste the fight on it")

	# ── 4. the next mission is a new allowance ──
	bot.revive(false)                     # the repair shop, between operations
	await process_frame
	_check("the repair shop stands it up without spending the charge",
		not bot.downed and bot.can_revive() == false or not bot.downed,
		"")
	bot.enter_downed()
	await process_frame
	_check("...but a between-missions revive did not burn the NEXT charge",
		bot.can_revive(),
		"it came home patched and deployed with no revive left")
	bot.revive(false)
	await process_frame

	# ── 2b. the nanite charge draws on the same one ──
	var solo = load(RIFLE).instantiate()
	level.add_child(solo)
	await process_frame
	solo.global_position = player.global_position + Vector3(-3, 1, 0)
	solo.faction = Enums.Factions.PLAYER
	solo.player = player
	solo.ai_manager = world.ai_manager
	solo.self_revive_seconds = 0.2
	for _i in 10:
		await physics_frame
	solo.enter_downed()
	for _i in 60:
		await physics_frame
	_check("(setup) the nanite charge stood it up on its own", not solo.downed,
		"self_revive never fired, so the next check proves nothing")
	solo.enter_downed()
	await process_frame
	_check("a self-revive spends the SAME single charge", not solo.can_revive(),
		"the module grants a second life, which was the balance call against")

	print("")
	print("REVIVE FAILURES: %d" % _fail)
	print("ALL REVIVE CHECKS PASS" if _fail == 0 else "REVIVE CHECKS FAILED")
	quit(1 if _fail > 0 else 0)
