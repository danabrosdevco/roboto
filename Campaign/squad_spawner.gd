extends Node
class_name SquadSpawner

# ─────────────────────────────────────────────
# SQUAD SPAWNER — records in, Soldiers out, and back again.
#
# Lives under World, NOT under a level, so it survives load_next_level() and can
# collect the squad on the way out of one map and rebuild it in the next.
#
# THE ROUND TRIP
#   deploy_into(level)  finds the level's SquadSpawnPoint, instantiates a
#                       Soldier per deployable record, builds a Squad around
#                       them and registers them with the AIManager.
#   write_back()        reads every spawned Soldier's surviving state into the
#                       record it came from. Call this BEFORE the level unloads
#                       or the nodes are already gone.
#
# This is the piece worth testing first and it needs no UI: hardcode three
# records, deploy, shoot one, write_back, redeploy, and check the damage stuck.
# ─────────────────────────────────────────────

@export var world: Node3D
@export var ai_manager: AIManager
# Used when a record has no chassis_scene of its own.
@export var default_chassis: PackedScene
# Optional. Instantiated for the Squad node; falls back to a bare Squad.
@export var squad_scene: PackedScene

signal squad_deployed(squad: Squad, count: int)
signal squad_collected(survivors: int, lost: int)

var active_squad: Squad = null
# Soldier node -> the record it was built from.
var _spawned: Dictionary = {}


func has_squad() -> bool:
	return active_squad != null and is_instance_valid(active_squad)


# ─────────────────────────────────────────────
# DEPLOY
# ─────────────────────────────────────────────
func deploy_into(level: Node, records: Array[SoldierRecord]) -> Squad:
	clear()
	if level == null:
		return null

	var point := _find_spawn_point(level)
	if point == null:
		# Not an error — a level with no spawn point simply doesn't get a squad.
		return null

	var to_deploy: Array[SoldierRecord] = []
	for r in records:
		if r != null and r.is_deployable():
			to_deploy.append(r)
		if point.max_slots > 0 and to_deploy.size() >= point.max_slots:
			break
	if to_deploy.is_empty():
		return null

	var members: Array[Soldier] = []
	for i in to_deploy.size():
		var soldier := _build_soldier(to_deploy[i])
		if soldier == null:
			continue
		level.add_child(soldier)
		soldier.global_position = point.slot_position(i)
		if ai_manager != null:
			ai_manager.register_enemy(soldier)
		_spawned[soldier] = to_deploy[i]
		members.append(soldier)

	if members.is_empty():
		return null

	active_squad = _build_squad(point, members)
	level.add_child(active_squad)
	squad_deployed.emit(active_squad, members.size())
	return active_squad


func _build_soldier(record: SoldierRecord) -> Soldier:
	var scene: PackedScene = record.chassis_scene if record.chassis_scene != null else default_chassis
	if scene == null:
		push_error("SquadSpawner: no chassis for %s and no default_chassis set." % record.display_name)
		return null
	var soldier := scene.instantiate() as Soldier
	if soldier == null:
		push_error("SquadSpawner: %s is not a Soldier scene." % scene.resource_path)
		return null
	# Before add_child: AI._ready() calls initialize(), which reads max_health
	# and initialises every equipment slot.
	record.write_to(soldier)
	return soldier


func _build_squad(point: SquadSpawnPoint, members: Array[Soldier]) -> Squad:
	var squad: Squad = null
	if squad_scene != null:
		squad = squad_scene.instantiate() as Squad
	if squad == null:
		squad = Squad.new()
	squad.name = "PlayerSquad"
	squad.callsign = point.callsign
	squad.player_commandable = point.player_commandable
	squad.default_objective = point.default_objective
	squad.target_objective = point.target_objective
	# Set membership BEFORE the node enters the tree — Squad._ready() connects
	# every member's signals and would connect to an empty array otherwise.
	squad.squad_members = members
	return squad


func _find_spawn_point(level: Node) -> SquadSpawnPoint:
	if level is SquadSpawnPoint:
		return level
	for child in level.get_children():
		var found := _find_spawn_point(child)
		if found != null:
			return found
	return null


# ─────────────────────────────────────────────
# COLLECT
# ─────────────────────────────────────────────
# Must run while the nodes still exist. A soldier that was freed mid-mission is
# recorded as destroyed rather than silently skipped, or the roster would
# quietly keep anyone who died to something that queue_free()d them.
func write_back() -> Dictionary:
	var survivors := 0
	var lost := 0
	for node in _spawned.keys():
		var record: SoldierRecord = _spawned[node]
		if record == null:
			continue
		if node == null or not is_instance_valid(node):
			record.read_from(null)
			lost += 1
			continue
		var soldier := node as Soldier
		record.read_from(soldier)
		if record.status == SoldierRecord.Status.DESTROYED:
			lost += 1
		else:
			survivors += 1
			record.missions_survived += 1
	squad_collected.emit(survivors, lost)
	return {"survivors": survivors, "lost": lost}


# Drops references without touching the records. The level unload frees the
# nodes themselves.
func clear() -> void:
	_spawned.clear()
	if has_squad():
		active_squad.queue_free()
	active_squad = null
