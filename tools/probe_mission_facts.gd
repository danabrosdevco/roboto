extends SceneTree
# REPORTS: prints the table Reference/Missions and objectives.md asserts, and asserts nothing

# ─────────────────────────────────────────────
# WHAT EACH LIVE MISSION ACTUALLY ASKS OF YOU, AND WHERE EACH LINE CAME FROM.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_mission_facts.gd
#   ... -- --static      the packed pass only, seconds rather than minutes
#
# The vault note `Reference/Missions and objectives.md` is written from this
# and names it in its `verified-by`. Re-run it before trusting the note.
#
# TWO PASSES, BECAUSE THERE ARE TWO ROUTES AND ONE FILE SHOWS NEITHER.
#
#   STATIC   instantiates each live mission's level WITHOUT adding it to the
#            tree, so no _ready runs: this is what is AUTHORED. Every objective
#            the level could ever need, its id, its gating flags, and which
#            ones `active_objectives` keeps. Also every way off the map.
#
#   RUNTIME  boots the real Master and deploys each mission the way
#            test_arena_assault.gd does, then reads ObjectiveTracker — the one
#            list the HUD and the extraction gate actually use. Anything in it
#            that was not in the packed scene was RAISED AT LOAD, and is
#            marked so. That is SiteSlice's bunker line today.
#
# The level file is the decoy here (see `Where the truth lives`): it holds
# objectives the mission frees at load, and it does not hold the ones a slice
# builds after the prune has run. Only the runtime column is the game.
#
# Writes nothing. Never the player's save — autosave is off before Master is
# in the tree, the same as every suite.
# ─────────────────────────────────────────────

const WORLD := "res://Env/world.tscn"
const MISSION_DIR := "res://Campaign/missions/"
const SLICE_BASE := "res://Env/world_objects/site_slice.gd"
## How long a deployed level settles before the tracker is read. SiteSlice
## refreshes the tracker deferred, and HoldableCore's terminal watchdog runs for
## six seconds; the objective LIST is settled well inside this.
const SETTLE_FRAMES := 60

var _static_only := false
## level path -> {objectives, exits, slice}
var _authored: Dictionary = {}


func _init() -> void:
	Engine.max_fps = 60   # a --script run has no frame cap and starves physics
	_static_only = OS.get_cmdline_user_args().has("--static")

	var live := _live_missions()
	if live.is_empty():
		push_warning("probe_mission_facts: no `missions` array found in %s, so there is nothing to report." % WORLD)
		quit(1)
		return

	_report_roster(live)
	print("")
	print("══ STATIC — what each level AUTHORS, and what the mission keeps ══")
	for m in live:
		_report_static(m)

	if _static_only:
		print("")
		print("(--static: runtime pass skipped — the RAISED column is not shown)")
		quit(0)
		return

	print("")
	print("══ RUNTIME — what ObjectiveTracker holds after a real deploy ══")
	await _report_runtime(live)
	quit(0)


# ── the roster ───────────────────────────────────────────────────────────────

## THE LIVE LIST IS world.tscn's, NOT THE FOLDER. Read off the packed scene's
## state rather than by booting it, so the static pass needs no campaign.
func _live_missions() -> Array:
	var packed := load(WORLD) as PackedScene
	if packed == null:
		push_warning("probe_mission_facts: %s did not load." % WORLD)
		return []
	var st := packed.get_state()
	for i in st.get_node_count():
		for p in st.get_node_property_count(i):
			if st.get_node_property_name(i, p) == &"missions":
				var out: Array = []
				for m in st.get_node_property_value(i, p):
					if m != null:
						out.append(m)
				return out
	return []


