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

# What the player is called on the roster, before they rename themselves.
#
# Straight out of lore.txt: the player is a StratCom AKR — autonomous killer
# robot — that Algie repurposed and fitted with a Tabula Rasa chip. So the name
# is the hardware designator, and the 00 is the blank slate: first of a line
# with nothing written on it yet.
#
# Deliberately a machine code while the squad carry human names. You are the
# thing that names THEM; the contrast in the roster column is the point. Defined
# once here because three different files were hardcoding the old "YOU".
const PLAYER_DEFAULT_NAME := "PLAYER"

# ── IDENTITY ──────────────────────────────────
# The single source of truth for what the player's squad is called. The spawner
# reads it onto the Squad node, so the roster header, the command HUD and the
# order toasts all agree.
@export var squad_name: String = "NAMELESS"

# The player's own loadout, held as a record so the management screen can treat
# them as one more row. Their chassis is whatever you make the player frame —
# the slot counts come from it exactly as they do for a squadmate.
@export var player_record: SoldierRecord = SoldierRecord.new()

# Spare kit. Items fitted to a soldier are NOT in here — they're in that
# soldier's slots. Total owned = armoury spare + everything fitted.
@export var armoury: Armoury = Armoury.new()

# Resolved at runtime by CampaignManager; not saved.
var catalogue: ItemCatalogue

signal ledger_changed
signal roster_changed
# Emitted after a paid repair. CampaignManager listens and tells the spawner to
# push the new health onto the live body, or bring a rebuilt soldier into the
# world if they were too wrecked to deploy when the level loaded.
signal soldier_repaired(record: SoldierRecord)


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
	var had := allocations.has(key)
	if not _allocate_quiet(key, cost):
		return false
	if not had:
		ledger_changed.emit()
	return true


# Records the allocation WITHOUT announcing it.
#
# Anything that changes the ledger AND the armoury has to use this and emit once
# at the end. ledger_changed is wired straight to the squad manager's rebuild,
# and that rebuild runs synchronously — so emitting from inside allocate() meant
# the UI redrew after the resources had been deducted but before the item had
# been added to stores. It read the new balance and the old count, and since
# nothing emits again afterwards the row stayed wrong until the next click
# happened to trigger another rebuild.
func _allocate_quiet(key: String, cost: int) -> bool:
	if allocations.has(key):
		return true
	if not can_afford(cost):
		return false
	allocations[key] = cost
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


# ── REPAIR ────────────────────────────────────
# Resources per point of health restored. A destroyed frame costs the same per
# point as a scratch, so a 0/60 wreck is simply expensive rather than a
# different transaction.
@export var repair_cost_per_hp: int = 1
# Multiplier on top for bringing a DESTROYED record back. Rebuilding a wreck
# should hurt more than patching a dent, or losing people costs nothing.
@export var rebuild_cost_multiplier: float = 2.0


func repair_cost(record: SoldierRecord) -> int:
	if record == null or record.damage <= 0:
		return 0
	var cost := float(record.damage) * float(repair_cost_per_hp)
	if record.status == SoldierRecord.Status.DESTROYED:
		cost *= rebuild_cost_multiplier
	return int(ceil(cost))


func can_repair(record: SoldierRecord) -> bool:
	var cost := repair_cost(record)
	return cost > 0 and can_afford(cost)


# Charged as an allocation that is never refunded. Consumed spend and refundable
# spend share one ledger that way — available() stays earned minus everything
# committed, and there's no second balance to drift out of sync.
func repair_soldier(record: SoldierRecord) -> bool:
	var cost := repair_cost(record)
	if cost <= 0 or not can_afford(cost):
		return false
	var key := "repair:%s:%d" % [record.id, _next_purchase()]
	# Quiet, then mend, then announce — same rule as buy_item. allocate() emits
	# ledger_changed, which the squad manager rebuilds on synchronously, so it
	# drew the resources already spent while the soldier was still showing full
	# damage. roster_changed a few lines later corrected it, but the panel had
	# already been built once from a half-applied repair.
	if not _allocate_quiet(key, cost):
		return false
	record.damage = 0
	record.signal_integrity = 1.0
	record.status = SoldierRecord.Status.ACTIVE
	record.recompute_stats(catalogue)
	ledger_changed.emit()
	soldier_repaired.emit(record)
	roster_changed.emit()
	return true


# Free full repair. Kept for debug and for a future "between campaigns" reset.
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
# Renames are expected to be instant. The record is the source of truth, but a
# body built from it earlier is carrying a stale copy of the name — the squad
# HUD roster reads Soldier.soldier_name, not the record — so push it across.
func rename_soldier(record: SoldierRecord, new_name: String, tree: SceneTree) -> void:
	if record == null:
		return
	var cleaned := new_name.strip_edges()
	record.display_name = cleaned if cleaned != "" else "UNNAMED"
	if tree == null:
		roster_changed.emit()
		return
	for squad in tree.get_nodes_in_group("squads"):
		if not (squad is Squad):
			continue
		for member in (squad as Squad).squad_members:
			if member == null or not is_instance_valid(member):
				continue
			if member.get_meta("record_id", &"") == record.id:
				member.soldier_name = record.display_name
	roster_changed.emit()


