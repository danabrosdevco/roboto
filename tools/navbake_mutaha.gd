extends SceneTree
# ─────────────────────────────────────────────
# RE-BAKE QAMAREEN'S NAVMESH AT A COARSER cell_size.
#
# map_get_closest_point walks every polygon in the map. Qamareen's mesh is
# 29,760 of them at the default cell_size of 0.25, which is 0.690 ms a query
# against the proving ground's 0.025 ms — and every robot pays it.
#
# Measured in memory first (tools/probe_navbake.gd):
#   0.25  29760 poly  0.690 ms      0.50  17117 poly  0.414 ms
#   0.40  21854 poly  0.552 ms      0.75   9378 poly  0.225 ms
#
# WRITES A .tres, NOT THE LEVEL. The baked mesh is saved on its own so it can be
# spliced into the one sub_resource block in the .tscn by hand. Packing and
# re-saving the whole scene would rewrite 30,000 lines of someone else's level
# and is exactly the force-rebuild that has broken this map before.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/navbake_mutaha.gd -- <cell_size>
# ─────────────────────────────────────────────
const OUT := "res://maps/minimaps/_navbake_tmp.tres"

func _all(n: Node, cls: String, out: Array) -> void:
	if n.get_class() == cls:
		out.append(n)
	for c in n.get_children():
		_all(c, cls, out)

func _init() -> void:
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	var args := OS.get_cmdline_user_args()
	var cell: float = float(args[0]) if args.size() > 0 else 0.5

	var lvl: Node = load("res://maps/mutaha_wip_level.tscn").instantiate()
	root.add_child(lvl)
	for _i in 180:
		await physics_frame
	var regions: Array = []
	_all(lvl, "NavigationRegion3D", regions)
	if regions.is_empty():
		printerr("no NavigationRegion3D"); quit(1); return
	var region: NavigationRegion3D = regions[0]
	var nm: NavigationMesh = region.navigation_mesh
	print("  before: cell %.3f  agent_r %.2f  %d polygons" % [
		nm.cell_size, nm.agent_radius, nm.get_polygon_count()])

	var baked: NavigationMesh = nm.duplicate(true)
	baked.cell_size = cell
	# agent_radius cannot be finer than the grid the mesh is built on, or the
	# bake erodes the walkable surface away. It is also what decides which gaps
	# a robot is allowed down, so it is the half of this change that touches
	# gameplay — see the chassis widths in the report.
	baked.agent_radius = maxf(nm.agent_radius, cell)
	region.navigation_mesh = baked
	region.bake_navigation_mesh(false)
	for _i in 180:
		await physics_frame
	print("  after:  cell %.3f  agent_r %.2f  %d polygons" % [
		baked.cell_size, baked.agent_radius, baked.get_polygon_count()])
	if baked.get_polygon_count() < 1000:
		printerr("  BAKE COLLAPSED — refusing to write a mesh this small.")
		quit(1)
		return
	var err := ResourceSaver.save(baked, OUT)
	print("  wrote %s (%s)" % [OUT, error_string(err)])
	quit(0)