func _report_roster(live: Array) -> void:
	var live_paths := {}
	for m in live:
		live_paths[m.resource_path] = true
	print("══ MISSIONS — %d live in %s ══" % [live.size(), WORLD])
	print("%-3s %-22s %-6s %-5s %-4s %-3s %-26s %s" % ["#", "id", "kind", "squad", "rep", "objs", "requires", "unlocks (retired)"])
	var i := 0
	for m in live:
		var kind := "sim" if m.sim else ("DEF" if m.defence else "attack")
		print("%-3d %-22s %-6s %-5s %-4s %-4d %-26s %s" % [i, m.id, kind,
			str(m.squad_size), "yes" if m.repeatable else "-",
			m.active_objectives.size(), _ids(m.requires), _ids(m.unlocks)])
		i += 1
	print("FINAL (clearing it sets campaign_won): %s" % live.back().id)

	# On disk and not in the campaign. The top folder only: appendix/ is the
	# archive and says so by where it lives.
	var stray: Array = []
	var dir := DirAccess.open(MISSION_DIR)
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".tres") and not live_paths.has(MISSION_DIR + f):
				stray.append(f)
	print("ON DISK, NOT LIVE: %s" % (", ".join(stray) if not stray.is_empty() else "(none)"))

	# Every `requires` must name a live mission, or the op can never open.
	for m in live:
		for req in m.requires:
			var found := false
			for n in live:
				if n.id == req:
					found = true
			if not found:
				print("  !! %s requires '%s', which is not a live mission — it can never open" % [m.id, req])


# ── static ───────────────────────────────────────────────────────────────────

func _report_static(m) -> void:
	print("")
	if m.level_scene == null:
		print("%s  — NO level_scene" % m.id)
		return
	var facts := _authored_facts(m.level_scene)
	var asked: Array = m.active_objectives
	print("%s  → %s%s" % [m.id, m.level_scene.resource_path.get_file(),
		"  [active_objectives EMPTY: every authored objective stays]" if asked.is_empty() else ""])
	if facts.slice != "":
		print("  slice: %s — raises BunkerObjective 'HOLD THE BUNKER' (no id) at load; cores on %s" % [
			facts.slice, ", ".join(facts.slice_cores)])

	var present := {}
	for o in facts.objectives:
		var keep := "KEEP"
		if o.id == "":
			keep = "BLANK"   # exempt from the prune: runs in every operation
		elif not asked.is_empty() and not asked.has(StringName(o.id)):
			keep = "freed"
		present[o.id] = true
		var flags: Array = []
		if o.optional: flags.append("optional")
		if not o.starts_active: flags.append("starts_inactive")
		if o.is_extraction: flags.append("EXTRACTION")
		if not o.prereqs.is_empty(): flags.append("after " + ",".join(o.prereqs))
		if o.cored: flags.append("core-driven")
		if o.res > 0 or o.cpu > 0: flags.append("pays %dres/%dcpu" % [o.res, o.cpu])
		print("  %-5s %-22s %-20s %-26s %s" % [keep, o.id if o.id != "" else "(none)", o.cls,
			o.label, " ".join(flags)])
	for want in asked:
		if not present.has(String(want)):
			print("  !! asks for '%s', which the level does not author — %s" % [want,
				"the slice raises no ids, so nothing will" if facts.slice != "" else "it will never appear"])

	for e in facts.exits:
		# LevelExit._ready frees a gate whose paired objective was pruned, and
		# closes one whose path resolves to nothing.
		var fate := ""
		if e.pairs != "":
			if e.paired_id == null:
				fate = "  → CLOSED: pairs_with resolves to nothing"
			elif e.paired_id != "" and not asked.is_empty() and not asked.has(StringName(e.paired_id)):
				fate = "  → FREED with its objective"
		print("  exit  %-22s objectives_gate=%s arming=%s%s%s" % [e.name,
			"yes" if e.req_obj else "no", "yes" if e.req_arm else "no",
			"  pairs_with=" + (e.paired_id if e.paired_id != null else e.pairs) if e.pairs != "" else "",
			fate])


