extends Node3D

@export var flash_textures: Array[Texture2D]
@onready var sprite: Sprite3D = $Sprite3D
@onready var light: OmniLight3D = $OmniLight3D

var frame_counter := 0
var active := false
@export var flash_frames := 2

func play_flash() -> void:
	if flash_textures.size() > 0:
		sprite.texture = flash_textures.pick_random()
	visible = true
	if light:
		light.visible = true
	active = true
	frame_counter = 0

func _process(delta: float) -> void:
	if not active:
		return

	frame_counter += 1
	if frame_counter >= flash_frames:
		visible = false
		if light:
			light.visible = false
		active = false
