extends SceneTree

# ─────────────────────────────────────────────
# SHOTS OF THE QAMAREEN COPY. Eye height where a robot would stand, plus two
# obliques for the layout.
#
#   RENDER_OUT=<dir> godot --path . --script res://tools/probe_shots_mutaha_wip.gd
#
# NOT headless: the dummy renderer returns blank images.
#
# The first frame of a fresh run comes back blank while the renderer warms up,
# so every shot is taken twice and the second one kept.
# ─────────────────────────────────────────────

const LEVEL := "res://maps/mutaha_wip_level.tscn"
const EYE := 1.7

const SHOTS: Array = [
	# name, camera, look at, fov
	["01_layout_south", Vector3(-40.0, 340.0, 620.0), Vector3(-130.0, 0.0, 150.0), 62.0],
	["02_layout_quarter", Vector3(-120.0, 220.0, 420.0), Vector3(-280.0, 0.0, 130.0), 58.0],
	["03_bridge_out_plain", Vector3(26.0, EYE, 210.0), Vector3(-30.0, 2.0, 150.0), 70.0],
	["04_bridge_out_close", Vector3(14.0, EYE, 192.0), Vector3(-6.0, 0.0, 154.0), 65.0],
	["05_bridge_out_island", Vector3(-22.0, EYE, 142.0), Vector3(14.0, 0.0, 190.0), 70.0],
	["06_island_wall_far", Vector3(30.0, 6.0, 206.0), Vector3(-60.0, 1.0, 192.0), 62.0],
	["07_island_wall_close", Vector3(-14.0, EYE, 196.0), Vector3(-48.0, 1.5, 214.0), 70.0],
	["08_island_wall_inside", Vector3(-58.0, EYE, 188.0), Vector3(-26.0, 2.0, 200.0), 70.0],
	["09_west_bridgehead_deck", Vector3(-112.0, 5.0, -31.0), Vector3(-190.0, 1.0, -56.0), 68.0],
	["10_west_bridgehead_above", Vector3(-214.0, 34.0, -18.0), Vector3(-152.0, 0.0, -52.0), 64.0],
	["11_west_bridgehead_arrive", Vector3(-136.0, 4.2, -42.0), Vector3(-205.0, 1.0, -56.0), 72.0],
	["11b_west_bridgehead_plaza", Vector3(-202.0, EYE, -62.0), Vector3(-148.0, 2.0, -46.0), 72.0],
	["12_new_crossing", Vector3(-62.0, 3.0, 316.0), Vector3(-170.0, 1.0, 314.0), 62.0],
	["13_new_crossing_gate", Vector3(-150.0, EYE, 312.0), Vector3(-80.0, 1.5, 318.0), 70.0],
	["14_quarter_from_south", Vector3(-186.0, 4.0, 262.0), Vector3(-270.0, 2.0, 170.0), 65.0],
	["15_quarter_street", Vector3(-208.5, EYE, 200.0), Vector3(-208.5, 1.4, 110.0), 70.0],
	["16_quarter_crossroads", Vector3(-249.5, EYE, 161.5), Vector3(-180.0, 1.4, 150.0), 70.0],
	["17_quay_at_island", Vector3(-160.0, EYE, 176.0), Vector3(-60.0, 3.0, 176.0), 70.0],
	["18_quarter_edge_north", Vector3(-300.0, EYE, 96.0), Vector3(-260.0, 1.5, 180.0), 70.0],
	["19_island_tip_above", Vector3(-46.0, 96.0, 268.0), Vector3(-56.0, 0.0, 180.0), 64.0],
	["20_map_from_above", Vector3(0.0, 900.0, 40.0), Vector3(0.0, 0.0, 0.0), 62.0],
	["21_south_from_above", Vector3(-90.0, 400.0, 210.0), Vector3(-90.0, 0.0, 200.0), 66.0],
	# The six estate blocks standing in the new quarter: what a five- to
	# eight-storey block does to a street the small buildings cannot.
	["22_estates_above", Vector3(-150.0, 170.0, 310.0), Vector3(-300.0, 8.0, 150.0), 60.0],
	["23_estates_street", Vector3(-286.0, EYE, 128.5), Vector3(-372.0, 5.0, 128.5), 70.0],
	["24_estates_from_approach", Vector3(-196.0, 3.0, 286.0), Vector3(-320.0, 12.0, 150.0), 66.0],
	["25_frame_shell_inside", Vector3(-249.5, EYE, 196.0), Vector3(-249.5, 6.0, 130.0), 72.0],
	["26_tower_and_gallery", Vector3(-214.0, EYE, 100.0), Vector3(-188.0, 12.0, 168.0), 70.0],
	["27_courtyard_block_street", Vector3(-331.5, EYE, 240.0), Vector3(-331.5, 8.0, 170.0), 70.0],
	# The island relaid as the compute hub: the avenue, the plaza with the
	# obelisk on it, the halls, and the canopies that replaced the panel rows.
	["30_island_above", Vector3(-46.0, 230.0, 240.0), Vector3(-46.0, 6.0, -60.0), 58.0],
	["31_island_north_above", Vector3(-46.0, 180.0, 60.0), Vector3(-46.0, 6.0, -170.0), 58.0],
	["32_avenue_north", Vector3(-44.5, EYE, 60.0), Vector3(-44.5, 9.0, -120.0), 70.0],
	["33_plaza", Vector3(-44.5, EYE, 14.0), Vector3(-44.0, 9.0, -22.0), 72.0],
	["33b_plaza_high", Vector3(-20.0, 26.0, 26.0), Vector3(-46.0, 6.0, -30.0), 62.0],
	["34_server_garden", Vector3(-38.0, EYE, -28.0), Vector3(-22.0, 2.5, -62.0), 72.0],
	["35_under_the_canopy", Vector3(-44.0, EYE, 70.0), Vector3(-12.0, 3.0, 40.0), 72.0],
	["36_from_the_east_bridge", Vector3(14.0, 4.5, 18.0), Vector3(-60.0, 8.0, -30.0), 70.0],
	["37_power_yard", Vector3(-44.0, EYE, -100.0), Vector3(-22.0, 5.0, -150.0), 72.0],
]


func _initialize() -> void:
	await process_frame
	var out := OS.get_environment("RENDER_OUT")
	if out == "":
		print("FAIL  set RENDER_OUT to a directory")
		quit(1)
		return
	var level: Node3D = (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	for _i in 30:
		await physics_frame

	var cam := Camera3D.new()
	cam.far = 1600.0
	level.add_child(cam)
	cam.make_current()
	for pass_i in 2:
		for s: Array in SHOTS:
			cam.fov = float(s[3])
			cam.position = s[1]
			cam.look_at(s[2], Vector3.UP)
			for _i in 10:
				await process_frame
			if pass_i == 1:
				root.get_texture().get_image().save_png(out.path_join("mutaha_wip_%s.png" % s[0]))
	print("   wrote %d shots to %s" % [SHOTS.size(), out])
	quit()
