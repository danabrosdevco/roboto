extends AI
class_name Enemy

# ── NODE REFERENCES ──────────────────────────
@export var patrol_path: PatrolPath
@export var nav_agent: NavigationAgent3D
@export var weapon: AIWeapon
@export var label: Label3D
@export var bark: Bark
@export var detection: Area3D
@export var particle_effects_die: Array[ParticleEffect]
@export var particle_effects_hit: Array[ParticleEffect]
@export var visible_pieces: Array[Node3D]

# ── EXPORT DATA ───────────────────────────────
@export var activation_distance: int = 75
@export var health: int = 30
@export var max_health: int = 30
@export var faction: Enums.Factions = Enums.Factions.ENEMY
@export var move_speed: float = 4.5
@export var acceleration := 1.50
@export var rotation_speed := 1.0
@export var reposition_distance: float = 2.0
@export var advance_distance: float = 3.0
@export var fallback_distance: float = 1.25
@export var max_fire_distance: float = 30
@export var max_accuracy: float = 0.90
@export var min_accuracy: float = 0.5
@export var bits: int = 10
@export var combat_recon_time: float = 1.65
# Search: how long to search before giving up
@export var search_duration: float = 8.0
# LOS patience at CLOSE range — scales up to 3x at max_fire_distance
@export var los_patience_close: float = 2.0

# ── ENUMS ─────────────────────────────────────
enum AIState { COMBAT, PATROL, SEARCH, IDLE, DEAD, PASSIVE }
enum MovementState { NONE, MOVING, LEAPING, ADVANCING, CHASING }
enum WeaponState { FIRE, RELOAD, AIM, IDLE }
enum CombatOptions { MOVE, AIM, FIRE }
enum MovementOptions { ADVANCE, REPOSITION, FALLBACK, LEAP, CHASE }

@export var DefaultAIState: AIState
@export var AllowedMovementOptions: Array[MovementOptions]
@export var AllowedCombatOptions: Array[CombatOptions]

# ── CONST ─────────────────────────────────────
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# ── MANAGER REFS ──────────────────────────────
var player: Player
var ai_manager: AIManager
var stimulus_manager: StimulusManager

# ── WORKING DATA ──────────────────────────────
var damaged_by_player: bool = false
var idle_to_wander = 3
var movement_recon_time = 1.5
var targeting_recon_time = 0.33
var weapon_recon_time = 1.5
var patrol_recon_time = 1.5
var chasing_recon_time = 0.2
var wander_delay = 1.5
var wander_radius = 3.5

var checking_for_target: bool = false
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
var alive: bool = true

var combat_time: float = 0.0
var movement_time: float = 0.0
var search_time: float = 0.0
var patrol_time: float = 0.0
var fire_time: float = 0.0
var weapon_time: float = 0.0
var wander_time: float = 0.0
var targeting_time: float = 0.0
var idle_time: float = 0.0
var chasing_time: float = 0.0
var los_lost_time: float = 0.0
# Set by Squad when broadcasting shared target — scales accuracy down
# proportional to how stale the intel is (1.0 = fresh, 0.0 = pure area fire)
var _shared_target_accuracy_scale: float = 1.0

# last_seen_point: ring buffer of up to 5 positions, newest at back
var last_seen_point: Array[Vector3] = []
var seen_bodies: Array = []
var frame_waited: bool = false

signal combat_triggered(ai: AI)


# ─────────────────────────────────────────────
# INIT
# ─────────────────────────────────────────────
func initialize():
	spawn_transform = transform
	activation_distance_sq = activation_distance * activation_distance
	# Wait for nav mesh and scene to fully settle
	for i in 8:
		await get_tree().process_frame
	ai_state = DefaultAIState
	frame_waited = true
	reconsider_target()


# ─────────────────────────────────────────────
# PHYSICS PROCESS
# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not frame_waited or ai_state == AIState.DEAD:
		return
	if player == null:
		return

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


# ─────────────────────────────────────────────
# PASSIVE MODE
# ─────────────────────────────────────────────
func enter_passive_mode():
	if ai_state == AIState.PASSIVE:
		return
	change_ai_state(AIState.PASSIVE)
	velocity.x = 0
	velocity.z = 0
	movement_state = MovementState.NONE
	weapon_state = WeaponState.IDLE
	nav_agent.set_target_position(global_position)

func exit_passive_mode():
	if ai_state != AIState.PASSIVE:
		return
	change_ai_state(DefaultAIState)


