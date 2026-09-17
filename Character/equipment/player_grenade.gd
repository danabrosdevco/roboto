extends PlayerEquipment
class_name PlayerGrenade

# ─────────────────────────────────────────────
# PLAYER GRENADE
#
# Throwables are the awkward case for number-key selection: select, throw, and
# then you're standing in a firefight holding nothing. That's what
# reverts_when_empty solves — spend the last one and the loadout puts your rifle
# back. Set it false if you'd rather keep holding grenades until you switch.
#
# Reuses the AI's projectile as-is. The physics, fuse and explosion are already
# written and there's no reason for the player to have a second copy — only the
# decision to throw differs, and that's this class. Worth moving
# ai_grenade_projectile.gd up out of the ai/ folder at some point, since both
# sides use it now.
# ─────────────────────────────────────────────

@export var grenade_scene: PackedScene       # AIGrenadeProjectile
@export var ammo_type: StringName = &"grenade"
@export var throw_speed: float = 16.0
# Upward bias on the throw. 0 throws flat down the crosshair, higher lobs it.
@export var throw_arc: float = 0.25
# Seconds between the input and the grenade actually leaving your hand — the
# animation window. Also the window in which a switch is refused.
@export var throw_time: float = 0.35
@export var spawn_offset: Vector3 = Vector3(0.0, -0.1, -0.6)

# Hold to cook. Off by default — cooking is a good mechanic but it needs a
# self-damage story and an audio cue before it's fair.
@export var can_cook: bool = false
@export var max_cook_time: float = 2.5

@export var throw_sound: AudioStreamPlayer3D
@export var pin_sound: AudioStreamPlayer3D

signal thrown(grenade: Node3D)

var _throwing: bool = false
var _throw_t: float = 0.0
var _cook_t: float = 0.0
var _cooking: bool = false


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
	if _cooking:
		r.fraction = clampf(_cook_t / maxf(max_cook_time, 0.01), 0.0, 1.0)
	return r


func is_busy() -> bool:
	return _throwing or _cooking


func _on_unequip() -> void:
	# A grenade half-thrown when you switch away is cancelled outright rather
	# than spawning later out of an item you're no longer holding.
	_throwing = false
	_cooking = false
	_throw_t = 0.0
	_cook_t = 0.0


# ─────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────
func primary_pressed() -> void:
	if _throwing or is_raising():
		#print ("THROWING OR RAISING")
		return
	if not has_charge():
		#denied.emit("NO GRENADES")
		return
	if can_cook:
		_cooking = true
		_cook_t = 0.0
		if pin_sound != null:
			pin_sound.play()
	else:
		_begin_throw()


func primary_held(delta: float) -> void:
	if _cooking:
		_cook_t += delta


func primary_released() -> void:
	if _cooking:
		_cooking = false
		_begin_throw()


func _begin_throw() -> void:
	_throwing = true
	_throw_t = throw_time
	if throw_sound != null:
		throw_sound.play()


func tick(delta: float) -> void:
	if not _throwing:
		return
	_throw_t -= delta
	if _throw_t > 0.0:
		return
	_throwing = false
	_release_grenade()


# ─────────────────────────────────────────────
# THROW
# ─────────────────────────────────────────────
func _release_grenade() -> void:
	if grenade_scene == null:
		push_error("PlayerGrenade: no grenade_scene assigned.")
		return
	if not has_charge():
		return
	if cam == null:
		return

	var world: Node = null
	if player != null:
		world = player.get("world")
	if world == null:
		world = get_tree().current_scene

	var g := grenade_scene.instantiate()
	world.add_child(g)

	var cam_basis := cam.global_transform.basis
	g.global_position = cam.global_position + (cam_basis * spawn_offset)

	var dir := (-cam_basis.z.normalized() + Vector3.UP * throw_arc).normalized()
	if g is RigidBody3D:
		var body := g as RigidBody3D
		body.linear_velocity = dir * throw_speed
		# Inherit the player's motion so throwing while running doesn't drop it
		# at your feet.
		if player != null and player is CharacterBody3D:
			body.linear_velocity += (player as CharacterBody3D).velocity
		body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))

	# Stops the thrower damaging themselves — same contract the AI uses.
	if g.has_method("setup"):
		g.setup(player)

	consume_charge()
	thrown.emit(g)
	used.emit()
	_notify_spent()
