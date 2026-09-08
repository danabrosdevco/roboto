extends Node
class_name Squad

# ─────────────────────────────────────────────
# SQUAD
# The brain. Soldiers are the limbs.
#
# UNENGAGED: Squad has an objective. Soldiers move toward it.
# ENGAGED:   Contact made. Squad assigns roles and coordinates.
# ─────────────────────────────────────────────

enum SquadContext { UNENGAGED, ENGAGED }
enum SquadObjective { NONE, ADVANCE, DEFEND, WITHDRAW }

@export var squad_members: Array [Soldier]

# Assign a SquadObjectivePoint in the inspector to give the squad
# a destination before contact is made.
@export var target_objective: SquadObjectivePoint
# What this squad does when it reaches its objective on map load
@export var default_objective: SquadObjective = SquadObjective.ADVANCE

var context: SquadContext = SquadContext.UNENGAGED
var objective: SquadObjective = SquadObjective.NONE
var objective_position: Vector3 = Vector3.ZERO

var squad_combat_target: CharacterBody3D = null
var nco: Soldier = null
var bound_pairs: Array = []

# How often to re-check whether combat is over (seconds)
const DISENGAGE_CHECK_INTERVAL: float = 2.0
var disengage_timer: float = 0.0

# How often to nudge unengaged soldiers who've stopped moving (seconds)
const OBJECTIVE_NUDGE_INTERVAL: float = 3.0
var nudge_timer: float = 0.0

# ── LIVING MEMBER CACHE ───────────────────────
# get_living_members() ran filter() every tick from three call sites,
# allocating a fresh array each time.
var _living_cache: Array = []
var _living_soldier_cache: Array = []
var _living_dirty: bool = true

# Guards the recursive alert cascade in _on_combat_triggered.
var _alerting: bool = false


# ─────────────────────────────────────────────
# READY
# ─────────────────────────────────────────────
func _ready() -> void:
	for ai in squad_members:
		if ai == null:
			continue
		_connect_member(ai)
		if ai is Soldier:
			ai.squad = self
	_living_dirty = true

	if target_objective != null:
		# Enemy.initialize awaits one frame; wait two to be safe.
		for i in 2:
			await get_tree().process_frame
		set_objective(default_objective, target_objective.global_position)


# ─────────────────────────────────────────────
# PROCESS — context monitoring
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	match context:
		SquadContext.ENGAGED:
			_tick_engaged(delta)
		SquadContext.UNENGAGED:
			_tick_unengaged(delta)


func _tick_engaged(delta: float) -> void:
	disengage_timer += delta
	if disengage_timer < DISENGAGE_CHECK_INTERVAL:
		return
	disengage_timer = 0.0

	var still_fighting := false
	for ai in get_living_members():
		if ai is Enemy and ai.combat_target != null and ai.combat_target.alive:
			still_fighting = true
			break

	if not still_fighting:
		_disengage_and_resume()


func _tick_unengaged(delta: float) -> void:
	if objective == SquadObjective.NONE or objective_position == Vector3.ZERO:
		return

	nudge_timer += delta
	if nudge_timer < OBJECTIVE_NUDGE_INTERVAL:
		return
	nudge_timer = 0.0

	for ai in get_living_soldiers():
		var dist = ai.global_position.distance_to(objective_position)
		var is_stuck = dist > 3.0 and (
			ai.movement_state == Enemy.MovementState.NONE or
			ai.ai_state == Enemy.AIState.PASSIVE
		)
		if is_stuck:
			ai.always_active = true
			var offset = Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
			ai.order_move_to(objective_position + offset)


# ─────────────────────────────────────────────
# MEMBER MANAGEMENT
# ─────────────────────────────────────────────
func add_ai_to_squad(ai: Node) -> void:
	if ai == null or squad_members.has(ai):
		return
	squad_members.append(ai)
	_connect_member(ai)
	if ai is Soldier:
		ai.squad = self
	_living_dirty = true

func remove_ai_from_squad(ai: Node) -> void:
	if ai == null or not squad_members.has(ai):
		return
	squad_members.erase(ai)
	_disconnect_member(ai)
	_living_dirty = true

