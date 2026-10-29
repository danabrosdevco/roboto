extends SceneTree

# ─────────────────────────────────────────────
# WHAT DOES THE TREE WALK SEE WHILE TWO LEVELS ARE CHILDREN OF WORLD?
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_level_overlap.gd -- --no-save
#
# THE CLAIM IT IS ABOUT (K28). `World.deload_current_level()` calls
# `level.queue_free()` with no preceding `remove_child()`, and
# `load_next_level()` add_childs the replacement immediately afterwards.
# `queue_free()` is deferred, so the outgoing level is still a child of World
# when the incoming one is parented — and `register_world_objects()` walks
# `get_nodes_in_group("enemies")` somewhere after that. If the walk lands
# inside the overlap window, the outgoing level's bodies are registered
# against the incoming level, which would be a correctness bug and not a
# tidiness one.
#
# WHY IT HAS TO BE MEASURED RATHER THAN READ. Three separate things decide the
# answer and none of them is visible in `world.gd`: when Godot flushes its
# delete queue relative to the `process_frame` signal a coroutine resumes on,
# whether `queue_free()` takes a node out of its groups (it does not — only
# the actual free does), and how many awaits sit between the `add_child` and
# the walk. Reading the file gives you the window; only a run gives you where
# the walk falls inside it.
#
# THE TRAP IT IS BUILT AROUND. A freed node compares equal to `null` in Godot
# 4.3, so `!= null` passes over it and `size()` still counts it. Every count
# here is taken twice — once naively, once with `is_instance_valid` — so a
# measurement that would have lied says so out loud.
#
# HOW IT SAMPLES. World's own `child_entered_tree` / `child_exiting_tree`
# signals bracket the window without touching `world.gd`:
#
#   A  the instant the incoming level enters the tree      (inside add_child)
#   B  later in the same frame, after a message-queue flush (call_deferred)
#   C  the instant the outgoing level leaves the tree       (the delete flush)
#   D  after load_next_level() returns, from AIManager.all_ai — the registry
#      the real walk actually wrote
#
# Each sample prints the process-frame number, so the ordering of A/B/C
# against D is in the output rather than in an argument.
#
# IT IS A PROBE, NOT A GATE. It prints measurements and asserts nothing; it
# writes no save (cm.autosave = false).
# ─────────────────────────────────────────────

const SITE := &"hfw_1_fort"
## Long enough for EnemyForceSpawner to build every squad and for _apply_posture
## to have run — the outgoing level has to actually hold a force for the
## overlap question to mean anything.
const SETTLE_FRAMES := 240

var _world: World
var _mgr: AIManager
var _out_level: Node = null          # the level being torn down
var _in_level: Node = null           # its replacement
var _samples: Array = []
var _seen_enter: bool = false


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
	_world = master._world()
	_mgr = _find_mgr(master)
	if _world == null or _mgr == null:
		print("FAIL  no World or no AIManager, so there is nothing to measure")
		quit(1)
		return
	cm.reset_campaign()

	# ── deploy, so the outgoing level holds a real enemy force ───────────────
	var m = cm.get_mission(SITE)
	if m == null:
		print("FAIL  no mission '%s'" % String(SITE))
		quit(1)
		return
	cm.in_mission = false
	cm.debug_mission = m
	cm.select_mission(SITE)
	await _world.load_next_level(m.level_scene)
	# NO SECOND on_level_loaded(). World.load_next_level() ends by calling it
	# itself, so an explicit call here redeploys BOTH spawners in the same frame
	# as the first deploy — and tearing a robot down that few frames after it
	# was stood up leaves the engine something it only trips over in final
	# cleanup: every assertion printed PASS and the run still handed the shell
	# exit 139. H10, root-caused 2026-10-24: dropping this one line is the whole
	# fix. A 10-frame gap before the second call also cures it; one or two
	# frames do not. The call was redundant either way.
	for _i in SETTLE_FRAMES:
		await physics_frame

	_out_level = _world.current_level
	var before := _walk()
	print("")
	print("LEVEL OVERLAP — K28, measured on %s" % String(SITE))
	print("")
	print("BEFORE THE TRANSITION, with one level in the tree")
	print("  (this state is itself the product of a base -> mission transition,")
	print("   so a stale base body in all_ai would show up here as an orphan)")
	print("  World's TrenchBroomLevel children : %d" % _level_children().size())
	print("  \"enemies\" group                   : %s" % _fmt(before))
	print("  AIManager.all_ai                  : %s" % _fmt_reg())
	print("  of those, under NO level at all   : %d" % _reg_orphans())
	print("")

	# ── bracket the transition ──────────────────────────────────────────────
	_world.child_entered_tree.connect(_on_entered)
	_world.child_exiting_tree.connect(_on_exiting)

	var f0: int = Engine.get_process_frames()
	# The real game path: extraction, then the base loads over the operation.
	await _world.load_next_level(cm.base_level, true)
	var f1: int = Engine.get_process_frames()
	_sample("D  load_next_level() has returned", _in_level)

	_world.child_entered_tree.disconnect(_on_entered)
	_world.child_exiting_tree.disconnect(_on_exiting)

	print("THE TRANSITION — load_next_level() spanned process frames %d..%d" % [f0, f1])
	print("")
	for s in _samples:
		print("  %s" % s["label"])
		print("      process frame                 : %d" % s["frame"])
		print("      World's level children        : %d  (%s)" % [s["kids"], s["kid_names"]])
		print("      outgoing level still in tree  : %s" % s["out_in_tree"])
		print("      \"enemies\" group               : %s" % s["walk"])
		print("        of those, under the OUTGOING level : %d" % s["from_out"])
		print("        of those, under the INCOMING level : %d" % s["from_in"])
		print("        of those, under neither (orphans)  : %d" % s["from_neither"])
		print("")

	print("AFTER THE TRANSITION — the registry the real walk wrote")
	print("  AIManager.all_ai                  : %s" % _fmt_reg())
	print("  of those, under the incoming level: %d" % _reg_under(_world.current_level))
	print("  of those, under NO level at all   : %d" % _reg_orphans())
	print("")

	await _lab_shape()

	print("PROBE DONE — the numbers above are the finding; nothing is asserted.")
	quit(0)


