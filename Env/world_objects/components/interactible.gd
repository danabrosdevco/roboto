extends Node3D
class_name Interactible
@export var type: Enums.InteractTypes
@export var value: int

func get_interactible():
	return [type, value]
