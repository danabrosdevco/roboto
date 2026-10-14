extends MissionObjective
class_name TrainingCore

# ─────────────────────────────────────────────
# THE LAST EXERCISE TEACHES THE THING THE CAMPAIGN IS MADE OF.
#
# The three sim arenas teach shooting, then a squad in a fight. Neither of them
# teaches CAPTURING — and capturing is the entire campaign: every site is its
# cores, holding them is what pays, and losing one is how you lose ground.
# A player arriving at Hillfort having never worked a core is meeting the verb
# the whole game is built on for the first time, under fire.
#
# So the Proving Ground gets one. Same HoldableCore the real sites use, same
# channel, same drone, same anchor, same beacon — in a place where nothing is
# at stake and it can be done twice.
#
# IT IS A MissionObjective, which is what gates it to the LAST arena. The
# Proving Ground level is shared by all three, and MissionObjective._ready
# frees any objective whose id the current operation did not ask for — so
# listing `proving_capture` in arena_5_proving's active_objectives, and nowhere
# else, is the whole of the gating. No mission check in here.
#
# BUILT RATHER THAN AUTHORED, because the arena has no capture point to borrow:
# this makes its own pad, post and interactible the way SiteSlice makes the
# bunker's.
# ─────────────────────────────────────────────

const _Core := preload("res://Env/world_objects/holdable_core.gd")
const _Signal := preload("res://Env/world_objects/core_signal.gd")
const INTERACTIBLE := preload("res://Env/world_objects/components/template_interactible.tscn")

## Where it stands. SET IN THE SCENE, not here — see the two nodes in
## maps/proving_level.tscn, which is the only thing that reads this default.
##
## THE BAY, which is the 30 x 30 m floor at Godot z 59..89 behind the enemy
## blockhouse. tools/build_proving.gd built it for exactly this and says so:
## "a capture node and an extraction point in the same bay is what the bunker
## is." The core sits at z 65 and the bunker at z 83, 18 m apart, both on the
## centreline and both well inside the floor's +/-15 m edges.
##
## THE OLD NUMBERS WERE z 30 AND 37, against the 88 x 54 m arena. The rebuild
## on 2026-10-13 made that ground the enemy blockhouse, so the core would have
## been placed inside a building. tools/probe_arena_cores.gd now casts for the
## floor, asks the navmesh, checks all four pad corners and walks a path from
## the spawn — run it if these move again. The bay floor is at y 0, NOT the
## 0.5 the navmesh bakes at; placing at 0.5 floats the pad.
@export var place: Vector3 = Vector3(0.0, 0.0, 65.0)
@export var tier: int = 0
## What it is called on the beacon and in the prompt. A bunker is a core in
## everything but name — §12.7 makes taking it the thing that ends an
## operation, and the training arena teaches both verbs with one node.
@export var noun: String = "CORE"

var core: Node3D = null


func _on_objective_ready() -> void:
	position = place
	_build()


func _build() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.17, 0.19, 0.20)
	mat.emission_enabled = true
	mat.emission = HUDPalette.FAC_ADVERSARY
	mat.emission_energy_multiplier = 0.55

	# A pad, so it reads as installed rather than dropped on the floor.
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var pm := BoxMesh.new()
	pm.size = Vector3(3.4, 0.4, 3.4)
	pad.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.14, 0.15, 0.14)
	pad.material_override = pmat
	pad.position = Vector3(0.0, 0.2, 0.0)
	add_child(pad)

	var body := MeshInstance3D.new()
	body.name = "CoreBody"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 4.2, 1.0)
	body.mesh = bm
	body.material_override = mat
	body.position = Vector3(0.0, 2.1, 0.0)
	add_child(body)

	# COLLISION ON ITS OWN BODY. The interact volume is an Area3D on layer 3
	# and has to stay separate, or the player's ray stops on the pillar before
	# it reaches the thing it is trying to press.
	var solid := StaticBody3D.new()
	solid.name = "CoreSolid"
	var scs := CollisionShape3D.new()
	var sbox := BoxShape3D.new()
	sbox.size = bm.size
	scs.shape = sbox
	solid.add_child(scs)
	solid.position = body.position
	add_child(solid)

	var inter: Interactible = INTERACTIBLE.instantiate()
	inter.name = "Interactible"
	add_child(inter)
	# LAYER 3, not the template's 1 — the player's InteractRaycast is mask 2
	# and layer 1 never meets it. Cost a session on the operations table.
	inter.collision_layer = 3
	inter.type = Enums.InteractTypes.OBJECTIVE
	inter.destroy_on_use = false
	inter.disable_on_use = false
	inter.position = Vector3(0.0, 1.0, 0.0)
	var ics := CollisionShape3D.new()
	var ibox := BoxShape3D.new()
	ibox.size = Vector3(3.0, 2.6, 3.0)
	ics.shape = ibox
	inter.add_child(ics)



	# THE SAME CORE THE REAL SITES USE. Not a simplified teaching version:
	# whatever it teaches has to be what the campaign then asks for.
	core = Node3D.new()
	core.set_script(_Core)
	core.name = "Hold"
	core.size_tier = tier
	core.mark_noun = noun
	core.interactible = inter
	add_child(core)

	# The light and the sound, same as a real one. `core` is set BEFORE
	# add_child because CoreSignal reads it in _ready, and _ready fires the
	# instant it is parented.
	var fx := Node3D.new()
	fx.set_script(_Signal)
	fx.name = "Signal"
	fx.core = core
	add_child(fx)

	# SHUT UNTIL IT IS THIS ONE'S TURN. The bunker waits on the core — that is
	# the lesson, core then bunker then out — but nothing enforced the order:
	# HoldableCore._drive_authored calls complete() on capture without looking
	# at `active`, so walking past the core and pressing F on the bunker ticked
	# an objective the HUD had never shown.
	#
	# THE LAYER, not a `disabled` flag: the player's InteractRaycast is mask 2,
	# so layer 0 is simply not there to be hit and no prompt appears. Restored
	# to 3 when the prerequisite completes — 3 and not 1 for the reason above.
	#
	# _ready activates before it calls _on_objective_ready, so `active` is
	# already right here and the signal has already fired for anything that
	# starts open.
	if not active:
		inter.collision_layer = 0   # AFTER HoldableCore._wire_interactible, which sets 3
		objective_activated.connect(_on_turn_came)


## The objective ticks when the core is held — HoldableCore drives the
## MissionObjective it is parented to, both ways, exactly as it does on a site.
## Nothing extra is wired here; that is the point of using the real one.
func progress() -> Array:
	if core == null or not is_instance_valid(core):
		return [0, 1]
	return [1 if core.is_held_by_player() else 0, 1]


## Its prerequisite finished, so open it. See the lock in _build().
func _on_turn_came(_o = null) -> void:
	var inter := get_node_or_null("Interactible")
	if inter == null:
		push_warning("TrainingCore '%s': activated with no Interactible, so there is nothing to open and this capture cannot be worked." % name)
		return
	inter.collision_layer = 3


## CAPTURE THE CORE / CAPTURE THE BUNKER, built the way every other objective
## builds its line: display_name names the THING and verb() supplies the action
## — see the labelling note in mission_objective.gd.
##
## The scene used to author the whole phrase instead ("WORK THE CORE"), which
## both read badly and sidestepped the one rule the rest of the game follows.
func verb() -> String:
	return "Capture the"
