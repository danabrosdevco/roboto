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
## How far a spawn point may be dragged onto the navmesh before the spawner
## gives up and says so. Big enough to fix an offset that overshot the edge of
## the walkable ground, small enough that a squad never silently appears in a
## different part of the map from the one it was authored into.
@export var max_spawn_snap: float = 45.0
## Stands each spawned body on the real ground: see ground_snap.gd. By path,
## not class_name, so an open editor never compiles this before it exists.
const _Ground := preload("res://Campaign/ground_snap.gd")

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

# ── LOSSES ────────────────────────────────────
# What the force has lost, and the waves waiting on that number. A reserve can
# name an objective (the tag IS the objective id) or a body count; this is the
# second kind, so escalation can answer a grinding fight as well as a captured
# point.
#
# Downs and destructions both count, once per body: an enemy Mechanic standing
# one of them back up does not un-ring the bell.
var _losses: int = 0
var _counted: Dictionary = {}
var _kill_waves: Array = []        # [{"after": int, "tag": StringName}]
## Reserves listening for this tag come in when any nest is destroyed. A
## convention rather than a field: a mission names the wave, the building does
## not have to know about it.
const NEST_DOWN_TAG := &"nest_down"


## How many hostiles this force has lost so far.
func losses() -> int:
	return _losses


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
			if spec.wake_after_kills > 0:
				_kill_waves.append({"after": spec.wake_after_kills, "tag": spec.reinforcement_tag})
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
		# They come in from outside activation_distance on purpose, so they are
		# exempt from the culling that would otherwise freeze them where they
		# landed until the player walked out to meet them. Only reinforcements
		# get this: see the note on the gate in Enemy._physics_process.
		for member in squad.squad_members:
			if member != null and is_instance_valid(member):
				member.never_culled = true
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
		# For the playtest log: "Chaser", not "enemy_chaser". Legacy count-form
		# frames are built on the fly and have no name worth reporting.
		if frame.resource_path != "":
			soldier.set_meta(&"analytics_kind", frame.display_name)
			# What a kill of this one counts as in the debrief (kill_kinds.gd).
			soldier.set_meta(&"chassis_id", frame.id)
		# PLACED BEFORE IT ENTERS THE TREE.
		#
		# Adding first and positioning after leaves the body at the level's
		# origin for the frame it readies in — and every robot spawned that
		# frame, both sides, is standing in the same spot. Their 25m Detection
		# areas all overlap, _on_detection_body_entered fills each empty
		# combat_target with whoever it found, and nothing ever clears it
		# because there is no line of sight to lose. The result was the entire
		# hostile force locked onto one of the player's robots from 150m+ away
		# before the mission started: every squad ENGAGED on the first frame,
		# so the picket never walked its patrol and the garrisons were already
		# fighting something they could not see.
		var at := anchor + _ring_offset(i, bodies.size())
		if spec.spawn_offset.y <= 0.0:
			at = _Ground.stand(at, soldier, level)   # aircraft keep the height they were given
		soldier.position = level.to_local(at)
		level.add_child(soldier)
		if ai_manager != null:
			ai_manager.register_enemy(soldier)
		_watch_losses(soldier)
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
# One body, watched for the moment it leaves the fight. Both signals, because
# a robot that can be downed emits went_down and a building emits destroyed,
# and a body that goes down and is then destroyed must only count once.
func _watch_losses(body: Enemy) -> void:
	if body == null:
		return   # nothing spawned to watch
	body.went_down.connect(_on_body_lost.bind(body))
	body.destroyed.connect(_on_body_lost.bind(body))


func _on_body_lost(body: Enemy) -> void:
	if body == null or not is_instance_valid(body):
		return   # gone before we could look at it
	var id := body.get_instance_id()
	if _counted.has(id):
		return   # already on the tally: downed first, destroyed after
	_counted[id] = true
	_losses += 1
	# A nest going down is its own call for help, whatever the body count is.
	if body.has_signal(&"hatched_body"):
		wake(NEST_DOWN_TAG)
	# So is losing a whole squad. "The patrol stopped answering" is the most
	# natural trigger a mission has, and it needs no new field: a reserve just
	# tags itself with the callsign it is answering for, the same way one tags
	# itself with an objective id.
	_check_squad_wiped(body)
	var due: Array = []
	for wave in _kill_waves:
		if int(wave["after"]) <= _losses:
			due.append(wave)
	for wave in due:
		_kill_waves.erase(wave)
		print("[EnemyForce] %d lost: calling in '%s'" % [_losses, wave["tag"]])
		wake(wave["tag"])


