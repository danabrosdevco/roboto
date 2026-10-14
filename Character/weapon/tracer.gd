extends Node3D
class_name Tracer

@export var speed: float = 160.0
@export var max_distance: float = 100.0
@export var hit_effect_scene: PackedScene

# --- Tracer scaling config ---
@export var start_scale_z: float = 0.5
@export var end_scale_z: float = 4.0
@export var scale_distance: float = 15  # distance over which tracer lengthens

@export var direction: Vector3
var distance_traveled := 0.0
var is_active := true

# ── ENDPOINT MODE ─────────────────────────────
# When the shooter already knows where the round lands (AIWeapon does —
# check_damage raycasts before spawning the tracer), the tracer just
# travels to that point. No per-frame raycast.
#
# The legacy direction-only path still raycasts, because HUDWeapon and
# AIWorldWeapon rely on it to place impact effects.
var _end_point: Vector3 = Vector3.ZERO
var _has_end_point: bool = false
var _spawn_hit_effect: bool = true


# ── WHOSE ROUND IS IT ─────────────────────────
# Every weapon in the game fired the same orange tracer, so your fire and
# theirs were pixel-identical and a firefight had no readable direction to it.
# Incoming is now red and outgoing is yellow-white.
#
# TWO SHARED MATERIALS, MADE ONCE. The authored material is a sub-resource of
# tracer.tscn, which means every instance gets the SAME object — setting a
# shader parameter on one tracer would recolour every tracer in the game, which
# is the resource-sharing trap this project has paid for before. Duplicating
# per tracer would be correct and would also allocate a ShaderMaterial on every
# bullet fired. Two variants built on first use and handed out by reference
# cost one allocation each, ever.
static var _tint_cache: Dictionary = {}

## Incoming. A deep red that is still clearly a hot round, not a laser.
const HOSTILE_HEAD := Color(1.0, 0.80, 0.72)
const HOSTILE_BODY := Color(1.0, 0.30, 0.16)
const HOSTILE_TAIL := Color(0.70, 0.06, 0.03)
## Outgoing. Pushed well off the hostile hue rather than merely lightened,
## because signal_filter subsamples chroma and quantises it to five levels —
## two colours a hue apart survive that, two shades of the same one do not.
const FRIENDLY_HEAD := Color(1.0, 0.99, 0.90)
const FRIENDLY_BODY := Color(1.0, 0.88, 0.30)
const FRIENDLY_TAIL := Color(0.92, 0.58, 0.08)


func _ready() -> void:
	# Never inherit the shooter's transform. Tracers were parented to the
	# weapon, so they were dragged sideways whenever the shooter turned.
	top_level = true


## Colour this round by who fired it. `shooter_faction` is an Enums.Factions,
## or null when nothing claimed the shot — which stays the friendly colour,
## since an unattributed round is almost always scenery or the player's own.
func set_side(shooter_faction) -> void:
	var hostile: bool = shooter_faction != null \
			and Enums.are_hostile(Enums.Factions.PLAYER, shooter_faction)
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		return
	mesh.material_override = _tint_for(hostile, mesh.material_override)


static func _tint_for(hostile: bool, base: Material) -> Material:
	if _tint_cache.has(hostile):
		return _tint_cache[hostile]
	if not (base is ShaderMaterial):
		return base
	var m: ShaderMaterial = (base as ShaderMaterial).duplicate()
	m.set_shader_parameter("head_color", HOSTILE_HEAD if hostile else FRIENDLY_HEAD)
	m.set_shader_parameter("body_color", HOSTILE_BODY if hostile else FRIENDLY_BODY)
	m.set_shader_parameter("tail_color", HOSTILE_TAIL if hostile else FRIENDLY_TAIL)
	_tint_cache[hostile] = m
	return m


## Preferred entry point: travel from `from` to a known impact point.
func launch(from: Vector3, to: Vector3, spawn_effect: bool = true) -> void:
	top_level = true
	global_position = from
	_end_point = to
	_has_end_point = true
	_spawn_hit_effect = spawn_effect
	var delta_v = to - from
	if delta_v.length() < 0.001:
		queue_free()
		return
	direction = delta_v.normalized()
	look_at(global_position + direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	if not is_active:
		return

	if _has_end_point:
		_tick_to_endpoint(delta)
	else:
		_tick_legacy(delta)


func _tick_to_endpoint(delta: float) -> void:
	var step = speed * delta
	var remaining = global_position.distance_to(_end_point)
	if step >= remaining:
		global_position = _end_point
		is_active = false
		if _spawn_hit_effect and hit_effect_scene:
			var effect = hit_effect_scene.instantiate()
			get_tree().current_scene.add_child(effect)
			effect.global_position = _end_point
		queue_free()
		return
	global_translate(direction * step)
	distance_traveled += step
	_update_stretch()


func _tick_legacy(delta: float) -> void:
	var move_amount = direction * speed * delta
	var space_state = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + move_amount)
	var exclusion: Array[RID] = []
	query.exclude = exclusion
	var result = space_state.intersect_ray(query)
	if result:
		is_active = false
		global_position = result.position
		if hit_effect_scene:
			var effect = hit_effect_scene.instantiate()
			get_tree().current_scene.add_child(effect)
			effect.global_position = result.position
		queue_free()
		return

	global_translate(move_amount)
	distance_traveled += move_amount.length()
	_update_stretch()
	if distance_traveled >= max_distance:
		is_active = false
		queue_free()


func _update_stretch() -> void:
	var t = clamp(inverse_lerp(0.0, scale_distance, distance_traveled), 0.0, 1.0)
	scale.z = lerp(start_scale_z, end_scale_z, t)
