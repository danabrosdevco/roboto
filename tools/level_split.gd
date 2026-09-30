extends "res://tools/level_map_rebuild.gd"

# ─────────────────────────────────────────────
# LEVEL SPLIT — takes a level that holds its art and its gameplay in one file
# and cuts it in two: an ART scene the TERRAIN lane can rewrite whenever it
# likes, and the LEVEL, which instances it and is never regenerated again.
#
#   LEVEL=res://maps/pittsburgh_level.tscn \
#   MOVE=NavigationRegion3D/Terrain,NavigationRegion3D/Blocks \
#       godot --headless --path . --script res://tools/level_split.gd
#
#   ...and again with --apply once the report reads right. It writes nothing
#   without it, because a tool whose entire purpose is not destroying work
#   should not destroy any on its first run.
#
# WHY. From GAMEPLAY's report, in their words: "the regenerator does not
# preserve nodes it did not place. Every rebuild deletes the relay console, the
# extraction and the spawn move." The repair was an idempotent shell script run
# by hand after every TERRAIN pass.
#
# The fix is not a better merge. It is a FILE BOUNDARY. A regenerator that
# writes maps/<name>_art.tscn cannot delete anything in maps/<name>_level.tscn,
# because it never opens it — and that is a guarantee rather than a promise,
# which a merge can never be.
#
# WHAT GOES WHERE. Terrain, its modifiers, its scatter and every block standing
# on it go to ART. The spawn, the exit, the environment, the navigation region,
# the objective anchors and everything GAMEPLAY adds stay in the LEVEL.
# Objective ANCHORS stay behind on purpose: patrol points are children of them,
# so an anchor that gets regenerated takes someone's patrol route with it.
#
# THE NAVMESH IS THE ONE THING THAT STILL CROSSES. It is baked from the art and
# stored on the level's NavigationRegion3D — but probe_nav_hillfort writes it
# back by replacing two lines, so a rebake is not a rewrite.
# ─────────────────────────────────────────────


func _initialize() -> void:
	await process_frame
	var path := OS.get_environment("LEVEL")
	var moves: Array = []
	for m in OS.get_environment("MOVE").split(",", false):
		moves.append(m.strip_edges())
	if path == "":
		print("usage: LEVEL=res://maps/<name>_level.tscn [MOVE=a/b,c/d] [--apply]")
		quit(2)
		return
	var art_path := OS.get_environment("ART")
	if art_path == "":
		art_path = path.replace("_level.tscn", "_art.tscn")
	var apply := OS.get_cmdline_user_args().has("--apply")
	var packed := load(path) as PackedScene
	if packed == null:
		print("FAIL  %s will not load" % path)
		quit(1)
		return
	var level := packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)

	# WORK THE LIST OUT RATHER THAN BE TOLD IT. Every level in this project
	# keeps its art as siblings of the exit under the navigation region:
	# Terrain, Dressing, Buildings, Bridges, Fort, Field, Plant, the FuncGodot
	# maps. What stays behind is the exit and anything carrying a Campaign
	# script, because that is gameplay whoever placed it. Typing the list by
	# hand for nine levels is nine chances to leave a group out.
	if moves.is_empty():
		var region := level.get_node_or_null(^"NavigationRegion3D")
		if region == null:
			print("FAIL  %s has no NavigationRegion3D to split under" % path.get_file())
			quit(1)
			return
		for c in region.get_children():
			if str(c.name) == "LevelExit" or _is_gameplay(c):
				continue
			moves.append("NavigationRegion3D/%s" % c.name)
		print("   auto: %s" % ", ".join(moves))
	if moves.is_empty():
		print("FAIL  nothing to move")
		quit(1)
		return

	# Everything that moves has to share one parent, because what replaces them
	# is a single instance of the art scene and it can only go in one place.
	var taken: Array = []
	var holder: Node = null
	var at := 1 << 30
	for m: String in moves:
		var n := level.get_node_or_null(NodePath(m))
		if n == null:
			print("FAIL  %s has no node at %s" % [path.get_file(), m])
			quit(1)
			return
		if holder == null:
			holder = n.get_parent()
		elif n.get_parent() != holder:
			print("FAIL  %s is under %s, not %s — everything moved must share a parent" % [
					m, n.get_parent().name, holder.name])
			quit(1)
			return
		at = mini(at, n.get_index())
		taken.append(n)

	var art_name: String = art_path.get_file().get_basename().to_pascal_case()
	var art := Node3D.new()
	art.name = art_name
	for n: Node in taken:
		holder.remove_child(n)
		art.add_child(n)
	var bases := {}
	reown(art, art, null, null, bases)
	free_bases(bases)
	# THE PATHS OF EVERYTHING MOVED HAVE CHANGED, by exactly one level: what was
	# NavigationRegion3D/Terrain is now NavigationRegion3D/<Art>/Terrain. Any
	# NodePath left in the level that pointed into the art is now broken, and a
	# broken NodePath is a null at load and a crash later, so they get named
	# here rather than found in play.
	var broken: Array = []
	_scan(level, level, broken)
	for b: String in broken:
		print("      BROKEN PATH  %s" % b)

	var counts := {}
	for n: Node in art.find_children("*", "", true, false):
		counts[n.get_class()] = int(counts.get(n.get_class(), 0)) + 1
	print("   %s" % path.get_file())
	print("   art: %s — %d node(s) moved under %s" % [art_path.get_file(),
			art.find_children("*", "", true, false).size(), holder.name])
	print("   level keeps: %s" % ", ".join(_names(level, holder)))
	if not broken.is_empty():
		print("   %d NodePath(s) in the level point into the art and would break." % broken.size())
		print("   Fix those first: they are the silent half of this change.")
		if apply:
			print("FAIL  refusing to --apply with broken paths")
			quit(1)
			return
	if not apply:
		print("   DRY RUN — pass --apply to write the two files")
		quit()
		return

	var art_scene := PackedScene.new()
	if art_scene.pack(art) != OK or ResourceSaver.save(art_scene, art_path) != OK:
		print("FAIL  could not write %s" % art_path)
		quit(1)
		return
	var stripped := _strip_defaults(FileAccess.get_file_as_string(art_path), art)
	var af := FileAccess.open(art_path, FileAccess.WRITE)
	af.store_string(stripped)
	af.close()

	# Put the art back in as one instance, where the first moved node was.
	var reloaded := load(art_path) as PackedScene
	var inst := reloaded.instantiate()
	inst.name = art_name
	holder.add_child(inst)
	holder.move_child(inst, mini(at, holder.get_child_count() - 1))
	inst.owner = level
	var uid := ResourceLoader.get_resource_uid(path)
	var out := PackedScene.new()
	if out.pack(level) != OK or ResourceSaver.save(out, path) != OK:
		print("FAIL  could not write %s" % path)
		quit(1)
		return
	var text := _strip_defaults(FileAccess.get_file_as_string(path), level)
	if uid != ResourceUID.INVALID_ID:
		var head := text.get_slice("\n", 0)
		if not head.contains("uid="):
			text = head.replace("]", " uid=\"%s\"]" % ResourceUID.id_to_text(uid)) \
					+ text.substr(head.length())
		ResourceUID.set_id(uid, path)
	var lf := FileAccess.open(path, FileAccess.WRITE)
	lf.store_string(text)
	lf.close()
	print("      wrote both. REBAKE THE NAVMESH, then check nothing moved.")
	print("LEVEL SPLIT DONE")
	quit()


