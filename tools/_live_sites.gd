# ─────────────────────────────────────────────
# WHICH SITES ARE LIVE — DERIVED, NEVER TYPED.
#
#   const Sites := preload("res://tools/_live_sites.gd")
#   for s in Sites.sites():
#       ... s.label, s.level, s.node, s.script_path
#
# WHY THIS EXISTS. Seven tools each carried their own copy of the same nine-row
# table of "site -> [level scene, slice node]". Hillfort was rebuilt as
# maps/hillfort_wip_level.tscn and the campaign moved to it; five of those
# tables were never updated, so they loaded the RETIRED maps/hillfort_level.tscn
# and printed a tidy `ok` about a level the game does not load (backlog H14).
# That is the same defect as a runner carrying its own list of suites instead of
# reading the `# BUCKET:` tag off each file — and the fix is the same one:
# READ THE TRUTH OUT OF THE FILES.
#
# WHERE THE TRUTH IS. `Env/world.tscn`'s `missions` array is what the campaign
# can deploy, per the vault's "Where the truth lives". NOT the
# Campaign/missions/ folder, which also holds missions that are on disk and not
# in the game (`arena_5_proving`), and not the maps/ folder, which holds retired
# and WIP levels as well.
#
# SIM ARENAS ARE NOT SITES. `MissionDefinition.sim` marks the practice track —
# no turn, no pay, no ground changes hands (§15) — and those levels carry no
# slice on purpose. They are excluded here and returned separately by
# `sim_levels()` so a caller can say what it skipped rather than skipping it in
# silence.
#
# THE SLICE IS DERIVED TOO, off each level, as the first node whose script
# extends site_slice.gd. A caller must still treat "no slice" as a FAILURE on a
# non-sim level: that is the regenerated-from-a-template failure mode
# probe_sites_live.gd exists to catch, and it must not become "not a site".
#
# ONE PIECE OF NOISE IT ADDS. Loading `world.tscn` pulls in the whole game's
# script graph, and `Character/characters/camera_3d.gd` references the
# `camera_switcher` autoload, which a bare `--script` run does not stand up. So
# every caller now prints one "Identifier not found: camera_switcher" compile
# error at startup. It is harmless here — nothing under maps/ or Env/ uses that
# script, and no caller instantiates world.tscn — and probe_level_facts.gd has
# printed the same line for as long as it has read the same array. Do not go
# hunting it.
#
# THE LABEL is the slice script's own name — coast_slice.gd -> "coast" — so the
# tables that used to be typed print the same row names they always did, with
# `hillfort` now reading `hillfort_wip` because that is the level the campaign
# actually loads.
# ─────────────────────────────────────────────

const WORLD := "res://Env/world.tscn"
const SLICE_BASE := "res://Env/world_objects/site_slice.gd"


## Every live site: {label, level, node, script_path}. `node` is "" and
## `script_path` is "" when the level carries no slice — which on a non-sim
## mission level is a fault, not a reason to drop the row.
## In campaign order, first appearance wins, one row per level.
static func sites() -> Array:
	var out: Array = []
	for level_path in mission_levels():
		var found := _slice_of(level_path)
		var label := ""
		if found.script_path != "":
			label = found.script_path.get_file().trim_suffix(".gd").trim_suffix("_slice")
		else:
			label = level_path.get_file().trim_suffix(".tscn").trim_suffix("_level")
		out.append({
			"label": label,
			"level": level_path,
			"node": found.node,
			"script_path": found.script_path,
		})
	return out


## The level scenes the campaign deploys into, sim arenas excluded, in the
## order `world.tscn` lists the missions, deduplicated — an attack and its
## defence share a map.
static func mission_levels() -> Array:
	return _levels(false)


## The practice-track levels, excluded from `sites()`. Print these rather than
## dropping them quietly.
static func sim_levels() -> Array:
	return _levels(true)


static func _levels(want_sim: bool) -> Array:
	var out: Array = []
	var packed := load(WORLD) as PackedScene
	if packed == null:
		push_error("_live_sites: %s did not load, so there is no live level list at all." % WORLD)
		return out
	var st := packed.get_state()
	for i in st.get_node_count():
		for p in st.get_node_property_count(i):
			if st.get_node_property_name(i, p) != &"missions":
				continue
			var missions = st.get_node_property_value(i, p)
			if missions == null:
				continue
			for m in missions:
				if m == null:
					push_warning("_live_sites: %s has a null entry in `missions`." % WORLD)
					continue
				if bool(m.get("sim")) != want_sim:
					continue
				var scene = m.get("level_scene")
				if scene == null:
					push_warning("_live_sites: mission '%s' has no level_scene, so it is in no table." % String(m.get("id")))
					continue
				var path: String = scene.resource_path
				if not (path in out):
					out.append(path)
	if out.is_empty():
		push_warning("_live_sites: found no %smission levels in %s — the `missions` array moved or is empty." % [
			"sim " if want_sim else "", WORLD])
	return out


## The first node in `level_path` whose script extends site_slice.gd, by node
## name and script path. Read off the packed state where it can be — that costs
## nothing — and only instantiates when the state scan comes up empty, which is
## what would happen if a slice were ever nested inside an instanced sub-scene.
static func _slice_of(level_path: String) -> Dictionary:
	var miss := {"node": "", "script_path": ""}
	var packed := load(level_path) as PackedScene
	if packed == null:
		push_warning("_live_sites: %s did not load, so its slice is unknown." % level_path)
		return miss
	var st := packed.get_state()
	for i in st.get_node_count():
		for p in st.get_node_property_count(i):
			if st.get_node_property_name(i, p) != &"script":
				continue
			var s = st.get_node_property_value(i, p)
			if s is Script and _extends(s, SLICE_BASE):
				return {"node": String(st.get_node_name(i)), "script_path": s.resource_path}

	# Not in this scene's own nodes. It could still be inside something this
	# level instances, and that only shows up on a real instantiate.
	var root := packed.instantiate()
	if root == null:
		push_warning("_live_sites: %s did not instantiate, so its slice is unknown." % level_path)
		return miss
	var hit := _walk_for_slice(root)
	var out := miss
	if hit != null:
		out = {"node": String(hit.name), "script_path": hit.get_script().resource_path}
	root.free()
	return out


static func _walk_for_slice(n: Node) -> Node:
	var s: Script = n.get_script()
	if s != null and _extends(s, SLICE_BASE):
		return n
	for c in n.get_children():
		var hit := _walk_for_slice(c)
		if hit != null:
			return hit
	return null


static func _extends(s: Script, base_path: String) -> bool:
	var cur := s
	while cur != null:
		if cur.resource_path == base_path:
			return true
		cur = cur.get_base_script()
	return false
