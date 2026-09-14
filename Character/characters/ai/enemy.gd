extends AI
class_name Enemy

# ── NODE REFERENCES ───────────────────────────
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
## Movement response rate, used as 1-exp(-acceleration*delta).
## Framerate independent. ~8 is responsive, ~3 is heavy and lumbering.
## NOTE: scenes overriding this with the old ~1.5-2.0 values will feel sluggish.
@export var acceleration := 8.0
## Turn response rate, same curve as acceleration.
@export var rotation_speed := 7.0
@export var reposition_distance: float = 2.0
@export var advance_distance: float = 3.0
@export var fallback_distance: float = 1.25
@export var bits: int = 10
@export var equipment_slots: Array[AIEquipmentSlot] = []
@export var combat_recon_time: float = 1.65
# Display name shown in the debug label — e.g. "Shotgun Grunt", "Sniper", "Heavy"
@export var soldier_name: String = "Enemy"

# ── ACCURACY ──────────────────────────────────
# accuracy_skill: static per-character. How close this AI shoots to the
# weapon's physical spread limit. Degraded at runtime by signal_integrity.
@export var accuracy_skill: float = 0.75

# ── AIMING ────────────────────────────────────
## Seconds of settled, stationary tracking before accuracy is at its best.
@export var aim_settle_time: float = 1.2
## Accuracy fraction at zero tracking. 0.35 means a snap shot has ~2.9x the
## spread of a settled shot.
@export var aim_floor: float = 0.35
## Spread multiplier applied while the body is actually moving.
@export var moving_accuracy_penalty: float = 3.0
## Shots per committed burst when the AI rolls FIRE.
@export var burst_min: int = 2
@export var burst_max: int = 5

# ── DECISION WEIGHTING ────────────────────────
## Multiplier applied to the previously chosen action when re-rolling.
## 1.0 = no memory, 0.0 = never repeat. Anything in between discourages
## repetition without banning it, which is what stops the metronome feel.
@export var repeat_penalty: float = 0.45
## Per-character jitter applied to combat_recon_time at spawn so squads
## don't re-decide in lockstep.
@export var recon_jitter: float = 0.25

# ── SEARCH ────────────────────────────────────
@export var search_duration: float = 9.0
@export var search_look_interval: float = 1.6

# ── SIGNAL INTEGRITY ──────────────────────────
# The health of this robot's networked systems.
# Degraded by suppressing fire, EMP, jamming. Recovers passively.
# Drives a cascade of behavioral degradation.
@export var signal_integrity: float = 1.0
@export var signal_recovery_rate: float = 0.08   # per second, passive recovery
@export var signal_resistance: float = 1.0       # damage multiplier. >1 = more resistant

# Never enters passive mode — set true on soldiers with active squad objectives
@export var always_active: bool = false
# ── CLOSE THREAT ───────────────────────────────
# Opportunistic retargeting. The detection Area3D handles long-range
# acquisition; this handles "something is right next to me", which the old code
# had no concept of — reconsider_target() kept whatever target it already had as
# long as that target was alive, so a hostile that walked into arm's reach while
# you were shooting at someone 40m away was simply never noticed.
#
# Deliberately narrow. It only fires inside close_threat_range, so patrolling
# robots don't start aggroing across the level from the targeting tick; the
# Area3D still owns everything beyond a few metres.
@export var close_threat_range: float = 6.0
# How much closer the new contact has to be before it's worth switching. Without
# a margin two hostiles at similar range make the AI oscillate between them
# every targeting tick and it never shoots anything.
@export var close_threat_advantage: float = 8.0
# Don't swap onto something on the far side of a wall.
@export var close_threat_requires_los: bool = true

# What we were shooting at before a close threat interrupted. Restored when the
# close threat dies, so a squad ATTACK order survives being jumped en route.
var _preempted_target: CharacterBody3D = null

signal close_threat_engaged(target)

# Detection range used for signal-degraded sensor checks (match your Area3D radius)
@export var detection_radius: float = 20.0

# ── ENUMS ─────────────────────────────────────
# NOTE: ordering is load-bearing. Scenes store these as raw ints.
enum AIState { COMBAT, PATROL, SEARCH, IDLE, DEAD, PASSIVE }
enum MovementState { NONE, MOVING, LEAPING, ADVANCING, CHASING }
enum WeaponState { FIRE, RELOAD, AIM, IDLE }
enum CombatOptions { MOVE, AIM, FIRE }
enum MovementOptions { ADVANCE, REPOSITION, FALLBACK, LEAP, CHASE }

# Signal degradation stages
enum SignalState { CLEAN, FUZZED, DEGRADED, CRITICAL, EKILL }
const SIGNAL_FUZZED: float   = 0.75  # below here: accuracy penalty kicks in
const SIGNAL_DEGRADED: float = 0.50  # below here: sensors halved, movement stutters
const SIGNAL_CRITICAL: float = 0.25  # below here: ignores squad orders, erratic
const SIGNAL_EKILL: float    = 0.01  # below here: fully disabled

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

var previous_combat_option: CombatOptions = CombatOptions.MOVE
var previous_movement_option: MovementOptions = MovementOptions.ADVANCE

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

var last_seen_point: Array[Vector3] = []
var seen_bodies: Array = []
var frame_waited: bool = false

# ── EQUIPMENT ─────────────────────────────────
var _equipment_cooldowns: Dictionary = {}
var _target_stationary_time: float = 0.0
var _target_last_position: Vector3 = Vector3.ZERO
const EQUIPMENT_RECON_TIME: float = 1.5
var _equipment_recon_timer: float = 0.0

# ── STUCK DETECTION ───────────────────────────
const STUCK_CHECK_INTERVAL: float = 3.0
const STUCK_MOVE_THRESHOLD: float = 0.5
var _stuck_timer: float = 0.0
var _stuck_last_position: Vector3 = Vector3.ZERO
var _stuck_retry_count: int = 0

# ── NO-LOS TIMER ──────────────────────────────
const NO_LOS_PATIENCE: float = 4.0
var _no_los_timer: float = 0.0

# ── LOS CACHE ─────────────────────────────────
# One raycast per interval, shared by weapon logic, the no-LOS timer and
# the deferred-detection check. Previously each of those raycast separately,
# every frame, per AI.
const LOS_CHECK_INTERVAL: float = 0.15
var _has_los: bool = false
var _los_check_timer: float = 0.0

