extends Resource
class_name SoldierRecord

# ─────────────────────────────────────────────
# SOLDIER RECORD — a squadmate as DATA rather than as a node.
#
# Today a Soldier IS the record: name, health, role and equipment_slots all live
# on a node placed by hand in the level scene, and all of it dies with the
# scene. Nothing can persist between missions while that's true.
#
# This is the other half of the split. A record outlives every level. The
# spawner builds a Soldier from one at deploy, and writes the survivor's state
# back into it at extraction. Levels stop containing Soldiers and start
# containing SquadSpawnPoints.
#
# DAMAGE, NOT HEALTH
# The record stores damage taken rather than current health, so raising
# max_health via an upgrade doesn't retroactively heal everyone in the roster —
# and refunding that upgrade can't drop someone below zero. current_health() is
# always derived.
# ─────────────────────────────────────────────

enum Status { ACTIVE, WOUNDED, DESTROYED }

# Stable across saves. Assigned once by CampaignState.mint_id() — never
# regenerate on load or every reference to this soldier breaks.
@export var id: StringName = &""
@export var display_name: String = "Unnamed"

# The scene to instantiate. Null falls back to the spawner's default, which is
# what you want until chassis types exist.
@export var chassis_scene: PackedScene

# ── CONDITION ─────────────────────────────────
# DERIVED, not authored. Recomputed by recompute_stats() from the chassis base
# plus fitted modules, and cached here so every existing read of
# record.max_health keeps working. Making it a true function would mean
# threading an ItemCatalogue through the UI, the spawner, the HUD and the save
# for no behavioural gain. Anything set by hand here is overwritten.
@export var max_health: int = 100
# Cached the same way, for stats the record can't express as one number.
@export var effective_accuracy: float = 1.0
@export var effective_speed: float = 1.0
@export var effective_signal_bonus: float = 0.0
@export var effective_sensor_range: float = 45.0
# Summed from modules. Added to the soldier's own signal_resistance at spawn.
@export var effective_signal_resistance_bonus: float = 0.0
# Longest self-revive among fitted modules; 0 = none. Longest rather than
# summed: two nanite modules are one soldier getting up, not getting up twice.
@export var effective_self_revive: float = 0.0
@export var damage: int = 0
@export var signal_integrity: float = 1.0
@export var status: Status = Status.ACTIVE
# BENCHED — still on the roster, still repaired, restocked and kitted like
# anyone else, but left at base when the squad deploys. Toggled in the squad
# manager. A choice the player made, so it is saved, and it is never cleared
# for them.
@export var benched: bool = false

# ── KIT ───────────────────────────────────────
# Same resource type the AI already uses, so the armoury UI is dragging these
# between a pool array and this array. No stat trees, no per-soldier levelling.
@export var equipment: Array[AIEquipmentSlot] = []
# Optional override for the weapon node in the chassis scene. Leave null to use
# whatever the chassis ships with.
@export var weapon_scene: PackedScene

# ── LOADOUT (id-based) ────────────────────────
# Slots hold ITEM IDS, not resources. The armoury owns the actual counts and the
# catalogue owns the definitions, so a save file is a list of short strings and
# nothing can go stale when you retune an item's stats in a patch.
#
# An empty StringName means an empty slot. Slot COUNT comes from the chassis, so
# these arrays are resized to match whenever the chassis changes.
@export var chassis_id: StringName = &""
@export var weapon_ids: Array[StringName] = []
@export var equipment_ids: Array[StringName] = []
@export var module_ids: Array[StringName] = []

# ── RANK ──────────────────────────────────────
# Rank gates what a soldier may be fitted with; xp is just the counter that
# earns it. Deliberately coarse — the game should be about what they carry, not
# about grinding a number.
@export var rank: int = 0
@export var xp: int = 0
@export var xp_per_rank: int = 100
@export var max_rank: int = 5


func add_xp(amount: int) -> void:
	if amount <= 0 or rank >= max_rank:
		return
	xp += amount
	while xp >= xp_per_rank and rank < max_rank:
		xp -= xp_per_rank
		rank += 1


func rank_title() -> String:
	const TITLES := ["Recruit", "Regular", "Veteran", "Sergeant", "Lieutenant", "Captain"]
	return TITLES[clampi(rank, 0, TITLES.size() - 1)]


# Slot arrays follow the chassis. Fitting a smaller frame drops the overflow,
# and the caller is responsible for returning those items to the armoury first.
func resize_slots(chassis: ChassisDefinition) -> void:
	if chassis == null:
		return
	chassis_id = chassis.id
	weapon_ids.resize(chassis.weapon_slots)
	equipment_ids.resize(chassis.equipment_slots)
	module_ids.resize(chassis.module_slots)


