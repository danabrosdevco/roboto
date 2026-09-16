extends PlayerEquipment
class_name PlayerScanner

# ─────────────────────────────────────────────
# PLAYER SCANNER — now a real equipment slot rather than a key on the player.
#
# It was already a quick-use tool with its own cooldown driven straight out of
# test_character._physics_process; this just gives it a slot, a viewmodel and a
# readout. It's also the cheapest test of whether the base class is right: the
# scanner predates the abstraction, so if it doesn't fit cleanly the abstraction
# is wrong.
#
# Drives the EXISTING Scanner component rather than absorbing it, so the sfx
# wiring in scanner.tscn and the highlight_target -> hud.activate_enemy_marker
# connection keep working untouched.
#
# Unlike the grenade this does NOT auto-revert — a scanner with no charges is
# just a scanner on cooldown, and yanking it out of the player's hands mid-sweep
# would be wrong.
# ─────────────────────────────────────────────

# The existing Character/components/scanner.tscn instance.
@export var scanner: Node3D
@export var cooldown: float = 12.0
# Kept in sync with the component so the readout matches the sweep.
@export var deploy_sound: AudioStreamPlayer3D

signal scan_started(cooldown: float)
signal scan_finished

var _cooldown_t: float = 0.0
var _scan_t: float = 0.0
var _scanning: bool = false


func _on_initialize() -> void:
	slot = Slot.EQUIPMENT
	consumes_charge = false
	reverts_when_empty = false
	equippable_when_empty = true
	if scanner == null and player != null:
		scanner = player.get("scanner")


func can_equip() -> bool:
	return true


func has_charge() -> bool:
	return _cooldown_t <= 0.0


func charges_remaining() -> int:
	return 1 if has_charge() else 0


func get_readout() -> Readout:
	var r := Readout.new(ReadoutMode.COOLDOWN)
	r.label = display_name
	if _scanning:
		r.fraction = clampf(1.0 - (_scan_t / maxf(_scan_duration(), 0.01)), 0.0, 1.0)
		r.label = "SCANNING"
	elif _cooldown_t > 0.0:
		r.fraction = clampf(1.0 - (_cooldown_t / maxf(cooldown, 0.01)), 0.0, 1.0)
	else:
		r.fraction = 1.0
	r.warn = _cooldown_t > 0.0
	return r


func is_busy() -> bool:
	return _scanning


func _scan_duration() -> float:
	if scanner != null and "scan_duration" in scanner:
		return float(scanner.scan_duration)
	return 3.5


# ─────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────
func primary_pressed() -> void:
	if is_raising():
		return
	if _scanning:
		return
	if _cooldown_t > 0.0:
		denied.emit("SCANNER CHARGING")
		return
	if scanner == null:
		push_warning("PlayerScanner: no Scanner component assigned.")
		return

	_scanning = true
	_scan_t = _scan_duration()
	_cooldown_t = cooldown
	if deploy_sound != null:
		deploy_sound.play()
	scanner.activate_scan()
	scan_started.emit(cooldown)
	used.emit()
	charges_changed.emit()


func tick(delta: float) -> void:
	if _scanning:
		_scan_t -= delta
		if _scan_t <= 0.0:
			_scanning = false
			scan_finished.emit()
		charges_changed.emit()
		return

	if _cooldown_t > 0.0:
		_cooldown_t = maxf(0.0, _cooldown_t - delta)
		charges_changed.emit()


func restock() -> void:
	_cooldown_t = 0.0
	_scanning = false
	charges_changed.emit()


# The cooldown keeps running while the scanner is stowed — it's a system
# recharging, not something you have to stand still holding.
func tick_stowed(delta: float) -> void:
	if _cooldown_t > 0.0:
		_cooldown_t = maxf(0.0, _cooldown_t - delta)
