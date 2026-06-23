extends Node3D
class_name HUDWeapon

# Node References # 
@export var cam: Camera3D
@export var tracer_origin: Node3D
@export var muzzle_flash: Node3D
@export var weapon_model: Node3D
@export var projectile_scene: PackedScene
@export var tracer_scene: PackedScene
@export var reload_sounds: Array[AudioStreamPlayer3D]
@export var reload_delays: Array[float]
@export var rifle_stream_player: AudioStreamPlayer3D
@export var click_stream_player: AudioStreamPlayer3D
# Weapon Data #
@export var firemode: Enums.FireModes
@export var damage: int = 10
@export var recoil_curve: Curve
@export var recoil_duration = 0.25
@export var recoil_per_shot : float = 2.0
@export var look_interp_speed := 12.0  # how fast the camera follows the target
@export var LEAN_ANGLE := 0.35
@export var LEAN_SPEED := 5.0
@export var ADS_FOV := 45.0
@export var HIP_FOV := 70.0
@export var ADS_SPEED := 10.0
@export var FIRE_RATE := 0.100
@export var reload_return_speed:= 30
@export var camera_recoil_scale := 0.75  # fraction of recoil applied to camera
@export var ads_position := Vector3(0.0,0.0,-1.077)
@export var ads_rotation := Vector3(0.0,0.0,3.0)
@export var reload_rotation := Vector3(0.2,20.5,58.0)
@export var reload_position := Vector3(0.31,-0.425,-0.015)
@export var base_weapon_position := Vector3(0.31,-0.425,-0.015)
@export var base_weapon_rotation := Vector3(-0.3,6.0,2.8)
@export var obstructed_weapon_position = Vector3(-0.5, -0.425, -1)
@export var obstructed_weapon_rotation = Vector3(0.3, 270, 3)
@export var magazine_size: int = 30
@export var tracers_in_mag: Array[int] = [30, 27, 25, 22, 20, 17, 15, 12, 10, 7, 5, 4, 3, 2, 1, 0]
@export var reload_time := 2.15 # seconds to reload
@export var bob_speed := 1.1            # how fast the gun bobs (Hz)
@export var bob_amount := 0.015          # how far the gun moves when hip-firing
@export var ads_bob_scale := 0.05         # how much to reduce bob when ADS (0.2 = 80% less)
@export var movement_bob_scale := 2.2    # scale bobbing when moving
# Working Data #
var move_factor
@export var active: bool = true
var magazine_capacity:= 16
var fire_cooldown := 0.0
var recoil_amount := 0.0
var recoil_timer := 0.0
var recoil_horizontal := 0.0
var recoil_vertical := 0.0
var camera_recoil_current := Vector3.ZERO  # yaw (x), pitch (y)
var recoil_rotation := Vector3.ZERO
var is_obstructed :=false
var is_ads := false
var tracer: bool = false
var is_reloading := false
var from
var to
var bob_time := 0.0
var target_lean := 0.0
var pitch := 0.0

signal request_status

func _ready() -> void:
	cam = get_parent()
	magazine_capacity = magazine_size
	muzzle_flash.play_flash()
	pass
func _physics_process(delta: float) -> void:
	if active == false:
		return
	fire_cooldown -= delta
	handle_camera_and_weapon(delta)

func set_move_factor(new_move_factor: float):
	move_factor = new_move_factor

