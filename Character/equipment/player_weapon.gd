extends PlayerEquipment
class_name PlayerWeapon

# ─────────────────────────────────────────────
# PLAYER WEAPON — the gun half of the split.
#
# Magazines, reserve ammunition, reloading, firemode and ADS live here.
# Everything above this (bob, pose, equip lifecycle, the HUD readout contract)
# is PlayerEquipment and is shared with the grenade, scanner and repair tool.
#
# TWO THINGS THIS FIXES OUTRIGHT
#
# 1. Ammunition is finite. The old start_reload() did
#        magazine_capacity = magazine_size
#    unconditionally. Reloading now transfers rounds out of the shared AmmoPool
#    and fails when the pool is empty.
#
# 2. The reload is cancellable. The old one was
#        await get_tree().create_timer(reload_time).timeout
#    which cannot be aborted — switch weapons or die mid-reload and the
#    coroutine still fired and still refilled the magazine. Harmless while ammo
#    was free; with a reserve it's a duplication bug. It's now a delta-driven
#    timer that _on_unequip() cancels.
#
# NAMING — the old script had magazine_size as the maximum and
# magazine_capacity as the current count, which reads backwards. The maximum
# keeps the name magazine_size (the weapon scenes store it, renaming it would
# silently drop the stored values) and the current count is now `loaded`.
# ─────────────────────────────────────────────

# ── AMMUNITION ────────────────────────────────
# Keyed by TYPE, so two weapons on the same feed share a reserve. Must match an
# AmmoStock in the loadout's starting_ammo.
@export var ammo_type: StringName = &"5.56"
@export var magazine_size: int = 30
@export var reload_time: float = 2.15
# TRUE  — a partial magazine is thrown away when you reload. Every reload is a
#         decision and panic-reloading after each contact costs you.
# FALSE — leftover rounds go back into the reserve. Forgiving, arcade.
# This is the single most felt consequence of finite ammo. It's per-weapon so
# you can try both; play it before committing.
@export var discrete_magazines: bool = true
# Fire the first shot straight out of a reload without a cooldown gap.
@export var chamber_round: bool = true

# ── FIRING ────────────────────────────────────
@export var firemode: Enums.FireModes

# ── MANUAL ACTION (pump / bolt) ───────────────
# FireModes.MANUAL existed in the enum but nothing implemented it — a weapon set
# to MANUAL simply never fired, because primary_pressed only answered SEMI and
# FULL. A manual gun fires one round per trigger pull and then has to cycle
# before the next, which is what makes a pump feel like a pump rather than a
# slow semi-auto.
@export var pump_time: float = 0.55
@export var pump_sound: AudioStreamPlayer3D

@export var damage: int = 10
@export var FIRE_RATE: float = 0.100

# ── ADS ───────────────────────────────────────
@export var ADS_FOV: float = 45.0
@export var HIP_FOV: float = 70.0
@export var ADS_SPEED: float = 10.0
@export var ads_bob_scale: float = 0.05
@export var ads_position: Vector3 = Vector3(0.0, 0.0, -1.077)
@export var ads_rotation: Vector3 = Vector3(0.0, 0.0, 3.0)

# ── RELOAD PRESENTATION ───────────────────────
@export var reload_position: Vector3 = Vector3(0.31, -0.425, -0.015)
@export var reload_rotation: Vector3 = Vector3(0.2, 20.5, 58.0)
@export var reload_sounds: Array[AudioStreamPlayer3D]
@export var reload_delays: Array[float]
@export var click_stream_player: AudioStreamPlayer3D

signal fired
signal reload_started
signal reload_finished
signal reload_cancelled

# ── RUNTIME ───────────────────────────────────
var loaded: int = 0
var is_reloading: bool = false
var fire_cooldown: float = 0.0

var _reload_t: float = 0.0
var _sound_index: int = 0
var _sound_t: float = 0.0
var _fire_held: bool = false

# MANUAL action only: true while the gun is being cycled and cannot fire.
var needs_pump: bool = false
var _pump_remaining: float = 0.0


func _on_initialize() -> void:
	loaded = magazine_size
	# Spawning with a full magazine shouldn't also cost you a magazine from the
	# reserve — the starting AmmoStock is what you carry ON TOP of what's loaded.


# ─────────────────────────────────────────────
# AMMUNITION
# ─────────────────────────────────────────────
func reserve() -> int:
	if ammo == null:
		return 0
	return ammo.get_count(ammo_type)


# A gun is "charged" if it can shoot OR could be reloaded. An empty magazine
# with rounds in the bag is still a usable weapon, so it stays selectable.
func has_charge() -> bool:
	return loaded > 0 or reserve() > 0


func charges_remaining() -> int:
	return loaded + reserve()


func consume_charge() -> void:
	loaded = maxi(0, loaded - 1)
	charges_changed.emit()


func get_readout() -> Readout:
	var r := Readout.new(ReadoutMode.MAGAZINE)
	r.primary = loaded
	r.secondary = reserve()
	r.label = display_name
	# Discrete magazines means the player is choosing between MAGAZINES, so show
	# them magazines — a raw round count doesn't support the decision.
	if discrete_magazines and magazine_size > 0:
		r.secondary = int(floor(float(reserve()) / float(magazine_size)))
	r.warn = loaded == 0 or (loaded <= magazine_size / 4 and reserve() == 0)
	return r


# ─────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────
# Mid-reload counts as busy. The loadout decides whether that blocks a switch or
# just cancels — see EquipmentLoadout.cancel_busy_on_switch.
func is_busy() -> bool:
	return is_reloading


