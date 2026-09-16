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
# NOTE: FOLLOW is appended for the same reason ATTACK was. WITHDRAW is no
# longer reachable from the command wheel (DEFEND at a point behind you does the
# same job) but it stays in the enum — deleting it would shift ATTACK and FOLLOW
# down and silently remap every inspector-set default_objective in the project.
# PATROL appended for the same reason ATTACK and FOLLOW were — inspector
# default_objective values are stored as ints and inserting would remap them.
enum SquadObjective { NONE, ADVANCE, DEFEND, WITHDRAW, ATTACK, FOLLOW, PATROL }

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

# ── FOLLOW ────────────────────────────────────
# Who the squad is trailing when objective == FOLLOW. Normally the player.
# FOLLOW is the one objective with no fixed world position, so objective_position
# is recomputed from the leader every frame rather than set once.
var follow_leader: Node3D = null
# How far behind the leader the formation centre sits.
@export var follow_distance: float = 5.0
# Re-issue move orders once the leader has drifted this far from where the last
# order was given. Too small and the squad stutters as it re-paths every frame;
# too large and they lag visibly behind.
@export var follow_reissue_distance: float = 3.5

# ── WHY FOLLOW JITTERED ───────────────────────
# Two causes, both of which made the squad shuffle constantly a few metres from
# the player without anyone actually going anywhere.
#
# 1. The anchor was taken from the leader's BODY YAW, and the player body turns
#    with mouse look. A 180° turn swings the anchor a full 2 x follow_distance
#    across the map, and about 40° was enough to exceed follow_reissue_distance
#    — so simply looking around re-pathed the whole squad. The heading is now
#    taken from the leader's MOVEMENT and latched: stand still and turn on the
#    spot and the squad ignores you.
#
# 2. _formation_offset derives its lateral axis from (objective_position -
#    get_center()). Standing at the anchor makes that vector near zero, so its
#    direction flips frame to frame and every soldier's slot spins around them.
#    It now falls back to the latched heading instead.
#
# Minimum seconds between re-issues, whatever the distance. Backstop against
# a leader jittering across the threshold.
@export var follow_reissue_interval: float = 0.6
# A member already this close to their slot isn't given a new order. Without it
# they re-path to a spot they're standing on and pivot in place.
@export var follow_slot_tolerance: float = 1.6
# How fast the leader must move for their heading to count. Below this they're
# considered stationary and the last heading is kept.
@export var follow_heading_min_speed: float = 0.6
# Smooths the anchor so it eases rather than snapping.
@export var follow_anchor_smoothing: float = 6.0

var _last_follow_issue: Vector3 = Vector3.ZERO
var _follow_heading: Vector3 = Vector3.ZERO
var _follow_anchor_smoothed: Vector3 = Vector3.INF
var _follow_reissue_t: float = 0.0

# ── DEFEND POSTS ──────────────────────────────
# Where each member was told to hunker down. _issue_defend_orders already does
# the clever part — cover-point spread sampling around the objective — but once
# a soldier arrived there was nothing holding them, so the same state machine
# paths that broke FOLLOW (idle wander, search roam, patrol re-pick) walked them
# off their cover. Posts are remembered and re-asserted every frame.
@export var defend_post_tolerance: float = 1.4

# ── LEASHES ───────────────────────────────────
# How far a member may wander from their assigned position WHILE FIGHTING.
#
# Contact used to suspend the positional hold entirely — _tick_follow and
# _tick_defend both returned on ENGAGED and handed the robot to its own combat
# AI, which chases. At shotgun range that was invisible because the target was
# already on top of them. With an 80m rifle it means a DEFEND squad abandons the
# post the moment anyone shoots, and a FOLLOW squad walks off across the valley.
#
# The fix isn't to stop them manoeuvring — it's to bound it. Inside the leash
# they fight for themselves: take cover, bound, reposition. Cross it and the
# squad pulls them back. The order survives the firefight.
@export var follow_combat_leash: float = 12.0
@export var defend_combat_leash: float = 9.0
# ASSAULT keeps advancing under fire; the leash tracks the objective rather than
# a fixed post, so "engage along the way" falls out of it.
@export var assault_combat_leash: float = 14.0

