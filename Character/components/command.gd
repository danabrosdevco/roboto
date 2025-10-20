extends Node3D
class_name CommandMarker
@export var marker: Node3D
@export var faction: Enums.Factions

func set_faction(new_faction):
	faction = Enums.Factions.values()[new_faction]

func perform_faction_check():
	var space_state = get_world_3d().direct_space_state

	# Create a sphere shape for overlap query
	var sphere = SphereShape3D.new()
	sphere.radius = 200.0

	var new_transform = Transform3D.IDENTITY
	transform.origin = global_position  # Center the sphere on this marker

	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = new_transform
	query.collide_with_areas = false
	query.collide_with_bodies = true

	# Get all intersecting bodies
	var results = space_state.intersect_shape(query, 32)

	for result in results:
		var body = result.get("collider")
		if body and body.has_method("get_faction"):
			if body.get_faction() == faction:
				if body.has_method("on_command_marker_nearby"):
					body.on_command_marker_nearby(self)
