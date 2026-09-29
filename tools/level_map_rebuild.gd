extends SceneTree

# ─────────────────────────────────────────────
# LEVEL MAP REBUILD — rebuilds the FuncGodotMap inside a level scene from its
# .map file, and leaves everything else in the scene alone.
#
#   LEVEL=res://maps/proving_level.tscn godot --headless --path . \
#       --script res://tools/level_map_rebuild.gd
#
# In the editor this is opening the level, selecting the FuncGodotMap node and
# pressing Build. A level scene holds the BUILT geometry — one mesh per entity
# and one CollisionShape3D per brush, all saved into the .tscn — so editing the
# .map changes nothing in the game until somebody rebuilds it. That is the step
# that gets forgotten, and a map fixed on disk that nobody can see in game is
# worse than one left alone, because it reads as done.
#
# WHAT IT WILL NOT TOUCH. Objectives, spawns, patrol points, lights, the world
# environment, the navigation mesh: only the FuncGodotMap node's own children
# are replaced. The map node is lifted OUT of the level to be built, so the
# level's scripts never enter the tree and never run — a level _ready() outside
# a game is a spray of errors at best.
#
# THE NAVMESH GOES STALE. Brush geometry is what the navmesh is baked from, so
# anything that moves a walkable surface needs a re-bake afterwards, and this
# tool says so rather than pretending the job is finished.
# ─────────────────────────────────────────────

const MapScript := preload("res://addons/func_godot/src/map/func_godot_map.gd")