# ── AIM / BURST ───────────────────────────────
var _aim_tracking: float = 0.0
var _burst_left: int = 0

# ── FACING ────────────────────────────────────
var _last_move_dir: Vector3 = Vector3.ZERO

# ── SEARCH / WANDER ───────────────────────────
var _search_look_timer: float = 0.0
var _next_wander_at: float = 3.0

# ── LOS SEEK BUDGET ───────────────────────────
# One ring per call rather than four, so a squad losing LOS at the same
# moment doesn't spike the frame.
const SEEK_RING_RADII := [1.0, 1.5, 2.5, 4.0]
var _seek_ring_index: int = 0

# ── CACHED NODES ──────────────────────────────
var _collision_shape: CollisionShape3D = null
var _self_rid: RID

# ── SIGNAL WORKING STATE ──────────────────────
# Tracks stuttering for DEGRADED movement hesitation
var _signal_stutter_timer: float = 0.0
const SIGNAL_STUTTER_INTERVAL: float = 0.8  # how often to check for stutter

signal combat_triggered(ai: AI)


# ─────────────────────────────────────────────
# INIT
# ─────────────────────────────────────────────
func initialize():
	spawn_transform = transform
	activation_distance_sq = activation_distance * activation_distance
	_self_rid = get_rid()
	_collision_shape = _find_collision_shape()

	# Desynchronise decision cadence per character. Without this every
	# soldier in a squad re-rolls on exactly the same frame.
	combat_recon_time *= randf_range(1.0 - recon_jitter, 1.0 + recon_jitter)
	combat_time = randf() * combat_recon_time
	targeting_time = randf() * targeting_recon_time
	_los_check_timer = randf() * LOS_CHECK_INTERVAL
	_next_wander_at = wander_delay + randf_range(0.0, float(idle_to_wander))

	await get_tree().process_frame
	ai_state = DefaultAIState
	frame_waited = true
	for slot in equipment_slots:
		slot.initialize()
	if weapon != null and not weapon.reload_finished.is_connected(_on_reload_finished):
		weapon.reload_finished.connect(_on_reload_finished)
	reconsider_target()

func _find_collision_shape() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child
	return null


# ─────────────────────────────────────────────
# PHYSICS PROCESS
# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not frame_waited or ai_state == AIState.DEAD:
		return
	if player == null:
		return

	handle_gravity(delta)

	# Signal always ticks, even when passive or disabled, so a robot can
	# actually recover from an e-kill instead of being bricked forever.
	_tick_signal(delta)

	# E-KILL: electronically disabled — freeze in place, do nothing
	if get_signal_state() == SignalState.EKILL:
		_enter_ekill()
		_apply_motion()
		return

	var dist_sq = global_position.distance_squared_to(player.global_position)
	if dist_sq > activation_distance_sq:
		enter_passive_mode()
		_apply_motion()
		return
	else:
		exit_passive_mode()

	_tick_los(delta)
	if checking_for_target and combat_target != null and _has_los:
		trigger_combat(combat_target)
	handle_time_passing(delta)
	handle_movement(delta)
	_update_facing(delta)
	handle_weapon_logic(delta)
	_apply_motion()
	if label != null:
		update_debug_label()


# ─────────────────────────────────────────────
# MOTION
# Single move_and_slide per frame, at the end.
# Previously it only ran inside move_along_nav / handle_leap, so a
# stationary AI accumulated velocity.y forever and never refreshed
# is_on_floor().
# ─────────────────────────────────────────────
func _apply_motion() -> void:
	# Cheap out for a settled passive body — nothing to resolve.
	if ai_state == AIState.PASSIVE and is_on_floor() and velocity.length_squared() < 0.01:
		return

	move_and_slide()

	# Leap landing is detected here now, after the move has resolved.
	if movement_state == MovementState.LEAPING and is_on_floor() and velocity.y <= 0.0:
		movement_state = MovementState.NONE
		velocity = Vector3.ZERO
		roll_combat_action()


# ─────────────────────────────────────────────
# LOS CACHE
# ─────────────────────────────────────────────
func _tick_los(delta: float) -> void:
	_los_check_timer -= delta
	if _los_check_timer > 0.0:
		return
	_los_check_timer = LOS_CHECK_INTERVAL

	var had_los = _has_los
	if combat_target == null or not combat_target.alive:
		_has_los = false
	else:
		_has_los = is_path_clear(
			global_position + Vector3.UP * 0.8,
			combat_target.global_position,
			combat_target)
		# Remember where they were the moment we lost sight of them.
		# This is what SEARCH now runs on.
		if had_los and not _has_los:
			_remember_last_seen(combat_target.global_position)

func _remember_last_seen(pos: Vector3) -> void:
	last_seen_point.append(pos)
	if last_seen_point.size() > 4:
		last_seen_point.remove_at(0)


# ─────────────────────────────────────────────
# PASSIVE MODE
# ─────────────────────────────────────────────
func enter_passive_mode():
	if ai_state == AIState.PASSIVE:
		return
	if always_active:
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
	# Re-issue movement if we had an active target before going passive
	if movement_target != Vector3.ZERO:
		move_to(movement_target)


# ─────────────────────────────────────────────
# TIME PASSING
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
			# Track time without LOS — if too long, seek a new position.
			# Uses the cached LOS result now instead of its own raycast.
			if combat_target != null and combat_target.alive:
				if not _has_los:
					_no_los_timer += delta
					if _no_los_timer >= NO_LOS_PATIENCE:
						_no_los_timer = 0.0
						_seek_los_position()
				else:
					_no_los_timer = 0.0
		AIState.PATROL:
			patrol_time += delta
			if patrol_time >= patrol_recon_time:
				reconsider_patrol()
		AIState.IDLE:
			idle_time += delta
			if idle_time >= _next_wander_at:
				idle_time = 0.0
				_next_wander_at = wander_delay + randf_range(0.0, float(idle_to_wander))
				_wander()
		AIState.SEARCH:
			search_time += delta
			_tick_search(delta)
			if search_time >= search_duration:
				_end_search()

	if targeting_time >= targeting_recon_time:
		reconsider_target()

	if ai_state == AIState.COMBAT and not equipment_slots.is_empty():
		_tick_equipment(delta)



# ─────────────────────────────────────────────
# GRAVITY / MOVEMENT
# ─────────────────────────────────────────────
func handle_gravity(delta: float) -> void:
	if is_on_floor():
		# Zero out accumulated fall speed instead of letting it grow.
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

