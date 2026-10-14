extends SceneTree
# Does the DEBUG tab's COMPLETE OPERATION actually clear an operation?
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_debug_clear.gd

func _find(n: Node, cls: String) -> Node:
	var s: Script = n.get_script() as Script
	if s != null and s.get_global_name() == StringName(cls):
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
	var cm: Node = world.get_node("CampaignManager")
	cm.autosave = false
	root.add_child(world)
	for _i in 120:
		await physics_frame

	print("  before: in_mission=%s" % str(cm.in_mission))
	print("  not-on-an-operation says: %s" % cm.debug_complete_mission())

	# Deploy into the first mission that has a level.
	var mission = null
	for m in cm.missions:
		if m != null and m.level_scene != null:
			mission = m
			break
	if mission == null:
		print("  NO MISSION WITH A LEVEL")
		quit(1)
		return
	cm.state.selected_mission_id = mission.id
	var w := _find(root, "World")
	w.load_next_level(mission.level_scene, true)
	for _i in 240:
		await physics_frame
	print("  deployed to '%s': in_mission=%s" % [str(mission.id), str(cm.in_mission)])

	var before := []
	if cm.objectives != null:
		for o in cm.objectives.objectives():
			before.append("%s=%s" % [str(o.id), "done" if o.completed else "open"])
	print("  objectives before: %s" % ", ".join(before))

	var said: String = cm.debug_complete_mission()
	print("  it said: %s" % said)
	for _i in 180:
		await physics_frame

	var after := []
	if cm.objectives != null:
		for o in cm.objectives.objectives():
			if o != null and is_instance_valid(o):
				after.append("%s=%s" % [str(o.id), "done" if o.completed else "open"])
	print("  objectives after:  %s" % ", ".join(after))
	print("  after: in_mission=%s" % str(cm.in_mission))
	quit(0)
