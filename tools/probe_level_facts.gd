extends SceneTree
# REPORTS: prints the table Reference/Levels.md asserts, and asserts nothing

# ─────────────────────────────────────────────
# WHAT EACH LEVEL SCENE IS, WHAT LOADS IT, AND WHAT IT OFFERS THE CODE THAT
# LOOKS THINGS UP IN IT BY NAME.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_level_facts.gd
#   ... -- --no-art-test      skip the missing-art experiment at the end
#
# The vault note `Reference/Levels.md` is written from this and names it in its
# `verified-by`. Re-run it before trusting the note.
#
# ONE ROW PER SCENE, AND EVERY SCENE — not a list. Every `.tscn` directly under
# maps/ and maps/appendix/ that is not `_art`, plus anything else whose root is
# a TrenchBroomLevel. A list in here would drift the first time TERRAIN added a
# map, and a drifted list still prints a tidy table.
#
# LIVE HAS TWO ROUTES, so both are printed. The game loads a level through
# Env/world.tscn — its `missions` array and its `base_level` — and the
# Laboratory loads one through Managers/lab.gd's ARENA or a LabPlan's `level`.
# Everything else that names the file is a tool or a suite: it keeps the file
# alive as a FIXTURE, not as content, and it is counted separately so "nothing
# loads it" is never concluded from the first column alone.
#
# BUILD HAS TWO ROUTES TOO, and on most sites it is BOTH. A GeneratedTerrain
# node is the heightfield route; a FuncGodotMap is the TrenchBroom route — and
# every block prefab under maps/blocks/ is one, so a terrain site's buildings
# are brushes. Counted through the art instance, because the level file alone
# shows neither: that is how a grep of the `_level` files once concluded "zero
# shipped sites use FuncGodot".
#
# STATIC ONLY. Each scene is instantiated and NOT added to the tree, so no
# _ready runs: nothing is raised, nothing is baked, nothing is pruned. That is
# deliberate — this asks what the file OFFERS. What a slice builds from it is
# probe_sites_live.gd's question, and what the tracker ends up holding is
# probe_mission_facts.gd's. The slice's lookups are replayed here by name with
# the same depth-first first-match search site_slice._find() uses.
#
# Writes nothing to the project. The missing-art experiment writes one scene to
# user:// and deletes it.
# ─────────────────────────────────────────────

const WORLD := "res://Env/world.tscn"
const LAB := "res://Managers/lab.gd"
const LAB_PLANS := "res://Campaign/lab/plans/"
const MISSION_DIRS := ["res://Campaign/missions/", "res://Campaign/missions/appendix/"]
const SCAN_DIRS := ["res://maps/", "res://maps/appendix/"]
const SLICE_BASE := "res://Env/world_objects/site_slice.gd"
const TERRAIN_SCRIPT := "res://Env/terrain/generated_terrain.gd"
## Where tools and suites live. Text-scanned for the file name.
const TOOL_DIR := "res://tools/"

## level path -> Array of "who loads it" strings, per route.
var _by_mission: Dictionary = {}
var _by_dead_mission: Dictionary = {}
var _by_base: Dictionary = {}
var _by_lab: Dictionary = {}


func _init() -> void:
	Engine.max_fps = 60   # a --script run has no frame cap; harmless here, house rule
	var levels := _level_scenes()
	if levels.is_empty():
		push_warning("probe_level_facts: found no level scenes under %s, so there is nothing to report." % str(SCAN_DIRS))
		quit(1)
		return

	_read_loaders()

	print("══ LEVELS — %d scenes ══" % levels.size())
	print("%-34s %-6s %-30s %-22s %-14s %-18s %s" % [
		"scene", "LIVE", "loaded by (game · lab)", "fixture for (tools)", "build", "navmesh", "slice"])
	var rows: Array = []
	for path in levels:
		rows.append(_row(path))
	for r in rows:
		print("%-34s %-6s %-30s %-22s %-14s %-18s %s" % [
			r.name, r.live, r.loaders, r.tools, r.build, r.nav, r.slice])

	print("")
	print("══ MARKERS — what each scene offers the code that looks things up ══")
	print("  root      TrenchBroomLevel exports: spawn_point / nav_region / level_exits (World reads these)")
	print("  ssp       SquadSpawnPoint (SquadSpawner: none ⇒ the squad does not deploy, warns)")
	print("  tags      SquadObjectivePoint tags (EnemyForceSpawner post_tag / spawn_tag)")
	print("  routes    PatrolPath tags (EnemyForceSpawner route_tag)")
	print("  exits / objs / cover   LevelExit · MissionObjective · CoverPoint counts")
	for r in rows:
		print("")
		print("%s" % r.name)
		for line in r.markers:
			print("  %s" % line)

	if not OS.get_cmdline_user_args().has("--no-art-test"):
		print("")
		print("══ WHAT HAPPENS WHEN THE ART IS MISSING ══")
		_missing_art_test()
	quit(0)