func handle_movement(delta):
	match movement_state:
		MovementState.NONE:
			# Decelerate through the same curve as acceleration rather than
			# snapping to zero. Instant stops are most of the "mechanical" read.
			var t = 1.0 - exp(-acceleration * delta)
			velocity.x = lerp(velocity.x, 0.0, t)
			velocity.z = lerp(velocity.z, 0.0, t)
			_stuck_timer = 0.0
			_stuck_retry_count = 0
		MovementState.MOVING:
			if nav_agent.is_navigation_finished():
				var dist_to_target = global_position.distance_to(movement_target)
				if dist_to_target < 2.0:
					# Actually arrived — normal completion
					reconsider_movement()
					_stuck_timer = 0.0
					_stuck_retry_count = 0
				else:
					# Nav says done but we're NOT there — path is blocked
					var t = 1.0 - exp(-acceleration * delta)
					velocity.x = lerp(velocity.x, 0.0, t)
					velocity.z = lerp(velocity.z, 0.0, t)
					_handle_path_blocked()
			else:
				move_along_nav(delta)
				_check_stuck(delta)
		MovementState.LEAPING:
			pass  # ballistic — gravity and landing handled in _apply_motion
		MovementState.CHASING:
			handle_chasing(delta)

func _check_stuck(delta: float) -> void:
	_stuck_timer += delta
	if _stuck_timer < STUCK_CHECK_INTERVAL:
		return
	_stuck_timer = 0.0
	var moved = global_position.distance_to(_stuck_last_position)
	_stuck_last_position = global_position
	if moved > STUCK_MOVE_THRESHOLD:
		_stuck_retry_count = 0
		return
	# Still here — hand off to path blocked handler
	velocity.x = 0
	velocity.z = 0
	_handle_path_blocked()

func move_to(pos: Vector3):
	nav_agent.set_target_position(pos)
	movement_target = pos
	movement_state = MovementState.MOVING
	movement_time = 0
	_stuck_timer = 0.0
	_stuck_last_position = global_position
	_stuck_retry_count = 0

func move_along_nav(delta):
	var path_dir = nav_agent.get_next_path_position() - global_position
	path_dir.y = 0
	var t = 1.0 - exp(-acceleration * delta)
	if path_dir.length() < 0.15:
		velocity.x = lerp(velocity.x, 0.0, t)
		velocity.z = lerp(velocity.z, 0.0, t)
		return
	var base_dir = path_dir.normalized()
	_last_move_dir = base_dir
	var target_velocity = base_dir * move_speed
	velocity.x = lerp(velocity.x, target_velocity.x, t)
	velocity.z = lerp(velocity.z, target_velocity.z, t)
	# NOTE: rotation is no longer set here. Facing is decoupled from
	# movement so the body can strafe and backpedal while aiming.

func handle_chasing(delta):
	if combat_target == null or not combat_target.alive:
		movement_state = MovementState.NONE
		return

	# Stop chasing once we're close enough to engage from here
	var dist_to_target = global_position.distance_to(combat_target.global_position)
	if dist_to_target <= _max_range() * 0.7:
		movement_state = MovementState.NONE
		return

	chasing_time += delta
	if chasing_time >= chasing_recon_time:
		chasing_time = 0
		nav_agent.set_target_position(combat_target.global_position)

	move_along_nav(delta)
	_check_stuck(delta)

func _update_facing(delta: float) -> void:
	# The core fix for "faces where it walks while shooting sideways".
	# In combat the body tracks the target; movement direction is
	# independent, which gives strafing and backpedalling for free.
	var face_dir := Vector3.ZERO
	if ai_state == AIState.COMBAT and combat_target != null and combat_target.alive:
		face_dir = combat_target.global_position - global_position
	elif weapon_target != Vector3.ZERO and ai_state == AIState.COMBAT:
		face_dir = weapon_target - global_position
	elif look_target != Vector3.ZERO and global_position.distance_squared_to(look_target) > 0.04:
		face_dir = look_target - global_position
	elif _last_move_dir.length_squared() > 0.0001:
		face_dir = _last_move_dir

	face_dir.y = 0.0
	if face_dir.length_squared() < 0.0001:
		return
	face_dir = face_dir.normalized()
	var target_yaw = atan2(-face_dir.x, -face_dir.z)
	var t = 1.0 - exp(-rotation_speed * delta)
	rotation.y = lerp_angle(rotation.y, target_yaw, t)

func _is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length() > 0.6


# ─────────────────────────────────────────────
# WEAPON LOGIC
# Now aware of magazines, reloads, sight-picture settling and
# committed bursts.
# ─────────────────────────────────────────────
func handle_weapon_logic(delta):
	if fire_time > 0.0:
		fire_time -= delta
	if weapon == null:
		return
	if ai_state != AIState.COMBAT:
		weapon_state = WeaponState.IDLE
		_aim_tracking = 0.0
		_burst_left = 0
		return

	# Reload is now a real state the AI reacts to, rather than the weapon
	# silently refusing to fire while the AI kept cycling FIRE.
	if weapon.is_reloading:
		weapon_state = WeaponState.RELOAD
		_aim_tracking = 0.0
		_burst_left = 0
		return
	if weapon.needs_reload():
		weapon.start_reload()
		_on_reload_started()
		return

	# Tracking builds while settled with LOS, decays while moving.
	if _has_los and combat_target != null:
		if _is_moving():
			_aim_tracking = maxf(0.0, _aim_tracking - delta * 1.5)
		else:
			_aim_tracking = minf(aim_settle_time, _aim_tracking + delta)
	else:
		_aim_tracking = maxf(0.0, _aim_tracking - delta * 2.0)

	if weapon_time >= weapon_recon_time:
		reconsider_weapon()

	var dist = global_position.distance_to(weapon_target)
	var max_range = _max_range()
	var min_range = weapon.min_effective_range

	match weapon_state:
		WeaponState.IDLE, WeaponState.RELOAD:
			weapon_state = WeaponState.AIM
		WeaponState.AIM:
			if fire_time > 0.0:
				return
			if combat_target == null:
				return
			if not _has_los and not _can_fire_without_los():
				return
			if dist > max_range or dist < min_range:
				return
			# A committed burst fires immediately. Otherwise wait for a
			# sight picture proportional to range — snap shots up close,
			# a real pause before a long shot.
			if _burst_left <= 0 and _aim_tracking < _prefire_threshold():
				return
			weapon_state = WeaponState.FIRE
		WeaponState.FIRE:
			if fire_time <= 0.0:
				fire()
				fire_time = weapon.fire_cooldown
				if _burst_left > 0:
					_burst_left -= 1
				weapon_state = WeaponState.AIM

