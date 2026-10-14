extends SceneTree

# ─────────────────────────────────────────────
# WHAT DOES THE BROADPHASE ACTUALLY COST? — the queries that really run.
#
#   LEVEL=res://maps/salient_level.tscn godot --audio-driver Dummy --path . \
#       --script res://tools/bench_block_collision.gd
#
#   TAG=before      label for the run, so two runs can be diffed by eye
#   REPS=4          how many times each family is swept (more = less noise)
#
# ── WHY THIS EXISTS ──────────────────────────
# tools/collapse_block_collision.gd turns 66 per-brush convex hulls into one
# trimesh and docs/briefs/BLOCK_COLLISION.md reports that as "45,881 -> 1,300
# shapes, 97% saved". That is a COUNT, and a count is not a frame time.
#
# Godot's broadphase — Jolt's, here; see project.godot — is a TREE. Query cost
# is roughly logarithmic in the number of shapes, so a 35x reduction in shapes
# buys about 1.5x fewer levels to descend, not 35x faster queries. Worse, the
# work does not vanish: it MOVES. A ConcavePolygonShape3D carries every
# triangle the 66 hulls described and keeps its own internal tree over them, so
# what leaves the broadphase arrives in the narrowphase. Memory and load time
# genuinely improve; per-query time may not move at all, and a shape sweep
# against a trimesh can be DEARER than against a convex.
#
# None of that is a reason not to do it. It is a reason not to do it for the
# wrong number. So this measures time.
#
# ── WHAT IT MEASURES, AND WHY THESE FOUR ─────
# Replicated from the real call sites, not invented. The brief named near-miss
# suppression as a per-shot broadphase query: IT IS NOT ONE ANY MORE.
# AIWeapon.suppress_along walks AI.SIGNAL_GROUP and does a dot product each
# (ai_weapon.gd:492-535); the sphere query object built in _ready() is dead
# code. Benching it would have measured something the game stopped doing. The
# four below are what is left, and all four are unmasked or masked to include
# layer 1, which is where every block's StaticBody3D lives:
#
#   los     enemy.gd:5062 is_path_clear  — the hottest. Every 0.15 s per awake
#           robot, NOT LOD-scaled, eye height 0.8, and Salient has 940 m
#           sightlines. If any family decides this, it is this one.
#   shot    ai_weapon.gd:441 the damage ray — 250 m, all layers, one per
#           pellet, plus up to 4 more in the friendly-fire loop at :345.
#   snap    ground_snap.gd:65 _surface — a 4 m vertical ray, 1 to 5 of them per
#           spawn and up to 4 passes each.
#   melee   ai_weapon.gd:555 check_melee_damage — a 0.6 m sphere 1.5 m along
#           the swing, intersect_shape(q, 16). THE ONE TO WATCH: a shape sweep
#           is where trimesh narrowphase is dearest, and it is the only family
#           here that is not a ray.
#
# ── TWO HOUSE RULES, BOTH OF WHICH HAVE COST SWEEPS BEFORE ──
# MEASURE CPU, NOT WALL CLOCK. Timing across `await physics_frame` reads the
# 16.67 ms tick and not the work, so every timer here brackets the query calls
# ONLY and never spans an await.
# PACE THE LOOP. Engine.max_fps = 60, or _process runs flat out, starves
# physics, and the number measured is the starvation.
#
# ── WHERE IT AIMS ────────────────────────────
# Uniform sampling over a 940 m map would spend most of its rays in open air
# and report the average of a question nobody asked. So queries are aimed TWICE
# and reported separately:
#   hot     origins taken from the real world positions of the instances of the
#           blocks being collapsed. This is the geometry that changes, so this
#           is where a regression would show.
#   broad   origins spread over the whole level AABB — the honest whole-map
#           figure, and the one that corresponds to a frame in play.
# An average over the two would hide whichever one matters. Per view, always.
# ─────────────────────────────────────────────

