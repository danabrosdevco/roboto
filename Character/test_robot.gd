extends CharacterBody3D
class_name TestRobot
# NODE REFERENCES #
@export var head: Node3D
@export var torso: Node3D
@export var legs_wheels: Node3D
@export var nav_agent: NavigationAgent3D
@export var Weapon: AIWorldWeapon

# EXPORT DATA # 
@export var health: int = 20
@export var faction : Enums.Factions = Enums.Factions.ENEMY
@export var move_speed: float = 4
@export var movement_recon_time : float = 0.35
@export var weapon_recon_time: float = 0.6
@export var wander_radius: float = 30
@export var wander_delay: float = 20
@export var idle_to_wander: float = 1
@export var acceleration := 1.50
@export var rotation_speed := 1.0  # Radians per second
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
var weapon_time: float = 0.0
var wander_time: float = 0.0
var idle_time: float = 0.0

func _ready():
	await get_tree().process_frame  # Wait 1 frame for the map to register
	await get_tree().process_frame  # (Optional second frame if needed)
	print("Navigation map ready:", nav_agent.get_navigation_map())

func _physics_process(delta: float) -> void:
	weapon_time += delta
	movement_time += delta
	if movement_state != MovementState.DEAD:
		handle_looking()
		handle_movement(delta)
	handle_weapon_logic()
	
func handle_movement(delta):
	if movement_time >= movement_recon_time:
		await reconsider_movement()
	match movement_state:
		MovementState.IDLE:
			idle_time += delta
			velocity = Vector3.ZERO
		MovementState.PATROL:
			if nav_agent.is_navigation_finished():
				current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
				move_to(patrol_points[current_patrol_index].global_position)
			else:
				move_along_nav()
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
				print ("Target pos is: " + str(target_pos))
				var map = nav_agent.get_navigation_map()
				var next_point = NavigationServer3D.map_get_closest_point(map, target_pos)
				movement_target = next_point
				look_target = next_point
				move_to(movement_target)
			else:
				move_along_nav()
		MovementState.ENGAGE:
			if is_instance_valid(movement_target):
				move_to(movement_target)
				move_along_nav()

		MovementState.SEEK_COVER:
			# TODO: implement cover seeking
			pass

		MovementState.DEAD:
			velocity = Vector3.ZERO


func move_to(pos: Vector3):
	if nav_agent:
		print("Moving to:", pos)
		nav_agent.set_target_position(pos)

func move_along_nav():
	var next_point = nav_agent.get_next_path_position()
	print (next_point)
	var dir = (next_point - global_position).normalized()
	print (dir)
	velocity = dir * move_speed
	print ("Velocity is: " + str(velocity))
	move_and_slide()

func handle_looking():
	look_at(look_target, Vector3.UP)
	## Optional: rotate head/torso separately
	#head.look_at(look_target, Vector3.UP)
	#torso.look_at(look_target, Vector3.UP)

func handle_weapon_logic():
	if weapon_time >= weapon_recon_time:
		reconsider_weapon()
	match weapon_state:
		WeaponState.IDLE:
			if is_instance_valid(weapon_target):
				weapon_state = WeaponState.AIM
		WeaponState.AIM:
			# Check distance or visibility
			weapon_state = WeaponState.FIRE
		WeaponState.FIRE:
			fire()
			weapon_state = WeaponState.RELOAD
		WeaponState.RELOAD:
			# Simulate reload time
			weapon_state = WeaponState.IDLE

func reconsider_movement():
	movement_time = 0
	if idle_time >= idle_to_wander:
		movement_state = MovementState.WANDER
	return

func reconsider_weapon():
	weapon_time = 0
	return


func fire():
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
