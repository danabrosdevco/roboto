extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# THE SIM ARENA IS ITS OWN PLACE.
#
# docs/briefs/archive/SIM_ARENA_MODE.md. A free action must not look like a costly one:
# the arenas used to sit on the operations table beside sites that cost a turn
# and can be lost, offered with the same furniture.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_sim_arena.gd
# ─────────────────────────────────────────────

const _UI := preload("res://Character/hud/sim_arena_ui.gd")

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	# PACE THE LOOP — see the note in tools/test.sh. Without this a
	# --script run has no frame cap, _process spins flat out and starves
	# physics, and every await physics_frame below takes far longer in
	# wall clock than the 1/60 s it is written as.
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 140:
		await physics_frame
	var cm = world.get_node("CampaignManager")

	# ── off the war board ───────────────────────
	var table = _find(root, "OpsTable")
	if table != null:
		var drawn: Array = table._board_missions()
		var sims: Array = []
		for m in drawn:
			if m != null and m.sim:
				sims.append(String(m.id))
		# THE EXERCISES ARE NOT SITES. They live inside the arena, which is one
		# entry on the board — a place you go, not a war you pick.
		_check("no exercise is drawn as a site", sims.is_empty(), str(sims))
		_check("...the arena is one entry instead", table._has_training())
		# NINE, NOT TEN. The board draws one pin per PLACE now, so the basin's
		# defence no longer has a marker of its own — see _board_missions and
		# docs/briefs/archive/ONE_PIN_PER_SITE.md.
		_check("...alongside the real sites", drawn.size() >= 9,
			"%d drawn" % drawn.size())
	else:
		_check("(setup) an OpsTable exists to ask", false)

	# ── the arena lists them instead ────────────
	var ui := _UI.new()
	ui.campaign = cm
	ui.catalogue = cm.catalogue
	root.add_child(ui)
	await process_frame
	var training: Array = ui._sim_missions()
	# ONE SINCE 2026-10-22. First Contact was cut: it was solo, eliminate and
	# extract, and it stood in front of the only exercise that teaches the verb
	# the campaign is made of.
	_check("there is exactly ONE exercise, then the war", training.size() == 1,
		"%d" % training.size())
	var costly: Array = []
	for m in training:
		if m.reward_resources > 0 or m.compute_reward > 0 or not m.repeatable:
			costly.append(String(m.id))
	_check("...and every one of them is free and repeatable", costly.is_empty(), str(costly))

	# ── a fight can be built ────────────────────
	_check("both sides start empty", ui._side_a.is_empty() and ui._side_b.is_empty())
	ui._picking = &"a"
	ui._add(&"soldier")
	ui._add(&"soldier")
	ui._picking = &"b"
	ui._add(&"rifleman")
	var m = ui._matchup()
	_check("a matchup is built from what was picked",
		m != null and m.allies.size() == 2 and m.hostiles.size() == 1,
		"%d v %d" % [m.allies.size(), m.hostiles.size()])
	_check("...and it is ONE run, not a measurement sweep", m.repeats == 1,
		"%d repeats" % m.repeats)

	# EVERY FRAME, OPENED OR NOT. The sim is where you find out what a thing
	# does before paying to open the line.
	var offered: Array = ui._all_frames()
	var locked_offered := false
	for f in offered:
		if not cm.state.is_unlocked(f.id):
			locked_offered = true
			break
	_check("the lab offers both sides — the Swarm's frames too",
		_has_frame(offered, &"rifleman") and _has_frame(offered, &"chaser"),
		"%d frames offered" % offered.size())
	_check("...including frames you have NOT unlocked", locked_offered,
		"%d frames offered" % offered.size())
	var structures: Array = []
	for f in offered:
		if f.supply <= 0:
			structures.append(String(f.id))
	_check("...but not structures — two Nests is not a fight", structures.is_empty(),
		str(structures))

	# ── the Lab can be led, not only watched ────
	var lab = load("res://Managers/lab.gd").new()
	_check("the Lab spectates by default, so measurements stay clean", lab.spectate)
	lab.free()

	# ── THE LAB'S SIDE LISTS ────────────────────
	var lab_ui = _UI.new()
	lab_ui.campaign = cm
	lab_ui.catalogue = cm.catalogue

	# NAMES COME FROM EITHER ROSTER. Eleven of the frames this screen offers
	# are the adversary's and are not in the player catalogue at all, so a
	# lookup that only asked the catalogue listed them by raw id — "MORTAR_TRACK"
	# in a column next to "Spotter Drone".
	var missed: Array = []
	for f in lab_ui._all_frames():
		if lab_ui._def(f.id) == null:
			missed.append(String(f.id))
	_check("every frame the lab offers can be named again afterwards",
		missed.is_empty(), str(missed))

	# REPEATS COLLAPSE. Five Lances is one row saying x5, not five rows.
	lab_ui._side_a.clear()
	for i in 5:
		lab_ui._side_a.append(&"lance")
	lab_ui._side_a.append(&"spotter")
	var box = lab_ui._side_box("a", "YOUR SIDE", lab_ui._side_a)
	var words := _labels(box)
	# THREE: the header row, the collapsed LANCE row, and SPOTTER. Six frames
	# would have drawn seven rows before this.
	_check("five of the same frame is ONE row", _count_rows(box) == 3,
		"%d row(s): %s" % [_count_rows(box), str(words)])
	_check("...and it says how many", _has(words, "x5"), str(words))

	# THE CEILING IS VISIBLE, not a dead button.
	lab_ui._side_b.clear()
	lab_ui._picking = &"b"
	_check("an empty side refuses nothing", lab_ui._refuse(lab_ui._all_frames()[0]) == "")
	for i in lab_ui.PER_SIDE:
		lab_ui._side_b.append(&"lance")
	var why: String = lab_ui._refuse(lab_ui._all_frames()[0])
	_check("a full side says so instead of swallowing the click", why != "", why)
	_check("...and names the side and the limit",
		why.contains("THEIRS") and why.contains(str(lab_ui.PER_SIDE)), why)
	lab_ui._side_b.clear()
	lab_ui._picking = &"a"
	# FREED, AND SO IS THE ROW BOX IT BUILT. lab_ui is never added to the tree,
	# so nothing takes it down for us: left alive it reaches ObjectDB's
	# end-of-run sweep, which runs AFTER the servers that own its canvas items
	# have gone, and the process segfaults there — 53/53 PASS and exit 139.
	# H10, root-caused 2026-10-24. Any scratch Control a suite builds and does
	# not parent has to be freed by hand.
	if box != null and box.get_parent() == null:
		box.free()
	lab_ui.free()

	# ── THE WIPE FIRES ON GOING IN, NOT ON OPENING THE MENU ──
	#
	# Selecting the arena at the table opens a menu over the board: you are
	# still at the table, still choosing, and nothing has happened yet. The
	# transition belongs on the step after — ENTER on an exercise, or WATCH /
	# LEAD on a fight — which is the moment you actually go into the
	# simulation. Built the wrong way round once, which made choosing feel like
	# arriving and left arriving with no transition to spend.
	var src := FileAccess.get_file_as_string("res://Character/hud/ops_table_ui.gd")
	var opens := src.split("func _open_arena()")
	_check("(setup) found _open_arena", opens.size() == 2)
	if opens.size() == 2:
		var body: String = opens[1].split("func _wipe(")[0]
		_check("opening the arena menu plays no wipe", not body.contains("_wipe("),
			"it calls _wipe, so choosing looks like arriving")
	_check("ENTER on an exercise deploys rather than only queueing",
		src.contains("_deploy_sim") and src.contains("load_next_level"),
		"select_mission alone only queues a destination at the departure pad")
	_check("...and WATCH / LEAD is connected at all",
		src.contains("fight_requested.connect"),
		"the arena emits it and nothing listens, so both buttons do nothing")
	_check("the wipe outlives the board it was launched from",
		src.contains("get_tree().root.add_child(wipe_layer)"),
		"parented to the board, it is freed mid-animation when the board closes")

	# ── AND IT RUNS WHEN IT HAS TO ──────────────
	#
	# The board holds the tree PAUSED the whole time its menu is up, and a
	# Tween on a pausable node does not advance. The wipe sat frozen and ENTER
	# looked dead until you escaped the menu, which released the hold.
	var wipe = load("res://Character/hud/cyberspace_wipe.gd").new()
	root.add_child(wipe)
	await process_frame
	_check("the wipe is not pausable, because it covers a pause",
		wipe.process_mode == Node.PROCESS_MODE_ALWAYS,
		"process_mode %d" % wipe.process_mode)

	# IT ALSO HAS TO ADVANCE under an actually paused tree, which is the thing
	# the mode is for — asserted by running it rather than by trusting the flag.
	# SceneTree.paused, not root.paused — the root is a Window and has no such
	# property, so the set silently does nothing and the check proves nothing.
	paused = true
	wipe.play()
	var before: float = wipe.material.get_shader_parameter("progress")
	for _i in 20:
		await process_frame
	var after: float = wipe.material.get_shader_parameter("progress")
	paused = false
	_check("...and it advances while the tree is paused", after > before,
		"progress %.3f -> %.3f" % [before, after])
	if is_instance_valid(wipe):
		wipe.queue_free()

	# UNDER THE LOADING SCREEN, which Master builds at layer 128.
	_check("the wipe sits below the loading screen, not over it",
		src.contains("wipe_layer.layer = 100"),
		"sharing 128 makes the order depend on which was added last")

	# ── WHAT THE OBJECTIVE LINE SAYS ────────────
	#
	# "Capture the X", always, with X the name of the PLACE. The arena's two
	# captures authored the whole phrase in the scene instead — "WORK THE CORE"
	# — which read badly and sidestepped the rule the rest of the game follows:
	# display_name names the thing, verb() supplies the action, label() joins
	# them. See the labelling note in mission_objective.gd.
	var level = load("res://maps/proving_level.tscn").instantiate()
	root.add_child(level)
	await process_frame
	for pair in [["TrainingCore", "Capture the Core"],
			["TrainingBunker", "Capture the Bunker"]]:
		var n = level.get_node_or_null(pair[0])
		_check("%s reads '%s'" % [pair[0], pair[1]],
			n != null and n.label() == pair[1],
			"reads '%s'" % (n.label() if n != null else "<missing>"))
	level.queue_free()

	# AND THE RULE IS NOT ONLY THE ARENA'S. Every capture in the game goes
	# through InteractObjective, so the article lives there rather than in each
	# level: the basin's "West Garrison" reads "Capture the West Garrison".
	var io = load("res://Campaign/interact_objective.gd").new()
	io.display_name = "West Garrison"
	_check("a site capture reads the same way", io.label() == "Capture the West Garrison",
		"reads '%s'" % io.label())
	io.free()

	# ── THE ARENAS ARE DEFENDED, NOT CHARGED ────
	#
	# Both exercises used one squad on ADVANCE out of the enemy muster: they
	# left their end the moment you were down and met you in the middle, every
	# time, in both missions. Nothing was held and nothing had to be taken.
	# They now dig in on the ground you have come for — arena 1 on the
	# blockhouse it extracts from, arena 2 on the core and the bunker in the
	# bay — so the fight is you moving up rather than them coming to you.
	var ADVANCE := 2
	var GARRISON := 1
	var RESERVE := 3
	var posts := {}
	var lvl = load("res://maps/proving_level.tscn").instantiate()
	root.add_child(lvl)
	await process_frame
	for n in _all_nodes(lvl):
		if "tag" in n and String(n.tag).begins_with("obj_arena"):
			posts[n.tag] = (n as Node3D).global_position

	for spec in [["arena_3_firing_line", 3]]:
		var def = cm.get_mission(StringName(spec[0]))
		_check("%s fields %d squad(s)" % [spec[0], spec[1]],
			def != null and def.enemy_force.size() == int(spec[1]),
			"%d" % (def.enemy_force.size() if def != null else -1))
		if def == null:
			continue
		for s in def.enemy_force:
			if s == null:
				continue
			_check("  %s is not ordered to advance" % s.callsign,
				s.posture != ADVANCE, "posture %d" % s.posture)
			_check("  ...and has ground to hold", s.post_tag != &"", String(s.post_tag))
			_check("  ...that the level actually has", posts.has(s.post_tag),
				"%s is not a post in proving_level (has %s)" % [
					String(s.post_tag), str(posts.keys())])
			if s.posture == RESERVE:
				_check("  ...and %s waits for something to wake it" % s.callsign,
					s.reinforcement_tag != &"" or s.wake_after_seconds > 0.0
					or s.wake_after_kills > 0,
					"a RESERVE with no trigger never arrives")

	# THE POSTS A MISSION USES ARE ON FLOOR, not in the air. Measured, because
	# a post inside or above geometry is a squad that spawns there.
	#
	# SCOPED TO POSTS IN USE, and the unused ones are named rather than
	# skipped quietly. The level carries `obj_arena_hostiles` at (0, 3.2, 37),
	# which is 2.7 m above the blockhouse COURT — the decks either side of it
	# are at x 7..13, and x 0 is the open slot between them. It was the spawn
	# point when both exercises simply charged out of it and the drop did not
	# matter. Nothing points at it now; arena 1 garrisons `obj_arena_blockhouse`
	# on the deck itself. Left where the level author put it.
	var used := {}
	for mid in ["arena_3_firing_line"]:
		var d = cm.get_mission(StringName(mid))
		if d == null:
			continue
		for s in d.enemy_force:
			if s != null and s.post_tag != &"":
				used[s.post_tag] = true
			if s != null and s.spawn_tag != &"":
				used[s.spawn_tag] = true
	var space := root.world_3d.direct_space_state
	for tag in posts:
		var p: Vector3 = posts[tag]
		if not used.has(tag):
			print("      NOTE  post '%s' at %v is not used by either exercise."
				% [String(tag), p])
			continue
		var q := PhysicsRayQueryParameters3D.create(
			p + Vector3(0, 0.6, 0), p - Vector3(0, 8, 0))
		var h := space.intersect_ray(q)
		_check("post '%s' stands on floor" % String(tag),
			not h.is_empty() and absf(h.position.y - p.y) <= 1.2,
			"at %v" % p)
	lvl.queue_free()

	# ── THE TRAINING TRACK FINISHES, AND SAYS SO ──
	#
	# A cleared exercise used to read "RUN x1" and keep its ENTER button, which
	# made a sequence you finish look like a list you grind. There is nothing
	# to gain from a second run: an exercise pays nothing and costs no turn.
	var ui2 = _UI.new()
	ui2.campaign = cm
	ui2.catalogue = cm.catalogue
	var sims: Array = ui2._sim_missions()
	_check("(setup) there are exercises to finish", not sims.is_empty())
	# ONE AT A TIME, AND THE NAME IS THE BIG THING.
	#
	# These used to assert a LIST: every exercise drawn at once, each saying
	# NOT RUN or COMPLETED, the cleared ones greyed but still there. That was
	# the old screen and the checks were right about it. The screen now shows
	# only the exercise you are on, because a list invites you to pick and
	# there is nothing to pick — they run in order.
	if not sims.is_empty():
		var fresh = ui2._training_row(sims[0], 1, sims.size())
		var w1 := _labels(fresh)
		_check("the exercise offers a way in",
			_has_button(fresh, "ENTER"), str(w1))
		_check("...and says where you are in the sequence",
			_has(w1, "EXERCISE 1 OF %d" % sims.size()), str(w1))
		_check("...and leads with the NAME",
			_has(w1, sims[0].display_name.to_upper()), str(w1))
		# The name has to be the biggest thing on the card — that was the whole
		# complaint about the old row, where it was set at BODY like everything
		# else with a clipped line of briefing under it taking more room.
		_check("...at a size nothing else on the card uses",
			_biggest_label(fresh) == sims[0].display_name.to_upper(),
			"biggest is '%s'" % _biggest_label(fresh))
		_check("...and the briefing is NOT squeezed in under it",
			not _has_substring(w1, sims[0].briefing.left(20)), str(w1))
		fresh.free()

		# AND THE SEQUENCE ADVANCES. _draw_training picks the first uncleared
		# one, so clearing the first has to move it on rather than leave a
		# finished exercise sitting at the top of the screen.
		#
		# ASKED BEFORE THE CLEAR, not after. There is ONE exercise since First
		# Contact was cut on 2026-10-22, so clearing the first one finishes
		# training — and the "both tabs are offered" check that used to sit
		# below this was reading a board that had just been completed.
		_check("while training is unfinished, both tabs are offered",
			not ui2._training_over())
		_check("a fresh exercise is not cleared", not ui2._is_cleared(sims[0]))
		cm.state.record_clear(sims[0].id)
		_check("...and running it clears it", ui2._is_cleared(sims[0]))
		if sims.size() > 1:
			_check("...while the next one is still ahead of you",
				not ui2._is_cleared(sims[1]))

	# ── AND THE TAB GOES WHEN THERE IS NOTHING ON IT ──
	for sim in sims:
		cm.state.record_clear(sim.id)
	_check("once every exercise is cleared, training is over", ui2._training_over())
	ui2.free()

	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _find(n: Node, named: String) -> Node:
	if n.name == named:
		return n
	for c in n.get_children():
		var f := _find(c, named)
		if f != null:
			return f
	return null


