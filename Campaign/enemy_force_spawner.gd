extends Node
class_name EnemyForceSpawner

## Robots are built through CsgBake.make() rather than scene.instantiate(): a
## CSGShape3D rebuilds its geometry the first time it enters the tree, which cost
## 8.6 ms per robot and made a 40-strong reserve wave a 336 ms frame. make()
## hands back the same node with the CSG already replaced by the mesh baked once
## at startup. It has to happen BEFORE the node is added to the tree — see
## csg_bake.gd for why neither _enter_tree nor _ready will do.
const _CsgBake := preload("res://Character/characters/ai/csg_bake.gd")

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
		var destination := _advance_destination(squad, spec, post)
		squad.target_objective = post
		squad.set_objective(Squad.SquadObjective.ADVANCE, destination, true)
		# They come in from outside activation_distance on purpose, so they are
		# exempt from the culling that would otherwise freeze them where they
		# landed until the player walked out to meet them. Only reinforcements
		# get this: see the note on the gate in Enemy._physics_process.
		for member in squad.squad_members:
			if member != null and is_instance_valid(member):
				member.exempt_from_culling()
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

	# Built first and placed after, so the ring can be laid out knowing how
	# much room each body takes (see _ring_offsets).
	var made: Array[Soldier] = []
	for i in bodies.size():
		var frame: ChassisDefinition = bodies[i]
		if frame == null or frame.scene == null:
			push_error("EnemyForceSpawner: '%s' roster slot %d has no scene." % [spec.callsign, i])
			continue
		var soldier := _CsgBake.make(frame.scene) as Soldier
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
		made.append(soldier)

	var members: Array[Soldier] = []
	var ring := _ring_offsets(made)
	var taken: Array = []   # the seats handed out so far: see _seat_is_free
	for i in made.size():
		var soldier := made[i]
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
		var at: Vector3 = anchor + ring[i]
		if spec.spawn_offset.y <= 0.0:
			# aircraft keep the height they were given
			var reach: float = maxf(_Ground.half_width(soldier), 0.5) + 0.2
			at = _Ground.stand(_seat_for(at, soldier, level, anchor, taken), soldier, level)
			# AFTER standing, not before. _Ground.stand snaps the seat to the
			# nearest navmesh point, and where the walkable ground near a post
			# is one small patch it pulls several seats onto the SAME spot —
			# which is how three of Mutaha's north island garrison ended up
			# inside one another with a good seat each.
			var spread := _spread_from(at, reach, taken)
			if spread != at:
				# Re-seat on the surface it was pushed onto, WITHOUT the snap
				# that pulled it back into the pile.
				at = _Ground.stand(spread, soldier, level, false)
			taken.append([at, reach])
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
	squad.engaged.connect(_on_squad_engaged)

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


# The tag a squad fires when it first comes into contact: "PORT" -> "port_engaged".
# The other end of the story from "_down": a position that calls for help the
# moment it is hit, not once it is gone — air support that answers a fight
# wherever the player chose to start it, rather than a captured objective.
static func squad_engaged_tag(callsign: String) -> StringName:
	return StringName(callsign.to_lower().replace(" ", "_") + "_engaged")


func _on_squad_engaged(squad: Squad) -> void:
	if squad == null or not is_instance_valid(squad):
		return   # freed between the emit and here
	var tag := squad_engaged_tag(squad.callsign)
	if not _reserves.has(tag):
		return   # nobody is waiting on this squad's contact
	print("[EnemyForce] '%s' is in contact: calling in '%s'" % [squad.callsign, tag])
	wake(tag)


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
	if frame.starting_weapon_id == &"":
		return   # nothing to issue
	# NOT GUARDED ON weapon_mount. The Reclaimer has none until it is asked for
	# a weapon: reclaimer.gd builds the mortar mount inside equip_weapon_scene,
	# on the boom, because the arm only exists after instantiate(). Refusing to
	# call it without a mount refused the one frame that makes its own — an
	# enemy Mortar Track spawned carrying nothing at all. A frame with truly
	# nowhere to put a gun warns from Enemy.equip_weapon_scene instead.
	if soldier.weapon_mount != null:
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
				_advance_destination(squad, spec, post), true)
		EnemySquadSpec.Posture.RESERVE:
			# Inert until something wakes them. This is the hook reinforcements
			# will hang off — a director flips them to ADVANCE on a trigger.
			squad.set_objective(Squad.SquadObjective.NONE, squad.get_center(), true)


