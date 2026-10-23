extends SceneTree

# ─────────────────────────────────────────────
# DOES ENTERING THE ARENA TICK "CHOOSE AN OPERATION"?
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_arena_induction.gd
#
# Reported from play: it does not. On paper it should — the induction's
# `induct_pick_op` fires on Trigger.SELECT_MISSION, and SimTerminal._on_training
# calls Campaign.select_mission, which emits `mission_selected`. So either the
# report is about something subtler or there is a gap in between, and guessing
# which would be guessing.
#
# This builds the induction the way the depot does, fires the arena's own code
# path, and reports which objectives are complete after. It asserts nothing and
# fixes nothing: it answers the question so the fix can be aimed.
# ─────────────────────────────────────────────

func _init() -> void:
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame

	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = true
	master.show_mission_briefing = false
	var cm: CampaignManager = master.find_child("CampaignManager", true, false)
	cm.autosave = false
	root.add_child(master)
	for _i in 90:
		await physics_frame
	cm.reset_campaign()

	var ind = cm.get("_induction") if "_induction" in cm else null
	print("induction present: %s" % str(ind != null))
	if ind == null:
		print("  no induction on the campaign — it is built when the depot loads,")
		print("  so this probe needs the depot rather than a bare boot.")
		print("  Looking for induction objectives in the tree instead:")

	var found := _objectives()
	print("objectives in the tree: %d" % found.size())
	for o in found:
		print("   %-24s complete=%s active=%s" % [o.id, str(o.completed),
			str(o.active) if "active" in o else "?"])

	var pick = _by_id(found, &"induct_pick_op")
	if pick == null:
		print("")
		print("VERDICT: induct_pick_op is NOT IN THE TREE at this point.")
		print("  It is built with the rest of the induction when the depot level")
		print("  loads. If the player reaches the arena without that having")
		print("  happened, there is nothing listening and no signal can tick it.")
		quit(0)
		return

	print("")
	print("before: induct_pick_op complete = %s" % str(pick.completed))
	# THE ARENA'S OWN PATH, not a hand-rolled one: this is exactly what
	# SimTerminal._on_training does when you press ENTER on an exercise.
	cm.select_mission(&"arena_3_firing_line")
	for _i in 10:
		await physics_frame
	print("after select_mission(arena_3_firing_line): complete = %s" % str(pick.completed))
	print("")
	print("VERDICT: %s" % ("the signal DOES tick it — the gap is elsewhere"
		if pick.completed else "the signal does NOT tick it"))
	quit(0)


func _objectives() -> Array:
	var out: Array = []
	_walk(root, out)
	return out


func _walk(n: Node, out: Array) -> void:
	var s = n.get_script()
	if s != null and String(s.resource_path).ends_with("induction_objective.gd"):
		out.append(n)
	for c in n.get_children():
		_walk(c, out)


func _by_id(list: Array, id: StringName):
	for o in list:
		if o.id == id:
			return o
	return null
