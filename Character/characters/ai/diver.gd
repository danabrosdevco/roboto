extends Soldier
class_name Diver

# ─────────────────────────────────────────────
# DIVER — a single-use frame that trades itself for one kill.
#
# Every other AI in the game picks what to attack by what is nearest and
# visible (Enemy.reconsider_target). This one ranks candidates by chassis COST
# instead, so it goes past a pistol soldier to reach a Walker. That is the only
# thing it does differently, and it is the whole reason to field one.
#
# ON "COMPUTE": compute is a campaign ledger resource (seats and software) and
# no robot carries it into a level, so the score used here is the target's
# ChassisDefinition.cost — the game's own number for what a frame is worth,
# available on both sides through KillKinds without touching CampaignState.
#
# BALANCE LIVES IN THREE EXPORTS:
#   climb_seconds  it rises first, which is the tell — the player gets a beat
#                  to react before it commits.
#   turn_rate      steering is rate-limited like the Walker's turret traverse,
#                  so moving late beats it. Perfect tracking would remove the
#                  counter entirely.
#   base_health    50 on the chassis. Everything in the game kills it.
#
# It expires on a timer, cannot be downed and repaired, and is not purchasable:
# it is spawned by the Drone Carrier Pack (equipment that sends one up) or by an
# enemy spec, the same way a Hatchling releases a hopper.
# ─────────────────────────────────────────────

const _Kinds := preload("res://Campaign/kill_kinds.gd")
const EXPLOSION := preload("res://Character/weapon/explosion.tscn")

enum Phase { CLIMB, HUNT, DIVE, SPENT }

@export_group("Flight")
## Metres above the ground it climbs to before it starts choosing.
@export var strike_height: float = 24.0
## Seconds of climb. The player's warning: nothing happens to anyone until this
## is over, and it is in plain sight the whole time.
@export var climb_seconds: float = 1.6
@export var climb_speed: float = 16.0
## Cruise speed while it is still choosing.
@export var hunt_speed: float = 9.0
## Speed once committed.
@export var dive_speed: float = 30.0
## Radians per second of steering. THE COUNTER: low enough that moving across
## its line late beats it.
@export var turn_rate: float = 2.4
## How hard it corrects onto the wanted heading.
## Named for what it is rather than "acceleration", which Enemy already exports
## as the walking accel — redeclaring it in a subclass is a parse error, and the
## two are different quantities anyway: this one is a lerp rate for steering.
@export var steer_rate: float = 6.0

@export_group("Attack")
## How far it looks for something to hit.
@export var seek_range: float = 90.0
## Goes off inside this of the target.
@export var trigger_radius: float = 2.2
@export var blast_damage: int = 90
## Seconds before it runs out and drops, whatever happened.
@export var lifetime: float = 30.0

@export_group("Rig")
## The whole model, so the rotors can spin and the body can bank.
@export var rig: Node3D
@export var rotors: Array[Node3D] = []
@export var rotor_speed: float = 42.0
## Straight down a run, radians. Reads as commitment.
@export var dive_pitch: float = 1.1
@export var ground_ray: RayCast3D

var phase: int = Phase.CLIMB
var _phase_t: float = 0.0
var _age: float = 0.0
var _target: Node3D = null
var _fly_dir: Vector3 = Vector3.FORWARD
var _launch_y: float = 0.0


func _ready() -> void:
	super()
	add_to_group("air")
	_launch_y = global_position.y
	_fly_dir = -global_transform.basis.z
	_fly_dir.y = 0.0
	if _fly_dir.length_squared() < 0.0001:
		_fly_dir = Vector3.FORWARD
	_fly_dir = _fly_dir.normalized()
	# A munition, not a casualty: there is nothing to walk over and repair.
	can_be_downed = false


# ─────────────────────────────────────────────
# SEAMS OVERRIDDEN FROM ENEMY
# Same set the Spotter overrides, and for the same reasons.
# ─────────────────────────────────────────────

# Flight cancels gravity — but only while it is flying. Shot down or knocked
# out by an EMP it has to fall, or the wreck hangs in the air.
func handle_gravity(delta: float) -> void:
	if alive and phase != Phase.SPENT and get_signal_state() != SignalState.EKILL:
		return
	super(delta)


