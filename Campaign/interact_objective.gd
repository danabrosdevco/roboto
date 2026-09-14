extends MissionObjective
class_name InteractObjective

# ─────────────────────────────────────────────
# INTERACT OBJECTIVE — press F on a thing, or several things.
#
# Composition rather than inheritance: this HOLDS Interactibles instead of being
# one. Interactible extends Area3D and MissionObjective extends Node3D, so they
# can't be the same node — and composition buys something anyway, since one
# objective can require three separate terminals with no extra machinery.
#
# The Interactibles need type = OBJECTIVE and, unless you want them to vanish,
# destroy_on_use = false with disable_on_use = true. Disabled is usually right:
# the console stays in the world, it just stops offering the prompt.
#
# CHANNELLING
# Set channel_duration above zero and the first press starts a timer rather than
# completing outright — planting a charge, pulling data. The player has to stay
# within channel_range or it resets. Implemented as a distance check rather than
# area overlap so it doesn't depend on collision layer setup.
# ─────────────────────────────────────────────

@export var interactibles: Array[Interactible] = []
# 0 means all of them.
@export var required_count: int = 0

@export var channel_duration: float = 0.0
@export var channel_range: float = 3.0
# Progress survives briefly if they step out and come back.
@export var channel_resume_grace: float = 2.0

signal channel_started(interactible: Interactible)
signal channel_progress(fraction: float)
signal channel_interrupted
signal channel_finished(interactible: Interactible)

var _done: Dictionary = {}          # Interactible -> true
var _channelling: Interactible = null
var _channel_t: float = 0.0
var _grace_t: float = 0.0
var _player: Node3D = null


func _on_objective_ready() -> void:
	for item in interactibles:
		if item != null:
			item.interacted.connect(_on_interacted)
	set_process(channel_duration > 0.0)
	_emit_progress()


func target_count() -> int:
	if required_count > 0:
		return mini(required_count, interactibles.size())
	return interactibles.size()


func progress() -> Array:
	return [_done.size(), maxi(1, target_count())]


func _emit_progress() -> void:
	progress_changed.emit(self, _done.size(), maxi(1, target_count()))


func _on_interacted(item: Interactible) -> void:
	if completed or failed or not active:
		return
	if _done.has(item):
		return

	if channel_duration <= 0.0:
		_register(item)
		return

	# Start (or restart) the channel on this one.
	_player = _find_player()
	if _channelling != item:
		_channelling = item
		_channel_t = 0.0 if _grace_t <= 0.0 else _channel_t
	_grace_t = 0.0
	channel_started.emit(item)


func _process(delta: float) -> void:
	if _grace_t > 0.0:
		_grace_t = maxf(0.0, _grace_t - delta)
		if _grace_t <= 0.0:
			_channel_t = 0.0
			_channelling = null
	if _channelling == null or completed:
		return

	if _player == null or not is_instance_valid(_player) \
			or _player.global_position.distance_to(_channelling.global_position) > channel_range:
		_grace_t = channel_resume_grace
		channel_interrupted.emit()
		_channelling = null
		return

	_channel_t += delta
	channel_progress.emit(clampf(_channel_t / maxf(channel_duration, 0.01), 0.0, 1.0))
	if _channel_t < channel_duration:
		return

	var finished := _channelling
	_channelling = null
	_channel_t = 0.0
	channel_finished.emit(finished)
	_register(finished)


func _register(item: Interactible) -> void:
	_done[item] = true
	_emit_progress()
	if _done.size() >= target_count():
		complete()


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0]
	# Fall back to walking up to World, which holds the reference directly.
	var node: Node = self
	while node != null:
		if node is World:
			return (node as World).player
		node = node.get_parent()
	return null
