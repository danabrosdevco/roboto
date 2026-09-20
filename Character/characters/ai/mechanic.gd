extends Soldier

# ─────────────────────────────────────────────
# MECHANIC — the frame that repairs.
#
# A welder where the gun goes. It brings downed squadmates back first, then
# patches up the damaged — vehicles first, since they have the most to put back
# — and otherwise keeps behind its squad. It never fights: it has nothing to
# fight with, and every second spent in a firefight is a second nobody is being
# fixed.
#
# The AI repair kit is deliberately NOT a revive: bringing a downed squadmate
# back was left to the player, so an AI would not quietly undo your losses. The
# Mechanic is the price of changing that. It takes a seat, it has no gun, and it
# has to walk out to the wreck and stand over it while it works.
#
# It is NOT marked for the enemy to shoot first. It was (target_priority), and in
# the valley lab it went down inside two seconds of every fight, before anyone
# needed fixing. It lives by walking at the back of its squad (formation_trail,
# on its scene) and keeping behind it once there is shooting.
#
# Healing goes through apply_healing(), the same call the repair tool and the
# kit use, so a downed robot stands up at revive_at_fraction exactly as it does
# for you, and the playtest log credits the Mechanic with it. The rover counts:
# it is in the other team, but a squadmate is a squadmate.
# ─────────────────────────────────────────────

@export_group("Welder")
## Health put back per second, on a squadmate standing or down.
@export var weld_per_second: float = 15.0
## How close it works from, measured to the edge of the patient — a rover is
## reached at its flank, not at its middle.
@export var weld_reach: float = 1.3
## How far it will go for someone.
@export var search_radius: float = 40.0
## Hurt enough to be worth a trip: below this share of full health.
@export var patch_below: float = 0.8
## Keeps welding a standing patient up to this share, then moves on. Above
## patch_below, so it does not flit between two robots at 79% and 81%.
@export var patch_to: float = 0.95
## Once it is this near, the patient stands still to be worked on: a squadmate
## that keeps walking is the commonest reason a repair never happens. The
## player's own repair tool holds allies for the same reason
## (PlayerRepairTool.assist_allies). Held robots still shoot.
@export var hold_within: float = 12.0
## A wreck with an enemy standing this close to it waits: walking out to it
## would only add the Mechanic to the pile.
@export var enemy_standoff: float = 7.0
## Gives up on a patient it has not reached in this long (blocked, cut off by
## the fight) and leaves it a while before trying again.
@export var give_up_after: float = 12.0
@export var retry_after: float = 8.0
@export var think_interval: float = 0.3

@export_group("Keeping back")
## Metres behind its squad, on the side away from whatever the squad is
## fighting.
@export var hang_back: float = 7.0
## How long a sighting keeps it back after the thing is out of view.
@export var threat_memory: float = 8.0
## How far the ideal spot behind the squad has to drift before it is worth
## walking to a new one. The squad bounds forward and the thing it is keeping
## away from moves too, so that spot slides a metre or two every tick: chasing
## it exactly is what had a Mechanic pacing about for a whole firefight.
@export var back_slack: float = 4.0
## How near that spot counts as behind them.
@export var back_arrive: float = 3.5
## Least time between two keep-back moves.
@export var back_recommit: float = 2.0

@export_group("Parts")
## A SparkBurst at the welder's tip, fired while it works.
@export var weld_sparks: Node3D
@export var weld_loop: AudioStreamPlayer3D
## Played when someone stands back up.
@export var weld_done: AudioStreamPlayer3D
@export var spark_interval: float = 0.22

## What it has done, for the lab and the playtest log. `revives` is Enemy's
## now — apply_healing() counts one for whoever got a robot back on its feet,
## whether that was a mechanic, a reclaimer or the player's repair tool, so
## this one kept its own tally and got credited twice for the same weld.
var repaired: int = 0

var _patient: Enemy = null
var _welding := false
var _weld_carry := 0.0
var _think_t := 0.0
var _spark_t := 0.0
var _approach_t := 0.0
var _skip_until: Dictionary = {}   # instance id -> _clock time it may be picked again
# Game seconds, so a lab run at 4x gives up and retries on the same beat.
var _clock := 0.0
var _walk_goal := Vector3.INF
# Untyped so .alive can be read: an Enemy or the player, and no type the two
# share declares it.
var _threat = null
var _threat_t := 0.0
# The squad's last move order, kept while it is busy or keeping back.
var _standing_order := Vector3.INF
# Whoever is being held still for the welder, so the hold is released exactly
# once and by whoever took it.
var _held: Enemy = null
# The spot behind the squad it settled on, and the wait before it will pick a
# new one.
var _back_spot := Vector3.INF
var _back_t := 0.0
var _standing_force := false


