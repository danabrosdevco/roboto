extends Node3D
class_name CoreSignal

# ─────────────────────────────────────────────
# CORE SIGNAL — what a capture LOOKS and SOUNDS like.
#
# HoldableCore already fires everything worth hearing: three beats, a progress
# fraction, an interruption, a dock, a loss, a change of owner. None of it had
# a listener, so the whole system ran silently and the first playtest of the
# slice reported that the map looked unchanged — every mechanic working and
# nothing to perceive. docs/briefs/CAMPAIGN_REWORK.md §13.2.
#
# A SEPARATE NODE ON PURPOSE. The core is gameplay and this is presentation,
# and keeping them apart means the real art can replace this without touching
# the state machine — the same reason the slice attaches to Valley Basin as one
# node. Deleting this changes nothing about who owns what.
#
# PROCEDURAL, like the departure lever's handle. Two meshes, a light and six
# sounds that already exist in the project. §13.2 has the real article.
#
# NO _process, and NO coroutines. Everything here is a signal handler or a
# Tween — a tween is killed with its node, where an `await` on process_frame
# outlives the tree at quit and takes the shutdown down with it.
# ─────────────────────────────────────────────

## The HoldableCore this dresses. Typed loosely: a brand-new `class_name` is
## not visible to another script until the editor rescans, and this project
## cannot run --import. Whoever builds this wires it.
@export var core: Node3D

## WHERE THE CLIMB ENDS. -1 takes the core's own dock height, which is the top
## of the pillar and where a tap lands.
@export var shaft_height: float = -1.0

## The sounds. Exported rather than hardcoded because which sound belongs on
## which beat is a feel judgement and not one a parse check can make — these
## are the closest fits already in the project, not a final answer.
@export var sound_contact: AudioStream = preload("res://sounds/sfx/psx ui sfx/ConfirmK.wav")
@export var sound_override: AudioStream = preload("res://sounds/sfx/psx ui sfx/ConfirmH.wav")
@export var sound_commit: AudioStream = preload("res://sounds/sfx/scanners/scanner_success.wav")
@export var sound_interrupted: AudioStream = preload("res://sounds/sfx/scanners/scanner_fail.wav")
@export var sound_docked: AudioStream = preload("res://sounds/sfx/psx ui sfx/DropB.wav")
@export var sound_lost: AudioStream = preload("res://sounds/sfx/scanners/scanner_fail.wav")

## How far the beats carry. A capture is a thing the whole site reacts to, so
## it should be audible from further than you can shoot.
@export var audible_metres: float = 70.0

## How tall the beacon column stands. Above the trench walls and the tower's
## shoulder, so a core is findable from the pass you land at.
@export var BEACON_HEIGHT: float = 34.0

var _light: OmniLight3D = null
var _collar: MeshInstance3D = null
var _collar_mat: StandardMaterial3D = null
var _band: MeshInstance3D = null
var _band_mat: StandardMaterial3D = null
var _voice: AudioStreamPlayer3D = null
var _beacon: Tween = null
var _beam: MeshInstance3D = null
var _beam_mat: StandardMaterial3D = null
var _base_colour: Color = HUDPalette.FAC_ADVERSARY
var _foot: float = 3.38


func _ready() -> void:
	if core == null or not is_instance_valid(core):
		push_warning("CoreSignal: no core wired, so this capture will have no light and no sound. Set `core` before adding it.")
		return
	# Asked for rather than tabled again — the core owns both numbers, and a
	# second copy of them here is a second copy that can disagree.
	if shaft_height < 0.0:
		shaft_height = float(core._dock_y()) if core.has_method("_dock_y") else 6.0
	if core.has_method("footprint"):
		_foot = float(core.footprint())
	_build()
	_connect(core)
	# The opening state arrives deferred (see holdable_core._ready), so the
	# colour and the beacon set themselves from that emit rather than here.


