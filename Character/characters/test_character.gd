extends CharacterBody3D
class_name Player

# Node References # 
@onready var cam: Camera3D = $Camera3D
@export var faction: Enums.Factions = Enums.Factions.PLAYER
@export var world: Node3D
@export var hud: Control
@export var scanner: Node3D
@export var tracer_origin: Node3D
@export var muzzle_flash: Node3D
@export var weapon_model: Node3D
@export var projectile_scene: PackedScene
@export var tracer_scene: PackedScene
@export var reload_sounds: Array[AudioStreamPlayer3D]
@export var reload_delays: Array[float]
@export var command_marker_scene: PackedScene
@export var rifle_stream_player: AudioStreamPlayer3D
@export var click_stream_player: AudioStreamPlayer3D
@export var reload_stream_player: AudioStreamPlayer3D
# Export Data # 
const SPEED := 6.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.002
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var health = 100
@export var recoil_curve: Curve

const LEAN_ANGLE := 0.35
const LEAN_SPEED := 5.0
const ADS_FOV := 45.0
const HIP_FOV := 70.0
const ADS_SPEED := 10.0
const FIRE_RATE := 0.0705
const reload_return_speed:= 30
# Enums #

# Working Data #

signal activate_scanner_ui
signal highlight_enemy(target:Node3D, duration: float)


var is_fullscreen = false
var look_direction: Vector3
@export var look_interp_speed := 12.0  # how fast the camera follows the target
var fire_cooldown := 0.0
var recoil_amount := 0.0
var recoil_per_shot := 3
const recoil_duration = 0.25
var recoil_timer := 0.0
var recoil_horizontal := 0.0
var command_marker_instance: Node3D = null
@export var camera_recoil_scale := 0.75  # fraction of recoil applied to camera
var camera_recoil_current := Vector3.ZERO  # yaw (x), pitch (y)
var recoil_rotation := Vector3.ZERO

var scanner_timer: = 0.0
var scanner_cooldown = 3

var ads_position := Vector3(0.0,0.0,-1.077)
var ads_rotation := Vector3(0.0,0.0,3.0)
var reload_rotation := Vector3(0.2,20.5,58.0)
var reload_position := Vector3(0.31,-0.425,-0.015)

# --- Weapon Bob (Idle Sway) ---
@export var bob_speed := 1.1            # how fast the gun bobs (Hz)
@export var bob_amount := 0.015          # how far the gun moves when hip-firing
@export var ads_bob_scale := 0.05         # how much to reduce bob when ADS (0.2 = 80% less)
@export var movement_bob_scale := 2.2    # scale bobbing when moving
var bob_time := 0.0                      # internal timer


# Base transform snapshot
const base_weapon_position := Vector3(0.31,-0.425,-0.015)
const base_weapon_rotation := Vector3(-0.3,6.0,2.8)


var is_ads := false
var magazine_size: int = 30
var magazine_capacity: int = 30
const tracers_in_mag: Array[int] = [30, 27, 25, 22, 20, 17, 15, 12, 10, 7, 5, 4, 3, 2, 1, 0]
var tracer: bool = false
var is_reloading := false
var from
var to

@export var reload_time := 2.15 # seconds to reload

var target_lean := 0.0
var pitch := 0.0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	hud.update_status(health, magazine_capacity, magazine_size)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Update the clean look direction, not the actual camera yet
		look_direction.y -= event.relative.x * MOUSE_SENS  # yaw
		look_direction.x = clamp(
			look_direction.x - event.relative.y * MOUSE_SENS, 
			-1.5, 
			1.5
		)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _physics_process(delta: float) -> void:
	fire_cooldown -= delta
	scanner_timer -= delta
	handle_gravity(delta)
	handle_input(delta)
	handle_movement(delta)
	handle_camera_and_weapon(delta)
	handle_weapon_logic(delta)

	move_and_slide()
func handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta


