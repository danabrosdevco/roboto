extends SceneTree

# ─────────────────────────────────────────────
# BRIDGE SPACING TESTS
#
# Two bridges in the same place look like a mistake, because they are one.
# Pittsburgh once had seventeen: sixteen of them stood within 20 m of another
# and eight pairs ran through each other, a long truss and a very long one
# overlapping by 24 m. Every one of them passed the navmesh checks — the squad
# could walk each deck — so nothing in the project said a word about it until
# the human saw a screenshot.
#
# A crossing list taken from the terrain has near-duplicates in it: a river
# bend offers the same crossing twice a few metres apart. Place one bridge per
# entry and they stack.
#
# Measured between the built geometry, not the origins. Each bridge becomes
# its deck centreline — the whole length, ramps included — with half its width
# either side, so a 94 m truss laid diagonally is judged by where it actually
# lies. Origin-to-origin says nothing about that.
#
# Reads the scenes without instantiating them: a level's terrain takes seconds
# to generate and none of it matters here.
# ─────────────────────────────────────────────

const LEVELS_DIR := "res://maps"
const BRIDGE_DIR := "res://maps/blocks/bridges/"
## The hand-made bridge that predates the kit; it counts too.
const HAND_MADE := ["res://maps/blocks/concrete_bridge.tscn"]
## Bridges closer than this are crowded. The human's rule, after the Pittsburgh
## pass: "get rid of all the bridges that have another bridge within like 20m".
## Raise it and levels get airier; lower it and pieces start to touch.
const MIN_GAP := 20.0
## A script error inside a check ends that coroutine without reaching quit(),
## and a headless SceneTree then idles for ever. The watchdog makes that loud.
const WATCHDOG_S := 240

var _fails := 0
## Bridge prefab path -> {"half_len": float, "half_w": float, "centre": Vector3}
var _shapes := {}


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_fails += 1


func _initialize() -> void:
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("FAIL  watchdog: the suite did not finish within %d s — a check probably crashed (see SCRIPT ERROR above)" % WATCHDOG_S)
		quit(2))
	await process_frame
	var levels := Array(DirAccess.get_files_at(LEVELS_DIR)).filter(
			func(f: String) -> bool: return f.ends_with(".tscn"))
	levels.sort()
	_check("there are levels in %s" % LEVELS_DIR, not levels.is_empty())
	for f: String in levels:
		_spacing(LEVELS_DIR.path_join(f))
	print("")
	print("ALL BRIDGE SPACING CHECKS PASS" if _fails == 0 else "%d BRIDGE SPACING CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


## Every bridge in one level, each against every other.
func _spacing(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		_check("%s loads" % path.get_file(), false, "load(%s) returned null" % path)
		return
	var bridges := _bridges_in(packed.get_state())
	if bridges.is_empty():
		return
	var name := path.get_file().get_basename()
	var worst := 1e9
	var worst_detail := ""
	for i in bridges.size():
		for j in range(i + 1, bridges.size()):
			var a: Dictionary = bridges[i]
			var b: Dictionary = bridges[j]
			var near := Geometry3D.get_closest_points_between_segments(a.a, a.b, b.a, b.b)
			var gap: float = (near[0] as Vector3).distance_to(near[1]) - a.hw - b.hw
			if gap < worst:
				worst = gap
				worst_detail = "%s (%s) and %s (%s) are %s" % [a.name, a.kind, b.name, b.kind,
						"%.1f m apart" % gap if gap >= 0.0 else "INSIDE each other by %.1f m" % -gap]
	_check("%s: %d bridge(s), none within %.0f m of another" % [name, bridges.size(), MIN_GAP],
			worst >= MIN_GAP, worst_detail)


## The bridge instances in a scene, as world-space deck centrelines. Read from
## the SceneState, so nothing is built and no _ready() runs.
func _bridges_in(state: SceneState) -> Array:
	# Every node's own transform first, so a bridge under a moved parent lands
	# where it really is.
	var local := {}
	for i in state.get_node_count():
		var xform := Transform3D.IDENTITY
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == "transform":
				xform = state.get_node_property_value(i, p)
				break
		local[String(state.get_node_path(i))] = xform
	var found: Array = []
	for i in state.get_node_count():
		var inst := state.get_node_instance(i)
		if inst == null:
			continue
		var res := inst.resource_path
		if not res.begins_with(BRIDGE_DIR) and not HAND_MADE.has(res):
			continue
		var shape := _shape_of(res)
		if shape.is_empty():
			continue
		var node_path := String(state.get_node_path(i))
		var world := _world_of(node_path, local)
		var centre: Vector3 = shape.centre
		var half: float = shape.half_len
		found.append({
			"name": node_path.get_file(),
			"kind": res.get_file().get_basename(),
			"a": world * (centre - Vector3(0.0, 0.0, half)),
			"b": world * (centre + Vector3(0.0, 0.0, half)),
			"hw": shape.half_w,
		})
	return found


## A node's transform composed with every ancestor's.
func _world_of(node_path: String, local: Dictionary) -> Transform3D:
	var world := Transform3D.IDENTITY
	var walked := ""
	for part in node_path.split("/", false):
		walked = part if walked == "" else walked + "/" + part
		world = world * (local.get(walked, Transform3D.IDENTITY) as Transform3D)
	return world


## How long and wide a bridge prefab is, in its own space. Built once per kind.
func _shape_of(res: String) -> Dictionary:
	if _shapes.has(res):
		return _shapes[res]
	var packed := load(res) as PackedScene
	if packed == null:
		_shapes[res] = {}
		return {}
	var node := packed.instantiate() as Node3D
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var piece := _relative(mi, node) * mi.get_aabb()
		box = piece if first else box.merge(piece)
		first = false
	node.free()
	if first:
		_shapes[res] = {}
		return {}
	# The bridges run along their own Z; X is the width.
	_shapes[res] = {"half_len": box.size.z * 0.5, "half_w": box.size.x * 0.5, "centre": box.get_center()}
	return _shapes[res]


## A descendant's transform in `top`'s space, without needing the tree to be
## inside a viewport.
func _relative(node: Node3D, top: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var walk := node
	while walk != null and walk != top:
		xform = walk.transform * xform
		walk = walk.get_parent() as Node3D
	return xform