# Seconds between forced recalls of the same soldier. order_move_to(pos, true)
# CLEARS combat_target and releases cover — that's what makes "fall back" work
# mid-firefight, and it's why issuing one every frame means a soldier can never
# finish acquiring, let alone shoot. A recall has to be an occasional
# correction, never a per-frame nudge.
@export var recall_interval: float = 1.6
# How far past the leash someone has to be before a recall interrupts a fight
# they're actually winning. Inside this band they're left alone.
@export var leash_grace_multiplier: float = 1.6
@export var assault_arrive_distance: float = 6.0
var _recall_times: Dictionary = {}   # Soldier -> msec of last forced order
var _defend_posts: Dictionary = {}   # Soldier -> Vector3

# ── PATROL ────────────────────────────────────
# The squad walks a level-authored route as a unit. Contact suspends it; the
# existing disengage path resumes it, from the point they were heading to
# rather than from the start, so a firefight doesn't reset the whole circuit.
@export var patrol_route: PatrolPath
@export var patrol_arrive_distance: float = 4.0
# Pause at each point. Zero makes them loop relentlessly, which reads as
# robotic in the bad way.
@export var patrol_dwell: float = 2.5
var patrol_index: int = 0
var _patrol_forward: bool = true
var _patrol_dwell_t: float = 0.0

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
	_tick_follow(delta)
	_tick_patrol(delta)
	_tick_defend()
	_tick_assault()
	_tick_contact(delta)
	match context:
		SquadContext.ENGAGED:
			_tick_engaged(delta)
		SquadContext.UNENGAGED:
			_tick_unengaged(delta)


# ─────────────────────────────────────────────
# FOLLOW
# ─────────────────────────────────────────────
# The leader is a moving objective, so this runs every frame regardless of
# context — the squad keeps its formation slot updated while it fights, and
# resumes following the moment contact breaks without needing a fresh order.
func _tick_follow(delta: float) -> void:
	if objective != SquadObjective.FOLLOW:
		return
	if follow_leader == null or not is_instance_valid(follow_leader):
		# Leader gone. Hold where they are rather than trailing a freed node.
		set_objective(SquadObjective.DEFEND, get_center(), true)
		return

	_update_follow_heading()
	objective_position = _follow_anchor(delta)

	if context == SquadContext.ENGAGED:
		# Fighting, but still following. Only the strays get pulled in.
		_enforce_leash(follow_combat_leash, false)
		return

	# Authoritative, every frame. Gating individual behaviours one at a time
	# (idle wander, search roam, patrol re-pick, stale passive targets) kept
	# missing one — there are at least five paths in Enemy that can start a
	# movement. So rather than chase them, the squad asserts the outcome: in
	# your slot means stopped and IDLE, out of it means walking to it. Anything
	# that starts a move on its own gets overridden within a frame.
	_hold_follow_formation()

	if _last_follow_issue.distance_to(objective_position) >= follow_reissue_distance:
		_last_follow_issue = objective_position


# ─────────────────────────────────────────────
# DEFEND — hold the post you were given
# ─────────────────────────────────────────────
func _tick_defend() -> void:
	if objective != SquadObjective.DEFEND:
		return
	if context == SquadContext.ENGAGED:
		# Holding under fire is the whole point of DEFEND. Manoeuvre locally,
		# but nobody leaves the position to chase.
		_enforce_leash(defend_combat_leash, true)
		return

	for ai in get_orderable_soldiers():
		var soldier := ai as Soldier
		if soldier == null or soldier.ai_state == Enemy.AIState.COMBAT:
			continue

		var post: Vector3 = _defend_post_for(soldier)
		var gap: float = soldier.global_position.distance_to(post)

		# Travelling: don't hug cover en route or they stop every few metres and
		# never arrive. defensive_mode goes on when they get there.
		if gap > defend_post_tolerance:
			soldier.defensive_mode = false

		if gap <= defend_post_tolerance:
			# In cover. Static, apart from the head — _tick_idle_scan turns
			# look_target and never touches movement.
			if soldier.ai_state != Enemy.AIState.IDLE:
				soldier.change_ai_state(Enemy.AIState.IDLE)
				# Watch outward, away from the thing being defended.
				soldier.set_scan_facing(soldier.global_position + (soldier.global_position - objective_position))
			soldier.defensive_mode = true
			if soldier.movement_state != Enemy.MovementState.NONE:
				soldier.halt()
			continue

		if soldier.movement_state == Enemy.MovementState.NONE \
				or soldier.movement_target.distance_to(post) > defend_post_tolerance:
			soldier.order_move_to(post, true)


