extends Walker
class_name Bastion

# ─────────────────────────────────────────────
# BASTION — "this ground is now expensive".
#
# WHAT IT IS FOR. Everything hostile today is either a threat you shoot or an
# objective you break. A Bastion makes the squad standing around it measurably
# harder to suppress, so "deal with the support unit first" becomes a real
# decision — one the game cannot currently ask. Home Command's doctrine on
# screen: Swarm is numbers, Argus is intelligence, Home Command is POSITION.
#
# It walks to a position, PLANTS, and makes everything of its own side inside
# its canopy hard to suppress.
#
# ─────────────────────────────────────────────
# TWO THINGS MAKE IT LEGIBLE AND BOTH ARE MANDATORY, NOT POLISH.
#
#   1. THE PLANTED STATE IS UNMISTAKABLE FROM ANY BEARING — outriggers driven,
#      skirts out, canopy lit. build_bastion.gd:94-98 chose four-fold symmetry
#      over three for exactly this. _set_stance_pose below is the switch.
#   2. THE PLAYER CAN SEE THEIR SUPPRESSION NOT LANDING. The effect is a RATE,
#      not an event — signal_resistance is read in exactly two places
#      (ai.gd's receive_signal_damage and lock_signal) and both are divisions.
#      A suppressed robot inside the canopy should drop one signal state band
#      instead of two. THAT CANNOT BE ASSERTED and it is the whole unit; it is
#      a human review item, see docs/integration/BASTION.md §7 step 6.
#
# ─────────────────────────────────────────────
# THE FIELD IS A STAMP, NOT A MUTATION — and the mechanism is in ai.gd.
#
# AI.add_hardening / AI.effective_signal_resistance carry the whole argument.
# The short version: mutate-on-entry / divide-on-exit leaves a robot
# permanently hardened whenever two projectors overlap, or one dies
# mid-effect, or either end is frozen by the distance cull (which switches
# _physics_process off outright). An expiry is the only version that is
# correct when either end stops ticking.
#
# A CULLED BASTION STOPS PROJECTING, AND THAT IS CORRECT. The stamps lapse
# within a second. Invisible mechanism, stated so nobody "fixes" it.
# ─────────────────────────────────────────────

enum Stance { WALKING, PLANTING, PLANTED, UNPLANTING }

@export_group("Plant")
## The animation, both ways.
@export var plant_seconds: float = 1.6
## move_speed while WALKING. The .tscn ships move_speed = 0.0 because the frame
## is BORN PLANTED — scene values beat script defaults, and that one is right.
@export var walk_speed: float = 2.4
## The fight moved further than this, so get up and follow it.
@export var unplant_range: float = 70.0

@export_group("Field")
## Matches the canopy hoop's own geometry. A HARD EDGE, no falloff in the first
## pass: an edge at 14 m is easier to read, easier to test and matches the thing
## the player is looking at. Add falloff only if the human says it feels wrong.
@export var field_radius: float = 14.0
## ADDITIVE. Base signal_resistance is 1.0 (ai.gd), so +0.6 is the design
## doc's "around 1.6x" on a stock frame, and it composes correctly with a
## module's signal_resistance_bonus instead of multiplying with it.
@export var field_bonus: float = 0.6
## Seconds between stamps. NOT every frame: MEMORY.md records mines as the
## single most expensive thing in the game (68 ms of 128 ms of script time),
## partly on group sweeps of exactly this shape.
@export var field_interval: float = 0.4

var stance: int = Stance.PLANTED

var _field_timer: float = 0.0
var _plant_tween: Tween = null
## 1.0 = fully planted, 0.0 = fully stowed. One driven float rather than three
## tweens, so there is a single thing to interrupt and a single thing to read.
var _planted_amount: float = 1.0

