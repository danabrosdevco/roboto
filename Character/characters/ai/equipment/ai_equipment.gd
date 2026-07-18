extends Node3D
class_name AIEquipment

# ─────────────────────────────────────────────
# AI EQUIPMENT — base class
# Extend this for each equipment type.
# Instantiated at use-time by Enemy, then freed.
#
# Subclasses override:
#   can_use(context: EquipmentContext) -> bool
#   execute(context: EquipmentContext) -> void
# ─────────────────────────────────────────────

# Context passed in when checking/using equipment.
# Contains everything the equipment needs to make a decision.
class EquipmentContext:
	var owner_ai: Enemy           # the enemy using this equipment
	var combat_target: CharacterBody3D
	var target_position: Vector3
	var nearby_hostiles: Array     # hostiles within a radius
	var time_since_target_moved: float  # how long target has been stationary
	var owner_is_reloading: bool

@export var equipment_name: String = "Equipment"
# Minimum seconds between uses (enforced by Enemy)
@export var cooldown: float = 8.0

# Subclasses implement these
func can_use(context: EquipmentContext) -> bool:
	return false

func execute(context: EquipmentContext) -> void:
	pass
