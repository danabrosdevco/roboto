extends RefCounted

# ─────────────────────────────────────────────
# CSG IS AN AUTHORING TOOL. IT WAS BUILDING EVERY ROBOT AT RUNTIME.
#
# A CSGShape3D rebuilds its geometry the first time it enters the tree. Every AI
# scene in the game ships with them — the soldier has 2, the walker 8, the
# watcher 9, the rover 10 — so every robot paid for a boolean mesh build on the
# frame it appeared.
#
# Measured on Three Rivers, a reserve wave of 40 soldiers:
#
#   standing them up (instantiate + add_child + register + order)      8.6 ms
#   the frame they first run _physics_process                        335.8 ms
#   ...the same frame with the two CSGMesh3D nodes removed             9.9 ms
#
# 97% of the spike, and none of it AI: it was identical with the move order
# removed, unregistered from the AIManager, and distance-culled. Just entering
# the tree. It is also linear — 4 robots cost 37.9 ms — so a reserve squad of
# rovers at 10 CSG nodes each is far worse than the soldiers that were measured.
#
# So: build each scene's CSG ONCE at startup, keep the resulting mesh, and give
# every robot after that a MeshInstance3D that shares it. The baked mesh is the
# CSG's own output — get_meshes() — not a re-authoring of it, and the test
# asserts the swapped body occupies the same space as the CSG did.
#
# WHY THE SWAP HAPPENS IN _enter_tree AND NOT LATER. The rebuild is scheduled
# when the CSG node enters the tree. _enter_tree runs top-down, so the body's
# fires before its children are in, and a CSG removed there never builds at all.
# Waiting until _ready would be too late — the cost is already committed.
#
# WHY THE REFERENCES HAVE TO BE REPOINTED. `visible_pieces` on the body and
# `pieces` on FactionLivery are exported as node_paths, which Godot resolves to
# LIVE NODE OBJECTS when the scene is instantiated — not to paths it would look
# up later. Swapping a node out without fixing those arrays leaves them holding
# a freed CSGMesh3D, and the first thing to touch one takes the game with it.
# ─────────────────────────────────────────────

const AI_DIR := "res://Character/characters/ai"

## scene path -> Array of { name, transform, mesh, material, visible, cast_shadow, layers }
static var _cache: Dictionary = {}
static var _warmed: bool = false

## Counters, for the test and for anyone reading a profile.
##
## arrays_skipped is the one that matters: it counts script arrays that CANNOT
## hold a node and were therefore not asked whether they contain one. Asking is
## not free — it is an engine error per array, and it crashed the game on load.
## A test can see this number; it cannot see the error.
static var arrays_skipped: int = 0
static var arrays_scanned: int = 0
static var baked_scenes: int = 0
static var baked_nodes: int = 0
static var swapped_bodies: int = 0


## True once warm() has run. Nothing fails without it — apply() simply leaves the
## CSG alone — so an unwarmed game is slow, not broken.
static func is_warm() -> bool:
	return _warmed


## Build every AI scene's CSG once and keep the meshes.
##
## A coroutine: the geometry is not available until the frame after the node
## enters the tree, so this adds every probe, waits ONE frame, and harvests them
## all together. `host` is anything already in the tree.
static func warm(host: Node) -> void:
	if _warmed:
		return
	_warmed = true
	if host == null or not host.is_inside_tree():
		push_warning("CsgBake.warm() needs a node that is in the tree; robots will build their CSG one at a time instead, which costs about 8.6 ms each.")
		return

	var paths := _scene_paths()
	var probes: Array = []
	var holder := Node3D.new()
	holder.name = "CsgBakeProbes"
	# Far enough under the map that a probe cannot be seen or collided with for
	# the single frame it exists.
	holder.position = Vector3(0.0, -10000.0, 0.0)
	host.add_child(holder)

	for p in paths:
		var packed := load(p) as PackedScene
		if packed == null:
			continue
		var inst := packed.instantiate()
		if inst is Node3D:
			# Nothing should think, shoot or fall during its one frame alive.
			(inst as Node3D).process_mode = Node.PROCESS_MODE_DISABLED
			holder.add_child(inst)
			probes.append({"path": p, "node": inst})
		else:
			inst.free()

	await host.get_tree().process_frame

	for probe in probes:
		var records := _harvest(probe["node"])
		if not records.is_empty():
			_cache[probe["path"]] = records
			baked_scenes += 1
			baked_nodes += records.size()
		(probe["node"] as Node).free()
	holder.free()


