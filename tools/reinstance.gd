extends "res://tools/level_map_rebuild.gd"

# ─────────────────────────────────────────────
# REINSTANCE — repairs a scene whose instanced sub-scenes have been written out
# as declared nodes, and puts them back to being instances.
#
#   SCENE=res://maps/hillfort_art.tscn godot --headless --path . \
#       --script res://tools/reinstance.gd
#   ...and again with --apply.
#
# WHAT GOES WRONG. A packed scene writes every node its root OWNS. A tool that
# repacks a scene and sets the owner of every descendant therefore writes the
# INSIDES of every instanced prefab out as well, each with its own `type=`.
# Ninety-six prefabs in hillfort became 2353 node entries that way. The file
# size is the least of it: those internals are now declared in this scene, so
# editing the prefab no longer reaches the level that instances it, and the
# whole maps/blocks workflow stops propagating without saying so.
#
# THE RULE. An instance ROOT is owned by the scene root — that is what writes
# the `instance=ExtResource(...)` line. Nothing inside one is owned by anybody,
# so nothing inside one is written. Overrides that were genuinely authored on
# an instance's child are lost by this, which is the trade: this repairs scenes
# that never had any, and it says how many it dropped so the trade is visible.
# ─────────────────────────────────────────────

const Split := preload("res://tools/level_split.gd")


func _initialize() -> void:
	await process_frame
	var path := OS.get_environment("SCENE")
	if path == "":
		print("usage: SCENE=res://maps/<name>.tscn [--apply]")
		quit(2)
		return
	var apply := OS.get_cmdline_user_args().has("--apply")
	var was := _declared_inside_instances(path)
	var packed := load(path) as PackedScene
	if packed == null:
		print("FAIL  %s will not load" % path)
		quit(1)
		return
	var scene := packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	var bases := {}
	Split.reown(scene, scene, null, null, bases)
	if not apply:
		print("   %-30s %d node(s) declared inside an instance" % [path.get_file(), was])
		print("   DRY RUN — pass --apply")
		quit()
		return
	var uid := ResourceLoader.get_resource_uid(path)
	var out := PackedScene.new()
	if out.pack(scene) != OK or ResourceSaver.save(out, path) != OK:
		print("FAIL  could not write %s" % path)
		quit(1)
		return
	var text := _strip_defaults(FileAccess.get_file_as_string(path), scene)
	if uid != ResourceUID.INVALID_ID:
		var head := text.get_slice("\n", 0)
		if not head.contains("uid="):
			text = head.replace("]", " uid=\"%s\"]" % ResourceUID.id_to_text(uid)) \
					+ text.substr(head.length())
		ResourceUID.set_id(uid, path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	Split.free_bases(bases)
	print("   %-30s %d -> %d node(s) declared inside an instance" % [
			path.get_file(), was, _declared_inside_instances(path)])
	quit()


## How many node entries this scene declares that sit under something it
## instances — the symptom, counted off the text rather than the tree.
func _declared_inside_instances(path: String) -> int:
	var roots: Array = []
	var n := 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if not line.begins_with("[node "):
			continue
		var name := line.get_slice("name=\"", 1).get_slice("\"", 0)
		var parent := line.get_slice("parent=\"", 1).get_slice("\"", 0) if line.contains("parent=\"") else ""
		var here := name if parent == "." or parent == "" else parent + "/" + name
		if line.contains("instance=ExtResource"):
			roots.append(here)
			continue
		for r: String in roots:
			if parent == r or parent.begins_with(r + "/"):
				n += 1
				break
	return n
