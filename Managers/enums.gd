extends Node
class_name Enums
 
# CHARACTER INF #
# PLAYER  — the human player
# ENEMY   — hostile robots (Argus forces etc.)
# ALLIED  — friendly robots fighting alongside the player
# NEUTRAL — third parties, non-combatants
enum Factions { PLAYER, ENEMY, ALLIED, NEUTRAL }
 
enum ScanModes { RECTANGLE, TOP_DOWN }
enum WorldStates { RUNNING, LOADING, PAUSED }
enum FireModes { SEMI, FULL, MANUAL }
enum AIWeaponTypes { MELEE, HITSCAN, PROJECTILE }
 
# BOSS AI #
enum GuardianCombatOptions { SPINNING_ATTACK, RECOVERY }
 
# WORLD OBJECT INF #
enum WorldObjectTypes { CHAR_SPAWN, AI_SPAWN, LEVEL_EXIT, PICKUP, INTERACTIBLE, AI, STATIC_TARGET }
enum PickUpTypes { HEALTH, SHARDS }
enum InteractTypes { HEALTH, SHARDS, BONFIRE, BITS }
 
# Which factions are hostile to which
# Returns true if faction_a should attack faction_b
static func are_hostile(faction_a: Factions, faction_b: Factions) -> bool:
	if faction_b == Factions.NEUTRAL:
		return false
	match faction_a:
		Factions.PLAYER:
			return faction_b == Factions.ENEMY
		Factions.ENEMY:
			return faction_b == Factions.PLAYER or faction_b == Factions.ALLIED
		Factions.ALLIED:
			return faction_b == Factions.ENEMY
		Factions.NEUTRAL:
			return false
	return false
 
