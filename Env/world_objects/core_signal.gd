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
var _circle: MeshInstance3D
var _circle_mat: StandardMaterial3D
## How far either side of the capture point to look for the floor. Generous
## downward because a core can sit on a gantry over a drop; short upward so an
## indoor ring measures its own floor and not the ceiling above it.
const CAST_UP := 1.5
const CAST_DOWN := 50.0


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
	# TOP-LEVEL, FOR THE SAME REASON THE RING IS — see _seat_deck. The collar is
	# deck furniture and the beacon is column furniture, and _dress() moving
	# this node to a BeaconMount used to drag the deck up the column with it.
	# The human caught this one in a render too, after the ring was fixed: a
	# teal hoop hanging five metres over a bunker, "an objective floating in
	# the air". Fixing the ring and leaving its sibling was the mistake.
	_collar.top_level = true
	add_child(_collar)

	# THE STANDING CIRCLE — where you have to be, drawn on the ground.
	#
	# The collar above frames the CORE. This frames the CAPTURE, and they are
	# not the same ring: the collar sits at the plinth's edge and the circle
	# sits at channel_range, which is metres further out and is the only one
	# that answers "am I close enough".
	#
	# Reported from play as "the ring is not visible" once the real core art
	# went in — and it was right, because the only ring on screen was hugging a
	# structure that had got big enough to hide it. A capture is ten seconds of
	# standing still and had nothing on the floor saying where.
	#
	# READ OFF THE CORE, never a copy. channel_range is the rule; a second
	# number here would be a ring that lies about where the edge is, which is
	# worse than no ring at all.
	var reach: float = float(core.channel_range) if core != null \
		and "channel_range" in core else 7.0
	_circle = MeshInstance3D.new()
	_circle.name = "StandingCircle"
	var ring := TorusMesh.new()
	ring.inner_radius = maxf(reach - 0.18, 0.2)
	ring.outer_radius = reach
	ring.rings = 48
	_circle.mesh = ring
	_circle_mat = _emissive()
	# FAINT UNTIL IT MATTERS. A hostile core's circle is a hint; it brightens
	# when you are working it. See _on_progress.
	_circle_mat.emission_energy_multiplier = 0.35
	_circle.material_override = _circle_mat
	# NOT CARRIED BY THIS NODE'S TRANSFORM, which is the whole reason the ring
	# needed fixing. The beacon frames the SITE from across the map and the ring
	# frames the CAPTURE at your feet, and site_slice._dress() moves this node
	# to a BeaconMount so the column clears a bunker's roof — which took the
	# ring up with it. Every one of the ten bunkers drew its circle 5 m in the
	# air and 15.6 m sideways, round the beacon instead of round the terminal
	# you actually press. Identical on all ten, because it is a fixed offset in
	# the kit rather than ten authoring mistakes.
	#
	# top_level cuts the ring loose from that move; _seat_deck() then puts it
	# where the channel is REALLY measured. Surface cores are unaffected — their
	# terminal sits on the core, so the ring lands where it already was.
	_circle.top_level = true
	add_child(_circle)
	_seat_deck()
	# AND AGAIN AFTER THE FIRST PHYSICS STEP. Two things are not ready yet at
	# this point and both of them matter:
	#
	#   - _dress() moves this node to the beacon mount AFTER add_child returns,
	#     and on a core seated by a patch script the interactible is wired a
	#     step later still, so the centre read above can be the wrong one.
	#   - the level's colliders are not in the physics world until a step has
	#     run, so the ground cast in _seat_deck finds nothing and falls back.
	#
	# ONE-SHOT, not a _process: this fires once, re-reads both, and disconnects
	# itself. Seating twice is cheap; a ring that cached a wrong centre is a
	# capture the player cannot find.
	get_tree().physics_frame.connect(_seat_deck, CONNECT_ONE_SHOT)


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
	# THE CIRCLE BRIGHTENS WITH THE WORK, so the thing you are standing in is
	# also the thing telling you how far through you are. It carries the same
	# fraction both ways: HoldableCore._reverse_tick emits 1.0 falling to 0.0
	# while they take it back, so a core slipping away dims on the floor in
	# front of you without needing a second channel of its own.
	if _circle_mat != null:
		_circle_mat.emission_energy_multiplier = 0.35 + 2.6 * f


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
	# AND THE MACHINE ITSELF, not just the dressing. The beacon, collar and beam
	# above are all nodes THIS script built, so recolouring them was easy and
	# looked complete — while the core's own 18-to-33 painted fins and lit
	# slots kept the amber the generator baked in, and a captured core went on
	# advertising itself as the enemy's. core_pulse.gd owns those materials and
	# the long version of why only `emission` is written.
	_recolour_model(_base_colour)
	if h == 2:
		_start_beacon()
	else:
		_stop_beacon()


