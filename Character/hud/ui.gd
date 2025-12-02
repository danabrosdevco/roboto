extends Control
@export var health_label: Label
@export var ammo_label: Label
@export var shards_label: Label
@export var second_label: Label
@export var progress_bars: Array[ProgressBar]
@export var bar_scene: PackedScene
@export var health_container: HBoxContainer
@export var scanner: TextureProgressBar
var tween : Tween

func update_scanner(time: float):
	if tween and is_instance_valid(tween):
		tween.kill()
	scanner.value = 0 
	tween = create_tween()
	tween.tween_property(scanner, "value", scanner.max_value, time)
	pass


func update_status(health: int, max_health: int, magazine_capacity: int, magazine_size: int, shards: int, bits: int) -> void:
	# --- Ammo & Shards ---
	ammo_label.text = "%d / %d" % [magazine_capacity, magazine_size]
	shards_label.text = ": " + str(shards)
	second_label.text = ": " + str(bits)

	# --- Health Segments ---
	var health_per_segment := 20
	var required_segments := int(ceil(max_health / float(health_per_segment)))

	# Auto-create or remove progress bars to match max_health
	while progress_bars.size() < required_segments:
		var new_bar = bar_scene.instantiate()
		# Optional: configure sizing, add to UI container
		health_container.add_child(new_bar)
		progress_bars.append(new_bar)

	while progress_bars.size() > required_segments:
		var bar = progress_bars.pop_back()
		bar.queue_free()

	# Update bar values
	var remaining := health
	for i in range(progress_bars.size()):
		var bar := progress_bars[i]
		if remaining > 0:
			bar.value = clamp(remaining, 0, health_per_segment)
		else:
			bar.value = 0
		remaining -= health_per_segment
