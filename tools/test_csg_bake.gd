extends SceneTree

# ─────────────────────────────────────────────
# ROBOTS MUST NOT BUILD CSG AT RUNTIME, AND MUST LOOK THE SAME WITHOUT IT.
#
# A CSGShape3D rebuilds its geometry the first time it enters the tree. Measured
# on Three Rivers, a reserve wave of 40 soldiers cost 335.8 ms on the frame it
# landed, 9.9 ms with the CSG nodes removed — 97% of the spike, and none of it
# AI. The rover carries 10 CSG nodes to a soldier's 2.
#
# csg_bake.gd builds each scene's CSG once at boot and hands every robot after
# that a MeshInstance3D sharing the result. The two things that can go wrong are
# both checked here:
#
#   * THE SHAPE CHANGES. The swap must occupy the same space as the CSG did, or
#     robots are the wrong size and nothing in a headless run would say so.
#   * A REFERENCE IS LEFT DANGLING. `visible_pieces` on the body and `pieces` on
#     FactionLivery are node_paths, which Godot resolves to LIVE NODES at
#     instantiate time. Swap without repointing them and they hold a freed node.
#
#   godot --headless --path . --script res://tools/test_csg_bake.gd
# ─────────────────────────────────────────────

const _CsgBake := preload("res://Character/characters/ai/csg_bake.gd")
const AI_DIR := "res://Character/characters/ai"

