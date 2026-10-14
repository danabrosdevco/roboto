extends SpotterDrone

# ─────────────────────────────────────────────
# KITE — the first aerial in the game that shoots.
#
# WHAT IT IS FOR. Not an angle. There is no vertical immunity here:
# AIWeapon.check_damage builds its ray from the muzzle to a POSITION rather than
# an orientation (ai_weapon.gd:396-399), and Enemy._tick_vision flattens the
# cone before the FOV test (enemy.gd:962-964, `forward.y = 0.0`). Height buys
# this frame nothing the engine enforces.
#
# What it does buy is REACH WITHOUT A ROUTE. A 99 m machine gun on a platform
# that crosses terrain at 18 m/s ignoring the navmesh is shooting at the
# objective while a Rover is still finding a way to it.
#
# AND THE COST IS THE IDENTITY. It is permanently `_is_moving()` — the
# threshold is 0.6 m/s (enemy.gd:2837) and it cruises at 18 — so it permanently
# eats `moving_accuracy_penalty`, 3.0x spread on this scene. It cannot stop to
# aim: AIM sets `movement_state = NONE` and the flight code never reads
# `movement_state`. So: the gun that gets there first and cannot be aimed
# properly, with 90 hull and no way to win an exchange it is caught in.
#
# NO `class_name`. A new global symbol is not resolvable headless until the
# editor rescans — spotter_drone.gd:94-96 records exactly that cost. The scene
# references this script by path and so do the tests.
#
# ─────────────────────────────────────────────
# WHAT THIS SCRIPT IS, IN ONE SENTENCE
#
# SpotterDrone's flight model with the weapon loop switched back on and the
# Rover's turret bolted to it. Five functions and a predicate; everything that
# flies is inherited and must stay that way — `handle_movement`,
# `handle_gravity`, `_apply_motion`, `move_to`, `takes_cover`,
# `slot_tolerance`, `formation_width`, `off_navmesh_is_normal`, `_enter_ekill`,
# `enter_downed`, the crash/revive set and everything under `_steer`.
# ─────────────────────────────────────────────

@export_group("Turret")
## The gun pod. MUST be named `turret` — enemy.gd:2895 escapes hull_spoils_aim
## only via a property literally called `turret` being non-null, and this frame
## is NEVER stationary, so without it `_aim_tracking` is decayed every single
## frame and the gun never leaves WeaponState.AIM. A rename here is a frame
## that never fires and never says why.
@export var turret: Node3D
## The elevating part, under the turret. The weapon mount hangs off this.
@export var gun_pivot: Node3D
## Degrees per second of traverse. NOT the Walker's 55: that number is a
## deliberate counter — a chaser can get around the side of a Walker faster
## than its gun follows. There is no getting around the side of a flyer, and an
## orbiting platform's bearing to a fixed target changes continuously, so a
## slow traverse here is not counter-play, it is a gun that never catches up
## with its own circle.
@export var turret_traverse_degrees: float = 90.0
@export var gun_elevation_degrees: float = 60.0
## A frame 22 m up shooting something 25 m away on the ground wants about 41
## degrees of DEPRESSION. The Walker's -12 would clamp that to a gun pointing
## at the horizon while the rounds went into the dirt.
@export var gun_min_pitch_degrees: float = -55.0
@export var gun_max_pitch_degrees: float = 10.0
## How far off the bearing still counts as on target. Wider than the Walker's 7
## because a 0.7 m platform yawing and rolling under `_orient`
## (spotter_drone.gd:341-349) cannot hold a 7 degree cone — and a cone it
## cannot hold is a frame that holds fire.
@export var fire_cone_degrees: float = 9.0


# The pod's fixed down-cant, read off the scene in _ready rather than written
# here as a number, so retouching the model does not silently un-aim the gun.
# See _update_facing for what it is for.
var _pod_cant: float = 0.0


func _ready() -> void:
	super()
	if turret == null:
		push_warning("%s has no turret assigned, so hull_spoils_aim will never clear (enemy.gd:2895) and a frame that is permanently moving will never fire." % name)
	if gun_pivot == null:
		push_warning("%s has no gun_pivot assigned, so its gun will not elevate and will visibly point at the horizon." % name)
	# Cached from `turret`, not from `gun_pivot`: the cant lives on the pod.
	_pod_cant = turret.rotation.x if turret != null else 0.0


