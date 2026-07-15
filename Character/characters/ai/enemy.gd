extends AI
class_name Enemy
# NODE REFERENCES #
@export var patrol_path: PatrolPath
@export var nav_agent: NavigationAgent3D
@export var weapon: AIWeapon
@export var label: Label3D
@export var bark: Bark
@export var detection: Area3D
@export var particle_effects_die: Array[ParticleEffect]
@export var particle_effects_hit: Array[ParticleEffect]
@export var visible_pieces: Array[Node3D]
# EXPORT DATA # 
@export var activation_distance : int = 75
@export var health: int = 30
@export var max_health: int = 30
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
# Equipment — assign AIEquipmentSlot resources in the inspector
@export var equipment_slots: Array[AIEquipmentSlot] = []
var damaged_by_player: bool = false
var idle_to_wander = 3
var movement_recon_time = 1.5
var targeting_recon_time = 0.33
@export var combat_recon_time = 1.65
var weapon_recon_time = 1.5
var patrol_recon_time = 1.5
var chasing_recon_time = 0.2
var wander_delay = 1.5
var wander_radius = 3.5


# ENUMS # 
enum AIState {COMBAT, PATROL, SEARCH, IDLE, DEAD, PASSIVE}
enum MovementState {NONE, MOVING, LEAPING, ADVANCING, CHASING}
enum WeaponState {FIRE, RELOAD, AIM, IDLE}
enum CombatOptions {MOVE, AIM, FIRE}
enum MovementOptions {ADVANCE, REPOSITION, FALLBACK, LEAP, CHASE}
@export var DefaultAIState: AIState
@export var AllowedMovementOptions: Array[MovementOptions]
@export var AllowedCombatOptions: Array[CombatOptions]

# CONST #
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# WORKING DATA # 
var player: Player           # always set by AIManager — used for player-specific logic
var ai_manager: AIManager    # set by AIManager on registration
var stimulus_manager: StimulusManager
var checking_for_target: bool = false  # was checking_for_player
var ai_state = AIState.COMBAT
var movement_state = MovementState.NONE
var weapon_state = WeaponState.IDLE
var activation_distance_sq: float

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
var patrol_time : float = 0.0
var fire_time: float = 0.0
var weapon_time: float = 0.0
var wander_time: float = 0.00
var targeting_time: float = 0.0
var idle_time: float = 0.0
var chasing_time: float = 0.0

var last_seen_point: Array[Vector3]
var seen_bodies: Array = []
var frame_waited: bool = false

# Equipment
var _equipment_cooldowns: Dictionary = {}   # slot index → remaining cooldown
var _target_stationary_time: float = 0.0    # how long combat_target hasn't moved
var _target_last_position: Vector3 = Vector3.ZERO
const EQUIPMENT_RECON_TIME: float = 1.5
var _equipment_recon_timer: float = 0.0

signal combat_triggered(ai: AI)


func initialize():
	spawn_transform = transform
	activation_distance_sq = activation_distance * activation_distance
	await get_tree().process_frame
	ai_state = DefaultAIState
	#combat_target = player
	frame_waited = true
	for slot in equipment_slots:
		slot.initialize()
	reconsider_target()
	pass

func _physics_process(delta: float) -> void:
	if frame_waited == false:
		return
	
	if ai_state == AIState.DEAD:
		return
		
	if player == null:
		return
	

	# Use player distance for activation (cheap check, player always present)
	# Once active, targeting is faction-aware via reconsider_target
	var dist_sq = global_position.distance_squared_to(player.global_position)
	if dist_sq > activation_distance_sq:
		enter_passive_mode()
		return
	else:
		exit_passive_mode()
	handle_gravity(delta)
	if checking_for_target and combat_target != null:
		if is_path_clear(global_position, combat_target.global_position):
			trigger_combat(combat_target)
	handle_time_passing(delta)
	handle_looking()
	handle_movement(delta)
	handle_weapon_logic(delta)
	if label != null:
		update_debug_label()



func enter_passive_mode():
	if ai_state == AIState.PASSIVE:
		return
	change_ai_state(AIState.PASSIVE)
	velocity.x = 0
	velocity.z = 0
	movement_state = MovementState.NONE
	weapon_state = WeaponState.IDLE
	# Optional: stop nav updates
	nav_agent.set_target_position(global_position)
func exit_passive_mode():
	if ai_state != AIState.PASSIVE:
		return
	# Resume default behavior
	change_ai_state(DefaultAIState)

