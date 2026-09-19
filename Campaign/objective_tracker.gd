extends Node
class_name ObjectiveTracker

# ─────────────────────────────────────────────
# OBJECTIVE TRACKER — the one thing that answers "can we leave yet".
#
# Put it under World so it survives level loads, and let Campaign.on_level_loaded
# call refresh() once the new level is in the tree. MissionExit asks this rather
# than scanning the group itself, so there's a single definition of "complete"
# and one place to hang the HUD off.
# ─────────────────────────────────────────────

signal objectives_refreshed(objectives: Array)
signal objective_changed(objective: MissionObjective)
# Named ...ed to avoid colliding with the all_required_complete() query below.
signal required_objectives_complete
signal mission_failed(objective: MissionObjective)

var _objectives: Array[MissionObjective] = []
var _announced: bool = false


func refresh() -> void:
	_objectives.clear()
	_announced = false
	for node in get_tree().get_nodes_in_group("mission_objectives"):
		if not (node is MissionObjective):
			continue
		var obj := node as MissionObjective
		_objectives.append(obj)
		if not obj.objective_completed.is_connected(_on_completed):
			obj.objective_completed.connect(_on_completed)
			obj.objective_failed.connect(_on_failed)
			obj.progress_changed.connect(_on_progress)
	_sort_objectives()
	objectives_refreshed.emit(_objectives)


# Extraction goes last, then optional, then everything else in scene order.
#
# The group returns nodes in tree order, and an extraction point lives inside
# LevelExit — which in valley_level is declared thousands of lines above the
# objectives you have to do first. So "get out" listed above "capture the
# garrison", which is the reverse of the order you do them in. Sorting here
# rather than in the HUD keeps every reader of objectives() consistent.
func _sort_objectives() -> void:
	var order := func(o: MissionObjective) -> int:
		if o.is_extraction:
			return 2
		if o.optional:
			return 1
		return 0
	# Stable: equal ranks keep the scene order the level author chose.
	var indexed: Array = []
	for i in _objectives.size():
		indexed.append({"obj": _objectives[i], "rank": order.call(_objectives[i]), "i": i})
	indexed.sort_custom(func(a, b):
		if a["rank"] != b["rank"]:
			return a["rank"] < b["rank"]
		return a["i"] < b["i"])
	_objectives.clear()
	for entry in indexed:
		_objectives.append(entry["obj"])
	_check_all()


func objectives() -> Array[MissionObjective]:
	return _objectives


func required() -> Array[MissionObjective]:
	var out: Array[MissionObjective] = []
	for o in _objectives:
		if o.counts_toward_extraction():
			out.append(o)
	return out


func all_required_complete() -> bool:
	for o in required():
		if not o.completed:
			return false
	return true


# [done, total] across required objectives only.
func required_progress() -> Array:
	var done := 0
	var list := required()
	for o in list:
		if o.completed:
			done += 1
	return [done, list.size()]


# Bonus paid at extraction for everything actually completed.
func earned_objective_rewards() -> int:
	var total := 0
	for o in _objectives:
		if o.completed:
			total += o.reward_resources
	return total


## Completed objectives that carry compute, as {id, compute}. The campaign pays
## each one once per campaign, so replaying a mission cannot farm it.
func earned_compute() -> Array:
	var out: Array = []
	for o in _objectives:
		if o.completed and o.compute_reward > 0:
			out.append({"id": String(o.id), "compute": o.compute_reward})
	return out


func clear() -> void:
	_objectives.clear()
	_announced = false


func _on_completed(objective: MissionObjective) -> void:
	objective_changed.emit(objective)
	_check_all()


func _on_failed(objective: MissionObjective) -> void:
	objective_changed.emit(objective)
	if objective.counts_toward_extraction():
		mission_failed.emit(objective)


func _on_progress(objective: MissionObjective, _current: int, _target: int) -> void:
	objective_changed.emit(objective)


func _check_all() -> void:
	# Announce once. Without the latch this fires on every subsequent completed
	# bonus objective and anything hooked to it re-triggers.
	if _announced or _objectives.is_empty():
		return
	if all_required_complete():
		_announced = true
		required_objectives_complete.emit()