# ─────────────────────────────────────────────
# TIME / STATE TICKS
# ─────────────────────────────────────────────
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
			# Track LOS loss — patience scales with distance
			if combat_target != null and combat_target.alive:
				if not is_path_clear(global_position, combat_target.global_position):
					los_lost_time += delta
					var effective_patience = _los_patience()
					if los_lost_time >= effective_patience:
						# Record last known and enter search
						_record_last_seen(combat_target.global_position)
						enter_search(last_seen_point.back())
				else:
					los_lost_time = 0.0
					_record_last_seen(combat_target.global_position)
					if self is Soldier and (self as Soldier).squad != null:
						(self as Soldier).squad.update_shared_target(combat_target.global_position, self)

		AIState.PATROL:
			patrol_time += delta
			if patrol_time >= patrol_recon_time:
				reconsider_patrol()

		AIState.IDLE:
			idle_time += delta

		AIState.SEARCH:
			search_time += delta
			if search_time >= search_duration:
				reconsider_search()
			# While searching, fire suppressing shots at last known position
			# even without confirmed LOS (area targeting mode)
			if not last_seen_point.is_empty():
				weapon_target = last_seen_point.back()
				look_target = weapon_target

	if targeting_time >= targeting_recon_time:
		reconsider_target()

func _los_patience() -> float:
	# Scale patience: close range = los_patience_close, max range = 3x that
	if combat_target == null:
		return los_patience_close
	var dist = global_position.distance_to(combat_target.global_position)
	var t = clamp(dist / max_fire_distance, 0.0, 1.0)
	return lerp(los_patience_close, los_patience_close * 3.0, t)

func _record_last_seen(pos: Vector3) -> void:
	if last_seen_point.is_empty() or last_seen_point.back().distance_to(pos) > 1.0:
		last_seen_point.append(pos)
		if last_seen_point.size() > 5:
			last_seen_point.pop_front()


# ─────────────────────────────────────────────
# GRAVITY / MOVEMENT
# ─────────────────────────────────────────────
func handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

func handle_targeting(_delta):
	pass

func handle_movement(delta):
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
	if base_dir.length() > 0.01:
		var current_yaw = rotation.y
		var target_yaw = atan2(-base_dir.x, -base_dir.z)
		rotation.y = lerp_angle(current_yaw, target_yaw, rotation_speed * delta)

func handle_chasing(delta):
	if combat_target == null or not combat_target.alive:
		movement_state = MovementState.NONE
		return
	chasing_time += delta
	if chasing_time >= chasing_recon_time:
		chasing_time = 0
		nav_agent.set_target_position(combat_target.global_position)
	move_along_nav(delta)

func handle_leap(delta):
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


# ─────────────────────────────────────────────
# WEAPON LOGIC
# ─────────────────────────────────────────────
func handle_weapon_logic(delta):
	if fire_time >= 0:
		fire_time -= delta

	var can_fire = ai_state == AIState.COMBAT or ai_state == AIState.SEARCH
	if not can_fire:
		weapon_state = WeaponState.IDLE
		return

	if weapon == null:
		return

	# If weapon needs a reload, enter RELOAD state and let weapon handle the timer
	if weapon.needs_reload():
		weapon_state = WeaponState.RELOAD
		weapon.start_reload()
		return

	# While weapon is reloading, stay in RELOAD — don't try to fire
	if weapon.is_reloading:
		weapon_state = WeaponState.RELOAD
		return

	if weapon_time >= weapon_recon_time:
		reconsider_weapon()

	match weapon_state:
		WeaponState.RELOAD:
			# Reload just finished (weapon.is_reloading is now false) — back to AIM
			weapon_state = WeaponState.AIM

		WeaponState.IDLE:
			weapon_state = WeaponState.AIM

		WeaponState.AIM:
			var dist = global_position.distance_to(weapon_target)
			if fire_time <= 0 and dist <= max_fire_distance and weapon.can_fire():
				if weapon.weapon_type == Enums.AIWeaponTypes.MELEE:
					if combat_target != null and is_path_clear(global_position, combat_target.global_position):
						weapon_state = WeaponState.FIRE
				else:
					if ai_state == AIState.SEARCH:
						weapon_state = WeaponState.FIRE
					elif combat_target != null and is_path_clear(global_position, combat_target.global_position):
						weapon_state = WeaponState.FIRE

		WeaponState.FIRE:
			if fire_time <= 0.0 and weapon.can_fire():
				fire()
				fire_time = weapon.fire_cooldown
				weapon_state = WeaponState.AIM


