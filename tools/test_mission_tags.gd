extends SceneTree

# ─────────────────────────────────────────────
# EVERY TAG A MISSION NAMES EXISTS IN THE LEVEL IT DEPLOYS TO.
#
# tools/test_mission_objectives.gd already checks the OBJECTIVE ids. This
# checks the other half, which nothing checked: every EnemySquadSpec resolves
# three tags through EnemyForceSpawner — post_tag and route_tag through
# _find_point / _find_route, and spawn_tag through _anchor_point — and all
# three look the tag up in a GROUP ("squad_objective_points", "patrol_paths").
#
# WHAT A DANGLING TAG ACTUALLY COSTS, from this project's own history:
#
#   * a GARRISON whose post_tag does not resolve gets DEFEND on the patch of
#     ground it spawned on, so it holds the wrong place for the whole mission;
#   * an ADVANCE whose post_tag does not resolve is pointed at the player's
#     spawn as a fallback — every proving ground squad sat on the muster
#     platform for an entire operation because of exactly this;
#   * a PATROL whose route_tag does not resolve falls back to DEFEND and never
#     walks anywhere;
#   * a spawn_tag that does not resolve drops the squad on its post instead,
#     which is how a reinforcement column meant to come in off the map edge
#     appears on top of the thing it was sent to retake.
#
# None of those crash and none of them warn loudly enough to find in a log.
# They just make the mission play differently from how it was written, which
# is the most expensive kind of bug in this codebase.
#
# WHY THIS ONE INSTANTIATES THE LEVEL and test_mission_objectives.gd does not.
# The objective test reads packed SceneState, which is fast and enough — an
# objective authors its `id` in the level's own state. Tags do not work that
# way any more: Georgetown, Polaris and Causeway carry their posts inside an
# INSTANCED ops scene (maps/gameplay/*_ops.tscn), and an instanced sub-scene's
# nodes are invisible to the parent's SceneState. The only honest way to ask
# "what tags does this level actually offer" is to build it and read the
# groups the spawner reads. One instantiate per distinct level, cached.
#
# It changes nothing and writes nothing: no save, no physics settling, no
# navmesh queries. Levels are freed as soon as their tags are collected.
# ─────────────────────────────────────────────

const POST_GROUP := "squad_objective_points"
const ROUTE_GROUP := "patrol_paths"

var _fails := 0
## level path -> {"posts": {tag: true}, "routes": {tag: true}}
var _cache: Dictionary = {}


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var world: PackedScene = load("res://Env/world.tscn")
	var missions: Array = _missions(world.get_state())
	_check("(setup) the campaign has missions to check", not missions.is_empty(),
		"world.tscn declares no mission list")
	if missions.is_empty():
		_finish()
		return

	for m in missions:
		if m == null or m.level_scene == null:
			continue
		var level_path: String = m.level_scene.resource_path
		var tags: Dictionary = await _tags_of(level_path, m.level_scene)
		var level := level_path.get_file()
		var posts: Dictionary = tags["posts"]
		var routes: Dictionary = tags["routes"]

		# A level that offers NO posts at all is worth saying out loud on its
		# own: every spec in the mission is about to fall back, and reporting
		# that as fifty separate failures buries the one fact that matters.
		if posts.is_empty() and not m.enemy_force.is_empty():
			_check("%s: %s offers at least one squad post" % [m.id, level], false,
				"the level has nothing in the \"%s\" group, so every post_tag and spawn_tag in this mission dangles" % POST_GROUP)
			continue

		var bad_posts: Array = []
		var bad_spawns: Array = []
		var bad_routes: Array = []
		for spec in m.enemy_force:
			if spec == null:
				continue
			if spec.post_tag != &"" and not posts.has(spec.post_tag):
				bad_posts.append("%s -> %s" % [spec.callsign, spec.post_tag])
			if spec.spawn_tag != &"" and not posts.has(spec.spawn_tag):
				bad_spawns.append("%s -> %s" % [spec.callsign, spec.spawn_tag])
			# Only a PATROL reads route_tag, but a route_tag written on a spec
			# that is not patrolling is still a lie in the data and still worth
			# reporting — it usually means the posture is the thing that is
			# wrong.
			if spec.route_tag != &"" and not routes.has(spec.route_tag):
				bad_routes.append("%s -> %s" % [spec.callsign, spec.route_tag])

		_check("%s: every post_tag resolves in %s" % [m.id, level], bad_posts.is_empty(),
			"%s. The level offers %s" % [str(bad_posts), str(posts.keys())])
		_check("%s: every spawn_tag resolves in %s" % [m.id, level], bad_spawns.is_empty(),
			"%s. The level offers %s" % [str(bad_spawns), str(posts.keys())])
		_check("%s: every route_tag resolves in %s" % [m.id, level], bad_routes.is_empty(),
			"%s. The level offers %s" % [str(bad_routes), str(routes.keys())])

		# A PATROL with no route is the one case the spawner silently converts
		# into something else entirely (DEFEND where it stands), so it is worth
		# its own line rather than being folded into the three above.
		var routeless: Array = []
		for spec in m.enemy_force:
			if spec == null:
				continue
			if spec.posture == EnemySquadSpec.Posture.PATROL and spec.route_tag == &"":
				routeless.append(String(spec.callsign))
		_check("%s: no PATROL squad is missing its route" % m.id, routeless.is_empty(),
			"%s are set to PATROL with an empty route_tag, so they will hold where they land" % str(routeless))

	_finish()


## The tags a level really offers, by building it once and reading the groups
## the spawner reads. Cached per level path: three missions on one map must not
## instantiate it three times.
func _tags_of(path: String, packed: PackedScene) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var out := {"posts": {}, "routes": {}}
	var level := packed.instantiate()
	if level == null:
		_cache[path] = out
		return out
	root.add_child(level)
	# One frame is enough: the groups are joined in _ready, and nothing here
	# needs physics or navigation to have settled.
	await process_frame
	for n in get_nodes_in_group(POST_GROUP):
		var tag: Variant = n.get("tag")
		if tag != null and String(tag) != "":
			out["posts"][StringName(tag)] = true
	for n in get_nodes_in_group(ROUTE_GROUP):
		var tag: Variant = n.get("tag")
		if tag != null and String(tag) != "":
			out["routes"][StringName(tag)] = true
	root.remove_child(level)
	level.free()
	_cache[path] = out
	return out


func _finish() -> void:
	print("")
	print("ALL MISSION TAG CHECKS PASS" if _fails == 0
		else "%d MISSION TAG CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


## The mission list as world.tscn authors it on CampaignManager. Same packed
## read as tools/test_mission_objectives.gd.
func _missions(st: SceneState) -> Array:
	for i in st.get_node_count():
		if st.get_node_name(i) != "CampaignManager":
			continue
		for j in st.get_node_property_count(i):
			if String(st.get_node_property_name(i, j)) == "missions":
				return st.get_node_property_value(i, j)
		return []
	return []
