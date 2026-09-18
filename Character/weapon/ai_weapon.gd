extends Node3D
class_name AIWeapon

# ── EXPORTS ───────────────────────────────────
@export var weapon_type: Enums.AIWeaponTypes
@export var fire_cooldown: float = 1.35

# Damage
@export var base_damage: int = 36            # damage at point-blank / falloff start
@export var min_damage: int = 18             # floor damage at max effective range
@export var damage_falloff_start: float = 20.0  # range at which falloff begins (m)

# Range
@export var min_effective_range: float = 0.0    # won't fire closer than this
@export var max_effective_range: float = 70.0   # max range for range checks

# Spread — in milliradians. At distance D, spread = mrad * D / 1000 metres.
@export var ai_spread_mrad: float = 6.0

# Suppression — signal_integrity damage applied to enemies near each shot.
@export var suppression_per_shot: float = 3.0   # signal_integrity units × 100
@export var near_miss_radius: float = 2.5       # metres

## Collision mask used for near-miss and melee queries. Restricting this to
## character layers stops every shot from testing terrain geometry.
@export_flags_3d_physics var character_mask: int = 1 | 2 | 4 | 8

## When false, rounds pass through same-faction bodies. Advancing soldiers
## were shooting their own squadmates in the back.
# Rounds DO hit allies — they just hit softer. Passing them straight through was
# the wrong fix: it meant you could stand in your own squad's line forever with
# no consequence, which makes the sidestep below pointless and makes the world
# feel fake. A third of damage is enough to punish a careless push without one
# stray burst wiping your own fireteam.
@export var friendly_fire: bool = true
@export var friendly_fire_multiplier: float = 0.34

# Magazine
@export var magazine_size: int = 30          # rounds per magazine
@export var reload_time: float = 2.8         # seconds to reload
@export var infinite_ammo: bool = false      # useful for turrets / bosses

# FX
@export var muzzle_flash: MuzzleFlash
@export var muzzle_origin: Node3D
@export var shot_audio: AudioStreamPlayer3D
@export var tracer_scene: PackedScene
## Visual-only tracer jitter, in degrees. The old code spawned 8 tracers
## per shot at 10 degrees of spread, none of which matched the single
## hitscan ray that actually did the damage.
@export var tracer_jitter_degrees: float = 0.6

# Melee
@export var melee_range: float = 1.5
@export var melee_radius: float = 0.6
@export var melee_arc_angle: float = 60.0

# ── STATE ─────────────────────────────────────
var magazine_current: int = 0
var is_reloading: bool = false
var reload_timer: float = 0.0

# Reused query objects — the old code allocated a fresh SphereShape3D and
# PhysicsShapeQueryParameters3D on every single shot.
var _near_miss_shape: SphereShape3D
var _near_miss_query: PhysicsShapeQueryParameters3D
# Reused across the four friendly-fire passes rather than reallocated per pass.
var _ff_query: PhysicsRayQueryParameters3D
var _melee_shape: SphereShape3D
var _melee_query: PhysicsShapeQueryParameters3D

signal reload_started
signal reload_finished
signal magazine_empty


# ─────────────────────────────────────────────
# READY
# ─────────────────────────────────────────────
func _ready() -> void:
	magazine_current = magazine_size

	_near_miss_shape = SphereShape3D.new()
	_near_miss_shape.radius = near_miss_radius
	_near_miss_query = PhysicsShapeQueryParameters3D.new()
	_near_miss_query.shape = _near_miss_shape
	_near_miss_query.collide_with_bodies = true
	_near_miss_query.collide_with_areas = false
	_near_miss_query.collision_mask = character_mask

	_melee_shape = SphereShape3D.new()
	_melee_shape.radius = melee_radius
	_melee_query = PhysicsShapeQueryParameters3D.new()
	_melee_query.shape = _melee_shape
	_melee_query.collision_mask = character_mask


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
func can_fire() -> bool:
	return not is_reloading and magazine_current > 0


# When a round last left this weapon.
#
# The squad HUD used to read ai_state == COMBAT as "FIRING", which is really
# "has a target" — so a soldier who had acquired someone and then spent ten
# seconds walking, reloading or waiting for a shot still read FIRING the whole
# time. That is the status getting stuck. A recency window on actual shots is
# the only honest answer to "is this one shooting".
var _last_fired_ms: int = -100000


func seconds_since_fired() -> float:
	return (Time.get_ticks_msec() - _last_fired_ms) / 1000.0

func needs_reload() -> bool:
	return not infinite_ammo and magazine_current <= 0 and not is_reloading

func start_reload() -> void:
	if is_reloading or infinite_ammo:
		return
	is_reloading = true
	reload_timer = reload_time
	reload_started.emit()