func handle_input(_delta: float) -> void:
	if Input.is_action_just_pressed("fullscreen"):
		is_fullscreen = !is_fullscreen
		if is_fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	if Input.is_action_just_pressed("command"):
		activate_command()

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if Input.is_action_just_pressed("scan"):
		if scanner_timer >= 0:
			return
		scanner_timer = scanner_cooldown
		scanner.activate_scan()
		activate_scanner_ui.emit()

	if Input.is_action_just_pressed("reload") and not is_reloading and magazine_capacity < magazine_size:
		start_reload()

	is_ads = Input.is_action_pressed("aim")

	if Input.is_action_pressed("lean_left"):
		target_lean = LEAN_ANGLE
	elif Input.is_action_pressed("lean_right"):
		target_lean = -LEAN_ANGLE
	else:
		target_lean = 0.0


func handle_movement(_delta: float) -> void:
	var input2 := Input.get_vector("ui_left", "ui_right", "ui_down", "ui_up")
	var new_basis = transform.basis
	var dir = new_basis.x * input2.x - new_basis.z * input2.y

	if dir.length_squared() > 0.001:
		dir = dir.normalized() * SPEED
		velocity.x = dir.x
		velocity.z = dir.z
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)


func handle_camera_and_weapon(delta: float) -> void:
	# Weapon Bobbing
	var move_factor = clamp(velocity.length() / SPEED, 0.0, 1.0)
	bob_time += delta * bob_speed * (1.0 + move_factor * movement_bob_scale)

	var current_bob_amount := bob_amount
	if is_ads:
		current_bob_amount *= ads_bob_scale

	var bob_offset = Vector3(
		sin(bob_time * 2.0) * current_bob_amount * 0.5,
		abs(sin(bob_time)) * current_bob_amount,
		0.0
	)

# FOV & Lean
	var target_fov: float
	if is_ads:
		if Input.is_action_pressed("zoom"):
			target_fov = ADS_FOV * 0.6
		else:
			target_fov = ADS_FOV
	else:
		target_fov = HIP_FOV

	if abs(cam.fov - target_fov) > 0.01:
		cam.fov = lerp(cam.fov, target_fov, delta * ADS_SPEED)
	cam.rotation.z = lerp(cam.rotation.z, target_lean, delta * LEAN_SPEED)

	# Weapon Pose Interpolation
	var target_pos: Vector3
	var target_rot: Vector3

	if is_reloading:
		target_pos = reload_position
		target_rot = reload_rotation
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

	# Rotation interpolation (look direction)
	rotation.y = lerp_angle(rotation.y, look_direction.y, delta * look_interp_speed)
	cam.rotation.x = lerp_angle(cam.rotation.x, look_direction.x, delta * look_interp_speed)

	# Apply recoil
	cam.rotation_degrees.x += camera_recoil_current.x
	cam.rotation_degrees.y += camera_recoil_current.y
	weapon_model.rotation_degrees = weapon_model.rotation + recoil_rotation + bob_rotation


func handle_weapon_logic(_delta: float) -> void:
	if not is_reloading and fire_cooldown <= 0.0:
		if magazine_capacity > 0 and Input.is_action_pressed("fire"):
			fire()
			fire_cooldown = FIRE_RATE
		elif magazine_capacity <= 0 and Input.is_action_just_pressed("fire"):
			click_stream_player.play()
			fire_cooldown = FIRE_RATE

