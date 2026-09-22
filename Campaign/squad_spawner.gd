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

## Stands each deployed robot on the real ground: see ground_snap.gd. By path,
## not class_name, so an open editor never compiles this before it exists.
const _Ground := preload("res://Campaign/ground_snap.gd")

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

# Your first team in the field. What everything that expects one squad is
# handed.
var active_squad: Squad = null
# Every team deployed: one squad per team on the squad page (CampaignState
# .teams), in its order, so each can be given orders of its own.
var squads: Array[Squad] = []
# Soldier node -> the record it was built from.
var _spawned: Dictionary = {}
# What a team is called if the campaign has no name for it — only a robot the
# campaign does not know about, a test rig's, ever needs this.
var _callsign_base: String = "ALPHA"

## How far behind you a team of vehicles follows at the least — well back of
## the robots on foot, so a rover is not threading through their line.
@export var armor_follow_distance: float = 10.0
## Each team in the field follows this much further back than the one before
## it, so their formations do not end up on the same patch of ground.
@export var team_follow_step: float = 5.0


func has_squad() -> bool:
	for squad in squads:
		if squad != null and is_instance_valid(squad):
			return true
	return false


func _state() -> CampaignState:
	var campaign := get_tree().get_first_node_in_group("campaign")
	return campaign.get("state") as CampaignState if campaign != null else null


# Which team a robot goes in with: the one it is in on the squad page. A record
# the campaign does not hold keeps whatever team it names.
func _team_of(record: SoldierRecord) -> StringName:
	var state := _state()
	if state != null and record != null and state.roster.has(record):
		return state.team_of(record)
	return record.team_id if record != null and record.team_id != &"" else &"t1"


# Where a team comes in the squad page's list. One the campaign does not know
# goes after all of those.
func _team_rank(team_id: StringName) -> int:
	var state := _state()
	var at := state.team_ids().find(team_id) if state != null else -1
	return at if at >= 0 else CampaignState.MAX_TEAMS


func _team_label(team_id: StringName) -> String:
	var state := _state()
	var label := state.team_name(team_id) if state != null else ""
	return label if label != "" else _callsign_base


# The deployed bodies by team, in the squad page's order. Teams with nobody
# deployed are left out.
func _split_by_team(members: Array[Soldier]) -> Array:
	var by_team := {}
	var order: Array[StringName] = []
	for soldier in members:
		var team_id := _team_of(_spawned.get(soldier))
		if not by_team.has(team_id):
			var crew: Array[Soldier] = []
			by_team[team_id] = crew
			order.append(team_id)
		(by_team[team_id] as Array).append(soldier)
	order.sort_custom(func(a: StringName, b: StringName) -> bool: return _team_rank(a) < _team_rank(b))
	var out := []
	for team_id in order:
		out.append([team_id, by_team[team_id]])
	return out


func _squad_of_team(team_id: StringName) -> Squad:
	for squad in squads:
		if squad != null and is_instance_valid(squad) and squad.team == team_id:
			return squad
	return null


func _new_squad(team_id: StringName, members: Array[Soldier]) -> Squad:
	var squad: Squad = null
	if squad_scene != null:
		squad = squad_scene.instantiate() as Squad
	if squad == null:
		squad = Squad.new()
	squad.name = "PlayerTeam_%s" % team_id
	squad.team = team_id
	# What it follows at before its place in the order is added: _style_teams
	# works from this every time, rather than from what it last set.
	squad.set_meta(&"own_follow_distance", squad.follow_distance)
	# Set membership BEFORE the node enters the tree — Squad._ready() connects
	# every member's signals and would connect to an empty array otherwise.
	squad.squad_members = members
	return squad


