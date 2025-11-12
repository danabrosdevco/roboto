extends Node3D
class_name PickUp
@export var model: Node3D
var time : float
@export var type: Enums.PickUpTypes
@export var value: int

func _process(delta: float) -> void:
	time += delta
	rotation.y += delta * 2.0 # constant spin
	rotation.x = sin(time * 1.5) * 0.05 # gentle wobble
	rotation.z = cos(time * 1.5) * 0.05
func _on_area_3d_body_entered(body: Node3D) -> void:
	if body is Player:
		match type:
			Enums.PickUpTypes.SHARDS:
				body.add_shards(value)
				pass
			Enums.PickUpTypes.HEALTH:
				body.apply_healing(value)
				model.visible = false
		pass

	
