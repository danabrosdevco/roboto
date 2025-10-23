extends RigidBody3D

@export var explosion_scene: PackedScene  # Assign your explosion scene in the editor
@export var explosion_radius: float = 6.0
@export var explosion_damage: int = 50

func _ready():
	# Optional: Set downward velocity or let gravity handle it
	linear_velocity = Vector3(0, -5, 0)

func _integrate_forces(state):
	# Optional: Limit max fall speed
	if linear_velocity.y < -50:
		linear_velocity.y = -50

func _on_body_entered(body: Node):
	if body != self:
		explode()
		await get_tree().create_timer(1.5).timeout
		queue_free()

func explode():
	if not explosion_scene:
		print("No explosion scene assigned!")
		return

	var explosion_instance = explosion_scene.instantiate()
	explosion_instance.global_position = global_position
	explosion_instance.radius = explosion_radius
	explosion_instance.damage = explosion_damage
	get_tree().current_scene.add_child(explosion_instance)
