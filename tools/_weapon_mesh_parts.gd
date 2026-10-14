extends SceneTree

# ─────────────────────────────────────────────
# WHAT CAN ACTUALLY BE ANIMATED ON A WEAPON.
#
# A reload only reads if something on the gun moves, and whether anything CAN is
# a property of the model rather than of the animation. Hand-built models
# (bolt_rifle_model.tscn, squad_automatic_model.tscn) name their parts as nodes
# and every one of them can be posed. An imported .blend is usually one
# MeshInstance3D, and then the only question left is whether its surfaces split
# by PART or by MATERIAL — the first can be pulled out into a node of its own,
# the second cannot, because every surface spans the whole weapon.
#
# The Ancient Rifle is the second kind: three surfaces called Main, MainDark and
# MainLight, each covering the length of the gun. That is why it has no magazine
# to drop.
#
#   godot --headless --path . --script res://tools/_weapon_mesh_parts.gd -- <weapon.tscn>
# ─────────────────────────────────────────────

func _init() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://Character/weapon/m4_hud_weapon.tscn"
	if not ResourceLoader.exists(path):
		printerr("no such weapon scene: %s" % path)
		quit(1)
		return
	var gun = load(path).instantiate()
	root.add_child(gun)
	await process_frame
	print("%s" % path.get_file())
	var posable := 0
	for n in _nodes(gun):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			_report(n as MeshInstance3D)
		elif n is Node3D and n.get_child_count() > 0:
			posable += 1
	print("  %d Node3D group(s) that could be posed as assemblies" % posable)
	quit(0)


func _report(m: MeshInstance3D) -> void:
	print("  %s: %d surface(s)" % [m.name, m.mesh.get_surface_count()])
	for i in m.mesh.get_surface_count():
		var arrays: Array = m.mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var box := AABB(verts[0], Vector3.ZERO)
		for v in verts:
			box = box.expand(v)
		var mat := m.mesh.surface_get_material(i)
		var name := str(mat.resource_name) if mat != null and mat.resource_name != "" else "unnamed"
		# A surface whose bounds cover most of the mesh is a MATERIAL, not a part.
		var whole: float = box.size.x / maxf(m.mesh.get_aabb().size.x, 0.001)
		print("    surface %d  %5d verts  %-12s spans %.0f%% of the length  %s" % [
			i, verts.size(), name, whole * 100.0,
			"— a material, not a part" if whole > 0.5 else "— could be split out"])


func _nodes(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_nodes(c))
	return out
