extends Node
class_name PatrolPath
@export var points: Array[Node3D]

var patrol_indices := {}

func get_next_point(ai: Node) -> Node3D:
	if not ai in patrol_indices:
		patrol_indices[ai] = 0

	if points.is_empty():
		return null

	var index = patrol_indices[ai]
	var next_point = points[index]

	# Advance index for next time
	index = (index + 1) % points.size()
	patrol_indices[ai] = index
	return next_point
