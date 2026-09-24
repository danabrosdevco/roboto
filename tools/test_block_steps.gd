extends SceneTree

# ─────────────────────────────────────────────
# TEST BLOCK STEPS — find the risers a robot cannot climb.
#
#   godot --path . --script res://tools/test_block_steps.gd
#   FOLDER=ground godot --path . --script res://tools/test_block_steps.gd
#
# NOT headless: it raycasts, which needs a real renderer to have built the
# collision. It opens a window for a few seconds.
#
# WHY. move_and_slide has no step-up: a slope up to floor_max_angle is
# walkable and anything steeper is a WALL, at any height. The navmesh baker
# does not know that — it climbs 0.25 m happily — so a piece built as stacked
# courses gets a mesh over the top of it that the bodies cannot reach, and
# the squad stands at the bottom of a plinth the mesh says they are on.
#
# HOW. Bake the piece's navmesh, then scan lines of rays straight down across
# it, 0.1 m apart. Between two neighbouring samples, a rise of more than
# RISE_MAX is steeper than about 38 degrees, which is a face rather than a
# slope.
#
# A FACE ONLY COUNTS IF THERE IS NAVMESH ON TOP OF IT. Every wall, crate,
# barrel and machine leg in the kit is a face a body cannot climb, and that is
# what they are FOR — the mesh carves round them and the squad walks past.
# The defect is the other case: the mesh lays walkable ground on top of a riser
# and then sends the squad to stand somewhere they cannot reach. Without that
# filter this test reports 114 of 150 pieces and is no use to anyone.
#
# A piece that reports nothing is one the squad can walk over. A piece that
# reports a riser either wants a ramp, or wants its collision made steep
# enough that the navmesh carves round it instead (see clip_block).
# ─────────────────────────────────────────────

## Samples this far apart along each scan line.
const STEP := 0.1
## A rise bigger than this between two samples is a face, not a slope.
const RISE_MAX := 0.08
## Only risers whose top is below this matter: above it, nothing is walking up
## anyway and the mesh has no business there either.
const REACH := 1.6
## Scan lines each way.
const LINES := 33

var space: PhysicsDirectSpaceState3D
var nav_map: RID


func _initialize() -> void:
	await process_frame
	var folder := "res://maps/blocks/%s" % (OS.get_environment("FOLDER") if OS.get_environment("FOLDER") != "" else "")
	var families: Array = []
	if OS.get_environment("FOLDER") != "":
		families = [OS.get_environment("FOLDER")]
	else:
		for d in DirAccess.get_directories_at("res://maps/blocks"):
			if d != "autosave":
				families.append(d)
		families.sort()
	print("   samples %.2f m apart, a rise over %.2f m is a face, tops under %.1f m count" % [
			STEP, RISE_MAX, REACH])
	var total := 0
	for fam: String in families:
		var dir := "res://maps/blocks/%s" % fam
		var names: Array = []
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".tscn"):
				names.append(f.get_basename())
		names.sort()
		for n: String in names:
			total += await _scan(dir, n)
	print("   %d piece(s) with a riser a body cannot climb" % total)
	quit()


func _scan(dir: String, piece_name: String) -> int:
	var packed := load(dir.path_join(piece_name + ".tscn")) as PackedScene
	if packed == null:
		return 0
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	world.add_child(floor_body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(200.0, 1.0, 200.0)
	cs.shape = bs
	cs.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(cs)
	var region := NavigationRegion3D.new()
	world.add_child(region)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.6
	nm.agent_height = 1.5
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	nm.cell_size = 0.25
	nm.region_min_size = 4.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.filter_baking_aabb = AABB(Vector3(-60.0, -6.0, -60.0), Vector3(120.0, 40.0, 120.0))
	region.navigation_mesh = nm
	floor_body.reparent(region)
	var piece := packed.instantiate() as Node3D
	region.add_child(piece)
	for _i in 6:
		await physics_frame
	region.bake_navigation_mesh(false)
	for _i in 4:
		await physics_frame
	nav_map = region.get_navigation_map()
	space = world.get_world_3d().direct_space_state

	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in piece.find_children("*", "CollisionShape3D", true, false):
		var shape: Shape3D = (c as CollisionShape3D).shape
		if shape == null:
			continue
		var aabb := shape.get_debug_mesh().get_aabb()
		var t := (c as CollisionShape3D).global_transform
		for i in 8:
			var w := t * aabb.get_endpoint(i)
			lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
			hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
	var worst := 0.0
	var count := 0
	if lo.x < hi.x:
		lo -= Vector2(0.4, 0.4)
		hi += Vector2(0.4, 0.4)
		for axis in 2:
			var across: float = hi.y - lo.y if axis == 0 else hi.x - lo.x
			for k in LINES:
				var t: float = (k + 0.5) / LINES
				var prev := INF
				var along: float = hi.x - lo.x if axis == 0 else hi.y - lo.y
				var n := int(along / STEP) + 1
				for i in n:
					var d: float = lo.x + i * STEP if axis == 0 else lo.y + i * STEP
					var o: float = lo.y + t * across if axis == 0 else lo.x + t * across
					var p := Vector3(d, 0.0, o) if axis == 0 else Vector3(o, 0.0, d)
					var y := _ground(p)
					if not is_nan(y) and not is_inf(prev):
						var rise: float = absf(y - prev)
						var top: float = maxf(y, prev)
						if rise > RISE_MAX and top < REACH and top > 0.02 and _meshed(Vector3(p.x, top, p.z)):
							count += 1
							worst = maxf(worst, rise)
					prev = y if not is_nan(y) else INF
	world.queue_free()
	await process_frame
	if count == 0:
		return 0
	print("   %-34s %4d riser sample(s), worst %.2f m" % [
			"%s/%s" % [dir.get_file(), piece_name], count, worst])
	return 1


## Height of whatever is under a point, or NAN if nothing is.
func _ground(p: Vector3) -> float:
	var from := p + Vector3.UP * 30.0
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0)
	var hit := space.intersect_ray(q)
	return (hit.position as Vector3).y if hit.has("position") else NAN


## Is there walkable mesh standing on this spot? 0.2 m out and 0.35 m up.
##
## The slack matters more than it looks. At half a metre a sample on top of a
## kerb finds the mesh on the ground beside it and reports a defect, which put
## 55 pieces on the list — every barrel, coil and light bar in the kit. It has
## to be tight enough that only mesh actually ON the riser counts.
func _meshed(p: Vector3) -> bool:
	var near := NavigationServer3D.map_get_closest_point(nav_map, p)
	return Vector2(near.x - p.x, near.z - p.z).length() < 0.2 and absf(near.y - p.y) < 0.35
