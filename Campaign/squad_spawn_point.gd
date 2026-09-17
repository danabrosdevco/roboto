extends Node3D
class_name SquadSpawnPoint

# ─────────────────────────────────────────────
# SQUAD SPAWN POINT — where the player's squad deploys.
#
# Levels used to contain hand-placed Soldier instances wired into a Squad's
# squad_members array. They contain one of these instead now: the roster decides
# WHO deploys, the level only says WHERE.
#
# Drop one in the base level too. Deploying from the base and arriving on a
# mission are the same operation as far as the spawner is concerned.
# ─────────────────────────────────────────────

@export var callsign: String = "ALPHA"
# Cap on how many of the roster deploy here. 0 means everyone deployable.
@export var max_slots: int = 4
@export var player_commandable: bool = true
@export var default_objective: Squad.SquadObjective = Squad.SquadObjective.FOLLOW
# Optional. Leave null and FOLLOW makes the player the objective.
@export var target_objective: SquadObjectivePoint

# Explicit stand positions. Add child Node3Ds to control the formation exactly;
# leave empty and the spawner lays out a simple arc behind this node.
@export var slot_markers: Array[Node3D] = []

@export var spacing: float = 1.8


func _ready() -> void:
	add_to_group("squad_spawn_points")
# Where the nth deployed soldier stands.
func slot_position(index: int) -> Vector3:
	if index < slot_markers.size() and slot_markers[index] != null:
		return slot_markers[index].global_position
	# Arc behind the spawn point, alternating left and right of centre.
	@warning_ignore("integer_division")
	var row := index / 2
	var side := 1.0 if index % 2 == 0 else -1.0
	var offset := Vector3(side * spacing * (float(row) * 0.5 + 0.5), 0.0, float(row) * spacing)
	return global_position + (global_transform.basis * offset)
