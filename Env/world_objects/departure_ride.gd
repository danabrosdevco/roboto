extends Node3D
class_name DepartureRide

# ─────────────────────────────────────────────
# THE DEPARTURE RIDE — the train takes you there.
#
# Throw the lever in the ops car and this runs: the platform door shuts, the
# tunnel starts going past the windows, the lamps drop to a running state, the
# train slows, the door opens, and the departure pad outside it comes alive.
# Then you walk out and the pad loads the mission the way it always has.
#
# THE RIDE COVERS NO LOAD, AND THAT IS THE WHOLE POINT.
# docs/briefs/DEPARTURE_RIDE.md has the long version. The short version: the
# obvious build loads the destination during the ride, and World.load_next_level
# frees the current level before instantiating the next — so that version is a
# ride on a train being deleted underneath you. It needs threaded loading,
# arrival staging in every mission, and a cut hidden in a door animation.
# Getting off the train FIRST deletes all three. Nothing here loads anything.
#
# NOTHING IN THE TRAIN MOVES EITHER. Moving it would mean moving the player, the
# squad and the physics with it. A bar of light slides along the tunnel wall 20 m
# out and eight window apertures a side turn that into motion —
# Env/world_objects/tunnel_scroll.gdshader.
#
# WHY THE LAMPS DIM AND DO NOT FLICKER. tools/build_railhead.gd is explicit that
# Home Command lights "no flicker, no exceptions", and it is right: real train
# interiors do not strobe, their windows do. Dimming to a running state and
# letting the outside do the moving is both truer to their rule and more
# convincing than fighting it.
#
# _physics_process IS ENABLED ONLY DURING THE RIDE. The scroll is an integral of
# speed over time and a Tween cannot integrate, so the tween shapes the speed
# curve and physics does the one multiply-and-add. It is off at _ready and off
# again the moment the train stops.
# ─────────────────────────────────────────────

const SCROLL := preload("res://Env/world_objects/tunnel_scroll.gdshader")
const DOOR_STEEL := preload("res://textures/PSX_Textures/stratcom_door_steel.tres")

## The art scene. Everything below is found by marker or by name under here,
## never typed as a coordinate — the same rule railhead_level.gd follows,
## because the cars change length and typed positions end up inside walls.
@export var art: Node3D
## The pad outside the platform door. Armed on arrival; refuses before it.
@export var exit_to_arm: Node3D

## Timing. Eight to twelve seconds end to end is the brief's figure.
@export var accelerate_seconds: float = 2.5
@export var cruise_seconds: float = 5.0
@export var brake_seconds: float = 3.0
@export var door_seconds: float = 1.6
## Metres a second at full rate.
##
## A PURE FEEL NUMBER — it only sets how fast the bars go past, because nothing
## is really moving. It is the speed knob, not the bar spacing: `pitch` is the
## tunnel's own lamp spacing and TERRAIN puts a rib every 8 m, so shortening
## that to fake speed would put the lights out of step with the architecture
## they are supposed to be mounted on.
##
## 26 was the first guess and read as a slow roll. At 72 and an 8 m pitch a bar
## crosses a window about every tenth of a second, which is a train going
## somewhere.
@export var line_speed: float = 72.0
## What the interior lamps fall to while running, as a fraction of their
## authored energy.
@export var running_lamp_level: float = 0.45

## Marker names. The contract with tools/build_railhead.gd.
const M_BACKDROP := ["Backdrop_Left", "Backdrop_Right"]
const M_LEAF_SHUT := "PlatformDoor_LeafClosed"
const M_LEAF_OPEN := "PlatformDoor_LeafOpen"
## Every interior light the generator made is named this way.
const LAMP_PREFIX := "Lamp_"
## And every car node.
const CAR_PREFIX := "Car"

## How far inboard of TERRAIN's tunnel plate the scrolling layer sits. Their
## plate's inner face is 0.0625 out from BACKDROP_Y and its ribs and conduits
## stand proud to 0.1875, so 0.3 clears both without z-fighting.
@export var inset: float = 0.3
## The lit band on the tunnel wall, in metres above the car floor. The windows
## see 1.25 to 3.0, so this is that plus light above and below it.
@export var band_low: float = 0.5
@export var band_high: float = 5.5
## A car's length, which is how long each plate is. One plate per car, parented
## to the car, so the layer follows if a car moves or the rake is reordered —
## the same reason TERRAIN draws its own plate per car.
@export var car_length: float = 32.0

