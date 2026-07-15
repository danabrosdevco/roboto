extends RigidBody3D
class_name AIGrenadeProjectile

# ─────────────────────────────────────────────
# AI GRENADE PROJECTILE
# Physics-based grenade. Thrown with a computed
# arc velocity, bounces off geometry, explodes
# on a timer or on impact after first bounce.
# ─────────────────────────────────────────────

@export var explosion_scene: PackedScene
@export var explosion_sfx: AudioStreamPlayer3D
@export var fuse_time: float = 3.0         # seconds before exploding regardless
@export var explode_on_bounce: bool = false # if true, explodes on first geometry hit
@export var bounce_before_explode: int = 1  # bounces to allow before arming
# Landing indicator — optional, assign a PackedScene with a flat circle mesh
@export var indicator_scene: PackedScene
@export var mesh: Node3D

var _fuse_timer: float = 0.0
var _bounce_count: int = 0
var _armed: bool = false
var _exploded: bool = false
var _indicator_instance: Node3D = null
var _thrower: Node = null  # set by AIGrenade so we don't damage ourselves


func _ready() -> void:
	# Spawn landing indicator
	if indicator_scene != null:
		_indicator_instance = indicator_scene.instantiate()
		get_tree().current_scene.add_child(_indicator_instance)
	explosion_sfx.finished.connect(queue_free)
func setup(thrower: Node) -> void:
	_thrower = thrower

func _physics_process(delta: float) -> void:
	if _exploded:
		return

	_fuse_timer += delta

	# Update landing indicator to follow grenade's XZ position on the ground
	if _indicator_instance != null and _indicator_instance.is_inside_tree():
		var cast_from = global_position
		var cast_to = global_position + Vector3.DOWN * 20.0
		var space = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(cast_from, cast_to)
		query.exclude = [self]
		var result = space.intersect_ray(query)
		if result:
			_indicator_instance.global_position = result.position + Vector3.UP * 0.02

	if _fuse_timer >= fuse_time:
		_explode()

func _on_body_entered(body: Node) -> void:
	if _exploded:
		return
	if body == _thrower or body == self:
		return

	_bounce_count += 1

	if explode_on_bounce and _bounce_count > bounce_before_explode:
		_explode()

func _explode() -> void:
	if _exploded:
		return
	_exploded = true

	# Remove landing indicator
	if _indicator_instance != null and _indicator_instance.is_inside_tree():
		_indicator_instance.queue_free()

	if explosion_scene != null:
		var exp = explosion_scene.instantiate()
		get_tree().current_scene.add_child(exp)
		exp.global_position = global_position
		explosion_sfx.play()
		mesh.queue_free()
		freeze = true
