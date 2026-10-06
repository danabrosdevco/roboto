extends AIEquipment
class_name AIGrenade

# Playtest analytics. By path: see the note in analytics.gd.
const _Analytics := preload("res://Managers/analytics.gd")

# ─────────────────────────────────────────────
# AI GRENADE
# Extends AIEquipment. Handles tactical decision
# (can_use) and throw arc computation (execute).
#
# Use conditions (Squad-realistic):
#   - Target has been stationary behind cover for a while
#   - Multiple hostiles clustered near target position
#   - AI is reloading and wants to suppress during reload
#   - Target is in a chokepoint (narrow geometry)
# ─────────────────────────────────────────────

@export var grenade_scene: PackedScene      # AIGrenadeProjectile scene
@export var throw_speed: float = 14.0       # initial velocity magnitude
@export var min_throw_distance: float = 4.0 # won't throw if target closer than this
@export var max_throw_distance: float = 30.0
@export var cluster_radius: float = 3.0     # radius to count nearby hostiles
@export var cluster_min_count: int = 2      # min hostiles in cluster to warrant throw
@export var stationary_time_threshold: float = 2.5  # seconds target must be still
@export var chokepoint_check_width: float = 2.0  # width to detect chokepoints

func can_use(context: AIEquipment.EquipmentContext) -> bool:
	if context.combat_target == null:
		return false

	var dist = context.owner_ai.global_position.distance_to(context.target_position)

	# Distance check
	if dist < min_throw_distance or dist > max_throw_distance:
		return false

	# Don't throw if we have direct LOS (just shoot them)
	# Grenades are for targets behind cover
	#
	# THIS COULD NEVER ANSWER YES. It cast from `global_position` — the feet,
	# inside the floor collider — at `target_position`, which is the target's own
	# origin, so the ray terminated inside the target's own body. `los_clear` was
	# false in an empty field, every time, and the rule below it has never once
	# fired: grenades have always been thrown at targets standing in the open
	# with nothing between.
	#
	# Both corrections are load-bearing and both are what every other sight test
	# in the game already does (enemy.gd does it in nine places, _update_los
	# included): start at eye height, and exclude the body you are looking AT.
	var los_clear = context.owner_ai.is_path_clear(
		context.owner_ai.global_position + Vector3.UP * 0.8,
		context.target_position,
		context.combat_target
	)
	if los_clear:
		# Exception: clustered targets are worth grenading even in the open
		if context.nearby_hostiles.size() < cluster_min_count:
			return false

	# At least one condition must be met:
	var target_is_stationary = context.time_since_target_moved >= stationary_time_threshold
	var target_is_clustered  = context.nearby_hostiles.size() >= cluster_min_count
	var owner_is_reloading   = context.owner_is_reloading
	var target_in_chokepoint = _check_chokepoint(context.target_position)

	return target_is_stationary or target_is_clustered or owner_is_reloading or target_in_chokepoint

func execute(context: AIEquipment.EquipmentContext) -> void:
	if grenade_scene == null:
		push_error("AIGrenade: no grenade_scene assigned.")
		return

	var grenade = grenade_scene.instantiate() as AIGrenadeProjectile
	# THE LEVEL, not the current scene. See AIEquipment.spawn_host — the scene is
	# Master, which outlives the mission and took the ordnance with it.
	var host: Node = spawn_host(context.owner_ai)
	if host == null:
		return
	host.add_child(grenade)

	# Spawn at the AI's position, slightly above head height
	var spawn_pos = context.owner_ai.global_position + Vector3.UP * 1.5
	grenade.global_position = spawn_pos
	grenade.setup(context.owner_ai)
	_Analytics.throw(context.owner_ai, _Analytics.label_for_scene(grenade_scene.resource_path))

	# Compute arc velocity toward target — or toward the point the player
	# designated, when this throw was ordered rather than chosen.
	var throw_vel = _compute_throw_velocity(
		spawn_pos,
		placement_or(context, context.target_position),
		throw_speed
	)
	grenade.linear_velocity = throw_vel

## The solve now lives on AIEquipment, because smoke and both mines throw at a
## point too and three private copies of one ballistics solve is how a fix to
## the arc silently stops applying to two thirds of the kit.
##
## `speed` was never read — the solve picks an arc height and lets the velocity
## fall out of it — so throw_speed has always been decoration on this scene.
## Kept in the signature rather than removed: ai_grenade.tscn, ai_emp_grenade.tscn
## and ai_mortar_round.tscn all set throw_speed, and dropping an export the
## scenes assign makes three scenes fail to load.
func _compute_throw_velocity(from: Vector3, to: Vector3, _speed: float) -> Vector3:
	return AIEquipment.throw_velocity(from, to)

func _check_chokepoint(_pos: Vector3) -> bool:
	# Cast two rays perpendicular to the owner→target direction at target position.
	# If both hit geometry within chokepoint_check_width, it's a chokepoint.
	# Uses owner_ai stored in a closure isn't available here directly,
	# so we use a simple world-space check via SceneTree.
	# Simple approximation: just return false for now.
	# Full implementation needs the space_state which requires a Node reference.
	# This gets called from execute() where we have context — override in subclass
	# or wire space_state in if needed.
	return false