func _prefire_threshold() -> float:
	if weapon == null:
		return 0.0
	var d = global_position.distance_to(weapon_target)
	var ratio = clampf(d / maxf(_max_range(), 0.01), 0.0, 1.0)
	return aim_settle_time * ratio * 0.8

## Overridden by Soldier so a SUPPRESSING soldier can put rounds onto a
## position it can't currently see.
func _can_fire_without_los() -> bool:
	return false

func _max_range() -> float:
	return weapon.max_effective_range if weapon != null else 30.0

func _on_reload_started() -> void:
	# Break contact while vulnerable rather than standing in the open.
	weapon_state = WeaponState.RELOAD
	_burst_left = 0
	_aim_tracking = 0.0
	if MovementOptions.FALLBACK in AllowedMovementOptions:
		move_to(find_fallback_target())
	elif MovementOptions.REPOSITION in AllowedMovementOptions:
		move_to(find_reposition_target())

func _on_reload_finished() -> void:
	if ai_state == AIState.COMBAT:
		weapon_state = WeaponState.AIM


# ─────────────────────────────────────────────
# RECONSIDER — weighted, context-driven
# ─────────────────────────────────────────────
func roll_combat_action():
	if AllowedCombatOptions.is_empty():
		return

	var weights: Dictionary = {}
	var total: float = 0.0
	for opt in AllowedCombatOptions:
		var w: float = maxf(_score_combat_option(opt), 0.0)
		if opt == previous_combat_option:
			w *= repeat_penalty
		weights[opt] = w
		total += w

	var chosen = AllowedCombatOptions[randi() % AllowedCombatOptions.size()]
	if total > 0.0:
		var roll = randf() * total
		for opt in AllowedCombatOptions:
			roll -= weights[opt]
			if roll <= 0.0:
				chosen = opt
				break

	perform_action(chosen)
	previous_combat_option = chosen

## Score, don't shuffle. The old version erased the previous option, which
## structurally forced move/stand/move/stand on a fixed timer.
func _score_combat_option(option: int) -> float:
	var max_range = _max_range()
	var dist = max_range
	if combat_target != null:
		dist = global_position.distance_to(combat_target.global_position)
	var range_ratio = clampf(dist / maxf(max_range, 0.01), 0.0, 2.0)
	var health_ratio = float(health) / maxf(float(max_health), 1.0)
	var pinned = signal_integrity < SIGNAL_FUZZED
	var low_ammo = false
	if weapon != null and not weapon.infinite_ammo:
		low_ammo = float(weapon.magazine_current) / maxf(float(weapon.magazine_size), 1.0) < 0.25

	var w: float = 1.0
	match option:
		CombatOptions.MOVE:
			w += range_ratio * 2.5             # far → close the distance
			if not _has_los:
				w += 3.0                       # blocked → moving is the only fix
			if range_ratio < 0.25:
				w += 1.0                       # crowding → open the range
			if health_ratio < 0.4:
				w += 0.8                       # hurt → don't stand still
			if pinned:
				w *= 0.5                       # under fire → less willing to move
		CombatOptions.AIM:
			if not _has_los:
				return 0.15                    # nothing to aim at
			w += 1.5
			w += range_ratio * 2.5             # long shots want a settled stance
			if low_ammo:
				w += 0.6                       # make the remaining rounds count
			if pinned:
				w *= 0.6
		CombatOptions.FIRE:
			if not _has_los and not _can_fire_without_los():
				return 0.1
			w += 2.5
			w += (1.0 - minf(range_ratio, 1.0)) * 2.0   # close range → just shoot
			if low_ammo:
				w *= 0.4
			if pinned:
				w += 0.8                       # return fire even while suppressed
	return w

func _pick_movement_option() -> int:
	if AllowedMovementOptions.is_empty():
		return -1
	var weights: Dictionary = {}
	var total: float = 0.0
	for m in AllowedMovementOptions:
		var w: float = maxf(_score_movement_option(m), 0.0)
		if m == previous_movement_option:
			w *= repeat_penalty
		weights[m] = w
		total += w
	if total <= 0.0:
		return AllowedMovementOptions[randi() % AllowedMovementOptions.size()]
	var roll = randf() * total
	for m in AllowedMovementOptions:
		roll -= weights[m]
		if roll <= 0.0:
			return m
	return AllowedMovementOptions[0]

func _score_movement_option(option: int) -> float:
	var max_range = _max_range()
	var dist = max_range
	if combat_target != null:
		dist = global_position.distance_to(combat_target.global_position)
	var range_ratio = clampf(dist / maxf(max_range, 0.01), 0.0, 2.0)
	var health_ratio = float(health) / maxf(float(max_health), 1.0)

	var w: float = 1.0
	match option:
		MovementOptions.ADVANCE:
			w = 0.4 + range_ratio * 3.0
			if range_ratio < 0.35:
				w *= 0.2
		MovementOptions.REPOSITION:
			w = 1.2
			if _has_los:
				w += 1.0                       # shuffle to break the firing solution
			else:
				w += 1.8                       # small step to try to open a lane
			if range_ratio > 1.0:
				w *= 0.5                       # too far for a 2m sidestep to matter
		MovementOptions.FALLBACK:
			w = 0.2
			if range_ratio < 0.3:
				w += 2.0                       # too close
			if health_ratio < 0.4:
				w += 1.5
			if weapon != null and weapon.is_reloading:
				w += 2.0
		MovementOptions.LEAP:
			if combat_target == null or not _has_los:
				return 0.0
			if range_ratio > 0.6 or range_ratio < 0.1:
				return 0.1
			w = 1.5
		MovementOptions.CHASE:
			w = 0.3 + range_ratio * 2.0
			if not _has_los:
				w += 1.5
			if range_ratio < 0.5:
				w *= 0.3
	return w

