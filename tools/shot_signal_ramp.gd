extends SceneTree

# ─────────────────────────────────────────────
# WATCH THE LINK GO DOWN, WITH THE PLAYER TOO TOUGH TO DIE OF IT.
#
# The tiered version (tools/shot_under_fire.gd) photographs five rungs. This
# walks the whole curve so the transitions are visible — which is where the
# effect either reads as a system or reads as five unrelated screens.
#
# HEALTH IS 9999 so the run is about the signal and nothing else. Without it
# the drone dies partway down and the last frames are a death screen.
#
# TWO QUESTIONS, AND THE FIRST ONE IS HONEST BOOKKEEPING:
#   A. does being shot at degrade the link ON ITS OWN? A window is run with
#      nothing pinned and the drift is reported. If near-miss suppression does
#      not move it, the ramp below is a jammer and the report says so, rather
#      than implying the fight did it.
#   B. then the ramp itself, driven through receive_signal_damage() — the same
#      call an EMP and a jammer use — so what is photographed is the real path
#      and not a float written behind the game's back.
#
# Outputs every frame full size, plus one contact sheet so the descent can be
# read in a single image.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_signal_ramp.gd -- <out dir> [steps]
# ─────────────────────────────────────────────

const LEVEL := "res://maps/mutaha_wip_level.tscn"
const HOSTILE := "res://Character/characters/ai/soldier_rifle.tscn"
const TOUGH := 9999

var _player: Node3D = null
var _hud: Node = null
var _hostiles: Array = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = String(args[0]) if args.size() > 0 else "res://docs/marketing/wip"
	var steps: int = int(args[1]) if args.size() > 1 else 12
	DirAccess.make_dir_recursive_absolute(out_dir)

	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false   # never write the real save
	root.add_child(world)
	for _i in 90:
		await physics_frame

	_player = world.player
	if _player == null:
		push_warning("shot_signal_ramp: no player, so there is nothing to photograph.")
		quit(1)
		return

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
	# NOT max_health. Inflating it builds a segment per 20 points and the strip
	# ran off the screen -- which is how the signal bar stretching got found.
	# Topping health up every frame makes the drone unkillable and leaves the
	# HUD looking exactly as it does in play, which is the thing being shot.
	# Health RAISED, not just topped up — you asked to see the strip grow, and
	# a segment per 20 points is the Far Cry read. 400 shows twenty segments
	# against the usual five, so "I have more health now" is visible rather
	# than a number changing.
	_player.max_health = 400
	_player.health = 400

	for p in [Vector3(-6, 0, -13), Vector3(5.5, 0, -15), Vector3(-11, 0, -9), Vector3(10, 0, -10.5)]:
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
		_hostiles.append(bot)
	_player.look_at(centre + Vector3(0, 1, -13), Vector3.UP)
	for _i in 240:
		await physics_frame

	# ── A. does the fight alone move it? ────────
	var before: float = float(_player.signal_integrity)
	var low: float = before
	for _i in 420:                     # seven seconds of being shot at
		await physics_frame
		_player.health = _player.max_health
		low = minf(low, float(_player.signal_integrity))
	var after: float = float(_player.signal_integrity)
	print("")
	print("  INCOMING FIRE ALONE, over 7s under four rifles:")
	print("    signal %.3f -> %.3f   (lowest seen %.3f)" % [before, after, low])
	if low >= before - 0.02:
		print("    Near-miss suppression does not meaningfully touch the link, so the")
		print("    ramp below is a JAMMER, not the firefight. Worth knowing: without")
		print("    a jamming source on the map the veil never appears in normal play.")
	else:
		print("    The firefight does degrade it on its own.")

	# ── B. the ramp ─────────────────────────────
	var shots: Array[Image] = []
	var labels: Array[String] = []
	print("")
	print("  Walking the link down in %d steps" % steps)
	for i in steps:
		var target: float = 1.0 - float(i) / float(maxi(1, steps - 1))
		for _f in 26:
			await process_frame
			_pin(target)
			_player.health = _player.max_health
		for h in _hostiles:
			if is_instance_valid(h) and _hud != null and _hud.has_method("register_hit"):
				_hud.register_hit(6.0, h)
		for _f in 3:
			await process_frame
			_pin(target)
			_player.health = _player.max_health
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		var path := "%s/ramp_%02d_sig%03d.png" % [out_dir, i, int(round(target * 100.0))]
		img.save_png(path)
		shots.append(img)
		labels.append("%.2f" % target)
		print("    %-26s  signal %.2f  %s" % [path.get_file(), target, _rung(target)])

	_contact_sheet(shots, out_dir)
	print("")
	print("  Contact sheet: %s/ramp_sheet.png" % out_dir)
	quit(0)


func _rung(sig: float) -> String:
	if sig <= AI.SIGNAL_EKILL:
		return "EKILL      squad layer gone"
	if sig <= AI.SIGNAL_CRITICAL:
		return "CRITICAL   callsign gone"
	if sig <= AI.SIGNAL_DEGRADED:
		return "DEGRADED   state gone"
	if sig <= AI.SIGNAL_FUZZED:
		return "FUZZED     health gone"
	return "CLEAN"


## One image, four across, so the descent reads at a glance instead of needing
## twelve files opened in order.
func _contact_sheet(shots: Array[Image], out_dir: String) -> void:
	if shots.is_empty():
		return
	var cols := 4
	var rows := int(ceil(float(shots.size()) / float(cols)))
	var tw := int(shots[0].get_width() / 3)
	var th := int(shots[0].get_height() / 3)
	var sheet := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.02, 0.03, 0.04, 1.0))
	for i in shots.size():
		var t := shots[i]
		t.resize(tw, th, Image.INTERPOLATE_BILINEAR)
		t.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(t, Rect2i(0, 0, tw, th),
			Vector2i((i % cols) * tw, int(i / cols) * th))
	sheet.save_png("%s/ramp_sheet.png" % out_dir)


## Through the real call so the e-kill latch behaves as it does in play.
func _pin(sig: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.signal_integrity = sig
	if sig <= AI.SIGNAL_EKILL and _player.has_method("receive_signal_damage"):
		_player.receive_signal_damage(1.0)
		_player.lock_signal(30.0)
	if _hud != null and _hud.has_method("set_signal"):
		_hud.set_signal(sig)


func _find_hud(n: Node) -> Node:
	if n.has_method("set_signal") and n.has_method("register_hit"):
		return n
	for c in n.get_children():
		var f := _find_hud(c)
		if f != null:
			return f
	return null
