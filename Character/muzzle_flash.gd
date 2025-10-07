extends Node3D

@export var flash_textures: Array[Texture2D]
@onready var sprite: Sprite3D = $Sprite3D
@onready var light: OmniLight3D = $OmniLight3D

var frame_counter := 0
var active := false
@export var flash_frames := 2
var prev_number
func play_flash() -> void:
	var number = randi_range(0, flash_textures.size() -1)
	sprite.texture = flash_textures.pick_random()
	if number == prev_number:
		if number == 3:
			sprite.texture = flash_textures[0]
		else:
			sprite.texture = flash_textures[number + 1]
	else:
		sprite.texture = flash_textures[number]
	visible = true
	if light:
		light.visible = true
	active = true
	frame_counter = 0
	prev_number = number

func _process(_delta: float) -> void:
	if not active:
		return

	frame_counter += 1
	if frame_counter >= flash_frames:
		visible = false
		if light:
			light.visible = false
		active = false
