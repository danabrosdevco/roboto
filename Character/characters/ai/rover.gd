extends Soldier

# ─────────────────────────────────────────────
# ROVER — a six-wheeled weapons carrier.
#
# Everything else in the squad is a body that turns on the spot and walks where
# it looks. This one DRIVES. It has a heading and steers like a car: it cannot
# turn without rolling, it slows for corners, and it backs up to reach a spot
# just behind it rather than turning round. Its gun sits in a turret that
# traverses on its own at a finite rate, so the hull can drive one way while
# the gun tracks another — and flanking one means getting round it faster than
# the turret can follow.
#
# Kinematic like every other robot, not a VehicleBody3D. Godot's vehicle is a
# RigidBody3D pushed about by forces, and everything the squad runs on —
# orders, formation, downed and repair, the spawners — is a CharacterBody3D
# moved by move_and_slide(). A physics car would need all of that again, plus a
# controller to hold it on a nav path it would keep skidding off. So this is a
# Soldier that drives: a bicycle model over the same path following, with the
# wheels, suspension and turret animated to match what the body really does.
# ─────────────────────────────────────────────

# ── DRIVING ───────────────────────────────────
## Front axle to middle axle, in metres. The rear wheels steer against the
## front, so the middle axle is the one that does not scrub, and this sets the
## turning circle: radius = wheelbase / tan(steer). 1.1m at 32 degrees is 1.8m.
@export var wheelbase: float = 1.1
@export var max_steer_degrees: float = 32.0
## How fast the wheels turn, degrees per second.
@export var steer_rate_degrees: float = 140.0
## Metres per second per second, gaining speed and losing it.
@export var drive_accel: float = 4.5
@export var brake_decel: float = 9.0
@export var reverse_speed: float = 3.2
## Somewhere behind it and nearer than this is reversed onto rather than driven
## round to. A loop to reach a spot four metres back reads as lost.
@export var reverse_within: float = 9.0
## Speed held through a hard turn, as a fraction of move_speed. One that took
## corners flat out would swing wide of every path.
@export_range(0.1, 1.0) var cornering_speed: float = 0.35

# ── GETTING OFF A WALL ────────────────────────
# A car cannot turn without rolling, so one with its nose on a wall and
# somewhere to be off to the side just sits there pushing. It gets out the way
# a driver does: a leg of a three-point turn — back up on the opposite lock,
# which swings the nose round towards where it is going, then drive on.
## Longest a single leg of a three-point turn runs.
@export var backoff_seconds: float = 1.4
## Throttle open and the wheels hardly turning for this long means it is up
## against something, and it takes the next leg rather than sit there pushing.
@export var pinned_after: float = 0.35
## How much room it wants ahead of the nose (or behind, reversing) before it
## commits to turning there, plus a little more per metre per second.
@export var bumper_clearance: float = 0.6

# ── PACK SPACING ──────────────────────────────
# A rover used to notice another one only by hitting it. _is_wall() ignores
# CharacterBody3D on purpose — a robot moves, and shoving one is caught as
# pinned — so nothing steered around a squadmate, and the first sign of one was
# _pinned_t tripping and a three-point turn starting. In a pack of four that is
# four rovers reversing into each other at once, which is how they ended up
# welded together in a heap in the middle of a field.
#
# So they keep station instead. A hull off to one side pushes this one's
# steering away from it; a hull close ahead going the same way takes the
# throttle off rather than shunting it; two nose to nose both go right, the way
# anything with a steering wheel does. All of it through the steering, so they
# peel apart like cars and the pack STAYS a pack — which is the whole point of
# fielding them together.
## How far out another vehicle starts pushing this one aside.
@export var spacing_radius: float = 9.0
## How hard that push steers, at its strongest, as a fraction of full lock.
@export var spacing_steer: float = 0.8
## A hull nearer than this, dead ahead and going the same way, is followed
## rather than rammed: the throttle comes off in proportion to how close it is.
@export var follow_gap: float = 6.0
## Lateral room this frame asks for in a formation line (Squad._line_spacing).
##
## This is the one that decides whether a pack looks like a pack or a scrum.
## Steering only keeps them off each other on the way; where they END UP is
## whatever the squad handed them, and at infantry spacing four rovers settle
## about 4.7m apart — close enough that they read as piled up and close enough
## that the next order has them shuffling round each other. At 8m the four of
## them hold a 24m frontage, which is an armoured line rather than a queue.
@export var line_spacing: float = 8.0
## Legs one order may take. Past that it stops where it is and lets whoever
## gave the order give another.
@export var max_manoeuvres: int = 10
@export var reverse_lamps: Array[Node3D] = []

