extends Node3D
class_name DepartureLever

# ─────────────────────────────────────────────
# THE DEPARTURE LEVER — the commit.
#
# You queue an operation at the operations table. You commit to it here, by
# throwing a handle, and the train takes you there. The whole reason this is a
# lever and not a button on the table's own board is that the commit should
# cost a gesture: docs/briefs/archive/DEPARTURE_RIDE.md.
#
# WHY THE HANDLE IS GENERATED AND NOT MODELLED. TERRAIN builds the housing it
# comes out of — docs/briefs/archive/OPS_TABLE_LEVER.md — but not the handle, because
# FuncGodot merges every worldspawn brush in a car into one mesh, so a handle
# drawn in the .map could not rotate. It would also be deleted by the next
# geometry rebuild: tools/block_prefabs.gd writes those scenes from scratch.
# So the car owns the housing, tools/fit_ops_table.gd owns the empty, and this
# owns the thing that moves. Exactly the arrangement the holographic board
# already uses on the table two metres away.
#
# NO _process. The throw is a Tween, which runs on the scene tree's own
# animation step. A hand-rolled lerp would also have had to survive the player
# quitting mid-throw, and an await that outlives the tree segfaults in cleanup
# — already written down in this project at some cost.
# ─────────────────────────────────────────────

## The handle's rest and thrown angles, about the lever's local X — which in
## the ops car is the car's WIDTH axis, so the handle swings along the car.
##
## Both are negative, so the handle leans toward the player at rest and comes
## down toward them when thrown: a pull, not a push. The angles are also what
## keeps the handle clear of the operations table's interact volume, which
## ends 0.2 m inboard of the pivot and would otherwise swallow every F press
## aimed at the lever — see tools/fit_ops_table.gd for the arithmetic.
@export var stowed_degrees: float = -20.0
@export var thrown_degrees: float = -80.0
## How long the handle takes to go over. Short: this is a throw, not a lift.
@export var throw_seconds: float = 0.45

## Handle dimensions.
##
## BIG. The first cut was 0.35 m and reasoned "a lever on a table, not a
## signal-box frame" — which was wrong about what this object is for. It is the
## single commit in the whole base loop, it lives in the darkest car in the
## rake, and at 0.35 m of unlit brass it was a detail you had to go looking
## for. A signal-box frame is exactly what it should read as.
##
## Growing it is not free: the handle's arc has to stay clear of the operations
## table's interact volume and inside its own, and those are constants in
## tools/fit_ops_table.gd. tools/test_departure_lever.gd checks the arithmetic
## and fails if this outgrows them — it caught 0.60 m against the old box.
@export var arm_length: float = 0.95
@export var arm_thickness: float = 0.10
@export var knob_radius: float = 0.13

const BRASS := preload("res://textures/PSX_Textures/stratcom_brass.tres")

## ─────────────────────────────────────────────
## THE LEVER TELLS YOU WHEN IT WILL DO SOMETHING.
##
## Dark brass in the darkest car is invisible, and worse, it is invisible in
## both states — you could not tell by looking whether throwing it would do
## anything. So it is inert until an operation is queued, then it lights and
## breathes: the base's way of saying there is somewhere to go. Thrown, it
## settles to a steady burn, because the decision is made and a thing still
## flashing for attention after you have pressed it is nagging.
##
## Driven off Campaign.mission_selected rather than polled, so there is no
## per-frame work for an object that changes state twice a mission.
@export var ready_glow: Color = Color(0.98, 0.72, 0.30)
## How hard it burns at the top and bottom of its breath, and how long a
## breath takes.
@export var ready_glow_low: float = 0.35
@export var ready_glow_high: float = 1.25
@export var ready_breath_seconds: float = 1.3
## Where it settles once thrown: lit, but done.
@export var thrown_glow: float = 0.45

## Set by whoever fits this — railhead_level.gd hands over the Interactible
## that tools/fit_ops_table.gd put on the anchor, because that Interactible is
## this node's SIBLING and _find_interactible only looks at children.
@export var interactible: Interactible

## Emitted when the handle goes over with somewhere to go. The ride listens.
signal thrown(mission)
## Emitted when F lands on a lever that cannot do anything, with the reason.
##
## NOTHING LISTENS TO THIS YET, and that is deliberate rather than forgotten:
## LevelExit.exit_blocked has had no listener since it was written, so there is
## no established channel for "pressed it and it said no". The refusal the
## player ACTUALLY READS is in get_prompt(), which names the reason before they
## press. This signal is the seam for when a channel exists.
signal refused(reason: String)

enum Pose { STOWED, THROWN }

var pose: int = Pose.STOWED
var _pivot: Node3D
var _tween: Tween
## The handle's own material, kept so the glow can be driven. Duplicated in
## _build_handle — see the note there.
var _brass: BaseMaterial3D = null
var _breath: Tween = null


func _ready() -> void:
	_build_handle()
	_wire_interactible()
	_watch_campaign()
	_refresh_glow()


## React to an operation being queued or cleared, rather than asking every
## frame. mission_selected fires on every change; state_loaded covers coming
## back to a save that already had one.
func _watch_campaign() -> void:
	var campaign := get_tree().get_first_node_in_group(&"campaign")
	if campaign == null:
		push_warning("DepartureLever: no campaign in the tree, so the handle cannot light when an operation is queued. It still throws.")
		return
	if campaign.has_signal(&"mission_selected"):
		campaign.mission_selected.connect(func(_m): _refresh_glow())
	if campaign.has_signal(&"state_loaded"):
		campaign.state_loaded.connect(_refresh_glow)


# ── The handle ───────────────────────────────────────────────────────────────

