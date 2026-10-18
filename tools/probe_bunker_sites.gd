extends SceneTree

# ─────────────────────────────────────────────
# DOES EVERY SITE BUILD A REAL BUNKER NOW?
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_bunker_sites.gd
#
# site_slice._build_bunker() used to generate a 1.2 m glowing post on a slab.
# It now instances TERRAIN's entrance kit and hangs gameplay off the named
# handles inside it — TerminalFace, DockPad, ExitVolume, LeafLeft, LeafRight.
# Those names are a contract between two lanes, and a rename on either side
# breaks it silently: the bunker still builds, it just has no terminal, or no
# dock, or doors that never move.
#
# So this stands each slice up on its own level and asks the built thing.
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
	print("site         cores  bunker  dock   term  exit  doors  verdict")
	for name in SLICES:
		await _one(String(name), SLICES[name][0], SLICES[name][1])
	print("")
	print("%d problem(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _one(label: String, slice_path: String, level_path: String) -> void:
	var level = (load(level_path) as PackedScene).instantiate()
	root.add_child(level)
	for _i in 30:
		await physics_frame

	# Parented to the level, which is where a real one goes — site_slice
	# searches downward from get_parent() and sees nothing above it.
	var slice = Node3D.new()
	slice.set_script(load(slice_path))
	level.add_child(slice)
	for _i in 40:
		await physics_frame

	var bunker = slice.get_node_or_null(^"SiteBunker")
	var kit = bunker.get_node_or_null(^"Entrance") if bunker != null else null
	var hold = bunker.get_node_or_null(^"Hold") if bunker != null else null
	var cores: int = slice.operation.cores.size() if slice.operation != null else 0
	var dock: float = float(hold.dock_height) if hold != null else -1.0
	var term = bunker.get_node_or_null(^"Interactible") if bunker != null else null
	var way_out = _find(kit, "ExitVolume") if kit != null else null
	var leaves: bool = _find(kit, "LeafLeft") != null and _find(kit, "LeafRight") != null if kit != null else false

	var bad: Array = []
	if cores < 1:
		bad.append("no cores")
	if kit == null:
		bad.append("no entrance kit")
	if hold == null:
		bad.append("not holdable")
	elif dock <= 0.5:
		bad.append("dock %.2f" % dock)
	if term == null:
		bad.append("no terminal")
	if way_out == null:
		bad.append("no exit volume")
	if not leaves:
		bad.append("no doors")

	print("%-12s %5d  %-6s %5.2f  %-4s  %-4s  %-5s  %s" % [
		label, cores, "yes" if kit != null else "NO",
		dock, "yes" if term != null else "NO",
		"yes" if way_out != null else "NO", "yes" if leaves else "NO",
		"ok" if bad.is_empty() else "FAIL: " + str(bad)])
	if not bad.is_empty():
		_fails += 1

	level.queue_free()
	await process_frame


func _find(n: Node, named: String) -> Node:
	if n == null:
		return null
	if n.name == named:
		return n
	for c in n.get_children():
		var h := _find(c, named)
		if h != null:
			return h
	return null
