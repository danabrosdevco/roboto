extends Control
class_name ScanEnemyMarker
var last_screen_pos: Vector2
@export var duration := 2.0
@export var scan_size := Vector2(120, 80)
@export var color := Color(1, 0.1, 0.1, 0.8)
var target: Node3D
@onready var camera = get_viewport().get_camera_3d()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(target):
		queue_free()
		return
	var screen_pos = camera.unproject_position(target.global_position)
	var to_target = target.global_position - camera.global_position
	var cam_forward = -camera.global_transform.basis.z  # camera looks along -Z
	var dot = to_target.dot(cam_forward)

	if dot <= 0.0:
		# Target is behind the camera — hide marker and stop
		visible = false
		return
	var viewport_rect = get_viewport_rect()
	if not viewport_rect.has_point(screen_pos):
		visible = false
		return
	else:
		visible = true

	if screen_pos != last_screen_pos:
		position = screen_pos
		last_screen_pos = screen_pos
