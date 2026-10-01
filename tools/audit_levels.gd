extends SceneTree

# ─────────────────────────────────────────────
# WHAT GAMEPLAY IS ACTUALLY IN EACH MAP, AND WHAT EACH MISSION EXPECTS TO FIND.
#
# Terrain and gameplay are owned by different people now, which is the right
# split and also exactly the shape of problem that needs a report: a map can be
# regenerated perfectly and come back without the objectives, spawns and exits
# the mission on top of it depends on. Nothing fails loudly when that happens —
# the mission just loads with no objective, or a reserve force that never wakes,
# and the first anyone knows is a playtest.
#
# Reads the PACKED scenes rather than instancing them: no physics, no
# navigation bake, no AI, and it can therefore check every map in a few
# seconds. The same technique test_mission_objectives.gd uses.
#
# This REPORTS. It is an audit, not a gate — a map that is mid-rebuild is
# expected to be missing things, and the point is to be able to see what.
#
#   godot --headless --path . --script res://tools/audit_levels.gd
# ─────────────────────────────────────────────

const OBJECTIVE_SCRIPTS := [
	"mission_objective.gd", "reach_objective.gd",
	"interact_objective.gd", "eliminate_objective.gd",
]
const MAPS := "res://maps"


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var world := load("res://Env/world.tscn") as PackedScene
	var missions: Array = _missions(world.get_state())
	# level path -> the missions played on it
	var played: Dictionary = {}
	for m in missions:
		if m == null or m.level_scene == null:
			continue
		var p: String = m.level_scene.resource_path
		if not played.has(p):
			played[p] = []
		played[p].append(m)

	print("")
	print("══ LEVELS ════════════════════════════════════════════════")
	var paths: Array = _level_paths()
	for path in paths:
		# *_art.tscn are the terrain lane's art-only companions. They are
		# SUPPOSED to have no spawn, no objectives and no exit — listing them
		# with four warnings each buries the levels that have a real problem.
		if path.get_file().get_basename().ends_with("_art"):
			continue
		_report_level(path, played.get(path, []))

	print("")
	print("══ MISSIONS ══════════════════════════════════════════════")
	for m in missions:
		_report_mission(m)
	print("")
	quit(0)


func _level_paths() -> Array:
	var out: Array = []
	var dir := DirAccess.open(MAPS)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			out.append("%s/%s" % [MAPS, f])
	out.sort()
	return out


func _report_level(path: String, missions: Array) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		print("  %-34s  COULD NOT LOAD" % path.get_file())
		return
	var st := packed.get_state()
	var objectives := {}
	var counts := {"cover_point.gd": 0, "squad_spawn_point.gd": 0, "level_exit.gd": 0,
		"bonfire.gd": 0, "spawn_point.gd": 0, "cover_point_spawner.gd": 0}
	var has_spawn := false
	var has_nav := false

	for i in st.get_node_count():
		var script_file := ""
		var id: StringName = &""
		var extract := false
		for j in st.get_node_property_count(i):
			var prop := String(st.get_node_property_name(i, j))
			var v: Variant = st.get_node_property_value(i, j)
			if prop == "script" and v != null:
				script_file = str(v.resource_path).get_file()
			elif prop == "id":
				id = StringName(v)
			elif prop == "is_extraction":
				extract = bool(v)
			elif prop == "spawn_point" and v != null:
				has_spawn = true
			elif prop == "nav_region" and v != null:
				has_nav = true
		if counts.has(script_file):
			counts[script_file] += 1
		else:
			# Instanced nodes keep their script on the instanced scene, so they
			# are identified by which scene they are. Exits and cover points are
			# both authored that way; counting only script overrides reported
			# every level in the game as having no way off it.
			var inst := st.get_node_instance(i)
			if inst != null:
				var f := inst.resource_path.get_file()
				for key in counts:
					if f == key.replace(".gd", ".tscn"):
						counts[key] += 1
		if id != &"" and (OBJECTIVE_SCRIPTS.has(script_file)
				or _instance_is_objective(st.get_node_instance(i))):
			objectives[id] = extract
		# A NavigationRegion3D does not carry a script, so it is found by type.
		if st.get_node_type(i) == &"NavigationRegion3D":
			has_nav = true

	var extracts := 0
	for k in objectives:
		if objectives[k]:
			extracts += 1

	var minimap := "res://maps/minimaps/%s.tres" % path.get_file().get_basename()
	var flags := PackedStringArray()
	if not has_spawn:
		flags.append("NO SPAWN POINT")
	if not has_nav:
		flags.append("no navmesh")
	if counts["level_exit.gd"] == 0 and extracts == 0:
		flags.append("NO WAY OFF THE MAP")
	if not ResourceLoader.exists(minimap):
		flags.append("no minimap")
	if counts["cover_point.gd"] == 0 and counts["cover_point_spawner.gd"] == 0:
		flags.append("no cover")
	if not missions.is_empty() and objectives.is_empty():
		flags.append("PLAYED BUT HAS NO OBJECTIVES")

	print("")
	print("  %s%s" % [path.get_file(), "   (not used by any mission)" if missions.is_empty() else ""])
	print("     objectives %-3d (%d extraction)   exits %-2d  squad spawns %-2d  cover %d%s" % [
		objectives.size(), extracts, counts["level_exit.gd"], counts["squad_spawn_point.gd"],
		counts["cover_point.gd"],
		"  (+%d spawners)" % counts["cover_point_spawner.gd"] if counts["cover_point_spawner.gd"] > 0 else ""])
	if not objectives.is_empty():
		var names := PackedStringArray()
		for k in objectives:
			names.append("%s%s" % [k, "*" if objectives[k] else ""])
		print("     ids: %s" % " ".join(names))
	if not flags.is_empty():
		print("     >> %s" % "  |  ".join(flags))