## Blocks that dominate the shape census (docs/briefs/BLOCK_COLLISION.md).
## "hot" origins are taken from where these actually stand.
const HOT_BLOCKS: Array[String] = [
	"feature_trench_revetment", "fort_razor_wire", "estate_u_block",
	"estate_collapsed_corner", "estate_frame_shell", "estate_slab_broken",
	"prop_sandbag_nest", "prop_power_pole", "alpine_stump",
]

## Queries per family per sweep. Big enough that one outlier cannot carry the
## number, small enough that a sweep fits in a frame's worth of work.
const N := 2000
## Eye height for the LOS family — enemy.gd uses UP * 0.8 at most call sites.
const EYE := 0.8
## ai_weapon.gd:441 hard-codes 250 m for the damage ray.
const SHOT_LEN := 250.0
## ground_snap.gd LOOK_UP / LOOK_DOWN.
const SNAP_UP := 1.5
const SNAP_DOWN := 2.5
## ai_weapon.gd melee_range / melee_radius. Nothing in the project overrides
## either, so every melee weapon in the game is exactly this.
const MELEE_RANGE := 1.5
const MELEE_RADIUS := 0.6
## ai_weapon.gd character_mask = 1|2|4|8. Worth saying plainly: layer 1 is
## GameWorld, which is where the blocks are, so this mask does NOT spare the
## level the way its own comment claims.
## MELEE_MASK overrides it, which is worth having because 14 — the same mask
## with GameWorld dropped — is a one-line change that costs no re-bake, and the
## point of this bench is to compare the collapse against the alternatives
## rather than against nothing.
const CHARACTER_MASK := 15

var _space: PhysicsDirectSpaceState3D
var _rng := RandomNumberGenerator.new()
var _tag: String
var _reps: int


func _init() -> void:
	# Headless (and windowed) runs _process flat out, which starves physics and
	# makes every number measured beside it a measurement of that instead.
	Engine.max_fps = 60

	_tag = OS.get_environment("TAG")
	if _tag == "":
		_tag = "run"
	_reps = 4
	if OS.get_environment("REPS") != "":
		_reps = maxi(1, int(OS.get_environment("REPS")))

	var path := OS.get_environment("LEVEL")
	if path == "":
		path = "res://maps/salient_level.tscn"

	var load_at := Time.get_ticks_usec()
	var packed: PackedScene = load(path)
	var load_us := Time.get_ticks_usec() - load_at
	if packed == null:
		printerr("could not load %s" % path)
		quit(1)
		return

	var inst_at := Time.get_ticks_usec()
	var level: Node = packed.instantiate()
	var inst_us := Time.get_ticks_usec() - inst_at

	root.add_child(level)
	# Let the physics server build its trees before asking it anything. A query
	# against a half-built broadphase is a measurement of the build.
	for _i in 30:
		await physics_frame

	_space = root.world_3d.direct_space_state
	if _space == null:
		printerr("no direct_space_state — physics is not up")
		quit(1)
		return

	var shapes := _count_shapes(level)
	var hot := _hot_origins(level)
	var aabb := _level_aabb(level)

	print("")
	print("══ bench_block_collision — TAG=%s ══" % _tag)
	print("  level            %s" % path.get_file())
	print("  CollisionShape3D %7d" % shapes)
	print("  load             %7.1f ms   (ResourceLoader)" % (load_us / 1000.0))
	print("  instantiate      %7.1f ms" % (inst_us / 1000.0))
	print("  static mem       %7.1f MB" % (float(OS.get_static_memory_usage()) / 1048576.0))
	print("  hot origins      %7d   (instances of the dominant blocks)" % hot.size())
	print("  level extent     %.0f x %.0f x %.0f m" % [aabb.size.x, aabb.size.y, aabb.size.z])

	if hot.is_empty():
		# Every early return warns: a bench that silently measures only half of
		# what it claims is worse than one that does not run.
		print("  !! no instances of the dominant blocks found — HOT VIEW SKIPPED.")
		print("     Either this is not Salient or HOT_BLOCKS is stale against the census.")

	# Sampled positions are fixed per view so the before and after runs ask the
	# physics server exactly the same questions. A bench that re-rolls its own
	# sample set between runs measures the dice.
	var views: Dictionary = {}
	if not hot.is_empty():
		views["hot"] = _points_near(hot, 12.0)
	views["broad"] = _points_in(aabb)

	print("")
	print("  %-7s %-7s %9s %9s %9s %9s" % ["view", "family", "us/query", "total ms", "hit %", "spread"])
	for view in views:
		var pts: PackedVector3Array = views[view]
		# AWAITED, every one. _report yields to pace the loop, so calling it
		# bare would start four sweeps that then interleave at their first
		# await and time each other's work.
		await _report(view, "los", _sweep_los.bind(pts))
		await _report(view, "shot", _sweep_shot.bind(pts))
		await _report(view, "snap", _sweep_snap.bind(pts))
		await _report(view, "melee", _sweep_melee.bind(pts))
	print("")
	quit(0)


