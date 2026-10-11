extends SpotterDrone
class_name BroodCarrier

# ─────────────────────────────────────────────
# BROODCARRIER — the Nest with the "walk over and break it" counter removed.
#
# WHAT IT IS FOR. Everything hostile in the game today punishes bad
# positioning. This punishes being slow. It is the Nest's producer loop under
# the Spotter's flight model: it keeps putting bodies out and it keeps
# relocating, so the answer stops being "go there eventually" and becomes
# "stop it now, while it is still in reach".
#
# EXTENDS, DOES NOT COPY. spotter_drone.gd is the third home of the flight
# helpers and extracting them is a real refactor — but it is a SEPARATE
# refactor, not a precondition for this frame. Extending costs nothing today
# and gets all of the Spotter's opt-outs for free: no weapon, no combat dice,
# no cover, its own slot tolerance and formation width, and crash-on-EMP.
# `bulwark.gd extends Walker` is the precedent.
#
# WHAT MAKES IT A UNIT RATHER THAN WEATHER, and both halves are mandatory:
#
#   * THE PODS VISIBLY EMPTY. build_brood.gd:41-48 named and ordered nine
#     siblings lowest-first specifically so a script could hide them one at a
#     time. A spawner whose remaining stock the player cannot read is a
#     spawner the player cannot make a decision about.
#   * THE STOCK IS FINITE. The Nest's max_alive is a CONCURRENCY cap with
#     unlimited lifetime output, which is right for a building you are
#     expected to go and break. For a thing that flies away from you,
#     unlimited total output means the fight has no end state the player can
#     produce. Nine pods, nine bodies, ever. So the sentence a tester can say
#     back is "there are six left, it is over there, go".
#
# `total_pods` and `release_min/max_seconds` are GAME FEEL and the human owns
# them — see docs/integration/BROODCARRIER.md §8.
#
# ─────────────────────────────────────────────
# BOTH Allowed*Options ARRAYS ON brood.tscn ARE EMPTY ON PURPOSE. DO NOT
# "FIX" THEM.
#
# This is the one frame in the batch for which empty is the right answer, and
# it needs saying because on the Bastion and the See-Engine the same empty
# arrays were a live defect — so the obvious sweep is to fill all three.
#
# The reason: roll_combat_action returns immediately on an empty combat array
# (enemy.gd:3053-3054), but on THIS frame that return is unreachable anyway.
# SpotterDrone gates both roll_combat_action and handle_weapon_logic behind
# _carries_a_weapon(), which is false here, so the combat dice is never rolled
# whatever the arrays contain. Filling them would be dead data that reads as
# live.
#
# IT STILL MOVES: movement comes from SpotterDrone.handle_movement, which
# replaces navigation entirely and orbits a station set by move_to from squad
# orders. The arrays were also MISTYPED as Array[ai_equipment_slot] by the
# generator; that half was a real bug and is fixed.
# ─────────────────────────────────────────────

# _CsgBake is inherited from Enemy (enemy.gd:1337) — declaring it again here
# is a parse error, not a shadow.
const _HOPPER := "res://Campaign/chassis/chassis_hopper.tres"

@export_group("Brood")
## One entry per possible body, same shape as EnemyNest.hatchlings. The roll is
## even across them, so listing the same frame twice weights it.
##
## TYPED, AND IT HAS TO BE. A plain Array here packs as `[]` in the .tscn in
## silence — see docs/briefs/FRAME_ANATOMY.md §6.6. Left empty it is filled
## from _HOPPER in _ready rather than the frame being a flying brick, and that
## fallback warns.
@export var brood: Array[ChassisDefinition] = []
## Seconds between releases, rolled fresh each time.
@export var release_min_seconds: float = 7.0
@export var release_max_seconds: float = 12.0
## How many of its own it keeps in the field at once.
@export var max_alive: int = 4
## LIFETIME cap, and the difference between this frame and the Nest. Nine,
## because there are nine pods and the bay is the readout.
@export var total_pods: int = 9
## First release comes this long after it joins a fight, so a squad walking
## into view is not met by something in the same second.
@export var first_release_seconds: float = 4.0
## Rig/BroodBay. Resolved in _ready if left null — a NodePath assigned to a
## typed Node3D export silently does nothing, so this is never authored.
@export var bay: Node3D

