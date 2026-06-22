extends Node3D
class_name SquadObjectivePoint
 
# ─────────────────────────────────────────────
# SQUAD OBJECTIVE POINT
# Place in your level to mark locations squads
# can be ordered to advance to, defend, or withdraw to.
#
# Assign to a Squad via:
#   squad.set_objective(SquadObjective.ADVANCE, objective_point.global_position)
# ─────────────────────────────────────────────
 
@export var objective_name: String = "Objective"
 
# Optional: visually mark this in-editor with a label
@export var show_debug_label: bool = true
 
var _label: Label3D = null
 
func _ready() -> void:
	add_to_group("squad_objective_points")
	if show_debug_label and Engine.is_editor_hint() == false:
		_label = Label3D.new()
		_label.text = objective_name
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.modulate = Color(1.0, 0.8, 0.0)
		add_child(_label)
