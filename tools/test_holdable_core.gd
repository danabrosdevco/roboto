extends SceneTree

# ─────────────────────────────────────────────
# HOLDABLE CORES CHANGE HANDS. BOTH WAYS.
#
# The whole campaign rework rests on one property the project does not have:
# an objective that can be LOST. There is no `uncomplete` anywhere in
# Campaign/, so until this works, a defence mission is a thing the enemy
# cannot win and holding ground is a thing the player cannot fail at.
# docs/briefs/CAMPAIGN_REWORK.md §12.
#
# So this drives a HoldableCore through the whole cycle with no level, no map
# and no campaign: channel it, watch the beats, land the tap, shoot the tap
# off, and check the core goes back to whoever held it before, not neutral.
#
#   godot --headless --path . --script res://tools/test_holdable_core.gd
# ─────────────────────────────────────────────

const _Point := preload("res://Env/world_objects/holdable_core.gd")

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	await process_frame

	# A stand-in player, in the group the point looks in.
	var player := Node3D.new()
	player.name = "FakePlayer"
	root.add_child(player)
	player.add_to_group("player")

	var point = _Point.new()
	point.name = "Core"
	# Short, so the suite is not mostly waiting. The real durations are
	# 4 / 6 / 10 by size tier.
	point.channel_seconds = [0.5, 0.5, 0.5] as Array[float]
	point.size_tier = 0
	point.tap_flight_seconds = 0.15
	root.add_child(point)

	# The terminal. A bare Interactible is all the point needs — it reads
	# global_position off it for the range check and listens to `interacted`.
	var tmpl: PackedScene = load("res://Env/world_objects/components/template_interactible.tscn")
	var inter = tmpl.instantiate()
	point.add_child(inter)
	point.interactible = inter
	point._wire_interactible()
	await physics_frame

	_check("it starts hostile", int(point.holder) == int(point.Holder.HOSTILE))
	_check("...and nothing is processing while idle", not point.is_physics_processing())
	_check("...and the terminal is on a layer the player's ray masks",
		int(inter.collision_layer) == 3, "layer = %d" % int(inter.collision_layer))

	# ── the channel ─────────────────────────────
	var beats: Array = []
	point.beat_reached.connect(func(b): beats.append(int(b)))
	var docked := [false]
	point.tap_docked.connect(func(): docked[0] = true)

	player.global_position = point.global_position   # in range
	point._on_interacted(null)
	_check("F starts a channel", point.is_physics_processing())

	for _i in 60:
		await physics_frame
		if point._tap != null:
			break
	_check("the channel completes and calls a tap", point._tap != null)
	_check("...and stops processing once it has", not point.is_physics_processing())
	_check("...having fired all three beats in order", beats == [0, 1, 2],
		"beats = %s" % str(beats))

	# ── the tap lands ───────────────────────────
	# The flight is not contestable by design, so this is just waiting.
	for _i in 60:
		await physics_frame
		if docked[0]:
			break
	_check("the tap docks", docked[0])
	_check("...and the core is now the player's", point.is_held_by_player(),
		"holder = %d" % int(point.holder))

	# ── one tap per core ────────────────────────
	var before = point._tap
	point._on_interacted(null)
	await physics_frame
	_check("a second tap cannot be called while the first lives",
		point._tap == before and not point.is_physics_processing())

	# ── shooting it off ─────────────────────────
	var lost := [false]
	point.tap_lost.connect(func(): lost[0] = true)
	point._tap.apply_damage(9999, null)
	for _i in 10:
		await physics_frame
	_check("shooting the tap off loses the core", lost[0])
	_check("...and it goes BACK TO THEM, not neutral",
		int(point.holder) == int(point.Holder.HOSTILE),
		"holder = %d" % int(point.holder))
	_check("...so it can be taken again", point._tap == null)

	# ── the pod becomes a shootable structure ───
	point.channel_seconds = [0.3, 0.3, 0.3] as Array[float]
	player.global_position = point.global_position
	point._on_interacted(null)
	for _i in 90:
		await physics_frame
		if point.is_held_by_player():
			break
	_check("the pod lands and the core is held", point.is_held_by_player())
	var anchor = point._anchor
	_check("...leaving a CaptureAnchor behind", anchor != null and is_instance_valid(anchor))
	if anchor != null and is_instance_valid(anchor):
		_check("...which is a CharacterBody3D the AI can hold a reference to",
			anchor is CharacterBody3D)
		_check("...on the PLAYER faction, so enemies treat it as a target",
			int(anchor.faction) == int(Enums.Factions.PLAYER),
			"faction = %d" % int(anchor.faction))
		_check("...with health", int(anchor.health) > 0, "%d hp" % int(anchor.health))
		_check("...and the flying pod is gone", point._tap == anchor)
		var gone := [false]
		point.tap_lost.connect(func(): gone[0] = true)
		anchor.apply_damage(99999, null)
		for _i in 30:
			await physics_frame
			if gone[0]:
				break
		_check("...and destroying it LOSES the core", gone[0])
		_check("...back to THEM, the owner it was authored with",
			int(point.holder) == int(point.Holder.HOSTILE), "holder = %d" % int(point.holder))

	# ── contest ─────────────────────────────────
	# A hostile standing on the terminal should bleed progress rather than
	# freeze it: standing in a fight you are losing costs you the work.
	var foe := Node3D.new()
	foe.name = "FakeEnemy"
	root.add_child(foe)
	foe.add_to_group("enemies")
	foe.global_position = point.global_position

	point.channel_seconds = [4.0, 4.0, 4.0] as Array[float]
	point._on_interacted(null)
	for _i in 10:
		await physics_frame
	var contested_t: float = point._t
	_check("a hostile in range stops the channel advancing",
		contested_t < 0.05, "progress = %.3f" % contested_t)

	foe.queue_free()
	await physics_frame
	for _i in 20:
		await physics_frame
	_check("...and it recovers once they are dead", point._t > contested_t,
		"progress = %.3f" % point._t)

	# ── stepping away ───────────────────────────
	point.grace_seconds = 0.1
	player.global_position = point.global_position + Vector3(50.0, 0.0, 0.0)
	var broke := [false]
	point.channel_interrupted.connect(func(): broke[0] = true)
	for _i in 30:
		await physics_frame
		if broke[0]:
			break
	_check("walking away past the grace breaks the channel", broke[0])
	_check("...and stops the processing again", not point.is_physics_processing())

	# ── A HANDLER THAT ARRIVES LATE ─────────────
	# THE PLAYTEST BUG, as a test. HoldableCore takes its terminal with a
	# deferred call, which catches anything already connected. But the authored
	# InteractObjective wires itself in _on_objective_ready, and the campaign
	# calls that when it ACTIVATES the mission — frames after the slice readied.
	# So the old objective reconnected, won the press, and completed the mission
	# the old way: no channel, no colour change, no drone, no anchor.
	#
	# Loading a level on its own cannot reproduce it, because everything readies
	# in one frame. This connects a foreign handler LATE, on purpose.
	var late := Node.new()
	root.add_child(late)
	var stolen := [0]
	var thief := func(_src): stolen[0] += 1
	point.interactible.interacted.connect(thief)
	_check("(setup) a late handler is on the terminal",
		point.interactible.interacted.get_connections().size() >= 2)
	# The watchdog ticks every 0.5s for six seconds.
	for _i in 60:
		await physics_frame
	var foreign := 0
	for c in point.interactible.interacted.get_connections():
		if (c["callable"] as Callable).get_object() != point:
			foreign += 1
	_check("the watchdog takes the terminal BACK off it", foreign == 0,
		"%d foreign handler(s) left" % foreign)
	point.interactible.interacted.emit(null)
	_check("...so a late handler never sees a press", stolen[0] == 0,
		"it got %d" % stolen[0])
	late.queue_free()

	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
