extends Resource
class_name AIEquipmentSlot

# ─────────────────────────────────────────────
# AI EQUIPMENT SLOT
# A resource that defines one type of equipment
# an Enemy carries, and how many they have.
# Attach as many as needed to enemy.equipment_slots.
# ─────────────────────────────────────────────

@export var equipment_scene: PackedScene   # the AIEquipment scene to instantiate
@export var quantity: int = 2              # how many uses this enemy starts with
@export var label: String = ""             # optional display name for debug

var _quantity_remaining: int = 0

func initialize() -> void:
	_quantity_remaining = quantity

func has_uses() -> bool:
	return _quantity_remaining > 0

func consume() -> void:
	_quantity_remaining = max(0, _quantity_remaining - 1)

func remaining() -> int:
	return _quantity_remaining
