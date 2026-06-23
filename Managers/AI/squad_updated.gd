extends Node
class_name Squad

# ─────────────────────────────────────────────
# SQUAD
# The brain. Soldiers are the limbs.
#
# UNENGAGED: moving toward objective
# ENGAGED:   in contact, coordinating roles
#
# SHARED TARGETING:
#   Any member with confirmed LOS calls update_shared_target().
#   shared_target_position is broadcast to all members who have
#   lost their personal target, so the squad fires as a unit
#   even when only one member has eyes on.
#   shared_target_credibility degrades over time — when it hits
#   zero the squad has no intelligence and enters search.
# ─────────────────────────────────────────────

enum SquadContext { UNENGAGED, ENGAGED }
enum SquadObjective { NONE, ADVANCE, DEFEND, WITHDRAW }

@export var squad_members: Array[AI]
@export var target_objective: SquadObjectivePoint

var context: SquadContext = SquadContext.UNENGAGED
var objective: SquadObjective = SquadObjective.NONE
var objective_position: Vector3 = Vector3.ZERO

var squad_combat_target: CharacterBody3D = null
var nco: Soldier = null
var bound_pairs: Array = []

# ── SHARED TARGETING ──────────────────────────
# Position all members without a personal target should fire at
var shared_target_position: Vector3 = Vector3.ZERO
# 1.0 = fresh intel, 0.0 = stale — degrades per second
var shared_target_credibility: float = 0.0
# How many seconds fresh intel lasts before fully degrading
@export var shared_target_ttl: float = 10.0
# Minimum credibility before members stop using shared target
const MIN_CREDIBILITY: float = 0.1

# ── TIMERS ────────────────────────────────────
const DISENGAGE_CHECK_INTERVAL: float = 2.0
var disengage_timer: float = 0.0

const OBJECTIVE_NUDGE_INTERVAL: float = 3.0
var nudge_timer: float = 0.0

# How often to broadcast shared target to members
const SHARED_TARGET_BROADCAST_INTERVAL: float = 0.5
var broadcast_timer: float = 0.0


# ─────────────────────────────────────────────
# READY
# ─────────────────────────────────────────────
func _ready() -> void:
	for ai in squad_members:
		_connect_member(ai)
		if ai is Soldier:
			ai.squad = self
	if target_objective != null:
		await get_tree().process_frame
		set_objective(SquadObjective.ADVANCE, target_objective.global_position)


# ─────────────────────────────────────────────
# PROCESS
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	match context:
		SquadContext.ENGAGED:
			_tick_engaged(delta)
		SquadContext.UNENGAGED:
			_tick_unengaged(delta)

func _tick_engaged(delta: float) -> void:
	# Degrade shared target credibility over time
	if shared_target_credibility > 0.0:
		shared_target_credibility -= delta / shared_target_ttl
		shared_target_credibility = maxf(shared_target_credibility, 0.0)

	# Broadcast shared target to members who've lost their personal target
	broadcast_timer += delta
	if broadcast_timer >= SHARED_TARGET_BROADCAST_INTERVAL:
		broadcast_timer = 0.0
		_broadcast_shared_target()

	# Check if combat is over
	disengage_timer += delta
	if disengage_timer >= DISENGAGE_CHECK_INTERVAL:
		disengage_timer = 0.0
		_check_disengage()

func _tick_unengaged(delta: float) -> void:
	if objective == SquadObjective.NONE or objective_position == Vector3.ZERO:
		return
	nudge_timer += delta
	if nudge_timer < OBJECTIVE_NUDGE_INTERVAL:
		return
	nudge_timer = 0.0
	for ai in get_living_members():
		if ai is Soldier:
			var dist = ai.global_position.distance_to(objective_position)
			if dist > 3.0 and ai.movement_state == Enemy.MovementState.NONE:
				var offset = Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
				ai.order_move_to(objective_position + offset)

