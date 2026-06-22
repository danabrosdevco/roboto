extends Enemy
class_name Soldier

# ─────────────────────────────────────────────
# SOLDIER STATE
# Extends Enemy's AIState with infantry-specific states.
# Enemy handles: COMBAT, PATROL, SEARCH, IDLE, DEAD, PASSIVE
# Soldier adds:  SUPPRESSING, COVER_SEEKING, BOUNDING, SUPPRESSED
# ─────────────────────────────────────────────

enum SoldierState {
	NONE,
	SUPPRESSING,   # Laying fire on a position to cover a squadmate's movement
	COVER_SEEKING, # Moving to a cover point before engaging
	BOUNDING,      # Moving while a partner suppresses; alternates with SUPPRESSING
	SUPPRESSED     # Taking fire, conservatively returning fire from current position
}

var soldier_state: SoldierState = SoldierState.NONE

# ─────────────────────────────────────────────
# COVER
# ─────────────────────────────────────────────
var current_cover_point: CoverPoint = null
var at_cover: bool = false

# How close the soldier needs to be to a cover point to consider itself "at cover"
@export var cover_arrival_threshold: float = 1.0
# How far away to search for cover points
@export var cover_search_radius: float = 20.0

# ─────────────────────────────────────────────
# SUPPRESSION
# ─────────────────────────────────────────────
# How long this soldier stays in SUPPRESSING before reconsidering
@export var suppress_duration: float = 3.0
var suppress_timer: float = 0.0

# How long this soldier stays SUPPRESSED before reconsidering
@export var suppressed_duration: float = 2.5
var suppressed_timer: float = 0.0

# Accuracy penalty while suppressed (multiplied against base accuracy)
@export var suppressed_accuracy_penalty: float = 0.4

# ─────────────────────────────────────────────
# BOUNDING
# ─────────────────────────────────────────────
# Set by Squad — the bound partner this soldier alternates with
var bound_partner: Soldier = null
# True when it's this soldier's turn to move
var is_my_bound_turn: bool = false

# ─────────────────────────────────────────────
# SQUAD ROLE
# Set externally by Squad
# ─────────────────────────────────────────────
enum SoldierRole { NONE, SUPPRESSOR, ADVANCER, FLANKER, FALLBACK, OVERWATCH }
var squad_role: SoldierRole = SoldierRole.NONE

# ─────────────────────────────────────────────
# SIGNALS
# ─────────────────────────────────────────────
signal reached_cover(soldier: Soldier)
signal suppressing_started(soldier: Soldier)
signal suppressed_started(soldier: Soldier)
signal bound_step_complete(soldier: Soldier)


# ─────────────────────────────────────────────
# OVERRIDE: _physics_process
# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	# Let Enemy handle gravity, passivity, targeting, weapon logic, debug label
	super(delta)

	# Soldier-specific state tick (only when alive and active)
	if frame_waited == false or ai_state == AIState.DEAD or ai_state == AIState.PASSIVE:
		return
	if player == null:
		return

	handle_soldier_state(delta)


# ─────────────────────────────────────────────
# SOLDIER STATE HANDLER
# ─────────────────────────────────────────────
func handle_soldier_state(delta: float) -> void:
	match soldier_state:
		SoldierState.COVER_SEEKING:
			tick_cover_seeking()

		SoldierState.SUPPRESSING:
			tick_suppressing(delta)

		SoldierState.SUPPRESSED:
			tick_suppressed(delta)

		SoldierState.BOUNDING:
			tick_bounding()

		SoldierState.NONE:
			pass


# ─────────────────────────────────────────────
# COVER SEEKING
# ─────────────────────────────────────────────
func enter_cover_seeking() -> void:
	if current_cover_point == null:
		current_cover_point = find_best_cover_point()

	if current_cover_point == null:
		# No cover available — fall back to base Enemy COMBAT behavior
		change_soldier_state(SoldierState.NONE)
		return

	change_soldier_state(SoldierState.COVER_SEEKING)
	move_to(current_cover_point.global_position)

func tick_cover_seeking() -> void:
	if current_cover_point == null:
		change_soldier_state(SoldierState.NONE)
		return

	var dist = global_position.distance_to(current_cover_point.global_position)
	if dist <= cover_arrival_threshold:
		at_cover = true
		current_cover_point.mark_occupied(self)
		change_soldier_state(SoldierState.NONE)
		reached_cover.emit(self)
		# Now that we're at cover, fight from here
		change_ai_state(AIState.COMBAT)

func find_best_cover_point() -> CoverPoint:
	var cover_points = get_tree().get_nodes_in_group("cover_points")
	var best: CoverPoint = null
	var best_score: float = -INF

	for cp in cover_points:
		if cp is not CoverPoint:
			continue
		if cp.is_occupied():
			continue

		var dist_to_self = global_position.distance_to(cp.global_position)
		if dist_to_self > cover_search_radius:
			continue

		# Score: closer to me is better, more cover from enemy direction is better
		var score = -dist_to_self
		if combat_target != null:
			# Prefer cover that breaks LOS to target
			if not cp.has_los_to(combat_target.global_position):
				score += 10.0

		if score > best_score:
			best_score = score
			best = cp

	return best

func release_cover() -> void:
	if current_cover_point != null:
		current_cover_point.mark_unoccupied(self)
	current_cover_point = null
	at_cover = false