# ── PHASE 2: how long the window is, in frames ──────────────────────────────
#
# `Managers/lab.gd:118-128` is the same three statements — `old.queue_free()`,
# `world.add_child(level)` — and then waits TWO process frames before
# `_clear_level()` walks `"enemies"`, and a third before
# `register_world_objects()`. Phase 1 shows the real window opening and closing
# inside ONE process frame; this sizes it frame by frame so lab's margin is a
# number rather than an assumption.
#
# IT USES A SYNTHETIC SUBTREE, NOT A LEVEL, ON PURPOSE. Driving lab's sequence
# over World's real `current_level` was tried first and is the wrong tool: it
# frees the base out from under Campaign and the base UI, and the run exits 139
# — the H10 shape, an orphan holding a resource past shutdown — with every line
# still printed, which is exactly the kind of green-looking lie this project
# keeps paying for. The thing being measured is engine behaviour and does not
# care what the nodes are: when does a `queue_free()`d parent take its
# descendants out of their GROUPS, which is the only reason the walk sees them.
# Phase 1's sample C confirms the same answer for a real level with 30 bodies.
func _lab_shape() -> void:
	print("THE WINDOW, FRAME BY FRAME — lab.gd waits 2 process frames; is that enough?")
	print("  (a synthetic subtree, so no real level is torn down to ask this)")
	var outgoing := Node3D.new()
	outgoing.name = "ProbeOutgoing"
	for i in 5:
		var body := Node3D.new()
		body.name = "ProbeBody%d" % i
		body.add_to_group("enemies")
		outgoing.add_child(body)
	_world.add_child(outgoing)
	await process_frame
	print("  with the synthetic subtree alone in the tree")
	print("      \"enemies\" group               : %s" % _fmt(_walk()))

	var incoming := Node3D.new()
	incoming.name = "ProbeIncoming"
	outgoing.queue_free()
	_world.add_child(incoming)
	print("  frame +0, immediately after add_child (the lab.gd:120-122 shape)")
	print("      outgoing still in tree        : %s" % ("YES" if _in_tree(outgoing) else "no"))
	print("      \"enemies\" group               : %s" % _fmt(_walk()))
	for i in 3:
		await process_frame
		print("  frame +%d%s" % [i + 1, "   <- lab.gd's _clear_level() walks here" if i == 1 else ("   <- lab.gd's register_world_objects() here" if i == 2 else "")])
		print("      outgoing still in tree        : %s" % ("YES" if _in_tree(outgoing) else "no"))
		print("      \"enemies\" group               : %s" % _fmt(_walk()))
	incoming.queue_free()
	for _i in 2:
		await process_frame
	print("")


# ── the two brackets ────────────────────────────────────────────────────────

