extends SceneTree

# ─────────────────────────────────────────────
# DOES SLOW-TICK LOD GET A FROZEN SQUAD TO ITS OBJECTIVE?
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_slow_tick.gd
#
# THE BUG IT IS ABOUT. Distance culling freezes any hostile more than
# activation_distance (75 m) from the player, and the freeze stops the whole
# brain — so a squad ordered across the map accepts the order and never walks.
# Measured 2026-10-17 with tools/test_core_retake_live.gd: a counter-attack
# ordered to a core from 32 m was still at 34.2 / 31.6 / 31.0 m after seventy
# seconds. That suite now parks the player at 30 m to get a green run, which is
# avoiding the bug rather than testing past it.
#
# THE PROTOTYPE. AIManager._poll_frozen already sweeps every frozen robot about
# four times a second. With AIManager.slow_tick_advance up it also walks a
# robot that has orders along its path (Enemy.cull_coarse_step) without
# thawing it and without a brain.
#
# A/B IN ONE PROCESS, AND IN THIS ORDER. The same squad is measured frozen with
# the flag DOWN, then with it UP. Loading twice would compare two different
# spawns on a machine that drifts — bench_freeze_ab.gd is swinging 20 ms
# between identical runs today, so nothing here relies on comparing across
# processes. The order matters too: OFF first establishes that the squad really
# is stuck before the flag is asked to unstick it.
#
# IT IS A PROBE, NOT A GATE. It reports metres and leaves the judgement to a
# human; it writes no save (cm.autosave = false).
# ─────────────────────────────────────────────

const SITE := &"hfw_1_fort"
## The distance that makes the point. Beyond activation_distance (75 m), so the
## whole map is culled and the squad is genuinely frozen — which is exactly the
## case the shipped suite had to back away from.
const PLAYER_AWAY := 400.0
## Frames per phase. ~17 s of simulation at 60 fps, long enough for a squad to
## cross tens of metres and short enough to run twice without a long wait.
const PHASE_FRAMES := 1000


func _init() -> void:
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame

	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = true
	master.show_mission_briefing = false
	var cm: CampaignManager = master.find_child("CampaignManager", true, false)
	cm.autosave = false
	root.add_child(master)
	for _i in 90:
		await physics_frame
	var world: World = master._world()
	cm.reset_campaign()

	var m = cm.get_mission(SITE)
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
	for _i in 240:
		await physics_frame

	var level = world.current_level
	var mgr: AIManager = _find_mgr(master)
	if mgr == null:
		print("FAIL  no AIManager, so there is no sweep to put this on")
		quit(1)
		return
	mgr.slow_tick_advance = false

	# A core with a hostile squad close enough to be called, same rule
	# CoreRetakers uses — otherwise sending nobody is correct and this measures
	# a feature declining to fire.
	var bunker = _find(level, "SiteBunker")
	var core = null
	var best: float = 1e9
	for c in _cores(level):
		if bunker != null and bunker.is_ancestor_of(c):
			continue
		var at: Vector3 = _point_of(c)
		for s in _hostile_squads():
			var d: float = (s.get_center() as Vector3).distance_to(at)
			if d < best and d <= 120.0:
				best = d
				core = c
	if core == null:
		print("FAIL  no core with a squad in call range")
		quit(1)
		return

	var home: Vector3 = _point_of(core)
	var player = _player()
	player.global_position = home + Vector3(PLAYER_AWAY, 0.0, 0.0)

	print("")
	print("SLOW-TICK LOD — %s, player parked %.0f m away (activation_distance is 75)"
		% [core.get_parent().name, PLAYER_AWAY])
	print("")

	core.start_held()
	for _i in 30:
		await physics_frame

	var sent = _sent_squad(home)
	if sent == null:
		print("FAIL  nobody was ordered to the core, so there is nothing to measure")
		quit(1)
		return
	print("  a squad was ordered to it from %.0f m" % best)
	print("  frozen members at the order: %d of %d"
		% [_frozen_in(sent), _alive_in(sent)])
	print("")

	var start: float = _nearest(sent, home)
	await _phase("OFF  (as shipped)", mgr, false, sent, home, start)
	var mid: float = _nearest(sent, home)
	await _phase("ON   (slow-tick)  ", mgr, true, sent, home, mid)

	print("")
	print("PROBE DONE — the numbers above are the finding; nothing is asserted.")
	quit(0)


func _phase(label: String, mgr, on: bool, squad, home: Vector3, from: float) -> void:
	mgr.slow_tick_advance = on
	for _i in PHASE_FRAMES:
		await physics_frame
	var now: float = _nearest(squad, home)
	print("  %s  nearest member %6.1f m -> %6.1f m   (closed %5.1f m in %d frames, %d still frozen)"
		% [label, from, now, from - now, PHASE_FRAMES, _frozen_in(squad)])


# ── helpers ──────────────────────────────────────────────────────────────────

func _nearest(squad, at: Vector3) -> float:
	var best: float = 1e9
	for mm in squad.get_orderable_soldiers():
		if mm == null or not is_instance_valid(mm):
			continue
		if ("alive" in mm) and not mm.alive:
			continue
		best = minf(best, (mm as Node3D).global_position.distance_to(at))
	return best


func _frozen_in(squad) -> int:
	var n := 0
	for mm in squad.get_orderable_soldiers():
		if mm != null and is_instance_valid(mm) and ("cull_frozen" in mm) and mm.cull_frozen:
			n += 1
	return n


func _alive_in(squad) -> int:
	var n := 0
	for mm in squad.get_orderable_soldiers():
		if mm != null and is_instance_valid(mm) and ("alive" in mm) and mm.alive:
			n += 1
	return n


func _sent_squad(home: Vector3):
	for s in _hostile_squads():
		var dest = s.get("objective_position")
		if dest != null and (dest as Vector3).distance_to(home) <= 7.0:
			return s
	return null


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


func _point_of(core) -> Vector3:
	if "interactible" in core and core.interactible != null \
			and is_instance_valid(core.interactible):
		return (core.interactible as Node3D).global_position
	return (core as Node3D).global_position


func _cores(level: Node) -> Array:
	var out: Array = []
	for n in _all(level):
		var s = n.get_script()
		if s != null and String(s.resource_path).ends_with("holdable_core.gd"):
			out.append(n)
	return out


func _player():
	for p in get_nodes_in_group("player"):
		if p != null and is_instance_valid(p) and p is Node3D:
			return p
	return null


func _find_mgr(n: Node) -> AIManager:
	if n is AIManager:
		return n as AIManager
	for c in n.get_children():
		var f := _find_mgr(c)
		if f != null:
			return f
	return null


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