func _connect_member(ai: Node) -> void:
	if ai == null:
		return
	if ai.has_signal("combat_triggered") and not ai.is_connected("combat_triggered", _on_combat_triggered):
		ai.connect("combat_triggered", _on_combat_triggered)
	if ai is Soldier and not ai.is_connected("bound_step_complete", _on_bound_step_complete):
		ai.connect("bound_step_complete", _on_bound_step_complete)

func _disconnect_member(ai: Node) -> void:
	if ai == null:
		return
	if ai.has_signal("combat_triggered") and ai.is_connected("combat_triggered", _on_combat_triggered):
		ai.disconnect("combat_triggered", _on_combat_triggered)
	if ai is Soldier and ai.is_connected("bound_step_complete", _on_bound_step_complete):
		ai.disconnect("bound_step_complete", _on_bound_step_complete)

func _rebuild_living_cache() -> void:
	_living_cache.clear()
	_living_soldier_cache.clear()
	for ai in squad_members:
		if ai == null or not is_instance_valid(ai) or not ai.alive:
			continue
		_living_cache.append(ai)
		if ai is Soldier:
			_living_soldier_cache.append(ai)
	_living_dirty = false

func get_living_members() -> Array:
	if _living_dirty:
		_rebuild_living_cache()
	return _living_cache

func get_living_soldiers() -> Array:
	if _living_dirty:
		_rebuild_living_cache()
	return _living_soldier_cache

func is_wiped() -> bool:
	return get_living_members().is_empty()


# ─────────────────────────────────────────────
# OBJECTIVE
# ─────────────────────────────────────────────
func set_objective(new_objective: SquadObjective, position: Vector3 = Vector3.ZERO) -> void:
	objective = new_objective
	objective_position = position

	# Don't interrupt active combat with movement orders
	if context == SquadContext.ENGAGED:
		return

	_issue_objective_orders()

func _issue_objective_orders() -> void:
	match objective:
		SquadObjective.ADVANCE, SquadObjective.WITHDRAW:
			for ai in get_living_members():
				var offset = Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
				ai.always_active = true
				if ai is Soldier:
					ai.defensive_mode = false
					ai.defensive_anchor = Vector3.ZERO
					ai.change_soldier_state(Soldier.SoldierState.NONE)
					ai.order_move_to(objective_position + offset)
				else:
					if ai.ai_state != Enemy.AIState.COMBAT:
						ai.move_to(objective_position + offset)
		SquadObjective.DEFEND:
			_issue_defend_orders()

func _issue_defend_orders() -> void:
	var soldiers = get_living_soldiers()
	if soldiers.is_empty():
		return

	var candidates = _get_cover_points_near(objective_position, 25.0)
	var chosen: Array = _select_spread_cover(candidates, soldiers.size())

	for i in soldiers.size():
		var soldier: Soldier = soldiers[i]
		soldier.always_active = true
		soldier.defensive_mode = true
		soldier.defensive_anchor = objective_position
		if i < chosen.size():
			# Route through COVER_SEEKING so at_cover is set on arrival.
			# The old path used order_move_to (which sets AIState.PATROL),
			# so at_cover stayed false and on contact the soldier walked
			# away from the very cover point the squad had reserved for it.
			soldier.order_move_to_cover(chosen[i])
		else:
			var angle = (TAU / soldiers.size()) * i
			var spread = Vector3(cos(angle), 0, sin(angle)) * 6.0
			soldier.order_move_to(objective_position + spread)

func _select_spread_cover(candidates: Array, count: int) -> Array:
	# Farthest-point sampling: maximises minimum distance between chosen points.
	if candidates.is_empty():
		return []

	var result: Array = []

	var seed_cp: CoverPoint = candidates[0]
	var seed_dist = INF
	for cp in candidates:
		var d = objective_position.distance_to(cp.global_position)
		if d < seed_dist:
			seed_dist = d
			seed_cp = cp
	result.append(seed_cp)

	var remaining: Array = candidates.duplicate()
	remaining.erase(seed_cp)

	while result.size() < count and not remaining.is_empty():
		var best: CoverPoint = null
		var best_min_dist: float = -1.0
		for cp in remaining:
			var min_dist: float = INF
			for chosen_cp in result:
				var d = cp.global_position.distance_to(chosen_cp.global_position)
				if d < min_dist:
					min_dist = d
			if min_dist > best_min_dist:
				best_min_dist = min_dist
				best = cp
		if best != null:
			result.append(best)
			remaining.erase(best)
		else:
			break

	return result

