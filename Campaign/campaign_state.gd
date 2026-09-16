extends Resource
class_name CampaignState

# ─────────────────────────────────────────────
# CAMPAIGN STATE — everything that survives a mission.
#
# THE LEDGER
# `earned` only ever goes up. Spending is NOT subtracted from it — allocations
# are stored separately and `available()` is derived:
#
#     available = earned - sum(allocations)
#
# There is no spend path and therefore no refund path, which is what makes
# "perfectly transferable" trivially correct: refunding is deleting an entry.
# It cannot desync because there is nothing to keep in sync, and changing an
# item's cost in a patch just recomputes on every existing save.
#
# Allocations are keyed by an arbitrary string so the same ledger serves squad
# kit, player upgrades and unit purchases without three parallel systems.
# ─────────────────────────────────────────────

const SAVE_PATH := "user://campaign.json"
# Bump when the shape changes so migrate() has something to switch on.
const SAVE_VERSION := 1

@export var roster: Array[SoldierRecord] = []
@export var earned: int = 0
# key -> cost. Key is caller-defined, e.g. "upgrade:armour_plating" or
# "unit:soldier_04" or "kit:bravo2:slot0".
@export var allocations: Dictionary = {}
@export var completed_missions: Array[StringName] = []
@export var unlocked: Array[StringName] = []
@export var selected_mission_id: StringName = &""

# Monotonic counter behind mint_id(). Persisted, because regenerating ids on
# load would break every allocation key that references a soldier.
@export var _next_id: int = 1

# Spare kit. Items fitted to a soldier are NOT in here — they're in that
# soldier's slots. Total owned = armoury spare + everything fitted.
@export var armoury: Armoury = Armoury.new()

# Resolved at runtime by CampaignManager; not saved.
var catalogue: ItemCatalogue

signal ledger_changed
signal roster_changed


# ─────────────────────────────────────────────
# LEDGER
# ─────────────────────────────────────────────
func spent() -> int:
	var total := 0
	for cost in allocations.values():
		total += int(cost)
	return total


func available() -> int:
	return earned - spent()


func can_afford(cost: int) -> bool:
	return available() >= cost


func allocate(key: String, cost: int) -> bool:
	if allocations.has(key):
		return true
	if not can_afford(cost):
		return false
	allocations[key] = cost
	ledger_changed.emit()
	return true


# The entire refund mechanic.
func refund(key: String) -> void:
	if allocations.erase(key):
		ledger_changed.emit()


func is_allocated(key: String) -> bool:
	return allocations.has(key)


func award(amount: int) -> void:
	if amount == 0:
		return
	earned += amount
	ledger_changed.emit()


# ─────────────────────────────────────────────
# ROSTER
# ─────────────────────────────────────────────
func mint_id() -> StringName:
	var id := StringName("s%03d" % _next_id)
	_next_id += 1
	return id


func add_soldier(record: SoldierRecord) -> void:
	if record.id == &"":
		record.id = mint_id()
	roster.append(record)
	roster_changed.emit()


func get_soldier(id: StringName) -> SoldierRecord:
	for r in roster:
		if r.id == id:
			return r
	return null


func deployable() -> Array[SoldierRecord]:
	var out: Array[SoldierRecord] = []
	for r in roster:
		if r.is_deployable():
			out.append(r)
	return out


# Between-mission repair. Costs nothing yet — wire it to the ledger once you've
# decided whether repairs are free, paid, or time-gated.
func repair_all() -> void:
	for r in roster:
		if r.status != SoldierRecord.Status.DESTROYED:
			r.damage = 0
			r.signal_integrity = 1.0
			r.status = SoldierRecord.Status.ACTIVE
	roster_changed.emit()


# Called on arrival at base. Ammunition and equipment only — leaving damage
# alone is what keeps the repair tool meaningful between missions.
func restock_roster() -> void:
	for r in roster:
		r.restock()
	roster_changed.emit()


func remove_destroyed() -> Array[SoldierRecord]:
	var lost: Array[SoldierRecord] = []
	var kept: Array[SoldierRecord] = []
	for r in roster:
		if r.status == SoldierRecord.Status.DESTROYED:
			lost.append(r)
		else:
			kept.append(r)
	roster = kept
	if not lost.is_empty():
		roster_changed.emit()
	return lost


# ─────────────────────────────────────────────
# ARMOURY TRANSACTIONS
# Every one of these is a single call that moves an item between exactly two
# places, so the pool and the slots cannot disagree.
# ─────────────────────────────────────────────
func can_fit(record: SoldierRecord, item: ItemDefinition) -> bool:
	if record == null or item == null:
		return false
	if armoury.spare(item.id) <= 0:
		return false
	if record.rank < item.required_rank:
		return false
	# A squadmate can only carry something that has an AI implementation.
	if not item.fits_ai():
		return false
	return item.fits_chassis(record.chassis_id)


# Puts `item` in `slot_index` of the matching slot group. Anything already there
# goes back to the pool, so swapping is one action rather than remove-then-fit.
func fit_item(record: SoldierRecord, item: ItemDefinition, slot_index: int) -> bool:
	if not can_fit(record, item):
		return false
	var slots := _slots_for(record, item.kind)
	if slots == null or slot_index < 0 or slot_index >= slots.size():
		return false
	if not armoury.take(item.id):
		return false
	var displaced: StringName = slots[slot_index]
	if displaced != &"":
		armoury.add(displaced)
	slots[slot_index] = item.id
	record.recompute_stats(catalogue)
	roster_changed.emit()
	return true


