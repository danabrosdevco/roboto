@tool
extends Node3D
class_name PatrolPoint

# ─────────────────────────────────────────────
# PATROL POINT — a stop on a route, visible while you're building the level and
# gone the moment you press play.
#
# The marker geometry is REAL nodes saved in patrol_point.tscn, not generated.
# That's deliberate: the editor renders them natively with no @tool trickery,
# they show up in the viewport exactly as they'll sit in the world, and there's
# no chance of a generated node accidentally being serialised into your map.
# At runtime _ready() frees them, so they cost nothing in the build.
#
# The connecting LINE can't work this way — it depends on where the other points
# are — so PatrolPath draws that with a tool script. See patrol_path.gd.
# ─────────────────────────────────────────────

@export var label: Label3D
# Editor-only visuals. Freed at runtime rather than hidden, so they aren't
# costing draw calls or sitting in the physics/render server for nothing.
@export var editor_visuals: Array[Node3D] = []

# Shown above the marker in the editor. PatrolPath overwrites this with the
# point's index when it redraws, so you can read the order at a glance.
@export var display_index: int = -1:
	set(value):
		display_index = value
		_refresh_label()

@export var point_name: String = "":
	set(value):
		point_name = value
		_refresh_label()


func _ready() -> void:
	add_to_group("patrol_points")
	if Engine.is_editor_hint():
		_refresh_label()
		return
	# Game is running — drop the scaffolding.
	for node in editor_visuals:
		if node != null and is_instance_valid(node):
			node.queue_free()
	if label != null:
		label.queue_free()


func _refresh_label() -> void:
	if label == null or not is_instance_valid(label):
		return
	var text := point_name
	if display_index >= 0:
		text = "%d" % display_index if text == "" else "%d · %s" % [display_index, text]
	label.text = text
