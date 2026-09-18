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
var _exploded: bool = false
var _indicator_instance: Node3D = null
var _thrower: Node = null  # set by AIGrenade so we don't damage ourselves


func _ready() -> void:
	# explode_on_bounce was DEAD. body_entered is connected in the scene, but a
	# RigidBody3D only emits it with contact_monitor on and a nonzero contact
	# budget, and this scene set neither — so the signal never fired and no
	# grenade in the game could detonate on impact. Harmless to enable for the
	# fused kind: with explode_on_bounce off it only counts bounces.
	contact_monitor = true
	max_contacts_reported = maxi(max_contacts_reported, 4)
	# Spawn landing indicator
	if indicator_scene != null:
		_indicator_instance = indicator_scene.instantiate()
		_level().add_child(_indicator_instance)
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
	# Never on another grenade. Two charges touching in the air is not an
	# impact with anything, and a stick of impact-fused bombs released on one
	# trajectory used to set each other off the instant they left the drone.
	if body.get_script() == get_script():
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
		var blast = explosion_scene.instantiate()
		# Hand the blast its owner BEFORE it enters the tree — the damage area
		# can fire on the same frame it is added. Without this the explosion
		# credited itself, so nobody scored the kill, and source_faction stayed
		# NEUTRAL, which meant the friendly-fire multiplier never applied and
		# your own squad took full blast damage.
		if _thrower != null and is_instance_valid(_thrower):
			blast.source_actor = _thrower
			if _thrower.has_method("get_faction"):
				blast.source_faction = _thrower.get_faction()
		_level().add_child(blast)
		blast.global_position = global_position
		explosion_sfx.play()
		mesh.queue_free()
		freeze = true


# Whatever this grenade was dropped INTO — the level — rather than
# get_tree().current_scene, which in this project is Master. Parenting the blast
# and the landing marker to Master put them above World, so they outlived the
# level they belonged to, and made both depend on there being a current scene
# at all.
func _level() -> Node:
	if get_parent() != null:
		return get_parent()
	if get_tree().current_scene != null:
		return get_tree().current_scene
	return get_tree().root
