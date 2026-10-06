extends AIGrenadeProjectile
class_name Mine

# ─────────────────────────────────────────────
# A MINE — it lands, it arms, and then it waits for the wrong faction.
#
# Built on AIGrenadeProjectile because everything about getting a lump of
# ordnance onto the ground and crediting its kills is already solved there:
# contact monitoring, continuous collision so it cannot tunnel through a
# heightmap, the blast's source_actor/source_faction pair, the analytics label,
# and level-scoped parenting so it does not outlive the mission.
#
# WHAT IT ADDS IS THE TRIGGER, and the trigger is faction-gated. A mine that
# kills your own squad is a mine nobody places, because in this game the squad
# pathfinds on its own and will walk over anything you put down. So it only
# ever answers to bodies hostile to whoever placed it. That is not realism, it
# is the difference between an item and a trap for the player.
#
# _physics_process is REPLACED rather than extended. The parent's is a fuse —
# it counts up and detonates — and a mine is the opposite: it sits until
# something comes, and when its time runs out it CLEARS rather than going off.
# Calling super() would have given every mine a hidden self-destruct.
# ─────────────────────────────────────────────

## Seconds on the ground before it will answer to anything. The window in which
## you can still walk over your own mine, and the reason a thrown one is not a
## grenade with extra steps.
@export var arm_seconds: float = 1.5
## How close a hostile has to get. Measured to the body's origin, so it is
## roughly ankle-height on a soldier.
@export var trigger_radius: float = 2.2
## Seconds before it clears itself. 0 means it stays for the mission, which is
## what BOTH mines now do: a mine you place is meant to still be there when they
## come, and a timer turns the item into a window you have to spend at exactly
## the right moment rather than ground you can deny.
##
## The usual objection — that area denial which never expires is a map you cannot
## use any more — does not apply here, because _candidates is faction-gated and
## your own squad and the player can walk over these all day.
@export var mine_lifetime: float = 0.0
## Rescans this often rather than every frame. Nothing crosses two metres in
## a tenth of a second, and a mine that is still there in ten minutes should
## not have cost ten minutes of per-frame scanning.
@export var scan_interval: float = 0.1
## Below this speed, once it has touched something, it stops being a physics
## body at all. Scattered submines bounce and roll a long way on a heightmap,
## and area denial that is still travelling is not denying the area you threw
## it at. Freezing also costs nothing: the trigger is a distance scan, not a
## contact, so a frozen mine still works.
@export var settle_speed: float = 0.7
## A hard stop on the rolling, however slowly it is going. Still requires that
## it has hit something — a mine frozen in mid-air is worse than one that rolls.
@export var settle_after: float = 3.0

var _armed: bool = false
var _settled: bool = false
var _life_t: float = 0.0
var _scan_t: float = 0.0


func _ready() -> void:
	super()
	# A mine detonating on the floor it just landed on is a grenade. The parent
	# scene may say otherwise, so this is asserted here rather than trusted.
	explode_on_bounce = false


func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_life_t += delta
	_try_settle()
	if not _armed:
		if _life_t >= arm_seconds:
			_armed = true
		return
	if mine_lifetime > 0.0 and _life_t >= mine_lifetime:
		_clear()
		return
	_scan_t += delta
	if _scan_t < scan_interval:
		return
	_scan_t = 0.0
	if _hostile_in_reach():
		_explode()


func _hostile_in_reach() -> bool:
	for body in _candidates():
		if body == null or not is_instance_valid(body) or not (body is Node3D):
			continue
		if body == _thrower:
			continue
		var living = body.get("alive")
		if living != null and not bool(living):
			continue
		if global_position.distance_to((body as Node3D).global_position) <= trigger_radius:
			return true
	return false


## Everything hostile to whoever laid this, THE PLAYER INCLUDED. The obvious
## version of this walked the `enemies` group, and the player is not in it — so
## an enemy-laid mine would have ignored the one thing it is most likely to be
## laid for. AIManager.hostiles_for() already answers this question for every
## other AI in the game (see diver.gd, which ranks the same list), and it knows
## about the player's targetable state on top.
func _candidates() -> Array:
	var mgr := _ai_manager()
	if mgr != null and mgr.has_method("hostiles_for"):
		return mgr.hostiles_for(_faction())
	var out: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		if n is Node3D and "faction" in n and Enums.are_hostile(_faction(), n.faction):
			out.append(n)
	return out


func _ai_manager() -> Node:
	for n in get_tree().get_nodes_in_group("ai_manager"):
		return n
	return null


## Whose side this mine is on. Taken from whoever placed it, so an enemy
## carrying mines lays mines that answer to YOU without a second scene.
func _faction() -> int:
	if _thrower != null and is_instance_valid(_thrower) and "faction" in _thrower:
		return _thrower.faction
	return Enums.Factions.PLAYER


## Out of time. It goes away rather than going off — a mine that detonates on a
## timer wherever it happens to be is indistinguishable from a bug, and it
## would kill whoever walked past at the wrong second through no decision of
## anyone's.
func _clear() -> void:
	if _exploded:
		return
	_exploded = true
	queue_free()


## Stop being a physics body once it has come to rest.
##
## _bounce_count > 0 is the gate and it is not optional: without it a mine can
## freeze at the top of a bounce, where the speed passes through zero, and hang
## in the air for the rest of the mission. It has to have hit something first.
func _try_settle() -> void:
	if _settled or _exploded:
		return
	if _bounce_count <= 0:
		return
	if linear_velocity.length() > settle_speed and _life_t < settle_after:
		return
	_settled = true
	freeze = true
