extends StaticBody3D

@export var faction = Enums.Factions.ENEMY
@export var health = 30
@export var obstacle = true

func apply_damage(damage):
	health -= damage
	if health <= 0:
		die()
	pass

func get_faction():
	return faction

func die():
	await get_tree().create_timer(0.25	).timeout
	queue_free()

func get_obstacle():
	return obstacle