# The post assigned by _issue_defend_orders, or a lazily-assigned fallback for a
# member who joined the squad after the order was given.
func _defend_post_for(soldier: Soldier) -> Vector3:
	if _defend_posts.has(soldier):
		return _defend_posts[soldier]
	var cover := soldier.find_best_cover_point()
	var post: Vector3
	if cover != null and cover.global_position.distance_to(objective_position) < 25.0:
		soldier.current_cover_point = cover
		cover.mark_occupied(soldier)
		post = cover.global_position
	else:
		var members := get_orderable_soldiers()
		var idx: int = maxi(0, members.find(soldier))
		var angle: float = (TAU / maxi(1, members.size())) * idx
		post = objective_position + Vector3(cos(angle), 0.0, sin(angle)) * 6.0
	_defend_posts[soldier] = post
	return post


# ASSAULT is "take the point, engage on the way" — so contact must not stop the
# advance. Without this an engaged squad plants itself wherever the first shot
# landed and the objective is never reached.
func _tick_assault() -> void:
	if objective != SquadObjective.ADVANCE and objective != SquadObjective.ATTACK:
		return
	if context != SquadContext.ENGAGED:
		return

	# NOT a leash. On ASSAULT the anchor IS the destination, so everyone is
	# "out of bounds" until they arrive — running the leash here meant every
	# soldier got a forced move every frame, which cleared their target every
	# frame. They ran at the objective and never fired a shot.
	#
	# The rule is instead: kill what you can reach, advance when you can't.
	for ai in get_orderable_members():
		if not (ai is Soldier):
			continue
		var soldier := ai as Soldier
		if _engaging_usefully(soldier):
			continue   # something in front of them — let the combat AI work

		var slot: Vector3 = objective_position + _formation_offset(soldier)
		if soldier.global_position.distance_to(slot) <= assault_arrive_distance:
			continue   # arrived; hold and fight from here

		# Already heading there under their own steam.
		if soldier.movement_state != Enemy.MovementState.NONE \
				and soldier.movement_target.distance_to(slot) <= assault_arrive_distance:
			continue

		if not _may_recall(soldier):
			continue
		soldier.defensive_mode = false
		soldier.order_move_to(slot, true)


# Is this soldier fighting something it can actually hit? A target 80m away for
# a 45m shotgun is not a reason to stand still, and a target in range is not a
# reason to be dragged off it.
func _engaging_usefully(soldier: Soldier) -> bool:
	if soldier.combat_target == null or not is_instance_valid(soldier.combat_target):
		return false
	if not soldier.combat_target.alive:
		return false
	var reach: float = 25.0
	if soldier.weapon != null and "max_effective_range" in soldier.weapon:
		reach = soldier.weapon.max_effective_range
	return soldier.global_position.distance_to(soldier.combat_target.global_position) <= reach


# Forced orders are rationed. Returns false if this soldier was recalled too
# recently to be recalled again.
func _may_recall(soldier: Soldier) -> bool:
	var now: float = Time.get_ticks_msec() / 1000.0
	var last: float = float(_recall_times.get(soldier, -999.0))
	if now - last < recall_interval:
		return false
	_recall_times[soldier] = now
	return true


# ─────────────────────────────────────────────
# LEASH
# ─────────────────────────────────────────────
# Runs DURING contact. Deliberately does nothing to anyone inside the radius —
# the point is to preserve the AI's combat behaviour, not replace it.
func _enforce_leash(radius: float, defensive: bool) -> void:
	if radius <= 0.0:
		return
	for ai in get_orderable_members():
		if not (ai is Soldier):
			continue
		var soldier := ai as Soldier
		var anchor: Vector3 = _anchor_for(soldier)
		var gap: float = soldier.global_position.distance_to(anchor)
		if gap <= radius:
			continue   # in bounds — leave them to fight

		# Just outside and shooting something they can hit: let them finish.
		# Yanking a soldier out of a winning exchange is worse than a loose
		# formation, and the recall clears their target to do it.
		if _engaging_usefully(soldier) and gap <= radius * leash_grace_multiplier:
			continue

		soldier.defensive_mode = defensive
		if soldier.movement_state != Enemy.MovementState.NONE \
				and soldier.movement_target.distance_to(anchor) <= radius * 0.5:
			continue   # already walking back
		if not _may_recall(soldier):
			continue
		soldier.order_move_to(anchor, true)


# Where this member is supposed to be, whatever the current objective is.
func _anchor_for(soldier: Soldier) -> Vector3:
	match objective:
		SquadObjective.DEFEND:
			return _defend_post_for(soldier)
		SquadObjective.FOLLOW, SquadObjective.PATROL:
			return objective_position + _formation_offset(soldier)
	return objective_position