func _get_cover_points_near(pos: Vector3, radius: float) -> Array:
	var all_cover = get_tree().get_nodes_in_group("cover_points")
	var result: Array = []
	var radius_sq = radius * radius
	for cp in all_cover:
		if not cp is CoverPoint:
			continue
		if cp.is_occupied():
			continue
		if pos.distance_squared_to(cp.global_position) <= radius_sq:
			result.append(cp)
	return result


# ─────────────────────────────────────────────
# CONTACT
# ─────────────────────────────────────────────
func _on_combat_triggered(triggered_ai: AI) -> void:
	if triggered_ai == null or triggered_ai.combat_target == null:
		return
	# Each alerted member re-emits combat_triggered, which re-entered this
	# function once per member. Terminated, but O(n^2) on first contact.
	if _alerting:
		return
	_alerting = true

	squad_combat_target = triggered_ai.combat_target

	for ai in get_living_members():
		if ai.ai_state != Enemy.AIState.COMBAT:
			ai.trigger_combat(triggered_ai.combat_target)

	_alerting = false

	if context != SquadContext.ENGAGED:
		context = SquadContext.ENGAGED
		disengage_timer = 0.0
		assign_roles()


# ─────────────────────────────────────────────
# ROLE ASSIGNMENT
# ─────────────────────────────────────────────
func assign_roles() -> void:
	var soldiers = get_living_soldiers()
	if soldiers.is_empty():
		return
	if objective == SquadObjective.DEFEND:
		_defensive_assign_roles(soldiers)
		return
	if nco != null and nco.alive:
		_nco_assign_roles(soldiers)
	else:
		_basic_assign_roles(soldiers)

func _defensive_assign_roles(soldiers: Array) -> void:
	bound_pairs.clear()
	for soldier in soldiers:
		if soldier == nco and nco != null and nco.alive:
			soldier.assign_role(Soldier.SoldierRole.OVERWATCH)
		else:
			soldier.assign_role(Soldier.SoldierRole.SUPPRESSOR)

func _basic_assign_roles(soldiers: Array) -> void:
	bound_pairs.clear()
	if soldiers.is_empty():
		return
	if soldiers.size() == 1:
		soldiers[0].assign_role(Soldier.SoldierRole.ADVANCER)
		return
	var half = int(soldiers.size() / 2)
	for i in soldiers.size():
		if i < half:
			soldiers[i].assign_role(Soldier.SoldierRole.SUPPRESSOR)
		else:
			soldiers[i].assign_role(Soldier.SoldierRole.ADVANCER)
	_build_bound_pairs(soldiers)

func _nco_assign_roles(soldiers: Array) -> void:
	bound_pairs.clear()
	var available = soldiers.filter(func(s): return s != nco)
	if available.is_empty():
		return
	nco.assign_role(Soldier.SoldierRole.OVERWATCH)
	if available.size() == 1:
		available[0].assign_role(Soldier.SoldierRole.ADVANCER)
		return
	available[0].assign_role(Soldier.SoldierRole.FLANKER)
	var rest = available.slice(1)
	var half = int(rest.size() / 2)
	for i in rest.size():
		if i < half:
			rest[i].assign_role(Soldier.SoldierRole.SUPPRESSOR)
		else:
			rest[i].assign_role(Soldier.SoldierRole.ADVANCER)
	_build_bound_pairs(rest)


