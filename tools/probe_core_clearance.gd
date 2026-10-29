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
	# hillfort_wip, NOT hillfort. The retired Hillfort also holds core prefabs,
	# which is why it sat here reading as live until 2026-10-26. K14 derived the
	# site probes from world.tscn; this list asks a different question (scenes
	# holding core prefabs, four of them gameplay/*_ops.tscn wrappers rather
	# than levels) so it stays typed — but it must name the LIVE fort.
	"res://maps/hillfort_wip_level.tscn",
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

## The three core prefabs, for the TICK mode.
const CORES := {
	"small": "res://maps/blocks/compute/compute_core_small.tscn",
	"med": "res://maps/blocks/compute/compute_core.tscn",
	"large": "res://maps/blocks/compute/compute_core_large.tscn",
}
const TICK := "res://Character/characters/ai/tick.tscn"
const TickPlaced := preload("res://tools/tick_placed.gd")
## Clearance is reported to this resolution: the test box is grown in 2 cm
## steps until it touches, which is honest about being a sweep rather than a
## distance function.
const GROW := 0.02
const GROW_MAX := 60


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
	if OS.get_environment("CORE_TICK") == "1":
		for id: String in CORES:
			await _tick(id)
		print("TICK DOCK: %s" % ("PASS" if _bad == 0 else "%d foul(s)" % _bad))
		quit(1 if _bad > 0 else 0)
		return
	var levels: Array = wanted if not wanted.is_empty() else LEVELS
	for path: String in levels:
		await _level(path)
	print("CORE CLEARANCE: %s" % ("PASS" if _bad == 0 else "%d clash(es)" % _bad))
	quit(1 if _bad > 0 else 0)


