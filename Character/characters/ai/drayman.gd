extends "res://Character/characters/ai/rover.gd"

# ─────────────────────────────────────────────
# DRAYMAN — the frame that restocks.
#
# A six-wheeled truck with a folding boom where a gun would go. It drives up to
# squadmates who have spent their equipment and hands them a charge back.
#
# WHAT IT RESTORES, AND WHY NOT AMMUNITION. The design doc this frame was
# approved from had it refilling magazines. There is nothing to refill:
# AIWeapon._finish_reload() ends with `magazine_current = magazine_size` and
# there is no reserve anywhere in ai_weapon.gd, so squad ammunition is already
# infinite and a frame that "topped it up" would have had no observable effect
# at all. AmmoPool/AmmoStock are player-side only.
#
# The one consumable in the game with no way back was AIEquipmentSlot: it had
# initialize(), has_uses(), consume() and remaining(), and nothing that added.
# Once the squad's smoke was thrown it was gone for the mission. That is this
# frame's job, and AIEquipmentSlot.restore() is the single line of shared API it
# needed.
#
# IT CARRIES ITS OWN KIT TOO, four slots of it — more than anything else in the
# game. restore() is slot-for-slot, not by item id, so the Drayman does NOT
# have to be carrying smoke in order to refill somebody's smoke; its own slots
# are therefore free to be whatever the squad is short of, and _tick_equipment
# (which only runs in COMBAT, on a non-empty array) is the only way an unarmed
# truck contributes to a firefight at all.
#
# IT IS NOT A FIGHTER AND NOT A MEDIC. No weapon, no mount contents, no aim or
# fire machine — handle_weapon_logic is `pass`, the same stub spotter_drone.gd
# ships. The welding/salvage/mortar brains on reclaimer.gd are deliberately not
# inherited: this extends Rover, so it gets Ackermann steering, reverse,
# whisker blocking, pack spacing, suspension and the vehicle wreck pose, and
# nothing it would have to switch off. The shape of the job — think clock,
# choose, approach, channel, hang back — is copied from mechanic.gd by hand.
#
# IT LIVES BY STAYING OUT OF IT. formation_trail on the scene puts it further
# back than the Mechanic, and _keep_back() walks it to the far side of the
# squad from whatever the squad is fighting. target_priority is left alone: the
# Mechanic's note records what marking a support frame cost.
# ─────────────────────────────────────────────

@export_group("Boom")
## Uses handed back per completed hand-over. One, so the decision is "who",
## not "how much".
@export var charges_per_load: int = 1
## How long a hand-over takes, standing still beside the customer. Long enough
## that doing it inside a firefight is a choice.
@export var hand_over_seconds: float = 2.5
## How close it works from, measured to the edge of the customer's collider — a
## rover is reached at its flank, not at its middle. The Mechanic's weld_reach.
@export var hand_reach: float = 1.6
## How far it will go for someone.
@export var search_radius: float = 40.0
## Once it is this near, the customer stands still to be worked on. A squadmate
## that keeps walking is the commonest reason a hand-over never happens.
@export var hold_within: float = 12.0
## A customer with an enemy standing this close waits: driving out to it would
## only add a truck to the pile.
@export var enemy_standoff: float = 7.0
## Gives up on a customer it has not reached in this long (blocked, cut off by
## the fight) and leaves it a while before trying again.
@export var give_up_after: float = 12.0
@export var retry_after: float = 8.0
@export var think_interval: float = 0.3

@export_group("Load")
## HOW MANY HAND-OVERS IT HAS IN IT. An infinite resupply frame is not a
## decision — you would simply always bring one. This number is a GUESS and
## cannot be judged without playing: it is the first thing to retune.
@export var loads: int = 8
## Crates on the bed are hidden as the load goes down, so the frame's state is
## readable from outside without a HUD element. Rig/Load holds twelve
## Crate*/Lid* pairs (build_drayman.gd); naming them here would be twelve
## NodePaths in the scene for nothing.
@export var deplete_crates: bool = true

