extends SceneTree
# REPORTS: what every authored objective's label() actually reads as on the HUD.
#
# Backlog K10 — "HUD labels double their verb". The verb is composed in
# MissionObjective.label(), the name is authored in a level, and NOTHING in
# either file shows the sentence they make together. So the bug is invisible
# from both ends and had to be read off the screen to be found.
#
# NO INSTANTIATION. A level scene builds terrain, bakes nothing and costs
# seconds; label() depends only on the node's class, its display_name and
# is_extraction, all three of which SceneState can read out of the packed
# scene. So this walks the .tscn as data, including one level down into any
# instanced objective prefab, and composes the label with the REAL label().

const OBJ_CLASSES := {
	"EliminateObjective": "res://Campaign/eliminate_objective.gd",
	"InteractObjective": "res://Campaign/interact_objective.gd",
	"ReachObjective": "res://Campaign/reach_objective.gd",
	"MissionObjective": "res://Campaign/mission_objective.gd",
}

var _rows: Array = []


func _init() -> void:
	var files: Array[String] = []
	_collect("res://maps", files)
	_collect("res://Env", files)
	files.sort()
	for f in files:
		_scan(f)

	print("")
	print("OBJECTIVE LABELS — %d authored objectives across %d scenes" % [_rows.size(), files.size()])
	print("")
	var bad := 0
	for r in _rows:
		var flag: String = _fault(r["verb"], r["name"], r["label"])
		if flag != "":
			bad += 1
		print("%-44s %-22s %-28s %s%s" % [
			r["scene"], r["cls"], '"' + r["name"] + '"', r["label"],
			"" if flag == "" else "   <-- " + flag])
	print("")
	print("%d of %d read wrong." % [bad, _rows.size()])
	quit(0)


# The two ways a composed label breaks.
#
# READ OFF THE COMPOSED LABEL, not rebuilt from the rule. A check that
# reimplements label() passes exactly when it shares label()'s bug, and the
# first version of this function did: it tested the authored name against the
# verb and went on reporting DOUBLE ARTICLE after the join had been fixed.
func _fault(verb: String, name_text: String, label_text: String) -> String:
	if verb == "":
		return ""
	var low := " " + label_text.to_lower() + " "
	for article in ["the", "a", "an"]:
		if low.contains(" %s %s " % [article, article]):
			return "DOUBLE ARTICLE"
	# The authored name is itself an instruction AND the verb got prefixed to it
	# anyway: "Eliminate Take The First Line". A label that came back equal to
	# the name had no verb applied, so there is nothing doubled — that is the
	# shape of the extraction fix, and the check has to see the difference or it
	# reports the fix as the bug.
	if not label_text.to_lower().begins_with(verb.to_lower() + " "):
		return ""
	# A closed list of the words this project actually authors — it reports and
	# never rewrites, so a word it has not seen costs a missed row and nothing else.
	var first := name_text.to_lower().split(" ")[0]
	if first in ["take", "through", "silence", "clear", "get", "off", "out",
			"round", "down", "all", "hold", "destroy", "reach", "capture",
			"eliminate", "extract", "secure", "push", "move"]:
		return "DOUBLE VERB"
	return ""


func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var p := dir_path + "/" + n
		if d.current_is_dir():
			if not n.begins_with("."):
				_collect(p, out)
		elif n.ends_with(".tscn"):
			out.append(p)
		n = d.get_next()
	d.list_dir_end()


func _scan(path: String) -> void:
	var packed: PackedScene = load(path)
	if packed == null:
		return
	var st := packed.get_state()
	for i in st.get_node_count():
		var props := {}
		for j in st.get_node_property_count(i):
			props[String(st.get_node_property_name(i, j))] = st.get_node_property_value(i, j)
		if not props.has("display_name"):
			continue
		var cls := _class_of(st, i, props)
		if cls == "":
			continue
		var name_val := String(props["display_name"])
		if name_val == "":
			continue
		var extraction: bool = bool(props.get("is_extraction", _inherited_extraction(st, i)))
		var obj: Object = load(OBJ_CLASSES[cls]).new()
		obj.set("display_name", name_val)
		obj.set("is_extraction", extraction)
		_rows.append({
			"scene": path.replace("res://", ""),
			"cls": cls + ("(extract)" if extraction and cls == "ReachObjective" else ""),
			"name": name_val,
			"verb": String(obj.call("verb")),
			"label": String(obj.call("label")),
		})
		if obj is Node:
			(obj as Node).free()
		else:
			obj.unreference()


# A node carries its class either as an attached script or as the script of the
# prefab it instances. Both routes are authored in this project, so both are read.
func _class_of(st: SceneState, i: int, props: Dictionary) -> String:
	var s: Script = props.get("script", null) as Script
	if s != null:
		var g := String(s.get_global_name())
		return g if OBJ_CLASSES.has(g) else ""
	var inst: PackedScene = st.get_node_instance(i)
	if inst == null:
		return ""
	var ist := inst.get_state()
	for k in ist.get_node_count():
		for j in ist.get_node_property_count(k):
			if String(ist.get_node_property_name(k, j)) == "script":
				var s2: Script = ist.get_node_property_value(k, j) as Script
				if s2 != null:
					var g2 := String(s2.get_global_name())
					if OBJ_CLASSES.has(g2):
						return g2
		break  # the prefab's own root only
	return ""


# An instanced objective may set is_extraction in the prefab and not in the level.
func _inherited_extraction(st: SceneState, i: int) -> bool:
	var inst: PackedScene = st.get_node_instance(i)
	if inst == null:
		return false
	var ist := inst.get_state()
	for j in ist.get_node_property_count(0):
		if String(ist.get_node_property_name(0, j)) == "is_extraction":
			return bool(ist.get_node_property_value(0, j))
	return false
