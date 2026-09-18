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
