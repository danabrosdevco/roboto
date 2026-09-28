extends Soldier
class_name SpotterDrone

# ─────────────────────────────────────────────
# SPOTTER DRONE — a flying eye that hands the whole squad its sight.
#
# WHAT IT IS FOR. Sensors reach 45m and rifles reach 80m, so a squad on the
# ground spends the first half of every engagement being shot at by something
# it cannot see. `Enemy._on_combat_triggered` wakes and engages the WHOLE
# squad the moment any one member acquires a target — so a single unit with a
# long sensor converts that gap for everybody at once. No new systems: the
# drone just has to be up there, alive, and looking.
#
# It carries no weapon and never will. Its whole contribution is the number in
# `base_sensor_range`, and every design decision below protects the drone's
# ability to keep flying rather than its ability to do anything else.
#
# ─────────────────────────────────────────────
# MODELLED ON THE BOMBER, WITHOUT ITS MISTAKES
#
# The flight primitives are EnemyHelicopter's, which earned them the hard way
# (see that file's header). Three of its documented failures are repeated here
# as rules, because they are the traps this shape of thing falls into:
#
#   1. IT NEVER HOVERS. The bomber held station on a fixed point and every one
#      of them was shot down. This orbits, always, even when its station has
#      not moved. A moving target is a harder one, and motion is also what
#      tells the player it is alive rather than stuck.
#   2. NOTHING GOES THROUGH THE COMBAT ROLL. The generic MOVE/AIM/FIRE dice is
#      what let one bomber drop and its wingman not. `roll_combat_action` and
#      `handle_weapon_logic` are no-ops, and the two behaviours below are the
#      whole of what it does.
#   3. TWO DRONES NEVER FLY TO ONE SPOT. `_separation()` is folded into the
#      heading, and each drone takes its own arc of the orbit off its instance
#      id, so a pair circles opposite sides of the squad instead of colliding
#      over the middle of it.
#
# ─────────────────────────────────────────────
# WHAT KILLS IT IS THE POINT
#
# 80 HP, no armour, and it flies in the open — this is meant to be killable,
# because a permanent 90m sensor with no counter would delete the approach
# phase of every mission. The three counters are deliberate and none of them
# is a bug:
#
#   - EMP and sustained suppression. `_enter_ekill` calls `die()`: losing the
#     link at altitude means losing lift, so it falls. That makes signal
#     damage anti-air.
#   - Marksmen. 48 damage falling off past 70m, against 80 HP, means a pair of
#     them bring it down in a few shots if it loiters in their band.
#   - Its own altitude. Cruise is ~22m, which is inside a rifle's 80m reach
#     from a long way off.
#
# It goes DOWN rather than being destroyed: `enter_downed` calls super(), so it
# crashes, lands, and a Mechanic can stand it back up. Losing the drone should
# cost you the sight and a trip to fetch it, not the drone.
# ─────────────────────────────────────────────

@export_group("Flight")
## Altitude it holds above whatever is under it. High enough to see over most
## cover, low enough that the squad can see where its eye is.
@export var cruise_height: float = 22.0
@export var altitude_smoothness: float = 2.2
@export var cruise_speed: float = 18.0
## How quickly it can swing onto a new heading. Low enough that turns read as
## arcs rather than snaps.
@export var turn_speed: float = 2.0
@export var bank_angle: float = 0.5

@export_group("Orbit")
## How wide a circle it flies around whatever it is watching over.
@export var orbit_radius: float = 14.0
## How fast it travels ALONG the circle, in m/s. Converted to an angular rate
## against orbit_radius below, so widening the orbit does not silently speed
## the drone up — the bomber loiters the same way.
@export var orbit_speed: float = 8.0
## Two drones on one station push apart inside this radius.
@export var separation_radius: float = 16.0
## Beyond this from its station it stops circling and just flies at it — a
## drone re-tasked across the map should transit, not spiral in.
@export var transit_distance: float = 40.0

@export_group("Audio")
@export var rotor_loop: AudioStreamPlayer3D

