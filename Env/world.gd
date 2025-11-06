extends Node3D
class_name WorldTemplate
var world_states: Enums.WorldStates
@export var world_env: WorldEnvironment
@export var spawn_area: Node3D
@export var player: Player
@export var current_level: TrenchBroomLevel

func _ready():
	await get_tree().process_frame
	await get_tree().process_frame
	if current_level:
		var spawn_transform = current_level.spawn_point.global_transform
		player.global_transform = spawn_transform
		player.cam.look_at(Vector3(player.global_position.x, player.global_position.y, player.global_position.z - 1))
		for level_exit in current_level.level_exits:
			level_exit.next_level_signal.connect(_on_next_level_requested)
		return
	else:
		for i in get_children():
			if i is TrenchBroomLevel:
				current_level = i
				for level_exit in current_level.level_exits:
					level_exit.next_level_signal.connect(_on_next_level_requested)
				pass

func load_next_level(next_level_scene: PackedScene) -> void:
	get_tree().paused = true
	# Optional: show transition blocker (e.g., fade to black)
# 	blocker.visible = true

	# Delay a few frames to allow blocker to render (optional but smoother)
	await get_tree().process_frame

	# De-load current level if one is loaded
	if current_level:
		await deload_current_level(current_level)
	# Instantiate the new map scene
	var new_level := next_level_scene.instantiate() as TrenchBroomLevel
	add_child(new_level)
	current_level = new_level
	# Ensure spawn point is valid
	if new_level.spawn_point:
		var spawn_transform = new_level.spawn_point.global_transform

		# Move the player to the spawn location
		player.global_transform = spawn_transform
	# Optional: orient player to match spawn direction
		# (depends on how your Player script handles rotation)
		# player.look_at(spawn_transform.origin + spawn_transform.basis.z)

	# Optionally: attach nav region if your level includes one
	for level_exit in current_level.level_exits:
		level_exit.next_level_signal.connect(_on_next_level_requested)
	await get_tree().process_frame

	# Resume game
	get_tree().paused = false


func deload_current_level(level):
	if level and is_instance_valid(level):
		level.queue_free()
	return true

func _on_next_level_requested(next_level_scene: PackedScene) -> void:
	#print("Received signal to load next level.")
	load_next_level(next_level_scene)
