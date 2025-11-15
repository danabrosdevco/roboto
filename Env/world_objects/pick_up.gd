extends Node3D
class_name PickUp

@export var model: Node3D
@export var collision_shape: CollisionShape3D
@export var type: Enums.PickUpTypes
@export var value: int = 1

# NEW FLAGS
@export var destroy_on_use: bool = false
@export var single_use: bool = true
@export var respawns_on_reset: bool = true

var time: float = 0.0
var used: bool = false
var spawn_position: Vector3

func _ready():
	spawn_position = global_position

func _process(delta: float) -> void:
	if used:
		return
	time += delta
	rotation.y += delta * 2.0 # constant spin
	rotation.x = sin(time * 1.5) * 0.05 # gentle wobble
	rotation.z = cos(time * 1.5) * 0.05

func _on_area_3d_body_entered(body: Node3D) -> void:
	if used and single_use:
		return
	if body is Player:
		match type:
			Enums.PickUpTypes.SHARDS:
				body.add_shards(value)
			Enums.PickUpTypes.HEALTH:
				body.apply_healing(value)

		# Handle post-use logic
		if single_use:
			used = true
			hide_pickup()

func hide_pickup():
	model.visible = false
	set_deferred("collision_shape.disabled", true)
	set_process(false)

func reset():
	if not respawns_on_reset:
		return
	used = false
	global_position = spawn_position
	model.visible = true
	collision_shape.disabled = false
	set_process(true)