# Runs every frame while following and out of contact. Cheap: one distance check
# per member, and orders only when something actually needs to change.
func _hold_follow_formation() -> void:
	for ai in get_orderable_members():
		if not (ai is Enemy):
			continue
		var robot := ai as Enemy
		# An engaged robot manoeuvres for itself — never override combat.
		if robot.ai_state == Enemy.AIState.COMBAT:
			continue

		robot.always_active = true
		var slot: Vector3 = objective_position + _formation_offset(ai)
		var gap: float = robot.global_position.distance_to(slot)

		if gap <= follow_slot_tolerance:
			# In position. Force the STATE as well as the movement — leaving
			# them in PATROL or SEARCH is what let the state machine restart a
			# move a frame later.
			if robot.ai_state != Enemy.AIState.IDLE:
				robot.change_ai_state(Enemy.AIState.IDLE)
			if robot.movement_state != Enemy.MovementState.NONE:
				robot.halt()
			continue

		# Out of position, and not already on their way there.
		if robot.movement_state == Enemy.MovementState.NONE \
				or robot.movement_target.distance_to(slot) > follow_slot_tolerance:
			if robot is Soldier:
				(robot as Soldier).defensive_mode = false
				(robot as Soldier).order_move_to(slot, true)
				(robot as Soldier).change_soldier_state(Soldier.SoldierState.NONE)
			else:
				robot.move_to(slot)


# Latched from the leader's actual motion, not their facing. Turning on the spot
# must not move the squad.
func _update_follow_heading() -> void:
	var velocity := Vector3.ZERO
	if follow_leader is CharacterBody3D:
		velocity = (follow_leader as CharacterBody3D).velocity
	velocity.y = 0.0
	if velocity.length() >= follow_heading_min_speed:
		_follow_heading = velocity.normalized()
		return
	if _follow_heading.length_squared() < 0.01:
		# Nothing to go on yet — seed from facing once, then never again.
		var back := follow_leader.global_transform.basis.z
		back.y = 0.0
		_follow_heading = -back.normalized() if back.length_squared() > 0.01 else Vector3.FORWARD


# A point behind the leader along their travel direction, so the squad stacks up
# at their back rather than walking through them — and smoothed, so a sharp
# change of direction eases the anchor across instead of teleporting it.
func _follow_anchor(delta: float) -> Vector3:
	var heading := _follow_heading
	if heading.length_squared() < 0.01:
		heading = Vector3.FORWARD
	var target: Vector3 = follow_leader.global_position - heading * follow_distance
	if _follow_anchor_smoothed == Vector3.INF or follow_anchor_smoothing <= 0.0:
		_follow_anchor_smoothed = target
	else:
		_follow_anchor_smoothed = _follow_anchor_smoothed.lerp(
			target, clampf(delta * follow_anchor_smoothing, 0.0, 1.0))
	return _follow_anchor_smoothed


func _issue_follow_orders() -> void:
	for ai in get_orderable_members():
		ai.always_active = true
		var slot: Vector3 = objective_position + _formation_offset(ai)
		# Already standing in their slot — stop, don't re-path. Re-issuing a
		# move to a spot you occupy is what produces the pivot-in-place shuffle.
		if ai.global_position.distance_to(slot) <= follow_slot_tolerance:
			if ai is Enemy:
				(ai as Enemy).halt()
			continue
		if ai is Soldier:
			ai.defensive_mode = false
			ai.order_move_to(slot, true)
			ai.change_soldier_state(Soldier.SoldierState.NONE)
		else:
			ai.move_to(slot)


# Cancels whatever the squad was doing and puts them on the leader's hip.
func follow(leader: Node3D) -> void:
	follow_leader = leader
	player_ordered = true
	ordered_target = null
	squad_combat_target = null
	_last_follow_issue = Vector3.ZERO
	# Seed the heading and anchor from the leader's current facing, once.
	_follow_heading = Vector3.ZERO
	_follow_anchor_smoothed = Vector3.INF
	_follow_reissue_t = 0.0
	if leader != null:
		_update_follow_heading()
	set_objective(SquadObjective.FOLLOW, _follow_anchor(0.0) if leader != null else get_center(), true)


# ─────────────────────────────────────────────
# PATROL
# ─────────────────────────────────────────────
func set_patrol(route: PatrolPath, start_index: int = 0) -> void:
	patrol_route = route
	patrol_index = start_index
	_patrol_forward = true
	_patrol_dwell_t = 0.0
	if route == null or route.points.is_empty():
		set_objective(SquadObjective.DEFEND, get_center(), true)
		return
	var point := route.point_at(patrol_index)
	set_objective(SquadObjective.PATROL, point.global_position if point else get_center(), true)