## Replace `body`'s CSG children with the baked meshes. Safe to call on anything:
## a scene with no CSG, or one that was never baked, is left exactly as it was.
##
## Call this from _enter_tree. See the note above for why nowhere else will do.
static func apply(body: Node) -> int:
	if body == null:
		return 0
	var records: Array = _cache.get(body.scene_file_path, [])
	if records.is_empty():
		return 0
	var done := 0
	## old CSG node -> the MeshInstance3D that replaced it.
	var swaps: Dictionary = {}
	for rec in records:
		# By PATH, not name: the rover and the walker hang their CSG off a rig
		# node rather than the body, and looking only at direct children found
		# 11 of the 16 scenes and 26 of the 62 shapes.
		var old := body.get_node_or_null(NodePath(rec["path"]))
		if old == null or not (old is CSGShape3D):
			continue   # the scene changed under the cache; leave it building its own
		var parent := (old as Node).get_parent()
		if parent == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = rec["mesh"]
		mi.transform = rec["transform"]
		mi.visible = rec["visible"]
		mi.cast_shadow = rec["cast_shadow"]
		mi.layers = rec["layers"]
		if rec["material"] != null:
			mi.material_override = rec["material"]
		var index := (old as Node).get_index()
		parent.remove_child(old)
		mi.name = rec["name"]           # named AFTER the old one is out, or Godot renames it
		parent.add_child(mi)
		parent.move_child(mi, index)
		swaps[old] = mi
		done += 1

	if not swaps.is_empty():
		# ONE pass for all of them. Repointing per shape walked the whole body
		# once per CSG node — nine times over for a watcher — and the walk reads
		# every script variable of every node on it.
		_repoint(body, swaps)
	# free, NOT queue_free, and only once the repointing has finished reading
	# them. make() runs this on a DETACHED node, so there is no tree notification
	# to be inside and immediate disposal is safe.
	#
	# It also has to be immediate. queue_free pushes the destruction of every
	# swapped-out CSG node onto the NEXT frame — which for a 40-robot wave is
	# eighty of them landing on the frame the wave appears, and measured 984 ms
	# against 354 for not baking at all. The optimisation was paying for itself
	# three times over in teardown.
	for old in swaps:
		(old as Node).free()
	if done > 0:
		swapped_bodies += 1
	return done


# ─────────────────────────────────────────────
# INTERNALS
# ─────────────────────────────────────────────

## Every AI scene that actually has CSG in it. Read from the directory rather
## than listed, so a new chassis is baked without anyone remembering to add it.
static func _scene_paths() -> Array:
	var out: Array = []
	var dir := DirAccess.open(AI_DIR)
	if dir == null:
		push_warning("CsgBake: cannot read %s, so nothing can be baked." % AI_DIR)
		return out
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			out.append("%s/%s" % [AI_DIR, f])
	out.sort()
	return out


## The baked record for every CSG shape anywhere under `inst`, taken from the
## CSG's own output.
##
## THE WHOLE SUBTREE, not just direct children: the rover and the walker carry
## theirs on a rig node, and looking only one level down found 11 of the 16
## scenes and 26 of the 62 shapes — which is to say it missed the two chassis
## with the most CSG on them, the ones the spike is worst for.
##
## A CSG shape nested inside ANOTHER CSG shape is skipped: it is an operand of
## the boolean above it, not geometry of its own, and the parent's baked mesh
## already contains its contribution.
static func _harvest(inst: Node) -> Array:
	var out: Array = []
	var stack: Array = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n == inst or not (n is CSGShape3D):
			continue
		if n.get_parent() is CSGShape3D:
			continue
		var csg := n as CSGShape3D
		var got: Array = csg.get_meshes()
		if got.size() < 2 or got[1] == null:
			# Not fatal — this one keeps building itself — but it is the whole
			# point of the exercise, so it has to be visible.
			push_warning("CsgBake: %s in %s produced no mesh, so it will go on rebuilding at runtime." % [
				csg.name, inst.scene_file_path])
			continue
		var owned := _copy(got[1] as Mesh)
		if owned == null:
			push_warning("CsgBake: %s in %s has no surfaces to copy." % [csg.name, inst.scene_file_path])
			continue
		out.append({
			"path": String(inst.get_path_to(csg)),
			# THE CSG'S OWN BOUNDS, measured here while the real thing still exists.
			# A test can then check the swap occupies the same space without having
			# to stand up a second, unbaked copy of every chassis to compare against
			# — which is the only place a CSG shape is still built at runtime.
			"aabb": csg.get_aabb(),
			"name": String(csg.name),
			"transform": csg.transform,
			"mesh": owned,
			"material": csg.material_override,
			"visible": csg.visible,
			"cast_shadow": csg.cast_shadow,
			"layers": csg.layers,
		})
	return out