func fire(weapon_target: Vector3) -> void:
	if not can_fire():
		return

	_last_fired_ms = Time.get_ticks_msec()
	if not infinite_ammo:
		magazine_current -= 1

	play_shot_audio()

	if weapon_type == Enums.AIWeaponTypes.MELEE:
		check_melee_damage()
	else:
		play_muzzle_flash()
		check_damage(weapon_target)

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

func calculate_damage(distance: float) -> int:
	if distance <= damage_falloff_start:
		return base_damage
	var range_beyond = max_effective_range - damage_falloff_start
	if range_beyond <= 0.0:
		return min_damage
	var t = clamp((distance - damage_falloff_start) / range_beyond, 0.0, 1.0)
	return int(lerp(float(base_damage), float(min_damage), t))

# The owning character, not merely the node this weapon hangs off.
#
# Baked chassis scenes park the weapon directly on the CharacterBody3D, so
# get_parent() was right for them — and every enemy in the game is baked.
# equip_weapon_scene() parents a RUNTIME-fitted weapon to weapon_mount instead,
# a bare Node3D, and every runtime-fitted weapon belongs to the player's squad.
#
# That single difference cost four things, all of them silent:
#   - no confirmed_kills on the mount, so squad kill credit was dropped
#   - no bark, so squad members never called out a kill
#   - no get_faction(), so _owner_faction() returned null, _is_friendly()
#     answered false for everybody, and they would happily shoot you
#   - not a CollisionObject3D, so their own body was never excluded from their
#     raycast
#
# Cached because this runs per shot and thirty robots fire at once.
var _owner_cache: Node = null


func _owner_body() -> Node:
	if _owner_cache != null and is_instance_valid(_owner_cache):
		return _owner_cache
	var n: Node = get_parent()
	while n != null:
		if n is CharacterBody3D:
			_owner_cache = n
			return n
		n = n.get_parent()
	_owner_cache = get_parent()
	return _owner_cache


func _owner_faction():
	var p = _owner_body()
	if p != null and p.has_method("get_faction"):
		return p.get_faction()
	return null

# "Friendly" means NOT HOSTILE, not "same faction". Enums.Factions.PLAYER and
# Enums.Factions.ALLIED are different values, so an equality test says your own
# squad and you are not friendly to each other — which is why they were putting
# rounds into you and into each other across the faction line. are_hostile() is
# the same test the AI uses to pick targets, so shooting and targeting finally
# agree about who's on whose side.
# Answers "is this one of ours", nothing more. It used to return false whenever
# friendly_fire was on, which conflated "is an ally" with "may be shot" — now
# that allies CAN be shot, those have to be separate questions.
func _is_friendly(body: Node) -> bool:
	var mine = _owner_faction()
	if mine == null:
		return false
	if not body.has_method("get_faction"):
		return false
	return not Enums.are_hostile(mine, body.get_faction())

# True when a non-hostile body is between the muzzle and the target. Firing
# anyway looks careless even when the round passes through — and it wastes
# ammunition the squad now has a finite amount of.
func friendly_in_line(weapon_target: Vector3) -> bool:
	if muzzle_origin == null:
		return false
	var from: Vector3 = muzzle_origin.global_position
	var to_target: Vector3 = weapon_target - from
	var distance: float = to_target.length()
	if distance < 0.01:
		return false
	var direction: Vector3 = to_target / distance

	var exclusion: Array[RID] = []
	var shooter = _owner_body()
	if shooter is CollisionObject3D:
		exclusion.append((shooter as CollisionObject3D).get_rid())

	# Both hoisted out of the loop. The space state cannot change between passes,
	# and the query was being reallocated four times per shot — with thirty
	# robots firing, that is the second-hottest path in the game allocating for
	# no reason. Everything else in this file already caches its query object;
	# this was the one that didn't.
	var space := space_state_or_null()
	if space == null:
		return false
	if _ff_query == null:
		_ff_query = PhysicsRayQueryParameters3D.new()
	var to_point := from + direction * distance

	for _pass in 4:
		var query := _ff_query
		query.from = from
		query.to = to_point
		query.exclude = exclusion
		var hit = space.intersect_ray(query)
		if not hit:
			return false
		var collider = hit.collider
		var damageable: Node = null
		if collider.has_method("apply_damage"):
			damageable = collider
		elif collider.get_parent() != null and collider.get_parent().has_method("apply_damage"):
			damageable = collider.get_parent()
		if damageable == null:
			return false   # geometry — a wall isn't a friendly-fire problem
		if _is_friendly(damageable):
			return true
		if collider is CollisionObject3D:
			exclusion.append((collider as CollisionObject3D).get_rid())
	return false


func space_state_or_null() -> PhysicsDirectSpaceState3D:
	var world := get_world_3d()
	return world.direct_space_state if world != null else null


signal friendly_hit(body: Node)


