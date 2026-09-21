extends Node3D
class_name MuzzleFlash

@export var flash_textures: Array[Texture2D]
@onready var sprite: Sprite3D = $Sprite3D
@onready var light: OmniLight3D = $OmniLight3D

var frame_counter := 0
var active := false
@export var flash_frames := 3
var prev_number

func _ready():
	_tint()
	if get_parent() is World:
		play_flash()


# The heat shader draws the texture, not the Sprite3D, so it has to be handed
# whichever star was picked. Sprite3D still owns the quad and its size; the
# override only owns how it is coloured. Nothing here if the material is a
# plain one — the flash then looks the way it always did.
func _tint() -> void:
	if sprite == null or sprite.texture == null:
		return
	var mat := sprite.material_override as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter(&"flash", sprite.texture)

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
	_tint()
	visible = true
	if light:
		light.visible = true
	active = true
	frame_counter = 0
	prev_number = number
	if get_parent() is World:
		await get_tree().create_timer(0.3).timeout
		queue_free()

func _process(_delta: float) -> void:
	if not active:
		return

	frame_counter += 1
	if frame_counter >= flash_frames:
		visible = false
		if light:
			light.visible = false
		active = false