# The tag a squad fires when the last of it goes down: "PICKET" -> "picket_down".
static func squad_down_tag(callsign: String) -> StringName:
	return StringName(callsign.to_lower().replace(" ", "_") + "_down")


# Was that the last of someone? Checked off the body that just fell rather than
# polled, and only for the squad it belonged to.
func _check_squad_wiped(body: Enemy) -> void:
	for squad in _squads:
		if squad == null or not is_instance_valid(squad):
			continue
		if not squad.squad_members.has(body):
			continue
		for member in squad.squad_members:
			if member != null and is_instance_valid(member) and member.alive:
				return   # someone is still up
		var tag := squad_down_tag(squad.callsign)
		if _reserves.has(tag):
			print("[EnemyForce] '%s' is gone: calling in '%s'" % [squad.callsign, tag])
			wake(tag)
		return


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
# directly (a chaser is 8 m/s, a quadcopter bomber 14), while base_speed is a multiplier
# from the player-roster side. Multiplying one by the other would quietly make
# every chaser 35% faster than it has ever been.
# The catalogue, for frames that come with a gun. Looked up through the
# campaign group rather than wired, the same way squad_spawner.gd does it.
var _cat: ItemCatalogue = null


func _catalogue() -> ItemCatalogue:
	if _cat != null:
		return _cat
	var campaign := get_tree().get_first_node_in_group("campaign")
	if campaign != null:
		_cat = campaign.get("catalogue")
	return _cat


# A frame whose robots are issued a weapon gets it here. Only the rover today,
# and only when its mount is empty — a scene with a gun wired in keeps that
# one. The lab already did this (Lab._issued_weapon) and missions did not, so
# every hostile rover a mission spawned drove out with nothing to shoot with.
func _issue_weapon(soldier: Soldier, frame: ChassisDefinition) -> void:
	if frame.starting_weapon_id == &"" or soldier.weapon_mount == null:
		return   # nothing to issue, or nowhere to put it
	for child in soldier.weapon_mount.get_children():
		if child is AIWeapon:
			return   # already carrying one from its scene
	var cat := _catalogue()
	var item: ItemDefinition = cat.item(frame.starting_weapon_id) if cat != null else null
	if item == null or item.ai_scene == null:
		push_warning("EnemyForceSpawner: %s should come with '%s', which the catalogue does not have as an AI weapon." % [frame.display_name, frame.starting_weapon_id])
		return
	soldier.equip_weapon_scene(item.ai_scene)


func _apply_frame(soldier: Soldier, frame: ChassisDefinition) -> void:
	_issue_weapon(soldier, frame)
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
	var out: Vector3 = base + spec.spawn_offset
	# AND THE OFFSET HAS TO LAND SOMEWHERE WALKABLE. A reinforcement that comes
	# in far enough out to be worth watching is, by definition, a long way from
	# the tag it was measured off — and nothing checked that the far end of
	# that offset was still on the navmesh. Off it, the squad spawns fine, can
	# path nowhere, and stands in the desert for the rest of the mission.
	#
	# Only the ground position is snapped: the height the spec asked for is
	# what makes an air arrival an air arrival, so that is kept as authored.
	var map: RID = get_tree().root.world_3d.navigation_map
	var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(out.x, base.y, out.z))
	if on_mesh == Vector3.ZERO:
		return out   # no navmesh to ask (a test rig, an unbaked level)
	var pulled := Vector2(on_mesh.x - out.x, on_mesh.z - out.z).length()
	if pulled > max_spawn_snap:
		push_warning("EnemyForceSpawner: '%s' spawns %.0fm off the navmesh — nearest walkable ground is further than %.0fm, so it is being left where it was authored and may not be able to move." % [spec.callsign, pulled, max_spawn_snap])
		return out
	return Vector3(on_mesh.x, on_mesh.y + spec.spawn_offset.y, on_mesh.z)


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
	_losses = 0
	_counted.clear()
	_kill_waves.clear()
	_squads.clear()
	# Holds specs waiting on an objective that will never fire now, and a stale
	# entry would send the next mission's reinforcements into the wrong level.
	_reserves.clear()
	_level = null