func is_player_record(record: SoldierRecord) -> bool:
	return record != null and record == player_record


func can_fit(record: SoldierRecord, item: ItemDefinition) -> bool:
	if record == null or item == null:
		return false
	if armoury.spare(item.id) <= 0:
		return false
	if record.rank < item.required_rank:
		return false
	# Which implementation is required depends on WHO is carrying it. The pump
	# shotgun has no HUDWeapon, so it can arm a squadmate and not you.
	if is_player_record(record):
		if not item.fits_player():
			return false
	elif not item.fits_ai():
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
	if player_record != null:
		player_record.recompute_stats(catalogue)
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
	# Quiet, then stock, then announce — see _allocate_quiet.
	if not _allocate_quiet(key, item.cost):
		return false
	armoury.add(item.id)
	ledger_changed.emit()
	return true


func buy_chassis(chassis: ChassisDefinition) -> bool:
	if chassis == null or not can_afford(chassis.cost):
		return false
	var key := "chassis:%s:%d" % [chassis.id, _next_purchase()]
	# Same ordering as buy_item: the chassis is in stores before anyone is told.
	if not _allocate_quiet(key, chassis.cost):
		return false
	armoury.add_chassis(chassis.id)
	ledger_changed.emit()
	return true


# Sell a spare. Clears the most recent purchase of that id — so a price change
# never leaves the ledger owing — but hands back only HALF of what was paid.
#
# The un-refunded half does not evaporate: it stays in the ledger under a
# "sold:" key that nothing ever refunds, exactly like a repair. Erasing the
# whole allocation would credit the full price back, and holding the loss
# anywhere else would be the second balance this system exists to avoid.
# available() is still earned - sum(allocations) and still cannot drift.
func sell_item(item: ItemDefinition) -> bool:
	if item == null or armoury.spare(item.id) <= 0:
		return false
	var newest := _newest_purchase_key("item:%s:" % item.id)

	# STARTING STOCK HAS NO ALLOCATION. Campaign.starting_stock puts items in the
	# armoury directly — they were issued, not bought — so there is no entry to
	# shrink. Refusing here meant none of the kit you begin the game with could
	# ever be sold, which is most of what is in stores on a fresh save.
	#
	# Selling those credits earned instead. That is sound: earned only ever goes
	# up, and it cannot be farmed, because anything you BUY gets an allocation
	# and therefore takes the branch below. There is no loop that ends with more
	# resources than it started with.
	if newest == "":
		if not armoury.take(item.id):
			return false
		award(sale_value(item.cost))
		return true

	if not armoury.take(item.id):
		return false
	var paid := int(allocations[newest])
	var kept := paid - sale_value(paid)
	# Mutate the ledger completely, THEN emit once. refund() emits on its own
	# and the squad manager rebuilds synchronously on ledger_changed, so it
	# would have read the ledger with the full price credited back and the
	# retained half not yet recorded — a one-frame flash of the wrong balance.
	allocations.erase(newest)
	if kept > 0:
		allocations["sold:%s:%d" % [item.id, _next_purchase()]] = kept
	ledger_changed.emit()
	return true


# What selling something bought for `paid` hands back. Integer division rounds
# the player down, so selling and re-buying is always a loss and never a way to
# launder resources.
func sale_value(paid: int) -> int:
	@warning_ignore("integer_division")
	return paid / 2


# What the player would get back for selling one spare right now. The UI needs
# the number before the sale to label the button honestly. Falls back to the
# catalogue price for issued stock, which has no purchase to look up — the same
# branch sell_item takes.
func sale_value_of(item: ItemDefinition) -> int:
	if item == null:
		return 0
	var newest := _newest_purchase_key("item:%s:" % item.id)
	if newest == "":
		return sale_value(item.cost)
	return sale_value(int(allocations[newest]))


# Highest-numbered purchase under a prefix. Compares the trailing counter
# NUMERICALLY: these keys were previously ordered with `>` on the whole string,
# which sorts "item:frag:9" above "item:frag:10" and picked the wrong
# allocation to refund as soon as the counter passed single digits.
func _newest_purchase_key(prefix: String) -> String:
	var best := ""
	var best_n := -1
	for key in allocations.keys():
		var s := String(key)
		if not s.begins_with(prefix):
			continue
		var n := int(s.substr(prefix.length()))
		if n > best_n:
			best_n = n
			best = s
	return best


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
		"squad_name": squad_name,
		"purchase_counter": _purchase_counter,
		"armoury": armoury.to_dict(),
		"player_record": player_record.to_dict(),
	}


static func from_dict(data: Dictionary) -> CampaignState:
	var s := CampaignState.new()
	s.earned = int(data.get("earned", 0))
	s.allocations = data.get("allocations", {})
	s._next_id = int(data.get("next_id", 1))
	s.squad_name = str(data.get("squad_name", "NAMELESS"))
	s._purchase_counter = int(data.get("purchase_counter", 0))
	s.armoury = Armoury.from_dict(data.get("armoury", {}))
	if data.has("player_record"):
		s.player_record = SoldierRecord.from_dict(data["player_record"])
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
