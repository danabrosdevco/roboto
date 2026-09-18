extends Node
class_name EquipmentLoadout

# ─────────────────────────────────────────────
# EQUIPMENT LOADOUT — owns the slots, the keys, and what's in your hands.
#
# Replaces weapon_list / current_weapon_index / set_active_weapon /
# switch_weapon_direct on the player. Those toggled `active` and
# `weapon_model.visible` from outside, which meant an item had no way to react
# to being put away — the reason a reload could complete after you'd switched.
#
# SLOTS
#   1  PRIMARY     2  SIDEARM     3  MELEE     4/5/6  EQUIPMENT[0..2]
#
# PRIMARY/SIDEARM/MELEE are named because there is only ever one of each.
# EQUIPMENT is an ordered list so a fourth piece of kit is a data change, not an
# enum change, and so a mission can hand out a different set without new code.
#
# AUTO-REVERT is what makes number-key selection work for throwables. The
# loadout remembers what you were holding; when a consumable runs dry and has
# reverts_when_empty set, you go back to it. That gets you throw-and-return
# without a dedicated grenade key.
# ─────────────────────────────────────────────

@export var player: Node
@export var cam: Camera3D
@export var ammo: AmmoPool

# Leave these empty to auto-collect every PlayerEquipment under `search_root`
# (the camera by default), sorting by slot and equipment_order. Assign them to
# override — useful for per-mission loadouts.
@export var search_root: Node
@export var primary: PlayerEquipment
@export var sidearm: PlayerEquipment
@export var melee: PlayerEquipment
@export var equipment: Array[PlayerEquipment] = []

# Input actions, in slot order. "4", "5" and "6" are NOT in the project's input
# map yet — add them before the equipment slots will respond.
@export var slot_actions: Array[StringName] = [&"1", &"2", &"3", &"4", &"5", &"6"]
@export var fire_action: StringName = &"fire"
@export var alt_fire_action: StringName = &"aim"
@export var reload_action: StringName = &"reload"

# TRUE  — pressing 2 mid-reload cancels the reload and switches.
# FALSE — the switch is refused until the reload finishes (the old behaviour,
#         which used an early `return` and silently ate the rest of the input
#         frame along with it).
@export var cancel_busy_on_switch: bool = true

# ── BUILD FROM THE RECORD ─────────────────────
# The player's kit came from whatever PlayerEquipment nodes happened to be
# parented under the camera in test_character.tscn — authored once, identical
# every mission, and untouched by the management screen. The squad's loadout was
# already data; the player's wasn't, so fitting a rifle to YOU changed a record
# nobody read.
#
# apply_record() rebuilds the hierarchy from CampaignState.player_record instead.
# Auto-collect is still the fallback, so a scene with no campaign behaves exactly
# as it always did.
@export var build_from_record: bool = true
# Kept and never rebuilt, because they aren't items. Melee in particular is the
# floor the whole slot system falls back to and must always exist.
@export var permanent_items: Array[PlayerEquipment] = []

var _record_built: Array[PlayerEquipment] = []

signal equipped(item: PlayerEquipment)
signal denied(reason: String)
signal readout_changed(readout: PlayerEquipment.Readout)

var current: PlayerEquipment = null
var _previous: PlayerEquipment = null
var _all: Array[PlayerEquipment] = []
var _fire_held: bool = false

# A record change can replace the object currently in the player's hands. Keep
# update/input out of the transition, and never carry held-trigger state from an
# old instance into the replacement instance.
var _rebuilding: bool = false
# True while `current` is the loadout's own automatic pick rather than
# something the player selected. See _ready and apply_record.
var _auto_opened: bool = false
var _block_fire_until_release: bool = false


func _is_live(item: PlayerEquipment) -> bool:
	return is_instance_valid(item) and not item.is_queued_for_deletion()


func _slot_index_for_item(item: PlayerEquipment) -> int:
	if not _is_live(item):
		return -1
	if item == primary:
		return 0
	if item == sidearm:
		return 1
	if item == melee:
		return 2
	var equipment_index := equipment.find(item)
	if equipment_index >= 0:
		return equipment_index + 3
	return -1


