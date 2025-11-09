extends Control
class_name HUD
@export var scan_effect_scene: PackedScene
@export var enemy_marker_scene: PackedScene
@export var health_label: Label
@export var ammo_label: Label
@export var shards_label: Label

func activate_scan_effect():
	var new_scan_effect_scene = scan_effect_scene.instantiate()
	add_child(new_scan_effect_scene)
	move_child(new_scan_effect_scene,0)

func activate_enemy_marker(obj:Node3D, duration: float):
	var target = obj
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen_pos = camera.unproject_position(target.global_position)
	var hud_marker = enemy_marker_scene.instantiate()
	hud_marker.position = Vector2(screen_pos.x, screen_pos.y)
	hud_marker.target = target
	hud_marker.duration = duration
	add_child(hud_marker)
	move_child(hud_marker, 0)


func update_status(health: int, magazine_capacity: int, magazine_size: int, shards:int) -> void:
	health_label.text = "Health: %d" % health
	ammo_label.text = "Ammo: %d / %d" % [magazine_capacity, magazine_size]
	shards_label.text = ": " + str(shards)