# Everything about a team's squad that comes from the squad page: its name, its
# place in the order, how far back it follows you and whether it is all
# vehicles. After any change to who is in which squad, and after a rename.
func _style_teams() -> void:
	var live: Array[Squad] = []
	for squad in squads:
		if squad != null and is_instance_valid(squad):
			live.append(squad)
	live.sort_custom(func(a: Squad, b: Squad) -> bool: return _team_rank(a.team) < _team_rank(b.team))
	for i in live.size():
		var squad := live[i]
		squad.callsign = _team_label(squad.team)
		squad.team_rank = _team_rank(squad.team)
		squad.vehicles_only = _all_vehicles(squad)
		var back: float = float(squad.get_meta(&"own_follow_distance", squad.follow_distance)) + team_follow_step * i
		squad.follow_distance = maxf(back, armor_follow_distance) if squad.vehicles_only else back


func _all_vehicles(squad: Squad) -> bool:
	var cat := _catalogue()
	var any := false
	for m in squad.squad_members:
		if m == null or not is_instance_valid(m):
			continue
		var record: SoldierRecord = _spawned.get(m)
		var frame: ChassisDefinition = cat.chassis_def(record.chassis_id) if cat != null and record != null else null
		if frame == null or not frame.vehicle:
			return false
		any = true
	return any


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

	# will_deploy, not is_deployable: benched robots stay home even if a caller
	# hands over the whole roster rather than CampaignState.deployable().
	var to_deploy: Array[SoldierRecord] = []
	for r in records:
		if r != null and r.will_deploy():
			to_deploy.append(r)
		if point.max_slots > 0 and to_deploy.size() >= point.max_slots:
			break
	if to_deploy.is_empty():
		# Everyone benched is a legitimate choice (a solo run), so it is only a
		# warning, and the message says the bench is one reason it can happen.
		push_warning("SquadSpawner: nobody to deploy (%d offered). Either every robot is benched or wrecked in the squad manager, or the roster is empty — check Campaign starting_* exports, and delete user://campaign.json if you changed them." % records.size())
		return null

	var members: Array[Soldier] = []
	for i in to_deploy.size():
		var soldier := _build_soldier(to_deploy[i])
		if soldier == null:
			continue
		# Placed before it enters the tree: see the note in
		# enemy_force_spawner.gd. A body that readies at the level origin shares
		# that spot with everything else spawned this frame, and their Detection
		# areas hand each other combat targets they will never be able to see.
		# ...and stood on the ground there: the slots are laid out flat behind the
		# marker, and on a slope the far ones started underground.
		soldier.position = level.to_local(_Ground.stand(point.slot_position(i), soldier, level))
		level.add_child(soldier)
		if ai_manager != null:
			ai_manager.register_enemy(soldier)
		# Back-reference by id. Renaming a record has to reach the body that was
		# built from it, and there's nothing else linking the two.
		soldier.set_meta("record_id", to_deploy[i].id)
		_spawned[soldier] = to_deploy[i]
		members.append(soldier)

	if members.is_empty():
		return null

	_callsign_base = point.callsign
	for part in _split_by_team(members):
		var squad := _build_squad(point, part[1], part[0])
		level.add_child(squad)
		squads.append(squad)
	_style_teams()
	active_squad = squads[0]
	print("[SquadSpawner] %d deployed at spawn point '%s' (%s, objective %d), %d team(s)" % [
		members.size(), point.callsign, str(point.global_position.round()),
		point.default_objective, squads.size(),
	])
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
	# These wrote to accuracy_multiplier and speed_multiplier, neither of which
	# exists on any character script — the `in` guard meant both assignments
	# were skipped every single time, silently, so the armoury's accuracy and
	# speed stats have never done anything at all.
	#
	# MULTIPLY, don't assign. accuracy_skill is authored per chassis (0.75 on a
	# line trooper) and the record's effective_accuracy is a 1.0-baseline
	# modifier; assigning it would hand every squad member a flat accuracy
	# upgrade the moment this started working. Multiplying is a no-op at 1.0,
	# so current balance is untouched and only fitted modules move the number.
	soldier.accuracy_skill *= record.effective_accuracy
	soldier.move_speed *= record.effective_speed
	soldier.sensor_range = record.effective_sensor_range
	soldier.sensor_bonus = 0.0   # already folded into the record's value
	# ADDED to the chassis' own value rather than assigned, the same rule as
	# accuracy: a frame may already carry resistance of its own, and a module
	# that replaced it could make a sturdy chassis worse.
	soldier.signal_resistance += record.effective_signal_resistance_bonus
	soldier.self_revive_seconds = record.effective_self_revive
	soldier.suppressive_fire = record.effective_suppressive
	if record.effective_signal_bonus != 0.0:
		soldier.signal_integrity = clampf(
			soldier.signal_integrity + record.effective_signal_bonus, 0.0, 1.0)


