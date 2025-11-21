extends AI
class_name Enemy
# NODE REFERENCES #
@export var nav_agent: NavigationAgent3D
@export var weapon: AIWorldWeapon
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
var idle_to_wander = 3
var movement_recon_time = 1.5
var weapon_recon_time = 1.5
var wander_delay = 1.5
var wander_radius = 10
# ENUMS # 
enum AIState {COMBAT, PATROL, SEARCH, IDLE, DEAD}
enum MovementState {NONE, MOVE_TO}
enum WeaponState {FIRE, RELOAD, AIM, IDLE}
enum CombatOptions {MOVE, AIM, FIRE}
enum MovementOptions {ADVANCE, REPOSITION, FALLBACK}
# CONST #
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# WORKING DATA # 
var ai_state = AIState.IDLE
var movement_state = MovementState.NONE
var weapon_state = WeaponState.IDLE
var movement_target: Vector3
var weapon_target: Vector3
var look_target: Vector3
var patrol_points: Array[Node3D] = []
var spawn_transform
var alive : bool = true

var current_patrol_index := 0
var movement_time: float = 0.0
var fire_time: float = 0.0
var weapon_time: float = 0.0
var wander_time: float = 0.00
var targetting_time: float = 0.0
var idle_time: float = 0.0
var last_seen_point: Array[Vector3]
var seen_bodies: Array = []
var frame_waited: bool = false


func initialize():
	spawn_transform = transform
	await get_tree().process_frame
	frame_waited = true
	pass

func _physics_process(delta: float) -> void:
	if frame_waited == false:
		return
	if ai_state != AIState.DEAD:
		weapon_time += delta
		movement_time += delta
		handle_gravity(delta)
		#handle_targeting(delta)
		handle_looking()
		handle_movement(delta)
		handle_weapon_logic(delta)
		if label != null:
			update_debug_label()

func handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

func handle_targeting(delta):
	targetting_time += delta
	for body in seen_bodies:
		if not is_instance_valid(body) or body.health <= 0:
			seen_bodies.erase(body)
			last_seen_point.clear()
	if seen_bodies.is_empty() && look_target != null:
		#if movement_state != MovementState.PATROL:
			#change_state(MovementState.MOVE_TO)
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
	pass

func handle_movement(delta):
	if movement_time >= movement_recon_time:
		await reconsider_movement()
	match movement_state:
		MovementState.NONE:
			velocity.x = 0
			velocity.z = 0
		MovementState.MOVE_TO:
			var nav_map = nav_agent.get_navigation_map()
			var next_point = NavigationServer3D.map_get_closest_point(nav_map, movement_target)
			move_to(next_point)
			look_target = next_point
			if nav_agent.is_navigation_finished():
				reconsider_movement()
				#move_to(next_point)
			else:
				move_along_nav(delta)

func move_to(pos: Vector3):
	if nav_agent:
		nav_agent.set_target_position(pos)

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
				if dist <= 10.0:
					if fire_time <= 0:
						weapon_state = WeaponState.FIRE
		WeaponState.FIRE:
			if fire_time <= 0.0:
				fire()
				var space_state = get_world_3d().direct_space_state
				var query := PhysicsRayQueryParameters3D.new()
				var from = weapon.muzzle_origin.global_position
				var direction = (weapon_target - from).normalized()
				var to = from + direction * 250.0
				query.from = from
				query.to = to
				query.exclude = [self]
				var result = space_state.intersect_ray(query)
				if result:
					var _hit_pos = result.position
					var collider = result.collider
					#print("Hit:", collider, " at ", hit_pos)
					#var sphere = MeshInstance3D.new()
					#sphere.mesh = SphereMesh.new()
					#sphere.mesh.radius = 0.05  # Very small
					#sphere.mesh.height = 0.1   # Optional if you want a stretched look
					#get_tree().current_scene.add_child(sphere)
					#sphere.global_position = hit_pos
					if collider.has_method("apply_damage"):
						collider.apply_damage(10)
					else:
						if collider.get_parent().has_method("apply_damage"):
							collider.apply_damage(10)
				fire_time = weapon.fire_cooldown
				weapon_state = WeaponState.AIM
		WeaponState.RELOAD:
			# Simulate reload time
			weapon_state = WeaponState.IDLE
#region Reconsider
func reconsider_movement():
	movement_time = 0
	if idle_time >= idle_to_wander:
		movement_state = MovementState.MOVE_TO
	return
func reconsider_weapon():
	weapon_time = 0
	return
#endregion Reconsider
func change_state(new_state: AIState):
	if movement_state != new_state:
		#print("Changing state to:", new_state)
		movement_state = new_state
		movement_time = 0
		idle_time = 0
		wander_time = 0

func fire():
	weapon.fire()
	#print ("FIRE!")
	pass

func apply_damage(damage):
	if ai_state == AIState.DEAD:
		return
	bark.bark()
	health -= damage
	if health <= 0:
		alive = false
		ai_state = AIState.DEAD
		die()
		print (name + (" has died!"))
	pass

func die():
	change_state(AIState.DEAD)
	alive = false
	set_physics_process(false)
	set_process(false)
	hide()
	if weapon != null:
		weapon.hide()
	nav_agent.set_target_position(global_position)  # Cancel nav
	#nav_agent.set_enabled(false)
	$CollisionShape3D.disabled = true  # or disable all collision shapes

func respawn():
	reset()

func reset():
	transform = spawn_transform
	health = max_health
	alive = true
	change_state(AIState.IDLE)
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

func _on_sight_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		if body.has_method("get_faction"):
			if body.get_faction() != get_faction():
				if seen_bodies.has(body) == true:
					return
				seen_bodies.append(body)
				weapon_target = body.global_position
				look_target = body.global_position
				change_state(AIState.COMBAT)
				weapon_state = WeaponState.AIM
				bark.bark()

func _on_sight_body_shape_exited(_body_rid: RID, body: Node3D, _body_shape_index: int, _local_shape_index: int) -> void:
	if seen_bodies.has(body) == true:
		seen_bodies.erase(body)
		last_seen_point.append(body.global_position)

func update_debug_label():
	var movement_state_str = MovementState.keys()[movement_state]
	var weapon_state_str = WeaponState.keys()[weapon_state]
	var faction_str = Enums.Factions.keys()[faction]
	label.text = "HP: %d\nFaction: %s\nMovement State: %s\nWeapon State: %s" % [
		health,
		faction_str,
		movement_state_str,
		weapon_state_str
	]

func get_obstacle_ahead() -> Node3D:
	var forward = -transform.basis.z
	var from = global_position
	var to = from + forward * 3.0

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.exclude = [self]
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		if collider.has_method("is_obstacle") and collider.is_obstacle():
			return collider  # return obstacle
	return null
