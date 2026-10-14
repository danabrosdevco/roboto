extends SceneTree

# ─────────────────────────────────────────────
# WHAT A LEVEL COSTS, COUNTED RATHER THAN GUESSED.
#
#   LEVEL=res://maps/salient_level.tscn godot --headless --audio-driver Dummy \
#       --path . --script res://tools/probe_level_cost.gd
#
# Salient is the biggest map in the project and the slowest, and "it has a lot
# of objects" is not a finding you can act on. This counts the things that
# actually cost per frame and attributes them to the PREFAB responsible, so
# the answer comes out as "this one block, times this many" rather than a
# total nobody can do anything with.
#
# WHY COLLISION SHAPES GET THEIR OWN COLUMN. A FuncGodot brush block becomes
# one ConvexPolygonShape3D per convex piece, and a long revetment is a lot of
# pieces. Those sit in the physics broadphase forever whether or not anything
# is near them, and every near-miss suppression query, every ground snap and
# every melee sweep pays for the size of that broadphase.
# ─────────────────────────────────────────────

func _init() -> void:
	var path := OS.get_environment("LEVEL")
	if path == "":
		path = "res://maps/salient_level.tscn"
	var level: Node = load(path).instantiate()
	root.add_child(level)
	for _i in 4:
		await process_frame

	var tally := _tally(level)
	print("── %s ──" % path.get_file())
	print("  nodes            %7d" % tally["nodes"])
	print("  MeshInstance3D   %7d   (one draw call each unless multimeshed)" % tally["meshes"])
	print("  CollisionShape3D %7d   (every one lives in the broadphase)" % tally["shapes"])
	print("  physics bodies   %7d" % tally["bodies"])
	print("  lights           %7d" % tally["lights"])
	print("")
	print("── WHERE IT COMES FROM (top offenders by collision shapes) ──")
	var rows: Array = []
	for k in tally["blocks"]:
		rows.append([k, tally["blocks"][k]])
	rows.sort_custom(func(a, b): return int(a[1]["shapes"]) > int(b[1]["shapes"]))
	print("  %-34s %6s %7s %8s" % ["block", "count", "meshes", "shapes"])
	for i in mini(rows.size(), 14):
		var r = rows[i]
		print("  %-34s %6d %7d %8d" % [r[0], r[1]["count"], r[1]["meshes"], r[1]["shapes"]])
	quit(0)


func _tally(level: Node) -> Dictionary:
	var out := {"nodes": 0, "meshes": 0, "shapes": 0, "bodies": 0, "lights": 0, "blocks": {}}
	# The art is a tree of instanced blocks. Attribute everything under a block
	# to that block, so the report names the thing to fix.
	_count(level, out, "")
	return out


func _count(n: Node, out: Dictionary, block: String) -> void:
	out["nodes"] += 1
	# A node whose scene_file_path is set is an instanced block; everything
	# below it belongs to that block.
	# The DEEPEST instanced block wins, not the outermost. Stopping at the
	# first one attributed the entire map to "salient_level", which is true
	# and useless: the point of the report is to name the block to fix.
	var here := block
	if n.scene_file_path != "":
		here = n.scene_file_path.get_file().get_basename()
		if not out["blocks"].has(here):
			out["blocks"][here] = {"count": 0, "meshes": 0, "shapes": 0}
		out["blocks"][here]["count"] += 1

	if n is MeshInstance3D:
		out["meshes"] += 1
		if here != "" and out["blocks"].has(here):
			out["blocks"][here]["meshes"] += 1
	if n is CollisionShape3D:
		out["shapes"] += 1
		if here != "" and out["blocks"].has(here):
			out["blocks"][here]["shapes"] += 1
	if n is PhysicsBody3D:
		out["bodies"] += 1
	if n is Light3D:
		out["lights"] += 1

	for c in n.get_children():
		_count(c, out, here)