# ── RECONSIDER REGION ─────────────────────────
func roll_combat_action():
	if AllowedCombatOptions.is_empty():
		return
	var options := AllowedCombatOptions.duplicate()
	if options.size() > 1:
		options.erase(previous_combat_option)
	var new_action = options[randi_range(0, options.size() - 1)]
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

func reconsider_weapon():
	weapon_time = 0

func reconsider_combat():
	combat_time = 0
	roll_combat_action()

func reconsider_target() -> void:
	targeting_time = 0

	# Target alive and hostile — keep it, update weapon/look
	if combat_target != null and combat_target.alive:
		if _is_hostile(combat_target):
			weapon_target = combat_target.global_position
			look_target = combat_target.global_position
			return

	# Target dead — clear it, look where we're going
	if combat_target != null and not combat_target.alive:
		combat_target = null
		weapon_target = Vector3.ZERO
		if movement_target != Vector3.ZERO:
			look_target = movement_target

	# Try to find a new hostile via manager
	var new_target: CharacterBody3D = null
	if ai_manager != null:
		new_target = ai_manager.get_nearest_hostile(self)
	elif player != null and Enums.are_hostile(faction, Enums.Factions.PLAYER):
		new_target = player

	if new_target != null:
		if ai_state == AIState.COMBAT:
			change_combat_target(new_target)
		elif ai_state == AIState.SEARCH:
			# Found a target while searching — re-engage immediately
			trigger_combat(new_target)
		# Don't auto-trigger from IDLE/PATROL — let detection handle that
	else:
		# No hostiles at all
		combat_target = null
		weapon_target = Vector3.ZERO
		if movement_target != Vector3.ZERO:
			look_target = movement_target
		if ai_state == AIState.COMBAT:
			if not last_seen_point.is_empty():
				enter_search(last_seen_point.back())
			else:
				change_ai_state(AIState.PATROL)
		# If already SEARCH, let search timer run out

func reconsider_patrol():
	if patrol_path == null or patrol_path.points.is_empty():
		return
	if nav_agent.is_navigation_finished() or movement_target == null:
		var next_point = patrol_path.get_next_point(self)
		if next_point:
			move_to(next_point.global_position)
			look_target = next_point.global_position

func enter_search(search_position: Vector3) -> void:
	los_lost_time = 0.0
	combat_target = null
	weapon_target = search_position   # keep firing at last known
	change_ai_state(AIState.SEARCH)
	move_to(search_position)
	look_target = search_position
	# Notify squad so shared target position stays current during search
	if self is Soldier and (self as Soldier).squad != null:
		(self as Soldier).squad.update_shared_target(search_position, self)

func reconsider_search() -> void:
	search_time = 0.0
	last_seen_point.clear()
	weapon_target = Vector3.ZERO
	if patrol_path != null and not patrol_path.points.is_empty():
		change_ai_state(AIState.PATROL)
		reconsider_patrol()
	else:
		change_ai_state(AIState.IDLE)
# ─────────────────────────────────────────────


func change_ai_state(new_state: AIState):
	if ai_state != new_state:
		ai_state = new_state
		movement_time = 0
		idle_time = 0
		wander_time = 0
		combat_time = 0
		search_time = 0
		patrol_time = 0
		chasing_time = 0
		targeting_time = 0
		los_lost_time = 0.0

func change_combat_target(body):
	combat_target = body
	weapon_target = body.global_position
	look_target = body.global_position

func perform_action(action: CombatOptions):
	match action:
		CombatOptions.MOVE:
			var keys := AllowedMovementOptions
			if keys.is_empty():
				return
			var movement = keys[randi_range(0, keys.size() - 1)]
			match movement:
				MovementOptions.LEAP:
					if combat_target != null:
						movement_state = MovementState.LEAPING
						leap_towards(combat_target.global_position)
				MovementOptions.REPOSITION:
					move_to(find_reposition_target())
				MovementOptions.ADVANCE:
					move_to(find_advance_target())
				MovementOptions.CHASE:
					if combat_target != null:
						movement_state = MovementState.CHASING
				MovementOptions.FALLBACK:
					move_to(find_fallback_target())
		CombatOptions.FIRE:
			pass
		CombatOptions.AIM:
			pass


