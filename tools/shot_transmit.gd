extends SceneTree

# ─────────────────────────────────────────────
# TRANSMITTING MAKES YOU LOUD — the mockup.
#
# Four frames of one order going out:
#   01  before. Four hostiles at 10, 22, 34 and 75 m. Nothing knows anything.
#   02  the instant you key the radio. The front has just left you.
#   03  mid-flight. It has passed the near pair and is reaching for the far one.
#   04  full reach. Three heard it; the one at 62 m is outside the radius and
#       still has no idea, which is the point — distance is a real defence.
#
# It also prints the integrity before and after, because the second cost of
# transmitting is the one you cannot see in a still.
#
# HEADFUL, because Godot cannot render in --headless. Takes the screen.
#
#   godot --audio-driver Dummy --path . --script res://tools/shot_transmit.gd -- <out dir>
# ─────────────────────────────────────────────

const LEVEL := "res://maps/mutaha_wip_level.tscn"
const HOSTILE := "res://Character/characters/ai/soldier_rifle.tscn"
## Metres out along the sightline. The last one is deliberately past tx_radius,
## and the NEGATIVE one is behind the player -- well inside tx_radius, so the
## only thing that can exclude it from an ADVANCE is the lobe.
const RANGES := [10.0, 22.0, 34.0, 75.0, -15.0]

