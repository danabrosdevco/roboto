extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# THE PLAYER TAKES A CORE, AND THE ENEMY COMES AND TAKES IT BACK.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/test_core_retake_live.gd
#
# tools/test_holdable_core.gd already covers the RULE: put `retake_hostiles`
# bodies in the circle for `retake_seconds` with the player elsewhere and the
# core flips. It proves it with bare Node3Ds added to the "enemies" group,
# standing exactly on the spot — which is the right way to test a state machine
# and tells you nothing about whether the situation can ever arise.
#
# THIS IS THE OTHER HALF. A real mission, real squads that have to be told to
# go, real bodies that have to walk there, and a real navmesh in the way. Three
# things have to work and only the first of them had a test:
#
#   1  CoreRetakers hears the capture and picks a squad          (sent)
#   2  that squad is ordered to the core's own capture point     (ordered)
#   3  enough of them arrive and stand there long enough         (taken)
#
# ANY OF THE THREE CAN FAIL SILENTLY. If no squad is in range the core is never
# contested; if the order goes to the core's ORIGIN rather than its terminal
# the squad stands 8 m off a 7 m circle and nothing counts; if the navmesh does
# not reach, they walk into a wall forever. In every case the player keeps the
# core, nothing is logged, and the feature simply does not happen.
#
# THE PLAYER IS PARKED 400 m AWAY on purpose. Standing on your own core is the
# defence — holdable_core._reverse_tick returns early while you are there — so
# leaving the player near it would be testing the opposite rule.
#
# IT WRITES NO SAVE. `cm.autosave = false`, same as test_hillfort_live.
# ─────────────────────────────────────────────

const SITE := &"hfw_1_fort"
## Long enough for a squad to cross a lane and stand still, at 60 fps headless.
## The walk is real; this is not a state machine being stepped.
const WALK_FRAMES := 4200
## Shortened from the shipped 9.0 so the test is not mostly a timer, but NOT to
## zero — the point is that they have to HOLD the ground, and 0 would pass on a
## body that clipped the edge of the circle for a single frame.
const RETAKE_SECONDS := 3.0

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _done() -> void:
	print("")
	print("PASS" if _fails == 0 else "FAIL  %d check(s) failed" % _fails)
	quit(0 if _fails == 0 else 1)


func _init() -> void:
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame

	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = true
	master.show_mission_briefing = false
	var cm: CampaignManager = master.find_child("CampaignManager", true, false)
	# NEVER THE PLAYER'S SAVE.
	cm.autosave = false
	root.add_child(master)
	for _i in 90:
		await physics_frame
	var world: World = master._world()
	cm.reset_campaign()

	var m = cm.get_mission(SITE)
	if m == null:
		_check("the mission exists", false, String(SITE))
		_done()
		return
	cm.in_mission = false
	cm.debug_mission = m
	cm.select_mission(SITE)
	await world.load_next_level(m.level_scene)
	# NO SECOND on_level_loaded(). World.load_next_level() ends by calling it
	# itself, so an explicit call here redeploys BOTH spawners in the same frame
	# as the first deploy — and tearing a robot down that few frames after it
	# was stood up leaves the engine something it only trips over in final
	# cleanup: every assertion printed PASS and the run still handed the shell
	# exit 139. H10, root-caused 2026-10-24: dropping this one line is the whole
	# fix. A 10-frame gap before the second call also cures it; one or two
	# frames do not. The call was redundant either way.
	# LONGER THAN THE OTHER LIVE SUITES WAIT. The enemy force spawns over
	# several frames and the squads group is what this whole test reads from,
	# so starting before it is populated would measure an empty map.
	for _i in 240:
		await physics_frame

	await _retake(world)
	_done()


