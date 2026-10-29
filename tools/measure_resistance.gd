extends SceneTree

# ─────────────────────────────────────────────
# WHAT EACH PLACE IS ACTUALLY DEFENDED BY.
#
# A Location's `resistance` is total enemy SUPPLY, and §2 is explicit that it
# must be MEASURED off the authored force rather than typed. This measures it,
# once, so the numbers that go into the .tres files came from the missions and
# not from somebody's judgement.
#
# TWO FIGURES, because they answer different questions and the project already
# disagrees with itself about which one "resistance" means:
#
#   ON MAP   what you walk into. OpsTable._force() reports this, and it
#            deliberately leaves RESERVE squads out because the spawner holds
#            them back until something calls them in.
#   TOTAL    on-map plus reserve. This is what SiteHeat spends from — the
#            reserve IS the pressure pool — and it is where basin_slice.gd's
#            hardcoded 82 came from.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/measure_resistance.gd
# ─────────────────────────────────────────────

func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var dir := "res://Campaign/missions/"
	var d := DirAccess.open(dir)
	if d == null:
		printerr("cannot read %s" % dir)
		quit(1)
		return

	var rows: Array = []
	for f in d.get_files():
		if not f.ends_with(".tres"):
			continue
		var m = load(dir + f)
		if m == null:
			push_warning("measure_resistance: %s did not load." % f)
			continue
		var on_map := 0
		var reserve := 0
		var on_map_supply := 0
		var reserve_supply := 0
		for spec in m.enemy_force:
			if spec == null:
				continue
			# body_count(), not roster.size() inline — ops_table.gd says the
			# same. It used to be the guard against the legacy `count` field,
			# which every shipped spec carried as a stale 3; H9 removed the
			# field on 2026-10-24 and the one-place habit stays.
			var bodies: int = spec.body_count()
			var sup := 0
			for c in spec.roster:
				if c != null:
					sup += c.supply
			if spec.posture == EnemySquadSpec.Posture.RESERVE:
				reserve += bodies
				reserve_supply += sup
			else:
				on_map += bodies
				on_map_supply += sup
		rows.append({
			"id": String(m.id),
			"name": m.display_name,
			"bodies": on_map,
			"reserve": reserve,
			"on_map": on_map_supply,
			"total": on_map_supply + reserve_supply,
			"reward": m.reward_resources,
		})

	rows.sort_custom(func(a, b): return int(a["total"]) < int(b["total"]))
	print("")
	print("%-22s %-24s %6s %6s %8s %8s" % ["id", "operation", "bodies", "resv", "ON MAP", "TOTAL"])
	print("%s" % "-".repeat(78))
	var sum_on := 0
	var sum_total := 0
	for r in rows:
		print("%-22s %-24s %6d %6d %8d %8d" % [r["id"], r["name"], r["bodies"],
			r["reserve"], r["on_map"], r["total"]])
		sum_on += int(r["on_map"])
		sum_total += int(r["total"])
	print("%s" % "-".repeat(78))
	print("%-47s %8d %8d" % ["", sum_on, sum_total])
	print("")
	quit(0)