func all_fitted_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for group in [weapon_ids, equipment_ids, module_ids]:
		for id_value in group:
			if id_value != null and id_value != &"":
				out.append(id_value)
	return out


# ── HISTORY ───────────────────────────────────
@export var missions_survived: int = 0
# Career total, accumulated at extraction from the body's per-mission count.
# Kept on the RECORD because that is the thing that outlives the robot — the
# node is destroyed between missions.
@export var confirmed_kills: int = 0
## Career total of squadmates this one got back on their feet — the repair
## tool, a mechanic's kit, a reclaimer's welder. A robot standing itself up on
## a nanite charge is not a revive: nobody did it for them.
@export var revives: int = 0
## The same for the mission just finished. Not saved.
var revives_this_mission: int = 0
# Kills from the mission just finished. NOT saved — it exists only long enough
# for the extraction to turn it into XP, because read_from() folds the body's
# count into the career total and zeroes the body on the way past.
var confirmed_kills_this_mission: int = 0
## Career kills by WHAT was killed: frame id -> count ("chaser": 3). See
## Campaign/kill_kinds.gd.
@export var kills_by_kind: Dictionary = {}
## The same for the mission just finished, for the debrief. Not saved.
var kills_by_kind_this_mission: Dictionary = {}

# Authored quantity per equipment slot, captured the first time we see it. The
# slot's own `quantity` is overwritten with what's left at extraction, so
# without this there's nothing left to restock FROM.
@export var equipment_max: Array[int] = []


func _sync_equipment_max() -> void:
	if equipment_max.size() == equipment.size():
		return
	equipment_max.clear()
	for slot in equipment:
		equipment_max.append(slot.quantity if slot != null else 0)


# Back to a full load-out. Condition is deliberately untouched — damage is the
# repair tool's problem, ammunition is the armoury's.
func restock() -> void:
	_sync_equipment_max()
	for i in equipment.size():
		if equipment[i] != null and i < equipment_max.size():
			equipment[i].quantity = equipment_max[i]


# ─────────────────────────────────────────────
# DERIVED STATS
# The chassis is the authority on how tough a soldier is. Toughness belongs to
# the frame, so moving someone onto a heavier chassis makes them tougher without
# anyone remembering to edit a number on the record.
# ─────────────────────────────────────────────
func recompute_stats(catalogue: ItemCatalogue) -> void:
	if catalogue == null:
		return
	var chassis := catalogue.chassis_def(chassis_id)
	if chassis == null:
		return

	var health := chassis.base_health
	var accuracy := chassis.base_accuracy
	var speed := chassis.base_speed
	var signal_gain := 0.0
	var sensors := chassis.base_sensor_range
	var resistance := 0.0
	var self_revive := 0.0
	for module_id in module_ids:
		if module_id == &"":
			continue
		var module := catalogue.item(module_id)
		if module == null:
			continue
		health += module.health_bonus
		accuracy += module.accuracy_bonus
		speed *= module.speed_multiplier
		signal_gain += module.signal_bonus
		sensors += module.sensor_bonus
		resistance += module.signal_resistance_bonus
		self_revive = maxf(self_revive, module.self_revive_seconds)

	max_health = maxi(1, health)
	effective_accuracy = accuracy
	effective_speed = speed
	effective_signal_bonus = signal_gain
	effective_sensor_range = maxf(4.0, sensors)
	effective_signal_resistance_bonus = resistance
	effective_self_revive = self_revive
	# Pulling a health module must not leave someone on negative health.
	damage = clampi(damage, 0, max_health)


# Slots and stats both come from the chassis, so they change together. Returns
# any item ids a smaller frame can't hold, for the caller to return to stores —
# dropping them silently would be theft.
#
# Modules first, equipment last: a Utility Harness that survives the move
# still counts toward the equipment slots of the new frame.
func set_chassis(chassis: ChassisDefinition, catalogue: ItemCatalogue) -> Array[StringName]:
	var displaced: Array[StringName] = []
	if chassis == null:
		return displaced
	for pair in [[weapon_ids, chassis.weapon_slots], [module_ids, chassis.module_slots]]:
		var slots: Array = pair[0]
		var keep: int = pair[1]
		for i in range(slots.size() - 1, keep - 1, -1):
			if slots[i] != &"":
				displaced.append(slots[i])
	chassis_id = chassis.id
	weapon_ids.resize(chassis.weapon_slots)
	module_ids.resize(chassis.module_slots)
	# A module can only be kept by a frame it fits. The harness is Soldier-only,
	# so moving onto a chaser hands it back rather than leaving a slot the frame
	# is not supposed to have.
	for i in module_ids.size():
		var module = catalogue.item(module_ids[i]) if catalogue != null and module_ids[i] != &"" else null
		if module != null and not module.fits_chassis(chassis.id):
			displaced.append(module_ids[i])
			module_ids[i] = &""
	# The frame is passed in, not looked up: with no catalogue the row must
	# still come out the frame's size, as resize_slots always made it.
	displaced.append_array(fit_equipment_capacity(catalogue, chassis))
	chassis_scene = chassis.scene
	recompute_stats(catalogue)
	return displaced


