extends SceneTree
# ─────────────────────────────────────────────
# WHAT EVERY CHASSIS ACTUALLY MOVES AT, in m/s.
#
# Two numbers, because there are two paths. A robot's scene authors move_speed
# directly; that is what an ENEMY of that frame runs at, because
# EnemyForceSpawner deliberately does not apply base_speed (see
# enemy_force_spawner.gd:418). For one in YOUR squad, SquadSpawner multiplies it
# by the record's effective_speed, which starts at the chassis base_speed
# multiplier — so an allied Walker at base_speed 0.9 is slower than the enemy
# Walker built from the same scene.
#
# Instantiated rather than grepped: a scene that does not set move_speed
# inherits Enemy's default, and the grep would miss it.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_speeds.gd
# ─────────────────────────────────────────────

func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var rows: Array = []
	var seen := {}

	var dir := DirAccess.open("res://Campaign/chassis")
	var files: Array = []
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".tres"):
				files.append(f)
	files.sort()
	for f in files:
		var def = load("res://Campaign/chassis/" + f)
		if def == null or def.scene == null:
			continue
		var sp := _speed_of(def.scene)
		seen[def.scene.resource_path] = true
		rows.append({
			"name": str(def.display_name), "id": str(def.id),
			"scene": def.scene.resource_path.get_file(),
			"raw": sp, "mult": float(def.base_speed),
			"buy": bool(def.purchasable), "cost": int(def.cost)})

	print("")
	print("══ CHASSIS SPEEDS, m/s ══════════════════════════════════════════════════")
	print("  %-18s %-7s %-7s %-7s %-11s %s" % ["FRAME", "ENEMY", "MULT", "ALLIED", "RECRUITABLE", "SCENE"])
	for r in rows:
		var allied: String = "—" if r["mult"] <= 0.0 else "%.2f" % (r["raw"] * r["mult"])
		var buy: String = ("yes, %d" % r["cost"]) if r["buy"] else "no (enemy)"
		print("  %-18s %-7s %-7s %-7s %-11s %s" % [
			r["name"], "%.2f" % r["raw"], "x%.2f" % r["mult"], allied, buy, r["scene"]])

	# Anything with a speed that no ChassisDefinition points at.
	print("")
	print("══ AI SCENES WITH NO CHASSIS ENTRY (enemy-only) ═════════════════════════")
	var ai := DirAccess.open("res://Character/characters/ai")
	var extra: Array = []
	if ai != null:
		for f in ai.get_files():
			if not f.ends_with(".tscn"):
				continue
			var p := "res://Character/characters/ai/" + f
			if seen.has(p):
				continue
			extra.append([f, _speed_of(load(p))])
	extra.sort_custom(func(a, b): return a[0] < b[0])
	for e in extra:
		if e[1] < 0.0:
			continue
		print("  %-42s %.2f" % [e[0], e[1]])
	quit(0)


## move_speed off a real instance, so an unset scene value falls back to the
## script default the way it does in game.
func _speed_of(packed: PackedScene) -> float:
	if packed == null:
		return -1.0
	var n = packed.instantiate()
	if n == null:
		return -1.0
	var v: Variant = n.get("move_speed")
	n.free()
	return -1.0 if v == null else float(v)