# ── the scene list ───────────────────────────────────────────────────────────

func _level_scenes() -> Array:
	var out: Array = []
	for dir_path in SCAN_DIRS:
		var d := DirAccess.open(dir_path)
		if d == null:
			push_warning("probe_level_facts: cannot open %s, so its scenes are not in the table." % dir_path)
			continue
		for f in d.get_files():
			# Godot leaves `*.tscn~RF*.TMP` beside edited scenes; they are not levels.
			if not f.ends_with(".tscn") or f.ends_with("_art.tscn"):
				continue
			var p: String = dir_path + f
			if f.ends_with("_level.tscn") or _root_is_level(p):
				out.append(p)
	out.sort()
	return out


## True if the root of the packed scene carries trench_broom_level.gd (or a
## script extending it). Read off the state, not by instancing, so an unrelated
## scene like railhead_station.tscn costs nothing.
func _root_is_level(path: String) -> bool:
	var ps := load(path) as PackedScene
	if ps == null:
		return false
	var st := ps.get_state()
	for p in st.get_node_property_count(0):
		if st.get_node_property_name(0, p) == &"script":
			var s = st.get_node_property_value(0, p)
			return s is Script and _extends(s, "res://maps/trench_broom_level.gd")
	return false


# ── who loads what ───────────────────────────────────────────────────────────

func _read_loaders() -> void:
	var packed := load(WORLD) as PackedScene
	if packed == null:
		push_warning("probe_level_facts: %s did not load, so the LIVE column is empty." % WORLD)
		return
	var st := packed.get_state()
	var live_ids := {}
	for i in st.get_node_count():
		for p in st.get_node_property_count(i):
			var pname := st.get_node_property_name(i, p)
			var v = st.get_node_property_value(i, p)
			if pname == &"missions":
				for m in v:
					if m != null and m.get("level_scene") != null:
						_add(_by_mission, m.level_scene.resource_path, String(m.id))
						live_ids[m.resource_path] = true
			elif pname == &"base_level" and v is PackedScene:
				_add(_by_base, v.resource_path, "base_level")

	# Missions on disk that world.tscn does not list. Not live; printed so a
	# level they point at is not mistaken for unreferenced.
	for dir_path in MISSION_DIRS:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for f in d.get_files():
			if not f.ends_with(".tres"):
				continue
			var mp: String = dir_path + f
			if live_ids.has(mp):
				continue
			var m = load(mp)
			if m != null and m.get("level_scene") != null:
				_add(_by_dead_mission, m.level_scene.resource_path, String(m.id))

	# THE LABORATORY — the second way into a level that is not a mission.
	var lab_src := FileAccess.get_file_as_string(LAB)
	var rx := RegEx.create_from_string("const ARENA := \"(res://[^\"]+)\"")
	var hit := rx.search(lab_src)
	if hit != null:
		_add(_by_lab, hit.get_string(1), "lab default")
	else:
		push_warning("probe_level_facts: no `const ARENA` in %s; the lab's default level is not counted." % LAB)
	var pd := DirAccess.open(LAB_PLANS)
	if pd != null:
		for f in pd.get_files():
			if f.ends_with(".tres"):
				var plan = load(LAB_PLANS + f)
				if plan != null and plan.get("level") != null:
					_add(_by_lab, plan.level.resource_path, "lab:" + f.get_basename())


func _add(into: Dictionary, path: String, who: String) -> void:
	if not into.has(path):
		into[path] = []
	if not (who in into[path]):
		into[path].append(who)


## Every tool or suite that names the file. Counted as suites (test_*) and the
## rest, because a suite keeping a level alive is a different claim from a probe.
func _tool_refs(path: String) -> Dictionary:
	# The project-relative path, not the bare file name: `tb_level.tscn` is a
	# substring of `test_01_tb_level.tscn`, and `valley_level.tscn` would match
	# whichever folder it is in.
	var file := path.trim_prefix("res://")
	var suites := 0
	var others := 0
	var d := DirAccess.open(TOOL_DIR)
	if d == null:
		return {"suites": 0, "others": 0}
	for f in d.get_files():
		if not (f.ends_with(".gd") or f.ends_with(".sh")) or f == "probe_level_facts.gd":
			continue
		if FileAccess.get_file_as_string(TOOL_DIR + f).contains(file):
			if f.begins_with("test_"):
				suites += 1
			else:
				others += 1
	return {"suites": suites, "others": others}


