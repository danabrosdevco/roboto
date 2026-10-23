extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# HILLFORT REDOUBT IS A REAL SITE, NOT A SET OF FILES THAT PARSE.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_hillfort_wip.gd
#
# Built from docs/briefs/HILLFORT_WIP_HANDOVER.md, whose tag table is the
# contract between TERRAIN's map and GAMEPLAY's operation. Everything here
# checks one half against the other, because every way this goes wrong is
# silent:
#
#   - a spec naming a post that is not in the level spawns on its ring offset
#     and warns once, at runtime, into a log nobody reads
#   - a core named by the slice that is not in the level is simply not holdable
#   - a route_tag with no PatrolPath behind it finds no anchor at all
#   - a Location whose connects_to is not reciprocal breaks the frontier rule
#     in one direction only
#
# THE DIFFICULTY IS PART OF THE CONTRACT. This is the ALTERNATIVE first
# mission, and the only reason to build an alternative is to compare it — so
# its supply has to match hillfort_1_relay's, or the comparison measures the
# budget instead of the map.
# ─────────────────────────────────────────────

const LEVEL := "res://maps/hillfort_wip_level.tscn"
const ATTACK := "res://Campaign/missions/mission_hfw_1_fort.tres"
const DEFEND := "res://Campaign/missions/mission_hfw_2_defend.tres"
const LOC := "res://Campaign/locations/loc_hillfort_wip.tres"
const CATALOGUE := "res://Campaign/location_catalogue.tres"
const HILLFORT := "res://Campaign/missions/mission_hillfort_1_relay.tres"

## The six cores the handover promises, and the tier each one's prefab needs.
## A tier that disagrees with the prefab sizes the interact volume wrong and
## puts the player inside it, where the ray reports nothing to press.
const CORES := {
	"CisternCore": 1, "ShoulderCore": 1, "PillarsCore": 1,
	"GatehouseCore": 1, "TerraceCore": 1, "RelayCore": 2,
}

