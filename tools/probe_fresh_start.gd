extends SceneTree

# ─────────────────────────────────────────────
# WHAT A BRAND NEW SAVE ACTUALLY GIVES YOU — booted for real, not read off the
# exports, so what it prints is what a playtester walks into.
#
# Nothing is written: autosave off, Settings on a probe path, -- --no-save.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_fresh_start.gd -- --no-save
# ─────────────────────────────────────────────


func _init() -> void:
	Settings.path = "user://settings_probe.json"
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

	# A clean campaign, then the base muster re-run exactly as World._ready does.
	cm.reset_campaign()
	cm.on_level_loaded(world.current_level)
	for _i in 60:
		await physics_frame

	var st: CampaignState = cm.state
	print("")
	print("══ A FRESH SAVE, AT THE DEPOT ═════════════════════════════════════")
	print("resources   %d available (%d earned, %d committed)" % [st.available(), st.earned, st.spent()])
	print("compute     %d earned, %d free" % [st.compute_earned, st.compute_free()])
	print("supply cap  %d seat(s)" % st.supply_cap)
	print("tutorial    completed_tutorial=%s  lessons_seen=%s" % [
		st.completed_tutorial, str(st.lessons_seen)])
	print("unlocked    %s" % ("(nothing yet)" if st.unlocked.is_empty() else str(st.unlocked)))

	var stock: Array = []
	for id in st.armoury.stock.keys():
		stock.append("%dx %s" % [int(st.armoury.stock[id]), String(id)])
	print("stores      %s" % ", ".join(stock))

	print("")
	print("ROSTER")
	for r in st.roster:
		if r == null:
			continue
		print("  %-12s %-10s %d/%d hp  weapon=%s" % [
			r.display_name, String(r.chassis_id), r.current_health(), r.max_health,
			str(r.weapon_ids)])
	var pr: SoldierRecord = st.player_record
	if pr != null:
		print("  player_record weapons=%s equipment=%s modules=%s" % [str(pr.weapon_ids), str(pr.equipment_ids), str(pr.module_ids)])
		print("  %-12s %-10s (you)" % [pr.display_name, String(pr.chassis_id)])

	print("")
	print("ON THE MAP RIGHT NOW")
	var body: Node = world.player
	# THE FRACTION IS THE REAL NUMBER HERE, not the maximum. reset_campaign()
	# swaps in a new CampaignState, but the player still has roster_changed wired
	# to the discarded one, so _apply_module_stats never re-runs and max_health
	# keeps whatever THIS MACHINE'S save had fitted. A true first boot reads 100.
	print("  player        %d/%d hp (%.0f%% — the max carries over from the real save)" % [
		int(body.health), int(body.max_health),
		float(body.health) / maxf(1.0, float(body.max_health)) * 100.0])
	var total := 0
	var down := 0
	for sq in world.squad_spawner.squads:
		if sq == null or not is_instance_valid(sq):
			continue
		for m in sq.squad_members:
			if m == null or not is_instance_valid(m):
				continue
			total += 1
			var state := "DOWNED — repair it" if m.downed else "up"
			print("  %-13s %d/%d hp  %s" % [m.soldier_name, int(m.health), int(m.max_health), state])
			if m.downed:
				down += 1
	print("  -> %d mustered, %d down" % [total, down])

	# The base's own teaching, if any is left in the level.
	var signs: Array = []
	_signs(world.current_level, signs)
	var teaching: Array = signs.filter(func(s): return str(s.toast_text) != "")
	print("")
	print("TUTORIAL SIGNS IN THE DEPOT: %d (%d carrying a lesson)" % [
		signs.size(), teaching.size()])
	for s in teaching:
		print("   %s" % str(s.toast_text).substr(0, 70))

	print("")
	print("OFFERED AT THE TERMINAL")
	for m in cm.available_missions():
		print("  %-22s %s" % [String(m.id), m.display_name])
	print("")
	print("LOCKED FOR NOW")
	for m in cm.missions:
		if m == null or cm.available_missions().has(m):
			continue
		print("  %-22s requires %s" % [String(m.id), str(m.requires)])
	quit(0)


func _signs(n: Node, out: Array) -> void:
	if n is TutorialLabel:
		out.append(n)
	for c in n.get_children():
		_signs(c, out)
