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
@export var max_health: int = 100
@export var damage: int = 0
@export var signal_integrity: float = 1.0
@export var status: Status = Status.ACTIVE

# ── KIT ───────────────────────────────────────
# Same resource type the AI already uses, so the armoury UI is dragging these
# between a pool array and this array. No stat trees, no per-soldier levelling.
@export var equipment: Array[AIEquipmentSlot] = []
# Optional override for the weapon node in the chassis scene. Leave null to use
# whatever the chassis ships with.
@export var weapon_scene: PackedScene

# ── HISTORY ───────────────────────────────────
@export var missions_survived: int = 0


func current_health() -> int:
	return maxi(0, max_health - damage)


func is_deployable() -> bool:
	return status != Status.DESTROYED and current_health() > 0


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
	if not soldier.alive:
		status = Status.DESTROYED
		damage = max_health
	elif health_fraction() < 0.5:
		status = Status.WOUNDED
	else:
		status = Status.ACTIVE

	# Consumables come home at whatever's left in them.
	for i in mini(equipment.size(), soldier.equipment_slots.size()):
		if equipment[i] != null and soldier.equipment_slots[i] != null:
			equipment[i].quantity = soldier.equipment_slots[i].remaining()


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
		"missions_survived": missions_survived,
		"equipment": kit,
	}


static func from_dict(data: Dictionary) -> SoldierRecord:
	var r := SoldierRecord.new()
	r.id = StringName(str(data.get("id", "")))
	r.display_name = str(data.get("display_name", "Unnamed"))
	r.max_health = int(data.get("max_health", 30))
	r.damage = int(data.get("damage", 0))
	r.signal_integrity = float(data.get("signal_integrity", 1.0))
	r.status = int(data.get("status", 0)) as Status
	r.missions_survived = int(data.get("missions_survived", 0))

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
	return r
