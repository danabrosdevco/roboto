extends AI
class_name Player

# ─────────────────────────────────────────────
# PLAYER
#
# WHAT CHANGED IN THE EQUIPMENT PASS
# weapon_list / current_weapon_index / set_active_weapon / switch_weapon /
# switch_weapon_direct are gone. They toggled `active` and
# `weapon_model.visible` from out here, which meant an item had no way to react
# to being put away — the reason a reload could finish after you'd switched off
# the weapon. EquipmentLoadout owns selection now and items get a real
# equip/unequip lifecycle.
#
# The fire, reload, slot and scan input blocks collapsed into one
# loadout.update() call. The scanner is a slot item rather than a key with its
# own cooldown timer living on the player.
#
# TWO BUGS THAT WENT WITH THEM, worth knowing about because they'd have looked
# like new bugs otherwise:
#   - weapon switching was chained onto the jump check with `elif`, so you
#     couldn't change weapon on a frame you jumped.
#   - it used is_action_pressed (held) rather than just_pressed, and the
#     is_reloading guard did a bare `return` that ate the rest of the input
#     frame — scan, reload, ADS, lean and interact all silently skipped.
# ─────────────────────────────────────────────

# Node References #
@export var cam: Camera3D
@export var faction: Enums.Factions = Enums.Factions.PLAYER
@export var world: Node3D
@export var hud: Control
@export var scanner: Node3D
@export var command_marker_scene: PackedScene
@export var commander: SquadCommander
@export var obstruction_raycast: RayCast3D
@export var interact_raycast: RayCast3D
@export var health_sfx: AudioStreamPlayer
@export var shards_sfx: AudioStreamPlayer

# ── EQUIPMENT ─────────────────────────────────
# Put the AmmoPool node ABOVE the EquipmentLoadout node in the scene tree.
# Children ready in order and the loadout hands the pool to every item during
# its own _ready, so the pool has to have populated itself first.
@export var loadout: EquipmentLoadout
@export var ammo: AmmoPool

# Export Data #
var coyote_time = 0.12
const SPEED := 6.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.002
# TYPED on purpose. As a bare `= true` the export took any Variant, and when the
# editor saved world.tscn while this script failed to compile it wrote
# `use_gravity = null` onto the player — which `if use_gravity == true` read as
# "no gravity". A typed bool rejects the null and keeps its default.
@export var use_gravity: bool = true
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var health = 100
@export var max_health = 100
## Every hit on the player is scaled by this, whatever it came from. A third:
## the body is 100 HP so the numbers read plainly, but it soaks like 300.
@export var damage_taken_scale: float = 1.0 / 3.0
# The fraction a scaled hit leaves over, carried into the next one so chip
# damage still adds up instead of rounding to nothing.
var _damage_carry: float = 0.0
var shards = 0
var bits = 0
const LEAN_ANGLE := 0.35
const LEAN_SPEED := 5.0
const ADS_FOV := 45.0
const HIP_FOV := 70.0
const ADS_SPEED := 10.0

# Working Data #
var time_since_grounded: float = 0.0
var last_grounded_time: float = 0.0
var coyote_used: bool = false
var is_grounded: bool
var was_grounded: bool
var look_direction: Vector3
@export var look_interp_speed := 12.0  # how fast the camera follows the target

var command_marker_instance: Node3D = null
@export var camera_recoil_scale := 0.75
var camera_recoil_current := Vector3.ZERO
var recoil_rotation := Vector3.ZERO

var current_interactible: Interactible
var alive = true
# Kills this mission. Enemy.apply_damage credits whoever dealt the lethal blow
# by checking `"confirmed_kills" in source` — the Player is a source like any
# other, and without this field the player's own kills were silently dropped.
var confirmed_kills: int = 0
var last_bonfire

# ── SPECTATOR MODE ────────────────────────────
# Toggle with F4. Free-flying camera, not targeted by AI, no collision.
var spectator_mode: bool = false
const SPECTATOR_SPEED: float = 12.0
const SPECTATOR_FAST_MULT: float = 3.0

# WEAPONS #
var is_ads := false
# Toggle-aim state. Only meaningful with AIM MODE set to TOGGLE.
var _aim_latched := false
var target_lean := 0.0
var move_factor := 0.0