func _build_handle() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_pivot.rotation.x = deg_to_rad(stowed_degrees)

	# The material is DUPLICATED, and that is load-bearing now rather than
	# merely tidy. stratcom_brass.tres is one resource shared by every brass
	# fitting on the train — the handrails, the plaques, the table's lip — so
	# lighting this one in place would set every one of them glowing.
	var brass: BaseMaterial3D = BRASS.duplicate() as BaseMaterial3D
	_brass = brass
	if brass != null:
		# Emission is switched on once and then driven by energy alone, because
		# toggling emission_enabled re-compiles the material's shader variant
		# and the first frame after each toggle hitches.
		brass.emission_enabled = true
		brass.emission = ready_glow
		brass.emission_energy_multiplier = 0.0

	var shaft := MeshInstance3D.new()
	shaft.name = "Arm"
	var bm := BoxMesh.new()
	bm.size = Vector3(arm_thickness, arm_length, arm_thickness)
	shaft.mesh = bm
	shaft.material_override = brass
	# Offset so the arm's BASE is at the pivot and not its middle: a box mesh is
	# centred on its origin, and left there the handle rotates about its own
	# waist and sinks half its length into the housing.
	shaft.position.y = arm_length * 0.5
	_pivot.add_child(shaft)

	var knob := MeshInstance3D.new()
	knob.name = "Knob"
	var sm := SphereMesh.new()
	sm.radius = knob_radius
	sm.height = knob_radius * 2.0
	# PSX-era geometry, so it sits with the rest of the train rather than being
	# the one smooth thing in the car.
	sm.radial_segments = 8
	sm.rings = 4
	knob.mesh = sm
	knob.material_override = brass
	knob.position.y = arm_length
	_pivot.add_child(knob)


# ── Being used ───────────────────────────────────────────────────────────────

func _wire_interactible() -> void:
	if interactible == null:
		interactible = _find_interactible(self)
	if interactible == null:
		push_warning("DepartureLever '%s' has no Interactible, so it cannot be thrown. Run tools/fit_ops_table.gd." % name)
		return
	# LAYER 3, not the template's default 1. The player's InteractRaycast is
	# mask 2, and layer 1 never meets it: the ray goes straight through and no
	# prompt appears. This cost a whole session on the operations table — see
	# Env/world_objects/ops_table.gd for the long version.
	interactible.collision_layer = 3
	# Throwing it once per load is correct, but destroy/disable would make the
	# handle VANISH rather than stay thrown. The pose is the state.
	interactible.destroy_on_use = false
	interactible.disable_on_use = false
	interactible.type = Enums.InteractTypes.DEPART
	interactible.interacted.connect(_on_interacted)


func _find_interactible(n: Node):
	for c in n.get_children():
		if c is Interactible:
			return c
		var f = _find_interactible(c)
		if f != null:
			return f
	return null


## What the F prompt says. The HUD prefixes "F | ".
##
## Also the only refusal the player ever sees, so it names the reason BEFORE
## they press rather than after. See the note on `refused`.
func get_prompt() -> String:
	if pose == Pose.THROWN:
		return "Departure Lever — thrown"
	var m = _queued()
	if m == null:
		return "Departure Lever — no operation queued"
	return "Depart for %s" % m.display_name


func _on_interacted(_source) -> void:
	if pose == Pose.THROWN:
		refused.emit("ALREADY THROWN")
		return
	var m = _queued()
	if m == null:
		# Not an error and not silent: the prompt already said so, and this is
		# the player trying anyway.
		refused.emit("NO OPERATION QUEUED")
		return
	pose = Pose.THROWN
	_swing_to(thrown_degrees)
	_refresh_glow()
	thrown.emit(m)


## Dark when there is nowhere to go, breathing when there is, steady once the
## handle is over. The one place the lever's three states are decided.
func _refresh_glow() -> void:
	if _brass == null:
		push_warning("DepartureLever: no handle material, so the lever cannot light. Was _build_handle skipped?")
		return
	if _breath != null and _breath.is_valid():
		_breath.kill()
	if pose == Pose.THROWN:
		_brass.emission_energy_multiplier = thrown_glow
		return
	if _queued() == null:
		_brass.emission_energy_multiplier = 0.0
		return
	# Breathing, not blinking. A blink is an alarm; this is an invitation.
	_brass.emission_energy_multiplier = ready_glow_low
	_breath = create_tween()
	_breath.set_loops()
	_breath.tween_property(_brass, ^"emission_energy_multiplier", ready_glow_high, ready_breath_seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breath.tween_property(_brass, ^"emission_energy_multiplier", ready_glow_low, ready_breath_seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## The operation the table has queued, or null. Reached through the group rather
## than the `Campaign` identifier so the lever still works in a scene with no
## campaign autoload — the same reason LevelExit looks it up that way.
func _queued():
	var campaign := get_tree().get_first_node_in_group(&"campaign")
	if campaign == null:
		return null
	if not campaign.has_method(&"selected_mission"):
		return null
	return campaign.selected_mission()


func _swing_to(degrees: float) -> void:
	if _pivot == null:
		push_warning("DepartureLever: no pivot, so the handle cannot move. Was _build_handle skipped?")
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	# EASE_OUT on TRANS_BACK: it goes over fast, overshoots the detent a little
	# and settles. A linear throw reads as a slider being dragged.
	_tween.tween_property(_pivot, ^"rotation:x", deg_to_rad(degrees), throw_seconds) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Put it back. For a departure that is cancelled rather than completed; a level
## reload gets a fresh lever and does not need this.
func reset_lever() -> void:
	pose = Pose.STOWED
	_swing_to(stowed_degrees)
