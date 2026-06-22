extends Node3D
class_name World
var world_states: Enums.WorldStates
@export var world_env: WorldEnvironment
@export var spawn_area: Node3D
@export var player: Player
@export var current_level: TrenchBroomLevel
@export var ai_manager: AIManager
@export var game_manager: GameManager
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
		var level_exits = get_tree().get_nodes_in_group("levelexit")
		for exit in level_exits:
			exit.next_level_signal.connect(_on_next_level_requested)
	else:
		for i in get_children():
			if i is TrenchBroomLevel:
				current_level = i
				for level_exit in current_level.level_exits:
					level_exit.next_level_signal.connect(_on_next_level_requested)
				pass
	register_world_objects(current_level)
func load_next_level(next_level_scene: PackedScene) -> void:
	get_tree().paused = true
	await get_tree().process_frame
	if current_level:
		await deload_current_level(current_level)
	var new_level := next_level_scene.instantiate() as TrenchBroomLevel
	add_child(new_level)
	current_level = new_level
	if new_level.spawn_point:
		var spawn_transform = new_level.spawn_point.global_transform
		player.global_transform = spawn_transform
		player.last_bonfire = current_level.spawn_point.global_position
	for level_exit in current_level.level_exits:
		level_exit.next_level_signal.connect(_on_next_level_requested)
	await get_tree().process_frame
	get_tree().paused = false
	register_world_objects(current_level)


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
