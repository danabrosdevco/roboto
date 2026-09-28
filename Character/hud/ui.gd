extends Control
@export var health_label: Label
@export var ammo_label: Label
@export var progress_bars: Array[ProgressBar]
@export var bar_scene: PackedScene
@export var health_container: HBoxContainer
@export var scanner: ProgressBar

# Optional. Assign a ProgressBar here and it gets the blue signal treatment and
# tracks player signal integrity. Leave null and nothing breaks.
@export var signal_bar: ProgressBar

# Segmented health, Far Cry style. Each segment covers this much health.
@export var health_per_segment: int = 20
# Colour each segment by the WHOLE bar's health rather than its own fill, so the
# strip turns amber together instead of the last segment going red on its own.
@export var color_segments_by_total: bool = true

var tween : Tween


func _ready() -> void:
	_apply_palette()


# ─────────────────────────────────────────────
# STYLING — pulls from HUDPalette, same source the squad roster uses.
# Overriding the theme in code rather than in the .tscn means the two HUDs
# can't drift apart when a colour changes.
# ─────────────────────────────────────────────
func _apply_palette() -> void:
	for bar in progress_bars:
		HUDPalette.style_bar(bar, HUDPalette.BRIGHT)
	if signal_bar != null:
		HUDPalette.style_bar(signal_bar, HUDPalette.SIGNAL)
	# The strip under the health blocks is the scanner's charge, and it wears
	# HUDPalette.SIGNAL — the same blue the squad roster uses for a degraded
	# link, so blue means "the signal side of things" wherever you read it.
	# It was a flat grey slab, which read as a disabled control.
	#
	# It is NOT the player's own signal integrity: the player has no live one
	# (nothing ever calls update_signal). If the player is ever given one the
	# way robots have it, assign `signal_bar` and it gets its own strip.
	if scanner != null:
		HUDPalette.style_bar(scanner, HUDPalette.SIGNAL)


func _color_health_bars(health: int, max_health: int) -> void:
	var total_fraction := float(health) / float(maxi(1, max_health))
	for i in progress_bars.size():
		var bar: ProgressBar = progress_bars[i]
		if bar == null:
			continue
		var col: Color
		if color_segments_by_total:
			col = HUDPalette.health_color(total_fraction)
		else:
			col = HUDPalette.health_color(bar.value / maxf(1.0, bar.max_value))
		HUDPalette.style_bar(bar, col)


func update_signal(integrity: float) -> void:
	if signal_bar == null:
		return
	signal_bar.min_value = 0.0
	signal_bar.max_value = 1.0
	signal_bar.value = clampf(integrity, 0.0, 1.0)
	HUDPalette.style_bar(signal_bar, HUDPalette.SIGNAL)

func update_scanner(time: float):
	if tween and is_instance_valid(tween):
		tween.kill()
	scanner.value = 0 
	tween = create_tween()
	tween.tween_property(scanner, "value", scanner.max_value, time)
	pass


func update_status(health: int, max_health: int, magazine_capacity: int, magazine_size: int) -> void:
	# --- Ammo ---
	ammo_label.text = "%d / %d" % [magazine_capacity, magazine_size]

	# --- Health Segments ---
	var required_segments := int(ceil(max_health / float(health_per_segment)))

	# Auto-create or remove progress bars to match max_health
	while progress_bars.size() < required_segments:
		var new_bar = bar_scene.instantiate()
		health_container.add_child(new_bar)
		progress_bars.append(new_bar)
		HUDPalette.style_bar(new_bar, HUDPalette.BRIGHT)

	while progress_bars.size() > required_segments:
		var bar = progress_bars.pop_back()
		bar.queue_free()

	# Update bar values
	var remaining := health
	for i in range(progress_bars.size()):
		var bar := progress_bars[i]
		if remaining > 0:
			bar.value = clampi(remaining, 0, health_per_segment)
		else:
			bar.value = 0
		remaining -= health_per_segment

	_color_health_bars(health, max_health)
