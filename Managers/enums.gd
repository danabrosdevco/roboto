extends Node
class_name Enums
 
# CHARACTER INF #
# PLAYER  — the human player
# ENEMY   — hostile robots (Argus forces etc.)
# ALLIED  — friendly robots fighting alongside the player
# NEUTRAL — third parties, non-combatants
# SWARM   — the Swarm: numbers. Broodcarrier and its brood
# HOME    — Home Command: position. The Bastion. The player's own parent
#           organisation, which is why its frames are built out of the player's
#           kit. Spelled HOME, not HOME_COMMAND or STRATCOM, to match
#           hud_palette.gd's FAC_HOME, which shipped first
# ARGUS   — Argus itself: intelligence. The See-Engine
#
# APPEND ONLY. These are stored as raw ints in .tscn and .tres — 823 of them at
# the time of writing — so inserting or reordering silently repoints every
# hostile in the game. An enum identifier is also permanent the day a kill is
# saved against it, for the same reason the quadcopter bomber is still called
# `gunship` in kill_kinds.gd:21.
enum Factions { PLAYER, ENEMY, ALLIED, NEUTRAL, SWARM, HOME, ARGUS }
 
enum ScanModes { RECTANGLE, TOP_DOWN }
enum WorldStates { RUNNING, LOADING, PAUSED }
enum FireModes { SEMI, FULL, MANUAL }
enum AIWeaponTypes { MELEE, HITSCAN, PROJECTILE }
 
# BOSS AI #
enum GuardianCombatOptions { SPINNING_ATTACK, RECOVERY }
 
# WORLD OBJECT INF #
enum WorldObjectTypes { CHAR_SPAWN, AI_SPAWN, LEVEL_EXIT, PICKUP, INTERACTIBLE, AI, STATIC_TARGET }
enum PickUpTypes { HEALTH, SHARDS }
enum InteractTypes { HEALTH, SHARDS, BONFIRE, BITS, OBJECTIVE, MISSION }
 
## Who attacks whom, as data.
##
## A TABLE, NOT A MATCH. The match this replaced had four arms and fell out to
## `return false`, so appending a fifth Factions value made every robot
## carrying it simultaneously invisible AND near-invulnerable, in both
## directions, across thirty-five call sites, not one of which errors.
## Outbound-false means nothing targets it; inbound-false means ai_weapon.gd's
## _is_friendly() (314-320) calls every body in the world friendly, so
## friendly_in_line() blocks the frame's own shot, _one_round() applies the
## friendly-fire multiplier to everything it hits, and check_melee_damage()
## skips the whole sweep. GDScript does not warn on a non-exhaustive match on
## an enum. The whole audit is docs/frames/ENEMY_FACTIONS.md.
##
## Keyed by the ATTACKER; the value is everything it attacks. A faction with no
## row still gets a wrong answer — but it is now a wrong answer that
## push_errors and that tools/test_factions.gd fails on, instead of one that
## ships silently.
##
## NEUTRAL: [] IS A ROW, NOT AN OMISSION. It has to be present or the
## push_error fires on a faction that is working correctly. It also reproduces
## the old function's first line (`if faction_b == NEUTRAL: return false`) by
## NEUTRAL never appearing in any row.
##
## THE THREE ENEMY FACTIONS ARE NOT HOSTILE TO EACH OTHER, and that is a
## performance decision, not a fiction one. AIManager.activation_sources() is
## built from hostiles_for(), and nearest_hostile_distance_sq() is the only
## thing that wakes a frozen robot. Make two hostile forces each other's
## activation sources and they keep each other awake across the whole map, and
## the distance cull stops culling.
const HOSTILITY := {
	Factions.PLAYER:  [Factions.ENEMY, Factions.SWARM, Factions.HOME, Factions.ARGUS],
	Factions.ENEMY:   [Factions.PLAYER, Factions.ALLIED],
	Factions.ALLIED:  [Factions.ENEMY, Factions.SWARM, Factions.HOME, Factions.ARGUS],
	Factions.NEUTRAL: [],
	Factions.SWARM:   [Factions.PLAYER, Factions.ALLIED],
	Factions.HOME:    [Factions.PLAYER, Factions.ALLIED],
	Factions.ARGUS:   [Factions.PLAYER, Factions.ALLIED],
}

# Which factions are hostile to which
# Returns true if faction_a should attack faction_b
static func are_hostile(faction_a: Factions, faction_b: Factions) -> bool:
	var row = HOSTILITY.get(faction_a)
	if row == null:
		# LOUD, because the silent version of this cost a whole frame batch.
		push_error("Enums.are_hostile: Factions value %d has no HOSTILITY row. Everything is about to read as friendly to it." % int(faction_a))
		return false
	return (row as Array).has(faction_b)
 