# The PLANTED pose, captured off the scene in _ready rather than hardcoded.
# build_bastion.gd's PLANT_LEAN / MAST_RAKE / SKIRT_CANT are 28/20/8 degrees,
# but each outrigger sits under its own yawed container, so reading the rest
# pose off the nodes is both shorter and immune to the generator being retuned.
var _rams: Array[Node3D] = []
var _ram_rest: Array[Vector3] = []
var _jacks: Array[Node3D] = []
var _jack_rest: Array[Vector3] = []
var _jack_stowed: Array[Vector3] = []
var _mast: Node3D = null
var _mast_rest: Vector3 = Vector3.ZERO
var _canopy: Node3D = null
var _canopy_rest: Vector3 = Vector3.ZERO
var _skirts: Array[Node3D] = []
var _skirt_rest: Array[Vector3] = []
var _lenses: Array[MeshInstance3D] = []
## Duplicated off Lens0's override. RESOURCES ARE SHARED: one sub-resource
## backs all four lenses AND every instance of this scene, so writing emission
## onto it directly would light the canopy of every Bastion on the map,
# including the dead ones.
var _lens_material: StandardMaterial3D = null
var _lens_energy: float = 2.6

## Where the mast lies when stowed: flat on the back deck, fore-and-aft.
const MAST_STOWED_X := -PI * 0.5
## Each apron swung up against the flank.
const SKIRT_STOWED := 80.0


func _ready() -> void:
	super()
	_collect_plant_nodes()
	# The scene IS the planted state, so the frame is born planted and
	# move_speed is already 0.0. Nothing to pose.
	stance = Stance.PLANTED
	_planted_amount = 1.0


func _collect_plant_nodes() -> void:
	for side in ["F", "A", "L", "R"]:
		var ram := get_node_or_null("Rig/Outriggers/Outrigger%s/Ram" % side) as Node3D
		if ram == null:
			push_warning("%s: no Rig/Outriggers/Outrigger%s/Ram, so that leg will not stow." % [name, side])
			continue
		_rams.append(ram)
		_ram_rest.append(ram.rotation)
		var jack := ram.get_node_or_null("Jack") as Node3D
		var gland := ram.get_node_or_null("Gland") as Node3D
		if jack != null and gland != null:
			# The Jack retracts INTO the Beam's Gland. It is a separate node for
			# exactly that, per build_bastion.gd:109-135.
			_jacks.append(jack)
			_jack_rest.append(jack.position)
			_jack_stowed.append(gland.position)

	_mast = get_node_or_null("Rig/Mast") as Node3D
	if _mast != null:
		_mast_rest = _mast.rotation
	else:
		push_warning("%s: no Rig/Mast, so the column will never lie down." % name)
	# COUNTER-ROTATES TO KEEP THE HOOP LEVEL. A stow has to drive both or the
	# hoop ends up on edge — build_bastion.gd says so in as many words.
	_canopy = get_node_or_null("Rig/Mast/Canopy") as Node3D
	if _canopy != null:
		_canopy_rest = _canopy.rotation

	for side in ["L", "R"]:
		var skirt := get_node_or_null("Rig/Skirts/Skirt%s" % side) as Node3D
		if skirt == null:
			continue
		_skirts.append(skirt)
		_skirt_rest.append(skirt.rotation)
	# Rig/Skirts/Bracket{L,R} are HULL and must not move. They hang off the
	# container rather than the hinges precisely so this loop cannot catch them.

	for i in 4:
		var lens := get_node_or_null("Rig/Mast/Canopy/Lenses/Lens%d" % i) as MeshInstance3D
		if lens == null:
			continue
		_lenses.append(lens)
	if not _lenses.is_empty():
		var base := _lenses[0].material_override as StandardMaterial3D
		if base != null:
			_lens_material = base.duplicate()
			_lens_energy = base.emission_energy_multiplier
			for lens in _lenses:
				lens.material_override = _lens_material


# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	super(delta)
	_tick_plant(delta)
	_tick_field(delta)


