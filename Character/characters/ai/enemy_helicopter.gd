extends Soldier
class_name EnemyHelicopter

# ─────────────────────────────────────────────
# BOMBER DRONE — flies bombing runs over whoever it is fighting.
#
# (The class keeps its old name because scenes and missions reference it. The
# model is drone_variant_02_interceptor and the behaviour is a drone's.)
#
# WHAT IT USED TO DO, AND WHY IT FAILED. It was built as a gunship: on contact
# it flew to a point 26m off the target and HOVERED there. Three things went
# wrong at once:
#   - hovering made it a sitting duck, so every one was shot down
#   - releases went through the generic MOVE/AIM/FIRE combat roll, gated on
#     line of sight, so one drone rolled FIRE and dropped while its wingman kept
#     rolling MOVE and never dropped anything
#   - two drones in one squad flew to the SAME hover point and collided
#
# WHAT IT DOES NOW. A run is a straight, fast pass that crosses the target:
#
#   LOITER   no target — orbit the post at cruise altitude
#   APPROACH fly to an entry point lined up on the target
#   RUN      straight and fast along the line, dropping a stick of bombs
#   EXTEND   carry on past, then come round for the next pass
#
# THE DROP IS PHYSICS, NOT AIM. A bomb released from something moving at v,
# h metres up, keeps moving at v for sqrt(2h/g) seconds while it falls. So it
# has to be let go that far SHORT of the target — about 35m at run speed — and
# it arcs forward onto it. By the time it lands the drone is already past. The
# stick is spaced so it walks across the aim point rather than stacking on it.
#
# Each drone offsets its approach angle by its own instance, so wingmen fly
# different lines instead of the same one, and they push apart when close.
# ─────────────────────────────────────────────

enum Phase { LOITER, APPROACH, RUN, EXTEND }

@export_group("Flight")
## Altitude when transiting and loitering.
@export var cruise_height: float = 22.0
## Altitude on the bombing pass. Lower is more accurate and more menacing, and
## the drop maths uses the real height so any value here is self-consistent.
@export var run_height: float = 14.0
@export var altitude_smoothness: float = 2.2
@export var cruise_speed: float = 20.0
@export var run_speed: float = 27.0
## How quickly it can swing onto a new heading. Low enough that turns are
## visible arcs, which is what sells it as something flying rather than
## something being dragged around.
@export var turn_speed: float = 1.7
@export var bank_angle: float = 0.6
## Nose-down attitude on the pass, radians. Reads as a dive.
@export var dive_pitch: float = 0.2

@export_group("Bombing run")
@export var bombs_per_stick: int = 4
## Seconds between bombs in a stick. At run speed this spaces impacts a few
## metres apart, so the stick straddles the aim point.
@export var stick_interval: float = 0.15
## Straight-and-level distance before the release point. Needs to be long
## enough to settle onto the line, or the pass wobbles and the stick sprays.
@export var run_up: float = 40.0
## How far past the target it flies before turning for the next pass.
@export var extend_distance: float = 60.0
## How close to the entry point counts as having arrived and starting the pass.
@export var entry_capture: float = 30.0
## How far ahead along the line the run steers. Shorter snaps onto the line
## harder; longer settles more gently but takes more room to do it.
@export var run_lookahead: float = 25.0
## Sideways error still allowed at release. Beyond this the stick is withheld
## and the drone goes round again.
@export var line_tolerance: float = 9.0
## How far the predicted impact may run past the opening point and still start
## the stick. Narrow on purpose: miss it and the pass is flown again rather
## than bombs being dropped where they will not land on anything.
@export var release_window: float = 7.0
## Hostiles within this radius of the target are averaged into the aim point.
## Squads bunch up; bombing the middle of the bunch is the whole idea.
@export var cluster_radius: float = 10.0
## Played as a pass begins. The one chance a player gets to react, and the
## difference between a threat that feels fair and one that feels cheap.
@export var run_warning: AudioStreamPlayer3D

