extends CharacterBody3D

const SPEED := 6.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.002
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@export var projectile_scene: PackedScene
@export var muzzle_flash: Node3D
@export var reload_sounds: Array[AudioStreamPlayer3D]
@export var reload_delays: Array[float]

const LEAN_ANGLE := 0.35
const LEAN_SPEED := 5.0
const ADS_FOV := 45.0
const HIP_FOV := 70.0
const ADS_SPEED := 10.0
const FIRE_RATE := 0.0705
var fire_cooldown := 0.0

var recoil_amount := 0.0
const RECOIL_DECAY := 8.0

var is_ads := false
var magazine_size: int = 30
var magazine_capacity: int = 30
var is_reloading := false

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
		rotate_y(-event.relative.x * MOUSE_SENS)
		pitch = clamp(pitch - event.relative.y * MOUSE_SENS, -1.5, 1.5)
		rotation.x = pitch
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _physics_process(delta: float) -> void:
	fire_cooldown -= delta

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

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
	recoil_amount += 0.03

	# Raycast
	var from = cam.global_position
	var to = from + -cam.global_transform.basis.z * 100.0

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

	magazine_capacity = max(0, magazine_capacity - 1)


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
