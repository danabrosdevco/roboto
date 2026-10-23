extends SceneTree

# ─────────────────────────────────────────────
# PHOTOGRAPH THE SCREENS.
#
# Everything built since the campaign rework started is a screen or a board,
# and none of it has been looked at by a person. This grabs each one with a
# campaign behind it that has enough in it to be worth drawing.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_ui.gd -- <out dir>
#
# HEADFUL, because this grabs the window's viewport; the headless dummy
# renderer has no image to give. It never writes the campaign.
# ─────────────────────────────────────────────

## The UI kit, for its motion switch — see the MOTION block in ui_kit.gd.
const Kit := preload("res://Character/hud/squad/ui_kit.gd")
const _SimArena := preload("res://Character/hud/sim_arena_ui.gd")
const _Squad := preload("res://Character/hud/squad_manager_ui.gd")
const _Debrief := preload("res://Character/hud/debrief_screen.gd")

var _out: String = ""
var _world: Node = null
var _cm = null


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_out = String(args[0]) if args.size() > 0 else "res://docs/marketing/wip"
	DirAccess.make_dir_recursive_absolute(_out)
	Settings.path = "user://settings_probe.json"
	# MOTION OFF, so a grab cannot catch a card mid-fade. See ui_kit.gd.
	Kit.motion = false
	await process_frame
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1600, 900))
		DisplayServer.window_set_position(Vector2i(60, 40))

	_world = load("res://Env/world.tscn").instantiate()
	_cm = _world.get_node("CampaignManager")
	_cm.autosave = false
	root.add_child(_world)
	for _i in 150:
		await physics_frame

	# A campaign with enough in it to draw: money, compute, a few lines open
	# and some ground held.
	var st = _cm.state
	st.earned = 9000
	st.compute_earned = 18
	for id in [&"soldier", &"mechanic", &"rover", &"walker", &"m4", &"frag",
			&"smoke", &"repair_kit", &"machine_gun", &"heavy_mg", &"optics"]:
		st.grant_unlock(id)
	st.set_site_owner(&"hillfort_wip", Enums.Factions.PLAYER)
	st.set_site_owner(&"valley_basin", Enums.Factions.PLAYER)
	st.completed_missions.append(&"arena_3_firing_line")
	st.completed_missions.append(&"hfw_1_fort")
	st.completed_missions.append(&"basin_1_anchor")
	st.under_attack = &"valley_basin"
	st.under_attack_turn = 6
	st.turn = 6
	await physics_frame

	await _shoot_sim()
	await _shoot_squad()
	await _shoot_debrief()
	await _shoot_board()
	print("")
	quit(0)


# ── the screens ──────────────────────────────────────────────────────────────

func _shoot_sim() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	root.add_child(layer)
	var ui = _SimArena.new()
	ui.campaign = _cm
	ui.catalogue = _cm.catalogue
	layer.add_child(ui)
	await process_frame
	ui.rebuild()
	await _grab("ui_sim_training.png", "the sim arena — training")
	ui._tab = &"lab"
	ui._picking = &"a"
	for id in [&"soldier", &"soldier", &"walker"]:
		ui._add(id)
	ui._picking = &"b"
	for id in [&"chaser", &"chaser", &"chaser", &"rifleman"]:
		ui._add(id)
	await _grab("ui_sim_lab.png", "the sim arena — a fight being built")
	layer.queue_free()
	await process_frame


func _shoot_squad() -> void:
	var ui = _Squad.new()
	ui.campaign = _cm
	ui.state = _cm.state
	ui.catalogue = _cm.catalogue
	var layer := CanvasLayer.new()
	layer.layer = 90
	root.add_child(layer)
	layer.add_child(ui)
	await process_frame
	for _i in 4:
		await process_frame
	if ui.has_method("open"):
		ui.open()
		for _i in 4:
			await process_frame
	# TOOLING AND THE ARMORER ARE BOTH GONE (steps 7a and 7b). What stands
	# where they stood is MEMORY, which has three tabs of its own.
	if ui.has_method("show_tab"):
		ui.show_tab(&"memory")
		await process_frame
		await _grab("ui_memory_weapons.png", "memory — the guns you may carry")
		var page = ui._pages.get(&"memory")
		if page != null:
			page._show(&"upgrades")
			await process_frame
			await _grab("ui_memory_upgrades.png", "memory — the branches, still blank")
	layer.queue_free()
	await process_frame


func _shoot_debrief() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	root.add_child(layer)
	var d = _Debrief.new()
	layer.add_child(d)
	await process_frame
	if d.has_method("show_result"):
		d.show_result(_cm.get_mission(&"basin_1_anchor"), _fake_result())
	elif d.has_method("_build"):
		d._build(_cm.get_mission(&"basin_1_anchor"), _fake_result())
	await process_frame
	await _grab("ui_debrief_turn.png", "the debrief — the turn, and what they did")
	layer.queue_free()
	await process_frame


## A result that exercises every row the turn report can draw.
func _fake_result() -> Dictionary:
	return {
		"success": true, "turn": 6, "income": 21,
		"site_taken": "Valley Basin", "site_compute": 1,
		"enemy": {"outcome": 3, "site": "valley_basin"},
		"resources_before": 7800, "resources_after": 8521,
		"reward": 500, "objective_reward": 200, "salvage": 0, "compute": 1,
		"compute_before": 17, "squad": [], "unlocked": [], "seconds": 412.0,
	}


# ── the board ────────────────────────────────────────────────────────────────

func _shoot_board() -> void:
	var table = _find(root, "OpsTable")
	if table == null:
		print("    (no OpsTable in the tree — the board shot was skipped)")
		return
	if table.has_method("refresh"):
		table.refresh()
	for _i in 30:
		await physics_frame
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var at: Vector3 = table.global_position
	# STRAIGHT DOWN, CLOSE. The board is a projection on the table top, so a
	# three-quarter view from standing height frames the room instead of it.
	cam.global_position = at + Vector3(0.0, 5.5, 0.9)
	cam.look_at(at, Vector3.UP)
	for _i in 10:
		await physics_frame
	await _grab("ui_ops_table.png", "the operations table")
	cam.queue_free()


# ── plumbing ─────────────────────────────────────────────────────────────────

func _grab(name: String, note: String) -> void:
	for _i in 4:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/%s" % [_out, name]
	var err := img.save_png(path)
	print("    %-28s %s" % [name, note if err == OK else "FAILED (%d)" % err])


func _find(n: Node, named: String) -> Node:
	if n.name == named:
		return n
	for c in n.get_children():
		var f := _find(c, named)
		if f != null:
			return f
	return null
