extends Node3D
class_name AIWeapon

# Playtest analytics. By path: see the note in analytics.gd.
const _Analytics := preload("res://Managers/analytics.gd")

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

# Rounds per shot. 1 is a rifle; a shotgun is several, each carrying its share
# of base_damage and thrown wide by pellet_spread_mrad. The pattern is what
# makes a shotgun fall off with range, so there is no separate falloff to tune.
@export var pellets: int = 1
@export var pellet_spread_mrad: float = 0.0

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
## Rounds per committed burst, whoever carries it. 0 leaves it to the robot's
## own burst_min/burst_max — set it where the weapon has a rhythm of its own.
@export var burst_min: int = 0
@export var burst_max: int = 0
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
	# Before the hit resolves, so the log can pair the two (same physics frame).
	_Analytics.shot(_owner_body())

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


# Where what this weapon leaves behind goes: the level its carrier stands in.
# get_tree().current_scene is Master in the game — above World, so anything put
# there outlives the level — and in a headless test there is none, which is
# where every tracer failed with "add_child on a null value".
func _level_node() -> Node:
	var shooter := _owner_body()
	if shooter != null and shooter.get_parent() != null:
		return shooter.get_parent()
	if get_tree().current_scene != null:
		return get_tree().current_scene
	return get_tree().root


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


# A SHOT MAY BE MORE THAN ONE ROUND.
#
# A shotgun firing a single ray for its whole damage is a slow rifle: it either
# lands all 45 or none of it, and at range it behaves exactly like every other
# hitscan. Pellets give it the shape it should have had — everything lands in
# your face, half of it lands across a room, almost none of it lands at forty
# metres — without a range table, because the pattern does it.
#
# `base_damage` stays the damage of a WHOLE shell; each pellet carries its
# share, so retuning the weapon is still one number.
func check_damage(weapon_target: Vector3) -> void:
	var count: int = maxi(pellets, 1)
	var from: Vector3 = muzzle_origin.global_position
	var centre := (weapon_target - from).normalized()
	var shooter = _owner_body()
	var exclusion: Array[RID] = []
	if shooter is CollisionObject3D:
		exclusion.append((shooter as CollisionObject3D).get_rid())

	# Split so the parts add up to the whole: the remainder rides on the first
	# pellet rather than being rounded away.
	var each: int = int(floor(float(base_damage) / float(count)))
	var spare: int = base_damage - each * count

	var centre_impact := from + centre * max_effective_range
	for i in count:
		var dir := centre
		if count > 1 and pellet_spread_mrad > 0.0:
			dir = scatter(centre, pellet_spread_mrad)
		var impact := _one_round(from, dir, exclusion, shooter, each + (spare if i == 0 else 0))
		if i == 0:
			centre_impact = impact

	# One tracer for the shot, down the middle of the pattern.
	fire_tracer_to(from, centre_impact)

	if suppression_per_shot > 0.0:
		_apply_near_miss_suppression(centre_impact)


# One round down one line. Returns where it stopped.
func _one_round(from: Vector3, direction: Vector3, exclusion: Array[RID],
		shooter, share: int) -> Vector3:
	var space_state = get_world_3d().direct_space_state
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
		# calculate_damage works off base_damage, so scale its falloff onto this
		# round's share of the shell.
		var full: float = maxf(float(base_damage), 1.0)
		var dealt: int = maxi(1, int(round(calculate_damage(hit_dist) * float(share) / full)))
		if _is_friendly(hit_body):
			dealt = maxi(1, int(round(float(dealt) * friendly_fire_multiplier)))
			friendly_hit.emit(hit_body)
		hit_body.apply_damage(dealt, shooter)
	return impact


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
				body.receive_signal_damage(suppression_amount, shooter)
			else:
				body.signal_integrity = maxf(0.0, body.signal_integrity - suppression_amount)

