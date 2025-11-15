extends Node3D
class_name World
var world_states: Enums.WorldStates
@export var world_env: WorldEnvironment
@export var spawn_area: Node3D
@export var player: Player
@export var current_level: TrenchBroomLevel
@export var ai_manager: AIManager

func _ready():
	await get_tree().process_frame
	await get_tree().process_frame
	if current_level:
		var spawn_transform = current_level.spawn_point.global_transform
		player.global_transform = spawn_transform
		player.cam.look_at(Vector3(player.global_position.x, player.global_position.y, player.global_position.z - 1))
		for level_exit in current_level.level_exits:
			level_exit.next_level_signal.connect(_on_next_level_requested)
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
	for level_exit in current_level.level_exits:
		level_exit.next_level_signal.connect(_on_next_level_requested)
	await get_tree().process_frame
	get_tree().paused = false
	register_world_objects(current_level)


func deload_current_level(level):
	if level and is_instance_valid(level):
		level.queue_free()
	return true

func register_world_objects(level:TrenchBroomLevel):
	ai_manager.reset_all_reg_enemies()
	for child in current_level.nav_region.get_children():
		if child is AI:
			ai_manager.register_enemy(child)
		if child is Interactible:
			pass
		if child is PickUp:
			pass

func _on_next_level_requested(next_level_scene: PackedScene) -> void:
	#print("Received signal to load next level.")
	load_next_level(next_level_scene)