@export_group("Formation")
## Drones closer than this steer apart.
@export var separation_radius: float = 16.0
## Two passes aimed within this distance of each other count as the same target
## and are flown one at a time.
@export var deconflict_radius: float = 30.0
## How far past its aim point a drone has to be before the next one may start.
@export var deconflict_clearance: float = 25.0
@export var loiter_radius: float = 45.0

@export_group("Audio")
@export var rotor_loop: AudioStreamPlayer3D

var _phase: Phase = Phase.LOITER
var _heading: Vector3 = Vector3.FORWARD
var _aim: Vector3 = Vector3.ZERO
var _entry: Vector3 = Vector3.ZERO
var _extend_from: Vector3 = Vector3.ZERO
var _bombs_left: int = 0
var _drop_timer: float = 0.0
var _loiter_centre: Vector3 = Vector3.ZERO
var _loiter_angle: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _ground_ray: RayCast3D
var _lifted: bool = false
# Per-drone offset to every approach angle, so two drones in one squad start
# their runs on different lines rather than the same one.
var _lane: float = 0.0
# Where it is actually flying. Separate from the body facing on purpose — see
# the note in _steer() about why deriving one from the other stopped it turning.
var _fly_dir: Vector3 = Vector3.FORWARD


func _ready() -> void:
	super()
	_home = global_position
	_loiter_centre = global_position
	add_to_group("air")
	# Stable per instance, spread across roughly +/-40 degrees.
	_lane = deg_to_rad(float(get_instance_id() % 81) - 40.0)
	_loiter_angle = randf() * TAU
	_fly_dir = _flat_body_forward()

	# Built in code rather than authored, so no drone scene can ship without it.
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


# A squad order sets where it loiters, not a navmesh path — it flies over the
# terrain rather than around it.
func move_to(pos: Vector3) -> void:
	movement_target = pos
	_loiter_centre = pos


# The run decides every release. The inherited weapon loop would ALSO fire via
# the combat roll, lobbing grenades from wherever it happened to be.
func handle_weapon_logic(_delta: float) -> void:
	pass


# No MOVE/AIM/FIRE dice. That roll is what let one drone drop and its wingman
# not: the phases below replace it entirely.
func roll_combat_action() -> void:
	pass


func _update_facing(_delta: float) -> void:
	pass


# ─────────────────────────────────────────────
# FLIGHT
# ─────────────────────────────────────────────
func handle_movement(delta: float) -> void:
	if downed or ai_state == AIState.DEAD:
		return

	# SPAWN AIRBORNE. A reserve built at a ground objective point used to start
	# on the grass and climb straight up, which read as popping out of the
	# earth. Put it at altitude on the first frame instead.
	if not _lifted:
		_lifted = true
		var floor_y := _ground_height()
		if global_position.y < floor_y + cruise_height * 0.6:
			global_position.y = floor_y + cruise_height

	var has_target := has_live_target()
	match _phase:
		Phase.LOITER:
			if has_target:
				_begin_run(true)
			else:
				_tick_loiter(delta)
		Phase.APPROACH:
			if not has_target:
				_phase = Phase.LOITER
			else:
				_tick_approach(delta)
		Phase.RUN:
			_tick_run(delta)
		Phase.EXTEND:
			_tick_extend(delta, has_target)


func _tick_loiter(delta: float) -> void:
	# A slow orbit rather than a hover. It keeps the drone visibly alive and
	# moving, and a moving target is a harder one.
	_loiter_angle += delta * (cruise_speed * 0.5) / maxf(loiter_radius, 1.0)
	var p := _loiter_centre + Vector3(cos(_loiter_angle), 0.0, sin(_loiter_angle)) * loiter_radius
	_steer(p, cruise_speed * 0.6, cruise_height, delta, 0.0)


