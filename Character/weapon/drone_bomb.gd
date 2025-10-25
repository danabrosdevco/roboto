extends RigidBody3D

@export var explosion_scene: PackedScene  # Assign your explosion scene in the editor
@export var explosion_radius: float = 6.0
@export var explosion_damage: int = 50
var impact_position

func _ready():
	pass
	## Optional: Set downward velocity or let gravity handle it
	#linear_velocity = Vector3(0, -5, 0)

#func _integrate_forces(_state):
	## Optional: Limit max fall speed
	#if linear_velocity.y < -85:
		#linear_velocity.y = -85

func _on_body_entered(body: Node):
	#print ("BOMB TOUCHED!")
	if body != self:
		impact_position = global_position
		await explode()
		queue_free()

func explode():
	if not explosion_scene:
		print("No explosion scene assigned!")
		return
	var explosion_instance = explosion_scene.instantiate()
	get_tree().current_scene.add_child(explosion_instance)
	explosion_instance.global_position = impact_position
	return
	#explosion_instance.radius = explosion_radius
	#explosion_instance.damage = explosion_damage


func _on_body_shape_entered(_body_rid: RID, body: Node, _body_shape_index: int, _local_shape_index: int) -> void:
	print ("BOMB TOUCHED!")
	if body != self:
		explode()
		await get_tree().create_timer(0.75).timeout
		queue_free()
