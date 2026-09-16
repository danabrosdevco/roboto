extends Node
class_name SquadCommander

# ─────────────────────────────────────────────
# SQUAD COMMANDER
# Child of Player. Owns the "command" input (T) and everything downstream of it.
#
# TAP T    — contextual order at the crosshair. The verb is inferred from what
#            you're looking at, so the common case costs one keypress:
#              hostile   → ASSAULT that target
#              friendly  → select that robot's squad
#              ground    → ASSAULT that position
#              nothing   → CONTACT callout down the sightline
# HOLD T   — opens the verb wheel. Mouse left/right picks, release commits.
#            Camera is frozen while the wheel is open.
# TAB      — cycle which squad you're commanding.
#
# WHY THREE VERBS
# The wheel used to carry MOVE TO / DEFEND / ATTACK / FALL BACK / CONTACT. Those
# weren't five orders, they were two questions collapsed into one list: WHERE
# and HOW. The aim point already answers WHERE in every case, so the verb only
# ever had to answer HOW.
#   ASSAULT at ground   = the old MOVE TO
#   ASSAULT at a hostile = the old ATTACK
#   DEFEND at a point behind you = the old FALL BACK
# CONTACT came off the wheel entirely — it isn't a posture, it's a report, and
# it needs to be instant. By the time you have held, scrubbed and released, the
# thing you spotted has moved. It is the TAP now.
#
# The old CommandMarker did a 600m physics sphere sweep every press to work out
# who should listen. That's replaced: the commander already knows which squad is
# selected, so it calls squad.receive_player_order() directly. The marker is now
# purely a visual.
# ─────────────────────────────────────────────

@export var player: Player
@export var cam: Camera3D
@export var world: Node3D
@export var hud: Control
@export var marker_scene: PackedScene

@export var ray_length: float = 500.0
# Layer 1 is level geometry. Widen this if your AI bodies sit on another layer —
# the commander needs to hit robots as well as terrain to infer intent.
@export var command_ray_mask: int = 0xFFFFFFFF

@export var hold_threshold: float = 0.22
@export var wheel_sensitivity: float = 0.006

# How often the squad registry is rebuilt. It used to be built exactly once in
# _ready(), so a squad that spawned later never became commandable and a wiped
# one stayed in the cycle list forever.
@export var registry_refresh_interval: float = 2.0

# ASSAULT is gone. "Go there and engage what you meet on the way" meant the
# squad self-directed mid-order, and self-direction is where almost every
# problem came from — chasing corpses, closing into shotgun range, stringing
# into a line, slipping the leash.
#
# ADVANCE is the old DEFEND behaviour under a better name: go there, hold, dig
# in. Taking ground becomes a sequence of orders you issue rather than a
# judgement call the AI gets wrong. Bounding a squad forward is now YOUR job,
# which is the whole appeal of a squad game.
enum Verb { ADVANCE, FOLLOW, CONTACT }

const VERB_LABELS := {
	Verb.ADVANCE: "ADVANCE",
	Verb.FOLLOW:  "FOLLOW",
	Verb.CONTACT: "CONTACT",
}

var commandable_squads: Array[Squad] = []
var selected_index: int = 0

var _hold_time: float = 0.0
var _wheel_open: bool = false
var _wheel_accum: float = 0.0
var _wheel_index: int = 0
var _markers: Dictionary = {}   # Squad -> CommandMarker
var _preview: CommandMarker = null
var _registry_timer: float = 0.0

signal squad_selected(squad: Squad)
signal squads_refreshed(squads: Array)
signal wheel_opened(verbs: Array, index: int)
signal wheel_moved(index: int)
signal wheel_closed()
signal order_issued(squad: Squad, verb: int, position: Vector3, target: Node)
signal contact_called(position: Vector3, target: Node)


func _ready() -> void:
	_autowire()
	# Squads add themselves to the group in their own _ready, which may not have
	# run yet. Wait a frame before the first sweep.
	await get_tree().process_frame
	refresh_squads()