## Hand the colour to the core model's own pulse script, wherever it is under
## the core. Found by method rather than by path: the model is a generated
## block scene whose node names change when the generator is rerun, and a path
## into it would be silently stale rather than loudly wrong.
func _recolour_model(c: Color) -> void:
	if core == null or not is_instance_valid(core):
		return   # already warned at ready; a core with no body is not this node's bug
	for n in core.find_children("*", "", true, false):
		if n.has_method(&"set_faction_colour"):
			n.call(&"set_faction_colour", c)
			return
	push_warning("CoreSignal: %s has no core_pulse under it, so the machine keeps its old colour when the holder changes." % name)


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


## PUT THE STANDING CIRCLE WHERE THE CHANNEL IS ACTUALLY MEASURED.
##
## holdable_core._physics_process tests
## `_player.global_position.distance_to(interactible.global_position)` against
## channel_range, falling back to the core's own origin. That point — not this
## node, not the beacon mount, not the bunker host — is the centre the player
## has to be inside. The ring is the on-screen statement of that rule, so it
## reads the same field rather than keeping a second copy, for exactly the
## reason the radius does.
##
## Y COMES FROM THE GROUND, found by casting. The first cut took it from the
## capture point itself on the assumption that the interactible sits at the
## foot of its collision box. It does not: TerminalFace is 1.36 m up the
## revetment, so every bunker ring hung at chest height — better than the 5 m
## it started at, and still not something you can stand in. The ground is the
## only thing that knows where the ground is.
##
## THE FALLBACK IS LOUD, because a ring that silently defaults to the capture
## point looks almost right and is exactly the bug this replaced.
func _seat_deck() -> void:
	# BOTH OR NEITHER. The ring and the collar are one piece of deck furniture
	# and seating only one of them is how this bug survived its first fix.
	var has_ring: bool = _circle != null and is_instance_valid(_circle)
	var has_collar: bool = _collar != null and is_instance_valid(_collar)
	if not has_ring and not has_collar:
		push_warning("CoreSignal: nothing to seat on the deck, so this capture has no ring and no collar to say where to stand.")
		return
	var at: Vector3 = _capture_centre()
	var y: float = at.y
	var world := get_world_3d()
	if world != null:
		var q := PhysicsRayQueryParameters3D.create(
			at + Vector3(0.0, CAST_UP, 0.0), at - Vector3(0.0, CAST_DOWN, 0.0))
		# EXCLUDE THE MACHINE ITSELF, or the cast lands on its own plinth.
		#
		# OFF THE HOST, NOT OFF `core`. The HoldableCore is a bare script node
		# seated ON the prefab — it owns no collision at all, so excluding it
		# excludes nothing and the cast stops 0.53 m up on the bund. That is
		# the core's own kerb, not the floor, and it put every surface ring
		# half a metre in the air on the first attempt at this. The host is
		# this node's parent, which is the prefab root for a surface core and
		# SiteBunker for a bunker, and it is the thing that owns the bodies.
		var skip: Array[RID] = []
		var host := get_parent()
		if host != null:
			for b in _solids(host):
				skip.append(b.get_rid())
		q.exclude = skip
		var hit := world.direct_space_state.intersect_ray(q)
		if hit.is_empty():
			push_warning("CoreSignal: found no ground under %s's capture point, so its ring and collar stay at the terminal's own height and may hang in the air." % String(core.name) if core != null else "a core")
		else:
			y = float(hit.position.y)
	else:
		push_warning("CoreSignal: no physics world yet, so %s's ring and collar are seated at the terminal height until they are re-seated." % String(core.name) if core != null else "a core")
	# ON the deck, not in it — a torus centred at 0 is half underground. The
	# collar rides a touch higher than the ring because it is the thicker tube
	# of the two and would otherwise bury half its section in the floor.
	if has_ring:
		_circle.global_position = Vector3(at.x, y + 0.06, at.z)
	if has_collar:
		_collar.global_position = Vector3(at.x, y + 0.17, at.z)


func _capture_centre() -> Vector3:
	if core == null or not is_instance_valid(core):
		return global_position
	var it = core.get("interactible")
	if it != null and is_instance_valid(it) and it is Node3D:
		return (it as Node3D).global_position
	return (core as Node3D).global_position


func _solids(n: Node) -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	if n is CollisionObject3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_solids(c))
	return out