func _ready() -> void:
	if search_root == null:
		search_root = cam
	_collect()
	for item in _all:
		item.initialize(player, cam, ammo)
		item.charges_changed.connect(_on_charges_changed)
		item.wants_revert.connect(_on_wants_revert.bind(item))
		item.denied.connect(func(reason: String): denied.emit(reason))
	# Start on the first thing that will actually come up.
	for candidate in [primary, sidearm, melee]:
		if candidate != null and candidate.can_equip():
			equip_item(candidate)
			break
	if current == null and not _all.is_empty():
		equip_item(_all[0])
	# Whatever that was, nobody chose it. At this point only the hand-placed
	# permanent item exists — the record's guns are built later by
	# apply_record() — so this is almost always the key-3 tool, and it must
	# not be mistaken for what the player was holding.
	_auto_opened = true


func _collect() -> void:
	_all.clear()
	var found: Array[PlayerEquipment] = []
	if search_root != null:
		_gather(search_root, found)

	# Explicit assignments win; anything not assigned is filled from what we
	# found, so a scene can be fully implicit or fully explicit or a mix.
	var loose: Array[PlayerEquipment] = []
	for item in found:
		match item.slot:
			PlayerEquipment.Slot.PRIMARY:
				if primary == null:
					primary = item
			PlayerEquipment.Slot.SIDEARM:
				if sidearm == null:
					sidearm = item
			PlayerEquipment.Slot.MELEE:
				if melee == null:
					melee = item
			_:
				loose.append(item)

	if equipment.is_empty():
		loose.sort_custom(func(a, b): return a.equipment_order < b.equipment_order)
		equipment = loose

	for item in [primary, sidearm, melee]:
		if item != null and not _all.has(item):
			_all.append(item)
	for item in equipment:
		if item != null and not _all.has(item):
			_all.append(item)


func _gather(node: Node, out: Array[PlayerEquipment]) -> void:
	for child in node.get_children():
		# queue_free() does not remove a node from the tree until the end of the
		# frame. A loadout rebuild must not recollect those outgoing instances.
		if child.is_queued_for_deletion():
			continue
		if child is PlayerEquipment:
			out.append(child)
		_gather(child, out)


# ─────────────────────────────────────────────
# SELECTION
# ─────────────────────────────────────────────
func item_for_slot(index: int) -> PlayerEquipment:
	match index:
		0: return primary
		1: return sidearm
		2: return melee
		_:
			var i := index - 3
			if i >= 0 and i < equipment.size():
				return equipment[i]
	return null


func equip_slot(index: int) -> void:
	_auto_opened = false
	var item := item_for_slot(index)
	if not _is_live(item):
		denied.emit("EMPTY SLOT")
		return
	equip_item(item)


func equip_item(item: PlayerEquipment) -> void:
	if not _is_live(item) or item == current:
		return

	# Denied rather than equipped-and-useless. Pulling out a grenade you don't
	# have is worse than the input doing nothing.
	if not item.can_equip():
		denied.emit("%s : EMPTY" % item.display_name.to_upper())
		return

	if _is_live(current) and current.is_busy():
		if not cancel_busy_on_switch:
			denied.emit("BUSY")
			return

	if _is_live(current):
		# If the trigger was down on the old item, finish that input lifecycle on
		# the old item. The replacement/new item waits for a fresh press.
		if _fire_held:
			current.primary_released()
			_fire_held = false
			_block_fire_until_release = Input.is_action_pressed(fire_action)
		_previous = current
		current.unequip()

	current = item
	current.equip()
	equipped.emit(current)
	_on_charges_changed()


# Where auto-revert lands. Falls through to melee, which can never be empty and
# is therefore the floor of the whole system — without it you can end up holding
# nothing and the game has no opinion about what that means.
func revert() -> void:
	var target := _previous
	if not _is_live(target) or not target.can_equip():
		target = _first_available()
	if _is_live(target):
		equip_item(target)


func _first_available() -> PlayerEquipment:
	for candidate in [primary, sidearm, melee]:
		if _is_live(candidate) and candidate.can_equip():
			return candidate
	for item in _all:
		if _is_live(item) and item.can_equip():
			return item
	return null


func _on_wants_revert(item: PlayerEquipment) -> void:
	if current == item:
		revert()


func _on_charges_changed() -> void:
	readout_changed.emit(get_readout())


func get_readout() -> PlayerEquipment.Readout:
	if not _is_live(current):
		return PlayerEquipment.Readout.new(PlayerEquipment.ReadoutMode.NONE)
	return current.get_readout()


