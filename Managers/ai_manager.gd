extends Node
class_name AIManager

@export var world: World
@export var enemies: Array [AI]

func register_enemy(new_enemy:AI):
	enemies.append(new_enemy)

func deregister_enemy(enemy:AI):
	enemies.erase(enemy)

func reset_all_reg_enemies():
	for e in enemies:
		deregister_enemy(e)
