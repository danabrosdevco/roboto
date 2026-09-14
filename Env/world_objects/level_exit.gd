extends Node3D
class_name LevelExit

# ─────────────────────────────────────────────
# LEVEL EXIT — the train, the extraction pad, any door out.
#
# It stays dumb on purpose. It does NOT ask where it goes; something else SETS
# next_level on it. At base that's the mission terminal writing the selected
# operation in. On a mission it's World pointing it back at home base.
#
# Two flags and a refusal are the only additions:
#   is_departure                  marks this as the one the terminal writes to
#   requires_objectives_complete  won't let you leave mid-mission
# and it refuses rather than emitting a null scene, which used to hand World a
# null and fail somewhere much less obvious.
# ─────────────────────────────────────────────

@export var area: Area3D
@export var next_level: PackedScene

# The train at base. World registers these with Campaign so selecting a mission
# knows which exit to point at the chosen level.
@export var is_departure: bool = false
# Extraction gate. Off by default so ordinary doors behave as they always did.
@export var requires_objectives_complete: bool = false

signal next_level_signal(level: PackedScene)
signal exit_blocked(reason: String)


func _ready() -> void:
	if is_departure:
		add_to_group("departure_exits")


func _on_area_3d_body_entered(body: Node3D) -> void:
	if not (body is Player):
		return

	if next_level == null:
		# At base this means no operation has been selected yet, which is a
		# prompt-the-player state rather than an error.
		exit_blocked.emit("NO DESTINATION SET" if is_departure else "NO DESTINATION")
		return

	if requires_objectives_complete and not _objectives_done():
		exit_blocked.emit("OBJECTIVES INCOMPLETE")
		return

	next_level_signal.emit(next_level)


# Looked up by path rather than by the `Campaign` identifier so a LevelExit
# still works in a scene where the campaign autoload isn't present — this is a
# generic door, and it shouldn't hard-depend on the campaign layer.
func _objectives_done() -> bool:
	var campaign := get_node_or_null("/root/Campaign")
	if campaign == null:
		return true
	var tracker = campaign.objectives
	if tracker == null:
		return true
	return tracker.all_required_complete()
