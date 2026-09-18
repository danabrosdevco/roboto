extends PlayerEquipment
class_name PlayerRepairTool

# ─────────────────────────────────────────────
# PLAYER REPAIR TOOL — channelled, works on yourself and on squadmates.
#
# Repairs HEALTH, not signal integrity. Those are two different verbs and mixing
# them into one tool makes neither legible; signal is left alone deliberately.
#
# TARGETING IS IMPLICIT. Crosshair on a friendly in range repairs them,
# otherwise you repair yourself. No mode key — the player's intent is already
# unambiguous from where they're looking, and a toggle here is pure friction.
#
# RESOURCE: a self-recharging reservoir by default, because it's the lowest
# friction option and self-balances without ever hard-blocking the player. Set
# use_ammo_pool to draw from finite charges instead once you know what the
# economy should be — shards are spoken for, so the other candidate is salvage
# off destroyed robots, which reuses the Interactible pickup you already have.
#
# INTERRUPTION is where the feel lives. Taking damage breaks the channel, but
# progress persists for resume_grace seconds — so ducking behind cover and
# resuming doesn't restart from zero. That turns an interrupt from a punishment
# into a rhythm. Call interrupt() from the player's apply_damage.
# ─────────────────────────────────────────────

@export var heal_per_second: float = 22.0
@export var repair_range: float = 3.5
# Reviving is aimed at something on the floor, so it gets a wider cone and a bit
# more reach than topping up a standing squadmate. 0.82 is roughly a 35 degree
# half-angle around the sightline.
@export var revive_aim_tolerance: float = 0.82
@export var revive_reach_bonus: float = 1.5

## Hurt allies within this range stop moving while the repair button is held,
## so you can actually get the crosshair on one mid-fight.
@export var assist_radius: float = 9.0
@export var assist_allies: bool = true
# Everyone frozen by _assist_hold(), so the releases can be matched exactly.
var _assisted: Array = []
# Who the CHANNEL is pinning, tracked separately from _target. Re-pressing on
# the same patient used to call hold_still() again without a matching release,
# leaving them stuck until max_hold_time expired thirty seconds later.
var _held_target: Node = null
# Reservoir units spent per point of health restored.
@export var cost_per_health: float = 1.0

# ── RESOURCE ──────────────────────────────────
@export var use_ammo_pool: bool = false
@export var ammo_type: StringName = &"repair"
@export var reservoir_max: float = 100.0
@export var recharge_per_second: float = 6.0
# Seconds after the last repair before the reservoir starts refilling.
@export var recharge_delay: float = 4.0

# ── CHANNEL ───────────────────────────────────
@export var resume_grace: float = 2.5
# Movement is allowed while channelling, but slowed. The player reads this.
@export var move_penalty: float = 0.45

@export var loop_sound: AudioStreamPlayer3D
@export var complete_sound: AudioStreamPlayer3D

signal channel_started(target: Node)
signal channel_ended(target: Node)
signal repaired(target: Node, amount: int)
# The squad should hold a member still while you're working on them. This is an
# order, not a new mechanic — SquadCommander already has the vocabulary.
signal repair_target_pinned(target: Node)
signal repair_target_released(target: Node)

var reservoir: float = 0.0
var _channelling: bool = false
var _target: Node = null
var _partial: float = 0.0        # fractional health carried between frames
var _grace_t: float = 0.0
var _recharge_t: float = 0.0


func _on_initialize() -> void:
	# The slot is NOT forced here any more. The tool lives on key 3 now — the
	# player scene places it in the MELEE slot as a permanent item — and forcing
	# EQUIPMENT at this point overrode that and left key 3 empty. The default
	# is still EQUIPMENT, and apply_record() sets it explicitly for anything it
	# builds from a record.
	consumes_charge = true
	# Used pressed up against the robot you are fixing, so it never swings aside.
	lowers_when_obstructed = false
	# Don't yank it out of their hands the instant the reservoir empties —
	# they're probably mid-repair and it refills.
	reverts_when_empty = false
	# Deliberately TRUE. Refusing to equip an empty repair tool reads as the
	# item being broken — and combined with the recharge only running while
	# equipped, it was a permanent deadlock: empty meant you couldn't hold it,
	# and not holding it meant it never refilled. Let them pull it out and watch
	# the bar climb.
	equippable_when_empty = true
	reservoir = reservoir_max


func has_charge() -> bool:
	if use_ammo_pool:
		return ammo != null and ammo.get_count(ammo_type) > 0
	return reservoir >= cost_per_health


func charges_remaining() -> int:
	if use_ammo_pool:
		return ammo.get_count(ammo_type) if ammo != null else 0
	return int(reservoir)