# ── one row ──────────────────────────────────────────────────────────────────

func _row(path: String) -> Dictionary:
	var r := {"name": path.trim_prefix("res://maps/"), "live": "-", "loaders": "-",
		"tools": "-", "build": "?", "nav": "?", "slice": "-", "markers": []}

	var game: Array = _by_base.get(path, []) + _by_mission.get(path, [])
	var lab: Array = _by_lab.get(path, [])
	if not game.is_empty():
		r.live = "BASE" if _by_base.has(path) else "yes"
	elif not lab.is_empty():
		r.live = "lab"
	var who: Array = []
	if not game.is_empty():
		who.append("%d op%s" % [game.size(), "" if game.size() == 1 else "s"] if not _by_base.has(path) else "world.tscn base")
	if not lab.is_empty():
		who.append(", ".join(lab))
	if _by_dead_mission.has(path):
		who.append("dead: " + ",".join(_by_dead_mission[path]))
	r.loaders = " · ".join(who) if not who.is_empty() else "-"
	var t := _tool_refs(path)
	r.tools = "%d suites, %d tools" % [t.suites, t.others]

	var ps := load(path) as PackedScene
	if ps == null:
		r.build = "LOAD FAIL"
		push_warning("probe_level_facts: %s did not load." % path)
		return r
	var root := ps.instantiate()
	if root == null:
		r.build = "INST FAIL"
		push_warning("probe_level_facts: %s did not instantiate." % path)
		return r

	var c := {"terrain": 0, "fg": 0, "regions": 0, "meshed": 0, "polys": 0,
		"ssp": [], "tags": [], "routes": [], "exits": 0, "objs": 0, "cover": 0,
		"slice": null, "names": {}, "first": {}, "art": []}
	_walk(root, c)

	# BUILD
	var parts: Array = []
	if c.terrain > 0:
		parts.append("terrain")
	if c.fg > 0:
		parts.append("brush×%d" % c.fg)
	r.build = "+".join(parts) if not parts.is_empty() else "neither"

	# NAVMESH — a region with a mesh with polygons. A region with no mesh is
	# how the live base is built, on purpose; see railhead_level.tscn.
	r.nav = "%d/%d regions, %d poly" % [c.meshed, c.regions, c.polys]

	# THE SLICE
	if c.slice != null:
		r.slice = String(c.slice.get_script().resource_path.get_file())

	# MARKERS
	var m: Array = r.markers
	var tbl := root as TrenchBroomLevel
	var root_script: Script = root.get_script()
	if tbl == null:
		m.append("root      NOT a TrenchBroomLevel (%s) — World's `as TrenchBroomLevel` cast would return null" % (
			root_script.resource_path if root_script != null else "no script"))
	else:
		m.append("root      %s · spawn_point=%s nav_region=%s level_exits=%d" % [
			root_script.resource_path.get_file(),
			"set" if tbl.spawn_point != null else "UNSET",
			"set" if tbl.nav_region != null else "unset",
			tbl.level_exits.size()])
	m.append("art       %s" % (", ".join(c.art) if not c.art.is_empty() else "none instanced"))
	m.append("ssp       %d %s" % [c.ssp.size(), str(c.ssp) if not c.ssp.is_empty() else ""])
	m.append("tags      %d%s" % [c.tags.size(), _dupes(c.tags)])
	m.append("routes    %d%s" % [c.routes.size(), _dupes(c.routes)])
	m.append("exits %d · objs %d · cover %d" % [c.exits, c.objs, c.cover])
	if c.slice != null:
		var s = c.slice
		var cores: Array = []
		for named in s.cores_by_node:
			cores.append(_found(c.names, String(named)))
		m.append("slice     cores: %s" % ", ".join(cores))
		m.append("          bunker: %s mount=%s" % [_found(c.names, String(s.bunker_marker)), String(s.bunker_mount)])
		# ENTRIES ARE FOUND BY NAME AND SPAWNED FROM BY TAG. EnemyCommander hands
		# the marker's `tag` to the spawner as spawn_tag, or its NODE NAME when it
		# has none — and _find_point matches tags only, so a name never resolves
		# and the reinforcement silently spawns at its post instead. Which node
		# the slice's first-match search lands on decides which happens.
		var ents: Array = []
		for named in s.entry_markers_named:
			var e := _found(c.names, String(named))
			var hit: Node = c.first.get(String(named), null)
			if hit != null:
				var etag: String = String(hit.tag) if "tag" in hit else ""
				e += (" → %s" % etag) if etag != "" else " → NO TAG"
			ents.append(e)
		m.append("          entries: %s" % ", ".join(ents))

	root.free()
	return r


