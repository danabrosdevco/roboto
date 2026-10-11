extends SceneTree

# ─────────────────────────────────────────────
# CONTACT MARKS IN THE WORLD, AND WHAT HAPPENS WHEN THE LINK DROPS.
#
# Three frames:
#   01  marks landing, fresh, ages counting from zero
#   02  the same marks thirty seconds older — the information is stale and
#       says so, while the squad is still out there seeing things
#   03  the link at the floor. No new reports arrive; the old marks keep
#       ageing. The battlefield did not go quiet, you stopped being told.
#
# HEADFUL, because Godot cannot render in --headless. Takes the screen.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_contacts.gd -- <out dir>
# ─────────────────────────────────────────────

const LEVEL := "res://maps/mutaha_wip_level.tscn"
const HOSTILE := "res://Character/characters/ai/soldier_rifle.tscn"

var _player: Node3D = null
var _hud: Node = null
var _bots: Array = []
var _auto: bool = false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = String(args[0]) if args.size() > 0 else "res://docs/marketing/wip"
	# --auto: do not call mark_contact at all. The squad reports the hostiles
	# by seeing them, which is the path a real mission takes and the one that
	# was dead until AIManager.contact_seen was wired up.
	var auto_mode: bool = args.has("--auto")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_auto = auto_mode

	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false   # never write the real save
	root.add_child(world)
	for _i in 90:
		await physics_frame
	_player = world.player
	var level: Node = _player.get_parent()
	level.add_child(load(LEVEL).instantiate())
	for _i in 150:
		await physics_frame
	for who in PauseHold.holders():
		PauseHold.release(who)

	var nmap: RID = _player.get_world_3d().navigation_map
	var centre: Vector3 = NavigationServer3D.map_get_closest_point(nmap, Vector3(300, 0, 250))
	_player.global_position = centre + Vector3.UP * 1.2
	for _i in 20:
		await physics_frame
	_hud = _find_hud(root)

	# ONE DOWN, ONE GONE. The roster draws these two states very differently
	# now — amber and actionable against dim and finished — and that is a thing
	# only a photograph can check. The induction already leaves Bravo-4 downed,
	# so this just destroys one more outright.
	# THREE CONDITIONS, TWO WORDS ON SCREEN. The induction already leaves
	# Bravo-4 on the deck and liftable, so this stages the other two:
	#
	#   killed        destroyed outright          -> DESTROYED
	#   spent         on the deck, no lift left   -> DESTROYED, same as killed
	#
	# The second is the one worth photographing. can_revive() is false, so the
	# player cannot pick it up, and the roster is supposed to stop calling it
	# a job and call it a loss.
	# NOT IN AUTO MODE. That mode is here to show the squad REPORTING, and a
	# squad with two of its four destroyed and one on the deck has one pair of
	# working eyes left -- which is a poor demonstration of eyes.
	var killed := 0
	var spent := 0
	for squad in ([] if _auto else root.get_tree().get_nodes_in_group("squads")):
		for m in squad.squad_members:
			if m == null or not is_instance_valid(m) or not m.alive:
				continue
			if "downed" in m and m.downed:
				continue
			if killed == 0:
				m.alive = false
				if "downed" in m:
					m.downed = false   # destroyed, not on the deck
				killed += 1
			elif spent == 0:
				m.alive = false
				m.downed = true
				m._revive_spent = true
				spent += 1
	await physics_frame

	if _hud == null or not _hud.has_method("mark_contact"):
		push_warning("shot_contacts: no HUD with mark_contact, so there is nothing to photograph.")
		quit(1)
		return

	# Bodies out there to have been reported. They are real robots so the frame
	# shows a mark and the thing it refers to, which is the whole point of
	# pinning: the mark stays where it was called, the robot walks off.
	for p in [Vector3(-5, 0, -11), Vector3(4, 0, -14), Vector3(-9, 0, -16), Vector3(8, 0, -9)]:
		var bot = load(HOSTILE).instantiate()
		level.add_child(bot)
		await process_frame
		bot.global_position = centre + p
		bot.faction = Enums.Factions.ENEMY
		bot.player = _player
		bot.ai_manager = world.ai_manager
		if world.ai_manager != null and world.ai_manager.has_method("register_enemy"):
			world.ai_manager.register_enemy(bot)
		bot.exempt_from_culling(10000.0)
		bot.health = 100000000
		bot.max_health = 100000000
		_bots.append(bot)
	# Angled DOWN so the marks sit against ground rather than on the skyline,
	# where a bracket at min_scale is lost in the terrain silhouette.
	# In auto mode, stand the squad up front where it can see down the line.
	if _auto:
		var n := 0
		for squad in root.get_tree().get_nodes_in_group("squads"):
			for m in squad.squad_members:
				if m == null or not is_instance_valid(m) or not m.alive:
					continue
				m.global_position = centre + Vector3(float(n) * 2.5 - 3.0, 0.0, -3.0)
				n += 1
		for _i in 30:
			await physics_frame
	_player.look_at(centre + Vector3(0.0, -2.5, -13.0), Vector3.UP)
	for _i in 120:
		await physics_frame

	# ── 01 fresh ────────────────────────────────
	_pin(1.0)
	_report(centre)
	for _i in 40:
		await process_frame
		_pin(1.0)
	await _grab("%s/contacts_01_fresh.png" % out_dir, "marks fresh, ages at zero")

	# ── 02 stale ────────────────────────────────
	# Wound the clock on rather than waiting half a minute of real time.
	_age_marks(30.0)
	for _i in 6:
		await process_frame
		_pin(1.0)
	await _grab("%s/contacts_02_stale.png" % out_dir, "same marks, thirty seconds older")

	# ── 03 link down ────────────────────────────
	for _i in 30:
		await process_frame
		_pin(0.0)
	# Reports keep being called and keep being refused.
	var took: bool = _report(centre)
	_age_marks(12.0)
	for _i in 6:
		await process_frame
		_pin(0.0)
	await _grab("%s/contacts_03_linkdown.png" % out_dir,
		"link at the floor — new report accepted: %s" % ("yes" if took else "NO"))

	print("")
	quit(0)