signal activate_scanner_ui(time: float)
signal highlight_enemy(target: Node3D, duration: float)
signal activate_interactible_ui(interactible: Interactible)
signal died(value: int, global_position)


func initialize() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	update_last_bonfire(null)
	_wire_loadout()
	update_status()


# The loadout auto-collects every PlayerEquipment under the camera and sorts
# them by slot, so there's no weapon list to build here any more. All this does
# is forward the signals the HUD already listens for.
func _wire_loadout() -> void:
	if loadout == null:
		push_warning("Player: no EquipmentLoadout assigned — no weapons will work.")
		return
	loadout.readout_changed.connect(_on_readout_changed)
	loadout.equipped.connect(_on_equipped)

	# Build what we're carrying from the player's record, exactly as the squad
	# does. Previously the player's kit was whatever nodes happened to be
	# parented under the camera, so fitting a rifle to YOU in the management
	# screen changed a record nobody read.
	# Deferred. In world.tscn the CampaignManager node is declared BELOW
	# test_character, and children ready in declaration order — so at this point
	# it isn't in its group yet and the lookup returns null. That's why fitting
	# a rifle to YOU did nothing: apply_record was never called.
	_bind_campaign.call_deferred()

	for item in loadout.equipment:
		if item is PlayerScanner:
			# Keeps the existing scanner sweep UI working off its new home.
			(item as PlayerScanner).scan_started.connect(
				func(cd: float): activate_scanner_ui.emit(cd))
		elif item is PlayerRepairTool:
			var tool := item as PlayerRepairTool
			# The squad should hold a member still while you're working on them.
			# That's an order, not a new mechanic — SquadCommander already has
			# the vocabulary for it. Hook it up when you're ready:
			# tool.repair_target_pinned.connect(commander.hold_member)
			tool.repaired.connect(func(_t, _a): update_status())


func _bind_campaign() -> void:
	var campaign := get_tree().get_first_node_in_group("campaign")
	if campaign == null or campaign.state == null:
		push_warning("Player: no CampaignManager found — carrying whatever is in the scene.")
		return
	var apply_loadout := func():
		loadout.apply_record(campaign.state.player_record, campaign.get("catalogue"))
		_apply_module_stats(campaign.state.player_record, campaign.get("catalogue"))
	apply_loadout.call()
	# Re-applied on roster changes, so a rifle fitted at base is in your hands
	# before you reach the train rather than next mission.
	campaign.state.roster_changed.connect(apply_loadout)
	if campaign.has_signal("returned_to_base"):
		campaign.returned_to_base.connect(func(): loadout.refill())


# ─────────────────────────────────────────────
# MODULES ON YOURSELF
#
# Squadmates get module stats through SoldierRecord.recompute_stats at spawn.
# The player never did: _bind_campaign rebuilt the loadout and nothing else, so
# every module ever fitted to yourself — the armour plating included — changed
# nothing about your body. It fit, it cost resources, and it did not work.
#
# Layered ON TOP of the authored values rather than replacing them. The player
# is authored at 100 HP (taking a third of every hit, so it soaks like 300);
# deriving it from a chassis the way squadmates are would have dropped you to
# 60 the first time you opened the armoury.
# ─────────────────────────────────────────────
var _base_max_health: int = -1
var _speed_mult: float = 1.0


func _apply_module_stats(record, catalogue) -> void:
	if record == null or catalogue == null:
		return
	if _base_max_health < 0:
		_base_max_health = int(max_health)
	var hp_bonus := 0
	var spd := 1.0
	for id in record.module_ids:
		if id == &"":
			continue
		var m = catalogue.item(id)
		# fits_player() so a squad-only module sitting in your slot somehow
		# (an old save, a hand-edit) still does nothing rather than half-works.
		if m == null or not m.fits_player():
			continue
		hp_bonus += m.health_bonus
		spd *= m.speed_multiplier

	var old_max := int(max_health)
	max_health = maxi(1, _base_max_health + hp_bonus)
	# Keep the damage you have TAKEN constant, the same rule squadmates follow:
	# fitting +25 armour at 300/500 leaves you at 325/525, not 300/525. Never
	# lets unfitting a module kill you, though.
	health = clampi(int(health) + (int(max_health) - old_max), 1, int(max_health))
	_speed_mult = spd
	update_status()


func _on_readout_changed(_readout: PlayerEquipment.Readout) -> void:
	update_status()