## "Name" if found once, "Name×N" if the name repeats (the slice takes the
## first, depth-first, and says nothing), "Name MISSING" if absent.
func _found(names: Dictionary, n: String) -> String:
	var k: int = names.get(n, 0)
	if k == 0:
		return "%s MISSING" % n
	return n if k == 1 else "%s×%d" % [n, k]


func _dupes(tags: Array) -> String:
	var seen := {}
	var d: Array = []
	for t in tags:
		if seen.has(t) and not (t in d):
			d.append(t)
		seen[t] = true
	return "  DUPLICATE: %s" % str(d) if not d.is_empty() else ""


func _walk(n: Node, c: Dictionary) -> void:
	var nm := String(n.name)
	c.names[nm] = int(c.names.get(nm, 0)) + 1
	# Pre-order, like site_slice._find, so this is the node the slice gets.
	if not c.first.has(nm):
		c.first[nm] = n
	var s: Script = n.get_script()
	if n.scene_file_path.ends_with("_art.tscn"):
		c.art.append(n.scene_file_path.get_file())
	if s != null:
		if s.resource_path == TERRAIN_SCRIPT:
			c.terrain += 1
		if c.slice == null and _extends(s, SLICE_BASE):
			c.slice = n
	if n is FuncGodotMap:
		c.fg += 1
	if n is NavigationRegion3D:
		c.regions += 1
		var nm3 := (n as NavigationRegion3D).navigation_mesh
		if nm3 != null and nm3.get_polygon_count() > 0:
			c.meshed += 1
			c.polys += nm3.get_polygon_count()
	if n is SquadSpawnPoint:
		c.ssp.append(String(n.callsign))
	elif n is SquadObjectivePoint:
		c.tags.append(String(n.tag) if n.tag != &"" else "<untagged:%s>" % nm)
	elif n is PatrolPath:
		c.routes.append(String(n.tag) if n.tag != &"" else "<untagged:%s>" % nm)
	elif n is LevelExit:
		c.exits += 1
	elif n is MissionObjective:
		c.objs += 1
	elif n is CoverPoint:
		c.cover += 1
	for ch in n.get_children():
		_walk(ch, c)


func _extends(s: Script, base_path: String) -> bool:
	var cur := s
	while cur != null:
		if cur.resource_path == base_path:
			return true
		cur = cur.get_base_script()
	return false


# ── the experiment ───────────────────────────────────────────────────────────

## A level whose `_art` instance points at a file that does not exist: does it
## load, and does anything say so? Written to user://, never to the project.
func _missing_art_test() -> void:
	var dir := "user://probe_level_facts"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "/missing_art_level.tscn"
	var src := "\n".join([
		"[gd_scene load_steps=3 format=3]",
		"",
		"[ext_resource type=\"Script\" path=\"res://maps/trench_broom_level.gd\" id=\"1\"]",
		"[ext_resource type=\"PackedScene\" path=\"res://maps/does_not_exist_art.tscn\" id=\"2\"]",
		"",
		"[node name=\"ProbeLevel\" type=\"Node3D\"]",
		"script = ExtResource(\"1\")",
		"",
		"[node name=\"Art\" parent=\".\" instance=ExtResource(\"2\")]",
		""])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("probe_level_facts: cannot write %s, so the missing-art test did not run." % path)
		return
	f.store_string(src)
	f.close()
	var ps = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if ps == null:
		print("  load() returned null — the LEVEL fails to load when its art is missing.")
		print("  A mission naming it would hand World a null scene. (See the errors above this line.)")
	else:
		var inst = (ps as PackedScene).instantiate()
		print("  load() succeeded; instantiate() → %s; children: %s" % [
			inst, str(inst.get_children().map(func(x): return String(x.name))) if inst != null else "-"])
		if inst != null:
			inst.free()
	DirAccess.remove_absolute(path)