func _initialize() -> void:
	# Built nodes need a tree with a root to go into; wait for it.
	await process_frame
	var path := OS.get_environment("LEVEL")
	if path == "":
		print("usage: LEVEL=res://maps/<name>_level.tscn")
		quit(2)
		return
	if not path.begins_with("res://") and not path.is_absolute_path():
		path = "res://" + path
	var packed := load(path) as PackedScene
	if packed == null:
		print("FAIL  %s will not load" % path)
		quit(1)
		return
	# MAIN edit state, not the default: it is the one that gives every node an
	# owner, and a node with no owner is a node that does not get packed back.
	var level := packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	var maps := level.find_children("*", "Node3D", true, false).filter(
			func(n: Node) -> bool: return n.get_script() == MapScript)
	if maps.size() != 1:
		print("FAIL  %s has %d FuncGodotMap node(s); expected exactly one" % [path, maps.size()])
		quit(1)
		return
	var fgm: Node3D = maps[0]
	var holder: Node = fgm.get_parent()
	var at := fgm.get_index()
	var was: int = fgm.find_children("*", "CollisionShape3D", true, false).size()
	var file: String = fgm.local_map_file
	if file == "" or not FileAccess.file_exists(file):
		print("FAIL  %s points at '%s', which is not there" % [fgm.name, file])
		quit(1)
		return

	# Out of the level, built on its own, and back in at the same index. The
	# level is never added to the tree, so nothing in it runs.
	for c in fgm.get_children():
		fgm.remove_child(c)
		c.queue_free()
	holder.remove_child(fgm)
	root.add_child(fgm)
	fgm.block_until_complete = true
	fgm.verify_and_build()
	var shapes: int = fgm.find_children("*", "CollisionShape3D", true, false).size()
	var meshes := 0
	for mi: MeshInstance3D in fgm.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null:
			meshes += 1
	if shapes == 0 and meshes == 0:
		print("FAIL  %s built nothing from %s — nothing written" % [fgm.name, file])
		quit(1)
		return
	fgm.block_until_complete = false
	root.remove_child(fgm)
	holder.add_child(fgm)
	holder.move_child(fgm, at)
	fgm.owner = level
	for c in fgm.find_children("*", "", true, false):
		c.owner = level

	# THE SCENE'S uid HAS TO BE PUT BACK BY HAND. pack() makes a new resource
	# with no identity, so saving it over the level writes a header without a
	# uid line, and every uid:// reference to the level dies quietly — three
	# missions point at this one. Nothing warns; they just stop resolving.
	var uid := ResourceLoader.get_resource_uid(path)
	var out := PackedScene.new()
	var err := out.pack(level)
	if err == OK:
		err = ResourceSaver.save(out, path)
	if err != OK:
		print("FAIL  %s: %s" % [path, error_string(err)])
		quit(1)
		return
	var text := _strip_defaults(FileAccess.get_file_as_string(path), level)
	if uid != ResourceUID.INVALID_ID:
		var head := text.get_slice("\n", 0)
		if not head.contains("uid="):
			text = head.replace("]", " uid=\"%s\"]" % ResourceUID.id_to_text(uid)) \
					+ text.substr(head.length())
		ResourceUID.set_id(uid, path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("      %-26s %d brush shape(s), was %d; %d mesh(es)" % [
			path.get_file(), shapes, was, meshes])
	print("      REBAKE THE NAVMESH if any walkable surface moved.")
	print("LEVEL MAP REBUILD DONE")
	quit()


## PACKING OUTSIDE THE EDITOR WRITES EVERY EXPORTED PROPERTY, defaults and all
## — four hundred extra lines in this level the first time it was rebuilt. They
## are the right values today, and they are a trap tomorrow: a scene value
## beats a script default in this engine, so a level that pins four hundred of
## them silently ignores every default anyone changes afterwards. The editor
## strips them on save, so this does too, and a rebuilt level diffs against an
## editor-saved one as only the geometry having moved.
##
## A line goes only if the value it stores is the value the node would have
## anyway, and WHAT THAT MEANS DEPENDS ON WHERE THE NODE CAME FROM:
##
##   - a node written out with a script: a fresh instance of that script.
##   - a node inside an INSTANCED sub-scene: the matching node in a fresh copy
##     of that scene. It must not be the script default, or a level that
##     deliberately puts a property BACK to the script's value gets that line
##     stripped and the sub-scene's value instead — a silent behaviour change,
##     which is the very thing this is here to prevent.
##
## Built-in Node properties never reach either test: ResourceSaver has already
## left those out unless they were changed.
func _strip_defaults(text: String, level: Node) -> String:
	var kept := PackedStringArray()
	var fresh: Array = []          # everything made here, to free at the end
	var bases := {}                # scene or script path -> a pristine copy
	var node: Node = null
	var like: Object = null        # what this node would be if nothing was set
	var header := -1
	var dropped: Array = []
	for line in text.split("\n"):
		if line.begins_with("["):
			_fix_node_paths(kept, header, dropped)
			header = -1
			dropped = []
			node = null
			like = null
			if line.begins_with("[node "):
				node = level.get_node_or_null(NodePath(_scene_path(line)))
				like = _pristine(node, level, bases, fresh) if node != null else null
				header = kept.size()
			kept.append(line)
			continue
		var eq := line.find(" = ")
		var key := line.substr(0, eq) if eq > 0 else ""
		if like == null or key == "" or key == "script" or not _has_property(node, key):
			kept.append(line)
			continue
		var was: Variant = like.get(key)
		if typeof(was) == typeof(node.get(key)) and was == node.get(key):
			dropped.append(key)
			continue
		kept.append(line)
	_fix_node_paths(kept, header, dropped)
	for o: Object in fresh:
		if o is Node:
			(o as Node).free()
	return "\n".join(kept)


## What this node would be with nothing written about it: its twin in a fresh
## copy of the sub-scene it belongs to, or a bare instance of its script.
func _pristine(node: Node, level: Node, bases: Dictionary, fresh: Array) -> Object:
	var inst: Node = node
	while inst != null and inst != level and inst.scene_file_path == "":
		inst = inst.get_parent()
	if inst != null and inst != level and inst.scene_file_path != "":
		if not bases.has(inst.scene_file_path):
			var packed := load(inst.scene_file_path) as PackedScene
			if packed == null:
				return null
			var copy := packed.instantiate()
			fresh.append(copy)
			bases[inst.scene_file_path] = copy
		var under: Node = bases[inst.scene_file_path]
		var twin: Node = under if node == inst else under.get_node_or_null(
				NodePath(String(inst.get_path_to(node))))
		# No twin means the node was ADDED under the instance rather than being
		# part of it — a cover point hung off a level exit — so it answers to
		# its script like any other.
		if twin != null:
			return twin
	var script: Script = node.get_script()
	if script == null:
		return null
	if not bases.has(script.resource_path):
		var made: Variant = script.new()
		if not (made is Object):
			return null
		fresh.append(made)
		bases[script.resource_path] = made
	return bases[script.resource_path]


## A dropped NodePath export has to come out of the node's node_paths list too,
## or the scene names a property it never stores and the load warns.
func _fix_node_paths(lines: PackedStringArray, header: int, dropped: Array) -> void:
	if header < 0 or dropped.is_empty():
		return
	var line := lines[header]
	var open := line.find("node_paths=PackedStringArray(")
	if open < 0:
		return
	var from := open + "node_paths=PackedStringArray(".length()
	var close := line.find(")", from)
	var keep: Array = []
	for name in line.substr(from, close - from).split(",", false):
		if not dropped.has(name.strip_edges().trim_prefix("\"").trim_suffix("\"")):
			keep.append(name.strip_edges())
	if keep.is_empty():
		lines[header] = (line.substr(0, open) + line.substr(close + 1)).replace("  ", " ").replace(" ]", "]")
	else:
		lines[header] = line.substr(0, from) + ", ".join(keep) + line.substr(close)


## The path a [node] line names, relative to the scene root.
func _scene_path(line: String) -> String:
	var name := line.get_slice("name=\"", 1).get_slice("\"", 0)
	if not line.contains("parent=\""):
		return "."
	var parent := line.get_slice("parent=\"", 1).get_slice("\"", 0)
	return name if parent == "." else parent + "/" + name


func _has_property(node: Node, key: String) -> bool:
	for p: Dictionary in node.get_property_list():
		if p.name == key:
			return true
	return false