func _check_disengage() -> void:
	var still_fighting := false
	for ai in get_living_members():
		if ai is Enemy:
			var e := ai as Enemy
			if (e.combat_target != null and e.combat_target.alive) or \
			   e.ai_state == Enemy.AIState.SEARCH:
				still_fighting = true
				break
	# Also still fighting if shared target has credibility
	if shared_target_credibility > MIN_CREDIBILITY:
		still_fighting = true
	if not still_fighting:
		_disengage_and_resume()


# ─────────────────────────────────────────────
# SHARED TARGETING
# ─────────────────────────────────────────────

# Called by any member that has confirmed LOS on a hostile
func update_shared_target(position: Vector3, _reporter: Enemy) -> void:
	shared_target_position = position
	shared_target_credibility = 1.0

# Broadcast shared target to members who've lost their own target
func _broadcast_shared_target() -> void:
	if shared_target_credibility <= MIN_CREDIBILITY:
		return
	if shared_target_position == Vector3.ZERO:
		return
	for ai in get_living_members():
		if not ai is Enemy:
			continue
		var e := ai as Enemy
		# Only help members who don't have a live personal target
		if e.combat_target != null and e.combat_target.alive:
			continue
		if e.ai_state == Enemy.AIState.COMBAT or e.ai_state == Enemy.AIState.SEARCH:
			# Give them the shared position to fire at
			e.weapon_target = shared_target_position
			e.look_target = shared_target_position
			# Use degraded accuracy based on credibility
			# (low credibility = spraying an area, not precise targeting)
			e._shared_target_accuracy_scale = shared_target_credibility


# ─────────────────────────────────────────────
# MEMBER MANAGEMENT
# ─────────────────────────────────────────────
func add_ai_to_squad(ai: AI) -> void:
	if ai == null or squad_members.has(ai):
		return
	squad_members.append(ai)
	_connect_member(ai)
	if ai is Soldier:
		ai.squad = self

func remove_ai_from_squad(ai: AI) -> void:
	if ai == null or not squad_members.has(ai):
		return
	squad_members.erase(ai)
	_disconnect_member(ai)

func _connect_member(ai: AI) -> void:
	if not ai.is_connected("combat_triggered", _on_combat_triggered):
		ai.connect("combat_triggered", _on_combat_triggered)
	if ai is Soldier and not ai.is_connected("bound_step_complete", _on_bound_step_complete):
		ai.connect("bound_step_complete", _on_bound_step_complete)

func _disconnect_member(ai: AI) -> void:
	if ai.is_connected("combat_triggered", _on_combat_triggered):
		ai.disconnect("combat_triggered", _on_combat_triggered)
	if ai is Soldier and ai.is_connected("bound_step_complete", _on_bound_step_complete):
		ai.disconnect("bound_step_complete", _on_bound_step_complete)

func get_living_members() -> Array:
	return squad_members.filter(func(ai): return ai != null and ai.alive)

func get_living_soldiers() -> Array:
	return squad_members.filter(func(ai): return ai != null and ai.alive and ai is Soldier)

func is_wiped() -> bool:
	return get_living_members().is_empty()


# ─────────────────────────────────────────────
# OBJECTIVE
# ─────────────────────────────────────────────
func set_objective(new_objective: SquadObjective, position: Vector3 = Vector3.ZERO) -> void:
	objective = new_objective
	objective_position = position
	if context == SquadContext.ENGAGED:
		return
	_issue_objective_orders()

func _issue_objective_orders() -> void:
	match objective:
		SquadObjective.ADVANCE, SquadObjective.DEFEND:
			for ai in get_living_members():
				var offset = Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
				if ai is Soldier:
					ai.order_move_to(objective_position + offset)
				elif ai.ai_state != Enemy.AIState.COMBAT:
					ai.move_to(objective_position + offset)
		SquadObjective.WITHDRAW:
			for ai in get_living_members():
				var offset = Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
				if ai is Soldier:
					ai.order_move_to(objective_position + offset)
					ai.change_soldier_state(Soldier.SoldierState.NONE)
				else:
					ai.move_to(objective_position + offset)


