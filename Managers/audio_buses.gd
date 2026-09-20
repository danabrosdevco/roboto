class_name AudioBuses

# ─────────────────────────────────────────────
# AUDIO BUSES — the four channels the options menu has sliders for.
#
#   Master ─┬─ Music      the title drone
#           ├─ Effects    everything in the world: guns, blasts, footsteps
#           ├─ Voice      squad radio chatter (Bark)
#           └─ Interface  menu, squad manager and order clicks
#
# The layout is authored in res://default_bus_layout.tres so the buses show up
# in the editor's Audio panel and in every player's bus dropdown. ensure()
# builds any that are missing anyway, so a renamed or deleted layout file costs
# you nothing but the editor view.
#
# EFFECTS IS THE DEFAULT, NOT AN OPT-IN. There are dozens of AudioStreamPlayer3D
# nodes across the weapon, chassis and level scenes and every one of them sat on
# Master. Rather than hand-edit each scene (and miss the next one someone adds),
# anything that enters the tree still on Master is moved to Effects as it
# arrives. The few things that belong elsewhere name their bus explicitly —
# Master's menu clicks and title drone, Bark, SquadHUD, SquadManagerUI — and an
# explicit bus is never touched.
#
# Static, like PauseHold: no autoload, no ready order.
# ─────────────────────────────────────────────

const MASTER    := &"Master"
const MUSIC     := &"Music"
const EFFECTS   := &"Effects"
const VOICE     := &"Voice"
const INTERFACE := &"Interface"
## Guns. A child of EFFECTS, so the effects slider still governs it, with the
## weight put back that pulling a fader always takes out. See _ensure_weapons.
const WEAPONS   := &"Weapons"

const CHILDREN: Array[StringName] = [MUSIC, EFFECTS, VOICE, INTERFACE]

static var _routing_installed: bool = false


## Makes sure every bus exists and the default routing is live. Idempotent —
## Settings calls it on first touch, and calling it again is free.
static func ensure() -> void:
	for bus in CHILDREN:
		if AudioServer.get_bus_index(bus) == -1:
			var i := AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, MASTER)
	_ensure_weapons()
	_install_routing()


## Volume as a 0..1 slider value. Squared on the way to dB so the slider feels
## even: halfway reads as half as loud (about -12dB) instead of barely quieter
## (-6dB), which is what a straight linear_to_db gives. Zero mutes outright.
static func set_volume(bus: StringName, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i == -1:
		return
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v * v, 0.00001)))


static func _install_routing() -> void:
	if _routing_installed:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_routing_installed = true
	tree.node_added.connect(func(n: Node) -> void: _route(n))
	# Anything that got into the tree before the first Settings call.
	_route_tree(tree.root)


static func _route_tree(n: Node) -> void:
	_route(n)
	for c in n.get_children():
		_route_tree(c)


static func _route(n: Node) -> void:
	if n is AudioStreamPlayer3D or n is AudioStreamPlayer or n is AudioStreamPlayer2D:
		if n.bus == MASTER:
			n.bus = EFFECTS


# ─────────────────────────────────────────────
# PAUSE
# ─────────────────────────────────────────────
# The world's sound stops when the world does. AudioServer keeps running
# through get_tree().paused, so without this every loop that happened to be
# playing carried on behind the pause menu. Held as a separate mute flag rather
# than by changing volumes, so it cannot fight the options sliders or leave the
# mix somewhere odd if a hold leaks.
#
# INTERFACE is deliberately left alone: the menu doing the pausing is the one
# thing that still needs to be heard.
static var _paused: bool = false


static func set_paused(paused: bool) -> void:
	if _paused == paused:
		return
	_paused = paused
	for bus in [EFFECTS, VOICE]:
		var i := AudioServer.get_bus_index(bus)
		if i == -1:
			continue
		# Only silence a bus the player has not already silenced themselves —
		# unmuting on resume must not turn an option back on.
		if paused:
			AudioServer.set_bus_mute(i, true)
		else:
			AudioServer.set_bus_mute(i, is_equal_approx(AudioServer.get_bus_volume_db(i), linear_to_db(0.00001)))


static func is_paused() -> bool:
	return _paused


# ─────────────────────────────────────────────
# WEAPONS
# ─────────────────────────────────────────────
# A gun quietened with the fader alone goes thin, not quiet: the ear loses the
# bottom of a sound faster than the middle as it gets softer, so -6dB on a
# rifle reads as a smaller rifle rather than a further-away one. This bus puts
# that back — a shelf of low end, a trim off the top where the spit lives, and
# a compressor so the body of the shot holds up once the level comes down.
#
# Built in code beside the rest of the routing rather than saved in a bus
# layout, for the same reason the other four are: one place to read it, and
# nothing to leave unassigned in an inspector.
static func _ensure_weapons() -> void:
	var i := AudioServer.get_bus_index(WEAPONS)
	if i != -1:
		return
	i = AudioServer.bus_count
	AudioServer.add_bus(i)
	AudioServer.set_bus_name(i, WEAPONS)
	AudioServer.set_bus_send(i, EFFECTS)

	# Bands are 32 / 100 / 320 / 1k / 3.2k / 10k.
	var eq := AudioEffectEQ6.new()
	eq.set_band_gain_db(0, 5.5)    # the thump you feel
	eq.set_band_gain_db(1, 3.5)    # the body of the report
	eq.set_band_gain_db(2, 0.5)
	eq.set_band_gain_db(3, -1.0)   # boxiness out
	eq.set_band_gain_db(4, -2.5)   # crack and spit down
	eq.set_band_gain_db(5, -3.5)
	AudioServer.add_bus_effect(i, eq)

	# Holds the tail of each shot up while the peak comes down, which is what
	# keeps a quieter gun sounding like a big one.
	var comp := AudioEffectCompressor.new()
	comp.threshold = -16.0
	comp.ratio = 3.5
	comp.attack_us = 60.0
	comp.release_ms = 180.0
	comp.gain = 3.0
	AudioServer.add_bus_effect(i, comp)

	# Automatic fire stacks: without a ceiling, four rovers firing at once is
	# just clipping.
	var limit := AudioEffectLimiter.new()
	limit.ceiling_db = -0.5
	limit.threshold_db = -1.5
	AudioServer.add_bus_effect(i, limit)