@export_group("Keeping back")
## Metres behind its squad, on the side away from whatever the squad is
## fighting. Further than the Mechanic's: it is bigger and has less reason to
## be near the line.
@export var hang_back: float = 9.0
## How long a sighting keeps it back after the thing is out of view.
@export var threat_memory: float = 8.0
## How far the ideal spot behind the squad has to drift before it is worth
## driving to a new one. That spot slides a metre or two every tick as the
## squad bounds forward, and chasing it exactly is how the Mechanic ended up
## pacing about for a whole firefight.
@export var back_slack: float = 5.0
## How near that spot counts as behind them. A truck's arrival radius, not a
## rifleman's.
@export var back_arrive: float = 4.5
## Least time between two keep-back moves.
@export var back_recommit: float = 2.0

@export_group("Parts")
## A SparkBurst at the boom's tip, fired while it works.
@export var hand_sparks: Node3D
@export var hand_loop: AudioStreamPlayer3D
## Played when a charge lands.
@export var hand_done: AudioStreamPlayer3D
@export var spark_interval: float = 0.22

## Charges handed back this mission, for the lab and the playtest log.
var restocked: int = 0

var _customer: Enemy = null
var _slot_index: int = -1
var _handing := false
var _hand_carry := 0.0
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
var _standing_force := false
# Whoever is being held still for the boom, so the hold is released exactly
# once and by whoever took it.
var _held: Enemy = null
# The spot behind the squad it settled on, and the wait before it will pick a
# new one.
var _back_spot := Vector3.INF
var _back_t := 0.0
var _loads_left := 0
# Said once per mission, not once per think tick.
var _warned_empty := false
# Crate tags in bed order, and the meshes each tag owns (the crate and its lid).
var _crates: Array[String] = []
var _crate_parts: Dictionary = {}


func _ready() -> void:
	_loads_left = maxi(0, loads)
	super()
	_collect_crates()
	_show_load()


## What is left in the bed. Public because `loads` is an authored maximum and
## the remainder is the only thing that answers "is this frame still useful".
func loads_left() -> int:
	return _loads_left


## Handing a charge over right now: what the HUD roster says it is doing, the
## same way Mechanic.is_repairing() reads.
func is_restocking() -> bool:
	return _handing


# ─────────────────────────────────────────────
# NO WEAPON
# ─────────────────────────────────────────────
# There is nothing on the mount and there never will be: starting_weapon_id is
# empty on the chassis, and every vehicle-legal gun in the catalogue carries a
# chassis_whitelist that excludes this frame. So the IDLE → AIM → FIRE machine
# is a state machine running for nothing, every tick, on every body.
# spotter_drone.gd:175 is the shipped example of exactly this stub.
func handle_weapon_logic(_delta: float) -> void:
	pass


# Nothing should ever read as on-target. Rover's version measures the turret
# bearing against weapon_target, and build_drayman.gd zeroed the traverse and
# elevation on purpose — so left alone this would answer "yes, always", on a
# frame with nothing to say yes about.
func _weapon_on_target() -> bool:
	return false


# THE DICE DO NOT OUTRANK THE JOB. AllowedCombatOptions is [MOVE] and
# AllowedMovementOptions is [ADVANCE, FALLBACK] on the scene — non-empty, because
# an empty combat array makes roll_combat_action return at enemy.gd:3053 and
# that is a defect, not a configuration. But ADVANCE calls
# move_to(find_advance_target()) directly (enemy.gd:3941), which is a truck
# driving at a rifleman, and it would also stamp on the move_to this frame
# issues to reach a customer. So while there is work to do, or a live threat to
# keep away from, MOVE is refused here and _hand_over/_keep_back place the
# frame instead.
func perform_action(action: CombatOptions) -> void:
	if action == CombatOptions.MOVE and (_customer != null or _keeping_back()):
		return
	super(action)


# Seeing something is still worth telling the squad: it rallies on the same
# signal a rifleman sends. The Drayman only notes where the threat is, to keep
# away from it. Copied from mechanic.gd:132 — same guards, same echo timer.
func trigger_combat(body: AI) -> void:
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


