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
# Where the defence is anchored — repositioning stays inside this radius.
var defensive_anchor: Vector3 = Vector3.ZERO
@export var defensive_perimeter: float = 7.0

# ── Cover ──
var current_cover_point: CoverPoint = null
var at_cover: bool = false
@export var cover_arrival_threshold: float = 1.2
@export var cover_search_radius: float = 25.0
# Role to apply once cover is reached. Lets the squad say "suppress" and
# have the soldier get into cover first instead of standing in the open.
var _pending_role_after_cover: SoldierRole = SoldierRole.NONE

# ── Suppression ──
@export var suppress_duration: float = 3.0
var suppress_timer: float = 0.0
## Position being suppressed. Blind fire goes here when LOS is lost.
var suppress_position: Vector3 = Vector3.ZERO
## Spread multiplier when firing at a position we cannot currently see.
@export var blind_fire_spread_multiplier: float = 4.0

@export var suppressed_duration: float = 2.5
var suppressed_timer: float = 0.0
@export var suppressed_accuracy_penalty: float = 0.4
## Signal integrity below which incoming fire pins this soldier.
## Matches Enemy.SIGNAL_DEGRADED by default (literal, since export defaults
## must be constant expressions).
@export var suppressed_trigger: float = 0.50

# ── Bounding ──
var bound_partner: Soldier = null

# ── Signals ──
signal reached_cover(soldier: Soldier)
signal suppressing_started(soldier: Soldier)
signal suppressed_started(soldier: Soldier)
signal bound_step_complete(soldier: Soldier)


# ─────────────────────────────────────────────
# OVERRIDE: reconsider_combat
# Blocks Enemy's weighted action rolling while a soldier state is active,
# so cover-seeking / bounding / suppressing complete uninterrupted.
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
# OVERRIDE: move_to
# `at_cover` was only ever cleared in release_cover(), so a soldier pushed
# off its cover kept believing it was in cover forever and never re-sought.
# ─────────────────────────────────────────────
func move_to(pos: Vector3) -> void:
	if at_cover and current_cover_point != null:
		if pos.distance_to(current_cover_point.global_position) > cover_arrival_threshold:
			release_cover()
	super(pos)


# ─────────────────────────────────────────────
# COVER SEEKING
# ─────────────────────────────────────────────
func enter_cover_seeking(pending_role: SoldierRole = SoldierRole.NONE) -> void:
	# Already on the way to a claimed point. Re-running find_best_cover_point
	# here would skip our own point (we marked it occupied) and send us to a
	# different one — which is the exact bug the DEFEND path used to have.
	if soldier_state == SoldierState.COVER_SEEKING and current_cover_point != null:
		if pending_role != SoldierRole.NONE:
			_pending_role_after_cover = pending_role
		return
	if at_cover and current_cover_point != null:
		if pending_role != SoldierRole.NONE:
			_apply_role_now(pending_role)
		return

	var cp = find_best_cover_point()
	if cp == null:
		_pending_role_after_cover = SoldierRole.NONE
		change_soldier_state(SoldierState.NONE)
		# No cover available — apply the role from here rather than idling.
		if pending_role != SoldierRole.NONE:
			_apply_role_now(pending_role)
		return
	_pending_role_after_cover = pending_role
	current_cover_point = cp
	cp.mark_occupied(self)   # claim it now so squadmates don't pick the same one
	change_soldier_state(SoldierState.COVER_SEEKING)
	super.move_to(cp.global_position)

## Assign a specific cover point (used by Squad's DEFEND orders) and route
## through COVER_SEEKING so at_cover actually gets set on arrival.
func order_move_to_cover(cp: CoverPoint, pending_role: SoldierRole = SoldierRole.NONE) -> void:
	if cp == null or not _can_receive_orders():
		return
	release_cover()
	current_cover_point = cp
	cp.mark_occupied(self)
	_pending_role_after_cover = pending_role
	change_ai_state(AIState.PATROL)
	change_soldier_state(SoldierState.COVER_SEEKING)
	super.move_to(cp.global_position)

func tick_cover_seeking() -> void:
	if current_cover_point == null:
		change_soldier_state(SoldierState.NONE)
		return
	# Was using is_target_reached() while everything else used
	# is_navigation_finished(), and cover_arrival_threshold went unused.
	var arrived = global_position.distance_to(current_cover_point.global_position) <= cover_arrival_threshold
	if not arrived and not nav_agent.is_navigation_finished():
		return
	if not arrived:
		# Nav gave up short of the point — take it anyway if we're close-ish,
		# otherwise drop the claim and re-plan.
		if global_position.distance_to(current_cover_point.global_position) > cover_arrival_threshold * 3.0:
			release_cover()
			change_soldier_state(SoldierState.NONE)
			var pending = _pending_role_after_cover
			_pending_role_after_cover = SoldierRole.NONE
			if pending != SoldierRole.NONE:
				_apply_role_now(pending)
			return
	at_cover = true
	movement_state = MovementState.NONE
	if current_cover_point.cover_direction.length_squared() > 0.0001:
		look_target = current_cover_point.global_position + current_cover_point.cover_direction * 5.0
	change_soldier_state(SoldierState.NONE)
	reached_cover.emit(self)

	var pending_role = _pending_role_after_cover
	_pending_role_after_cover = SoldierRole.NONE
	if pending_role != SoldierRole.NONE:
		_apply_role_now(pending_role)

