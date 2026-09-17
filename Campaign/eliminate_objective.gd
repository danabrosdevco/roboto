extends MissionObjective
class_name EliminateObjective

# ─────────────────────────────────────────────
# ELIMINATE OBJECTIVE — destroy specific targets, or clear an area.
#
# Polled on a slow tick rather than hooked to a death signal, because Enemy
# doesn't emit one. A half-second poll over a handful of nodes is cheaper than
# threading a signal through every AI, and it also catches a target that was
# freed outright rather than dying properly.
# ─────────────────────────────────────────────

# Explicit targets. Leave empty and use `zone` instead.
@export var targets: Array[Node3D] = []
# Everything hostile inside this counts, captured once when the objective
# activates so reinforcements walking in later don't extend the objective.
@export var zone: Area3D
@export var poll_interval: float = 0.5
# 0 means all of them.
@export var required_kills: int = 0
## How long to keep looking for targets before saying so out loud.
@export var empty_warn_after: float = 6.0

var _watched: Array[Node3D] = []
var _timer: float = 0.0
var _killed: int = 0
var _empty_for: float = 0.0
var _warned_empty: bool = false


func _on_objective_ready() -> void:
	set_process(true)
	if not active:
		return
	_capture_targets()


func _on_activated() -> void:
	_capture_targets()


func _capture_targets() -> void:
	_watched.clear()
	for t in targets:
		if t != null and is_instance_valid(t):
			_watched.append(t)
	if zone != null:
		for body in zone.get_overlapping_bodies():
			if body is Enemy and Enums.are_hostile(Enums.Factions.PLAYER, body.faction):
				if not _watched.has(body):
					_watched.append(body)
	progress_changed.emit(self, 0, maxi(1, target_count()))


func target_count() -> int:
	if required_kills > 0:
		return mini(required_kills, _watched.size())
	return _watched.size()


func progress() -> Array:
	return [_killed, maxi(1, target_count())]


func _process(delta: float) -> void:
	if completed or failed or not active:
		return
	_timer += delta
	if _timer < poll_interval:
		return
	_timer = 0.0

	# TARGETS ARRIVE AFTER THE LEVEL DOES. EnemyForceSpawner builds the hostile
	# force during Campaign.on_level_loaded, and an Area3D cannot report bodies
	# the physics server has not processed yet — so capturing once at activation
	# caught nothing, _watched stayed empty, and this function used to return
	# here forever. The objective sat at 0/1 for the whole mission with no
	# error. Keep asking until the zone answers.
	if _watched.is_empty():
		_capture_targets()
		if _watched.is_empty():
			_empty_for += poll_interval
			if _empty_for >= empty_warn_after and not _warned_empty:
				_warned_empty = true
				push_warning("EliminateObjective '%s' has found no targets after %.0fs. Check the zone actually covers where the enemy force spawns, or assign `targets` directly." % [id, empty_warn_after])
			return

	var down := 0
	for t in _watched:
		if t == null or not is_instance_valid(t):
			down += 1
		elif "alive" in t and not t.alive:
			down += 1
	if down == _killed:
		return
	_killed = down
	progress_changed.emit(self, _killed, maxi(1, target_count()))
	if _killed >= target_count():
		complete()


func verb() -> String:
	return "Eliminate"
