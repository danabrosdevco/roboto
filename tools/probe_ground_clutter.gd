extends SceneTree

# ─────────────────────────────────────────────
# PROBE GROUND CLUTTER — things lying on the ground that are solid and should
# not be.
#
#   godot --path . --script res://tools/probe_ground_clutter.gd
#   DIR=maps/blocks/canal  godot ... --script res://tools/probe_ground_clutter.gd
#   LIST=60                               show more rows
#
# WHAT IT LOOKS FOR. A collider whose TOP is below 0.5 m and whose footprint is
# small enough to be clutter rather than a floor. Nothing in this game is cover
# at that height — cover is waist to head — so a solid thing down there is
# either something the squad steps over, or something it snags on, and which of
# the two is not reliably predictable.
#
# WHY IT MATTERS MORE THAN IT LOOKS. Recast erodes the walkable surface by the
# agent radius around every obstacle, and the radius is 0.5 m. So an ankle-high
# stone 0.3 m across does not remove 0.3 m of navmesh, it removes a disc about
# 1.3 m wide. Put a line of them down and the gaps between them fall under
# 2 x radius and bake as nothing at all — the same arithmetic that stops a
# 0.34 m stair tread baking. A hedge with collision does not narrow a route,
# it closes one.
#
# And a thing at 0.45 m is the worst case of all: that is the AI's step-over
# height exactly, so the squad clears it sometimes and not others depending on
# approach angle. A row of park benches is, in the kit's own words, a line of
# maybes.
#
# The fix is always the same: no_collision() before the clutter, so it is drawn
# and not solid. See docs/ASSETS.md section 5.
#
# This probe reports. It does not edit, and it cannot tell you that a given
# piece is WRONG — only that it is solid down there and probably should not be.
# ─────────────────────────────────────────────

## Above this, a thing is cover or architecture and collision is the point.
## Below it, nothing in this game is meant to stop a body.
const LOW := 0.5
## THE BOTTOM OF THE BAND IS THE BAKER'S CLIMB, NOT THE FLOOR.
##
## Recast walks over anything it can climb, so a 0.16 m kerb does not carve the
## navmesh at all — the mesh flows up and over it, and a kerb is solid for good
## reasons. Only an obstacle TALLER than the climb is treated as an obstacle,
## and only then is the walkable surface eroded by the agent radius around it.
##
## That makes the dangerous band narrow and specific: taller than the baker
## will climb (0.25 m) and shorter than the squad's step-over (0.45 m, rounded
## to 0.5 here). In that band the navmesh says "wall" and the AI says "step",
## which is the worst of both and the reason a row of park benches is a line of
## maybes.
##
## This is per level: `agent_max_climb` is 0.25 on georgetown and polaris but
## 0.5 on salient, where the band closes entirely. Override with CLIMB=.
const CLIMB_DEFAULT := 0.25
## Plan area over this is a slab, an apron or a deck — a surface to walk ON,
## which is not what this probe is about.
const SLAB_M2 := 12.0
## Recast erodes by the agent radius on every side. Verified against the
## NavigationMesh in the level scenes, not assumed.
const AGENT_R := 0.5


