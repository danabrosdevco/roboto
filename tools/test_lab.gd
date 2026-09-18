extends SceneTree

# ─────────────────────────────────────────────
# LABORATORY — does a plan run from start to results, without touching the game?
#
# Boots the real master.tscn in lab mode with a small plan (two rifles against
# a chaser, twice, at 4x speed), waits for the results screen, and checks the
# fights ran, were scored, and wrote a report — and that the campaign never
# noticed: no deploy, no mission, nothing earned.
#
# Records into user://lab_test and deletes it afterwards. Campaign autosave is
# off.
# ─────────────────────────────────────────────

const _Analytics := preload("res://Managers/analytics.gd")
const _Plan := preload("res://Campaign/lab/lab_plan.gd")
const _Matchup := preload("res://Campaign/lab/lab_matchup.gd")
const TEST_DIR := "user://lab_test"

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_fails += 1


func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_wipe(dir + "/" + sub)
	for file in d.get_files():
		d.remove(file)
	DirAccess.remove_absolute(dir)


func _init() -> void:
	Settings.path = "user://settings_lab_test.json"
	_wipe(TEST_DIR)
	_Analytics.force_enable = true
	_Analytics.dir_override = TEST_DIR
	await process_frame

	var rifle: ChassisDefinition = load("res://Campaign/chassis/chassis_rifleman.tres")
	var chaser: ChassisDefinition = load("res://Campaign/chassis/chassis_chaser.tres")
	var m = _Matchup.new()
	m.label = "2 rifles vs 1 chaser"
	m.allies = [rifle, rifle] as Array[ChassisDefinition]
	m.ally_order = _Matchup.Order.ADVANCE
	m.hostiles = [chaser] as Array[ChassisDefinition]
	m.hostile_order = _Matchup.Order.ADVANCE
	m.distance = 15.0
	m.repeats = 2
	m.time_limit = 45.0
	m.swap_sides = true
	var plan = _Plan.new()
	plan.title = "Lab test"
	plan.matchups = [m] as Array[Resource]
	plan.speed = 4.0

	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.lab_mode = true
	master.lab_plan = plan
	var cm: CampaignManager = master.find_child("CampaignManager", true, false)
	cm.autosave = false
	root.add_child(master)
	var earned_before: int = -1
	for _i in 30:
		await process_frame
	if cm.state != null:
		earned_before = cm.state.earned

	# Wait for the results screen, on the clock: fights run in game time.
	var waited := 0.0
	while master._menu != "lab" and waited < 90.0:
		await create_timer(0.5).timeout
		waited += 0.5
	var lab = master._lab
	_check("the plan runs to the results screen", master._menu == "lab", "waited %.0fs, menu=%s" % [waited, master._menu])
	if lab == null:
		quit(1)
		return
	var world: World = master._world()
	_check("the fights are in the arena", world.current_level.scene_file_path == "res://maps/arena_level.tscn",
		world.current_level.scene_file_path)
	_check("the player watches as a ghost, out of harm's way", world.player.spectator_mode
		and world.player.damage_taken_scale == 0.0)
	var runs: Array = lab.results[0]["runs"] if not lab.results.is_empty() else []
	_check("every run was fought", runs.size() == 2, str(runs.size()))
	_check("...and each has an outcome", runs.all(func(r): return ["ally", "hostile", "draw"].has(r["outcome"])),
		str(runs.map(func(r): return r["outcome"])))
	_check("...and was scored from the fight itself", runs.any(func(r): return int(r["a_dmg"]) + int(r["h_dmg"]) > 0),
		str(runs))
	_check("...shots included", runs.any(func(r): return int(r["a_shots"]) > 0))
	var wiped := true
	for r in runs:
		if r["outcome"] == "ally" and int(r["h_alive"]) != 0:
			wiped = false
		if r["outcome"] == "hostile" and int(r["a_alive"]) != 0:
			wiped = false
	_check("a run that was won ends with the loser wiped out", wiped)
	var rows: Array = lab.summary()
	_check("the summary adds up", rows.size() == 1 and int(rows[0]["ally_wins"]) + int(rows[0]["hostile_wins"])
		+ int(rows[0]["draws"]) == 2, str(rows))
	var report := FileAccess.get_file_as_string(lab.report_path)
	_check("lab_report.md is written", report.contains("## Results") and report.contains("## By chassis")
		and report.contains("2 rifles vs 1 chaser"), lab.report_path)
	_check("game speed is back to normal", is_equal_approx(Engine.time_scale, 1.0))
	_check("the campaign never noticed: no mission, nothing earned",
		not cm.in_mission and cm.state != null and cm.state.earned == earned_before)
	var leftover := 0
	for n in get_nodes_in_group("enemies"):
		if n is Soldier and is_instance_valid(n) and not n.is_queued_for_deletion():
			leftover += 1
	_check("the arena is cleared after the last fight", leftover == 0, str(leftover))

	master.queue_free()
	for _i in 5:
		await process_frame
	_Analytics.force_enable = false
	_Analytics.dir_override = ""
	_wipe(TEST_DIR)
	if FileAccess.file_exists("user://settings_lab_test.json"):
		DirAccess.remove_absolute("user://settings_lab_test.json")
	print("")
	print("ALL LAB CHECKS PASS" if _fails == 0 else "%d LAB CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
