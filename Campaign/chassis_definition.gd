extends Resource
class_name ChassisDefinition

# ─────────────────────────────────────────────
# CHASSIS DEFINITION — the frame a soldier is built on.
#
# Decides base stats and, more importantly, HOW MANY SLOTS they have. That's the
# real progression currency: a better chassis isn't just tougher, it carries
# more. Buying one is the big purchase; fitting it out is the ongoing one.
# ─────────────────────────────────────────────

@export var id: StringName = &"light"
@export var display_name: String = "Light Frame"
@export_multiline var description: String = ""
@export var icon: Texture2D

# The Soldier scene instantiated for this frame.
@export var scene: PackedScene
@export var cost: int = 0
## Offered for RECRUITMENT in the squad manager: a new robot, born in this
## frame, for `cost` resources.
@export var purchasable: bool = false
## Squad supply this frame occupies while ACTIVE. Every frame is 1 for now;
## bigger machines (a gunship, an APC) will cost more.
@export var supply: int = 1
## The weapon a robot built in this frame comes with, issued with it rather
## than taken from stores, so it can fight the moment it is built. Empty for
## frames with nothing to hold (claws are part of the body).
@export var starting_weapon_id: StringName = &""

# ── BASE STATS ────────────────────────────────
@export var base_health: int = 30
@export var base_speed: float = 1.0
@export var base_accuracy: float = 1.0
# How far this frame can SEE, in metres. Independent of whatever it's holding —
# a heavy frame with better optics spots sooner regardless of its weapon.
@export var base_sensor_range: float = 45.0

# ── SLOTS ─────────────────────────────────────
# Weapon slots are almost always 1; kept configurable for a future heavy frame.
@export var weapon_slots: int = 1
## The weapon slot is a TURRET: it takes weapons made for this frame — ones that
## name it in their chassis_whitelist — and not a rifle off the rack.
@export var turret: bool = false
@export var equipment_slots: int = 2
@export var module_slots: int = 2

# Ranks this chassis can be crewed by, if you want to gate frames behind
# experience as well as cost. 0 means no requirement.
@export var required_rank: int = 0


## Whether `item` goes on this frame at all: the item's whitelist allows the
## frame, and a turret takes only what was made for it.
func takes(item: ItemDefinition) -> bool:
	if item == null:
		return false
	if not item.fits_chassis(id):
		return false
	return not (turret and item.kind == ItemDefinition.Kind.WEAPON and not item.chassis_whitelist.has(id))