func check_damage(weapon_target: Vector3) -> void:
	var space_state = get_world_3d().direct_space_state
	var from = muzzle_origin.global_position
	var direction = (weapon_target - from).normalized()

	var exclusion: Array[RID] = []
	var shooter = _owner_body()
	if shooter is CollisionObject3D:
		exclusion.append((shooter as CollisionObject3D).get_rid())

	var impact = from + direction * max_effective_range
	var hit_body: Node = null
	var hit_dist: float = max_effective_range

	# The round stops at the FIRST thing it meets, ally or not. Who it was only
	# changes how hard it lands.
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 250.0)
	query.exclude = exclusion
	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		var damageable: Node = null
		if collider.has_method("apply_damage"):
			damageable = collider
		elif collider.get_parent() != null and collider.get_parent().has_method("apply_damage"):
			damageable = collider.get_parent()
		impact = result.position
		hit_dist = from.distance_to(result.position)
		hit_body = damageable

	if hit_body != null:
		var dealt: int = calculate_damage(hit_dist)
		if _is_friendly(hit_body):
			dealt = maxi(1, int(round(float(dealt) * friendly_fire_multiplier)))
			friendly_hit.emit(hit_body)
		hit_body.apply_damage(dealt, shooter)

	# One tracer, along the line the round actually took.
	fire_tracer_to(from, impact)

	if suppression_per_shot > 0.0:
		_apply_near_miss_suppression(impact)

func _apply_near_miss_suppression(shot_pos: Vector3) -> void:
	var space_state = get_world_3d().direct_space_state
	_near_miss_shape.radius = near_miss_radius
	_near_miss_query.transform = Transform3D(Basis(), shot_pos)
	_near_miss_query.collision_mask = character_mask
	var results = space_state.intersect_shape(_near_miss_query, 8)
	var suppression_amount = suppression_per_shot / 100.0
	var shooter = _owner_body()
	for hit in results:
		var body = hit.collider
		if body == null:
			continue
		if not body.has_method("apply_damage"):
			var parent_body = body.get_parent()
			if parent_body != null and parent_body.has_method("apply_damage"):
				body = parent_body
		if body == shooter:
			continue
		if _is_friendly(body):
			continue
		if "signal_integrity" in body:
			if body.has_method("receive_signal_damage"):
				body.receive_signal_damage(suppression_amount)
			else:
				body.signal_integrity = maxf(0.0, body.signal_integrity - suppression_amount)

func check_melee_damage() -> void:
	var space_state = get_world_3d().direct_space_state
	_melee_shape.radius = melee_radius
	_melee_query.transform = Transform3D(Basis(), global_position + get_forward_vector() * melee_range)
	_melee_query.collision_mask = character_mask
	var exclusion: Array[RID] = []
	var shooter = _owner_body()
	if shooter is CollisionObject3D:
		exclusion.append((shooter as CollisionObject3D).get_rid())
	_melee_query.exclude = exclusion

	var results = space_state.intersect_shape(_melee_query, 16)
	for result in results:
		var collider = result.collider
		var to_target = (collider.global_position - global_position).normalized()
		if rad_to_deg(acos(clampf(get_forward_vector().dot(to_target), -1.0, 1.0))) > melee_arc_angle:
			continue
		var damageable: Node = null
		if collider.has_method("apply_damage"):
			damageable = collider
		elif collider.get_parent() != null and collider.get_parent().has_method("apply_damage"):
			damageable = collider.get_parent()
		if damageable == null or _is_friendly(damageable):
			continue
		damageable.apply_damage(base_damage, shooter)

func get_forward_vector() -> Vector3:
	return muzzle_origin.global_transform.basis.x.normalized()

func play_shot_audio() -> void:
	if shot_audio != null:
		shot_audio.play()

func play_muzzle_flash() -> void:
	if muzzle_flash != null:
		muzzle_flash.play_flash()

## One tracer per shot, added to the world rather than parented to the
## weapon, travelling to the point the hitscan actually resolved to.
func fire_tracer_to(from: Vector3, to: Vector3) -> void:
	if tracer_scene == null:
		return
	var new_tracer = tracer_scene.instantiate()
	get_tree().current_scene.add_child(new_tracer)

	var end_point = to
	if tracer_jitter_degrees > 0.0:
		var dir = (to - from)
		var dist = dir.length()
		if dist > 0.01:
			dir = dir.normalized()
			var jy = deg_to_rad(randf_range(-tracer_jitter_degrees, tracer_jitter_degrees))
			var jz = deg_to_rad(randf_range(-tracer_jitter_degrees, tracer_jitter_degrees))
			var basis_j = Basis().rotated(Vector3.UP, jy).rotated(Vector3.FORWARD, jz)
			end_point = from + (basis_j * dir).normalized() * dist

	if new_tracer.has_method("launch"):
		new_tracer.launch(from, end_point)
	else:
		new_tracer.global_position = from
		new_tracer.direction = (end_point - from).normalized()
		new_tracer.look_at(from + new_tracer.direction, Vector3.UP)
