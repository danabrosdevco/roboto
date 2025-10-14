extends Control
class_name ScanEnemyMarker

@export var duration := 5.0
var time: float = 0
@export var base_size := Vector2(120, 80)
@export var color := Color(1, 0.1, 0.1, 0.8)
@export var height_offset := 1.01   # move marker above feet
@export var min_scale := 0.6       # smallest when far
@export var max_scale := 2.0       # largest when near
@export var min_distance := 2.0
@export var max_distance := 30.0

var target: Node3D
var last_screen_pos: Vector2
@onready var camera = get_viewport().get_camera_3d()


func _physics_process(delta: float) -> void:
	time += delta
	if time >= duration:
		queue_free()
	if not is_instance_valid(target):
		queue_free()
		return

	# Offset the target position upward
	var world_pos = target.global_position + Vector3.UP * height_offset
	var screen_pos = camera.unproject_position(world_pos)

	# Hide if behind camera
	var to_target = world_pos - camera.global_position
	var cam_forward = -camera.global_transform.basis.z
	if to_target.dot(cam_forward) <= 0.0:
		visible = false
		return

	# Hide if off-screen
	var viewport_rect = get_viewport_rect()
	if not viewport_rect.has_point(screen_pos):
		visible = false
		return
	else:
		visible = true

	# Update position
	position = screen_pos

	# --- Distance-based scaling ---
	var distance = to_target.length()
	var t = clamp((distance - min_distance) / (max_distance - min_distance), 0.0, 1.0)
	var scale_factor = lerp(max_scale, min_scale, t)
	size = base_size * scale_factor
