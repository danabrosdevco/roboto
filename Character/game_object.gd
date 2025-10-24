extends Node3D
class_name GameObject
@export var active: bool = true
@export var invulnerable: bool = false

func _ready():
	object_manager.register_object(self)

func pause():
	active = false

func start():
	active = true

func make_invulnerable():
	invulnerable = true

func make_vulnerable():
	invulnerable = false