func handle_camera_and_weapon(delta: float) -> void:
	if move_factor == null:
		return
	bob_time += delta * bob_speed * (1.0 + move_factor * movement_bob_scale)
	var current_bob_amount := bob_amount
	if is_ads:
		current_bob_amount *= ads_bob_scale
	var bob_offset = Vector3(
		sin(bob_time * 2.0) * current_bob_amount * 0.5,
		abs(sin(bob_time)) * current_bob_amount,
		0.0
	)
	# Weapon Pose Interpolation
	var target_pos: Vector3
	var target_rot: Vector3
	if is_reloading:
		target_pos = reload_position
		target_rot = reload_rotation
	elif is_obstructed:
		target_pos = obstructed_weapon_position
		target_rot = obstructed_weapon_rotation
	elif is_ads:
		target_pos = ads_position
		target_rot = ads_rotation
	else:
		target_pos = base_weapon_position
		target_rot = base_weapon_rotation
	if weapon_model.position.distance_to(target_pos) > 0.001:
		weapon_model.position = weapon_model.position.lerp(target_pos, delta * ADS_SPEED)
	if weapon_model.rotation.distance_to(target_rot) > 0.001:
		weapon_model.rotation = weapon_model.rotation.lerp(target_rot, delta * ADS_SPEED)
	if not is_reloading:
		weapon_model.position += bob_offset
	# Recoil
	if recoil_timer > 0.0:
		recoil_timer -= delta
		var t = clamp(1.0 - (recoil_timer / recoil_duration), 0.0, 1.0)
		var pitch_offset = recoil_curve.sample(t) * recoil_per_shot
		var yaw = recoil_horizontal * (1.0 - t)
		recoil_rotation = Vector3(0, yaw, pitch_offset)
		camera_recoil_current = Vector3(pitch_offset * camera_recoil_scale, 0, 0)
		pitch = clamp(pitch - deg_to_rad(camera_recoil_current.x), -1.5, 1.5)
	var bob_rotation = Vector3(
		sin(bob_time * 2.0) * current_bob_amount * 20.0,
		sin(bob_time) * current_bob_amount * 10.0,
		0.0
	)
	cam.rotation.x = lerp_angle(cam.rotation.x, cam.get_parent().look_direction.x, delta * look_interp_speed)
	cam.rotation_degrees.x += camera_recoil_current.x
	cam.rotation_degrees.y += camera_recoil_current.y
	weapon_model.rotation_degrees = weapon_model.rotation + recoil_rotation + bob_rotation

func fire() -> void:
	if not is_reloading and fire_cooldown <= 0.0:
		if magazine_capacity <= 0:
			click_stream_player.play()
			fire_cooldown = FIRE_RATE
			return
		for i in tracers_in_mag:
			if magazine_capacity == i:
				tracer = true
				break
			else:
				tracer = false
		fire_cooldown = FIRE_RATE
		recoil_timer = recoil_duration
		recoil_horizontal = randf_range(-1.0, 1.0) * 2.0 * 0.5 * recoil_per_shot # control horizontal sway strength
		from = cam.global_position
		to = from + tracer_origin.global_transform.basis.x.normalized() * 250.0
		var space_state = get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.new()
		query.from = from
		query.to = to
		query.exclude = [self]
		rifle_stream_player.play()
		muzzle_flash.play_flash()
		var result = space_state.intersect_ray(query)
		#var sphere = MeshInstance3D.new()
		#sphere.mesh = SphereMesh.new()
		#sphere.mesh.radius = 0.05  # Very small
		#sphere.mesh.height = 0.1   # Optional if you want a stretched look
		#sphere.global_position = hit_pos
		#get_tree().current_scene.add_child(sphere)
		# Hit detection
		if result:
			var collider = result.collider
			if collider.has_method("apply_damage"):
				collider.apply_damage(damage, cam.get_parent())
			else:
				if collider.get_parent().has_method("apply_damage"):
					collider.apply_damage(damage, cam.get_parent())
		if tracer:
			fire_tracer()
		magazine_capacity = max(0, magazine_capacity - 1)
		tracer = false
		request_status.emit()
		# Alert nearby enemies that the player fired
		var player_node = cam.get_parent()
		if player_node and player_node.has_node("../AIManager"):
			var mgr = player_node.get_node("../AIManager")
			if mgr and mgr.stimulus_manager != null:
				mgr.stimulus_manager.emit_stimulus(
					StimulusManager.StimulusType.GUNSHOT_HEARD,
					global_position,
					Enums.Factions.PLAYER,
					player_node
				)
func fire_tracer():
	var new_tracer = tracer_scene.instantiate()
	cam.get_parent().world.add_child(new_tracer)
	new_tracer.global_position = tracer_origin.global_position
	var dir = tracer_origin.global_transform.basis.x.normalized()
	new_tracer.direction = dir
	new_tracer.look_at(new_tracer.global_position + dir)
func start_reload() -> void:
	if active == false:
		return
	if is_reloading == true:
		return
	if magazine_capacity >= magazine_size:
		return
	is_reloading = true
	play_reload_sequence()
	await get_tree().create_timer(reload_time).timeout
	magazine_capacity = magazine_size
	is_reloading = false
	request_status.emit()
func play_reload_sequence():
	for i in reload_sounds.size():
		var sound = reload_sounds[i]
		var delay = reload_delays[i]
		await get_tree().create_timer(delay).timeout
		sound.play()