# ─────────────────────────────────────────────
# THE WEAPON LOOP, SWITCHED BACK ON
# ─────────────────────────────────────────────
# SpotterDrone stubs `handle_weapon_logic` and `roll_combat_action` behind this
# predicate because it is an unarmed scout and says so. This frame is the
# reason the predicate exists.
#
# `roll_combat_action` is the half that is easy to overlook and is not
# optional: it is the only path to `_commit_burst` (enemy.gd:3948), which is
# what makes the gun fire the weapon's own bursts of 8-16 instead of single
# shots through the full settle gate. On a frame whose entire case is volume of
# fire, that is the difference between working and not.
func _carries_a_weapon() -> bool:
	return true


# ─────────────────────────────────────────────
# THE TURRET — the Rover's, not the Walker's
# ─────────────────────────────────────────────
# Deliberately does NOT call super(). The body's attitude belongs to the
# flight: `_orient` (spotter_drone.gd:341) yaws it to the heading and rolls it
# into the turn, and Enemy's `_update_facing` would fight that every frame by
# turning the whole aircraft to face its target. The same choice of what to
# look at turns the pod instead. rover.gd:597-615 is the template.
func _update_facing(delta: float) -> void:
	if turret == null:
		return   # warned about in _ready; the body's facing is the flight's
	var face := _desired_facing()
	if face != Vector3.ZERO:
		var local := global_transform.basis.inverse() * face
		var want_yaw := atan2(-local.x, -local.z)
		turret.rotation.y = rotate_toward(turret.rotation.y, want_yaw,
				deg_to_rad(turret_traverse_degrees) * delta)
	if gun_pivot != null:
		var want_pitch := 0.0
		if ai_state == AIState.COMBAT and weapon_target != Vector3.ZERO:
			var to := weapon_target - gun_pivot.global_position
			want_pitch = atan2(to.y, Vector2(to.x, to.z).length())
		want_pitch = clampf(want_pitch, deg_to_rad(gun_min_pitch_degrees),
				deg_to_rad(gun_max_pitch_degrees))
		# THE CANT IS SUBTRACTED, AND THIS WILL LOOK LIKE A BUG TO WHOEVER READS
		# IT NEXT. `want_pitch` is world geometry — atan2 of a world offset — but
		# `gun_pivot.rotation.x` is LOCAL to a pod that already carries a fixed
		# -24 degrees of down-cant (build_kite.gd:624). Assigned raw, as the
		# Rover does on a frame with no cant, the gun would sit at
		# `-24 + want_pitch` and visibly point well under its target.
		#
		# It would still FIRE: `_weapon_on_target` below flattens y and
		# `check_damage` resolves position-to-position, so elevation is cosmetic
		# for both the gate and the damage. It is still wrong on screen on the
		# frame whose whole silhouette argument is that the gun, its eye and its
		# ring all look where it shoots.
		gun_pivot.rotation.x = rotate_toward(gun_pivot.rotation.x,
				want_pitch - _pod_cant, deg_to_rad(gun_elevation_degrees) * delta)


func _turret_forward() -> Vector3:
	var f := -(turret.global_transform.basis.z if turret != null else global_transform.basis.z)
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else _flat_body_forward()


# WHICH WAY THE SENSORS LOOK, and the one function no design document named.
#
# `_tick_vision` (enemy.gd:960-964) builds its 130 degree FOV cone from this,
# and Enemy's version returns `-basis.z` — the AIRFRAME's nose, which `_orient`
# points along the flight path. An orbiting Kite would therefore sweep its cone
# around the circle and lose sight of its own target every half-orbit. The pod
# is where this frame is actually looking. rover.gd:621-622 solves exactly this
# the same way; the Spotter does not need it because losing a contact costs it
# nothing.
func _sight_forward() -> Vector3:
	return _turret_forward()


# THE FIRE CONE. Flattened, so the pod's cant does not enter the gate — see
# the note in _update_facing. rover.gd:625-630.
func _weapon_on_target() -> bool:
	var to := weapon_target - global_position
	to.y = 0.0
	if to.length_squared() < 0.25:
		return true   # directly below it: any bearing is as good as another
	return rad_to_deg(_turret_forward().angle_to(to.normalized())) <= fire_cone_degrees
