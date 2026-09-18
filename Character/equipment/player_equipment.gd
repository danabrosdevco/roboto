extends Node3D
class_name PlayerEquipment

# ─────────────────────────────────────────────
# PLAYER EQUIPMENT — base class for everything the player holds.
#
# Guns, melee, grenades, the scanner and the repair tool are all this. They live
# as persistent children of the Camera3D and are shown/hidden by the loadout —
# nothing is instantiated at use-time. That's the opposite of AIEquipment, which
# spawns, executes and frees; the player needs a viewmodel that persists across
# frames and that model doesn't fit.
#
# WHAT LIVES HERE vs IN PlayerWeapon
# This class owns everything every held item needs: the viewmodel pose stack
# (bob, the lerp between poses, the swing-away when you're against a wall), the
# equip/unequip lifecycle, and the charge/readout interface the HUD reads.
# PlayerWeapon adds the gun-only half — magazines, reloading, recoil, ADS.
# If you find yourself adding a firemode or a magazine here, it belongs there.
#
# SUBCLASSES OVERRIDE
#   _on_equip() / _on_unequip()    lifecycle hooks
#   _get_pose_target()             where the viewmodel wants to sit this frame
#   _extra_rotation()              recoil and other additive rotation
#   primary_pressed() etc.         input
#   has_charge() / consume_charge()
#   get_readout()                  what the HUD ammo widget shows
# ─────────────────────────────────────────────

# Which key selects this. PRIMARY/SIDEARM/MELEE are 1/2/3 and there is only ever
# one of each. EQUIPMENT is 4/5/6 and is an ordered list, so adding a fourth
# piece of kit later is a data change rather than an enum change.
enum Slot { PRIMARY, SIDEARM, MELEE, EQUIPMENT }

# How the HUD should draw this item's status.
#   MAGAZINE  loaded / reserve      — guns
#   COUNT     a single number       — grenades
#   COOLDOWN  a 0-1 fill            — scanner
#   CHANNEL   a 0-1 fill + a number — repair tool
#   NONE      nothing               — melee
enum ReadoutMode { NONE, MAGAZINE, COUNT, COOLDOWN, CHANNEL }


# What the HUD needs to draw one status widget, whatever the item is. This is
# the whole reason hud.update_status() can stop reaching into the weapon for
# magazine_capacity — items answer a question instead of exposing fields.
class Readout:
	var mode: int = ReadoutMode.NONE
	var primary: int = 0        # rounds loaded, grenades left, charges left
	var secondary: int = 0      # reserve rounds, or magazines held
	var fraction: float = 0.0   # 0-1 for COOLDOWN and CHANNEL
	var label: String = ""
	var warn: bool = false      # HUD should colour this as low/empty

	func _init(p_mode: int = ReadoutMode.NONE) -> void:
		mode = p_mode


# ── IDENTITY ──────────────────────────────────
@export var display_name: String = "Equipment"
@export var slot: Slot = Slot.EQUIPMENT
# Position within the EQUIPMENT list. 0 is key 4, 1 is key 5, and so on.
# Ignored for PRIMARY/SIDEARM/MELEE.
@export var equipment_order: int = 0
@export var icon: Texture2D

# ── VIEWMODEL ─────────────────────────────────
# The visible model. Left null for items with no viewmodel yet — everything
# still works, you just don't see anything in hand.
@export var viewmodel: Node3D
@export var use_default_position: bool = true
@export var base_position: Vector3 = Vector3(0.31, -0.425, -0.015)
@export var base_rotation: Vector3 = Vector3(-0.3, 6.0, 2.8)
@export var obstructed_position: Vector3 = Vector3(-0.5, -0.425, -1.0)
@export var obstructed_rotation: Vector3 = Vector3(0.3, 270.0, 3.0)
## Swing aside when something is right in front of the camera. Off for items
## used up close: the repair tool's whole job is standing against a robot,
## which is exactly what the obstruction ray sees.
@export var lowers_when_obstructed: bool = true
@export var pose_speed: float = 10.0
@export var bob_speed: float = 1.1
@export var bob_amount: float = 0.015
@export var movement_bob_scale: float = 2.2

