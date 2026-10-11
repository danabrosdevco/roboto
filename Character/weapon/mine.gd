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
# ─────────────────────────────────────────────
# MINES WERE THE MOST EXPENSIVE THING IN THE GAME.
#
# In-editor profile of a real firefight: Mine._physics_process 68.56 ms, of a
# 128.16 ms Script Functions total. More than half, and more than every robot
# chassis on the map put together (Soldier 35.96 + Enemy 34.84 + Walker 4.33).
# Nearly all of it was _hostile_in_reach at 0.56 ms a scan.
#
# None of it is the mine count being wrong. mine_lifetime 0 is deliberate — a
# mine stays for the mission, which is what makes laying one a decision — and a
# cluster canister is SUPPOSED to become a field of submines. There were ~232
# live mines and that is the feature working.
#
# It was the scan: every mine walked the whole hostile list, and for each body
# did a string-keyed `get("alive")` and a distance_to() with its square root.
# Four things fixed it, none of which change when a mine goes off:
#   - the list hostiles_for() returns is ALREADY filtered to living bodies, so
#     the per-body alive check was redundant work on every candidate
#   - distance_squared_to against a cached squared radius, no sqrt per body
#   - the AI manager is looked up once, not through a group search per scan
#   - and the scans are STAGGERED, below
# ─────────────────────────────────────────────
## Staggered, not zero. Every mine used to start its scan clock at 0.0, so all
## ~232 of them scanned on the same frame once every scan_interval and the cost
## arrived as a spike rather than a cost. Same reasoning as the robots'
## _stagger_ai_timers.
var _scan_t: float = randf() * 0.1
## Looked up once. _ai_manager() ran a get_nodes_in_group search, per mine, per
## scan.
var _mgr: Node = null
var _mgr_found: bool = false


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


## Nothing sane has more than a handful of bodies inside 2.2 m, and a cap keeps
## a pile-up from turning one scan into a long one.
const MAX_IN_REACH := 8

## Reused, never rebuilt. ai_weapon.gd learned this one already: a query object
## allocated per call, with thirty robots firing, was "the second-hottest path
## in the game allocating for no reason".
var _probe: PhysicsShapeQueryParameters3D = null
var _probe_shape: SphereShape3D = null


# ─────────────────────────────────────────────
# ASK THE BROADPHASE, DON'T WALK THE MAP.
#
# This used to iterate every hostile in the level to find one within 2.2 m —
# 130 bodies, per mine, per scan — which is the wrong shape of work no matter
# how fast the inner loop gets. Trimming it (squared distance, no redundant
# alive check, cached manager) took it from 155 to 68 us, and 68 us x 232 mines
# is still 2.6 ms a frame.
#
# A shape query costs one broadphase lookup and returns the two or three things
# actually near the mine. The spatial filtering happens in C++, where it is
# already being done for everything else in the world.
#
# NOT an Area3D per mine, which was the other candidate: 232 more monitored
# areas is 232 more things the physics server reconciles every step, and that
# is the cost this is trying to avoid. A one-Area3D-per-cluster variant would
# fix that, but submines "bounce and roll a long way on a heightmap" (see
# scatter_speed), so a shared bound would have to be huge and would wake the
# whole field for anything near any part of it. The query has no such problem:
# it is exact, per mine, and costs nothing while nothing is near.
#
# Filtering by TYPE rather than by collision mask, which is the convention
# Enemy.force_check_detection already uses — characters and terrain are both on
# layer 1 here, so a mask cannot separate them and a guess would mean a mine
# that never fires.
# ─────────────────────────────────────────────
func _hostile_in_reach() -> bool:
	var space: PhysicsDirectSpaceState3D = null
	if is_inside_tree():
		space = get_world_3d().direct_space_state
	if space == null:
		return _hostile_in_reach_by_list()   # no space to ask; fall back
	if _probe == null:
		_probe_shape = SphereShape3D.new()
		_probe = PhysicsShapeQueryParameters3D.new()
		_probe.shape = _probe_shape
		_probe.collide_with_bodies = true
		_probe.collide_with_areas = false
		_probe.exclude = [get_rid()]   # never trigger on itself
	# trigger_radius is an export and may be tuned at runtime.
	if not is_equal_approx(_probe_shape.radius, trigger_radius):
		_probe_shape.radius = trigger_radius
	_probe.transform = global_transform
	for hit in space.intersect_shape(_probe, MAX_IN_REACH):
		var body = hit.get("collider")
		if body == null or not is_instance_valid(body) or body == _thrower:
			continue
		# Terrain and debris are in here too; only something with a side counts.
		if not ("faction" in body):
			continue
		if not Enums.are_hostile(_faction(), body.faction):
			continue
		var living = body.get("alive")
		if living != null and not bool(living):
			continue
		return true
	return false


## The original scan, kept for the case where there is no physics space to ask
## — a mine measured outside the tree, or a headless rig without a world.
func _hostile_in_reach_by_list() -> bool:
	# Squared, so the inner loop has no square root in it. trigger_radius is an
	# export and can be changed at runtime, so it is squared here rather than
	# cached in _ready.
	var reach_sq: float = trigger_radius * trigger_radius
	var here: Vector3 = global_position
	# `filtered` is true when the list came from AIManager.hostiles_for(), which
	# has ALREADY dropped anything dead, untargetable or not hostile. Re-testing
	# `alive` through a string-keyed get() on every body, every scan, was most of
	# what made this the hottest function in the game. The fallback path below
	# is not filtered, so it still gets the full check.
	var filtered: bool = _hostiles_are_filtered
	for body in _candidates():
		if body == null or not is_instance_valid(body) or not (body is Node3D):
			continue
		if body == _thrower:
			continue
		if not filtered:
			var living = body.get("alive")
			if living != null and not bool(living):
				continue
		if here.distance_squared_to((body as Node3D).global_position) <= reach_sq:
			return true
	return false


## Set by _candidates(): true when the list came from AIManager and is already
## filtered to living, targetable, hostile bodies.
var _hostiles_are_filtered: bool = false


## Everything hostile to whoever laid this, THE PLAYER INCLUDED. The obvious
## version of this walked the `enemies` group, and the player is not in it — so
## an enemy-laid mine would have ignored the one thing it is most likely to be
## laid for. AIManager.hostiles_for() already answers this question for every
## other AI in the game (see diver.gd, which ranks the same list), and it knows
## about the player's targetable state on top.
func _candidates() -> Array:
	var mgr := _ai_manager()
	if mgr != null and mgr.has_method("hostiles_for"):
		_hostiles_are_filtered = true
		return mgr.hostiles_for(_faction())
	_hostiles_are_filtered = false
	var out: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		if n is Node3D and "faction" in n and Enums.are_hostile(_faction(), n.faction):
			out.append(n)
	return out


## Resolved once and remembered. This ran a get_nodes_in_group search for every
## mine on every scan; with ~232 mines that is 232 tree searches a tenth of a
## second for a node that never changes. `_mgr_found` rather than a null check
## so a level genuinely without a manager does not re-search forever.
func _ai_manager() -> Node:
	if _mgr_found and is_instance_valid(_mgr):
		return _mgr
	# ONLY A HIT IS CACHED. Remembering a miss is how this went wrong in the
	# first place: nothing was in the "ai_manager" group at all, every mine
	# concluded there was no manager, and every scan took the slow path for the
	# whole mission. A miss here is cheap — it happens at most once a
	# scan_interval — and re-asking means a manager that arrives late is found.
	for n in get_tree().get_nodes_in_group("ai_manager"):
		_mgr = n
		_mgr_found = true
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