func _tick_approach(delta: float) -> void:
	_steer(_entry, cruise_speed, run_height, delta, 0.0)
	var to_entry := _entry - global_position
	to_entry.y = 0.0
	# Close enough — commit. Heading is deliberately NOT a condition here. It
	# used to be, and a drone arriving at the entry point is pointing wherever
	# it came FROM, which is rarely down the run line: it circled the entry
	# forever and never started a pass. The run below pulls it onto the line
	# from any heading, and the run-up is there to give it room to do that.
	# ONE DRONE ON A TARGET AT A TIME. Every pass is lined up on the aim point,
	# so however different the approach angles, two runs started together cross
	# directly over the target at the same moment — that was the collision.
	# Holding here until the other is clear staggers them into turns, which is
	# both safer and reads as deliberate: a pair working a target together.
	if to_entry.length() < entry_capture and not _pass_conflict():
		_phase = Phase.RUN
		_bombs_left = maxi(1, bombs_per_stick)
		_drop_timer = 0.0
		if run_warning != null:
			run_warning.play()


func _tick_run(delta: float) -> void:
	# PURE PURSUIT onto the run line. Project the drone onto the line, then
	# steer at a point a fixed distance further along it. From any position and
	# heading that converges onto the line pointing the right way — which is
	# the thing a straight "fly along the heading" cannot do: that flies
	# PARALLEL to the line, so any sideways offset at the start of the pass
	# stays there for the whole pass and the stick misses by exactly that much.
	var rel := global_position - _aim
	rel.y = 0.0
	var s := rel.dot(_heading)                 # along-track; negative = short of the aim
	var carrot := _aim + _heading * (s + run_lookahead)
	_steer(carrot, run_speed, run_height, delta, dive_pitch)

	# CONTINUOUSLY COMPUTED IMPACT POINT — where a bomb let go RIGHT NOW would
	# land, from the drone's actual velocity and height. Release when that point
	# reaches the target.
	#
	# The first version computed a fixed release distance from run_speed and a
	# level flight, and missed by a median of 14m, because neither was true at
	# the moment of release: the drone was usually still accelerating out of
	# the approach, and still descending from cruise height. A bomb inherits
	# that descent, falls faster, and lands short. Predicting the impact from
	# the real state makes the drop correct whatever the drone is doing.
	var impact := _predicted_impact()
	var impact_rel := impact - _aim
	impact_rel.y = 0.0
	var impact_along := impact_rel.dot(_heading)          # < 0 = would land short
	var impact_lateral := (impact_rel - _heading * impact_along).length()
	# Lined up means the BOMBS would land on the line, not merely that the
	# drone is near it — those differ whenever it is still turning.
	var lined_up := _flat_forward().dot(_heading) > 0.9 and impact_lateral < line_tolerance
	# Open the stick half its length early so the impacts straddle the aim
	# rather than all landing long.
	var half_stick := _ground_speed() * stick_interval * float(maxi(1, bombs_per_stick) - 1) * 0.5
	if _bombs_left > 0:
		var started := _bombs_left < maxi(1, bombs_per_stick)
		if started:
			# Stick in progress: keep the rhythm regardless. The spacing IS
			# the pattern, and stopping halfway would bunch it on one side.
			_drop_timer -= delta
			if _drop_timer <= 0.0:
				_release_one_bomb()
		elif lined_up and impact_along >= -half_stick and impact_along <= -half_stick + release_window:
			# Opening the stick only inside a narrow WINDOW. The first version
			# only checked "not short", with no upper bound — so a drone that
			# overshot without dropping dumped the whole stick 60m downrange.
			_release_one_bomb()
		# Past the window without starting: the pass is blown. Hold the bombs
		# and let it go round rather than scatter them over nothing.

	# Past the target — pull off and come round, whether or not the stick went.
	# A pass that never lined up is abandoned and flown again, as a real pilot
	# would, rather than chased.
	if s > extend_distance * 0.25:
		_phase = Phase.EXTEND
		_extend_from = global_position


func _tick_extend(delta: float, has_target: bool) -> void:
	_steer(global_position + _heading * 200.0, cruise_speed, cruise_height, delta, 0.0)
	if global_position.distance_to(_extend_from) >= extend_distance:
		if has_target:
			_begin_run(false)
		else:
			_phase = Phase.LOITER


