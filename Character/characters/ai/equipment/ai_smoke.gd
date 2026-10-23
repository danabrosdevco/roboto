extends AIEquipment

# BY PATH, NOT class_name: a brand-new class_name is not resolvable until the
# editor rescans, and that rescan must not be run with the editor open. The
# scene references this script by path, which needs no registration.

# ─────────────────────────────────────────────
# SMOKE — THROWN TO END A FIREFIGHT, NOT TO WIN ONE.
#
# Every other piece of AI kit answers "how do I hurt that". Smoke answers "how
# do I stop being shot", which is why running it on AIGrenade would have been
# worse than leaving it unusable: a grenade wants a target that is STATIONARY,
# CLUSTERED and BEHIND COVER at four to thirty metres, and a robot in that
# situation is winning. Smoke is for the opposite situation.
#
# It is a real tactical act here and not a cosmetic one, because smoke blocks
# AI sight: Enemy.is_path_clear() asks SmokeVolume.blocks_sight() after its ray
# comes back clear (enemy.gd, "SMOKE BLOCKS SIGHT AND NOTHING ELSE"), and every
# caller of that function is a sight question — can I see it, can I shoot it
# from that cover point, who shot me. A cloud on the sightline genuinely makes
# the squad harder to engage.
#
# THREE REASONS, AND NO FOURTH:
#
#   1. The squad is WITHDRAWING and we are under fire. The order is the signal.
#      Nobody needs to check whether the fight is going badly — the player or
#      the squad AI has already decided to leave, and leaving under fire without
#      a screen is how a withdrawal becomes a wipe.
#
#   2. A squadmate is DOWN within reach and we are under fire. A downed robot is
#      recoverable — a mechanic can stand it back up — but not while the thing
#      that dropped it still has the sightline. This is the one case where the
#      cloud goes on the casualty rather than toward the threat.
#
#   3. We are ADVANCING or ATTACKING across open ground, under fire from far
#      enough away to be shot at while we cross, AND we are losing the exchange.
#      This one needs the third clause and the others do not: an advancing robot
#      that dumps smoke every time a round lands near it empties its pouches in
#      the first thirty seconds of every mission.
#
# WHAT IT DELIBERATELY DOES NOT DO is require a combat_target. The robot that
# most needs a cloud is the one being shot from somewhere it cannot see, which
# is exactly the robot that has no target. `_evaluate_equipment_use` used to
# return early without one; it no longer does, and this is the equipment that
# change was made for.
# ─────────────────────────────────────────────

## The thrown canister. Not the cloud — the canister carries its own.
@export var canister_scene: PackedScene

## How far along the line to the threat the cloud goes. 0.6 puts a 7-metre cloud
## comfortably across the sightline without putting it in the threat's lap,
## where it would screen them and not us.
@export var screen_fraction: float = 0.6
## Clamps on where that lands. The lower bound keeps a cloud off our own feet at
## knife range — smoke you are standing inside blinds you as much as them, and
## at that distance the answer is the rifle. The upper bound is how far a robot
## can actually put one.
@export var min_screen_metres: float = 5.0
@export var max_screen_metres: float = 26.0

## How recently something has to have hit us to count as "under fire". All three
## reasons require it: a cloud thrown by a robot nobody is shooting at is a
## wasted canister and reads, in play, as the AI panicking at nothing.
@export var recent_fire_seconds: float = 2.5
## How close a downed squadmate has to be for reason 2. Beyond this it is
## somebody else's casualty and our own cloud does not reach them.
@export var rescue_radius: float = 12.0
## How far off the threat has to be for reason 3 to read as open ground rather
## than a firefight. Inside this, smoke is cover for a fight we are already in.
@export var crossing_min_metres: float = 14.0
## Below this fraction of hull we are losing reason 3's exchange.
@export var losing_health_fraction: float = 0.6
## ...or this many hostiles are standing on top of us. `nearby_hostiles` is a
## five-metre radius, so two is genuinely being swarmed and not a crowd.
@export var losing_hostile_count: int = 2

## Don't throw within this many seconds of a squadmate throwing anything. Four
## robots evaluating one bad moment on the same tick is how a squad answers it
## with four canisters. Longer than the deploy's spacing because one cloud
## covers a whole fireteam — the second one adds nothing.
@export var squad_spacing_seconds: float = 10.0

## Squad.SquadObjective, which is not visible from here. Named rather than
## written as bare ints at the comparison, because these are stored as ints in
## .tscn files and an append-only enum makes a magic 3 unreadable a year later.
const OBJ_ADVANCE := 1
const OBJ_WITHDRAW := 3
const OBJ_ATTACK := 4

const _Analytics := preload("res://Managers/analytics.gd")