func _on_unequip() -> void:
	# THE important line. Without it a reload that started before the switch
	# completes in the background and credits a magazine you didn't pay for.
	cancel_reload()
	_fire_held = false


# ─────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────
func primary_pressed() -> void:
	_fire_held = true
	if firemode == Enums.FireModes.SEMI:
		try_fire()
	elif firemode == Enums.FireModes.FULL:
		try_fire()
	elif firemode == Enums.FireModes.MANUAL:
		# One round per pull, same as SEMI. The difference is the cycle gate in
		# can_fire(), not the trigger.
		try_fire()


func primary_held(_delta: float) -> void:
	if firemode == Enums.FireModes.FULL:
		try_fire()


func primary_released() -> void:
	_fire_held = false


func reload_pressed() -> void:
	start_reload()


func tick(delta: float) -> void:
	if fire_cooldown > 0.0:
		fire_cooldown -= delta
	_tick_pump(delta)
	_tick_reload(delta)


# The cycle. Ends by telling the HUD, because "ready to fire again" is part of
# the readout even though the round count has not moved.
func _tick_pump(delta: float) -> void:
	if not needs_pump:
		return
	_pump_remaining -= delta
	if _pump_remaining <= 0.0:
		_pump_remaining = 0.0
		needs_pump = false
		charges_changed.emit()


func _start_pump() -> void:
	needs_pump = true
	_pump_remaining = pump_time
	if pump_sound != null:
		pump_sound.play()
	charges_changed.emit()


# ─────────────────────────────────────────────
# FIRING
# ─────────────────────────────────────────────
func can_fire() -> bool:
	return not is_reloading and fire_cooldown <= 0.0 and not is_raising() \
		and not needs_pump


func try_fire() -> void:
	if not can_fire():
		return
	if loaded <= 0:
		_dry_fire()
		return
	fire_cooldown = FIRE_RATE
	_fire_shot()
	loaded = maxi(0, loaded - 1)
	# Cycle even on the last round: you rack the empty gun, and the reload picks
	# up from there. Skipping the pump when empty would let a reload-cancel fire
	# instantly off a gun that was never cycled.
	if firemode == Enums.FireModes.MANUAL:
		_start_pump()
	charges_changed.emit()
	fired.emit()
	used.emit()
	# A gun with an empty magazine and an empty bag is spent. reverts_when_empty
	# is off for guns by default — you want to keep holding it and hear the
	# click, not get silently switched — but the signal is there if you want it.
	if not has_charge():
		_notify_spent()


func _dry_fire() -> void:
	fire_cooldown = FIRE_RATE
	if click_stream_player != null:
		click_stream_player.play()
	denied.emit("EMPTY")


# Subclasses do the actual shot — raycast, tracer, muzzle flash, recoil.
func _fire_shot() -> void:
	pass


# ─────────────────────────────────────────────
# RELOAD — delta driven, cancellable, paid for
# ─────────────────────────────────────────────
func start_reload() -> void:
	if not is_equipped or is_reloading:
		return
	if loaded >= magazine_size:
		return
	if reserve() <= 0:
		if click_stream_player != null:
			click_stream_player.play()
		denied.emit("NO AMMO")
		return
	is_reloading = true
	_reload_t = reload_time
	_sound_index = 0
	_sound_t = 0.0
	reload_started.emit()


func cancel_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	_reload_t = 0.0
	_stop_reload_sounds()
	reload_cancelled.emit()


func _tick_reload(delta: float) -> void:
	if not is_reloading:
		return

	# Reload sounds, previously a chain of awaits that couldn't be stopped.
	if _sound_index < reload_sounds.size() and _sound_index < reload_delays.size():
		_sound_t += delta
		if _sound_t >= reload_delays[_sound_index]:
			_sound_t = 0.0
			var s: AudioStreamPlayer3D = reload_sounds[_sound_index]
			if s != null:
				s.play()
			_sound_index += 1

	_reload_t -= delta
	if _reload_t > 0.0:
		return
	_finish_reload()


# The reserve is debited HERE, at completion, not at the start. A cancelled
# reload therefore costs nothing and needs no refund path — which is the one
# place an ammo system usually leaks.
func _finish_reload() -> void:
	is_reloading = false
	# Reloading chambers a round, so a manual action comes out of it ready. Left
	# set, the gun would demand a pump it had already been given.
	needs_pump = false
	_pump_remaining = 0.0
	if ammo == null:
		loaded = magazine_size
		charges_changed.emit()
		reload_finished.emit()
		return

	var wanted: int = magazine_size
	if not discrete_magazines:
		wanted = magazine_size - loaded

	var granted: int = ammo.take(ammo_type, wanted)

	if discrete_magazines:
		# Whatever was still in the magazine goes on the floor with it.
		loaded = granted
	else:
		loaded = mini(magazine_size, loaded + granted)

	charges_changed.emit()
	reload_finished.emit()
	if chamber_round:
		fire_cooldown = 0.0


func _stop_reload_sounds() -> void:
	for s in reload_sounds:
		if s != null and s.playing:
			s.stop()


# ─────────────────────────────────────────────
# VIEWMODEL
# ─────────────────────────────────────────────
func _get_pose_target() -> Array:
	if is_reloading:
		return [reload_position, reload_rotation]
	if is_obstructed:
		return [obstructed_position, obstructed_rotation]
	if is_ads:
		return [ads_position, ads_rotation]
	return [base_position, base_rotation]


func _bob_amount_now() -> float:
	return bob_amount * ads_bob_scale if is_ads else bob_amount


func _apply_bob() -> bool:
	return not is_reloading
