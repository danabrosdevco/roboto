extends SceneTree

# ─────────────────────────────────────────────
# WHAT IS ACTUALLY WHERE ON SALIENT, AND CAN THE BIG FRAMES GET THERE.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_salient_art.gd
#
# The art is authored in GROUPS — the emplacements sit at local offsets under
# parents that carry the world transform, so reading transforms out of the
# .tscn gives you the offset and not the place. This loads the level and asks
# the nodes where they ended up.
#
# AND IT CHECKS CLEARANCE, which is the part a reachability probe cannot.
# Godot's navigation takes no agent radius at QUERY time: map_get_path returns
# the same line for a soldier and for a 320 hp Walker, so a post a rifleman
# strolls to can be one a Walker cannot physically enter. The only honest test
# is to sweep the chassis' own width along the path and see what it hits.
# ─────────────────────────────────────────────

const LEVEL := "res://maps/salient_level.tscn"

## Widths swept along each route, in metres (half-width).
const FRAMES := {
	"soldier": 0.45,
	"rover": 1.30,
	"walker": 1.90,
	"bulwark": 2.10,
}

## Emplacements worth knowing the position of.
const WANTED := ["mortar_pit", "sandbag_nest", "ammo_dump", "op_tower_ruin", "dragon_teeth"]


func _init() -> void:
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	for _i in 8:
		await process_frame
	await physics_frame

	var world: World3D = (level as Node3D).get_world_3d()
	var map: RID = world.navigation_map

	# ── emplacements ──────────────────────────
	var found := {}
	_gather(level, found)
	print("── EMPLACEMENTS (world positions) ──")
	for kind in WANTED:
		var list: Array = found.get(kind, [])
		if list.is_empty():
			continue
		print("  %s  x%d" % [kind, list.size()])
		list.sort_custom(func(a, b): return a.x < b.x)
		for p in list:
			print("     (%4.0f, %5.1f, %4.0f)" % [p.x, p.y, p.z])

	# ── posts, and what fits on the way ───────
	var spawn := Vector3(-468, 1, 20)
	print("")
	print("── CLEARANCE FROM SPAWN (half-width swept along the path) ──")
	var posts := {}
	for n in level.find_children("*", "", true, false):
		if n.get("tag") != null and String(n.get("tag")).begins_with("obj_salient"):
			posts[String(n.get("tag"))] = (n as Node3D).global_position
	var keys := posts.keys()
	keys.sort()
	for tag in keys:
		var to: Vector3 = posts[tag]
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, spawn, to, true)
		var pinch: Array = _narrowest(world, path)
		var r: float = float(pinch[0])
		var widest := "nothing"
		if r >= 2.1: widest = "bulwark"
		elif r >= 1.9: widest = "walker"
		elif r >= 1.3: widest = "rover"
		elif r >= 0.45: widest = "soldier"
		var miss: float = 999.0
		if path.size() > 0:
			miss = path[path.size() - 1].distance_to(to)
		print("  %-26s within %5.1fm   tightest %.2fm at (%.0f, %.0f) -> %s" % [
			tag, miss, r, (pinch[1] as Vector3).x, (pinch[1] as Vector3).z, widest])

	quit(0)


func _gather(n: Node, out: Dictionary) -> void:
	var name_lower := String(n.name).to_lower()
	for kind in WANTED:
		if name_lower.ends_with(kind) and n is Node3D:
			if not out.has(kind):
				out[kind] = []
			out[kind].append((n as Node3D).global_position)
	for c in n.get_children():
		_gather(c, out)


## The NARROWEST PINCH along the path, and where it is.
##
## "Is the whole corridor clear at this width" is the wrong question on this
## map: a 700 m route through 456 revetments and 117 coils of razor wire
## brushes something somewhere, and a single touch failed the entire route —
## which is how a 0.45 m soldier came back as not fitting anywhere on ground
## the whole force demonstrably walks.
##
## What a wide chassis actually needs to know is the TIGHTEST point, because
## that is the one that stops it. Returns [radius, where].
func _narrowest(world: World3D, path: PackedVector3Array) -> Array:
	var widest := [0.0, 2.4, Vector3.ZERO]
	if path.size() < 2:
		return [0.0, Vector3.ZERO]
	var shape := SphereShape3D.new()
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collide_with_areas = false
	var worst: float = 99.0
	var worst_at := Vector3.ZERO
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var steps: int = maxi(int(a.distance_to(b) / 1.5), 1)
		for s in steps + 1:
			var p: Vector3 = a.lerp(b, float(s) / float(steps))
			var down := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 4.0)
			var ground := world.direct_space_state.intersect_ray(down)
			var base: float = (ground.position as Vector3).y if not ground.is_empty() else p.y
			# Largest of the frame widths that fits here, stepping down.
			var fits: float = 0.0
			for r in [2.1, 1.9, 1.3, 0.45]:
				shape.radius = r
				q.transform = Transform3D(Basis(), Vector3(p.x, base + r + 0.25, p.z))
				if world.direct_space_state.intersect_shape(q, 1).is_empty():
					fits = r
					break
			if fits < worst:
				worst = fits
				worst_at = p
	return [worst, worst_at]