func get_readout() -> Readout:
	var r := Readout.new(ReadoutMode.CHANNEL)
	r.label = display_name
	# Was reservoir over nothing, which printed "100/0" and read as broken.
	# Charge over capacity is what the player actually wants to know.
	r.primary = charges_remaining()
	r.secondary = int(reservoir_max) if not use_ammo_pool else 0
	if use_ammo_pool:
		r.fraction = 1.0 if has_charge() else 0.0
	else:
		r.fraction = clampf(reservoir / maxf(reservoir_max, 0.01), 0.0, 1.0)
	r.warn = not has_charge()
	if _channelling and _target != null:
		r.label = "REPAIRING"
	return r


func is_busy() -> bool:
	return _channelling


# Multiply the player's movement speed by this while the tool is working.
func get_move_scale() -> float:
	return move_penalty if _channelling else 1.0


func _on_unequip() -> void:
	_stop_channel()
	# Stowing the tool must never leave the squad frozen where they stood.
	_assist_release()


# ─────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────
func primary_pressed() -> void:
	if is_raising():
		return
	if not has_charge():
		denied.emit("NO CHARGE")
		return
	# Freeze the ward BEFORE trying to acquire. A hurt robot is still fighting —
	# strafing, bounding, chasing — and putting a crosshair on a moving ally
	# while you are also being shot at is most of why the repair tool felt
	# broken. Holding the button says "hold still, all of you", which is a thing
	# a squad leader can plausibly order and makes the aim a formality.
	_assist_hold()
	_start_channel()


func primary_released() -> void:
	_stop_channel()
	_assist_release()


# ─────────────────────────────────────────────
# ASSIST HOLD
# Paired strictly with _assist_release(). hold_still() is reference counted, so
# an unmatched call pins a robot until max_hold_time (30s) bails it out.
# ─────────────────────────────────────────────
func _assist_hold() -> void:
	if not assist_allies or player == null:
		return
	_assist_release()
	var origin: Vector3 = player.global_position
	var r_sq: float = assist_radius * assist_radius
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == player or not (node is Node3D):
			continue
		if not _is_repairable_ally(node):
			continue
		if _is_full(node):
			continue
		if origin.distance_squared_to((node as Node3D).global_position) > r_sq:
			continue
		if node.has_method("hold_still"):
			node.hold_still()
			_assisted.append(node)


func _assist_release() -> void:
	for node in _assisted:
		if node != null and is_instance_valid(node) and node.has_method("release_hold"):
			node.release_hold()
	_assisted.clear()


# Call from the player's apply_damage. Progress survives for resume_grace.
func interrupt() -> void:
	# Released unconditionally: being shot mid-repair is exactly when a frozen
	# squad standing still around you is worst.
	_assist_release()
	if _channelling:
		_stop_channel()
		denied.emit("REPAIR INTERRUPTED")


# The reservoir refills whether or not it's in your hands. This is the half of
# the deadlock fix that matters — see equippable_when_empty above for the other.
func tick_stowed(delta: float) -> void:
	if _recharge_t > 0.0:
		_recharge_t = maxf(0.0, _recharge_t - delta)
		return
	_tick_recharge(delta)


# Back to full at base.
func restock() -> void:
	reservoir = reservoir_max
	_recharge_t = 0.0
	_grace_t = 0.0
	_partial = 0.0
	charges_changed.emit()


func tick(delta: float) -> void:
	if _grace_t > 0.0:
		_grace_t = maxf(0.0, _grace_t - delta)
		if _grace_t <= 0.0:
			_partial = 0.0

	if _channelling:
		_tick_channel(delta)
	else:
		_tick_recharge(delta)


func _tick_recharge(delta: float) -> void:
	if use_ammo_pool:
		return
	if _recharge_t > 0.0:
		_recharge_t = maxf(0.0, _recharge_t - delta)
		return
	if reservoir < reservoir_max:
		reservoir = minf(reservoir_max, reservoir + recharge_per_second * delta)
		charges_changed.emit()


# ─────────────────────────────────────────────
# CHANNEL
# ─────────────────────────────────────────────
func _start_channel() -> void:
	var target := _acquire_target()
	if target == null:
		denied.emit("NO TARGET")
		return
	# Re-pressing while already channelling on someone else would otherwise
	# leave the previous patient pinned forever.
	if _channelling and _target != target:
		_stop_channel()
	if _target != target:
		# Different patient — progress doesn't carry across.
		_partial = 0.0
	_target = target
	_channelling = true
	_grace_t = 0.0
	if loop_sound != null and not loop_sound.playing:
		loop_sound.play()
	if _target != player and _held_target != _target:
		# Pin them. Without this the patient walks off mid-channel, the
		# crosshair loses them, and _tick_channel drops the repair a frame
		# later — which is the "putzing around" problem.
		#
		# Guarded on _held_target: clicking again on the same patient used to
		# add a second reference-counted hold that nothing ever released.
		_release_channel_hold()
		if _target.has_method("hold_still"):
			_target.hold_still()
			_held_target = _target
		repair_target_pinned.emit(_target)
	channel_started.emit(_target)


