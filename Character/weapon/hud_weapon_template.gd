extends PlayerWeapon
class_name HUDWeapon

## By path, not by class_name — see the note in ai_weapon.gd.
const _WeaponAudio := preload("res://Managers/weapon_audio.gd")

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
## Sideways camera kick, as a fraction of the vertical one. 0 restores the old
## dead-vertical climb. A burst picks its direction once and keeps it (see
## _fire_shot), so sustained fire walks up and off to one side instead of
## shivering left and right a shot at a time.
@export var camera_recoil_yaw_scale: float = 0.4
## HOW A BURST SETTLES. The recoil curve is per-SHOT — it is re-armed on every
## round, so on anything automatic it only ever plays its first fraction and
## every shot kicks identically. That cannot express "jumps, then steadies",
## which is what a machine gun should feel like and what a launcher should
## NOT. These two do: over `settle_shots` rounds of continuous fire the kick
## fades from full to `settle_to`, and the count resets the moment you stop.
## settle_shots 0 leaves every shot at full strength.
@export var settle_shots: int = 0
@export var settle_to: float = 1.0
@export var look_interp_speed: float = 12.0
@export var reload_return_speed: float = 30.0

# ── LEAN ──────────────────────────────────────
@export var LEAN_ANGLE: float = 0.35
@export var LEAN_SPEED: float = 5.0

# ── TRACERS ───────────────────────────────────
# Magazine positions that fire a visible tracer.
@export var tracers_in_mag: Array[int] = [30, 27, 25, 22, 20, 17, 15, 12, 10, 7, 5, 4, 3, 2, 1, 0]

@export var hitscan_range: float = 250.0

# Rounds per shot. 1 is a rifle; a shotgun is several, each carrying its share
# of `damage` and thrown wide by pellet_spread_mrad, so the pattern — not a
# range table — is what makes it fall off. Mirrors AIWeapon's pellets, so the
# shotgun behaves the same whichever side of it you are on.
@export var pellets: int = 1
@export var pellet_spread_mrad: float = 0.0

# How far this weapon is heard. Suppressed or small-calibre weapons should carry
# less; -1 uses StimulusManager's default for GUNSHOT_HEARD.
@export var noise_radius: float = 34.0
# Off by default. Turn it on for a difficulty mode if you ever want it to bite.
# Your rounds hit your own squad too, at reduced damage. Making them harmless
# would mean the squad's own sidestep logic is protecting them from a threat
# that doesn't exist.
@export var friendly_fire_multiplier: float = 0.34

# ── SUPPRESSION ───────────────────────────────
# Signal damage to hostiles near each round, exactly as AIWeapon does it — the
# pass itself is AIWeapon.suppress_near, called from both so the two cannot
# drift. Until this existed the exchange was one-way: enemy fire pinned your
# squad and your own fire did nothing to theirs, which quietly made the whole
# mechanic something that only ever happened TO you.
#
# Same units as the AI side: signal_integrity × 100, so 3.5 is 0.035 a round.
# Set per weapon in its scene; these defaults match the AI rifle.
@export var suppression_per_shot: float = 3.5
@export var near_miss_radius: float = 2.5
# What the centre round connected with, or null if it missed. Written by
# _one_round and read by _fire_shot immediately after; see the same member on
# AIWeapon for why this is not a second return value.
var _struck_this_shot: Node = null

signal request_status