func _handle_path_blocked() -> void:
	_stuck_retry_count += 1

	var nav_map = nav_agent.get_navigation_map()

	if _stuck_retry_count == 1:
		# First block — try a lateral step to get around whatever is blocking
		var to_target = (movement_target - global_position).normalized()
		var right = to_target.cross(Vector3.UP).normalized()
		var lateral_dir = right if randf() > 0.5 else -right
		var step = global_position + lateral_dir * 3.0 + to_target * 1.5
		var nav_point = NavigationServer3D.map_get_closest_point(nav_map, step)
		nav_agent.set_target_position(nav_point)
		return

	if _stuck_retry_count == 2:
		# Second block — try the opposite lateral direction
		var to_target = (movement_target - global_position).normalized()
		var right = to_target.cross(Vector3.UP).normalized()
		var lateral_dir = -right if randf() > 0.5 else right
		var step = global_position + lateral_dir * 4.0
		var nav_point = NavigationServer3D.map_get_closest_point(nav_map, step)
		nav_agent.set_target_position(nav_point)
		return

	# Third block — path is genuinely impassable from here
	_stuck_retry_count = 0
	movement_state = MovementState.NONE
	if ai_state == AIState.COMBAT:
		# Stand and fight — roll a non-move combat action
		var options = AllowedCombatOptions.duplicate()
		options.erase(CombatOptions.MOVE)
		if not options.is_empty():
			perform_action(options[randi_range(0, options.size() - 1)])
	else:
		var random_offset = Vector3(randf_range(-5.0, 5.0), 0, randf_range(-5.0, 5.0))
		var fallback = NavigationServer3D.map_get_closest_point(nav_map, global_position + random_offset)
		move_to(fallback)

## One ring of 8 samples per call instead of 32 samples in a single frame.
## Successive calls widen the search; the angle offset is randomised so
## squadmates don't all test identical points.
func _seek_los_position() -> void:
	if combat_target == null:
		return
	var nav_map = nav_agent.get_navigation_map()
	var target_pos = combat_target.global_position
	var check_from_height = Vector3.UP * 0.8

	var radius = advance_distance * SEEK_RING_RADII[_seek_ring_index]
	_seek_ring_index = (_seek_ring_index + 1) % SEEK_RING_RADII.size()

	var best_pos: Vector3 = Vector3.ZERO
	var best_dist: float = INF
	var angle_offset = randf() * TAU

	for i in 8:
		var angle = angle_offset + (TAU / 8.0) * i
		var dir = Vector3(cos(angle), 0.0, sin(angle))
		var test = target_pos + dir * radius
		var nav_point = NavigationServer3D.map_get_closest_point(nav_map, test)
		if nav_point.distance_to(global_position) < 1.5:
			continue
		if is_path_clear(nav_point + check_from_height, target_pos, combat_target):
			var dist = global_position.distance_to(nav_point)
			if dist < best_dist:
				best_dist = dist
				best_pos = nav_point

	if best_pos != Vector3.ZERO:
		_seek_ring_index = 0
		move_to(best_pos)

func reconsider_movement():
	movement_time = 0
	match ai_state:
		AIState.COMBAT:
			roll_combat_action()
		AIState.PATROL:
			reconsider_patrol()
		_:
			movement_state = MovementState.NONE

func reconsider_weapon():
	weapon_time = 0
	if weapon == null:
		return
	# Top up out of contact rather than starting a fight on a half magazine.
	if not weapon.infinite_ammo and not weapon.is_reloading:
		var frac = float(weapon.magazine_current) / maxf(float(weapon.magazine_size), 1.0)
		if frac < 0.35 and (not _has_los or ai_state != AIState.COMBAT):
			weapon.start_reload()
			_on_reload_started()

func reconsider_combat():
	combat_time = 0
	roll_combat_action()

func reconsider_target() -> void:
	targeting_time = 0

	# Checked BEFORE the keep-current-target early return below. That return is
	# exactly what made a point-blank contact invisible — it fired whenever the
	# existing target was alive, without ever comparing distances.
	if _check_close_threat():
		return

	if combat_target != null and combat_target.alive:
		if _is_hostile(combat_target):
			weapon_target = combat_target.global_position
			look_target = combat_target.global_position
			return
	if combat_target != null and not combat_target.alive:
		_remember_last_seen(combat_target.global_position)
		combat_target = null
		weapon_target = Vector3.ZERO
		_has_los = false
		if movement_target != Vector3.ZERO:
			look_target = movement_target

		# Close threat is down — go back to whatever we were on rather than
		# re-picking nearest, which would lose a player-designated target.
		var resumed := _take_preempted_target()
		if resumed != null:
			change_combat_target(resumed)
			return

	var new_target: CharacterBody3D = _nearest_hostile()

	if new_target != null:
		if ai_state == AIState.COMBAT:
			change_combat_target(new_target)
		# Don't auto-trigger from IDLE/PATROL — let detection handle that
	else:
		combat_target = null
		weapon_target = Vector3.ZERO
		_has_los = false
		if movement_target != Vector3.ZERO:
			look_target = movement_target
		if ai_state == AIState.COMBAT:
			# Lost them — go look, rather than instantly forgetting.
			_enter_search()

# Extracted from reconsider_target so the close-threat check shares one source
# of truth for "who is hostile and nearby".
func _nearest_hostile() -> CharacterBody3D:
	if ai_manager != null:
		return ai_manager.get_nearest_hostile(self)
	if player != null and _is_hostile(player) and player.is_targetable():
		return player
	return null


func _take_preempted_target() -> CharacterBody3D:
	var t := _preempted_target
	_preempted_target = null
	if t == null or not is_instance_valid(t) or not t.alive:
		return null
	if not _is_hostile(t):
		return null
	return t


# Returns true if it took over targeting this tick.
func _check_close_threat() -> bool:
	if close_threat_range <= 0.0 or ai_state == AIState.DEAD:
		return false
	# Same sensor rule the detection area uses — a robot with a wrecked sensor
	# package doesn't get a free point-blank sense.
	var sig := get_signal_state()
	if sig == SignalState.EKILL or sig == SignalState.CRITICAL:
		return false

	var candidate := _nearest_hostile()
	if candidate == null or candidate == combat_target:
		return false

	var dist := global_position.distance_to(candidate.global_position)
	if dist > close_threat_range:
		return false

	var current_valid: bool = combat_target != null \
		and is_instance_valid(combat_target) \
		and combat_target.alive

	# Already fighting something at least as close? Leave it alone.
	if current_valid:
		var current_dist := global_position.distance_to(combat_target.global_position)
		if current_dist - dist < close_threat_advantage:
			return false

	if close_threat_requires_los:
		if not is_path_clear(global_position + Vector3.UP * 0.8, candidate.global_position, candidate):
			return false

	if current_valid:
		_preempted_target = combat_target

	if ai_state == AIState.COMBAT:
		change_combat_target(candidate)
	else:
		# Not fighting yet. This is the case the Area3D misses when the hostile
		# was already inside the radius before this robot became relevant —
		# body_entered never fires for an overlap that already existed.
		trigger_combat(candidate)

	close_threat_engaged.emit(candidate)
	return true