## Equipment slots: the frame's, plus whatever the fitted modules add. `frame`
## defaults to this record's own, looked up in the catalogue.
func equipment_capacity(catalogue: ItemCatalogue, frame: ChassisDefinition = null) -> int:
	if frame == null and catalogue != null:
		frame = catalogue.chassis_def(chassis_id)
	# No frame, no base to add to: keep the row as it is. Adding a module's
	# bonus to the CURRENT size instead would grow it on every settle.
	if frame == null:
		return equipment_ids.size()
	var n: int = frame.equipment_slots
	if catalogue != null:
		for module_id in module_ids:
			if module_id == &"":
				continue
			var module := catalogue.item(module_id)
			if module != null:
				n += module.equipment_slot_bonus
	return maxi(0, n)


## Grows or shrinks the equipment slots to capacity. Returns what a shrink
## pushed out, for the caller to put back in stores.
func fit_equipment_capacity(catalogue: ItemCatalogue, frame: ChassisDefinition = null) -> Array[StringName]:
	var displaced: Array[StringName] = []
	var capacity := equipment_capacity(catalogue, frame)
	for i in range(equipment_ids.size() - 1, capacity - 1, -1):
		if equipment_ids[i] != &"":
			displaced.append(equipment_ids[i])
	equipment_ids.resize(capacity)
	return displaced


func current_health() -> int:
	return maxi(0, max_health - damage)


## Fit to fight — COULD deploy. Repairs and revives go by this.
func is_deployable() -> bool:
	return status != Status.DESTROYED and current_health() > 0


## WILL deploy: fit to fight and not benched. This is what picks the squad.
func will_deploy() -> bool:
	return is_deployable() and not benched


func health_fraction() -> float:
	return float(current_health()) / float(maxi(1, max_health))


# ─────────────────────────────────────────────
# NODE <-> RECORD
# ─────────────────────────────────────────────
# Push this record onto a freshly instantiated Soldier. Call BEFORE add_child —
# AI._ready() runs initialize(), which reads max_health and calls initialize()
# on every equipment slot.
func write_to(soldier: Soldier) -> void:
	soldier.soldier_name = display_name
	soldier.max_health = max_health
	soldier.health = current_health()
	soldier.signal_integrity = signal_integrity
	soldier.faction = Enums.Factions.ALLIED

	# CRITICAL: duplicate the slot resources. AIEquipmentSlot holds
	# _quantity_remaining as runtime state, so two soldiers sharing the same
	# .tres would share a grenade count — one throws, both lose it.
	var slots: Array[AIEquipmentSlot] = []
	for slot in equipment:
		if slot != null:
			slots.append(slot.duplicate() as AIEquipmentSlot)
	soldier.equipment_slots = slots


# Read a surviving Soldier back into this record at extraction.
func read_from(soldier: Soldier) -> void:
	if soldier == null or not is_instance_valid(soldier):
		status = Status.DESTROYED
		damage = max_health
		return
	damage = clampi(max_health - soldier.health, 0, max_health)
	signal_integrity = soldier.signal_integrity

	# Career total. Zeroed on the body after reading so a second read_from in
	# the same mission cannot count the same kills twice — write_back runs once
	# per extraction today, but this is not a thing to leave depending on that.
	if "confirmed_kills" in soldier:
		confirmed_kills_this_mission = soldier.confirmed_kills
		confirmed_kills += soldier.confirmed_kills
		soldier.confirmed_kills = 0
	if "kills_by_kind" in soldier:
		take_kills_by_kind(soldier.kills_by_kind)
	if "revives" in soldier:
		revives_this_mission = soldier.revives
		revives += soldier.revives
		soldier.revives = 0
	if not soldier.alive:
		status = Status.DESTROYED
		damage = max_health
	elif health_fraction() < 0.5:
		status = Status.WOUNDED
	else:
		status = Status.ACTIVE

	# Consumables come home at whatever's left in them.
	_sync_equipment_max()
	for i in mini(equipment.size(), soldier.equipment_slots.size()):
		if equipment[i] != null and soldier.equipment_slots[i] != null:
			equipment[i].quantity = soldier.equipment_slots[i].remaining()


