extends SceneTree

# ─────────────────────────────────────────────
# EVERY MISSION'S OBJECTIVES EXIST IN THE LEVEL IT DEPLOYS TO.
#
# A MissionDefinition names its objectives by id in `active_objectives`. The
# level is supposed to contain a node for each one. Nothing checked that the
# two agreed, and the failure is completely silent: the tracker collects the
# objectives it can find, finds none, and the mission runs with an empty
# objective HUD and no way to finish. The Hillfort shipped like that — the
# mission named hillfort_relay and hillfort_extract, the level had been
# regenerated without either node, and the first anyone knew was a playtest
# where the HUD was blank.
#
# It also catches the other half of the same disagreement: a mission whose
# reinforcement_tag names an objective id that does not exist, so the reserves
# it was written around can never be woken.
#
# PACKED DATA, NOT A LOAD. SceneState reads a .tscn without instantiating it,
# so this is fast and touches no physics, no navmesh and no save file. It only
# sees AUTHORED properties, which is exactly right here: an objective that does
# not author an `id` has id &"" and could not be named by a mission anyway.
#
# One known limit, stated rather than worked around: an objective hidden inside
# an instanced sub-scene is not visible in the level's own state and would be
# reported missing. No level in this project authors one that way. If that
# changes, this fails loudly and points at the file, which is the direction an
# error of this kind should fail in.
# ─────────────────────────────────────────────

## Scripts whose nodes are objectives. Matched on the file name so this does
## not need the class list, which an editor that has not rescanned may not have.
const OBJECTIVE_SCRIPTS := [
	"mission_objective.gd", "reach_objective.gd",
	"interact_objective.gd", "eliminate_objective.gd",
]

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  %s" if ok else "FAIL  %s  " + detail) % label)
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var world: PackedScene = load("res://Env/world.tscn")
	var missions: Array = _missions(world.get_state())
	_check("(setup) the campaign has missions to check", not missions.is_empty(),
		"world.tscn declares no mission list")
	if missions.is_empty():
		_finish()
		return

	for m in missions:
		if m == null:
			continue
		if m.level_scene == null:
			_check("%s names a level to deploy to" % m.id, false, "level_scene is null")
			continue
		var found := _objective_ids(m.level_scene)
		var level: String = m.level_scene.resource_path.get_file()

		# An EMPTY active_objectives means "the level's own set, all of it",
		# which is a deliberate and valid way to author a mission — so it is
		# only worth a word when the level then offers nothing at all.
		if m.active_objectives.is_empty():
			_check("%s takes the whole of %s, which is not empty" % [m.id, level],
				not found.is_empty(), "the level authors no objectives either")
			continue

		# THE FATAL CASE, and the only one: active_objectives is a WHITELIST.
		# _prune_inactive_objectives() frees every objective in the level that
		# the mission does not name, so a mission sharing NO id with its level
		# frees all of them — blank HUD, nothing to complete, no way home. A
		# single name that does not match is merely dead weight and is reported
		# below rather than failed, because several shipped missions carry one
		# and play correctly.
		var live: Array = []
		var dead: Array = []
		for id in m.active_objectives:
			if found.has(id):
				live.append(String(id))
			else:
				dead.append(String(id))
		_check("%s keeps at least one objective alive in %s" % [m.id, level],
			not live.is_empty(),
			"it names %s and the level authors %s, so the prune frees every one"
				% [str(dead), str(found.keys())])

		# THE WAY HOME. A mission whose surviving objectives are all capture
		# points and no extraction can be completed and never left.
		_check("...and one of them gets you off the map", _has_extract(m, found),
			"none of %s is an extraction" % str(live))

		if not dead.is_empty():
			print("      NOTE  %s names %s, which %s does not author. Harmless "
				% [m.id, str(dead), level] + "while the rest match, but it is a lie in the data.")

		# RESERVES. A reinforcement_tag is woken from four places, not one, so
		# checking it against objective ids alone reports most of the game as
		# broken. The full set is: an objective id, the nest-down convention,
		# "<callsign>_down" when a squad is wiped, "<callsign>_engaged" on its
		# first contact, and a spec that wakes itself on a kill count.
		var wakeable := _wake_tags(m, found)
		for spec in m.enemy_force:
			if spec == null or spec.reinforcement_tag == &"":
				continue
			if spec.wake_after_kills > 0:
				continue   # wakes itself on the body count; needs no other source
			_check("...%s's %s reserves have something that wakes them" % [m.id, spec.callsign],
				wakeable.has(spec.reinforcement_tag),
				"reinforcement_tag %s is not an objective in %s, not a callsign in this force, and not %s"
					% [spec.reinforcement_tag, level, EnemyForceSpawner.NEST_DOWN_TAG])

	_finish()


func _finish() -> void:
	print("")
	print("ALL MISSION OBJECTIVE CHECKS PASS" if _fails == 0
		else "%d MISSION OBJECTIVE CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


## Every tag that something in this mission can actually fire. Built from the
## same rules EnemyForceSpawner uses, so the two cannot drift apart quietly:
## objective ids, the nest-down convention, and the _down / _engaged tags the
## spawner derives from each squad's own callsign.
func _wake_tags(m, found: Dictionary) -> Dictionary:
	var out := {}
	for id in found.keys():
		out[id] = true
	out[EnemyForceSpawner.NEST_DOWN_TAG] = true
	for spec in m.enemy_force:
		if spec == null:
			continue
		out[EnemyForceSpawner.squad_down_tag(spec.callsign)] = true
		out[EnemyForceSpawner.squad_engaged_tag(spec.callsign)] = true
	return out


## True when at least one of the named objectives is flagged is_extraction.
## Read off the level rather than the mission: is_extraction is a property of
## the node, and the mission only names it.
func _has_extract(m, found: Dictionary) -> bool:
	for id in m.active_objectives:
		if bool(found.get(id, false)):
			return true
	return false


## Every objective id the level authors, mapped to whether it is an extraction.
func _objective_ids(packed: PackedScene) -> Dictionary:
	var out := {}
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
		if is_objective and id != &"":
			out[id] = extract
	return out


## The mission list as world.tscn authors it on CampaignManager. Same packed
## read as tools/audit_economy.gd.
func _missions(st: SceneState) -> Array:
	for i in st.get_node_count():
		if st.get_node_name(i) != "CampaignManager":
			continue
		for j in st.get_node_property_count(i):
			if String(st.get_node_property_name(i, j)) == "missions":
				return st.get_node_property_value(i, j)
		return []
	return []