## ─────────────────────────────────────────────
## THE WINDOW GLASS IS OPAQUE, AND THAT HID THE WHOLE EFFECT.
##
## textures/PSX_Textures/glass_dark.tres is a plain StandardMaterial3D with an
## albedo texture and no transparency set at all — so is glass_window.tres and
## so is glass_broken.tres. Every pane in the project is a solid dark panel.
## Nothing outside the train has ever been visible from inside it, which quietly
## defeats the reason TERRAIN gave the cars windows in the first place: "they
## exist to show MOVEMENT during a transition".
##
## MEASURED, not guessed. tools/shot_departure_ride.gd photographs a flooded
## tunnel plate from inside the ops car (invisible) and from outside the hull
## (a wall of light). Same plate, same frame, same shader.
##
## So the panes are cleared here, at runtime, by overriding the surface rather
## than editing the .tres: that file is TERRAIN's, it is shared by every glazed
## thing in the project, and whether glass in general should be see-through is
## their call. The override is a duplicate, so nothing else changes.
##
## Turn this off and the ride still runs — you just cannot see it.
@export var clear_the_glass: bool = true
## How much of the dark pane survives. 0 is a hole, 1 is the opaque panel it is
## today; this keeps a tint so the apertures still read as glazed.
@export var glass_alpha: float = 0.22
## Which material to clear. Only the one _glaze uses, so a change here cannot
## accidentally make a readout board or a broken pane see-through.
@export var glass_token: String = "glass_dark"

signal departed(mission)
signal arrived(mission)

var running: bool = false
var arrived_already: bool = false

var _rate: float = 0.0
var _scroll: float = 0.0
var _mats: Array[ShaderMaterial] = []
var _lamps: Array[OmniLight3D] = []
var _lamp_energy: Array[float] = []
var _leaf: Node3D
var _leaf_shut: Vector3
var _leaf_open: Vector3
var _ride: Tween
var _mission


func _ready() -> void:
	set_physics_process(false)
	if art == null:
		push_warning("DepartureRide: no art scene, so there is nothing to find the tunnel, the lamps or the door in. The ride will do nothing.")
		return
	_build_scroll()
	_find_lamps()
	_build_leaf()
	if clear_the_glass:
		_clear_glass()


# ── Built once ───────────────────────────────────────────────────────────────

## One plate per car, each a quad facing inward at the tunnel wall.
##
## THE SIDE IS TAKEN FROM THE MARKER, not assumed. Backdrop_Left is at the
## generator's +Y, which FuncGodot puts at Godot +X, and getting that backwards
## puts both plates on one side where only half the windows ever show one.
func _build_scroll() -> void:
	var sides: Array = []
	for named in M_BACKDROP:
		var m := _marker(named)
		if m == null:
			continue
		# global, then used as a car-local offset: the cars are placed along Z
		# only and the rake is offset in Y only, so car-local X IS world X. The
		# sign is what actually matters here.
		sides.append(m.global_position.x)
	if sides.is_empty():
		push_warning("DepartureRide: no '%s' markers in the art, so there is no tunnel wall to scroll and the ride will have no motion." % M_BACKDROP[0])
		return

	var cars := _named_with(CAR_PREFIX)
	if cars.is_empty():
		push_warning("DepartureRide: no '%s*' nodes in the art, so the scrolling layer has nothing to hang off and the ride will have no motion." % CAR_PREFIX)
		return

	var height: float = band_high - band_low
	var centre: float = (band_high + band_low) * 0.5
	for car in cars:
		for x: float in sides:
			var plate := MeshInstance3D.new()
			plate.name = "TunnelScroll_%s" % ("L" if x > 0.0 else "R")
			var q := QuadMesh.new()
			# size.x is the plate's own local X, which the rotation below turns
			# along the track. The shader reads local VERTEX and not UV, so this
			# is also the along-track metre scale the bars are spaced in.
			q.size = Vector2(car_length, height)
			plate.mesh = q
			var mat := ShaderMaterial.new()
			mat.shader = SCROLL
			mat.set_shader_parameter(&"half_height", height * 0.5)
			mat.set_shader_parameter(&"rate", 0.0)
			mat.set_shader_parameter(&"scroll", 0.0)
			plate.material_override = mat
			_mats.append(mat)
			car.add_child(plate)
			# Inboard of their plate, at the window band's height, and turned to
			# face the train. A quad faces its own +Z; -90 degrees about Y takes
			# +Z to -X, which is inward for the plate on the +X side.
			plate.position = Vector3(x - signf(x) * inset, centre, 0.0)
			plate.rotation.y = -PI * 0.5 if x > 0.0 else PI * 0.5