# WHERE AN ADVANCING SQUAD IS ACTUALLY HEADED.
#
# ADVANCE onto squad.get_center() is the one fallback that does nothing at all:
# the destination is the patch of ground the squad is already standing on, so
# the order is issued, accepted and satisfied on the first tick. Every proving
# ground squad sat on the muster platform for the whole mission because
# post_tag named a point that level does not contain — the posture was right,
# the tag was dangling, and nothing said so.
#
# So a missing post is now reported, and the advance is pointed at the player's
# own spawn instead. "Push towards the player" is what ADVANCE means when the
# level offers nowhere else to push, and it is never worse than holding still.
func _advance_destination(squad: Squad, spec: EnemySquadSpec, post: SquadObjectivePoint) -> Vector3:
	if post != null:
		return post.global_position
	var muster := _player_spawn()
	if muster != Vector3.INF:
		# An EMPTY post_tag is a decision — "this squad has nowhere particular to
		# be, go at the player" — and small maps are full of those. A tag that
		# was written and does not resolve is a mistake, and only that warns.
		if spec.post_tag != &"":
			push_warning("EnemyForceSpawner: '%s' is set to ADVANCE but post_tag=%s is not in this level, so it is advancing on the player spawn instead.\n  points in level: %s" % [
				spec.callsign, spec.post_tag, _known_tags("squad_objective_points")])
		return muster
	push_warning("EnemyForceSpawner: '%s' is set to ADVANCE but post_tag=%s is not in this level and there is no player spawn to head for, so it will hold where it landed." % [
		spec.callsign, spec.post_tag])
	return squad.get_center()


## The player's own start, read off the level script the way World does it.
func _player_spawn() -> Vector3:
	if _level == null or not is_instance_valid(_level):
		return Vector3.INF
	var sp: Variant = _level.get("spawn_point")
	if sp is Node3D and (sp as Node3D).is_inside_tree():
		return (sp as Node3D).global_position
	return Vector3.INF


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


## Clear ground left between neighbours on a spawn ring, flat.
const RING_GAP := 0.5

## How far the search steps out when a seat on the ring is occupied, and how
## many turns it tries at each step.
const SEAT_STEP := 1.6
const SEAT_TURNS := 8
const SEAT_STEPS := 4


# WHERE A BODY WILL ACTUALLY FIT.
#
# _ring_offsets gives everyone their own arc, but it draws the ring without
# looking at the world: on a street grid a seat lands inside a wall, a rack row
# or a parked hull often enough to matter. Godot settles an overlap by pushing
# the pair apart every tick, and since each shove moves both, an overlapping
# pair ACCELERATES — measured at 52 m/s across Mutaha, ending against the
# boundary wall or out of the world, with the bodies counted as losses before
# anyone had seen them. Enemy._damp_shoving caps how fast that goes wrong; this
# stops it starting.
#
# Squadmates already placed are in the tree, so they are part of the test: the
# search also keeps a squad from stacking on itself.
func _seat_for(at: Vector3, soldier: Soldier, level: Node, anchor: Vector3, taken: Array) -> Vector3:
	if not (level is Node3D) or not level.is_inside_tree():
		return at
	var space := (level as Node3D).get_world_3d().direct_space_state
	if space == null:
		return at
	var reach: float = maxf(_Ground.half_width(soldier), 0.5) + 0.2
	# Best: room on the ground AND nobody already sitting there.
	for step in SEAT_STEPS:
		var out := float(step) * SEAT_STEP
		for turn in SEAT_TURNS:
			var angle := TAU * float(turn) / float(SEAT_TURNS)
			var candidate: Vector3 = at if step == 0 else at + Vector3(cos(angle), 0.0, sin(angle)) * out
			if _seat_is_free(candidate, reach, taken) and _seat_is_clear(candidate, reach, space, level as Node3D):
				return candidate
			if step == 0:
				break   # the drawn seat is one spot, not eight
	# NOBODY STACKS, EVER. A post wedged between buildings can fail the clear
	# test at every candidate — and falling back to one spot for all of them
	# put three bodies inside each other at Mutaha's north island, which is
	# precisely the pile this pass exists to prevent (see Enemy._damp_shoving
	# for what an overlapping pair then does). Standing in a doorway is a bad
	# spawn; standing INSIDE a squadmate is a broken one.
	for step in SEAT_STEPS:
		var out := float(step) * SEAT_STEP
		for turn in SEAT_TURNS:
			var angle := TAU * float(turn) / float(SEAT_TURNS)
			var candidate: Vector3 = at if step == 0 else at + Vector3(cos(angle), 0.0, sin(angle)) * out
			if _seat_is_free(candidate, reach, taken):
				return candidate
			if step == 0:
				break
	return at   # the ring drew this seat: at least it is spread like the others