func find_best_cover_point() -> CoverPoint:
	var cover_points = get_tree().get_nodes_in_group("cover_points")
	var best: CoverPoint = null
	var best_score: float = -INF
	var target_pos = combat_target.global_position if combat_target else global_position
	var radius_sq = cover_search_radius * cover_search_radius

	for cp in cover_points:
		if not cp is CoverPoint or cp.is_occupied():
			continue
		if global_position.distance_squared_to(cp.global_position) > radius_sq:
			continue
		# In defensive mode, don't wander out of the perimeter chasing cover.
		if defensive_mode and defensive_anchor != Vector3.ZERO:
			if cp.global_position.distance_to(defensive_anchor) > defensive_perimeter:
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
# Now actually suppresses: keeps firing at the last known position even
# without LOS, at heavy spread. Previously a suppressor with no LOS just
# stood still doing nothing for the whole duration.
# ─────────────────────────────────────────────
func enter_suppressing(target_position: Vector3 = Vector3.ZERO) -> void:
	change_soldier_state(SoldierState.SUPPRESSING)
	suppress_timer = 0.0
	movement_state = MovementState.NONE
	if target_position != Vector3.ZERO:
		suppress_position = target_position
	elif combat_target != null:
		suppress_position = combat_target.global_position
	elif not last_seen_point.is_empty():
		suppress_position = last_seen_point.back()
	else:
		suppress_position = weapon_target
	weapon_target = suppress_position
	look_target = suppress_position
	suppressing_started.emit(self)

func tick_suppressing(delta: float) -> void:
	suppress_timer += delta
	# Keep the aim point fresh while we can see them; otherwise keep
	# hosing the last known position.
	if combat_target != null and combat_target.alive and _has_los:
		suppress_position = combat_target.global_position
	weapon_target = suppress_position
	look_target = suppress_position
	if suppress_timer >= suppress_duration:
		change_soldier_state(SoldierState.NONE)
		bound_step_complete.emit(self)

func _can_fire_without_los() -> bool:
	return soldier_state == SoldierState.SUPPRESSING


# ─────────────────────────────────────────────
# SUPPRESSED
# enter_suppressed() was never called from anywhere. It's now driven by
# incoming near-miss fire via receive_signal_damage.
# ─────────────────────────────────────────────
func _on_signal_damaged(before: float, after: float) -> void:
	if before > suppressed_trigger and after <= suppressed_trigger:
		if soldier_state != SoldierState.SUPPRESSED and ai_state == AIState.COMBAT:
			enter_suppressed()

func enter_suppressed() -> void:
	change_soldier_state(SoldierState.SUPPRESSED)
	suppressed_timer = 0.0
	movement_state = MovementState.NONE
	if not last_seen_point.is_empty() and combat_target == null:
		weapon_target = last_seen_point.back()
	suppressed_started.emit(self)

func tick_suppressed(delta: float) -> void:
	suppressed_timer += delta
	# Stay pinned as long as rounds keep landing close.
	if signal_integrity <= suppressed_trigger:
		suppressed_timer = minf(suppressed_timer, suppressed_duration * 0.5)
	if suppressed_timer >= suppressed_duration:
		change_soldier_state(SoldierState.NONE)
		# Coming out of being pinned, get into cover rather than standing up.
		if not at_cover and ai_state == AIState.COMBAT:
			enter_cover_seeking()


# ─────────────────────────────────────────────
# BOUNDING
# ─────────────────────────────────────────────
func enter_bounding(target_pos: Vector3) -> void:
	change_soldier_state(SoldierState.BOUNDING)
	move_to(target_pos)

func tick_bounding() -> void:
	# If chasing, check proximity to target rather than nav finished
	if movement_state == MovementState.CHASING:
		if combat_target != null:
			var dist = global_position.distance_to(combat_target.global_position)
			if dist <= _max_range() * 0.6:
				movement_state = MovementState.NONE
				change_soldier_state(SoldierState.NONE)
				bound_step_complete.emit(self)
		else:
			movement_state = MovementState.NONE
			change_soldier_state(SoldierState.NONE)
			bound_step_complete.emit(self)
		return
	if movement_state == MovementState.NONE or nav_agent.is_navigation_finished():
		change_soldier_state(SoldierState.NONE)
		bound_step_complete.emit(self)


