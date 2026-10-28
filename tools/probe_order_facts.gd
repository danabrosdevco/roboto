extends SceneTree
# REPORTS: prints the table Reference/Orders and squad AI.md asserts, and says PASS/FAIL on its last line. NOT BUCKETed, and deliberately not a suite: booting master.tscn under --script segfaults the engine in cleanup at exit, so this tool CANNOT report through an exit code. Read the last line.

# ─────────────────────────────────────────────
# THE COMMAND CHAIN, END TO END — what the player can say, what a squad does
# with it, and which of the seven objectives anything can actually reach.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_order_facts.gd -- --no-save
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_order_facts.gd -- --no-save hfw_1_fort
#
# The vault note `Reference/Orders and squad AI.md` is written from this and
# names it in its `verified-by`. Re-run it before trusting the note.
#
# THE POINT OF IT. There are TWO order vocabularies and they are different
# sizes: SquadCommander.Verb has four values and Squad.SquadObjective has
# seven. Which of the seven a player can actually cause, which only a mission
# can cause, and which nothing causes at all, is not answerable from either
# enum — it is a property of the CALL SITES. So §2 scans every .gd in the
# project for objective writes rather than trusting a list in this file, which
# would drift the first time somebody added one.
#
# And §4 does the thing no static scan can: it issues all four verbs through
# the real SquadCommander, at a real deployed squad, and reads back what the
# objective became. That is the only honest answer to "what does this verb do",
# because the commander's match statement has no case for one of them.
#
# THE VERDICT IS THE LAST PRINTED LINE, NOT THE EXIT CODE, and that is not a
# shortcut. Any tool that boots `master.tscn` under `--script` segfaults the
# engine in cleanup AFTER quit() — `tools/probe_home_base.gd` does exactly the
# same thing, measured 2026-10-23: 332 resources still in use, ObjectDB
# instances leaked, exit 139 on a run whose every check passed. Freeing the
# Master before quitting does not help. So this is a `probe_`, the house rule
# that a suite's contract is its exit code stands, and a tool that cannot keep
# that contract must not wear the `test_` prefix and pretend to.
#
# NOTHING IS WRITTEN. autosave off, Settings on a probe path, `-- --no-save`
# (a hard gate in CampaignState.save() and SaveSlots), and no scene is saved.
# ─────────────────────────────────────────────

const DEFAULT_MISSION := &"basin_1_anchor"
## Walked for objective write-sites in §2. `tools/` is left out on purpose: a
## suite setting an objective by hand is not a route the game has.
const SCAN_ROOTS := ["res://Campaign/", "res://Character/", "res://Managers/", "res://Env/"]
## Other lanes' worktrees live here and their stale copies disagree with the
## live files. See the note in the vault's Traps.
const SKIP_DIRS := [".claude", ".godot", "addons"]

const OBJECTIVE_NAMES := ["NONE", "ADVANCE", "DEFEND", "WITHDRAW", "ATTACK", "FOLLOW", "PATROL"]
const VERB_NAMES := ["ADVANCE", "FOLLOW", "CONTACT", "ATTACK"]

## What the note claims each verb leaves the squad on. `""` means "the verb
## returns before any objective is set" — which is a claim too, and a louder
## one. Checked in §4; a change here is a change to the document.
const CLAIMED := {
	"ADVANCE": "DEFEND",
	"FOLLOW":  "FOLLOW",
	"CONTACT": "",
	"ATTACK":  "",
}

var _mission: StringName = DEFAULT_MISSION
var _cm = null
var _world = null
var _fail: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# PACE THE LOOP — a --script run has no frame cap, so _process spins flat
	# out and starves physics, and every `await physics_frame` below takes far
	# longer in wall clock than the 1/60 s it is written as.
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a != "--no-save" and not a.begins_with("--"):
			_mission = StringName(a)

	# EVERY FILE SCAN BEFORE THE DEPLOY, and nothing after it but the quit.
	# Walking a few hundred .gd and .tscn files takes long enough that doing it
	# with a live mission in the tree — sixty robots, a navmesh mid-sync —
	# segfaulted the engine in the middle of printing. The static half needs no
	# tree, so it is simply done first.
	_report_vocabularies()
	var writes := _report_write_sites()
	await _report_authored_objectives()
	_report_unreachable(writes)

	await _boot()
	_report_squads()
	await _report_verbs()
	_report_member_layer()
	_report_leashes()
	_report_equipment()

	print("")
	if _fail == 0:
		print("ORDERS  the four verbs map as Reference/Orders and squad AI.md says")
		quit(0)
	else:
		print("ORDERS  %d claim(s) in the note no longer hold — see FAIL above" % _fail)
		quit(1)


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fail += 1


