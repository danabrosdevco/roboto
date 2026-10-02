extends SceneTree

# ─────────────────────────────────────────────
# WHAT FOLDING THE OPTIONAL REWARDS INTO THE MISSION WOULD COST.
#
# Nests and other optional objectives each pay their own resources on top of the
# mission. Three Rivers alone has four of them worth 210, which is a third of
# the operation's own 650 — so the headline number on the briefing has not been
# the number you actually come home with for a long time.
#
# This REPORTS. It reads every mission, works out which optional objectives it
# activates, and prints what the mission would pay if those were folded in and
# rounded. Nothing is written: the arithmetic wants looking at before five maps
# and twenty-odd missions are edited.
#
# PER MISSION, not per map. Six missions share the valley and seven share the
# basin; folding a map's optional total into each of them would pay the same
# hives out six times over. Only what a mission actually lists in its
# active_objectives counts.
#
#   godot --headless --path . --script res://tools/fold_optional_rewards.gd -- [round_to]
# ─────────────────────────────────────────────

const OBJECTIVE_SCRIPTS := [
	"mission_objective.gd", "reach_objective.gd",
	"interact_objective.gd", "eliminate_objective.gd",
]
const NEST_SCRIPT := "eliminate_objective.gd"


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var args := OS.get_cmdline_user_args()
	var round_to: int = int(args[0]) if args.size() > 0 else 25

	var world := load("res://Env/world.tscn") as PackedScene
	var missions: Array = _missions(world.get_state())

	print("")
	print("FOLDING OPTIONAL REWARDS INTO THE MISSION  (rounded to %d)" % round_to)
	print("")
	print("  %-30s %7s %7s %7s   %s" % ["mission", "now", "+opt", "becomes", "what it absorbs"])
	var total_moved := 0
	for m in missions:
		if m == null or m.level_scene == null:
			continue
		var objectives := _objectives(m.level_scene)
		var fold := 0
		var parts := PackedStringArray()
		for want in m.active_objectives:
			if not objectives.has(want):
				continue
			var o: Dictionary = objectives[want]
			if not o["optional"]:
				continue
			fold += int(o["reward"])
			parts.append("%s %d%s" % [String(want), int(o["reward"]), "*" if o["nest"] else ""])
		if fold == 0:
			continue
		var now := int(m.reward_resources)
		var raw := now + fold
		var rounded := int(round(float(raw) / float(round_to))) * round_to
		total_moved += fold
		print("  %-30s %7d %7d %7d   %s" % [str(m.id), now, fold, rounded, " ".join(parts)])

	print("")
	print("  %d resources in total move off objectives and onto missions." % total_moved)
	print("  * = a nest, which also stops being an objective at all.")

	# And what each MAP would have zeroed, which is the other half of the edit.
	print("")
	print("OPTIONAL OBJECTIVES WHOSE OWN REWARD WOULD GO TO ZERO")
	for path in _levels():
		var objectives := _objectives(load(path) as PackedScene)
		var rows := PackedStringArray()
		for id in objectives:
			var o: Dictionary = objectives[id]
			if o["optional"] and int(o["reward"]) > 0:
				rows.append("%s %d%s" % [String(id), int(o["reward"]), "*" if o["nest"] else ""])
		if not rows.is_empty():
			print("  %-32s %s" % [path.get_file(), " ".join(rows)])
	quit(0)


func _levels() -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://maps")
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".tscn") and not f.get_basename().ends_with("_art"):
			out.append("res://maps/%s" % f)
	out.sort()
	return out


## id -> { optional, reward, nest } for every objective in a level.
func _objectives(packed: PackedScene) -> Dictionary:
	var out := {}
	if packed == null:
		return out
	var st := packed.get_state()
	for i in st.get_node_count():
		var id: StringName = &""
		var optional := false
		var reward := 0
		var script_file := ""
		for j in st.get_node_property_count(i):
			var prop := String(st.get_node_property_name(i, j))
			var v: Variant = st.get_node_property_value(i, j)
			if prop == "id":
				id = StringName(str(v))
			elif prop == "optional":
				optional = bool(v)
			elif prop == "reward_resources":
				reward = int(v)
			elif prop == "script" and v != null:
				script_file = str(v.resource_path).get_file()
		if id == &"":
			continue
		# An instanced objective keeps its script on the instanced scene's root.
		if script_file == "":
			var inst := st.get_node_instance(i)
			if inst != null and inst.get_state().get_node_count() > 0:
				var ist := inst.get_state()
				for j in ist.get_node_property_count(0):
					if String(ist.get_node_property_name(0, j)) == "script":
						var sv: Variant = ist.get_node_property_value(0, j)
						if sv != null:
							script_file = str(sv.resource_path).get_file()
		if not OBJECTIVE_SCRIPTS.has(script_file):
			continue
		out[id] = {"optional": optional, "reward": reward,
			"nest": optional and script_file == NEST_SCRIPT}
	return out


func _missions(st: SceneState) -> Array:
	for i in st.get_node_count():
		if st.get_node_name(i) != "CampaignManager":
			continue
		for j in st.get_node_property_count(i):
			if String(st.get_node_property_name(i, j)) == "missions":
				return st.get_node_property_value(i, j)
		return []
	return []
