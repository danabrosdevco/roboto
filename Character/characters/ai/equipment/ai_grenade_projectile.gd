extends RigidBody3D
class_name AIGrenadeProjectile

# Playtest analytics. By path: see the note in analytics.gd.
const _Analytics := preload("res://Managers/analytics.gd")

# ─────────────────────────────────────────────
# AI GRENADE PROJECTILE
# Physics-based grenade. Thrown with a computed
# arc velocity, bounces off geometry, explodes
# on a timer or on impact after first bounce.
# ─────────────────────────────────────────────

@export var explosion_scene: PackedScene
@export var explosion_sfx: AudioStreamPlayer3D
## Overrides the blast's own damage_value. Left at 0 the explosion keeps what
## its scene says. One projectile scene is shared by the hand grenade, the
## launcher, the turret and the bombers, so a round that should hit softer
## dials it here rather than forking explosion.tscn and letting the two copies
## drift apart the next time the VFX change.
@export var blast_damage: int = 0
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
## What the playtest log should call this round's blast. Empty means "whatever
## my scene is", which for a thrown grenade is right. A launcher sets its own
## so its damage files under the same name as its shots. A plain var rather
## than an export on purpose: this scene is instanced by six other scenes, and
## an editor left open writes a new export's default into every one of them.
var analytics_label: String = ""
## Overrides how far the blast reaches. 0 keeps the explosion's own — a hand
## grenade's. Set by a launcher, and a plain var for the same reason as
## analytics_label. Widens the damage area only: scaling the explosion node
## itself scales its debris too, into building-sized wedges.
var blast_radius: float = 0.0


func _ready() -> void:
	# A LIVE ROUND STOPS WHEN THE GAME DOES. Pause behaviour is inherited
	# from whatever this ended up parented to, and the fallback parent when a
	# thrower has no world is the current scene, which is Master, and Master
	# is PROCESS_MODE_ALWAYS so its menus answer while paused. A grenade that
	# landed there kept counting its fuse and went off behind the pause screen.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# explode_on_bounce was DEAD. body_entered is connected in the scene, but a
	# RigidBody3D only emits it with contact_monitor on and a nonzero contact
	# budget, and this scene set neither — so the signal never fired and no
	# grenade in the game could detonate on impact. Harmless to enable for the
	# fused kind: with explode_on_bounce off it only counts bounces.
	contact_monitor = true
	max_contacts_reported = maxi(max_contacts_reported, 4)
	# AND THE CONTACT HAS TO HAPPEN AT ALL. Without continuous collision a
	# round covers its speed/60 per physics tick, and whenever that is more
	# than it is thick it can be above a surface one tick and below it the
	# next, touching nothing. The valley floor is a heightmap with no thickness
	# at all. The mortar round (0.2m across, down at 29 m/s: 0.48m a tick) went
	# through the ground about half the time — no bang, gone. The Rover's
	# launcher (32 m/s), the bombers' drops and every EMP and hatchling pod
	# are this scene too, and a slope or a wall facing them is the same miss.
	continuous_cd = true
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
		if blast_damage > 0:
			blast.damage_value = blast_damage
		if blast_radius > 0.0:
			_widen(blast)
		# Hand the blast its owner BEFORE it enters the tree — the damage area
		# can fire on the same frame it is added. Without this the explosion
		# credited itself, so nobody scored the kill, and source_faction stayed
		# NEUTRAL, which meant the friendly-fire multiplier never applied and
		# your own squad took full blast damage.
		if _thrower != null and is_instance_valid(_thrower):
			blast.source_actor = _thrower
			if _thrower.has_method("get_faction"):
				blast.source_faction = _thrower.get_faction()
		# So the playtest log scores the blast as a frag, not as whatever the
		# thrower happens to be holding by the time it goes off.
		#
		# UNLESS SOMETHING LAUNCHED IT. This scene is the round for the hand
		# grenade AND for both launchers, so scoring it by its own filename
		# credited every launcher blast to "Frag" — which is why the ally
		# weapon table read "Grenade Launcher: 807 shots, 0 damage, 0 kills"
		# while Frag showed 132 kills off 32 throws. The shots were filed under
		# the weapon and the damage under the round, and the two never met.
		blast.set_meta(&"analytics_cause", analytics_label if analytics_label != ""
			else _Analytics.label_for_scene(scene_file_path))
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
# The damage sphere at blast_radius, on this blast only. The shape is shared by
# every explosion instanced from the scene, so it is duplicated before it is
# touched — resizing the original would widen every frag in the level.
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


func _level() -> Node:
	if get_parent() != null:
		return get_parent()
	if get_tree().current_scene != null:
		return get_tree().current_scene
	return get_tree().root