# ── BEHAVIOUR ─────────────────────────────────
# Seconds the item takes to come up. Blocks use, not switching.
@export var equip_time: float = 0.25
# Does using this spend a charge?  Guns and grenades yes, scanner and melee no.
@export var consumes_charge: bool = true
# When the last charge is spent, hand control back to whatever was held before.
# This is what makes "press 4, throw, back to the rifle" work without a
# dedicated throw key. Off for the scanner — you put that away yourself.
@export var reverts_when_empty: bool = true
# Can this be selected at all when empty? Almost always no: equipping an empty
# hand is worse than denying the input.
@export var equippable_when_empty: bool = false
# ── SIGNALS ───────────────────────────────────
signal equipped
signal unequipped
@warning_ignore("unused_signal")
signal used                          # one discrete use happened
signal charges_changed               # HUD should re-read get_readout()
signal wants_revert                  # empty, and reverts_when_empty is set
@warning_ignore("unused_signal")
signal denied(reason: String)        # tried to use it and couldn't

# ── RUNTIME ───────────────────────────────────
var player: Node = null
var cam: Camera3D = null
var ammo: AmmoPool = null

var is_equipped: bool = false
var move_factor: float = 0.0
var is_obstructed: bool = false
var _rest_pose_read: bool = false
var is_ads: bool = false

var _bob_time: float = 0.0
var _equip_timer: float = 0.0


# Called by EquipmentLoadout — again on every rebuild, for permanent items.
# Don't do this in _ready: the item needs
# references it can't find on its own, and _ready order isn't guaranteed.
func initialize(p_player: Node, p_cam: Camera3D, p_ammo: AmmoPool) -> void:
	player = p_player
	cam = p_cam
	ammo = p_ammo
	# _on_initialize BEFORE set_hidden: subclasses assign `viewmodel` in there
	# (HUDWeapon forwards its own weapon_model export into it) and set_hidden
	# needs it to already be there or the model starts visible.
	_on_initialize()
	# The authored pose, read ONCE. "Called once" above is not true of a
	# permanent item: the loadout re-initializes everything when it rebuilds
	# from the save, and by then the item may already have been drawn — which
	# snaps the model to the obstructed pose. Re-reading here recorded that
	# off-screen spot as the rest pose, and the repair tool sat beside your head
	# where no scale would ever bring it into view.
	if use_default_position == false and not _rest_pose_read:
		base_position = viewmodel.position
		base_rotation = viewmodel.rotation
		_rest_pose_read = true
	set_hidden(true)


func _on_initialize() -> void:
	pass


# ─────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────
# The loadout asks before switching. Default: you can't pull out something with
# nothing in it. Melee overrides this by never being empty.
func can_equip() -> bool:
	if equippable_when_empty:
		return true
	return has_charge()


# True while the item is doing something that shouldn't be interrupted by a slot
# change — mid-reload, mid-throw, mid-channel. The loadout checks this and will
# either refuse the switch or cancel the action, depending on its policy.
func is_busy() -> bool:
	return false


func equip() -> void:
	if is_equipped:
		return
	is_equipped = true
	_equip_timer = equip_time
	set_hidden(false)
	# Snap the pose to the obstructed position so the item swings up into view
	# rather than popping in at the ready pose.
	if viewmodel != null:
		viewmodel.position = obstructed_position
		viewmodel.rotation = obstructed_rotation
	_on_equip()
	equipped.emit()


func unequip() -> void:
	if not is_equipped:
		return
	is_equipped = false
	_on_unequip()
	set_hidden(true)
	unequipped.emit()


func set_hidden(hidden: bool) -> void:
	visible = not hidden
	if viewmodel != null:
		viewmodel.visible = not hidden
	set_process(not hidden)
	set_physics_process(not hidden)


# Subclasses put "cancel whatever I was doing" in _on_unequip. This is the hook
# that stops a reload continuing to completion after you've switched away —
# which, with a finite reserve, would otherwise be an accounting bug.
func _on_equip() -> void:
	pass


func _on_unequip() -> void:
	pass


func is_raising() -> bool:
	return _equip_timer > 0.0


# Per-frame logic for the equipped item. Driven by the loadout rather than
# _process so ordering against input is explicit — an item must never fire on a
# frame after the loadout has already switched away from it.
func tick(_delta: float) -> void:
	pass


# Ticked for every item you are NOT holding. Anything that recovers over time
# has to run here, or it only recovers while equipped — which for a resource
# that gates equipping is a deadlock: empty means you can't hold it, and not
# holding it means it never refills.
func tick_stowed(_delta: float) -> void:
	pass