func _build() -> void:
	# A COLLAR AT THE DECK, sat just outside the plinth so it frames the core
	# rather than clipping through it. This is the read when you are standing
	# on the objective looking down, where anything up the shaft is behind you.
	_collar = MeshInstance3D.new()
	_collar.name = "DeckCollar"
	_collar.mesh = _tube(_foot * 0.92, 0.34)
	_collar_mat = _emissive()
	_collar.material_override = _collar_mat
	_collar.position = Vector3(0.0, 0.17, 0.0)
	add_child(_collar)

	# THE CLIMB, AND THE WHOLE POINT OF THIS NODE.
	#
	# The first cut moved only an OmniLight3D up the shaft, and the shot of it
	# showed nothing: the core is a solid box and the light was INSIDE it, so
	# the one thing meant to read from across the bowl was occluded by the
	# object it was describing. A capture is ten seconds long and had a picture
	# for none of them.
	#
	# So the climb is a MESH that rides OUTSIDE the pillar, and the light
	# follows it for the spill onto the deck and the trench walls.
	_band = MeshInstance3D.new()
	_band.name = "ClimbBand"
	_band.mesh = _tube(_foot * 0.48, 0.42)
	_band_mat = _emissive()
	_band.material_override = _band_mat
	_band.visible = false   # nothing is being captured yet
	add_child(_band)

	_light = OmniLight3D.new()
	_light.name = "ChannelLight"
	_light.omni_range = 16.0
	_light.light_energy = 0.0
	_light.light_color = _base_colour
	# Shadows off: up to five of these on a map, moving every frame of a
	# channel. A shadow-casting moving light is the most expensive thing you
	# can add to a scene for the least read.
	_light.shadow_enabled = false
	# Clear of the pillar, for the same reason the band is.
	_light.position = Vector3(_foot * 0.7, 0.0, 0.0)
	add_child(_light)

	# THE BEACON COLUMN — how you find an objective at all.
	#
	# This replaces a billboarded Label3D reading "CORE · ADVERSARY" over every
	# point. That was slice scaffolding and it worked, but a floating label is
	# the only text in the world, it is not how this game says anything else,
	# and five of them turn a valley into a debug view.
	#
	# A column of light instead: tall enough to clear the trench walls and be
	# seen from the pass, thin enough not to obscure the thing it marks, and
	# coloured by who holds it — so the question "what is left to take" is
	# answered by looking, from anywhere, without reading.
	#
	# UNSHADED AND DOUBLE-SIDED, so it reads the same at any angle and in the
	# dark bowl Valley Basin is lit as.
	_beam = MeshInstance3D.new()
	_beam.name = "Beacon"
	var bm := CylinderMesh.new()
	bm.top_radius = 0.22
	bm.bottom_radius = 0.42
	bm.height = BEACON_HEIGHT
	bm.cap_top = false
	bm.cap_bottom = false
	_beam.mesh = bm
	_beam_mat = _emissive()
	# Faint rather than solid: a marker you can see THROUGH, so four of them do
	# not wall the bowl off.
	_beam_mat.albedo_color = Color(_base_colour.r, _base_colour.g, _base_colour.b, 0.22)
	_beam_mat.emission_energy_multiplier = 1.4
	_beam.material_override = _beam_mat
	_beam.position = Vector3(0.0, BEACON_HEIGHT * 0.5, 0.0)
	add_child(_beam)

	_voice = AudioStreamPlayer3D.new()
	_voice.name = "Voice"
	_voice.bus = &"Effects"
	_voice.max_distance = audible_metres
	_voice.unit_size = 14.0
	add_child(_voice)