func _initialize() -> void:
	var dir := OS.get_environment("DIR")
	if dir == "":
		dir = "maps/blocks"
	if not dir.begins_with("res://"):
		dir = "res://" + dir
	var rows := int(OS.get_environment("LIST")) if OS.get_environment("LIST") != "" else 25
	var climb: float = float(OS.get_environment("CLIMB")) if OS.get_environment("CLIMB") != "" else CLIMB_DEFAULT

	var paths: Array = []
	_collect(dir, paths)
	paths.sort()
	if paths.is_empty():
		print("FAIL  no .tscn prefabs under %s — nothing to check" % dir)
		quit(1)
		return

	print("
   GROUND CLUTTER — solid things between %.2f m (the baker climbs it)
   and %.2f m (the squad steps over it), in %s" % [climb, LOW, dir])
	print("   %d prefab(s)\n" % paths.size())

	var hits: Array = []
	var total := 0
	var eroded := 0.0
	for p: String in paths:
		var packed := load(p) as PackedScene
		if packed == null:
			push_warning("probe_ground_clutter: %s did not load — not checked" % p)
			continue
		var inst := packed.instantiate() as Node3D
		if inst == null:
			push_warning("probe_ground_clutter: %s is not a Node3D — not checked" % p)
			continue
		# Measured without putting it in the tree. global_transform needs a node
		# that is inside one, and adding 360 prefabs and waiting a frame for
		# each is 360 frames to learn what the transforms already say.
		var found := _check(inst, climb)
		inst.free()
		if found["n"] > 0:
			hits.append({"name": p.get_file().get_basename(), "n": found["n"],
					"area": found["area"], "top": found["top"]})
			total += found["n"]
			eroded += found["area"]

	if hits.is_empty():
		print("   none — nothing solid is lying on the ground")
		print("\nGROUND CLUTTER DONE")
		quit()
		return

	# By eroded area, not by count: one long kerb costs the navmesh more than
	# six pebbles, and the point of the check is the navmesh.
	hits.sort_custom(func(a, b): return a.area > b.area)
	print("   %-34s %6s %10s %8s" % ["prefab", "solid", "navmesh m2", "tallest"])
	for i in mini(hits.size(), rows):
		var h: Dictionary = hits[i]
		print("   %-34s %6d %10.0f %7.2fm" % [h.name, h.n, h.area, h.top])
	if hits.size() > rows:
		print("   ... and %d more prefab(s) — set LIST= to see them" % (hits.size() - rows))
	print("\n   %d prefab(s), %d solid piece(s) of clutter" % [hits.size(), total])
	print("   about %.0f m2 of navmesh removed by things nothing should be stopped by" % eroded)
	print("   the fix is no_collision() before the clutter — docs/ASSETS.md section 5")
	print("\nGROUND CLUTTER DONE — read the list, do not count it")
	quit()


## Every collider under `n`, measured in the prefab's own space.
func _check(n: Node3D, climb: float) -> Dictionary:
	var count := 0
	var area := 0.0
	var tallest := 0.0
	var boxes: Array = []
	for cs: CollisionShape3D in n.find_children("*", "CollisionShape3D", true, false):
		if cs.shape == null:
			continue
		var dbg := cs.shape.get_debug_mesh()
		if dbg == null:
			continue
		boxes.append(_to_root(cs, n) * dbg.get_aabb())
	for box: AABB in boxes:
		var top := box.position.y + box.size.y
		if top <= climb or top >= LOW:
			continue
		var plan := box.size.x * box.size.z
		if plan > SLAB_M2:
			continue
		# NOT THE BOTTOM COURSE OF SOMETHING TALL. A wall or a sandbag revetment
		# built as a stack of boxes has a short brush at the bottom, and that
		# brush is correctly solid — the thing it belongs to is waist high or
		# more. Without this the probe called 38 pieces of one trench revetment
		# clutter. Only flag a low collider with nothing standing over it.
		if _covered(box, boxes):
			continue
		count += 1
		# What Recast actually loses: the footprint grown by the agent radius
		# on every side.
		area += (box.size.x + AGENT_R * 2.0) * (box.size.z + AGENT_R * 2.0)
		tallest = maxf(tallest, top)
	return {"n": count, "area": area, "top": tallest}


## True if something tall stands over this box's footprint — then the box is
## the foot of that thing, not something lying on the ground beside it.
func _covered(box: AABB, boxes: Array) -> bool:
	for other: AABB in boxes:
		if other.position.y + other.size.y < LOW:
			continue
		# Plan overlap only: it is above this box, not merely near it.
		if other.position.x > box.position.x + box.size.x or box.position.x > other.position.x + other.size.x:
			continue
		if other.position.z > box.position.z + box.size.z or box.position.z > other.position.z + other.size.z:
			continue
		return true
	return false


## The transform of `node` in `root`'s space, accumulated by walking up. The
## tree-based global_transform is not available on a prefab that was never
## added to the tree, and this says the same thing.
func _to_root(node: Node3D, root: Node3D) -> Transform3D:
	var x := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != root:
		if at is Node3D:
			x = (at as Node3D).transform * x
		at = at.get_parent()
	return x


func _collect(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		push_warning("probe_ground_clutter: cannot open %s — skipped" % dir)
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			if not f.begins_with("."):
				_collect(dir.path_join(f), out)
		elif f.ends_with(".tscn"):
			out.append(dir.path_join(f))
		f = d.get_next()
	d.list_dir_end()