# ── WRECKED ───────────────────────────────────
# What a dead one looks like. See _collapse_pieces: a hull this size cannot
# just sink, so it goes over on one side instead.
## How far it rolls onto the side it went over on.
@export var wreck_roll_degrees: float = 14.0
## And how far it goes down at the nose.
@export var wreck_nose_degrees: float = 6.0
## Belly clearance it gives up, as a multiple of belly_drop — down on its frame
## with the suspension gone. NOT a way to hide the model in the ground: at 2.2
## the hull sat 60cm under the deck, which is the sinking trick that does not
## work on something this size. The lean and the splayed wheels carry it.
@export var wreck_settle: float = 1.0
## How far the wheels on the low side drop, as if the suspension let go.
@export var wreck_wheel_sag: float = 0.12
## Where the barrel ends up. Past gun_min_pitch_degrees deliberately.
@export var wreck_barrel_degrees: float = -30.0

# ── TURRET ────────────────────────────────────
@export var turret_traverse_degrees: float = 95.0   # per second
@export var gun_elevation_degrees: float = 60.0     # per second
@export var gun_min_pitch_degrees: float = -8.0
@export var gun_max_pitch_degrees: float = 30.0
## How near the target the gun has to point before it opens up.
@export var fire_cone_degrees: float = 6.0

# ── RIG ───────────────────────────────────────
## Everything drawn. Pitches and rolls to sit on the ground under it — the body
## itself stays upright like every CharacterBody3D.
@export var rig: Node3D
@export var turret: Node3D
@export var gun_pivot: Node3D
## Pivots at the wheel centres, each with a child named "Spin" that rolls.
@export var wheels: Array[Node3D] = []
## Per wheel, in the same order: 1 steers with the front, -1 against it, 0 fixed.
@export var wheel_steer: Array[float] = []
@export var wheel_radius: float = 0.36
## How far a wheel can ride up or hang down to follow the ground.
@export var suspension_travel: float = 0.16
## How far the hull drops onto its belly when it is knocked out.
@export var belly_drop: float = 0.24

var _steer: float = 0.0          # wheel angle now, radians; + is left
var _manoeuvre_t: float = 0.0    # seconds left of the current turn leg
var _manoeuvre_gear: float = 0.0 # -1 backing out, +1 pulling forward out
var _manoeuvre_steer: float = 0.0
var _manoeuvres: int = 0         # legs taken on this order
var _pinned_t: float = 0.0
var _command: float = 0.0        # drive speed asked for this frame, signed
var _driving: bool = false       # move_along_nav ran this frame
var _gave_up_at := Vector3.INF   # where it last ran out of turn legs, for the warning
var _last_pos: Vector3
var _last_speed: float = 0.0
var _wheel_rest: Array[Vector3] = []
var _wheel_lift: Array[float] = []
var _rig_rest: Transform3D
var _tilt := Vector3.ZERO        # pitch, heave, roll — smoothed
var _still_frames: int = 0
var _ray: PhysicsRayQueryParameters3D
var _spins: Array[Node3D] = []
var _rolled: float = 0.0          # metres along the hull last frame, signed
var _nav_end := Vector3.INF       # where the current path ends
var _path_fresh: bool = false     # the path is for the current order

## How hard it slows for the end of a path. Gentler than brake_decel: a
## vehicle rolling up to where it was sent, not stopping for an obstacle.
const ARRIVAL_DECEL := 3.0


