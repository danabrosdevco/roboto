extends Node3D
class_name Explosion
@export var effects: Array[GPUParticles3D]
@export var audio: AudioStreamPlayer3D
@export var damage_value:=  20
@export var damage_area: Area3D
var damaged: = {}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:

	for i in effects:
		i.emitting = true
	audio.pitch_scale = randf_range(0.9, 1.1)   # ±10% pitch change
	if get_parent() is not World:
		audio.play()
	await get_tree().create_timer(0.3).timeout
	damage_area.monitoring = false
	await get_tree().create_timer(2).timeout
	queue_free()



func _on_area_3d_body_entered(body: Node3D) -> void:
	if damaged.has(body):  # skip repeat
		return

	if body.has_method("apply_damage"):
		body.apply_damage(damage_value)
		damaged[body] = true
		print("BOMBED", body.name)
	elif body.get_parent() and body.get_parent().has_method("apply_damage"):
		body.get_parent().apply_damage(damage_value)
		damaged[body.get_parent()] = true
		print("BOMBED", body.get_parent().name)
