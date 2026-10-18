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
# ─────────────────────────────────────────────

const SLICES := {
	"hillfort":   ["res://Env/world_objects/hillfort_slice.gd",   "res://maps/hillfort_level.tscn"],
	"coast":      ["res://Env/world_objects/coast_slice.gd",      "res://maps/coastal-road_level.tscn"],
	"rivers":     ["res://Env/world_objects/rivers_slice.gd",     "res://maps/pittsburgh_level.tscn"],
	"qamareen":   ["res://Env/world_objects/qamareen_slice.gd",   "res://maps/mutaha_wip_level.tscn"],
	"lockside":   ["res://Env/world_objects/lockside_slice.gd",   "res://maps/georgetown_level.tscn"],
	"polaris":    ["res://Env/world_objects/polaris_slice.gd",    "res://maps/polaris_level.tscn"],
	"causeway":   ["res://Env/world_objects/causeway_slice.gd",   "res://maps/causeway_level.tscn"],
	"trenchline": ["res://Env/world_objects/trenchline_slice.gd", "res://maps/salient_level.tscn"],
	"basin":      ["res://Env/world_objects/basin_slice.gd",      "res://maps/valley_basin_level.tscn"],
}

var _fails := 0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	for name in SLICES:
		await _one(String(name), SLICES[name][0], SLICES[name][1])
	print("")
	print("%d problem(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _one(label: String, slice_path: String, level_path: String) -> void:
	var packed := load(level_path) as PackedScene
	if packed == null:
		_bad("%s: cannot load %s" % [label, level_path])
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