func can_use(context: AIEquipment.EquipmentContext) -> bool:
	if canister_scene == null:
		# EVERY REFUSAL SAYS WHY. Smoke with nothing to throw would otherwise sit
		# in a slot looking like a decision the AI keeps making.
		push_warning("AISmoke '%s': no canister_scene, so it can never be used." % equipment_name)
		return false
	var owner_ai := context.owner_ai
	if owner_ai == null:
		push_warning("AISmoke '%s': asked with no owner in the context." % equipment_name)
		return false
	# Somebody in the squad has just thrown something. One cloud is enough.
	if context.squad_last_equipment_ms > 0:
		var since: float = (Time.get_ticks_msec() - context.squad_last_equipment_ms) / 1000.0
		if since < squad_spacing_seconds:
			return false
	# All three reasons are reasons to stop being shot, so all three need
	# somebody to be shooting.
	if context.under_fire_seconds > recent_fire_seconds:
		return false

	# 1 — breaking contact under fire.
	if context.squad_objective == OBJ_WITHDRAW:
		return true

	# 2 — a casualty within reach. Screening the recovery is worth a canister
	# whatever else is happening.
	if _casualty_in_reach(context):
		return true

	# 3 — crossing open ground, and losing.
	var crossing: bool = context.squad_objective == OBJ_ADVANCE \
		or context.squad_objective == OBJ_ATTACK
	if not crossing:
		return false
	if context.threat_bearing == Vector3.ZERO:
		# Taking fire from something nobody has located. No bearing means no
		# sensible place to put a cloud, so this is not a refusal to fix with a
		# wider radius — it is "wait until something is seen".
		return false
	var threat_range: float = owner_ai.global_position.distance_to(context.threat_position)
	if threat_range < crossing_min_metres:
		return false
	# Can they actually see us? is_path_clear() answers through the smoke test,
	# so a cloud already on this sightline makes this false — which is the
	# behaviour we want and the reason this check is worth its raycast: a squad
	# cannot stack three canisters on the same line.
	#
	# BOTH arguments past the first are load-bearing. From `global_position` the
	# ray starts at the feet, inside the floor; and without the actor excluded it
	# terminates inside the threat's own collider, so the answer is "blocked"
	# every single time and this branch never fires. enemy.gd's own LOS check
	# does both of these (see `_update_los`) and this is the same question.
	if not owner_ai.is_path_clear(owner_ai.global_position + Vector3.UP * 0.8,
			context.threat_position, context.threat_actor):
		return false
	return _losing(context)


## Reason 2's test. Downed and not dead: a wreck is nobody's problem.
func _casualty_in_reach(context: AIEquipment.EquipmentContext) -> bool:
	var mate := context.downed_friendly
	if mate == null or not is_instance_valid(mate):
		return false
	return context.owner_ai.global_position.distance_to(mate.global_position) <= rescue_radius


## Are we losing this one? Three ways, any of which is enough: we are hurt, a
## squadmate is already down, or there are bodies on top of us.
func _losing(context: AIEquipment.EquipmentContext) -> bool:
	if context.downed_friendly != null and is_instance_valid(context.downed_friendly):
		return true
	if context.nearby_hostiles.size() >= losing_hostile_count:
		return true
	var owner_ai := context.owner_ai
	var hull: float = maxf(float(owner_ai.max_health), 1.0)
	return float(owner_ai.health) / hull <= losing_health_fraction


func execute(context: AIEquipment.EquipmentContext) -> void:
	if canister_scene == null:
		return
	var owner_ai := context.owner_ai
	var mark := placement_or(context, _screen_point(context))
	var from: Vector3 = owner_ai.global_position + Vector3.UP * 1.5
	var arc := AIEquipment.throw_velocity(from, mark)
	if arc == Vector3.ZERO:
		# The mark came out on top of us, which the clamp should prevent. Say so
		# rather than dropping a live canister at our feet and consuming it.
		push_warning("AISmoke '%s': no throwable arc to %s, holding." % [equipment_name, str(mark)])
		return

	var canister = canister_scene.instantiate()
	# THE LEVEL, not the current scene. See AIEquipment.spawn_host — the scene is
	# Master, which outlives the mission and took the ordnance with it.
	var host: Node = spawn_host(owner_ai)
	if host == null:
		return
	host.add_child(canister)
	canister.global_position = from
	if canister.has_method("setup"):
		canister.setup(owner_ai)
	_Analytics.throw(owner_ai, _Analytics.label_for_scene(canister_scene.resource_path))
	if canister is RigidBody3D:
		(canister as RigidBody3D).linear_velocity = arc


## Where the cloud goes.
##
## On the casualty when there is one, because the sightline that matters is the
## one onto the robot that cannot move. Otherwise most of the way to the threat,
## so the cloud sits ACROSS the line rather than around either end of it.
func _screen_point(context: AIEquipment.EquipmentContext) -> Vector3:
	var owner_ai := context.owner_ai
	if _casualty_in_reach(context):
		return context.downed_friendly.global_position
	if context.threat_bearing == Vector3.ZERO:
		# Withdrawing from something unseen: put it between us and the way we
		# came, which is behind the facing. Better than our own feet and better
		# than not throwing, since reason 1 has already decided this is worth it.
		var back: Vector3 = owner_ai.global_transform.basis.z
		back = Vector3(back.x, 0.0, back.z)
		back = back.normalized() if back.length_squared() > 0.0001 else Vector3.BACK
		return owner_ai.global_position + back * min_screen_metres
	var reach: float = clampf(
		owner_ai.global_position.distance_to(context.threat_position) * screen_fraction,
		min_screen_metres, max_screen_metres)
	return owner_ai.global_position + context.threat_bearing * reach
