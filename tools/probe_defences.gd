extends SceneTree

# ─────────────────────────────────────────────
# EVERY DEFENCE, CHECKED AGAINST THE LEVEL IT DEPLOYS TO.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_defences.gd
#
# Nine sites, nine defences, and every one of them is a pile of StringNames
# that fail SILENTLY. A garrison post that is not a tag in the level puts no
# garrison anywhere. A spawn_tag that is not a tag drops the squad on its post
# instead, so a wave meant to arrive from the north edge appears standing on
# the core it was sent to take. An objective id the level does not carry gives
# the player an empty HUD and no way to finish. None of that errors; it plays.
#
# So this asserts the whole contract from ATTACK_AND_DEFEND.md, per defence:
#
#   defence = true, sim = false, repeatable = true
#   reward_resources = 0 and compute_reward = 0 — a defence pays NOTHING (§4)
#   unlocks empty, squad_size = -1
#   requires names exactly its own site's attack, and that attack exists
#   >= 3 garrison_posts, every one of them a real SquadObjectivePoint tag
#   >= 3 DISTINCT spawn_tags — "a defence where everyone comes from one edge
#     is a queue" — and every spawn_tag and post_tag is a real tag
#   every spec posture = ADVANCE, always_active = true, faction = ENEMY.
#     always_active is not optional: a wake-delayed wave without it is culled
#     before it has walked anywhere and the pool never empties
#   every active_objectives id exists in the level
#   the Location that names this defence also names the attack it requires
#
# IT LOADS THE LEVELS. test_mission_objectives.gd reads packed SceneState,
# which is faster and enough for objective ids; tags are only resolvable the
# way the spawner resolves them, which is get_nodes_in_group on a live tree.
#
# WHAT IT DOES NOT ANSWER: whether a body that spawned at a legal tag is
# standing anywhere sensible. A tag can resolve perfectly and still bury the
# second seat on the ring in a wall — four of these eight did, every one of
# them a five-body squad led by a rover arriving through a bench pocket, a ring
# road or a village. That is spawn_geometry_audit.gd's question and it is worth
# asking whenever a roster or a spawn_tag changes here:
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/spawn_geometry_audit.gd -- <mission id>
# ─────────────────────────────────────────────

var _fails := 0
var _checks := 0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame

	var world: PackedScene = load("res://Env/world.tscn")
	var missions: Array = _missions(world.get_state())
	if missions.is_empty():
		_bad("world.tscn's CampaignManager lists no missions at all")
		_finish()
		return

	var locations := _locations()
	var defences: Array = []
	for m in missions:
		if m != null and m.defence:
			defences.append(m)
	print("%d mission(s) in world.tscn, %d of them defences" % [missions.size(), defences.size()])
	if defences.size() != locations.size():
		_bad("%d defences but %d locations — every Location with ground the player can hold needs one (ATTACK_AND_DEFEND.md, 'Done when')" % [defences.size(), locations.size()])

	for loc in locations:
		if String(loc.defend_mission_id) == "":
			_bad("%s has no defend_mission_id, so a raid there offers a DEFEND the player cannot deploy to" % loc.id)

	for m in defences:
		await _one(m, missions, locations)
	_finish()


