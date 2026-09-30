extends RigidBody3D

# ─────────────────────────────────────────────
# THE QUADCOPTER'S BOMB — falls, hits something, goes off.
#
# IT DID NOT GO OFF ON THE GROUND, and the reason is a Godot rule rather than
# anything in this file: a RigidBody3D emits `body_entered` / `body_shape_entered`
# ONLY when contact_monitor is on and max_contacts_reported is above zero. The
# scene connected both signals and set neither property, so both handlers were
# wired to something that never fired. What was left was the Area3D's own
# body_entered — an Area3D reports contacts regardless — and that box is a
# proximity fuse hanging below the bomb, so a bomb that fell past the edge of
# it, or landed on a slope, simply lay there.
#
# Switched on in code rather than in the scene on purpose: it is a correctness
# requirement, not a tuning value, and a scene re-save must not be able to
# quietly turn the fuse off again.
#
# ONCE. Three signals are connected into this script and two of them can fire
# on the same frame; `_spent` is what stops a bomb detonating twice and putting
# two explosions on one crater.
# ─────────────────────────────────────────────

@export var explosion_scene: PackedScene
@export var explosion_radius: float = 6.0
@export var explosion_damage: int = 50
## How many contacts the body reports. Anything above zero turns the signals on;
## a few, so landing in a corner against several faces still registers.
@export var contacts_reported: int = 4

var impact_position: Vector3
var _spent := false


func _ready() -> void:
	# See the note above: without these two the contact signals never fire.
	contact_monitor = true
	max_contacts_reported = maxi(1, contacts_reported)
	if explosion_scene == null:
		push_warning("%s has no explosion_scene, so it will fall, land and do nothing." % name)


func _on_body_entered(body: Node) -> void:
	_detonate(body)


func _on_body_shape_entered(_body_rid: RID, body: Node, _body_shape_index: int,
		_local_shape_index: int) -> void:
	_detonate(body)


## Everything that hits anything ends up here. `body` is only used to rule out
## the bomb finding itself; what it struck does not change what it does.
func _detonate(body: Node) -> void:
	if _spent or body == self:
		return
	_spent = true
	impact_position = global_position
	# STOP BEING A PHYSICS OBJECT FIRST. The explosion is parented to the level
	# and outlives this node, so the bomb can go immediately — but it must not
	# bounce, roll or report a second contact in the frame between now and being
	# freed.
	freeze = true
	set_deferred(&"contact_monitor", false)
	_explode()
	queue_free()


func _explode() -> void:
	if explosion_scene == null:
		return   # warned about in _ready; nothing to spawn
	var explosion_instance: Node3D = explosion_scene.instantiate()
	# current_scene is Master in this project — above World, so the blast is not
	# freed with the bomb's parent. Same host the AI grenade uses.
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	if host == null:
		return   # nothing to parent a blast to: the level is going away anyway
	host.add_child(explosion_instance)
	explosion_instance.global_position = impact_position
