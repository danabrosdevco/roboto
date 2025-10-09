extends Node3D
class_name AIWorldWeapon

@export var muzzle_flash: MuzzleFlash
@export var muzzle_origin: Node3D
@export var shot_audio: AudioStreamPlayer3D
@export var tracer_scene: PackedScene

func fire():
	play_shot_audio()
	play_muzzle_flash()
	fire_tracer()
	print ("WEAPON FIRED!")

func play_shot_audio():
	shot_audio.play()

func play_muzzle_flash():
	muzzle_flash.play_flash()

func fire_tracer():
	var new_tracer = tracer_scene.instantiate()
	add_child(new_tracer)
	# 1. Set starting position at tracer origin (on the weapon)
	new_tracer.global_position = muzzle_origin.global_position
	# 2. Get world-space forward direction from tracer_origin
	var dir = muzzle_origin.global_transform.basis.x.normalized()
	# 3. Set the tracer's direction (assuming it has a .direction property)
	new_tracer.direction = dir
	# 4. Point it visually in the direction (optional but good for visuals)
	new_tracer.look_at(new_tracer.global_position + dir)
