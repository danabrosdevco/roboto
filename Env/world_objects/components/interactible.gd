extends Area3D
class_name Interactible
@export var collision_body: CollisionShape3D
@export var static_body: StaticBody3D
@export var type: Enums.InteractTypes
@export var value: int
@export var used: bool = false
@export var respawns_on_reset: bool = true
@export var destroy_on_use: bool = true
@export var disable_on_use: bool = false
var spawn_transform

func _ready() -> void:
	spawn_transform = transform

func reset():
	if not respawns_on_reset:
		return

	used = false
	transform = spawn_transform
	visible = true
	monitoring = true
	monitorable = true
	if collision_body:
		collision_body.disabled = false

	if static_body:
		static_body.disabled = false


func get_interactible():
	if used:
		return null
	return [type, value]
func get_type():
	if used:
		return null
	return type
func get_value():
	if used:
		return null
	return value
func destroy():
	visible = false
	monitoring = false
	monitorable = false
	collision_body.disabled = true
	if static_body:
		static_body.disabled = true
	used = true
func disable():
	monitoring = false
	monitorable = false
	collision_body.monitoring = false
	collision_body.monitorable = false
	collision_body.disabled = true
	used = true

func interacted_with():
	match destroy_on_use:
		true:
			destroy()
		false:
			pass
	match disable_on_use:
		true:
			disable()
		false:
			pass
