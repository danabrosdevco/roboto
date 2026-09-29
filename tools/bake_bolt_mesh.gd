extends SceneTree

# ─────────────────────────────────────────────
# BAKE THE FOUNDRY RIFLE'S BARE MESH — SniperRifle_6 with its telescope cut off.
#
# WHY THIS EXISTS. The pack guns are ONE MeshInstance3D with five named
# surfaces, so the scope is not a node that can be hidden and not a surface that
# can be dropped: its triangles are mixed into Black (the tube), DarkMetal (the
# rings) and Glass (the lenses). The only way to take it off is to rebuild the
# mesh without the triangles that sit inside its envelope.
#
# WHERE THE CUT IS. Measured, not guessed. In the receiver region there is a
# clean empty band at y 0.1-0.2, the barrel occupies y 0.15-0.35, and every
# vertex of Glass is above y 0.42. So y > CUT_Y removes the whole telescope and
# nothing else, and the low scope-mount bases at y 0.3 are deliberately KEPT —
# with the tube gone they read as the rail the iron sights bolt to.
#
# Re-run if the base model is ever swapped:
#   godot --headless --audio-driver Dummy --path . --script res://tools/bake_bolt_mesh.gd
# ─────────────────────────────────────────────

const SOURCE := "res://3d_assets/gun_pack/Blends/SniperRifle_6.blend"
const OUT := "res://Character/weapon/models/bolt_rifle_base.res"
## Everything above this, forward of the butt and behind the muzzle, is scope.
const CUT_Y := 0.38
const CUT_X_MIN := -0.60
const CUT_X_MAX := 2.60


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var body: Node = (load(SOURCE) as PackedScene).instantiate()
	var src: ArrayMesh = null
	for mi in _meshes(body):
		if mi.mesh is ArrayMesh:
			src = mi.mesh as ArrayMesh
			break
	if src == null:
		printerr("bake_bolt_mesh: no ArrayMesh in %s" % SOURCE)
		quit(1)
		return

	var out := ArrayMesh.new()
	var dropped := 0
	var kept := 0
	for s in src.get_surface_count():
		var mat: Material = src.surface_get_material(s)
		var arrays: Array = src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		# Flattened to triangle soup: the filter works per triangle, and
		# re-indexing a partially removed surface is not worth the bookkeeping
		# on a model this size.
		if idx.is_empty():
			idx = PackedInt32Array()
			for i in verts.size():
				idx.append(i)

		var nv := PackedVector3Array()
		var nn := PackedVector3Array()
		var nu := PackedVector2Array()
		var tri := idx.size() / 3
		for t in tri:
			var a: int = idx[t * 3]
			var b: int = idx[t * 3 + 1]
			var c: int = idx[t * 3 + 2]
			var centre: Vector3 = (verts[a] + verts[b] + verts[c]) / 3.0
			if _is_scope(centre):
				dropped += 1
				continue
			kept += 1
			for v in [a, b, c]:
				nv.append(verts[v])
				if v < norms.size():
					nn.append(norms[v])
				if v < uvs.size():
					nu.append(uvs[v])
		if nv.is_empty():
			print("  surface %d (%s) removed entirely" % [s, mat.resource_name if mat else "?"])
			continue
		var out_arrays: Array = []
		out_arrays.resize(Mesh.ARRAY_MAX)
		out_arrays[Mesh.ARRAY_VERTEX] = nv
		if nn.size() == nv.size():
			out_arrays[Mesh.ARRAY_NORMAL] = nn
		if nu.size() == nv.size():
			out_arrays[Mesh.ARRAY_TEX_UV] = nu
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
		out.surface_set_material(out.get_surface_count() - 1, mat)
		out.surface_set_name(out.get_surface_count() - 1,
			mat.resource_name if mat != null and mat.resource_name != "" else "surface%d" % s)
		print("  surface %d (%s): %d verts" % [s, mat.resource_name if mat else "?", nv.size()])

	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var err := ResourceSaver.save(out, OUT)
	print("bake_bolt_mesh: %d triangles kept, %d cut away -> %s (%s)" % [
		kept, dropped, OUT, "ok" if err == OK else "ERROR %d" % err])
	body.free()
	quit(0 if err == OK else 1)


func _is_scope(p: Vector3) -> bool:
	return p.y > CUT_Y and p.x > CUT_X_MIN and p.x < CUT_X_MAX


func _meshes(node: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_meshes(c, out)
	return out
