extends SceneTree
# ─────────────────────────────────────────────
# HOW MUCH WALKABLE DECK IS LEFT ON EACH BRIDGE?
#
# cell_size went 0.25 -> 0.5 for the query-cost win. A coarser grid quantises
# the navmesh boundary to 0.5m steps, so a deck that is not aligned to the grid
# can lose up to half a metre a side — which on a bridge is the difference
# between a rover crossing and a rover scraping the parapet.
#
# Samples across each bridge and reports how wide the navigable strip is, for
# the bake on disk and for a 0.25 and 0.4 bake made in memory.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_bridge_width.gd
# ─────────────────────────────────────────────
const BRIDGES := [
	["Br05 south", Vector3(12, 0, 190), Vector3(1, 0, 0)],
	["Br04 central", Vector3(21, 0, 2.7), Vector3(1, 0, 0)],
	["Br03 west", Vector3(-122, 0, -38), Vector3(1, 0, 0)],
	["Br02 isle", Vector3(-17, 0, -207), Vector3(1, 0, 0)],
	["Br01 north", Vector3(-36, 0, -381), Vector3(1, 0, 0)],
	["East bridge", Vector3(340, 0, 153), Vector3(0, 0, 1)],
]

func _all(n: Node, cls: String, out: Array) -> void:
	if n.get_class() == cls:
		out.append(n)
	for c in n.get_children():
		_all(c, cls, out)

## Walkable width across the deck, sampled every 10cm out from the centre line.
func _width(map: RID, at: Vector3, across: Vector3) -> float:
	var centre := NavigationServer3D.map_get_closest_point(map, at)
	if centre.distance_to(at) > 6.0:
		return -1.0   # no navmesh anywhere near: not a crossing any more
	var span := 0.0
	for side in [1.0, -1.0]:
		var d := 0.1
		while d < 12.0:
			var p: Vector3 = centre + across * d * side
			var on := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(on.x - p.x, on.z - p.z).length() > 0.35:
				break
			d += 0.1
		span += d
	return span

func _init() -> void:
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	var lvl: Node = load("res://maps/mutaha_wip_level.tscn").instantiate()
	root.add_child(lvl)
	for _i in 180:
		await physics_frame
	var regions: Array = []
	_all(lvl, "NavigationRegion3D", regions)
	var region: NavigationRegion3D = regions[0]
	var original: NavigationMesh = region.navigation_mesh
	var map := region.get_navigation_map()

	var cells := [original.cell_size, 0.25, 0.4]
	var results := {}
	for cs in cells:
		if cs != original.cell_size:
			var copy: NavigationMesh = original.duplicate(true)
			copy.cell_size = cs
			copy.agent_radius = maxf(0.4, cs)
			region.navigation_mesh = copy
			NavigationServer3D.map_set_cell_size(map, cs)
			region.bake_navigation_mesh(false)
			for _i in 150:
				await physics_frame
		else:
			NavigationServer3D.map_set_cell_size(map, cs)
			for _i in 60:
				await physics_frame
		var row := []
		for b in BRIDGES:
			row.append(_width(map, b[1], b[2]))
		results[cs] = row

	print("")
	print("  WALKABLE DECK WIDTH, metres        %s" % " ".join(cells.map(func(c): return "cell %.2f" % c)))
	for i in BRIDGES.size():
		var line := "  %-20s" % BRIDGES[i][0]
		for cs in cells:
			var w: float = results[cs][i]
			line += "   %8s" % ("none" if w < 0.0 else "%.1f m" % w)
		print(line)
	print("")
	print("  (memory-only bakes; nothing written)")
	quit(0)