# Mid-job the squad's orders wait: pulled off a half-finished hand-over by a
# formation correction, nobody would ever be restocked. In a fight it keeps
# behind the squad instead of driving where the squad drives (_keep_back);
# either way the order is kept, and carried out when it is free.
func order_move_to(pos: Vector3, force: bool = false, keep_target: bool = false,
		think_delay: float = 0.0) -> void:
	# Restocking ITSELF is no reason to stand still: it is always in its own
	# reach, so it can carry the order out and work on the way.
	if (_customer != null and _customer != self) or _keeping_back():
		_standing_order = pos
		_standing_force = force
		return
	_standing_order = Vector3.INF
	_walk_goal = Vector3.INF
	super(pos, force, keep_target, think_delay)


# Rover already stubs this to SoldierState.NONE and takes_cover() to false — a
# 3.3 m truck is not sent to a cover point. This adds only the one case Rover
# cannot know about: not while there is someone to restock.
func enter_cover_seeking() -> void:
	if _customer != null:
		return
	super()


# ─────────────────────────────────────────────
# THE JOB
# ─────────────────────────────────────────────
# A _physics_process with a clock, not a new _process: CLAUDE.md forbids the
# latter outright, and the think_interval throttle is mechanic.gd's idiom.
# super(delta) FIRST or the frame stops driving — Rover's steering, suspension
# and wreck pose all live in its own _physics_process.
func _physics_process(delta: float) -> void:
	super(delta)
	# Down, asleep or jammed: nothing to hand anything with. Ordinary states
	# rather than faults, and this runs every frame, so they pass without a
	# warning.
	if not alive or not frame_waited or ai_state == AIState.PASSIVE \
			or get_signal_state() == SignalState.EKILL:
		_stop_handing()
		_release_customer()
		_customer = null
		_slot_index = -1
		return
	_clock += delta
	_threat_t = maxf(0.0, _threat_t - delta)
	_back_t = maxf(0.0, _back_t - delta)
	_think_t -= delta
	var thinking := _think_t <= 0.0
	if thinking:
		_think_t = think_interval
		_choose_customer()
		if _customer == null:
			_keep_back()
	if _customer != null:
		_hand_over(delta, thinking)


# WHO IS DRY. mechanic.gd:219's shape with a different question: not "who is
# hurt" but "whose equipment slot has been spent". Fully spent slots first,
# because a robot with no smoke at all is the one that cannot answer an order;
# then partly spent; distance orders each band. ITSELF LAST, for the same
# reason the Mechanic patches its own plating last.
#
# Once it has someone it finishes them, unless someone else falls into a more
# urgent band. Re-ranking everyone each tick is what had the Mechanic walking
# back and forth between two patients.
#
# THE SQUAD WILL NEVER ASK. AIEquipment.EquipmentContext has no "I am low"
# field and _score_combat_option's low_ammo is local to the robot scoring it, so
# polling is the only way — which is exactly why the search_radius/_skip_until
# idiom is the right one to copy.
func _choose_customer() -> void:
	if _loads_left <= 0:
		# EMPTY, AND IT SAYS SO. A Drayman that has silently stopped working is
		# the most expensive bug shape in this project; the frame is still
		# worth having on the field for its own four slots, so it keeps
		# driving rather than switching itself off.
		if not _warned_empty:
			_warned_empty = true
			push_warning("%s has handed out all %d of its loads: it will not restock anyone else this mission." % [name, loads])
		_set_customer(null, -1)
		return
	var best: Enemy = null
	var best_slot := -1
	var best_score := INF
	if _customer != null:
		var keep := _driest_slot(_customer)
		if keep >= 0:
			best = _customer
			best_slot = keep
			best_score = _band(_customer, keep) * 10000.0 - 1.0
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e == _customer:
			continue
		var slot := _driest_slot(e)
		if slot < 0:
			continue
		if float(_skip_until.get(e.get_instance_id(), 0.0)) > _clock:
			continue   # recently given up on
		if _under_fire(e.global_position):
			continue
		var score := _band(e, slot) * 10000.0 + global_position.distance_to(e.global_position)
		if score < best_score:
			best_score = score
			best = e
			best_slot = slot
	_set_customer(best, best_slot)