func _ready() -> void:
	if rig != null:
		_rig_rest = rig.transform
	for w in wheels:
		_wheel_rest.append(w.position if w != null else Vector3.ZERO)
		_wheel_lift.append(0.0)
		_spins.append(w.get_node_or_null(^"Spin") as Node3D if w != null else null)
	if turret == null:
		push_warning("%s has no turret: it will turn its whole hull to aim, which fights the steering." % name)
	if wheel_steer.size() != wheels.size():
		push_warning("%s: %d wheels but %d steering entries; the extra wheels will not steer." % [name, wheels.size(), wheel_steer.size()])
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.exclude = [get_rid()]
	_last_pos = global_position
	# The gun drawn on the mount in the editor and in the icon. By now a fitted
	# weapon has already cleared the mount; with none fitted, the turret is
	# empty, and must not look armed.
	var display := weapon_mount.get_node_or_null(^"DisplayGun") if weapon_mount != null else null
	if display != null:
		display.queue_free()
	super()


func _physics_process(delta: float) -> void:
	super(delta)
	if movement_state == MovementState.NONE:
		_manoeuvre_t = 0.0   # stopped: an unfinished leg is not owed to the next order
	if not downed and alive:
		_tick_rig(delta)


# ─────────────────────────────────────────────
# DRIVING
# ─────────────────────────────────────────────
# A leg of a turn already under way survives a new order. A squad re-orders a
# follower every time the player shifts, and combat re-rolls a move every two
# seconds: cancelling the back-out each time (and move_to() restarting the
# three-second stuck check each time) is how a rover stayed pinned to a wall for
# as long as you were moving or fighting nearby.
func move_to(pos: Vector3):
	if pos.distance_to(movement_target) > 6.0:
		_manoeuvres = 0   # somewhere new, not the same spot again
	_path_fresh = false
	super(pos)


# The agent counts a path point reached within path_desired_distance in 3D,
# from the body's origin — 0.85m above the path, on this frame. A car doing
# seven metres a second went straight past the end of every path and then
# shuffled back and forth trying to stand on it. So the end of the path counts
# within arrival_radius, flat, the way the rest of the rover parks.
#
# Only on a path worked out for the current order: set_target_position() does
# not replace the old path until the next query, and the old one ends where it
# is already parked — every new order would have arrived on the spot.
func _tick_nav(delta: float) -> void:
	var due := _nav_think_timer - delta
	super(delta)
	if _nav_think_timer > due + 0.0001:
		_path_fresh = true   # a query ran: the path is for what it was last told
		var path := nav_agent.get_current_navigation_path()
		_nav_end = path[path.size() - 1] if not path.is_empty() else Vector3.INF
	if _path_fresh and _nav_end != Vector3.INF and _flat_gap(_nav_end) <= arrival_radius:
		_nav_finished = true


func _flat_gap(to: Vector3) -> float:
	return Vector2(to.x - global_position.x, to.z - global_position.z).length()