# Commit to a pass: fix the aim point for the whole run, choose the line, and
# work out where to start it.
func _begin_run(first: bool) -> void:
	_aim = _aim_point()
	var yaw: float
	if first:
		# Straight in from wherever it is, offset by its lane.
		var to_aim := _aim - global_position
		to_aim.y = 0.0
		yaw = atan2(to_aim.x, to_aim.z) + _lane
	else:
		# Come back the other way, but not along the exact same line — a real
		# attack pattern varies the approach so the defenders cannot just
		# stand beside the last one.
		yaw = atan2(-_heading.x, -_heading.z) + deg_to_rad(randf_range(-55.0, 55.0))
	_heading = Vector3(sin(yaw), 0.0, cos(yaw)).normalized()
	_entry = _aim - _heading * (_release_distance() + run_up)
	_entry.y = _aim.y
	_phase = Phase.APPROACH


# Where the stick should land: the middle of whatever is bunched up around the
# current target. A squad standing together is the point of bombing at all.
func _aim_point() -> Vector3:
	if not has_live_target():
		return global_position
	var centre: Vector3 = combat_target.global_position
	var sum := Vector3.ZERO
	var n := 0
	for c in _visible_candidates():
		if c == null or not is_instance_valid(c) or not (c is Node3D):
			continue
		var p: Vector3 = (c as Node3D).global_position
		if p.distance_to(centre) <= cluster_radius:
			sum += p
			n += 1
	return sum / float(n) if n > 0 else centre


# True while another drone is mid-pass over roughly the same spot and has not
# yet cleared it. Its aim point is compared rather than its position, because
# what matters is whether the two LINES meet, not where the drones are now.
func _pass_conflict() -> bool:
	for other in get_tree().get_nodes_in_group("air"):
		if other == self or not is_instance_valid(other) or not (other is EnemyHelicopter):
			continue
		var o := other as EnemyHelicopter
		if o.downed or o._phase != Phase.RUN:
			continue
		if o._aim.distance_to(_aim) > deconflict_radius:
			continue
		# Still short of its aim, or only just past it: its line still owns
		# the airspace over the target.
		var rel := o.global_position - o._aim
		rel.y = 0.0
		if rel.dot(o._heading) < deconflict_clearance:
			return true
	return false


func _release_one_bomb() -> void:
	_drop_timer = stick_interval
	_bombs_left -= 1
	if weapon != null and weapon.has_method("drop_bomb"):
		weapon.drop_bomb()


# Where a bomb released this instant would come down, at the aim point's
# height. Solves the fall WITH the drone's current vertical velocity:
#   h + vy*t - g*t^2/2 = 0   =>   t = (vy + sqrt(vy^2 + 2*g*h)) / g
# vy is negative while descending, which shortens the fall — exactly the
# effect the level-flight version ignored.
func _predicted_impact() -> Vector3:
	var g: float = gravity if gravity > 0.0 else 9.8
	var origin := _drop_origin()
	var h: float = maxf(origin.y - _aim.y, 0.25)
	var vy: float = velocity.y
	var t: float = (vy + sqrt(vy * vy + 2.0 * g * h)) / g
	return Vector3(origin.x + velocity.x * t, _aim.y, origin.z + velocity.z * t)


# The bombs leave from the weapon's muzzle, not the body's centre.
func _drop_origin() -> Vector3:
	if weapon != null and "muzzle_origin" in weapon and weapon.muzzle_origin != null:
		return weapon.muzzle_origin.global_position
	return global_position


func _ground_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


# Planning estimate only: how far short of the target a pass must be set up,
# used to place the entry point before the drone is on the line. The actual
# release is decided by _predicted_impact() in flight.
func _release_distance() -> float:
	var h: float = maxf(global_position.y - _aim.y, 1.0)
	var g: float = gravity if gravity > 0.0 else 9.8
	return run_speed * sqrt(2.0 * h / g)