# ─────────────────────────────────────────────
# PLANT / UNPLANT, AS A STATE
# ─────────────────────────────────────────────
# PLANT ON FIRST CONTACT, UNPLANT IF THE FIGHT MOVES BEYOND unplant_range. The
# planting itself is hooked to trigger_combat rather than polled; this tick
# only watches for the fight walking away.
func _tick_plant(_delta: float) -> void:
	if stance != Stance.PLANTED:
		return
	var target = combat_target if combat_target != null and is_instance_valid(combat_target) else null
	if target == null and squad != null and is_instance_valid(squad):
		target = squad.squad_combat_target
	if target == null or not is_instance_valid(target) or not (target is Node3D):
		return   # nothing to measure against: stay down rather than fidget
	if global_position.distance_to((target as Node3D).global_position) > unplant_range:
		_begin_unplant()


# super() FIRST — soldier.gd:320 overrides this and the base work has to happen
# whatever the stance.
func trigger_combat(body: AI) -> void:
	super(body)
	if stance == Stance.WALKING:
		_begin_plant()


func _begin_plant() -> void:
	if stance == Stance.PLANTING or stance == Stance.PLANTED:
		return
	stance = Stance.PLANTING
	move_speed = 0.0            # it stops before the outriggers go in
	_drive_stance(1.0, Stance.PLANTED)


func _begin_unplant() -> void:
	if stance == Stance.UNPLANTING or stance == Stance.WALKING:
		return
	stance = Stance.UNPLANTING
	move_speed = 0.0            # still pinned until the jacks are off the soil
	_set_lens_energy(0.0)       # the field dies at the START of getting up
	_drive_stance(0.0, Stance.WALKING)


# A TWEEN CHAIN, NOT A COROUTINE. MEMORY.md: await-on-process_frame at quit
# segfaults in cleanup. One tween on one float, so there is exactly one thing
# to kill in die().
func _drive_stance(to: float, becomes: int) -> void:
	if _plant_tween != null and _plant_tween.is_valid():
		_plant_tween.kill()
	_plant_tween = create_tween()
	var span: float = plant_seconds * absf(to - _planted_amount)
	_plant_tween.tween_method(_set_stance_pose, _planted_amount, to, maxf(span, 0.05)) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_plant_tween.tween_callback(func() -> void:
		stance = becomes
		if becomes == Stance.WALKING:
			move_speed = walk_speed
		else:
			move_speed = 0.0
			_set_lens_energy(_lens_energy))


## 1.0 = the pose the scene shipped; 0.0 = stowed. Writes absolutely, the same
## way walker.gd's _pose_leg does, so an interrupted transition resumes from
## wherever it actually is rather than from where it thought it was.
func _set_stance_pose(amount: float) -> void:
	_planted_amount = amount
	for i in _rams.size():
		_rams[i].rotation = _ram_rest[i] * amount
	for i in _jacks.size():
		_jacks[i].position = _jack_stowed[i].lerp(_jack_rest[i], amount)
	if _mast != null:
		_mast.rotation = Vector3(
			lerpf(MAST_STOWED_X, _mast_rest.x, amount), _mast_rest.y, _mast_rest.z)
	if _canopy != null:
		# Counter-rotation, so the hoop stays level all the way down.
		_canopy.rotation = Vector3(
			lerpf(-MAST_STOWED_X, _canopy_rest.x, amount), _canopy_rest.y, _canopy_rest.z)
	for i in _skirts.size():
		# rotation.z from +-SKIRT_CANT to about -+80 deg: the sign of the stowed
		# angle is the OPPOSITE of the planted cant, which is why it is read off
		# the rest pose rather than written per side.
		var cant: float = _skirt_rest[i].z
		var stowed: float = -signf(cant) * deg_to_rad(SKIRT_STOWED)
		_skirts[i].rotation = Vector3(_skirt_rest[i].x, _skirt_rest[i].y,
			lerpf(stowed, cant, amount))


func _set_lens_energy(e: float) -> void:
	if _lens_material != null:
		_lens_material.emission_energy_multiplier = e


