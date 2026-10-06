extends SceneTree

# ─────────────────────────────────────────────
# PHOTOGRAPHS THE REAL SQUAD MANAGER. Not a mock of it — the actual
# SquadManagerUI, its actual pages, driven by a made-up campaign the same way
# tools/test_squad_manager.gd drives one.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_squad_manager.gd -- <out dir>
#
# MUST RUN HEADFUL: --headless has no renderer and would write blank files.
#
# WHY THIS EXISTS. tools/wip_screens.gd drew its own controls to try a design
# out; this proves the design landed, because anything wrong in the live pages
# shows up here and nothing here can flatter them. When the UI work is finished
# both files go.
#
# A MADE-UP CAMPAIGN, never a real one: no CampaignManager, no save file, and
# SaveSlots points itself at a sandbox under --script. It cannot touch
# campaign.json.
# ─────────────────────────────────────────────

const CAT := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const SHOT := Vector2i(1920, 1080)

var _out := "docs/marketing/wip"
var ui: SquadManagerUI
var state: CampaignState
var _cat: ItemCatalogue


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Settings.path = "user://settings_probe.json"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://") + _out)

	_cat = load(CAT)
	state = CampaignState.new()
	state.armoury = Armoury.new()
	state.catalogue = _cat
	state.award(540)
	state.award_compute(4)
	state.supply_cap = 12
	var p := state.player_record
	p.display_name = "PLAYER"
	p.set_chassis(_cat.chassis_def(&"soldier"), _cat)
	p.weapon_ids[0] = &"m4"

	# One of every buildable frame, kitted the way a squad looks mid-campaign:
	# an empty roster photographs an empty page and proves nothing about how the
	# cards hold real contents.
	_robot(&"walker", "CANNON", [&"autocannon", &"heavy_mg"], [],
		[&"armor_plating", &"optics", &"overclock_servos"], 12, 4)
	_robot(&"rover", "VESNA", [&"machine_gun"], [], [&"armor_plating"], 7, 4)
	_robot(&"reclaimer", "ANVIL", [&"mortar"], [], [&"optics", &"hardened_uplink"], 3, 3)
	_robot(&"soldier", "BRICK", [&"squad_auto"], [&"frag", &"repair_kit"],
		[&"armor_plating", &"nanite_reboot"], 9, 4)
	_robot(&"mechanic", "TOOLBOX", [], [&"repair_kit"], [&"armor_plating"], 0, 4)
	_robot(&"spotter", "SPARROW", [], [&"scanner"], [&"optics"], 0, 2)
	for id in [&"m4", &"frag", &"smoke", &"repair_kit", &"armor_plating", &"cluster_launcher",
			&"optics", &"emp"]:
		state.armoury.add(id)

	var s := GDScript.new()
	s.source_code = "extends Node\nvar state\nvar catalogue\nvar in_mission = false\nfunc selected_mission():\n\treturn null\n"
	s.reload()
	var campaign := Node.new()
	campaign.set_script(s)
	campaign.set("state", state)
	campaign.set("catalogue", _cat)
	campaign.add_to_group("campaign")
	root.add_child(campaign)

	ui = SquadManagerUI.new()
	root.add_child(ui)
	await process_frame
	ui.open()
	await process_frame

	await _shoot(&"squad", "live_squad_walker.png", func(): _select("CANNON"))
	await _shoot(&"squad", "live_squad_soldier.png", func(): _select("BRICK"))
	await _shoot(&"factory", "live_factory.png", Callable())
	await _shoot(&"armorer", "live_armorer_weapon.png", func(): _pick(&"cluster_launcher"))
	await _shoot(&"armorer", "live_armorer_equipment.png", func(): _pick(&"emp"))
	await _shoot(&"armorer", "live_armorer_module.png", func(): _pick(&"optics"))
	await _shoot(&"armorer", "live_armorer_folded.png", func():
		_pick(&"optics")
		var page: Control = ui._pages[&"armorer"]
		page._folded[ItemDefinition.Kind.WEAPON] = true
		page._folded[ItemDefinition.Kind.EQUIPMENT] = true
		page.rebuild())
	quit(0)


func _robot(frame: StringName, name: String, weapons: Array, kit: Array, mods: Array,
		kills: int, ops: int) -> void:
	var r := SoldierRecord.new()
	r.display_name = name
	r.set_chassis(_cat.chassis_def(frame), _cat)
	for i in mini(weapons.size(), r.weapon_ids.size()):
		r.weapon_ids[i] = weapons[i]
	for i in mini(kit.size(), r.equipment_ids.size()):
		r.equipment_ids[i] = kit[i]
	for i in mini(mods.size(), r.module_ids.size()):
		r.module_ids[i] = mods[i]
	r.confirmed_kills = kills
	r.missions_survived = ops
	r.rank = mini(ops, 5)
	r.recompute_stats(_cat)
	state.add_soldier(r)


func _select(who: String) -> void:
	var page: Control = ui._pages[&"squad"]
	for r in state.roster:
		if r.display_name == who:
			# Set and redraw, rather than _select(): opening the tab runs on_open,
			# which lands on the player, and a select that happened before that is
			# a select that did not happen.
			page.selected = r
			page.rebuild()
			return
	push_warning("shot_squad_manager: no robot called '%s' to select." % who)


func _pick(id: StringName) -> void:
	var page: Control = ui._pages[&"armorer"]
	page.selected_id = id
	page.rebuild()


func _shoot(tab: StringName, file: String, prepare: Callable) -> void:
	ui.show_tab(tab)
	await process_frame
	if prepare.is_valid():
		prepare.call()
	await process_frame

	# The UI is a CanvasLayer on the root viewport, so there is no way to render
	# it into a SubViewport without reparenting the live tree — which would be
	# photographing something other than the thing under test. The window is the
	# frame instead, and the window is told what size to be ONCE, here, in a tool
	# that is not the game.
	DisplayServer.window_set_size(SHOT)
	get_root().content_scale_size = SHOT
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := "res://%s/%s" % [_out, file]
	var err := img.save_png(path)
	if err != OK:
		printerr("shot_squad_manager: could not write %s (%s)" % [path, error_string(err)])
	else:
		print("wrote %s  %dx%d" % [path, img.get_width(), img.get_height()])
