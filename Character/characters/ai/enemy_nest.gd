extends Soldier

# ─────────────────────────────────────────────
# NEST — an enemy building that makes more enemies.
#
# It is a Soldier so it travels the same road every other hostile does: a
# ChassisDefinition in a mission's EnemySquadSpec, spawned onto a post tag,
# counted by the eliminate objective, shot, downed, and ground up by a
# Reclaimer like anything else. It simply never moves and never shoots.
#
# WHAT IT DOES. Once the fight has started — it has seen something, or its
# squad has called contact — it opens its hatch every `hatch_seconds` and puts
# out ONE body, chosen by a dice roll from `hatchlings`. It stops at
# `max_alive` of its own, so a nest left alone is a slow bleed rather than an
# avalanche, and the cap is what makes leaving one standing a decision instead
# of a death sentence.
#
# WHAT COMES OUT IS NOT IN A SQUAD. Chasers and leapers rush whatever they can
# see; a squad node around them would only add formation orders they would
# immediately break. They are handed the nest's target so they set off towards
# the fight rather than standing on the hatch waiting to notice it.
# ─────────────────────────────────────────────

@export_group("Hatching")
## One entry per possible body. The roll is even across them, so listing the
## same frame twice weights it.
@export var hatchlings: Array[ChassisDefinition] = []
## Seconds between hatches, rolled fresh each time.
@export var hatch_min_seconds: float = 10.0
@export var hatch_max_seconds: float = 20.0
## How many of its own it will keep in the field at once.
@export var max_alive: int = 6
## Where they appear, measured out from the nest.
@export var hatch_radius: float = 2.6
## First hatch comes this long after the nest joins a fight, so a squad walking
## into view is not met by something in the same second.
@export var first_hatch_seconds: float = 4.0

@export_group("Parts")
## Turned while the nest is working, so a live one reads differently from a
## dead one at a distance.
@export var dish: Node3D
@export var dish_degrees_per_second: float = 40.0
## Fires that come up as it is shot apart. See _tick_burning.
@export var flames: Array[GPUParticles3D] = []
## The health fraction the first flames appear at. Above this it looks intact,
## which is the point: damage on a building has to be readable from a distance.
@export var burn_starts_at: float = 0.75
## Shown while a hatch is close, hidden otherwise.
@export var hatch_light: Node3D
@export var hatch_sound: AudioStreamPlayer3D

## What it has put into the field, for the playtest log and the mission report.
var hatched: int = 0

var _next_hatch := 0.0
var _mine: Array[Node] = []

signal hatched_body(body: Node3D)


func _ready() -> void:
	# A building has no business rolling advances and chases. It still enters
	# COMBAT — that is how it knows the fight has started — but every combat
	# option that moves or shoots is off it.
	AllowedMovementOptions.clear()
	AllowedCombatOptions.clear()
	if hatchlings.is_empty():
		push_warning("%s has no hatchlings listed, so it is an ordinary building with health." % name)
	super()
	_next_hatch = first_hatch_seconds


# Bolted down. The base drives velocity from the nav agent and the squad sends
# it places; neither should move a building.
func move_along_nav(_delta) -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func move_to(_pos: Vector3) -> void:
	pass   # a nest is where it was built


func order_move_to(_pos: Vector3, _force: bool = false, _keep_target: bool = false) -> void:
	pass   # the squad can want it elsewhere all it likes


func takes_cover() -> bool:
	return false


func enter_cover_seeking() -> void:
	change_soldier_state(SoldierState.NONE)


# IT IS A BUILDING. The base turns a robot's whole body to face what it is
# looking at, which on something bolted to the ground read as the bunker slowly
# swivelling to watch you — the only part of it that should move is the dish on
# the mast. Facing is dropped entirely rather than damped: there is nothing it
# needs to point at, because it has no weapon.
func _update_facing(_delta: float) -> void:
	pass


# THE FIRES GO OUT WITH IT. destroy() switches the physics tick off, so
# _tick_burning stops being called — and whatever the flames were doing on that
# last frame is what they kept doing, forever, on a dead hive. Put them out
# here rather than relying on a tick that is about to stop.
func destroy() -> void:
	_douse()
	super()


