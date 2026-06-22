extends Node
class_name Squad

# ─────────────────────────────────────────────
# SQUAD
# The brain. Soldiers are the limbs.
#
# Squad has two contexts:
#   UNENGAGED — moving to / holding an objective
#   ENGAGED   — contact made, managing roles and tactics
#
# Squad decides WHAT each Soldier does.
# Soldier decides HOW to do it.
# ─────────────────────────────────────────────

enum SquadContext { UNENGAGED, ENGAGED }
enum SquadObjective { NONE, ADVANCE, DEFEND, WITHDRAW }

@export var squad_members: Array[AI]
@export var target_objective: SquadObjectivePoint
var context: SquadContext = SquadContext.UNENGAGED
var objective: SquadObjective = SquadObjective.NONE
var objective_position: Vector3 = Vector3.ZERO

# The confirmed combat target shared across the squad
var squad_combat_target: CharacterBody3D = null

# NCO — if present and alive, they direct role assignment.
# If null or dead, squad falls back to basic coordination.
var nco: Soldier = null

# Bounding pairs: array of [suppressor, advancer] Soldier pairs
var bound_pairs: Array = []

# ─────────────────────────────────────────────
# READY
# ─────────────────────────────────────────────
func _ready() -> void:
	for ai in squad_members:
		_connect_member(ai)
	if target_objective:
		set_objective(SquadObjective.ADVANCE, target_objective.global_position)
# ─────────────────────────────────────────────
# MEMBER MANAGEMENT
# ─────────────────────────────────────────────
func add_ai_to_squad(ai: AI) -> void:
	if ai == null or squad_members.has(ai):
		return
	squad_members.append(ai)
	_connect_member(ai)

func remove_ai_from_squad(ai: AI) -> void:
	if ai == null or not squad_members.has(ai):
		return
	squad_members.erase(ai)
	_disconnect_member(ai)

func _connect_member(ai: AI) -> void:
	if ai.has_signal("combat_triggered"):
		ai.connect("combat_triggered", _on_combat_triggered)
	if ai is Soldier:
		ai.connect("bound_step_complete", _on_bound_step_complete)

func _disconnect_member(ai: AI) -> void:
	if ai.has_signal("combat_triggered") and ai.is_connected("combat_triggered", _on_combat_triggered):
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
# OBJECTIVE (UNENGAGED)
# ─────────────────────────────────────────────
func set_objective(new_objective: SquadObjective, position: Vector3 = Vector3.ZERO) -> void:
	objective = new_objective
	objective_position = position

	if context == SquadContext.ENGAGED:
		return  # Don't override active combat coordination

	match objective:
		SquadObjective.ADVANCE:
			_order_advance_to(objective_position)
		SquadObjective.DEFEND:
			_order_defend(objective_position)
		SquadObjective.WITHDRAW:
			_order_withdraw(objective_position)

func _order_advance_to(pos: Vector3) -> void:
	for ai in get_living_members():
		# Spread members slightly so they don't stack on the exact same point
		var offset = Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
		ai.move_to(pos + offset)

func _order_defend(pos: Vector3) -> void:
	# Members hold position near the objective
	for ai in get_living_members():
		var offset = Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0))
		ai.move_to(pos + offset)

func _order_withdraw(pos: Vector3) -> void:
	for ai in get_living_members():
		var offset = Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
		ai.move_to(pos + offset)
		# Soldiers stop engaging while withdrawing
		if ai is Soldier:
			ai.change_soldier_state(Soldier.SoldierState.NONE)


# ─────────────────────────────────────────────
# CONTACT (ENGAGED)
# Called when any member spots an enemy.
# ─────────────────────────────────────────────
func _on_combat_triggered(triggered_ai: AI) -> void:
	if triggered_ai == null or triggered_ai.combat_target == null:
		return

	squad_combat_target = triggered_ai.combat_target

	# Alert all members not yet in combat
	for ai in get_living_members():
		if ai.ai_state != Enemy.AIState.COMBAT:
			ai.trigger_combat(triggered_ai.combat_target)

	# Switch squad to ENGAGED and assign roles
	if context != SquadContext.ENGAGED:
		context = SquadContext.ENGAGED
		assign_roles()


# ─────────────────────────────────────────────
# ROLE ASSIGNMENT
# Distributes roles across living Soldiers.
# NCO directs if alive; otherwise basic fallback logic.
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
	# With no NCO: roughly half suppress, half advance.
	# If only one soldier, they advance (no choice).
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

	# Pair suppressors with advancers for bounding coordination
	_build_bound_pairs(soldiers)


func _nco_assign_roles(soldiers: Array) -> void:
	# NCO present: smarter role split.
	# One flanker, one suppressor per two advancers, NCO overwatches.
	bound_pairs.clear()

	var available = soldiers.filter(func(s): return s != nco)
	if available.is_empty():
		return

	# NCO holds back and overwatches
	nco.assign_role(Soldier.SoldierRole.OVERWATCH)

	if available.size() == 1:
		available[0].assign_role(Soldier.SoldierRole.ADVANCER)
		return

	# First soldier flanks, rest split suppress/advance
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
# Pairs each suppressor with an advancer.
# When the advancer finishes their bound, they become the suppressor.
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


# ─────────────────────────────────────────────
# BOUNDING COORDINATION
# When a bound step completes, swap roles in that pair.
# ─────────────────────────────────────────────
func _on_bound_step_complete(soldier: Soldier) -> void:
	for pair in bound_pairs:
		var suppressor: Soldier = pair["suppressor"]
		var advancer: Soldier   = pair["advancer"]

		if soldier == advancer:
			# Advancer arrived — swap: advancer suppresses, suppressor advances
			pair["suppressor"] = advancer
			pair["advancer"]   = suppressor
			advancer.assign_role(Soldier.SoldierRole.SUPPRESSOR)
			suppressor.assign_role(Soldier.SoldierRole.ADVANCER)
			return

		if soldier == suppressor:
			# Suppressor finished their cover window — re-trigger advancer if stalled
			advancer.assign_role(Soldier.SoldierRole.ADVANCER)
			return


# ─────────────────────────────────────────────
# NCO MANAGEMENT
# ─────────────────────────────────────────────
func set_nco(soldier: Soldier) -> void:
	nco = soldier

func notify_member_died(ai: AI) -> void:
	# Called externally (or via signal) when a member dies
	if ai == nco:
		nco = null
		# Squad degrades without NCO — reassign roles with basic logic
		if context == SquadContext.ENGAGED:
			_basic_assign_roles(get_living_soldiers())

	# Rebuild bound pairs without the dead member
	if context == SquadContext.ENGAGED:
		_rebuild_pairs_after_loss()

func _rebuild_pairs_after_loss() -> void:
	bound_pairs = bound_pairs.filter(func(pair):
		return pair["suppressor"].alive and pair["advancer"].alive
	)
	# Any orphaned suppressor now just advances
	for ai in get_living_soldiers():
		if ai.squad_role == Soldier.SoldierRole.SUPPRESSOR and ai.bound_partner != null and not ai.bound_partner.alive:
			ai.bound_partner = null
			ai.assign_role(Soldier.SoldierRole.ADVANCER)


# ─────────────────────────────────────────────
# DISENGAGE
# ─────────────────────────────────────────────
func disengage() -> void:
	context = SquadContext.UNENGAGED
	squad_combat_target = null
	bound_pairs.clear()
	for ai in get_living_members():
		if ai is Soldier:
			ai.change_soldier_state(Soldier.SoldierState.NONE)
			ai.assign_role(Soldier.SoldierRole.NONE)