## The packed level, instantiated and never added: every node as authored,
## nothing pruned, nothing raised. Cached per level — six levels carry two ops.
func _authored_facts(scene: PackedScene) -> Dictionary:
	var key := scene.resource_path
	if _authored.has(key):
		return _authored[key]
	var level := scene.instantiate()
	var facts := {"objectives": [], "exits": [], "slice": "", "slice_cores": [], "paths": {}}
	_walk(level, level, facts)
	# A capture point named in a slice's cores_by_node is driven by a
	# HoldableCore at runtime — the authored objective stays, the terminal does not.
	for o in facts.objectives:
		o["cored"] = facts.slice_cores.has(o.name)
	level.free()
	_authored[key] = facts
	return facts


func _walk(n: Node, level: Node, facts: Dictionary) -> void:
	if n is MissionObjective:
		var o := n as MissionObjective
		var prereqs: Array = []
		for p in o.prerequisites:
			if p != null:
				prereqs.append(String(p.id) if p.id != &"" else String(p.name))
		var path := String(level.get_path_to(n))
		facts.objectives.append({
			"id": String(o.id), "name": String(o.name), "path": path,
			"cls": _class_of(n), "label": o.label(),
			"optional": o.optional, "starts_active": o.starts_active,
			"is_extraction": o.is_extraction, "prereqs": prereqs,
			"res": o.reward_resources, "cpu": o.compute_reward,
		})
		facts.paths[path] = true
	elif n is LevelExit:
		var e := n as LevelExit
		if not e.is_departure:
			# Resolved here, relative to the exit, the way LevelExit._ready does.
			var paired = null
			if not e.pairs_with_objective.is_empty():
				var p := e.get_node_or_null(e.pairs_with_objective)
				if p is MissionObjective:
					paired = String((p as MissionObjective).id)
			facts.exits.append({"name": String(n.name),
				"req_obj": e.requires_objectives_complete, "req_arm": e.requires_arming,
				"pairs": String(e.pairs_with_objective), "paired_id": paired})
	if _is_slice(n):
		facts.slice = (n.get_script() as Script).resource_path.get_file()
		for k in n.get("cores_by_node"):
			facts.slice_cores.append(String(k))
	for c in n.get_children():
		_walk(c, level, facts)


func _is_slice(n: Node) -> bool:
	var s: Script = n.get_script()
	while s != null:
		if s.resource_path == SLICE_BASE:
			return true
		s = s.get_base_script()
	return false


## The objective's class as the code names it. BunkerObjective has no
## class_name (it is loaded by path, so a level never depends on an editor
## rescan), so the nearest named class is not the honest answer — the file is.
func _class_of(n: Node) -> String:
	var s: Script = n.get_script()
	if s == null:
		return n.get_class()
	if s.get_global_name() != &"":
		return String(s.get_global_name())
	return s.resource_path.get_file().get_basename()


# ── runtime ──────────────────────────────────────────────────────────────────

func _report_runtime(live: Array) -> void:
	Settings.path = "user://settings_probe_mission_facts.json"
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

	for m in live:
		await _deploy(cm, world, m)
		await _report_deployed(cm, world, m)

	# OUT OF THE TREE BEFORE quit(). It DOES NOT cure the exit: the run still
	# segfaults in cleanup (exit 139) after every line has printed, with or
	# without this. Left in because it is harmless; the exit code of a probe is
	# not its contract. The table is complete once basin_2_defend has printed.
	root.remove_child(master)
	master.queue_free()
	for _i in 3:
		await process_frame


## The direct-launch path, as test_arena_assault.gd does it: debug_mission is
## what on_level_loaded adopts, and in_mission is cleared first or the second
## deploy runs extract() on the first. load_next_level calls on_level_loaded
## itself — calling it again would field the enemy force twice.
func _deploy(cm, world, m) -> void:
	cm.in_mission = false
	cm.debug_mission = m
	cm.select_mission(m.id)
	await world.load_next_level(m.level_scene)
	for _i in SETTLE_FRAMES:
		await physics_frame


