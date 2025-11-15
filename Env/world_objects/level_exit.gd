extends Node3D
class_name LevelExit
@export var area: Area3D
@export var next_level: PackedScene
signal next_level_signal(level :PackedScene)

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body is Player:
		next_level_signal.emit(next_level)