# `world` and `hud` are not set in test_character.tscn. _place_marker() bails on
# `world == null` and _call_contact() skips the enemy marker on `hud == null`,
# which is the whole reason no marker ever appeared at the aim point. Player
# already holds both references, so take them from there rather than relying on
# the inspector.
func _autowire() -> void:
	if player == null:
		player = get_parent() as Player
	if player == null:
		return
	if cam == null:
		cam = player.cam
	if world == null:
		world = player.world
	if hud == null:
		hud = player.hud
	if marker_scene == null:
		marker_scene = player.command_marker_scene


# ─────────────────────────────────────────────
# SQUAD REGISTRY
# ─────────────────────────────────────────────
func refresh_squads() -> void:
	commandable_squads.clear()
	for s in get_tree().get_nodes_in_group("squads"):
		if not s is Squad:
			continue
		var squad := s as Squad
		if squad.is_wiped():
			continue
		if squad.player_commandable or _is_friendly_squad(squad):
			commandable_squads.append(squad)
	selected_index = clampi(selected_index, 0, maxi(0, commandable_squads.size() - 1))
	squads_refreshed.emit(commandable_squads)
	squad_selected.emit(get_selected_squad())


func _is_friendly_squad(squad: Squad) -> bool:
	for m in squad.get_living_members():
		return not Enums.are_hostile(Enums.Factions.PLAYER, m.faction)
	return false


# This node extends Node, which has no get_world_3d(). Borrow the player's —
# it's a CharacterBody3D and always lives in the same 3D world we care about.
func _space() -> PhysicsDirectSpaceState3D:
	return player.get_world_3d().direct_space_state


func get_selected_squad() -> Squad:
	if commandable_squads.is_empty():
		return null
	if selected_index >= commandable_squads.size():
		selected_index = 0
	return commandable_squads[selected_index]


func cycle_squad(dir: int = 1) -> void:
	if commandable_squads.size() <= 1:
		return
	selected_index = wrapi(selected_index + dir, 0, commandable_squads.size())
	squad_selected.emit(get_selected_squad())


# Squads within radius of the player, for the "squads around you" HUD readout.
func get_nearby_squads(radius: float = 120.0) -> Array:
	var result: Array = []
	if player == null:
		return result
	for s in get_tree().get_nodes_in_group("squads"):
		if not s is Squad:
			continue
		var squad := s as Squad
		if squad.is_wiped():
			continue
		if player.global_position.distance_to(squad.get_center()) <= radius:
			result.append(squad)
	return result


# ─────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	# While the wheel is open we eat mouse motion so the camera holds still and
	# the same gesture drives selection instead.
	if _wheel_open and event is InputEventMouseMotion:
		_wheel_accum += event.relative.x * wheel_sensitivity
		var verbs := _available_verbs()
		var idx = wrapi(int(round(_wheel_accum)), 0, verbs.size())
		if idx != _wheel_index:
			_wheel_index = idx
			wheel_moved.emit(_wheel_index)
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			cycle_squad(1)


func _process(delta: float) -> void:
	if player == null or not player.alive:
		return

	_registry_timer += delta
	if _registry_timer >= registry_refresh_interval:
		_registry_timer = 0.0
		_refresh_registry_quietly()

	if Input.is_action_pressed("command"):
		_hold_time += delta
		if not _wheel_open and _hold_time >= hold_threshold:
			_open_wheel()
		# Live preview: while the wheel is open the marker tracks the crosshair
		# and recolours as you scrub verbs, so you can see where the order will
		# land BEFORE you commit it.
		if _wheel_open:
			_update_preview()
		return

	if Input.is_action_just_released("command") or (_hold_time > 0.0 and not Input.is_action_pressed("command")):
		if _wheel_open:
			_commit_wheel()
		elif _hold_time > 0.0:
			_issue_contextual_order()
		_hold_time = 0.0


# CONTACT is deliberately absent — it's the tap, not a wheel entry.
func _available_verbs() -> Array:
	return [Verb.ADVANCE, Verb.FOLLOW]


func _open_wheel() -> void:
	if get_selected_squad() == null:
		return
	_wheel_open = true
	_wheel_accum = 0.0
	_wheel_index = 0
	_spawn_preview()
	var labels: Array = []
	for v in _available_verbs():
		labels.append(VERB_LABELS[v])
	wheel_opened.emit(labels, _wheel_index)


