extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# PLAY THE OPENING, AS FAR AS A HEADLESS RUN CAN.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_hillfort_live.gd
#
# tools/test_hillfort_wip.gd checks that the FILES agree with each other —
# every tag resolves, every tier matches, the connects_to is mutual. It loads
# the level but it never runs the campaign, so everything it proves is still
# structural.
#
# This boots Master, resets the campaign, walks the ladder from a fresh save to
# the first site, deploys into it, takes the ground, and extracts. It is the
# question the structural suite cannot ask: DOES THE OPENING ACTUALLY WORK.
#
# WRITTEN WHEN hfw_1_fort REPLACED hillfort_1_relay as the opening site
# (2026-10-15). A swap touches the catalogue, the board, the gate chain, the
# callsign pool and the save — and every one of those fails quietly. The
# campaign does not crash when the first site is unreachable; it simply never
# offers a second one.
#
# IT WRITES NO SAVE. `cm.autosave = false`, same as test_site_win.
# ─────────────────────────────────────────────

const SITE := &"hfw_1_fort"
const DEFENCE := &"hfw_2_defend"
const LOC := &"hillfort_wip"

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
	# NEVER THE PLAYER'S SAVE. This boots the real campaign; without this it
	# would write over a run in progress.
	cm.autosave = false
	root.add_child(master)
	for _i in 90:
		await physics_frame
	var world: World = master._world()
	cm.reset_campaign()

	_ladder(cm)
	_board(cm)
	await _deploy_and_win(cm, world)
	_aftermath(cm)
	_done()


# ── 1 · the way in ───────────────────────────────────────────────────────────

## From a fresh save to the first site, through the gates the player meets.
func _ladder(cm) -> void:
	var open := _ids(cm.available_missions())
	# ONE EXERCISE SINCE 2026-10-22, not two: First Contact was cut and Take
	# And Hold is the whole of training.
	_check("a fresh campaign offers only the exercise",
		open == ["arena_3_firing_line"], str(open))
	_check("...and the war is shut until it is cleared", not open.has(String(SITE)), str(open))

	cm.state.completed_missions.append(&"arena_3_firing_line")
	open = _ids(cm.available_missions())
	_check("CLEARING THE TRAINING OPENS THE HILLFORT", open.has(String(SITE)), str(open))
	# THE RETIRED ONE IS GONE, not merely unreferenced. A mission left in
	# Campaign.missions would still be offered from the board.
	_check("...and the retired hillfort is not offered",
		not open.has("hillfort_1_relay"), str(open))
	_check("...and nothing deeper opens with it",
		not open.has("basin_1_anchor"), str(open))

	# THE GATE BEYOND IT. This is the one a swap breaks silently:
	# available_missions() gates on completed_missions.has(req), so a mission
	# that is not in Campaign.missions can never satisfy anything that requires
	# it, and the board simply never offers a second site.
	cm.state.completed_missions.append(SITE)
	open = _ids(cm.available_missions())
	_check("CLEARING THE HILLFORT OPENS VALLEY BASIN",
		open.has("basin_1_anchor"), str(open))
	cm.state.completed_missions.erase(SITE)


# ── 2 · what the board says about it ─────────────────────────────────────────

func _board(cm) -> void:
	var m = cm.get_mission(SITE)
	_check("the mission is in the campaign", m != null)
	if m == null:
		return
	_check("...and the player sees it called Hillfort",
		m.display_name == "Hillfort", m.display_name)

	var site = cm.state.locations.for_mission(SITE) if cm.state.locations != null else null
	_check("...and it resolves to a location", site != null)
	if site != null:
		_check("...named Hillfort too", site.display_name == "Hillfort", site.display_name)
		_check("...which the defence resolves to as well",
			cm.state.locations.for_mission(DEFENCE) == site)
		_check("...and it starts in their hands",
			cm.state.site_owner(site.id) != int(Enums.Factions.PLAYER))

	# ONE PIN, not two. The defence folds onto the attack's marker — a site is
	# a place with two operations on it, not two places.
	var pins := 0
	for mm in cm.missions:
		if mm == null or mm.defence or mm.sim:
			continue
		var l = cm.state.locations.for_mission(mm.id) if cm.state.locations != null else null
		if l != null and l.id == LOC:
			pins += 1
	_check("the hillfort draws one pin, not two", pins == 1, "%d" % pins)

	# THE CALLSIGN POOL FOLLOWED THE SWAP. Keyed by LOCATION id, so retiring
	# `hillfort` without adding `hillfort_wip` drops the site's own names and
	# everything falls back to the faction pool — silently, and only audible.
	_check("the site keeps its own callsign pool",
		Callsigns.BY_SITE.has(LOC), str(Callsigns.BY_SITE.keys()))


# ── 3 · deploy, take it, and get out ─────────────────────────────────────────