# ── POSITION FINDERS ──────────────────────────
func find_reposition_target():
	if combat_target == null:
		return global_position
	var nav_map = nav_agent.get_navigation_map()
	var to_target = (combat_target.global_position - global_position).normalized()
	var right = to_target.cross(Vector3.UP).normalized()
	var lateral_dir = right if randf() > 0.5 else -right
	var test_pos = global_position + lateral_dir * reposition_distance
	var closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
	if is_path_clear(closest_point, combat_target.global_position):
		return closest_point
	test_pos = global_position + lateral_dir * reposition_distance * 0.5
	closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
	if is_path_clear(closest_point, combat_target.global_position):
		return closest_point
	return global_position

func find_advance_target():
	if combat_target == null:
		return global_position
	var nav_map = nav_agent.get_navigation_map()
	var direction = (combat_target.global_position - global_position).normalized()
	var test_pos = global_position + direction * advance_distance
	var closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
	if is_path_clear(closest_point, combat_target.global_position):
		return closest_point
	test_pos = global_position + direction * advance_distance * 0.5
	closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
	if is_path_clear(test_pos, combat_target.global_position):
		return closest_point
	return global_position

func find_fallback_target():
	if combat_target == null:
		return global_position
	var nav_map = nav_agent.get_navigation_map()
	var away_dir = (global_position - combat_target.global_position).normalized()
	var test_pos = global_position + away_dir * fallback_distance
	var closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
	if is_path_clear(closest_point, combat_target.global_position):
		return closest_point
	test_pos = global_position + away_dir * fallback_distance * 0.5
	closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
	if is_path_clear(test_pos, combat_target.global_position):
		return closest_point
	return global_position


# ── LEAP ──────────────────────────────────────
func leap_towards(target_pos: Vector3, leap_vel: float = 16.5):
	movement_state = MovementState.LEAPING
	velocity = compute_leap_velocity_fixed_speed(target_pos, leap_vel)
	look_target = target_pos

func compute_leap_velocity(target: Vector3, time: float) -> Vector3:
	var displacement := target - global_position
	var vy = (displacement.y / time) + (0.5 * gravity * time)
	return Vector3(displacement.x / time, vy, displacement.z / time)

func compute_leap_velocity_fixed_speed(target: Vector3, speed: float) -> Vector3:
	if speed <= 0.0:
		return Vector3.ZERO
	var displacement := target - global_position
	var horiz = displacement
	horiz.y = 0.0
	var distance = horiz.length()
	var time = distance / speed
	var direction = horiz.normalized()
	var vy = (displacement.y / time) + (0.5 * gravity * time)
	return Vector3(direction.x * speed, vy, direction.z * speed)


# ── FIRE / DAMAGE / DEATH ─────────────────────
func fire():
	if weapon == null or not weapon.can_fire():
		return
	var final_target = get_inaccurate_target(weapon_target)
	weapon.fire(final_target)
	if stimulus_manager != null:
		stimulus_manager.emit_stimulus(
			StimulusManager.StimulusType.GUNSHOT_HEARD,
			global_position, faction, self)

func apply_damage(damage, source) -> void:
	if ai_state == AIState.DEAD:
		return
	if source is Player:
		player = source
		damaged_by_player = true
	if source is CharacterBody3D and _is_hostile(source):
		if ai_state != AIState.COMBAT:
			trigger_combat(source)
			combat_triggered.emit(self)
		elif combat_target == null:
			change_combat_target(source)
		if stimulus_manager != null:
			stimulus_manager.emit_stimulus(
				StimulusManager.StimulusType.ALLY_SHOT,
				global_position, faction, source)
	bark.bark()
	health -= damage
	if health <= 0:
		die()
		return
	for i in particle_effects_hit:
		i.activate()

func die():
	if not alive:
		return
	if stimulus_manager != null:
		stimulus_manager.emit_stimulus(
			StimulusManager.StimulusType.ALLY_DIED,
			global_position, faction, self)
	set_physics_process(false)
	set_process(false)
	alive = false
	change_ai_state(AIState.DEAD)
	for i in particle_effects_die:
		i.activate()
	nav_agent.set_target_position(global_position)
	if damaged_by_player:
		player.add_bits(bits)
	$CollisionShape3D.disabled = true
	damaged_by_player = false
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
	los_lost_time = 0.0
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
	set_physics_process(true)
	set_process(true)
	$CollisionShape3D.disabled = false


