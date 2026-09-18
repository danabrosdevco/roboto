extends Node
class_name EnemyForceSpawner

# ─────────────────────────────────────────────
# ENEMY FORCE SPAWNER — builds a mission's opposition from EnemySquadSpecs.
#
# Lives under World so it survives level loads, same as SquadSpawner. Campaign
# calls deploy_force() once the level is in the tree, AFTER the player squad,
# so anything reading the world (an EliminateObjective capturing hostiles in a
# zone) sees a fully populated map.
#
# Resolution is by TAG, looked up in the level's groups. A spec asking for a tag
# the level doesn't have is a warning and a skipped squad, not a crash — maps
# and missions get edited independently and a typo shouldn't take the run down.
# ─────────────────────────────────────────────

@export var world: Node3D
@export var ai_manager: AIManager
@export var default_chassis: PackedScene
@export var squad_scene: PackedScene
# Ring the squad spawns in around its anchor.
@export var spawn_spread: float = 2.0

signal force_deployed(squads: int, hostiles: int)

var _squads: Array[Squad] = []

# RESERVE squads, keyed by the reinforcement_tag that wakes them.
#
# THE TAG IS AN OBJECTIVE ID. A reserve tagged "valley_garrison_cap_2" comes in
# when that objective is completed, so escalation is triggered by what the
# PLAYER did rather than by a clock — which is the whole point of the posture.
# No new field on MissionDefinition and no threshold table: the tag says which
# moment it answers.
var _reserves: Dictionary = {}

# The level reserves will be built into when their tag fires. Held because the
# bodies no longer exist at deploy time, so wake() has nothing else to parent to.
var _level: Node = null

signal reinforcements_woken(tag: StringName, squads: int)


# Every early return here used to be silent, which meant "no enemies spawned"
# and "no warnings" arrived together and told you nothing. They all talk now.
func deploy_force(level: Node, mission: MissionDefinition) -> void:
	clear()
	if level == null:
		push_warning("EnemyForceSpawner: no level — nothing to spawn into.")
		return
	if mission == null:
		push_warning("EnemyForceSpawner: no current mission. Campaign.current_mission is null, which usually means the level was launched directly instead of deployed to from base. See Campaign.debug_mission.")
		return
	_level = level
	if mission.replace_level_enemies:
		_clear_level_hostiles(level)
	if mission.enemy_force.is_empty():
		push_warning("EnemyForceSpawner: mission '%s' has an empty enemy_force." % mission.id)
		return
	print("[EnemyForce] deploying %d spec(s) for mission '%s'" % [mission.enemy_force.size(), mission.id])

	var hostiles := 0
	for spec in mission.enemy_force:
		if spec == null:
			continue
		if spec.body_count() <= 0:
			# Was `spec.count <= 0`, which skipped every roster-form spec.
			# Warned rather than silent: an empty spec is always an authoring
			# mistake, and the failure it produces is a map with no enemies on
			# it, which looks like the spawner being broken.
			push_warning("EnemyForceSpawner: spec '%s' describes 0 bodies (roster empty and count %d). Skipped." % [spec.callsign, spec.count])
			continue
		# RESERVES ARE NOT SPAWNED YET.
		#
		# They used to be built at mission start and merely given a NONE squad
		# objective. That is inert at the SQUAD level only — each body was still
		# a live AI with working sensors, sitting in the world on always_active,
		# so the whole reserve engaged the moment the player wandered into
		# sensor range. Every helicopter arrived at once, hours before the
		# objective that was supposed to call them.
		#
		# Holding the spec and building the bodies in wake() is the only way the
		# posture means what it says. It also stops the player finding parked
		# aircraft at a garrison and shooting them down before they ever fly.
		if spec.posture == EnemySquadSpec.Posture.RESERVE:
			if spec.reinforcement_tag == &"":
				push_warning("EnemyForceSpawner: RESERVE squad '%s' has no reinforcement_tag, so nothing can ever wake it. It will never appear." % spec.callsign)
				continue
			if not _reserves.has(spec.reinforcement_tag):
				_reserves[spec.reinforcement_tag] = []
			_reserves[spec.reinforcement_tag].append(spec)
			continue

		var squad := _spawn_squad(level, spec)
		if squad != null:
			_squads.append(squad)
			hostiles += squad.squad_members.size()
	if not _reserves.is_empty():
		print("[EnemyForce] reserves held: %s" % str(pending_reserve_tags()))
	force_deployed.emit(_squads.size(), hostiles)