func handle_time_passing(delta):
	weapon_time += delta
	targeting_time += delta
	if movement_state == MovementState.MOVING:
		movement_time += delta
	match ai_state:
		AIState.COMBAT:
			combat_time += delta
			if combat_time >= combat_recon_time:
				reconsider_combat()
		AIState.PATROL:
			patrol_time += delta
			if patrol_time >= patrol_recon_time:
				reconsider_patrol()
		AIState.IDLE:
			idle_time += delta
		AIState.SEARCH:
			search_time += delta


	if targeting_time >= targeting_recon_time:
		reconsider_target()

	# Equipment evaluation — only during active combat
	if ai_state == AIState.COMBAT and not equipment_slots.is_empty():
		_tick_equipment(delta)

func handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
func handle_targeting(_delta):
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
		MovementState.LEAPING:
			handle_leap(delta)
		MovementState.CHASING:
			handle_chasing(delta)

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

func handle_chasing(delta):
	chasing_time += delta
	if chasing_time >= chasing_recon_time:
		chasing_time = 0 
		nav_agent.set_target_position(combat_target.global_position)
	move_along_nav(delta)
	pass


func handle_leap(delta):
	#print ("HANDLING LEAP")
	velocity.y -= gravity * delta
	move_and_slide()
	if is_on_floor():
		movement_state = MovementState.NONE
		velocity = Vector3.ZERO
		roll_combat_action()

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
						if weapon:
							if weapon.weapon_type == Enums.AIWeaponTypes.MELEE:
								if is_path_clear(global_position, combat_target.global_position):
									weapon_state = WeaponState.FIRE
							elif is_path_clear(global_position, combat_target.global_position) == true:
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
	if AllowedCombatOptions.is_empty():
		return
	var options := AllowedCombatOptions.duplicate()  # Clone to safely modify
	if options.size() > 1:
		options.erase(previous_combat_option)  # Remove last action to avoid repetition
	var new_action = options[randi_range(0, options.size() - 1)]
	#print("Combat action selected:", new_action)
	perform_action(new_action)
	previous_combat_option = new_action

func reconsider_movement():
	movement_time = 0
	if movement_target.distance_to(global_position) >= 3:
		return
	if ai_state == AIState.COMBAT:
		roll_combat_action()
		return
	if ai_state == AIState.PATROL:
		reconsider_patrol()
	return
func reconsider_weapon():
	weapon_time = 0
	return

func reconsider_combat():
	combat_time = 0
	roll_combat_action()

func reconsider_target() -> void:
	targeting_time = 0
	# If current target is still alive and hostile, keep it
	if combat_target != null and combat_target.alive:
		if _is_hostile(combat_target):
			weapon_target = combat_target.global_position
			look_target = combat_target.global_position
			return

	# Target is dead, gone, or no longer hostile — stop looking at it
	if combat_target != null and not combat_target.alive:
		combat_target = null
		weapon_target = Vector3.ZERO
		if movement_target != Vector3.ZERO:
			look_target = movement_target

	# Current target is gone or no longer hostile — find a new one
	var new_target: CharacterBody3D = null
	if ai_manager != null:
		new_target = ai_manager.get_nearest_hostile(self)
	elif player != null and Enums.are_hostile(faction, Enums.Factions.PLAYER):
		new_target = player

	if new_target != null:
		if ai_state == AIState.COMBAT:
			change_combat_target(new_target)
		# Don't auto-trigger combat from IDLE/PATROL — let detection handle that
	else:
		# No hostiles — clear target and look where we're going
		combat_target = null
		weapon_target = Vector3.ZERO
		if movement_target != Vector3.ZERO:
			look_target = movement_target
		if ai_state == AIState.COMBAT:
			change_ai_state(AIState.PATROL)

func _tick_equipment(delta: float) -> void:
	# Tick all cooldowns
	for i in _equipment_cooldowns.size():
		_equipment_cooldowns[i] = maxf(0.0, _equipment_cooldowns[i] - delta)

	# Track how long the target has been stationary
	if combat_target != null and combat_target.alive:
		var target_pos = combat_target.global_position
		if target_pos.distance_to(_target_last_position) < 0.5:
			_target_stationary_time += delta
		else:
			_target_stationary_time = 0.0
			_target_last_position = target_pos

	# Evaluate whether to use equipment
	_equipment_recon_timer += delta
	if _equipment_recon_timer < EQUIPMENT_RECON_TIME:
		return
	_equipment_recon_timer = 0.0
	_evaluate_equipment_use()

