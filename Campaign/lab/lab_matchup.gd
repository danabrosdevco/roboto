extends Resource
class_name LabMatchup

# ─────────────────────────────────────────────
# LAB MATCHUP — one fight for the laboratory, run `repeats` times.
#
# Two squads on the arena floor: ALLIES (your side's faction) and HOSTILES.
# Each is a roster of chassis — one entry per body, same as an EnemySquadSpec —
# and an order. Both sides are ordinary AI; nobody is steering them.
#
# WHERE THEY START. The arena runs in a line from its hostile post (the enemy
# garrison's dug-in position, with cover) to the insertion point.
#   - hostiles_on_post: hostiles start on the post, allies down the line.
#   - Exactly one side on HOLD: that side is the DEFENDER and starts on the
#     post; the other starts `distance` metres down the line.
#   - Otherwise: both start `distance` apart, centred on the middle of the
#     arena — open ground, no one gets the cover.
# swap_sides alternates which side gets which start on every other run, so a
# map advantage cancels out instead of hiding inside the result.
# ─────────────────────────────────────────────

enum Order {
	HOLD,           ## dig in where they start (a garrison, or the tap order on your own spot)
	ADVANCE,        ## push onto the other side's start and fight through it
	ATTACK,         ## focus the first enemy body, then carry on
	MOVE_AND_HOLD,  ## the player's tap onto the enemy: go there, then hold
}

@export var label: String = "4 chasers vs 4 rifles"
@export_group("Allies")
@export var allies: Array[ChassisDefinition] = []
@export var ally_order: Order = Order.ADVANCE
@export_group("Hostiles")
@export var hostiles: Array[ChassisDefinition] = []
@export var hostile_order: Order = Order.ADVANCE
@export_group("Setup")
## Metres between the two starts.
@export var distance: float = 25.0
@export var repeats: int = 5
## Seconds before a run is called a draw.
@export var time_limit: float = 120.0
## Only for fights where neither side is dug in: alternate the two starts on
## every other run.
@export var swap_sides: bool = false
## Hostiles start on the post (in its cover) whatever the orders, and allies
## `distance` down the line. For testing YOUR orders against a garrison.
@export var hostiles_on_post: bool = false
