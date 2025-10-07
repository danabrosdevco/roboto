extends Control
class_name ScanEnemyMarker

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

func _process(_delta):
	if is_instance_valid(target):
		var screen_pos = camera.unproject_position(target.global_position)
		position = Vector2(screen_pos.x, screen_pos.y)
	#else:
		#queue_free()
