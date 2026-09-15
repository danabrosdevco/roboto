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
@export var unlocks: Array[StringName] = []

# ── REPLAYABILITY ─────────────────────────────
@export var repeatable: bool = false
# Missions that must be completed before this one appears.
@export var requires: Array[StringName] = []