func _catalogue() -> ItemCatalogue:
	if catalogue != null:
		return catalogue
	var campaign := get_tree().get_first_node_in_group("campaign")
	if campaign != null:
		catalogue = campaign.get("catalogue")
	return catalogue


# Every team takes the spawn point's orders, so at the start they all set off
# for the same objective, as one squad used to.
func _build_squad(point: SquadSpawnPoint, members: Array[Soldier], team_id: StringName) -> Squad:
	var squad := _new_squad(team_id, members)
	squad.player_commandable = point.player_commandable
	squad.default_objective = point.default_objective
	squad.target_objective = point.target_objective
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
		if r != null and r.will_deploy():
			to_deploy.append(r)
	if to_deploy.is_empty():
		push_warning("SquadSpawner: nobody to form up on the player — every robot is benched or wrecked.")
		return null

	var basis := player.global_transform.basis
	var anchor := player.global_position + (basis.z.normalized() * player_back_offset)

	var members: Array[Soldier] = []
	for i in to_deploy.size():
		var soldier := _build_soldier(to_deploy[i])
		if soldier == null:
			continue
		@warning_ignore("integer_division")
		var row := i / 2
		var side := 1.0 if i % 2 == 0 else -1.0
		var offset := Vector3(side * player_spacing * (float(row) * 0.5 + 0.5), 0.0, float(row) * player_spacing)
		# Placed before it enters the tree, same as above.
		soldier.position = level.to_local(_Ground.stand(anchor + (basis * offset), soldier, level))
		level.add_child(soldier)
		if ai_manager != null:
			ai_manager.register_enemy(soldier)
		# Back-reference by id. Renaming a record has to reach the body that was
		# built from it, and there's nothing else linking the two.
		soldier.set_meta("record_id", to_deploy[i].id)
		_spawned[soldier] = to_deploy[i]
		members.append(soldier)

	if members.is_empty():
		return null

	_callsign_base = "ALPHA"
	for part in _split_by_team(members):
		var squad := _new_squad(part[0], part[1])
		squad.player_commandable = true
		squad.default_objective = Squad.SquadObjective.FOLLOW
		level.add_child(squad)
		squads.append(squad)
	# Named and spaced before they fall in, so each takes its own distance.
	_style_teams()
	for squad in squads:
		# Straight onto the player's hip, which is the point of spawning here.
		squad.follow(player)
	active_squad = squads[0]
	squad_deployed.emit(active_squad, members.size())
	print("[SquadSpawner] %d deployed on the player (no spawn point used), %d team(s)" % [members.size(), squads.size()])
	return active_squad


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

	# Not in the world. If they're deployable now, they should be — unless they
	# are benched: repairing a benched wreck mid-mission must not drop it into a
	# fight the player chose to leave it out of.
	if record.will_deploy():
		return spawn_one(record)
	return null


## Every record that had a body this mission: deployed at the start, or
## repaired back in part-way. Only these earned anything from it. Read before
## clear(), which forgets them.
func deployed_records() -> Array[SoldierRecord]:
	var out: Array[SoldierRecord] = []
	for record in _spawned.values():
		if record != null and not out.has(record):
			out.append(record)
	return out


func find_body(record: SoldierRecord) -> Soldier:
	for node in _spawned.keys():
		if _spawned[node] == record and node != null and is_instance_valid(node):
			return node as Soldier
	return null