# Replaces walking straight down the path. Same cached direction, but it has to
# be steered onto.
func move_along_nav(delta):
	var fwd := _hull_forward()
	var speed := _speed_along(fwd)
	var target_speed := 0.0
	var steer_to := 0.0
	var max_steer := deg_to_rad(max_steer_degrees)
	var has_path := _nav_dir.length() >= 0.15
	var err := _nav_error()

	# Pushing and not rolling — driving, or mid-leg into something the bumper
	# does not count, like a squadmate: the next leg, the other way.
	if _pinned_t >= pinned_after:
		_pinned_t = 0.0
		_start_manoeuvre(-signf(_command) if absf(_command) > 0.0 else -1.0, err)

	if _manoeuvre_t > 0.0:
		_manoeuvre_t -= delta
		target_speed = _manoeuvre_gear * reverse_speed
		steer_to = _manoeuvre_steer
		# A leg ends once there is nothing more to gain from it. Out of room
		# backing up, it pulls forward on the other lock — the many-point turn,
		# for a spot too tight for three. Pointing its way with room to go, it
		# drives on.
		if _blocked(_manoeuvre_gear, speed):
			_manoeuvre_t = 0.0
			if _manoeuvre_gear < 0.0 and not _blocked(1.0, 0.0):
				_start_manoeuvre(1.0, err)
		elif has_path and absf(err) < deg_to_rad(35.0 if _manoeuvre_gear < 0.0 else 20.0) and not _blocked(1.0, 0.0):
			_manoeuvre_t = 0.0
	elif has_path:
		var want := _nav_dir.normalized()
		if absf(err) > deg_to_rad(115.0) and global_position.distance_to(_goal()) < reverse_within \
				and not _blocked(-1.0, speed):
			# Reverse onto it. Backing up, the wheels steer the tail, so the
			# lock is the other way round.
			steer_to = -(-fwd).signed_angle_to(want, Vector3.UP) * 1.8
			target_speed = -reverse_speed
		elif absf(err) > deg_to_rad(20.0) and _blocked(1.0, speed):
			# A wall right where it has to turn: no room to turn in. Out first.
			_start_manoeuvre(-1.0, err)
		else:
			# Off the walls either side as it goes. The navmesh is laid out for
			# robots on foot and hugs corners a hull this wide cannot make.
			steer_to = err * 1.8 + (_whisker(1.0, speed) - _whisker(-1.0, speed)) * max_steer
			var sharp := clampf(absf(err) / deg_to_rad(90.0), 0.0, 1.0)
			target_speed = move_speed * lerpf(1.0, cornering_speed, sharp)
			# And room for the rest of the pack.
			var pack := _pack_spacing(fwd)
			steer_to += pack.x * max_steer
			target_speed = minf(target_speed, pack.y)
			# Come off the throttle for the end of the path rather than
			# arriving flat out and rolling on past it.
			if _path_fresh and _nav_end != Vector3.INF:
				var left := _flat_gap(_nav_end) - arrival_radius * 0.5
				target_speed = minf(target_speed, maxf(sqrt(2.0 * ARRIVAL_DECEL * maxf(left, 0.0)), 1.2))

	_steer = move_toward(_steer, clampf(steer_to, -max_steer, max_steer), deg_to_rad(steer_rate_degrees) * delta)
	var speeding_up := absf(target_speed) > absf(speed) and target_speed * speed >= 0.0
	speed = move_toward(speed, target_speed, (drive_accel if speeding_up else brake_decel) * delta)
	# Bicycle model about the middle axle, on how far the wheels actually rolled
	# last frame — not on the speed asked for. Pressed against a wall with the
	# throttle open it went nowhere and swung round on the spot.
	rotation.y += _rolled / maxf(wheelbase, 0.1) * tan(_steer)
	fwd = _hull_forward()
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	_command = speed
	_driving = true
	if absf(speed) > 0.3:
		_last_move_dir = fwd * signf(speed)


# Signed angle from the hull's heading to the way the path goes; + is left.
func _nav_error() -> float:
	var to := _nav_dir if _nav_dir.length_squared() > 0.0225 else _goal() - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return 0.0
	return _hull_forward().signed_angle_to(to.normalized(), Vector3.UP)


# One leg of a three-point turn. Backing out, the lock goes AWAY from where it
# is heading, which swings the nose round towards it; pulling forward, the lock
# points where it is heading.
func _start_manoeuvre(gear: float, err: float) -> void:
	if _manoeuvres >= max_manoeuvres:
		# Wedged somewhere it cannot turn out of. Stop, and let the squad or the
		# next combat roll send it somewhere it can get to.
		if _gave_up_at.distance_to(global_position) > 3.0:
			push_warning("%s: %d turn legs and still stuck at %s; stopping there." % [name, _manoeuvres, global_position.round()])
			_gave_up_at = global_position
		_manoeuvres = 0
		_manoeuvre_t = 0.0
		halt()
		return
	_manoeuvres += 1
	_manoeuvre_gear = -1.0 if gear < 0.0 else 1.0
	_manoeuvre_t = backoff_seconds
	var side := signf(err) if absf(err) > 0.05 else (1.0 if randf() < 0.5 else -1.0)
	_manoeuvre_steer = (side if _manoeuvre_gear > 0.0 else -side) * deg_to_rad(max_steer_degrees)


# Something solid just off the nose (gear > 0) or the tail (gear < 0), at the
# height of the hull's widest point: a wall — not a slope it can drive up, and
# not a robot, which moves (and pushing into one is caught as pinned anyway).
func _blocked(gear: float, speed: float) -> bool:
	if gear == 0.0 or not is_inside_tree():
		return false
	var dir := _hull_forward() * signf(gear)
	var from := global_position + dir * 1.2 + Vector3.DOWN * 0.1
	_ray.from = from
	_ray.to = from + dir * (0.5 + bumper_clearance + absf(speed) * 0.15)
	return _is_wall(get_world_3d().direct_space_state.intersect_ray(_ray))