# Called by EquipmentLoadout.refill() at base. Reservoirs, cooldowns, anything
# that isn't in the shared AmmoPool and so isn't covered by refill_all().
func restock() -> void:
	pass


# ─────────────────────────────────────────────
# INPUT — the loadout routes to whatever is held
# ─────────────────────────────────────────────
func primary_pressed() -> void:
	pass


func primary_held(_delta: float) -> void:
	pass


func primary_released() -> void:
	pass


func secondary_pressed() -> void:
	pass


func secondary_released() -> void:
	pass


func reload_pressed() -> void:
	pass


# ─────────────────────────────────────────────
# CHARGES
# ─────────────────────────────────────────────
# Default is "always usable" — correct for melee and the scanner. Anything that
# draws on the ammo pool overrides all three.
func has_charge() -> bool:
	return true


func charges_remaining() -> int:
	return 1


func consume_charge() -> void:
	pass


# Call after spending the last one. Emits wants_revert so the loadout can put
# the previous item back rather than leaving the player holding nothing.
func _notify_spent() -> void:
	charges_changed.emit()
	if consumes_charge and reverts_when_empty and not has_charge():
		wants_revert.emit()


func get_readout() -> Readout:
	return Readout.new(ReadoutMode.NONE)


# ─────────────────────────────────────────────
# VIEWMODEL
# ─────────────────────────────────────────────
# Called every frame by the loadout for the equipped item only. Bob and the pose
# lerp are shared by everything you can hold; guns extend the pose set with ADS
# and reload via _get_pose_target().
func update_view(delta: float, p_move_factor: float, p_obstructed: bool, p_ads: bool) -> void:
	move_factor = p_move_factor
	is_obstructed = p_obstructed and lowers_when_obstructed
	is_ads = p_ads

	if _equip_timer > 0.0:
		_equip_timer = maxf(0.0, _equip_timer - delta)

	if viewmodel == null:
		return

	_bob_time += delta * bob_speed * (1.0 + move_factor * movement_bob_scale)
	var amount := _bob_amount_now()
	var bob_offset := Vector3(
		sin(_bob_time * 2.0) * amount * 0.5,
		abs(sin(_bob_time)) * amount,
		0.0
	)

	var target: Array = _get_pose_target()
	var target_pos: Vector3 = target[0]
	var target_rot: Vector3 = target[1]

	if viewmodel.position.distance_to(target_pos) > 0.001:
		viewmodel.position = viewmodel.position.lerp(target_pos, delta * pose_speed)
	if viewmodel.rotation.distance_to(target_rot) > 0.001:
		viewmodel.rotation = viewmodel.rotation.lerp(target_rot, delta * pose_speed)

	if _apply_bob():
		viewmodel.position += bob_offset

	var bob_rotation := Vector3(
		sin(_bob_time * 2.0) * amount * 20.0,
		sin(_bob_time) * amount * 10.0,
		0.0
	)
	viewmodel.rotation_degrees = viewmodel.rotation + _extra_rotation() + bob_rotation


func _bob_amount_now() -> float:
	return bob_amount


# [position, rotation]. Guns override to add the ADS and reload poses.
func _get_pose_target() -> Array:
	if is_obstructed:
		return [obstructed_position, obstructed_rotation]
	return [base_position, base_rotation]


func _apply_bob() -> bool:
	return true


# Additive rotation on top of the pose — recoil for guns, swing for melee.
func _extra_rotation() -> Vector3:
	return Vector3.ZERO


# ─────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────
# Where the player is looking. Everything that needs a world target — the
# grenade arc, the repair beam, the melee swing — starts here.
func aim_ray(distance: float, exclude: Array = []) -> Dictionary:
	if cam == null:
		return {}
	var from := cam.global_position
	var to := from + (-cam.global_transform.basis.z.normalized() * distance)
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.exclude = exclude
	query.collide_with_areas = false
	var space := get_world_3d().direct_space_state
	var result := space.intersect_ray(query)
	return result if result else {}


func aim_point(distance: float, exclude: Array = []) -> Vector3:
	var hit := aim_ray(distance, exclude)
	if hit.is_empty():
		if cam == null:
			return global_position
		return cam.global_position + (-cam.global_transform.basis.z.normalized() * distance)
	return hit.position