func _commit_wheel() -> void:
	_wheel_open = false
	_clear_preview()
	wheel_closed.emit()
	var verbs := _available_verbs()
	if _wheel_index < 0 or _wheel_index >= verbs.size():
		return
	_issue_order(verbs[_wheel_index])


# ─────────────────────────────────────────────
# AIM RESOLUTION
# One raycast, then branch on what it hit. The old version masked to layer 1
# only, which is why it could never resolve anything but terrain.
# ─────────────────────────────────────────────
func _aim_result() -> Dictionary:
	if cam == null or player == null:
		return {}
	var origin := cam.global_position
	var end := origin + (-cam.global_transform.basis.z * ray_length)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collide_with_areas = false
	query.collision_mask = command_ray_mask
	query.exclude = [player.get_rid()]
	return _space().intersect_ray(query)


func _issue_contextual_order() -> void:
	var hit := _aim_result()

	if hit.is_empty():
		# Looking at open sky. Treat as a callout down the sightline.
		var far_point = cam.global_position + (-cam.global_transform.basis.z * 60.0)
		_call_contact(far_point, null)
		return

	var collider = hit.get("collider")

	# Friendly robot under the crosshair — select their squad, don't order.
	if collider is Soldier and not Enums.are_hostile(Enums.Factions.PLAYER, collider.faction):
		var s: Squad = collider.squad
		if s != null and commandable_squads.has(s):
			selected_index = commandable_squads.find(s)
			squad_selected.emit(s)
			return

	# Hostile under the crosshair. With no assault verb there's nothing to send
	# them AT, so mark it instead — the squad gets a contact call and picks it
	# up themselves if it's in reach.
	if collider is Enemy and Enums.are_hostile(Enums.Factions.PLAYER, collider.faction):
		_issue_order(Verb.CONTACT, hit.position, collider)
		return

	# Ground. Move there and hold.
	_issue_order(Verb.ADVANCE, hit.position)


func _issue_order(verb: int, position = null, target: Node = null) -> void:
	var squad := get_selected_squad()
	if squad == null:
		return

	# Resolve a position if the caller didn't supply one (wheel path).
	var pos: Vector3
	if position == null:
		var hit := _aim_result()
		if hit.is_empty():
			pos = player.global_position
		else:
			pos = hit.position
			if verb == Verb.ADVANCE and target == null:
				var c = hit.get("collider")
				if c is Enemy and Enums.are_hostile(Enums.Factions.PLAYER, c.faction):
					target = c
	else:
		pos = position

	match verb:
		Verb.CONTACT:
			_call_contact(pos, target)
			return
		Verb.ADVANCE:
			# Maps to SquadObjective.DEFEND — go there and hold. The enum keeps
			# ADVANCE and ATTACK because EnemySquadSpec.Posture still uses them
			# for garrisons and patrols; enemies genuinely should push. Only the
			# PLAYER's vocabulary shrank.
			squad.receive_player_order(Squad.SquadObjective.DEFEND, pos)
		Verb.FOLLOW:
			# No world position to mark — the objective is a moving node. Clear
			# any standing marker so the map doesn't still show an objective the
			# squad has been pulled off.
			squad.follow(player)
			_clear_marker(squad)
			order_issued.emit(squad, verb, player.global_position, player)
			return

	_place_marker(squad, verb, pos)
	order_issued.emit(squad, verb, pos, target)


# ─────────────────────────────────────────────
# CONTACT CALLOUT
# Rides the existing StimulusManager. Note the faction: emit_stimulus filters
# on `ai.faction != emitting_faction`, and your friendly robots are ALLIED, not
# PLAYER — emitting as PLAYER would reach nobody.
# ─────────────────────────────────────────────
func _call_contact(position: Vector3, target: Node) -> void:
	# NOTE: Player has no ai_manager property (that lives on Enemy), so this
	# resolves through World, which exports one.
	var sm: StimulusManager = _get_stimulus_manager()

	if sm != null:
		sm.emit_stimulus(
			StimulusManager.StimulusType.ENEMY_SPOTTED,
			position,
			Enums.Factions.ALLIED,
			target,
			45.0)

	# Reuse the scanner's existing world-space marker for the visual.
	if hud != null and target is Node3D and hud.has_method("activate_enemy_marker"):
		hud.activate_enemy_marker(target, 8.0)

	contact_called.emit(position, target)


