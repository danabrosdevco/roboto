extends Node3D
class_name Interactible
@export var type: Enums.InteractTypes
@export var value: int

func get_interactible():
	return [type, value]
func get_type():
	return type
func get_value():
	return value
func disable():
	queue_free()