func unfit_item(record: SoldierRecord, kind: int, slot_index: int) -> bool:
	var slots := _slots_for(record, kind)
	if slots == null or slot_index < 0 or slot_index >= slots.size():
		return false
	var id_value: StringName = slots[slot_index]
	if id_value == &"":
		return false
	slots[slot_index] = &""
	armoury.add(id_value)
	record.recompute_stats(catalogue)
	roster_changed.emit()
	return true


# A soldier who doesn't come home hands their kit back. This is the "modules are
# returned to you after they die" rule, and it's why modules are worth fitting
# to anyone rather than hoarding for your best unit.
func recover_kit(record: SoldierRecord) -> void:
	for id_value in record.all_fitted_ids():
		armoury.add(id_value)
	record.weapon_ids.fill(&"")
	record.equipment_ids.fill(&"")
	record.module_ids.fill(&"")
	record.recompute_stats(catalogue)
	roster_changed.emit()


# Fitting a soldier to a frame. Anything the smaller frame can't hold comes back
# to stores rather than vanishing.
func set_chassis(record: SoldierRecord, chassis: ChassisDefinition) -> bool:
	if record == null or chassis == null:
		return false
	if record.rank < chassis.required_rank:
		return false
	for displaced in record.set_chassis(chassis, catalogue):
		armoury.add(displaced)
	roster_changed.emit()
	return true


# Called once after the catalogue is available, since max_health is derived and
# a freshly loaded save has whatever was cached when it was written.
func recompute_roster() -> void:
	for r in roster:
		r.recompute_stats(catalogue)
	roster_changed.emit()


func _slots_for(record: SoldierRecord, kind: int) -> Array:
	match kind:
		ItemDefinition.Kind.WEAPON:
			return record.weapon_ids
		ItemDefinition.Kind.EQUIPMENT:
			return record.equipment_ids
		ItemDefinition.Kind.MODULE:
			return record.module_ids
	return []


# ─────────────────────────────────────────────
# SHOP
# Purchases are ALLOCATIONS, so selling is deleting an entry rather than a
# separate credit path. The key has to be unique per purchase, hence the counter.
# ─────────────────────────────────────────────
func buy_item(item: ItemDefinition) -> bool:
	if item == null or not can_afford(item.cost):
		return false
	var key := "item:%s:%d" % [item.id, _next_purchase()]
	if not allocate(key, item.cost):
		return false
	armoury.add(item.id)
	return true


func buy_chassis(chassis: ChassisDefinition) -> bool:
	if chassis == null or not can_afford(chassis.cost):
		return false
	var key := "chassis:%s:%d" % [chassis.id, _next_purchase()]
	if not allocate(key, chassis.cost):
		return false
	armoury.add_chassis(chassis.id)
	return true


# Sell a spare. Refunds the most recent purchase of that id at what was paid for
# it, so a price change never leaves the ledger owing.
func sell_item(item: ItemDefinition) -> bool:
	if item == null or armoury.spare(item.id) <= 0:
		return false
	var prefix := "item:%s:" % item.id
	var newest := ""
	for key in allocations.keys():
		if String(key).begins_with(prefix) and String(key) > newest:
			newest = String(key)
	if newest == "":
		return false
	if not armoury.take(item.id):
		return false
	refund(newest)
	return true


@export var _purchase_counter: int = 0

func _next_purchase() -> int:
	_purchase_counter += 1
	return _purchase_counter


# ─────────────────────────────────────────────
# SAVE / LOAD
# ─────────────────────────────────────────────
func to_dict() -> Dictionary:
	var records: Array = []
	for r in roster:
		records.append(r.to_dict())
	var missions: Array = []
	for m in completed_missions:
		missions.append(String(m))
	var unlocks: Array = []
	for u in unlocked:
		unlocks.append(String(u))
	return {
		"version": SAVE_VERSION,
		"earned": earned,
		"allocations": allocations,
		"roster": records,
		"completed_missions": missions,
		"unlocked": unlocks,
		"selected_mission_id": String(selected_mission_id),
		"next_id": _next_id,
		"purchase_counter": _purchase_counter,
		"armoury": armoury.to_dict(),
	}


static func from_dict(data: Dictionary) -> CampaignState:
	var s := CampaignState.new()
	s.earned = int(data.get("earned", 0))
	s.allocations = data.get("allocations", {})
	s._next_id = int(data.get("next_id", 1))
	s._purchase_counter = int(data.get("purchase_counter", 0))
	s.armoury = Armoury.from_dict(data.get("armoury", {}))
	s.selected_mission_id = StringName(str(data.get("selected_mission_id", "")))

	var records: Array[SoldierRecord] = []
	for entry in data.get("roster", []):
		records.append(SoldierRecord.from_dict(entry))
	s.roster = records

	var missions: Array[StringName] = []
	for m in data.get("completed_missions", []):
		missions.append(StringName(str(m)))
	s.completed_missions = missions

	var unlocks: Array[StringName] = []
	for u in data.get("unlocked", []):
		unlocks.append(StringName(str(u)))
	s.unlocked = unlocks
	return s


func save_to_disk(path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("CampaignState: could not open %s for writing (%s)" % [
			path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true


# Returns null when there's no save yet — the caller decides whether that means
# "new campaign" or "something is wrong".
static func load_from_disk(path: String = SAVE_PATH) -> CampaignState:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CampaignState: could not read %s" % path)
		return null
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CampaignState: save at %s is not valid JSON" % path)
		return null
	return from_dict(migrate(parsed))


# Every field read above already has a default, so a save written before a field
# existed loads cleanly. This is here for the changes defaults can't cover.
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	if version > SAVE_VERSION:
		push_warning("CampaignState: save is version %d, this build reads %d." % [
			version, SAVE_VERSION])
	return data
