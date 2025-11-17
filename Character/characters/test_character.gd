extends CharacterBody3D
class_name Player

# Node References # 
@export var cam: Camera3D 
@export var faction: Enums.Factions = Enums.Factions.PLAYER
@export var hud_weapon: HUDWeapon
@export var world: Node3D
@export var hud: Control
@export var scanner: Node3D
@export var command_marker_scene: PackedScene
@export var obstruction_raycast: RayCast3D
@export var interact_raycast: RayCast3D
@export var health_sfx: AudioStreamPlayer
@export var shards_sfx: AudioStreamPlayer
@export var weapon_list: Array[HUDWeapon]
var current_weapon_index: int
# Export Data # 
const SPEED := 6.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.002
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var health = 50
@export var max_health = 100
var shards = 0
const LEAN_ANGLE := 0.35
const LEAN_SPEED := 5.0
const ADS_FOV := 45.0
const HIP_FOV := 70.0
const ADS_SPEED := 10.0

# Working Data #

var is_fullscreen = false
var look_direction: Vector3
@export var look_interp_speed := 12.0  # how fast the camera follows the target

var command_marker_instance: Node3D = null
@export var camera_recoil_scale := 0.75  # fraction of recoil applied to camera
var camera_recoil_current := Vector3.ZERO  # yaw (x), pitch (y)
var recoil_rotation := Vector3.ZERO

var scanner_timer: = 0.0
var scanner_cooldown = 3


var current_interactible : Interactible



# WEAPONS #
var is_ads := false
var fire_held_last_frame := false
var target_lean := 0.0
var pitch := 0.0

signal activate_scanner_ui
signal highlight_enemy(target:Node3D, duration: float)
signal activate_interactible_ui(interactible: Interactible)

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	update_status()
	for child in cam.get_children():
		if child is HUDWeapon:
			if weapon_list.has(child):
				continue
			else:
				weapon_list.append(child)
		else:
				continue
	if weapon_list.size() > 0:
		current_weapon_index = 0
		set_active_weapon(0)

func set_active_weapon(index: int):
	# Deactivate all weapons
	for i in weapon_list.size():
		weapon_list[i].active = false
		weapon_list[i].weapon_model.visible = false
	
	# Activate the selected one
	current_weapon_index = index
	hud_weapon = weapon_list[index]
	hud_weapon.active = true
	hud_weapon.weapon_model.visible = true
	#print("✅ Switched to weapon:", hud_weapon.name)

func switch_weapon(direction: int):
	var next_index = (current_weapon_index + direction) % weapon_list.size()
	if next_index < 0:
		next_index = weapon_list.size() - 1
	set_active_weapon(next_index)
	update_status()

func switch_weapon_direct(index: int):
	if index >= 0 and index < weapon_list.size():
		set_active_weapon(index)
	update_status()



func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Update the clean look direction, not the actual camera yet
		look_direction.y -= event.relative.x * MOUSE_SENS  # yaw
		look_direction.x = clamp(
			look_direction.x - event.relative.y * MOUSE_SENS, 
			-1.5, 
			1.5
		)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _physics_process(delta: float) -> void:
	scanner_timer -= delta
	check_interactible()
	handle_gravity(delta)
	handle_input(delta)
	handle_movement(delta)
	handle_camera_and_weapon(delta)
	move_and_slide()

func check_interactible():
	if interact_raycast and interact_raycast.is_colliding():
		var collider = interact_raycast.get_collider()
		if !collider:
			return
		if collider is not Interactible:
			return
		if collider.used == true:
			return
		if current_interactible == collider:
			return
		current_interactible = collider
		activate_interactible_ui.emit(current_interactible)
		return
	else:
		if current_interactible:
			current_interactible = null
			activate_interactible_ui.emit(current_interactible)


func handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta


func handle_input(_delta: float) -> void:
	if Input.is_action_just_pressed("fullscreen"):
		is_fullscreen = !is_fullscreen
		if is_fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


	var fire_pressed := Input.is_action_pressed("fire")
	var fire_just_pressed := Input.is_action_just_pressed("fire")

	match hud_weapon.firemode:
		Enums.FireModes.FULL:
			if fire_pressed:
				hud_weapon.fire()
		Enums.FireModes.SEMI:
			if fire_just_pressed and not fire_held_last_frame:
				hud_weapon.fire()
	fire_held_last_frame = fire_pressed
	if Input.is_action_just_pressed("command"):
		activate_command()

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY


	#if Input.is_action_pressed("weapon_next"):
		#switch_weapon(1)
	#elif Input.is_action_pressed("weapon_prev"):
		#switch_weapon(-1)
	elif Input.is_action_pressed("1"):
		switch_weapon_direct(0)
	elif Input.is_action_pressed("2"):
		switch_weapon_direct(1)

	if Input.is_action_just_pressed("scan"):
		if scanner_timer >= 0:
			return
		scanner_timer = scanner_cooldown
		scanner.activate_scan()
		activate_scanner_ui.emit()

	if Input.is_action_just_pressed("reload"):
		hud_weapon.start_reload()

	is_ads = Input.is_action_pressed("aim")
	hud_weapon.is_ads = is_ads
	if Input.is_action_pressed("lean_left"):
		target_lean = LEAN_ANGLE
	elif Input.is_action_pressed("lean_right"):
		target_lean = -LEAN_ANGLE
	else:
		target_lean = 0.0

	if Input.is_action_just_pressed("interact") and current_interactible != null:
		interact(current_interactible)


