extends PlayerWeapon
class_name HUDWeapon

# ─────────────────────────────────────────────
# HUD WEAPON — the M4 and the pistol.
#
# This used to be a 200-line standalone Node3D. Roughly half of it (bob, the
# pose lerp, the equip lifecycle) was generic to anything you can hold and now
# lives in PlayerEquipment; the magazine, reload and firemode half moved to
# PlayerWeapon. What's left here is what's actually gun-specific to THIS gun:
# the hitscan shot, tracers, muzzle flash, and the recoil that kicks the camera.
#
# The export names the weapon scenes store — weapon_model, tracer_origin,
# magazine_size, ads_position and the rest — are all preserved, so
# m4_hud_weapon.tscn and pistol_hud_weapon.tscn keep their tuned values.
# Renaming a stored export drops it silently back to the default, which is a
# miserable bug to chase.
#
# WHAT MOVED, so you know where to look:
#   magazine_size, reload_time, firemode, damage, FIRE_RATE,
#   ADS_FOV/HIP_FOV/ADS_SPEED, ads_position/rotation,
#   reload_position/rotation, reload_sounds, reload_delays,
#   click_stream_player                              -> PlayerWeapon
#   bob_speed, bob_amount, movement_bob_scale        -> PlayerEquipment
#   base_weapon_position    -> base_position         (PlayerEquipment)
#   base_weapon_rotation    -> base_rotation
#   obstructed_weapon_*     -> obstructed_position/rotation
#   magazine_capacity       -> loaded                (PlayerWeapon)
#   fire()                  -> _fire_shot()          (try_fire drives it)
#   start_reload()          -> PlayerWeapon, delta-driven and cancellable
# ─────────────────────────────────────────────

# ── NODE REFERENCES ───────────────────────────
@export var tracer_origin: Node3D
@export var muzzle_flash: Node3D
# Kept under its original name because the weapon scenes store it. Forwarded
# into PlayerEquipment.viewmodel in _on_initialize().
@export var weapon_model: Node3D
@export var projectile_scene: PackedScene
@export var tracer_scene: PackedScene
@export var rifle_stream_player: AudioStreamPlayer3D

# ── RECOIL ────────────────────────────────────
@export var recoil_curve: Curve
@export var recoil_duration: float = 0.25
@export var recoil_per_shot: float = 2.0
@export var camera_recoil_scale: float = 0.75
@export var look_interp_speed: float = 12.0
@export var reload_return_speed: float = 30.0

# ── LEAN ──────────────────────────────────────
@export var LEAN_ANGLE: float = 0.35
@export var LEAN_SPEED: float = 5.0

# ── TRACERS ───────────────────────────────────
# Magazine positions that fire a visible tracer.
@export var tracers_in_mag: Array[int] = [30, 27, 25, 22, 20, 17, 15, 12, 10, 7, 5, 4, 3, 2, 1, 0]

@export var hitscan_range: float = 250.0

signal request_status

var recoil_amount: float = 0.0
var recoil_timer: float = 0.0
var recoil_horizontal: float = 0.0
var recoil_vertical: float = 0.0
var camera_recoil_current: Vector3 = Vector3.ZERO
var recoil_rotation: Vector3 = Vector3.ZERO
var tracer: bool = false
var target_lean: float = 0.0
var pitch: float = 0.0
var from
var to


func _on_initialize() -> void:
	super()
	viewmodel = weapon_model
	pose_speed = ADS_SPEED
	if muzzle_flash != null:
		muzzle_flash.play_flash()


# ─────────────────────────────────────────────
# VIEWMODEL — camera recoil on top of the shared pose stack
# ─────────────────────────────────────────────
func update_view(delta: float, p_move_factor: float, p_obstructed: bool, p_ads: bool) -> void:
	_tick_recoil(delta)
	# Camera follow + recoil kick. Runs before super() so the pose is built
	# against this frame's camera orientation.
	if cam != null and cam.get_parent() != null and "look_direction" in cam.get_parent():
		cam.rotation.x = lerp_angle(cam.rotation.x, cam.get_parent().look_direction.x, delta * look_interp_speed)
		cam.rotation_degrees.x += camera_recoil_current.x
		cam.rotation_degrees.y += camera_recoil_current.y
	super(delta, p_move_factor, p_obstructed, p_ads)


func _tick_recoil(delta: float) -> void:
	if recoil_timer <= 0.0:
		camera_recoil_current = Vector3.ZERO
		recoil_rotation = Vector3.ZERO
		return
	recoil_timer -= delta
	var t: float = clampf(1.0 - (recoil_timer / recoil_duration), 0.0, 1.0)
	var pitch_offset: float = 0.0
	if recoil_curve != null:
		pitch_offset = recoil_curve.sample(t) * recoil_per_shot
	var yaw := recoil_horizontal * (1.0 - t)
	recoil_rotation = Vector3(0, yaw, pitch_offset)
	camera_recoil_current = Vector3(pitch_offset * camera_recoil_scale, 0, 0)
	pitch = clampf(pitch - deg_to_rad(camera_recoil_current.x), -1.5, 1.5)


func _extra_rotation() -> Vector3:
	return recoil_rotation


# ─────────────────────────────────────────────
# THE SHOT
# ─────────────────────────────────────────────
# Cooldown, the empty click and the ammo decrement all happen in
# PlayerWeapon.try_fire(). This is only what leaves the barrel.
func _fire_shot() -> void:
	tracer = tracers_in_mag.has(loaded)

	recoil_timer = recoil_duration
	recoil_horizontal = randf_range(-1.0, 1.0) * 2.0 * 0.5 * recoil_per_shot

	if cam == null or tracer_origin == null:
		return

	from = cam.global_position
	to = from + tracer_origin.global_transform.basis.x.normalized() * hitscan_range

	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.exclude = [self, player] if player != null else [self]

	if rifle_stream_player != null:
		rifle_stream_player.play()
	if muzzle_flash != null:
		muzzle_flash.play_flash()

	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		var victim = collider
		if not victim.has_method("apply_damage") and victim.get_parent() != null:
			victim = victim.get_parent()
		if victim.has_method("apply_damage"):
			victim.apply_damage(damage, player)

	if tracer:
		fire_tracer()
	tracer = false
	request_status.emit()


func fire_tracer() -> void:
	if tracer_scene == null or tracer_origin == null:
		return
	var world: Node = null
	if player != null:
		world = player.get("world")
	if world == null:
		world = get_tree().current_scene
	var new_tracer = tracer_scene.instantiate()
	world.add_child(new_tracer)
	new_tracer.global_position = tracer_origin.global_position
	var dir := tracer_origin.global_transform.basis.x.normalized()
	new_tracer.direction = dir
	new_tracer.look_at(new_tracer.global_position + dir)