func _report_deployed(cm, world, m) -> void:
	var level: Node = world.current_level
	var facts := _authored_facts(m.level_scene)
	print("")
	print("%s" % m.id)
	var raised := 0
	for o in cm.objectives.objectives():
		if o == null or not is_instance_valid(o):
			continue
		var path := String(level.get_path_to(o))
		var origin := "authored" if facts.paths.has(path) else "RAISED"
		if origin == "RAISED":
			raised += 1
		var state := "done" if o.completed else ("active" if o.active else "waiting")
		print("  %-8s %-22s %-20s %-26s %-7s %s%s" % [origin, o.id if o.id != &"" else "(none)",
			_class_of(o), o.label(), state,
			"EXTRACTION" if o.is_extraction else ("optional" if o.optional else "required"),
			"" if origin == "authored" else "   @ " + path])
	var req: Array = cm.objectives.required_progress()
	print("  required %d/%d · raised at load: %d" % [req[0], req[1], raised])

	# THE SLICE MEETS THE PRUNE. SiteSlice seats a core on every node named in
	# cores_by_node without asking whether the mission kept that objective —
	# and on a capture-point prefab the objective IS the host, so a pruned one
	# takes its core with it. SiteOperation still has it in `cores`, and
	# held_cores() is size() minus the valid hostile ones, so a freed core
	# counts as HELD. This prints what the operation believes against what is
	# actually standing.
	for op in _of_script(level, "site_operation.gd"):
		var valid := 0
		for c in op.cores:
			if c != null and is_instance_valid(c):
				valid += 1
		print("  site  cores listed=%d standing=%d · held_cores()=%d hostile_cores()=%d%s" % [
			op.cores.size(), valid, op.held_cores(), op.hostile_cores(),
			"   !! %d freed core(s) count as HELD" % (op.cores.size() - valid) if valid < op.cores.size() else ""])

	# Every way off the map that survived the load.
	var gates := 0
	for e in _exits_under(level, LevelExit):
		if e.is_queued_for_deletion() or e.is_departure:
			continue
		gates += 1
		print("  gate  %-22s objectives_gate=%s arming=%s" % [e.name,
			"yes" if e.requires_objectives_complete else "no",
			"yes" if e.requires_arming else "no"])
	if gates == 0:
		print("  gate  (none) — no LevelExit survived the load")

	# WHAT WINNING AT THE BUNKER PAYS, measured rather than read.
	#
	# open_way_out() is what SiteSlice calls on operation_complete. It ticks
	# every non-extraction objective — and HoldableCore._guard_authored un-ticks
	# any core-driven one whose core is not yours, the same frame. What is
	# left completed is what extract() pays, win or lose. Run LAST for this
	# mission: it changes the objectives, and the next deploy rebuilds them.
	if not _of_script(level, "site_operation.gd").is_empty():
		var said: String = cm.open_way_out()
		await process_frame
		var unearned: Array = []
		for o in cm.objectives.objectives():
			if o != null and is_instance_valid(o) and o.completed and o.reward_resources > 0 \
					and _of_script(o, "holdable_core.gd").is_empty():
				unearned.append("%s %d" % [o.id if o.id != &"" else "(none)", o.reward_resources])
		var cpu := 0
		for e in cm.objectives.earned_compute():
			cpu += int(e["compute"])
		print("  win   open_way_out → pays %d res / %d cpu, cores as deployed · %s" % [
			cm.objectives.earned_objective_rewards(), cpu, said])
		if not unearned.is_empty():
			print("        ticked, not done: %s" % ", ".join(unearned))


## LevelExit has no group of its own (the `levelexit` group is the prefab's,
## not the class's), so walk for the class.
func _exits_under(n: Node, cls) -> Array:
	var out: Array = []
	if is_instance_of(n, cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_exits_under(c, cls))
	return out


## Nodes under `n` running a script whose file is `file` — by path, so this
## does not depend on a class_name the editor may not have indexed.
func _of_script(n: Node, file: String) -> Array:
	var out: Array = []
	var s: Script = n.get_script()
	if s != null and s.resource_path.get_file() == file:
		out.append(n)
	for c in n.get_children():
		out.append_array(_of_script(c, file))
	return out


func _ids(a: Array) -> String:
	if a.is_empty():
		return "-"
	var s: Array = []
	for x in a:
		s.append(String(x))
	return ",".join(s)
