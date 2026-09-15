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
var player_corpse_scene = preload("res://Env/world_objects/components/player_corpse.tscn")

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
func load_next_level(next_level_scene: PackedScene) -> void:
	get_tree().paused = true
	await get_tree().process_frame

	# Campaign lifecycle happens HERE, before anything is freed. Extraction has
	# to read the squad's surviving state off nodes that still exist — run it
	# after deload and every record comes home marked destroyed.
	if Campaign.in_mission:
		Campaign.extract(true)
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
	get_tree().paused = false
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

func reset_level():
	game_manager.reset_level()

func respawn_player():
	if player.last_bonfire is Bonfire == true:
		player.global_position = player.last_bonfire.global_position
		return
	elif player.last_bonfire is Vector3 == true:
		player.global_position = player.last_bonfire
	player.reset()
	pass

func _on_next_level_requested(next_level_scene: PackedScene) -> void:
	#print("Received signal to load next level.")
	load_next_level(next_level_scene)

func _on_player_died(value: int, pos) -> void:
	reset_level()
	player.bits = 0
	player.update_status()
	respawn_player()
	create_corpse(value, pos)

func create_corpse(value: int, pos: Vector3):
	var new_corpse = player_corpse_scene.instantiate()
	current_level.add_child(new_corpse)
	new_corpse.activate(value)
	new_corpse.global_position = pos
	pass