# The slot most worth a charge on this robot, or -1 for nobody who needs one.
# REFUSES THE FULL, which is what stops a load being spent on a robot that has
# not thrown anything.
func _driest_slot(e: Enemy) -> int:
	if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
		return -1
	if not e.alive or e.downed:
		return -1   # a wreck is the Mechanic's problem, not the quartermaster's
	if e != self and _is_hostile(e):
		return -1
	if global_position.distance_to(e.global_position) > search_radius:
		return -1
	var best := -1
	var fewest := 0
	for i in e.equipment_slots.size():
		var slot: AIEquipmentSlot = e.equipment_slots[i]
		if slot == null or slot.quantity <= 0:
			continue
		var left := slot.remaining()
		if left >= slot.quantity:
			continue   # already full: no load goes here
		if best < 0 or left < fewest:
			best = i
			fewest = left
	return best


# 0 = spent dry, 1 = partly spent, 2 = itself. Itself last: it carries the only
# boom in the squad, and every second spent on its own crates is a second
# nobody else is being restocked.
func _band(e: Enemy, slot: int) -> int:
	if e == self:
		return 2
	var s: AIEquipmentSlot = e.equipment_slots[slot]
	return 0 if s.remaining() <= 0 else 1


func _set_customer(c: Enemy, slot: int) -> void:
	if c == _customer and slot == _slot_index:
		return
	if c != _customer:
		_stop_handing()
		_approach_t = 0.0
		_walk_goal = Vector3.INF
	_customer = c
	_slot_index = slot
	if c == null:
		_release_customer()
		_resume_orders()


# mechanic.gd:286's _tend, with a charge at the end instead of health per
# second. Approach, hold the customer still, channel for hand_over_seconds,
# then one restore() and one load off the bed.
func _hand_over(delta: float, thinking: bool) -> void:
	if _slot_index < 0 or not is_instance_valid(_customer) \
			or not _customer.alive or _customer.downed \
			or _slot_index >= _customer.equipment_slots.size():
		_set_customer(null, -1)
		return
	var slot: AIEquipmentSlot = _customer.equipment_slots[_slot_index]
	if slot == null or slot.remaining() >= slot.quantity:
		_set_customer(null, -1)   # somebody else filled it, or it was never short
		_think_t = 0.0
		return
	# Near enough to work on it: stand still. Further off it carries on with
	# whatever it was doing — a squadmate frozen while the truck is still forty
	# metres away is a squadmate taken out of the fight for nothing.
	_hold_customer(_customer if _gap_to(_customer) <= hold_within else null)
	if _customer != self and _gap_to(_customer) > hand_reach:
		_stop_handing()
		_approach_t += delta
		if _approach_t > give_up_after:
			# Could not get there. Leave it to later.
			_skip_until[_customer.get_instance_id()] = _clock + retry_after
			_set_customer(null, -1)
			return
		# Re-aimed on the think tick only, and only when the spot has moved or
		# the drive stopped: a move_to every frame resets Rover's stuck checks,
		# which is what pinned a rover to a wall for a whole fight.
		if thinking:
			var goal := _beside(_customer)
			if movement_state != MovementState.MOVING or _walk_goal == Vector3.INF \
					or _walk_goal.distance_to(goal) > 1.0:
				_walk_goal = goal
				move_to(goal)
		return

	_approach_t = 0.0
	if not _handing:
		_start_handing()
	if _customer != self and movement_state != MovementState.NONE:
		halt()
		_walk_goal = Vector3.INF
	if not _tool_on(_customer):
		return   # still bringing the boom round: nothing is handed over until it is there
	_hand_carry += delta
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = spark_interval
		if hand_sparks != null and hand_sparks.has_method("activate"):
			hand_sparks.activate()
	if _hand_carry < hand_over_seconds:
		return
	_hand_carry = 0.0
	slot.restore(charges_per_load)
	restocked += charges_per_load
	_loads_left = maxi(0, _loads_left - 1)
	_show_load()
	if hand_done != null:
		hand_done.play()
	# Straight on to the next one, or back to this one's other empty slot.
	_set_customer(null, -1)
	_think_t = 0.0