# JSON wants string keys; kinds are StringNames.
static func _kills_to_dict(kinds: Dictionary) -> Dictionary:
	var out := {}
	for kind in kinds:
		out[String(kind)] = int(kinds[kind])
	return out


## A body's kills-by-kind at extraction: kept as this mission's, added to the
## career, and cleared on the body so a second read cannot count them twice.
func take_kills_by_kind(from_body: Dictionary) -> void:
	kills_by_kind_this_mission = from_body.duplicate()
	for kind in from_body:
		kills_by_kind[kind] = int(kills_by_kind.get(kind, 0)) + int(from_body[kind])
	from_body.clear()


# ─────────────────────────────────────────────
# SERIALISATION
# ─────────────────────────────────────────────
# Plain dictionaries, not .tres. A save file lives in a user-writable directory
# and a .tres encodes script paths, which makes it a code-loading surface. JSON
# is inert, easier to migrate, and you can open it and read it when something
# has gone wrong. Resources are referenced by path and re-loaded on the way in.
func to_dict() -> Dictionary:
	var kit: Array = []
	for slot in equipment:
		if slot == null:
			continue
		kit.append({
			"path": slot.resource_path,
			"quantity": slot.quantity,
		})
	return {
		"id": String(id),
		"display_name": display_name,
		"chassis": chassis_scene.resource_path if chassis_scene != null else "",
		"weapon": weapon_scene.resource_path if weapon_scene != null else "",
		"max_health": max_health,
		"damage": damage,
		"signal_integrity": signal_integrity,
		"status": int(status),
		"benched": benched,
		"missions_survived": missions_survived,
		"confirmed_kills": confirmed_kills,
		"revives": revives,
		"kills_by_kind": _kills_to_dict(kills_by_kind),
		"equipment": kit,
		"equipment_max": equipment_max,
		"chassis_id": String(chassis_id),
		"weapon_ids": weapon_ids.map(func(v): return String(v)),
		"equipment_ids": equipment_ids.map(func(v): return String(v)),
		"module_ids": module_ids.map(func(v): return String(v)),
		"rank": rank,
		"xp": xp,
	}


static func from_dict(data: Dictionary) -> SoldierRecord:
	var r := SoldierRecord.new()
	r.id = StringName(str(data.get("id", "")))
	r.display_name = str(data.get("display_name", "Unnamed"))
	r.max_health = int(data.get("max_health", 30))
	r.damage = int(data.get("damage", 0))
	r.signal_integrity = float(data.get("signal_integrity", 1.0))
	r.status = int(data.get("status", 0)) as Status
	# Saves from before the bench existed have no key: everyone deploys.
	r.benched = bool(data.get("benched", false))
	r.missions_survived = int(data.get("missions_survived", 0))
	r.confirmed_kills = int(data.get("confirmed_kills", 0))
	r.revives = int(data.get("revives", 0))
	var kinds: Dictionary = data.get("kills_by_kind", {})
	for kind in kinds:
		# Through the rename table, so a career tally does not split into two
		# columns when a frame is renamed. See CampaignState.RENAMED.
		var id: StringName = CampaignState._renamed(StringName(str(kind)))
		r.kills_by_kind[id] = int(r.kills_by_kind.get(id, 0)) + int(kinds[kind])

	var chassis := str(data.get("chassis", ""))
	if chassis != "" and ResourceLoader.exists(chassis):
		r.chassis_scene = load(chassis)
	var weap := str(data.get("weapon", ""))
	if weap != "" and ResourceLoader.exists(weap):
		r.weapon_scene = load(weap)

	var kit: Array[AIEquipmentSlot] = []
	for entry in data.get("equipment", []):
		var path := str(entry.get("path", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var slot := (load(path) as AIEquipmentSlot).duplicate() as AIEquipmentSlot
		slot.quantity = int(entry.get("quantity", slot.quantity))
		kit.append(slot)
	r.equipment = kit
	var maxes: Array[int] = []
	for v in data.get("equipment_max", []):
		maxes.append(int(v))
	r.equipment_max = maxes
	r.chassis_id = StringName(str(data.get("chassis_id", "")))
	r.rank = int(data.get("rank", 0))
	r.xp = int(data.get("xp", 0))
	for field in ["weapon_ids", "equipment_ids", "module_ids"]:
		var ids: Array[StringName] = []
		for v in data.get(field, []):
			ids.append(StringName(str(v)))
		r.set(field, ids)
	r._sync_equipment_max()
	return r