## Every interior light, with the energy it was authored at — the ride scales
## them and has to be able to put them back exactly, including the table lamp,
## which is brighter than the rest on purpose.
func _find_lamps() -> void:
	for n in _named_with(LAMP_PREFIX):
		var l := n as OmniLight3D
		if l == null:
			continue
		_lamps.append(l)
		_lamp_energy.append(l.light_energy)
	if _lamps.is_empty():
		push_warning("DepartureRide: no '%s*' lights in the art, so the interior will not change while the train runs." % LAMP_PREFIX)


## The platform door's leaf.
##
## TERRAIN DREW THE POCKET AND NOT THE LEAF, deliberately: tools/block_railhead.gd
## keeps 3.25 m of wall face clear for it with a header rail and a floor guide,
## and leaves the leaf to gameplay for the same reason the lever's handle is
## generated — a brush drawn in the .map is welded into the car's one merged
## mesh and cannot slide.
##
## Its size and its travel both come from the two markers, so neither is typed.
func _build_leaf() -> void:
	var shut := _marker(M_LEAF_SHUT)
	var open := _marker(M_LEAF_OPEN)
	if shut == null or open == null:
		push_warning("DepartureRide: no '%s'/'%s' markers, so there is no door leaf and the way out is an open hole throughout." % [M_LEAF_SHUT, M_LEAF_OPEN])
		return
	_leaf_shut = shut.global_position
	_leaf_open = open.global_position
	# The travel IS the leaf's width: it slides exactly its own span into the
	# pocket beside the opening, which is how the generator sized that pocket.
	var travel: float = _leaf_shut.distance_to(_leaf_open)
	if travel < 0.5:
		push_warning("DepartureRide: '%s' and '%s' are %.2f m apart, which is not a door's travel, so the leaf is left out." % [M_LEAF_SHUT, M_LEAF_OPEN, travel])
		return

	var body := StaticBody3D.new()
	body.name = "PlatformDoorLeaf"
	# A closed door has to actually stop you, or the gate is a picture of a
	# gate. The LevelExit's refusal is the readable half; this is the physical
	# half. Nothing is trapped by it: the lever is always reachable, and
	# railhead_level.gd only builds this when there IS a lever to open it.
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# Across the car is the thickness; along the car is the width; the height
	# is the doorway's. DOOR_H in their builder is 3.40625 and the markers sit
	# at its half-height, which is where that number comes from.
	shape.size = Vector3(0.1, 3.40625, travel)
	cs.shape = shape
	body.add_child(cs)

	var leaf := MeshInstance3D.new()
	leaf.name = "Leaf"
	var bm := BoxMesh.new()
	bm.size = shape.size
	leaf.mesh = bm
	leaf.material_override = DOOR_STEEL.duplicate()
	body.add_child(leaf)

	add_child(body)
	body.global_position = _leaf_shut
	_leaf = body


## Make the window panes see-through, per surface, without touching the shared
## material on disk. See the note on `clear_the_glass` for why this is needed
## at all and why it is done here rather than in the .tres.
##
## PER SURFACE, because FuncGodot merges a whole entity's brushes into ONE
## ArrayMesh with one surface per material — so the glass is a surface inside
## the same mesh as the hull, and a material_override on the MeshInstance3D
## would turn the entire car transparent.
func _clear_glass() -> void:
	var panes := 0
	for mi in _mesh_instances(art):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m: Material = mesh.surface_get_material(i)
			if m == null or not m.resource_path.contains(glass_token):
				continue
			var clear: BaseMaterial3D = m.duplicate() as BaseMaterial3D
			if clear == null:
				continue
			clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var tint: Color = clear.albedo_color
			tint.a = glass_alpha
			clear.albedo_color = tint
			mi.set_surface_override_material(i, clear)
			panes += 1
	if panes == 0:
		push_warning("DepartureRide: found no '%s' surface to clear, so the windows stay opaque and the ride will be invisible from inside. Has the glass material been renamed?" % glass_token)


