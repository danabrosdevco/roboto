extends SceneTree

# ─────────────────────────────────────────────
# COLLAPSE A TRENCHBROOM BLOCK'S PER-BRUSH COLLISION INTO ONE SHAPE.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/collapse_block_collision.gd -- [--write] [path or dir]
#
# Dry run by default: it reports what it WOULD save and writes nothing.
#
# ── THE PROBLEM, MEASURED ────────────────────
# FuncGodot builds one ConvexPolygonShape3D per BRUSH for any entity whose FGD
# class is CONVEX, and `worldspawn` is CONVEX. 400 of the project's 423 .map
# files put their bulk geometry in worldspawn, so a block authored from 66
# brushes ships 66 collision shapes — and then a level instances it 456 times.
#
# Salient: 45,881 CollisionShape3D nodes, 30,096 of them from one block.
# Every one sits in the physics broadphase for the life of the level, and
# every ground snap, near-miss suppression query and melee sweep pays for the
# size of that broadphase.
#
# ── WHAT THIS DOES ───────────────────────────
# Replaces the per-brush convex shapes under a StaticBody3D with a single
# ConcavePolygonShape3D built from the body's own mesh — which is exactly what
# FuncGodot would have produced had the class been CONCAVE, as func_detail
# already is. The visual is untouched.
#
# ── WHY A BACKFILL AND NOT JUST THE FGD ──────
# Changing worldspawn to CONCAVE in the FGD fixes every FUTURE import and
# nothing that already exists, because the committed .tscn blocks are the
# artefact levels instance — they are not rebuilt unless someone re-imports
# the .map. This fixes what is on disk today. Do both: the FGD so new blocks
# are born cheap, this so the existing 423 are not left behind.
#
# ── WHAT IT WILL NOT DO ──────────────────────
# A trimesh is STATIC-ONLY collision. If a block is ever used on a moving
# body this is the wrong shape for it, so anything whose StaticBody3D is not
# a direct child of the block root is left alone and reported.
# ─────────────────────────────────────────────

var _write: bool = false
var _total_before: int = 0
var _total_after: int = 0
var _changed: int = 0
var _skipped: Array[String] = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var target := "res://maps/blocks"
	for a in args:
		if a == "--write":
			_write = true
		elif a.strip_edges() != "":
			target = a

	var files: Array[String] = []
	if target.ends_with(".tscn"):
		files.append(target)
	else:
		_gather(target, files)
	files.sort()

	print("── %s %d block(s) under %s ──" % ["REWRITING" if _write else "DRY RUN on", files.size(), target])
	for f in files:
		_do(f)

	print("")
	print("  collision shapes: %d -> %d   (%d block(s) changed, %.0f%% saved)" % [
		_total_before, _total_after, _changed,
		0.0 if _total_before == 0 else float(_total_before - _total_after) / float(_total_before) * 100.0])
	if not _skipped.is_empty():
		print("  left alone (%d):" % _skipped.size())
		for s in _skipped:
			print("     %s" % s)
	if not _write:
		print("")
		print("  nothing written. Re-run with --write to apply.")
	quit(0)


func _gather(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for sub in d.get_directories():
		_gather(dir_path.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".tscn"):
			out.append(dir_path.path_join(f))


func _do(path: String) -> void:
	var packed: PackedScene = load(path)
	if packed == null:
		return
	var root_node: Node = packed.instantiate()
	var before := 0
	var after := 0
	var touched := false

	for body in _static_bodies(root_node):
		var shapes: Array = []
		var mesh_node: MeshInstance3D = null
		for c in body.get_children():
			if c is CollisionShape3D:
				shapes.append(c)
			elif c is MeshInstance3D and mesh_node == null:
				mesh_node = c
		before += shapes.size()
		# One shape already, or none: nothing to collapse.
		if shapes.size() <= 1:
			after += shapes.size()
			continue
		if mesh_node == null or mesh_node.mesh == null:
			_skipped.append("%s/%s — shapes but no mesh to build a trimesh from" % [path.get_file(), body.name])
			after += shapes.size()
			continue
		var tri: ConcavePolygonShape3D = mesh_node.mesh.create_trimesh_shape()
		if tri == null or tri.get_faces().is_empty():
			_skipped.append("%s/%s — trimesh came back empty" % [path.get_file(), body.name])
			after += shapes.size()
			continue
		for s in shapes:
			body.remove_child(s)
			s.queue_free()
		var merged := CollisionShape3D.new()
		merged.name = "collision_merged"
		merged.shape = tri
		body.add_child(merged)
		merged.owner = root_node
		after += 1
		touched = true

	_total_before += before
	_total_after += after
	if before != after:
		_changed += 1
		print("  %-54s %5d -> %d" % [path.get_file(), before, after])

	if touched and _write:
		var out := PackedScene.new()
		if out.pack(root_node) == OK:
			var err := ResourceSaver.save(out, path)
			if err != OK:
				printerr("  could not write %s (%s)" % [path, error_string(err)])
	root_node.free()


func _static_bodies(n: Node) -> Array:
	var out: Array = []
	if n is StaticBody3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_static_bodies(c))
	return out
