extends SceneTree

# ─────────────────────────────────────────────
# COVER — rebuild a level's baked CoverPoints and write them back into the
# scene text, which is the editor's "tick Generate, save the scene" without the
# editor.
#
#   godot --path . --script res://tools/probe_cover_mutaha.gd
#   LEVEL=res://maps/x.tscn godot --path . --script res://tools/probe_cover_mutaha.gd
#
# NOT headless: the spawner raycasts against real collision.
#
# WHY IT HAS TO BE REDONE. The points are baked children, found by walking the
# navmesh edges and casting at the geometry either side. Move the geometry and
# every one of them is a lie: points inside a building that was not there
# before, and none at all in a district that was. Mutaha's WIP copy grew a
# quarter, six estate blocks and a relaid island since its 2606 were baked.
#
# It rewrites ONLY the CoverPointSpawner's children — everything from the
# spawner's own node line down to the next node that is not one of its
# CoverPoints. The navmesh sub-resource, the objectives and the dressing are
# left exactly as they are.
# ─────────────────────────────────────────────

var level_path := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "res://maps/mutaha_wip_level.tscn"


func _initialize() -> void:
	await process_frame
	var packed := ResourceLoader.load(level_path, "PackedScene",
			ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if packed == null:
		print("FAIL  could not load %s" % level_path)
		quit(1)
		return
	var level: Node3D = packed.instantiate()
	root.add_child(level)
	for _i in 40:
		await physics_frame
	var spawner: Node3D = level.get_node_or_null("CoverPointSpawner")
	if spawner == null:
		print("FAIL  %s has no CoverPointSpawner" % level_path.get_file())
		quit(1)
		return
	var was := spawner.get_child_count()
	# CALL THE METHODS, NOT THE EXPORTED BUTTONS. Both setters are guarded by
	# Engine.is_editor_hint(), so outside the editor ticking them does nothing
	# at all — the first run of this reported "3241, was 3241" and had only
	# re-serialised the points it started with.
	spawner.call("_clear")
	for _i in 4:
		await physics_frame
	spawner.call("_generate")
	for _i in 20:
		await physics_frame
	var kids := spawner.get_children()
	print("   %s: %d cover point(s), was %d" % [level_path.get_file(), kids.size(), was])
	if kids.size() < 200:
		print("FAIL  that is too few to believe — is this running with a display?")
		quit(1)
		return

	# The script id the existing CoverPoints use, so the rewrite matches.
	var text := FileAccess.get_file_as_string(level_path)
	var script_id := ""
	for line in text.split("\n"):
		if line.begins_with("[ext_resource") and line.contains("cover_point.gd"):
			var at := line.find("id=\"")
			script_id = line.substr(at + 4, line.find("\"", at + 4) - at - 4)
	if script_id == "":
		print("FAIL  the scene has no cover_point.gd ext_resource to point the new nodes at")
		quit(1)
		return

	var out: PackedStringArray = []
	var i := 0
	for c in kids:
		var node := c as Node3D
		if node == null:
			continue
		var p := node.position
		var dir: Vector3 = node.get("cover_direction")
		var crouch: bool = bool(node.get("is_crouch_cover"))
		out.append("")
		out.append("[node name=\"CoverPoint_%d\" type=\"Node3D\" parent=\"CoverPointSpawner\"]" % i)
		out.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)" % [
				_num(p.x), _num(p.y), _num(p.z)])
		out.append("script = ExtResource(\"%s\")" % script_id)
		out.append("cover_direction = Vector3(%s, %s, %s)" % [_num(dir.x), _num(dir.y), _num(dir.z)])
		if crouch:
			out.append("is_crouch_cover = true")
		out.append("metadata/cover_direction = Vector3(%s, %s, %s)" % [_num(dir.x), _num(dir.y), _num(dir.z)])
		if crouch:
			out.append("metadata/is_crouch_cover = true")
		i += 1

	# Splice: keep everything up to the spawner's last property, drop its old
	# children, put the new ones in, keep whatever followed them.
	var lines := text.split("\n")
	var start := -1
	var finish := -1
	for k in lines.size():
		var line: String = lines[k]
		if line.begins_with("[node ") and line.contains("name=\"CoverPoint_") \
				and line.contains("parent=\"CoverPointSpawner\""):
			if start < 0:
				start = k
			finish = k
		elif start >= 0 and line.begins_with("[") and not line.begins_with("[\""):
			break
	if start < 0:
		print("FAIL  found no CoverPoint_ nodes to replace")
		quit(1)
		return
	# Walk on to the end of the last one's properties.
	var end := finish + 1
	while end < lines.size() and not lines[end].begins_with("["):
		end += 1
	var head: PackedStringArray = []
	for k in range(0, start - 1 if start > 0 and lines[start - 1] == "" else start):
		head.append(lines[k])
	var tail: PackedStringArray = []
	for k in range(end, lines.size()):
		tail.append(lines[k])
	var f := FileAccess.open(level_path, FileAccess.WRITE)
	if f == null:
		print("FAIL  could not write %s" % level_path)
		quit(1)
		return
	f.store_string("\n".join(head) + "\n" + "\n".join(out) + "\n\n" + "\n".join(tail))
	f.close()
	print("   wrote %d cover point(s) back into %s" % [i, level_path.get_file()])
	quit()


## Godot's own float formatting, so the file reads the way the editor writes it.
func _num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return String.num(v, 6).rstrip("0").rstrip(".")
