extends Node3D
class_name AIWorldWeapon

@export var muzzle_flash: MuzzleFlash
@export var muzzle_origin: Node3D
@export var shot_audio: AudioStreamPlayer3D

func fire():
	play_shot_audio()
	play_muzzle_flash()

func play_shot_audio():
	shot_audio.play()

func play_muzzle_flash():
	muzzle_flash.play_flash()
