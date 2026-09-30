extends AIWeapon
class_name AIWeaponGrenadeLauncher

# ─────────────────────────────────────────────
# GRENADE DROP-LAUNCHER — the quadcopter bomber's ordnance.
#
# Extends AIWeapon rather than AIWorldWeapon. There are two weapon base classes
# in this project and only AIWeapon is the one Enemy.weapon is typed against;
# the older AIWeaponDroneBomb extends AIWorldWeapon and therefore cannot be
# fitted to a chassis at all.
#
# Only check_damage() is overridden. Everything that makes a weapon behave like
# a weapon — magazine, reload timer, fire cooldown, shot audio, muzzle flash,
# friendly_in_line, near-miss suppression — is inherited and keeps working.
# Hitscan is replaced with "release a grenade and let physics have it".
#
# THE ARC IS COMPUTED, NOT GUESSED. A helicopter is moving and high up, so
# aiming at where the target is now drops the round behind it. The lead comes
# from the fall time at the current altitude, which is the honest version of
# "drop it early" and costs one square root.
# ─────────────────────────────────────────────

@export var grenade_scene: PackedScene
## Forward shove on release. Zero is a pure drop; a little forward makes it
## read as launched rather than jettisoned.
@export var launch_speed: float = 6.0
## Inherited from the launcher's own motion, so a fast pass throws long.
@export var inherit_carrier_velocity: float = 0.85
## Rounds released per trigger pull. A short stick reads better than singles
## from something this size.
@export var salvo: int = 2
@export var salvo_spacing: float = 0.12
## Spread across the salvo, in metres at the target.
@export var salvo_scatter: float = 2.5
## Fuse override. Left at 0 the projectile keeps its own.
@export var fuse_override: float = 0.0
## What the playtest log calls this launcher's blasts. Left empty they are
## scored by the round's own scene, which is the hand grenade's, so every
## launcher in the game reported zero damage and its kills showed up under
## Frag. Set it to whatever the weapon is called and the shots and the damage
## land in the same row.
@export var analytics_label: String = ""
## Fires on the HIGH solution instead of the low one: the same speed, the other
## root of the same equation, steep up and steep down. That is what a mortar
## is — over a wall and down behind it, where a flat lob would hit the wall.
@export var high_arc: bool = false
## Widens the round's blast, in metres. 0 keeps the round's own.
@export var blast_radius_override: float = 0.0
## Blast override, passed to the round. Left at 0 the projectile keeps its own,
## which is the hand grenade's. A launcher that puts two of these downrange on
## every pull should not each hit as hard as the one you throw by hand.
@export var blast_override: int = 0
## FROM THE GROUND. Above zero, each round leaves the muzzle at this speed on
## the low ballistic arc that comes down on the target — a launcher on a
## turret, lobbing over cover. Zero is the quadcopter bomber's drop from altitude.
@export var lob_speed: float = 0.0
## Goes off on the first thing it hits instead of on the fuse: a launched
## round, not a hand grenade rolling about at the far end.
@export var impact_fused: bool = false

# Bombs from the current stick still in the air. See drop_bomb().
var _recent_bombs: Array = []


func check_damage(weapon_target: Vector3) -> void:
	if grenade_scene == null:
		push_warning("AIWeaponGrenadeLauncher on '%s' has no grenade_scene — it fires, makes noise, and nothing comes out." % name)
		return
	_release_salvo(weapon_target)


func _release_salvo(weapon_target: Vector3) -> void:
	for i in maxi(1, salvo):
		_release_one(weapon_target, i)
		if salvo_spacing > 0.0 and i < salvo - 1:
			await get_tree().create_timer(salvo_spacing, false).timeout
			# The launcher can be freed mid-salvo when the quadcopter bomber is shot down.
			if not is_inside_tree():
				return


