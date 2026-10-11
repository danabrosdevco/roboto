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
# ─────────────────────────────────────────────
# GONE — finished, and still readable.
#
# DIM was the obvious choice for a destroyed squadmate and it is the wrong one.
# Every other colour here is on the green axis because the HUD is a green CRT,
# and DIM is the most desaturated of them: Color(0.45, 0.62, 0.48) against
# Mutaha's grass is very nearly the same colour, so a destroyed row rendered in
# it did not read as quiet, it vanished. Photographed, the roster had a blank
# band where the fourth robot should have been — a HUD that says you have
# three squadmates when you have four.
#
# This is deliberately OFF that axis: a cool neutral grey that cannot
# camouflage against terrain, sky or the filter, and that reads as switched
# off precisely because nothing else in the palette is colourless.
const GONE     := Color(0.66, 0.70, 0.73, 0.95)   # destroyed: inert, not urgent

# Backgrounds are the fill colour at low alpha, so an empty bar still reads as
# belonging to the same channel rather than as a generic grey trough.
# ─────────────────────────────────────────────
# WHO A MARK IS ABOUT, IN COLOUR.
#
# Taken from the faction briefs so the HUD and the world agree: the bracket
# over a contact is the same colour family as the thing it is bracketing.
#
# LIFTED FROM THE WORLD VALUES, deliberately. A material colour and a HUD glyph
# have different jobs: the Swarm's painted amber is #B35A05 and Home Command's
# institutional green is #5A6B4A, and both are too dark to read as a 40px
# bracket over terrain through the signal filter. These are the same hues with
# the value raised until they survive that.
#
# ONLY ENEMY EXISTS TODAY. Enums.Factions is PLAYER/ENEMY/ALLIED/NEUTRAL, so
# Home Command and Argus hostiles have nowhere to live yet — adding them is an
# APPEND to that enum, which is safe (the rule is append-only, and these would
# go on the end). The colours are written now so the day someone adds the
# faction there is nothing to design.
const FAC_SWARM    := Color(0.91, 0.63, 0.23)   # amber, lifted from #B35A05
const FAC_HOME := Color(0.64, 0.73, 0.44)   # institutional green, lifted
const FAC_ARGUS    := Color(0.69, 0.20, 0.47)   # tyrian, lifted from #66023C
const FAC_UNKNOWN  := Color(0.70, 0.74, 0.76)   # a contact with no identity


## The bracket colour for a faction. Falls back to the amber hostile, because
## a contact report with nothing identified is overwhelmingly a hostile one and
## a grey bracket on a real enemy reads as a bug.
static func faction_color(faction) -> Color:
	match faction:
		Enums.Factions.PLAYER, Enums.Factions.ALLIED:
			return SIGNAL
		Enums.Factions.NEUTRAL:
			return FAC_UNKNOWN
		Enums.Factions.SWARM:
			return FAC_SWARM
		Enums.Factions.HOME:
			return FAC_HOME
		Enums.Factions.ARGUS:
			return FAC_ARGUS
		_:
			# ENEMY and anything unforeseen. Kept as the fall-through rather
			# than an arm of its own, because a contact report with nothing
			# identified is overwhelmingly a hostile one.
			return FAC_SWARM


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
