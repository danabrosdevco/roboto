extends CharacterBody3D
class_name EnemyTest
@export var faction = Enums.Factions.ENEMY
@export var move_speed: float = 3.0
@export var glide_height: float = 2.0
@export var hover_smoothness: float = 2.0
@export var target_node_path: NodePath  # Assign a player or path node
@export var health = 30
var target: Node3D
var hover_offset := 0.0
var base_y := 0.0

func _ready():
	target = get_node_or_null(target_node_path)
	base_y = global_transform.origin.y
	hover_offset = randf() * TAU  # Randomize starting phase

func _physics_process(delta):
	if target:
		_move_towards_target(delta)
		_apply_hover_effect(delta)

func _move_towards_target(_delta):
	var to_target = (target.global_transform.origin - global_transform.origin)
	to_target.y = 0  # Flatten movement (no vertical chase)
	var direction = to_target.normalized()
	
	velocity = direction * move_speed
	move_and_slide()

func _apply_hover_effect(delta):
	hover_offset += delta
	var height = sin(hover_offset * hover_smoothness) * 0.2
	var pos = global_transform.origin
	pos.y = base_y + height
	global_transform.origin = pos

func apply_damage(damage):
	health -= damage
	if health <= 0:
		die()
	pass

func die():
	await get_tree().create_timer(0.75).timeout
	queue_free()

func get_faction():
	return faction
