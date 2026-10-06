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
## What to call this on screen. NOT just for debug any more: the squad HUD prints
## it when a robot spends something, and the designator groups the squad's kit by
## it, so a slot built with this empty showed up as the word "EQUIPMENT".
@export var label: String = ""
## Which catalogue item this came out of, when it came out of one. The slot used
## to know only its scene, and a scene cannot be turned back into an icon or a
## price — so anything wanting to DRAW a squadmate's kit had to walk the whole
## catalogue matching ai_scene paths. Empty for a slot authored by hand in a
## .tres, which is how the enemy garrisons get theirs.
@export var item_id: StringName = &""

var _quantity_remaining: int = 0

func initialize() -> void:
	_quantity_remaining = quantity

func has_uses() -> bool:
	return _quantity_remaining > 0

func consume() -> void:
	_quantity_remaining = max(0, _quantity_remaining - 1)

func remaining() -> int:
	return _quantity_remaining