# Whether the boom is on the customer yet. The Mechanic holds its welder in its
# hands and so answers true as soon as it has arrived; the Reclaimer's boom has
# to swing first. THIS BOOM IS AUTHORED ON THE BODY and does not articulate at
# runtime — build_drayman.gd:139-161 zeroed turret_traverse_degrees and
# gun_elevation_degrees on purpose, so Rover's aiming code is a no-op every
# frame and there is nothing to wait for. Kept as a seam because that is the
# one thing most likely to change if the arm is ever animated.
func _tool_on(_c: Enemy) -> bool:
	return true


# Holding a customer still, and letting it go. Paired: hold_still/release_hold
# is a counter on the robot, so one of ours must answer exactly one of theirs.
func _hold_customer(c: Enemy) -> void:
	if c == _held:
		return
	_release_customer()
	if c == null or c == self or not is_instance_valid(c) or c.downed or not c.alive:
		return
	_held = c
	c.hold_still()


func _release_customer() -> void:
	if _held == null:
		return   # holding nobody
	if is_instance_valid(_held):
		_held.release_hold()
	_held = null


func _start_handing() -> void:
	_handing = true
	_hand_carry = 0.0
	_spark_t = 0.0
	if hand_loop != null and not hand_loop.playing:
		hand_loop.play()


func _stop_handing() -> void:
	if not _handing:
		return
	_handing = false
	_hand_carry = 0.0
	if hand_loop != null:
		hand_loop.stop()


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
# THE LOAD, VISIBLY
# ─────────────────────────────────────────────
# Twelve crates on the bed, hidden a course at a time as the load goes down.
# The Vessel's bay makes the same argument: a frame whose remaining usefulness
# is readable from outside needs no HUD element to say so.
# Crate000 and Lid000 are ONE box and must go together, so the bed is gathered
# as boxes keyed by the three-digit tag build_drayman.gd writes, not as a flat
# list of meshes. A crate standing on the bed with no lid is not a half-empty
# truck, it is a modelling error.
func _collect_crates() -> void:
	_crates.clear()
	var bed := get_node_or_null(^"Rig/Load")
	if bed == null:
		push_warning("%s has no Rig/Load: the crates cannot show what is left in it." % name)
		return
	var by_tag: Dictionary = {}
	for c in bed.get_children():
		if not (c is Node3D):
			continue
		var nm := String(c.name)
		var tag := ""
		if nm.begins_with("Crate"):
			tag = nm.substr(5)
		elif nm.begins_with("Lid"):
			tag = nm.substr(3)
		else:
			continue
		if not by_tag.has(tag):
			by_tag[tag] = []
			_crates.append(tag)
		(by_tag[tag] as Array).append(c)
	_crate_parts = by_tag


func _show_load() -> void:
	if not deplete_crates or _crates.is_empty():
		return
	var full := maxi(1, loads)
	var share := clampf(float(_loads_left) / float(full), 0.0, 1.0)
	# ceil, so the bed only reads empty when the frame actually is: a truck
	# showing bare planks while it still has a load to give would be a lie the
	# player would plan around.
	var keep := int(ceil(float(_crates.size()) * share))
	for i in _crates.size():
		for part in (_crate_parts[_crates[i]] as Array):
			(part as Node3D).visible = i < keep


