extends Node
class_name CampaignManager

# ─────────────────────────────────────────────
# CAMPAIGN — the autoload that owns state across level loads.
#
# Register in Project Settings > Autoload with the name "Campaign". It has to
# be an autoload rather than a node under World: World.load_next_level() frees
# the level and the roster has to outlive that.
#
# LIFECYCLE
#   deploy(mission)  remembers the mission and hands World the level to load
#   on_level_loaded  the spawner builds the squad from the roster
#   extract()        write_back, pay rewards, save, return to base
#
# The base is just another TrenchBroomLevel. Deploying from it and extracting
# back to it are the same operation with different destinations, which is why
# MissionExit resolves its target from here instead of from the inspector.
# ─────────────────────────────────────────────

@export var base_level: PackedScene
# Everything the player can deploy to. Authored .tres definitions.
@export var missions: Array[MissionDefinition] = []
@export var autosave: bool = true

# ── DEV: launching a mission level directly ───
# Running valley_level.tscn (or world.tscn pointed at it) skips the base, so
# begin_deploy() never runs: in_mission stays false, current_mission stays null,
# the enemy force never spawns and the objective HUD hides itself. All silently.
#
# Assign a MissionDefinition here and the campaign assumes that operation when
# it finds itself in a level that isn't base. Leave null for shipping builds.
@export var debug_mission: MissionDefinition

# ── STARTING ROSTER ───────────────────────────
# A brand new CampaignState has an empty roster, so without this nothing ever
# deploys and the spawner silently does nothing — which looks exactly like the
# spawner being broken. These are only used on a fresh save.
@export var starting_squad_size: int = 4
@export var starting_names: Array[String] = ["Bravo-1", "Bravo-2", "Bravo-3", "Bravo-4"]
@export var starting_chassis: PackedScene
@export var starting_max_health: int = 30
@export var starting_resources: int = 0

signal state_loaded
signal deployed(mission: MissionDefinition)
signal extracted(mission: MissionDefinition, result: Dictionary)
signal returned_to_base
signal mission_selected(mission: MissionDefinition)
signal departure_ready(mission: MissionDefinition)

var state: CampaignState
var current_mission: MissionDefinition = null
var spawner: SquadSpawner = null
var objectives: ObjectiveTracker = null
var enemy_spawner: EnemyForceSpawner = null
# The exits at base that the terminal writes a destination into. Registered by
# World on every level load, because they live in the level scene and die with
# it.
var departure_exits: Array[LevelExit] = []

# True while the player is on a mission map rather than at base.
var in_mission: bool = false


func _ready() -> void:
	state = CampaignState.load_from_disk()
	if state == null:
		state = CampaignState.new()
		_seed_new_campaign()
	state_loaded.emit()


func _seed_new_campaign() -> void:
	state.award(starting_resources)
	for i in starting_squad_size:
		var r := SoldierRecord.new()
		r.display_name = starting_names[i] if i < starting_names.size() else "Unit-%02d" % (i + 1)
		r.max_health = starting_max_health
		r.chassis_scene = starting_chassis
		state.add_soldier(r)
	if autosave:
		state.save_to_disk()


# Wipes the save and starts over. Bind it to a debug key while you're iterating
# — otherwise every change to the starting roster is invisible until you go and
# delete user://campaign.json by hand.
func reset_campaign() -> void:
	state = CampaignState.new()
	_seed_new_campaign()
	current_mission = null
	in_mission = false
	state_loaded.emit()


# World registers itself here so Campaign doesn't have to go looking for it.
func register_spawner(s: SquadSpawner) -> void:
	spawner = s


func register_objective_tracker(t: ObjectiveTracker) -> void:
	objectives = t


func register_enemy_spawner(s: EnemyForceSpawner) -> void:
	enemy_spawner = s


# True when this objective id should be live for the current operation. An empty
# active_objectives list on the mission means "all of them", so a level's
# objectives keep working with no mission configuration at all.
func is_objective_active(id: StringName) -> bool:
	if current_mission == null:
		return true
	if current_mission.active_objectives.is_empty():
		return true
	return current_mission.active_objectives.has(id)


# World calls this after each level load with whatever it found in the
# "departure_exits" group. Re-pushes the current selection so the train is
# already pointed somewhere if a mission was picked before this level existed.
func register_departure_exits(exits: Array) -> void:
	departure_exits.clear()
	for e in exits:
		if e is LevelExit:
			departure_exits.append(e)
	_push_destination()


# The whole "terminal sets the train's destination" mechanic, in one place.
func _push_destination() -> void:
	var mission := selected_mission()
	for exit in departure_exits:
		if is_instance_valid(exit):
			exit.next_level = mission.level_scene if mission != null else null
	if mission != null:
		departure_ready.emit(mission)


