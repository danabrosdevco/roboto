extends Soldier

# ─────────────────────────────────────────────
# WATCHER — an enemy building whose weapon is the radio.
#
# It never moves and never shoots. What it does is SEE, and keep telling the
# rest of the map where you are: while it is alive and in contact, it calls in
# one group of reserves every `call_interval_seconds`. Kill it and the calls
# stop; leave it and they keep coming for as long as you are on its hill.
#
# WHY IT EXISTS. The flanking posts on the Hillfort were two riflemen on a hill
# you could walk straight past, and the briefing's promise — "watchers on both
# flanking hills to tell them you are coming" — was not true of anything in the
# level. This makes it true, and in doing so it creates the one decision the
# squad-command verbs exist for: send a fireteam up to silence it, or keep
# climbing and pay for it the whole way.
#
# THE TARGET IS AT THE BASE, NOT THE TOP. Its collision shape covers the plinth
# only; the mast and the sweeping arm carry no collider at all, so rounds pass
# through them. That is deliberate and it is the whole balance of the thing: a
# scoped rifle from the valley floor must not be able to solve it, because then
# nobody ever climbs. You have to get line of sight on the base, and on a ridge
# that means going up there.
#
# WHAT IT CALLS. Its squad's own contact tag — "WESTWATCH" -> westwatch_engaged,
# the same name EnemyForceSpawner derives for every squad. So a mission queues
# as many reserve squads on that tag as it wants the hill to be worth, and the
# watcher pulls them in one at a time. No new field, and nothing to keep in
# step by hand.
#
# It stops when the queue runs dry, and says so. A building that goes on
# calling an empty tag every half minute is a building doing nothing loudly.
# ─────────────────────────────────────────────

@export_group("Calling")
## Seconds between calls once it is in contact.
@export var call_interval_seconds: float = 28.0
## Grace before the first one, so walking into view is not instantly punished.
@export var first_call_seconds: float = 9.0

@export_group("Parts")
## The long arm. Yaws slowly — a sweep you can time from below.
@export var scanner: Node3D
@export var scan_degrees_per_second: float = 20.0
## The drum above it, and the amber lamp riding on it. Spins fast, so the two
## speeds together read as machinery rather than as one thing turning.
@export var spinner: Node3D
@export var spin_degrees_per_second: float = 165.0
## Tips over when it dies: the clearest possible "that is switched off now".
@export var mast_tilt_on_death_degrees: float = 24.0

var _next_call: float = 0.0
var _exhausted: bool = false


func _ready() -> void:
	# A building has no business rolling advances and chases, and this one has
	# no gun to roll a FIRE for either. Same clearing the nest does.
	AllowedMovementOptions.clear()
	AllowedCombatOptions.clear()
	super()
	_next_call = first_call_seconds


# Bolted down, exactly like the nest: the base drives velocity off the nav
# agent and the squad sends it places, and neither should move a building.
func move_along_nav(_delta) -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func move_to(_pos: Vector3, _think_delay: float = 0.0) -> void:
	pass   # a watcher is where it was built


func order_move_to(_pos: Vector3, _force: bool = false, _keep_target: bool = false,
		_think_delay: float = 0.0) -> void:
	pass   # the squad can want it elsewhere all it likes


func takes_cover() -> bool:
	return false


func enter_cover_seeking() -> void:
	change_soldier_state(SoldierState.NONE)


# IT IS A BUILDING. The base swings a robot's whole body to face its target,
# which on something bolted to a hilltop reads as the entire tower slewing
# round. Only the arm and the drum turn. Dropped rather than damped: it has no
# weapon, so there is nothing it needs to point at.
func _update_facing(_delta: float) -> void:
	pass


# THE ARM STOPS AND THE MAST LEANS. Tweened from here rather than eased in the
# physics tick, because destroy() switches that tick OFF — the same trap the
# nest hit with its fires, where whatever the last frame was doing is what a
# dead one kept doing forever. A tween runs on its own.
func destroy() -> void:
	if mast_tilt_on_death_degrees > 0.0 and is_inside_tree():
		var fall := create_tween()
		fall.tween_property(self, "rotation:z", deg_to_rad(mast_tilt_on_death_degrees), 0.9) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	super()


func _physics_process(delta: float) -> void:
	super(delta)
	if not alive:
		return   # down: the arm is still and destroy() has leaned the mast
	if get_signal_state() == SignalState.EKILL:
		return   # jammed: the dish stops and nothing gets called in
	if scanner != null:
		scanner.rotate_y(deg_to_rad(scan_degrees_per_second) * delta)
	if spinner != null:
		spinner.rotate_y(deg_to_rad(spin_degrees_per_second) * delta)
	if _exhausted or not _fighting():
		return   # nothing queued, or nothing seen yet: it just sweeps
	_next_call -= delta
	if _next_call > 0.0:
		return
	_next_call = call_interval_seconds
	_call_it_in()


## In contact — its own, or its squad's. Same test the nest uses to decide the
## fight has started.
func _fighting() -> bool:
	if ai_state == AIState.COMBAT:
		return true
	if combat_target != null and is_instance_valid(combat_target) and combat_target.alive:
		return true
	return squad != null and is_instance_valid(squad) and squad.has_live_contact()


func _call_it_in() -> void:
	var spawner := _spawner()
	if spawner == null:
		push_warning("%s has nothing to call: no EnemyForceSpawner on the campaign. It is an ordinary building with health." % name)
		_exhausted = true
		return
	var tag := _tag()
	if tag == &"":
		push_warning("%s is in no squad, so it has no tag to call on. Give its EnemySquadSpec a callsign." % name)
		_exhausted = true
		return
	var woken: int = spawner.wake(tag)
	if woken <= 0:
		# Everything queued on this hill has already come. Said once, then it
		# goes quiet rather than asking every half minute for the rest of the
		# mission.
		print("[Watcher] %s called '%s' and nothing was left queued; it stops calling." % [name, tag])
		_exhausted = true
		return
	print("[Watcher] %s has eyes on you: '%s' brings in %d." % [name, tag, woken])
	if bark != null:
		bark.bark(BarkSet.Line.CONTACT)


## "WESTWATCH" -> westwatch_engaged, derived exactly the way the spawner does
## it so the two cannot drift apart.
func _tag() -> StringName:
	if squad == null or not is_instance_valid(squad):
		return &""
	return EnemyForceSpawner.squad_engaged_tag(squad.callsign)


## The force spawner, through the campaign's group rather than a path: this
## body is instanced into a level by that very spawner and has no route back to
## it except the campaign.
func _spawner() -> EnemyForceSpawner:
	var campaign := get_tree().get_first_node_in_group("campaign")
	if campaign == null:
		return null
	return campaign.get("enemy_spawner") as EnemyForceSpawner
