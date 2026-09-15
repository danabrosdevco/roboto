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
	if mission.replace_level_enemies:
		_clear_level_hostiles(level)
	if mission.enemy_force.is_empty():
		push_warning("EnemyForceSpawner: mission '%s' has an empty enemy_force." % mission.id)
		return
	print("[EnemyForce] deploying %d spec(s) for mission '%s'" % [mission.enemy_force.size(), mission.id])

	var hostiles := 0
	for spec in mission.enemy_force:
		if spec == null or spec.count <= 0:
			continue
		var squad := _spawn_squad(level, spec)
		if squad != null:
			_squads.append(squad)
			hostiles += squad.squad_members.size()
	force_deployed.emit(_squads.size(), hostiles)


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

	var scene: PackedScene = spec.chassis if spec.chassis != null else default_chassis
	if scene == null:
		push_error("EnemyForceSpawner: no chassis for '%s' and no default_chassis." % spec.callsign)
		return null

	var members: Array[Soldier] = []
	for i in spec.count:
		var soldier := scene.instantiate() as Soldier
		if soldier == null:
			push_error("EnemyForceSpawner: %s is not a Soldier scene." % scene.resource_path)
			break
		# Before add_child — AI._ready() runs initialize() and reads these.
		soldier.faction = spec.faction
		soldier.always_active = spec.always_active
		soldier.soldier_name = "%s-%d" % [spec.callsign, i + 1]
		level.add_child(soldier)
		soldier.global_position = anchor + _ring_offset(i, spec.count)
		if ai_manager != null:
			ai_manager.register_enemy(soldier)
		members.append(soldier)

	if members.is_empty():
		return null

	var squad: Squad = null
	if squad_scene != null:
		squad = squad_scene.instantiate() as Squad
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
