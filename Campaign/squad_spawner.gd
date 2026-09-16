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
# Needed to turn a record's item ids into scenes. Falls back to the campaign's
# catalogue if left blank.
@export var catalogue: ItemCatalogue

# ── WHERE THE SQUAD APPEARS ───────────────────
# SPAWN_POINT        use the level's SquadSpawnPoint, fail if there isn't one
# PLAYER             ignore spawn points, form up on the player
# NEAREST_ELSE_PLAYER  use the spawn point closest to the player, and fall back
#                    to the player if the level has none
#
# The last is the default because it's what you want while iterating: drop a
# spawn point where you want a set-piece arrival, and everywhere else the squad
# just turns up with you instead of silently not deploying.
enum SpawnMode { SPAWN_POINT, PLAYER, NEAREST_ELSE_PLAYER }
@export var spawn_mode: SpawnMode = SpawnMode.NEAREST_ELSE_PLAYER
@export var player: Node3D
# Formation stand-off when forming up on the player.
@export var player_spacing: float = 2.2
@export var player_back_offset: float = 3.0

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

	if player == null and world != null:
		player = world.get("player")

	var point := _pick_spawn_point(level)
	if point == null and spawn_mode != SpawnMode.SPAWN_POINT and player != null:
		# No point, but we know where the player is — form up on them.
		return _deploy_on_player(level, records)
	if point == null:
		# Was silent on the theory that some levels legitimately have no squad.
		# In practice it's always a forgotten node, and silence cost more than
		# the occasional redundant warning.
		push_warning("SquadSpawner: no SquadSpawnPoint in '%s' — your squad will not deploy here." % level.name)
		return null

	var to_deploy: Array[SoldierRecord] = []
	for r in records:
		if r != null and r.is_deployable():
			to_deploy.append(r)
		if point.max_slots > 0 and to_deploy.size() >= point.max_slots:
			break
	if to_deploy.is_empty():
		push_warning("SquadSpawner: no deployable soldiers in the roster (%d total). Check Campaign starting_* exports, and delete user://campaign.json if you changed them." % records.size())
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
		# Back-reference by id. Renaming a record has to reach the body that was
		# built from it, and there's nothing else linking the two.
		soldier.set_meta("record_id", to_deploy[i].id)
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
	# Stats first: max_health is derived from the chassis and fitted modules,
	# and write_to() copies it onto the soldier.
	record.recompute_stats(_catalogue())
	record.write_to(soldier)
	_fit_loadout(soldier, record)
	return soldier


# Turns the record's fitted item ids into actual nodes on the chassis.
func _fit_loadout(soldier: Soldier, record: SoldierRecord) -> void:
	var cat := _catalogue()
	if cat == null:
		return

	# Weapon: only the first slot is used today, but the loop means a future
	# two-weapon frame needs no change here.
	for id_value in record.weapon_ids:
		if id_value == &"":
			continue
		var item := cat.item(id_value)
		if item != null and item.fits_ai():
			soldier.equip_weapon_scene(item.ai_scene)
		break

	# Equipment: the AI carries these as AIEquipmentSlot resources rather than
	# nodes. Built fresh each spawn so two soldiers with the same item don't
	# share a use count.
	var slots: Array[AIEquipmentSlot] = []
	for id_value in record.equipment_ids:
		if id_value == &"":
			continue
		var kit := cat.item(id_value)
		if kit == null or not kit.fits_ai() or kit.ai_scene == null:
			continue
		var slot := AIEquipmentSlot.new()
		slot.equipment_scene = kit.ai_scene
		slot.quantity = kit.quantity
		slots.append(slot)
	if not slots.is_empty():
		soldier.equipment_slots = slots

	# Module health is already folded into record.max_health by
	# recompute_stats(), so adding it again here would double-count it. What's
	# left are the stats the record can't express as a single number.
	if "accuracy_multiplier" in soldier:
		soldier.accuracy_multiplier = record.effective_accuracy
	if "speed_multiplier" in soldier:
		soldier.speed_multiplier = record.effective_speed
	soldier.sensor_range = record.effective_sensor_range
	soldier.sensor_bonus = 0.0   # already folded into the record's value
	if record.effective_signal_bonus != 0.0:
		soldier.signal_integrity = clampf(
			soldier.signal_integrity + record.effective_signal_bonus, 0.0, 1.0)


# CampaignState.squad_name wins over whatever the level author typed on the
# spawn point — it's what the player set, so it has to be what they see in the
# roster header and in every order toast.
func _squad_name(fallback: String) -> String:
	var campaign := get_tree().get_first_node_in_group("campaign")
	if campaign != null and campaign.state != null:
		var chosen: String = campaign.state.squad_name
		if chosen != "":
			return chosen
	return fallback


func _catalogue() -> ItemCatalogue:
	if catalogue != null:
		return catalogue
	var campaign := get_tree().get_first_node_in_group("campaign")
	if campaign != null:
		catalogue = campaign.get("catalogue")
	return catalogue


func _build_squad(point: SquadSpawnPoint, members: Array[Soldier]) -> Squad:
	var squad: Squad = null
	if squad_scene != null:
		squad = squad_scene.instantiate() as Squad
	if squad == null:
		squad = Squad.new()
	squad.name = "PlayerSquad"
	squad.callsign = _squad_name(point.callsign)
	squad.player_commandable = point.player_commandable
	squad.default_objective = point.default_objective
	squad.target_objective = point.target_objective
	# Set membership BEFORE the node enters the tree — Squad._ready() connects
	# every member's signals and would connect to an empty array otherwise.
	squad.squad_members = members
	return squad


