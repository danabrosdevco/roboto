extends Node
class_name AIManager

@export var world: World
@export var player: Player
@export var stimulus_manager: StimulusManager

# All registered AI bodies in the current level
var all_ai: Array[AI] = []

func register_enemy(new_enemy: AI) -> void:
	if new_enemy in all_ai:
		return
	all_ai.append(new_enemy)
	new_enemy.player = player
	new_enemy.ai_manager = self
	if stimulus_manager != null:
		new_enemy.stimulus_manager = stimulus_manager
		stimulus_manager.register_ai(new_enemy)
	# Spread their think-frames. A squad spawned in one loop otherwise ticks in
	# lockstep forever.
	if new_enemy.has_method("_stagger_ai_timers"):
		new_enemy._stagger_ai_timers()

func deregister_enemy(enemy: AI) -> void:
	all_ai.erase(enemy)
	# The cache holds hard references to the bodies it listed. Leaving it intact
	# after removing one meant it kept handing out a node that was about to be
	# freed — and on level unload that is EVERY node, for up to
	# HOSTILE_CACHE_LIFETIME. Any robot that ticked vision in that window
	# dereferenced a corpse: "Invalid access to property 'global_position' on a
	# base object of type 'previously freed'". A cache must never outlive the
	# roster it was built from.
	_hostile_cache.clear()
	if stimulus_manager != null:
		stimulus_manager.deregister_ai(enemy)

func reset_all_reg_enemies() -> void:
	all_ai = []
	_hostile_cache.clear()
	if stimulus_manager != null:
		stimulus_manager.clear()

# ─────────────────────────────────────────────
# FACTION QUERY
# Called by Enemy to find the nearest hostile body.
# Returns the closest living CharacterBody3D that
# is hostile to the requesting AI's faction.
# ─────────────────────────────────────────────
# Called by reconsider_target, _check_close_threat and the vision scan — several
# times per AI per second, each one a full pass over every registered body. With
# 35 AI that is well over a thousand iterations a second before anything useful
# happens.
#
# The list is cached per faction and rebuilt on a short timer instead. Callers
# still get an exact nearest; they just don't each re-filter the whole world.
var _hostile_cache: Dictionary = {}     # faction -> Array[CharacterBody3D]
var _hostile_cache_age: float = 0.0
const HOSTILE_CACHE_LIFETIME: float = 0.4


func _process(delta: float) -> void:
	_hostile_cache_age -= delta
	if _hostile_cache_age <= 0.0:
		_hostile_cache.clear()
		_hostile_cache_age = HOSTILE_CACHE_LIFETIME


func hostiles_for(faction) -> Array:
	if _hostile_cache.has(faction):
		return _hostile_cache[faction]
	var list: Array = []
	for other in all_ai:
		if other == null or not is_instance_valid(other) or not other.alive:
			continue
		if not Enums.are_hostile(faction, other.faction):
			continue
		if other is Player and not other.is_targetable():
			continue
		list.append(other)
	if player != null and player.alive and player.is_targetable() \
			and Enums.are_hostile(faction, player.faction) and not list.has(player):
		list.append(player)
	_hostile_cache[faction] = list
	return list


func get_nearest_hostile(requesting_ai: AI) -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_dist: float = INF
	var req_faction = requesting_ai.faction

	# Check the player first
	if player != null and player.is_targetable():
		if Enums.are_hostile(req_faction, player.faction):
			var d = requesting_ai.global_position.distance_squared_to(player.global_position)
			if d < best_dist:
				best_dist = d
				best = player

	# Check all other registered AI
	for ai in all_ai:
		# Belt to the _exit_tree brace: a freed entry must never reach .alive.
		if ai == null or not is_instance_valid(ai):
			continue
		if ai == requesting_ai:
			continue
		if not ai.alive:
			continue
		if not ai is Enemy:
			continue
		var enemy := ai as Enemy
		if Enums.are_hostile(req_faction, enemy.faction):
			var d = requesting_ai.global_position.distance_squared_to(enemy.global_position)
			if d < best_dist:
				best_dist = d
				best = enemy

	return best

# ─────────────────────────────────────────────
# Get all living hostiles within a radius
# ─────────────────────────────────────────────
func get_hostiles_in_radius(requesting_ai: AI, radius: float) -> Array:
	var result: Array = []
	var radius_sq = radius * radius
	var req_faction = requesting_ai.faction

	if player != null and player.is_targetable():
		if Enums.are_hostile(req_faction, Enums.Factions.PLAYER):
			if requesting_ai.global_position.distance_squared_to(player.global_position) <= radius_sq:
				result.append(player)

	for ai in all_ai:
		if ai == null or not is_instance_valid(ai):
			continue
		if ai == requesting_ai or not ai.alive or not ai is Enemy:
			continue
		if Enums.are_hostile(req_faction, (ai as Enemy).faction):
			if requesting_ai.global_position.distance_squared_to(ai.global_position) <= radius_sq:
				result.append(ai)

	return result

func on_sound_emitted(_location: Vector3, _meter_distance: float) -> void:
	pass
