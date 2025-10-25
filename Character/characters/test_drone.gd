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
@export var min_speed := 5.0  # helicopter can’t go below this
@export var turn_speed := 1.2  # slower turning
@export var acceleration := 2.0
@export var lift_force := 5.0  # constant upward lift
@export var gravity_force := -9.8
@export var hover_height := 60.0
@export var altitude_smoothness := 3.0
@export var wander_radius := 600.0
@export var wander_delay := 10.0
@export var engage_reset_distance := 300.0  # how far past target before disengaging


# === Flocking / Avoidance ===
@export var neighbor_radius := 15.0
@export var separation_weight := 2.0
@export var alignment_weight := 1.0
@export var cohesion_weight := 1.0
@export var obstacle_avoidance_weight := 3.0

# === Weapon Logic ===
@export var fire_cooldown := 1.0
var weapon_target: Vector3
var look_target: Vector3
var fire_time := 0.0
var wander_target := Vector3.ZERO
var enroute: bool = false
var flyby: bool = false
enum WeaponState { IDLE, AIM, FIRE, RELOAD }
enum MovementState { WANDER, ENGAGE, DEAD }

# WORKING CODE #
var weapon_state = WeaponState.IDLE
var movement_state = MovementState.WANDER
var wander_time := 0.0
var current_speed := 0.0
var frame_waited := false
var origin: Vector3
var targetting_count = 0.0
var targetting_time = 0.5
var seen_bodies : Array = []
var last_seen_point: Array = []
var engage_target_point: Vector3 = Vector3.ZERO
var check_weapon_target: Vector3
var distance_to_target: float


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
			distance_to_target = global_position.distance_to(check_weapon_target)
			_handle_engage(delta)
		MovementState.DEAD:
			return
	handle_targeting(delta)
	_handle_weapon_logic(delta)
	_update_debug_label()


func handle_targeting(delta):
	targetting_count += delta
	if targetting_count <= targetting_time:
		return
	for body in seen_bodies:
		if not is_instance_valid(body) or body.health <= 0:
			seen_bodies.erase(body)
			last_seen_point.clear()
	if seen_bodies.is_empty() && look_target != null && movement_state != MovementState.WANDER:
			weapon_target = Vector3.ZERO
			engage_target_point = Vector3.ZERO
			movement_state = MovementState.WANDER
			weapon_state = WeaponState.IDLE
			return
	if seen_bodies.is_empty() == false:
		for i in seen_bodies:
			seen_bodies.sort_custom(func(a, b):
				return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position)
			)
		weapon_target = seen_bodies[0].global_position
		look_target = seen_bodies[0].global_position
		targetting_time = 0.0
		return
	if seen_bodies.is_empty():
		if last_seen_point.is_empty():
			pass
	#if !command_point:
		#pass
	#var obstacle = get_obstacle_ahead()
	#if obstacle:
		#weapon_target = obstacle.global_position
		#look_target = obstacle.global_position
		#change_state(MovementState.ENGAGE)
		#weapon_state = WeaponState.AIM
		#return
	#pass


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
	# Pick a single fly-over point once per engage
	#if engage_target_point == Vector3.ZERO:
		#var to_target := (weapon_target - global_position).normalized()
		##engage_target_point = global_position + (to_target * engage_reset_distance)
	# Steer toward that fly-over point
	_fly_steering(delta, engage_target_point)

	# Once we’ve flown past it, reset to wander or pick a new target
	if global_position.distance_to(engage_target_point) < 100.0:
		engage_target_point = Vector3.ZERO

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
	#var target_basis = Basis.looking_at(new_dir, Vector3.UP)
	var flat_dir = Vector3(to_target.x, 0, to_target.z).normalized()
	var current_facing = -global_transform.basis.z
	var flat_facing = Vector3(current_facing.x, 0, current_facing.z).normalized()

	var angle = flat_facing.angle_to(flat_dir)
	var axis = Vector3.UP

	if angle > 0.01 and axis.length() > 0.001:
		var max_angle = turn_speed * delta
		var limited_angle = min(angle, max_angle)
		var new_rotation = Quaternion(axis, limited_angle)
		var rotation_basis = Basis(new_rotation)
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
	fire_time -= delta
	match weapon_state:
		WeaponState.IDLE:
			weapon_state = WeaponState.AIM
		WeaponState.AIM:
			if weapon_target == Vector3.ZERO:
				return
			#DebugDraw3D.draw_line(global_position, weapon_target, Color(1, 1, 0))
			#if engage_target_point != Vector3.ZERO:
				#DebugDraw3D.draw_line(global_position, engage_target_point, Color(1, 1, 0))
			check_weapon_target = Vector3(weapon_target.x, global_position.y, weapon_target.z)
			var to_target := (weapon_target - global_position).normalized()
			if distance_to_target <=100:
				engage_target_point = global_position + (to_target * engage_reset_distance)
			if distance_to_target <= 8.0 and fire_time <= 0:
				weapon_state = WeaponState.FIRE
				engage_target_point = global_position + (to_target * engage_reset_distance)

		WeaponState.FIRE:
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


func _on_sight_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		if body.has_method("get_faction"):
			if body.get_faction() != get_faction():
				if seen_bodies.has(body):
					return
				#print ("SEEING ENEMY: " + str(body))
				seen_bodies.append(body)
				weapon_target = body.global_position
				look_target = body.global_position
				movement_state = MovementState.ENGAGE
				weapon_state = WeaponState.AIM
				bark.bark()

#func _on_sight_body_shape_exited(_body_rid: RID, body: Node3D, _body_shape_index: int, _local_shape_index: int) -> void:
	#if seen_bodies.has(body) == true:
		#seen_bodies.erase(body)
		#last_seen_point.append(body.global_position)
