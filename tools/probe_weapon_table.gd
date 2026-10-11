extends SceneTree
# Every player-buyable weapon, with the numbers that live on its AIWeapon scene
# rather than on the item — damage, range, cadence — plus what it is allowed to
# go on. This is the data a weapons spec card would need.
func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var dir := DirAccess.open("res://Campaign/items")
	var files: Array = []
	for f in dir.get_files():
		if f.ends_with(".tres"):
			files.append(f)
	files.sort()
	print("  %-22s %-5s %-9s %-6s %-6s %-6s %-5s %-5s %-6s %s" % [
		"WEAPON", "cost", "type", "dmg", "range", "cd", "burst", "mag", "AI?", "fits/requires"])
	for f in files:
		var it = load("res://Campaign/items/" + f)
		if it == null or it.kind != 0:
			continue
		var t := "—"; var dmg := 0; var rng := 0.0; var cd := 0.0
		var bmin := 0; var bmax := 0; var mag := 0
		if it.ai_scene != null:
			var w = it.ai_scene.instantiate()
			t = ["melee", "hitscan", "projectile"][int(w.weapon_type)]
			dmg = w.base_damage; rng = w.max_effective_range; cd = w.fire_cooldown
			bmin = w.burst_min; bmax = w.burst_max; mag = w.magazine_size
			if t == "melee":
				rng = w.melee_range
			w.free()
		var restrict := ""
		if not it.fits_vehicles:
			restrict += "no-veh "
		if it.requires_chassis.size() > 0:
			restrict += "requires:" + ",".join(it.requires_chassis.map(func(v): return String(v))) + " "
		if it.chassis_whitelist.size() > 0:
			restrict += "only:" + ",".join(it.chassis_whitelist.map(func(v): return String(v)))
		var who := ("P" if it.usable_by_player else "-") + ("A" if it.usable_by_ai else "-")
		print("  %-22s %-5d %-9s %-6d %-6.0f %-6.2f %-5s %-5d %-6s %s" % [
			it.display_name, it.cost, t, dmg, rng, cd, "%d-%d" % [bmin, bmax], mag, who, restrict])
	quit(0)
