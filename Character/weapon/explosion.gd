extends Node3D
class_name Explosion
@export var effects: Array[GPUParticles3D]
@export var audio: AudioStreamPlayer3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for i in effects:
		i.emitting = true
	audio.pitch_scale = randf_range(0.9, 1.1)   # ±10% pitch change
	audio.play()
	await get_tree().create_timer(2).timeout
	queue_free()
