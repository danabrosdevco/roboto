extends StaticBody3D
class_name CaptureTap

# ─────────────────────────────────────────────
# CAPTURE TAP — the thing that holds a compute core for you.
#
# You work a core's terminal; that calls one of these. It flies in, docks on the
# core's head, and from that moment the core is yours and pays. Shoot it off and
# the core goes NEUTRAL — not back to them, so there is a scramble rather than a
# flip. docs/briefs/CAMPAIGN_REWORK.md §12.3.
#
# WHY THE FLIGHT IS NOT CONTESTABLE. An earlier draft had the drone shootable on
# approach, and that is a loss the player has no play against: a tap killed 500 m
# out, by something they cannot see and could not have reached. So the flight is
# spectacle and the DOCK is gameplay. It arrives. What you defend is what lands.
#
# PLACEHOLDER GEOMETRY. Generated here rather than modelled, the same way the
# departure lever's handle is, so the system can be built and played before
# TERRAIN draws the real one. docs/briefs/CAMPAIGN_REWORK.md §13.2 has the art.
#
# NO _process. The descent is a Tween; after that this node does nothing until
# something shoots it.
# ─────────────────────────────────────────────

signal docked(tap: CaptureTap)
signal damaged(remaining: int, amount: int)
signal destroyed(tap: CaptureTap)

## How far above the core it appears, and how long it takes to come down. The
## flight reads as an arrival rather than a spawn, which is the whole job.
@export var approach_height: float = 10.0
## HOW FAR OUT IT STARTS, not just how high. It comes in ACROSS the view at a
## shallow angle rather than down out of the sky — 21 m of lateral travel
## against 10 m of height — because straight down is the one direction a
## player standing at a core is not looking. The first cut dropped straight
## down from 22 m — which is the one direction a player on the ground is not
## looking, over in 2.6 s, and the first playtest of the bunker reported simply
## not seeing it arrive. Coming in across the view at a slant is the whole
## difference between an arrival and a spawn.
@export var approach_offset: Vector3 = Vector3(18.0, 0.0, 12.0)
@export var flight_seconds: float = 5.0

@export var health: int = 120
@export var max_health: int = 120
## PLAYER, so the enemy's hostility checks pick it as a target. That is the
## entire recapture mechanic — see the note in §12.3 on why no AI needs to
## learn to channel anything.
@export var faction: Enums.Factions = Enums.Factions.PLAYER
## Reported to cover scoring and the AI's obstacle checks. A tap is small and
## sits on top of a core; nothing should be taking cover behind it.
@export var obstacle: bool = false

## WHAT IT TURNS INTO WHEN IT LANDS.
##
## The flying pod is a delivery, not the thing that holds the core. On landing
## it frees itself and leaves a CaptureAnchor — a Nest-derived structure with
## health that the enemy can actually target and shoot. See capture_anchor.gd
## for why it has to be built that way.
##
## THE DEFAULT IS A CONST SO NOBODY HAS TO BUILD A TAP TO READ IT.
## holdable_core.start_held() wants this scene without wanting a tap, and it
## used to get it with `_Tap.new().anchor_scene` — which stood up a whole
## StaticBody3D, read one field and dropped it unparented and unfreed. An
## orphaned node that still holds a Resource SEGFAULTS Godot 4.3 at exit:
## ObjectDB's final sweep deletes it after the servers owning its RIDs are
## gone, so the resource's destructor frees an RID into a dead server. That
## one line was exit 139 on test_site_win, test_hillfort_live and
## test_core_retake_live — the three suites that reach start_held() — and a
## leak on every capture in a real run. Read the const; never `.new()` a Node
## to read a default.
const DEFAULT_ANCHOR_SCENE := preload("res://Character/characters/ai/capture_anchor.tscn")

@export var anchor_scene: PackedScene = DEFAULT_ANCHOR_SCENE

var alive: bool = true
var landed: bool = false
var _bleed: float = 0.0
var _mesh: MeshInstance3D = null
var _rotors: Node3D = null


func _ready() -> void:
	if max_health < health:
		max_health = health
	set_physics_process(false)
	_build_body()
	_descend()


