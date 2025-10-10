extends CharacterBody3D
class_name TestRobot
# NODE REFERENCES #
@export var head: Node3D
@export var torso: Node3D
@export var legs_wheels: Node3D
@export var nav_agent: NavigationAgent3D
@export var weapon: AIWorldWeapon
@export var hearing: Area3D
@export var sight: Area3D
@export var label: Label3D

# EXPORT DATA # 
@export var health: int = 20
@export var faction : Enums.Factions = Enums.Factions.ENEMY
@export var move_speed: float = 4
@export var fire_cooldown: float = 0.75
@export var movement_recon_time : float = 0.35
@export var weapon_recon_time: float = 0.6
@export var wander_radius: float = 30
@export var wander_delay: float = 20
@export var idle_to_wander: float = 1
@export var acceleration := 1.50
@export var rotation_speed := 1.0  # Radians per second
@export var hearing_sphere_radius: float = 5 
@export var sight_rectangle_near_area: float = 4
@export var sight_rectangle_far_area: float = 100
@export var sight_rectangle_distance: float = 20

# ENUMS # 
enum MovementState {IDLE, PATROL, ENGAGE, SEEK_COVER, DEAD, WANDER}
enum WeaponState {FIRE, RELOAD, IDLE, AIM}


# WORKING DATA # 
@export var movement_target: Vector3
@export var weapon_target: Vector3
@export var look_target: Vector3
@export var patrol_points: Array[Node3D] = []
var movement_state = MovementState.IDLE
var weapon_state = WeaponState.IDLE
var current_patrol_index := 0
var movement_time: float = 0.0
var fire_time: float = 0.0
var weapon_time: float = 0.0
var wander_time: float = 0.0
var idle_time: float = 0.0
var last_seen_point: Array[Vector3]

var seen_bodies: Array = []

func _ready():
	create_sight_shape()
	create_hearing_sphere()
	pass

func _physics_process(delta: float) -> void:
	weapon_time += delta
	movement_time += delta
	if movement_state != MovementState.DEAD:
		handle_looking()
		handle_movement(delta)
	handle_weapon_logic(delta)
	update_debug_label()
	
func handle_movement(delta):
	if movement_time >= movement_recon_time:
		await reconsider_movement()
	match movement_state:
		MovementState.IDLE:
			idle_time += delta
			velocity = Vector3.ZERO
		MovementState.PATROL:
			if patrol_points.is_empty():
				return
			if nav_agent.is_navigation_finished():
				current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
				var next_point = patrol_points[current_patrol_index].global_position
				movement_target = next_point
				look_target = next_point
				move_to(next_point)
			else:
				move_along_nav(delta)
		MovementState.WANDER:
			wander_time -= delta
			if wander_time <= 0.0:
				wander_time = wander_delay
				var origin = global_position
				var random_offset = Vector3(
					randf_range(-wander_radius, wander_radius),
					0,
					randf_range(-wander_radius, wander_radius)
				)
				var target_pos = origin + random_offset
				#print ("Target pos is: " + str(target_pos))
				var map = nav_agent.get_navigation_map()
				var next_point = NavigationServer3D.map_get_closest_point(map, target_pos)
				movement_target = next_point
				look_target = next_point
				move_to(movement_target)
			else:
				move_along_nav(delta)
		MovementState.ENGAGE:
				var to_target = weapon_target - global_position
				to_target.y = 0
				var engage_distance = 8.0  # Stand this far from the target
				if to_target.length() > engage_distance:
					var offset = to_target.normalized() * (to_target.length() - engage_distance)
					var destination = global_position + offset
					var nav_map = nav_agent.get_navigation_map()
					var nav_pos = NavigationServer3D.map_get_closest_point(nav_map, destination)
					movement_target = nav_pos
					look_target = weapon_target
					move_to(movement_target)
				look_target = weapon_target
				move_along_nav(delta)
		MovementState.SEEK_COVER:
			# TODO: implement cover seeking
			pass

		MovementState.DEAD:
			velocity = Vector3.ZERO


func move_to(pos: Vector3):
	if nav_agent:
		nav_agent.set_target_position(pos)

func move_along_nav(delta):
	var next_point = nav_agent.get_next_path_position()
	var direction = next_point - global_position
	direction.y = 0  # Flatten direction to ground plane
	if direction.length() > 0.1:
		direction = direction.normalized()
		# Smooth velocity with lerp
		var target_velocity = direction * move_speed
		velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)
	else:
		# Stop when close enough
		velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
		velocity.z = lerp(velocity.z, 0.0, acceleration * delta)
	move_and_slide()
	if direction.length() > 0.1:
		var current_yaw = rotation.y
		var target_yaw = atan2(-direction.x, -direction.z)  # Negative because Godot faces -Z by default
		var new_yaw = lerp_angle(current_yaw, target_yaw, rotation_speed * delta)
		rotation.y = new_yaw