# How near a wall is off one front corner: 0 for nothing in reach, towards 1
# for touching. side is -1 for the left corner, +1 for the right.
func _whisker(side: float, speed: float) -> float:
	if not is_inside_tree():
		return 0.0
	var from: Vector3 = global_position + global_transform.basis * Vector3(0.75 * side, -0.1, -1.2)
	var dir := _hull_forward().rotated(Vector3.UP, deg_to_rad(-28.0) * side)
	var reach := 1.4 + absf(speed) * 0.2
	_ray.from = from
	_ray.to = from + dir * reach
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if not _is_wall(hit):
		return 0.0
	return 1.0 - from.distance_to(hit.position) / reach


# What the neighbouring hulls want of this one:
#   x  steer bias, -1..1 of full lock, + is left (same sign as _steer)
#   y  a speed cap, INF when nothing is in the way
#
# Only vehicles count. Infantry are small, they give way on their own, and a
# rover that flinched off every soldier walking past would never drive in a
# straight line through its own squad.
func _pack_spacing(fwd: Vector3) -> Vector2:
	var bias := 0.0
	var cap := INF
	# By script rather than a class_name: rover.gd has never declared one, and
	# adding a global class an open editor has not indexed yet is how you take
	# the whole front end down (see the note in master.gd).
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other) or other.get_script() != get_script():
			continue
		var them: Soldier = other
		if not them.alive:
			continue   # a wreck is terrain, and the whiskers already see it
		var away: Vector3 = global_position - them.global_position
		away.y = 0.0
		var gap := away.length()
		if gap < 0.01 or gap > spacing_radius:
			continue
		var to_them := -away / gap
		var ahead := fwd.dot(to_them)
		if ahead < -0.2:
			continue   # behind: their problem to solve, not this one's
		var strength := (1.0 - gap / spacing_radius) * spacing_steer
		# Beside, and getting nearer: steer off it. sin of the bearing, so
		# something square on the flank pushes hardest and something dead ahead
		# not at all — that case is the two below.
		var bearing := fwd.signed_angle_to(to_them, Vector3.UP)
		bias -= sin(bearing) * strength
		if ahead <= 0.75:
			continue
		if fwd.dot(them._hull_forward()) > 0.3:
			# Nose to tail, both going the same way: fall in behind it. Easing
			# to a stop at contact rather than braking late, so a column
			# concertinas instead of rear-ending itself.
			cap = minf(cap, move_speed * clampf(gap / maxf(follow_gap, 0.1), 0.0, 1.0))
		else:
			# Nose to nose. Both of them read it the same way and both go
			# right, which is the one rule that resolves it without the two
			# agreeing on anything first.
			bias -= strength
	return Vector2(bias, cap)


func _is_wall(hit: Dictionary) -> bool:
	if hit.is_empty() or hit.collider is CharacterBody3D:
		return false
	return absf((hit.normal as Vector3).y) < 0.6


# Where this leg of driving ends: whoever it is chasing, or where it was sent.
func _goal() -> Vector3:
	if movement_state == MovementState.CHASING and combat_target != null and is_instance_valid(combat_target):
		return combat_target.global_position
	return movement_target


# The base answer to a blocked path is a sidestep of three or four metres — for
# a car that cannot step sideways, and that counts anywhere within
# arrival_radius as there, a detour it "arrives" at before it has moved.
func _handle_path_blocked() -> void:
	if _nav_finished:
		# The path ends short of where it was sent: the spot is off the navmesh
		# or past a gap it cannot fit, and this is as near as it gets. Stop here
		# — and in a fight, fight from here, as the base does once it gives up.
		movement_state = MovementState.NONE
		if ai_state == AIState.COMBAT:
			var options := AllowedCombatOptions.duplicate()
			options.erase(CombatOptions.MOVE)
			if not options.is_empty():
				perform_action(options[randi_range(0, options.size() - 1)])
		return
	# Three seconds on the throttle without getting anywhere, in some way the
	# pinned check missed — scraping along a wall still turns the wheels.
	_start_manoeuvre(-1.0, _nav_error())