## Call four contacts at places around the sightline.
func _report(_centre: Vector3) -> bool:
	# AT THE BODIES' REAL POSITIONS, not at a guessed offset from the navmesh
	# point. The robots fall and settle, so a mark pinned to centre.y + 1 floats
	# above them -- which is the exact "it does not sit over the thing" problem
	# this shot exists to show fixed.
	var any := false
	if _auto:
		# Nothing is reported by hand here. Whatever is on screen was put there
		# by a squadmate seeing it.
		for c in _hud.get_children():
			if c is ScanEnemyMarker and c.pinned:
				any = true
		return any
	for b in _bots:
		if not is_instance_valid(b):
			continue
		if _hud.mark_contact(b.global_position, 120.0, _player):
			any = true
	return any


## Push every pinned mark's clock forward, so a stale frame does not cost
## thirty seconds of shutter time.
func _age_marks(seconds: float) -> void:
	for c in _hud.get_children():
		if c is ScanEnemyMarker and c.pinned:
			c.time += seconds


func _pin(sig: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.signal_integrity = sig
	if sig <= AI.SIGNAL_EKILL and _player.has_method("receive_signal_damage"):
		_player.receive_signal_damage(1.0)
		_player.lock_signal(30.0)
	if _hud != null and _hud.has_method("set_signal"):
		_hud.set_signal(sig)


func _grab(path: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var err := img.save_png(path)
	if err == OK:
		print("    %-30s  %s" % [path.get_file(), note])
	else:
		printerr("    could not write %s (%s)" % [path, error_string(err)])


func _find_hud(n: Node) -> Node:
	if n.has_method("set_signal") and n.has_method("register_hit"):
		return n
	for c in n.get_children():
		var f := _find_hud(c)
		if f != null:
			return f
	return null
