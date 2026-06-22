extends Node3D
class_name CoverPoint

# ─────────────────────────────────────────────
# COVER POINT
# Placed by CoverPointSpawner via navmesh edge-walking.
# Stores cover quality data baked at edit time.
# ─────────────────────────────────────────────

## Direction the soldier faces when using this cover (away from the wall)
@export var cover_direction: Vector3 = Vector3.FORWARD

## If true, only provides crouch cover (low wall)
@export var is_crouch_cover: bool = false

## Height offset for LOS checks
@export var los_check_height: float = 1.0

var occupant: Soldier = null

func _ready() -> void:
	add_to_group("cover_points")
	# Restore baked metadata if set by spawner
	if has_meta("cover_direction"):
		cover_direction = get_meta("cover_direction")
	if has_meta("is_crouch_cover"):
		is_crouch_cover = get_meta("is_crouch_cover")

func is_occupied() -> bool:
	return occupant != null and occupant.alive

func mark_occupied(soldier: Soldier) -> void:
	occupant = soldier

func mark_unoccupied(soldier: Soldier) -> void:
	if occupant == soldier:
		occupant = null

## Returns true if there is clear LOS from this cover point to world_pos.
## Soldiers PREFER points where this returns FALSE (wall blocks LOS = good cover).
func has_los_to(world_pos: Vector3) -> bool:
	var from = global_position + Vector3.UP * los_check_height
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, world_pos)
	var result = space_state.intersect_ray(query)
	return result.is_empty()

## Score this cover point for a given soldier and target position.
## Higher is better. Used by Soldier.find_best_cover_point().
func score_for(soldier_pos: Vector3, target_pos: Vector3) -> float:
	var score: float = 0.0

	# Prefer closer cover
	score -= global_position.distance_to(soldier_pos) * 0.5

	# Strongly prefer cover that blocks LOS to target
	if not has_los_to(target_pos):
		score += 15.0

	# Prefer stand cover over crouch cover
	if not is_crouch_cover:
		score += 5.0

	# Prefer cover where the soldier's facing direction is toward the target
	var to_target = (target_pos - global_position).normalized()
	var dot = cover_direction.dot(to_target)
	score += dot * 3.0  # rewards cover that naturally faces the enemy

	return score
