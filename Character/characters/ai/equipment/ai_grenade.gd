extends AIEquipment
class_name AIGrenade

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
	var los_clear = context.owner_ai.is_path_clear(
		context.owner_ai.global_position,
		context.target_position
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
	get_tree().current_scene.add_child(grenade)

	# Spawn at the AI's position, slightly above head height
	var spawn_pos = context.owner_ai.global_position + Vector3.UP * 1.5
	grenade.global_position = spawn_pos
	grenade.setup(context.owner_ai)

	# Compute arc velocity toward target
	var throw_vel = _compute_throw_velocity(
		spawn_pos,
		context.target_position,
		throw_speed
	)
	grenade.linear_velocity = throw_vel

func _compute_throw_velocity(from: Vector3, to: Vector3, speed: float) -> Vector3:
	# Split into horizontal and vertical components.
	# Find the angle that gets us there at the given speed.
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var displacement = to - from
	var horiz = Vector2(displacement.x, displacement.z)
	var horiz_dist = horiz.length()
	var dy = displacement.y

	if horiz_dist < 0.01 or speed <= 0.0:
		return Vector3.ZERO

	# Time to travel horizontal distance
	# We use a fixed 45-degree-ish arc: vy chosen to peak nicely
	# Solve: horiz_dist = vx * t, dy = vy*t - 0.5*g*t^2
	# We pick t such that the arc peaks at ~half the horizontal distance
	# Simple: set arc height = max(2.0, dy + 2.0) above start
	var arc_height = maxf(2.0, dy + 2.5)
	# From arc height: vy = sqrt(2 * g * arc_height)
	var vy = sqrt(2.0 * gravity * arc_height)
	# Time to peak, then time to fall to target
	var t_up = vy / gravity
	var t_down = sqrt(2.0 * maxf(arc_height - dy, 0.01) / gravity)
	var total_time = t_up + t_down

	if total_time <= 0.0:
		return Vector3.ZERO

	var vx = displacement.x / total_time
	var vz = displacement.z / total_time

	return Vector3(vx, vy, vz)

func _check_chokepoint(pos: Vector3) -> bool:
	# Cast two rays perpendicular to the owner→target direction at target position.
	# If both hit geometry within chokepoint_check_width, it's a chokepoint.
	# Uses owner_ai stored in a closure isn't available here directly,
	# so we use a simple world-space check via SceneTree.
	var space = Engine.get_singleton("PhysicsServer3D")
	# Simple approximation: just return false for now.
	# Full implementation needs the space_state which requires a Node reference.
	# This gets called from execute() where we have context — override in subclass
	# or wire space_state in if needed.
	return false