func _has_frame(frames: Array, id: StringName) -> bool:
	for f in frames:
		if f != null and f.id == id:
			return true
	return false


## Every Label's text under a control, in tree order.
func _labels(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		out.append_array(_labels(c))
	return out


func _has(words: Array, want: String) -> bool:
	for w in words:
		if String(w).strip_edges() == want:
			return true
	return false


## How many frame rows a side box drew. One HBoxContainer per row, plus the
## header row — which is why the expected counts here include it.
func _count_rows(n: Node) -> int:
	var rows := 0
	for c in n.get_children():
		if c is HBoxContainer:
			rows += 1
		rows += _count_rows(c)
	return rows


## Every node under one, flattened.
func _all_nodes(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all_nodes(c))
	return out


## True when a button with this text sits anywhere under a control.
func _has_button(n: Node, text: String) -> bool:
	if n is Button and String((n as Button).text).strip_edges() == text:
		return true
	for c in n.get_children():
		if _has_button(c, text):
			return true
	return false


## The text of the largest label under a node. The exercise name has to be the
## biggest thing on its card — that was the whole point of the rework, and a
## check on the words alone would pass on the old layout too.
func _biggest_label(n: Node, best: Array = [0, ""]) -> String:
	if n is Label:
		var px: int = (n as Label).get_theme_font_size("font_size")
		if px > int(best[0]):
			best[0] = px
			best[1] = (n as Label).text
	for c in n.get_children():
		_biggest_label(c, best)
	return String(best[1])


## Does any label contain this text? `_has` is an exact match on a whole label,
## which cannot answer "is the briefing in here somewhere".
func _has_substring(words: Array, want: String) -> bool:
	if want.strip_edges() == "":
		return false
	for w in words:
		if String(w).find(want) >= 0:
			return true
	return false
