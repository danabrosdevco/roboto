extends Control

@export var scan_duration := 3.5
@export var scan_thickness := 16.0
@export var scan_color := Color(1, 0, 0, 0.8)  # semi-transparent red

var tween: Tween

func _ready():
	_setup_scan_rects()
	_run_scan_animation()

func _setup_scan_rects():
	var screen_size = get_viewport_rect().size

	# Set color and reset anchors
	for rect in get_children():
		if rect is ColorRect:
			rect.color = scan_color
			rect.anchor_left = 0
			rect.anchor_top = 0
			rect.anchor_right = 0
			rect.anchor_bottom = 0
			rect.offset_left = 0
			rect.offset_top = 0
			rect.offset_right = 0
			rect.offset_bottom = 0

	# Position each bar manually (off-screen)
	$Top.position = Vector2(0, -scan_thickness)
	$Top.size = Vector2(screen_size.x, scan_thickness)

	$Bottom.position = Vector2(0, screen_size.y)
	$Bottom.size = Vector2(screen_size.x, scan_thickness)

	$Left.position = Vector2(-scan_thickness, 0)
	$Left.size = Vector2(scan_thickness, screen_size.y)

	$Right.position = Vector2(screen_size.x, 0)
	$Right.size = Vector2(scan_thickness, screen_size.y)

func _run_scan_animation():
	var screen_size = get_viewport_rect().size
	tween = create_tween()

	# --- Rectangle size parameters ---
	var rect_width = screen_size.x * 0.4  # 50% of screen width
	var rect_height = screen_size.y * 0.4   # 30% of screen height

	# --- Animate bars inward to rectangle edges ---
	# Horizontal bars move vertically toward rect_height center
	tween.tween_property($Top, "position:y", (screen_size.y - rect_height) * 0.5 - scan_thickness, scan_duration)
	tween.parallel().tween_property($Bottom, "position:y", (screen_size.y + rect_height) * 0.5, scan_duration)

	# Vertical bars move horizontally toward rect_width center
	tween.parallel().tween_property($Left, "position:x", (screen_size.x - rect_width) * 0.5 - scan_thickness, scan_duration)
	tween.parallel().tween_property($Right, "position:x", (screen_size.x + rect_width) * 0.5, scan_duration)

	# --- Optional pause and fade out ---
	tween.tween_interval(0.4)
	tween.tween_callback(Callable(self, "_fade_out"))


func _fade_out():
	var screen_size = get_viewport_rect().size
	var center_y = screen_size.y * 0.5
	var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	var time = 0.1
	# Collapse vertically toward center
	for rect in get_children():
		if rect is ColorRect:
			# Move top/bottom bars to the center line
			if rect == $Top:
				tween.parallel().tween_property(rect, "position:y", center_y - scan_thickness * 0.5, time)
			elif rect == $Bottom:
				tween.parallel().tween_property(rect, "position:y", center_y - scan_thickness * 0.5, time)
			elif rect == $Left or rect == $Right:
				# Shrink vertical bars horizontally toward middle
				var center_x = screen_size.x * 0.5
				tween.parallel().tween_property(rect, "position:x", center_x - scan_thickness * 0.5, time)
				tween.parallel().tween_property(rect, "size:x", 1.0, time)
			# Bright flash as they meet
			tween.parallel().tween_property(rect, "modulate", Color(1, 0.2, 0.2, 1.0), time * 0.75)
	tween.tween_interval(0.05)
	# Snap to black instantly
	for rect in get_children():
		if rect is ColorRect:
			tween.parallel().tween_property(rect, "modulate:a", 0.0, 0.05)
	tween.tween_callback(Callable(self, "queue_free"))
