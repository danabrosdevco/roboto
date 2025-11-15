extends Node3D
class_name WorldObject
@export var worldobject_type : Enums.WorldObjectTypes
func _ready():
	initialize()
	register_world_object()

func initialize():
	pass

func register_world_object():
	pass