# Collects every spawn point rather than taking the first one found. A level
# with several used to silently use whichever came first in the tree, which
# makes the other two look broken.
func _pick_spawn_point(level: Node) -> SquadSpawnPoint:
	if spawn_mode == SpawnMode.PLAYER and player != null:
		return null

	var found: Array[SquadSpawnPoint] = []
	_gather_points(level, found)
	if found.is_empty():
		return null
	if found.size() == 1 or player == null:
		return found[0]

	# Nearest to the player. With several in a level that's almost always the
	# one you meant, and it makes extra points useful instead of inert.
	var best: SquadSpawnPoint = found[0]
	var best_d: float = player.global_position.distance_to(best.global_position)
	for p in found:
		var d: float = player.global_position.distance_to(p.global_position)
		if d < best_d:
			best = p
			best_d = d
	return best


func _gather_points(node: Node, out: Array[SquadSpawnPoint]) -> void:
	if node is SquadSpawnPoint:
		out.append(node)
	for child in node.get_children():
		_gather_points(child, out)


# Form up behind the player, in the same alternating arc SquadSpawnPoint uses.
func _deploy_on_player(level: Node, records: Array[SoldierRecord]) -> Squad:
	var to_deploy: Array[SoldierRecord] = []
	for r in records:
		if r != null and r.is_deployable():
			to_deploy.append(r)
	if to_deploy.is_empty():
		push_warning("SquadSpawner: no deployable soldiers to form up on the player.")
		return null

	var basis := player.global_transform.basis
	var anchor := player.global_position + (basis.z.normalized() * player_back_offset)

	var members: Array[Soldier] = []
	for i in to_deploy.size():
		var soldier := _build_soldier(to_deploy[i])
		if soldier == null:
			continue
		level.add_child(soldier)
		var row := i / 2
		var side := 1.0 if i % 2 == 0 else -1.0
		var offset := Vector3(side * player_spacing * (float(row) * 0.5 + 0.5), 0.0, float(row) * player_spacing)
		soldier.global_position = anchor + (basis * offset)
		if ai_manager != null:
			ai_manager.register_enemy(soldier)
		# Back-reference by id. Renaming a record has to reach the body that was
		# built from it, and there's nothing else linking the two.
		soldier.set_meta("record_id", to_deploy[i].id)
		_spawned[soldier] = to_deploy[i]
		members.append(soldier)

	if members.is_empty():
		return null

	var squad: Squad = null
	if squad_scene != null:
		squad = squad_scene.instantiate() as Squad
	if squad == null:
		squad = Squad.new()
	squad.name = "PlayerSquad"
	squad.callsign = _squad_name("ALPHA")
	squad.player_commandable = true
	squad.default_objective = Squad.SquadObjective.FOLLOW
	squad.squad_members = members
	level.add_child(squad)
	# Straight onto the player's hip, which is the point of spawning here.
	squad.follow(player)
	active_squad = squad
	squad_deployed.emit(squad, members.size())
	print("[SquadSpawner] %d deployed on the player (no spawn point used)" % members.size())
	return squad


# ─────────────────────────────────────────────
# SINGLE-SOLDIER SYNC
# ─────────────────────────────────────────────
# The body standing in the world carries a COPY of the record's health, taken at
# deploy. Repairing the record doesn't touch it, so at base you'd pay to rebuild
# someone and watch them keep standing there at 0/60 — or, if they were
# destroyed, not appear at all because they weren't deployable when the level
# loaded. Both cases are handled here.
func sync_record(record: SoldierRecord) -> Soldier:
	if record == null:
		return null

	var existing := find_body(record)
	if existing != null:
		# Already in the world: push the repaired numbers across, and stand them
		# back up if the repair brought them out of the downed state.
		existing.max_health = record.max_health
		existing.health = record.current_health()
		existing.signal_integrity = record.signal_integrity
		if "downed" in existing and existing.downed and record.is_deployable():
			existing.revive()
		return existing

	# Not in the world. If they're deployable now, they should be.
	if record.is_deployable():
		return spawn_one(record)
	return null


func find_body(record: SoldierRecord) -> Soldier:
	for node in _spawned.keys():
		if _spawned[node] == record and node != null and is_instance_valid(node):
			return node as Soldier
	return null


# Adds one soldier to the squad that's already deployed, beside the others.
func spawn_one(record: SoldierRecord) -> Soldier:
	if not has_squad():
		return null
	var level := active_squad.get_parent()
	if level == null:
		return null

	var soldier := _build_soldier(record)
	if soldier == null:
		return null
	level.add_child(soldier)
	soldier.global_position = _rejoin_position()
	soldier.set_meta("record_id", record.id)
	if ai_manager != null:
		ai_manager.register_enemy(soldier)
	_spawned[soldier] = record
	active_squad.add_ai_to_squad(soldier)
	active_squad.notify_roster_changed()
	return soldier


# Beside the squad, or beside the player if the squad is empty.
func _rejoin_position() -> Vector3:
	var anchor := active_squad.get_center()
	if anchor == Vector3.ZERO and player != null:
		anchor = player.global_position
	var angle := randf() * TAU
	return anchor + Vector3(cos(angle), 0.0, sin(angle)) * 2.0


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
