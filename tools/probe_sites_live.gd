extends SceneTree

# ─────────────────────────────────────────────
# IS EVERY SITE ACTUALLY A SITE NOW — loading the level ALONE?
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_sites_live.gd
#
# probe_bunker_sites.gd stood each slice up by hand to test the kit. This one
# does not: it loads the nine levels exactly as the game does and asks whether
# the slice node authored INTO them built a site. If a .tscn edit is wrong, or
# a level is regenerated from a template and loses its slice, this is what says
# so — and that is the failure mode the recon warned about for Georgetown,
# Polaris and Trenchline, where a --force-level rebuild drops the node with no
# error at all.
# ─────────────────────────────────────────────

const LEVELS := {
	"hillfort":   ["res://maps/hillfort_level.tscn",     "HillfortSlice"],
	"coast":      ["res://maps/coastal-road_level.tscn", "CoastSlice"],
	"rivers":     ["res://maps/pittsburgh_level.tscn",   "RiversSlice"],
	"qamareen":   ["res://maps/mutaha_wip_level.tscn",   "QamareenSlice"],
	"lockside":   ["res://maps/georgetown_level.tscn",   "LocksideSlice"],
	"polaris":    ["res://maps/polaris_level.tscn",      "PolarisSlice"],
	"causeway":   ["res://maps/causeway_level.tscn",     "CausewaySlice"],
	"trenchline": ["res://maps/salient_level.tscn",      "TrenchlineSlice"],
	"basin":      ["res://maps/valley_basin_level.tscn", "BasinSlice"],
}

var _fails := 0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	print("site         slice  cores  bunker  operation  verdict")
	for name in LEVELS:
		await _one(String(name), LEVELS[name][0], LEVELS[name][1])
	print("")
	print("%d problem(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _one(label: String, level_path: String, node_name: String) -> void:
	var level = (load(level_path) as PackedScene).instantiate()
	root.add_child(level)
	for _i in 60:
		await physics_frame

	var slice = level.get_node_or_null(NodePath(node_name))
	var cores := 0
	var has_bunker := false
	var has_op := false
	if slice != null:
		has_op = slice.operation != null and is_instance_valid(slice.operation)
		if has_op:
			cores = slice.operation.cores.size()
			has_bunker = slice.operation.bunker != null
	var bad: Array = []
	if slice == null:
		bad.append("NO SLICE NODE IN THE LEVEL")
	else:
		if not has_op:
			bad.append("no operation")
		if cores < 1:
			bad.append("no cores")
		if not has_bunker:
			bad.append("no bunker")

	print("%-12s %-6s %5d  %-6s  %-9s  %s" % [
		label, "yes" if slice != null else "NO", cores,
		"yes" if has_bunker else "NO", "yes" if has_op else "NO",
		"ok" if bad.is_empty() else "FAIL: " + str(bad)])
	if not bad.is_empty():
		_fails += 1
	level.queue_free()
	await process_frame