func _apply_motion() -> void:
	move_and_slide()


# It flies over terrain rather than around it, so an order is a hint about
# where to look, not a path to queue.
func move_to(pos: Vector3, _think_delay: float = 0.0) -> void:
	movement_target = pos


# It has no gun; its attack IS its movement.
func handle_weapon_logic(_delta: float) -> void:
	pass


func roll_combat_action() -> void:
	pass


# Facing is flight attitude, set from the heading in _orient.
func _update_facing(_delta: float) -> void:
	pass


func takes_cover() -> bool:
	return false


# ─────────────────────────────────────────────
# THE RUN
# ─────────────────────────────────────────────
func handle_movement(delta: float) -> void:
	if not alive or phase == Phase.SPENT:
		return
	_age += delta
	_phase_t += delta
	_spin_rotors(delta)

	if _age >= lifetime:
		_expire()
		return

	match phase:
		Phase.CLIMB:
			_tick_climb(delta)
		Phase.HUNT:
			_tick_hunt(delta)
		Phase.DIVE:
			_tick_dive(delta)


# Straight up, in the open, for a fixed beat. Leaving when it reaches height
# ALSO leaves when it spawns on a rooftop already at height, which skips the
# warning entirely — so the clock, not the altitude, ends this phase.
func _tick_climb(delta: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, clampf(steer_rate * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, 0.0, clampf(steer_rate * delta, 0.0, 1.0))
	var want_y: float = _ground_height() + strike_height
	velocity.y = climb_speed if global_position.y < want_y else 0.0
	_orient(_fly_dir, 0.0, delta)
	if _phase_t >= climb_seconds:
		_enter(Phase.HUNT)


# At height, picking. It keeps drifting the way it was pointed so it is never a
# stationary balloon, and re-asks every frame until something is in range.
func _tick_hunt(delta: float) -> void:
	_target = _best_target()
	if _target != null:
		_enter(Phase.DIVE)
		return
	_steer_toward(global_position + _fly_dir * 20.0, hunt_speed, delta)
	velocity.y = _hold_height(_ground_height() + strike_height, delta)
	_orient(_fly_dir, 0.0, delta)


# Committed. It keeps the target it chose unless that target is gone — a drone
# that re-shopped every frame would wander between two robots and hit neither.
func _tick_dive(delta: float) -> void:
	if not _alive_target(_target):
		_target = _best_target()
		if _target == null:
			_enter(Phase.HUNT)
			return
	var to := _target.global_position - global_position
	if to.length() <= trigger_radius:
		_detonate()
		return
	_steer_toward(_target.global_position, dive_speed, delta)
	_orient(_fly_dir, dive_pitch * clampf(-to.normalized().y, 0.0, 1.0), delta)


func _enter(next: int) -> void:
	phase = next
	_phase_t = 0.0


# ─────────────────────────────────────────────
# CHOOSING
# ─────────────────────────────────────────────
# Worth, then distance — never distance alone. Ties break toward the closer one
# so two Walkers at the same price do not make it dither.
func _best_target() -> Node3D:
	var best: Node3D = null
	var best_score := -INF
	for body in _candidates():
		if not _alive_target(body):
			continue
		var d := global_position.distance_to((body as Node3D).global_position)
		if d > seek_range:
			continue
		var score := _worth(body) * 1000.0 - d
		if score > best_score:
			best_score = score
			best = body as Node3D
	return best


func _candidates() -> Array:
	if ai_manager != null and is_instance_valid(ai_manager) and ai_manager.has_method("hostiles_for"):
		return ai_manager.hostiles_for(faction)
	var out: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		if n is Soldier and Enums.are_hostile(faction, (n as Soldier).faction):
			out.append(n)
	return out


# What the frame cost to build. A body with no chassis behind it (the player,
# a prop) falls back to its hull, so it still ranks rather than scoring zero
# and being ignored forever.
func _worth(body: Node) -> float:
	var frame := _Kinds.frame_of(_Kinds.kind_of(body))
	if frame != null:
		return float(frame.cost)
	var hp = body.get("max_health")
	return float(hp) if hp != null else 1.0


func _alive_target(body: Node) -> bool:
	if body == null or not is_instance_valid(body) or not (body is Node3D):
		return false
	var living = body.get("alive")
	return living == null or bool(living)


# ─────────────────────────────────────────────
# GOING OFF
# ─────────────────────────────────────────────
func _detonate() -> void:
	if phase == Phase.SPENT:
		return
	_enter(Phase.SPENT)
	var blast := EXPLOSION.instantiate()
	blast.damage_value = blast_damage
	blast.source_faction = faction
	# Its kills belong to whoever released it, the same bargain a Hatchling
	# makes — see Enemy.credit_kills_to.
	blast.source_actor = credit_kills_to if credit_kills_to != null else self
	var host := get_parent()
	if host != null:
		host.add_child(blast)
		(blast as Node3D).global_position = global_position
	die()
	_vanish()


# Out of time. It drops rather than going off: a charge that detonates on a
# timer wherever it happens to be is a mine nobody placed.
func _expire() -> void:
	if phase == Phase.SPENT:
		return
	_enter(Phase.SPENT)
	die()
	_vanish()


# ─────────────────────────────────────────────
# FLIGHT HELPERS
# ─────────────────────────────────────────────
# Heading is its own state turned at a fixed rate, in 3D — unlike the Spotter,
# which only ever turns about UP because it never points anywhere but level.
func _steer_toward(point: Vector3, speed: float, delta: float) -> void:
	var wish := point - global_position
	if wish.length_squared() < 0.0001:
		return
	_fly_dir = _turn_toward(_fly_dir, wish.normalized(), turn_rate * delta)
	var wanted := _fly_dir * speed
	var k := clampf(steer_rate * delta, 0.0, 1.0)
	velocity = velocity.lerp(wanted, k)


func _turn_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle := from.angle_to(to)
	if angle <= max_angle or angle < 0.0001:
		return to
	var axis := from.cross(to)
	if axis.length_squared() < 0.000001:
		return to
	return from.rotated(axis.normalized(), max_angle).normalized()


func _hold_height(want_y: float, delta: float) -> float:
	return lerpf(velocity.y, clampf((want_y - global_position.y) * 2.0, -climb_speed, climb_speed),
		clampf(4.0 * delta, 0.0, 1.0))


func _ground_height() -> float:
	if ground_ray != null and ground_ray.is_colliding():
		return ground_ray.get_collision_point().y
	return _launch_y


# Yaw to the heading, pitch into the run. Past 90 degrees a Euler pitch flips,
# so the attitude is built as a basis — see the note in GDScript gotchas.
func _orient(dir: Vector3, pitch: float, delta: float) -> void:
	if rig == null or dir.length_squared() < 0.0001:
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		flat = -global_transform.basis.z
	var yaw := atan2(-flat.x, -flat.z)
	rotation.y = rotate_toward(rotation.y, yaw, turn_rate * delta)
	rig.basis = rig.basis.slerp(Basis(Vector3.RIGHT, -pitch), clampf(6.0 * delta, 0.0, 1.0))


func _spin_rotors(delta: float) -> void:
	for r in rotors:
		if r != null and is_instance_valid(r):
			r.rotate_y(rotor_speed * delta)


## NOTHING IS LEFT OF IT.
##
## Enemy.destroy() hides the body and kills its colliders but leaves the NODE
## in the tree, which is right for a wreck a Reclaimer can still grind down and
## wrong for a munition that has just gone off. The rotor loop is an
## autoplaying AudioStreamPlayer3D on that node, so a spent Diver went on
## buzzing from the spot where it blew up for the rest of the mission.
##
## The audio is stopped before the free rather than left to it: queue_free is
## deferred, and a frame of rotor noise coming out of a fireball is a frame too
## many. The blast itself is a separate node parented to the level, so it
## outlives this and finishes properly.
func _vanish() -> void:
	for c in get_children():
		if c is AudioStreamPlayer3D:
			(c as AudioStreamPlayer3D).stop()
	queue_free()