func _tick_patrol(delta: float) -> void:
	if objective != SquadObjective.PATROL:
		return
	if patrol_route == null or patrol_route.points.is_empty():
		return
	# Fighting takes priority. _disengage_and_resume re-issues the current leg.
	if context == SquadContext.ENGAGED:
		return

	if _patrol_dwell_t > 0.0:
		_patrol_dwell_t = maxf(0.0, _patrol_dwell_t - delta)
		return

	var point := patrol_route.point_at(patrol_index)
	if point == null:
		return
	if get_center().distance_to(point.global_position) > patrol_arrive_distance:
		return

	var stepped: Array = patrol_route.advance(patrol_index, _patrol_forward)
	patrol_index = stepped[0]
	_patrol_forward = stepped[1]
	_patrol_dwell_t = patrol_dwell
	var next_point := patrol_route.point_at(patrol_index)
	if next_point != null:
		objective_position = next_point.global_position
		_issue_patrol_orders(true)


func _issue_patrol_orders(force: bool = false) -> void:
	for ai in get_orderable_members():
		ai.always_active = true
		if ai is Soldier:
			ai.defensive_mode = false
			ai.order_move_to(objective_position + _formation_offset(ai), force)
			ai.change_soldier_state(Soldier.SoldierState.NONE)
		else:
			ai.move_to(objective_position + _formation_offset(ai))


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
		var robot := ai as Enemy
		# COMBAT alone is NOT enough. A robot whose target has been downed sits
		# in COMBAT with a dead reference, and the old check read that as an
		# ongoing firefight — so CONTACT never cleared and the squad stayed
		# engaged with nothing to shoot. Require an actual live target.
		if robot.has_live_target():
			return true
		# SEARCH still counts: someone hunting a target they just lost sight of
		# is in contact by any sane reading. It times out on its own.
		if robot.ai_state == Enemy.AIState.SEARCH:
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
	# The squad owns this robot's movement now. Without this they keep running
	# idle wander and individual patrol underneath every order we give.
	if ai is Enemy:
		(ai as Enemy).squad_directed = true
	if ai.has_signal("combat_triggered") and not ai.is_connected("combat_triggered", _on_combat_triggered):
		ai.connect("combat_triggered", _on_combat_triggered)
	if ai is Soldier and not ai.is_connected("bound_step_complete", _on_bound_step_complete):
		ai.connect("bound_step_complete", _on_bound_step_complete)

func _disconnect_member(ai: Node) -> void:
	if ai == null:
		return
	# Hand them back their own behaviour.
	if ai is Enemy:
		(ai as Enemy).squad_directed = false
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
# Any new objective invalidates the old posts, including a DEFEND re-issued at a
# different position — otherwise they walk back to where they were last time.
func _clear_defend_posts() -> void:
	_defend_posts.clear()


func set_objective(
	new_objective: SquadObjective,
	position: Vector3 = Vector3.ZERO,
	force: bool = false
) -> void:
	# Posts belong to the previous order. A DEFEND re-issued at a new position
	# must not send everyone back to where they stood last time.
	if new_objective != objective or not position.is_equal_approx(objective_position):
		_clear_defend_posts()

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
		SquadObjective.FOLLOW:
			_last_follow_issue = objective_position
			_issue_follow_orders()
		SquadObjective.PATROL:
			_issue_patrol_orders(force)


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
	# Near the objective this vector collapses and its direction becomes noise,
	# spinning every slot around. Fall back to the latched follow heading (or a
	# fixed axis) so the formation holds its shape when the squad has arrived.
	if advance_dir.length_squared() < 0.25:
		if _follow_heading.length_squared() > 0.01:
			advance_dir = _follow_heading
		else:
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

	# FOLLOW has no world position — it tracks a node. Route it through follow()
	# so the leader gets stored and the anchor is computed rather than frozen.
	if order == SquadObjective.FOLLOW:
		return

	# Any other order cancels a follow.
	follow_leader = null

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

	_defend_posts.clear()

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
			_defend_posts[soldier] = cp.global_position
		else:
			# More soldiers than cover points — spread in a ring around objective
			var angle = (TAU / soldiers.size()) * i
			var spread = Vector3(cos(angle), 0, sin(angle)) * 6.0
			soldier.order_move_to(objective_position + spread)
			_defend_posts[soldier] = objective_position + spread

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
	# FOLLOW squads escort; they don't run a bounding assault away from the
	# player. Same static roles a defending squad uses.
	if objective == SquadObjective.FOLLOW:
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
