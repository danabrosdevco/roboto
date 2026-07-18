extends Enemy
class_name Soldier

# ─────────────────────────────────────────────
# SOLDIER
# Extends Enemy with smart infantry behaviors.
#
# Responsibility split:
#   Enemy  — physics, nav, weapons, gravity, detection, timers
#   Soldier — WHAT to do in combat (cover, suppress, bound)
#             and HOW to respond to squad orders
#
# Key design: reconsider_combat() is overridden to block
# Enemy's random action rolling while a soldier state is
# active. This lets cover-seeking / bounding / suppressing
# complete uninterrupted.
# ─────────────────────────────────────────────

enum SoldierState {
	NONE,
	SUPPRESSING,   # Stationary, laying fire to cover a squadmate's movement
	COVER_SEEKING, # Moving to a cover point before engaging
	BOUNDING,      # Moving toward objective/target while partner suppresses
	SUPPRESSED     # Pinned, returning fire conservatively
}
enum SoldierRole { NONE, SUPPRESSOR, ADVANCER, FLANKER, FALLBACK, OVERWATCH }

var soldier_state: SoldierState = SoldierState.NONE
var squad_role: SoldierRole = SoldierRole.NONE

# Reference back to the squad — set by Squad on registration
var squad: Squad = null

# When true: soldier holds position near objective, does not advance
# or chase, fires from cover only. Set by Squad on DEFEND objective.
var defensive_mode: bool = false

# ── Cover ──
var current_cover_point: CoverPoint = null
var at_cover: bool = false
@export var cover_arrival_threshold: float = 1.2
@export var cover_search_radius: float = 25.0

# ── Suppression ──
@export var suppress_duration: float = 3.0
var suppress_timer: float = 0.0
@export var suppressed_duration: float = 2.5
var suppressed_timer: float = 0.0
@export var suppressed_accuracy_penalty: float = 0.4

# ── Bounding ──
var bound_partner: Soldier = null

# ── Signals ──
signal reached_cover(soldier: Soldier)
signal suppressing_started(soldier: Soldier)
signal suppressed_started(soldier: Soldier)
signal bound_step_complete(soldier: Soldier)


# ─────────────────────────────────────────────
# OVERRIDE: reconsider_combat
# Blocks Enemy's random action rolling while a
# soldier state is active. This is the core fix.
# ─────────────────────────────────────────────
func reconsider_combat() -> void:
	if soldier_state != SoldierState.NONE:
		combat_time = 0
		return
	super()


# ─────────────────────────────────────────────
# OVERRIDE: _physics_process
# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	super(delta)
	if not frame_waited or ai_state == AIState.DEAD or ai_state == AIState.PASSIVE:
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
	var cp = find_best_cover_point()
	if cp == null:
		change_soldier_state(SoldierState.NONE)
		return
	current_cover_point = cp
	change_soldier_state(SoldierState.COVER_SEEKING)
	move_to(current_cover_point.global_position)

func tick_cover_seeking() -> void:
	if current_cover_point == null:
		change_soldier_state(SoldierState.NONE)
		return
	if nav_agent.is_target_reached():
		at_cover = true
		current_cover_point.mark_occupied(self)
		change_soldier_state(SoldierState.NONE)
		reached_cover.emit(self)

func find_best_cover_point() -> CoverPoint:
	var cover_points = get_tree().get_nodes_in_group("cover_points")
	var best: CoverPoint = null
	var best_score: float = -INF
	var target_pos = combat_target.global_position if combat_target else global_position

	for cp in cover_points:
		if not cp is CoverPoint or cp.is_occupied():
			continue
		if global_position.distance_to(cp.global_position) > cover_search_radius:
			continue
		var score = cp.score_for(global_position, target_pos)
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
# ─────────────────────────────────────────────
func enter_suppressing(target_position: Vector3 = Vector3.ZERO) -> void:
	change_soldier_state(SoldierState.SUPPRESSING)
	suppress_timer = 0.0
	movement_state = MovementState.NONE
	velocity.x = 0
	velocity.z = 0
	if target_position != Vector3.ZERO:
		weapon_target = target_position
		look_target = target_position
	elif combat_target != null:
		weapon_target = combat_target.global_position
		look_target = combat_target.global_position
	suppressing_started.emit(self)

func tick_suppressing(delta: float) -> void:
	suppress_timer += delta
	# Keep weapon target fresh as enemy moves
	if combat_target != null:
		weapon_target = combat_target.global_position
		look_target = combat_target.global_position
	if suppress_timer >= suppress_duration:
		change_soldier_state(SoldierState.NONE)
		bound_step_complete.emit(self)


# ─────────────────────────────────────────────
# SUPPRESSED
# ─────────────────────────────────────────────
func enter_suppressed() -> void:
	change_soldier_state(SoldierState.SUPPRESSED)
	suppressed_timer = 0.0
	movement_state = MovementState.NONE
	velocity.x = 0
	velocity.z = 0
	suppressed_started.emit(self)

func tick_suppressed(delta: float) -> void:
	suppressed_timer += delta
	if suppressed_timer >= suppressed_duration:
		change_soldier_state(SoldierState.NONE)


# ─────────────────────────────────────────────
# BOUNDING
# Move to a position while partner suppresses.
# On arrival, signal Squad to swap roles.
# ─────────────────────────────────────────────
func enter_bounding(target_pos: Vector3) -> void:
	change_soldier_state(SoldierState.BOUNDING)
	move_to(target_pos)

