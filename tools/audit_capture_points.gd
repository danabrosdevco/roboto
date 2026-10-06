extends SceneTree

# ─────────────────────────────────────────────
# CAN EVERY CAPTURE OBJECTIVE ACTUALLY BE CAPTURED?
#
# Some are compute_core_point instances, which bring their own core, their own
# terminal and a reach volume sized to the core. Others were hand-built before
# that existed: a bare InteractObjective with a template_interactible dropped
# under it. The template ships with a CollisionShape3D AND NO SHAPE ON IT —
# shape is left for the level to fill in — so a hand-built objective whose level
# forgot is an interactible the player's ray can never hit. There is nothing to
# walk up to and nothing on screen to say so.
#
# Hillfort reads exactly that way: the relay is there, it has a console prop,
# and it cannot be taken.
#
# So this walks every objective in every level a mission plays, and says which
# ones are real.
#
#   godot --headless --path . --script res://tools/audit_capture_points.gd
# ─────────────────────────────────────────────

const CAPTURE_SCENES := [
	"res://Env/world_objects/capture_point.tscn",
	"res://Env/world_objects/compute_core_point_small.tscn",
	"res://Env/world_objects/compute_core_point.tscn",
	"res://Env/world_objects/compute_core_point_large.tscn",
]
const INTERACT_SCRIPT := "interact_objective.gd"


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world := load("res://Env/world.tscn") as PackedScene
	var missions: Array = _missions(world.get_state())

	# Which levels are actually played, and by whom.
	var played := {}
	for m in missions:
		if m == null or m.level_scene == null:
			continue
		var p: String = m.level_scene.resource_path
		if not played.has(p):
			played[p] = []
		played[p].append(str(m.id))

	print("")
	print("══ CAPTURE OBJECTIVES IN EVERY LEVEL A MISSION PLAYS ═════")
	var broken := 0
	var hand_built := 0
	var paths: Array = played.keys()
	paths.sort()
	for path in paths:
		var rows := _capture_rows(path)
		if rows.is_empty():
			continue
		print("")
		print("  %s   (%s)" % [path.get_file(), " ".join(played[path])])
		for r in rows:
			var kind: String = r["kind"]
			var note := ""
			if kind == "hand-built":
				hand_built += 1
				if not r["has_shape"]:
					broken += 1
					note = "  <<< NO REACH VOLUME — CANNOT BE CAPTURED"
				else:
					note = "  (reach %s)" % r["shape"]
			print("     %-26s %-14s%s" % [r["id"], kind, note])

	print("")
	print("  %d hand-built capture objective(s), %d of them with no reach volume at all." % [
		hand_built, broken])
	print("  A compute_core_point brings its own; a hand-built one only has what its level gave it.")
	quit(0)


## Every InteractObjective in a level, and whether it can actually be used.
## IT FOLLOWS INSTANCED SUB-SCENES, scene by scene rather than node by node.
##
## Georgetown, Polaris and Causeway keep their capture points in
## maps/gameplay/<name>_ops.tscn and only INSTANCE it, because their level
## files are rewritten from a template by the terrain builders. An instanced
## scene's nodes are not in the parent's SceneState, so all three returned an
## empty row list — and the caller's `rows.is_empty(): continue` meant the
## three levels disappeared from this report with no line printed at all.
##
## Per scene and not per node, because _shape_under() matches node paths
## WITHIN one state and cannot cross an instance boundary.
##
## Only into res://maps and never into an _art scene: a level's art is hundreds
## of instances and holds no objectives.
const MAX_SUB_DEPTH := 2


func _capture_rows(path: String, depth: int = 0, seen: Dictionary = {}) -> Array:
	var out: Array = []
	if seen.has(path):
		return out
	seen[path] = true
	var packed := load(path) as PackedScene
	if packed == null:
		return out
	var st := packed.get_state()
	if depth < MAX_SUB_DEPTH:
		for i in st.get_node_count():
			var sub := st.get_node_instance(i)
			if sub == null:
				continue
			var sub_path := str(sub.resource_path)
			if not sub_path.begins_with("res://maps/") or sub_path.get_basename().ends_with("_art"):
				continue
			out.append_array(_capture_rows(sub_path, depth + 1, seen))
	for i in st.get_node_count():
		var id: StringName = &""
		var script_file := ""
		for j in st.get_node_property_count(i):
			var prop := String(st.get_node_property_name(i, j))
			var v: Variant = st.get_node_property_value(i, j)
			if prop == "id":
				id = StringName(str(v))
			elif prop == "script" and v != null:
				script_file = str(v.resource_path).get_file()
		if id == &"":
			continue

		var inst := st.get_node_instance(i)
		if inst != null and CAPTURE_SCENES.has(inst.resource_path):
			out.append({"id": String(id), "kind": _core_name(inst.resource_path),
				"has_shape": true, "shape": ""})
			continue
		if script_file != INTERACT_SCRIPT:
			continue
		# Hand-built. Find the shape on its Interactible child, if it has one.
		var found := _shape_under(st, i)
		out.append({"id": String(id), "kind": "hand-built",
			"has_shape": found != "", "shape": found})
	return out


func _core_name(p: String) -> String:
	if p.ends_with("capture_point.tscn"):
		return "old console"
	if p.ends_with("_small.tscn"):
		return "core (small)"
	if p.ends_with("_large.tscn"):
		return "core (large)"
	return "core"


## The CollisionShape3D shape under node `idx`, as text. Empty when the level
## never gave it one — which is the failure this audit exists for.
func _shape_under(st: SceneState, idx: int) -> String:
	var want := String(st.get_node_path(idx))
	for i in st.get_node_count():
		var p := String(st.get_node_path(i))
		if not p.begins_with(want) or p == want:
			continue
		for j in st.get_node_property_count(i):
			if String(st.get_node_property_name(i, j)) != "shape":
				continue
			var v: Variant = st.get_node_property_value(i, j)
			if v == null:
				continue
			if v is BoxShape3D:
				return "box %s" % str((v as BoxShape3D).size)
			if v is SphereShape3D:
				return "sphere r%.1f" % (v as SphereShape3D).radius
			if v is CylinderShape3D:
				return "cylinder r%.1f" % (v as CylinderShape3D).radius
			return v.get_class()
	return ""


func _missions(st: SceneState) -> Array:
	for i in st.get_node_count():
		if st.get_node_name(i) != "CampaignManager":
			continue
		for j in st.get_node_property_count(i):
			if String(st.get_node_property_name(i, j)) == "missions":
				return st.get_node_property_value(i, j)
		return []
	return []
