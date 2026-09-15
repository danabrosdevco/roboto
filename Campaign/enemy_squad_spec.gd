extends Resource
class_name EnemySquadSpec

# ─────────────────────────────────────────────
# ENEMY SQUAD SPEC — one hostile squad, described as data.
#
# This is the thing that takes enemies out of the level scene and into the
# mission. It's the same pattern as SoldierRecord: data instantiated into
# level-provided positions at load time, rather than nodes baked into a map.
#
# WHY IT MATTERS: with enemies baked into the level, every operation on that map
# is exactly as hard forever, and the resource economy has nothing to push
# against. Composition per mission is your entire difficulty curve.
#
# EVERYTHING REFERENCES THE LEVEL BY TAG. post_tag matches a
# SquadObjectivePoint.tag, route_tag matches a PatrolPath.tag. Never node paths
# — those weld a mission to one map and break on rename.
# ─────────────────────────────────────────────

enum Posture {
	PATROL,    # walk route_tag as a unit
	GARRISON,  # dig in at post_tag (defensive_mode, holds cover)
	ADVANCE,   # push to post_tag
	RESERVE,   # sit inert at spawn until a director wakes them
}

@export var callsign: String = "HOSTILE"
@export var count: int = 3
# Null falls back to the spawner's default_chassis.
@export var chassis: PackedScene

@export var posture: Posture = Posture.PATROL
## Which PatrolPath to walk. Used when posture is PATROL.
@export var route_tag: StringName = &""
## Which SquadObjectivePoint to hold or push to. Used for GARRISON and ADVANCE.
@export var post_tag: StringName = &""
## Where they physically appear. Leave empty and they spawn on their post, or on
## the first point of their route — which is usually what you want and one less
## node to place.
@export var spawn_tag: StringName = &""

# Keeps them simulating even when the player is far away. Expensive for large
# forces; worth it for a patrol you want to be somewhere specific when found.
@export var always_active: bool = false
@export var faction: Enums.Factions = Enums.Factions.ENEMY

# Held back until a director calls for them. RESERVE squads are spawned but
# inert; this is the hook reinforcements will hang off.
@export var reinforcement_tag: StringName = &""