func _release_channel_hold() -> void:
	if _held_target == null:
		return
	if is_instance_valid(_held_target) and _held_target.has_method("release_hold"):
		_held_target.release_hold()
		repair_target_released.emit(_held_target)
	_held_target = null


func _stop_channel() -> void:
	if not _channelling:
		return
	_channelling = false
	_grace_t = resume_grace
	_recharge_t = recharge_delay
	if loop_sound != null:
		loop_sound.stop()
	_release_channel_hold()
	channel_ended.emit(_target)


func _tick_channel(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_stop_channel()
		return
	if not has_charge():
		denied.emit("NO CHARGE")
		_stop_channel()
		return
	# Re-acquire each frame — look away and the channel drops, which is the
	# feedback that tells the player targeting is where they're pointing.
	if _target != player and _acquire_target() != _target:
		_stop_channel()
		return
	# BACK ON ITS FEET, BACK IN THE FIGHT. revive() happens partway through the
	# channel — health only comes back to revive_at_fraction — so the tool kept
	# topping them up afterwards with the pin still on. That is the "revived and
	# then paralysed for four seconds": they were repaired and standing, and
	# being held the whole time. Healing continues; the hold does not.
	if _held_target != null and "downed" in _held_target and not _held_target.downed:
		_release_channel_hold()

	if _is_full(_target):
		if complete_sound != null:
			complete_sound.play()
		_stop_channel()
		return

	_partial += heal_per_second * delta
	var whole := int(floor(_partial))
	if whole <= 0:
		return
	_partial -= float(whole)

	var cost := float(whole) * cost_per_health
	if use_ammo_pool:
		var granted := ammo.take(ammo_type, int(ceil(cost))) if ammo != null else 0
		if granted <= 0:
			_stop_channel()
			return
	else:
		if reservoir < cost:
			whole = int(reservoir / maxf(cost_per_health, 0.01))
			cost = float(whole) * cost_per_health
		reservoir = maxf(0.0, reservoir - cost)

	if whole <= 0:
		_stop_channel()
		return

	_apply_repair(_target, whole)
	charges_changed.emit()
	used.emit()


func _apply_repair(target: Node, amount: int) -> void:
	if target.has_method("apply_healing"):
		target.apply_healing(amount)
	elif "health" in target and "max_health" in target:
		target.health = mini(int(target.max_health), int(target.health) + amount)
	repaired.emit(target, amount)


func _is_full(target: Node) -> bool:
	# A downed robot is never "full" — there's always the revive to finish.
	if "downed" in target and target.downed:
		return false
	if "health" in target and "max_health" in target:
		return int(target.health) >= int(target.max_health)
	return false


# ─────────────────────────────────────────────
# TARGETING
# ─────────────────────────────────────────────
# A friendly under the crosshair wins; otherwise you patch yourself up.
func _acquire_target() -> Node:
	var exclude: Array = [player] if player != null else []
	var hit := aim_ray(repair_range, exclude)
	if not hit.is_empty():
		var candidate = hit.get("collider")
		if candidate != null:
			var body = candidate
			if not ("faction" in body) and body.get_parent() != null:
				body = body.get_parent()
			if _is_repairable_ally(body):
				return body

	# Ray missed. A collapsed robot is a small, low target and the camera is at
	# head height, so requiring a clean hit makes reviving feel broken even when
	# everything is wired correctly. Fall back to the nearest downed ally you're
	# roughly facing.
	var downed_ally := _find_downed_ally_near_aim()
	if downed_ally != null:
		return downed_ally

	return player


func _find_downed_ally_near_aim() -> Node:
	if cam == null:
		return null
	var forward: Vector3 = -cam.global_transform.basis.z.normalized()
	var best: Node = null
	var best_dot: float = revive_aim_tolerance

	for squad in get_tree().get_nodes_in_group("squads"):
		if not (squad is Squad):
			continue
		for member in (squad as Squad).squad_members:
			if member == null or not is_instance_valid(member):
				continue
			if not ("downed" in member) or not member.downed:
				continue
			if not _is_repairable_ally(member):
				continue
			var to_member: Vector3 = member.global_position - cam.global_position
			if to_member.length() > repair_range + revive_reach_bonus:
				continue
			# Dot product against the sightline: 1.0 is dead ahead.
			var facing: float = forward.dot(to_member.normalized())
			if facing > best_dot:
				best_dot = facing
				best = member
	return best


func _is_repairable_ally(body) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if not ("faction" in body):
		return false
	# A downed ally IS a valid patient — that's the revive. A properly destroyed
	# one is not: `downed` distinguishes the wreck you can bring back from the
	# one you can't.
	if "downed" in body and body.downed:
		return not Enums.are_hostile(Enums.Factions.PLAYER, body.faction)
	if "alive" in body and not body.alive:
		return false
	return not Enums.are_hostile(Enums.Factions.PLAYER, body.faction)
