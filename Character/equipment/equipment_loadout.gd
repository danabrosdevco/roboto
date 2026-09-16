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
	var item := item_for_slot(index)
	if item == null:
		denied.emit("EMPTY SLOT")
		return
	equip_item(item)


func equip_item(item: PlayerEquipment) -> void:
	if item == null or item == current:
		return

	# Denied rather than equipped-and-useless. Pulling out a grenade you don't
	# have is worse than the input doing nothing.
	if not item.can_equip():
		denied.emit("%s : EMPTY" % item.display_name.to_upper())
		return

	if current != null and current.is_busy():
		if not cancel_busy_on_switch:
			denied.emit("BUSY")
			return

	if current != null:
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
	if target == null or not target.can_equip():
		target = _first_available()
	if target != null:
		equip_item(target)


func _first_available() -> PlayerEquipment:
	for candidate in [primary, sidearm, melee]:
		if candidate != null and candidate.can_equip():
			return candidate
	for item in _all:
		if item.can_equip():
			return item
	return null


func _on_wants_revert(item: PlayerEquipment) -> void:
	if current == item:
		revert()


func _on_charges_changed() -> void:
	readout_changed.emit(get_readout())


func get_readout() -> PlayerEquipment.Readout:
	if current == null:
		return PlayerEquipment.Readout.new(PlayerEquipment.ReadoutMode.NONE)
	return current.get_readout()


# ─────────────────────────────────────────────
# PER-FRAME
# ─────────────────────────────────────────────
# Call this once from the player's _physics_process, after movement so
# move_factor is current. It owns fire/reload/slot input so the player script
# stops reaching into the weapon directly.
func update(delta: float, move_factor: float, obstructed: bool, ads: bool) -> void:
	_handle_slot_input()

	# Everything you are NOT holding still ticks. Cooldowns and reservoirs don't
	# pause because you happen to be carrying a rifle — and for the repair tool
	# that was a hard deadlock: empty meant it couldn't be equipped, and not
	# being equipped meant it never recharged.
	for item in _all:
		if item != current:
			item.tick_stowed(delta)

	if current == null:
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


func _handle_use_input(delta: float) -> void:
	var pressed := Input.is_action_pressed(fire_action)
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

	# Tear down only what WE built. Anything hand-placed and listed in
	# permanent_items survives, which is what keeps melee from evaporating.
	for node in _record_built:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_record_built.clear()

	var current_id: StringName = &""
	for group in [record.weapon_ids, record.equipment_ids]:
		for item_id in group:
			if item_id == &"":
				continue
			var item = catalogue.item(item_id)
			if item == null or not item.fits_player() or item.player_scene == null:
				continue
			var node = item.player_scene.instantiate()
			if not (node is PlayerEquipment):
				push_warning("EquipmentLoadout: %s is not a PlayerEquipment scene." % item.player_scene.resource_path)
				node.queue_free()
				continue
			search_root.add_child(node)
			_record_built.append(node)
			current_id = item_id

	# Hand-placed items we're replacing must go, or you end up holding two
	# rifles — the authored one and the one the record asked for.
	for child in search_root.get_children():
		if child is PlayerEquipment and not _record_built.has(child) \
				and not permanent_items.has(child):
			child.queue_free()

	# Rebuild the slot table from what's actually there now.
	primary = null
	sidearm = null
	melee = null
	equipment.clear()
	current = null
	_previous = null
	await get_tree().process_frame
	_collect()
	for item in _all:
		item.initialize(player, cam, ammo)
		if not item.charges_changed.is_connected(_on_charges_changed):
			item.charges_changed.connect(_on_charges_changed)
			item.wants_revert.connect(_on_wants_revert.bind(item))
			item.denied.connect(func(reason: String): denied.emit(reason))
	var opener := _first_available()
	if opener != null:
		equip_item(opener)


# For a resupply crate or a respawn.
# Reserve, magazines, reservoirs and cooldowns. ammo.reset() alone restored the
# starting reserve and nothing else — every weapon kept whatever was chambered
# when you extracted, and the repair tool's reservoir isn't in the AmmoPool at
# all, so neither came back.
func refill() -> void:
	if ammo != null:
		ammo.refill_all()
	for item in _all:
		item.restock()
		if item is PlayerWeapon:
			var gun := item as PlayerWeapon
			gun.cancel_reload()
			gun.loaded = gun.magazine_size
	_on_charges_changed()
