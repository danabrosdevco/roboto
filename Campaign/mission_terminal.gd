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

@export_group("Screen")
## The "EXPECTED ENEMY SQUADS" line under the status line. Turn off if your
## terminal panel is too small to carry it.
@export var show_briefing: bool = true
## Wrap column for the screen text, in Label3D width units (multiplied by
## pixel_size to get metres). Only applied if the label is still at Godot's
## default AUTOWRAP_OFF, so anything you set in the inspector wins.
@export var label_width: float = 420.0
# Was get_parent().get_parent().Campaign, which assumes this node sits exactly
# two levels under World. Nest it one deeper and Campaign is null, _ready throws
# on the state_loaded connect, and the terminal goes quiet with no error you'd
# associate with the terminal.
var Campaign: CampaignManager
signal mission_selected(mission: MissionDefinition)

var _cycle_index: int = -1


func _ready() -> void:
	Campaign = _find_campaign() as CampaignManager
	if Campaign == null:
		push_warning("MissionTerminal '%s': no CampaignManager found. Selecting a mission will do nothing." % name)
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
	_style_label()
	if Campaign != null:
		Campaign.state_loaded.connect(_refresh)
		# Coming home blanks the selection, so the label has to catch up — and
		# cycling restarts from the top rather than resuming mid-list.
		Campaign.returned_to_base.connect(_on_returned_to_base)
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
	if Campaign == null:
		return "Terminal offline"
	if mission != null:
		return "Brief: %s%s" % [mission.display_name, _clear_suffix(mission)]
	var queued: MissionDefinition = Campaign.selected_mission()
	if queued != null:
		return "Next Op: %s%s" % [queued.display_name, _clear_suffix(queued)]
	return "Select Mission"


# ─────────────────────────────────────────────
# STATUS — every mission here is repeatable, so "have I done this?" is a
# question the player genuinely cannot answer from the world. Without it the
# obvious thing to do at the terminal is press F once and deploy, which means
# replaying mission one forever and never seeing the rest of the campaign.
# ─────────────────────────────────────────────

func _clears(m: MissionDefinition) -> int:
	if Campaign == null or Campaign.state == null or m == null:
		return 0
	return Campaign.state.clears_of(m.id)


# Short form for the HUD's F-prompt, which has one line to work with.
func _clear_suffix(m: MissionDefinition) -> String:
	var n := _clears(m)
	if n <= 0:
		return ""
	if n == 1:
		return " [CLEARED]"
	return " [CLEARED x%d]" % n


# The display name of the first unmet prerequisite. Telling the player the
# mission is locked without saying what opens it just reads as a dead end.
func _lock_reason(m: MissionDefinition) -> String:
	if Campaign == null or Campaign.state == null or m == null:
		return ""
	for req in m.requires:
		if not Campaign.state.completed_missions.has(req):
			var prereq: MissionDefinition = Campaign.get_mission(req)
			return prereq.display_name if prereq != null else String(req)
	return ""


# Where the cycle should land on the first press after coming home. Pointing it
# at unplayed content makes "press F once and go" advance the campaign instead
# of repeating the top of the list.
func _first_unplayed_index(available: Array[MissionDefinition]) -> int:
	for i in available.size():
		if _clears(available[i]) <= 0:
			return i
	return 0


func _on_interacted(_source: Interactible) -> void:
	if Campaign == null:
		push_warning("MissionTerminal: no CampaignManager, cannot select a mission.")
		return
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
	elif _cycle_index < 0:
		# First press since returning to base. Land on something unplayed
		# rather than on whatever happens to sit at index 0.
		_cycle_index = _first_unplayed_index(available)
		chosen = available[_cycle_index]
	else:
		_cycle_index = (_cycle_index + 1) % available.size()
		chosen = available[_cycle_index]

	Campaign.select_mission(chosen.id)
	if select_sound != null:
		select_sound.play()
	mission_selected.emit(chosen)
	# Every terminal re-reads, so the previously lit one goes dim.
	_refresh_all()