# ─────────────────────────────────────────────
# OVERRIDE: perform_action
# In defensive mode the old code re-dispatched to AIM/FIRE, both of which
# were no-ops, so a defending soldier could never adjust position at all
# despite the comment saying it could.
# ─────────────────────────────────────────────
func perform_action(action: CombatOptions) -> void:
	if defensive_mode and action == CombatOptions.MOVE:
		# Allow small adjustments inside the perimeter; block advance/chase/leap.
		if randf() < 0.5:
			var pos = _find_perimeter_reposition()
			if pos != global_position:
				move_to(pos)
				previous_movement_option = MovementOptions.REPOSITION
				return
		_enter_aim_stance()
		return
	super(action)

func _find_perimeter_reposition() -> Vector3:
	var anchor = defensive_anchor if defensive_anchor != Vector3.ZERO else global_position
	var nav_map = nav_agent.get_navigation_map()
	var to_target = Vector3.FORWARD
	if combat_target != null:
		to_target = (combat_target.global_position - global_position)
		to_target.y = 0.0
		if to_target.length_squared() < 0.0001:
			to_target = Vector3.FORWARD
		to_target = to_target.normalized()
	var right = to_target.cross(Vector3.UP).normalized()
	var lateral = right if randf() > 0.5 else -right
	for mult in [1.0, 0.5]:
		var test = global_position + lateral * reposition_distance * mult
		if test.distance_to(anchor) > defensive_perimeter:
			continue
		var pt = NavigationServer3D.map_get_closest_point(nav_map, test)
		if pt.distance_to(anchor) > defensive_perimeter:
			continue
		return pt
	return global_position


# ─────────────────────────────────────────────
# OVERRIDE: trigger_combat
# ─────────────────────────────────────────────
func trigger_combat(body: AI) -> void:
	super(body)
	if soldier_state != SoldierState.NONE:
		return
	if defensive_mode:
		if at_cover:
			enter_suppressing()
		else:
			enter_cover_seeking(SoldierRole.SUPPRESSOR)
		return
	if not at_cover:
		enter_cover_seeking()


# ─────────────────────────────────────────────
# SQUAD ORDER: move to objective
# ─────────────────────────────────────────────
func order_move_to(pos: Vector3) -> void:
	if ai_state == AIState.COMBAT or ai_state == AIState.DEAD:
		return
	# CRITICAL or E-KILL: signal too degraded to receive squad orders
	if not _can_receive_orders():
		return
	release_cover()
	_pending_role_after_cover = SoldierRole.NONE
	change_soldier_state(SoldierState.NONE)
	change_ai_state(AIState.PATROL)
	move_to(pos)


# ─────────────────────────────────────────────
# ROLE ASSIGNMENT (called by Squad)
# Roles that want the soldier stationary now route through cover first,
# instead of standing up in the open. Previously the squad's assign_roles
# fired immediately after trigger_combat and cancelled cover-seeking, so
# cover was effectively never used in a fight.
# ─────────────────────────────────────────────
func assign_role(role: SoldierRole) -> void:
	if not _can_receive_orders():
		return
	squad_role = role
	if role == SoldierRole.SUPPRESSOR or role == SoldierRole.OVERWATCH:
		if not at_cover and ai_state == AIState.COMBAT:
			enter_cover_seeking(role)
			return
	_apply_role_now(role)

func _apply_role_now(role: SoldierRole) -> void:
	squad_role = role
	match role:
		SoldierRole.SUPPRESSOR:
			enter_suppressing()
		SoldierRole.ADVANCER:
			if combat_target != null:
				release_cover()
				movement_state = MovementState.CHASING
				change_soldier_state(SoldierState.BOUNDING)
		SoldierRole.FLANKER:
			if combat_target != null:
				release_cover()
				enter_bounding(find_flank_target())
		SoldierRole.FALLBACK:
			release_cover()
			enter_bounding(find_fallback_target())
		SoldierRole.OVERWATCH:
			movement_state = MovementState.NONE
			change_soldier_state(SoldierState.NONE)
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
# OVERRIDE: aim spread
# Folds the suppressed penalty and blind-fire penalty into Enemy's
# multiplier rather than duplicating the whole spread calculation.
# ─────────────────────────────────────────────
func get_aim_spread_multiplier() -> float:
	var mult = super()
	if soldier_state == SoldierState.SUPPRESSED:
		mult *= 1.0 / maxf(suppressed_accuracy_penalty, 0.1)
	if soldier_state == SoldierState.SUPPRESSING and not _has_los:
		mult *= blind_fire_spread_multiplier
	if at_cover:
		mult *= 0.85   # braced against cover
	return mult


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
	_pending_role_after_cover = SoldierRole.NONE
	defensive_mode = false
	defensive_anchor = Vector3.ZERO
	bound_partner = null
	suppress_timer = 0.0
	suppressed_timer = 0.0
	suppress_position = Vector3.ZERO
	super()


# ─────────────────────────────────────────────
# OVERRIDE: update_debug_label
# ─────────────────────────────────────────────
func update_debug_label() -> void:
	super()
	if label != null:
		label.text += "\n%s / %s" % [
			SoldierRole.keys()[squad_role],
			SoldierState.keys()[soldier_state]
		]

func reset_debug_label() -> void:
	if label != null:
		label.text = "DEAD"