## Every district anchor in the handover's tag table. A mission may reference
## any of them later, so a missing one is a trap whether or not it is used now.
const ANCHORS := [
	"obj_hfw_trailhead", "obj_hfw_pillars", "obj_hfw_centre_apron",
	"obj_hfw_cistern", "obj_hfw_shoulder", "obj_hfw_west_apron",
	"obj_hfw_gatehouse", "obj_hfw_terrace", "obj_hfw_east_apron",
	"obj_hfw_yard", "obj_hfw_dish", "obj_hfw_hall", "obj_hfw_postern",
	"obj_hfw_bunker", "obj_hfw_west_flank", "obj_hfw_east_flank",
	"obj_hfw_south_meadow",
]

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame

	var level: Node = (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	for _i in 10:
		await process_frame
	await physics_frame

	var tags := _tags(level)
	var routes := _routes(level)

	_cores(level)
	_tag_table(tags)
	_mission(load(ATTACK), tags, routes, "attack")
	_mission(load(DEFEND), tags, routes, "defence")
	_bunker(level)
	_exit(level)
	_optional(level)
	_location()
	_economy()

	print("")
	print("PASS" if _fails == 0 else "FAIL  %d check(s) failed" % _fails)
	quit(0 if _fails == 0 else 1)


# ── The level's own furniture ────────────────────────────────────────────────

func _cores(level: Node) -> void:
	var missing: Array[String] = []
	for named in CORES:
		if _find(level, named) == null:
			missing.append(named)
	_check("all six capture points are in the level", missing.is_empty(),
		"missing: %s" % str(missing) if not missing.is_empty() else "")


func _tag_table(tags: Dictionary) -> void:
	var missing: Array[String] = []
	for t in ANCHORS:
		if not tags.has(t):
			missing.append(t)
	_check("all 17 district anchors are in the level", missing.is_empty(),
		"missing: %s" % str(missing) if not missing.is_empty() else "")


func _bunker(level: Node) -> void:
	_check("the bunker marker HFW_Bunker exists", _find(level, "HFW_Bunker") != null)
	var slice = load("res://Env/world_objects/hillfort_wip_slice.gd").new()
	_check("the slice points at that marker", slice.bunker_marker == &"HFW_Bunker",
		String(slice.bunker_marker))
	_check("the slice mounts it on the cliff kit", slice.bunker_mount == &"cliff",
		String(slice.bunker_mount))
	# The one open design question in the handover, answered — and answered
	# AGAINST the recommendation, which is exactly why it is pinned here.
	# All four quarters were photographed from the mouth with the doors open
	# (tools/shot_bunker_arrival.gd): 0 is clear for 60 m with the dish beside
	# the frame rather than filling it, 90 goes square into the Data Hall at
	# 20.8 m, 180 into the rampart at 12 m. Turning it buys a wall.
	_check("the doors are left on the facing that has a sightline",
		is_equal_approx(slice.bunker_yaw, 0.0), "%.0f" % slice.bunker_yaw)

	_check("the slice names exactly the six authored cores",
		slice.cores_by_node.size() == CORES.size(),
		"%d" % slice.cores_by_node.size())
	var wrong: Array[String] = []
	for named in CORES:
		if int(slice.cores_by_node.get(named, -1)) != int(CORES[named]):
			wrong.append("%s=%s want %d" % [named,
				str(slice.cores_by_node.get(named, "nothing")), int(CORES[named])])
	_check("every core's tier matches its prefab", wrong.is_empty(),
		str(wrong) if not wrong.is_empty() else "")


## The operation ends at the bunker, so the gate must not open before it.
func _exit(level: Node) -> void:
	var ex := _find(level, "LevelExit")
	if ex == null:
		_check("the level has a LevelExit", false)
		return
	_check("the level has a LevelExit", true)
	_check("the way out waits for the operation",
		"requires_objectives_complete" in ex and ex.requires_objectives_complete)


## None of the six are compulsory — the lane design hands you 1, 2 or 2 of them
## and the operation is won at the bunker regardless. Required captures would
## make a centre-lane run unfinishable.
func _optional(level: Node) -> void:
	var bad: Array[String] = []
	for named in CORES:
		var host := _find(level, named)
		if host == null:
			continue
		if not ("optional" in host) or not host.optional:
			bad.append(named)
	_check("all six captures are optional", bad.is_empty(),
		"compulsory: %s" % str(bad) if not bad.is_empty() else "")


# ── The missions ─────────────────────────────────────────────────────────────

func _mission(m, tags: Dictionary, routes: Dictionary, label: String) -> void:
	if m == null:
		_check("%s mission loads" % label, false)
		return
	_check("%s mission loads" % label, true, String(m.id))
	_check("%s points at the redoubt level" % label,
		m.level_scene != null and String(m.level_scene.resource_path) == LEVEL)

	var bad: Array[String] = []
	for spec in m.enemy_force:
		if spec == null:
			continue
		if spec.route_tag != &"":
			if not routes.has(String(spec.route_tag)):
				bad.append("%s route=%s" % [spec.callsign, spec.route_tag])
			continue
		if spec.post_tag != &"" and not tags.has(String(spec.post_tag)):
			bad.append("%s post=%s" % [spec.callsign, spec.post_tag])
		if spec.spawn_tag != &"" and not tags.has(String(spec.spawn_tag)):
			bad.append("%s spawn=%s" % [spec.callsign, spec.spawn_tag])
	_check("every %s spec resolves to a real anchor" % label, bad.is_empty(),
		str(bad) if not bad.is_empty() else "%d specs" % m.enemy_force.size())

	# An ADVANCE spec is the one that walks, and a spec that walks has to be
	# allowed to — see EnemyForceSpawner._let_them_walk_in.
	var lazy: Array[String] = []
	for spec in m.enemy_force:
		if spec != null and spec.posture == 2 and not spec.always_active:
			lazy.append(String(spec.callsign))
	_check("every %s ADVANCE spec is always_active" % label, lazy.is_empty(),
		str(lazy) if not lazy.is_empty() else "")

	# A RESERVE WAKES ON AN OBJECTIVE ID, not on a tag of its own invention:
	# Campaign._on_objective_changed passes the completed objective's id
	# straight to wake(). A reinforcement_tag naming anything else is silent —
	# the wave simply never arrives — so every one is checked against the
	# objectives this mission actually turns on.
	var live := {}
	for o in m.active_objectives:
		live[String(o)] = true
	var orphan: Array[String] = []
	for spec in m.enemy_force:
		if spec == null or spec.posture != 3:
			continue
		if spec.reinforcement_tag == &"" or not live.has(String(spec.reinforcement_tag)):
			orphan.append("%s waits on %s" % [spec.callsign, spec.reinforcement_tag])
	_check("every %s reserve waits on a live objective" % label, orphan.is_empty(),
		str(orphan) if not orphan.is_empty() else "")


func _location() -> void:
	var loc = load(LOC)
	if loc == null:
		_check("the location loads", false)
		return
	_check("the location loads", true, String(loc.id))
	_check("it names the attack", loc.mission_id == &"hfw_1_fort")
	_check("it names the defence", loc.defend_mission_id == &"hfw_2_defend")

	var cat = load(CATALOGUE)
	var ids: Array[StringName] = []
	for l in cat.locations:
		if l != null:
			ids.append(l.id)
	_check("it is in the catalogue", ids.has(&"hillfort_wip"))

	# RECIPROCAL, both ways. A one-way edge is a frontier the player can cross
	# in one direction and not the other, and nothing complains.
	for other in loc.connects_to:
		var o = _loc_by_id(cat, other)
		if o == null:
			_check("  connects_to %s exists" % other, false)
			continue
		_check("  connects_to %s is reciprocal" % other, o.connects_to.has(loc.id))


## The whole reason this map exists is to be compared with Hillfort, which only
## works if the two cost the same to beat.
func _economy() -> void:
	var a = load(ATTACK)
	var hf = load(HILLFORT)
	if a == null or hf == null:
		_check("both first missions load for comparison", false)
		return
	_check("supply matches hillfort_1_relay", _supply(a) == _supply(hf),
		"redoubt %d vs hillfort %d" % [_supply(a), _supply(hf)])

	# The quick lane has one core on it and the slow lanes have two, so taking
	# the quick one has to pay less. If it ever pays more, the map's central
	# choice has quietly inverted.
	var pay := _rewards()
	var centre: int = int(pay.get("hfw_pillars", 0))
	var west: int = int(pay.get("hfw_cistern", 0)) + int(pay.get("hfw_shoulder", 0))
	var east: int = int(pay.get("hfw_gatehouse", 0)) + int(pay.get("hfw_terrace", 0))
	_check("the fast lane pays least", centre < west and centre < east,
		"centre %d, west %d, east %d" % [centre, west, east])
	_check("the gated lane pays most", east > west, "east %d, west %d" % [east, west])
	_check("the relay is the richest single core",
		int(pay.get("hfw_relay", 0)) > centre,
		"relay %d" % int(pay.get("hfw_relay", 0)))


func _supply(m) -> int:
	var total := 0
	for spec in m.enemy_force:
		if spec == null:
			continue
		for c in spec.roster:
			if c != null:
				total += int(c.supply)
	return total


## Read off the level file rather than duplicated here, so the check cannot
## drift away from the thing it is checking.
func _rewards() -> Dictionary:
	var out := {}
	var f := FileAccess.open(LEVEL, FileAccess.READ)
	if f == null:
		push_warning("test_hillfort_wip: cannot read the level file, so the reward shape is unchecked.")
		return out
	var cur := ""
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("id = &\"hfw_"):
			cur = line.substr(7).replace("\"", "").strip_edges()
		elif line.begins_with("reward_resources = ") and cur != "":
			out[cur] = int(line.substr(19))
			cur = ""
	return out


# ── Looking things up ────────────────────────────────────────────────────────

func _loc_by_id(cat, id: StringName):
	for l in cat.locations:
		if l != null and l.id == id:
			return l
	return null


func _tags(level: Node) -> Dictionary:
	var out := {}
	for n in _all(level):
		if n is SquadObjectivePoint and String(n.tag) != "":
			out[String(n.tag)] = true
	return out


func _routes(level: Node) -> Dictionary:
	var out := {}
	for n in _all(level):
		if n is PatrolPath and String(n.tag) != "":
			out[String(n.tag)] = true
	return out


func _find(level: Node, named: String) -> Node:
	for n in _all(level):
		if String(n.name) == named:
			return n
	return null


func _all(n: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out
