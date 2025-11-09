extends Node3D
class_name Tracer

@export var speed: float = 160.0
@export var max_distance: float = 100.0
@export var hit_effect_scene: PackedScene

# --- Tracer scaling config ---
@export var start_scale_z: float = 0.5
@export var end_scale_z: float = 4.0
@export var scale_distance: float = 15  # distance over which tracer lengthens

@export var direction: Vector3
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

		await get_tree().create_timer(0.01).timeout
		queue_free()
	else:
		global_translate(move_amount)
		distance_traveled += move_amount.length()
		var t = clamp(inverse_lerp(0.0, scale_distance, distance_traveled), 0.0, 1.0)
		var new_scale_z = lerp(start_scale_z, end_scale_z, t)
		scale.z = new_scale_z
		if distance_traveled >= max_distance:
			is_active = false
			queue_free()
