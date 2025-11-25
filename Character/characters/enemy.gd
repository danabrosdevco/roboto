extends AI
class_name Enemy
# NODE REFERENCES #
@export var nav_agent: NavigationAgent3D
@export var weapon: AIWeapon
@export var label: Label3D
@export var bark: Bark
#@export var fire_cooldown: float = 0.75
# EXPORT DATA # 
@export var health: int = 20
@export var max_health: int = 20
@export var faction : Enums.Factions = Enums.Factions.ENEMY
@export var move_speed: float = 4.5
@export var acceleration := 1.50
@export var rotation_speed := 1.0  # Radians per second
@export var reposition_distance: float = 2.0
@export var advance_distance: float = 3.0
@export var fallback_distance: float = 1.25 
@export var max_fire_distance: float = 30
@export var max_accuracy: float = 0.90
@export var min_accuracy: float = 0.5
@export var bits: int = 10
var damaged_by_player : bool = false
var idle_to_wander = 3
var movement_recon_time = 1.5
var targeting_recon_time = 0.33
var combat_recon_time = 1.65
var weapon_recon_time = 1.5
var wander_delay = 1.5
var wander_radius = 3.5


# ENUMS # 
enum AIState {COMBAT, PATROL, SEARCH, IDLE, DEAD}
enum MovementState {NONE, MOVING}
enum WeaponState {FIRE, RELOAD, AIM, IDLE}
enum CombatOptions {MOVE, AIM, FIRE}
enum MovementOptions {ADVANCE, REPOSITION, FALLBACK}

@export var AllowedMovementOptions: Array[MovementOptions]

# CONST #
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# WORKING DATA # 
var player: Player
var ai_state = AIState.COMBAT
var movement_state = MovementState.NONE
var weapon_state = WeaponState.IDLE

var previous_combat_option: CombatOptions
var previous_movement_option: CombatOptions

var combat_target: CharacterBody3D
var movement_target: Vector3
var weapon_target: Vector3
var look_target: Vector3
var patrol_points: Array[Node3D] = []
var spawn_transform
var alive : bool = true

var combat_time: float = 0.0
var movement_time: float = 0.0
var search_time : float = 0.0
var fire_time: float = 0.0
var weapon_time: float = 0.0
var wander_time: float = 0.00
var targeting_time: float = 0.0
var idle_time: float = 0.0



var last_seen_point: Array[Vector3]
var seen_bodies: Array = []
var frame_waited: bool = false


func initialize():
	spawn_transform = transform
	await get_tree().process_frame
	await get_tree().process_frame
	combat_target = player
	frame_waited = true
	pass

func _physics_process(delta: float) -> void:
	if frame_waited == false:
		return
	if ai_state != AIState.DEAD:
		handle_time_passing(delta)
		handle_gravity(delta)
		handle_looking()
		handle_movement(delta)
		handle_weapon_logic(delta)
		if label != null:
			update_debug_label()

func handle_time_passing(delta):
	weapon_time += delta
	targeting_time += delta
	if movement_state == MovementState.MOVING:
		movement_time += delta
	if ai_state == AIState.COMBAT:
		combat_time += delta
	if ai_state == AIState.IDLE:
		idle_time += delta
	if ai_state == AIState.SEARCH:
		search_time += delta
	if combat_time >= combat_recon_time:
		reconsider_combat()
	if targeting_time >= targeting_recon_time:
		reconsider_target()

func handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
func handle_targeting(delta):
	pass
func handle_movement(delta):
	#if movement_time >= movement_recon_time:
		#await reconsider_movement()
	match movement_state:
		MovementState.NONE:
			velocity.x = 0
			velocity.z = 0
		MovementState.MOVING:
			if nav_agent.is_navigation_finished():
				reconsider_movement()
			else:
				move_along_nav(delta)

func move_to(pos: Vector3):
	#if nav_agent:
	nav_agent.set_target_position(pos)
	movement_target = pos
	movement_state = MovementState.MOVING
	movement_time = 0

func move_along_nav(delta):
	var path_dir = nav_agent.get_next_path_position() - global_position
	path_dir.y = 0
	var base_dir = path_dir.normalized()
	if base_dir.length() > 0.01:
		base_dir = base_dir.normalized()
	var target_velocity = base_dir * move_speed
	velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)
	move_and_slide()
	# Rotate to face direction
	if base_dir.length() > 0.01:
		var current_yaw = rotation.y
		var target_yaw = atan2(-base_dir.x, -base_dir.z)
		rotation.y = lerp_angle(current_yaw, target_yaw, rotation_speed * delta)