func _evaluate_equipment_use() -> void:
	if combat_target == null:
		return

	# Build context once for all equipment to evaluate
	var context = AIEquipment.EquipmentContext.new()
	context.owner_ai = self
	context.combat_target = combat_target
	context.target_position = combat_target.global_position
	context.time_since_target_moved = _target_stationary_time
	context.owner_is_reloading = weapon != null and weapon.is_reloading
	# Collect nearby hostiles for cluster check
	context.nearby_hostiles = []
	if ai_manager != null:
		context.nearby_hostiles = ai_manager.get_hostiles_in_radius(self, 5.0)

	# Check each slot in order — use the first one that's ready and applicable
	for i in equipment_slots.size():
		var slot: AIEquipmentSlot = equipment_slots[i]
		if not slot.has_uses():
			continue
		# Check cooldown
		var cooldown_remaining = _equipment_cooldowns.get(i, 0.0)
		if cooldown_remaining > 0.0:
			continue
		if slot.equipment_scene == null:
			continue
		# Instantiate temporarily to call can_use — then discard or keep
		var equipment = slot.equipment_scene.instantiate() as AIEquipment
		if equipment == null:
			continue
		if equipment.can_use(context):
			# Add to scene so it has tree access for execute()
			get_tree().current_scene.add_child(equipment)
			equipment.execute(context)
			slot.consume()
			_equipment_cooldowns[i] = equipment.cooldown
			# equipment frees itself or we free it after execute
			if equipment.is_inside_tree():
				equipment.queue_free()
			return  # only one piece of equipment per evaluation tick
		else:
			equipment.free()

func reconsider_patrol():
	if patrol_path == null or patrol_path.points.is_empty():
		return
	if nav_agent.is_navigation_finished() or movement_target == null:
		var next_point = patrol_path.get_next_point(self)
		if next_point:
			move_to(next_point.global_position)
			look_target = next_point.global_position

#endregion Reconsider
func change_ai_state(new_state: AIState):
	#bark.bark()
	if ai_state != new_state:
		#print("Changing state to:", new_state)
		ai_state = new_state
		movement_time = 0
		idle_time = 0
		wander_time = 0
		combat_time = 0
		search_time = 0
		patrol_time = 0
		chasing_time = 0
		targeting_time = 0

func change_combat_target(body):
	combat_target = body
	weapon_target = body.global_position
	look_target = body.global_position

func perform_action(action: CombatOptions):
	match action:
		CombatOptions.MOVE:
			#print ("HEY MOVE WAS SEELCTED!")
			var keys := AllowedMovementOptions
			var random_index := randi_range(0, keys.size() - 1)
			var new_move_target
			var movement = keys[random_index]
			#print (movement)
			match movement:
				MovementOptions.LEAP:
					#print ("LEAP")
					movement_state = MovementState.LEAPING
					leap_towards(combat_target.global_position)
					pass
				MovementOptions.REPOSITION:
					#print ("REPOSITION")
					new_move_target = find_reposition_target()
					#if new_move_target != false:
					move_to(new_move_target)
					pass
				MovementOptions.ADVANCE:
					#OLD ADVANCE
					new_move_target =  find_advance_target()
					move_to(new_move_target)
					#NEW ADVANCE
					pass
				MovementOptions.CHASE:
					movement_state = MovementState.CHASING
				MovementOptions.FALLBACK:
					#print ("FALLBACK")
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

func leap_towards(target_pos: Vector3, leap_vel: float = 16.5):
	movement_state = MovementState.LEAPING
	var vel = compute_leap_velocity_fixed_speed(target_pos, leap_vel)
	velocity = vel
	look_target = target_pos

func compute_leap_velocity(target: Vector3, time: float) -> Vector3:
	var g = gravity
	var displacement := target - global_position
	var dx = displacement.x
	var dy = displacement.y
	var dz = displacement.z
	var vx = dx / time
	var vz = dz / time
	var vy = (dy / time) + (0.5 * g * time)
	return Vector3(vx, vy, vz)
func compute_leap_velocity_fixed_speed(target: Vector3, speed: float) -> Vector3:
	var g = gravity
	var displacement := target - global_position
	# Separate horizontal and vertical components
	var horizontal_displacement = displacement
	horizontal_displacement.y = 0.0
	var distance = horizontal_displacement.length()
	# How long will the leap take at this fixed horizontal speed?
	if speed <= 0.0:
		return Vector3.ZERO  # avoid divide by zero
	var time = distance / speed
	# Horizontal direction (normalized)
	var direction = horizontal_displacement.normalized()
	# Compute horizontal velocity
	var vx = direction.x * speed
	var vz = direction.z * speed
	# Compute vertical velocity to reach Y in that time
	var dy = displacement.y
	var vy = (dy / time) + (0.5 * g * time)
	return Vector3(vx, vy, vz)

func fire():
	var final_target = get_inaccurate_target(weapon_target)
	weapon.fire(final_target)
	pass

func apply_damage(damage, source) -> void:
	if ai_state == AIState.DEAD:
		return
	if source is Player:
		player = source
		damaged_by_player = true
	# Retaliate against whoever shot us, if hostile
	if source is CharacterBody3D and _is_hostile(source):
		if ai_state != AIState.COMBAT:
			trigger_combat(source)
			combat_triggered.emit(self)
		elif combat_target == null:
			change_combat_target(source)
	bark.bark()
	health -= damage
	if health <= 0:
		die()
		return
	for i in particle_effects_hit:
		i.activate()

