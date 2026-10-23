extends Control
@export var health_label: Label
@export var ammo_label: Label
@export var progress_bars: Array[ProgressBar]
@export var bar_scene: PackedScene
@export var health_container: HBoxContainer
@export var scanner: ProgressBar

# The blue strip under the health blocks. It is the player's own link quality:
# the same number that drives the signal filter's `damage` uniform, so what the
# bar says and what the screen looks like cannot disagree.
#
# IT USED TO BE THE SCANNER'S CHARGE, which was never wired to anything —
# activate_scan_effect has no callers in the project, so the strip sat at a
# static 100 forever. If the scanner comes back it needs its own strip; see the
# warning in update_scanner.
@export var signal_bar: ProgressBar

# Segmented health, Far Cry style. Each segment covers this much health.
@export var health_per_segment: int = 20
## Most segments the strip will ever draw. Past this a segment covers more
## health instead of another bar being added -- see update_status.
@export var max_segments: int = 24
# Colour each segment by the WHOLE bar's health rather than its own fill, so the
# strip turns amber together instead of the last segment going red on its own.
@export var color_segments_by_total: bool = true

var tween : Tween


func _ready() -> void:
	_apply_palette()
	_free_the_signal_bar()


# ─────────────────────────────────────────────
# THE SIGNAL BAR IS NOT PART OF THE HEALTH STRIP.
#
# Both live in `Corner`, a VBoxContainer, and a VBox stretches its children to
# the widest one. The health strip is built from one ProgressBar per
# health_per_segment, so a chassis with a lot of health widens the VBox — and
# the signal bar, which has no business caring, grows with it.
#
# Photographed at 9999 health: five hundred health segments ran off the screen
# and the signal bar stretched the full width with them, so a 0-to-1 gauge was
# being drawn at whatever size the hull happened to be. custom_minimum_size in
# the scene is a MINIMUM and does not stop it.
#
# SHRINK_BEGIN rather than a width: the bar keeps the 215px the scene asks for,
# stays left-aligned with everything above it, and stops inheriting the strip's
# problems. Done in code so the scene stays the terrain lane's to edit.
# ─────────────────────────────────────────────
func _free_the_signal_bar() -> void:
	if signal_bar == null:
		return
	signal_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


# ─────────────────────────────────────────────
# STYLING — pulls from HUDPalette, same source the squad roster uses.
# Overriding the theme in code rather than in the .tscn means the two HUDs
# can't drift apart when a colour changes.
# ─────────────────────────────────────────────
func _apply_palette() -> void:
	for bar in progress_bars:
		HUDPalette.style_bar(bar, HUDPalette.BRIGHT)
	# Blue is "the signal side of things" wherever you read it — the same blue
	# the squad roster uses for a degraded link.
	if signal_bar != null:
		HUDPalette.style_bar(signal_bar, HUDPalette.SIGNAL)
		_signal_tone = HUDPalette.SIGNAL
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


# ─────────────────────────────────────────────
# SIGNAL INTEGRITY
#
# Driven from HUD._apply_damage_uniform with the player's live
# signal_integrity, so the strip is that number 1:1 — not a reading derived
# from it, and not the shader's value, which carries a hit flinch on top.
#
# THE BANDS ARE THE GAME'S OWN. AI.SIGNAL_FUZZED and friends are what the rest
# of the game means by a degraded link; a second set of thresholds here would
# have the strip turn amber at a point nothing else in the game agrees is
# significant.
# ─────────────────────────────────────────────

var _signal_tone: Color = HUDPalette.SIGNAL
var _signal_readout: Label = null