## Every NodePath property on every node left in the level, tested against the
## level as it now is.
func _scan(node: Node, level: Node, broken: Array) -> void:
	for p: Dictionary in node.get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_STORAGE):
			continue
		var v: Variant = node.get(p.name)
		if v is NodePath:
			if String(v) != "" and node.get_node_or_null(v as NodePath) == null:
				broken.append("%s.%s -> %s" % [level.get_path_to(node), p.name, v])
		elif v is Array:
			for e in (v as Array):
				if e is NodePath and String(e) != "" and node.get_node_or_null(e) == null:
					broken.append("%s.%s -> %s" % [level.get_path_to(node), p.name, e])
	for c in node.get_children():
		_scan(c, level, broken)


func _names(level: Node, holder: Node) -> Array:
	var out: Array = []
	for c in level.get_children():
		out.append(str(c.name))
	for c in holder.get_children():
		if not out.has(str(c.name)):
			out.append("%s/%s" % [holder.name, c.name])
	return out


## A node the GAMEPLAY lane owns: anything running a script out of Campaign/,
## at any depth. Those stay in the level whatever they are called.
func _is_gameplay(node: Node) -> bool:
	var s: Script = node.get_script()
	if s != null and s.resource_path.begins_with("res://Campaign/"):
		return true
	for c in node.get_children():
		if _is_gameplay(c):
			return true
	return false


## WHO OWNS WHAT, AND WHY IT IS NOT "EVERYTHING".
##
## A packed scene writes out every node the root OWNS. Set the owner of every
## descendant and the insides of each instanced prefab get written as declared
## nodes — 96 prefabs became 2353 node entries the first time this ran, and
## worse than the bloat, it PINS them: each one is re-declared with its own
## type, so editing landmark_relay_dish.tscn would no longer reach the level
## that instances it. The whole prefab workflow quietly stops working.
##
## So: an instance ROOT is owned, because that is what writes the
## `instance=ExtResource(...)` line. Nothing inside one is touched.
static func reown(root: Node, node: Node, inst: Node, base: Node, cache: Dictionary) -> void:
	for c in node.get_children():
		var next_inst := inst
		var next_base := base
		if c.scene_file_path != "":
			# An instance ROOT is owned: that is what writes the instance= line.
			c.owner = root
			next_inst = c
			next_base = _base_of(c.scene_file_path, cache)
		elif inst == null:
			c.owner = root
		else:
			# INSIDE AN INSTANCE, and this is the distinction that matters. If
			# the prefab has a node at this path it is the prefab's own and must
			# not be written — owner cleared. If it does not, somebody ADDED it,
			# and it has to stay: patrol points are children of instanced
			# objective anchors, and clearing those would delete the patrol
			# routes this whole exercise exists to protect.
			var twin: Node = null
			if base != null:
				twin = base.get_node_or_null(NodePath(String(inst.get_path_to(c))))
			c.owner = null if twin != null else root
		reown(root, c, next_inst, next_base, cache)


static func _base_of(path: String, cache: Dictionary) -> Node:
	if not cache.has(path):
		var p := load(path) as PackedScene
		cache[path] = p.instantiate() if p != null else null
	return cache[path]


static func free_bases(cache: Dictionary) -> void:
	for k in cache:
		if cache[k] is Node:
			(cache[k] as Node).free()