func reconsider_patrol():
	patrol_time = 0
	if patrol_path == null or patrol_path.points.is_empty():
		return
	if nav_agent.is_navigation_finished():
		var next_point = patrol_path.get_next_point(self)
		if next_point:
			move_to(next_point.global_position)
			look_target = next_point.global_position


# ─────────────────────────────────────────────
# SEARCH
# Previously a declared-but-unreachable state.
# ─────────────────────────────────────────────
func _enter_search() -> void:
	if last_seen_point.is_empty():
		change_ai_state(AIState.PATROL)
		return
	change_ai_state(AIState.SEARCH)
	search_time = 0.0
	_search_look_timer = 0.0
	move_to(last_seen_point.back())
	look_target = last_seen_point.back()

func _tick_search(delta: float) -> void:
	if movement_state != MovementState.NONE:
		return
	_search_look_timer -= delta
	if _search_look_timer > 0.0:
		return
	_search_look_timer = search_look_interval * randf_range(0.7, 1.4)

	# Sweep a random heading, and sometimes push to a new vantage point.
	var a = randf() * TAU
	look_target = global_position + Vector3(cos(a), 0.0, sin(a)) * 6.0
	if randf() < 0.45:
		var nav_map = nav_agent.get_navigation_map()
		var offset = Vector3(randf_range(-7.0, 7.0), 0.0, randf_range(-7.0, 7.0))
		move_to(NavigationServer3D.map_get_closest_point(nav_map, global_position + offset))

func _end_search() -> void:
	search_time = 0.0
	last_seen_point.clear()
	if patrol_path != null and not patrol_path.points.is_empty():
		change_ai_state(AIState.PATROL)
	else:
		change_ai_state(AIState.IDLE)


# ─────────────────────────────────────────────
# IDLE WANDER
# Previously four declared variables and no implementation.
# ─────────────────────────────────────────────
func _wander() -> void:
	if movement_state != MovementState.NONE:
		return
	var nav_map = nav_agent.get_navigation_map()
	var a = randf() * TAU
	var r = randf_range(wander_radius * 0.4, wander_radius)
	var pt = NavigationServer3D.map_get_closest_point(
		nav_map, global_position + Vector3(cos(a), 0.0, sin(a)) * r)
	move_to(pt)
	look_target = pt


# ─────────────────────────────────────────────
# EQUIPMENT
# ─────────────────────────────────────────────
func _tick_equipment(delta: float) -> void:
	for i in _equipment_cooldowns.keys():
		_equipment_cooldowns[i] = maxf(0.0, _equipment_cooldowns[i] - delta)
	if combat_target != null and combat_target.alive:
		var target_pos = combat_target.global_position
		if target_pos.distance_to(_target_last_position) < 0.5:
			_target_stationary_time += delta
		else:
			_target_stationary_time = 0.0
			_target_last_position = target_pos
	_equipment_recon_timer += delta
	if _equipment_recon_timer < EQUIPMENT_RECON_TIME:
		return
	_equipment_recon_timer = 0.0
	_evaluate_equipment_use()

func _evaluate_equipment_use() -> void:
	if combat_target == null:
		return
	var context = AIEquipment.EquipmentContext.new()
	context.owner_ai = self
	context.combat_target = combat_target
	context.target_position = combat_target.global_position
	context.time_since_target_moved = _target_stationary_time
	context.owner_is_reloading = weapon != null and weapon.is_reloading
	context.nearby_hostiles = []
	if ai_manager != null:
		context.nearby_hostiles = ai_manager.get_hostiles_in_radius(self, 5.0)
	for i in equipment_slots.size():
		var slot: AIEquipmentSlot = equipment_slots[i]
		if not slot.has_uses():
			continue
		if _equipment_cooldowns.get(i, 0.0) > 0.0:
			continue
		if slot.equipment_scene == null:
			continue
		var equipment = slot.equipment_scene.instantiate() as AIEquipment
		if equipment == null:
			continue
		if equipment.can_use(context):
			get_tree().current_scene.add_child(equipment)
			equipment.execute(context)
			slot.consume()
			_equipment_cooldowns[i] = equipment.cooldown
			if equipment.is_inside_tree():
				equipment.queue_free()
			return
		else:
			equipment.free()

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
		_no_los_timer = 0.0

func change_combat_target(body):
	if body != combat_target:
		_aim_tracking = 0.0
		_burst_left = 0
		_has_los = false
		_los_check_timer = 0.0
	combat_target = body
	weapon_target = body.global_position
	look_target = body.global_position


# ─────────────────────────────────────────────
# ACTIONS / MOVEMENT FINDERS
# ─────────────────────────────────────────────
func perform_action(action: CombatOptions):
	match action:
		CombatOptions.MOVE:
			var movement = _pick_movement_option()
			if movement < 0:
				return
			previous_movement_option = movement
			match movement:
				MovementOptions.LEAP:
					if combat_target != null:
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
			_commit_burst()
		CombatOptions.AIM:
			_enter_aim_stance()

## AIM used to be `pass`. It now means: stop, settle, let accuracy build.
func _enter_aim_stance() -> void:
	if movement_state == MovementState.MOVING or movement_state == MovementState.CHASING:
		movement_state = MovementState.NONE
	_burst_left = 0

## FIRE used to be `pass`. It now means: commit to a burst from wherever
## you are — if you were moving, keep moving and eat the accuracy penalty.
func _commit_burst() -> void:
	_burst_left = randi_range(burst_min, max(burst_min, burst_max))