# ─────────────────────────────────────────────
# §1 — the two vocabularies, read off the classes rather than typed out here
# ─────────────────────────────────────────────
func _report_vocabularies() -> void:
	print("\n== §1 THE TWO VOCABULARIES")
	print("  SquadCommander.Verb      %d: %s" % [
		SquadCommander.Verb.size(), ", ".join(SquadCommander.Verb.keys())])
	print("  Squad.SquadObjective     %d: %s" % [
		Squad.SquadObjective.size(), ", ".join(Squad.SquadObjective.keys())])
	print("  VERB_LABELS (the HUD's)  %s" % str(SquadCommander.VERB_LABELS.values()))
	# The enums are append-only (values are stored as ints in .tscn/.tres), so
	# the index matters as much as the name. Print both.
	var pairs: Array = []
	for k in Squad.SquadObjective.keys():
		pairs.append("%s=%d" % [k, Squad.SquadObjective[k]])
	print("  objective ints           %s" % ", ".join(pairs))
	_check("the vocabularies are still different sizes, which is the whole domain",
		SquadCommander.Verb.size() != Squad.SquadObjective.size(),
		"%d verbs / %d objectives" % [SquadCommander.Verb.size(), Squad.SquadObjective.size()])


# ─────────────────────────────────────────────
# §2 — WHO SETS EACH OBJECTIVE, scanned, not listed
#
# Returns {objective_name: [site, ...]}. A site is "<file>:<line>  <text>".
# ─────────────────────────────────────────────
func _report_write_sites() -> Dictionary:
	print("\n== §2 WHO SETS EACH OBJECTIVE (every .gd outside tools/, scanned)")
	var out: Dictionary = {}
	for n in OBJECTIVE_NAMES:
		out[n] = []
	var files: Array = []
	for scan_root in SCAN_ROOTS:
		_collect(scan_root, ".gd", files)
	# set_patrol() is the only way into PATROL and it names no objective, so it
	# is matched on its own rather than by the objective token.
	var patrol_calls: Array = []
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			continue
		var lines := text.split("\n")
		for i in lines.size():
			var line: String = lines[i]
			var trimmed := line.strip_edges()
			if trimmed.begins_with("#"):
				continue   # a comment naming an objective is not a write
			if "set_patrol(" in line and not "func set_patrol" in line:
				patrol_calls.append("%s:%d  %s" % [path.replace("res://", ""), i + 1, trimmed])
			for name in OBJECTIVE_NAMES:
				var token := "SquadObjective.%s" % name
				if not token in line:
					continue
				if not _is_write(line, token):
					continue
				out[name].append("%s:%d  %s" % [path.replace("res://", ""), i + 1, trimmed])
	for name in OBJECTIVE_NAMES:
		var sites: Array = out[name]
		if name == "PATROL":
			sites = sites + patrol_calls
			out[name] = sites
		print("  %-9s %d write site(s)%s" % [name, sites.size(), "" if sites.size() > 0 else "   ← NOBODY SETS THIS"])
		for s in sites:
			print("      %s" % s)
	return out


## Is this line a write of the objective, as opposed to a comparison? The three
## shapes that set one are set_objective(...), receive_player_order(...) and a
## bare `objective =`; `==`, `!=` and `default_objective`/`target_objective`
## are reads or are a different field.
func _is_write(line: String, token: String) -> bool:
	if "set_objective(" in line and not "func set_objective" in line:
		return true
	if "receive_player_order(" in line and not "func receive_player_order" in line:
		return true
	var at := line.find(token)
	var before := line.substr(0, at).strip_edges()
	if not before.ends_with("="):
		return false
	if before.ends_with("==") or before.ends_with("!=") or before.ends_with(">=") or before.ends_with("<="):
		return false
	return not ("default_objective" in before or "target_objective" in before)


