extends Node3D
class_name AIWorldWeapon

@export var muzzle_flash: MuzzleFlash
@export var muzzle_origin: Node3D
@export var shot_audio: AudioStreamPlayer3D
@export var tracer_scene: PackedScene

func fire():
	play_shot_audio()
	play_muzzle_flash()
	fire_tracer_spread()
	#print ("WEAPON FIRED!")

func play_shot_audio():
	shot_audio.play()

func play_muzzle_flash():
	muzzle_flash.play_flash()

## Hostile by default. A world-placed emplacement shooting at you is the enemy;
## nothing here has a faction to ask, and if a friendly one is ever wanted this
## grows an export then rather than guessing now.
##
## BOTH PATHS IN THIS FILE ARE CURRENTLY UNREACHABLE — ai_drone_bomb_weapon.tscn
## is referenced by nothing and does not set tracer_scene, and
## appx/ai_world_weapon.tscn has no users either. Tinted anyway so that "every
## tracer spawner colours its round" has no exceptions waiting to be rediscovered.
const WORLD_WEAPON_FACTION := Enums.Factions.ENEMY

func fire_tracer():
	var new_tracer = tracer_scene.instantiate()
	add_child(new_tracer)
	if new_tracer.has_method("set_side"):
		new_tracer.set_side(WORLD_WEAPON_FACTION)
	# 1. Set starting position at tracer origin (on the weapon)
	new_tracer.global_position = muzzle_origin.global_position
	# 2. Get world-space forward direction from tracer_origin
	var dir = muzzle_origin.global_transform.basis.x.normalized()
	# 3. Set the tracer's direction (assuming it has a .direction property)
	new_tracer.direction = dir
	# 4. Point it visually in the direction (optional but good for visuals)
	new_tracer.look_at(new_tracer.global_position + dir)

func fire_tracer_spread(spread_count := 8, spread_angle_degrees := 10.0):
	for i in spread_count:
			var new_tracer = tracer_scene.instantiate()
			add_child(new_tracer)
			if new_tracer.has_method("set_side"):
				new_tracer.set_side(WORLD_WEAPON_FACTION)
			new_tracer.global_position = muzzle_origin.global_position
			# Godot forward is -Z, but your muzzle uses +X
			var base_dir = muzzle_origin.global_transform.basis.x.normalized()
			var angle_y = deg_to_rad(randf_range(-spread_angle_degrees, spread_angle_degrees))
			var angle_z = deg_to_rad(randf_range(-spread_angle_degrees, spread_angle_degrees))
			var spread_basis = Basis()
			spread_basis = spread_basis.rotated(Vector3.UP, angle_y)
			spread_basis = spread_basis.rotated(Vector3.FORWARD, angle_z)
			var final_dir = (spread_basis * base_dir).normalized()
			new_tracer.direction = final_dir
			# Align forward (-Z) with +X direction
			new_tracer.look_at(new_tracer.global_position + final_dir, Vector3.UP)