# The level your teams are standing in, or null if none of them is.
func _level_of_squads() -> Node:
	if active_squad != null and is_instance_valid(active_squad) and active_squad.get_parent() != null:
		return active_squad.get_parent()
	for squad in squads:
		if squad != null and is_instance_valid(squad) and squad.get_parent() != null:
			return squad.get_parent()
	return null


# A team's squad for a robot to join, made if that team is not in the field
# yet — made falling in on you, since it has no orders of its own.
func _squad_to_join(team_id: StringName, level: Node) -> Squad:
	var squad := _squad_of_team(team_id)
	if squad != null:
		return squad
	var none: Array[Soldier] = []
	squad = _new_squad(team_id, none)
	squad.player_commandable = true
	level.add_child(squad)
	squads.append(squad)
	_style_teams()
	if player != null:
		squad.follow(player)
	return squad


# Adds one soldier to the squad that's already deployed, beside the others.
func spawn_one(record: SoldierRecord) -> Soldier:
	if not has_squad():
		return null
	var level := _level_of_squads()
	if level == null:
		push_warning("SquadSpawner: no team of yours is in a level, so %s has nowhere to rejoin." % record.display_name)
		return null

	var soldier := _build_soldier(record)
	if soldier == null:
		return null
	# Back into its own team — which, if it never went in this mission (a robot
	# repaired back into a fight it started out of), is made now.
	_spawned[soldier] = record
	var squad := _squad_to_join(_team_of(record), level)
	level.add_child(soldier)
	soldier.global_position = _rejoin_position(squad)
	soldier.set_meta("record_id", record.id)
	if ai_manager != null:
		ai_manager.register_enemy(soldier)
	squad.add_ai_to_squad(soldier)
	_style_teams()
	squad.notify_roster_changed()
	return soldier


## Brings the squads standing in the world into line with the squad page: a
## robot moved to another team changes squad where it stands and takes up that
## team's orders; a team made for it falls in on you; a renamed team is renamed.
## At base as much as in a mission. Not the bench — benching mid-mission only
## changes the next deploy, so nobody vanishes from a fight.
func regroup() -> void:
	var level := _level_of_squads()
	if level == null:
		return   # nobody deployed: the next deploy reads the teams afresh
	var joined: Array[Squad] = []
	var left: Array[Squad] = []
	for body in _spawned.keys():
		if body == null or not is_instance_valid(body):
			continue
		var soldier := body as Soldier
		var want := _team_of(_spawned[body])
		var from: Squad = soldier.squad if soldier.squad != null and is_instance_valid(soldier.squad) else null
		if from != null and from.team == want:
			continue
		var to := _squad_to_join(want, level)
		if from != null:
			from.remove_ai_from_squad(soldier)
			left.append(from)
		to.add_ai_to_squad(soldier)
		if not joined.has(to):
			joined.append(to)
	# A team whose last robot left is gone from the field with it.
	for squad in left:
		if is_instance_valid(squad) and squad.squad_members.is_empty():
			squads.erase(squad)
			squad.queue_free()
	_style_teams()
	if active_squad == null or not is_instance_valid(active_squad) or not squads.has(active_squad):
		active_squad = null
		for squad in squads:
			if active_squad == null or squad.team_rank < active_squad.team_rank:
				active_squad = squad
	for squad in joined:
		# The newcomer takes its part in whatever its team is doing: a post of its
		# own on a DEFEND, a place in the line on a FOLLOW.
		squad.resume_objective()
	for squad in squads:
		squad.notify_roster_changed()


# Beside its team, or beside the player if the team is empty.
func _rejoin_position(squad: Squad) -> Vector3:
	var anchor := squad.get_center() if not squad.get_living_members().is_empty() else Vector3.ZERO
	if anchor == Vector3.ZERO and active_squad != null and is_instance_valid(active_squad) \
			and not active_squad.get_living_members().is_empty():
		anchor = active_squad.get_center()
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
	for squad in squads:
		if squad != null and is_instance_valid(squad):
			squad.queue_free()
	squads.clear()
	active_squad = null