## Runs one family _reps times and prints the MEDIAN per-query cost plus the
## spread across reps. The median rather than the mean because a single sweep
## that lands during a GC or a window repaint is not the cost of a query, and
## the spread is printed so a noisy run cannot be mistaken for a result.
func _report(view: String, family: String, fn: Callable) -> void:
	var per: Array[float] = []
	var hits := 0
	var total := 0
	for _r in _reps:
		# The timer brackets the query calls ONLY — never an await. Timing
		# across a frame boundary measures the 16.67 ms tick, not the work.
		var res: Array = fn.call()
		per.append(float(res[0]) / float(N))
		hits += int(res[1])
		total += N
		# Pace: give physics its frame back between sweeps, OUTSIDE the timer.
		await physics_frame
	per.sort()
	var mid: float = per[per.size() / 2]
	print("  %-7s %-7s %9.3f %9.3f %8.1f%% %9s" % [
		view, family, mid, mid * float(N) / 1000.0,
		float(hits) / float(total) * 100.0,
		"%.3f-%.3f" % [per[0], per[-1]]])


func _sweep_los(pts: PackedVector3Array) -> Array:
	# enemy.gd:5062 — create(from, to), exclude = self, default mask, areas off.
	var q := PhysicsRayQueryParameters3D.new()
	var hits := 0
	var at := Time.get_ticks_usec()
	for i in N:
		q.from = pts[i % pts.size()] + Vector3.UP * EYE
		q.to = pts[(i * 7 + 3) % pts.size()] + Vector3.UP * EYE
		if not _space.intersect_ray(q).is_empty():
			hits += 1
	return [Time.get_ticks_usec() - at, hits]


func _sweep_shot(pts: PackedVector3Array) -> Array:
	# ai_weapon.gd:441 — a 250 m ray, all layers.
	var q := PhysicsRayQueryParameters3D.new()
	var hits := 0
	var dirs := _dirs()
	var at := Time.get_ticks_usec()
	for i in N:
		q.from = pts[i % pts.size()] + Vector3.UP * EYE
		q.to = q.from + dirs[i % dirs.size()] * SHOT_LEN
		if not _space.intersect_ray(q).is_empty():
			hits += 1
	return [Time.get_ticks_usec() - at, hits]


func _sweep_snap(pts: PackedVector3Array) -> Array:
	# ground_snap.gd:65 — a 4 m vertical ray.
	var q := PhysicsRayQueryParameters3D.new()
	var hits := 0
	var at := Time.get_ticks_usec()
	for i in N:
		var p: Vector3 = pts[i % pts.size()]
		q.from = p + Vector3.UP * SNAP_UP
		q.to = p + Vector3.DOWN * SNAP_DOWN
		if not _space.intersect_ray(q).is_empty():
			hits += 1
	return [Time.get_ticks_usec() - at, hits]


