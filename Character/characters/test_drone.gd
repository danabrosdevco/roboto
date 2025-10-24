extends CharacterBody3D
class_name TestHelicopter

# === Node References ===
@export var weapon: AIWorldWeapon
@export var hearing: Area3D
@export var sight: Area3D
@export var label: Label3D
@export var bark: Bark
@export var heli_loop: AudioStreamPlayer3D

# === Helicopter Flight Properties ===
@export var health := 60
@export var faction : Enums.Factions = Enums.Factions.ENEMY
@export var move_speed := 40.0
@export var min_speed := 10.0  # helicopter can’t go below this
@export var turn_speed := 0.8  # slower turning
@export var acceleration := 2.0
@export var lift_force := 5.0  # constant upward lift
@export var gravity_force := -9.8
@export var hover_height := 60.0
@export var altitude_smoothness := 3.0
@export var wander_radius := 600.0
@export var wander_delay := 10.0

# === Flocking / Avoidance ===
@export var neighbor_radius := 15.0
@export var separation_weight := 2.0
@export var alignment_weight := 1.0
@export var cohesion_weight := 1.0
@export var obstacle_avoidance_weight := 3.0

# === Weapon Logic ===
@export var fire_cooldown := 6.0
var weapon_target: Vector3
var look_target: Vector3
var fire_time := 0.0
var wander_target := Vector3.ZERO

enum WeaponState { IDLE, AIM, FIRE, RELOAD }
enum MovementState { WANDER, ENGAGE, DEAD }

var weapon_state = WeaponState.IDLE
var movement_state = MovementState.WANDER
var wander_time := 0.0
var current_speed := 0.0
var frame_waited := false
var origin: Vector3

# === Initialization ===
func _ready():
	await get_tree().process_frame
	origin = global_position
	frame_waited = true
	current_speed = move_speed * 0.6
	_pick_new_wander_target()

# === Main Loop ===
func _physics_process(delta):
	if not frame_waited:
		return

	match movement_state:
		MovementState.WANDER:
			_handle_wander(delta)
		MovementState.ENGAGE:
			_handle_engage(delta)
		MovementState.DEAD:
			return

	_handle_weapon_logic(delta)
	fire_time -= delta
	_update_debug_label()

# === Wander Logic ===
func _handle_wander(delta):
	wander_time -= delta
	if wander_time <= 0.0 or global_position.distance_to(wander_target) < 100.0:
		#print ("TIME TO PICK NEW WANDER")
		_pick_new_wander_target()
		wander_time = wander_delay

	_fly_steering(delta, wander_target)

# === Engage Logic ===
func _handle_engage(delta):
	if weapon_target == Vector3.ZERO:
		movement_state = MovementState.WANDER
		return

	# Fly near target but orbit around it
	var offset_dir = (global_position - weapon_target).normalized()
	var orbit_point = weapon_target + offset_dir.rotated(Vector3.UP, deg_to_rad(90)) * 80.0
	_fly_steering(delta, orbit_point)

# === Steering + Flight ===
func _fly_steering(delta, target: Vector3):
	var to_target = (target - global_position).normalized()

	# Adjust desired heading gradually (helicopters don't snap)
	var forward = -global_transform.basis.z
	var new_dir = forward.lerp(to_target, turn_speed * delta).normalized()

	# Maintain constant forward motion
	current_speed = clamp(lerp(current_speed, move_speed, acceleration * delta), min_speed, move_speed)

	# Altitude control (hover at set height over terrain)
	var desired_y = _get_desired_hover_altitude()
	var altitude_error = desired_y - global_position.y
	var lift = altitude_error * altitude_smoothness * delta + lift_force * delta

	# Apply velocity with inertia
	var move_vec = new_dir * current_speed
	move_vec.y += lift + gravity_force * delta

	velocity = velocity.lerp(move_vec, 0.2)
	move_and_slide()

	# Smooth rotation to match heading (banking effect)
	var target_basis = Basis().looking_at(new_dir, Vector3.UP)
	var flat_dir = Vector3(to_target.x, 0, to_target.z).normalized()
	var current_facing = -global_transform.basis.z
	var flat_facing = Vector3(current_facing.x, 0, current_facing.z).normalized()

	var angle = flat_facing.angle_to(flat_dir)
	var axis = Vector3.UP

	if angle > 0.01 and axis.length() > 0.001:
		var max_angle = turn_speed * delta
		var limited_angle = min(angle, max_angle)
		var rotation = Quaternion(axis, limited_angle)
		var rotation_basis = Basis(rotation)
		global_transform.basis = rotation_basis * global_transform.basis
# === Hovering ===
func _get_desired_hover_altitude() -> float:
	var ray_origin = global_position + Vector3.UP * 10
	var ray_end = ray_origin - Vector3.UP * 200
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	if result:
		return result.position.y + hover_height
	else:
		return global_position.y

# === Wander Target ===
func _pick_new_wander_target():
	var random_offset = Vector3(
		randf_range(-wander_radius, wander_radius),
		0,
		randf_range(-wander_radius, wander_radius)
	)
	wander_target = origin + random_offset
	look_target = wander_target

# === Weapon Logic ===
func _handle_weapon_logic(delta):
	if weapon_state == WeaponState.IDLE:
		weapon_state = WeaponState.AIM
	elif weapon_state == WeaponState.AIM:
		if weapon_target != Vector3.ZERO:
			var dist = global_position.distance_to(weapon_target)
			if dist <= 120.0 and fire_time <= 0:
				weapon_state = WeaponState.FIRE
	elif weapon_state == WeaponState.FIRE:
		_fire_weapon()
		fire_time = fire_cooldown
		weapon_state = WeaponState.AIM

func _fire_weapon():
	if weapon:
		weapon.fire()
	bark.bark()
	var space_state = get_world_3d().direct_space_state
	var from = weapon.muzzle_origin.global_position
	var to = weapon_target
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	if result:
		var hit = result.collider
		if hit and hit.has_method("apply_damage"):
			hit.apply_damage(10)

# === Damage & Debug ===
func apply_damage(amount: int):
	health -= amount
	bark.bark()
	if health <= 0:
		movement_state = MovementState.DEAD
		queue_free()

func get_faction():
	return faction

func _update_debug_label():
	label.text = "HP: %d\nAlt: %.2f\nSpeed: %.1f\nState: %s" % [
		health,
		global_position.y,
		current_speed,
		MovementState.keys()[movement_state]
	]
