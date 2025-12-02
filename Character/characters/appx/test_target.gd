extends StaticBody3D

@export var faction = Enums.Factions.ENEMY
@export var health = 30
@export var obstacle = true
var alive: bool = true

func apply_damage(damage):
	if alive == false:
		return
	health -= damage
	if health <= 0:
		alive = false
		die()
		print (name + (" has died!"))
	pass
func get_faction():
	return faction

func die():
	await get_tree().create_timer(0.25	).timeout
	queue_free()

func get_obstacle():
	return obstacle