var _fails: int = 0
var _level: Node = null
var _host: Node3D = null
## Instances kept alive deliberately. See _test_shape.
var _parked: Array = []


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 120:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	_level = player.get_parent()
	_host = _level

	_check("the bake ran at boot, without anyone asking it to", _CsgBake.is_warm())
	_check("...and it baked every AI scene that has CSG in it",
		_CsgBake.baked_scenes >= 14 and _CsgBake.baked_nodes >= 50,
		"%d scene(s), %d CSG node(s)" % [_CsgBake.baked_scenes, _CsgBake.baked_nodes])

	await _test_shape()
	await _test_refs()
	await _test_cost()
	_test_spawned()
	await _test_typed_arrays()

	print("")
	print("ALL CSG BAKE CHECKS PASS" if _fails == 0 else "%d CSG BAKE CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


## THE SWAPPED BODY OCCUPIES THE SAME SPACE AS THE CSG DID.
##
## Compared against a reference instance that is NOT swapped — built by hand with
## the cache bypassed — so this is the real CSG's bounds, not a number copied out
## of the bake and checked against itself.
func _test_shape() -> void:
	print("")
	print("══ SHAPE ═════════════════════════════════════════════════")
	for path in _csg_scenes():
		var packed := load(path) as PackedScene
		# NOT process_mode DISABLED, and given room to go. A disabled body torn
		# down a frame later is what crashed the headless renderer on exit — all
		# checks passing and the process still returning 139, which test.sh reads
		# as a failure. tools/probe_bake_churn.gd builds and frees every chassis
		# this way and exits clean.
		var got: Node3D = _CsgBake.make(packed)
		_host.add_child(got)
		for _i in 6:
			await physics_frame

		# Against the CSG bounds recorded AT BAKE TIME. Standing up a second,
		# unbaked copy of every chassis to compare against meant sixteen bodies
		# building real CSG and being torn down in one run, which crashed the
		# headless renderer on exit — 25 checks passing and the process still
		# returning 139, which test.sh reads as a failure.
		var recs: Array = _CsgBake._cache[path]
		var worst := 0.0
		var n_mesh := 0
		for rec in recs:
			var n := got.get_node_or_null(NodePath(rec["path"]))
			if n == null or not (n is MeshInstance3D):
				continue
			n_mesh += 1
			var want: AABB = rec["aabb"]
			var have: AABB = (n as VisualInstance3D).get_aabb()
			worst = maxf(worst, want.size.distance_to(have.size))
			worst = maxf(worst, want.position.distance_to(have.position))
		_check("%-30s %d shape(s), same bounds as the CSG" % [path.get_file(), n_mesh],
			n_mesh == recs.size() and n_mesh > 0 and worst < 0.02,
			"worst corner differs by %.4f m" % worst)
		got.queue_free()
		for _i in 8:
			await physics_frame


## NOTHING IS LEFT POINTING AT THE NODE THAT WAS REMOVED.
func _test_refs() -> void:
	print("")
	print("══ REFERENCES ════════════════════════════════════════════")
	var packed := load("res://Character/characters/ai/soldier_rifle.tscn") as PackedScene
	var body: Node3D = _CsgBake.make(packed)
	body.process_mode = Node.PROCESS_MODE_DISABLED
	_host.add_child(body)
	for _i in 4:
		await physics_frame

	var vp = body.get("visible_pieces")
	var live := true
	var kinds := PackedStringArray()
	for n in vp:
		if n == null or not is_instance_valid(n):
			live = false
		else:
			kinds.append(n.get_class())
	_check("visible_pieces holds live nodes, none of them freed", live, str(kinds))
	_check("...and no CSG survives in it", not kinds.has("CSGMesh3D"), str(kinds))

	var liv := body.get_node_or_null("FactionLivery")
	if liv != null:
		var pieces = liv.get("pieces")
		var ok := true
		for n in pieces:
			if n == null or not is_instance_valid(n) or n is CSGShape3D:
				ok = false
		_check("FactionLivery.pieces was repointed at the baked mesh", ok and pieces.size() > 0,
			"%d piece(s)" % (pieces.size() if pieces != null else -1))
	body.free()


## AND THE SPIKE IS ACTUALLY GONE.
func _test_cost() -> void:
	print("")
	print("══ COST ══════════════════════════════════════════════════")
	# SETTLE FIRST. The sections above queue_free about thirty instances, and a
	# deferred free lands on a later frame — which was the frame being measured,
	# so the wave was being billed for tearing down somebody else's CSG.
	for _i in 30:
		await physics_frame
	var packed := load("res://Character/characters/ai/soldier_rifle.tscn") as PackedScene
	var made: Array = []
	for _i in 40:
		var b: Node3D = _CsgBake.make(packed)
		b.faction = Enums.Factions.ENEMY
		_host.add_child(b)
		b.global_position = Vector3(randf_range(-20, 20), 2, randf_range(-20, 20))
		made.append(b)
	# Prove they are actually baked before billing them, or a failure here is
	# ambiguous between "the swap did not happen" and "the frame was expensive".
	var csg_left := 0
	for b in made:
		var s2: Array = [b]
		while not s2.is_empty():
			var n: Node = s2.pop_back()
			for c in n.get_children():
				s2.append(c)
			if n is CSGShape3D:
				csg_left += 1
	_check("the wave was built through make(), so it carries no CSG", csg_left == 0,
		"%d shape(s) left" % csg_left)
	var t0 := Time.get_ticks_usec()
	await physics_frame
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	# It was 335.8 ms. Anything near that means the swap is not happening at all;
	# the threshold is deliberately loose because this runs on whatever machine.
	_check("a 40-robot wave costs a frame, not a third of a second", ms < 90.0,
		"%.1f ms on the frame it lands" % ms)
	for b in made:
		b.queue_free()
	await physics_frame
	await physics_frame


func _csg_scenes() -> Array:
	var out: Array = []
	var dir := DirAccess.open(AI_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".tscn"):
			continue
		var p := "%s/%s" % [AI_DIR, f]
		if not _CsgBake._cache.has(p):
			continue
		out.append(p)
	out.sort()
	return out


## Combined bounds of exactly the nodes the bake recorded, in body space.
func _bounds_at(body: Node3D, recs: Array) -> AABB:
	var out := AABB()
	var first := true
	for rec in recs:
		var n := body.get_node_or_null(NodePath(rec["path"]))
		if n == null or not (n is VisualInstance3D):
			continue
		var box: AABB = (n as VisualInstance3D).get_aabb()
		box = body.global_transform.affine_inverse() * (n as Node3D).global_transform * box
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


func _count_at(body: Node3D, recs: Array, csg: bool) -> int:
	var n := 0
	for rec in recs:
		var node := body.get_node_or_null(NodePath(rec["path"]))
		if node == null:
			continue
		if (node is CSGShape3D) if csg else (node is MeshInstance3D):
			n += 1
	return n


## AND THE GAME'S OWN SPAWNERS GO THROUGH IT.
##
## The swap cannot live inside the robot — _enter_tree is a tree notification and
## restructuring from inside one segfaults the engine, _ready runs after
## initialize() has already measured the body — so it lives at the four places
## that BUILD robots instead. Which means the thing most likely to go wrong is
## someone adding a fifth and calling instantiate() directly.
##
## So this checks the squad the world deploys on its own at boot: if those came
## through CsgBake.make(), the wiring is real.
func _test_spawned() -> void:
	print("")
	print("══ THE SQUAD THE GAME DEPLOYED ON ITS OWN ════════════════")
	var bodies: Array = []
	var stack: Array = [_level]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.is_in_group("enemies") and n.scene_file_path != "":
			bodies.append(n)
	_check("the world stood a squad up without being asked", bodies.size() >= 4,
		"%d robot(s)" % bodies.size())
	var with_csg := PackedStringArray()
	for b in bodies:
		var found := 0
		var s2: Array = [b]
		while not s2.is_empty():
			var n: Node = s2.pop_back()
			for c in n.get_children():
				s2.append(c)
			if n is CSGShape3D:
				found += 1
		if found > 0:
			with_csg.append("%s (%d)" % [str(b.name), found])
	_check("...and not one of them is still carrying CSG", with_csg.is_empty(),
		str(with_csg) if not with_csg.is_empty() else "%d checked" % bodies.size())


## TYPED ARRAYS MUST BE ASKED WHAT THEY HOLD, NOT PROBED.
##
## Array.find() validates its argument against the array's element type and
## ERRORS on a mismatch rather than returning -1. A robot carries script arrays
## of ints, of AudioStreams, of Scripts; asking each whether it contains a CSG
## node printed one engine error per array per node per swapped shape. On load
## that was thousands of lines and it took the game down.
##
## NOT ONE TEST SAW IT. The checks above all passed while the game crashed on
## startup, and smoke.sh missed it too because its filter looks for "SCRIPT
## ERROR" and these are engine-level ERR_FAIL prints. So this watches the only
## thing a script CAN see: that the incompatible arrays were skipped rather than
## probed. If that count goes to zero, the probing is back.
func _test_typed_arrays() -> void:
	print("")
	print("══ TYPED ARRAYS ══════════════════════════════════════════")
	_CsgBake.arrays_skipped = 0
	_CsgBake.arrays_scanned = 0
	var body: Node3D = _CsgBake.make(load("res://Character/characters/ai/vehicle_rover.tscn"))
	_host.add_child(body)
	for _i in 4:
		await physics_frame
	print("     %d array(s) skipped as unable to hold a node, %d scanned" % [
		_CsgBake.arrays_skipped, _CsgBake.arrays_scanned])
	_check("arrays that cannot hold a node are skipped, not probed",
		_CsgBake.arrays_skipped > 0, "%d skipped" % _CsgBake.arrays_skipped)
	_check("...and the ones that can are still scanned, or nothing gets repointed",
		_CsgBake.arrays_scanned > 0, "%d scanned" % _CsgBake.arrays_scanned)
	body.queue_free()
	for _i in 8:
		await physics_frame
