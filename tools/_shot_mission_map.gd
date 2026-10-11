extends SceneTree

# The in-mission map, with some objectives finished, so the "taken position"
# mark can be judged against the live ones. MUST RUN HEADFUL.

const MISSION := "res://Campaign/missions/mission_polaris_1_siege.tres"

func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	if DisplayServer.get_name() == "headless":
		printerr("_shot_mission_map: needs a window. Drop --headless.")
		quit(1)
		return
	var m: MissionDefinition = load(MISSION)
	var ids: Array = m.active_objectives
	var src := GDScript.new()
	src.source_code = "extends Node
var id: StringName = &\"\"
var completed: bool = true
"
	src.reload()
	for n in range(0, mini(6, ids.size())):
		var stub := Node.new()
		stub.set_script(src)
		stub.set("id", ids[n])
		stub.name = "Done_%d" % n
		root.add_child(stub)
	print("marked done: %s" % str(ids.slice(0, mini(6, ids.size()))))
	print("objectives on this mission: %s" % str(ids))
	var brief := load("res://Character/hud/mission_briefing.gd").new() as Control
	root.add_child(brief)
	brief.open_map(m)
	for _i in 30:
		await process_frame
	# Mark the first few done by standing in stub nodes carrying their ids:
	# _completed_ids() scans the tree for anything with `id` and `completed`.
	for _i in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png("res://docs/marketing/wip/mission_map.png")
	print("  wrote mission_map.png")
	quit(0)