# ─────────────────────────────────────────────
# BOUNDING PAIRS
# ─────────────────────────────────────────────
func _build_bound_pairs(soldiers: Array) -> void:
	var suppressors = soldiers.filter(func(s): return s.squad_role == Soldier.SoldierRole.SUPPRESSOR)
	var advancers   = soldiers.filter(func(s): return s.squad_role == Soldier.SoldierRole.ADVANCER)
	var pair_count = min(suppressors.size(), advancers.size())
	for i in pair_count:
		var pair = { "suppressor": suppressors[i], "advancer": advancers[i] }
		bound_pairs.append(pair)
		suppressors[i].bound_partner = advancers[i]
		advancers[i].bound_partner = suppressors[i]

## The old version, when the suppressor finished its burn, re-ordered the
## advancer to advance (which it already was) and left the suppressor with
## no state and no role work — so it fell back to random rolling and the
## pair stopped alternating after one cycle.
func _on_bound_step_complete(soldier: Soldier) -> void:
	for pair in bound_pairs:
		var suppressor: Soldier = pair["suppressor"]
		var advancer: Soldier   = pair["advancer"]
		if not is_instance_valid(suppressor) or not is_instance_valid(advancer):
			continue

		if soldier == advancer:
			# Advancer finished its bound — swap: it covers, partner moves.
			pair["suppressor"] = advancer
			pair["advancer"]   = suppressor
			advancer.bound_partner = suppressor
			suppressor.bound_partner = advancer
			advancer.assign_role(Soldier.SoldierRole.SUPPRESSOR)
			suppressor.assign_role(Soldier.SoldierRole.ADVANCER)
			return

		if soldier == suppressor:
			# Suppressor burned out its window. If the partner is still
			# moving, renew the suppression rather than going idle.
			if advancer.alive and advancer.soldier_state == Soldier.SoldierState.BOUNDING:
				suppressor.assign_role(Soldier.SoldierRole.SUPPRESSOR)
			else:
				pair["suppressor"] = advancer
				pair["advancer"]   = suppressor
				advancer.bound_partner = suppressor
				suppressor.bound_partner = advancer
				advancer.assign_role(Soldier.SoldierRole.SUPPRESSOR)
				suppressor.assign_role(Soldier.SoldierRole.ADVANCER)
			return


# ─────────────────────────────────────────────
# NCO
# ─────────────────────────────────────────────
func set_nco(soldier: Soldier) -> void:
	nco = soldier

func notify_member_died(ai: AI) -> void:
	_living_dirty = true
	if ai == nco:
		nco = null
		if context == SquadContext.ENGAGED:
			_basic_assign_roles(get_living_soldiers())
			return
	if context == SquadContext.ENGAGED:
		_rebuild_pairs_after_loss()

func _rebuild_pairs_after_loss() -> void:
	var surviving: Array = []
	for pair in bound_pairs:
		var s: Soldier = pair["suppressor"]
		var a: Soldier = pair["advancer"]
		if not is_instance_valid(s) or not is_instance_valid(a):
			continue
		if not s.alive or not a.alive:
			continue
		surviving.append(pair)
	bound_pairs = surviving

	for ai in get_living_soldiers():
		if ai.squad_role == Soldier.SoldierRole.SUPPRESSOR and ai.bound_partner != null:
			if not is_instance_valid(ai.bound_partner) or not ai.bound_partner.alive:
				ai.bound_partner = null
				ai.assign_role(Soldier.SoldierRole.ADVANCER)


# ─────────────────────────────────────────────
# DISENGAGE — resume objective after combat ends
# ─────────────────────────────────────────────
func _disengage_and_resume() -> void:
	context = SquadContext.UNENGAGED
	squad_combat_target = null
	bound_pairs.clear()

	for ai in get_living_members():
		if ai is Soldier:
			ai.change_soldier_state(Soldier.SoldierState.NONE)
			ai.assign_role(Soldier.SoldierRole.NONE)
			ai.bound_partner = null
			if objective != SquadObjective.DEFEND:
				ai.defensive_mode = false
				ai.defensive_anchor = Vector3.ZERO
				ai.release_cover()
		# Let distant members go passive again. This was set true and never
		# cleared, so every squad member ran full physics for the whole level.
		if objective == SquadObjective.NONE or objective_position == Vector3.ZERO:
			ai.always_active = false

	if objective != SquadObjective.NONE and objective_position != Vector3.ZERO:
		_issue_objective_orders()
