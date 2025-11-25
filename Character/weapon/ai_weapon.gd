extends Node3D
class_name AIWeapon

@export var weapon_type: Enums.AIWeaponTypes
@export var damage: int = 10
@export var fire_cooldown : float = 1.35
@export var muzzle_flash: MuzzleFlash
@export var muzzle_origin: Node3D
@export var shot_audio: AudioStreamPlayer3D
@export var tracer_scene: PackedScene
@export var melee_range: float = 1.5
@export var melee_radius: float = 0.6
@export var melee_arc_angle: float = 60.0 # degrees cone in front

func fire(weapon_target: Vector3):
	play_shot_audio()
	check_damage(weapon_target)
	if weapon_type == Enums.AIWeaponTypes.MELEE:
		check_melee_damage()
		return
	if weapon_type != Enums.AIWeaponTypes.MELEE:
		play_muzzle_flash()
		fire_tracer_spread(weapon_target)

func check_damage(weapon_target: Vector3):
	var space_state = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	var from = muzzle_origin.global_position
	var direction = (weapon_target - from).normalized()
	var to = from + direction * 250.0
	query.from = from
	query.to = to
	query.exclude = [self, get_parent()]
	var result = space_state.intersect_ray(query)
	if result:
		var _hit_pos = result.position
		var collider = result.collider
		#print("Hit:", collider, " at ", hit_pos)
		#var sphere = MeshInstance3D.new()
		#sphere.mesh = SphereMesh.new()
		#sphere.mesh.radius = 0.05  # Very small
		#sphere.mesh.height = 0.1   # Optional if you want a stretched look
		#get_tree().current_scene.add_child(sphere)
		#sphere.global_position = hit_pos
		if collider.has_method("apply_damage"):
			collider.apply_damage(damage, get_parent())
		else:
			if collider.get_parent().has_method("apply_damage"):
				collider.apply_damage(damage, get_parent())

func check_melee_damage():
	var space_state = get_world_3d().direct_space_state

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = SphereShape3D.new()
	query.shape.radius = melee_radius
	query.transform = Transform3D(Basis(), global_position + get_forward_vector() * melee_range)
	query.collision_mask = 1 | 2 | 4 | 8  # whatever layers your characters use
	query.exclude = [self, get_parent()]

	var results = space_state.intersect_shape(query, 16)

	for result in results:
		var collider = result.collider

		# Check arc / cone angle
		var to_target = (collider.global_position - global_position).normalized()
		var forward = get_forward_vector()

		var angle = rad_to_deg(acos(forward.dot(to_target)))
		if angle > melee_arc_angle:
			continue  # outside the cone

		# Damage check
		if collider.has_method("apply_damage"):
			collider.apply_damage(damage, get_parent())
		elif collider.get_parent().has_method("apply_damage"):
			collider.get_parent().apply_damage(damage, get_parent())

func get_forward_vector() -> Vector3:
	return muzzle_origin.global_transform.basis.x.normalized()

func play_shot_audio():
	shot_audio.play()

func play_muzzle_flash():
	muzzle_flash.play_flash()

func fire_tracer():
	var new_tracer = tracer_scene.instantiate()
	add_child(new_tracer)
	# 1. Set starting position at tracer origin (on the weapon)
	new_tracer.global_position = muzzle_origin.global_position
	# 2. Get world-space forward direction from tracer_origin
	var dir = muzzle_origin.global_transform.basis.x.normalized()
	# 3. Set the tracer's direction (assuming it has a .direction property)
	new_tracer.direction = dir
	# 4. Point it visually in the direction (optional but good for visuals)
	new_tracer.look_at(new_tracer.global_position + dir)

func fire_tracer_spread(weapon_target, spread_count := 8, spread_angle_degrees := 10.0):
	for i in spread_count:
			var new_tracer = tracer_scene.instantiate()
			add_child(new_tracer)
			new_tracer.global_position = muzzle_origin.global_position
			# Godot forward is -Z, but your muzzle uses +X
			var base_dir = muzzle_origin.global_transform.basis.x.normalized()
			var angle_y = deg_to_rad(randf_range(-spread_angle_degrees, spread_angle_degrees))
			var angle_z = deg_to_rad(randf_range(-spread_angle_degrees, spread_angle_degrees))
			var spread_basis = Basis()
			spread_basis = spread_basis.rotated(Vector3.UP, angle_y)
			spread_basis = spread_basis.rotated(Vector3.FORWARD, angle_z)
			var final_dir = (spread_basis * base_dir).normalized()
			new_tracer.direction = final_dir
			# Align forward (-Z) with +X direction
			new_tracer.look_at(new_tracer.global_position + final_dir, Vector3.UP)
