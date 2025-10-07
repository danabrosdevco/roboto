extends CharacterBody3D
@export var faction: Enums.Factions = Enums.Factions.PLAYER
@export var world: Node3D
@export var hud: Control
signal activate_scanner_ui
signal highlight_enemy(target:Node3D)
const SPEED := 6.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.002
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var tracer_scene: PackedScene
@export var tracer_origin: Node3D
@export var projectile_scene: PackedScene
@export var muzzle_flash: Node3D
@export var weapon_model: Node3D
@export var reload_sounds: Array[AudioStreamPlayer3D]
@export var reload_delays: Array[float]
@export var recoil_curve: Curve
@export var scanner: Node3D
var is_fullscreen = false
const LEAN_ANGLE := 0.35
const LEAN_SPEED := 5.0
const ADS_FOV := 45.0
const HIP_FOV := 70.0
const ADS_SPEED := 10.0
const FIRE_RATE := 0.0705
const reload_return_speed:= 30
var look_direction: Vector3
@export var look_interp_speed := 12.0  # how fast the camera follows the target
var fire_cooldown := 0.0
var recoil_amount := 0.0
var recoil_per_shot := 3
const recoil_duration = 0.25
var recoil_timer := 0.0
var recoil_horizontal := 0.0
@export var camera_recoil_scale := 0.75  # fraction of recoil applied to camera
var camera_recoil_current := Vector3.ZERO  # yaw (x), pitch (y)
var recoil_rotation := Vector3.ZERO

var scanner_timer: = 0.0
var scanner_cooldown = 20

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
@export var rifle_stream_player: AudioStreamPlayer3D
@export var click_stream_player: AudioStreamPlayer3D
@export var reload_stream_player: AudioStreamPlayer3D

var target_lean := 0.0
var pitch := 0.0

@onready var cam: Camera3D = $Camera3D

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


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

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	if Input.is_action_just_pressed("fullscreen"):
		is_fullscreen = !is_fullscreen
		if is_fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	if Input.is_action_just_pressed("scan"):
		scanner.activate_scan()
		activate_scanner_ui.emit()
	# Movement
	var input2 := Input.get_vector("ui_left", "ui_right", "ui_down", "ui_up")
	var dir := (transform.basis.x * input2.x) + (-transform.basis.z * input2.y)
	if dir.length() > 0.001:
		dir = dir.normalized() * SPEED
		velocity.x = dir.x
		velocity.z = dir.z
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

	# Lean
	if Input.is_action_pressed("lean_left"):
		target_lean = LEAN_ANGLE
	elif Input.is_action_pressed("lean_right"):
		target_lean = -LEAN_ANGLE
	else:
		target_lean = 0.0

	is_ads = Input.is_action_pressed("aim")
	#if is_ads:
		#
		
	# --- Weapon Bob ---
	# Increment time based on movement speed
	var move_factor = clamp(velocity.length() / SPEED, 0.0, 1.0)
	bob_time += delta * bob_speed * (1.0 + move_factor * movement_bob_scale)

	# Choose bob amplitude based on ADS
	var current_bob_amount := bob_amount

	if is_ads:
		current_bob_amount *= ads_bob_scale
	# Apply sine-wave based offset for natural motion
	var bob_offset = Vector3(
		sin(bob_time * 2.0) * current_bob_amount * 0.5,  # slight horizontal wobble
		abs(sin(bob_time)) * current_bob_amount,         # vertical bounce
		0.0
	)



	# FOV transition
	var target_fov
	if is_ads:
		target_fov = ADS_FOV
		if Input.is_action_pressed("zoom"):
			target_fov = ADS_FOV * 0.6
	else:
		target_fov = HIP_FOV

	cam.fov = lerp(cam.fov, target_fov, delta * ADS_SPEED)
	cam.rotation.z = lerp(cam.rotation.z, target_lean, delta * LEAN_SPEED)
	# --- ADS / RELOAD state transitions ---
	if is_reloading:
		# Lerp toward reload pose
		weapon_model.position = weapon_model.position.lerp(reload_position, delta * reload_return_speed)
		weapon_model.rotation = weapon_model.rotation.lerp(reload_rotation, delta * reload_return_speed)
	elif is_ads:
		# Lerp toward ADS pose
		weapon_model.position = weapon_model.position.lerp(ads_position, delta * ADS_SPEED)
		weapon_model.rotation = weapon_model.rotation.lerp(ads_rotation, delta * ADS_SPEED)
	else:
		# Return to base
		weapon_model.position = weapon_model.rotation.lerp(base_weapon_position, delta * ADS_SPEED)
		weapon_model.rotation = weapon_model.rotation.lerp(base_weapon_rotation, delta * ADS_SPEED)
	if not is_reloading:
		weapon_model.position += bob_offset
	if recoil_timer > 0.0:
		recoil_timer -= delta
		var t = 1.0 - (recoil_timer / recoil_duration)
		t = clamp(t, 0.0, 1.0)
		
		# --- WEAPON RECOIL (visual) ---
		pitch = recoil_curve.sample(t) * recoil_per_shot
		var yaw = recoil_horizontal * (1.0 - t)  # decays horizontally
		recoil_rotation = Vector3(0, yaw, pitch)
		
		# --- CAMERA RECOIL (gameplay effect) ---
		var cam_pitch_kick = pitch * camera_recoil_scale
		camera_recoil_current = Vector3(cam_pitch_kick, 0, 0)
		pitch = clamp(
	pitch - deg_to_rad(camera_recoil_current.x),  # pitch up
	-1.5, 1.5
	)
	
	var bob_rotation = Vector3(
	sin(bob_time * 2.0) * current_bob_amount * 20.0,  # tilt side to side
	sin(bob_time) * current_bob_amount * 10.0,        # yaw wobble
	0.0
	)


