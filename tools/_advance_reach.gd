extends SceneTree

# ─────────────────────────────────────────────
# WHICH ADVANCE SQUADS WERE STANDING STILL.
#
# Distance culling freezes a hostile beyond its activation_distance from the
# nearest thing it would fight, and it ignores always_active, so an ADVANCE
# authored from further out than that never set off. EnemyForceSpawner now
# exempts them for the length of the walk (see _let_them_walk_in) — this reports
# every ADVANCE spec in the game against that threshold, so the missions whose
# difficulty the fix moves are named rather than guessed at.
#
# Straight-line spawn-to-post, which is what the exemption test uses. Loads each
# level once and runs every mission on it.
# ─────────────────────────────────────────────

func _init() -> void:
	await process_frame
	var by_level: Dictionary = {}
	for f in DirAccess.get_files_at("res://Campaign/missions"):
		if not f.ends_with(".tres"):
			continue
		var m = load("res://Campaign/missions/" + f)
		if m == null or not ("enemy_force" in m) or m.level_scene == null:
			continue
		var wants := false
		for spec in m.enemy_force:
			if spec.posture == EnemySquadSpec.Posture.ADVANCE:
				wants = true
		if not wants:
			continue
		var path: String = m.level_scene.resource_path
		if not by_level.has(path):
			by_level[path] = []
		by_level[path].append(m)
	var frozen := 0
	var walked := 0
	for path in by_level:
		var lvl: Node = load(path).instantiate()
		root.add_child(lvl)
		for _i in 30:
			await process_frame
		var tags: Dictionary = {}
		_collect(lvl, tags)
		print("\n%s" % path.get_file())
		for m in by_level[path]:
			for spec in m.enemy_force:
				if spec.posture != EnemySquadSpec.Posture.ADVANCE:
					continue
				var from_tag: StringName = spec.spawn_tag if spec.spawn_tag != &"" else spec.post_tag
				if not tags.has(from_tag) or not tags.has(spec.post_tag):
					print("  %-28s %-12s spawn/post tag missing from this level" % [m.id, spec.callsign])
					continue
				var d: float = (tags[from_tag] as Vector3).distance_to(tags[spec.post_tag])
				# The threshold is the member's own radius, and it is set per
				# SCENE: troopers 120, walker 200, anything unset 75.
				var reach := 75
				for frame in spec.roster:
					if frame != null and frame.scene != null:
						var probe = frame.scene.instantiate()
						if "activation_distance" in probe:
							reach = max(reach, int(probe.activation_distance))
						probe.free()
				var was := d > float(reach)
				if was:
					frozen += 1
				else:
					walked += 1
				print("  %-28s %-12s %6.0fm vs %3dm  %s" % [
					m.id, spec.callsign, d, reach,
					"WAS FROZEN, now walks" if was else "already walked"])
		lvl.queue_free()
		await process_frame
	print("\n%d ADVANCE spec(s) were frozen and now walk; %d were already inside their radius." % [frozen, walked])
	quit(0)


func _collect(n: Node, out: Dictionary) -> void:
	if n.is_in_group("squad_objective_points") and "tag" in n:
		out[StringName(str(n.get("tag")))] = (n as Node3D).global_position
	for c in n.get_children():
		_collect(c, out)