func find_reposition_target():
	if combat_target == null:
		return global_position
	var nav_map = nav_agent.get_navigation_map()
	var to_target = (combat_target.global_position - global_position).normalized()
	var right = to_target.cross(Vector3.UP).normalized()
	var lateral_dir = right if randf() > 0.5 else -right
	for mult in [1.0, 0.5]:
		var test_pos = global_position + lateral_dir * reposition_distance * mult
		var closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
		if is_path_clear(closest_point + Vector3.UP * 0.8, combat_target.global_position, combat_target):
			return closest_point
	return global_position

## Step length now scales with range: long bounds when far, short careful
## steps when close, and it won't step inside a crowding distance.
func find_advance_target():
	if combat_target == null:
		return global_position
	var nav_map = nav_agent.get_navigation_map()
	var to_target = combat_target.global_position - global_position
	to_target.y = 0.0
	var dist = to_target.length()
	if dist < 0.01:
		return global_position
	var direction = to_target / dist
	var max_range = _max_range()

	var step = advance_distance * clampf(dist / maxf(max_range, 0.01), 0.4, 3.0)
	step = minf(step, dist - max_range * 0.35)   # don't crowd the target
	if step <= 0.2:
		return global_position

	for mult in [1.0, 0.6, 0.3]:
		var test_pos = global_position + direction * step * mult
		var closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
		# Previously this checked test_pos but returned closest_point.
		if is_path_clear(closest_point + Vector3.UP * 0.8, combat_target.global_position, combat_target):
			return closest_point
	return global_position

func find_fallback_target():
	if combat_target == null:
		return global_position
	var nav_map = nav_agent.get_navigation_map()
	var away_dir = (global_position - combat_target.global_position).normalized()
	for mult in [1.0, 0.5]:
		var test_pos = global_position + away_dir * fallback_distance * mult
		var closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
		# Same copy-paste bug as find_advance_target had.
		if is_path_clear(closest_point + Vector3.UP * 0.8, combat_target.global_position, combat_target):
			return closest_point
	return global_position


# ─────────────────────────────────────────────
# LEAP
# ─────────────────────────────────────────────
func leap_towards(target_pos: Vector3, leap_vel: float = 16.5):
	movement_state = MovementState.LEAPING
	velocity = compute_leap_velocity_fixed_speed(target_pos, leap_vel)
	look_target = target_pos

func compute_leap_velocity(target: Vector3, time: float) -> Vector3:
	if time <= 0.0:
		return Vector3.ZERO
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
	if distance < 0.01:
		return Vector3.ZERO
	var time = distance / speed
	var direction = horiz.normalized()
	var vy = (displacement.y / time) + (0.5 * gravity * time)
	return Vector3(direction.x * speed, vy, direction.z * speed)


# ─────────────────────────────────────────────
# FIRE / DAMAGE / DEATH
# ─────────────────────────────────────────────
func fire():
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
	if bark != null:
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
	if damaged_by_player and player != null:
		player.add_bits(bits)
	if _collision_shape == null:
		_collision_shape = _find_collision_shape()
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", true)
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
	velocity = Vector3.ZERO
	weapon_target = Vector3.ZERO
	look_target = Vector3.ZERO
	combat_target = null
	show_body()
	if weapon != null:
		weapon.show()
	movement_state = MovementState.NONE
	weapon_state = WeaponState.IDLE
	movement_time = 0
	combat_time = 0
	weapon_time = 0
	targeting_time = 0
	fire_time = 0
	idle_time = 0
	search_time = 0
	wander_time = 0
	_stuck_timer = 0.0
	_stuck_last_position = Vector3.ZERO
	_stuck_retry_count = 0
	_no_los_timer = 0.0
	_has_los = false
	_los_check_timer = 0.0
	_aim_tracking = 0.0
	_burst_left = 0
	_last_move_dir = Vector3.ZERO
	_seek_ring_index = 0
	_search_look_timer = 0.0
	# Was never reset — squads set this true and nothing ever set it back,
	# so every squad member ran full physics forever.
	always_active = false
	signal_integrity = 1.0
	_signal_stutter_timer = 0.0
	_equipment_cooldowns.clear()
	_target_stationary_time = 0.0
	_target_last_position = Vector3.ZERO
	_equipment_recon_timer = 0.0
	for slot in equipment_slots:
		slot.initialize()
	set_physics_process(true)
	set_process(true)
	if _collision_shape == null:
		_collision_shape = _find_collision_shape()
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", false)


# ─────────────────────────────────────────────
# STIMULUS
# ─────────────────────────────────────────────
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
				_remember_last_seen(source_position)
		StimulusManager.StimulusType.ALLY_SHOT:
			if ai_state != AIState.COMBAT:
				look_target = source_position
				_remember_last_seen(source_position)
			if source_node != null and _is_hostile(source_node):
				if is_path_clear(global_position + Vector3.UP * 0.8, source_position, source_node):
					trigger_combat(source_node)
		StimulusManager.StimulusType.ALLY_DIED:
			if ai_state != AIState.COMBAT:
				look_target = source_position
				_remember_last_seen(source_position)
			if distance < StimulusManager.DEFAULT_RADIUS[type] * 0.5:
				if source_node != null and _is_hostile(source_node):
					if is_path_clear(global_position + Vector3.UP * 0.8, source_node.global_position, source_node):
						trigger_combat(source_node)
		StimulusManager.StimulusType.ENEMY_SPOTTED:
			if ai_state != AIState.COMBAT and ai_state != AIState.SEARCH:
				_remember_last_seen(source_position)
				if distance < 20.0:
					move_to(source_position)
				else:
					look_target = source_position


# ─────────────────────────────────────────────
# SIGNAL INTEGRITY
# ─────────────────────────────────────────────
func get_signal_state() -> SignalState:
	if signal_integrity <= SIGNAL_EKILL:
		return SignalState.EKILL
	elif signal_integrity <= SIGNAL_CRITICAL:
		return SignalState.CRITICAL
	elif signal_integrity <= SIGNAL_DEGRADED:
		return SignalState.DEGRADED
	elif signal_integrity <= SIGNAL_FUZZED:
		return SignalState.FUZZED
	return SignalState.CLEAN

# Called by near-miss suppression, EMP grenades, jamming, etc.
func receive_signal_damage(amount: float) -> void:
	var actual = amount / maxf(signal_resistance, 0.01)
	var before = signal_integrity
	signal_integrity = maxf(0.0, signal_integrity - actual)
	_on_signal_damaged(before, signal_integrity)
	if signal_integrity <= SIGNAL_EKILL:
		_enter_ekill()

