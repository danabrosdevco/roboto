extends Node
class_name Squad

# ─────────────────────────────────────────────
# SQUAD
# The brain. Soldiers are the limbs.
#
# UNENGAGED: Squad has an objective. Soldiers move toward it.
# ENGAGED:   Contact made. Squad assigns roles and coordinates.
#
# The Squad ticks every frame to:
#   - Detect when all enemies are dead → resume objective
#   - Re-issue move orders when unengaged soldiers finish moving
# ─────────────────────────────────────────────

enum SquadContext { UNENGAGED, ENGAGED }
# NOTE: ATTACK is appended, never inserted — inspector-set default_objective
# values are stored as ints and inserting would silently remap every squad.
enum SquadObjective { NONE, ADVANCE, DEFEND, WITHDRAW, ATTACK }

@export var squad_members: Array [Soldier]

# Human-readable callsign shown on the HUD. Falls back to node name.
@export var callsign: String = ""

# True if this squad answers to the player's command layer.
@export var player_commandable: bool = false

# Assign a SquadObjectivePoint in the inspector to give the squad
# a destination before contact is made.
@export var target_objective: SquadObjectivePoint
# What this squad does when it reaches its objective on map load
@export var default_objective: SquadObjective = SquadObjective.ADVANCE

var context: SquadContext = SquadContext.UNENGAGED
var objective: SquadObjective = SquadObjective.NONE
var objective_position: Vector3 = Vector3.ZERO

# ── CONTACT TRACKING ──────────────────────────
# ENGAGED used to be purely event-driven: set by _on_combat_triggered, cleared
# by a 2s poll that asked "does anyone still hold a live combat_target?".
# Both halves leaked.
#   - reconsider_target() nulls combat_target the instant a target dies and
#     drops the AI into SEARCH. Kill something and every member can be holding
#     a null target on the same poll, so the squad declared itself CLEAR in the
#     middle of a firefight.
#   - if the combat_triggered signal was ever missed (member added after
#     _ready, combat entered before connection) nothing ever set ENGAGED at all.
# Now: contact is POLLED from member state and held for CONTACT_GRACE seconds
# after the last confirmed sighting, so the readout is stable.
const CONTACT_GRACE: float = 6.0
var _since_contact: float = CONTACT_GRACE

var squad_combat_target: CharacterBody3D = null
var nco: Soldier = null
var bound_pairs: Array = []

# ── PLAYER COMMAND ────────────────────────────
# Set when the player issues an order. Player orders outrank the squad's own
# reasoning: they survive contact, and _disengage_and_resume() returns to them
# rather than to the designer-placed objective.
var player_ordered: bool = false
var ordered_target: CharacterBody3D = null

signal objective_changed(squad: Squad)
signal roster_changed(squad: Squad)

# How often to re-check whether combat is over (seconds)
const DISENGAGE_CHECK_INTERVAL: float = 2.0
var disengage_timer: float = 0.0

# How often to nudge unengaged soldiers who've stopped moving (seconds)
const OBJECTIVE_NUDGE_INTERVAL: float = 3.0
var nudge_timer: float = 0.0


# ─────────────────────────────────────────────
# READY
# ─────────────────────────────────────────────
func _ready() -> void:
	# The debug overlay, the player's commander and the squad HUD all discover
	# squads through this group. Registering here means level designers never
	# have to remember to tick it.
	if not is_in_group("squads"):
		add_to_group("squads")

	for ai in squad_members:
		if ai == null:
			continue
		_connect_member(ai)
		if ai is Soldier:
			ai.squad = self

	if target_objective != null:
		# Wait until all members have finished their initialization (8 frames in Enemy)
		# Use 10 frames to be safe
		for i in 2:
			await get_tree().process_frame
		set_objective(default_objective, target_objective.global_position)


# ─────────────────────────────────────────────
# PROCESS — context monitoring
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	_tick_contact(delta)
	match context:
		SquadContext.ENGAGED:
			_tick_engaged(delta)
		SquadContext.UNENGAGED:
			_tick_unengaged(delta)


# ─────────────────────────────────────────────
# CONTACT — polled, with hysteresis
# ─────────────────────────────────────────────
# True the moment any member is actually fighting. SEARCH counts: a soldier who
# just lost sight of a target and is moving to their last known position is
# still in contact by any sane reading, and excluding it was most of the reason
# the HUD flickered back to CLEAR.
func has_live_contact() -> bool:
	for ai in get_living_members():
		if not ai is Enemy:
			continue
		if ai.ai_state == Enemy.AIState.COMBAT or ai.ai_state == Enemy.AIState.SEARCH:
			return true
		if ai.combat_target != null and ai.combat_target.alive:
			return true
	return false


