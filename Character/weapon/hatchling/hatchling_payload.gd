extends Node3D
class_name HatchlingPayload

# ─────────────────────────────────────────────
# HATCHLING PAYLOAD — the canister bursts and something climbs out of it.
#
# Spawned by AIGrenadeProjectile exactly where a frag's Explosion would be, and
# it takes the same source_actor / source_faction pair. So a Hatchling Charge is
# just a grenade whose explosion_scene is this: no new projectile code, and it
# inherits the impact fusing and level-scoped parenting the bombs already use.
#
# What comes out is the ordinary hopper chassis on the THROWER'S side — the same
# unit the enemy fields, turned around. It is already aggressive and already
# leaps, so it needs no new AI: it is released, pointed at the nearest hostile,
# and left to it. It lives for `lifetime` seconds and then falls apart.
#
# Whoever throws it owns it — an enemy squad carrying Hatchling Charges would
# release hoppers of its own, which is exactly right.
# ─────────────────────────────────────────────

## The unit that climbs out. The hopper by default; anything that is a Soldier
## scene works.
@export var unit_scene: PackedScene
## How many. More than one turns it into a swarm charge.
@export var count: int = 1
## Seconds before a released unit shuts down. It is a charge, not a recruit.
@export var lifetime: float = 25.0
## How far it looks for its first target. Wider than its own sensors on purpose:
## the throw IS the order, so it should go after something even when the player
## lobbed it toward a fight it cannot personally see yet.
@export var seek_radius: float = 45.0

var source_actor: Node = null
var source_faction: Enums.Factions = Enums.Factions.NEUTRAL


func _ready() -> void:
	# Deferred: this runs inside the projectile's detonation, and adding bodies
	# to the level mid-physics-callback is the kind of thing that works until it
	# doesn't. One frame costs nothing here.
	_release.call_deferred()


func _release() -> void:
	if unit_scene == null:
		push_warning("HatchlingPayload: no unit_scene — the canister burst and nothing came out.")
		queue_free()
		return
	var level := get_parent()
	var manager := _find_ai_manager()
	var faction := source_faction if source_faction != Enums.Factions.NEUTRAL else Enums.Factions.PLAYER

	for i in maxi(1, count):
		var unit := unit_scene.instantiate() as Soldier
		if unit == null:
			push_warning("HatchlingPayload: %s is not a Soldier scene." % unit_scene.resource_path)
			break
		# All of this BEFORE add_child. FactionLivery reads `faction` in its own
		# _ready, so setting it afterwards would paint a player-side hatchling in
		# enemy amber — and a friendly that looks hostile gets shot by you.
		unit.faction = faction
		unit.soldier_name = "HATCHLING"
		unit.always_active = true
		# Its kills are the thrower's. See Enemy.credit_kills_to.
		if source_actor != null and is_instance_valid(source_actor):
			unit.credit_kills_to = source_actor
		# Temporary. A hatchling that went down and waited for a repair tool
		# would just be a wreck you have to walk over to.
		if "can_be_downed" in unit:
			unit.can_be_downed = false
		level.add_child(unit)
		unit.global_position = global_position + Vector3(randf_range(-0.8, 0.8), 0.4, randf_range(-0.8, 0.8))
		# Without registration it has no `player` reference, and Enemy's
		# physics tick returns immediately when that is null: it would sit on
		# the grass doing nothing for its whole life.
		if manager != null:
			manager.register_enemy(unit)
		_sic(unit, faction)
		_expire_later(unit)

	queue_free()


# THE THROW IS THE ORDER. Point it at the nearest hostile straight away rather
# than waiting for its own perception to notice something — that is what makes
# it feel sent rather than dropped.
func _sic(unit: Soldier, faction: Enums.Factions) -> void:
	var best: Node3D = null
	var best_d := seek_radius
	for n in get_tree().get_nodes_in_group("enemies"):
		if n == unit or not (n is Node3D) or not is_instance_valid(n):
			continue
		if "alive" in n and not n.alive:
			continue
		if not n.has_method("get_faction") or not Enums.are_hostile(faction, n.get_faction()):
			continue
		var d := global_position.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n
	if best != null and unit.has_method("trigger_combat"):
		unit.trigger_combat(best)


func _expire_later(unit: Soldier) -> void:
	var timer := get_tree().create_timer(lifetime, false)
	timer.timeout.connect(func():
		if is_instance_valid(unit) and unit.alive and unit.has_method("destroy"):
			unit.destroy())


func _find_ai_manager() -> Node:
	for n in get_tree().get_nodes_in_group("ai_manager"):
		return n
	return _search(get_tree().root)


func _search(node: Node) -> Node:
	if node is AIManager:
		return node
	for c in node.get_children():
		var f := _search(c)
		if f != null:
			return f
	return null
