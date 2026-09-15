extends Label
var timer = 0.0
var time_to_check = 0.15
@export var hud_color: HUDPalette.HudColors = HUDPalette.HudColors.BRIGHT
func _ready():
	add_theme_color_override(
		"font_color",
		HUDPalette.get_hud_color(hud_color)
	)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	timer += delta
	if timer >= time_to_check:
		timer = 0.0
		text = ("FPS: " + str(Engine.get_frames_per_second()))
	pass