# ─────────────────────────────────────────────
# PER-FRAME
# ─────────────────────────────────────────────
# Call this once from the player's _physics_process, after movement so
# move_factor is current. It owns fire/reload/slot input so the player script
# stops reaching into the weapon directly.
func update(delta: float, move_factor: float, obstructed: bool, ads: bool) -> void:
	# apply_record() is synchronous now, but this also protects against any signal
	# callback that tries to drive equipment during the rebuild itself.
	if _rebuilding:
		return

	_handle_slot_input()

	# Everything you are NOT holding still ticks. Cooldowns and reservoirs don't
	# pause because you happen to be carrying a rifle — and for the repair tool
	# that was a hard deadlock: empty meant it couldn't be equipped, and not
	# being equipped meant it never recharged.
	for item in _all:
		if not _is_live(item):
			continue
		if item != current:
			item.tick_stowed(delta)

	if not _is_live(current):
		current = null
		_fire_held = false
		if Input.is_action_pressed(fire_action):
			_block_fire_until_release = true
		return

	_handle_use_input(delta)
	current.tick(delta)
	current.update_view(delta, move_factor, obstructed, ads)


func _handle_slot_input() -> void:
	for i in slot_actions.size():
		var action := slot_actions[i]
		if not InputMap.has_action(action):
			continue
		if Input.is_action_just_pressed(action):
			equip_slot(i)
			return


# Public because a UI can swallow the press a gun would otherwise inherit.
# Closing the squad manager with the mouse still down meant the first unpaused
# frame read a held trigger and fired a shot nobody asked for — the same
# inherited-trigger problem as a weapon switch, from a different direction.
func block_fire_until_release() -> void:
	_fire_held = false
	_block_fire_until_release = true


func _handle_use_input(delta: float) -> void:
	var pressed := Input.is_action_pressed(fire_action)

	# A held mouse button belongs to the item on which the press began. After a
	# switch/replacement, require release before beginning a new item's fire cycle.
	if _block_fire_until_release:
		_fire_held = false
		if not pressed:
			_block_fire_until_release = false
	else:
		if pressed and not _fire_held:
			current.primary_pressed()
		elif pressed:
			current.primary_held(delta)
		elif _fire_held:
			current.primary_released()
		_fire_held = pressed

	if Input.is_action_just_pressed(reload_action):
		current.reload_pressed()


# ─────────────────────────────────────────────
# RECORD -> NODES
# ─────────────────────────────────────────────
# Instances the player_scene of every fitted item under the camera, then
# re-collects. Called at deploy, and again whenever the record changes at base.
func apply_record(record, catalogue) -> void:
	if not build_from_record or record == null or catalogue == null:
		return
	if search_root == null:
		search_root = cam
	if search_root == null:
		return
	if _rebuilding:
		return

	_rebuilding = true

	# Preserve the logical slot, not the old Node. If the PRIMARY is replaced by
	# another PRIMARY, the player should come out holding the new PRIMARY.
	#
	# Unless nobody chose it. On spawn, _ready opens on the only thing that
	# exists yet — the permanent key-3 tool — and "keep the held slot" then
	# spawned you holding the repair tool (and before it, the knife) instead
	# of your gun. An automatic pick is not a choice to preserve.
	var held_slot := -1 if _auto_opened else _slot_index_for_item(current)

	# Finish the outgoing item's input/equip lifecycle while it is still alive.
	if _is_live(current):
		if _fire_held:
			current.primary_released()
		current.unequip()

	# Trigger state cannot be inherited by a newly-instanced gun/tool.
	_fire_held = false
	_block_fire_until_release = Input.is_action_pressed(fire_action)

	# CRITICAL: detach the old generation from every runtime lookup BEFORE any of
	# its nodes are freed. update() can no longer tick or select those objects.
	current = null
	_previous = null
	primary = null
	sidearm = null
	melee = null
	equipment.clear()
	_all.clear()

	# Tear down only what WE built. Anything hand-placed and listed in
	# permanent_items survives, which is what keeps melee from evaporating.
	for node in _record_built:
		if is_instance_valid(node):
			node.queue_free()
	_record_built.clear()

	# THE SLOT COMES FROM THE RECORD, not from the packed scene.
	#
	# m4_hud_weapon.tscn doesn't store `slot` — that was set on the INSTANCE in
	# test_character.tscn, which no longer exists. So a scene instanced here
	# arrives with the PlayerEquipment default of EQUIPMENT, and your rifle
	# quietly landed on key 4 instead of key 1. Which slot an item occupies is a
	# property of where it was fitted, so assign it from the array it came out
	# of and ignore whatever the scene happens to say.
	for weapon_index in record.weapon_ids.size():
		var node := _build_item(catalogue, record.weapon_ids[weapon_index])
		if node == null:
			continue
		# First weapon slot is PRIMARY, any further ones are SIDEARM.
		node.slot = PlayerEquipment.Slot.PRIMARY if weapon_index == 0 else PlayerEquipment.Slot.SIDEARM

	for equip_index in record.equipment_ids.size():
		var node := _build_item(catalogue, record.equipment_ids[equip_index])
		if node == null:
			continue
		node.slot = PlayerEquipment.Slot.EQUIPMENT
		# Position in the record decides whether it's key 4, 5 or 6.
		node.equipment_order = equip_index

	# Hand-placed items we're replacing must go, or you end up holding two
	# rifles — the authored one and the one the record asked for. Nodes queued
	# above are still children until end-of-frame, so skip them explicitly.
	for child in search_root.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is PlayerEquipment and not _record_built.has(child) \
				and not permanent_items.has(child):
			child.queue_free()

	# Rebuild immediately. _gather() ignores outgoing queued nodes, so there is no
	# process-frame gap in which _all can still point at the old generation.
	_collect()

	for item in _all:
		if not _is_live(item):
			continue
		item.initialize(player, cam, ammo)
		if not item.charges_changed.is_connected(_on_charges_changed):
			item.charges_changed.connect(_on_charges_changed)
			item.wants_revert.connect(_on_wants_revert.bind(item))
			item.denied.connect(func(reason: String): denied.emit(reason))

	# Before choosing what to hold: an empty grenade slot cannot be equipped,
	# and whether it is empty depends on this.
	_scale_thrown_capacity()

	# Prefer the newly-built item occupying the slot that was held before the
	# swap. If that slot no longer exists or cannot equip, use the normal fallback.
	var opener: PlayerEquipment = null
	if held_slot >= 0:
		opener = item_for_slot(held_slot)
		if not _is_live(opener) or not opener.can_equip():
			opener = null
	if opener == null:
		opener = _first_available()

	if _is_live(opener):
		equip_item(opener)
	else:
		_on_charges_changed()

	_auto_opened = false
	_rebuilding = false