func _on_equipped(_item: PlayerEquipment) -> void:
	update_status()


# Convenience for anything that still needs the gun specifically — FOV, the
# debug overlay. Returns null when you're holding a grenade or the scanner,
# so always null-check it.
func current_weapon() -> PlayerWeapon:
	if loadout == null:
		return null
	var item := loadout.current
	if not is_instance_valid(item) or item.is_queued_for_deletion():
		return null
	return item as PlayerWeapon


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# MOUSE_SENS is the base; the options screen scales it, and scales it
		# again while aiming (Settings.look_scale).
		var sens := MOUSE_SENS * Settings.look_scale(is_ads)
		var pitch: float = event.relative.y * (-1.0 if Settings.get_bool("controls.invert_y") else 1.0)
		look_direction.y -= event.relative.x * sens
		look_direction.x = clamp(
			look_direction.x - pitch * sens,
			-1.5,
			1.5
		)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif event.keycode == KEY_F4:
			_toggle_spectator()


func _physics_process(delta: float) -> void:
	# First frame back from the squad manager. The click that closed it may still
	# be held, and the loadout polls the fire action — so without this the menu
	# hands the gun a trigger pull the player never aimed.
	if SquadManagerUI.release_pending:
		SquadManagerUI.release_pending = false
		if loadout != null:
			loadout.block_fire_until_release()

	if spectator_mode == true:
		_handle_spectator(delta)
		return
	check_interactible()
	if use_gravity == true:
		handle_gravity(delta)
	handle_input(delta)
	handle_movement(delta)
	handle_camera(delta)

	# Equipment runs after movement so move_factor is this frame's, and before
	# move_and_slide so a shot fired this frame uses the camera position the
	# player was actually looking from.
	if loadout != null:
		move_factor = clampf(velocity.length() / SPEED, 0.0, 1.0)
		var obstructed := obstruction_raycast != null and obstruction_raycast.is_colliding()
		loadout.update(delta, move_factor, obstructed, is_ads)

	move_and_slide()


func _toggle_spectator() -> void:
	spectator_mode = not spectator_mode
	# Find collision shape safely by type rather than hardcoded name
	var col_shape: CollisionShape3D = null
	for child in get_children():
		if child is CollisionShape3D:
			col_shape = child
			break
	if spectator_mode:
		if col_shape:
			col_shape.set_deferred("disabled", true)
		faction = Enums.Factions.NEUTRAL
		velocity = Vector3.ZERO
		use_gravity = false
		_set_viewmodel_visible(false)
	else:
		if col_shape:
			col_shape.set_deferred("disabled", false)
		faction = Enums.Factions.PLAYER
		velocity = Vector3.ZERO
		use_gravity = true
		_set_viewmodel_visible(true)


func _set_viewmodel_visible(shown: bool) -> void:
	if loadout == null:
		return
	var item := loadout.current
	if is_instance_valid(item) and not item.is_queued_for_deletion():
		item.set_hidden(not shown)


func _handle_spectator(_delta: float) -> void:
	# Mouse look
	var look_basis = Basis()
	look_basis = look_basis.rotated(Vector3.UP, look_direction.y)
	look_basis = look_basis.rotated(look_basis.x, look_direction.x)

	# Horizontal movement — existing inputs
	var input2 := Input.get_vector("ui_left", "ui_right", "ui_down", "ui_up")
	var dir = look_basis.x * input2.x - look_basis.z * input2.y

	# Vertical — Space up, Ctrl down. Shift = fast.
	var fast = Input.is_key_pressed(KEY_SHIFT)
	var speed = SPECTATOR_SPEED * (SPECTATOR_FAST_MULT if fast else 1.0)

	if dir.length_squared() > 0.001:
		dir = dir.normalized() * speed
		velocity.x = dir.x
		velocity.z = dir.z
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	if Input.is_action_pressed("jump"):
		velocity.y = speed
	elif Input.is_key_pressed(KEY_CTRL):
		velocity.y = -speed
	else:
		velocity.y = move_toward(velocity.y, 0.0, speed)

	# Apply camera rotation
	cam.global_transform.basis = look_basis
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
	if spectator_mode == true:
		return
	was_grounded = is_grounded
	is_grounded = is_on_floor()
	if not is_grounded:
		velocity.y -= gravity * delta
		time_since_grounded += delta
	if is_grounded:
		time_since_grounded = 0.0
		last_grounded_time = Time.get_ticks_msec() / 1000.0
		coyote_used = false