func _on_returned_to_base() -> void:
	_cycle_index = -1
	_refresh()


func _refresh_all() -> void:
	for t in get_tree().get_nodes_in_group("mission_terminals"):
		if t is MissionTerminal:
			t._refresh()


func _refresh() -> void:
	add_to_group("mission_terminals")
	if Campaign == null:
		return
	var selected: MissionDefinition = Campaign.selected_mission()

	if mission != null:
		_refresh_pinned(selected)
	else:
		_refresh_cycling(selected)


func _refresh_pinned(selected: MissionDefinition) -> void:
	if not Campaign.available_missions().has(mission):
		var reason := _lock_reason(mission)
		var tail := ("needs %s" % reason) if reason != "" else "unavailable"
		_set_label("%s\n[LOCKED]\n%s" % [
			mission.display_name.to_upper(), tail], unavailable_color)
		return
	var is_selected: bool = selected != null and selected.id == mission.id
	_set_label("%s\n%s\n%s" % [
		mission.display_name.to_upper(),
		"► SELECTED" if is_selected else "press F to queue",
		_detail_lines(mission),
	], selected_color if is_selected else idle_color)


func _refresh_cycling(selected: MissionDefinition) -> void:
	var available: Array[MissionDefinition] = Campaign.available_missions()

	if selected == null:
		if available.is_empty():
			_set_label("OPERATIONS\nNO OPERATIONS AVAILABLE", unavailable_color)
			return
		_set_label("OPERATIONS\n%d AVAILABLE\npress F to cycle" % available.size(), idle_color)
		return

	# find() is by reference, and available_missions() hands back the same
	# MissionDefinition instances every call, so this is stable.
	var pos := available.find(selected)
	var counter := ("%d/%d" % [pos + 1, available.size()]) if pos >= 0 else "-"
	_set_label("OPERATIONS: %s\n%s\n%s" % [
		counter,
		selected.display_name.to_upper(),
		_detail_lines(selected),
	], selected_color)


# One fact per line, in the order you weigh them:
#
#   SOLO                        (only when the op limits your squad)
#   EXPECTED ENEMY SQUADS: 1
#   REWARDS: 45 RESOURCES
#
# A mission with no force of its own falls back on the level's garrison, which
# it can't count, so the squad line says nothing rather than "0". The briefing
# prose lives on the deploy screen; a paragraph here read as a wall of text.
func _detail_lines(m: MissionDefinition) -> String:
	var lines: PackedStringArray = []
	var squad := m.squad_label()
	if squad != "":
		lines.append(squad)
	var squads := m.enemy_squad_count()
	if show_briefing and squads > 0:
		lines.append("EXPECTED ENEMY SQUADS: %d" % squads)
	lines.append("REWARDS: %d RESOURCES" % m.reward_resources)
	return "\n".join(lines)


# The screen used to hold two short lines and now holds up to four, one of
# which is a whole sentence. An unwrapped Label3D renders that as a single run
# metres wide. Only touched when the label is still at AUTOWRAP_OFF, so styling
# done in the inspector is never clobbered.
func _style_label() -> void:
	if label == null:
		return
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.width = label_width


func _set_label(text: String, color: Color) -> void:
	if label == null:
		return
	label.text = text
	label.modulate = color


# Finds the campaign however it happens to be wired: as a node in the "campaign"
# group (the reliable way), as a /root/Campaign autoload, or via World's export.
# Returns null rather than erroring, so a scene without a campaign still runs.
func _find_campaign() -> Node:
	var found := get_tree().get_first_node_in_group("campaign")
	if found != null:
		return found
	found = get_node_or_null("/root/Campaign")
	if found != null:
		return found
	var node: Node = self
	while node != null:
		if "Campaign" in node and node.get("Campaign") != null:
			return node.get("Campaign")
		node = node.get_parent()
	return null