func _retake(world) -> void:
	var level = world.current_level
	var retakers = _find(level, "CoreRetakers")
	_check("the site built a CoreRetakers", retakers != null)

	# IT HAS TO BE LISTENING, not merely present. CoreRetakers._ready scans for
	# cores once and connects to holder_changed; if that scan finds none it
	# connects to nothing and every capture after it is silent.
	var listening := 0
	for c in _cores(level):
		if c.has_signal("holder_changed"):
			for conn in c.holder_changed.get_connections():
				if conn.get("callable") != null \
						and conn["callable"].get_object() == retakers:
					listening += 1
					break
	_check("...and it is connected to the cores", listening == _cores(level).size(),
		"listening to %d of %d cores" % [listening, _cores(level).size()])

	var squads := _hostile_squads()
	_check("there are hostile squads on the map to send", squads.size() > 0,
		"%d" % squads.size())
	if squads.is_empty():
		return

	# ── PICK THE CORE THE TEST CAN ACTUALLY ANSWER FOR ──
	# Not an arbitrary one. The nearest hostile squad has to be inside
	# CoreRetakers.call_radius and big enough to field retake_hostiles, or
	# sending nobody is the CORRECT behaviour and this suite would be asserting
	# that a feature fails to fire.
	# NOT THE BUNKER. Its core is named Hold and it answers to a DIFFERENT
	# rule: start_held() plants an anchor, and holdable_core hands the core
	# back to them when that anchor is destroyed. With twelve hostile squads
	# on this map the anchor is shot within seconds, so the first run of this
	# suite watched the bunker flip back with nobody in its circle at all and
	# reported a pass for the wrong reason. Capture-by-standing is a compute
	# core's rule, so a compute core is what this tests.
	var bunker = _find(level, "SiteBunker")
	_check("the bunker can be told apart from the compute cores", bunker != null,
		"found it" if bunker != null
			else "no SiteBunker, so its core cannot be excluded and this suite "
				+ "would test the anchor rule by accident")
	var core = null
	var core_d: float = 1e9
	var radius: float = float(retakers.call_radius) if retakers != null else 120.0
	for c in _cores(level):
		if bunker != null and bunker.is_ancestor_of(c):
			continue
		var at: Vector3 = _point_of(c)
		for s in squads:
			var d: float = (s.get_center() as Vector3).distance_to(at)
			if d < core_d and d <= radius and _alive_in(s) >= int(c.retake_hostiles):
				core_d = d
				core = c
	_check("...and one of them is within call of a core", core != null,
		"nearest %.0f m, call radius %.0f m" % [core_d, radius])
	if core == null:
		return
	# BY ITS HOST, not by its own name. Every HoldableCore the slice seats is
	# called "Hold" — the identity a human recognises is the prefab it sits on.
	print("      core under test: %s, nearest hostile squad %.0f m away"
		% [core.get_parent().name, core_d])

	# ── THE PLAYER IS SOMEWHERE ELSE ──
	# Being on it is the defence, so this has to be true BEFORE the capture or
	# the core can never slip.
	var player = _player(world)
	_check("there is a player to move out of the way", player != null)
	if player == null:
		return
	# FAR ENOUGH TO NOT DEFEND IT, NEAR ENOUGH TO NOT FREEZE THE MAP.
	#
	# The first cut parked the player 400 m away, copying test_holdable_core —
	# which is right for bare Node3Ds and catastrophic here. Enemy culling
	# freezes any hostile more than activation_distance (75 m) from the player,
	# so a player that far off switches the whole map off and the retakers were
	# measured still standing on their start line after seventy seconds. That
	# was the test's own doing, not the game's.
	#
	# 30 m is four times the 7 m circle, so being there is not a defence, and
	# comfortably inside 75 m so the AI actually runs.
	var home: Vector3 = _point_of(core)
	(player as Node3D).global_position = home + Vector3(30.0, 0.0, 0.0)

	core.retake_seconds = RETAKE_SECONDS

	# ── 1 · THE PLAYER TAKES IT ──
	core.start_held()
	for _i in 20:
		await physics_frame
	_check("the player holds the core", core.is_held_by_player(),
		"holder = %d" % int(core.holder))
	if not core.is_held_by_player():
		return
	_check("...and it keeps ticking, so it can be lost",
		core.is_physics_processing())

	# ── 2 · SOMEBODY IS SENT FOR IT ──
	# Read off the squads, not off the log line. An ADVANCE order whose
	# destination is the core's own CAPTURE POINT is the thing that matters —
	# an order to the core's origin would park them 8 m off a 7 m circle and
	# every print would still say the counter-attack was sent.
	# INSIDE THE CIRCLE IS THE BAR, not some tolerance picked out of the air.
	# A squad records its own formation centre rather than the literal point it
	# was handed, so the order lands a few metres out by design; what decides
	# whether the counter-attack can work is whether that lands within
	# channel_range, because outside it they can stand there forever and the
	# core will not count them.
	var sent = null
	var nearest_order: float = 1e9
	for s in _hostile_squads():
		var dest = s.get("objective_position")
		if dest == null:
			continue
		var d: float = (dest as Vector3).distance_to(home)
		nearest_order = minf(nearest_order, d)
		if d <= float(core.channel_range):
			sent = s
			break
	_check("a hostile squad is ordered inside the core's circle", sent != null,
		"nearest order lands %.1f m from the capture point, circle is %.1f m"
			% [nearest_order, float(core.channel_range)])

	# ── 3 · THEY WALK THERE AND TAKE IT ──
	var want: int = int(core.retake_hostiles)
	var peak := 0
	var flipped := false
	for _i in WALK_FRAMES:
		await physics_frame
		peak = maxi(peak, _hostiles_within(core))
		if not core.is_held_by_player():
			flipped = true
			break
	# WHERE THE SQUAD ACTUALLY ENDED UP. When the count falls short this is the
	# number that says why: a squad holds a formation, so being "at" a point
	# spreads its members around it, and anyone outside channel_range is not
	# counted by the core no matter how close they look on screen.
	if sent != null:
		var spread: Array[String] = []
		for mm in sent.get_orderable_soldiers():
			if mm == null or not is_instance_valid(mm):
				continue
			if ("alive" in mm) and not mm.alive:
				spread.append("%s dead" % mm.name)
				continue
			spread.append("%s %.1f m" % [mm.name,
				(mm as Node3D).global_position.distance_to(home)])
		print("      the squad that was sent, at the end: %s  (circle is %.1f m)"
			% [str(spread), float(core.channel_range)])

	_check("...and %d of them reach the circle and stand in it" % want,
		peak >= want, "most that ever stood in it at once: %d" % peak)
	# The detail reports the OUTCOME, not a failure message — _check prints it
	# either way, and "PASS ... still the player's" was unreadable.
	_check("THE ENEMY TAKES THE CORE BACK", flipped,
		"took it back" if flipped else "still the player's after %d frames" % WALK_FRAMES)
	if flipped:
		_check("...to THEM, not to nobody",
			int(core.holder) == int(core.Holder.HOSTILE),
			"holder = %d" % int(core.holder))