## What it has put into the field, for the playtest log and the mission report.
var released: int = 0

var _next_release: float = 0.0
var _mine: Array[Node] = []

signal released_body(body: Node3D)


func _ready() -> void:
	super()
	if bay == null:
		bay = get_node_or_null("Rig/BroodBay") as Node3D
	if bay == null:
		push_warning("%s has no Rig/BroodBay, so the pods will never empty and the player has no clock to read." % name)
	if brood.is_empty():
		var frame := load(_HOPPER) as ChassisDefinition
		if frame != null:
			brood.append(frame)
		else:
			push_warning("%s has no brood listed and %s would not load, so it is an expensive flying hull." % [name, _HOPPER])
	_next_release = first_release_seconds


# ─────────────────────────────────────────────
# THE PRODUCER LOOP
# ─────────────────────────────────────────────
# Shaped on EnemyNest._physics_process (153-170): the tick runs AFTER super()
# and behind the same four gates.
#
# A CULLED BROODCARRIER PRODUCES NOTHING, AND THAT IS CORRECT. The distance
# cull switches _physics_process off entirely (ai_manager.gd:576-593), so a
# frozen carrier stops releasing until the player is near enough to see it
# again. Stated here because the mechanism is invisible and somebody will
# otherwise "fix" it by moving the loop somewhere that still ticks.
func _physics_process(delta: float) -> void:
	super(delta)
	if not alive or not frame_waited or ai_state == AIState.PASSIVE \
			or get_signal_state() == SignalState.EKILL:
		return   # down, asleep or jammed: the bay stays shut
	if released >= total_pods:
		return   # empty. The whole point of the frame — see the header
	if not _fighting():
		return   # nothing has started yet: it loiters with a full bay
	_next_release -= delta
	if _next_release > 0.0:
		return
	_next_release = randf_range(release_min_seconds, release_max_seconds)
	_hatch()


# The fight has started as far as this carrier is concerned: it has a target of
# its own, or the squad it belongs to has called contact. EnemyNest._fighting
# (177-183). WITHOUT THIS GATE the carrier empties its whole bay into an empty
# map before the squad ever arrives, and the frame is over before it is seen.
func _fighting() -> bool:
	if ai_state == AIState.COMBAT:
		return true
	if combat_target != null and is_instance_valid(combat_target) and combat_target.alive:
		return true
	return squad != null and is_instance_valid(squad) and squad.has_live_contact()


