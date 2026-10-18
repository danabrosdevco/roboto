extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# A CAPTURE YOU CAN SEE AND HEAR.
#
# The slice's first playtest reported that the map looked unchanged, with every
# mechanic working — HoldableCore fires six signals and nothing was listening
# to any of them. That is the failure this guards: not "the light is the right
# colour", but "something is connected at all".
#
# So the checks are deliberately about the WIRING, which is what silently
# rotted, rather than about the numbers, which are feel and belong to whoever
# can play it.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_core_signal.gd
# ─────────────────────────────────────────────

const _Core := preload("res://Env/world_objects/holdable_core.gd")
const _Signal := preload("res://Env/world_objects/core_signal.gd")

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var core := Node3D.new()
	core.set_script(_Core)
	core.size_tier = 1
	root.add_child(core)
	await process_frame

	var fx := Node3D.new()
	fx.set_script(_Signal)
	# BEFORE add_child, the way basin_slice._dress does it: _ready reads this
	# to find the shaft height, and add_child runs _ready synchronously.
	fx.core = core
	root.add_child(fx)
	await process_frame

	var light: OmniLight3D = fx.get_node_or_null(^"ChannelLight")
	var collar: MeshInstance3D = fx.get_node_or_null(^"DeckCollar")
	var voice: AudioStreamPlayer3D = fx.get_node_or_null(^"Voice")

	_check("it builds a light, a collar and a voice",
		light != null and collar != null and voice != null,
		"light=%s collar=%s voice=%s" % [light != null, collar != null, voice != null])
	if light == null:
		print("")
		print("%d failure(s)" % _fails)
		quit(1)
		return

	_check("it takes its shaft height from the core, not a second table",
		is_equal_approx(fx.shaft_height, core._dock_y()),
		"%.2f vs the core's %.2f" % [fx.shaft_height, core._dock_y()])

	# ── progress moves the light ────────────────
	core.channel_progress.emit(0.0)
	var low_y: float = light.position.y
	var low_e: float = light.light_energy
	core.channel_progress.emit(1.0)
	_check("progress CLIMBS the light up the shaft", light.position.y > low_y,
		"%.2f -> %.2f m" % [low_y, light.position.y])
	_check("...and brightens it", light.light_energy > low_e,
		"%.2f -> %.2f" % [low_e, light.light_energy])
	_check("...and the collar with it",
		(collar.material_override as StandardMaterial3D).emission_energy_multiplier > 0.0)

	# ── each beat is audible ────────────────────
	# One stream per beat, and three DIFFERENT ones, because three beats that
	# sound identical is the same as one beat.
	var heard: Array = []
	for b in [0, 1, 2]:
		core.beat_reached.emit(b)
		await process_frame
		heard.append(voice.stream)
	_check("every beat plays something", not heard.has(null), str(heard.size()))
	_check("...and the three do not sound the same",
		heard[0] != heard[1] and heard[1] != heard[2])

	# ── interruption reads as a loss ────────────
	core.channel_progress.emit(0.9)
	core.channel_interrupted.emit()
	await process_frame
	_check("an interruption plays its own sound", voice.stream != null, str(voice.stream))

	# ── ownership ───────────────────────────────
	core.holder_changed.emit(2)   # Holder.PLAYER
	await process_frame
	_check("a held core turns HELD blue",
		light.light_color.is_equal_approx(HUDPalette.HELD), str(light.light_color))
	_check("...and lights a beacon that keeps running",
		fx._beacon != null and fx._beacon.is_valid())
	_check("...parked at the top of the shaft, not the deck",
		light.position.y > fx.shaft_height * 0.5, "%.2f m" % light.position.y)

	core.holder_changed.emit(0)   # Holder.HOSTILE
	await process_frame
	_check("losing it goes back to THEIR amber",
		light.light_color.is_equal_approx(HUDPalette.FAC_ADVERSARY), str(light.light_color))
	_check("...and the beacon stops", fx._beacon == null or not fx._beacon.is_valid())

	# ── and it does not cost a frame to exist ───
	# No _process anywhere in this file; everything is a signal or a tween. A
	# regression here would put five of these on the slice's frame budget.
	_check("it never takes a _process slot",
		not fx.is_processing() and not fx.is_physics_processing())

	# ── THE STANDING CIRCLE DOES NOT RIDE THE BEACON ───
	#
	# site_slice._dress() moves this whole node to a BeaconMount so a bunker's
	# beacon column clears its roof. The ring used to be an ordinary child and
	# went up with it: all ten bunkers drew their capture circle 5 m in the air
	# and 15.6 m sideways, round the beacon instead of round the terminal you
	# press. Nothing caught it for the life of the feature, because every
	# structural check it had — does a ring exist, is it the right radius, does
	# it read channel_range — passed the whole time.
	#
	# Moving the node is the exact thing _dress does, so that is what this does.
	var ring: MeshInstance3D = fx.get_node_or_null(^"StandingCircle")
	_check("there is a standing circle at all", ring != null)
	if ring != null:
		var before: Vector3 = ring.global_position
		fx.global_position += Vector3(9.0, 5.0, 0.0)
		await process_frame
		_check("...and moving the signal to a beacon mount does not take it along",
			ring.global_position.is_equal_approx(before),
			"was %s, now %s" % [str(before), str(ring.global_position)])
		# AND IT IS ROUND THE RIGHT POINT. holdable_core measures the channel
		# from the interactible, so that is the centre — a ring anywhere else
		# is an instruction to stand somewhere that does not work.
		var centre: Vector3 = core.global_position
		if core.interactible != null:
			centre = (core.interactible as Node3D).global_position
		_check("...and it is centred where the channel is measured from",
			absf(ring.global_position.x - centre.x) < 0.01
				and absf(ring.global_position.z - centre.z) < 0.01,
			"ring %s vs capture point %s" % [str(ring.global_position), str(centre)])

	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