# ─────────────────────────────────────────────
# ORDERS, REFUSED WHILE PLANTED
# ─────────────────────────────────────────────
# Without these a planted hardpoint is walked off its position by its own squad
# with its outriggers in the ground. enemy_nest.gd:91/95 and
# enemy_watcher.gd:76 are the two shipped frames that refuse orders.
#
# BELT AND BRACES, and both are needed: perform_action(MOVE) reaches move_to
# directly (enemy.gd:3938-3946) without passing through order_move_to. The
# combat dice cannot pick MOVE on this frame — AllowedCombatOptions is [1, 2]
# on the scene for that reason — but a squad order is a different road in.
#
# NO WARNING HERE, deliberately, against CLAUDE.md's "every early return
# warns": a squad re-issues a follow order every few seconds for the whole
# mission, so warning would be thousands of lines of log saying the frame is
# working. The reason lives in this comment instead.
func move_to(pos: Vector3, think_delay: float = 0.0):
	if stance != Stance.WALKING:
		return
	super(pos, think_delay)


func order_move_to(pos: Vector3, force: bool = false, keep_target: bool = false,
		think_delay: float = 0.0) -> void:
	if stance != Stance.WALKING:
		return
	super(pos, force, keep_target, think_delay)


# Belt-and-braces with the inherited takes_cover() = false (walker.gd:251),
# which is already correct: Squad splits its members on it and false means
# "parks on the spot" rather than "is sent to a cover point".
func enter_cover_seeking() -> void:
	change_soldier_state(SoldierState.NONE)


# ─────────────────────────────────────────────
# THE RESISTANCE FIELD
# ─────────────────────────────────────────────
func _tick_field(delta: float) -> void:
	if stance != Stance.PLANTED or not alive or downed \
			or get_signal_state() == SignalState.EKILL:
		return
	_field_timer -= delta
	if _field_timer > 0.0:
		return
	_field_timer = field_interval
	var r_sq: float = field_radius * field_radius
	# AI.SIGNAL_GROUP, NOT "enemies". ai.gd joins it in AI._ready for everything
	# with a signal_integrity, robots and the player alike — "enemies" does not
	# contain the player, which is the bug that moved EMP onto this group.
	for n in get_tree().get_nodes_in_group(AI.SIGNAL_GROUP):
		if n == self or not (n is AI):
			continue
		# ALLY MEANS SAME FACTION, NOT "NOT HOSTILE".
		# are_hostile(HOME, SWARM) is FALSE by design — the three enemy
		# factions are deliberately not hostile to each other, because mutual
		# hostility would make them each other's activation sources and the
		# distance cull would stop culling. So a "not hostile" filter here
		# would harden every Swarm and Argus unit in the radius, and every
		# NEUTRAL. Nothing would warn, and the symptom is a Bastion making
		# somebody else's army tougher.
		if not ("faction" in n) or n.faction != faction:
			continue
		if global_position.distance_squared_to((n as Node3D).global_position) > r_sq:
			continue
		# The expiry is comfortably longer than the gap between stamps, so
		# there is no flicker, and short enough that the effect is gone within
		# a second of this frame dying, being culled, or the neighbour walking
		# out of the canopy.
		(n as AI).add_hardening(field_bonus, field_interval * 2.5)


# ─────────────────────────────────────────────
# DEATH
# ─────────────────────────────────────────────
# THE TWEEN MUST NOT OUTLIVE THE FRAME. A Bastion killed mid-transition would
# otherwise leave a tween driving nodes under a freed body — MEMORY.md records
# that class of thing as a segfault in cleanup, not a cosmetic bug.
#
# The stamps need no undoing: they expire on their own, which is the whole
# reason the field is a stamp. But the VISUAL has to go out here, or a dead
# Bastion still stands there with a lit canopy looking like it is projecting.
func die() -> void:
	_stop_projecting()
	super()


func enter_downed() -> void:
	_stop_projecting()
	super()


func _stop_projecting() -> void:
	if _plant_tween != null and _plant_tween.is_valid():
		_plant_tween.kill()
	_plant_tween = null
	_set_lens_energy(0.0)
