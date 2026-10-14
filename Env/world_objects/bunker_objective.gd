extends MissionObjective

# ─────────────────────────────────────────────
# THE BUNKER, AS AN OBJECTIVE LINE.
#
# The cores already appear in the objective HUD and on the minimap, because
# each one drives the authored MissionObjective it stands on
# (holdable_core.gd). The bunker had nothing to drive — it is a place this
# slice adds, not one the map was authored with — so it brings its own.
#
# Being a MissionObjective is the whole trick: ObjectiveTracker finds it in the
# "mission_objectives" group, the HUD draws it from label() and progress(), and
# none of that needed a line of new UI.
#
# NO id ON PURPOSE. MissionObjective._ready() frees any objective whose id the
# current operation did not ask for — an empty id skips that check, which is
# right for something the mission never knew about.
# ─────────────────────────────────────────────

## The SiteOperation whose stand-down this reports.
var operation: Node3D = null


func _on_objective_ready() -> void:
	if operation == null or not is_instance_valid(operation):
		push_warning("BunkerObjective: no operation, so the HUD line will sit at zero forever.")
		return
	operation.stand_down_progress.connect(_on_stand_down)
	operation.stand_down_started.connect(_on_stand_down_changed)
	operation.stand_down_interrupted.connect(_on_stand_down_changed)
	operation.operation_complete.connect(_on_done)


## Shown as the suffix on the HUD row — the stand-down as a percentage, which
## is the one number that says how close this operation is to being over.
func progress() -> Array:
	if operation == null or not is_instance_valid(operation):
		return [0, 100]
	return [int(round(operation.stand_down_fraction() * 100.0)), 100]


## THROTTLED TO WHOLE PERCENT.
##
## SiteOperation emits stand_down_progress every physics frame. Republishing
## that as progress_changed means ObjectiveTracker re-emits objective_changed
## sixty times a second, and ObjectiveHUD._on_changed calls _rebuild() on every
## one — the whole objective panel torn down and rebuilt per frame for the
## entire stand-down. It flickers, and it is the "noise after it reaches the
## objective" the first playtest hit.
##
## A percentage only has a hundred states. Emit when it actually changes.
var _last_pct: int = -1


func _on_stand_down(_fraction: float) -> void:
	var p: Array = progress()
	if p[0] == _last_pct:
		return
	_last_pct = p[0]
	progress_changed.emit(self, p[0], p[1])


func _on_stand_down_changed() -> void:
	# Forced through, because starting and stopping must show even when the
	# percentage has not moved.
	_last_pct = -1
	_on_stand_down(0.0)


func _on_done() -> void:
	if not completed:
		complete()