func handle_looking():
	var flat_look_target = Vector3(look_target.x, global_position.y, look_target.z)
	if global_position.distance_to(flat_look_target) > 0.01:
		look_at(flat_look_target, Vector3.UP)
func handle_weapon_logic(delta):
	fire_time -= delta
	if weapon_time >= weapon_recon_time:
		reconsider_weapon()
	match weapon_state:
		WeaponState.IDLE:
			weapon_state = WeaponState.AIM
		WeaponState.AIM:
				var dist = global_position.distance_to(weapon_target)
				if dist <= 16.0:
					if fire_time <= 0:
						weapon_state = WeaponState.FIRE
				# Aim weapon toward target
				var from = weapon.muzzle_origin.global_position
				var to = weapon_target
				var dir = (to - from).normalized()
				
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
					var hit_pos = result.position
					var collider = result.collider
					print("Hit:", collider, " at ", hit_pos)
					var sphere = MeshInstance3D.new()
					sphere.mesh = SphereMesh.new()
					sphere.mesh.radius = 0.05  # Very small
					sphere.mesh.height = 0.1   # Optional if you want a stretched look
					sphere.global_position = hit_pos
					get_tree().current_scene.add_child(sphere)
					if collider.has_method("apply_damage"):
						collider.apply_damage(10)
					else:
						if collider.get_parent().has_method("apply_damage"):
							collider.apply_damage(10)
				fire_time = fire_cooldown
				weapon_state = WeaponState.AIM
		WeaponState.RELOAD:
			# Simulate reload time
			weapon_state = WeaponState.IDLE
#region Reconsider
func reconsider_movement():
	movement_time = 0
	if idle_time >= idle_to_wander:
		movement_state = MovementState.WANDER
	return

func reconsider_weapon():
	weapon_time = 0
	return

#endregion Reconsider
func change_state(new_state: MovementState):
	if movement_state != new_state:
		#print("Changing state to:", new_state)
		movement_state = new_state
		movement_time = 0
		idle_time = 0

func fire():
	weapon.fire()
	#print ("FIRE!")
	pass

func apply_damage(damage):
	health -= damage
	if health <= 0:
		die()
	pass

func die():
	await get_tree().create_timer(0.25).timeout
	queue_free()

func get_faction():
	return faction

func _on_navigation_agent_3d_target_reached() -> void:
	pass # Replace with function body.

func create_hearing_sphere():
	hearing.get_child(0).shape.radius = hearing_sphere_radius

func create_sight_shape():
	var shape := ConvexPolygonShape3D.new()
	var half_near := sqrt(sight_rectangle_near_area) * 0.5
	var half_far := sqrt(sight_rectangle_far_area) * 0.5
	# Define 8 vertices (same as previous answer)
	var vertices := PackedVector3Array([
		# Near face (Z = 0)
		Vector3( half_near,  half_near, 0),  # n0 - top-left
		Vector3( half_near, -half_near, 0),  # n1 - top-right
		Vector3(-half_near, -half_near, 0),  # n2 - bottom-right
		Vector3(-half_near,  half_near, 0),  # n3 - bottom-left
		# Far face (Z = distance)
		Vector3( half_far,  half_far, sight_rectangle_distance),  # f0 - top-left
		Vector3( half_far, -half_far, sight_rectangle_distance),  # f1 - top-right
		Vector3(-half_far, -half_far, sight_rectangle_distance),  # f2 - bottom-right
		Vector3(-half_far,  half_far, sight_rectangle_distance),  # f3 - bottom-left
	])

	shape.points = vertices
	sight.get_child(0).shape = shape

func _on_sight_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		if body.has_method("get_faction"):
			if body.get_faction() != get_faction():
				seen_bodies.append(body)
				weapon_target = body.global_position
				look_target = body.global_position
				change_state(MovementState.ENGAGE)
				weapon_state = WeaponState.AIM

func _on_sight_body_shape_exited(_body_rid: RID, body: Node3D, _body_shape_index: int, _local_shape_index: int) -> void:
	if seen_bodies.has(body) == true:
		seen_bodies.erase(body)
		last_seen_point.append(body.global_position)

func update_debug_label():
	var movement_state_str = MovementState.keys()[movement_state]
	var weapon_state_str = WeaponState.keys()[weapon_state]
	label.text = "HP: %d\nMovement State: %s\nWeapon State: %s" % [
		health,
		movement_state_str,
		weapon_state_str
	]
