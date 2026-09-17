extends MissionObjective
class_name ReachObjective

# ─────────────────────────────────────────────
# REACH OBJECTIVE — get someone into an area.
#
# Also what an extraction zone is, if you'd rather gate extraction on standing
# somewhere than on pressing F. Set is_extraction and let MissionExit sit inside
# the same trigger.
# ─────────────────────────────────────────────

@export var area: Area3D
# Require the squad too, not just the player. This is the "get everyone out"
# version and it's the one that makes the repair tool matter.
@export var requires_squad: bool = false
@export var squad_radius: float = 12.0

var _player_inside: bool = false


func _on_objective_ready() -> void:
	if area == null:
		area = _find_area(self)
	if area == null:
		push_warning("ReachObjective '%s' has no Area3D." % display_name)
		return
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	set_process(requires_squad)


func _find_area(node: Node) -> Area3D:
	for child in node.get_children():
		if child is Area3D:
			return child
		var found := _find_area(child)
		if found != null:
			return found
	return null


func _on_body_entered(body: Node3D) -> void:
	if not (body is Player):
		return
	_player_inside = true
	if not requires_squad:
		_try_complete()


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_inside = false


func _process(_delta: float) -> void:
	if _player_inside:
		_try_complete()


func _try_complete() -> void:
	if completed or failed or not active:
		return
	if requires_squad and not _squad_present():
		return
	complete()


func _squad_present() -> bool:
	var centre: Vector3 = area.global_position if area != null else global_position
	for squad in get_tree().get_nodes_in_group("squads"):
		if not (squad is Squad) or not squad.player_commandable:
			continue
		for member in squad.get_living_members():
			if centre.distance_to(member.global_position) > squad_radius:
				return false
	return true


# The extraction point is the one objective players most need named clearly, and
# it is also the one most often left unnamed in a level — MissionExit sits
# inside it and the node is easy to place and forget.
func verb() -> String:
	return "Extract" if is_extraction else "Reach"