# It parks within arrival_radius of a spot rather than on it, so that is how
# near counts as there. At the squad's 1.6m a parked rover was never in its slot
# and got re-ordered every tick.
func slot_tolerance(squad_tolerance: float) -> float:
	# UNLESS IT IS PARKED ON A SQUADMATE. 3.5m of slack either side means two
	# neighbours can both stop three metres off their slots towards each other
	# and both call it arrived, which is how an 8m line collapses back into a
	# huddle. Crowded, it wants the slot it was actually given, so the squad
	# keeps sending it there until it has room.
	if _crowded():
		return maxf(squad_tolerance, 1.0)
	return maxf(squad_tolerance, arrival_radius)


# A line of these stands wider than a line of infantry, or they park in each
# other's slots. See Squad._line_spacing.
func formation_width() -> float:
	return line_spacing


# Another hull near enough that standing here is standing in its way.
func _crowded() -> bool:
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other) or other.get_script() != get_script():
			continue
		if not (other as Soldier).alive:
			continue
		if _flat_gap((other as Node3D).global_position) < line_spacing * 0.5:
			return true
	return false


# Vehicles do not take cover; they are cover. The cover points in a level are
# sized for a robot on foot, and this one would park on top of them.
func enter_cover_seeking() -> void:
	change_soldier_state(SoldierState.NONE)


func takes_cover() -> bool:
	return false


func _hull_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


func _speed_along(fwd: Vector3) -> float:
	return Vector2(velocity.x, velocity.z).dot(Vector2(fwd.x, fwd.z))


# ─────────────────────────────────────────────
# TURRET
# ─────────────────────────────────────────────
# The body's version turns the whole robot. Here the hull belongs to the
# driving, so the same choice of what to look at turns the turret instead.
func _update_facing(delta: float) -> void:
	if turret == null:
		super(delta)   # warned about in _ready
		return
	var face := _desired_facing()
	if face != Vector3.ZERO:
		var local := global_transform.basis.inverse() * face
		var want_yaw := atan2(-local.x, -local.z)
		turret.rotation.y = rotate_toward(turret.rotation.y, want_yaw, deg_to_rad(turret_traverse_degrees) * delta)
	if gun_pivot != null:
		var want_pitch := 0.0
		if ai_state == AIState.COMBAT and weapon_target != Vector3.ZERO:
			var to := weapon_target - gun_pivot.global_position
			want_pitch = atan2(to.y, Vector2(to.x, to.z).length())
		want_pitch = clampf(want_pitch, deg_to_rad(gun_min_pitch_degrees), deg_to_rad(gun_max_pitch_degrees))
		gun_pivot.rotation.x = rotate_toward(gun_pivot.rotation.x, want_pitch, deg_to_rad(gun_elevation_degrees) * delta)


func _turret_forward() -> Vector3:
	var f := -(turret.global_transform.basis.z if turret != null else global_transform.basis.z)
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else _hull_forward()


func _sight_forward() -> Vector3:
	return _turret_forward()


func _weapon_on_target() -> bool:
	var to := weapon_target - global_position
	to.y = 0.0
	if to.length_squared() < 0.25:
		return true   # on top of it: any bearing is as good as another
	return rad_to_deg(_turret_forward().angle_to(to.normalized())) <= fire_cone_degrees


