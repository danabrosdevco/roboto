extends RefCounted
class_name HUDPalette

# ─────────────────────────────────────────────
# HUD PALETTE
# Single source of truth for the telemetry look. squad_hud.gd and ui.gd both
# pull from here, so changing a colour once changes it everywhere rather than
# leaving the player's own bars drifting away from the squad roster's.
#
# The greens are deliberately desaturated relative to the CRT filter so they
# read as overlay rather than as part of the filtered scene.
# ─────────────────────────────────────────────
const colors = [DIM, BRIGHT, WARN, CRIT, SIGNAL, POSSESS]
enum HudColors {
	DIM,
	BRIGHT,
	WARN,
	CRIT,
	SIGNAL,
	POSSESS
}
const DIM      := Color(0.45, 0.62, 0.48, 0.85)   # inactive text, labels
const BRIGHT   := Color(0.62, 0.95, 0.66)         # healthy / active
const WARN     := Color(0.95, 0.78, 0.35)         # degraded
const CRIT     := Color(0.95, 0.42, 0.35)         # critical / destroyed
const SIGNAL   := Color(0.40, 0.78, 0.95)         # signal integrity (blue)
const POSSESS  := Color(0.95, 0.85, 0.40)         # body under manual control

# Backgrounds are the fill colour at low alpha, so an empty bar still reads as
# belonging to the same channel rather than as a generic grey trough.
const BG_ALPHA: float = 0.18

# Health thresholds — shared so a segment in the player's bar turns amber at
# the same point a squadmate's roster bar does.
const HEALTH_WARN_AT: float = 0.6
const HEALTH_CRIT_AT: float = 0.3


static func get_hud_color(hud_color) -> Color:
	return colors[hud_color]

static func fill_style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	return sb


static func bg_style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, BG_ALPHA)
	return sb


# Apply the palette to any ProgressBar in one call.
static func style_bar(bar: ProgressBar, col: Color) -> void:
	if bar == null:
		return
	bar.show_percentage = false
	bar.add_theme_stylebox_override("fill", fill_style(col))
	bar.add_theme_stylebox_override("background", bg_style(col))


static func health_color(fraction: float) -> Color:
	if fraction > HEALTH_WARN_AT:
		return BRIGHT
	if fraction > HEALTH_CRIT_AT:
		return WARN
	return CRIT
