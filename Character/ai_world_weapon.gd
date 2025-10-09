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

func fire_tracer_spread(spread_count := 8, spread_angle_degrees := 10.0):
	for i in spread_count:
		var new_tracer = tracer_scene.instantiate()
		add_child(new_tracer)

		# 1. Starting position
		new_tracer.global_position = muzzle_origin.global_position

		# 2. Base forward direction (e.g. +X)
		var base_dir = muzzle_origin.global_transform.basis.x.normalized()

		# 3. Apply random spread in Y and Z (like a cone)
		var angle_y = deg_to_rad(randf_range(-spread_angle_degrees, spread_angle_degrees))
		var angle_z = deg_to_rad(randf_range(-spread_angle_degrees, spread_angle_degrees))

		var spread_basis = Basis()
		spread_basis = spread_basis.rotated(Vector3.UP, angle_y)
		spread_basis = spread_basis.rotated(Vector3.FORWARD, angle_z)

		var final_dir = (spread_basis * base_dir).normalized()

		# 4. Assign direction and rotate tracer
		new_tracer.direction = final_dir
		new_tracer.look_at(new_tracer.global_position + final_dir)