## `integrity` is the player's signal_integrity, 1.0 clean and 0.0 e-killed.
## `shader_damage` is what the feed is actually being degraded by, carried
## through only so the debug readout can state the real figure — the two differ
## by the hit flinch, and quoting the wrong one would make the readout useless
## for exactly what it is for.
func update_signal(integrity: float, shader_damage: float = -1.0) -> void:
	if signal_bar == null:
		return
	var v: float = clampf(integrity, 0.0, 1.0)
	signal_bar.min_value = 0.0
	signal_bar.max_value = 1.0
	signal_bar.value = v
	# RESTYLE ONLY ON A BAND CHANGE. style_bar allocates two StyleBoxFlats, and
	# this is called every physics frame — doing it unconditionally churned
	# garbage for an identical result on all but three frames.
	var tone := HUDPalette.SIGNAL
	if v <= AI.SIGNAL_CRITICAL:
		tone = HUDPalette.CRIT
	elif v <= AI.SIGNAL_DEGRADED:
		tone = HUDPalette.WARN
	if tone != _signal_tone:
		_signal_tone = tone
		HUDPalette.style_bar(signal_bar, tone)
	_update_signal_readout(v, shader_damage)


## The band, in the game's own vocabulary.
static func signal_word(integrity: float) -> String:
	if integrity <= AI.SIGNAL_EKILL:
		return "LINK LOST"
	if integrity <= AI.SIGNAL_CRITICAL:
		return "LINK CRITICAL"
	if integrity <= AI.SIGNAL_DEGRADED:
		return "LINK DEGRADED"
	if integrity <= AI.SIGNAL_FUZZED:
		return "LINK FUZZED"
	return "LINK STABLE"


## The exact figures, behind the debug switch, so the effect can be judged at a
## known value instead of by eye. Absent entirely when the switch is off.
func _update_signal_readout(v: float, shader_damage: float) -> void:
	var want: bool = Settings.debug_tools_enabled() and Settings.get_bool("debug.signal_readout")
	if not want:
		if _signal_readout != null and is_instance_valid(_signal_readout):
			_signal_readout.queue_free()
			_signal_readout = null
		return
	if _signal_readout == null or not is_instance_valid(_signal_readout):
		_signal_readout = Label.new()
		_signal_readout.add_theme_font_size_override("font_size", 14)
		_signal_readout.add_theme_color_override("font_color", HUDPalette.SIGNAL)
		signal_bar.get_parent().add_child(_signal_readout)
	var tail: String = "" if shader_damage < 0.0 else "   feed %.2f" % shader_damage
	_signal_readout.text = "%s  %d%%%s" % [signal_word(v), int(round(v * 100.0)), tail]


func update_scanner(time: float):
	# The scanner lost its strip to signal integrity, because nothing in the
	# project has ever called this. If something starts to, it needs a bar of
	# its own rather than stealing the one that now means something.
	if scanner == null:
		push_warning("ui: update_scanner called but no scanner bar is assigned — the blue strip is signal integrity now, so the scanner needs its own.")
		return
	if tween and is_instance_valid(tween):
		tween.kill()
	scanner.value = 0
	tween = create_tween()
	tween.tween_property(scanner, "value", scanner.max_value, time)


func update_status(health: int, max_health: int, magazine_capacity: int, magazine_size: int) -> void:
	# --- Ammo ---
	ammo_label.text = "%d / %d" % [magazine_capacity, magazine_size]

	# --- Health Segments ---
	# BOUNDED. One bar per health_per_segment is the Far Cry look and it is
	# right up to a few hundred health, but nothing capped it: at 9999 it built
	# five hundred ProgressBars, ran the strip off the screen and dragged the
	# whole corner panel wide with it. Past the cap a segment simply covers
	# more health, so the strip keeps its shape for any chassis.
	var per: int = maxi(health_per_segment,
		int(ceil(max_health / float(maxi(1, max_segments)))))
	var required_segments := int(ceil(max_health / float(per)))

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
		# The bar's own ceiling moves with the segment size, or a segment that
		# covers 50 health still reads full at 20 and the colour band below
		# divides by the wrong number.
		bar.max_value = per
		if remaining > 0:
			bar.value = clampi(remaining, 0, per)
		else:
			bar.value = 0
		remaining -= per

	_color_health_bars(health, max_health)
