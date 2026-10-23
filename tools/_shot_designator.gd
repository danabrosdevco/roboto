extends SceneTree

# Photographs the designator from a 3/4 view and from roughly where the player's
# eye sits, so the screen can be judged for READABILITY rather than for shape.
#
# IT DRAWS THE REAL READOUT NOW. This used to build a mock-up of the display in
# this file, which was fine while the screen was a proposal and is actively
# misleading now that designator_screen.gd exists — a shot of a mock-up is a
# shot of something nobody will ever hold. So it instantiates the actual tool
# scene, hands its screen a set of modes, and photographs that.
#
# The modes are faked because there is no mission here: the live tool reads them
# off the squad's real equipment slots through the commander. Everything DOWNSTREAM
# of that — the layout, the sizes, the colours, the fill bar — is the shipping code.

const TOOL := "res://Character/weapon/designator_hud_weapon.tscn"
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"

const SHOTS := [
	["three_quarter", Vector3(0.52, 0.34, -0.46), Vector3(0, 0.02, 0)],
	["first_person", Vector3(0.14, 0.3, -0.62), Vector3(0, 0.0, 0.05)],
	["side", Vector3(0.7, 0.05, 0.0), Vector3(0, 0.0, 0.0)],
]


# MUST RUN HEADFUL. --headless has no renderer, so get_image() comes back blank
# and the run hangs waiting on a frame_post_draw that never arrives:
#   "D:/Godot Games/Godot_v4.3-stable_win64.exe/Godot_v4.3-stable_win64_console.exe" \
#     --audio-driver Dummy --path . --script tools/_shot_designator.gd
func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	if DisplayServer.get_name() == "headless":
		printerr("_shot_designator: this photographs the tool, so it needs a window. Drop --headless.")
		quit(1)
		return

	var holder := Node3D.new()
	root.add_child(holder)
	# THE ICONS COME OUT OF THE CATALOGUE, and hud_glyphs finds the catalogue by
	# walking the "campaign" group — which exists in a mission and not here. A
	# stand-in in that group is the whole of what the screen needs, and it keeps
	# the shot honest: the real icon path is exercised rather than bypassed.
	var stub := _CampaignStub.new()
	stub.catalogue = load(CATALOGUE)
	stub.add_to_group("campaign")
	root.add_child(stub)

	var tool_node = load(TOOL).instantiate()
	holder.add_child(tool_node)
	# The loadout normally does this. Without a player there is no loadout, so
	# the one wiring step the screen depends on is called directly.
	tool_node._wire_screen()
	tool_node._modes = [
		{"item_id": &"@advance", "label": "Advance", "holders": 4, "wants_point": true, "deliberate": false},
		{"item_id": &"@follow", "label": "Follow Me", "holders": 4, "wants_point": false, "deliberate": false},
		{"item_id": &"smoke", "label": "Smoke Canister", "holders": 3, "wants_point": true, "deliberate": true},
		{"item_id": &"mine_cluster", "label": "Cluster Mine", "holders": 2, "wants_point": true, "deliberate": true},
		{"item_id": &"drone_pack", "label": "Drone Carrier Pack", "holders": 1, "wants_point": false, "deliberate": true},
	]
	# ON SMOKE, the commonest case. Switch _mode to 2 for "DRONE CARRIER PACK",
	# which is the longest name the dial has to wrap and the only confirm mode.
	#
	tool_node._mode = 0
	# Mid-hold, so the fill bar is in the picture — it is a third of the reason
	# the tool is held rather than bound to a key.
	tool_node.charge = 0.62

	var key := DirectionalLight3D.new()
	key.light_energy = 1.5
	key.rotation_degrees = Vector3(-38, 40, 0)
	holder.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.45
	fill.light_color = Color(0.7, 0.85, 0.95)
	fill.rotation_degrees = Vector3(-10, -130, 0)
	holder.add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.045, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.38, 0.34)
	e.ambient_light_energy = 0.5
	# GLOW, but only on the screen: the threshold sits above everything else in
	# the shot, so the readout blooms and the dark body does not lift.
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_bloom = 0.1
	e.glow_hdr_threshold = 0.7
	env.environment = e
	holder.add_child(env)

	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.current = true
	cam.fov = 42.0
	for s in SHOTS:
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP)
		# Generous: the SubViewport has to render its own frame before the 3D
		# pass can sample it, so one frame is a blank screen every time.
		for _i in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		img.save_png("res://docs/marketing/wip/designator_%s.png" % s[0])
		print("  %s" % s[0])
	quit(0)


## Stands in for the Campaign node so HUDGlyphs can find a catalogue. A plain
## Node with the one property that lookup reads.
class _CampaignStub extends Node:
	var catalogue: ItemCatalogue = null