# Two frags fitted is twice the frags carried. Thrown items only: guns share a
# reserve by calibre on purpose, and a second rifle is not a second bandolier.
func _scale_thrown_capacity() -> void:
	if ammo == null:
		return
	var carriers := {}
	for item in _all:
		if _is_live(item) and item is PlayerGrenade:
			var t: StringName = (item as PlayerGrenade).ammo_type
			carriers[t] = int(carriers.get(t, 0)) + 1
	for stock in ammo.starting_ammo:
		if stock != null and stock.ammo_type != &"":
			ammo.set_carriers(stock.ammo_type, int(carriers.get(stock.ammo_type, 1)))


func _build_item(catalogue, item_id: StringName) -> PlayerEquipment:
	if item_id == &"":
		return null
	var item = catalogue.item(item_id)
	if item == null:
		push_warning("EquipmentLoadout: no catalogue entry for '%s'." % item_id)
		return null
	if not item.fits_player():
		return null
	if item.player_scene == null:
		push_warning("EquipmentLoadout: '%s' has no player_scene; nothing to put in your hands." % item_id)
		return null
	var node = item.player_scene.instantiate()
	if not (node is PlayerEquipment):
		push_warning("EquipmentLoadout: %s is not a PlayerEquipment scene." % item.player_scene.resource_path)
		node.queue_free()
		return null
	search_root.add_child(node)
	_record_built.append(node)

	# Alignment and per-item stats come from the definition. Applied AFTER
	# add_child so the node's transform isn't overwritten by the scene's own.
	node.position = item.player_mount_offset
	node.rotation_degrees = item.player_mount_rotation_degrees
	node.display_name = item.display_name
	if node is PlayerWeapon:
		var gun := node as PlayerWeapon
		if item.ammo_type != &"":
			gun.ammo_type = item.ammo_type
		if item.weapon_damage > 0:
			gun.damage = item.weapon_damage

	return node


# For a resupply crate or a respawn.
# Reserve, magazines, reservoirs and cooldowns. ammo.reset() alone restored the
# starting reserve and nothing else — every weapon kept whatever was chambered
# when you extracted, and the repair tool's reservoir isn't in the AmmoPool at
# all, so neither came back.
func refill() -> void:
	if ammo != null:
		ammo.refill_all()
	for item in _all:
		if not _is_live(item):
			continue
		item.restock()
		if item is PlayerWeapon:
			var gun := item as PlayerWeapon
			gun.cancel_reload()
			gun.loaded = gun.magazine_size
	_on_charges_changed()
