extends SceneTree

# ─────────────────────────────────────────────
# TERRAIN BAKE — regenerate every GeneratedTerrain in a level from the command
# line, and optionally rebake its navmesh. The same as ticking Generate Terrain
# in the editor; for a recipe edit across many levels, or for an agent that
# cannot open the editor.
#
#   godot --headless --path . --script res://tools/terrain_bake.gd -- res://maps/level.tscn
#   godot --headless --path . --script res://tools/terrain_bake.gd -- res://maps/level.tscn --navmesh
#
# IT NEVER RESAVES THE SCENE. Packing a scene outside the editor writes every
# script property out, `= null` ones included (check.sh rightly calls those
# corruption), and flattens instanced sub-scenes. So this writes only files the
# scene points AT:
#   - each terrain's TerrainData .res (Generate's usual path);
#   - with --navmesh, each NavigationRegion3D's NavigationMesh — but only one
#     saved as its own .res. A navmesh embedded in the .tscn is baked, then
#     reported: bake that one in the editor, or save it to a .res once.
# A brand-new terrain whose scene does not reference its data file yet is
# reported too: open the level in the editor and save it once.
#
# WAITS ONE FRAME FIRST. Inside _initialize() the root viewport is not in the
# tree yet, so a level added there has no global transforms: every stamp and
# path reads as sitting at the origin, and the navmesh bake refuses outright.
# ─────────────────────────────────────────────

const TerrainScript := preload("res://Env/terrain/generated_terrain.gd")


func _initialize() -> void:
	await process_frame
	var scenes: Array[String] = []
	var navmesh := false
	for a in OS.get_cmdline_user_args():
		if a == "--navmesh":
			navmesh = true
		elif a.ends_with(".tscn") or a.ends_with(".scn"):
			scenes.append(a)
		else:
			print("ignoring argument '%s'" % a)
	if scenes.is_empty():
		print("usage: godot --headless --path . --script res://tools/terrain_bake.gd -- res://maps/level.tscn [--navmesh]")
		quit(2)
		return
	var failed := 0
	for path in scenes:
		if not _bake(path, navmesh):
			failed += 1
	print("TERRAIN BAKE %s" % ("DONE" if failed == 0 else "FAILED (%d level(s))" % failed))
	quit(1 if failed > 0 else 0)


func _bake(path: String, navmesh: bool) -> bool:
	var packed: PackedScene = load(path)
	if packed == null:
		print("FAIL  could not load %s" % path)
		return false
	var level := packed.instantiate()
	var terrains := _find_all(level, func(n: Node) -> bool: return n.get_script() == TerrainScript)
	if terrains.is_empty():
		print("FAIL  %s has no GeneratedTerrain in it" % path)
		level.free()
		return false
	# Set before the level enters the tree, so _ready does not generate first.
	for t in terrains:
		t.generate_missing_at_runtime = false
	root.add_child(level)

	var ok := true
	var scene_text := FileAccess.get_file_as_string(path) if path.ends_with(".tscn") else ""
	for t in terrains:
		if not t.generate():
			print("FAIL  %s: %s did not generate (see the warning above)" % [path, t.name])
			ok = false
			continue
		var data_file: String = t.data.resource_path
		print("      %s → %s" % [t.name, data_file])
		if scene_text != "" and not scene_text.contains(data_file):
			print("NOTE  %s does not reference %s yet — open it in the editor and save once, or it will load without this terrain." % [path, data_file])

	if ok and navmesh:
		var regions := _find_all(level, func(n: Node) -> bool: return n is NavigationRegion3D)
		if regions.is_empty():
			print("WARN  %s has no NavigationRegion3D — no navmesh baked" % path)
		for region: NavigationRegion3D in regions:
			var nm := region.navigation_mesh
			if nm == null:
				print("WARN  %s has no NavigationMesh — skipped" % region.name)
				continue
			var t0 := Time.get_ticks_msec()
			region.bake_navigation_mesh(false)
			var polys := nm.get_polygon_count()
			print("      navmesh %s: %d polygons in %.1f s" % [region.name, polys, (Time.get_ticks_msec() - t0) / 1000.0])
			if polys == 0:
				print("FAIL  %s baked EMPTY — is the terrain under the region, and filter_baking_aabb over it?" % region.name)
				ok = false
				continue
			var nm_path := nm.resource_path
			if nm_path == "" or nm_path.contains("::"):
				print("NOTE  %s's NavigationMesh is embedded in the scene, so it can only be saved by the editor. Bake it there, or save it to a .res once." % region.name)
				continue
			var err := ResourceSaver.save(nm, nm_path)
			if err != OK:
				print("FAIL  could not save %s (%s)" % [nm_path, error_string(err)])
				ok = false
			else:
				print("      saved %s" % nm_path)
	_drop(level)
	return ok


func _find_all(node: Node, match_fn: Callable) -> Array:
	var out: Array = []
	if match_fn.call(node):
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_all(child, match_fn))
	return out


func _drop(level: Node) -> void:
	root.remove_child(level)
	level.free()
