extends Label

enum HudColor {
	DIM,
	BRIGHT,
	WARN,
	CRIT,
	SIGNAL,
	POSSESS
}

@export var hud_color: HUDPalette.HudColors = HUDPalette.HudColors.BRIGHT
func _ready():
	add_theme_color_override(
		"font_color",
		HUDPalette.get_hud_color(hud_color)
	)
