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
	# NOT super(). PlayerMelee.tick resolves the hit on one frame; _tick_swing
	# below does the same job with a window. See its note.
	_tick_swing(delta)
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


# ─────────────────────────────────────────────
# A THRUST CONNECTS WHEN IT ARRIVES, NOT ON ONE FRAME.
#
# PlayerMelee resolves the hit with a single ray on the one frame _swing_t
# crosses swing_time * impact_at. That is survivable when impact lands late in a
# long swing — the old 0.62 of 1.1s gave you two thirds of a second to walk into
# something after committing. With the stroke retimed to 0.154s the whole
# question is decided almost the instant you click, so closing the last half
# metre into a target no longer counts: you have to already be in reach when you
# press, which is not how anyone uses a polearm.
#
# So the lance keeps asking for STRIKE_WINDOW after the point is out. It still
# cannot hit before the lance has extended, it still lands at most once per
# swing, and a swing at nothing is still a miss — it just stops being a single
# frame's worth of luck.
# ─────────────────────────────────────────────

## How long after full extension the lance goes on looking for something to hit.
@export var strike_window: float = 0.18

## Why the last attempt of THIS swing came to nothing, reported once when the
## window closes. Emitting from _mend() instead fired it on every frame of the
## window — twelve "UNDAMAGED" messages for one thrust, which strobes the HUD.
var _refusal: String = ""


## Resets the per-swing refusal before the base class starts the swing.
func primary_pressed() -> void:
	_refusal = ""
	super()


## Replaces PlayerMelee.tick's swing handling. See the note above.
func _tick_swing(delta: float) -> void:
	if not _swinging:
		return
	_swing_t += delta
	if not _impact_done:
		var out_at: float = swing_time * impact_at
		if _swing_t >= out_at:
			if _strike_lands():
				_impact_done = true
			elif _swing_t >= out_at + strike_window:
				# Nothing came into reach for the whole window. A miss, and it has
				# to be recorded as one or the lance would go on hunting for the
				# rest of the swing and connect during the recovery.
				_impact_done = true
				if _refusal != "":
					denied.emit(_refusal)
	if _swing_t >= swing_time:
		_swinging = false
		_swing_t = 0.0


# ── THE ONE BRANCH ───────────────────────────
## True when it actually put damage or repair into something, which is what tells
## tick() above to stop looking.
func _strike_lands() -> bool:
	# RIDs, not nodes: PhysicsRayQueryParameters3D.exclude is Array[RID], and the
	# rest of the project passes get_rid(). It happens to be tolerated here, but
	# agreeing with everything else costs nothing.
	var exclude: Array = [player.get_rid()] if player != null else []
	var result := aim_ray(range, exclude)
	if result.is_empty():
		return false                   # nothing in reach yet; tick() will ask again
	var collider = result.get("collider")
	if collider == null:
		return false
	# Same walk-up the melee base does: a hitbox is usually a child of the body
	# that owns the health.
	var victim = collider
	if not victim.has_method("apply_damage") and victim.get_parent() != null:
		victim = victim.get_parent()

	if _is_friendly(victim):
		return _mend(victim)
	if victim.has_method("apply_damage"):
		victim.apply_damage(damage, player)
		if hit_sound != null:
			hit_sound.play()
		hit.emit(victim)
		return true
	# Something solid, but not something with health — a wall, a crate. That is a
	# real stop: the point is buried in it and the swing is spent.
	return true


## True when it actually mended something. A refusal returns false so the thrust
## goes on looking — brushing an undamaged ally must not spend the swing you were
## aiming past them.
func _mend(victim: Node) -> bool:
	if charges <= 0:
		# EVERY EARLY RETURN SAYS WHY, AND THIS ONE SAYS IT OUT LOUD. Silence
		# reads as "the lance is broken" rather than "you are out", and the two
		# want different reactions from the player. The scene wires no
		# click_sound, so without the signal there was no feedback of any kind.
		if click_sound != null:
			click_sound.play()
		_refusal = "%s : NO CHARGES" % display_name.to_upper()
		return false
	# Nothing spent on someone already whole — otherwise brushing past a
	# full-health ally mid-swing eats a charge you were saving. BUT SAY SO: an
	# undamaged ally is the most likely thing to be pointed at, and this did
	# nothing whatsoever — no sound, no message, no charge spent. That is
	# indistinguishable from a lance that does not work, which is exactly how it
	# was reported.
	if "health" in victim and "max_health" in victim \
			and int(victim.health) >= int(victim.max_health):
		_refusal = "%s : UNDAMAGED" % str(victim.name).to_upper()
		return false
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
	return true


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
# of spear. A lance goes FORWARD.
#
# AND IT IS APPLIED OUTSIDE THE POSE LERP.
#
# It used to be folded into _get_pose_target(), which PlayerEquipment then LERPS
# toward at pose_speed. That is the wrong side of the lerp for a movement with a
# deadline: at pose_speed 10 the viewmodel chases its target with a 0.1s time
# constant, so a fast extension arrived late and short and the lance looked like
# it was being pushed rather than driven. Out here the offset is exact, which is
# what lets the out-stroke be as quick as it reads.
#
# Driving it from position rather than rotation is also deliberate — a wrench
# arcs, and an arc on two and a half metres of spear reads as sweeping the floor.
# A lance goes FORWARD.
func _extra_position() -> Vector3:
	if not _swinging or swing_time <= 0.0:
		return Vector3.ZERO
	var t: float = clampf(_swing_t / swing_time, 0.0, 1.0)
	var f: float
	if t <= impact_at:
		# OUT LINEARLY, AT FULL SPEED INTO THE HIT. This was a quarter-sine with a
		# comment claiming it was "still accelerating when it connects" — sin over
		# 0..PI/2 does the opposite, arriving at full extension with zero velocity,
		# which is what "placed" looks like instead of "thrust". Linear is still
		# travelling at the moment of impact.
		f = t / maxf(impact_at, 0.01)
	else:
		# Recovered slowly: the lance is heavy and you are committed.
		var back: float = (t - impact_at) / maxf(1.0 - impact_at, 0.01)
		f = 1.0 - smoothstep(0.0, 1.0, back)
	# -Z is forward in the weapon's space, which is the camera's.
	return Vector3(0.0, thrust_rise * f, -thrust_distance * f)


# No arc. See _extra_position(): the swing IS the thrust, and nothing rotates.
func _extra_rotation() -> Vector3:
	return Vector3.ZERO
