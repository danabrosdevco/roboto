extends Node3D
class_name AIEquipment

# ─────────────────────────────────────────────
# AI EQUIPMENT — base class
# Extend this for each equipment type.
# Instantiated at use-time by Enemy, then freed.
#
# Subclasses override:
#   can_use(context: EquipmentContext) -> bool
#   execute(context: EquipmentContext) -> void
# ─────────────────────────────────────────────

# Context passed in when checking/using equipment.
# Contains everything the equipment needs to make a decision.
#
# IT USED TO DESCRIBE A FIREFIGHT AND NOTHING ELSE, which was fine while the
# only equipment was a grenade. It is not fine for the rest of the kit: smoke
# exists to STOP a firefight, mines are laid before contact or while breaking
# it, and a drone pack answers a target you cannot currently engage. A context
# that only knows who you are shooting can never justify any of those, and
# `Enemy._evaluate_equipment_use` additionally refused to run at all without a
# combat target — so EMP and Hatchling, which are the grenade scene with a
# different payload, could only ever be thrown under exactly a grenade's
# conditions.
#
# The fields below the line are what the rest of the kit needs. They are filled
# in by Enemy on every evaluation; an equipment that does not care about one
# simply does not read it.
class EquipmentContext:
	var owner_ai: Enemy           # the enemy using this equipment
	var combat_target: CharacterBody3D
	var target_position: Vector3
	var nearby_hostiles: Array     # hostiles within a radius OF THE OWNER
	var time_since_target_moved: float  # how long target has been stationary
	var owner_is_reloading: bool

	# ── beyond the firefight ──────────────────
	## The squad's current order, as Squad.SquadObjective. NONE when the robot
	## is in no squad, which is also what an enemy garrison robot reports.
	var squad_objective: int = 0
	## Seconds since this robot was last hit. NEVER_HIT until something lands,
	## so "am I under fire" is `under_fire_seconds < 2.0` rather than a flag
	## somebody has to remember to clear.
	var under_fire_seconds: float = NEVER_HIT
	## The nearest squadmate on the floor, or null. What smoke is for.
	var downed_friendly: Node3D = null
	## Unit vector from the robot toward what is threatening it — its target if
	## it has one, otherwise the nearest hostile. ZERO when nothing is known,
	## which means "do not place anything directional".
	var threat_bearing: Vector3 = Vector3.ZERO
	## Where that bearing points, as a world point. Smoke and mines both need
	## the DISTANCE and not just the direction — a cloud goes most of the way to
	## the threat, a mine goes on the approach — and recomputing it from the
	## manager in each of them would ask the same question three times a tick.
	##
	## `threat_bearing` is the flag for "nothing known", not this: Vector3.ZERO
	## is a legal map position, so read this only when the bearing is non-zero.
	var threat_position: Vector3 = Vector3.ZERO
	## WHO that is, when it is a body and not a remembered position. Carried
	## because a sight test toward a robot has to EXCLUDE that robot: a ray cast
	## at something's own position terminates inside its collider, so
	## `is_path_clear(me, them)` without this comes back blocked every single
	## time and "can they see me" always answers no. enemy.gd's own LOS check
	## passes combat_target for exactly this reason (see `_update_los`).
	##
	## Null is normal and is not the same as no threat: a robot being shot at
	## from cover it cannot see has a bearing and no actor.
	var threat_actor: Node3D = null
	## Hostiles clustered around the TARGET rather than around the owner. The
	## two are different questions and `nearby_hostiles` only answers the second
	## — a robot deciding whether a throw is worth it cares about what is
	## standing where it would land.
	var hostiles_near_target: Array = []
	## Time.get_ticks_msec() when ANY member of this squad last spent a piece of
	## equipment. Without it a squad answers one situation with four canisters
	## on the same frame.
	var squad_last_equipment_ms: int = 0

	# ── the player has decided ─────────────────
	## Where the player designated, when this use was ORDERED rather than chosen.
	## Read through `placement_or()`, never directly: Vector3.ZERO is a legal map
	## position, so `has_ordered_position` is the flag.
	##
	## An ordered use runs the SAME `execute()` as an autonomous one — the squad
	## throwing smoke where you pointed must be the same code as the squad
	## throwing it because it is losing, or the two drift and only one of them
	## gets fixed. What an order changes is the AIM, and `can_use()` not being
	## consulted at all.
	var ordered_position: Vector3 = Vector3.ZERO
	var has_ordered_position: bool = false