# ─────────────────────────────────────────────
# AIM PREVIEW — the marker you see while the wheel is open
# ─────────────────────────────────────────────
# Returns the world point currently under the crosshair, or a point 60m down
# the sightline when the ray hits nothing.
func get_aim_point() -> Vector3:
	var hit := _aim_result()
	if hit.is_empty():
		if cam == null:
			return Vector3.ZERO
		return cam.global_position + (-cam.global_transform.basis.z * 60.0)
	return hit.position


func _spawn_preview() -> void:
	if marker_scene == null or world == null:
		return
	if _preview != null and is_instance_valid(_preview):
		return
	_preview = marker_scene.instantiate() as CommandMarker
	if _preview == null:
		push_warning("SquadCommander: marker_scene is not a CommandMarker.")
		return
	_preview.preview = true
	world.add_child(_preview)
	_update_preview()


func _update_preview() -> void:
	if _preview == null or not is_instance_valid(_preview):
		_spawn_preview()
		if _preview == null:
			return
	var verbs := _available_verbs()
	var verb: int = verbs[_wheel_index] if _wheel_index >= 0 and _wheel_index < verbs.size() else Verb.ADVANCE
	# FOLLOW has no aim point — park the preview at the player's feet so the
	# ring still reads as "this order is about you", not about the crosshair.
	if verb == Verb.FOLLOW and player != null:
		_preview.global_position = _snap_to_ground(player.global_position)
	else:
		_preview.global_position = _snap_to_ground(get_aim_point())
	_preview.set_order(verb, str(VERB_LABELS.get(verb, "")))


func _clear_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null


# Rebuild the registry without firing squad_selected, so the HUD doesn't toast
# "COMMANDING X" twice a second.
func _refresh_registry_quietly() -> void:
	var previous := get_selected_squad()
	commandable_squads.clear()
	for s in get_tree().get_nodes_in_group("squads"):
		if not s is Squad:
			continue
		var squad := s as Squad
		if squad.is_wiped():
			continue
		if squad.player_commandable or _is_friendly_squad(squad):
			commandable_squads.append(squad)
	if previous != null and commandable_squads.has(previous):
		selected_index = commandable_squads.find(previous)
	else:
		selected_index = clampi(selected_index, 0, maxi(0, commandable_squads.size() - 1))
		if get_selected_squad() != previous:
			squad_selected.emit(get_selected_squad())


# ─────────────────────────────────────────────
# MARKERS — one per squad, moved rather than respawned
# ─────────────────────────────────────────────
func _get_stimulus_manager() -> StimulusManager:
	if world != null and world is World and (world as World).ai_manager != null:
		return (world as World).ai_manager.stimulus_manager
	for n in get_tree().get_nodes_in_group("ai_manager"):
		if n is AIManager:
			return (n as AIManager).stimulus_manager
	return null


func _place_marker(squad: Squad, verb: int, pos: Vector3) -> void:
	if marker_scene == null or world == null:
		return

	var marker: Node3D = _markers.get(squad)
	if marker == null or not is_instance_valid(marker):
		marker = marker_scene.instantiate()
		world.add_child(marker)
		_markers[squad] = marker

	marker.global_position = _snap_to_ground(pos)
	marker.rotation = Vector3.ZERO
	if marker.has_method("set_order"):
		marker.set_order(verb, VERB_LABELS.get(verb, ""))


func _clear_marker(squad: Squad) -> void:
	var marker = _markers.get(squad)
	if marker != null and is_instance_valid(marker):
		marker.queue_free()
	_markers.erase(squad)


# The old code forced marker.y = 0, which drops the marker to world origin
# height — fine on a flat arena, wrong on anything with terrain.
func _snap_to_ground(pos: Vector3) -> Vector3:
	if player == null:
		return pos
	var query := PhysicsRayQueryParameters3D.create(
		pos + Vector3.UP * 3.0, pos + Vector3.DOWN * 30.0)
	query.collision_mask = 1
	var hit: Dictionary = _space().intersect_ray(query)
	if hit.is_empty():
		return pos
	return hit.position + Vector3.UP * 0.05