func _sweep_melee(pts: PackedVector3Array) -> Array:
	# ai_weapon.gd:555 — a 0.6 m sphere 1.5 m along the swing, 16 results, mask 15.
	var shape := SphereShape3D.new()
	shape.radius = MELEE_RADIUS
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = CHARACTER_MASK
	if OS.get_environment("MELEE_MASK") != "":
		q.collision_mask = int(OS.get_environment("MELEE_MASK"))
	var hits := 0
	var dirs := _dirs()
	var at := Time.get_ticks_usec()
	for i in N:
		var swing: Vector3 = dirs[i % dirs.size()]
		q.transform = Transform3D(Basis(), pts[i % pts.size()] + Vector3.UP * EYE + swing * MELEE_RANGE)
		if not _space.intersect_shape(q, 16).is_empty():
			hits += 1
	return [Time.get_ticks_usec() - at, hits]


## A fixed ring of mostly-horizontal directions. Deterministic, so before and
## after fire the same shots.
func _dirs() -> PackedVector3Array:
	var out := PackedVector3Array()
	_rng.seed = 20261010
	for _i in 64:
		out.append(Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.3, 0.1),
				_rng.randf_range(-1.0, 1.0)).normalized())
	return out


## Origins scattered within `spread` of the dominant blocks' own positions, so
## the hot view asks about the geometry that is actually changing.
func _points_near(anchors: PackedVector3Array, spread: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	_rng.seed = 11235813
	for i in N:
		var a: Vector3 = anchors[i % anchors.size()]
		out.append(a + Vector3(_rng.randf_range(-spread, spread), _rng.randf_range(0.0, 3.0),
				_rng.randf_range(-spread, spread)))
	return out


## Origins over the whole level, at plausible standing heights rather than
## anywhere in a 200 m vertical box — a ray starting in the sky measures the
## sky.
func _points_in(aabb: AABB) -> PackedVector3Array:
	var out := PackedVector3Array()
	_rng.seed = 31415926
	var q := PhysicsRayQueryParameters3D.new()
	for _i in N:
		var x := _rng.randf_range(aabb.position.x, aabb.end.x)
		var z := _rng.randf_range(aabb.position.z, aabb.end.z)
		# Drop onto whatever is there so the sample stands on the map. If
		# nothing is under it, keep it at mid-height rather than discarding it:
		# open air is part of the whole-map picture.
		q.from = Vector3(x, aabb.end.y, z)
		q.to = Vector3(x, aabb.position.y, z)
		var hit := _space.intersect_ray(q)
		if hit.is_empty():
			out.append(Vector3(x, (aabb.position.y + aabb.end.y) * 0.5, z))
		else:
			out.append((hit.position as Vector3) + Vector3.UP * 1.0)
	return out


func _hot_origins(n: Node, out: PackedVector3Array = PackedVector3Array()) -> PackedVector3Array:
	if n is Node3D and n.scene_file_path != "":
		if HOT_BLOCKS.has(n.scene_file_path.get_file().get_basename()):
			out.append((n as Node3D).global_position)
	for c in n.get_children():
		_hot_origins(c, out)
	return out


## Extent taken from where the COLLISION is, not from VisualInstance3D.get_aabb().
## The dummy renderer hands back no surfaces — a headless run of this printed
## "Parameter m is null" out of mesh_get_surface_count and a zero-size box — and
## in any case the thing being benched is the collision world, so that is the
## box the samples belong in.
func _level_aabb(n: Node) -> AABB:
	var pts := PackedVector3Array()
	_shape_points(n, pts)
	if pts.is_empty():
		return AABB(Vector3(-500, -50, -500), Vector3(1000, 150, 1000))
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	return box


func _shape_points(n: Node, out: PackedVector3Array) -> void:
	if n is CollisionShape3D:
		out.append((n as CollisionShape3D).global_position)
	for c in n.get_children():
		_shape_points(c, out)


func _count_shapes(n: Node) -> int:
	var c := 1 if n is CollisionShape3D else 0
	for ch in n.get_children():
		c += _count_shapes(ch)
	return c