# ─────────────────────────────────────────────
# KEEPING BACK
# ─────────────────────────────────────────────
# Behind its squad, on the far side from what the squad is fighting: close
# enough to reach whoever runs dry, and not the nearest thing to shoot at.
# mechanic.gd:437's loop, unchanged except for the distances.
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
	# Direct: _back_spot below is the throttle, and a refused snap would cache
	# a wrong spot the same way the squad's formation slots did.
	var want := NavigationServer3D.map_get_closest_point(nav_agent.get_navigation_map(),
		centre + away.normalized() * hang_back)
	# A new spot only when the old one is properly out of date.
	if _back_spot == Vector3.INF or _back_spot.distance_to(want) > back_slack:
		_back_spot = want
	if global_position.distance_to(_back_spot) < back_arrive:
		return   # near enough behind them
	if _back_t > 0.0:
		return   # moved recently: let that one finish before picking again
	if movement_state == MovementState.MOVING and _walk_goal != Vector3.INF \
			and _walk_goal.distance_to(_back_spot) < 2.0:
		return   # already on its way there
	_back_t = back_recommit
	_walk_goal = _back_spot
	move_to(_back_spot)


# In a fight, and not holding a post. A squad told to hold puts everyone in
# cover, the truck included, and that is the better place to wait.
func _keeping_back() -> bool:
	if squad == null or not is_instance_valid(squad):
		return false
	if nav_agent == null:
		return false   # nowhere to snap a spot to; _keep_back would fault on it
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


# Facing the customer while it works, so the boom is pointed at the thing it is
# handing to. Rover owns the hull/turret split otherwise, and _update_facing is
# deliberately NOT overridden: build_drayman.gd zeroed the traverse so the
# aiming code cannot give a supply truck a tracking arm.
func _desired_facing() -> Vector3:
	if _handing and is_instance_valid(_customer) and _customer != self:
		var d := _customer.global_position - global_position
		d.y = 0.0
		if d.length_squared() > 0.0001:
			return d.normalized()
	return super()


# ─────────────────────────────────────────────
# MEASURING
# mechanic.gd's geometry, which measures to a collider's world box rather than
# to a centre: a rover is reached at its flank, not at a point under its roof.
# ─────────────────────────────────────────────
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


func _gap_to(c: Enemy) -> float:
	var box := _box_of(c)
	var q := Vector2(clampf(global_position.x, box.position.x, box.end.x),
		clampf(global_position.z, box.position.z, box.end.z))
	return Vector2(global_position.x, global_position.z).distance_to(q) - _own_radius()


# Where to stand to work on `c`: out from it towards where the Drayman is, to
# the edge of its box that way, then its own radius and most of its reach
# again.
func _beside(c: Enemy) -> Vector3:
	var box := _box_of(c)
	var centre := box.get_center()
	var away := global_position - centre
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.BACK
	away = away.normalized()
	var spot := centre + away * (_edge_along(box, away) + _own_radius() + hand_reach * 0.4)
	if nav_agent == null:
		return spot
	return NavigationServer3D.map_get_closest_point(nav_agent.get_navigation_map(), spot)


# Centre of a world box to its edge, flat, going `dir`.
func _edge_along(box: AABB, dir: Vector3) -> float:
	var half := box.size * 0.5
	var flat := Vector2(dir.x, dir.z)
	if flat.length_squared() < 0.0001:
		return minf(half.x, half.z)   # no direction: the near side, whichever it is
	flat = flat.normalized()
	return minf(half.x / maxf(absf(flat.x), 0.001), half.z / maxf(absf(flat.y), 0.001))


func _box_of(c: Enemy) -> AABB:
	var cs: CollisionShape3D = c._collision_shape if c._collision_shape != null else c._find_collision_shape()
	if cs == null or cs.shape == null:
		return AABB(c.global_position - Vector3(0.5, 1.0, 0.5), Vector3(1.0, 2.0, 1.0))
	return cs.global_transform * c._shape_box(cs.shape)


func _own_radius() -> float:
	var cs: CollisionShape3D = _collision_shape if _collision_shape != null else _find_collision_shape()
	if cs == null or cs.shape == null:
		return 0.5
	var box := _shape_box(cs.shape)
	return minf(box.size.x, box.size.z) * 0.5