func _ready() -> void:
	# Before super(), which starts the brain in it. The frames' default is
	# COMBAT, which has a welder rolling attack moves at nothing; see
	# change_ai_state.
	DefaultAIState = AIState.IDLE
	super()


# ─────────────────────────────────────────────
# NEVER A FIGHTER
# ─────────────────────────────────────────────
# Every way into COMBAT ends up here or in trigger_combat. COMBAT is where the
# brain rolls advances, chases and fire; for something holding a welder, that is
# walking into the enemy.
func change_ai_state(new_state: AIState):
	super(AIState.IDLE if new_state == AIState.COMBAT else new_state)


# Seeing something is still worth telling the squad: it rallies on the same
# signal a rifleman sends. The Mechanic only notes where the threat is, to keep
# away from it.
func trigger_combat(body: AI) -> void:
	# Same guards as Enemy.trigger_combat: nothing there, or already down.
	if body == null or not is_instance_valid(body) or not body.alive or not _is_hostile(body):
		return
	var fresh := _threat_t <= 0.0
	_threat = body
	_threat_t = threat_memory
	# What the squad reads off a member that calls contact. Never fired at.
	combat_target = body
	# Once: the squad answers by calling trigger_combat on everyone, this
	# included, and the timer is what stops that echoing back.
	if fresh:
		combat_triggered.emit(self)


# No part in fire and manoeuvre: nothing to suppress with, and bounding forward
# is the opposite of the job.
func assign_role(_role: SoldierRole) -> void:
	squad_role = SoldierRole.NONE


# Mid-job the squad's orders wait: pulled off a half-welded wreck by a
# formation correction, nobody would ever be finished. In a fight it keeps
# behind the squad instead of walking where the squad walks (_keep_back); either
# way the order is kept, and carried out when it is free.
func order_move_to(pos: Vector3, force: bool = false, keep_target: bool = false) -> void:
	# Welding ITSELF is no reason to stand still: it is always in its own
	# reach, so it can carry the order out and patch its plating on the way.
	if (_patient != null and _patient != self) or _keeping_back():
		_standing_order = pos
		_standing_force = force
		return
	_standing_order = Vector3.INF
	_walk_goal = Vector3.INF
	super(pos, force, keep_target)


func enter_cover_seeking() -> void:
	# Not while it has someone to fix: cover is for waiting, and it is working.
	if _patient != null:
		return
	super()


func _desired_facing() -> Vector3:
	if _welding and is_instance_valid(_patient):
		var d := _patient.global_position - global_position
		d.y = 0.0
		if d.length_squared() > 0.0001:
			return d.normalized()
	return super()


# ─────────────────────────────────────────────
# THE JOB
# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	super(delta)
	# Down, asleep or jammed: nothing to weld with. Ordinary states rather than
	# faults, and this runs every frame, so they pass without a warning.
	if not alive or not frame_waited or ai_state == AIState.PASSIVE \
			or get_signal_state() == SignalState.EKILL:
		_stop_welding()
		_release_patient()
		_patient = null
		return
	_clock += delta
	_threat_t = maxf(0.0, _threat_t - delta)
	_back_t = maxf(0.0, _back_t - delta)
	_think_t -= delta
	var thinking := _think_t <= 0.0
	if thinking:
		_think_t = think_interval
		_choose_patient()
		if _patient == null:
			_keep_back()
	if _patient != null:
		_tend(delta, thinking)


# Down first, whoever they are. Then vehicles, which have the most to put back.
# Then the worst hurt. Distance orders each band.
#
# Once it has someone it finishes them, unless someone else falls into a more
# urgent band. Re-ranking everyone each tick had it walking back and forth
# between two hurt rifles: welding one lifted it above the other, every time.
func _choose_patient() -> void:
	var best: Enemy = null
	var best_score := INF
	if _needs_work(_patient):
		best = _patient
		best_score = _band(_patient) * 10000.0 - 1.0
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == _patient or not _needs_work(e):
			continue
		if float(_skip_until.get(e.get_instance_id(), 0.0)) > _clock:
			continue   # recently given up on
		if _under_fire(e.global_position):
			continue
		var band := _band(e)
		var d := global_position.distance_to(e.global_position)
		var within := d if band < 2 else _frac(e) * 100.0 + d * 0.1
		var score := band * 10000.0 + within
		if score < best_score:
			best_score = score
			best = e
	_set_patient(best)


# A squadmate within reach who is down, or hurt enough: below patch_below to
# be taken on, and kept on until patch_to.
func _needs_work(e: Enemy) -> bool:
	if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
		return false
	if _is_hostile(e) or (not e.downed and not e.alive):
		return false   # the other side, or destroyed outright: nothing to weld
	if global_position.distance_to(e.global_position) > search_radius:
		return false
	if e.downed:
		return true
	return _frac(e) < (patch_to if e == _patient else patch_below)


