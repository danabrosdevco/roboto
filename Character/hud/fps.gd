extends Label
var timer = 0.0
var time_to_check = 0.15
@export var hud_color: HUDPalette.HudColors = HUDPalette.HudColors.BRIGHT
func _ready():
	add_theme_color_override(
		"font_color",
		HUDPalette.get_hud_color(hud_color)
	)
	# SHOW FPS in the options. Off by default — a shipped game does not open
	# with a debug counter in the corner.
	Settings.add_listener(_on_setting_changed)
	_on_setting_changed("*")


func _exit_tree() -> void:
	Settings.remove_listener(_on_setting_changed)


func _on_setting_changed(_key: String) -> void:
	visible = Settings.get_bool("display.show_fps")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if not visible:
		return
	timer += delta
	if timer >= time_to_check:
		timer = 0.0
		text = ("FPS: " + str(Engine.get_frames_per_second()))