var recoil_amount: float = 0.0
var recoil_timer: float = 0.0
var recoil_horizontal: float = 0.0
var recoil_vertical: float = 0.0
## Degrees of sideways camera kick for the shot in flight, signed.
var recoil_yaw_kick: float = 0.0
## Which way the CURRENT burst is walking, +1 or -1. Held between shots so a
## magazine climbs in one direction rather than jittering.
var _yaw_dir: float = 0.0
## Rounds into the current burst, for _settle_scale(). Reset by arm_recoil()
## whenever the recoil timer has run out, which is the same test as "you let go".
var _burst_shots: int = 0
var _warned_no_curve: bool = false
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
		# YAW HAS TO BE PULLED BACK TO A REST VALUE, exactly like pitch above.
		#
		# Pitch is safe because the line above SETS it from look_direction.x
		# before the kick is added, so the offset decays every frame. Yaw had no
		# such line: the player BODY carries yaw (test_character.gd lerps
		# rotation.y), nothing ever writes cam.rotation.y, and so `+=` below
		# accumulated for as long as you held the trigger. It was not a hard
		# kick — it was an unbounded one, and the camera ended up 160 degrees
		# off. The camera's rest yaw relative to the body is zero, so that is
		# what it lerps back to.
		cam.rotation.y = lerp_angle(cam.rotation.y, 0.0, delta * look_interp_speed)
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
	# NO CURVE MEANS NO CAMERA RECOIL AT ALL. Only the Ancient Rifle had one,
	# so it was the only weapon in the game whose camera moved when it fired —
	# every other gun's kick lived entirely in the viewmodel. Warned rather
	# than defaulted: a silent 0.0 here is indistinguishable from a weapon that
	# is meant to be soft, and that is how it went unnoticed.
	if recoil_curve == null:
		camera_recoil_current = Vector3.ZERO
		recoil_rotation = Vector3.ZERO
		if not _warned_no_curve:
			_warned_no_curve = true
			push_warning("%s has no recoil_curve, so firing it does not move the camera at all. Give it a Curve or say in the scene why it should be dead." % display_name)
		return
	var kick: float = recoil_curve.sample(t) * _settle_scale()
	var pitch_offset: float = kick * recoil_per_shot
	var yaw := recoil_horizontal * (1.0 - t)
	recoil_rotation = Vector3(0, yaw, pitch_offset)
	# UP *AND* TO THE SIDE. The y term here was hard-wired to 0, so the camera
	# only ever pitched — every gun climbed dead vertical and the only sideways
	# motion in the whole system was the VIEWMODEL's yaw, which moves the model
	# and not your aim. It read as a horizontal wobble bolted onto a vertical
	# climb rather than as a kick.
	camera_recoil_current = Vector3(pitch_offset * camera_recoil_scale,
		kick * recoil_yaw_kick, 0)
	pitch = clampf(pitch - deg_to_rad(camera_recoil_current.x), -1.5, 1.5)


## How much of the full kick this shot gets. 1.0 on the first round of a burst,
## easing to `settle_to` by round `settle_shots`. See the export for why the
## recoil curve alone cannot do this.
func _settle_scale() -> float:
	if settle_shots <= 0:
		return 1.0
	var through: float = clampf(float(_burst_shots) / float(settle_shots), 0.0, 1.0)
	return lerpf(1.0, settle_to, through)


func _extra_rotation() -> Vector3:
	return recoil_rotation


# ─────────────────────────────────────────────
# THE SHOT
# ─────────────────────────────────────────────
## Winds the kick for one shot. Pulled out of _fire_shot() so a weapon that
## overrides the shot — a launcher putting a shell on an arc rather than a
## hitscan down a line — still kicks the same way, instead of carrying its own
## copy of this to drift out of step.
func arm_recoil() -> void:
	# THE DIRECTION IS PICKED ONCE PER BURST, before recoil_timer is re-armed —
	# a timer still running means you are still firing, so the walk continues
	# the way it started. Re-rolling the sign every shot is what makes recoil
	# read as a shake instead of a climb.
	# A STOPPED TIMER MEANS A NEW BURST. Same test the yaw direction uses: if
	# nothing is still winding down you have let go and picked the trigger up
	# again, so the gun is allowed to jump again.
	if recoil_timer <= 0.0:
		_yaw_dir = 1.0 if randf() < 0.5 else -1.0
		_burst_shots = 0
	else:
		_burst_shots += 1
	recoil_timer = recoil_duration
	recoil_horizontal = randf_range(-1.0, 1.0) * 2.0 * 0.5 * recoil_per_shot
	# Magnitude still varies shot to shot so it is not a metronome.
	recoil_yaw_kick = _yaw_dir * randf_range(0.55, 1.0) * recoil_per_shot * camera_recoil_yaw_scale


