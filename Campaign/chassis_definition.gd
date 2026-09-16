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
@export var equipment_slots: int = 2
@export var module_slots: int = 2

# Ranks this chassis can be crewed by, if you want to gate frames behind
# experience as well as cost. 0 means no requirement.
@export var required_rank: int = 0
