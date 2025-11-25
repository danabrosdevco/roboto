extends Node
class_name AIManager

@export var world: World
@export var enemies: Array [AI]
@export var player: Player

func register_enemy(new_enemy:AI):
	enemies.append(new_enemy)
	new_enemy.player = player

func deregister_enemy(enemy):
	enemies.erase(enemy)

func reset_all_reg_enemies():
	enemies = []

func on_sound_emitted(location: Vector3, meter_distance: float):
	pass
