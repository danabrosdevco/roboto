extends Node3D
class_name AIWeapon

# ── EXPORTS ───────────────────────────────────
@export var weapon_type: Enums.AIWeaponTypes
@export var damage: int = 10
@export var fire_cooldown: float = 1.35

# Magazine
@export var magazine_size: int = 10          # rounds per magazine
@export var reload_time: float = 2.0         # seconds to reload
@export var infinite_ammo: bool = false      # useful for turrets / bosses

# FX
@export var muzzle_flash: MuzzleFlash
@export var muzzle_origin: Node3D
@export var shot_audio: AudioStreamPlayer3D
@export var tracer_scene: PackedScene

# Melee
@export var melee_range: float = 1.5
@export var melee_radius: float = 0.6
@export var melee_arc_angle: float = 60.0

# ── STATE ─────────────────────────────────────
var magazine_current: int = 0
var is_reloading: bool = false
var reload_timer: float = 0.0

signal reload_started
signal reload_finished
signal magazine_empty


# ─────────────────────────────────────────────
# READY
# ─────────────────────────────────────────────
func _ready() -> void:
	magazine_current = magazine_size


# ─────────────────────────────────────────────
# PROCESS — reload timer
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	if not is_reloading:
		return
	reload_timer -= delta
	if reload_timer <= 0.0:
		_finish_reload()


# ─────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────

# Returns true if the weapon can fire right now
func can_fire() -> bool:
	return not is_reloading and magazine_current > 0

# Returns true if a reload is needed and not already in progress
func needs_reload() -> bool:
	return magazine_current <= 0 and not is_reloading

func start_reload() -> void:
	if is_reloading or infinite_ammo:
		return
	is_reloading = true
	reload_timer = reload_time
	reload_started.emit()

func fire(weapon_target: Vector3) -> void:
	if not can_fire():
		return

	if not infinite_ammo:
		magazine_current -= 1

	play_shot_audio()

	if weapon_type == Enums.AIWeaponTypes.MELEE:
		check_melee_damage()
	else:
		play_muzzle_flash()
		fire_tracer_spread(weapon_target)
		check_damage(weapon_target)

	# Trigger reload automatically on empty
	if magazine_current <= 0 and not infinite_ammo:
		magazine_empty.emit()
		start_reload()


# ─────────────────────────────────────────────
# INTERNAL
# ─────────────────────────────────────────────
func _finish_reload() -> void:
	is_reloading = false
	reload_timer = 0.0
	magazine_current = magazine_size
	reload_finished.emit()

func check_damage(weapon_target: Vector3) -> void:
	var space_state = get_world_3d().direct_space_state
	var from = muzzle_origin.global_position
	var direction = (weapon_target - from).normalized()
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 250.0)
	query.exclude = [self, get_parent()]
	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		if collider.has_method("apply_damage"):
			collider.apply_damage(damage, get_parent())
		elif collider.get_parent().has_method("apply_damage"):
			collider.get_parent().apply_damage(damage, get_parent())

func check_melee_damage() -> void:
	var space_state = get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = SphereShape3D.new()
	query.shape.radius = melee_radius
	query.transform = Transform3D(Basis(), global_position + get_forward_vector() * melee_range)
	query.collision_mask = 1 | 2 | 4 | 8
	query.exclude = [self, get_parent()]
	var results = space_state.intersect_shape(query, 16)
	for result in results:
		var collider = result.collider
		var to_target = (collider.global_position - global_position).normalized()
		if rad_to_deg(acos(get_forward_vector().dot(to_target))) > melee_arc_angle:
			continue
		if collider.has_method("apply_damage"):
			collider.apply_damage(damage, get_parent())
		elif collider.get_parent().has_method("apply_damage"):
			collider.get_parent().apply_damage(damage, get_parent())

func get_forward_vector() -> Vector3:
	return muzzle_origin.global_transform.basis.x.normalized()

func play_shot_audio() -> void:
	shot_audio.play()

func play_muzzle_flash() -> void:
	muzzle_flash.play_flash()

func fire_tracer() -> void:
	var new_tracer = tracer_scene.instantiate()
	add_child(new_tracer)
	new_tracer.global_position = muzzle_origin.global_position
	var dir = muzzle_origin.global_transform.basis.x.normalized()
	new_tracer.direction = dir
	new_tracer.look_at(new_tracer.global_position + dir)

func fire_tracer_spread(weapon_target: Vector3, spread_count := 8, spread_angle_degrees := 10.0) -> void:
	var aim_dir = (weapon_target - muzzle_origin.global_position).normalized()
	for i in spread_count:
		var new_tracer = tracer_scene.instantiate()
		add_child(new_tracer)
		new_tracer.global_position = muzzle_origin.global_position
		var angle_y = deg_to_rad(randf_range(-spread_angle_degrees, spread_angle_degrees))
		var angle_z = deg_to_rad(randf_range(-spread_angle_degrees, spread_angle_degrees))
		var spread_basis = Basis().rotated(Vector3.UP, angle_y).rotated(Vector3.FORWARD, angle_z)
		var final_dir = (spread_basis * aim_dir).normalized()
		new_tracer.direction = final_dir
		new_tracer.look_at(new_tracer.global_position + final_dir, Vector3.UP)
