extends Control
class_name ScanEnemyMarker
var last_screen_pos: Vector2
@export var duration := 2.0
@export var scan_size := Vector2(120, 80)
@export var color := Color(1, 0.1, 0.1, 0.8)
var target: Node3D
@onready var camera = get_viewport().get_camera_3d()
func start_pulse():
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.2)
	tween.tween_property(self, "scale", Vector2.ONE, 0.2)
	tween.set_loops(3)
	tween.tween_interval(duration)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	#tween.tween_callback(Callable(self, "queue_free"))

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		queue_free()
		return
	# Frustum culling optimization: skip if off-screen
	var screen_pos = camera.unproject_position(target.global_position)

	# Optional: don't update if it's off-screen
	var viewport_rect = get_viewport_rect()
	if not viewport_rect.has_point(screen_pos):
		visible = false
		return
	else:
		visible = true

	# Only update if position changed
	if screen_pos != last_screen_pos:
		position = screen_pos
		last_screen_pos = screen_pos
