extends SceneTree

# ─────────────────────────────────────────────
# BLOCK PREFABS — builds every TrenchBroom map in a folder into a prefab scene
# beside it, in the shape FuncGodot gives one in the editor: a FuncGodotMap
# root pointing at the .map, with the built geometry saved under it. Levels
# instance the prefab; a TerrainScatterLayer takes it in its Scenes list.
#
#   godot --headless --path . --script res://tools/block_prefabs.gd -- maps/blocks/props
#   godot --headless --path . --script res://tools/block_prefabs.gd -- maps/blocks/props --force
#
# In the editor it is the same as opening the prefab, selecting its root and
# pressing Build — which is how to refresh one after editing its map. Never
# Build on an instance in a level: that saves a second copy of the geometry
# into the level, beside the prefab's own.
#
# An existing prefab is skipped unless --force, since nodes added to it in the
# editor would be lost. Every texture should already have a material in the
# texture folder; FuncGodot would otherwise invent one and embed it in the
# prefab, and this names each one it had to invent.
#
# Packing a scene outside the editor writes every script property out, even
# the defaults. The FuncGodotMap defaults are taken out again afterwards, so a
# prefab made here reads the same as one the editor saved.
# ─────────────────────────────────────────────

const MapScript := preload("res://addons/func_godot/src/map/func_godot_map.gd")
const SETTINGS := "res://addons/func_godot/func_godot_default_map_settings.tres"
const DEFAULT_LINES := ["global_map_file = \"\"", "print_profiling_data = false", "block_until_complete = false", "set_owner_batch_size = 1000"]


func _initialize() -> void:
	# Built nodes need a tree with a root to go into; wait for it.
	await process_frame
	var dir := ""
	var force := false
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif dir == "":
			dir = a
		else:
			print("ignoring argument '%s'" % a)
	if dir == "":
		print("usage: godot --headless --path . --script res://tools/block_prefabs.gd -- maps/blocks/props [--force]")
		quit(2)
		return
	if not dir.begins_with("res://") and not dir.is_absolute_path():
		dir = "res://" + dir
	if not DirAccess.dir_exists_absolute(dir):
		print("FAIL  no such folder: %s" % dir)
		quit(1)
		return
	var settings: Resource = load(SETTINGS)
	# Built with a copy that never saves materials, so a run of this tool
	# cannot drop new files into the texture folder behind anyone's back.
	var quiet: Resource = settings.duplicate()
	quiet.save_generated_materials = false
	var maps := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.ends_with(".map"))
	maps.sort()
	if maps.is_empty():
		print("FAIL  no .map files in %s" % dir)
		quit(1)
		return
	var made := 0
	var skipped := 0
	for f: String in maps:
		var base := f.get_basename()
		var out := dir.path_join(base + ".tscn")
		if FileAccess.file_exists(out) and not force:
			print("SKIP  %s exists — it may hold editor changes. Pass --force to rebuild it." % out)
			skipped += 1
			continue
		var fgm: Node3D = MapScript.new()
		fgm.name = base.to_pascal_case()
		fgm.local_map_file = dir.path_join(f)
		fgm.map_settings = quiet
		fgm.block_until_complete = true
		root.add_child(fgm)
		fgm.verify_and_build()
		var invented: Array = []
		for mi: MeshInstance3D in fgm.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				if mat == null or mat.resource_path == "":
					invented.append(mi.mesh.surface_get_name(s))
		var shapes := fgm.find_children("*", "CollisionShape3D", true, false).size()
		if shapes == 0:
			print("FAIL  %s built nothing — is it a valid map?" % f)
			root.remove_child(fgm)
			fgm.free()
			continue
		# Saved pointing at the project's own settings, not the quiet copy.
		fgm.map_settings = settings
		fgm.block_until_complete = false
		for c in fgm.find_children("*", "", true, false):
			c.owner = fgm
		var ps := PackedScene.new()
		var err := ps.pack(fgm)
		if err == OK:
			err = ResourceSaver.save(ps, out)
		root.remove_child(fgm)
		fgm.free()
		if err != OK:
			print("FAIL  %s: %s" % [out, error_string(err)])
			continue
		var lines := FileAccess.get_file_as_string(out).split("\n")
		var kept := PackedStringArray()
		for l in lines:
			if not DEFAULT_LINES.has(l):
				kept.append(l)
		var w := FileAccess.open(out, FileAccess.WRITE)
		w.store_string("\n".join(kept))
		w.close()
		made += 1
		print("      %-30s %3d brush(es)%s" % [base + ".tscn", shapes,
				("   WARNING no material for %s — one was made up and embedded" % ", ".join(invented)) if not invented.is_empty() else ""])
	print("BLOCK PREFABS DONE: %d built%s" % [made, (", %d skipped" % skipped) if skipped > 0 else ""])
	quit()