# Where it is circling. FOLLOW writes the squad slot here every time the slot
# moves; a DEFEND order writes the ordered point and leaves it there.
var _station: Vector3 = Vector3.ZERO
var _station_set: bool = false
var _orbit_angle: float = 0.0
var _lifted: bool = false
var _ground_ray: RayCast3D = null
# Its own arc of the circle, so wingmen are never on the same side of it.
var _arc: float = 0.0
# The direction it is FLYING, held separately from the body's facing. Deriving
# one from the other chains two lags and collapses the real turn rate — the
# bomber could not turn at all until this was split out. See _steer there.
var _fly_dir: Vector3 = Vector3.FORWARD


func _ready() -> void:
	super()
	add_to_group("air")
	_station = global_position
	_arc = TAU * float(get_instance_id() % 360) / 360.0
	_orbit_angle = _arc
	_fly_dir = _flat_body_forward()

	# Built in code rather than authored, so no drone scene can ship without
	# the ray it needs to hold an altitude.
	_ground_ray = RayCast3D.new()
	_ground_ray.target_position = Vector3(0, -300.0, 0)
	_ground_ray.collision_mask = 1
	_ground_ray.exclude_parent = true
	add_child(_ground_ray)

	if rotor_loop != null and not rotor_loop.playing:
		rotor_loop.play()


# ─────────────────────────────────────────────
# SEAMS OVERRIDDEN FROM ENEMY
# ─────────────────────────────────────────────

# Flight cancels gravity outright.
func handle_gravity(_delta: float) -> void:
	pass


func _apply_motion() -> void:
	move_and_slide()


# An order sets where it CIRCLES, not a navmesh path — it flies over the
# terrain rather than around it, so there is nothing to queue.
func move_to(pos: Vector3, _think_delay: float = 0.0) -> void:
	movement_target = pos
	_station = pos
	_station_set = true


# No weapon, ever. The inherited loop would look for one every frame and the
# combat roll would try to manoeuvre it into a firing position it can never
# use. See failure 2 in the header.
func handle_weapon_logic(_delta: float) -> void:
	pass


func roll_combat_action() -> void:
	pass


# Facing is flight attitude, set by _orient from the heading.
func _update_facing(_delta: float) -> void:
	pass


# It cannot use cover and must never be sent to look for any: a cover point is
# a spot on the ground, and steering a flying thing at one drops it into the
# fight it is supposed to be watching from above.
func takes_cover() -> bool:
	return false


# It is never in its slot the way a robot on foot is — it is circling above it.
# Without this the squad re-issues the same order every frame because the drone
# is permanently `orbit_radius` from where it was told to stand.
func slot_tolerance(squad_tolerance: float) -> float:
	return maxf(squad_tolerance, orbit_radius + 4.0)


# A drone needs its own airspace in a formation, or the line packs its slot in
# beside a soldier's and two of them try to occupy one circle.
func formation_width() -> float:
	return orbit_radius


# ─────────────────────────────────────────────
# FLIGHT
# ─────────────────────────────────────────────
# Two behaviours and no more:
#
#   FOLLOW      circle the squad slot the commander gives it, which moves with
#               the squad, so the eye travels with the people it is for.
#   ordered     circle the point it was sent to and stay there.
#
# Both are the same manoeuvre around a different centre, which is why there is
# no phase machine here. The bomber needs four phases because a bombing run is
# a sequence; looking at things is not.
func handle_movement(delta: float) -> void:
	if downed or ai_state == AIState.DEAD:
		return

	# SPAWN AIRBORNE. Built at a ground point, it would otherwise start on the
	# grass and climb out of the earth in full view.
	if not _lifted:
		_lifted = true
		var floor_y := _ground_height()
		if global_position.y < floor_y + cruise_height * 0.6:
			global_position.y = floor_y + cruise_height

	var centre := _station_centre()
	var flat_gap := Vector2(centre.x - global_position.x, centre.z - global_position.z).length()

	# Far from station: fly AT it rather than spiralling in from the horizon.
	if flat_gap > transit_distance:
		_steer(centre, cruise_speed, cruise_height, delta)
		return

	# On station: circle. Never hover — see failure 1 in the header.
	_orbit_angle += delta * orbit_speed / maxf(orbit_radius, 1.0)
	var on_circle := centre + Vector3(cos(_orbit_angle), 0.0, sin(_orbit_angle)) * orbit_radius
	_steer(on_circle, cruise_speed * 0.8, cruise_height, delta)