## An open tube. Uncapped so it reads as a band from any angle rather than a
## disc from above, and a cylinder rather than a torus only because it is the
## simpler shape — under the headless dummy renderer every primitive mesh logs
## one "Parameter m is null", whatever type it is, and smoke.sh passes anyway
## because it boots the home base and never builds a core.
func _tube(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.cap_top = false
	m.cap_bottom = false
	return m


func _emissive() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(_base_colour.r, _base_colour.g, _base_colour.b, 0.9)
	m.emission_enabled = true
	m.emission = _base_colour
	m.emission_energy_multiplier = 0.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # an open tube seen from inside
	return m


func _connect(c: Node3D) -> void:
	# String form, because a signal declared on a script this one only knows as
	# Node3D is not resolvable as a &"name" at parse time.
	c.connect("channel_progress", _on_progress)
	c.connect("beat_reached", _on_beat)
	c.connect("channel_interrupted", _on_interrupted)
	c.connect("holder_changed", _on_holder)
	c.connect("tap_docked", _on_docked)
	c.connect("tap_lost", _on_lost)


# ── The channel ──────────────────────────────────────────────────────────────

## Progress drives the band UP the shaft, with the light riding alongside it.
## Set directly rather than tweened: this arrives every physics frame already,
## so a tween per frame would be a tween per frame.
func _on_progress(fraction: float) -> void:
	if _light == null:
		return   # _build was skipped, which only happens with no core; already warned
	var f: float = clampf(fraction, 0.0, 1.0)
	var y: float = shaft_height * f
	_light.position.y = y
	_light.light_energy = 1.2 + 3.4 * f
	if _band != null:
		_band.visible = f > 0.0
		_band.position.y = y
		_band_mat.emission_energy_multiplier = 1.0 + 3.0 * f
	if _collar_mat != null:
		_collar_mat.emission_energy_multiplier = 0.4 + 2.2 * f


## Each beat gets a sound and a visible kick, so the three moments read as
## three moments. Bleeding back down past a beat does not re-fire it — that is
## HoldableCore's `_beat` doing its job, not something to second-guess here.
func _on_beat(beat: int) -> void:
	match beat:
		0: _say(sound_contact, 0.92)
		1: _say(sound_override, 1.0)
		2: _say(sound_commit, 1.06)
	_kick(1.8)


func _on_interrupted() -> void:
	_say(sound_interrupted, 0.85)
	if _light == null:
		return   # no light to drop; already warned at ready
	# Falls rather than snaps, so a break reads as losing something.
	var t := create_tween()
	t.tween_property(_light, ^"light_energy", 0.0, 0.45)
	t.parallel().tween_property(_light, ^"position:y", 0.0, 0.45)
	if _band != null:
		t.parallel().tween_property(_band, ^"position:y", 0.0, 0.45)
		t.parallel().tween_property(_band_mat, ^"emission_energy_multiplier", 0.0, 0.45)
		t.tween_callback(func(): _band.visible = false)
	if _collar_mat != null:
		t.parallel().tween_property(_collar_mat, ^"emission_energy_multiplier", 0.0, 0.45)


func _on_docked() -> void:
	_say(sound_docked, 1.0)
	_kick(6.0)


func _on_lost() -> void:
	_say(sound_lost, 0.8)
	_kick(4.0)


# ── State ────────────────────────────────────────────────────────────────────

## Owner sets the colour of everything here, from the same palette the core's
## own pillar and the operations table use. A held core also gets a BEACON:
## the band parked at the top of the shaft, pulsing slowly, which says "this is
## yours and it is paying" from across the map. That is the one piece of
## feedback the economy has no other way to show.
func _on_holder(h: int) -> void:
	_base_colour = [HUDPalette.FAC_ADVERSARY, HUDPalette.GONE, HUDPalette.HELD][clampi(h, 0, 2)]
	if _light != null:
		_light.light_color = _base_colour
	for m in [_collar_mat, _band_mat, _beam_mat]:
		if m != null:
			m.emission = _base_colour
			m.albedo_color = Color(_base_colour.r, _base_colour.g, _base_colour.b, 0.9)
	# THE BEACON SAYS WHOSE IT IS AT A GLANCE, and a held one burns brighter —
	# "what is left to take" has to be answerable from the far side of the bowl.
	if _beam_mat != null:
		_beam_mat.emission_energy_multiplier = 2.2 if h == 2 else 1.4
		_beam_mat.albedo_color.a = 0.30 if h == 2 else 0.22
	if h == 2:
		_start_beacon()
	else:
		_stop_beacon()


## A LOOPING TWEEN, not a _process and not an await loop. set_loops() keeps it
## running for the node's life and it dies with the node; an `await` chain
## would still be pending at quit, which is how this project learned that a
## coroutine outliving the tree segfaults in cleanup.
func _start_beacon() -> void:
	_stop_beacon()
	if _light == null:
		return   # nothing to pulse; already warned at ready
	_light.position.y = shaft_height
	if _band != null:
		_band.visible = true
		_band.position.y = shaft_height
		_band_mat.emission_energy_multiplier = 2.4
	if _collar_mat != null:
		_collar_mat.emission_energy_multiplier = 1.6
	_beacon = create_tween().set_loops()
	_beacon.tween_property(_light, ^"light_energy", 2.6, 1.3).set_trans(Tween.TRANS_SINE)
	_beacon.tween_property(_light, ^"light_energy", 0.9, 1.9).set_trans(Tween.TRANS_SINE)


func _stop_beacon() -> void:
	if _beacon != null and _beacon.is_valid():
		_beacon.kill()
	_beacon = null
	if _light != null:
		_light.light_energy = 0.0
		_light.position.y = 0.0
	if _band != null:
		_band.visible = false
		_band.position.y = 0.0
		_band_mat.emission_energy_multiplier = 0.0
	if _collar_mat != null:
		# NOT to zero. A core nobody is capturing still has to be findable, and
		# the collar at a low burn is the only thing marking where one stands
		# once the label is off-screen.
		_collar_mat.emission_energy_multiplier = 0.5


# ── Parts ────────────────────────────────────────────────────────────────────

## A brief flare on top of whatever the light is doing, then back. Used for the
## beats and the dock, where something discrete happened.
func _kick(energy: float) -> void:
	if _light == null:
		return   # already warned at ready
	var held: bool = _beacon != null and _beacon.is_valid()
	var back: float = _light.light_energy
	# A kick while the beacon is looping would fight the loop for the property,
	# so pause it for the flare and hand it back afterwards.
	if held:
		_beacon.pause()
	var t := create_tween()
	t.tween_property(_light, ^"light_energy", energy, 0.06)
	t.tween_property(_light, ^"light_energy", back, 0.40)
	if held:
		t.tween_callback(_beacon.play)


func _say(stream: AudioStream, pitch: float) -> void:
	if _voice == null:
		return   # _build was skipped, which only happens with no core; already warned
	if stream == null:
		# Not silent-by-accident: an export was cleared deliberately or a file
		# moved, and a beat with no sound is exactly the bug this file exists
		# to fix, so it should say so rather than play nothing quietly.
		push_warning("CoreSignal on '%s': a beat fired with no stream, so it makes no sound." % name)
		return
	_voice.stream = stream
	_voice.pitch_scale = pitch
	_voice.play()