func die():
	if alive == false:
		return
	set_physics_process(false)
	set_process(false)
	alive = false
	change_ai_state(AIState.DEAD)
	for i in particle_effects_die:
		i.activate()
	nav_agent.set_target_position(global_position)  # Cancel nav
	if damaged_by_player == true:
		player.add_bits(bits)
	$CollisionShape3D.disabled = true  # or disable all collision shapes
	damaged_by_player = false
	#await get_tree().create_timer(0.9).timeout
	hide_body()
	if weapon != null:
		weapon.hide()
func respawn():
	reset()

func hide_body():
	for i in visible_pieces:
		i.visible = false

func show_body():
	for i in visible_pieces:
		i.visible = true

func reset():
	ai_state = DefaultAIState
	transform = spawn_transform
	health = max_health
	alive = true
	change_ai_state(DefaultAIState)
	seen_bodies.clear()
	last_seen_point.clear()
	checking_for_target = false
	velocity = Vector3.ZERO
	weapon_target = Vector3.ZERO
	look_target = Vector3.ZERO
	show_body()
	if weapon != null:
		weapon.show()
	movement_time = 0
	combat_time = 0
	weapon_time = 0
	targeting_time = 0
	fire_time = 0
	idle_time = 0
	search_time = 0
	wander_time = 0
	_equipment_cooldowns.clear()
	_target_stationary_time = 0.0
	_target_last_position = Vector3.ZERO
	_equipment_recon_timer = 0.0
	for slot in equipment_slots:
		slot.initialize()
	set_physics_process(true)
	set_process(true)
	$CollisionShape3D.disabled = false

func get_faction():
	return faction

func _is_hostile(body: Node3D) -> bool:
	if body is Player:
		return Enums.are_hostile(faction, Enums.Factions.PLAYER)
	if body is Enemy:
		return Enums.are_hostile(faction, (body as Enemy).faction)
	return false

func is_path_clear(from: Vector3, to: Vector3) -> bool:
	var space_state = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclusion = [self]
	if combat_target != null:
		exclusion.append(combat_target)
	elif player != null:
		exclusion.append(player)
	query.exclude = exclusion
	var result = space_state.intersect_ray(query)
	return not result

func update_debug_label():
	var ai_state_str = AIState.keys()[ai_state]
	var movement_state_str = MovementState.keys()[movement_state]
	var weapon_state_str = WeaponState.keys()[weapon_state]
	var faction_str = Enums.Factions.keys()[faction]
	label.text = "AI: %s\nFaction: %s\nMovement State: %s\nWeapon State: %s" % [
		ai_state_str,
		faction_str,
		movement_state_str,
		weapon_state_str
	]
func force_check_detection():
	var shape = detection.get_child(0).shape
	var new_transform: Transform3D = detection.global_transform
	var space_state = get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = new_transform
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [detection, self]
	var results = space_state.intersect_shape(query, 64)
	for result in results:
		var collider = result.collider
		#print("Area overlaps with: ", collider)
		if collider is Player:
			_on_detection_body_entered(collider)
func _on_detection_body_entered(body: Node3D) -> void:
	if ai_state == AIState.DEAD:
		return
	# Ignore bodies that aren't AI or Player
	if not (body is Player or body is Enemy):
		return
	# Ignore if already fighting this body
	if ai_state == AIState.COMBAT and combat_target == body:
		return
	# Faction check — only react to hostiles
	if not _is_hostile(body):
		return
	if is_path_clear(global_position, body.global_position):
		trigger_combat(body)
	else:
		# LOS blocked — keep checking each frame until clear
		checking_for_target = true
		combat_target = body

func _on_detection_body_exited(body: Node3D) -> void:
	# If the body we were waiting on LOS for just left detection range, stop checking
	if checking_for_target and body == combat_target:
		checking_for_target = false

func trigger_combat(body: AI):
	change_combat_target(body)
	movement_target = Vector3.ZERO
	change_ai_state(AIState.COMBAT)
	combat_triggered.emit(self)
	checking_for_target = false
	combat_time = combat_recon_time
	reconsider_combat()

func get_inaccurate_target(target_pos: Vector3) -> Vector3:
	var dist := global_position.distance_to(weapon_target)
	# If too far away → guaranteed miss
	if dist > max_fire_distance:
		return target_pos + get_random_spread(dist, min_accuracy)
	var t = clamp(dist / max_fire_distance, 0.0, 1.0)
	var accuracy = lerp(max_accuracy, min_accuracy, t)
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