# ─────────────────────────────────────────────
# STEERING
# ─────────────────────────────────────────────
func _steer(target: Vector3, speed: float, height: float, delta: float, pitch: float) -> void:
	var to_target := target - global_position
	to_target.y = 0.0
	var wish := to_target.normalized() if to_target.length() > 0.01 else _flat_forward()

	# Push apart from nearby drones. Folded into the heading rather than added
	# to velocity, so they bank away from each other instead of sliding.
	wish = (wish + _separation() * 1.4).normalized()

	# THE FLIGHT DIRECTION IS ITS OWN STATE, turned at a fixed rate.
	#
	# It used to be derived from the body's facing (-basis.z), eased toward the
	# wish — while the body's facing ITSELF eased toward that eased direction.
	# Two lags chained: each frame the body chased a target only a sliver of
	# the way to where it needed to go, so the real turn rate collapsed to a
	# fraction of a percent of the angle per frame. The drone could not turn.
	# It flew a near-straight line and passed forty metres wide of the target.
	# Now the flight path turns at turn_speed rad/s and the body follows it
	# purely for looks.
	_fly_dir = _turn_toward(_fly_dir, wish, turn_speed * delta)

	var planar := _fly_dir * speed
	var k := clampf(acceleration * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, planar.x, k)
	velocity.z = lerpf(velocity.z, planar.z, k)
	velocity.y = _altitude_velocity(height, delta)
	_orient(_fly_dir, pitch, delta)


# Rotate `from` toward `to` about UP by at most `max_angle`. A constant turn
# RATE, like an aircraft, rather than easing — easing turns fast when far off
# and crawls as it gets close, which is exactly backwards for lining up a pass.
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


# Terrain-following: holds a height above whatever is under it.
func _altitude_velocity(height: float, delta: float) -> float:
	var error := (_ground_height() + height) - global_position.y
	return lerpf(velocity.y, clampf(error * altitude_smoothness, -run_speed, run_speed),
		clampf(altitude_smoothness * delta, 0.0, 1.0))


func _ground_height() -> float:
	if _ground_ray != null and _ground_ray.is_colliding():
		return _ground_ray.get_collision_point().y
	return _home.y


# The direction it is FLYING, which is what "lined up" has to mean — the body
# can be banked and yawed slightly off it without the pass being off.
func _flat_forward() -> Vector3:
	return _fly_dir


func _flat_body_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


# Yaw to the heading, roll into turns, pitch the nose down on a pass.
func _orient(dir: Vector3, pitch: float, delta: float) -> void:
	if dir.length_squared() < 0.01:
		return
	var yaw := atan2(-dir.x, -dir.z)
	var turn := angle_difference(rotation.y, yaw)
	var roll := clampf(turn * 2.5, -bank_angle, bank_angle)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(rotation_speed * delta, 0.0, 1.0))
	rotation.z = lerpf(rotation.z, roll, clampf(4.0 * delta, 0.0, 1.0))
	rotation.x = lerpf(rotation.x, -pitch, clampf(3.0 * delta, 0.0, 1.0))


# ─────────────────────────────────────────────
# DEATH
# ─────────────────────────────────────────────
# AN EMP TAKES OUT THE ROTORS, NOT JUST THE ORDERS.
#
# Enemy's version zeroes horizontal velocity and holds the robot where it is —
# right for something standing on the ground. This has no gravity, so an EMP'd
# drone froze in mid-air and hung there, which read as a bug rather than a hit.
# Losing its signal at altitude means losing lift: it goes down, and the
# ordinary airborne-death path makes it fall and crash.
#
# That makes the EMP an anti-air weapon, deliberately. It is a hard shot to
# make — the blast is 9m across and a drone on a pass is 14m up and moving at
# 27 m/s — so it earns the reward.
func _enter_ekill() -> void:
	if downed or not alive:
		return
	die()


# Belt and braces: the crash hooks only fire when it dies AIRBORNE. One that
# somehow dies on the ground would take the settle path and keep droning.
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