func tick_bounding() -> void:
	# If chasing, check proximity to target rather than nav finished
	if movement_state == MovementState.CHASING:
		if combat_target != null:
			var dist = global_position.distance_to(combat_target.global_position)
			if dist <= weapon.max_effective_range * 0.6:
				# Close enough to engage — stop advancing
				movement_state = MovementState.NONE
				change_soldier_state(SoldierState.NONE)
				bound_step_complete.emit(self)
		return
	if nav_agent.is_navigation_finished():
		change_soldier_state(SoldierState.NONE)
		bound_step_complete.emit(self)


# ─────────────────────────────────────────────
# OVERRIDE: trigger_combat
# Seek cover on first contact.
# ─────────────────────────────────────────────
# ─────────────────────────────────────────────
# OVERRIDE: perform_action
# In defensive mode, intercept MOVE actions and
# block any movement that would leave cover.
# ─────────────────────────────────────────────
func perform_action(action: CombatOptions) -> void:
	if defensive_mode and action == CombatOptions.MOVE:
		# Only allow repositioning within the defence perimeter
		# Explicitly block advance, chase, leap by re-rolling as AIM
		var roll = randi_range(0, 1)
		if roll == 0:
			perform_action(CombatOptions.AIM)
		else:
			perform_action(CombatOptions.FIRE)
		return
	super(action)

func trigger_combat(body: AI) -> void:
	super(body)
	if soldier_state != SoldierState.NONE:
		return
	if defensive_mode:
		# Already in position — suppress from here rather than seeking new cover
		if at_cover:
			enter_suppressing()
		else:
			# Not at cover yet — seek nearest cover to objective, not to enemy
			enter_cover_seeking()
		return
	# Normal combat: seek cover proactively
	if not at_cover:
		enter_cover_seeking()


# ─────────────────────────────────────────────
# SQUAD ORDER: move to objective
# Called by Squad when unengaged and an objective exists.
# Only executes if not currently in combat.
# ─────────────────────────────────────────────
func order_move_to(pos: Vector3) -> void:
	if ai_state == AIState.COMBAT or ai_state == AIState.DEAD:
		return
	# CRITICAL or E-KILL: signal too degraded to receive squad orders
	if not _can_receive_orders():
		return
	change_soldier_state(SoldierState.NONE)
	change_ai_state(AIState.PATROL)
	move_to(pos)


# ─────────────────────────────────────────────
# ROLE ASSIGNMENT (called by Squad)
# ─────────────────────────────────────────────
func assign_role(role: SoldierRole) -> void:
	# CRITICAL or E-KILL: ignores squad role assignments
	if not _can_receive_orders():
		return
	squad_role = role
	match role:
		SoldierRole.SUPPRESSOR:
			enter_suppressing()
		SoldierRole.ADVANCER:
			if combat_target != null:
				# Move aggressively toward the target — use CHASE so
				# it keeps updating nav rather than one small step
				movement_state = MovementState.CHASING
				change_soldier_state(SoldierState.BOUNDING)
		SoldierRole.FLANKER:
			if combat_target != null:
				enter_bounding(find_flank_target())
		SoldierRole.FALLBACK:
			enter_bounding(find_fallback_target())
		SoldierRole.OVERWATCH:
			movement_state = MovementState.NONE
			velocity.x = 0
			velocity.z = 0
		SoldierRole.NONE:
			change_soldier_state(SoldierState.NONE)


# ─────────────────────────────────────────────
# FLANK TARGET
# ─────────────────────────────────────────────
func find_flank_target() -> Vector3:
	if combat_target == null:
		return global_position
	var nav_map = nav_agent.get_navigation_map()
	var to_target = (combat_target.global_position - global_position).normalized()
	var right = to_target.cross(Vector3.UP).normalized()
	var flank_dir = right if randf() > 0.5 else -right
	var test_pos = combat_target.global_position + flank_dir * reposition_distance * 3.0
	return NavigationServer3D.map_get_closest_point(nav_map, test_pos)


# ─────────────────────────────────────────────
# OVERRIDE: get_inaccurate_target
# When SUPPRESSED, multiply spread mrad by the penalty factor instead
# of the old accuracy float system.
# ─────────────────────────────────────────────
func get_inaccurate_target(target_pos: Vector3) -> Vector3:
	if soldier_state == SoldierState.SUPPRESSED and weapon != null:
		var dist := global_position.distance_to(weapon_target)
		# suppressed_accuracy_penalty < 1.0 means worse accuracy.
		# We invert it to get a spread multiplier: 0.4 penalty → 2.5x spread.
		var spread_mult = 1.0 / maxf(suppressed_accuracy_penalty, 0.1)
		var effective_skill = accuracy_skill * maxf(signal_integrity, 0.1)
		var spread_mrad = (weapon.ai_spread_mrad / effective_skill) * spread_mult
		var spread_m = spread_mrad * dist / 1000.0
		return target_pos + Vector3(
			randf_range(-spread_m, spread_m),
			randf_range(-spread_m * 0.35, spread_m * 0.35),
			randf_range(-spread_m, spread_m)
		)
	return super(target_pos)


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
# ─────────────────────────────────────────────
func die() -> void:
	release_cover()
	if squad != null:
		squad.notify_member_died(self)
	reset_debug_label()
	super()


# ─────────────────────────────────────────────
# OVERRIDE: reset
# ─────────────────────────────────────────────
func reset() -> void:
	release_cover()
	soldier_state = SoldierState.NONE
	squad_role = SoldierRole.NONE
	defensive_mode = false
	bound_partner = null
	suppress_timer = 0.0
	suppressed_timer = 0.0
	super()


# ─────────────────────────────────────────────
# OVERRIDE: update_debug_label
# ─────────────────────────────────────────────
func update_debug_label() -> void:
	super()
	if label != null:
		label.text += "\n%s" % SoldierRole.keys()[squad_role]

func reset_debug_label() -> void:
	if label != null:
		label.text = "DEAD"
