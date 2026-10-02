extends SceneTree

# ─────────────────────────────────────────────
# WHAT THE BRIEFING AND THE MAP BOARD ACTUALLY MARK.
#
# Both go through MinimapData.objective_order(), so this tests the one function
# that decides what a player sees as a numbered destination.
#
# The thing it guards: a hive has to stay in a mission's active_objectives or
# Campaign._prune_inactive_objectives() deletes it and it stops hatching — so
# "is it active" cannot be the test for "should it be on the map", and the two
# will keep wanting to be the same list. They are not.
#
#   godot --headless --path . --script res://tools/test_minimap_objectives.gd
# ─────────────────────────────────────────────

var _fails: int = 0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var world := load("res://Env/world.tscn") as PackedScene
	var missions: Array = _missions(world.get_state())
	_check_arrow()

	print("")
	print("══ WHAT EACH MISSION MARKS ON THE MAP ════════════════════")
	for m in missions:
		if m == null or m.level_scene == null:
			continue
		var data := MinimapData.for_mission(m)
		if data == null:
			continue   # not baked; audit_levels.gd reports that separately
		var shown: Array[int] = data.objective_order(m.active_objectives)
		var marked := PackedStringArray()
		for i in shown:
			marked.append(String(data.objective_ids[i]))
		var hidden := PackedStringArray()
		var nests: Dictionary = data.nest_ids()
		for want in m.active_objectives:
			if nests.has(want):
				hidden.append(String(want))

		print("")
		print("  %-26s %s" % [str(m.id), data.resource_path.get_file()])
		print("     marks  %d: %s" % [marked.size(), " ".join(marked)])
		if not hidden.is_empty():
			print("     hides  %d: %s" % [hidden.size(), " ".join(hidden)])

		# A hive on the map is the bug. Nothing whose id says hive may be marked.
		for id in marked:
			if id.contains("hive"):
				_fail("%s marks '%s' as a destination" % [str(m.id), id])
		# And the op still has to have somewhere to go, or the filter has eaten
		# the mission instead of the clutter.
		if m.active_objectives.is_empty():
			continue
		if marked.is_empty():
			_fail("%s marks nothing at all" % str(m.id))
		var has_exit := false
		for i in shown:
			if data.objective_kinds[i] == &"extract":
				has_exit = true
		if not has_exit:
			_fail("%s marks no extraction" % str(m.id))

	# Every hive the levels define has to be recognised as one, or the filter is
	# only working on the maps that happen to spell their ids the same way.
	print("")
	print("══ NESTS RECOGNISED PER LEVEL ════════════════════════════")
	for path in _minimaps():
		var data := load(path) as MinimapData
		if data == null:
			continue
		# A bake whose level has been renamed or deleted out from under it cannot
		# be checked and is nobody's mission — report it rather than failing the
		# suite on an artefact that is already stale.
		if data.level_scene_path == "" or not ResourceLoader.exists(data.level_scene_path):
			print("  %-34s ORPHAN — level %s is gone, stale bake" % [path.get_file(), data.level_scene_path])
			continue
		var nests: Dictionary = data.nest_ids()
		var hives := 0
		for id in data.objective_ids:
			if String(id).contains("hive"):
				hives += 1
				if not nests.has(id):
					_fail("%s: '%s' is a hive the filter did not recognise" % [path.get_file(), id])
		if nests.is_empty() and hives == 0:
			continue
		var names := PackedStringArray()
		for id in nests:
			names.append(String(id))
		print("  %-34s %d nest(s): %s" % [path.get_file(), nests.size(), " ".join(names)])

	print("")
	if _fails == 0:
		print("PASS — no hive is marked as a destination, every op still has a route")
	else:
		print("FAIL — %d problem(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _fail(msg: String) -> void:
	_fails += 1
	print("     >> FAIL: %s" % msg)


func _minimaps() -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://maps/minimaps")
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".tres"):
			out.append("res://maps/minimaps/%s" % f)
	out.sort()
	return out


func _missions(st: SceneState) -> Array:
	for i in st.get_node_count():
		if st.get_node_name(i) != "CampaignManager":
			continue
		for j in st.get_node_property_count(i):
			if String(st.get_node_property_name(i, j)) == "missions":
				return st.get_node_property_value(i, j)
		return []
	return []


# ─────────────────────────────────────────────
# THE "YOU ARE HERE" ARROW POINTS THE WAY YOU ARE FACING
#
# It did not. The old maths went through signed_angle_to and rebuilt a vector as
# (sin, -cos), which negates the vertical component only — so the arrow was
# right facing east or west and exactly backwards facing north or south. A
# MIRROR, not a rotation, and that is why nobody caught it: half of every spin
# looks correct. It was reported as "the arrow is reversed 180 degrees on
# Qamareen", and it was on every map.
#
# CHECKED AGAINST to_uv'S OWN AXES, not against a second copy of the formula.
# to_uv puts world X on u and world Z on v, so walking one metre in the facing
# direction has to move the dot the way the arrow points. That is the invariant,
# and it is the one thing a re-implementation inside the test would not catch.
# ─────────────────────────────────────────────
const _Briefing := preload("res://Character/hud/mission_briefing.gd")
const _Minimap := preload("res://Campaign/minimap_data.gd")

func _check_arrow() -> void:
	print("")
	print("══ THE PLAYER ARROW ══════════════════════════════════════")
	var data = _Minimap.new()
	data.world_min = Vector2(-100.0, -100.0)
	data.world_max = Vector2(100.0, 100.0)
	var here := Vector3(10.0, 0.0, -20.0)      # off-centre, so a sign error shows
	for row in [
			["north", Vector3(0, 0, -1)], ["south", Vector3(0, 0, 1)],
			["east", Vector3(1, 0, 0)], ["west", Vector3(-1, 0, 0)],
			["north-east", Vector3(1, 0, -1).normalized()]]:
		var name: String = row[0]
		var facing: Vector3 = row[1]
		var arrow: Vector2 = _Briefing.map_arrow(facing)
		# Where a step in that direction actually lands on the image.
		var a: Vector2 = data.to_uv(here)
		var b: Vector2 = data.to_uv(here + facing * 5.0)
		var moved := (b - a).normalized()
		var ok := arrow.distance_to(moved) < 0.01
		if not ok:
			_fail("facing %s: the arrow points %s but the dot moves %s" % [
				name, arrow, moved])
		print("     %-11s arrow %-16s dot moves %-16s %s" % [
			name, "(%.2f, %.2f)" % [arrow.x, arrow.y],
			"(%.2f, %.2f)" % [moved.x, moved.y], "ok" if ok else "WRONG"])

	# A pitched-straight-down facing has no heading at all. It must still give a
	# unit vector, or the arrow collapses to a dot with no warning.
	var degenerate: Vector2 = _Briefing.map_arrow(Vector3(0, -1, 0))
	if absf(degenerate.length() - 1.0) > 0.01:
		_fail("a facing with no heading gave %s, which does not draw an arrow" % degenerate)
	print("     %-11s arrow %-16s (must still be a unit vector)" % [
		"straight down", "(%.2f, %.2f)" % [degenerate.x, degenerate.y]])