# ─────────────────────────────────────────────
# MISSION SELECTION
# ─────────────────────────────────────────────
func get_mission(id: StringName) -> MissionDefinition:
	for m in missions:
		if m.id == id:
			return m
	return null


func available_missions() -> Array[MissionDefinition]:
	var out: Array[MissionDefinition] = []
	for m in missions:
		if not m.repeatable and state.completed_missions.has(m.id):
			continue
		var gated := false
		for req in m.requires:
			if not state.completed_missions.has(req):
				gated = true
				break
		if not gated:
			out.append(m)
	return out


func select_mission(id: StringName) -> void:
	state.selected_mission_id = id
	# Writing the destination into the exit is the point of selecting. Do it
	# here rather than in the terminal so every terminal, and any future map
	# UI, gets the behaviour for free.
	_push_destination()
	mission_selected.emit(selected_mission())


func selected_mission() -> MissionDefinition:
	return get_mission(state.selected_mission_id)


# ─────────────────────────────────────────────
# DESTINATION — what the special level exit resolves to
# ─────────────────────────────────────────────
# On the base map this is the selected mission. On a mission map it's the base.
# Returns null when nothing is selected, and MissionExit refuses to fire rather
# than dumping the player into a null scene.
func next_destination() -> PackedScene:
	if in_mission:
		return base_level
	var mission := selected_mission()
	return mission.level_scene if mission != null else null


# ─────────────────────────────────────────────
# DEPLOY / EXTRACT
# ─────────────────────────────────────────────
func begin_deploy() -> void:
	current_mission = selected_mission()
	in_mission = true
	if current_mission != null:
		deployed.emit(current_mission)


# Called by World once the new level is in the tree and its spawn point exists.
func on_level_loaded(level: Node) -> void:
	if level == null:
		return

	# Direct launch: no one called begin_deploy(), so adopt debug_mission.
	if not in_mission and debug_mission != null:
		current_mission = debug_mission
		state.selected_mission_id = debug_mission.id
		in_mission = true
		print("[Campaign] debug_mission active: '%s'. Base flow was skipped." % debug_mission.id)

	if not in_mission and debug_mission == null and base_level != null:
		push_warning("Campaign: level loaded but in_mission is false, so NO enemy force will spawn and the objective HUD will stay hidden. If you launched this level directly, set Campaign.debug_mission.")

	if in_mission and current_mission == null:
		push_warning("Campaign: in a mission but current_mission is null. Nothing will spawn. Either deploy from base, or set Campaign.debug_mission while iterating.")
	if spawner != null:
		spawner.deploy_into(level, state.deployable())
	# Opposition AFTER the player squad, so an EliminateObjective capturing
	# hostiles in a zone sees a fully populated map.
	if enemy_spawner != null and in_mission:
		enemy_spawner.deploy_force(level, current_mission)
	# After deploy: an EliminateObjective captures hostiles in its zone when it
	# activates, and the squad should already be in the world by then.
	if objectives != null:
		objectives.refresh()


# Success path. Collect the squad, pay out, save, and head home.
func extract(success: bool = true) -> Dictionary:
	var result := {"survivors": 0, "lost": 0, "reward": 0}
	if spawner != null:
		var counts := spawner.write_back()
		result["survivors"] = counts["survivors"]
		result["lost"] = counts["lost"]

	# Bonus objectives pay out whether or not the mission itself succeeded —
	# you did the work, and withholding it makes players avoid optional content.
	var objective_reward := 0
	if objectives != null:
		objective_reward = objectives.earned_objective_rewards()
		state.award(objective_reward)
	result["objective_reward"] = objective_reward

	if success and current_mission != null:
		state.award(current_mission.reward_resources)
		result["reward"] = current_mission.reward_resources
		if not state.completed_missions.has(current_mission.id):
			state.completed_missions.append(current_mission.id)
		for u in current_mission.unlocks:
			if not state.unlocked.has(u):
				state.unlocked.append(u)

	extracted.emit(current_mission, result)
	in_mission = false
	if autosave:
		state.save_to_disk()
	return result


# The player died, or withdrew. Same collection, no rewards, no completion.
func abort() -> Dictionary:
	return extract(false)


func on_returned_to_base() -> void:
	current_mission = null
	in_mission = false
	if spawner != null:
		spawner.clear()
	if objectives != null:
		objectives.clear()
	if enemy_spawner != null:
		enemy_spawner.clear()
	returned_to_base.emit()


func save() -> void:
	state.save_to_disk()