func handle_movement(_delta: float) -> void:
	var input2 := Input.get_vector("ui_left", "ui_right", "ui_down", "ui_up")
	var new_basis = transform.basis
	var dir = new_basis.x * input2.x - new_basis.z * input2.y

	if dir.length_squared() > 0.001:
		dir = dir.normalized() * SPEED
		velocity.x = dir.x
		velocity.z = dir.z
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)
		velocity.z = move_toward(velocity.z, 0.0, SPEED)

func handle_camera_and_weapon(delta: float) -> void:
	var move_factor = clamp(velocity.length() / SPEED, 0.0, 1.0)
	hud_weapon.set_move_factor(move_factor)
	hud_weapon.is_obstructed = obstruction_raycast.is_colliding()
	hud_weapon.pitch = look_direction.x
	# FOV adjustment
	var target_fov = ADS_FOV if Input.is_action_pressed("zoom") else HIP_FOV
	if is_ads and Input.is_action_pressed("zoom"):
		target_fov = hud_weapon.ADS_FOV * 0.6
	elif is_ads:
		target_fov = hud_weapon.ADS_FOV

	cam.fov = lerp(cam.fov, target_fov, delta * ADS_SPEED)
	cam.rotation.z = lerp(cam.rotation.z, target_lean, delta * LEAN_SPEED)
	# Camera look rotation
	rotation.y = lerp_angle(rotation.y, look_direction.y, delta * look_interp_speed)
	cam.rotation.x = lerp_angle(cam.rotation.x, look_direction.x, delta * look_interp_speed)

func activate_command():
	# Raycast from the camera to where it's looking
	var ray_origin = cam.global_position
	var ray_end = ray_origin + cam.global_transform.basis.z * -1000  # Forward direction in Godot is -Z
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collision_mask = 1  # Set this if your terrain/ground uses a specific mask

	var result = space_state.intersect_ray(query)

	if result:
		var target_position = result.position

		# If we already have a command marker, move it
		if command_marker_instance and is_instance_valid(command_marker_instance):
			command_marker_instance.global_position = target_position
			command_marker_instance.global_position.y = 0
			command_marker_instance.rotation = Vector3(0,0,0)
			command_marker_instance.perform_faction_check()
		else:
			# Spawn new marker
			command_marker_instance = command_marker_scene.instantiate()
			world.add_child(command_marker_instance)
			command_marker_instance.global_position = target_position
			command_marker_instance.global_position.y = 0
			command_marker_instance.rotation = Vector3(0,0,0)

			# Optional: Assign faction/team if needed
			if command_marker_instance.has_method("set_faction"):
				command_marker_instance.set_faction(faction)
			await get_tree().create_timer(0.1).timeout
			command_marker_instance.perform_faction_check()
			# Optional: orient marker to look forward from camera
			#command_marker_instance.look_at(target_position + cam.global_transform.basis.z * -1, Vector3.UP)
	else:
		print("No valid target point found where camera is looking.")
	pass

func interact(interactible:Interactible):
	if interactible == null:
		return
	match interactible.get_type():
		Enums.InteractTypes.HEALTH:
			apply_healing(interactible.get_value())
		Enums.InteractTypes.SHARDS:
			add_shards(interactible.get_value())
		Enums.InteractTypes.BONFIRE:
			pass
		_:
			print("Unknown interactible type")
	interactible.interacted_with()
	current_interactible = null
	update_status()
	activate_interactible_ui.emit(current_interactible)
	pass

func update_status():
	if hud_weapon == null:
		await get_tree().process_frame
	hud.update_status(health, hud_weapon.magazine_capacity, hud_weapon.magazine_size, shards)


func _on_scanner_highlight_target(target: Node3D, duration: float) -> void:
	#print ("TIME TO HIGHLIGHT!")
	highlight_enemy.emit(target, duration)


func apply_damage(damage):
	health -= damage
	update_status()
	if health <= 0:
		health = 0
		die()
	pass

func apply_healing(healing):
	var new_health = health + healing
	if new_health >= max_health:
		new_health = max_health
	health = new_health
	health_sfx.play()
	update_status()
func add_shards(value):
	shards += value
	shards_sfx.play()
	update_status()

func reset():
	health = max_health
	hud_weapon.magazine_capacity = hud_weapon.magazine_size

func die():
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	# Delay to allow any death effects (like sounds, particles)
	await get_tree().create_timer(0.25).timeout
	# Show cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Optional: Unlock the camera or transition
	# You might want to detach camera from the player before freeing the node
	# For now, we just clean up:
	queue_free()
func get_faction():
	return faction
