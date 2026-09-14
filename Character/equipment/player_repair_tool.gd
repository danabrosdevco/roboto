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
	slot = Slot.EQUIPMENT
	consumes_charge = true
	# Don't yank it out of their hands the instant the reservoir empties —
	# they're probably mid-repair and it refills.
	reverts_when_empty = false
	equippable_when_empty = false
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
	r.primary = charges_remaining()
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


# ─────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────
func primary_pressed() -> void:
	if is_raising():
		return
	if not has_charge():
		denied.emit("NO CHARGE")
		return
	_start_channel()


func primary_released() -> void:
	_stop_channel()


# Call from the player's apply_damage. Progress survives for resume_grace.
func interrupt() -> void:
	if _channelling:
		_stop_channel()
		denied.emit("REPAIR INTERRUPTED")


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
	if _target != player:
		# Pin them. Without this the patient walks off mid-channel, the
		# crosshair loses them, and _tick_channel drops the repair a frame
		# later — which is the "putzing around" problem.
		if _target.has_method("hold_still"):
			_target.hold_still()
		repair_target_pinned.emit(_target)
	channel_started.emit(_target)


func _stop_channel() -> void:
	if not _channelling:
		return
	_channelling = false
	_grace_t = resume_grace
	_recharge_t = recharge_delay
	if loop_sound != null:
		loop_sound.stop()
	if _target != null and is_instance_valid(_target) and _target != player:
		if _target.has_method("release_hold"):
			_target.release_hold()
		repair_target_released.emit(_target)
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
	return player


func _is_repairable_ally(body) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if not ("faction" in body):
		return false
	if "alive" in body and not body.alive:
		# Destroyed squadmates are out of scope for now. If squad members are
		# meant to be yours across missions rather than replaceable, reviving is
		# the same channel with a different precondition and this is where it
		# would go.
		return false
	return not Enums.are_hostile(Enums.Factions.PLAYER, body.faction)