# Called by Campaign when an objective completes. Flips any reserve holding
# that tag from inert to ADVANCE on its post.
#
# Returns how many squads it woke, so the caller can tell "no reserves for this
# objective" from "the trigger never fired" — the two look identical otherwise
# and that is exactly the kind of silence this project keeps getting bitten by.
# Which objective ids still have reinforcements waiting on them. Exposed so a
# completed objective that wakes nothing can say WHY: "no reserve is listening
# for this id" and "the completion never reached the spawner" are the same
# silence otherwise, and telling them apart is most of debugging this system.
func pending_reserve_tags() -> Array:
	var out: Array = []
	for t in _reserves:
		out.append(String(t))
	return out


func wake(tag: StringName) -> int:
	if tag == &"" or not _reserves.has(tag):
		return 0
	var entries: Array = _reserves[tag]
	# Erase FIRST. A reserve wakes once; leaving the entry in place would send
	# them in again if the objective re-completed, and a repeatable mission can
	# do exactly that.
	_reserves.erase(tag)

	if _level == null or not is_instance_valid(_level):
		push_warning("EnemyForceSpawner: '%s' called for reinforcements but the level is gone." % tag)
		return 0

	var woken := 0
	for spec in entries:
		# Built HERE, not at mission start. See the RESERVE branch in
		# deploy_force() for why.
		var squad := _spawn_squad(_level, spec)
		if squad == null:
			continue
		_squads.append(squad)
		var post := _find_point(spec.post_tag)
		var destination := post.global_position if post != null else squad.get_center()
		squad.target_objective = post
		squad.set_objective(Squad.SquadObjective.ADVANCE, destination, true)
		woken += 1

	if woken > 0:
		print("[EnemyForce] reinforcements woken by '%s': %d squad(s)" % [tag, woken])
		reinforcements_woken.emit(tag, woken)
	return woken


