extends Resource
class_name MissionDefinition

# ─────────────────────────────────────────────
# MISSION DEFINITION — one deployable operation.
#
# Authored as a .tres in the editor. This is a DEFINITION, not save state —
# definitions ship with the game and are referenced from the save by id.
# ─────────────────────────────────────────────

@export var id: StringName = &"mission_01"
@export var display_name: String = "Operation"
@export_multiline var briefing: String = ""

# The TrenchBroomLevel scene this mission deploys into.
@export var level_scene: PackedScene

# Marked on the map pane later. Kept here so the map is a view over mission
# data rather than a second source of truth.
@export var map_position: Vector2 = Vector2.ZERO

# ── OPPOSITION ────────────────────────────────
# The hostile force for THIS operation. Empty means "whatever the level ships
# with" — levels keep a baseline garrison so you can still press F5 on a map
# and have something to shoot, and this adds to it rather than replacing it.
@export var enemy_force: Array[EnemySquadSpec] = []
# Wipe the level's own hostile squads before spawning this force. Use when the
# mission wants full control of who's on the map.
@export var replace_level_enemies: bool = false

# ── OBJECTIVES ────────────────────────────────
# Which MissionObjective ids in the level are live for this operation. Empty
# means all of them. This is what lets one map host several operations without
# a full objective-spawning system: the level holds every objective it could
# ever need, and the mission switches a subset on.
@export var active_objectives: Array[StringName] = []

# ── REWARDS ───────────────────────────────────
# Paid into CampaignState.earned on successful extraction. Because the ledger
# only ever accumulates and spending is derived from allocations, this is the
# single place resources enter the game.
@export var reward_resources: int = 0
## Compute for the first clear only — replays pay resources, never compute.
## Compute is spent on squad supply (and, later, the skill tree).
@export var compute_reward: int = 0
@export var unlocks: Array[StringName] = []

# ── SQUAD ─────────────────────────────────────
## How many of your squad deploy with you. -1 is everyone who is ACTIVE (the
## spawn point's own cap still applies); 0 is a solo op. This is the campaign's
## pacing: the first ops are yours alone, then allies arrive one at a time, so
## commanding is learned one robot at a time rather than four at once. Roster
## order decides who fills the places — bench someone to choose.
@export var squad_size: int = -1

# ── REPLAYABILITY ─────────────────────────────
@export var repeatable: bool = false

## A DEFENCE, NOT AN ATTACK (Phase 5). Flips the operation: you start on the
## ground you already hold, your garrison spawns with you, and the attacker
## comes in from a frontier edge.
##
## A defence pays NOTHING — §2. The stake is the yield you keep, which is the
## whole reason it is worth turning up for, and paying for it as well would
## make losing ground profitable.
@export var defence: bool = false

## A SIM ARENA — A FREE ACTION, NOT AN OPERATION (Phase 6.4).
##
## The three Sim Arenas were ordinary missions: they paid resources and
## compute, sat on the `requires` ladder and would now burn a TURN, which makes
## practising cost you ground. They are a practice track, so:
##
##   no turn passes · nothing is paid · no site changes hands
##   the other side does not get a move · it can be run as often as you like
##
## §15 already settled that they are not territory and are not on the adjacency
## graph. This is the same statement, applied to the turn loop.
@export var sim: bool = false

## Where the player's garrison digs in, by anchor tag. One squad per post,
## sized from compute and built from what the player has unlocked — see
## force_generator.garrison(). Empty on an attack.
@export var garrison_posts: Array[StringName] = []
# Missions that must be completed before this one appears.
@export var requires: Array[StringName] = []


## "SOLO", "MAX 1 ALLY", "MAX 3 ALLIES" — or "" when there is no limit, which is
## the normal case and not worth a word: once the roster fills out, you choose
## how many go by benching, not the mission. Shown on the terminal and the
## briefing, so leaving your squad at base reads as the op's rule rather than
## as the game losing them.
func squad_label() -> String:
	if squad_size < 0:
		return ""
	if squad_size == 0:
		return "SOLO"
	return "MAX 1 ALLY" if squad_size == 1 else "MAX %d ALLIES" % squad_size


## How many hostile squads the op fields, reserves included. This is what the
## mission terminal shows instead of the briefing prose: one number the player
## can weigh against their own squad, with the detail left to the briefing.
func enemy_squad_count() -> int:
	var n := 0
	for spec in enemy_force:
		if spec != null:
			n += 1
	return n