# ─────────────────────────────────────────────
# §3 of the second route: the one objective a LEVEL can author.
#
# Squad.default_objective is read in exactly one place — Squad._ready() — and
# only when target_objective is non-null. So the authored route is really the
# PAIR, and a default_objective with no target_objective is inert. Both halves
# are counted straight out of the scene text.
# ─────────────────────────────────────────────
func _report_authored_objectives() -> void:
	print("\n== §2b THE AUTHORED ROUTE (Squad.default_objective + target_objective, from the scenes)")
	var scenes: Array = []
	for scan_root in ["res://maps/", "res://Env/", "res://Managers/", "res://Campaign/"]:
		_collect(scan_root, ".tscn", scenes)
	var defaults: Array = []
	var targets: Array = []
	for path in scenes:
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			continue
		var lines := text.split("\n")
		for i in lines.size():
			var line: String = lines[i]
			if line.begins_with("default_objective = "):
				var v := int(line.trim_prefix("default_objective = "))
				defaults.append("%s:%d  default_objective = %d (%s)" % [
					path.replace("res://", ""), i + 1, v,
					OBJECTIVE_NAMES[v] if v >= 0 and v < OBJECTIVE_NAMES.size() else "?"])
			if line.begins_with("target_objective = "):
				targets.append("%s:%d  %s" % [path.replace("res://", ""), i + 1, line])
	print("  default_objective authored on %d node(s):" % defaults.size())
	for d in defaults:
		print("      %s" % d)
	print("  target_objective authored on %d node(s)%s" % [
		targets.size(), "" if targets.size() > 0 else "   ← the gate on default_objective, set NOWHERE"])
	for t in targets:
		print("      %s" % t)
	await _check_default_objective_is_inert(defaults.size())


# A LIVE SQUAD, NOT A SCAN (OA4).
#
# This used to be _check(…, true, …) — a verdict that could not fail, printing
# the scan counts beside it. It read as a measurement and was a label, and a
# label cannot tell you when the thing it describes changes.
#
# It is written as "still inert" rather than "now applied" ON PURPOSE. Applying
# it was tried on 2026-10-28 and taken back out: the script default is ADVANCE
# and squad.tscn does not override it, so every ad-hoc squad got a move order
# two frames in (test_reclaimer went red on four checks), and SquadSpawnPoint's
# own default is FOLLOW, so switching it on makes every mission squad fall in
# on the player — which is Backlog OA6, a design call nobody has made. The
# second squad here is the trap that comes with the fix whenever it is taken: a
# reserve is ORDERED to NONE, so a guard on `objective` reads it as unordered.
func _check_default_objective_is_inert(authored: int) -> void:
	var held := Squad.new()
	held.default_objective = Squad.SquadObjective.DEFEND
	root.add_child(held)
	var reserve := Squad.new()
	root.add_child(reserve)
	reserve.set_objective(Squad.SquadObjective.NONE, Vector3.ZERO, true)
	for _i in 6:
		await process_frame
	_check("an authored default_objective with no target_objective is still DROPPED",
		held.objective == Squad.SquadObjective.NONE,
		"objective %s, with %d authored in the project and 0 targets" % [
			OBJECTIVE_NAMES[int(held.objective)], authored])
	_check("...and `objective` cannot tell that squad from an ordered reserve — use _ordered",
		reserve.objective == held.objective and reserve._ordered and not held._ordered,
		"reserve objective %s, _ordered %s / %s" % [
			OBJECTIVE_NAMES[int(reserve.objective)], reserve._ordered, held._ordered])
	held.queue_free()
	reserve.queue_free()