# ─────────────────────────────────────────────
# SUPPRESSING
# Lay continuous fire on a position to pin enemies / cover squadmate movement.
# ─────────────────────────────────────────────
func enter_suppressing(target_position: Vector3 = Vector3.ZERO) -> void:
	change_soldier_state(SoldierState.SUPPRESSING)
	suppress_timer = 0.0
	# Keep the soldier stationary while suppressing
	movement_state = MovementState.NONE
	velocity.x = 0
	velocity.z = 0
	# Aim at the suppression target (defaults to current combat target position)
	if target_position != Vector3.ZERO:
		weapon_target = target_position
		look_target = target_position
	elif combat_target != null:
		weapon_target = combat_target.global_position
		look_target = combat_target.global_position
	suppressing_started.emit(self)

func tick_suppressing(delta: float) -> void:
	suppress_timer += delta
	# Weapon logic is still handled by Enemy — just keep firing
	# After duration, return control to squad
	if suppress_timer >= suppress_duration:
		change_soldier_state(SoldierState.NONE)
		bound_step_complete.emit(self)


# ─────────────────────────────────────────────
# SUPPRESSED
# Taking fire. Stay put, fire back conservatively with reduced accuracy.
# ─────────────────────────────────────────────
func enter_suppressed() -> void:
	change_soldier_state(SoldierState.SUPPRESSED)
	suppressed_timer = 0.0
	# Pin in place
	movement_state = MovementState.NONE
	velocity.x = 0
	velocity.z = 0
	suppressed_started.emit(self)

func tick_suppressed(delta: float) -> void:
	suppressed_timer += delta
	# Soldier still fires back, but accuracy is penalised.
	# We temporarily reduce max_accuracy during this state.
	# Weapon logic in Enemy handles the actual firing.
	if suppressed_timer >= suppressed_duration:
		change_soldier_state(SoldierState.NONE)


# ─────────────────────────────────────────────
# BOUNDING
# Move while bound_partner suppresses. On arrival, signal Squad to swap.
# ─────────────────────────────────────────────
func enter_bounding(target_pos: Vector3) -> void:
	change_soldier_state(SoldierState.BOUNDING)
	move_to(target_pos)

func tick_bounding() -> void:
	if nav_agent.is_navigation_finished():
		change_soldier_state(SoldierState.NONE)
		bound_step_complete.emit(self)


# ─────────────────────────────────────────────
# OVERRIDE: get_inaccurate_target
# Apply suppressed accuracy penalty when suppressed.
# ─────────────────────────────────────────────
func get_inaccurate_target(target_pos: Vector3) -> Vector3:
	if soldier_state == SoldierState.SUPPRESSED:
		var dist := global_position.distance_to(weapon_target)
		var penalised_accuracy = clamp(min_accuracy * suppressed_accuracy_penalty, 0.0, 1.0)
		return target_pos + get_random_spread(dist, penalised_accuracy)
	return super(target_pos)


# ─────────────────────────────────────────────
# OVERRIDE: trigger_combat
# On entering combat, seek cover first if unengaged.
# ─────────────────────────────────────────────
func trigger_combat(body: AI) -> void:
	super(body)
	# If not already in a soldier state, proactively seek cover on first contact
	if soldier_state == SoldierState.NONE and not at_cover:
		enter_cover_seeking()


# ─────────────────────────────────────────────
# ROLE ASSIGNMENT (called by Squad)
# ─────────────────────────────────────────────
func assign_role(role: SoldierRole) -> void:
	squad_role = role
	match role:
		SoldierRole.SUPPRESSOR:
			enter_suppressing()
		SoldierRole.ADVANCER:
			if combat_target != null:
				var advance_pos = find_advance_target()
				enter_bounding(advance_pos)
		SoldierRole.FLANKER:
			if combat_target != null:
				var flank_pos = find_flank_target()
				enter_bounding(flank_pos)
		SoldierRole.FALLBACK:
			var fallback_pos = find_fallback_target()
			move_to(fallback_pos)
		SoldierRole.OVERWATCH:
			movement_state = MovementState.NONE
			velocity.x = 0
			velocity.z = 0
		SoldierRole.NONE:
			change_soldier_state(SoldierState.NONE)


# ─────────────────────────────────────────────
# FLANK TARGET
# Find a position to the side of the enemy, out of their forward arc.
# ─────────────────────────────────────────────
func find_flank_target() -> Vector3:
	if combat_target == null:
		return global_position
	var nav_map = nav_agent.get_navigation_map()
	var to_target = (combat_target.global_position - global_position).normalized()
	var right = to_target.cross(Vector3.UP).normalized()
	# Pick left or right flank based on squad position to avoid clustering
	var flank_dir = right if randf() > 0.5 else -right
	var flank_dist = reposition_distance * 3.0
	var test_pos = combat_target.global_position + flank_dir * flank_dist
	var closest = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
	return closest


# ─────────────────────────────────────────────
# STATE CHANGE
# ─────────────────────────────────────────────
func change_soldier_state(new_state: SoldierState) -> void:
	if soldier_state == new_state:
		return
	soldier_state = new_state
	suppress_timer = 0.0
	suppressed_timer = 0.0


# ─────────────────────────────────────────────
# OVERRIDE: die
# Release cover point on death.
# ─────────────────────────────────────────────
func die() -> void:
	release_cover()
	super()


# ─────────────────────────────────────────────
# OVERRIDE: reset
# ─────────────────────────────────────────────
func reset() -> void:
	release_cover()
	soldier_state = SoldierState.NONE
	squad_role = SoldierRole.NONE
	bound_partner = null
	is_my_bound_turn = false
	suppress_timer = 0.0
	suppressed_timer = 0.0
	super()


# ─────────────────────────────────────────────
# DEBUG LABEL OVERRIDE
# ─────────────────────────────────────────────
func update_debug_label() -> void:
	super()
	if label != null:
		var soldier_str = SoldierState.keys()[soldier_state]
		var role_str = SoldierRole.keys()[squad_role]
		label.text += "\nSoldier: %s\nRole: %s" % [soldier_str, role_str]