func _spawn_squad(level: Node, spec: EnemySquadSpec) -> Squad:
	var route := _find_route(spec.route_tag)
	var post := _find_point(spec.post_tag)
	var anchor := _resolve_anchor(spec, route, post)
	if anchor == Vector3.INF:
		# Nearly always a tag typo, so list what the level actually offers
		# rather than making them go hunting.
		push_warning("EnemyForceSpawner: '%s' found no anchor (route_tag=%s post_tag=%s spawn_tag=%s).\n  routes in level: %s\n  points in level: %s" % [
			spec.callsign, spec.route_tag, spec.post_tag, spec.spawn_tag,
			_known_tags("patrol_paths"), _known_tags("squad_objective_points")])
		return null

	# One entry per body, whichever form the spec used.
	var bodies: Array[ChassisDefinition] = _bodies_of(spec)
	if bodies.is_empty():
		push_error("EnemyForceSpawner: no chassis for '%s' and no default_chassis." % spec.callsign)
		return null

	var members: Array[Soldier] = []
	for i in bodies.size():
		var frame: ChassisDefinition = bodies[i]
		if frame == null or frame.scene == null:
			push_error("EnemyForceSpawner: '%s' roster slot %d has no scene." % [spec.callsign, i])
			continue
		var soldier := frame.scene.instantiate() as Soldier
		if soldier == null:
			push_error("EnemyForceSpawner: %s is not a Soldier scene." % frame.scene.resource_path)
			continue
		# Before add_child — AI._ready() runs initialize() and reads these.
		soldier.faction = spec.faction
		soldier.always_active = spec.always_active
		# Numbered across the whole squad rather than per type, so a mixed
		# garrison reads RELAY-1..RELAY-6 instead of RELAY-L-1 / RELAY-M-1.
		soldier.soldier_name = "%s-%d" % [spec.callsign, i + 1]
		_apply_frame(soldier, frame)
		level.add_child(soldier)
		soldier.global_position = anchor + _ring_offset(i, bodies.size())
		if ai_manager != null:
			ai_manager.register_enemy(soldier)
		members.append(soldier)

	if members.is_empty():
		return null

	var squad: Squad = null
	if squad_scene != null:
		# Freed if it is not a Squad. world.tscn had a robot scene in this slot:
		# the cast failed, the fallback below took over, and every hostile squad
		# of every mission left a whole orphaned robot behind — never in the
		# tree, never freed, and the thing the engine tripped over on quit.
		var built := squad_scene.instantiate()
		squad = built as Squad
		if squad == null:
			push_warning("EnemyForceSpawner: squad_scene '%s' is not a Squad; using a plain one." % squad_scene.resource_path)
			built.free()
	if squad == null:
		squad = Squad.new()
	squad.name = "Hostile_%s" % spec.callsign
	squad.callsign = spec.callsign
	squad.player_commandable = false
	# Membership before the node enters the tree — Squad._ready() connects every
	# member's signals and would otherwise connect to an empty array.
	squad.squad_members = members
	level.add_child(squad)

	_apply_posture(squad, spec, route, post)
	return squad


# Flattens either spec form into one entry per body, so the spawn loop has a
# single shape to deal with.
func _bodies_of(spec: EnemySquadSpec) -> Array[ChassisDefinition]:
	var out: Array[ChassisDefinition] = []
	if not spec.roster.is_empty():
		for frame in spec.roster:
			if frame != null:
				out.append(frame)
		return out

	# Legacy count + chassis. Wrapped in a throwaway definition whose stat
	# fields are all zero, which _apply_frame reads as "not specified" and
	# leaves the scene's authored values untouched — the old behaviour exactly.
	var scene: PackedScene = spec.chassis if spec.chassis != null else default_chassis
	if scene == null:
		return out
	var legacy := ChassisDefinition.new()
	legacy.scene = scene
	legacy.base_health = 0
	legacy.base_accuracy = 0.0
	legacy.base_sensor_range = 0.0
	for _i in spec.count:
		out.append(legacy)
	return out


# Stats from the frame, where the frame specifies them.
#
# base_speed is deliberately NOT applied: the enemy scenes author move_speed
# directly (a chaser is 8 m/s, a gunship 14), while base_speed is a multiplier
# from the player-roster side. Multiplying one by the other would quietly make
# every chaser 35% faster than it has ever been.
func _apply_frame(soldier: Soldier, frame: ChassisDefinition) -> void:
	if frame.base_health > 0:
		soldier.max_health = frame.base_health
		soldier.health = frame.base_health
	if frame.base_accuracy > 0.0:
		soldier.accuracy_skill = frame.base_accuracy
	if frame.base_sensor_range > 0.0:
		soldier.sensor_range = frame.base_sensor_range


