extends Node3D
class_name MissionTerminal

# ─────────────────────────────────────────────
# MISSION TERMINAL — the thing you press F on at base to pick where to go.
#
# It doesn't move the player anywhere. All it does is set
# Campaign.selected_mission_id, which is what MissionExit reads when you walk
# into the departure pad. Selection and departure stay separate so you can
# change your mind without being teleported.
#
# TWO MODES, decided by whether `mission` is assigned:
#
#   PINNED   — `mission` set. This terminal always selects that one mission.
#              Put one per operation on a briefing wall. Diegetic, no UI needed,
#              and the obvious thing to replace with a map pane later.
#
#   CYCLING  — `mission` left null. Each press advances through
#              Campaign.available_missions(). One terminal, every mission.
#              Good enough to play with today.
#
# Either way the Label3D shows what's currently queued, so the choice is
# visible in the world rather than living in a menu that doesn't exist yet.
# ─────────────────────────────────────────────

@export var interactible: Interactible
@export var label: Label3D
# Assign for PINNED mode. Leave null for CYCLING.
@export var mission: MissionDefinition
# Only the currently selected terminal lights up.
@export var selected_color: Color = Color(0.55, 0.85, 0.55)
@export var idle_color: Color = Color(0.75, 0.75, 0.75)
@export var unavailable_color: Color = Color(0.5, 0.35, 0.35)
@export var select_sound: AudioStreamPlayer3D
@onready var Campaign: CampaignManager = get_tree().get_first_node_in_group("campaign")
signal mission_selected(mission: MissionDefinition)

var _cycle_index: int = -1


func _ready() -> void:
	if interactible == null:
		interactible = _find_interactible(self)
	if interactible != null:
		interactible.interacted.connect(_on_interacted)
		# A terminal you can only use once is not a terminal.
		interactible.destroy_on_use = false
		interactible.disable_on_use = false
		interactible.type = Enums.InteractTypes.MISSION
	else:
		push_warning("MissionTerminal '%s' has no Interactible child." % name)
	Campaign.state_loaded.connect(_refresh)
	_refresh()


func _find_interactible(node: Node) -> Interactible:
	for child in node.get_children():
		if child is Interactible:
			return child
		var found := _find_interactible(child)
		if found != null:
			return found
	return null


# What the HUD shows next to the F prompt. Reads better than "F | 0".
func get_prompt() -> String:
	if mission != null:
		return "Brief: %s" % mission.display_name
	var queued: MissionDefinition = Campaign.selected_mission()
	if queued != null:
		return "Next Op: %s" % queued.display_name
	return "Select Mission"


func _on_interacted(_source: Interactible) -> void:
	var available: Array[MissionDefinition] = Campaign.available_missions()
	if available.is_empty():
		_set_label("NO OPERATIONS AVAILABLE", unavailable_color)
		return

	var chosen: MissionDefinition = null
	if mission != null:
		# Pinned. Refuse if its prerequisites aren't met rather than selecting
		# something the player can't actually deploy to.
		if not available.has(mission):
			_set_label("%s\nLOCKED" % mission.display_name.to_upper(), unavailable_color)
			return
		chosen = mission
	else:
		_cycle_index = (_cycle_index + 1) % available.size()
		chosen = available[_cycle_index]

	Campaign.select_mission(chosen.id)
	if select_sound != null:
		select_sound.play()
	mission_selected.emit(chosen)
	# Every terminal re-reads, so the previously lit one goes dim.
	_refresh_all()


func _refresh_all() -> void:
	for t in get_tree().get_nodes_in_group("mission_terminals"):
		if t is MissionTerminal:
			t._refresh()


func _refresh() -> void:
	add_to_group("mission_terminals")
	var selected: MissionDefinition = Campaign.selected_mission()

	if mission != null:
		var is_selected: bool = selected != null and selected.id == mission.id
		var locked: bool = not Campaign.available_missions().has(mission)
		if locked:
			_set_label("%s\n[LOCKED]" % mission.display_name.to_upper(), unavailable_color)
		else:
			_set_label("%s\n%s" % [
				mission.display_name.to_upper(),
				"► SELECTED" if is_selected else "%d RES" % mission.reward_resources
			], selected_color if is_selected else idle_color)
		return

	if selected == null:
		_set_label("OPERATIONS\nno op selected", idle_color)
	else:
		_set_label("OPERATIONS\n► %s" % selected.display_name.to_upper(), selected_color)


func _set_label(text: String, color: Color) -> void:
	if label == null:
		return
	label.text = text
	label.modulate = color