var _player: Node3D = null
var _cmd: Node = null
var _bots: Array = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = String(args[0]) if args.size() > 0 else "res://docs/marketing/wip"
	DirAccess.make_dir_recursive_absolute(out_dir)

	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false   # never write the real save
	root.add_child(world)
	for _i in 90:
		await physics_frame
	_player = world.player
	var level: Node = _player.get_parent()
	# --depot: stay in the base instead of loading a mission. The ring banking
	# to the local surface normal only showed up indoors, on the depot floor,
	# so that is where the fix has to be checked.
	var in_depot: bool = args.has("--depot")
	if not in_depot:
		level.add_child(load(LEVEL).instantiate())
	for _i in 150:
		await physics_frame
	for who in PauseHold.holders():
		PauseHold.release(who)

	var nmap: RID = _player.get_world_3d().navigation_map
	var centre: Vector3 = _player.global_position
	if not in_depot:
		centre = NavigationServer3D.map_get_closest_point(nmap, Vector3(300, 0, 250))
		_player.global_position = centre + Vector3.UP * 1.2
	for _i in 20:
		await physics_frame

	_cmd = _player.get("commander")
	if _cmd == null or not _cmd.has_method("_transmit"):
		push_warning("shot_transmit: the player has no SquadCommander, so there is no radio to key.")
		quit(1)
		return

	# A line of hostiles running away from the camera, so the frame shows the
	# front overtaking them one at a time rather than all at once.
	for d in RANGES:
		var bot = load(HOSTILE).instantiate()
		level.add_child(bot)
		await process_frame
		bot.global_position = centre + Vector3(d * 0.22, 0.0, -d)
		bot.faction = Enums.Factions.ENEMY
		bot.player = _player
		bot.ai_manager = world.ai_manager
		if world.ai_manager != null and world.ai_manager.has_method("register_enemy"):
			world.ai_manager.register_enemy(bot)
		bot.exempt_from_culling(10000.0)
		bot.health = 100000000
		bot.max_health = 100000000
		# BLINDED, so the only thing that can tell them about you is the radio.
		# sight_range floors at 4 m, which is close enough to nothing at these
		# ranges -- without this they simply SEE the player standing in the open
		# at 12 m and the shot proves nothing about transmitting.
		bot.sensor_range = 0.0
		bot.sensor_bonus = 0.0
		# AWAKE. A freshly instanced soldier sits in PASSIVE, and receive_stimulus
		# returns on the first line for PASSIVE and DEAD -- so every probe below
		# read "no" and it looked like the transmission was not landing.
		bot.change_ai_state(Enemy.AIState.IDLE)
		bot.never_culled = true
		_bots.append(bot)
	# Angled down the line, and tilted so the ground carries the ring.
	# STEEPLY DOWN. A ground ring seen from eye height along the horizon is a
	# couple of pixels thick and lands behind the terrain silhouette; the wave
	# only reads when the camera can see the ground it is crossing.
	_player.look_at(centre + Vector3(3.0, -14.0, -26.0), Vector3.UP)
	for _i in 100:
		await physics_frame

	# NOT FROZEN. set_physics_process(false) on an Enemy and back on again left
	# all four inert for the rest of the run -- the chassis has its own
	# enable/disable logic and does not expect to be driven from outside. The
	# ranges printed below are therefore snapshotted at the moment of the
	# transmission rather than assumed to hold still.

	# The commander's own count, not an inference from AI state. Reading
	# ai_state afterwards was telling me things the transmission had nothing to
	# do with — a robot is in COMBAT for plenty of reasons, and AIState.COMBAT
	# is 0, so a "!= 0" test called every idle robot alerted as well.
	# A one-element array, not a plain int. GDScript lambdas capture by VALUE,
	# so assigning to a captured local inside the callback changes the lambda's
	# copy and nothing else -- the count came back as the initial -1 every time.
	var reached := [-1]
	_cmd.transmitted.connect(func(_o, _r, n): reached[0] = n)

	print("")
	print("    ranges            %s" % str(RANGES))
	print("    tx_radius         %.0f m" % float(_cmd.get("tx_radius")))
	var before_tx: float = _player.signal_integrity
	print("    integrity before  %.3f" % before_tx)
	# Who the bus can even see. A hostile that never reached registered_ai is
	# deaf to everything, not just to this, and it would look exactly like the
	# transmission having failed.
	var sm = world.ai_manager.stimulus_manager
	for i in _bots.size():
		var b = _bots[i]
		print("      bot %d  %5.1f m  registered=%s  faction=%d  alive=%s" % [
			i, _player.global_position.distance_to(b.global_position),
			str(b in sm.registered_ai), int(b.faction), str(b.alive)])

	# WOKEN IMMEDIATELY BEFORE, not at spawn. Something between instancing and
	# here puts them back in PASSIVE, and receive_stimulus returns on its first
	# line for PASSIVE -- so the order went out and nothing could hear it.
	for b in _bots:
		b.exit_passive_mode()
	await physics_frame

	await _grab("%s/transmit_01_before.png" % out_dir, "before the order — nothing has heard anything")

	# The range each hostile was actually at when the mic was keyed. These are
	# live robots that drift, and RANGES is only where they were PUT.
	var origin_of_tx: Vector3 = _player.global_position
	var tx_range := []
	for b in _bots:
		tx_range.append(_player.global_position.distance_to(b.global_position))

	# KEY THE RADIO. Through the real order path, not a hand-rolled call, so
	# what the shot photographs is what playing the game does.
	var squad = _cmd.get_selected_squad() if _cmd.has_method("get_selected_squad") else null
	if squad != null:
		_cmd._issue_order(0, _player.global_position + Vector3(2, 0, -14))   # Verb.ADVANCE
		print("    path              _issue_order(ADVANCE) — the real one")
	else:
		_cmd._transmit()
		print("    path              _transmit() direct — no squad was selected to order")

	# MEASURED HERE, not at the end. Passive recovery is 0.04/s, so by the
	# fourth frame most of a 0.06 transmission has already been earned back and
	# the cost looks like a third of what it is.
	var after_tx: float = _player.signal_integrity
	for _i in 2:
		await process_frame
	await _grab("%s/transmit_02_keyed.png" % out_dir, "the front has just left you")

	for _i in 26:
		await process_frame
	await _grab("%s/transmit_03_crossing.png" % out_dir, "crossing the near pair, reaching for the far one")

	for _i in 14:
		await process_frame
	await _grab("%s/transmit_04_reach.png" % out_dir, "well out — the far edge runs off over the horizon")

	print("    integrity after   %.3f  (the order cost %.3f on the frame it went out)"
		% [_player.signal_integrity, before_tx - after_tx])
	print("    ADVANCE receivers (lobe %.0f deg): %d of %d" % [float(_cmd.get("tx_cone_degrees")), reached[0], _bots.size()])

	# ── 06 THE OTHER SHAPE ──────────────────────
	# FOLLOW has no bearing in it -- "come with me" is addressed to the squad
	# wherever it is -- so it goes out as a circle.
	#
	# FIRED RIGHT AFTER THE ADVANCE, not at the end. These are live robots that
	# wander several metres a second: with the two transmissions five seconds
	# apart the receiver counts differed because the ROBOTS had moved, which
	# tells you nothing about the lobe. Back to back, position is held roughly
	# constant and the only variable left is the shape.
	reached[0] = -1
	_cmd._issue_order(1, null)   # Verb.FOLLOW
	for _i in 28:
		await process_frame
	await _grab("%s/transmit_06_follow_circle.png" % out_dir, "FOLLOW — no bearing, so a full circle")
	print("    FOLLOW receivers (full circle):   %d of %d" % [reached[0], _bots.size()])
	# NO PER-BOT TABLE HERE. One was printed and it contradicted the counts:
	# the counts are taken by the commander at the instant of each order and
	# the table a moment later, by which time these live robots had walked far
	# enough to change the answer. Two measurements of different instants read
	# as a bug in the feature rather than as wander.

	# ── 05 the reaction ─────────────────────────

	# A BEAT AFTER THE FRONT LANDS. The arrival callbacks are spread across
	# `travel`, and the last of them fires a frame or two after the fourth
	# photograph -- probing on that frame said nobody had been told, including
	# the robot standing 12 m away.
	for _i in 70:
		await physics_frame

	# WHAT EACH ROBOT NOW KNOWS, read off the robot rather than guessed from
	# its behaviour.
	#
	# Facing was the first thing I measured and it is the wrong instrument:
	# idle robots drift and turn for their own reasons, so the numbers moved
	# whether or not anything had been told anything. last_seen_point is the
	# memory ENEMY_SPOTTED actually writes — if the transmission's origin is in
	# there, that robot has your position, full stop.
	# AND ITS STATE, because the handler only writes that memory for a robot
	# that is not already in COMBAT or SEARCH. Without the state printed beside
	# it a "no" looks like the transmission failing, when most of the time it
	# means that robot was already in a firefight with the player's own squad
	# forty metres away and knew plenty.
	var state_names := ["COMBAT", "PATROL", "SEARCH", "IDLE", "DEAD", "PASSIVE"]
	var all_passive := true
	for b in _bots:
		if int(b.ai_state) != 5:
			all_passive = false
	print("    does it have your position? (last_seen_point, within 2 m of where you keyed)")
	for i in _bots.size():
		var b = _bots[i]
		if not is_instance_valid(b):
			continue
		var knows := false
		for p in b.last_seen_point:
			if (p as Vector3).distance_to(origin_of_tx) <= 2.0:
				knows = true
				break
		print("      %5.1f m   %-4s  %-7s  %s" % [tx_range[i], "YES" if knows else "no",
			state_names[int(b.ai_state)],
			"in reach" if tx_range[i] <= float(_cmd.get("tx_radius")) else "OUT OF REACH"])

	if all_passive:
		print("")
		print("    NOTE: every hostile here is PASSIVE and stayed PASSIVE through")
		print("          exit_passive_mode(), never_culled and an explicit state set.")
		print("          Something in this level holds them -- the induction, most")
		print("          likely. receive_stimulus returns on its first line for")
		print("          PASSIVE, so the BEHAVIOURAL half is not exercised by this")
		print("          shot. What is: the order path fires the transmission, the")
		print("          integrity cost, the receiver count, and the wavefront.")

	for _i in 300:
		await physics_frame
	await _grab("%s/transmit_05_reaction.png" % out_dir, "five seconds later")

	print("")
	quit(0)


func _grab(path: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var err := img.save_png(path)
	if err == OK:
		print("    %-28s  %s" % [path.get_file(), note])
	else:
		printerr("    could not write %s (%s)" % [path, error_string(err)])
