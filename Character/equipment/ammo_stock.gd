extends Resource
class_name AmmoStock

# ─────────────────────────────────────────────
# One entry in the player's starting ammunition. Add as many as the loadout
# needs to EquipmentLoadout.starting_ammo.
#
# Ammo is keyed by TYPE, not by weapon. An SMG you add later that also feeds
# 5.56 draws from the same pool as the M4 with no extra wiring, pickups grant a
# type rather than "ammo for whatever I'm holding", and a dropped enemy weapon
# doesn't need a special case for what ammunition comes with it.
# ─────────────────────────────────────────────

# Match this against PlayerWeapon.ammo_type. Suggested: &"5.56", &"9mm",
# &"grenade", &"repair".
@export var ammo_type: StringName = &""
# How much the player spawns with, in ROUNDS (not magazines).
@export var amount: int = 0
# Hard carry limit. Pickups past this are wasted. 0 means no limit.
@export var capacity: int = 0
