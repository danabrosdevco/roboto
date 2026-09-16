extends Resource
class_name ItemDefinition

# ─────────────────────────────────────────────
# ITEM DEFINITION — one thing you can own, buy, and fit to a soldier.
#
# Weapons, equipment and upgrade modules are all this. They differ only in which
# kind of slot they occupy, which keeps the armoury, the shop and the drag-drop
# UI as one code path instead of three.
#
# Authored as .tres and shipped with the game. NOT save state — the save records
# ids and counts, never the definitions themselves.
# ─────────────────────────────────────────────

enum Kind {
	WEAPON,      # the soldier's gun. One per chassis weapon slot.
	EQUIPMENT,   # consumables and gadgets — maps to AIEquipmentSlot
	MODULE,      # passive upgrade. Refundable, returns to the pool on death.
}

@export var id: StringName = &""
@export var display_name: String = "Item"
# What fits in a 58px slot. "Ancient Rifle" and "Ancient Pistol" both truncate
# to "Ancient" at eight characters, so slots need their own short label rather
# than a substring of the long one. Leave blank and short_label() derives a
# sensible one from the last word.
@export var short_name: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.EQUIPMENT
@export var icon: Texture2D

# What it costs to buy. Charged through CampaignState's allocation ledger, so
# selling is a refund rather than a separate transaction.
@export var cost: int = 0

# ── THE TWO SCENES ────────────────────────────
# A player weapon and an AI weapon are genuinely different objects and cannot
# share a scene. HUDWeapon is a viewmodel hanging off the camera with ADS,
# camera recoil and hand-relative tracers; AIWeapon is a world-space object
# bolted to a robot with falloff curves, spread in milliradians and suppression
# values. They don't even have the same base class.
#
# So an item carries BOTH, and either may be null. That's not a workaround — it
# IS the thing you're modelling: "the M4" is a concept with two implementations,
# and an item that only has one of them simply can't be carried by the other
# side. The UI reads usable_by_* to refuse the fit before you drag it.
@export var player_scene: PackedScene   # HUDWeapon / PlayerEquipment
@export var ai_scene: PackedScene       # AIWeapon / AIEquipment

# Set these deliberately rather than inferring from which scene is non-null, so
# a half-authored item fails loudly instead of quietly becoming AI-only.
# ── PLAYER MOUNT ──────────────────────────────
# Per-instance overrides that used to live on the node in test_character.tscn —
# the M4 carried transform = (0.192761, -0.207464, 0) to sit at eye level, and
# instancing the packed scene fresh loses that. It belongs on the ITEM now: the
# alignment is a property of the weapon, not of one hand-placed node, so every
# copy of an M4 hangs the same way and a new weapon is tuned in one place.
@export var player_mount_offset: Vector3 = Vector3.ZERO
@export var player_mount_rotation_degrees: Vector3 = Vector3.ZERO

# Blank leaves whatever the scene says. Set it where two items share a scene but
# feed from different pools — the pistol uses m4-shaped scenes but 9mm ammo.
@export var ammo_type: StringName = &""
# 0 leaves the scene's value.
@export var weapon_damage: int = 0

@export var usable_by_player: bool = true
@export var usable_by_ai: bool = true
# EQUIPMENT only: how many uses one of these grants.
@export var quantity: int = 1

# ── MODULE EFFECTS ────────────────────────────
# Flat and multiplicative, applied on top of the chassis base when a soldier is
# spawned. Kept as plain numbers rather than a script hook so the UI can show
# "+15 HP" without running anything.
@export var health_bonus: int = 0
@export var accuracy_bonus: float = 0.0
@export var damage_bonus: int = 0
@export var speed_multiplier: float = 1.0
@export var signal_bonus: float = 0.0
# Additive metres of sight. The module that lets a rifle squad actually use its
# range — see Enemy.sensor_range for why that gap exists on purpose.
@export var sensor_bonus: float = 0.0

# Gating. A module can require a rank before it will fit — that's what makes
# rank matter more than raw level.
@export var required_rank: int = 0
# Empty means any chassis. Otherwise a list of ChassisDefinition ids.
@export var chassis_whitelist: Array[StringName] = []


func fits_chassis(chassis_id: StringName) -> bool:
	return chassis_whitelist.is_empty() or chassis_whitelist.has(chassis_id)


# Can a squadmate carry this? Weapons and equipment need something to instance;
# a MODULE is a passive stat delta with no node at all, so demanding a scene for
# one would make every module unfittable. Kinds differ in what "usable" means.
func fits_ai() -> bool:
	if not usable_by_ai:
		return false
	if kind == Kind.MODULE:
		return true
	return ai_scene != null


func fits_player() -> bool:
	if not usable_by_player:
		return false
	if kind == Kind.MODULE:
		return true
	return player_scene != null


# Shown in the armoury so a player-only weapon in stores reads as deliberate
# rather than as a bug when it won't drop onto a squadmate.
# Marks items only one side can carry. "[SQUAD]" on the pump shotgun means it
# has no player_scene — there is no HUDWeapon version of it — so it will refuse
# to drop onto your own loadout. Without the tag that refusal looks like a bug.
# Items both sides can use, and all modules, show nothing.
func carrier_tag() -> String:
	if kind == Kind.MODULE:
		return ""
	if fits_ai() and fits_player():
		return ""
	if fits_player():
		return "[YOU]"
	if fits_ai():
		return "[SQUAD]"
	return "[UNUSABLE]"


# Slot label. Falls back to the most distinguishing part of the name — the LAST
# word — because that's what differs between "Ancient Rifle" and "Ancient
# Pistol". Truncating from the front gets it exactly backwards.
func short_label() -> String:
	if short_name != "":
		return short_name
	var words := display_name.split(" ", false)
	if words.is_empty():
		return "?"
	var last: String = words[words.size() - 1]
	return last.substr(0, 9)


# One line for the UI, built from whatever is non-default.
func effect_summary() -> String:
	var parts: Array = []
	if health_bonus != 0:
		parts.append("%+d HP" % health_bonus)
	if damage_bonus != 0:
		parts.append("%+d DMG" % damage_bonus)
	if accuracy_bonus != 0.0:
		parts.append("%+.0f%% ACC" % (accuracy_bonus * 100.0))
	if signal_bonus != 0.0:
		parts.append("%+.0f%% SIG" % (signal_bonus * 100.0))
	if sensor_bonus != 0.0:
		parts.append("%+.0fm SENSOR" % sensor_bonus)
	if not is_equal_approx(speed_multiplier, 1.0):
		parts.append("%+.0f%% SPD" % ((speed_multiplier - 1.0) * 100.0))
	if kind == Kind.EQUIPMENT and quantity > 0:
		parts.append("x%d" % quantity)
	return ", ".join(parts)
