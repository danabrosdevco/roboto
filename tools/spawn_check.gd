extends SceneTree

# ─────────────────────────────────────────────
# SPAWN CHECK — instantiates each mission's level and runs the real
# EnemyForceSpawner against it, then counts the bodies that actually landed.
#
# WHY THIS IS NOT A DATA CHECK: a spec's roster can be perfectly authored and
# still spawn nothing. deploy_force() once skipped every spec whose legacy
# `count` was 0 — exactly what a roster-form spec sets — so Valley Siege parsed
# as 45 hostiles and loaded as an empty valley, silently.
#
# RESERVES ARE CHECKED SEPARATELY. They are deliberately NOT built at deploy:
# a spawned-but-idle body is still a live AI that engages on sight, which had
# every helicopter arriving the moment the player walked near instead of when
# the objective that calls them completed. So the test is two-part — the
# garrison lands at deploy, and the reserves land only when their tag fires.
# ─────────────────────────────────────────────

func _init() -> void:
	await process_frame
	var failures := 0
	var dir := DirAccess.open("res://Campaign/missions")
	var names := dir.get_files()
	names.sort()

	for f in names:
		if not f.ends_with(".tres"):
			continue
		var m = load("res://Campaign/missions/" + f)
		if m == null or m.level_scene == null:
			continue

		var at_deploy := 0
		var in_reserve := 0
		var tags := {}
		for spec in m.enemy_force:
			if spec == null:
				continue
			if spec.posture == EnemySquadSpec.Posture.RESERVE:
				in_reserve += spec.body_count()
				tags[spec.reinforcement_tag] = true
			else:
				at_deploy += spec.body_count()

		var level: Node = m.level_scene.instantiate()
		root.add_child(level)
		var spawner = preload("res://Campaign/enemy_force_spawner.gd").new()
		root.add_child(spawner)
		spawner.deploy_force(level, m)
		await process_frame

		var got := _count(level)
		var ok: bool = (got == at_deploy)

		# Now call every reinforcement tag and confirm the reserves arrive.
		var after := got
		if not tags.is_empty():
			for t in tags:
				spawner.wake(t)
			await process_frame
			after = _count(level)
			if after != at_deploy + in_reserve:
				ok = false

		if not ok:
			failures += 1
		print("%s %-22s deploy %3d/%-3d   reserve +%-3d → %3d/%-3d" % [
			"PASS " if ok else "FAIL ", m.id, got, at_deploy,
			in_reserve, after, at_deploy + in_reserve])

		spawner.queue_free()
		level.queue_free()
		await process_frame

	print("")
	if failures == 0:
		print("ALL MISSIONS SPAWN AS AUTHORED")
	else:
		print("%d MISSION(S) DO NOT SPAWN WHAT THEY DESCRIBE" % failures)
	quit(1 if failures > 0 else 0)


func _count(level: Node) -> int:
	var n := 0
	for c in level.get_children():
		if c is Soldier:
			n += 1
	return n
