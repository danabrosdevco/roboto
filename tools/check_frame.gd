extends SceneTree

# ─────────────────────────────────────────────
# IS THIS ROBOT SCENE ACTUALLY WIRED? One frame, or many.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/check_frame.gd -- <scene.tscn> [...]
#
# WHY IT EXISTS. check.sh proves a scene PARSES. Every expensive bug the
# Bulwark hit passed that check and still shipped a robot that looked right and
# did nothing: groups added non-persistently so the scene saved with no groups
# line at all; untyped arrays assigned to typed exports, which fail SILENTLY
# and save as []; a WeaponMount yawed the wrong way so the gun pointed
# backwards. None of those raise. All of them are one assertion each.
#
# So this is the Bulwark's bug list turned into a test, written once for the
# family rather than re-learned per frame. A new chassis scene is not done
# until this prints PASS.
#
# It instantiates but does NOT add to the tree: _ready on these scripts reaches
# for managers that do not exist in a headless probe, and every property below
# is resolved at instantiate time anyway.
# ─────────────────────────────────────────────

var _fails := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("check_frame: <scene.tscn> [...]")
		quit(1)
		return
	for path in args:
		await _check(path)
	print("")
	if _fails > 0:
		print("FAIL  %d of %d checks failed" % [_fails, _checks])
		quit(1)
		return
	print("PASS  %d checks" % _checks)
	quit(0)

func _ok(cond: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if cond:
		print("  ok    %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fails += 1
		print("  FAIL  %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _check(path: String) -> void:
	print("\n=== %s" % path)
	if not ResourceLoader.exists(path):
		_ok(false, "scene exists")
		return
	var ps := load(path) as PackedScene
	if ps == null:
		_ok(false, "loads as PackedScene")
		return
	var n := ps.instantiate()
	_ok(n is CharacterBody3D, "root is CharacterBody3D", n.get_class())

	# GROUPS. add_to_group's second argument defaults to false — "this run
	# only" — so a scene built without it saves with no groups line and the
	# robot is invisible to AIManager, to EMP and to every hostile sweep.
	_ok(n.is_in_group("enemies"), "in group \"enemies\" PERSISTENTLY")

	var col := _find(n, "CollisionShape3D", true)
	_ok(col != null and col.get("shape") != null, "CollisionShape3D has a shape")
	if col != null and col.get("shape") != null:
		var sh = col.get("shape")
		if sh is CapsuleShape3D:
			print("        capsule  r %.2f  h %.2f" % [sh.radius, sh.height])
		elif sh is BoxShape3D:
			print("        box      %.2f x %.2f x %.2f" % [sh.size.x, sh.size.y, sh.size.z])

	for prop in ["nav_agent", "detection"]:
		_ok(n.get(prop) != null, "%s wired" % prop)

	# TYPED ARRAYS OR THEY SAVE EMPTY. Assigning a plain Array to an
	# Array[Node3D] export fails with no error and the packed scene comes out
	# with []. The Bulwark shipped all four of these empty on its first build.
	for prop in ["visible_pieces", "particle_effects_die", "particle_effects_hit"]:
		var arr = n.get(prop)
		_ok(arr != null and (arr as Array).size() > 0, "%s non-empty" % prop,
				"size %d" % [(arr as Array).size() if arr != null else -1])

	# LIVERY. An empty `pieces` is worse than no livery at all: FactionLivery
	# falls back to walking its entire parent, which paints every mesh on the
	# frame INCLUDING THE EYE.
	var liv := _find(n, "FactionLivery", false)
	_ok(liv != null, "FactionLivery present")
	if liv != null:
		var pieces = liv.get("pieces")
		_ok(pieces != null and (pieces as Array).size() > 0, "livery pieces non-empty",
				"size %d" % [(pieces as Array).size() if pieces != null else -1])
		var eye := _find(n, "Eye", true)
		if eye != null and pieces != null:
			_ok(not (pieces as Array).has(eye), "EYE EXCLUDED from livery")

	# MOUNT YAW. +PI/2, not -PI/2. Both shipping frames agree and a mount built
	# the other way points the barrel backwards with nothing complaining.
	var mount = n.get("weapon_mount")
	if mount != null:
		var yaw: float = (mount as Node3D).rotation.y
		_ok(absf(yaw - PI * 0.5) < 0.01, "WeaponMount yaw is +90 degrees",
				"%.1f deg" % rad_to_deg(yaw))

	# Nothing unpainted. One mesh without a material is invisible as a bug
	# until someone renders the frame in a faction colour.
	var bare: Array[String] = []
	_bare_meshes(n, n, bare)
	_ok(bare.is_empty(), "every mesh has a material",
			"bare: " + ", ".join(bare) if not bare.is_empty() else "")

	# IN THE TREE, and only for the measurement. A CSGShape3D outside the tree
	# has never generated a mesh, so get_aabb() returns nothing and every
	# CSG-heavy frame measures short — the Walker came out 3.73 against a real
	# 3.81, and the Picket lost its entire launcher. Found by the Picket agent,
	# which measured in-tree by hand and got a different answer.
	root.add_child(n)
	await process_frame
	await process_frame
	var bb := _bounds(n, n)
	print("        measured  W %.2f  H %.2f  L %.2f" % [bb.size.x, bb.size.y, bb.size.z])
	root.remove_child(n)
	n.free()


func _find(from: Node, nm: String, recurse: bool) -> Node:
	for c in from.get_children():
		if c.name == nm:
			return c
		if recurse:
			var sub := _find(c, nm, true)
			if sub != null:
				return sub
	return null


func _bare_meshes(n: Node, root_n: Node, out: Array[String]) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var has := mi.material_override != null
		if not has and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			has = mi.get_surface_override_material(0) != null \
					or mi.mesh.surface_get_material(0) != null
		if not has:
			out.append(str(root_n.get_path_to(mi)))
	for c in n.get_children():
		_bare_meshes(c, root_n, out)


## Subtraction shapes are deliberately oversized and do not count.
func _bounds(n: Node, body: Node3D) -> AABB:
	if n is CSGShape3D and (n as CSGShape3D).operation == CSGShape3D.OPERATION_SUBTRACTION:
		return AABB()
	var out := AABB()
	var started := false
	for c in n.get_children():
		var sub := _bounds(c, body)
		if sub.size != Vector3.ZERO:
			out = sub if not started else out.merge(sub)
			started = true
	if n is VisualInstance3D:
		var vi := n as VisualInstance3D
		var local := body.global_transform.affine_inverse() * vi.global_transform
		var a := local * vi.get_aabb()
		out = a if not started else out.merge(a)
	return out


## Transform relative to `body` without needing the node in a tree.
func _rel(n: Node3D, body: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != body:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