func can_coyote_jump() -> bool:
	# Can jump if grounded OR within coyote time window
	if is_grounded:
		return true
	# Coyote time check
	if time_since_grounded <= coyote_time and not coyote_used:
		coyote_used = true  # Prevent double-jumps from coyote
		return true
	return false


# Fire, reload, slot selection and scanning are all gone from here — the
# loadout reads those actions itself. What's left is movement and world
# interaction, which is the right split: this script shouldn't know what a
# magazine is.
func handle_input(_delta: float) -> void:
	# Fullscreen moved to Master._input. Polling it here meant F did nothing
	# whenever _physics_process wasn't running — paused for the squad manager,
	# paused for a level load, or in spectator mode.

	# Its own `if`, not chained onto anything. The old version had the weapon
	# switch as an `elif` on this check.
	if Input.is_action_just_pressed("jump") and can_coyote_jump():
		velocity.y = JUMP_VELOCITY

	# AIM MODE in the options: TOGGLE latches on a click, for anyone who finds
	# holding a mouse button for a whole firefight a strain.
	if Settings.get_bool("controls.toggle_aim"):
		if Input.is_action_just_pressed("aim"):
			_aim_latched = not _aim_latched
		is_ads = _aim_latched
	else:
		_aim_latched = false
		is_ads = Input.is_action_pressed("aim")

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

	# Channelling the repair tool slows you rather than rooting you. Being able
	# to shuffle into cover mid-repair is most of what makes the channel feel
	# like a decision instead of a punishment.
	# _speed_mult is the Overclock Servos module (and anything else with a
	# speed_multiplier). SPEED is a const, so this is the one place it can bend.
	var speed := SPEED * _move_scale() * _speed_mult

	if dir.length_squared() > 0.001:
		dir = dir.normalized() * speed
		velocity.x = dir.x
		velocity.z = dir.z
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)


func _move_scale() -> float:
	if loadout == null:
		return 1.0
	var item := loadout.current
	if not is_instance_valid(item) or item.is_queued_for_deletion():
		return 1.0
	if item is PlayerRepairTool:
		return (item as PlayerRepairTool).get_move_scale()
	return 1.0


# The weapon half of this moved into PlayerEquipment.update_view, and the
# camera-recoil kick into HUDWeapon.update_view. Don't re-add them here or the
# recoil applies twice.
func handle_camera(delta: float) -> void:
	# FOV adjustment
	# HIP_FOV is only the default now — FIELD OF VIEW in the options sets it.
	var target_fov = ADS_FOV if Input.is_action_pressed("zoom") else Settings.get_float("display.fov")
	var weapon := current_weapon()
	if weapon != null:
		if is_ads and Input.is_action_pressed("zoom"):
			target_fov = weapon.ADS_FOV * 0.6
		elif is_ads:
			target_fov = weapon.ADS_FOV

	cam.fov = lerp(cam.fov, target_fov, delta * ADS_SPEED)
	cam.rotation.z = lerp(cam.rotation.z, target_lean, delta * LEAN_SPEED)
	# Camera look rotation
	rotation.y = lerp_angle(rotation.y, look_direction.y, delta * look_interp_speed)
	cam.rotation.x = lerp_angle(cam.rotation.x, look_direction.x, delta * look_interp_speed)


func activate_command():
	# Kept so existing call sites and .tscn signal connections don't break.
	# The real work moved to SquadCommander, which owns the "command" action,
	# resolves the verb from what you're aiming at, and dispatches straight to
	# the selected squad. The old body raycast-and-sphere-sweep is gone.
	if commander != null:
		commander._issue_contextual_order()


# Enemies use this instead of reading spectator_mode directly, so ghosting the
# player removes them from targeting in one place.
func is_targetable() -> bool:
	if not alive:
		return false
	if spectator_mode:
		return false
	return true


# Where the player's ATTENTION is. Enemy uses this for activation-distance
# culling. Kept as a seam even though it now just returns the body position.
func get_focus_position() -> Vector3:
	return global_position