# EnemyNest._hatch (184-227) with four changes, and everything else kept:
# the lifetime check, the pod depleting before the body is visible, the release
# point being under the hull rather than on the navmesh, and the chassis_id
# meta the Nest never sets.
#
# NONE OF THE REST IS OPTIONAL. This function does the spawner's whole job by
# hand and skipping any one line of it is silent: the Soldier cast, the
# faction, always_active, health off the frame, a name, add_child BEFORE the
# position, the AIManager registration, and handing the newborn its parent's
# target so it leaves heading for the fight instead of hovering underneath
# waiting to notice one.
func _hatch() -> void:
	if brood.is_empty():
		return   # warned about in _ready
	_forget_dead()
	if _mine.size() >= max_alive:
		return   # its share of the field is already out there
	var frame: ChassisDefinition = brood[randi() % brood.size()]
	if frame == null or frame.scene == null:
		push_warning("%s: a brood frame has no scene, so nothing came out." % name)
		return
	var body := _CsgBake.make(frame.scene) as Soldier
	if body == null:
		push_warning("%s: %s is not a Soldier scene." % [name, frame.display_name])
		return

	# FACTION INHERITANCE, AND IT IS NOT THE LINE THAT IS HARD.
	#
	# `body.faction = faction` is the whole of it, and the trap is that
	# hardcoding `Enums.Factions.SWARM` — or worse, ENEMY — would look correct
	# in review and spawn the wrong side. Two things make it subtle:
	#
	#   * IT MUST HAPPEN BEFORE add_child. AI._ready() runs initialize() and
	#     reads this field; set it afterwards and the body initialises as
	#     whatever the scene shipped (faction = 1) and then has the field
	#     changed underneath everything initialize() derived from it.
	#     enemy_force_spawner.gd:269 carries the same comment.
	#   * THE BUG LOOKS RIGHT AND THE FIX LOOKS BROKEN. FactionLivery.apply is
	#     what repaints the body, so a wrongly-factioned offspring is also the
	#     wrong colour — and before faction_livery.gd's COLORS gained its SWARM
	#     entry, a CORRECT Swarm offspring rendered grey and a WRONG enemy one
	#     rendered amber. Both entries exist now; this note is here so nobody
	#     reverses the line on the strength of a screenshot.
	body.faction = faction
	body.always_active = always_active
	body.max_health = frame.base_health
	body.health = frame.base_health
	body.soldier_name = "%s-%d" % [frame.display_name.to_upper(), released + 1]

	# COUNTED WITHOUT A KillKinds.SCENES ENTRY. The Nest never sets this, which
	# is exactly why kill_kinds.gd:47 has to carry "enemy_nest-chaser":
	# &"leaper" — a hatchling is otherwise identified by its scene basename.
	# KillKinds.kind_of checks the meta first (66-67), so one line here means
	# the brood tallies as its real frame and no shared registry needs editing.
	body.set_meta(&"chassis_id", frame.id)

	# THE POD GOES BEFORE THE BODY DOES, so the pod the offspring came out of
	# is already gone by the time the offspring is on screen.
	_deplete_bay(released + 1)

	get_parent().add_child(body)
	body.global_position = _release_point()
	if ai_manager != null:
		ai_manager.register_enemy(body)
	var target = combat_target if combat_target != null and is_instance_valid(combat_target) else null
	if target == null and squad != null and is_instance_valid(squad):
		target = squad.squad_combat_target
	if target != null and is_instance_valid(target) and target.alive:
		body.trigger_combat(target)
	_mine.append(body)
	released += 1
	released_body.emit(body)


# UNDER THE HULL, NOT ON THE NAVMESH. EnemyNest._hatch_spot snaps to
# NavigationServer3D.map_get_closest_point, which is right for a building
# standing on the ground and wrong for something at cruise_height — snapping a
# release at 12 m altitude teleports the body to the nearest navmesh point,
# which from above a building is the wrong side of a wall.
#
# The offspring are ground frames, so they are DROPPED: released just under the
# belly and handed to Enemy.handle_gravity, which is already running on them.
# Spread around the hull rather than stacked, because two bodies in one spot
# shove each other across the map.
func _release_point() -> Vector3:
	var angle: float = randf() * TAU
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * 1.4 + Vector3.DOWN * 1.2


# Counting UP from Pod1, which build_brood.gd:41-48 ordered lowest-first for
# this and modelled already open. Hiding rather than freeing: queue_free is
# deferred and this runs inside a physics tick.
func _deplete_bay(n: int) -> void:
	if bay == null:
		return
	var pod := bay.get_node_or_null("Pod%d" % n) as Node3D
	if pod == null:
		push_warning("%s: no Rig/BroodBay/Pod%d, so the bay cannot show it is emptying." % [name, n])
		return
	pod.visible = false


func _forget_dead() -> void:
	var live: Array[Node] = []
	for body in _mine:
		if body != null and is_instance_valid(body) and body.get("alive"):
			live.append(body)
	_mine = live


## How many bodies it can still produce. For the HUD, the debrief and the test.
func pods_left() -> int:
	return maxi(total_pods - released, 0)
