extends SceneTree

# ─────────────────────────────────────────────
# ANALYTICS — does a real mission leave a record that answers the questions?
#
# Boots the real game, deploys to the arena, and plays a short, rigged fight
# through the same entry points the game uses: the player lands a shot on an
# enemy, an enemy hits the player, the squad is ordered to ADVANCE, and the
# player dies. Then reads events.jsonl and report.md back.
#
# Records into user://analytics_test, never into the folder real playtest data
# is collected from, and deletes it afterwards. Campaign autosave is off.
# ─────────────────────────────────────────────

const _Analytics := preload("res://Managers/analytics.gd")
const _Report := preload("res://Managers/analytics_report.gd")
const TEST_DIR := "user://analytics_test"

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_fails += 1


func _events_in(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var e = JSON.parse_string(line)
		if typeof(e) == TYPE_DICTIONARY:
			out.append(e)
	return out


func _of(events: Array, ev: String) -> Array:
	return events.filter(func(e): return e.get("ev", "") == ev)


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
	Settings.path = "user://settings_analytics_test.json"
	_wipe(TEST_DIR)
	_Analytics.force_enable = true
	_Analytics.dir_override = TEST_DIR
	await process_frame
	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = true
	master.show_mission_briefing = false
	var cm: CampaignManager = master.find_child("CampaignManager", true, false)
	cm.autosave = false
	root.add_child(master)
	for _i in 90:
		await physics_frame
	var world: World = master._world()
	var player: Player = world.player
	var recorder = master.get_node("Analytics")

	# ── DEPLOY ───────────────────────────────────
	# Firing Line: two allies go in, so there is a squad to order and to score.
	var op: MissionDefinition = cm.get_mission(&"arena_3_firing_line")
	cm.select_mission(op.id)
	await world.load_next_level(op.level_scene)
	for _i in 30:
		await physics_frame
	var enemies: Array = []
	for n in get_nodes_in_group("enemies"):
		if n is Soldier and Enums.are_hostile(Enums.Factions.PLAYER, n.faction) and n.alive:
			enemies.append(n)
	_check("(setup) deployed with enemies on the map", cm.in_mission and enemies.size() >= 2, str(enemies.size()))
	if enemies.size() < 2:
		quit(1)
		return

	# ── A FIGHT, THROUGH THE REAL ENTRY POINTS ──
	# A shot and its hit in the same physics frame, as hitscan does it.
	_Analytics.shot(player)
	enemies[0].apply_damage(99999, player)
	_Analytics.shot(enemies[1])
	player.apply_damage(30, enemies[1])
	# Signal: a suppressing near-miss off the player's gun, then an EMP — named
	# as a blast names itself — that takes the rest and e-kills.
	enemies[1].receive_signal_damage(0.2, player)
	_Analytics.set_cause("EMP")
	enemies[1].receive_signal_damage(1.2, player)
	_Analytics.clear_cause()
	var squad: Squad = cm.spawner.active_squad if cm.spawner != null else null
	if squad != null:
		squad.receive_player_order(Squad.SquadObjective.ADVANCE, player.global_position + Vector3(0, 0, -10))
	for _i in 60:
		await physics_frame
	player.apply_damage(100000, enemies[1])
	await create_timer(1.0).timeout
	await process_frame
	master._continue_after_death()
	for _i in 60:
		await physics_frame

	# ── READ IT BACK ─────────────────────────────
	var dir: String = recorder.session_dir()
	var events := _events_in(dir + "/events.jsonl")
	_check("every line of events.jsonl parses", events.size() > 5, str(events.size()))
	_check("the session is opened", _of(events, "session_start").size() == 1)
	var build_label: String = preload("res://Managers/build_version.gd").label()
	_check("...and says which build it is (+dev from the editor)", _of(events, "session_start").size() == 1
		and _of(events, "session_start")[0].get("version") == build_label and build_label.ends_with("+dev"),
		str(_of(events, "session_start")[0].get("version")) if _of(events, "session_start").size() == 1 else "")
	var start := _of(events, "mission_start")
	_check("the mission start records the op and the player's kit",
		start.size() == 1 and start[0].get("m") == "arena_3_firing_line" and start[0].has("player"))
	var squad_ev := _of(events, "squad")
	_check("the squad is listed with its kit", squad_ev.size() == 1 and not squad_ev[0].get("allies", []).is_empty()
		and squad_ev[0]["allies"][0].has("modules"))
	var kills := _of(events, "damage").filter(func(e): return e["atk"]["side"] == "player" and e["lethal"])
	_check("the player's kill is recorded with the weapon that did it",
		kills.size() == 1 and kills[0]["vic"]["side"] == "enemy" and kills[0]["w"] != "unknown",
		str(kills))
	var hurt := _of(events, "damage").filter(func(e): return e["vic"]["side"] == "player")
	# What a hit COSTS is a tuning number and has already moved once (a third,
	# then a half), so read the scale off the player rather than restating it.
	# What is being checked is that the event carries both the raw hit and what
	# it actually took off, not that the dial sits at any one value.
	var want := int(round(30.0 * player.damage_taken_scale))
	_check("hits on the player say what hit them, and what it cost after scaling",
		hurt.size() == 2 and hurt[0]["atk"]["side"] == "enemy" and hurt[0]["atk"]["kind"] != ""
		and int(hurt[0]["raw"]) == 30 and int(hurt[0]["dmg"]) == want,
		"%s (expected %d off a raw 30)" % [str(hurt), want])
	var death := _of(events, "player_death")
	_check("the death names its killer and the damage before it",
		death.size() == 1 and death[0]["killer"]["side"] == "enemy" and death[0]["recent"].size() >= 1)
	var orders := _of(events, "order")
	_check("the ADVANCE order is logged as the player's", orders.any(func(e): return e["to"] == "ADVANCE" and e["by_player"]))
	var end := _of(events, "mission_end")
	_check("the mission ends as a death", end.size() == 1 and end[0]["result"] == "death", str(end))
	if end.size() == 1:
		var shots: Dictionary = end[0]["shots"]
		var hits: Dictionary = end[0]["hits"]
		var player_key := ""
		for k in shots:
			if str(k).begins_with("player|"):
				player_key = k
		_check("shots and hits are counted per weapon", player_key != "" and int(shots[player_key]) == 1
			and int(hits.get(player_key, 0)) == 1, "%s / %s" % [str(shots), str(hits)])
		var advance := 0.0
		for sq in end[0]["orders"]:
			advance += float(end[0]["orders"][sq].get("ADVANCE", 0.0))
		_check("time under each order is totalled", advance > 0.3, str(end[0]["orders"]))
		_check("ammo left is snapshotted", not (end[0]["ammo"] as Dictionary).is_empty())
		var sig: Dictionary = end[0].get("signal", {})
		var by_gun := 0.0
		var by_emp := 0.0
		for k in sig:
			if str(k) == "player|EMP":
				by_emp = float(sig[k])
			elif str(k).begins_with("player|"):
				by_gun = float(sig[k])
		_check("signal taken off is totalled per weapon: the gun's near-miss and the EMP apart",
			is_equal_approx(by_gun, 0.2) and is_equal_approx(by_emp, 0.8), str(sig))
		_check("...and the e-kill is counted to the EMP", int((end[0].get("ekills", {}) as Dictionary).get("player|EMP", 0)) == 1,
			str(end[0].get("ekills", {})))
	var ek := _of(events, "ekill")
	_check("the e-kill is logged, credited to the EMP rather than the gun in the thrower's hands",
		ek.size() == 1 and ek[0]["w"] == "EMP" and ek[0]["atk"]["side"] == "player" and ek[0]["vic"]["side"] == "enemy",
		str(ek))
	_check("mission time is play time, and it moved", end.size() == 1 and float(end[0]["duration"]) > 0.3)

	# ── THE REPORT ───────────────────────────────
	var report := FileAccess.get_file_as_string(dir + "/report.md")
	_check("report.md is written after the mission", report.contains("## How hard is it?")
		and report.contains("## What hurts the player most?") and report.contains("## Which player weapons work?")
		and report.contains("## Follow vs. advance"))
	_check("...and says the attempt ended in a death", report.contains("died **1**"))
	_check("...and which build the session was", report.contains("Build %s." % build_label))
	_check("...and what wore down their signal, and who was e-killed", report.contains("## Signal and e-kills")
		and report.contains("You: EMP") and report.contains("E-killed: 1"))
	var rebuilt: String = _Report.build(events, "roundtrip")
	_check("the report rebuilds from the parsed file alone", rebuilt.contains("Mission attempts: **1**"))

	master.queue_free()
	for _i in 5:
		await process_frame
	var after := _events_in(dir + "/events.jsonl")
	_check("closing the game closes the session", _of(after, "session_end").size() == 1)

	_Analytics.force_enable = false
	_Analytics.dir_override = ""
	_wipe(TEST_DIR)
	if FileAccess.file_exists("user://settings_analytics_test.json"):
		DirAccess.remove_absolute("user://settings_analytics_test.json")
	print("")
	print("ALL ANALYTICS CHECKS PASS" if _fails == 0 else "%d ANALYTICS CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