func _finish() -> void:
	print("")
	print("%d check(s), %d problem(s)" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _one(m: MissionDefinition, missions: Array, locations: Array) -> void:
	var id := String(m.id)
	print("")
	print("── %s" % id)

	_ok(id, "defence = true", m.defence)
	_ok(id, "sim = false", not m.sim)
	_ok(id, "repeatable = true", m.repeatable)
	_ok(id, "pays nothing", m.reward_resources == 0 and m.compute_reward == 0,
		"reward_resources=%d compute_reward=%d" % [m.reward_resources, m.compute_reward])
	_ok(id, "unlocks nothing", m.unlocks.is_empty(), str(m.unlocks))
	_ok(id, "squad_size = -1", m.squad_size == -1, str(m.squad_size))
	_ok(id, "replace_level_enemies = true", m.replace_level_enemies)
	_ok(id, "has a level_scene", m.level_scene != null)

	# ── THE SITE IT BELONGS TO ────────────────
	var site: Location = null
	for loc in locations:
		if loc.defend_mission_id == m.id:
			site = loc
			break
	_ok(id, "a Location names it as its defence", site != null)

	_ok(id, "requires exactly one mission", m.requires.size() == 1, str(m.requires))
	if m.requires.size() == 1:
		var req := m.requires[0]
		var attack: MissionDefinition = null
		for other in missions:
			if other != null and other.id == req:
				attack = other
		_ok(id, "requires a mission that exists (%s)" % String(req), attack != null)
		if site != null:
			_ok(id, "requires its OWN site's attack", site.mission_id == req,
				"site %s attacks with %s" % [site.id, String(site.mission_id)])
		if attack != null:
			_ok(id, "same level_scene as its attack",
				attack.level_scene == m.level_scene)
			# The core objectives, minus extraction and minus eliminates: the
			# defence must not invent its own objective set (§2).
			var stray: Array = []
			for o in m.active_objectives:
				if not attack.active_objectives.has(o):
					stray.append(String(o))
			_ok(id, "names no objective its attack does not", stray.is_empty(), str(stray))

	# ── THE FORCE ─────────────────────────────
	_ok(id, "fields at least 3 squads", m.enemy_force.size() >= 3,
		"%d spec(s)" % m.enemy_force.size())
	var spawns := {}
	var bad_posture: Array = []
	var not_active: Array = []
	var wrong_faction: Array = []
	var no_spawn: Array = []
	for spec in m.enemy_force:
		if spec == null:
			_bad("%s has a null spec in enemy_force" % id)
			continue
		if spec.posture != EnemySquadSpec.Posture.ADVANCE:
			bad_posture.append(spec.callsign)
		if not spec.always_active:
			not_active.append(spec.callsign)
		if spec.faction != Enums.Factions.ENEMY:
			wrong_faction.append(spec.callsign)
		if String(spec.spawn_tag) == "":
			no_spawn.append(spec.callsign)
		else:
			spawns[spec.spawn_tag] = true
	_ok(id, "every spec ADVANCEs", bad_posture.is_empty(), str(bad_posture))
	_ok(id, "every spec always_active", not_active.is_empty(), str(not_active))
	_ok(id, "every spec faction = ENEMY", wrong_faction.is_empty(), str(wrong_faction))
	_ok(id, "every spec names a spawn_tag", no_spawn.is_empty(), str(no_spawn))
	_ok(id, "3+ distinct spawn_tags", spawns.size() >= 3,
		"%d: %s" % [spawns.size(), str(spawns.keys())])

	_ok(id, "3+ garrison_posts", m.garrison_posts.size() >= 3,
		"%d" % m.garrison_posts.size())

	# ── AGAINST THE LEVEL ─────────────────────
	if m.level_scene == null:
		return
	var level = m.level_scene.instantiate()
	root.add_child(level)
	for _i in 20:
		await process_frame

	var tags := {}
	var ids := {}
	_walk(level, tags, ids)

	var missing_posts: Array = []
	for t in m.garrison_posts:
		if not tags.has(t):
			missing_posts.append(String(t))
	_ok(id, "every garrison_post is a tag in the level", missing_posts.is_empty(),
		str(missing_posts))

	var missing_spawn: Array = []
	var missing_post: Array = []
	for spec in m.enemy_force:
		if spec == null:
			continue
		if String(spec.spawn_tag) != "" and not tags.has(spec.spawn_tag):
			missing_spawn.append("%s:%s" % [spec.callsign, String(spec.spawn_tag)])
		if String(spec.post_tag) != "" and not tags.has(spec.post_tag):
			missing_post.append("%s:%s" % [spec.callsign, String(spec.post_tag)])
	_ok(id, "every spawn_tag is a tag in the level", missing_spawn.is_empty(),
		str(missing_spawn))
	_ok(id, "every post_tag is a tag in the level", missing_post.is_empty(),
		str(missing_post))

	var missing_objs: Array = []
	for o in m.active_objectives:
		if not ids.has(o):
			missing_objs.append(String(o))
	_ok(id, "every active_objectives id is in the level", missing_objs.is_empty(),
		str(missing_objs))
	_ok(id, "names at least one objective", not m.active_objectives.is_empty())

	level.queue_free()
	await process_frame


func _walk(n: Node, tags: Dictionary, ids: Dictionary) -> void:
	if n is SquadObjectivePoint and n.tag != &"":
		tags[n.tag] = n.global_position
	if n is MissionObjective and n.id != &"":
		ids[n.id] = true
	for c in n.get_children():
		_walk(c, tags, ids)


## The CampaignManager's authored mission list, read off world.tscn the way
## test_mission_objectives.gd does — the array is a scene value, so a script
## default would be the wrong answer.
func _missions(state: SceneState) -> Array:
	for i in state.get_node_count():
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == &"missions":
				return state.get_node_property_value(i, p)
	return []


## THE BOARD, READ FROM THE CATALOGUE — not from a listing of
## Campaign/locations/.
##
## This used to DirAccess that directory, and it was wrong twice over.
## location_catalogue.gd says why in its own header: a directory listing does
## not enumerate in an exported build, so the catalogue resource is the shape
## that ships and the authored array is the only statement of what is on the
## board.
##
## It also reported a failure that was not one. A site can be RETIRED without
## being deleted — deleting authored content is the human's call, so the .tres
## stays on disk and comes out of the catalogue. That is what happened to
## loc_hillfort when hillfort_wip replaced it: nine live locations, nine
## defences, and a tenth file in the folder that is nobody's site. The scan
## counted the file and called the board incomplete.
func _locations() -> Array:
	var out: Array = []
	var cat = load("res://Campaign/location_catalogue.tres")
	if cat == null:
		_bad("cannot load res://Campaign/location_catalogue.tres, which is the board")
		return out
	for l in cat.locations:
		if l == null:
			_bad("location_catalogue.tres has an empty slot, so a place silently stopped existing")
			continue
		out.append(l)
	return out


func _ok(label: String, what: String, pass_: bool, detail: String = "") -> void:
	_checks += 1
	if pass_:
		print("  ok    %s" % what)
	else:
		print("  FAIL  %s  %s  %s" % [label, what, detail])
		_fails += 1


func _bad(what: String) -> void:
	print("  FAIL  %s" % what)
	_fails += 1
