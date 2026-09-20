extends RigidBody3D
class_name RocketProjectile

# Playtest analytics. By path: see the note in analytics.gd.
const _Analytics := preload("res://Managers/analytics.gd")

# ─────────────────────────────────────────────
# ROCKET — what comes out of the recoilless rifle.
#
# Flies nearly flat and fast and goes off on the first thing it touches. The
# grenade is the other half of this pair: it arcs, bounces and waits on a fuse,
# because a grenade is for something behind cover. This is for something in
# front of you that a rifle cannot finish, so it is direct fire with a blast
# big enough to take a group with it.
#
# The blast is the SAME explosion scene the grenade uses, handed bigger numbers
# on the way in: one set of particles, sound and damage rules for every
# explosion in the game, rather than a second copy that drifts out of step. Its
# radius shape is duplicated first — sub-resources are shared between every
# instance of a scene, and widening the original would widen every frag in the
# level with it.
# ─────────────────────────────────────────────

@export var explosion_scene: PackedScene
@export var explosion_sfx: AudioStreamPlayer3D
@export var mesh: Node3D
@export var trail: Node3D
## What the blast does at the middle, and how far out it reaches.
@export var blast_damage: int = 95
@export var blast_radius: float = 6.0
## Goes off on its own after this long, so a rocket fired at the sky does not
## live in the level forever. At this speed that is still most of a level.
@export var life_seconds: float = 4.0
## Arms this long after launch, so a rocket cannot go off in the firer's face
## by clipping their own body on the way out.
@export var arm_seconds: float = 0.06

var _fired_by: Node = null
var _exploded := false
var _age := 0.0
var _last_at := Vector3.ZERO
var _sweeping := false
var _path := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	# A LIVE ROUND STOPS WHEN THE GAME DOES. Pause behaviour is inherited
	# from whatever this ended up parented to, and the fallback parent when a
	# thrower has no world is the current scene, which is Master, and Master
	# is PROCESS_MODE_ALWAYS so its menus answer while paused. A grenade that
	# landed there kept counting its fuse and went off behind the pause screen.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_path.collide_with_bodies = true
	_path.collide_with_areas = false
	_path.exclude = [get_rid()]


## Who fired it: kept off the blast's damage list and credited with the kills.
func setup(shooter: Node) -> void:
	_fired_by = shooter
	if shooter is CollisionObject3D:
		# Off the sweep as well as the blast, or it goes off on the firer's own
		# capsule in the first metre.
		_path.exclude = [get_rid(), (shooter as CollisionObject3D).get_rid()]


func _physics_process(delta: float) -> void:
	_age += delta
	# Nose follows the flight path, so a rocket in the air reads as going
	# somewhere rather than tumbling.
	var speed := linear_velocity.length()
	if speed > 1.0:
		look_at(global_position + linear_velocity, Vector3.UP)
	# The first frame only records where it started: `_ready` runs on add_child,
	# BEFORE the launcher puts the rocket at the muzzle, so a sweep from the
	# position captured there would run out of the world origin.
	if _sweeping:
		_check_path()
	else:
		_sweeping = true
	_last_at = global_position
	if _age >= life_seconds:
		_explode()


# WHY A SWEEP AND NOT JUST CONTACTS.
#
# This is the fastest thing in the game — two metres between physics ticks,
# which is wider than a robot. contact_monitor only sees what the capsule is
# touching at the end of a tick, so the rocket flew clean through a squad of
# four and went off in the dirt sixty metres behind them. So it also checks the
# line it just flew and goes off at the first thing standing on it, which is
# what the rifle's hitscan does, one frame behind the flight. Contacts stay
# connected for the point-blank case the sweep hasn't started covering yet.
func _check_path() -> void:
	if _exploded or _age < arm_seconds:
		return   # already gone off, or still leaving the tube
	_path.from = _last_at
	_path.to = global_position
	if _path.from.is_equal_approx(_path.to):
		return   # went nowhere this tick: a zero-length ray hits nothing anyway
	var hit := get_world_3d().direct_space_state.intersect_ray(_path)
	if hit.is_empty():
		return
	# Go off where it struck, not where the tick happened to leave it.
	global_position = hit.position
	_explode()


func _on_body_entered(body: Node) -> void:
	if _exploded or _age < arm_seconds:
		return   # already gone off, or still leaving the tube
	if body == _fired_by:
		return   # clipped the firer on the way out
	_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	freeze = true
	if mesh != null:
		mesh.visible = false
	if trail != null and trail.has_method("set_emitting"):
		trail.set_emitting(false)
	if explosion_scene == null:
		push_warning("RocketProjectile: no explosion_scene, so it went off with nothing to show for it.")
		queue_free()
		return

	var blast = explosion_scene.instantiate()
	blast.damage_value = blast_damage
	if _fired_by != null and is_instance_valid(_fired_by):
		blast.source_actor = _fired_by
		if _fired_by.has_method("get_faction"):
			blast.source_faction = _fired_by.get_faction()
	blast.set_meta(&"analytics_cause", _Analytics.label_for_scene(scene_file_path))
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	host.add_child(blast)
	blast.global_position = global_position
	_widen(blast)
	if explosion_sfx != null:
		explosion_sfx.play()
		# Outlives the rocket: freed with it, the bang is cut off at the start.
		remove_child(explosion_sfx)
		host.add_child(explosion_sfx)
		explosion_sfx.global_position = global_position
		explosion_sfx.finished.connect(explosion_sfx.queue_free)
	queue_free()


# The blast's reach, on a shape of this explosion's own. Its radius shape is
# duplicated first — sub-resources are shared between every instance of a
# scene, and widening the original would widen every frag in the level with it.
#
# ONLY THE SPHERE, NOT THE WHOLE NODE. Scaling the explosion so the fireball
# matched the reach was tried and looks broken: the debris pass draws cylinder
# spikes, and at 2.4x they come off the impact as building-sized orange wedges
# across the screen. The fireball stays grenade-sized and the reach is wider
# than it looks, which is the cheaper of the two lies.
func _widen(blast: Node) -> void:
	var area: Area3D = blast.get("damage_area")
	if area == null:
		return   # an explosion with no damage area: nothing to widen
	for child in area.get_children():
		var shape := child as CollisionShape3D
		if shape == null or shape.shape == null:
			continue
		var own := shape.shape.duplicate()
		if own is SphereShape3D:
			(own as SphereShape3D).radius = blast_radius
		shape.shape = own
