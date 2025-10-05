extends Area3D


@export var speed: float = 120.0
@export var max_distance: float = 100.0
@export var hit_effect_scene: PackedScene

var direction: Vector3
var distance_traveled := 0.0
var is_active := true

func _physics_process(delta: float) -> void:
	if not is_active:
		return

	var move_amount = direction * speed * delta
	var space_state = get_world_3d().direct_space_state

	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + move_amount)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)

	if result:
		# 🎯 Stop tracer on hit
		is_active = false
		global_position = result.position

		if hit_effect_scene:
			var effect = hit_effect_scene.instantiate()
			effect.global_position = result.position
			get_tree().current_scene.add_child(effect)

		# Optionally stick tracer or destroy it
		await get_tree().create_timer(0.1).timeout
		queue_free()
	else:
		global_translate(move_amount)
		distance_traveled += move_amount.length()

		if distance_traveled >= max_distance:
			is_active = false
			queue_free()