# ITSELF LAST. It carries the only welder in the squad, so every second it
# spends on its own plating is a second nobody else is being fixed — but a
# Mechanic that limps out of a fight at a third health and cannot do anything
# about it is the one robot in the squad with no excuse.
func _band(e: Enemy) -> int:
	if e == self:
		return 3
	return 0 if e.downed else (1 if _is_vehicle(e) else 2)


func _frac(e: Enemy) -> float:
	return float(e.health) / float(maxi(1, e.max_health))


func _set_patient(p: Enemy) -> void:
	if p == _patient:
		return
	_stop_welding()
	_patient = p
	_approach_t = 0.0
	_walk_goal = Vector3.INF
	if p == null:
		_release_patient()
		_resume_orders()


func _tend(delta: float, thinking: bool) -> void:
	if not is_instance_valid(_patient) or (not _patient.downed and not _patient.alive):
		_set_patient(null)
		return
	# Near enough to work on it: stand still. Further off it carries on with the
	# fight — a squadmate frozen while the welder is still forty metres away is
	# a squadmate taken out of the fight for nothing.
	_hold_patient(_patient if _gap_to(_patient) <= hold_within else null)
	if _patient != self and _gap_to(_patient) > weld_reach:
		_stop_welding()
		_approach_t += delta
		if _approach_t > give_up_after:
			# Could not get there. Leave it to the player, or to later.
			_skip_until[_patient.get_instance_id()] = _clock + retry_after
			_set_patient(null)
			return
		# Re-aimed on the think tick only, and only when the spot has moved or
		# the walk stopped: a move_to every frame resets the stuck checks.
		if thinking:
			var goal := _beside(_patient)
			if movement_state != MovementState.MOVING or _walk_goal == Vector3.INF \
					or _walk_goal.distance_to(goal) > 1.0:
				_walk_goal = goal
				move_to(goal)
		return

	_approach_t = 0.0
	if not _welding:
		_start_welding()
	if _patient != self and movement_state != MovementState.NONE:
		halt()
		_walk_goal = Vector3.INF
	if not _tool_on(_patient):
		return   # still bringing the tool round to it: nothing is welded until it is there
	_weld_carry += weld_per_second * delta
	var whole := int(_weld_carry)
	if whole > 0:
		_weld_carry -= whole
		var was_down := _patient.downed
		var before := _patient.health
		_patient.apply_healing(whole, self)
		repaired += maxi(0, _patient.health - before)
		if was_down and not _patient.downed:
			# The count itself happened inside apply_healing; this is the noise
			# it makes when one stands back up.
			if weld_done != null:
				weld_done.play()
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = spark_interval
		if weld_sparks != null and weld_sparks.has_method("activate"):
			weld_sparks.activate()
	if not _patient.downed and float(_patient.health) >= float(_patient.max_health) * patch_to:
		_set_patient(null)
		_think_t = 0.0   # straight on to the next one


# Whether the welder is on the patient yet. The Mechanic holds it in its hands,
# so it is there as soon as the Mechanic is; a frame that has to reach first
# says otherwise.
func _tool_on(_p: Enemy) -> bool:
	return true


# Holding a patient still, and letting it go. Paired: hold_still/release_hold
# is a counter on the robot, so one of ours must answer exactly one of theirs.
func _hold_patient(p: Enemy) -> void:
	if p == _held:
		return
	_release_patient()
	if p == null or p == self or not is_instance_valid(p) or p.downed or not p.alive:
		return   # nothing to hold, or already on the floor and going nowhere
	_held = p
	p.hold_still()


func _release_patient() -> void:
	if _held == null:
		return   # holding nobody
	if is_instance_valid(_held):
		_held.release_hold()
	_held = null


func _start_welding() -> void:
	_welding = true
	_weld_carry = 0.0
	_spark_t = 0.0
	if weld_loop != null and not weld_loop.playing:
		weld_loop.play()


func _stop_welding() -> void:
	if not _welding:
		return
	_welding = false
	if weld_loop != null:
		weld_loop.stop()


# Back to what the squad last wanted, now that it is free — unless there is a
# fight on, in which case _keep_back places it.
func _resume_orders() -> void:
	_walk_goal = Vector3.INF
	if _keeping_back():
		return
	if _standing_order == Vector3.INF:
		halt()
		return
	var pos := _standing_order
	_standing_order = Vector3.INF
	super.order_move_to(pos, _standing_force, true)