# A SWING GOES WHERE IT IS LOOKING, not down the weapon node's own X axis.
#
# The sphere used to be placed at `global_position + basis.x * melee_range`.
# That axis is whatever rotation the weapon was given in its scene, and the
# chaser's is yawed ninety degrees — so the swing landed a metre and a half to
# the SIDE of whatever it was attacking, and a metre above it, because the
# weapon is mounted high on the body. A chaser could stand on your feet, in
# COMBAT, cycling its attack, and never once touch you.
#
# Aimed at the target instead, so the sphere is always on the line between the
# two. The arc is still measured against the BODY's facing, which is what stops
# it hitting something behind it.
func check_melee_damage() -> void:
	var space_state = get_world_3d().direct_space_state
	var shooter = _owner_body()
	var swing := _melee_direction(shooter)
	_melee_shape.radius = melee_radius
	_melee_query.transform = Transform3D(Basis(), global_position + swing * melee_range)
	_melee_query.collision_mask = character_mask
	var exclusion: Array[RID] = []
	if shooter is CollisionObject3D:
		exclusion.append((shooter as CollisionObject3D).get_rid())
	_melee_query.exclude = exclusion
	var facing := swing
	if shooter is Node3D:
		var nose: Vector3 = -(shooter as Node3D).global_transform.basis.z
		if nose.length_squared() > 0.0001:
			facing = nose.normalized()

	var results = space_state.intersect_shape(_melee_query, 16)
	for result in results:
		var collider = result.collider
		# ON THE FLAT. The arc says "is this in front of me", and a weapon mounted
		# high on a chaser looks DOWN at something standing next to it — that tilt
		# alone was most of the sixty degrees, so a target dead ahead measured 63
		# and was thrown away. Height is the sphere's business, not the arc's.
		var to_target := _flat(collider.global_position - global_position)
		var flat_facing := _flat(facing)
		if to_target == Vector3.ZERO or flat_facing == Vector3.ZERO:
			continue
		if rad_to_deg(acos(clampf(flat_facing.dot(to_target), -1.0, 1.0))) > melee_arc_angle:
			continue
		var damageable: Node = null
		if collider.has_method("apply_damage"):
			damageable = collider
		elif collider.get_parent() != null and collider.get_parent().has_method("apply_damage"):
			damageable = collider.get_parent()
		if damageable == null or _is_friendly(damageable):
			continue
		damageable.apply_damage(base_damage, shooter)

# Where a swing is aimed: at what the owner is fighting, or at whatever it was
# last told to shoot at. Falls back to the weapon's own axis when it has
# neither, which is the old behaviour and fine for a swing at nothing.
func _melee_direction(shooter: Node) -> Vector3:
	var aim_points: Array = []
	if shooter != null and is_instance_valid(shooter):
		var target = shooter.get("combat_target")
		if target != null and is_instance_valid(target) and target is Node3D:
			aim_points.append((target as Node3D).global_position)
		var spot = shooter.get("weapon_target")
		if spot is Vector3 and (spot as Vector3) != Vector3.ZERO:
			aim_points.append(spot)
	for point in aim_points:
		var to: Vector3 = (point as Vector3) - global_position
		if to.length_squared() > 0.0001:
			return to.normalized()
	return get_forward_vector()


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
	_level_node().add_child(new_tracer)

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


# One pellet's line, thrown off `centre` by up to `mrad` milliradians on each
# of the two axes across the line. Static, and the player's own shotgun calls
# it too — a pattern that differs depending on who pulled the trigger is a bug
# waiting to be argued about.
static func scatter(centre: Vector3, mrad: float) -> Vector3:
	var spread := mrad / 1000.0
	var side := centre.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = centre.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(centre).normalized()
	return (centre + side * randf_range(-spread, spread)
		+ up * randf_range(-spread, spread)).normalized()


# Horizontal only, for arc tests between bodies standing on the same ground.
static func _flat(v: Vector3) -> Vector3:
	var out := Vector3(v.x, 0.0, v.z)
	return out.normalized() if out.length_squared() > 0.0001 else Vector3.ZERO