func _douse() -> void:
	for fire in flames:
		if fire != null and is_instance_valid(fire):
			fire.emitting = false


# Burning as it comes apart. Flames rather than a health bar: you can see from
# across the compound how far along a hive is, and a hive that has never been
# touched looks untouched.
func _tick_burning() -> void:
	if flames.is_empty() or max_health <= 0:
		return
	var left: float = clampf(float(health) / float(max_health), 0.0, 1.0)
	var burning: bool = alive and left < burn_starts_at
	# How far into the burn range it is: a trickle at the first threshold,
	# everything by the time it is nearly gone.
	var heat: float = 0.0
	if burning:
		heat = clampf((burn_starts_at - left) / maxf(burn_starts_at, 0.01), 0.0, 1.0)
	for fire in flames:
		if fire == null or not is_instance_valid(fire):
			continue
		if fire.emitting != burning:
			fire.emitting = burning
		if burning:
			fire.amount_ratio = lerpf(0.35, 1.0, heat)


func _physics_process(delta: float) -> void:
	super(delta)
	# Before the early returns: a dead or jammed hive still burns.
	_tick_burning()
	if not alive or not frame_waited or ai_state == AIState.PASSIVE \
			or get_signal_state() == SignalState.EKILL:
		return   # down, asleep or jammed: the hatch stays shut
	if dish != null:
		dish.rotate_y(deg_to_rad(dish_degrees_per_second) * delta)
	if not _fighting():
		return   # nothing has started yet: it sits there
	_next_hatch -= delta
	if hatch_light != null:
		hatch_light.visible = _next_hatch <= 2.0
	if _next_hatch > 0.0:
		return   # still counting down to the next one
	_next_hatch = randf_range(hatch_min_seconds, hatch_max_seconds)
	_hatch()


# The fight has started as far as this nest is concerned: it has a target of
# its own, or the squad it belongs to has called contact.
func _fighting() -> bool:
	if ai_state == AIState.COMBAT:
		return true
	if combat_target != null and is_instance_valid(combat_target) and combat_target.alive:
		return true
	return squad != null and is_instance_valid(squad) and squad.has_live_contact()


func _hatch() -> void:
	if hatchlings.is_empty():
		return   # warned about in _ready
	_forget_dead()
	if _mine.size() >= max_alive:
		return   # its share of the field is already out there
	var frame: ChassisDefinition = hatchlings[randi() % hatchlings.size()]
	if frame == null or frame.scene == null:
		push_warning("%s: a hatchling frame has no scene, so nothing came out." % name)
		return
	var body := frame.scene.instantiate() as Soldier
	if body == null:
		push_warning("%s: %s is not a Soldier scene." % [name, frame.display_name])
		return
	body.faction = faction
	body.always_active = always_active
	body.max_health = frame.base_health
	body.health = frame.base_health
	body.soldier_name = "%s-%d" % [frame.display_name.to_upper(), hatched + 1]
	get_parent().add_child(body)
	body.global_position = _hatch_spot()
	if ai_manager != null:
		ai_manager.register_enemy(body)
	# Pointed at what the nest is looking at, so it leaves the hatch heading
	# for the fight instead of waiting to see it for itself.
	var target = combat_target if combat_target != null and is_instance_valid(combat_target) else null
	if target == null and squad != null and is_instance_valid(squad):
		target = squad.squad_combat_target
	if target != null and is_instance_valid(target) and target.alive:
		body.trigger_combat(target)
	_mine.append(body)
	hatched += 1
	if hatch_sound != null:
		hatch_sound.play()
	hatched_body.emit(body)


# On the navmesh, out at hatch_radius, away from the last one: two bodies in
# the same spot shove each other across the map.
func _hatch_spot() -> Vector3:
	var angle := randf() * TAU
	var spot := global_position + Vector3(cos(angle), 0.0, sin(angle)) * hatch_radius
	if nav_agent != null:
		spot = NavigationServer3D.map_get_closest_point(nav_agent.get_navigation_map(), spot)
	return spot + Vector3.UP * 0.5


func _forget_dead() -> void:
	var live: Array[Node] = []
	for body in _mine:
		if body != null and is_instance_valid(body) and body.get("alive"):
			live.append(body)
	_mine = live