## DOES THE DRONE ACTUALLY FIT ON THE SHELF?
##
## The contract everybody has honoured is "the pad is 2.625 m across and
## nothing is directly above it", and the relay keeps it by construction. That
## was the whole question while the pad was a CENTRED CAP on a stem with open
## sky on four sides. On a CANTILEVERED SHELF it is the wrong question: the
## TICK is 3.23 m across placed and its four barbs reach 1.81 m from the axis,
## so a third of a metre of drone hangs past every pad edge — and on one of
## those edges the machine now continues upward.
##
## So this seats a real tick.tscn, in the real placed pose (tools/tick_placed.gd,
## which is build_tick.gd's documented state change and nothing invented), on
## the real Dock marker, and sweeps every one of its meshes against the core's
## own collision. Then it grows each box 2 cm at a time until something touches,
## which turns "it fits" into a number.
func _tick(id: String) -> void:
	var core: Node3D = (load(CORES[id]) as PackedScene).instantiate()
	root.add_child(core)
	var tick: Node3D = (load(TICK) as PackedScene).instantiate()
	root.add_child(tick)
	var moved := TickPlaced.seat(tick)
	var dock := core.get_node_or_null(^"Dock") as Node3D
	if dock == null:
		print("      %-6s NO DOCK MARKER — run tools/core_skeleton_dress.gd" % id)
		_bad += 1
		root.remove_child(core); core.free(); root.remove_child(tick); tick.free()
		return
	tick.global_position = dock.global_position + TickPlaced.LIFT
	for _i in 4:
		await process_frame
	await physics_frame

	var parts: Array = []
	_meshes(tick, parts)
	var space := (core.get_viewport() as Viewport).world_3d.direct_space_state
	var ex := _rids(tick)
	var pad_top: float = dock.global_position.y
	var worst := GROW * float(GROW_MAX)
	var fouled: Array = []
	var span := AABB()
	var first := true
	var barbs: Array = []
	for mi: MeshInstance3D in parts:
		var box := _world_aabb(mi)
		span = box if first else span.merge(box)
		first = false
		if String(mi.name) == "Barb":
			barbs.append(box)
		# THE TEST IS SPLIT AT THE PAD PLANE, and the first version was not —
		# which reported all four barbs fouling at every size and was measuring
		# the thing the drone is FOR. A barb is meant to come down 0.4 m outside
		# the edge and bite; an axis-aligned box round an angled barb therefore
		# always clips the deck corner. Above the pad plane there is no such
		# excuse: anything the drone puts up there has to be clear of the
		# machine, and that is the cantilever question nobody had asked.
		var upper := _clip_above(box, pad_top + 0.02)
		if upper.size.y <= 0.0:
			continue
		# GROWN SIDEWAYS ONLY. AABB.grow() expands in all six directions, and
		# every one of these boxes is sitting ON the pad — so the first 2 cm of
		# growth went straight down through the deck and every size came back
		# "clear by 0.02 m", which is a measurement of the floor. The question
		# is horizontal: how much further out could the drone reach before it
		# touched the machine beside it.
		var clear := 0.0
		for g in GROW_MAX + 1:
			var grow: float = float(g) * GROW
			if _hits(space, AABB(upper.position - Vector3(grow, 0.0, grow),
					upper.size + Vector3(grow * 2.0, 0.0, grow * 2.0)), ex):
				break
			clear = grow
		if clear <= 0.0 and _hits(space, upper, ex):
			fouled.append([String(mi.name), upper])
		worst = minf(worst, clear)
	print("      %-6s dock %s · %d joints posed · placed span %.2f x %.2f m, %.2f m tall"
			% [id, dock.position, moved, span.size.x, span.size.z, span.size.y])
	print("             %.2f m of drone past each pad edge · above the pad: %s"
			% [maxf(span.size.x, span.size.z) * 0.5 - 1.3125,
					("%d FOUL(S)" % fouled.size()) if not fouled.is_empty() else "clear by %.2f m or more" % worst])
	for f: Array in fouled:
		var b: AABB = f[1]
		print("                 FOUL %-10s world x %.2f..%.2f  z %.2f..%.2f  y %.2f..%.2f"
				% [f[0], b.position.x, b.end.x, b.position.z, b.end.z, b.position.y, b.end.y])
	if not fouled.is_empty():
		_bad += 1
	# AND WHAT EACH BARB IS ACTUALLY STANDING ON. A clamp that closes on thin
	# air is a different failure from one that closes on the machine, and on a
	# shelf with open sky on three sides it is the likely one. The tip is the
	# bottom centre of the barb's own box.
	#
	# THE RAY STARTS WELL ABOVE THE PAD AND NOT JUST ABOVE THE TIP, and the
	# difference is not pedantry: the barbs come down 5 to 11 cm BELOW the deck
	# surface — they are meant to, that is a clamp hooking an edge rather than
	# a foot standing on a floor — so a ray from tip + 0.1 m starts INSIDE the
	# slab. From inside a trimesh it either misses or reports the far side, and
	# this probe did both: it called a barb standing on 0.25 m of lip "NOTHING
	# UNDER IT" because its start was 6 mm under the deck top. Starting clear
	# above and comparing the surface to the tip says the true thing instead.
	for i in barbs.size():
		var b: AABB = barbs[i]
		var tip := Vector3(b.position.x + b.size.x * 0.5, b.position.y, b.position.z + b.size.z * 0.5)
		var top := maxf(pad_top, tip.y) + 0.60
		var rq := PhysicsRayQueryParameters3D.create(Vector3(tip.x, top, tip.z), Vector3(tip.x, tip.y - 3.0, tip.z))
		rq.exclude = ex
		var hit := space.intersect_ray(rq)
		var local: Vector3 = core.global_transform.affine_inverse() * tip
		var said := "NOTHING UNDER IT"
		if not hit.is_empty():
			var surf: float = (hit["position"] as Vector3).y
			# Over deck AT the pad surface is a grip; anything much lower is the
			# tray floor or the ground, which is not something to hook.
			said = ("on deck, tip %.2f m below the surface" % (surf - tip.y)) if absf(surf - pad_top) < 0.05 \
					else "over nothing nearer than %.2f m below the tip" % (tip.y - surf)
		print("                 barb %d at local (%.2f, %.2f, %.2f) — %s"
				% [i + 1, local.x, local.y, local.z, said])
	root.remove_child(tick)
	tick.free()
	root.remove_child(core)
	core.free()


func _hits(space: PhysicsDirectSpaceState3D, box: AABB, ex: Array[RID]) -> bool:
	var shape := BoxShape3D.new()
	shape.size = box.size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), box.position + box.size * 0.5)
	q.collide_with_areas = false
	q.exclude = ex
	return not space.intersect_shape(q, 1).is_empty()


## World AABB of one mesh, which is what a sweep needs: get_aabb() is local.
func _world_aabb(mi: MeshInstance3D) -> AABB:
	var local := mi.get_aabb()
	var xf := mi.global_transform
	var out := AABB(xf * local.position, Vector3.ZERO)
	for i in 8:
		out = out.expand(xf * (local.position + local.size * Vector3(
				float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))))
	return out


func _meshes(n: Node, out: Array) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.visible and mi.get_aabb().size != Vector3.ZERO:
		out.append(mi)
	for c in n.get_children():
		_meshes(c, out)


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


## The part of `box` above `y`, or a zero-height box if none of it is.
func _clip_above(box: AABB, y: float) -> AABB:
	if box.end.y <= y:
		return AABB(box.position, Vector3(box.size.x, 0.0, box.size.z))
	var lo: float = maxf(box.position.y, y)
	return AABB(Vector3(box.position.x, lo, box.position.z),
			Vector3(box.size.x, box.end.y - lo, box.size.z))
