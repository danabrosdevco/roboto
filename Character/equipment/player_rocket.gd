extends PlayerEquipment
class_name PlayerRocket

# Playtest analytics. By path: see the note in analytics.gd.
const _Analytics := preload("res://Managers/analytics.gd")

# ─────────────────────────────────────────────
# RECOILLESS RIFLE — two rockets, and nothing in the squad that fires flat and
# hits that hard.
#
# It is the grenade's opposite, deliberately. A grenade goes over cover, waits
# on a fuse and is cheap; this goes THROUGH what you are looking at, at once,
# and you get two of them a deployment. That is the whole decision: the moment
# to spend one, and which of the two things in front of you is worth it.
#
# The tube reloads between shots (`reload_time`) so a pair cannot be dumped
# into the same second, and it is held down while it reloads, which is what
# stops the second rocket being fired at something three metres away in a
# panic. Spent, the loadout puts the rifle back (reverts_when_empty).
# ─────────────────────────────────────────────

@export var rocket_scene: PackedScene
@export var ammo_type: StringName = &"rocket"
## Flat and very fast: this is direct fire, not a lob. At this speed the flight
## to anything you can see is a fifth of a second, so the rocket lands where the
## crosshair was when you pulled — no lead, no hold-over.
@export var launch_speed: float = 120.0
## Which is why there is no arc left: the rocket carries no gravity either, so
## any lift here would walk the shot UP off the crosshair rather than correct a
## drop that no longer happens. Kept as a dial for a slower variant.
@export var launch_arc: float = 0.0
## From the trigger to the rocket leaving the tube.
@export var fire_time: float = 0.18
## And the wait before the next one can be loaded.
@export var reload_time: float = 1.9
@export var spawn_offset: Vector3 = Vector3(0.0, -0.08, -1.0)

# ── AIMING ────────────────────────────────────
# There is a sight on the tube, so it aims like anything else you shoulder.
# Not as tight as a rifle: this is a shoulder-fired tube with an optical block,
# not a scope, and the whole point of the weapon is the thing you are pointing
# at being large.
@export var ADS_FOV: float = 55.0
## Where the tube sits when shouldered.
##
## LOW, so you look OVER it rather than down it. Bringing a metre-long open
## tube up to eye level put the camera inside the bore: you ended up staring
## down it at the back of the loaded rocket, with the sight block underneath
## and out of frame. Shouldered for real, your eye sits above the tube and
## picks up the sight standing off the top of it, which is what this is.
@export var ads_position: Vector3 = Vector3(0.0, -0.205, -0.05)
## Square on: the sight column stands up the middle of the screen, so the post
## and the crosshair are the same line.
@export var ads_rotation: Vector3 = Vector3(0.0, 0.0, 0.0)

@export var launch_sound: AudioStreamPlayer3D
## Unused, and left unwired in the scene on purpose. The tube had an AR-15
## metal click here, played when the reload finished — which is the ca-chunk
## you could hear a couple of seconds after every shot. A recoilless rifle
## makes one noise worth hearing and that is the launch.
@export var reload_sound: AudioStreamPlayer3D
## Kicked back on firing and eased home over the reload.
@export var recoil_metres: float = 0.22

signal fired(rocket: Node3D)

var _firing := false
var _fire_t := 0.0
var _reload_t := 0.0
var _kick := 0.0


func _on_initialize() -> void:
	slot = Slot.EQUIPMENT
	consumes_charge = true
	reverts_when_empty = true


func has_charge() -> bool:
	return charges_remaining() > 0


func charges_remaining() -> int:
	if ammo == null:
		return 0
	return ammo.get_count(ammo_type)


func consume_charge() -> void:
	if ammo != null:
		ammo.take(ammo_type, 1)
	charges_changed.emit()


