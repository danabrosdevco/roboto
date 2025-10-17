extends Control
class_name ScanEnemyMarker

@export var duration := 5.0
var time: float = 0

@export var base_size := Vector2(75, 75)
@export var color := Color(1, 0.1, 0.1, 0.8)
@export var height_offset := 1.005  # vertical offset above target origin
@export var min_scale := 0.6
@export var max_scale := 2.0

# These define the pixel range of the marker's on-screen height
@export var min_pixel_height := 20.0
@export var max_pixel_height := 200.0

var target: Node3D
@onready var camera := get_viewport().get_camera_3d()

func _ready():
	await get_tree().create_timer(0.05)
	visible = true

func _physics_process(delta: float) -> void:
	time += delta
	if time >= duration:
		queue_free()
		return

	if not is_instance_valid(target):
		queue_free()
		return

	# Get two world positions: bottom and top of target
	var bottom_pos = target.global_position
	var top_pos = bottom_pos

	# Convert to screen space
	var screen_top = camera.unproject_position(top_pos)
	var screen_bottom = camera.unproject_position(bottom_pos)

	# Check if target is behind camera
	var to_target = top_pos - camera.global_position
	var cam_forward = -camera.global_transform.basis.z
	if to_target.dot(cam_forward) <= 0.0:
		visible = false
		return

	# Hide if off screen
	var screen_pos = screen_top
	var viewport_rect = get_viewport_rect()
	if not viewport_rect.has_point(screen_pos):
		visible = false
		return
	visible = true

	# Update this Control's position (centered on screen_pos)
	position = screen_pos
	# --- On-screen height scaling (FOV-aware) ---
	var pixel_height = abs(screen_top.y - screen_bottom.y)
	var t = clamp((pixel_height - min_pixel_height) / (max_pixel_height - min_pixel_height), 0.0, 1.0)
	var scale_factor = lerp(min_scale, max_scale, t)

	var scaled_size = base_size * scale_factor
	size = scaled_size
	position -= size * 0.5  # Center the marker

	# Optional: draw debug rect
	# update()

# Optional: If drawing manually, you can override _draw
# func _draw():
#     draw_rect(Rect2(Vector2.ZERO, size), color)
