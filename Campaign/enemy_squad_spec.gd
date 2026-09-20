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

## ONE ENTRY PER BODY. Drop in four riflemen, a hopper and a chaser and you get
## a six-robot MIXED squad — one Squad node, one set of orders, one callsign.
##
## This is the field to use. `count` and `chassis` below are the old one-type
## form, kept working because Godot silently drops properties it doesn't
## recognise when loading a resource: deleting them would empty every mission
## that still uses them, with no error and no warning, and you'd find out by
## walking into an empty valley.
##
## Why it matters: without this, a mixed garrison had to be three separate specs
## pointing at the same post_tag — which is three separate Squad nodes standing
## in the same place. They didn't coordinate, they tripled the squad count the
## HUD had to list, and their callsigns came out as RELAY-L, RELAY-M.
##
## ChassisDefinition rather than PackedScene so the frame's stats travel with
## it: one place to retune "rifle trooper" instead of editing every mission, and
## display_name feeds the comms log.
@export var roster: Array[ChassisDefinition] = []

# ── LEGACY ONE-TYPE FORM ──────────────────────
# Used only when `roster` is empty.
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
## Added to whatever the spawn/post/route tag resolved to, in world axes.
##
## Every tag in a level marks a spot on the GROUND, because every tag was
## authored for infantry. Air reinforcements need to arrive out at distance and
## well up — appearing at ground level on top of the position they are meant to
## attack looks wrong and plays worse. Use this rather than adding a parallel
## set of map nodes just for aircraft.
@export var spawn_offset: Vector3 = Vector3.ZERO

# Keeps them simulating even when the player is far away. Expensive for large
# forces; worth it for a patrol you want to be somewhere specific when found.
@export var always_active: bool = false
@export var faction: Enums.Factions = Enums.Factions.ENEMY

# Held back until a director calls for them. RESERVE squads are spawned but
# inert; this is the hook reinforcements will hang off.
@export var reinforcement_tag: StringName = &""
## Wakes itself once this many hostiles have been lost, instead of waiting for
## an objective of that name. 0 leaves it on the objective alone.
##
## Counted across the whole enemy force, downs and destructions together, so
## "after ten of ours are down" is one number rather than a table of triggers.
## The tag still has to be set: it is what the wave is called in the log.
@export var wake_after_kills: int = 0


## How many bodies this spec describes, whichever form it was authored in.
##
## Anything deciding "is this spec worth spawning" MUST ask this rather than
## reading `count`. A roster spec sets count = 0 to mark the legacy field dead,
## and the spawner's `count <= 0` skip silently threw away every roster squad in
## the game — 45 hostiles in Valley Siege, no warning, an empty map.
func body_count() -> int:
	return roster.size() if not roster.is_empty() else count