func _deploy_and_win(cm, world) -> void:
	var m = cm.get_mission(SITE)
	if m == null:
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
	for _i in 120:
		await physics_frame

	var slice = _find(world.current_level, "HillfortWipSlice")
	_check("the level carries its site slice", slice != null)
	if slice == null:
		return
	var op = slice.get("operation")
	_check("...which built an operation", op != null)
	if op == null:
		return
	_check("...with six cores on it", op.cores.size() == 6, "%d" % op.cores.size())
	_check("...and a bunker", op.get("bunker") != null)
	if op.get("bunker") == null:
		return

	# EVERY CORE IS REACHABLE. A HoldableCore with no interactible is a core
	# the player walks up to and cannot press F on, which is invisible to every
	# structural check because the node is there and correctly named.
	var mute := 0
	for c in op.cores:
		if c == null or c.get("interactible") == null \
				or not is_instance_valid(c.interactible):
			mute += 1
	_check("every core has a terminal to work", mute == 0,
		"%d core(s) with nothing to press" % mute)

	# AND THEY START HOSTILE, or holding them proves nothing.
	var held := 0
	for c in op.cores:
		if c != null and c.is_held_by_player():
			held += 1
	_check("...and they all start in their hands", held == 0, "%d already yours" % held)

	var exit = _exit(world.current_level)
	_check("the level has a way out", exit != null)
	if exit == null:
		return
	_check("...and it is shut to begin with", exit.requires_objectives_complete,
		"already open, so unlocking it proves nothing")

	# ── A CAPTURE CALLS THE COUNTER-ATTACK ────
	# reinforcement_tag IS an objective id (Campaign._on_objective_changed), so
	# this is the whole trigger. A typo here is silent: the wave never comes
	# and the fight is simply easier than it was authored to be.
	var before := _hostiles()
	var pillars = _core_named(world.current_level, "PillarsCore")
	_check("the Pillars core is on the map", pillars != null)
	if pillars != null:
		pillars.start_held()
		for _i in 150:
			await physics_frame
		var after := _hostiles()
		_check("TAKING A CORE CALLS THE COUNTER-ATTACK", after > before,
			"%d hostiles before, %d after" % [before, after])

	# ── THE BUNKER ENDS IT ────────────────────
	# Deliberately with five of the six cores still theirs: §12.7 says you do
	# not have to clear the board, and the lane design hands a centre run one
	# core out of five.
	op.bunker.start_held()
	op.stand_down_seconds = 0.5
	for _i in 240:
		await physics_frame

	_check("TAKING THE BUNKER ENDS THE OPERATION", bool(op.get("_settled")),
		"the stand-down ran and nothing concluded")
	_check("...with five cores still theirs", _held_count(op) <= 2,
		"%d of 6 held, so this did not test the partial case" % _held_count(op))
	_check("...and the way out opens", not exit.requires_objectives_complete,
		"the exit still demands every objective, which this win does not satisfy")
	_check("...and the operation runs until they walk it", cm.in_mission,
		"it ended on its own, so the walk means nothing")


# ── 4 · what it paid and what it changed ─────────────────────────────────────

func _aftermath(cm) -> void:
	var before: int = cm.state.earned
	var result: Dictionary = cm.extract(true)
	_check("extracting ends the mission", not cm.in_mission)

	# 225 FLAT PLUS WHAT WAS ACTUALLY TAKEN. The flat reward was cut from 325
	# so the lane choice would show up in the payout; a run that took one core
	# must be paid less than one that swept the hill.
	var paid: int = cm.state.earned - before
	_check("...and it pays the flat reward plus the cores taken",
		paid >= 225, "paid %d, result %s" % [paid, str(result.get("reward", "?"))])

	# THE GROUND IS YOURS NOW, which is what makes the site pay every turn and
	# what makes the defence possible at all.
	_check("...and the hillfort is held",
		cm.state.site_owner(LOC) == int(Enums.Factions.PLAYER),
		"owner %d" % cm.state.site_owner(LOC))

	# THE DEFENCE IS NOT OFFERED UNTIL A RAID IS IN DOUBT. Offering it freely
	# would make losing ground impossible.
	var open := _ids(cm.available_missions())
	_check("the defence is not on the board unsolicited",
		not open.has(String(DEFENCE)), str(open))
	cm.state.under_attack = LOC
	open = _ids(cm.available_missions())
	_check("...but it IS once the hillfort is raided",
		open.has(String(DEFENCE)), str(open))
	cm.state.under_attack = &""


# ── looking things up ────────────────────────────────────────────────────────

func _held_count(op) -> int:
	var n := 0
	for c in op.cores:
		if c != null and c.is_held_by_player():
			n += 1
	return n


## How many hostiles are standing in the tree right now. Counted off the group
## rather than the level, because a woken reserve is parented by the spawner
## and not necessarily under the level node the caller happens to hold.
func _hostiles() -> int:
	var n := 0
	for s in get_nodes_in_group("enemies"):
		if s != null and is_instance_valid(s):
			n += 1
	return n


func _core_named(level: Node, named: String):
	var host := _find(level, named)
	if host == null:
		return null
	for c in host.get_children():
		if c.get_script() != null \
				and String(c.get_script().resource_path).ends_with("holdable_core.gd"):
			return c
	return null


func _exit(level: Node):
	for n in _all(level):
		if String(n.name) == "LevelExit" and "requires_objectives_complete" in n:
			return n
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


func _ids(missions: Array) -> Array:
	var out: Array = []
	for m in missions:
		if m != null:
			out.append(String(m.id))
	out.sort()
	return out
