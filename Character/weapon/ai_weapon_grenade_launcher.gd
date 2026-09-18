extends AIWeapon
class_name AIWeaponGrenadeLauncher

# ─────────────────────────────────────────────
# GRENADE DROP-LAUNCHER — the gunship's ordnance.
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


func check_damage(weapon_target: Vector3) -> void:
	if grenade_scene == null:
		push_warning("AIWeaponGrenadeLauncher on '%s' has no grenade_scene — it fires, makes noise, and nothing comes out." % name)
		return
	_release_salvo(weapon_target)


func _release_salvo(weapon_target: Vector3) -> void:
	for i in maxi(1, salvo):
		_release_one(weapon_target, i)
		if salvo_spacing > 0.0 and i < salvo - 1:
			await get_tree().create_timer(salvo_spacing).timeout
			# The launcher can be freed mid-salvo when the gunship is shot down.
			if not is_inside_tree():
				return


func _release_one(weapon_target: Vector3, index: int) -> void:
	var origin: Vector3 = muzzle_origin.global_position if muzzle_origin != null else global_position
	var grenade := grenade_scene.instantiate()

	# setup() BEFORE the tree, same contract the thrown grenade uses — the
	# projectile hands its thrower to the Explosion, which is what makes a
	# grenade kill count for somebody and what stops the gunship blast-killing
	# its own escorts at full damage.
	var shooter := _owner_body()
	if grenade.has_method("setup"):
		grenade.setup(shooter)
	if fuse_override > 0.0 and "fuse_time" in grenade:
		grenade.fuse_time = fuse_override

	get_tree().current_scene.add_child(grenade)
	grenade.global_position = origin

	# A released charge must never collide with the thing that let go of it.
	# The drop spawns at the muzzle, which is INSIDE the gunship's own collider,
	# so move_and_slide() resolved the overlap by shoving the aircraft sideways
	# — it knocked itself off its flight path with every round in the salvo.
	if shooter is PhysicsBody3D and grenade is PhysicsBody3D:
		(grenade as PhysicsBody3D).add_collision_exception_with(shooter)

	if grenade is RigidBody3D:
		(grenade as RigidBody3D).linear_velocity = _release_velocity(origin, weapon_target, index)
		(grenade as RigidBody3D).angular_velocity = Vector3(
			randf_range(-4.0, 4.0), randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))


# Lead the target by however long the round spends falling. Without this the
# gunship drops on where the target WAS and never hits anything that moves.
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
