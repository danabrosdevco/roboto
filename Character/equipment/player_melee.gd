extends PlayerEquipment
class_name PlayerMelee

# ─────────────────────────────────────────────
# PLAYER MELEE — slot 3.
#
# The only item that can never be empty, which makes it the floor of the whole
# system. When a consumable runs out and auto-revert has nowhere to go, this is
# where the player lands. That's why equippable_when_empty is forced true here
# and why EquipmentLoadout._first_available() checks it last but always finds it.
#
# No ammo, no reload, no readout — the HUD ammo widget should draw nothing.
# ─────────────────────────────────────────────

@export var damage: int = 40
@export var range: float = 2.2
@export var swing_time: float = 0.45
# When the damage lands within the swing, as a fraction of swing_time. Damage on
# the contact frame rather than the input frame, so the animation reads.
@export var impact_at: float = 0.35
@export var swing_rotation: Vector3 = Vector3(-35.0, 15.0, 0.0)
@export var swing_sound: AudioStreamPlayer3D
@export var hit_sound: AudioStreamPlayer3D

signal swung
signal hit(target: Node)

var _swing_t: float = 0.0
var _swinging: bool = false
var _impact_done: bool = false


func _on_initialize() -> void:
	slot = Slot.MELEE
	consumes_charge = false
	equippable_when_empty = true
	reverts_when_empty = false


func can_equip() -> bool:
	return true


func has_charge() -> bool:
	return true


func get_readout() -> Readout:
	var r := Readout.new(ReadoutMode.NONE)
	r.label = display_name
	return r


func is_busy() -> bool:
	return _swinging


func _on_unequip() -> void:
	_swinging = false
	_swing_t = 0.0


func primary_pressed() -> void:
	if _swinging or is_raising():
		return
	_swinging = true
	_swing_t = 0.0
	_impact_done = false
	if swing_sound != null:
		swing_sound.play()
	swung.emit()
	used.emit()


func tick(delta: float) -> void:
	if not _swinging:
		return
	_swing_t += delta
	if not _impact_done and _swing_t >= swing_time * impact_at:
		_impact_done = true
		_strike()
	if _swing_t >= swing_time:
		_swinging = false
		_swing_t = 0.0


func _strike() -> void:
	var exclude: Array = [player] if player != null else []
	var result := aim_ray(range, exclude)
	if result.is_empty():
		return
	var collider = result.get("collider")
	if collider == null:
		return
	var victim = collider
	if not victim.has_method("apply_damage") and victim.get_parent() != null:
		victim = victim.get_parent()
	if victim.has_method("apply_damage"):
		victim.apply_damage(damage, player)
		if hit_sound != null:
			hit_sound.play()
		hit.emit(victim)


func _extra_rotation() -> Vector3:
	if not _swinging:
		return Vector3.ZERO
	# Out and back over the swing.
	var t := clampf(_swing_t / maxf(swing_time, 0.01), 0.0, 1.0)
	var arc := sin(t * PI)
	return swing_rotation * arc