## A LIFT DRONE YOU CAN ACTUALLY SEE ARRIVE.
##
## The first cut was a 0.55 m box. It flew the right path and nobody ever saw
## it: starting 14 m up and 13 m out, a half-metre crate is about ten pixels
## against a mountain, and by the time it lands it is a crate on a four-metre
## pillar. The playtest reported "the drones never came" — they came every
## time. A render of the descent found it as a speck on the skyline.
##
## So the body is sized to READ AT RANGE, which is the whole job: four rotor
## booms around a slung hull, lit, so the silhouette says aircraft from the far
## side of the bowl. SPAN is the number that matters — it is 3.4 m across,
## nearly twice the width of the core it lands on.
##
## Generated rather than modelled, the same way the departure lever's handle
## is, so the system can be played before TERRAIN draws the real one.
## docs/briefs/CAMPAIGN_REWORK.md §13.2 and §12.9 have the two real drone
## classes this stands in for.
## THE TICK — TERRAIN's model, in place of the generated quadcopter.
##
## It is the thing that comes in and hacks a core, and it now looks like one:
## a drum body on four barbed legs with three ducted rotors and a sensor
## cluster. docs/concepts/hack_tick.png is where it came from.
##
## ITS RIG ONLY, NOT THE WHOLE SCENE. Character/characters/ai/tick.tscn is a
## CharacterBody3D with a script, a nav agent, a detection area and the
## "enemies" group on it — it is an AI unit in its own right. Instancing that
## whole thing to use as a prop would put a live hostile in the middle of the
## player's capture. So this takes the Rig subtree, which is the model, and
## frees the rest.
##
## WHAT THE PLACEHOLDER GOT RIGHT AND THIS KEEPS: the thing has to READ AT
## RANGE. The first cut was a 0.55 m box that nobody ever saw arrive, and the
## playtest reported "the drones never came" when they came every time. If the
## tick turns out to be smaller than the 3.4 m span the box was grown to, that
## is the number to revisit — see tools/shot_drone.gd, which photographs it.
const TICK := preload("res://Character/characters/ai/tick.tscn")


func _build_body() -> void:
	var whole := TICK.instantiate()
	var rig := whole.get_node_or_null(^"Rig")
	if rig == null:
		push_warning("CaptureTap: tick.tscn has no Rig, so the tap has no body and will arrive invisible. The model has been renamed.")
		whole.queue_free()
		return
	# Off the AI body BEFORE that body is freed, and before this is added to
	# the tree — a reparent of a node whose owner is going away loses it.
	whole.remove_child(rig)
	add_child(rig)
	rig.name = "Rig"
	whole.queue_free()
	_mesh = _first_mesh(rig)
	# THE ROTORS, for the spin. The tick carries three in a FanTower; turning
	# the tower is one tween against three meshes.
	_rotors = rig.get_node_or_null(^"FanTower")
	if _rotors == null:
		push_warning("CaptureTap: the tick has no FanTower, so its rotors will not turn. Not fatal; it will fly in still.")

	# THE INTERACT/DAMAGE VOLUME stays generated. It is gameplay, not art, and
	# the model's own collision belongs to the AI body that was just freed.
	var solid := StaticBody3D.new()
	solid.name = "Body"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.40, 1.30, 1.40)
	cs.shape = box
	solid.add_child(cs)
	add_child(solid)


## The first MeshInstance3D under the rig, which is what the damage flash and
## the dissolve act on.
func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null
func _spin() -> void:
	if _rotors == null:
		push_warning("CaptureTap: no rotor node, so the drone arrives perfectly still.")
		return
	var t := create_tween().set_loops()
	t.tween_property(_rotors, ^"rotation:y", TAU, 0.9).from(0.0)


## Comes down from overhead onto wherever it was placed. Position is set by the
## CapturePoint before this runs, so the tween's destination is just where we
## already are.
func _descend() -> void:
	var rest := position
	position = rest + Vector3.UP * approach_height + approach_offset
	var t := create_tween()
	t.tween_property(self, ^"position", rest, flight_seconds) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(_on_landed)


func _on_landed() -> void:
	landed = true
	docked.emit(self)




# TWO ARGUMENTS, ALWAYS. Every damage source in this project calls
# apply_damage(amount, source) — the one-parameter form raises "too many
# arguments" and the thing silently cannot be shot. See breakable_panel.gd,
# which learned this the same way.
func apply_damage(damage, _source = null) -> void:
	if not alive:
		return   # already down; a second hit on a dying thing is not an error
	health -= int(damage)
	damaged.emit(maxi(health, 0), int(damage))
	if health > 0:
		_flash()
		return
	alive = false
	destroyed.emit(self)
	queue_free()


## A hit read, until there is an effect for it. Brightens and settles, which is
## at least legible from a distance.
func _flash() -> void:
	if _mesh == null:
		push_warning("CaptureTap: no mesh, so a hit on it shows nothing. Was _build_body skipped?")
		return
	var mat := _mesh.material_override as StandardMaterial3D
	if mat == null:
		return   # a material override is always set in _build_body; nothing to flash
	var t := create_tween()
	t.tween_property(mat, ^"emission_energy_multiplier", 3.0, 0.05)
	t.tween_property(mat, ^"emission_energy_multiplier", 0.8, 0.25)