func _report_mission(m) -> void:
	if m == null:
		return
	var lvl: String = m.level_scene.resource_path if m.level_scene != null else ""
	if lvl == "":
		print("  %-26s  NO LEVEL SCENE" % str(m.id))
		return
	var objectives := _objective_ids(load(lvl) as PackedScene)
	var problems := PackedStringArray()

	# THE WHITELIST IS THE DANGEROUS ONE. Campaign._prune_inactive_objectives()
	# frees every level objective the mission does not name, so a name that has
	# gone stale does not fall back to anything — it deletes the real objective
	# and leaves the mission pointing at nothing.
	for want in m.active_objectives:
		if not objectives.has(want):
			problems.append("active_objectives names '%s', which the level does not have" % want)
	if not m.active_objectives.is_empty():
		var kept_extract := false
		for want in m.active_objectives:
			if objectives.get(want, false):
				kept_extract = true
		if not kept_extract:
			problems.append("nothing it keeps is an extraction — no way to end the mission")

	# Reserves that can never be woken. Five things can wake a force; see
	# test_mission_objectives.gd for the list this mirrors.
	var callsigns := {}
	for f in m.enemy_force:
		if f != null:
			callsigns[String(f.callsign).to_lower()] = true
	for f in m.enemy_force:
		if f == null or String(f.reinforcement_tag) == "":
			continue
		var tag := String(f.reinforcement_tag)
		var low := tag.to_lower()
		var ok: bool = objectives.has(StringName(tag)) or tag == "nest_down" \
			or callsigns.has(low) \
			or low.ends_with("_down") and callsigns.has(low.trim_suffix("_down")) \
			or low.ends_with("_engaged") and callsigns.has(low.trim_suffix("_engaged"))
		if not ok and int(f.wake_after_kills) <= 0:
			problems.append("%s waits on '%s', which nothing can ever trigger (%d bodies)" % [
				String(f.callsign), tag, _bodies(f)])

	if problems.is_empty():
		print("  %-26s  ok   (%s)" % [str(m.id), lvl.get_file()])
	else:
		print("  %-26s  (%s)" % [str(m.id), lvl.get_file()])
		for p in problems:
			print("        >> %s" % p)


func _bodies(force) -> int:
	if force == null:
		return 0
	var n := 0
	if "roster" in force and force.roster != null:
		n = force.roster.size()
	return n


func _objective_ids(packed: PackedScene) -> Dictionary:
	var out := {}
	if packed == null:
		return out
	var st := packed.get_state()
	for i in st.get_node_count():
		var id: StringName = &""
		var extract := false
		var is_objective := false
		for j in st.get_node_property_count(i):
			var prop := String(st.get_node_property_name(i, j))
			var v: Variant = st.get_node_property_value(i, j)
			if prop == "script" and v != null:
				is_objective = OBJECTIVE_SCRIPTS.has(str(v.resource_path).get_file())
			elif prop == "id":
				id = StringName(v)
			elif prop == "is_extraction":
				extract = bool(v)
		if id == &"":
			continue
		# AN INSTANCED OBJECTIVE HAS NO `script` PROPERTY OF ITS OWN. Capture
		# points are instanced scenes: the script lives on the instanced scene's
		# root and the level only overrides `id`, so testing for a script
		# override missed every one of them — and then reported the mission that
		# named them as pointing at nothing, and its reserves as unwakeable.
		# Eleven false alarms across three maps, all of them real objectives.
		if not is_objective and not _instance_is_objective(st.get_node_instance(i)):
			continue
		out[id] = extract
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


## True when `packed`'s own root carries one of the objective scripts — which
## is where an instanced objective keeps it. See _objective_ids().
func _instance_is_objective(packed: PackedScene) -> bool:
	if packed == null:
		return false
	var st := packed.get_state()
	if st.get_node_count() == 0:
		return false
	for j in st.get_node_property_count(0):
		if String(st.get_node_property_name(0, j)) != "script":
			continue
		var v: Variant = st.get_node_property_value(0, j)
		if v != null:
			return OBJECTIVE_SCRIPTS.has(str(v.resource_path).get_file())
	return false