func _collect(dir_path: String, suffix: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with(".") and not SKIP_DIRS.has(entry):
				_collect(dir_path.path_join(entry), suffix, out)
		elif entry.ends_with(suffix):
			out.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()


# ─────────────────────────────────────────────
# A REAL DEPLOY. Nothing below this line is answerable from the files: a
# squad's objective is set by a spawner reading a posture off a .tres against a
# marker in a level, and all three have to be present for the answer to be the
# game's answer.
# ─────────────────────────────────────────────
func _boot() -> void:
	print("\n== §3 A REAL DEPLOY — '%s'" % String(_mission))
	var master: Node = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = true
	master.show_mission_briefing = false
	_cm = master.find_child("CampaignManager", true, false)
	# NEVER THE PLAYER'S SAVE.
	_cm.autosave = false
	root.add_child(master)
	for _i in 90:
		await physics_frame
	_world = master._world()
	_cm.reset_campaign()
	var m = _cm.get_mission(_mission)
	if m == null:
		printerr("probe_order_facts: no mission '%s'" % String(_mission))
		quit(1)
		return
	_cm.in_mission = false
	_cm.debug_mission = m
	_cm.select_mission(_mission)
	await _world.load_next_level(m.level_scene)
	# NO SECOND on_level_loaded(). World.load_next_level() ends by calling it
	# itself, so an explicit call here redeploys BOTH spawners in the same frame
	# as the first deploy — and tearing a robot down that few frames after it
	# was stood up leaves the engine something it only trips over in final
	# cleanup: every assertion printed PASS and the run still handed the shell
	# exit 139. H10, root-caused 2026-10-24: dropping this one line is the whole
	# fix. A 10-frame gap before the second call also cures it; one or two
	# frames do not. The call was redundant either way.
	#
	# Long enough for the force spawner to build every squad, for Squad._ready
	# to connect its members, and for _apply_posture to have run — it is
	# deliberately deferred until the squad is in the tree, because set_patrol
	# and set_objective both read member positions through get_center().
	for _i in 150:
		await physics_frame


func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _obj_name(squad: Squad) -> String:
	var v := int(squad.objective)
	return OBJECTIVE_NAMES[v] if v >= 0 and v < OBJECTIVE_NAMES.size() else "?%d" % v


func _squads() -> Array:
	var out: Array = []
	for s in get_nodes_in_group("squads"):
		if s is Squad and is_instance_valid(s):
			out.append(s)
	return out


# ─────────────────────────────────────────────
# §3 — EVERY SQUAD ON THE MAP, and the objective each one is actually on
# ─────────────────────────────────────────────
func _report_squads() -> void:
	var squads := _squads()
	print("  %d squad(s) in the \"squads\" group" % squads.size())
	print("")
	print("  %-22s %-9s %-6s %-5s %-5s %-5s %-9s %s" % [
		"squad", "objective", "ctx", "cmd?", "auto?", "team", "members", "callsign"])
	print("  " + "─".repeat(92))
	var tally: Dictionary = {}
	for squad in squads:
		var obj := _obj_name(squad)
		tally[obj] = int(tally.get(obj, 0)) + 1
		print("  %-22s %-9s %-6s %-5s %-5s %-5s %-9s %s" % [
			squad.name.left(22),
			obj,
			"ENGAGED" if squad.context == Squad.SquadContext.ENGAGED else "idle",
			"yes" if squad.player_commandable else "no",
			"yes" if squad.autonomous else "no",
			String(squad.team) if squad.team != &"" else "—",
			"%d/%d" % [squad.get_living_members().size(), squad.squad_members.size()],
			squad.callsign])
	print("")
	print("  by objective: %s" % str(tally))
	# The commander's own list, which is a different filter: is_lost() out,
	# autonomous out, then player_commandable OR a non-hostile first member.
	var commander = _find(root, "SquadCommander")
	if commander != null:
		commander.refresh_squads()
		var names: Array = []
		for s in commander.commandable_squads:
			names.append("%s(%s)" % [s.callsign if s.callsign != "" else s.name, _obj_name(s)])
		print("  commandable:  %d — %s" % [commander.commandable_squads.size(), ", ".join(names)])
		print("  teams on G:   %d — has_teams() %s, selection_label() '%s'" % [
			commander.team_squads().size(), str(commander.has_teams()), commander.selection_label()])
	_check("the deploy produced at least one squad the player commands",
		commander != null and commander.commandable_squads.size() > 0)


# ─────────────────────────────────────────────
# §4 — THE FOUR VERBS, issued for real, and what the objective became
#
# This is the section the document hangs off. Two of the four verbs return from
# _issue_order before any objective is set; one maps to an objective with a
# DIFFERENT NAME; and one has no case in the match at all. None of that is
# visible in either enum.
# ─────────────────────────────────────────────
func _report_verbs() -> void:
	print("\n== §4 THE FOUR VERBS, ISSUED THROUGH THE REAL COMMANDER")
	var commander = _find(root, "SquadCommander")
	var player = _find(root, "Player")
	if commander == null or player == null:
		_check("(setup) there is a commander and a player to issue through", false)
		return
	commander.refresh_squads()
	var squad: Squad = commander.get_selected_squad()
	if squad == null:
		_check("(setup) a squad is selected to receive the orders", false)
		return
	print("  ordering %s (%d alive)" % [squad.callsign, squad.get_living_members().size()])
	print("")
	print("  %-9s %-11s %-11s %-9s %s" % ["verb", "before", "after", "ordered?", "what happened"])
	print("  " + "─".repeat(86))
	var mark: Vector3 = player.global_position + Vector3(0, 0, -12)
	for v in SquadCommander.Verb.size():
		var before := _obj_name(squad)
		var before_pos: Vector3 = squad.objective_position
		commander._issue_order(v, mark)
		for _i in 4:
			await physics_frame
		var after := _obj_name(squad)
		var note := "objective unchanged"
		if after != before:
			note = "set %s at %s" % [after, str(squad.objective_position.round())]
		elif not squad.objective_position.is_equal_approx(before_pos):
			note = "same objective, moved to %s" % str(squad.objective_position.round())
		print("  %-9s %-11s %-11s %-9s %s" % [
			VERB_NAMES[v], before, after, "yes" if squad.player_ordered else "no", note])
		var want: String = str(CLAIMED.get(VERB_NAMES[v], ""))
		if want == "":
			_check("%s sets no objective of its own" % VERB_NAMES[v], after == before,
				"became %s" % after)
		else:
			_check("%s leaves the squad on %s" % [VERB_NAMES[v], want], after == want,
				"became %s" % after)
	# ATTACK's objective is not dead — it is just not on a player verb. The
	# squad's own entry point takes it, which is the route the Laboratory uses.
	var target = null
	for s in _squads():
		if s.player_commandable or s.get_living_members().is_empty():
			continue
		target = s.get_living_members()[0]
		break
	if target != null:
		squad.receive_player_order(Squad.SquadObjective.ATTACK, target.global_position, target)
		for _i in 4:
			await physics_frame
		_check("...but receive_player_order(ATTACK, pos, target) does set it",
			_obj_name(squad) == "ATTACK", "became %s" % _obj_name(squad))
	else:
		print("  (no hostile body to aim an ATTACK at in this mission)")


# ─────────────────────────────────────────────
# §5 — WHAT REACHES A BODY
# ─────────────────────────────────────────────
func _report_member_layer() -> void:
	print("\n== §5 WHAT REACHES A BODY")
	var squad: Squad = null
	for s in _squads():
		if s.player_commandable and not s.get_living_members().is_empty():
			squad = s
			break
	if squad == null:
		print("  (no player squad with a living member)")
		return
	print("  there is NO per-member order field: a squad order is N calls to")
	print("  Soldier.order_move_to(pos, force, keep_target, think_delay), each at")
	print("  objective_position + that member's formation slot.")
	print("  order_stagger_seconds = %.3f  → member n waits n × that before its" % squad.order_stagger_seconds)
	print("    FIRST NAV QUERY, not before the order. Enemy.move_to sets")
	print("    _nav_think_timer = think_delay; movement_target and movement_state")
	print("    are set on the same frame for everyone.")
	print("  FORMATION_SPACING = %.1f m, widened to the widest frame in the line" % Squad.FORMATION_SPACING)
	print("")
	print("  %-22s %-9s %-11s %-9s %-7s %s" % [
		"member", "ai_state", "movement", "slot gap", "signal", "takes orders?"])
	print("  " + "─".repeat(86))
	for m in squad.squad_members:
		if m == null or not is_instance_valid(m):
			continue
		var slot: Vector3 = squad.objective_position + squad._formation_offset(m)
		print("  %-22s %-9s %-11s %-9s %-7s %s" % [
			m.name.left(22),
			Enemy.AIState.keys()[int(m.ai_state)],
			Enemy.MovementState.keys()[int(m.movement_state)],
			"%.1f m" % m.global_position.distance_to(slot),
			"%.2f" % m.signal_integrity,
			"yes" if m._can_receive_orders() else "NO (signal)"])
	print("")
	print("  the gate: Soldier.order_move_to refuses on AIState.DEAD, on COMBAT")
	print("    without force, and on _can_receive_orders() == false — which is")
	print("    SignalState CRITICAL or EKILL, checked EVEN FOR FORCED ORDERS.")
	print("  order_use_equipment does NOT check it: a jammed robot will not walk")
	print("    and will still throw.")


# ─────────────────────────────────────────────
# §6 — THE LEASHES, off the live instance (scene values beat script defaults)
# ─────────────────────────────────────────────
func _report_leashes() -> void:
	print("\n== §6 THE LEASH MODEL (read off a deployed Squad, not the script)")
	var squad: Squad = null
	for s in _squads():
		if s.player_commandable:
			squad = s
			break
	if squad == null:
		squad = _squads()[0] if not _squads().is_empty() else null
	if squad == null:
		print("  (no squad to read)")
		return
	print("  on %s:" % squad.name)
	for row in [
		["follow_combat_leash", squad.follow_combat_leash, "FOLLOW: slot + this"],
		["defend_combat_leash", squad.defend_combat_leash, "DEFEND: the post + this"],
		["aggressive_chase_radius", squad.aggressive_chase_radius, "a rusher with a LIVE target"],
		["leash_grace_multiplier", squad.leash_grace_multiplier, "× leash, if it can hit what it is shooting"],
		["recall_interval", squad.recall_interval, "s between forced orders to one body"],
		["defend_post_tolerance", squad.defend_post_tolerance, "m, 'arrived at the post'"],
		["follow_distance", squad.follow_distance, "m behind the leader"],
		["follow_slot_tolerance", squad.follow_slot_tolerance, "m, 'in the slot'"],
		["follow_repath_distance", squad.follow_repath_distance, "m a standing order may go stale"],
		["follow_snap_refresh", squad.follow_snap_refresh, "m before the navmesh snap is re-measured"],
		["follow_reissue_distance", squad.follow_reissue_distance, "m of leader drift"],
		["follow_reissue_interval", squad.follow_reissue_interval, "s floor on re-issues"],
		["patrol_arrive_distance", squad.patrol_arrive_distance, "m, 'reached the leg'"],
		["patrol_dwell", squad.patrol_dwell, "s at each point"],
		["assault_arrive_distance", squad.assault_arrive_distance, "m, 'arrived' on ADVANCE/ATTACK"],
		["order_stagger_seconds", squad.order_stagger_seconds, "s × member index, nav only"],
	]:
		print("    %-26s %-8s %s" % [row[0], "%.2f" % float(row[1]), row[2]])
	print("  CONTACT_GRACE %.1f s · DISENGAGE_CHECK_INTERVAL %.1f s · OBJECTIVE_NUDGE_INTERVAL %.1f s" % [
		Squad.CONTACT_GRACE, Squad.DISENGAGE_CHECK_INTERVAL, Squad.OBJECTIVE_NUDGE_INTERVAL])
	print("  AGGRESSIVE_PULL_INTERVAL %.2f s · EQUIPMENT_COVER_METRES %.1f · EQUIPMENT_SPREAD_METRES %.1f" % [
		Squad.AGGRESSIVE_PULL_INTERVAL, Squad.EQUIPMENT_COVER_METRES, Squad.EQUIPMENT_SPREAD_METRES])
	# _enforce_leash is reached from _tick_follow and _tick_defend only.
	# _tick_assault is the ADVANCE/ATTACK branch and deliberately runs no leash.
	#
	# This used to assert that `assault_combat_leash` was declared and read by
	# nothing, which was true and is the measurement that got it deleted
	# (OA5). The check now guards the deletion instead: the number must not
	# come back as an export without a reader, in a file whose own comment in
	# _tick_assault explains why it cannot have one.
	var src := FileAccess.get_file_as_string("res://Managers/AI/squad.gd")
	var declared := false
	for line in src.split("\n"):
		if "assault_combat_leash" in line and line.strip_edges().begins_with("@export"):
			declared = true
	# The detail prints on a pass too in this probe, so it says the STATE, not
	# the failure — "it is declared again" under a PASS read as a contradiction.
	_check("assault_combat_leash is gone, not re-exported (ADVANCE runs no leash)",
		not declared, "declared: %s" % ("yes" if declared else "no"))


# ─────────────────────────────────────────────
# §7 — THE EQUIPMENT ORDER, and every ground it is refused on
# ─────────────────────────────────────────────
func _report_equipment() -> void:
	print("\n== §7 THE EQUIPMENT ORDER")
	var commander = _find(root, "SquadCommander")
	if commander == null:
		print("  (no commander)")
		return
	print("  ORDERED_THROW_RANGE = %.0f m (Enemy) — the refusal the player hits most" % Enemy.ORDERED_THROW_RANGE)
	print("  refusals from the BODY (Enemy.order_use_equipment):")
	print("    down · not carried · none left · reloading · broken · too far")
	print("  refusals from the SQUAD when nobody answered (Squad._why_nobody_answered):")
	print("    nobody carrying · none left · reloading")
	print("  'reloading' is the ONLY one the commander holds and retries:")
	print("    queue_retry_interval %.2f s, queue_timeout %.1f s" % [
		commander.queue_retry_interval, commander.queue_timeout])
	print("  can_use() is NOT consulted on an ordered use — that is the whole")
	print("    difference from the autonomous path.")
	print("")
	var modes = commander.command_modes()
	print("  the designator's dial, for the selected squad — %d entr(y/ies):" % modes.size())
	for m in modes:
		print("    %-18s %-14s holders %-3s remaining %-4s point %-5s hold %s" % [
			String(m.get("item_id", &"")), str(m.get("label", "")),
			str(m.get("holders", 0)), str(m.get("remaining", 0)),
			str(m.get("wants_point", false)), str(m.get("deliberate", false))])
	print("  LINK: link_down() %s, resync_seconds %.1f, uplink_drag %.2f/s" % [
		str(commander.link_down()), commander.resync_seconds, commander.uplink_drag])
	print("  TRANSMIT: tx_radius %.0f m, tx_travel %.2f s, cost %.3f integrity, cone %.0f°" % [
		commander.tx_radius, commander.tx_travel, commander.tx_signal_cost, commander.tx_cone_degrees])


# ─────────────────────────────────────────────
# §2c — WHAT NOTHING CAN REACH
#
# An objective with no write site is not merely unorderable, it is unreachable
# — and four things downstream read for one of them anyway. The conclusion of
# the scan above, so it sits with it rather than at the end.
# ─────────────────────────────────────────────
func _report_unreachable(writes: Dictionary) -> void:
	print("\n== §2c WHAT NOTHING CAN REACH")
	var orphans: Array = []
	for name in OBJECTIVE_NAMES:
		if name == "NONE":
			continue   # the initial value; it needs no setter
		if (writes[name] as Array).is_empty():
			orphans.append(name)
	if orphans.is_empty():
		print("  every objective has at least one write site.")
	else:
		print("  %s — no write site anywhere outside tools/." % ", ".join(orphans))
		print("  and these still read for it:")
		for probe in [
			["Character/hud/squad_hud.gd", "WITHDRAW"],
			["Character/characters/ai/equipment/ai_smoke.gd", "OBJ_WITHDRAW"],
			["Character/characters/ai/equipment/ai_mine.gd", "WITHDRAW"],
			["Managers/analytics_report.gd", "WITHDRAW"],
		]:
			var text := FileAccess.get_file_as_string("res://" + str(probe[0]))
			var hits := 0
			for line in text.split("\n"):
				if str(probe[1]) in line:
					hits += 1
			print("    %-52s %d line(s) mentioning %s" % [probe[0], hits, probe[1]])
	# The squad's own role layer has the same shape: three of six SoldierRoles
	# are assigned only where an NCO exists, and nothing appoints one.
	#
	# COUNTED FROM OUTSIDE squad.gd. The two writes inside it are bookkeeping —
	# set_nco()'s own body and the `nco = null` when the NCO dies — and
	# counting them would answer "does the field exist" instead of "does
	# anything appoint one", which is the question. `==` is excluded explicitly
	# because `.nco =` is a substring of `.nco ==` and bark_director compares
	# against it.
	var nco_setters: Array = []
	var files: Array = []
	for scan_root in SCAN_ROOTS:
		_collect(scan_root, ".gd", files)
	for path in files:
		if path == "res://Managers/AI/squad.gd":
			continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var t: String = lines[i].strip_edges()
			if t.begins_with("#"):
				continue
			var appoints := "set_nco(" in t
			var at := t.find(".nco =")
			if at >= 0 and not t.substr(at).begins_with(".nco =="):
				appoints = true
			if appoints:
				nco_setters.append("%s:%d  %s" % [path.replace("res://", ""), i + 1, t])
	print("  Squad.nco is appointed from %d site(s) outside squad.gd and tools/." % nco_setters.size())
	for s in nco_setters:
		print("      %s" % s)
	_check("nothing appoints an NCO, so OVERWATCH and FLANKER are unassignable",
		nco_setters.is_empty(), "%d appointing site(s)" % nco_setters.size())
	print("    _nco_assign_roles is the only source of FLANKER, and the only")
	print("    source of OVERWATCH; SoldierRole.FALLBACK is assigned nowhere at")
	print("    all. So a real squad only ever holds NONE, SUPPRESSOR, ADVANCER.")