# ── STIMULUS ──────────────────────────────────
func receive_stimulus(
	type: StimulusManager.StimulusType,
	source_position: Vector3,
	source_node: Node,
	distance: float
) -> void:
	if ai_state == AIState.DEAD or ai_state == AIState.PASSIVE:
		return
	match type:
		StimulusManager.StimulusType.GUNSHOT_HEARD:
			if ai_state != AIState.COMBAT:
				look_target = source_position

		StimulusManager.StimulusType.ALLY_SHOT:
			if ai_state != AIState.COMBAT:
				look_target = source_position
			if source_node != null and _is_hostile(source_node):
				if is_path_clear(global_position, source_position):
					trigger_combat(source_node)

		StimulusManager.StimulusType.ALLY_DIED:
			if ai_state != AIState.COMBAT:
				look_target = source_position
			if distance < StimulusManager.DEFAULT_RADIUS[type] * 0.5:
				if source_node != null and _is_hostile(source_node):
					if is_path_clear(global_position, source_node.global_position):
						trigger_combat(source_node)

		StimulusManager.StimulusType.ENEMY_SPOTTED:
			# Squad shared target — move toward spotted position if nearby and idle
			if ai_state != AIState.COMBAT and ai_state != AIState.SEARCH:
				if distance < 20.0:
					enter_search(source_position)
				else:
					look_target = source_position


# ── HELPERS ───────────────────────────────────
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
	var target_str = combat_target.name if combat_target != null else "none"
	label.text = "AI: %s\nFaction: %s\nMove: %s\nWeapon: %s\nTarget: %s\nLOS lost: %.1fs" % [
		AIState.keys()[ai_state],
		Enums.Factions.keys()[faction],
		MovementState.keys()[movement_state],
		WeaponState.keys()[weapon_state],
		target_str,
		los_lost_time
	]

func force_check_detection():
	var shape = detection.get_child(0).shape
	var space_state = get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = detection.global_transform
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [detection, self]
	var results = space_state.intersect_shape(query, 64)
	for result in results:
		var collider = result.collider
		if collider is Player:
			_on_detection_body_entered(collider)

func _on_detection_body_entered(body: Node3D) -> void:
	if ai_state == AIState.DEAD:
		return
	if not (body is Player or body is Enemy):
		return
	if ai_state == AIState.COMBAT and combat_target == body:
		return
	if not _is_hostile(body):
		return
	if is_path_clear(global_position, body.global_position):
		trigger_combat(body)
		if stimulus_manager != null:
			stimulus_manager.emit_stimulus(
				StimulusManager.StimulusType.ENEMY_SPOTTED,
				body.global_position, faction, body)
	else:
		checking_for_target = true
		combat_target = body

func _on_detection_body_exited(body: Node3D) -> void:
	if checking_for_target and body == combat_target:
		checking_for_target = false
	# Active combat target left detection range while alive — search for them
	if body == combat_target and combat_target != null and combat_target.alive:
		if ai_state == AIState.COMBAT:
			_record_last_seen(body.global_position)
			enter_search(last_seen_point.back())

func trigger_combat(body: AI):
	change_combat_target(body)
	movement_target = Vector3.ZERO
	change_ai_state(AIState.COMBAT)
	combat_triggered.emit(self)
	checking_for_target = false
	combat_time = combat_recon_time
	reconsider_combat()


# ── ACCURACY ──────────────────────────────────
func get_inaccurate_target(target_pos: Vector3) -> Vector3:
	var dist := global_position.distance_to(weapon_target)
	if dist > max_fire_distance:
		return target_pos + get_random_spread(dist, min_accuracy)
	var t = clamp(dist / max_fire_distance, 0.0, 1.0)
	var accuracy = lerp(max_accuracy, min_accuracy, t)
	# Degrade accuracy further when firing at shared/stale target position
	accuracy *= _shared_target_accuracy_scale
	# Reset scale so next frame uses personal accuracy unless squad updates it again
	_shared_target_accuracy_scale = 1.0
	return target_pos + get_random_spread(dist, accuracy)

func get_random_spread(distance: float, accuracy: float) -> Vector3:
	var spread_strength := (1.0 - accuracy)
	var max_offset := spread_strength * (distance * 0.1)
	return Vector3(
		randf_range(-max_offset, max_offset),
		randf_range(-max_offset, max_offset),
		randf_range(-max_offset, max_offset)
	)
