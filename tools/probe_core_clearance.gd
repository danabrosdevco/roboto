extends SceneTree

# ─────────────────────────────────────────────
# DOES THE WIDER CORE STILL FIT WHERE THE NARROW ONE STOOD?
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_core_clearance.gd [-- <level> ...]
#
# tools/build_core_relay.gd grew the three cores from the shipped
# 1.88 / 3.38 / 5.18 m SQUARE to 4.50x3.50 / 6.00x4.75 / 8.25x6.50 m, because
# the human asked for wider and more imposing. Ten levels hold 42 of them and
# NOTHING IN THE PROJECT WOULD HAVE SAID A WORD if one of them now stands
# inside a wall: a FuncGodot prefab intersecting a building is not an error, it
# is just two meshes. Five small cores sit in one Pittsburgh street.
#
# So this sweeps a box the size of the NEW bund through each capture point's
# own position and reports what else is in it. It is a clearance check and not
# a navmesh check — a rebake is owed on every one of these levels regardless,
# because the bund is a 0.53 m sheer step and it moved.
#
# WHAT COUNTS AS A CLASH. Anything solid in the box that is not the core's own
# body and not the ground under it. The ground is excluded by raising the box
# 0.30 m: the bund's own plinth is 0.53 m tall, so a box from 0.30 to 0.70 m
# sits in the band a wall would occupy and above anything flat.
# ─────────────────────────────────────────────

const LEVELS := [
	"res://maps/pittsburgh_level.tscn",
	"res://maps/mutaha_wip_level.tscn",
	"res://maps/valley_basin_level.tscn",
	"res://maps/hillfort_level.tscn",
	"res://maps/coastal-road_level.tscn",
	"res://maps/appendix/mutaha_level.tscn",
	"res://maps/gameplay/causeway_ops.tscn",
	"res://maps/gameplay/georgetown_ops.tscn",
	"res://maps/gameplay/salient_ops.tscn",
	"res://maps/gameplay/polaris_ops.tscn",
]

## Godot X by Godot Z, which is map Y by map X — the SHORT side first. Getting
## these the wrong way round is the whole reason the wrapper scenes now carry a
## paragraph about it.
const FOOT := {
	"compute_core_point_small.tscn": Vector2(3.50, 4.50),
	"compute_core_point.tscn": Vector2(4.75, 6.00),
	"compute_core_point_large.tscn": Vector2(6.50, 8.25),
}

## CORE_FOOT=shipped|r1 MEASURES AN EARLIER TRIO INSTEAD, and this is the only
## reason the probe is worth keeping. "Three of Pittsburgh's five cores clash"
## is not a finding on its own: the cores stand where a 1.88 m one was dropped
## years of edits ago, nobody has measured one since, and a clash that was
## already there is a different piece of news from one this round caused. Run
## all three and diff the lists.
const EARLIER := {
	"shipped": [1.88, 3.38, 5.18],
	"r1": [3.25, 4.44, 6.31],
}

var _bad := 0
var _foot := FOOT.duplicate()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var era := OS.get_environment("CORE_FOOT")
	if EARLIER.has(era):
		var sq: Array = EARLIER[era]
		_foot = {
			"compute_core_point_small.tscn": Vector2(sq[0], sq[0]),
			"compute_core_point.tscn": Vector2(sq[1], sq[1]),
			"compute_core_point_large.tscn": Vector2(sq[2], sq[2]),
		}
		print("CORE CLEARANCE, measuring the '%s' footprints: %s" % [era, str(sq)])
	elif not era.is_empty():
		print("CORE CLEARANCE: CORE_FOOT='%s' is not one of %s — measuring the current cores" % [era, str(EARLIER.keys())])
	var wanted: Array = []
	for a in OS.get_cmdline_user_args():
		wanted.append(a)
	var levels: Array = wanted if not wanted.is_empty() else LEVELS
	for path: String in levels:
		await _level(path)
	print("CORE CLEARANCE: %s" % ("PASS" if _bad == 0 else "%d clash(es)" % _bad))
	quit(1 if _bad > 0 else 0)


func _level(path: String) -> void:
	if not ResourceLoader.exists(path):
		# Every early return warns: a level that has been renamed would
		# otherwise be silently skipped and read as a pass.
		print("  SKIP %s — no such scene" % path)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		print("  SKIP %s — would not load" % path)
		return
	var level: Node = packed.instantiate()
	root.add_child(level)
	for _i in 8:
		await process_frame
	await physics_frame
	var points: Array = []
	_find(level, points)
	var space := (level.get_viewport() as Viewport).world_3d.direct_space_state
	print("  %-44s %d capture point(s)" % [path.get_file(), points.size()])
	for p: Array in points:
		var node: Node3D = p[0]
		var foot: Vector2 = p[1]
		var shape := BoxShape3D.new()
		shape.size = Vector3(foot.x, 0.40, foot.y)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis(node.global_transform.basis.get_rotation_quaternion()),
				node.global_position + Vector3(0, 0.50, 0))
		q.collide_with_areas = false
		q.collision_mask = 0xFFFFFFFF
		q.exclude = _rids(node)
		var hits := space.intersect_shape(q, 16)
		var names: Array = []
		for h: Dictionary in hits:
			var c: Node = h.get("collider")
			if c == null or node.is_ancestor_of(c):
				continue
			names.append(String(c.name))
		if names.is_empty():
			continue
		_bad += 1
		print("      CLASH  %-26s at %s  <- %s" % [node.name, node.global_position, ", ".join(names)])
	root.remove_child(level)
	level.free()


func _rids(n: Node) -> Array[RID]:
	var out: Array[RID] = []
	var body := n as CollisionObject3D
	if body != null:
		out.append(body.get_rid())
	for c in n.get_children():
		out.append_array(_rids(c))
	return out


## Capture points, found by the scene file each one instances rather than by
## name: levels call them Core1, Objective, CapturePointA and worse.
func _find(n: Node, out: Array) -> void:
	var f: String = n.scene_file_path.get_file()
	if _foot.has(f):
		out.append([n as Node3D, _foot[f]])
	for c in n.get_children():
		_find(c, out)