func handle_looking():
	var flat_look_target = Vector3(look_target.x, global_position.y, look_target.z)
	if global_position.distance_to(flat_look_target) > 0.01:
		look_at(flat_look_target, Vector3.UP)
func handle_weapon_logic(delta):
	if fire_time >= 0:
		fire_time -= delta
	if ai_state != AIState.COMBAT:
		weapon_state = WeaponState.IDLE
		return
	if weapon_time >= weapon_recon_time:
		reconsider_weapon()
	match weapon_state:
		WeaponState.IDLE:
			weapon_state = WeaponState.AIM
		WeaponState.AIM:
				var dist = global_position.distance_to(weapon_target)
				if fire_time <= 0:
					if dist <= max_fire_distance:
						if is_path_clear(weapon.muzzle_origin.global_position, combat_target.global_position) == true:
							weapon_state = WeaponState.FIRE
		WeaponState.FIRE:
			if fire_time <= 0.0:
				fire()
				fire_time = weapon.fire_cooldown
				weapon_state = WeaponState.AIM
		WeaponState.RELOAD:
			weapon_state = WeaponState.IDLE
#region Reconsider
func roll_combat_action():
	var keys := CombatOptions.keys()
	var action := randi_range(0, keys.size() - 1)
	var new_action = keys[action]
	var new_action_value = CombatOptions[new_action]
	if new_action_value == previous_combat_option:
		action = (action) % keys.size() 
		new_action = keys[action] 
	new_action_value = CombatOptions[new_action]
	perform_action(new_action_value)
	new_action_value = previous_combat_option

func reconsider_movement():
	movement_time = 0
	if movement_target.distance_to(global_position) >= 3:
		return
	if ai_state == AIState.COMBAT:
		roll_combat_action()
	return
func reconsider_weapon():
	weapon_time = 0
	return

func reconsider_combat():
	combat_time = 0
	roll_combat_action()

func reconsider_target():
	if combat_target == null:
		change_ai_state(AIState.IDLE)
		return
	if combat_target.alive == true:
		weapon_target = combat_target.global_position
		look_target = combat_target.global_position

#endregion Reconsider
func change_ai_state(new_state: AIState):
	if ai_state != new_state:
		#print("Changing state to:", new_state)
		ai_state = new_state
		movement_time = 0
		idle_time = 0
		wander_time = 0
		combat_time = 0
		search_time = 0

func change_combat_target(body):
	combat_target = body
	weapon_target = body.global_position
	look_target = body.global_position

func perform_action(action: CombatOptions):
	match action:
		CombatOptions.MOVE:
			#print ("HEY MOVE WAS SEELCTED!")
			var keys := AllowedMovementOptions
			var movement := randi_range(0, keys.size() - 1)
			var new_move_target
			match movement:
				MovementOptions.REPOSITION:
					new_move_target = find_reposition_target()
					#if new_move_target != false:
					move_to(new_move_target)
					pass
				MovementOptions.ADVANCE:
					new_move_target =  find_advance_target()
					#if new_move_target != false:
					move_to(new_move_target)
					pass
				MovementOptions.FALLBACK:
					new_move_target = find_fallback_target()
					#if new_move_target != false:
					move_to(new_move_target)
					pass
		CombatOptions.FIRE:
			pass
		CombatOptions.AIM:
			pass
	pass

func find_reposition_target():
	var nav_map = nav_agent.get_navigation_map()
	var to_target = (combat_target.global_position - global_position).normalized()
	var right = to_target.cross(Vector3.UP).normalized()
	var lateral_dir = right if randf() > 0.5 else -right
	var test_pos = global_position + lateral_dir * reposition_distance
	var closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)

	if is_path_clear(closest_point, combat_target.global_position):
		return closest_point
	else:
		test_pos = global_position + lateral_dir * reposition_distance * 0.5
		closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
		if is_path_clear(closest_point, combat_target.global_position):
			return closest_point
	return global_position
	pass