# ─────────────────────────────────────────────
# CONTACT
# ─────────────────────────────────────────────
func _on_combat_triggered(triggered_ai: AI) -> void:
	if triggered_ai == null or triggered_ai.combat_target == null:
		return
	squad_combat_target = triggered_ai.combat_target
	# Update shared target immediately from the triggering member
	update_shared_target(triggered_ai.combat_target.global_position, triggered_ai)
	# Alert all members not yet in combat
	for ai in get_living_members():
		if ai.ai_state != Enemy.AIState.COMBAT:
			ai.trigger_combat(triggered_ai.combat_target)
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
	if nco != null and nco.alive:
		_nco_assign_roles(soldiers)
	else:
		_basic_assign_roles(soldiers)

func _basic_assign_roles(soldiers: Array) -> void:
	bound_pairs.clear()
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
# BOUNDING
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

func _on_bound_step_complete(soldier: Soldier) -> void:
	for pair in bound_pairs:
		var suppressor: Soldier = pair["suppressor"]
		var advancer: Soldier   = pair["advancer"]
		if soldier == advancer:
			pair["suppressor"] = advancer
			pair["advancer"]   = suppressor
			advancer.assign_role(Soldier.SoldierRole.SUPPRESSOR)
			suppressor.assign_role(Soldier.SoldierRole.ADVANCER)
			return
		if soldier == suppressor:
			advancer.assign_role(Soldier.SoldierRole.ADVANCER)
			return


# ─────────────────────────────────────────────
# NCO
# ─────────────────────────────────────────────
func set_nco(soldier: Soldier) -> void:
	nco = soldier

# Called when a SUPPRESSOR starts reloading and can no longer suppress.
# Promotes an ADVANCER to SUPPRESSOR temporarily to keep fire going.
func notify_suppressor_reloading(reloading_soldier: Soldier) -> void:
	# Find a bound pair where this soldier is the suppressor
	for pair in bound_pairs:
		if pair["suppressor"] == reloading_soldier:
			var advancer: Soldier = pair["advancer"]
			if advancer != null and advancer.alive:
				# Swap — advancer covers while suppressor reloads
				advancer.assign_role(Soldier.SoldierRole.SUPPRESSOR)
			return
	# No pair found — find any advancer to fill the gap
	for ai in get_living_soldiers():
		if ai.squad_role == Soldier.SoldierRole.ADVANCER and ai != reloading_soldier:
			ai.assign_role(Soldier.SoldierRole.SUPPRESSOR)
			return

func notify_member_died(ai: AI) -> void:
	if ai == nco:
		nco = null
		if context == SquadContext.ENGAGED:
			_basic_assign_roles(get_living_soldiers())
	if context == SquadContext.ENGAGED:
		_rebuild_pairs_after_loss()

func _rebuild_pairs_after_loss() -> void:
	bound_pairs = bound_pairs.filter(func(pair):
		return pair["suppressor"].alive and pair["advancer"].alive)
	for ai in get_living_soldiers():
		if ai.squad_role == Soldier.SoldierRole.SUPPRESSOR and \
		   ai.bound_partner != null and not ai.bound_partner.alive:
			ai.bound_partner = null
			ai.assign_role(Soldier.SoldierRole.ADVANCER)


# ─────────────────────────────────────────────
# DISENGAGE
# ─────────────────────────────────────────────
func _disengage_and_resume() -> void:
	context = SquadContext.UNENGAGED
	squad_combat_target = null
	shared_target_position = Vector3.ZERO
	shared_target_credibility = 0.0
	bound_pairs.clear()
	for ai in get_living_members():
		if ai is Soldier:
			ai.change_soldier_state(Soldier.SoldierState.NONE)
			ai.assign_role(Soldier.SoldierRole.NONE)
	if objective != SquadObjective.NONE and objective_position != Vector3.ZERO:
		_issue_objective_orders()
