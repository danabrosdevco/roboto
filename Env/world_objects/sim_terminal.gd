extends Node3D
class_name SimTerminal

# ─────────────────────────────────────────────
# THE SIM ARENA'S DOOR, in the depot.
#
# docs/briefs/SIM_ARENA_MODE.md. The arenas came off the operations table
# because a free action must not look like a costly one — but that left the
# sim with no way in. This is it: something in the base you walk up to and
# press F on, which opens SimArenaUI.
#
# BUILT IN CODE, NOT AUTHORED INTO THE DEPOT. The same reasoning Induction
# writes down at the top of its own file: the depot is TERRAIN's level, and a
# level should not carry nodes that belong to a system. One line in campaign.gd
# puts this in when you arrive at base; nothing in maps/ changes.
#
# PLACEHOLDER GEOMETRY, like the departure lever's handle and the slice's
# cores. A cabinet and a lit screen, generated here, so the mode is reachable
# and playable before anyone models the real thing.
#
# IT OWNS THE FIGHT, TOO. The screen builds a LabMatchup and emits it; this
# turns that into a running Laboratory. Keeping both ends in one file means the
# thing that opens the door is the thing that knows what is behind it.
# ─────────────────────────────────────────────

const _UI := preload("res://Character/hud/sim_arena_ui.gd")
const _Lab := preload("res://Managers/lab.gd")
const _Plan := preload("res://Campaign/lab/lab_plan.gd")
const INTERACTIBLE := preload("res://Env/world_objects/components/template_interactible.tscn")

## Where it stands, relative to the level origin. The depot's own furniture is
## authored; this is dropped beside it.
@export var place: Vector3 = Vector3(6.0, 0.0, -4.0)
@export var prompt: String = "SIM ARENA"

var interactible: Interactible
var _ui: Control = null
var _layer: CanvasLayer = null
var _lab: Node = null


func _ready() -> void:
	position = place
	_build_body()
	_wire()


func _build_body() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.18, 0.19)

	var cab := MeshInstance3D.new()
	cab.name = "Cabinet"
	var cm := BoxMesh.new()
	cm.size = Vector3(0.9, 1.5, 0.5)
	cab.mesh = cm
	cab.material_override = mat
	cab.position = Vector3(0.0, 0.75, 0.0)
	add_child(cab)

	var solid := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = cm.size
	cs.shape = box
	solid.add_child(cs)
	solid.position = cab.position
	add_child(solid)

	# A LIT SCREEN, in the compute cyan, so it reads as a console rather than a
	# crate at the distance you first see it from.
	var face := MeshInstance3D.new()
	face.name = "Screen"
	var fm := BoxMesh.new()
	fm.size = Vector3(0.74, 0.5, 0.04)
	face.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = HUDPalette.SIGNAL
	fmat.emission_enabled = true
	fmat.emission = HUDPalette.SIGNAL
	fmat.emission_energy_multiplier = 1.6
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face.material_override = fmat
	face.position = Vector3(0.0, 1.1, 0.26)
	add_child(face)


func _wire() -> void:
	interactible = INTERACTIBLE.instantiate()
	add_child(interactible)
	# LAYER 3, not the template's 1. The player's InteractRaycast is mask 2 and
	# layer 1 never meets it — the ray goes straight through and no prompt
	# appears. Cost a session on the operations table; see ops_table.gd.
	interactible.collision_layer = 3
	interactible.type = Enums.InteractTypes.OBJECTIVE
	interactible.destroy_on_use = false
	interactible.disable_on_use = false
	interactible.position = Vector3(0.0, 1.0, 0.0)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.4, 2.0)
	cs.shape = box
	interactible.add_child(cs)
	interactible.interacted.connect(_on_interacted)


func get_prompt() -> String:
	return prompt


# ── The screen ───────────────────────────────────────────────────────────────

func _on_interacted(_source = null) -> void:
	if _ui != null and is_instance_valid(_ui):
		return   # already open; pressing again is harmless
	var cm := get_tree().get_first_node_in_group("campaign")
	if cm == null:
		push_warning("SimTerminal: no campaign, so there is no training to list and no catalogue to build a fight from.")
		return
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)
	_ui = _UI.new()
	_ui.campaign = cm
	_ui.catalogue = cm.catalogue
	_layer.add_child(_ui)
	_ui.closed.connect(_close)
	_ui.training_chosen.connect(_on_training)
	_ui.fight_requested.connect(_on_fight)
	# PauseHold rather than get_tree().paused, for the reason world.gd writes
	# out at length: something else always wants the pause too.
	PauseHold.take(&"sim_arena")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close() -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_ui = null
	PauseHold.release(&"sim_arena")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Training is an ordinary deployment — a sim mission is still a mission, it
## just costs nothing. Selecting it is exactly what the operations table used to
## do, so the campaign needs no new path.
func _on_training(mission_id: StringName) -> void:
	var cm := get_tree().get_first_node_in_group("campaign")
	if cm == null or not cm.has_method("select_mission"):
		push_warning("SimTerminal: no campaign to deploy through, so the exercise cannot start.")
		return
	_close()
	cm.select_mission(mission_id)


## A fight the player built. Handed to the Laboratory, which already knows how
## to seat two sides facing each other on the proving ground.
func _on_fight(matchup: Resource, lead: bool) -> void:
	if matchup == null:
		push_warning("SimTerminal: no matchup, so there is no fight to run.")
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		world = _find_world(get_tree().root)
	if world == null:
		push_warning("SimTerminal: no World, so the Laboratory has nowhere to put the fight.")
		return
	_close()
	var plan = _Plan.new()
	plan.title = "Sim Arena"
	plan.matchups = [matchup] as Array[Resource]
	_lab = _Lab.new()
	_lab.name = "SimFight"
	_lab.plan = plan
	_lab.world = world
	# SPECTATE OR LEAD. A measurement run is always watched so the player
	# cannot affect the numbers; this is not a measurement.
	_lab.spectate = not lead
	get_tree().root.add_child(_lab)
	_lab.run()


func _find_world(n: Node) -> Node:
	if n is World:
		return n
	for c in n.get_children():
		var f := _find_world(c)
		if f != null:
			return f
	return null
