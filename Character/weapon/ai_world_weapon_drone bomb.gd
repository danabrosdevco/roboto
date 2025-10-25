extends AIWorldWeapon
class_name AIWeaponDroneBomb

@export var bomb_scene: PackedScene

func fire():
	play_shot_audio()
	fire_bomb()
	#print ("WEAPON FIRED!")

func play_shot_audio():
	if !shot_audio:
		return
	shot_audio.play()


func fire_bomb():
	var new_bomb = bomb_scene.instantiate()
	get_tree().current_scene.add_child(new_bomb)
	# 1. Set starting position at tracer origin (on the weapon)
	new_bomb.global_position = global_position
	# 2. Get world-space forward direction from tracer_origin