func activate_command():
	# Raycast from the camera to where it's looking
	var ray_origin = cam.global_position
	var ray_end = ray_origin + cam.global_transform.basis.z * -1000  # Forward direction in Godot is -Z
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collision_mask = 1  # Set this if your terrain/ground uses a specific mask

	var result = space_state.intersect_ray(query)

	if result:
		var target_position = result.position

		# If we already have a command marker, move it
		if command_marker_instance and is_instance_valid(command_marker_instance):
			command_marker_instance.global_position = target_position
			command_marker_instance.global_position.y = 0
			command_marker_instance.rotation = Vector3(0,0,0)
			command_marker_instance.perform_faction_check()
		else:
			# Spawn new marker
			command_marker_instance = command_marker_scene.instantiate()
			world.add_child(command_marker_instance)
			command_marker_instance.global_position = target_position
			command_marker_instance.global_position.y = 0
			command_marker_instance.rotation = Vector3(0,0,0)

			# Optional: Assign faction/team if needed
			if command_marker_instance.has_method("set_faction"):
				command_marker_instance.set_faction(faction)
			await get_tree().create_timer(0.1).timeout
			command_marker_instance.perform_faction_check()
			# Optional: orient marker to look forward from camera
			#command_marker_instance.look_at(target_position + cam.global_transform.basis.z * -1, Vector3.UP)
	else:
		print("No valid target point found where camera is looking.")
	pass


func fire() -> void:
	for i in tracers_in_mag:
		if magazine_capacity == i:
			tracer = true
			break
		else:
			tracer = false
	recoil_timer = recoil_duration
	recoil_horizontal = randf_range(-1.0, 1.0) * 2.0 * 0.5*recoil_per_shot # control horizontal sway strength
	# Existing raycast and muzzle flash code...
	# Raycast
	
	from = cam.global_position
	to = from + tracer_origin.global_transform.basis.x.normalized() * 250.0

	var space_state = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.exclude = [self]

	rifle_stream_player.play()

	var result = space_state.intersect_ray(query)
	# Muzzle flash
	muzzle_flash.play_flash()
	# Hit detection
	if result:
		#var hit_pos = result.position
		var collider = result.collider
		#print("Hit:", collider, " at ", hit_pos)
		#var sphere = MeshInstance3D.new()
		#sphere.mesh = SphereMesh.new()
		#sphere.mesh.radius = 0.05  # Very small
		#sphere.mesh.height = 0.1   # Optional if you want a stretched look
		#sphere.global_position = hit_pos
		#get_tree().current_scene.add_child(sphere)
		if collider.has_method("apply_damage"):
			collider.apply_damage(10)
		else:
			if collider.get_parent().has_method("apply_damage"):
				collider.apply_damage(10)
	if tracer:
		fire_tracer()
	magazine_capacity = max(0, magazine_capacity - 1)
	tracer = false
	hud.update_status(health, magazine_capacity, magazine_size)


func fire_tracer():
	var new_tracer = tracer_scene.instantiate()
	world.add_child(new_tracer)
	# 1. Set starting position at tracer origin (on the weapon)
	new_tracer.global_position = tracer_origin.global_position
	# 2. Get world-space forward direction from tracer_origin
	var dir = tracer_origin.global_transform.basis.x.normalized()
	# 3. Set the tracer's direction (assuming it has a .direction property)
	new_tracer.direction = dir
	# 4. Point it visually in the direction (optional but good for visuals)
	new_tracer.look_at(new_tracer.global_position + dir)




# 🔁 Reload Handling
func start_reload() -> void:
	is_reloading = true
	play_reload_sequence()
	#print("Reloading...")
	await get_tree().create_timer(reload_time).timeout
	magazine_capacity = magazine_size
	is_reloading = false
	hud.update_status(health, magazine_capacity, magazine_size)
	#print("Reload complete.")
func play_reload_sequence():
	for i in reload_sounds.size():
		var sound = reload_sounds[i]
		var delay = reload_delays[i]
		await get_tree().create_timer(delay).timeout
		sound.play()


func _on_scanner_highlight_target(target: Node3D, duration: float) -> void:
	#print ("TIME TO HIGHLIGHT!")
	highlight_enemy.emit(target, duration)


func apply_damage(damage):
	health -= damage
	hud.update_status(health, magazine_capacity, magazine_size)
	if health <= 0:
		health = 0
		die()
	pass

func die():
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	# Delay to allow any death effects (like sounds, particles)
	await get_tree().create_timer(0.25).timeout
	# Show cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Optional: Unlock the camera or transition
	# You might want to detach camera from the player before freeing the node
	# For now, we just clean up:
	queue_free()

func get_faction():
	return faction