# ── helpers ──────────────────────────────────────────────────────────────────

## Where the channel is measured from — holdable_core uses the interactible and
## falls back to the core. Anything that guesses the origin instead is watching
## a different point from the one the game watches.
func _point_of(core) -> Vector3:
	if "interactible" in core and core.interactible != null \
			and is_instance_valid(core.interactible):
		return (core.interactible as Node3D).global_position
	return (core as Node3D).global_position


func _hostiles_within(core) -> int:
	var at: Vector3 = _point_of(core)
	var r: float = float(core.channel_range)
	var n := 0
	for e in get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e) or not (e is Node3D):
			continue
		if ("alive" in e) and not e.alive:
			continue
		if (e as Node3D).global_position.distance_to(at) <= r:
			n += 1
	return n


func _hostile_squads() -> Array:
	var out: Array = []
	for s in get_nodes_in_group("squads"):
		if s == null or not is_instance_valid(s):
			continue
		if "player_commandable" in s and s.player_commandable:
			continue
		if not s.has_method("get_center") or not s.has_method("get_orderable_soldiers"):
			continue
		out.append(s)
	return out


func _alive_in(squad) -> int:
	var n := 0
	for mm in squad.get_orderable_soldiers():
		if mm != null and is_instance_valid(mm) and ("alive" in mm) and mm.alive:
			n += 1
	return n


func _cores(level: Node) -> Array:
	var out: Array = []
	for n in _all(level):
		var s = n.get_script()
		if s != null and String(s.resource_path).ends_with("holdable_core.gd"):
			out.append(n)
	return out


func _player(world):
	for p in get_nodes_in_group("player"):
		if p != null and is_instance_valid(p) and p is Node3D:
			return p
	return world.get("player") if world != null else null


func _find(level: Node, named: String) -> Node:
	for n in _all(level):
		if String(n.name) == named:
			return n
	return null


func _all(n: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out