func _tick_contact(delta: float) -> void:
	if has_live_contact():
		_since_contact = 0.0
		# Safety net: promote to ENGAGED even if combat_triggered never arrived.
		if context != SquadContext.ENGAGED:
			context = SquadContext.ENGAGED
			disengage_timer = 0.0
			assign_roles()
	else:
		_since_contact += delta


# Seconds since this squad last had anyone in contact. The HUD reads this
# rather than `context` so the readout can't lag a frame behind the fight.
func seconds_since_contact() -> float:
	return _since_contact


func is_in_contact() -> bool:
	return _since_contact < CONTACT_GRACE


func _tick_engaged(delta: float) -> void:
	disengage_timer += delta
	if disengage_timer < DISENGAGE_CHECK_INTERVAL:
		return
	disengage_timer = 0.0

	# Only stand down once the grace window has fully elapsed with nobody in
	# contact. This is the fix for the squad flipping to CLEAR between one
	# target dying and the next being acquired.
	if _since_contact >= CONTACT_GRACE:
		_disengage_and_resume()


func _tick_unengaged(delta: float) -> void:
	if objective == SquadObjective.NONE or objective_position == Vector3.ZERO:
		return

	nudge_timer += delta
	if nudge_timer < OBJECTIVE_NUDGE_INTERVAL:
		return
	nudge_timer = 0.0

	# Re-issue move orders to any soldier who has stopped or gone passive
	for ai in get_orderable_soldiers():
		var dist = ai.global_position.distance_to(objective_position)
		var is_stuck = dist > 3.0 and (
			ai.movement_state == Enemy.MovementState.NONE or
			ai.ai_state == Enemy.AIState.PASSIVE
		)
		if is_stuck:
			ai.always_active = true  # prevent passive mode from blocking movement
			ai.order_move_to(objective_position + _formation_offset(ai))


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

func remove_ai_from_squad(ai: Node) -> void:
	if ai == null or not squad_members.has(ai):
		return
	squad_members.erase(ai)
	_disconnect_member(ai)

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

func get_living_members() -> Array:
	return squad_members.filter(func(ai): return ai != null and ai.alive)

func get_living_soldiers() -> Array:
	return squad_members.filter(func(ai): return ai != null and ai.alive and ai is Soldier)

func is_wiped() -> bool:
	return get_living_members().is_empty()

# Members the squad is still allowed to give orders to.
func get_orderable_members() -> Array:
	return get_living_members()

func get_orderable_soldiers() -> Array:
	return get_orderable_members().filter(func(ai): return ai is Soldier)

# Squad is a plain Node, so it has no transform of its own.
func get_center() -> Vector3:
	var living = get_living_members()
	if living.is_empty():
		return objective_position
	var sum := Vector3.ZERO
	for ai in living:
		sum += ai.global_position
	return sum / living.size()

func get_display_name() -> String:
	return callsign if callsign != "" else name

func notify_roster_changed() -> void:
	roster_changed.emit(self)

# Public re-issue, used when a body comes back under AI control after the
# player releases it and needs slotting into the current plan.
func resume_objective() -> void:
	if objective == SquadObjective.NONE:
		return
	_issue_objective_orders(true)


# ─────────────────────────────────────────────
# OBJECTIVE
# ─────────────────────────────────────────────
func set_objective(
	new_objective: SquadObjective,
	position: Vector3 = Vector3.ZERO,
	force: bool = false
) -> void:
	objective = new_objective
	objective_position = position
	objective_changed.emit(self)

	# The squad's own reasoning doesn't interrupt a firefight with a move order.
	# A player order does — being able to say "break contact, move there" mid-
	# contact is the entire point of the command layer.
	if context == SquadContext.ENGAGED and not force:
		return

	_issue_objective_orders(force)