## A TRUE DROP, for a bombing run. Released with the carrier's own velocity and
## nothing added — no aim, no lead, no forward shove.
##
## _release_one() aims: it computes a throw that lands on a point. That is the
## right model for something hovering and lobbing. A bomber that is already
## flying fast and straight does not aim its bombs at all; it lets go at the
## right MOMENT and physics carries them forward onto the target. The drone
## decides the moment, so this only has to let go.
func drop_bomb() -> void:
	if grenade_scene == null:
		return
	var origin: Vector3 = muzzle_origin.global_position if muzzle_origin != null else global_position
	var grenade := _spawn_charge(origin)
	# IMPACT-FUSED. The release point is computed so the bomb LANDS on the
	# target — but on the stock 3s fuse it landed after ~1.7s and then skidded
	# and bounced at run speed for the rest, detonating a median 18m downrange.
	# The aim was right; the bombs just did not stay where they were aimed.
	if "explode_on_bounce" in grenade:
		grenade.explode_on_bounce = true
		grenade.bounce_before_explode = 0

	# STICK-MATES MUST NOT TOUCH. Each bomb leaves one stick_interval after the
	# last, on the same trajectory, having fallen only ~10cm — so it spawns on
	# top of the previous one. Impact-fused, the two detonated each other at
	# the moment of release, fourteen metres up, and every stick "missed" by
	# exactly the release distance. Excepted against every bomb still falling,
	# not just the last, since three in a row can still overlap.
	_recent_bombs = _recent_bombs.filter(func(b): return b != null and is_instance_valid(b))
	if grenade is PhysicsBody3D:
		for b in _recent_bombs:
			if b is PhysicsBody3D:
				(grenade as PhysicsBody3D).add_collision_exception_with(b)
	_recent_bombs.append(grenade)
	if grenade is RigidBody3D:
		(grenade as RigidBody3D).linear_velocity = shooter_velocity()
		(grenade as RigidBody3D).angular_velocity = Vector3(
			randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
	play_shot_audio()


# Builds one charge at `origin`, owned by the carrier and unable to collide with
# it. Shared by the aimed throw and the bombing drop so neither can drift from
# the other on attribution or on the self-collision fix.
func _spawn_charge(origin: Vector3) -> Node:
	var grenade := grenade_scene.instantiate()
	# setup() BEFORE the tree, same contract the thrown grenade uses — the
	# projectile hands its thrower to the Explosion, which is what makes a
	# grenade kill count for somebody and what stops the quadcopter bomber blast-killing
	# its own escorts at full damage.
	var shooter := _owner_body()
	if grenade.has_method("setup"):
		grenade.setup(shooter)
	if fuse_override > 0.0 and "fuse_time" in grenade:
		grenade.fuse_time = fuse_override
	if blast_override > 0 and "blast_damage" in grenade:
		grenade.blast_damage = blast_override
	if analytics_label != "" and "analytics_label" in grenade:
		grenade.analytics_label = analytics_label
	if blast_radius_override > 0.0 and "blast_radius" in grenade:
		grenade.blast_radius = blast_radius_override
	_charge_parent(shooter).add_child(grenade)
	grenade.global_position = origin
	# A released charge must never collide with the thing that let go of it.
	# The drop spawns at the muzzle, which is INSIDE the carrier's own collider,
	# so move_and_slide() resolved the overlap by shoving the aircraft sideways.
	if shooter is PhysicsBody3D and grenade is PhysicsBody3D:
		(grenade as PhysicsBody3D).add_collision_exception_with(shooter)
	return grenade


# The carrier's LEVEL, not get_tree().current_scene. In this project the
# current scene is Master, so charges were parented above World and outlived
# the level they were dropped into — a bomb in the air at extraction came home
# with you. Parenting to the carrier's parent keeps them level-scoped, and
# does not depend on there being a current scene at all.
func _charge_parent(shooter: Node) -> Node:
	if shooter != null and shooter.get_parent() != null:
		return shooter.get_parent()
	if get_tree().current_scene != null:
		return get_tree().current_scene
	return get_tree().root


func _release_one(weapon_target: Vector3, index: int) -> void:
	var origin: Vector3 = muzzle_origin.global_position if muzzle_origin != null else global_position
	# Same spawn as the bombing drop — ownership, attribution, level-scoped
	# parenting and the self-collision exception all live in _spawn_charge().
	var grenade := _spawn_charge(origin)
	if impact_fused and "explode_on_bounce" in grenade:
		grenade.explode_on_bounce = true
		grenade.bounce_before_explode = 0

	if grenade is RigidBody3D:
		var body := grenade as RigidBody3D
		if lob_speed > 0.0:
			# The arc is solved without drag; the project's default damping
			# would drop every round a few metres short at range.
			body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
			body.linear_damp = 0.0
			body.linear_velocity = _lob_velocity(origin, weapon_target)
			# How long it will be up, for a round that wants to know: the
			# mortar's whistles for the last second or so of it.
			if "flight_time" in grenade:
				grenade.flight_time = _flight_time(origin, weapon_target, body.linear_velocity)
		else:
			body.linear_velocity = _release_velocity(origin, weapon_target, index)
		body.angular_velocity = Vector3(
			randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))


