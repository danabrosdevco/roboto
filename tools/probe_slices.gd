extends SceneTree

# ─────────────────────────────────────────────
# DOES EVERY SLICE ACTUALLY FIND WHAT IT NAMES?
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_slices.gd
#
# site_slice._find() matches NODE NAMES. Every marker table in
# SITE_CONVERSION.md lists TAGS, and the two are different strings on every map
# — obj_hillfort_trailhead is a tag, Hillfort_Trailhead is the node. A slice
# written from those tables resolves nothing, falls back to a typed coordinate
# for the bunker and silently gets no entries at all, and the map plays exactly
# as it did before. Nothing errors.
#
# So this loads each level and asks the slice's own lookup for every name it
# carries, before any of them are wired into a mission.
#
# THE LIST IS DERIVED, NOT TYPED (backlog H14). It used to be a nine-row table
# in this file, and that table named the RETIRED maps/hillfort_level.tscn: the
# campaign has deployed maps/hillfort_wip_level.tscn since the Hillfort was
# rebuilt, so this probe printed a tidy `ok` about a level the game does not
# load and said nothing at all about the one it does. tools/_live_sites.gd now
# reads the levels off Env/world.tscn's `missions` array and the slice off each
# level, for the same reason the suite runner reads `# BUCKET:` off each suite
# rather than keeping its own list: a hand-kept list drifts the first time
# somebody forgets, and a drifted list still reports a pass.
# ─────────────────────────────────────────────

const Sites := preload("res://tools/_live_sites.gd")

var _fails := 0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	var skipped := Sites.sim_levels()
	if not skipped.is_empty():
		# Said out loud rather than dropped: a sim arena is a practice track and
		# carries no slice on purpose, so it is not a miss.
		print("sim arenas, not sites, skipped: %s" % ", ".join(skipped))
	for s in Sites.sites():
		await _one(s.label, s.script_path, s.level)
	print("")
	print("%d problem(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _one(label: String, slice_path: String, level_path: String) -> void:
	var packed := load(level_path) as PackedScene
	if packed == null:
		_bad("%s: cannot load %s" % [label, level_path])
		return
	# NO SLICE IS A FAULT, NOT A SKIP. A level regenerated from a template loses
	# the authored slice node with no error at all — that is the failure this
	# family of probes exists for, so it must not read as "not a site".
	if slice_path == "":
		_bad("%s: %s carries NO SLICE NODE, so it names nothing" % [label, level_path])
		return
	var level = packed.instantiate()
	root.add_child(level)
	for _i in 20:
		await process_frame

	# The slice's own values, read WITHOUT running _ready — this is about what
	# it names, not about what it builds.
	var slice = load(slice_path).new()
	slice._init()

	var missing: Array = []
	for node_name in slice.cores_by_node:
		if _find(level, String(node_name)) == null:
			missing.append("core:" + String(node_name))
	if _find(level, String(slice.bunker_marker)) == null:
		missing.append("bunker:" + String(slice.bunker_marker))
	for e in slice.entry_markers_named:
		if _find(level, String(e)) == null:
			missing.append("entry:" + String(e))

	print("%s  %-11s %d core(s), bunker '%s', %d entr(ies)%s" % [
		"ok  " if missing.is_empty() else "MISS",
		label, slice.cores_by_node.size(), String(slice.bunker_marker),
		slice.entry_markers_named.size(),
		"" if missing.is_empty() else "   NOT FOUND: " + str(missing)])
	if not missing.is_empty():
		_fails += 1
	slice.free()
	level.queue_free()
	await process_frame


func _find(n: Node, named: String) -> Node:
	if n.name == named:
		return n
	for c in n.get_children():
		var h := _find(c, named)
		if h != null:
			return h
	return null


func _bad(what: String) -> void:
	print("FAIL  %s" % what)
	_fails += 1