func _issue_objective_orders(force: bool = false) -> void:
	match objective:
		SquadObjective.ADVANCE:
			for ai in get_orderable_members():
				var offset = _formation_offset(ai)
				if ai.has_method("enter_passive_mode"):
					ai.always_active = true
				if ai is Soldier:
					ai.defensive_mode = false
					ai.order_move_to(objective_position + offset, force)
				else:
					if force or ai.ai_state != Enemy.AIState.COMBAT:
						ai.move_to(objective_position + offset)
		SquadObjective.DEFEND:
			_issue_defend_orders()
		SquadObjective.WITHDRAW:
			for ai in get_orderable_members():
				var offset = _formation_offset(ai)
				if ai.has_method("enter_passive_mode"):
					ai.always_active = true
				if ai is Soldier:
					ai.defensive_mode = false
					ai.order_move_to(objective_position + offset, force)
					ai.change_soldier_state(Soldier.SoldierState.NONE)
				else:
					ai.move_to(objective_position + offset)
		SquadObjective.ATTACK:
			_issue_attack_orders()


# ─────────────────────────────────────────────
# ATTACK — player designated a specific hostile
# ─────────────────────────────────────────────
func _issue_attack_orders() -> void:
	if ordered_target == null or not is_instance_valid(ordered_target):
		# Target died or was never valid — fall back to pushing the last position.
		objective = SquadObjective.ADVANCE
		_issue_objective_orders(true)
		return

	squad_combat_target = ordered_target
	for ai in get_orderable_members():
		ai.always_active = true
		if ai is Soldier:
			ai.defensive_mode = false
		if ai.has_method("trigger_combat"):
			ai.trigger_combat(ordered_target)

	if context != SquadContext.ENGAGED:
		context = SquadContext.ENGAGED
		disengage_timer = 0.0
	assign_roles()


# ─────────────────────────────────────────────
# FORMATION
# Replaces the old randf_range scatter. Places members in slots along an axis
# perpendicular to the advance, so a squad moves as a spread line rather than
# a clump that a single grenade deletes.
# ─────────────────────────────────────────────
const FORMATION_SPACING: float = 2.6

func _formation_offset(member: Node) -> Vector3:
	var members = get_orderable_members()
	var idx = members.find(member)
	if idx < 0:
		return Vector3.ZERO

	var advance_dir = (objective_position - get_center())
	advance_dir.y = 0.0
	if advance_dir.length_squared() < 0.01:
		advance_dir = Vector3.FORWARD
	advance_dir = advance_dir.normalized()

	var lateral = advance_dir.cross(Vector3.UP).normalized()

	# Slot order: centre, right, left, right2, left2 ...
	var slot := 0
	if idx > 0:
		slot = int((idx + 1) / 2)
		if idx % 2 == 0:
			slot = -slot
	return lateral * (slot * FORMATION_SPACING)

# ─────────────────────────────────────────────
# PLAYER ORDER — the single entry point for the command layer
#
# Everything the player can tell a squad to do funnels through here. The old
# CommandMarker did a 600m physics sphere sweep to find out who was listening;
# this instead pushes the order straight at a squad the player has already
# selected. No physics, no faction scan, deterministic.
# ─────────────────────────────────────────────
func receive_player_order(
	order: SquadObjective,
	position: Vector3 = Vector3.ZERO,
	target: CharacterBody3D = null
) -> void:
	player_ordered = true
	ordered_target = target

	if order == SquadObjective.ATTACK:
		if target == null or not is_instance_valid(target):
			return
		objective = SquadObjective.ATTACK
		objective_position = target.global_position
		objective_changed.emit(self)
		_issue_attack_orders()
		return

	set_objective(order, position, true)


func _issue_defend_orders() -> void:
	var soldiers = get_orderable_soldiers()
	if soldiers.is_empty():
		return

	# Get all candidate cover points near the objective
	var candidates = _get_cover_points_near(objective_position, 25.0)

	# Use farthest-point sampling to spread soldiers out:
	# Pick the first point closest to the objective, then each
	# subsequent pick is the point farthest from all chosen points.
	var chosen: Array = _select_spread_cover(candidates, soldiers.size())

	for i in soldiers.size():
		var soldier: Soldier = soldiers[i]
		if soldier.has_method("enter_passive_mode"):
			soldier.always_active = true
		soldier.defensive_mode = true
		if i < chosen.size():
			var cp: CoverPoint = chosen[i]
			soldier.current_cover_point = cp
			cp.mark_occupied(soldier)
			soldier.order_move_to(cp.global_position)
		else:
			# More soldiers than cover points — spread in a ring around objective
			var angle = (TAU / soldiers.size()) * i
			var spread = Vector3(cos(angle), 0, sin(angle)) * 6.0
			soldier.order_move_to(objective_position + spread)

