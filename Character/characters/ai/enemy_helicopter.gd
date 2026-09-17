extends Soldier
class_name EnemyHelicopter

# ─────────────────────────────────────────────
# HELICOPTER — a flying Enemy.
#
# WHAT THIS REPLACES. The original TestHelicopter extended CharacterBody3D
# directly and reimplemented the whole robot: its own WeaponState and
# MovementState enums, its own sight Area3D and `seen_bodies` list, its own
# targeting timer. None of it was connected to anything — it never registered
# with AIManager, so squads could not see it, `get_nearest_hostile` never
# returned it, stimulus never reached it, and it had no faction hostility
# check, no downed state, no signal integrity, no LOD and no barks.
#
# It also carried three real bugs: `seen_bodies.erase(body)` while iterating
# that same array, `targetting_time = 0.0` set on acquisition and never reset
# (so it re-targeted every frame afterwards), and a `look_target != null` test
# on a Vector3, which is never null and so was always true.
#
# WHAT THIS IS INSTEAD. Everything above is inherited by extending Enemy. The
# only thing a helicopter genuinely does differently is MOVE, so this overrides
# exactly three seams — handle_gravity, handle_movement and _apply_motion — and
# leaves perception, targeting, factions, barks, downing and budgeting alone.
#
# nav_agent is still assigned in the scene even though flight ignores it.
# Inherited paths (_seek_los_position, find_advance_target) reach for the
# navigation map, and a null agent there would crash rather than degrade.
#
# EXTENDS SOLDIER, NOT ENEMY. Squad.squad_members is typed Array[Soldier] and
# EnemyForceSpawner casts every spawned body with `as Soldier`, so an
# Enemy-rooted scene cannot be used as a squad chassis at all — it fails the
# cast and the whole squad is skipped. Soldier extends Enemy, so this costs
# nothing and buys cover-seeking and squad states it can simply not use.
# Soldier does not override handle_movement, _apply_motion, handle_gravity or
# _update_facing, so the flight overrides below still sit directly on Enemy's.
# ─────────────────────────────────────────────

@export_group("Flight")
## Height above the ground it tries to hold. Measured by raycast, so it climbs
## over terrain rather than flying into hillsides.
@export var hover_height: float = 18.0
@export var altitude_smoothness: float = 3.0
## Helicopters do not stop dead. Below this it still drifts.
@export var min_speed: float = 4.0
@export var turn_speed: float = 1.4
@export var bank_angle: float = 0.45
## How far out it holds station from whatever it is shooting at.
@export var standoff_distance: float = 26.0
## Radius it drifts around when it has nothing to do. Enemy already declares
## wander_radius/wander_delay for ground patrol at 3.5m and 1.5s — far too tight
## for something that cruises. These are separate rather than overriding the
## parent's, so ground wander tuning stays where it is.
@export var flight_wander_radius: float = 60.0
@export var flight_wander_delay: float = 8.0

@export_group("Audio")
@export var rotor_loop: AudioStreamPlayer3D

var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _current_speed: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _ground_ray: RayCast3D


func _ready() -> void:
	super()
	_home = global_position
	_current_speed = move_speed * 0.6
	_pick_wander_target()

	# Built in code rather than authored, so every helicopter scene gets one and
	# none of them can ship with the export left blank.
	_ground_ray = RayCast3D.new()
	_ground_ray.target_position = Vector3(0, -200.0, 0)
	_ground_ray.collision_mask = 1
	_ground_ray.exclude_parent = true
	add_child(_ground_ray)

	if rotor_loop != null and not rotor_loop.playing:
		rotor_loop.play()


# Flight cancels gravity outright. Enemy's version zeroes fall speed against the
# floor, which a helicopter never touches.
func handle_gravity(_delta: float) -> void:
	pass


# Ground robots resolve against the floor and detect leap landings. Neither
# applies, and is_on_floor() is false forever up here.
func _apply_motion() -> void:
	move_and_slide()


# Flight ignores the navmesh entirely — it is a ground-path solver and this
# thing goes over the terrain, not around it.
func move_to(pos: Vector3) -> void:
	movement_target = pos
	movement_state = MovementState.MOVING


