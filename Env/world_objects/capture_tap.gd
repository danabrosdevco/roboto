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
@export var anchor_scene: PackedScene = preload("res://Character/characters/ai/capture_anchor.tscn")

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
func _build_body() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.55, 0.82)
	mat.emission_enabled = true
	mat.emission = Color(0.40, 0.78, 0.95)
	mat.emission_energy_multiplier = 1.1
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	# THE HULL. Slung under the rotors, deep enough to read side-on.
	_mesh = MeshInstance3D.new()
	_mesh.name = "Pod"
	var hull := BoxMesh.new()
	hull.size = Vector3(1.30, 0.62, 1.30)
	_mesh.mesh = hull
	_mesh.material_override = mat
	add_child(_mesh)

	# THE CLAW it docks with, below the hull — the part that meets the core.
	var claw := MeshInstance3D.new()
	claw.name = "Claw"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.62
	cm.bottom_radius = 0.30
	cm.height = 0.55
	claw.mesh = cm
	claw.material_override = mat
	claw.position = Vector3(0.0, -0.56, 0.0)
	add_child(claw)

	# FOUR BOOMS AND FOUR DISCS. The silhouette is the read: a cross of rotors
	# says aircraft at a distance where no amount of detail would.
	var rotor_mat := StandardMaterial3D.new()
	rotor_mat.albedo_color = Color(0.62, 0.86, 1.0, 0.75)
	rotor_mat.emission_enabled = true
	rotor_mat.emission = Color(0.55, 0.85, 1.0)
	rotor_mat.emission_energy_multiplier = 1.6
	rotor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rotor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_rotors = Node3D.new()
	_rotors.name = "Rotors"
	add_child(_rotors)
	for corner in [Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(-1, 0, -1)]:
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.16, 0.14, 1.30)
		arm.mesh = am
		arm.material_override = mat
		arm.position = corner * Vector3(0.55, 0.0, 0.0) + Vector3(0.0, 0.18, 0.0)
		arm.look_at_from_position(arm.position, arm.position + corner, Vector3.UP)
		_rotors.add_child(arm)

		var disc := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 0.62
		dm.bottom_radius = 0.62
		dm.height = 0.05
		disc.mesh = dm
		disc.material_override = rotor_mat
		disc.position = corner * Vector3(1.05, 0.0, 1.05) + Vector3(0.0, 0.30, 0.0)
		_rotors.add_child(disc)

	# A LIGHT, so it is a moving source rather than a shape. This is what makes
	# it findable in the dark bowl Valley Basin is lit as.
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.omni_range = 18.0
	lamp.light_energy = 3.0
	lamp.light_color = Color(0.45, 0.78, 1.0)
	# Shadows off: it moves every frame of a four-second descent, and a
	# shadow-casting moving light is the most expensive thing in a scene.
	lamp.shadow_enabled = false
	lamp.position = Vector3(0.0, -0.2, 0.0)
	add_child(lamp)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.40, 1.30, 1.40)
	shape.shape = box
	add_child(shape)

	_spin()


## Rotors turn. A LOOPING TWEEN, not a _process: it is killed with the node,
## where an await chain would still be pending at quit — which is how this
## project learned a coroutine outliving the tree segfaults in cleanup.
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