func get_readout() -> Readout:
	var r := Readout.new(ReadoutMode.COUNT)
	r.primary = charges_remaining()
	r.label = display_name
	r.warn = r.primary <= 1
	# The reload runs the bar, so the wait is visible rather than a dead
	# trigger the player keeps pulling.
	if _reload_t > 0.0:
		r.fraction = 1.0 - clampf(_reload_t / maxf(reload_time, 0.01), 0.0, 1.0)
	return r


func is_busy() -> bool:
	return _firing or _reload_t > 0.0


func _on_unequip() -> void:
	# A shot half-fired when you switch away is cancelled rather than arriving
	# out of a tube you are no longer holding.
	_firing = false
	_fire_t = 0.0
	_kick = 0.0
	# And the launch sample goes with it: spending the last rocket reverts to
	# your rifle mid-shot, and a sound has no business carrying on out of a tube
	# that is already back over your shoulder.
	if launch_sound != null and launch_sound.playing:
		launch_sound.stop()


func primary_pressed() -> void:
	if _firing or is_raising():
		return   # already on the way, or still coming up
	if _reload_t > 0.0:
		denied.emit("RELOADING")
		return
	if not has_charge():
		denied.emit("NO ROCKETS")
		return
	_firing = true
	_fire_t = fire_time


func tick(delta: float) -> void:
	if _reload_t > 0.0:
		_reload_t = maxf(0.0, _reload_t - delta)
		if _reload_t == 0.0 and reload_sound != null and has_charge():
			reload_sound.play()
		charges_changed.emit()
	# The tube comes back to rest across the reload.
	if _kick > 0.0 and viewmodel != null:
		_kick = maxf(0.0, _kick - delta / maxf(reload_time, 0.01) * recoil_metres)
		viewmodel.position.z = _rest_z() + _kick
	if not _firing:
		return
	_fire_t -= delta
	if _fire_t > 0.0:
		return
	_firing = false
	_launch()


func ads_fov() -> float:
	return ADS_FOV


# Shouldered, obstructed, or carried.
#
# THE SIGHT STAYS UP THROUGH THE SHOT. Dropping to the carry pose on firing and
# holding it across the reload was meant to read as the tube coming down to take
# a rocket — what it actually did was throw your aim off the thing you had just
# hit, every time, a fifth of a second after you pulled. You are still holding
# the aim button; the weapon should still be aimed. The kick and the recovery in
# tick() are what say a rocket left the tube.
func _get_pose_target() -> Array:
	if is_obstructed:
		return [obstructed_position, obstructed_rotation]
	if is_ads:
		return [ads_position, ads_rotation]
	return [base_position, base_rotation]


func _rest_z() -> float:
	if not has_meta(&"rest_z") and viewmodel != null:
		set_meta(&"rest_z", viewmodel.position.z)
	return float(get_meta(&"rest_z", 0.0))


func _launch() -> void:
	if rocket_scene == null:
		push_error("PlayerRocket: no rocket_scene assigned.")
		return
	if not has_charge() or cam == null:
		return
	var world: Node = null
	if player != null:
		world = player.get("world")
	if world == null:
		world = get_tree().current_scene
	if world == null:
		world = get_parent()

	var rocket := rocket_scene.instantiate()
	world.add_child(rocket)
	var cam_basis := cam.global_transform.basis
	rocket.global_position = cam.global_position + (cam_basis * spawn_offset)
	var dir := (-cam_basis.z.normalized() + Vector3.UP * launch_arc).normalized()
	if rocket is RigidBody3D:
		(rocket as RigidBody3D).linear_velocity = dir * launch_speed
	if rocket.has_method("setup"):
		rocket.setup(player)
	# The log counts firing this as a throw under display_name; tell the blast
	# to call itself the same thing, or the weapon shows up twice with half its
	# story in each row.
	if "analytics_label" in rocket:
		rocket.analytics_label = display_name

	consume_charge()
	_reload_t = reload_time
	_kick = recoil_metres
	if launch_sound != null:
		launch_sound.play()
	_Analytics.throw(player, display_name)
	fired.emit(rocket)
	used.emit()
	_notify_spent()