# Where it should be circling right now. A FOLLOW slot moves with the squad
# every frame, so it is read live rather than remembered; an ordered point was
# written once by move_to and stays put.
func _station_centre() -> Vector3:
	if not _station_set:
		_station = global_position
		_station_set = true
	return _station


# ─────────────────────────────────────────────
# STEERING — EnemyHelicopter's, minus the bombing-run parts.
# ─────────────────────────────────────────────
func _steer(target: Vector3, speed: float, height: float, delta: float) -> void:
	var to_target := target - global_position
	to_target.y = 0.0
	var wish := to_target.normalized() if to_target.length() > 0.01 else _fly_dir

	# Push apart from other aircraft. Folded into the HEADING rather than added
	# to velocity, so a pair banks away from each other instead of sliding
	# sideways while still pointing at the same spot.
	wish = (wish + _separation() * 1.4).normalized()

	# The flight direction is its own state, turned at a fixed rate. Deriving
	# it from the body facing is what stopped the bomber turning at all.
	_fly_dir = _turn_toward(_fly_dir, wish, turn_speed * delta)

	var planar := _fly_dir * speed
	var k := clampf(acceleration * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, planar.x, k)
	velocity.z = lerpf(velocity.z, planar.z, k)
	velocity.y = _altitude_velocity(height, delta)
	_orient(_fly_dir, delta)


# Rotate `from` toward `to` about UP by at most `max_angle`. A constant turn
# RATE, like an aircraft, rather than easing — easing turns fast when far off
# and crawls as it closes, which is backwards for holding a circle.
func _turn_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	if to.length_squared() < 0.0001:
		return from
	var a := from.signed_angle_to(to, Vector3.UP)
	return from.rotated(Vector3.UP, clampf(a, -max_angle, max_angle)).normalized()


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("air"):
		if other == self or not (other is Node3D) or not is_instance_valid(other):
			continue
		var away: Vector3 = global_position - (other as Node3D).global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.01 and d < separation_radius:
			push += away / d * (1.0 - d / separation_radius)
	return push


# Terrain-following: holds a height above whatever is under it, so it clears a
# hill instead of flying into it.
func _altitude_velocity(height: float, delta: float) -> float:
	var error := (_ground_height() + height) - global_position.y
	return lerpf(velocity.y, clampf(error * altitude_smoothness, -cruise_speed, cruise_speed),
		clampf(altitude_smoothness * delta, 0.0, 1.0))


func _ground_height() -> float:
	if _ground_ray != null and _ground_ray.is_colliding():
		return _ground_ray.get_collision_point().y
	return _station.y


func _flat_body_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


# Yaw to the heading and roll into the turn. No pitch: it has nothing to dive
# at, and a nose-down scout reads as a crashing one.
func _orient(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.01:
		return
	var yaw := atan2(-dir.x, -dir.z)
	var turn := angle_difference(rotation.y, yaw)
	var roll := clampf(turn * 2.5, -bank_angle, bank_angle)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(rotation_speed * delta, 0.0, 1.0))
	rotation.z = lerpf(rotation.z, roll, clampf(4.0 * delta, 0.0, 1.0))
	rotation.x = lerpf(rotation.x, 0.0, clampf(3.0 * delta, 0.0, 1.0))


# ─────────────────────────────────────────────
# DEATH — kept vulnerable on purpose. See the header.
# ─────────────────────────────────────────────
# AN EMP TAKES OUT THE ROTORS, NOT JUST THE ORDERS. Enemy's version holds the
# robot still, which is right for something standing on the ground. This has
# no gravity, so an EMP'd drone would hang in mid-air, which reads as a bug
# rather than a hit. Losing the link at altitude means losing lift.
func _enter_ekill() -> void:
	if downed or not alive:
		return
	die()


# Crashes, lands, and stays repairable — super() keeps the downed path, so a
# Mechanic can walk over and stand it back up.
func enter_downed() -> void:
	if rotor_loop != null:
		rotor_loop.stop()
	super()


func _on_crash_started() -> void:
	if rotor_loop != null:
		rotor_loop.stop()


func _on_crash_landed() -> void:
	if rotor_loop != null:
		rotor_loop.stop()