func handle_movement(delta: float) -> void:
	if downed or ai_state == AIState.DEAD:
		# Never actually reached while downed — Enemy._physics_process returns
		# in its downed branch long before handle_movement. The crash is handled
		# by _on_crash_started/_on_crash_landed instead, which is why the rotor
		# kept running: this was the wrong place to stop it.
		return

	_fly_toward(_destination(delta), delta)


# Belt and braces: the crash hooks only fire when it dies AIRBORNE. One that
# somehow dies on the ground would take the settle path and keep droning.
func enter_downed() -> void:
	if rotor_loop != null:
		rotor_loop.stop()
	super()


# Killed in the air. Enemy's crash path takes over from here — this just cuts
# the engine, so the rotor stops the moment it dies rather than droning on over
# a wreck for the rest of the mission.
func _on_crash_started() -> void:
	if rotor_loop != null:
		rotor_loop.stop()


func _on_crash_landed() -> void:
	if rotor_loop != null:
		rotor_loop.stop()


# Where it wants to be this frame. Combat wins, then a standing move order,
# then idle drift.
func _destination(delta: float) -> Vector3:
	if has_live_target():
		# Hold station off the target rather than flying onto it — a helicopter
		# that closes to melee range reads as a drone, and the weapon's own
		# range check would stop it firing anyway.
		var to_self := global_position - combat_target.global_position
		to_self.y = 0.0
		if to_self.length_squared() < 0.01:
			to_self = Vector3.FORWARD
		return combat_target.global_position + to_self.normalized() * standoff_distance

	if movement_state == MovementState.MOVING and movement_target != Vector3.ZERO:
		if global_position.distance_to(movement_target) > 6.0:
			return movement_target
		movement_state = MovementState.NONE

	_wander_timer -= delta
	if _wander_timer <= 0.0 or global_position.distance_to(_wander_target) < 12.0:
		_pick_wander_target()
	return _wander_target


func _pick_wander_target() -> void:
	var angle := randf() * TAU
	var radius := randf_range(flight_wander_radius * 0.35, flight_wander_radius)
	_wander_target = _home + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_wander_timer = flight_wander_delay + randf_range(0.0, flight_wander_delay * 0.5)


func _fly_toward(target: Vector3, delta: float) -> void:
	var to_target := target - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var heading := to_target.normalized() if distance > 0.01 else -global_transform.basis.z

	# Ease the heading rather than snapping. The banking read comes from the
	# turn being visibly gradual.
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var new_dir := forward.lerp(heading, clampf(turn_speed * delta, 0.0, 1.0)).normalized()

	# Slow down as it arrives so it settles into a hover instead of overshooting
	# and circling back.
	var wanted_speed := move_speed
	if distance < standoff_distance:
		wanted_speed = lerpf(min_speed, move_speed, clampf(distance / standoff_distance, 0.0, 1.0))
	_current_speed = lerpf(_current_speed, wanted_speed, clampf(acceleration * delta, 0.0, 1.0))

	var planar := new_dir * _current_speed
	velocity.x = lerpf(velocity.x, planar.x, clampf(acceleration * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, planar.z, clampf(acceleration * delta, 0.0, 1.0))
	velocity.y = _altitude_velocity(delta)

	_bank_toward(new_dir, delta)


# Terrain-following. The raycast is what stops it flying into a hillside while
# holding a fixed world altitude.
func _altitude_velocity(delta: float) -> float:
	var ground := _home.y
	if _ground_ray != null and _ground_ray.is_colliding():
		ground = _ground_ray.get_collision_point().y
	var error := (ground + hover_height) - global_position.y
	return lerpf(velocity.y, clampf(error * altitude_smoothness, -move_speed, move_speed),
		clampf(altitude_smoothness * delta, 0.0, 1.0))


func _bank_toward(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.01:
		return
	var yaw := atan2(-dir.x, -dir.z)
	# Roll into the turn, proportional to how hard it is turning.
	var turn_delta := angle_difference(rotation.y, yaw)
	var roll := clampf(turn_delta * 2.0, -bank_angle, bank_angle)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(rotation_speed * delta, 0.0, 1.0))
	rotation.z = lerpf(rotation.z, roll, clampf(4.0 * delta, 0.0, 1.0))


# Facing is driven by the flight model, so the ground version — which turns to
# face a target on the spot — must not also run.
func _update_facing(_delta: float) -> void:
	pass