func _mesh_instances(n: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_mesh_instances(c, out)
	return out


# ── The ride ─────────────────────────────────────────────────────────────────

## Throw the lever and this is what happens. Safe to call twice: a second call
## while running is ignored rather than restarting the sequence halfway.
func begin(mission = null) -> void:
	if running:
		push_warning("DepartureRide: already running, so this departure request is ignored rather than restarting the ride mid-journey.")
		return
	if arrived_already:
		push_warning("DepartureRide: the train has already arrived, so there is nothing to depart for. The way out is the pad.")
		return
	running = true
	_mission = mission
	set_physics_process(true)
	departed.emit(mission)

	if _ride != null and _ride.is_valid():
		_ride.kill()
	_ride = create_tween()
	# Accelerate. EASE_IN on a sine: it leans into it rather than snapping to
	# line speed, which is the one part of this a player can feel.
	_ride.tween_property(self, ^"_rate", 1.0, accelerate_seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_ride.parallel().tween_method(_set_lamp_level, 1.0, running_lamp_level, accelerate_seconds)
	_ride.tween_interval(cruise_seconds)
	# And brake. EASE_OUT, so the last bars crawl past before they stop.
	_ride.tween_property(self, ^"_rate", 0.0, brake_seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_ride.parallel().tween_method(_set_lamp_level, running_lamp_level, 1.0, brake_seconds)
	_ride.tween_callback(_on_arrived)


func _physics_process(delta: float) -> void:
	_scroll += _rate * line_speed * delta
	for m in _mats:
		m.set_shader_parameter(&"rate", _rate)
		m.set_shader_parameter(&"scroll", _scroll)


func _on_arrived() -> void:
	running = false
	arrived_already = true
	# Exactly zero, not whatever the last physics tick left, and then stop
	# integrating. A rate of 1e-7 is invisible but keeps a _physics_process
	# alive forever, which is the kind of thing that shows up as a mystery
	# millisecond six months later.
	_rate = 0.0
	for m in _mats:
		m.set_shader_parameter(&"rate", 0.0)
	set_physics_process(false)
	_set_lamp_level(1.0)
	_open_door()
	# THE PAD COMES ALIVE HERE and not when the mission was queued. Walking out
	# of a train that has not moved would deploy you from the station you are
	# already standing in.
	if exit_to_arm != null and exit_to_arm.has_method(&"arm"):
		exit_to_arm.arm()
	else:
		push_warning("DepartureRide: nothing to arm, so the departure pad's gate is whatever it was — check railhead_level.gd wired exit_to_arm.")
	arrived.emit(_mission)


func _open_door() -> void:
	if _leaf == null:
		return   # no leaf was built; _build_leaf already said why
	var t := create_tween()
	t.tween_property(_leaf, ^"global_position", _leaf_open, door_seconds) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Scale every lamp off its AUTHORED energy rather than its current one, so
## repeated calls cannot drift the interior darker and darker.
func _set_lamp_level(level: float) -> void:
	for i in _lamps.size():
		var l := _lamps[i]
		if l == null or not is_instance_valid(l):
			continue
		l.light_energy = _lamp_energy[i] * level


# ── Finding things ───────────────────────────────────────────────────────────

func _marker(named: String) -> Node3D:
	return _named_under(art, named) as Node3D


func _named_under(n: Node, named: String) -> Node:
	if n.name == named:
		return n
	for c in n.get_children():
		var f := _named_under(c, named)
		if f != null:
			return f
	return null


func _named_with(prefix: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	_collect_with(art, prefix, out)
	out.sort_custom(func(a, b): return a.name < b.name)
	return out


func _collect_with(n: Node, prefix: String, out: Array[Node3D]) -> void:
	if n is Node3D and String(n.name).begins_with(prefix):
		out.append(n)
	for c in n.get_children():
		_collect_with(c, prefix, out)
