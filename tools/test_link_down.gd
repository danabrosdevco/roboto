extends SceneTree

# ─────────────────────────────────────────────
# NO LINK, NO ORDERS — AND IT DOES NOT COME BACK THE INSTANT THE BAR DOES.
#
# An e-killed drone keeps its gun and loses its command. Four things have to
# hold, and the last two are the ones that would rot quietly:
#
#   1. at the floor, link_down() is true and every order path refuses
#   2. recovery starts a RESYNC window — the bar is up, the squad is not
#      answering yet, so a link that flickers for one frame cannot hand the
#      squad back mid-firefight
#   3. a dead uplink drags the squad's own signal down, but FLOORS at critical:
#      jamming should cost a coordinated squad, not delete it
#   4. no player to ask means orders are never refused. A command layer that
#      fails closed locks the player out of their own game when something
#      unrelated breaks.
#
#   godot --headless --audio-driver Dummy --path . --script tools/test_link_down.gd
# ─────────────────────────────────────────────

const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fail += 1


func _init() -> void:
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false   # never write the real save
	root.add_child(world)
	for _i in 90:
		await physics_frame
	var player: Node3D = world.player

	var cmd: Node = _find(root, "link_down")
	_check("(setup) found the squad commander", cmd != null)
	if cmd == null:
		_finish()
		return
	cmd.player = player

	# ── 1. the floor refuses ────────────────────
	player.signal_integrity = 1.0
	cmd._tick_link(0.1)
	_check("a clean link commands normally", not cmd.link_down())

	player.receive_signal_damage(1.0)
	player.lock_signal(30.0)
	cmd._tick_link(0.1)
	_check("(setup) the drone is e-killed",
		int(player.get_signal_state()) == int(AI.SignalState.EKILL),
		"integrity %.3f" % player.signal_integrity)
	_check("at the floor the player cannot command", cmd.link_down())
	_check("...and the dial refuses an order",
		not cmd.issue_dial_order({"item_id": &"@advance", "verb": 0, "label": "ADVANCE"},
			player.global_position))
	_check("...and equipment refuses too",
		not cmd.issue_equipment_order(&"smoke", "SMOKE", player.global_position, true),
		"a gate on one entrance is not a gate")
	_check("...and the refusal says which problem it is",
		cmd._link_refusal() == "LINK LOST", cmd._link_refusal())

	# ── 2. recovery does not hand it straight back ──
	player.signal_integrity = 1.0
	player.lock_signal(0.0)
	if "_ekill_latched" in player:
		player._ekill_latched = false
	cmd._tick_link(0.1)      # the edge: link is up, window arms
	_check("the bar coming back does NOT hand the squad back", cmd.link_down(),
		"a one-frame flicker would otherwise restore command mid-firefight")
	_check("...and the readout says it is resyncing",
		cmd._link_refusal().begins_with("RESYNC"), cmd._link_refusal())
	cmd._tick_link(cmd.resync_seconds + 0.2)
	_check("...and after the window it commands again", not cmd.link_down())

	# ── 3. the squad goes down with you, to a floor ──
	var squad = cmd.get_selected_squad()
	if squad == null or squad.squad_members.is_empty():
		print("SKIP  squad drag: no squad deployed in this boot to lean on")
	else:
		var m = squad.squad_members[0]
		m.signal_integrity = 1.0
		player.receive_signal_damage(1.0)
		player.lock_signal(30.0)
		for _i in 40:
			cmd._tick_link(0.1)
		_check("a dead uplink drags the squad's own link down",
			m.signal_integrity < 0.99,
			"member sits at %.2f" % m.signal_integrity)
		_check("...but floors at critical rather than e-killing them",
			m.signal_integrity >= AI.SIGNAL_CRITICAL - 0.05,
			"member fell to %.2f, below the %.2f floor" % [m.signal_integrity, AI.SIGNAL_CRITICAL])

	# ── 4. fails open ───────────────────────────
	cmd.player = null
	_check("no player to ask means orders are never refused", not cmd.link_down(),
		"failing closed would lock the player out over an unrelated fault")

	_finish()


func _find(n: Node, method: String) -> Node:
	if n.has_method(method):
		return n
	for c in n.get_children():
		var f := _find(c, method)
		if f != null:
			return f
	return null


func _finish() -> void:
	print("")
	print("LINK FAILURES: %d" % _fail)
	print("ALL LINK CHECKS PASS" if _fail == 0 else "LINK CHECKS FAILED")
	quit(1 if _fail > 0 else 0)