# Squadmates seated EARLIER THIS FRAME are invisible to a shape query: the
# physics space has not stepped since they were added, so it reports their
# seats empty and the whole squad piles onto the same few spots. The seats
# handed out so far are therefore remembered and checked in code.
func _seat_is_free(at: Vector3, reach: float, taken: Array) -> bool:
	for seat in taken:
		var other: Vector3 = seat[0]
		var room: float = reach + float(seat[1])
		if Vector2(other.x - at.x, other.z - at.z).length() < room:
			return false
	return true


func _seat_is_clear(at: Vector3, reach: float, space: PhysicsDirectSpaceState3D, level: Node3D) -> bool:
	var map: RID = level.get_world_3d().navigation_map
	var on: Vector3 = NavigationServer3D.map_get_closest_point(map, at)
	if on == Vector3.ZERO or Vector2(on.x - at.x, on.z - at.z).length() > 2.0:
		return false   # no walkable ground here to stand on
	var ball := SphereShape3D.new()
	ball.radius = reach
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	# A whole radius above the mesh, so the ground itself is not the hit.
	q.transform = Transform3D(Basis(), Vector3(at.x, on.y + reach + 0.1, at.z))
	q.collide_with_areas = false
	return space.intersect_shape(q, 1).is_empty()


# THE LAST WORD ON SPACING, SAID AFTER THE GROUND HAS ITS SAY.
#
# _seat_for hands every body its own spot, and _Ground.stand then pulls that
# spot up to 3m onto the nearest navmesh point — so on a post whose walkable
# ground is one small patch, several bodies that were properly spread arrive
# on the SAME point anyway. That is what still had three of Mutaha's north
# island garrison inside one another after the search was already working.
# Pushing them apart here, in the plane and after the snap, is the only place
# nothing downstream can undo it.
func _spread_from(at: Vector3, reach: float, taken: Array) -> Vector3:
	var here := at
	for turn in SEAT_TURNS:
		var push := Vector2.ZERO
		for seat in taken:
			var other: Vector3 = seat[0]
			var room: float = reach + float(seat[1])
			var gap := Vector2(here.x - other.x, here.z - other.z)
			var span := gap.length()
			if span >= room:
				continue
			var away := Vector2.ZERO
			if span > 0.01:
				away = gap / span
			else:
				# Exactly on top of one another leaves no direction to push
				# along, so each body takes its own bearing off the ring.
				var angle := TAU * float(taken.size() + turn) / float(SEAT_TURNS)
				away = Vector2(cos(angle), sin(angle))
			push += away * (room - span + RING_GAP * 0.5)
		if push == Vector2.ZERO:
			break   # clear of everyone: done
		here = Vector3(here.x + push.x, here.y, here.z + push.y)
	return here


# A ring round the anchor with room for everyone on it. The old one spaced a
# squad evenly on a fixed 2m circle, which put nine bodies 1.4m apart and, at
# Pittsburgh's North Shore, a Rover and a Reclaimer side by side: overlapping
# hulls, which the physics settled by pushing the Reclaimer down through the
# ground and out of the world. Each body gets an arc as wide as it is, the ring
# grows until they all fit, and spare room is shared out evenly as before.
func _ring_offsets(built: Array) -> Array:
	var out: Array = []
	if built.size() <= 1:
		for _b in built:
			out.append(Vector3.ZERO)
		return out   # one body stands on the anchor itself
	var widths: Array = []
	var circumference := 0.0
	for body in built:
		var w: float = maxf(_Ground.half_width(body), 0.5) * 2.0 + RING_GAP
		widths.append(w)
		circumference += w
	var radius := maxf(spawn_spread, circumference / TAU)
	var stretch := TAU * radius / circumference
	var along := 0.0
	for i in built.size():
		along += float(widths[i]) * 0.5 * stretch
		var angle := along / radius
		out.append(Vector3(cos(angle), 0.0, sin(angle)) * radius)
		along += float(widths[i]) * 0.5 * stretch
	return out


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
