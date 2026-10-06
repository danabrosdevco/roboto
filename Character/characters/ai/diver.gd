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

## DITCH is the end of the clock: out of time, nose down, and it goes off on
## the ground rather than evaporating in mid-air. APPEND-ONLY, like every enum
## in this project — these are stored as ints.
enum Phase { CLIMB, HUNT, DIVE, SPENT, DITCH }

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
## Seconds in the air before it ditches. Two minutes: long enough that a drone
## released at the start of a push is still useful when the push arrives, short
## enough that none is ever left circling a map the fight has moved off.
##
## It does NOT simply vanish at the end of this — see _expire. A charge that
## quietly disappears is one the player cannot account for.
@export var lifetime: float = 120.0
## How close to the ground a ditching drone gets before it goes off.
@export var ditch_trigger: float = 1.6
## A ceiling on the ditch itself, so a drone wedged under an overhang cannot
## hang there nose-down for the rest of the mission.
@export var ditch_seconds: float = 6.0

@export_group("Rig")
## The whole model, so the rotors can spin and the body can bank.
@export var rig: Node3D
@export var rotors: Array[Node3D] = []
@export var rotor_speed: float = 42.0
## Straight down a run, radians. Reads as commitment.
@export var dive_pitch: float = 1.1
@export var ground_ray: RayCast3D
## Looks AHEAD, which ground_ray cannot. See air_clearance.gd.
const _AirClearance := preload("res://Character/characters/ai/air_clearance.gd")
var _clearance := _AirClearance.new()

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

	# Out of time. It does not get to abandon a dive it is already committed to
	# — that is a hit about to land, and cutting it short wastes the drone for
	# the sake of a second.
	if _age >= lifetime and phase != Phase.DIVE and phase != Phase.DITCH:
		_expire()

	match phase:
		Phase.CLIMB:
			_tick_climb(delta)
		Phase.HUNT:
			_tick_hunt(delta)
		Phase.DIVE:
			_tick_dive(delta)
		Phase.DITCH:
			_tick_ditch(delta)


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


# OUT OF TIME, SO IT PUTS ITSELF INTO THE GROUND.
#
# It used to drop silently, on the reasoning that a charge going off on a timer
# wherever it happens to be is a mine nobody placed. True — so it does not go
# off where it is. It flies down first, and detonates on the dirt, which is
# both accountable (the player sees and hears the drone they paid for end) and
# harmless in a way a mid-air burst over a squad is not.
#
# Straight down rather than at anything: this is a disposal, not a last attack,
# and picking a target here would make the timer a weapon.
func _tick_ditch(delta: float) -> void:
	var floor_y := _ground_height()
	if global_position.y - floor_y <= ditch_trigger or _phase_t >= ditch_seconds:
		_detonate()
		return
	_steer_toward(Vector3(global_position.x, floor_y - 2.0, global_position.z),
		dive_speed, delta)
	_orient(_fly_dir, dive_pitch, delta)


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


# Out of time. Nose down — see _tick_ditch for why it is not just dropped.
func _expire() -> void:
	if phase == Phase.SPENT or phase == Phase.DITCH:
		return
	_target = null
	_enter(Phase.DITCH)


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
	# Refresh what is ahead; _hold_height() is solved from it.
	_clearance.tick(get_physics_process_delta_time(), self, _fly_dir, Vector2(velocity.x, velocity.z).length())
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


# Whatever is UNDER it, or anything higher it is about to fly into. A down-ray
# alone only notices an obstacle once it is already beneath. See air_clearance.gd.
func _ground_height() -> float:
	var under: float = ground_ray.get_collision_point().y if (ground_ray != null and ground_ray.is_colliding()) else _launch_y
	return maxf(under, _clearance.ground_ahead())


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
## A MUNITION LEAVES NO WRECK, WHICHEVER WAY IT ENDS.
##
## _detonate called _vanish itself, so a drone that went off cleaned up — but a
## drone SHOT DOWN, EMP'd, or cut short by the payload's backstop timer went
## through Enemy.destroy() instead, which hides the body and disables the
## colliders and then leaves the node in the level for the rest of the mission.
## Invisible, inert, and permanent: one per drone, every mission.
##
## Overriding here catches every one of those paths at once, because they all
## end in destroy().
func destroy() -> void:
	super()
	_vanish()


func _vanish() -> void:
	for c in get_children():
		if c is AudioStreamPlayer3D:
			(c as AudioStreamPlayer3D).stop()
	queue_free()