func interact(interactible: Interactible):
	if interactible == null:
		return
	match interactible.get_type():
		Enums.InteractTypes.HEALTH:
			apply_healing(interactible.get_value())
		Enums.InteractTypes.SHARDS:
			add_shards(interactible.get_value())
		Enums.InteractTypes.BONFIRE:
			last_bonfire = interactible
			pass
		Enums.InteractTypes.BITS:
			add_bits(interactible.value)
		Enums.InteractTypes.OBJECTIVE:
			# Nothing to collect. The objective connected to this Interactible's
			# `interacted` signal and handles itself.
			pass
		_:
			pass
	interactible.interacted_with()
	current_interactible = null
	update_status()
	activate_interactible_ui.emit(current_interactible)
	pass


# Passes the equipped item's readout rather than reaching into the weapon for
# magazine_capacity, which is what lets a grenade count or a repair charge use
# the same widget. This still calls hud.update_status with its existing six
# arguments so nothing else has to change today — but the better version is:
#
#   hud.update_status(health, max_health, readout, shards, bits)
#
# with hud.gd switching on readout.mode. Worth doing when you touch the HUD.
func update_status():
	if hud == null:
		return
	var readout := PlayerEquipment.Readout.new()
	if loadout != null:
		readout = loadout.get_readout()
	hud.update_status(health, max_health, readout.primary, readout.secondary, shards, bits)


# ─────────────────────────────────────────────
# NOISE
# ─────────────────────────────────────────────
# The AI already has a full stimulus system — AIManager hands every registered
# Enemy a StimulusManager, and enemy weapons emit GUNSHOT_HEARD when they fire.
# The PLAYER's weapons never did, so the player was silent to the AI: you could
# empty a magazine three metres from a patrol and none of them would react.
#
# Lives on Player rather than on the weapon so grenades, melee and anything else
# noisy can call it without each finding the manager for itself.
var _stimulus_manager: StimulusManager


func get_stimulus_manager() -> StimulusManager:
	if _stimulus_manager != null:
		return _stimulus_manager
	if world != null and world.ai_manager != null:
		_stimulus_manager = world.ai_manager.stimulus_manager
	return _stimulus_manager


func emit_noise(type: StimulusManager.StimulusType, radius: float = -1.0, at: Vector3 = Vector3.INF) -> void:
	var manager := get_stimulus_manager()
	if manager == null:
		return
	var origin := global_position if at == Vector3.INF else at
	manager.emit_stimulus(type, origin, faction, self, radius)


func _on_scanner_highlight_target(target: Node3D, duration: float) -> void:
	highlight_enemy.emit(target, duration)


func apply_damage(damage, _source):
	if alive == false:
		return
	_damage_carry += float(damage) * damage_taken_scale
	var whole := int(floor(_damage_carry))
	_damage_carry -= whole
	health -= whole
	# Taking fire breaks a repair channel. Progress survives for resume_grace
	# seconds, so ducking into cover and resuming doesn't start from zero.
	if loadout != null:
		var item := loadout.current
		if is_instance_valid(item) and not item.is_queued_for_deletion() \
				and item is PlayerRepairTool:
			(item as PlayerRepairTool).interrupt()
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
	#if health_sfx != null:
		#health_sfx.play()
	update_status()


func add_shards(value):
	shards += value
	shards_sfx.play()
	update_status()


func add_bits(value):
	bits += value
	update_status()


func update_last_bonfire(bonfire: Node3D):
	if bonfire == null:
		if world.current_level == null:
			return
		last_bonfire = world.current_level.spawn_point.global_position
		return
	last_bonfire = bonfire


func reset():
	set_process(true)
	set_physics_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
	alive = true
	health = max_health
	_damage_carry = 0.0
	# Was: hud_weapon.magazine_capacity = hud_weapon.magazine_size, which
	# refilled one gun and nothing else. refill() resets every reserve from the
	# starting AmmoStock list.
	#
	# THIS IS A DESIGN DECISION, not just a port. Refilling here makes ammo a
	# per-life resource and the pressure per-encounter. Delete the call and it
	# becomes per-mission and dying compounds — much harsher, and only fair if
	# resupply is reliable.
	if loadout != null:
		loadout.refill()
	if last_bonfire is Vector3:
		global_position = last_bonfire
	if last_bonfire is Bonfire:
		global_position = last_bonfire.global_position
	update_status()


func die():
	alive = false
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	# Delay to allow any death effects (like sounds, particles)
	await get_tree().create_timer(0.5).timeout
	died.emit(bits, global_position)
	bits = 0


func get_faction():
	return faction