# --- CAMERA & RECOIL ROTATION INTERPOLATION ---
# Smoothly move the player's rotation toward the look_direction (yaw)
	var current_yaw = rotation.y
	var target_yaw = look_direction.y
	current_yaw = lerp_angle(current_yaw, target_yaw, delta * look_interp_speed)
	rotation.y = current_yaw

# Smoothly move the camera pitch toward look_direction.x
	var current_pitch = cam.rotation.x
	var target_pitch = look_direction.x
	current_pitch = lerp_angle(current_pitch, target_pitch, delta * look_interp_speed)
	cam.rotation.x = current_pitch

# Apply recoil offset (temporary offset on top)
	cam.rotation_degrees.x += camera_recoil_current.x
	cam.rotation_degrees.y += camera_recoil_current.y
	weapon_model.rotation_degrees = weapon_model.rotation + recoil_rotation + bob_rotation
	# 🔫 Firing Logic
	if not is_reloading and fire_cooldown <= 0.0:
		if magazine_capacity > 0:
			if Input.is_action_pressed("fire"):
				fire()
				fire_cooldown = FIRE_RATE
		else:
			if Input.is_action_just_pressed("fire"):
				click_stream_player.play()
				fire_cooldown = FIRE_RATE

	# 🔁 Reload Logic
	if Input.is_action_just_pressed("reload") and not is_reloading and magazine_capacity < magazine_size:
		start_reload()

	move_and_slide()


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

	# Projectile
	#var new_bullet = projectile_scene.instantiate()
	#new_bullet.initiate(Vector3(cam.rotation.x, cam.rotation.y, cam.rotation.z))
	#add_child(new_bullet)

	# Muzzle flash
	muzzle_flash.play_flash()

	# Hit detection
	if result:
		var hit_pos = result.position
		var collider = result.collider
		print("Hit:", collider, " at ", hit_pos)
		if collider.has_method("apply_damage"):
			collider.apply_damage(10)
	if tracer:
		fire_tracer()
	magazine_capacity = max(0, magazine_capacity - 1)
	tracer = false


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
	print("Reloading...")
	await get_tree().create_timer(reload_time).timeout
	magazine_capacity = magazine_size
	is_reloading = false
	print("Reload complete.")
func play_reload_sequence():
	for i in reload_sounds.size():
		var sound = reload_sounds[i]
		var delay = reload_delays[i]
		await get_tree().create_timer(delay).timeout
		sound.play()


func _on_scanner_highlight_target(target: Node3D) -> void:
	highlight_enemy.emit(target)
