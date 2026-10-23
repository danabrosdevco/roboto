extends AIEquipment

# BY PATH, NOT class_name: a brand-new class_name is not resolvable until the
# editor rescans, and that rescan must not be run with the editor open. The
# scenes reference this script by path, which needs no registration.

# ─────────────────────────────────────────────
# MINES — LAID ON THE GROUND YOU ARE WORRIED ABOUT, BEFORE THEY GET TO IT.
#
# A mine is the only piece of kit in the game whose value is in the FUTURE. A
# grenade, a cloud, a pack of Divers all pay out within seconds of being spent;
# a mine pays out when something walks over it, which may be never. That makes
# the decision entirely about timing, and gets two rules out of it that nothing
# else in the kit needs:
#
#   IT IS TOO LATE WHEN THEY ARE ON YOU. Mine.arm_seconds is 1.5 — a mine laid
#   at contact range is inert for the whole exchange and then sits there armed
#   with nothing left to catch. A robot in that position should be shooting.
#   `min_contact_metres` is that rule, and it is the single most important
#   number in this file.
#
#   AND IT IS POINTLESS WHEN NOTHING IS COMING. A robot with no idea where
#   anything is, laying mines on the ground it happens to be standing on, is
#   littering. So it needs a bearing: something seen, somewhere, within
#   `watch_radius`. That is not a limitation to widen later — "lay it where you
#   know they will come from" is the whole skill of the item.
#
# BETWEEN THOSE TWO IS THE WINDOW: contact is known and coming, and is not here
# yet. In that window the mine goes on the approach — along the threat bearing,
# `place_metres` out — so whatever is coming has to cross it.
#
# NO FRIENDLY-FIRE RULE IS NEEDED and that is not an oversight. Mine._candidates
# asks AIManager.hostiles_for(whoever placed it), so a squad-laid mine cannot
# answer to the squad or to the player, and an enemy-laid one answers to both.
# Our own robots walking over our own mines is already impossible, which is the
# only reason an AI can be trusted to lay these at all.
#
# OBJECTIVES, and why NONE is in the list: an enemy garrison robot is in no
# squad and reports NONE, and a garrison robot holding a position is the most
# natural mine-layer in the game. Excluding NONE would have meant only the
# player's own squad ever laid one.
# ─────────────────────────────────────────────

## The mine, as a projectile scene. Thrown, not dropped — it settles itself
## (Mine._try_settle) once it has touched something.
@export var mine_scene: PackedScene

## How far out on the approach to put it. Far enough that whatever is coming
## crosses it before it reaches us, close enough that a robot can throw it.
@export var place_metres: float = 9.0
## Closer than this and it is too late: Mine.arm_seconds means a mine laid at
## contact range is inert for the exchange it was laid for.
@export var min_contact_metres: float = 12.0
## How far to look for a reason to lay one. Something has to be out there or the
## mine goes on ground nobody will cross.
@export var watch_radius: float = 60.0
## Don't lay within this many seconds of a squadmate laying one. The point of a
## minefield is coverage; four robots answering the same approach on the same
## tick put all four mines on the same three square metres of it.
@export var squad_spacing_seconds: float = 12.0

## Which orders lay mines, as Squad.SquadObjective values. Holding ground,
## breaking contact, walking a beat, and NONE — which is what a robot in no
## squad reports, including every enemy garrison robot in the game.
##
## ADVANCE and ATTACK are deliberately absent: a robot moving onto an objective
## is going to be standing past its own mine within the minute.
const LAYING_OBJECTIVES: Array[int] = [
	0,  # NONE
	2,  # DEFEND
	3,  # WITHDRAW
	6,  # PATROL
]

const _Analytics := preload("res://Managers/analytics.gd")


func can_use(context: AIEquipment.EquipmentContext) -> bool:
	if mine_scene == null:
		# EVERY REFUSAL SAYS WHY. A mine layer with no mine would otherwise sit
		# in a slot looking like a decision the AI keeps making.
		push_warning("AIMine '%s': no mine_scene, so it can never be used." % equipment_name)
		return false
	var owner_ai := context.owner_ai
	if owner_ai == null:
		push_warning("AIMine '%s': asked with no owner in the context." % equipment_name)
		return false
	# A squadmate just spent something. Mines in particular want spreading out —
	# four of them in one spot is one mine with a bigger blast.
	if context.squad_last_equipment_ms > 0:
		var since: float = (Time.get_ticks_msec() - context.squad_last_equipment_ms) / 1000.0
		if since < squad_spacing_seconds:
			return false
	if not LAYING_OBJECTIVES.has(context.squad_objective):
		return false
	# Something has to be out there, and we have to know roughly where.
	if context.threat_bearing == Vector3.ZERO:
		return false
	var threat_range: float = owner_ai.global_position.distance_to(context.threat_position)
	if threat_range > watch_radius:
		return false
	# ...and it has to not be here yet.
	return threat_range >= min_contact_metres



func execute(context: AIEquipment.EquipmentContext) -> void:
	if mine_scene == null:
		return
	var owner_ai := context.owner_ai
	# On the approach, not at our feet. Never further than the threat itself —
	# a mine thrown past what it is meant to catch catches nothing.
	var reach: float = minf(place_metres,
		owner_ai.global_position.distance_to(context.threat_position) * 0.5)
	var mark: Vector3 = placement_or(context,
		owner_ai.global_position + context.threat_bearing * maxf(reach, 2.0))

	var from: Vector3 = owner_ai.global_position + Vector3.UP * 1.2
	var arc := AIEquipment.throw_velocity(from, mark)
	if arc == Vector3.ZERO:
		# The mark came out on top of us. Say so rather than consuming a mine
		# and dropping it between our own feet.
		push_warning("AIMine '%s': no throwable arc to %s, holding." % [equipment_name, str(mark)])
		return

	var mine = mine_scene.instantiate()
	# THE LEVEL, not the current scene. See AIEquipment.spawn_host — the scene is
	# Master, which outlives the mission and took the ordnance with it.
	var host: Node = spawn_host(owner_ai)
	if host == null:
		return
	host.add_child(mine)
	mine.global_position = from
	if mine.has_method("setup"):
		# Load-bearing: Mine._faction() reads the thrower, and a mine with no
		# thrower defaults to the PLAYER's side. An enemy robot laying one
		# without this would lay a mine that hunts its own garrison.
		mine.setup(owner_ai)
	_Analytics.throw(owner_ai, _Analytics.label_for_scene(mine_scene.resource_path))
	if mine is RigidBody3D:
		(mine as RigidBody3D).linear_velocity = arc