# ─────────────────────────────────────────────
# KEEPING BACK
# ─────────────────────────────────────────────
# Behind its squad, on the far side from what the squad is fighting: close
# enough to reach whoever goes down, and not the nearest thing to shoot at.
func _keep_back() -> void:
	if not _keeping_back():
		_back_spot = Vector3.INF
		return   # no fight, or holding a post: the squad's orders stand
	var threat := _live_threat()
	# The robots it is with, not counting itself: measured from a centre that
	# included it, every step back moved the place it was stepping back to.
	var centre := squad.line_center()
	var away := centre - threat.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		return   # standing on the threat: any way is as good as another
	var want := NavigationServer3D.map_get_closest_point(nav_agent.get_navigation_map(),
		centre + away.normalized() * hang_back)
	# A new spot only when the old one is properly out of date.
	if _back_spot == Vector3.INF or _back_spot.distance_to(want) > back_slack:
		_back_spot = want
	if global_position.distance_to(_back_spot) < back_arrive:
		return   # near enough behind them
	if _back_t > 0.0:
		return   # moved recently: let that one finish before picking again
	if movement_state == MovementState.MOVING and _walk_goal != Vector3.INF and _walk_goal.distance_to(_back_spot) < 2.0:
		return   # already on its way there
	_back_t = back_recommit
	_walk_goal = _back_spot
	move_to(_back_spot)


# In a fight, and not holding a post. A squad told to hold puts everyone in
# cover, the Mechanic included, and that is the better place to wait.
func _keeping_back() -> bool:
	if squad == null or not is_instance_valid(squad):
		return false
	if squad.objective == Squad.SquadObjective.DEFEND:
		return false
	return _live_threat() != null


func _live_threat() -> Node3D:
	if _threat_t > 0.0 and _threat != null and is_instance_valid(_threat) and _threat.alive:
		return _threat as Node3D
	if squad != null and is_instance_valid(squad) and squad.has_live_contact():
		var t = squad.squad_combat_target
		if t != null and is_instance_valid(t) and t.alive:
			return t
	return null


# ─────────────────────────────────────────────
# MEASURING
# ─────────────────────────────────────────────
func _is_vehicle(e: Enemy) -> bool:
	return e is Soldier and not (e as Soldier).takes_cover()


func _under_fire(pos: Vector3) -> bool:
	if ai_manager == null:
		return false
	for ai in ai_manager.all_ai:
		if ai == null or not is_instance_valid(ai) or not (ai is Enemy):
			continue
		var e := ai as Enemy
		if e.alive and _is_hostile(e) and e.global_position.distance_to(pos) < enemy_standoff:
			return true
	return false


# From the Mechanic's side to the patient's collider, flat. The collider's
# world box, so a rover is measured to its flank and a wreck lying down to its
# length, not to a centre it could never stand on.
func _gap_to(p: Enemy) -> float:
	var box := _box_of(p)
	var q := Vector2(clampf(global_position.x, box.position.x, box.end.x),
		clampf(global_position.z, box.position.z, box.end.z))
	return Vector2(global_position.x, global_position.z).distance_to(q) - _own_radius()


# Where to stand to work on `p`: out from it towards where the Mechanic is, to
# the edge of its box that way, then its own radius and most of its reach
# again. To the edge that way, not by the box's longest side: a rover walked up
# to from the flank was stood off by half its length, just past weld_reach.
func _beside(p: Enemy) -> Vector3:
	var box := _box_of(p)
	var centre := box.get_center()
	var away := global_position - centre
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.BACK
	away = away.normalized()
	var spot := centre + away * (_edge_along(box, away) + _own_radius() + weld_reach * 0.4)
	return NavigationServer3D.map_get_closest_point(nav_agent.get_navigation_map(), spot)


# Centre of a world box to its edge, flat, going `dir`.
func _edge_along(box: AABB, dir: Vector3) -> float:
	var half := box.size * 0.5
	var flat := Vector2(dir.x, dir.z)
	if flat.length_squared() < 0.0001:
		return minf(half.x, half.z)   # no direction: the near side, whichever it is
	flat = flat.normalized()
	return minf(half.x / maxf(absf(flat.x), 0.001), half.z / maxf(absf(flat.y), 0.001))


func _box_of(p: Enemy) -> AABB:
	var cs: CollisionShape3D = p._collision_shape if p._collision_shape != null else p._find_collision_shape()
	if cs == null or cs.shape == null:
		return AABB(p.global_position - Vector3(0.5, 1.0, 0.5), Vector3(1.0, 2.0, 1.0))
	return cs.global_transform * p._shape_box(cs.shape)


func _own_radius() -> float:
	var cs: CollisionShape3D = _collision_shape if _collision_shape != null else _find_collision_shape()
	if cs == null or cs.shape == null:
		return 0.5
	var box := _shape_box(cs.shape)
	return minf(box.size.x, box.size.z) * 0.5


## Welding someone right now: what the HUD roster says it is doing.
func is_repairing() -> bool:
	return _welding