# Cooldown, the empty click and the ammo decrement all happen in
# PlayerWeapon.try_fire(). This is only what leaves the barrel.
func _fire_shot() -> void:
	tracer = tracers_in_mag.has(loaded)
	arm_recoil()

	if cam == null or tracer_origin == null:
		return

	from = cam.global_position
	var centre := tracer_origin.global_transform.basis.x.normalized()
	to = from + centre * hitscan_range

	if rifle_stream_player != null:
		# Your own gun is always the near band, but this is also what puts it on
		# the Weapons bus without every weapon scene having to name it.
		_WeaponAudio.stage(rifle_stream_player)
		rifle_stream_player.play()

	# Tell the AI. Emitted on every shot, from the shooter's position rather
	# than the impact point — you're giving away where YOU are.
	if player != null and player.has_method("emit_noise"):
		player.emit_noise(StimulusManager.StimulusType.GUNSHOT_HEARD, noise_radius)
	if muzzle_flash != null:
		muzzle_flash.play_flash()
	#DebugDraw3D.draw_line(from, to, Color(1,0,0), 50)

	# Split so the parts add up to the whole: the remainder rides on the first
	# round rather than being rounded away.
	var count: int = maxi(pellets, 1)
	var each: int = int(floor(float(damage) / float(count)))
	var spare: int = damage - each * count
	var exclude: Array = [self, player] if player != null else [self]
	var centre_impact: Vector3 = to
	var struck: Node = null
	for i in count:
		var dir := centre
		if count > 1 and pellet_spread_mrad > 0.0:
			dir = AIWeapon.scatter(centre, pellet_spread_mrad)
		var landed := _one_round(from, dir, exclude, each + (spare if i == 0 else 0))
		if i == 0:
			centre_impact = landed
			# The centre round only, matching the one-pass-per-shot rule below:
			# a shotgun must not land the hit bonus nine times over.
			struck = _struck_this_shot

	# One suppression pass per shot, down the middle of the pattern — not one
	# per pellet, or a shotgun would suppress eight times as hard as the pellet
	# count alone implies. The same rule AIWeapon follows.
	#
	# Measured along the whole flight path rather than at the impact: see the
	# note on suppress_along for why the impact point was the wrong place.
	if suppression_per_shot > 0.0:
		var mine = player.faction if player != null and "faction" in player else null
		AIWeapon.suppress_along(get_tree(), from, centre_impact,
				near_miss_radius, suppression_per_shot / 100.0, player, mine, struck)

	if tracer:
		fire_tracer()
	tracer = false
	request_status.emit()


# One round down one line, carrying `share` of the shot's damage.
#
# Returns WHERE IT LANDED — the hit point, or the end of the ray when it hit
# nothing. A miss still has a place, and suppression is centred on it: the
# whole point of suppressing fire is the rounds that do not connect.
func _one_round(origin: Vector3, direction: Vector3, exclude: Array, share: int) -> Vector3:
	_struck_this_shot = null
	var query := PhysicsRayQueryParameters3D.new()
	query.from = origin
	query.to = origin + direction * hitscan_range
	query.exclude = exclude
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result:
		return query.to
	var victim = result.collider
	if not victim.has_method("apply_damage") and victim.get_parent() != null:
		victim = victim.get_parent()
	# The player's rounds had NO faction check — walking your own squad into
	# your line of fire simply killed them. Same are_hostile() test the AI
	# uses, so both sides agree on who can be shot.
	if victim.has_method("apply_damage"):
		victim.apply_damage(_damage_for(victim, share), player)
		_struck_this_shot = victim
	return result.position


func _damage_for(victim: Node, share: int) -> int:
	if not victim.has_method("get_faction"):
		return share   # scenery and props take it full
	var mine: int = player.faction if player != null and "faction" in player else Enums.Factions.PLAYER
	if Enums.are_hostile(mine, victim.get_faction()):
		return share
	return maxi(1, int(round(float(share) * friendly_fire_multiplier)))


func fire_tracer() -> void:
	if tracer_scene == null or tracer_origin == null:
		return
	var world: Node = level_node()
	var new_tracer = tracer_scene.instantiate()
	world.add_child(new_tracer)
	if new_tracer.has_method("set_side"):
		new_tracer.set_side(player.faction if player != null and "faction" in player else Enums.Factions.PLAYER)
	new_tracer.global_position = tracer_origin.global_position
	var dir := tracer_origin.global_transform.basis.x.normalized()
	new_tracer.direction = dir
	new_tracer.look_at(new_tracer.global_position + dir)

