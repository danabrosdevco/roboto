extends Node3D
class_name World
var world_states: Enums.WorldStates
@export var world_env: WorldEnvironment
@export var spawn_area: Node3D
@export var player: Player
@export var current_level: TrenchBroomLevel
@export var ai_manager: AIManager
@export var game_manager: GameManager
# Persists across level loads so it can collect the squad out of one map and
# rebuild it in the next. Put it under World, never under a level.
@export var squad_spawner: SquadSpawner
@export var objective_tracker: ObjectiveTracker
@export var Campaign : CampaignManager
@export var enemy_spawner: EnemyForceSpawner


func _ready():
	await get_tree().process_frame
	if current_level == null:
		for child in get_children():
			if child is TrenchBroomLevel:
				current_level = child
	if current_level:
		var spawn_transform = current_level.spawn_point.global_transform
		player.global_transform = spawn_transform
		player.last_bonfire = current_level.spawn_point.global_position
		player.cam.look_at(Vector3(player.global_position.x, player.global_position.y, player.global_position.z - 1))
	else:
		for i in get_children():
			if i is TrenchBroomLevel:
				current_level = i
	register_world_objects(current_level)
	if squad_spawner != null:
		Campaign.register_spawner(squad_spawner)
	if objective_tracker != null:
		Campaign.register_objective_tracker(objective_tracker)
	if enemy_spawner != null:
		Campaign.register_enemy_spawner(enemy_spawner)
	_register_exits()
	Campaign.on_level_loaded(current_level)


# Exits live in the level scene, so they are gone after every load and have to
# be found again. Three jobs: hook the signal; tell Campaign which one is the
# train, so mission selection can write a destination into it; and point every
# OTHER exit home while we are on a mission. That last one is the return leg,
# and it means an extraction pad needs no configuration at all.
func _register_exits() -> void:
	var departures: Array = []
	for exit in get_tree().get_nodes_in_group("levelexit"):
		if not (exit is LevelExit):
			continue
		if not exit.next_level_signal.is_connected(_on_next_level_requested):
			exit.next_level_signal.connect(_on_next_level_requested)
		if exit.is_departure:
			departures.append(exit)
		elif Campaign.in_mission:
			exit.next_level = Campaign.base_level
	Campaign.register_departure_exits(departures)
## `success` is only read when leaving an operation: false is a failed one (the
## player died), which pays nothing and does not count as a clear.
func load_next_level(next_level_scene: PackedScene, success: bool = true) -> void:
	# A named hold rather than get_tree().paused: the mission briefing opens
	# INSIDE this load (begin_deploy below fires it), and the old direct write
	# at the end unpaused the game out from under it. See PauseHold.
	PauseHold.take(&"level_load")
	await get_tree().process_frame

	# Campaign lifecycle happens HERE, before anything is freed. Extraction has
	# to read the squad's surviving state off nodes that still exist — run it
	# after deload and every record comes home marked destroyed.
	if Campaign.in_mission:
		Campaign.extract(success)
	else:
		Campaign.begin_deploy()
	if current_level:
		await deload_current_level(current_level)
	var new_level := next_level_scene.instantiate() as TrenchBroomLevel
	add_child(new_level)
	current_level = new_level
	if new_level.spawn_point:
		var spawn_transform = new_level.spawn_point.global_transform
		player.global_transform = spawn_transform
		player.last_bonfire = current_level.spawn_point.global_position
	await get_tree().process_frame
	PauseHold.release(&"level_load")
	register_world_objects(current_level)
	_register_exits()
	# Arriving somewhere new. in_mission was already flipped above.
	if not Campaign.in_mission:
		Campaign.on_returned_to_base()
	Campaign.on_level_loaded(current_level)


func deload_current_level(level):
	if level and is_instance_valid(level):
		level.queue_free()
	return true

func register_world_objects(_level:TrenchBroomLevel):
	ai_manager.reset_all_reg_enemies()
	for child in get_tree().get_nodes_in_group("enemies"):
		if child is AI:
			ai_manager.register_enemy(child)
		if child is Interactible:
			pass
		if child is PickUp:
			pass

func _on_next_level_requested(next_level_scene: PackedScene) -> void:
	load_next_level(next_level_scene)


# ─────────────────────────────────────────────
# DEATH
# The player's `died` lands here. It used to run the old souls-style respawn —
# reset the level, respawn at a bonfire, drop a corpse — and the reset called
# into enemies GameManager had listed at boot, most of them freed by then,
# which is where the crash on death came from. Now it only announces the death:
# Master puts up YOU DIED, and CONTINUE comes back to return_home_after_death().
# ─────────────────────────────────────────────
signal player_killed


func _on_player_died(_value: int, _pos) -> void:
	player_killed.emit()


## CONTINUE on the death screen. On an operation it is a failed extraction —
## the squad comes home as it stands, nothing is paid, the op stays uncleared —
## and then the base loads. At base there is nothing to leave, so the player
## simply gets up at the spawn point.
func return_home_after_death() -> void:
	player.reset()
	if Campaign != null and Campaign.in_mission and Campaign.base_level != null:
		await load_next_level(Campaign.base_level, false)
	elif current_level != null and current_level.spawn_point != null:
		player.global_transform = current_level.spawn_point.global_transform