# ─────────────────────────────────────────────
# RIG — wheels, suspension, lean
# ─────────────────────────────────────────────
# Drawn from what the body actually did this frame, not from what the driving
# asked for, so a rover shoved by a wall or coasting to a stop still rolls
# right.
func _tick_rig(delta: float) -> void:
	var moved := global_position - _last_pos
	_last_pos = global_position
	var fwd := _hull_forward()
	var travelled := Vector2(moved.x, moved.z).dot(Vector2(fwd.x, fwd.z))
	_rolled = travelled
	# Asking for speed and not making a quarter of it: up against something.
	if _driving and absf(_command) > 1.0 and absf(travelled) < absf(_command) * delta * 0.25:
		_pinned_t += delta
	else:
		_pinned_t = 0.0
	# The wheels turn at the speed the drive asks for, not the speed it makes.
	# Pinned against a wall they spin, so you can see it is trying — and which
	# way — rather than a rover sitting dead still.
	var wheel_speed := _command if _driving else travelled / maxf(delta, 0.0001)
	_driving = false
	var spin := wheel_speed * delta / maxf(wheel_radius, 0.05)
	for i in wheels.size():
		var w := wheels[i]
		if w == null:
			continue
		w.rotation.y = _steer * (wheel_steer[i] if i < wheel_steer.size() else 0.0)
		if _spins[i] != null:
			_spins[i].rotate_x(-spin)   # forward is -Z: the top of the tyre rolls that way
	for lamp in reverse_lamps:
		if lamp != null:
			lamp.visible = wheel_speed < -0.3

	var speed := travelled / maxf(delta, 0.0001)
	var accel := (speed - _last_speed) / maxf(delta, 0.0001)
	_last_speed = speed
	if absf(travelled) < 0.002 and absf(accel) < 0.1:
		_still_frames += 1
	else:
		_still_frames = 0
	# Parked and settled: the ground under it is not going anywhere. Rays only
	# while it moves, and the lean with them.
	if rig == null or _still_frames > 30 or lod_scale() > 2.0:
		return

	var ground := _ground_under_wheels()
	var fit := _terrain_fit(ground)
	var pitch := fit.x
	var heave := fit.y
	var roll := fit.z
	# And the weight moving about: the nose lifts under power and dives under
	# braking, and it leans out of a turn.
	var yaw_rate := speed / maxf(wheelbase, 0.1) * tan(_steer)
	pitch += clampf(accel * 0.012, -0.05, 0.05)
	roll += clampf(-speed * yaw_rate * 0.015, -0.06, 0.06)

	var k := 1.0 - exp(-10.0 * delta)
	_tilt = _tilt.lerp(Vector3(pitch, heave, roll), k)
	var pose := _rig_rest
	pose.origin.y += _tilt.y
	pose.basis = Basis.from_euler(Vector3(_tilt.x, 0.0, _tilt.z)) * pose.basis
	rig.transform = pose

	# Each wheel takes up whatever the tilted hull does not.
	for i in ground.size():
		var w := wheels[i]
		if w == null:
			continue
		var rest: Vector3 = _wheel_rest[i]
		var plane := _tilt.y + rest.z * -tan(_tilt.x) + rest.x * tan(_tilt.z)
		_wheel_lift[i] = lerpf(_wheel_lift[i], clampf(ground[i] - plane, -suspension_travel, suspension_travel), k)
		w.position = rest + Vector3.UP * _wheel_lift[i]


# How far each wheel's contact is above (+) or below (-) where it sits at rest,
# within the suspension's travel. Empty if the body is not in a world.
func _ground_under_wheels() -> Array[float]:
	var out: Array[float] = []
	if not is_inside_tree():
		push_warning("%s: not in the tree, so the suspension has nothing to feel." % name)
		return out
	var space := get_world_3d().direct_space_state
	for i in wheels.size():
		var at: Vector3 = global_transform * _wheel_rest[i]
		_ray.from = at + Vector3.UP * (suspension_travel + 0.3)
		_ray.to = at + Vector3.DOWN * (wheel_radius + suspension_travel + 0.3)
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			out.append(-suspension_travel)   # nothing under it: hanging
			continue
		var contact_y: float = (hit.position as Vector3).y
		out.append(clampf(contact_y + wheel_radius - at.y, -suspension_travel, suspension_travel))
	return out


# The hull's pose over this ground, from where each wheel's contact is: pitch,
# heave and roll (x, y, z), the ground alone — nothing for how it is moving.
func _terrain_fit(ground: Array[float]) -> Vector3:
	if ground.is_empty():
		return Vector3.ZERO
	var front := 0.0
	var back := 0.0
	var left := 0.0
	var right := 0.0
	var nf := 0
	var nb := 0
	var nl := 0
	var nr := 0
	var heave := 0.0
	for i in ground.size():
		var rest: Vector3 = _wheel_rest[i]
		var lift: float = ground[i]
		heave += lift
		if rest.z < -0.3:
			front += lift
			nf += 1
		elif rest.z > 0.3:
			back += lift
			nb += 1
		if rest.x < 0.0:
			left += lift
			nl += 1
		else:
			right += lift
			nr += 1
	var pitch := atan2(front / nf - back / nb, _axle_spread()) if nf > 0 and nb > 0 else 0.0
	var roll := atan2(right / nr - left / nl, _track()) if nl > 0 and nr > 0 else 0.0
	return Vector3(pitch, heave / ground.size(), roll)