# The velocity a round would leave `origin` with to land on `target`. Public so
# whatever carries the launcher can point the tube along it before it fires —
# the Reclaimer's boom does, so the mortar is visibly elevated for the shot it
# is about to take.
func launch_velocity(origin: Vector3, target: Vector3) -> Vector3:
	return _lob_velocity(origin, target)


# The arc at lob_speed, from the muzzle onto the target: the low one, or the
# high one if high_arc. Out of reach, it throws at 45 degrees — as far as it
# can — and lands short.
func _lob_velocity(origin: Vector3, weapon_target: Vector3) -> Vector3:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var flat := Vector3(weapon_target.x - origin.x, 0.0, weapon_target.z - origin.z)
	var d := flat.length()
	var dir := flat / d if d > 0.01 else global_transform.basis.x   # weapons point down +X
	dir.y = 0.0
	dir = dir.normalized()
	var h := weapon_target.y - origin.y
	var v := lob_speed
	var disc := v * v * v * v - g * (g * d * d + 2.0 * h * v * v)
	var root := sqrt(disc) if disc >= 0.0 else 0.0
	var angle := deg_to_rad(45.0) if disc < 0.0 \
		else atan2(v * v + (root if high_arc else -root), g * d)
	return dir * cos(angle) * v + Vector3.UP * sin(angle) * v


# Seconds from leaving `origin` at `v` to coming back down to `target`'s
# height: the later root of y(t) = target.y. Zero if the arc never gets that
# low, which a round fired at a target it can reach cannot do.
func _flight_time(origin: Vector3, target: Vector3, v: Vector3) -> float:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var disc := v.y * v.y + 2.0 * g * (origin.y - target.y)
	if disc < 0.0:
		return 0.0   # the target is above anything the arc reaches: no time to give
	return (v.y + sqrt(disc)) / g


# Lead the target by however long the round spends falling. Without this the
# bomber drops on where the target WAS and never hits anything that moves.
func _release_velocity(origin: Vector3, weapon_target: Vector3, index: int) -> Vector3:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var drop: float = maxf(origin.y - weapon_target.y, 0.0)
	var fall_time: float = sqrt(2.0 * drop / maxf(gravity, 0.01)) if drop > 0.0 else 0.0

	var to_target: Vector3 = weapon_target - origin
	to_target.y = 0.0
	var aim: Vector3 = to_target.normalized() if to_target.length_squared() > 0.01 else -global_transform.basis.z

	# Horizontal speed needed to cover the ground distance in the fall time,
	# capped so it never reads as a rocket rather than a dropped charge.
	var needed: float = to_target.length() / fall_time if fall_time > 0.05 else launch_speed
	var speed: float = clampf(needed, 0.0, launch_speed * 4.0)

	var velocity: Vector3 = aim * speed
	if inherit_carrier_velocity > 0.0 and shooter_velocity() != Vector3.ZERO:
		velocity += shooter_velocity() * inherit_carrier_velocity

	# Scatter the stick so a salvo walks across the target instead of stacking
	# every round on one point.
	if index > 0 and salvo_scatter > 0.0:
		var side: Vector3 = aim.cross(Vector3.UP).normalized()
		velocity += side * randf_range(-salvo_scatter, salvo_scatter)
		velocity += aim * randf_range(-salvo_scatter, salvo_scatter)
	return velocity


# The carrier's motion, if whatever is holding this has any.
func shooter_velocity() -> Vector3:
	var shooter := _owner_body()
	if shooter != null and "velocity" in shooter:
		return shooter.velocity
	return Vector3.ZERO
