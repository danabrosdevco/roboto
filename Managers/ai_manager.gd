extends Node
class_name AIManager

@export var world: World
@export var player: Player

# All registered AI bodies in the current level
var all_ai: Array[AI] = []

func register_enemy(new_enemy: AI) -> void:
	if new_enemy in all_ai:
		return
	all_ai.append(new_enemy)
	# Always give every AI a reference to the player
	# so existing player-targeting code keeps working
	new_enemy.player = player
	# Give it a reference to the manager so it can query targets
	new_enemy.ai_manager = self

func deregister_enemy(enemy: AI) -> void:
	all_ai.erase(enemy)

func reset_all_reg_enemies() -> void:
	all_ai = []

# ─────────────────────────────────────────────
# FACTION QUERY
# Called by Enemy to find the nearest hostile body.
# Returns the closest living CharacterBody3D that
# is hostile to the requesting AI's faction.
# ─────────────────────────────────────────────
func get_nearest_hostile(requesting_ai: AI) -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_dist: float = INF
	var req_faction = requesting_ai.faction

	# Check the player first
	if player != null and player.alive:
		if Enums.are_hostile(req_faction, Enums.Factions.PLAYER):
			var d = requesting_ai.global_position.distance_squared_to(player.global_position)
			if d < best_dist:
				best_dist = d
				best = player

	# Check all other registered AI
	for ai in all_ai:
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

	if player != null and player.alive:
		if Enums.are_hostile(req_faction, Enums.Factions.PLAYER):
			if requesting_ai.global_position.distance_squared_to(player.global_position) <= radius_sq:
				result.append(player)

	for ai in all_ai:
		if ai == requesting_ai or not ai.alive or not ai is Enemy:
			continue
		if Enums.are_hostile(req_faction, (ai as Enemy).faction):
			if requesting_ai.global_position.distance_squared_to(ai.global_position) <= radius_sq:
				result.append(ai)

	return result

func on_sound_emitted(_location: Vector3, _meter_distance: float) -> void:
	pass