func _axle_spread() -> float:
	var lo := INF
	var hi := -INF
	for p in _wheel_rest:
		lo = minf(lo, p.z)
		hi = maxf(hi, p.z)
	return maxf(hi - lo, 0.5)


func _track() -> float:
	var lo := INF
	var hi := -INF
	for p in _wheel_rest:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	return maxf(hi - lo, 0.5)


# ─────────────────────────────────────────────
# KNOCKED OUT
# ─────────────────────────────────────────────
# A vehicle does not fall over. The suspension gives: the hull drops onto its
# belly between wheels that splay out, and the gun sags. Every part moved is
# recorded in _piece_rest, so the base revive() puts it all back.
func _collapse_pieces() -> void:
	var parts: Array[Node3D] = [rig, turret, gun_pivot]
	parts.append_array(wheels)
	for p in parts:
		if p != null and not _piece_rest.has(p):
			_piece_rest[p] = p.transform
	# WHICH WAY IT WENT OVER.
	#
	# A rover is too much model to read as dead by sinking: sunk a little it is
	# just a rover parked in a dip, and sunk a lot it is a rover in a hole. So
	# it goes over instead. One side takes the weight — the hull rolls that
	# way, and the wheels on that side sag under it — which breaks the level,
	# symmetrical, on-its-wheels silhouette that made it look like it was
	# waiting for orders. Everything below is chosen to be visible in a glance
	# from across a field, because that is where you will be looking from.
	var over := 1.0 if randf() < 0.5 else -1.0
	if rig != null:
		# Posed over the ground as it is, not from the lean it had on the move.
		# Started from that, a rover caught braking stayed pitched onto its nose
		# and the collapse tipped it further: front wheels 20cm into the dirt.
		var fit := _terrain_fit(_ground_under_wheels())
		var pose := _rig_rest
		pose.origin.y += fit.y - belly_drop * wreck_settle
		pose.basis = Basis.from_euler(Vector3(fit.x + deg_to_rad(-wreck_nose_degrees), 0.0,
			fit.z + deg_to_rad(wreck_roll_degrees * over + randf_range(-2.5, 2.5)))) * pose.basis
		rig.transform = pose
	if turret != null:
		# Knocked round off its bearing rather than parked facing front. A
		# turret still pointed where it was aiming reads as a live gun.
		turret.rotation.y += deg_to_rad(randf_range(50.0, 125.0)) * (1.0 if randf() < 0.5 else -1.0)
	if gun_pivot != null:
		# And the barrel goes down into the dirt, well past the elevation limit
		# it honours while it is alive: nothing is holding it up any more.
		gun_pivot.rotation.x = deg_to_rad(wreck_barrel_degrees)
	for i in wheels.size():
		var w := wheels[i]
		if w == null:
			continue
		# Each wheel on the ground under it as the hull comes down between
		# them, tops leaning out.
		w.position = _wheel_rest[i]
		w.position.y += _ground_gap(w)
		var outward := 1.0 if _wheel_rest[i].x < 0.0 else -1.0   # +Z roll tips a top towards -X
		w.rotation.z = deg_to_rad(randf_range(26.0, 36.0)) * outward
		# The side it went over on has collapsed under it.
		if signf(_wheel_rest[i].x) == over:
			w.position.y -= wreck_wheel_sag
	# Nothing is running any more. The lamps are driven from the wheel speed in
	# _tick_rig, which stops with the rest of the brain, so whatever they were
	# doing at the moment of death is what they would have kept doing.
	for lamp in reverse_lamps:
		if lamp != null:
			lamp.visible = false


# How far a wheel has to move up (+) or down (-) for its tyre to sit on the
# ground beneath it. With nothing below, as far as the hull dropped.
func _ground_gap(w: Node3D) -> float:
	if not is_inside_tree():
		return belly_drop
	var at := w.global_position
	_ray.from = at + Vector3.UP * (belly_drop + 0.6)
	_ray.to = at + Vector3.DOWN * (wheel_radius + belly_drop + 0.6)
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		return belly_drop
	var reach := belly_drop + suspension_travel + 0.1
	return clampf((hit.position as Vector3).y + wheel_radius - at.y, -reach, reach)
