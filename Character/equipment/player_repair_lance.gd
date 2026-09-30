extends PlayerMelee
class_name PlayerRepairLance

# ─────────────────────────────────────────────
# REPAIR LANCE — the only weapon that makes walking TOWARD your own downed
# squadmate the aggressive play.
#
# It is a melee weapon that does one extra thing: if the thing on the end of it
# is friendly, it puts health back instead of taking it away. That is a single
# branch in _strike(), and everything else — the swing timing, the reach, the
# impact frame, the viewmodel arc — is PlayerMelee's and untouched.
#
# THE REPAIR IS THE RESOURCE, THE DAMAGE IS NOT. Charges are spent only on
# allies and refill on a timer, so the lance never stops being a weapon and
# never becomes a Mechanic you can also stab people with. A lance that healed
# on every touch would retire the Mechanic, which repairs from range and cannot
# fight — this one has to close to 3.4m and is standing in the open while it
# does. Three charges is a burst: get there, put someone back up, and then you
# are carrying a spear again until it fills.
#
# The reservoir on the model is literally the thing that empties.
# ─────────────────────────────────────────────

## Health returned to an ally per hit. Half the damage, deliberately: the
## lance is a better weapon than it is a medic.
@export var repair_amount: int = 30
## Hits' worth of repair carried. Damage ignores this entirely.
@export var max_charges: int = 3
## Seconds to earn one back. Runs whenever the lance is below full, equipped
## or not — you should not have to hold it to recover.
@export var recharge_seconds: float = 9.0

## charges_changed is PlayerEquipment's own signal, not a new one — the HUD is
## already listening to it, so emitting it is what makes the counter move.
##
## How far the lance drives forward on a swing, in metres. This is the whole
## animation: a thrust is a POSITION change, not a rotation, and the wrench's
## inherited arc reads as a swipe on something two and a half times its length.
@export var thrust_distance: float = 0.22
## A little lift with it, so the point comes up into the target rather than
## sliding along the floor.
@export var thrust_rise: float = 0.05

## Played when the lance touches an ally with nothing left to give. Optional —
## an empty lance is still a weapon, so this is feedback rather than a failure
## noise, and a scene that does not wire it simply says nothing.
@export var click_sound: AudioStreamPlayer3D

var charges: int = 0
var _recharge_t: float = 0.0


func _on_initialize() -> void:
	super()
	charges = max_charges


# A LANCE OUT OF CHARGE IS STILL A LANCE. PlayerMelee answers true here and so
# does this: has_charge() gates whether the item can be *used at all*, and
# answering false would put a weapon that still does sixty damage into the
# greyed-out state.
func has_charge() -> bool:
	return true


func tick(delta: float) -> void:
	super(delta)
	if charges >= max_charges:
		_recharge_t = 0.0
		return
	_recharge_t += delta
	if _recharge_t < recharge_seconds:
		return
	_recharge_t -= recharge_seconds
	charges += 1
	charges_changed.emit()


func get_readout() -> Readout:
	var r := Readout.new(ReadoutMode.COUNT)
	r.label = display_name
	r.primary = charges
	r.secondary = max_charges
	r.warn = charges <= 0
	return r


# ── THE ONE BRANCH ───────────────────────────
func _strike() -> void:
	var exclude: Array = [player] if player != null else []
	var result := aim_ray(range, exclude)
	if result.is_empty():
		return
	var collider = result.get("collider")
	if collider == null:
		return
	# Same walk-up the melee base does: a hitbox is usually a child of the body
	# that owns the health.
	var victim = collider
	if not victim.has_method("apply_damage") and victim.get_parent() != null:
		victim = victim.get_parent()

	if _is_friendly(victim):
		_mend(victim)
		return
	if victim.has_method("apply_damage"):
		victim.apply_damage(damage, player)
		if hit_sound != null:
			hit_sound.play()
		hit.emit(victim)


func _mend(victim: Node) -> void:
	if charges <= 0:
		# EVERY EARLY RETURN SAYS WHY. Silence here reads as "the lance is
		# broken" rather than "you are out", and the two want different
		# reactions from the player.
		if click_sound != null:
			click_sound.play()
		return
	# Nothing spent on someone already whole — otherwise brushing past a
	# full-health ally mid-swing eats a charge you were saving.
	if "health" in victim and "max_health" in victim \
			and int(victim.health) >= int(victim.max_health):
		return
	charges -= 1
	charges_changed.emit()
	if victim.has_method("apply_healing"):
		victim.apply_healing(repair_amount, player)
	elif "health" in victim and "max_health" in victim:
		victim.health = mini(int(victim.max_health), int(victim.health) + repair_amount)
	if hit_sound != null:
		hit_sound.play()
	hit.emit(victim)
	used.emit()


## Anyone the player would not shoot. Same test player_repair_tool.gd uses, so
## the lance and the welder agree about who counts as ours.
func _is_friendly(body: Node) -> bool:
	if body == null or not ("faction" in body):
		return false
	return not Enums.are_hostile(Enums.Factions.PLAYER, body.faction)


# ─────────────────────────────────────────────
# THE THRUST
# ─────────────────────────────────────────────
# PlayerMelee swings: _extra_rotation() arcs the model out and back, which is
# right for a wrench held at arm's length and wrong for two and a half metres
# of spear, where it reads as sweeping the floor. A lance goes FORWARD.
#
# Driving it from the pose position rather than the rotation also keeps it out
# of the additive-rotation path, where PlayerEquipment mixes the pose (radians)
# with _extra_rotation (degrees) on one line. Nothing here needs to go near
# that.
func _get_pose_target() -> Array:
	var pose := super()
	if not _swinging or swing_time <= 0.0:
		return pose
	var t: float = clampf(_swing_t / swing_time, 0.0, 1.0)
	var f: float
	if t <= impact_at:
		# Out fast, and still accelerating when it connects.
		f = sin((t / maxf(impact_at, 0.01)) * PI * 0.5)
	else:
		# Recovered slowly: the lance is heavy and you are committed.
		var back: float = (t - impact_at) / maxf(1.0 - impact_at, 0.01)
		f = 1.0 - smoothstep(0.0, 1.0, back)
	# -Z is forward in the weapon's space, which is the camera's.
	var out: Vector3 = pose[0] + Vector3(0.0, thrust_rise * f, -thrust_distance * f)
	return [out, pose[1]]


# No arc. See _get_pose_target(): the swing is the thrust and nothing rotates.
func _extra_rotation() -> Vector3:
	return Vector3.ZERO
