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
# IT FOLLOWS INSTANCED SUB-SCENES. This used to be a stated limit — an
# objective inside an instanced scene is not in the parent's SceneState, so it
# read as missing — on the grounds that no level authored one that way. Three
# now do: Georgetown, Polaris and Causeway keep their whole gameplay layer in
# maps/gameplay/<name>_ops.tscn, because the first two have their level .tscn
# written from a template by the terrain builders and anything added to one
# dies on the next rebuild. The limit announced itself as sixty failures, which
# is the direction this kind of error should fail in; see _collect_ids().
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

		# RESERVES. A reinforcement_tag is woken from FIVE places, not one, so
		# checking it against objective ids alone reports most of the game as
		# broken. The full set is: an objective id, the nest-down convention,
		# "<callsign>_down" when a squad is wiped, "<callsign>_engaged" on its
		# first contact, and a spec that wakes itself on a kill count or a clock.
		var wakeable := _wake_tags(m, found)
		for spec in m.enemy_force:
			if spec == null or spec.reinforcement_tag == &"":
				continue
			if spec.wake_after_kills > 0:
				continue   # wakes itself on the body count; needs no other source
			if spec.wake_after_seconds > 0.0:
				# ...and so does a wave on a CLOCK. This case was missing, and
				# the list above says "four places" while naming five, which is
				# the tell: wake_after_seconds was added to EnemySquadSpec and
				# implemented in the spawner (_time_waves, ticked in
				# _physics_process) without this check learning about it.
				#
				# It reported Salient's five quadcopter flights as broken when
				# they are the one kind of wave that cannot have a source
				# anywhere else — the whole point of a timed wave is that it
				# does not care what the player has done.
				continue
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
##
## FOLLOWS INSTANCED SUB-SCENES, which it used to refuse to do. The header
## said so and said it would fail loudly if a level ever authored an objective
## that way; three did at once. Georgetown, Polaris and Causeway keep their
## whole gameplay layer in maps/gameplay/<name>_ops.tscn and instance it,
## because the first two have their level .tscn regenerated from a template by
## the terrain builders and anything written into one dies on the next
## rebuild. An instanced scene's nodes are not in the parent's SceneState at
## all, so the sixty failures that found this were the test being honest about
## a limit rather than the data being wrong.
##
## DEPTH-LIMITED and cycle-safe by path: a scene that instances itself would
## otherwise recurse forever, and a deep tree of instanced props is not where
## objectives live.
const MAX_INSTANCE_DEPTH := 3


func _objective_ids(packed: PackedScene) -> Dictionary:
	return _collect_ids(packed, 0, {})


func _collect_ids(packed: PackedScene, depth: int, seen: Dictionary) -> Dictionary:
	var out := {}
	if packed == null:
		return out
	var key := str(packed.resource_path)
	if key != "" and seen.has(key):
		return out
	seen[key] = true
	var st := packed.get_state()
	for i in st.get_node_count():
		var instanced: PackedScene = st.get_node_instance(i)
		# WHAT IS INSIDE THE INSTANCE, first. Anything this scene overrides on
		# the instance is read below and wins, which is the right precedence: a
		# level that instances an ops layer and rewrites an id meant the rewrite.
		if instanced != null and depth < MAX_INSTANCE_DEPTH:
			var inner := _collect_ids(instanced, depth + 1, seen)
			for inner_id in inner:
				out[inner_id] = inner[inner_id]
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
		if not is_objective and not _instance_is_objective(instanced):
			continue
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
