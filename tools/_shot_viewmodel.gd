extends SceneTree

# Photographs what the player actually sees with a given item in hand. The only
# way to judge a viewmodel pose: the model's own shot tool photographs it in
# isolation, which says nothing about where it sits in the view.
#
# MUST RUN HEADFUL. --headless has no renderer.
#   ... --audio-driver Dummy --path . --script tools/_shot_viewmodel.gd -- <slot>

func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	if DisplayServer.get_name() == "headless":
		printerr("_shot_viewmodel: needs a window. Drop --headless.")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var slot: int = int(args[0]) if args.size() > 0 else 1

	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 120:
		await physics_frame

	var player: Node3D = get_first_node_in_group("player") as Node3D
	if player == null or player.get("loadout") == null:
		# The player node is called `test_character` in world.tscn; the group
		# lookup is not always what answers first.
		player = _find(root, "test_character") as Node3D
	var loadout = player.get("loadout") if player != null else null
	if loadout == null:
		printerr("no loadout"); quit(1); return
	loadout.equip_slot(slot)
	for _i in 60:
		await physics_frame
		# Drive the pose lerp the way the player's own tick does, so the shot is
		# of the settled rest pose and not of the draw animation.
		if loadout.current != null:
			loadout.current.update_view(1.0 / 60.0, 0.0, false, false)
	# Optionally hold the trigger, so a tool whose whole point is what happens
	# DURING a hold can be photographed doing it.
	if args.size() > 1 and str(args[1]) == "hold":
		if held_has(loadout.current, "primary_pressed"):
			loadout.current.primary_pressed()
			for _i in 45:
				loadout.current.primary_held(1.0 / 60.0)
				await physics_frame
				loadout.current.update_view(1.0 / 60.0, 0.0, false, false)
			print("  charge %.2f  mark %s" % [float(loadout.current.get("charge")),
				str(loadout.current.get("mark"))])
	var held = loadout.current
	print("holding: %s" % (held.display_name if held != null else "<nothing>"))
	if held != null and held.viewmodel != null:
		print("  viewmodel pos %s  rot %s  visible %s" % [
			str(held.viewmodel.position), str(held.viewmodel.rotation_degrees),
			str(held.viewmodel.visible)])
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png("res://docs/marketing/wip/viewmodel_slot%d.png" % slot)
	print("  wrote viewmodel_slot%d.png" % slot)
	quit(0)


func _find(node: Node, named: String) -> Node:
	if node.name == named:
		return node
	for kid in node.get_children():
		var hit := _find(kid, named)
		if hit != null:
			return hit
	return null


func held_has(n, m: String) -> bool:
	return n != null and is_instance_valid(n) and n.has_method(m)