## Point anything that held a swapped-out node at its replacement instead.
##
## `visible_pieces` on the body and `pieces` on FactionLivery are exported as
## node_paths, which Godot resolves to LIVE NODE OBJECTS when the scene is
## instantiated — not to paths it looks up later. Leave them and they hold a
## freed CSGMesh3D, and the first thing to touch one takes the game with it.
##
## Only SCRIPT variables are examined: that is where those two live, and reading
## every built-in property of every node would be both slower and a good way to
## trip over a getter with opinions.
static func _repoint(root: Node, swaps: Dictionary) -> void:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.get_script() == null:
			continue
		for p in n.get_property_list():
			if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			var t := int(p["type"])
			if t != TYPE_OBJECT and t != TYPE_ARRAY:
				continue
			var v = n.get(p["name"])
			# TYPE FIRST. `v == old` with an Array on the left is not false in
			# GDScript, it is an error.
			if v is Array:
				_repoint_array(n, String(p["name"]), v as Array, swaps)
			elif v is Object and swaps.has(v):
				n.set(p["name"], swaps[v])


## A TYPED ARRAY DOES NOT POLITELY DECLINE.
##
## Array.find() validates what it is handed against the array's element type, and
## on a mismatch it ERRORS rather than returning -1:
##
##   "Attempted to find a variable of type 'Object' into a TypedArray of type 'int'"
##   "...a 'CSGMesh3D' into a TypedArray, which does not inherit from 'AudioStream'"
##
## Every robot carries script arrays of ints, of AudioStreams, of Scripts. Asking
## each of them whether it contains a CSG node printed one error per array per
## node per swapped shape — thousands of lines on load, and it took the game down
## with it. So ask what the array can hold FIRST, and then walk it by hand.
static func _repoint_array(owner: Node, prop: String, arr: Array, swaps: Dictionary) -> void:
	if arr.is_empty():
		return
	var builtin := arr.get_typed_builtin()
	if builtin != TYPE_NIL:
		if builtin != TYPE_OBJECT:
			arrays_skipped += 1
			return          # Array[int], Array[String] — cannot hold a node at all
		if arr.get_typed_script() != null:
			arrays_skipped += 1
			return          # wants a specific script; a bare MeshInstance3D is not it
		var want := String(arr.get_typed_class_name())
		if want != "" and not ClassDB.is_parent_class("MeshInstance3D", want):
			arrays_skipped += 1
			return          # Array[AudioStream], Array[Interactible], ...
	arrays_scanned += 1
	var changed := false
	for i in arr.size():
		if arr[i] != null and swaps.has(arr[i]):
			changed = true
			break
	if not changed:
		return
	var copy: Array = arr.duplicate()
	for i in copy.size():
		if copy[i] != null and swaps.has(copy[i]):
			copy[i] = swaps[copy[i]]
	owner.set(prop, copy)


## Drop the cache. For tests and tools that tear the world down and want the
## baked meshes released before the renderer goes with them; nothing in the game
## calls this, because the cache is meant to last the run.
static func clear() -> void:
	_cache.clear()
	_warmed = false
	arrays_skipped = 0
	arrays_scanned = 0
	baked_scenes = 0
	baked_nodes = 0
	swapped_bodies = 0


## An independent copy of `src`, surface by surface.
##
## WHY NOT JUST KEEP WHAT get_meshes() RETURNED. That mesh belongs to the CSG
## NODE — its RID is created and destroyed with the shape. Caching it and then
## freeing the probe leaves every record holding a mesh whose RID is already
## gone, which the renderer reports as "Parameter m is null" and which would have
## put a MeshInstance3D with nothing in it on every robot in the game. Headless,
## that reads as a crash on teardown; on screen it would read as invisible
## robots, and nothing in a parse check would have caught either.
##
## Copying the surface arrays builds a mesh this cache owns outright.
static func _copy(src: Mesh) -> ArrayMesh:
	if src == null or src.get_surface_count() == 0:
		return null
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(s))
	return out if out.get_surface_count() > 0 else null


## Instantiate `scene` with its CSG already replaced. USE THIS TO BUILD ROBOTS.
##
## WHY A FACTORY RATHER THAN A HOOK INSIDE THE BODY. The swap has to happen
## before the node is in the tree, and the two hooks that are early enough are
## both wrong: _enter_tree is a tree notification, and removing a child from
## inside one segfaults the engine on teardown — disabling exactly that line took
## test_give_way from exit 139 back to exit 0 — while _ready runs after
## initialize() has already read the body's children and measured them.
##
## Out here the node is detached and nothing has looked at it yet, which is the
## only moment where restructuring it is free of consequences.
static func make(scene: PackedScene) -> Node:
	if scene == null:
		return null
	var inst := scene.instantiate()
	apply(inst)
	return inst