## Fires inside World.add_child(new_level), before the new level's own children
## have entered the tree and before any of its _ready() runs. Maximum overlap.
func _on_entered(node: Node) -> void:
	if not (node is TrenchBroomLevel) or node == _out_level or _seen_enter:
		return
	_seen_enter = true
	_in_level = node
	_sample("A  incoming level entered the tree (inside add_child)", node)
	# Later in the same frame, once the message queue has been flushed but
	# before SceneTree's delete queue has been. A second look at the same
	# window, after every _ready() in the incoming level has run.
	_sample_later.call_deferred()


func _sample_later() -> void:
	_sample("B  same frame, after a message-queue flush", _in_level)


## Fires when the outgoing level actually leaves the tree — which is the delete
## flush, not the queue_free() call. This is the end of the overlap window.
func _on_exiting(node: Node) -> void:
	if node != _out_level:
		return
	_sample("C  outgoing level is leaving the tree (the delete flush)", _in_level)


# ── sampling ────────────────────────────────────────────────────────────────

func _sample(label: String, incoming) -> void:
	var walk := _walk()
	var kids := _level_children()
	var names: Array = []
	for k in kids:
		names.append(String(k.name))
	_samples.append({
		"label": label,
		"frame": Engine.get_process_frames(),
		"kids": kids.size(),
		"kid_names": ", ".join(names) if not names.is_empty() else "none",
		"out_in_tree": "YES" if _in_tree(_out_level) else "no",
		"walk": _fmt(walk),
		"from_out": _under(walk["nodes"], _out_level),
		"from_in": _under(walk["nodes"], incoming),
		"from_neither": _under_neither(walk["nodes"]),
	})


## The walk `register_world_objects()` does, counted both ways: `!= null` (which
## a freed node passes) and `is_instance_valid` (which it does not).
func _walk() -> Dictionary:
	var nodes: Array = get_nodes_in_group("enemies")
	var naive := 0
	var valid := 0
	var is_ai := 0
	var queued := 0
	for n in nodes:
		if n != null:
			naive += 1
		if is_instance_valid(n):
			valid += 1
			if n is AI:
				is_ai += 1
			if (n as Node).is_queued_for_deletion():
				queued += 1
	return {"nodes": nodes, "size": nodes.size(), "naive": naive,
		"valid": valid, "ai": is_ai, "queued": queued}


func _fmt(w: Dictionary) -> String:
	return "%d returned, %d pass \"!= null\", %d pass is_instance_valid, %d are AI, %d queued for deletion" % [
		w["size"], w["naive"], w["valid"], w["ai"], w["queued"]]


func _fmt_reg() -> String:
	var all: Array = _mgr.all_ai
	var valid := 0
	for a in all:
		if is_instance_valid(a):
			valid += 1
	return "%d entries, %d valid, %d freed-but-held" % [all.size(), valid, all.size() - valid]


# ── helpers ─────────────────────────────────────────────────────────────────

func _level_children() -> Array:
	var out: Array = []
	for c in _world.get_children():
		if c is TrenchBroomLevel:
			out.append(c)
	return out


func _in_tree(n) -> bool:
	return n != null and is_instance_valid(n) and (n as Node).is_inside_tree()


func _under(nodes: Array, level) -> int:
	if level == null or not is_instance_valid(level):
		return 0
	var n := 0
	for x in nodes:
		if is_instance_valid(x) and (level as Node).is_ancestor_of(x):
			n += 1
	return n


func _under_neither(nodes: Array) -> int:
	var n := 0
	for x in nodes:
		if not is_instance_valid(x):
			continue
		var in_out: bool = _out_level != null and is_instance_valid(_out_level) and (_out_level as Node).is_ancestor_of(x)
		var in_in: bool = _in_level != null and is_instance_valid(_in_level) and (_in_level as Node).is_ancestor_of(x)
		if not in_out and not in_in:
			n += 1
	return n


func _reg_under(level) -> int:
	if level == null or not is_instance_valid(level):
		return 0
	var n := 0
	for a in _mgr.all_ai:
		if is_instance_valid(a) and (level as Node).is_ancestor_of(a):
			n += 1
	return n


func _reg_orphans() -> int:
	var n := 0
	for a in _mgr.all_ai:
		if not is_instance_valid(a):
			continue
		var cur = _world.current_level
		if cur == null or not is_instance_valid(cur) or not (cur as Node).is_ancestor_of(a):
			n += 1
	return n


func _find_mgr(n: Node) -> AIManager:
	if n is AIManager:
		return n as AIManager
	for c in n.get_children():
		var f := _find_mgr(c)
		if f != null:
			return f
	return null