# Posture is applied AFTER the squad is in the tree, because set_patrol and
# set_objective both read member positions via get_center().
func _apply_posture(squad: Squad, spec: EnemySquadSpec, route: PatrolPath, post: SquadObjectivePoint) -> void:
	match spec.posture:
		EnemySquadSpec.Posture.PATROL:
			if route != null:
				squad.set_patrol(route)
			else:
				squad.set_objective(Squad.SquadObjective.DEFEND, squad.get_center(), true)
		EnemySquadSpec.Posture.GARRISON:
			squad.target_objective = post
			squad.set_objective(Squad.SquadObjective.DEFEND,
				post.global_position if post != null else squad.get_center(), true)
		EnemySquadSpec.Posture.ADVANCE:
			squad.target_objective = post
			squad.set_objective(Squad.SquadObjective.ADVANCE,
				post.global_position if post != null else squad.get_center(), true)
		EnemySquadSpec.Posture.RESERVE:
			# Inert until something wakes them. This is the hook reinforcements
			# will hang off — a director flips them to ADVANCE on a trigger.
			squad.set_objective(Squad.SquadObjective.NONE, squad.get_center(), true)


func _resolve_anchor(spec: EnemySquadSpec, route: PatrolPath, post: SquadObjectivePoint) -> Vector3:
	var base := _anchor_point(spec, route, post)
	if base == Vector3.INF:
		return base
	# Every tag in a level marks a spot on the GROUND, because every tag was
	# written for infantry. Air reinforcements arriving at ground level on top
	# of the position they are meant to attack is both odd to watch and a bad
	# fight. The offset lets a spec say "start well out and well up" without
	# needing a second set of map nodes just for aircraft.
	return base + spec.spawn_offset


func _anchor_point(spec: EnemySquadSpec, route: PatrolPath, post: SquadObjectivePoint) -> Vector3:
	if spec.spawn_tag != &"":
		var explicit := _find_point(spec.spawn_tag)
		if explicit != null:
			return explicit.global_position
	if post != null:
		return post.global_position
	if route != null:
		var first := route.point_at(0)
		if first != null:
			return first.global_position
	return Vector3.INF


func _ring_offset(index: int, total: int) -> Vector3:
	if total <= 1:
		return Vector3.ZERO
	var angle := TAU * (float(index) / float(total))
	return Vector3(cos(angle), 0.0, sin(angle)) * spawn_spread


# ─────────────────────────────────────────────
# TAG LOOKUP
# ─────────────────────────────────────────────
# For error messages. A tag mismatch is the single most likely failure here and
# the fastest fix is seeing both lists side by side.
func _known_tags(group: String) -> Array:
	var tags: Array = []
	for node in get_tree().get_nodes_in_group(group):
		if "tag" in node:
			tags.append(String(node.tag) if node.tag != &"" else "<untagged:%s>" % node.name)
	return tags


func _find_point(tag: StringName) -> SquadObjectivePoint:
	if tag == &"":
		return null
	for node in get_tree().get_nodes_in_group("squad_objective_points"):
		if node is SquadObjectivePoint and node.tag == tag:
			return node
	return null


func _find_route(tag: StringName) -> PatrolPath:
	if tag == &"":
		return null
	for node in get_tree().get_nodes_in_group("patrol_paths"):
		if node is PatrolPath and node.tag == tag:
			return node
	return null


# ─────────────────────────────────────────────
# TEARDOWN
# ─────────────────────────────────────────────
func _clear_level_hostiles(level: Node) -> void:
	for node in get_tree().get_nodes_in_group("squads"):
		if not (node is Squad) or node.player_commandable:
			continue
		if not level.is_ancestor_of(node):
			continue
		# Hostility, not "not commandable". An allied squad placed in the level
		# is also not player_commandable and would otherwise be deleted here.
		if not _is_hostile_squad(node):
			continue
		for member in node.squad_members:
			if member != null and is_instance_valid(member):
				member.queue_free()
		node.queue_free()


func _is_hostile_squad(squad: Squad) -> bool:
	for member in squad.get_living_members():
		return Enums.are_hostile(Enums.Factions.PLAYER, member.faction)
	return false


# Drops references only. The level unload frees the nodes.
func clear() -> void:
	_squads.clear()
	# Holds specs waiting on an objective that will never fire now, and a stale
	# entry would send the next mission's reinforcements into the wrong level.
	_reserves.clear()
	_level = null