func _select_spread_cover(candidates: Array, count: int) -> Array:
	# Farthest-point sampling: maximises minimum distance between chosen points.
	# Seed with the point closest to the objective so the defence anchors there.
	if candidates.is_empty():
		return []

	var result: Array = []

	# Seed: pick point closest to objective
	var seed: CoverPoint = candidates[0]
	var seed_dist = INF
	for cp in candidates:
		var d = objective_position.distance_to(cp.global_position)
		if d < seed_dist:
			seed_dist = d
			seed = cp
	result.append(seed)

	# Greedy farthest-point: each pick maximises min-distance to all chosen
	var remaining: Array = candidates.duplicate()
	remaining.erase(seed)

	while result.size() < count and not remaining.is_empty():
		var best: CoverPoint = null
		var best_min_dist: float = -1.0
		for cp in remaining:
			# Find this candidate's minimum distance to any already-chosen point
			var min_dist: float = INF
			for chosen_cp in result:
				var d = cp.global_position.distance_to(chosen_cp.global_position)
				if d < min_dist:
					min_dist = d
			# Keep the candidate whose min distance to chosen set is largest
			if min_dist > best_min_dist:
				best_min_dist = min_dist
				best = cp
		if best != null:
			result.append(best)
			remaining.erase(best)

	return result

func _get_cover_points_near(pos: Vector3, radius: float) -> Array:
	var all_cover = get_tree().get_nodes_in_group("cover_points")
	var result: Array = []
	for cp in all_cover:
		if not cp is CoverPoint:
			continue
		if cp.is_occupied():
			continue
		if pos.distance_to(cp.global_position) <= radius:
			result.append(cp)
	return result


# ─────────────────────────────────────────────
# CONTACT
# ─────────────────────────────────────────────
func _on_combat_triggered(triggered_ai: AI) -> void:
	if triggered_ai == null or triggered_ai.combat_target == null:
		return

	squad_combat_target = triggered_ai.combat_target

	# Alert all members not yet in combat.
	for ai in get_orderable_members():
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
	var soldiers = get_orderable_soldiers()
	if soldiers.is_empty():
		return
	# Defending squads don't bound — everyone suppresses or overwatches
	if objective == SquadObjective.DEFEND:
		_defensive_assign_roles(soldiers)
		return
	if nco != null and nco.alive:
		_nco_assign_roles(soldiers)
	else:
		_basic_assign_roles(soldiers)

func _defensive_assign_roles(soldiers: Array) -> void:
	bound_pairs.clear()
	# NCO overwatches if present, everyone else suppresses from cover
	for soldier in soldiers:
		if soldier == nco and nco != null and nco.alive:
			soldier.assign_role(Soldier.SoldierRole.OVERWATCH)
		else:
			soldier.assign_role(Soldier.SoldierRole.SUPPRESSOR)

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

func notify_member_died(ai: AI) -> void:
	if ai == nco:
		nco = null
		if context == SquadContext.ENGAGED:
			_basic_assign_roles(get_orderable_soldiers())
	if context == SquadContext.ENGAGED:
		_rebuild_pairs_after_loss()
	roster_changed.emit(self)

func _rebuild_pairs_after_loss() -> void:
	bound_pairs = bound_pairs.filter(func(pair):
		return pair["suppressor"].alive and pair["advancer"].alive
	)
	for ai in get_orderable_soldiers():
		if ai.squad_role == Soldier.SoldierRole.SUPPRESSOR and ai.bound_partner != null and not ai.bound_partner.alive:
			ai.bound_partner = null
			ai.assign_role(Soldier.SoldierRole.ADVANCER)


# ─────────────────────────────────────────────
# DISENGAGE — resume objective after combat ends
# ─────────────────────────────────────────────
func _disengage_and_resume() -> void:
	context = SquadContext.UNENGAGED
	_since_contact = CONTACT_GRACE
	squad_combat_target = null
	bound_pairs.clear()

	for ai in get_orderable_members():
		if ai is Soldier:
			ai.change_soldier_state(Soldier.SoldierState.NONE)
			ai.assign_role(Soldier.SoldierRole.NONE)
			# Only clear defensive mode if we're no longer on a DEFEND objective
			if objective != SquadObjective.DEFEND:
				ai.defensive_mode = false

	# An ATTACK order is spent once its target is down — don't loop on a corpse.
	if objective == SquadObjective.ATTACK:
		ordered_target = null
		objective = SquadObjective.DEFEND
		objective_position = get_center()

	# Resume movement toward objective if one exists
	if objective != SquadObjective.NONE and objective_position != Vector3.ZERO:
		_issue_objective_orders()