## What `under_fire_seconds` reads before anything has ever hit this robot.
## Large rather than infinite so arithmetic on it stays sane.
const NEVER_HIT := 9999.0

@export var equipment_name: String = "Equipment"
# Minimum seconds between uses (enforced by Enemy)
@export var cooldown: float = 8.0
## Does a PLAYER ORDER for this want a point on the ground, or just a yes?
##
## Smoke, mines and grenades all land somewhere, so pointing is the order. The
## Drone Carrier Pack and the Hatchling release units that climb and pick their
## own target, so designating a spot for them is ceremony — the useful order is
## "open it", and it is the one the player can give instantly.
##
## The designator reads this to decide whether a mode needs the hold-and-scrub
## or fires on the press.
@export var ordered_at_point: bool = true

# Subclasses implement these
func can_use(_context: EquipmentContext) -> bool:
	return false

func execute(_context: EquipmentContext) -> void:
	pass


## WHERE A PLACEMENT ACTUALLY GOES: the point the player designated when this
## use was ordered, and whatever the equipment worked out for itself otherwise.
##
## Every `execute()` that puts something on the ground ends with this, so the
## ordered and the autonomous paths differ in exactly one expression instead of
## forking into two functions that then stop matching.
func placement_or(context: EquipmentContext, own_choice: Vector3) -> Vector3:
	return context.ordered_position if context.has_ordered_position else own_choice


## WHERE SPAWNED ORDNANCE BELONGS: THE LEVEL, NOT THE SCENE.
##
## `get_tree().current_scene` is MASTER in this project — above World, above the
## level — so anything parented there outlives the mission it was fired in. Every
## execute() in this file's subclasses used it, and the Drone Carrier Pack made
## that visible: two Divers released near the end of a mission were still flying
## around after the next one loaded.
##
## The player's side already knew this. PlayerEquipment.level_node() documents
## the identical bug from the identical cause, and ai_grenade_projectile._level()
## says it a third time. This is the AI's copy of that rule.
##
## A robot's own parent IS the level it is standing in — squad_spawner and the
## enemy spawner both add bodies straight into it — so that is the host.
func spawn_host(owner_ai: Node) -> Node:
	if owner_ai != null and is_instance_valid(owner_ai) and owner_ai.get_parent() != null:
		return owner_ai.get_parent()
	# No level to belong to: a robot mid-removal, or a tree started by a script.
	# Still somewhere rather than nowhere, but it has to SAY so — anything parented
	# here survives a mission change.
	push_warning("%s: no level to spawn into, so this is going into the current scene and will outlive the mission." % equipment_name)
	var tree := get_tree()
	if tree == null:
		return null
	return tree.current_scene if tree.current_scene != null else tree.root


## THE ARC EVERY THROWN PIECE OF KIT USES.
##
## It lived in AIGrenade, which was fine while the grenade was the only thing
## that got thrown. Smoke and both mines are now thrown at a point too, and
## three private copies of a ballistics solve is exactly the family of bug this
## project keeps paying for — fix the arc in one and the other two keep the old
## behaviour, silently, because nothing is wrong enough to error.
##
## Picks the arc rather than the speed: the height is chosen so the thing clears
## the thrower's own head and comes down on the mark, and the velocity falls out
## of that. ZERO back means the geometry is unthrowable (the mark is directly on
## top of us) — callers must read that as "do not throw", not as "drop it".
static func throw_velocity(from: Vector3, to: Vector3) -> Vector3:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var displacement := to - from
	var horiz_dist := Vector2(displacement.x, displacement.z).length()
	var dy := displacement.y
	if horiz_dist < 0.01 or gravity <= 0.0:
		return Vector3.ZERO
	var arc_height: float = maxf(2.0, dy + 2.5)
	var vy: float = sqrt(2.0 * gravity * arc_height)
	var total_time: float = (vy / gravity) + sqrt(2.0 * maxf(arc_height - dy, 0.01) / gravity)
	if total_time <= 0.0:
		return Vector3.ZERO
	return Vector3(displacement.x / total_time, vy, displacement.z / total_time)