## Hook for subclasses. Soldier uses this to enter SUPPRESSED.
func _on_signal_damaged(_before: float, _after: float) -> void:
	pass

func _enter_ekill() -> void:
	# Robot is electronically disabled — physically intact, non-functional.
	# Recovers automatically when signal_integrity rises above SIGNAL_EKILL.
	movement_state = MovementState.NONE
	velocity.x = 0
	velocity.z = 0
	weapon_state = WeaponState.IDLE
	_burst_left = 0
	_aim_tracking = 0.0

func _tick_signal(delta: float) -> void:
	# Passive signal recovery
	if signal_integrity < 1.0:
		signal_integrity = minf(1.0, signal_integrity + signal_recovery_rate * delta)

	# DEGRADED: movement hesitation — occasional stutter
	if get_signal_state() == SignalState.DEGRADED:
		_signal_stutter_timer += delta
		if _signal_stutter_timer >= SIGNAL_STUTTER_INTERVAL:
			_signal_stutter_timer = 0.0
			if randf() < 0.35:  # 35% chance to stutter each interval
				velocity.x = 0
				velocity.z = 0

func _can_receive_orders() -> bool:
	# CRITICAL or E-KILL: robot ignores squad orders
	var state = get_signal_state()
	return state != SignalState.CRITICAL and state != SignalState.EKILL

func get_effective_detection_radius() -> float:
	match get_signal_state():
		SignalState.FUZZED:    return detection_radius * 0.85
		SignalState.DEGRADED:  return detection_radius * 0.5
		SignalState.CRITICAL:  return detection_radius * 0.2
		SignalState.EKILL:     return 0.0
		_:                     return detection_radius

func get_faction():
	return faction

func _is_hostile(body: Node3D) -> bool:
	if body is Player:
		return Enums.are_hostile(faction, (body as Player).faction)
	if body is Enemy:
		return Enums.are_hostile(faction, (body as Enemy).faction)
	return false

## `exclude` in Godot 4 is Array[RID], not Array[Node]. The old version
## passed nodes, which meant the exclusion silently did nothing and rays
## could hit the caster's own capsule. Also no longer blanket-excludes the
## player when there's no combat target.
func is_path_clear(from: Vector3, to: Vector3, ignore: Node3D = null) -> bool:
	var space_state = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclusion: Array[RID] = [_self_rid]
	if ignore != null and ignore is CollisionObject3D:
		exclusion.append((ignore as CollisionObject3D).get_rid())
	query.exclude = exclusion
	return not space_state.intersect_ray(query)

func update_debug_label():
	var sig_str = SignalState.keys()[get_signal_state()]
	var faction_str = Enums.Factions.keys()[faction]
	label.text = "%s | %s\nHP: %d  Sig: %s\n%s" % [
		soldier_name,
		faction_str,
		health,
		sig_str,
		AIState.keys()[ai_state]
	]


func force_check_detection():
	if detection == null or detection.get_child_count() == 0:
		return
	var shape = detection.get_child(0).shape
	var space_state = get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = detection.global_transform
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var exclusion: Array[RID] = [_self_rid]
	query.exclude = exclusion
	var results = space_state.intersect_shape(query, 64)
	for result in results:
		var collider = result.collider
		if collider is Player or collider is Enemy:
			_on_detection_body_entered(collider)

func _on_detection_body_entered(body: Node3D) -> void:
	if ai_state == AIState.DEAD:
		return
	# E-KILL and CRITICAL: sensors too degraded to detect anything
	var sig_state = get_signal_state()
	if sig_state == SignalState.EKILL or sig_state == SignalState.CRITICAL:
		return
	if not (body is Player or body is Enemy):
		return
	if ai_state == AIState.COMBAT and combat_target == body:
		return
	if not _is_hostile(body):
		return
	# Detection used to be last-enterer-wins: anything walking into the radius
	# took the target, even from 40m away while something was shooting at us
	# from 3m. Nearest wins now, which is the same rule _check_close_threat uses.
	if ai_state == AIState.COMBAT and combat_target != null \
			and is_instance_valid(combat_target) and combat_target.alive:
		if global_position.distance_to(body.global_position) \
				>= global_position.distance_to(combat_target.global_position):
			return
	if sig_state != SignalState.CLEAN:
		var eff_range = get_effective_detection_radius()
		if global_position.distance_to(body.global_position) > eff_range:
			return
	if is_path_clear(global_position + Vector3.UP * 0.8, body.global_position, body):
		trigger_combat(body)
		if stimulus_manager != null:
			stimulus_manager.emit_stimulus(
				StimulusManager.StimulusType.ENEMY_SPOTTED,
				body.global_position, faction, body)
	else:
		# Spotted but no clear line. This used to assign combat_target directly,
		# which silently replaced whatever we were actually fighting with a body
		# behind a wall — without changing state, so nothing corrected it. Only
		# fill the slot when it's empty.
		checking_for_target = true
		if combat_target == null:
			combat_target = body

func _on_detection_body_exited(body: Node3D) -> void:
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


# ─────────────────────────────────────────────
# ACCURACY
# ─────────────────────────────────────────────
func get_inaccurate_target(target_pos: Vector3) -> Vector3:
	if weapon == null:
		return target_pos
	# Was measuring distance to weapon_target rather than the passed-in
	# position, which diverged whenever a subclass passed something else.
	var dist := global_position.distance_to(target_pos)

	var effective_skill = accuracy_skill * maxf(signal_integrity, 0.1)
	var spread_mrad = weapon.ai_spread_mrad / maxf(effective_skill, 0.01)
	spread_mrad *= get_aim_spread_multiplier()

	var spread_m = spread_mrad * dist / 1000.0

	return target_pos + Vector3(
		randf_range(-spread_m, spread_m),
		randf_range(-spread_m * 0.35, spread_m * 0.35),
		randf_range(-spread_m, spread_m)
	)

## Settled and stationary shoots tight. Snap-firing on the move is bad.
## This is what makes "stop and aim" vs "shoot while moving" a real choice
## rather than two labels for the same behaviour.
func get_aim_spread_multiplier() -> float:
	var mult := 1.0
	if aim_settle_time > 0.0:
		var t = clampf(_aim_tracking / aim_settle_time, 0.0, 1.0)
		mult = 1.0 / maxf(lerp(aim_floor, 1.0, t), 0.01)
	if _is_moving():
		mult *= moving_accuracy_penalty
	return mult
