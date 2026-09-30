extends SceneTree

# ─────────────────────────────────────────────
# FACTION LIVERY — is every metal panel actually painted?
#
# FactionLivery paints a listed set of pieces and recurses into their children.
# The failure it cannot report is a piece nobody listed: that mesh keeps the
# stock material and the robot fights in enemy amber on the player's side. It
# has happened twice — the quadcopter bomber flew untinted in its model's own
# colours (see the note in faction_livery.gd), and the Walker shipped with its
# shins, feet, hip caps, turret ring, antenna and mantlet unpainted.
#
# THE RULE THIS PINS: a mesh whose own material IS the livery's base material
# is a piece of the robot's bodywork and must end up painted. A mesh with some
# other material of its own — an eye, a lamp, a glowing marker — is a
# deliberate exception and is left alone. So the test never has to be told
# which pieces to skip; the model says so itself.
#
# Nothing is added to the tree: the livery is collected and applied by hand, so
# no robot ever runs its _ready without a level under it.
# ─────────────────────────────────────────────

const _Livery := preload("res://faction_livery.gd")
const ROBOTS := "res://Character/characters/ai"

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s  %s" % [label, detail])
		_fails += 1


func _livery_of(root: Node) -> Node:
	for child in root.get_children():
		var s: Variant = child.get_script()
		if s != null and str(s.resource_path).ends_with("faction_livery.gd"):
			return child
	return null


# The material the model itself puts on this surface, override first.
# ASK THE RESOURCE, NEVER THE RENDERING SERVER. Headless runs on the dummy
# renderer, where get_surface_count() on an imported mesh errors out with a null
# RID and get_surface_override_material() walks off the end of an empty array.
func _own_material(g: GeometryInstance3D) -> Material:
	if g is CSGShape3D:
		return g.get("material") as Material   # CSGCombiner3D has none; primitives do
	var mi := g as MeshInstance3D
	if mi == null or mi.mesh == null:
		return null
	if mi.get_surface_override_material_count() > 0:
		var over := mi.get_surface_override_material(0)
		if over != null:
			return over
	if mi.mesh is PrimitiveMesh:
		return (mi.mesh as PrimitiveMesh).material
	if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_surface_count() > 0:
		return (mi.mesh as ArrayMesh).surface_get_material(0)
	return null


func _meshes(node: Node, out: Array) -> void:
	if node is CSGShape3D or node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_meshes(child, out)


func _scenes() -> Array[String]:
	var found: Array[String] = []
	var d := DirAccess.open(ROBOTS)
	if d == null:
		return found
	for file in d.get_files():
		if not file.ends_with(".tscn"):
			continue
		var path := "%s/%s" % [ROBOTS, file]
		if FileAccess.get_file_as_string(path).contains("faction_livery.gd"):
			found.append(path)
	found.sort()
	return found


func _init() -> void:
	Settings.path = "user://settings_livery_test.json"
	await process_frame
	var scenes := _scenes()
	_check("there are liveried robots to check", scenes.size() >= 10, str(scenes.size()))

	var want: Color = _Livery.COLORS[Enums.Factions.PLAYER]
	for path in scenes:
		var scene: PackedScene = load(path)
		var robot: Node = scene.instantiate()
		var livery := _livery_of(robot)
		var label := path.get_file()
		if livery == null:
			_check("%s carries a FactionLivery" % label, false, path)
			robot.free()
			continue
		# By hand, in this order, because the robot is never added to the tree:
		# _ready is what normally does this, and running a robot's _ready without
		# a level under it is a different kind of trouble.
		livery._collect()
		livery.apply(Enums.Factions.PLAYER)

		var all: Array = []
		_meshes(robot, all)
		var base: Material = livery.base_material
		var bare: Array[String] = []
		var painted := 0
		for g in all:
			var mat := g.material_override as ShaderMaterial
			if mat != null and (mat.get_shader_parameter("faction_color") as Color).is_equal_approx(want):
				painted += 1
			elif base != null and _own_material(g) == base:
				# Bodywork: the model put the shared metal on this surface, so
				# the livery owes it a coat. A mesh wearing a material of its
				# own — an eye, a lamp, a marker — is left alone on purpose, and
				# a robot modelled in a GLB wears its own materials throughout,
				# which is why this asks what the model says rather than holding
				# a list of exceptions.
				bare.append(str(robot.get_path_to(g)))
		_check("%s paints every panel it is built from" % label, bare.is_empty(),
			"unpainted: %s" % str(bare))
		_check("...and the livery reached something at all", painted > 0, label)
		robot.free()

	if FileAccess.file_exists("user://settings_livery_test.json"):
		DirAccess.remove_absolute("user://settings_livery_test.json")
	print("")
	print("ALL LIVERY CHECKS PASS" if _fails == 0 else "%d LIVERY CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
