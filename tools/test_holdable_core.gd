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

	await _dock_suite()

	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


## ─────────────────────────────────────────────
## THE TAP LANDS ON THE PAD, WHICH IS A PLACE AND NOT A HEIGHT.
##
## THE BUG THIS IS ON A GATE FOR. `_call_tap` used to do
## `tap.position = Vector3(0.0, _dock_y(), 0.0)` — the core's own AXIS, at a
## height off `size_tier`. The three relay cores built by
## tools/build_core_relay.gd carry their landing pad OFF-AXIS, out on a
## cantilevered shelf at two thirds height, so that point is mid-air beside the
## crown at every size: capture dropped the drone through the model and nothing
## in the project said a word, because a prefab and a pod occupying the same
## space is not an error, it is two meshes.
##
## An art round can photograph a drone staged by hand and prove none of this.
## So this runs the REAL dock path on the REAL prefabs and measures where the
## pod stopped.
##
## THE HOST IS MOVED AND TURNED, and that is the half of it a test at the
## origin cannot see: the dock marker is read in GLOBAL space and assigned in
## the core's LOCAL space, so an identity transform passes whether or not the
## conversion is there at all. 37 degrees off the axis at (12, 3, -7) fails
## loudly if anyone ever drops the to_local.
## ─────────────────────────────────────────────
const RELAYS := {
	"small": ["res://maps/blocks/compute/compute_core_small.tscn", 0],
	"med": ["res://maps/blocks/compute/compute_core.tscn", 1],
	"large": ["res://maps/blocks/compute/compute_core_large.tscn", 2],
}
## The bund's SHORT axis at each tier, which is what footprint() has to agree
## with — it returned the long-dead 1.88 / 3.38 / 5.19 trio until this round,
## so core_signal.gd was drawing its deck collar inside the machine.
const RELAY_FOOT := {"small": 3.50, "med": 4.75, "large": 6.50}


func _dock_suite() -> void:
	for id: String in RELAYS:
		var packed := load(RELAYS[id][0]) as PackedScene
		if packed == null:
			_check("[%s] the prefab loads" % id, false, String(RELAYS[id][0]))
			continue
		# SEATED THE WAY site_slice.gd SEATS ONE: `Hold` is a child of the
		# authored capture point and a SIBLING of the `Core` model, so a core
		# that only searched its own children would find no marker. That is the
		# arrangement the eight maps ship, so it is the one under test.
		var host := Node3D.new()
		host.name = "Point_" + id
		root.add_child(host)
		host.global_position = Vector3(12.0, 3.0, -7.0)
		host.rotation.y = deg_to_rad(37.0)
		var model: Node3D = packed.instantiate()
		model.name = "Core"
		host.add_child(model)

		var hold = _Point.new()
		hold.name = "Hold"
		hold.size_tier = int(RELAYS[id][1])
		hold.tap_flight_seconds = 0.1
		host.add_child(hold)
		await physics_frame

		var dock := model.get_node_or_null(^"Dock") as Node3D
		_check("[%s] the prefab ships a Dock marker" % id, dock != null,
			"run tools/core_skeleton_dress.gd if not")
		if dock == null:
			continue
		_check("[%s] ...which the core finds from a sibling" % id,
			hold._find_dock() == dock)
		_check("[%s] ...and is NOT on the core's axis, which is the whole point" % id,
			Vector2(dock.position.x, dock.position.z).length() > 0.5,
			"dock = %s" % str(dock.position))

		hold._call_tap()
		var tap = hold._tap
		_check("[%s] the dock path calls a tap" % id, tap != null)
		if tap == null:
			continue
		var landed := [Vector3.ZERO, false]
		tap.docked.connect(func(t): landed[0] = t.global_position; landed[1] = true)
		for _i in 90:
			await physics_frame
			if landed[1]:
				break
		_check("[%s] ...which docks" % id, landed[1])
		var off: float = landed[0].distance_to(dock.global_position)
		_check("[%s] ...ON THE PAD, not on the axis" % id, off < 0.01,
			"%.3f m from the marker (pod at %s, pad at %s)" % [off, str(landed[0]), str(dock.global_position)])
		var axis: float = host.to_global(Vector3(0.0, hold._dock_y(), 0.0)).distance_to(dock.global_position)
		_check("[%s] ...and the axis it used to use is %.2f m away from the pad" % [id, axis],
			axis > 0.5, "if this ever reads 0 the pad has moved back onto the axis")

		_check("[%s] footprint() matches the bund's short side" % id,
			absf(hold.footprint() - float(RELAY_FOOT[id])) < 0.01,
			"%.2f, want %.2f" % [hold.footprint(), float(RELAY_FOOT[id])])

		host.queue_free()
		await physics_frame

	# ── AND THE FALLBACK STILL WORKS, LOUDLY ────
	# A core with no marker is the bunker and the training post, which are
	# flat-topped masts where the axis IS the pad. dock_height is how they say
	# so; without it the tier table answers and push_warnings, and
	# core_signal.gd still gets a shaft height out of _dock_y either way.
	var bare = _Point.new()
	bare.name = "Mast"
	bare.size_tier = 1
	root.add_child(bare)
	bare.dock_height = 4.9
	_check("a core with no marker docks on its own axis at dock_height",
		bare._dock_point().is_equal_approx(Vector3(0.0, 4.9, 0.0)),
		str(bare._dock_point()))
	_check("...and _dock_y agrees with it, because core_signal reads that",
		is_equal_approx(bare._dock_y(), 4.9), "%.2f" % bare._dock_y())
	bare.dock_height = -1.0
	bare._dock_hunted = false
	_check("...and with neither, the tier table answers rather than nothing",
		is_equal_approx(bare._dock_y(), 7.0), "%.2f" % bare._dock_y())
	_check("...having said so out loud", bare._dock_warned)
	bare.queue_free()