func find_advance_target():
	var nav_map = nav_agent.get_navigation_map()
	var direction = (combat_target.global_position - global_position).normalized()
	var test_pos = global_position + direction * advance_distance
	var closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
	if is_path_clear(closest_point, combat_target.global_position):
		return closest_point
	else:
		test_pos = global_position + direction * advance_distance * 0.5
		closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
		if is_path_clear(test_pos, combat_target.global_position):
			return closest_point
	return global_position  # fallback to current
func find_fallback_target():
	var nav_map = nav_agent.get_navigation_map()
	var away_dir = (global_position - combat_target.global_position).normalized()
	var test_pos = global_position + away_dir * fallback_distance
	var closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
	if is_path_clear(closest_point, combat_target.global_position):
		return closest_point
	else:
		test_pos = global_position + away_dir * fallback_distance * 0.5
		closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
		if is_path_clear(test_pos, combat_target.global_position):
			return closest_point
	return global_position
func fire():
	var final_target = get_inaccurate_target(weapon_target)
	weapon.fire(final_target)
	pass

func apply_damage(damage, source):
	print (source)
	if ai_state == AIState.DEAD:
		return
	if source is Player:
		damaged_by_player = true
	bark.bark()
	health -= damage
	if health <= 0:
		alive = false
		ai_state = AIState.DEAD
		die()
		print (name + (" has died!"))
	pass

func die():
	change_ai_state(AIState.DEAD)
	alive = false
	set_physics_process(false)
	set_process(false)
	hide()
	if weapon != null:
		weapon.hide()
	nav_agent.set_target_position(global_position)  # Cancel nav
	if damaged_by_player == true:
		player.add_bits(bits)
	$CollisionShape3D.disabled = true  # or disable all collision shapes

func respawn():
	reset()

func reset():
	transform = spawn_transform
	health = max_health
	alive = true
	change_ai_state(AIState.IDLE)
	seen_bodies.clear()
	last_seen_point.clear()
	velocity = Vector3.ZERO
	weapon_target = Vector3.ZERO
	look_target = Vector3.ZERO
	show()
	if weapon != null:
		weapon.show()
	set_physics_process(true)
	set_process(true)
	#hearing.monitoring = true
	#sight.monitoring = true
	$CollisionShape3D.disabled = false

func get_faction():
	return faction

func is_path_clear(from: Vector3, to: Vector3) -> bool:
	#return true
	var space_state = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	DebugDraw3D.draw_ray(to, from, from.distance_squared_to(to))

	query.exclude = [self, combat_target]
	var result = space_state.intersect_ray(query)
	return not result

func update_debug_label():
	var ai_state_str = AIState.keys()[ai_state]
	var movement_state_str = MovementState.keys()[movement_state]
	var weapon_state_str = WeaponState.keys()[weapon_state]
	var faction_str = Enums.Factions.keys()[faction]
	label.text = "AI: %s\nCombatTime: %s\nMovement State: %s\nWeapon State: %s" % [
		ai_state_str,
		faction_str,
		movement_state_str,
		weapon_state_str
	]

func _on_detection_body_entered(body: Node3D) -> void:
	if ai_state == AIState.DEAD:
		return
	if body is Player:
		change_ai_state(AIState.COMBAT)
		change_combat_target(body)
	pass # Replace with function body.

func _on_detection_body_exited(body: Node3D) -> void:
	pass # Replace with function body.


func get_inaccurate_target(target_pos: Vector3) -> Vector3:
	var dist := global_position.distance_to(weapon_target)
	# If too far away → guaranteed miss
	if dist > max_fire_distance:
		return target_pos + get_random_spread(dist, min_accuracy)
	# Accuracy scales based on distance
	var t = clamp(dist / max_fire_distance, 0.0, 1.0)
	var accuracy = lerp(max_accuracy, min_accuracy, t)
	# Apply random spread based on accuracy
	return target_pos + get_random_spread(dist, accuracy)

func get_random_spread(distance: float, accuracy: float) -> Vector3:
	# Accuracy 1.0 = no spread
	# Accuracy 0.0 = huge spread
	var spread_strength := (1.0 - accuracy)
	# Scale spread with distance so missing becomes more dramatic further away
	var max_offset := spread_strength * (distance * 0.1)
	return Vector3(
		randf_range(-max_offset, max_offset),
		randf_range(-max_offset, max_offset),
		randf_range(-max_offset, max_offset)
	)
