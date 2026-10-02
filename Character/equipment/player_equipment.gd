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
## Swung aside, muzzle to the LEFT of screen. 90, not 270: the two are the same
## line mirrored, and 270 pointed the barrel out to the right and back across the
## view, so a long weapon swept three quarters of a turn to get there instead of
## a quarter. It reads as the gun whipping round the wrong way. The shotgun was
## given 90 on its own when someone hit this before, which left eighteen other
## items still inheriting the flip — fixed on the class this time.
@export var obstructed_rotation: Vector3 = Vector3(0.3, 90.0, 3.0)
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
## What bob added to viewmodel.position last frame, taken back out before the
## pose lerp runs again. See the note in update_view().
var _last_bob: Vector3 = Vector3.ZERO
## The pose lerp's own state, in DEGREES. See update_view().
var _pose_rotation: Vector3 = Vector3.ZERO
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
		# DEGREES, because every pose in this system is degrees — swing_rotation
		# (-18, 6, 0), the default reload_rotation (0.2, 20.5, 58.0), the bob term
		# at amount * 20.0 — and update_view() ends by writing rotation_DEGREES.
		# Reading .rotation here took the authored pose in radians and handed it to
		# a degrees pipeline, so the repair lance's 107.9 degrees of yaw became 1.88
		# and the lance lay flat across the screen: the exact thing its own scene
		# comment says the authored basis exists to prevent.
		base_rotation = viewmodel.rotation_degrees
		_rest_pose_read = true
	_pose_rotation = base_rotation
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
		# Degrees. Assigning .rotation here put the then-default holster pose of
		# (0.3, 270, 3) on screen as 15469 degrees of yaw and 172 of roll — every
		# item in the game spun through forty-three turns each time you drew it.
		viewmodel.rotation_degrees = obstructed_rotation
		_pose_rotation = obstructed_rotation
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

	# TAKE LAST FRAME'S BOB BACK OUT BEFORE LERPING.
	#
	# Bob used to be added straight into viewmodel.position, and the next
	# frame's lerp then read that as where the weapon actually was. The
	# vertical term is abs(sin()) — never negative — so every frame shoved the
	# model up and the lerp only pulled back `delta * pose_speed` of it. It
	# settled bob_amount / (delta * pose_speed) above its own pose: 6mm on the
	# recoilless at the 60Hz physics tick this runs on. Six millimetres is
	# nothing on a rifle you never look down, and everything on an iron sight
	# 0.41m from the eye — it is 0.8 degrees, which puts the rocket a metre low
	# at 65m while the ring looks like it is on the target.
	viewmodel.position -= _last_bob
	_last_bob = Vector3.ZERO

	if viewmodel.position.distance_to(target_pos) > 0.001:
		viewmodel.position = viewmodel.position.lerp(target_pos, delta * pose_speed)
	# THE ROTATION LERP KEEPS ITS OWN STATE AND NEVER READS THE NODE BACK.
	#
	# It ran on viewmodel.rotation, which is RADIANS, while the write at the
	# bottom of this function is rotation_DEGREES. So every frame read back 1/57.3
	# of what the frame before it wrote, and a pose settled at about 17% of the
	# angle it named — the 270 degree holster yaw arrived as 45.8. Same shape as
	# the bob double-count above, same cure: the lerp owns its state rather than
	# reading it off the thing it just drove.
	if _pose_rotation.distance_to(target_rot) > 0.001:
		_pose_rotation = _pose_rotation.lerp(target_rot, delta * pose_speed)

	# BOB AND ANY ADDITIVE OFFSET GO ON AFTER THE LERP, and come back off at the
	# top of the next frame by the same accounting. See the note above: anything
	# written into viewmodel.position that the lerp then reads back as "where the
	# weapon is" feeds itself.
	var offset := Vector3.ZERO
	if _apply_bob():
		offset += bob_offset
	offset += _extra_position()
	viewmodel.position += offset
	_last_bob = offset

	var bob_rotation := Vector3(
		sin(_bob_time * 2.0) * amount * 20.0,
		sin(_bob_time) * amount * 10.0,
		0.0
	)
	viewmodel.rotation_degrees = _pose_rotation + _extra_rotation() + bob_rotation


func _bob_amount_now() -> float:
	return bob_amount


## An additive position offset applied AFTER the pose lerp — the positional twin
## of _extra_rotation().
##
## A movement that has to land on a DEADLINE belongs here rather than in
## _get_pose_target(), because the lerp only ever chases its target at
## pose_speed. At the default 10 that is a 0.1s time constant, so a 0.16s thrust
## routed through the pose reaches about four fifths of its extension by the
## moment it is supposed to connect, peaks after the hit has already landed, and
## reads as a shove rather than a stab. Out here it is exact.
func _extra_position() -> Vector3:
	return Vector3.ZERO


# [position, rotation]. Guns override to add the ADS and reload poses.
func _get_pose_target() -> Array:
	if is_obstructed:
		return [obstructed_position, obstructed_rotation]
	return [base_position, base_rotation]


## The field of view this item aims down to, or 0 for something that cannot be
## aimed — a scanner, a repair tool, a grenade in your hand.
##
## Asked of whatever is HELD rather than read off PlayerWeapon, because aiming
## is not a property of being a gun. The launcher is a PlayerEquipment with a
## sight on the tube; before this, Player.current_weapon() cast the held item
## to PlayerWeapon, got null, and the aim button did nothing at all with a
## recoilless rifle up.
func ads_fov() -> float:
	return 0.0


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


## WHERE A SPAWNED THING BELONGS: THE LEVEL, NOT THE WORLD.
##
## `player.world` is the persistent node that levels are loaded INTO — the
## player is a SIBLING of the level, not a child of it, which is why it
## survives a mission change. Parenting ordnance there makes the ordnance
## survive too: a Drone Carrier Pack thrown in the depot put two Divers in the
## air that were still flying after the next mission loaded.
##
## World.current_level is what deload_current_level() frees, so anything
## parented to it goes when the mission does. The AI side already worked this
## out — see ai_weapon_grenade_launcher._charge_parent(), which notes that a
## bomb in the air at extraction used to come home with you.
var _warned_no_level: bool = false


func level_node() -> Node:
	var w = player.get("world") if player != null else null
	if w != null:
		var lvl = w.get("current_level")
		if lvl != null and is_instance_valid(lvl):
			return lvl
		# Falling back to the World means whatever this is will outlive the
		# mission. Worth saying so — once: this is also the tracer path, and a
		# warning per round would bury the message it is trying to send.
		if not _warned_no_level:
			_warned_no_level = true
			push_warning("%s: no current_level, so this is being parented to the World and will survive a mission change." % display_name)
		return w
	return get_tree().current_scene
