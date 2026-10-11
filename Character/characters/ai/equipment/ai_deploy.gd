extends AIEquipment

# BY PATH, NOT class_name: a brand-new class_name is not resolvable until the
# editor rescans, and that rescan must not be run with the editor open. The
# scene references this script by path, which needs no registration.

# ─────────────────────────────────────────────
# DEPLOYED, NOT THROWN AT ANYTHING.
#
# A grenade is aimed: it wants a target standing still, or clustered, or behind
# cover, at between four and thirty metres. The Hatchling is not that. It is a
# canister that opens and lets small robots out, and they find their own way to
# whatever is nearby — so the only question worth asking is "is there anything
# around for them to find", and the only placement that matters is "not on my
# own feet".
#
# Running it on AIGrenade meant it inherited every one of the grenade's
# conditions. A squad with hatchlings would stand in a fight and never open one,
# because the thing it was fighting was moving, or in the open, or too close.
#
# WHAT IT NEEDS FROM THE CONTEXT is only `hostiles_near_target` and the squad's
# last spend — both of which exist because the firefight-only EquipmentContext
# was widened. It deliberately does NOT need `combat_target`: a robot that has
# been shot at from cover it cannot see has every reason to let these out.
#
# The Drone Carrier Pack is the same shape — release it, the Divers pick their
# own target — so ai_drone_pack.tscn is this script with a higher bar: two
# hostiles, a longer spacing, and min_target_health set so the pack waits for
# armour instead of being spent on the first rifle trooper that walks past.
# ─────────────────────────────────────────────

## What comes out, as a projectile scene. The canister, not the units — the
## canister carries its own payload.
@export var canister_scene: PackedScene
## How far to look for something worth opening it for. Matched to the payload's
## own seek radius by default: releasing them where they will find nothing is
## the one outcome worth avoiding, since there is no taking it back.
@export var release_radius: float = 40.0
## How many hostiles make it worth spending. One is enough for a hatchling —
## they are cheap and they swarm — but it is a knob because the drone pack,
## which is not cheap, will want a higher bar.
@export var min_hostiles: int = 1
## Hold unless something in range has at least this much hull. 0 means "anything
## will do", which is the hatchling.
##
## This is the Drone Carrier Pack's whole gate: two Divers at 95 supply spent on
## a rifle trooper is a worse trade than the rifle it is already carrying, and
## spent on a Walker it is the best thing in the loadout. Hull rather than frame
## cost on purpose — cost is the truer measure and it is what the Divers
## themselves rank by, but reading it means a load() per candidate inside a
## 1.5-second AI tick, and max_health separates infantry (60) from a rover (180)
## and a walker (320) on a plain property read.
@export var min_target_health: float = 0.0
## Don't open one within this many seconds of a squadmate spending anything.
## Four robots evaluating the same fight on the same tick is how a squad empties
## its pockets into one skirmish.
@export var squad_spacing_seconds: float = 6.0
## A gentle lob forward so it does not land between the thrower's feet. Not an
## aimed arc — there is nothing to aim at.
@export var toss_speed: float = 7.0

const _Analytics := preload("res://Managers/analytics.gd")


func can_use(context: AIEquipment.EquipmentContext) -> bool:
	if canister_scene == null:
		# EVERY REFUSAL SAYS WHY. A deploy with nothing to deploy would
		# otherwise sit in a slot looking like a decision the AI keeps making.
		push_warning("AIDeploy '%s': no canister_scene, so it can never be used." % equipment_name)
		return false
	# Somebody in the squad has just spent something. Let it land first.
	if context.squad_last_equipment_ms > 0:
		var since: float = (Time.get_ticks_msec() - context.squad_last_equipment_ms) / 1000.0
		if since < squad_spacing_seconds:
			return false
	# The only real question: is there anything out there for them to go and
	# find? Measured around the OWNER, because that is where they come out.
	var owner_ai := context.owner_ai
	if owner_ai == null or owner_ai.ai_manager == null:
		return false
	var found: Array = owner_ai.ai_manager.get_hostiles_in_radius(owner_ai, release_radius)
	if found.size() < min_hostiles:
		return false
	# And is any of it worth the payload? Skipped entirely at the default, so the
	# hatchling pays nothing for a rule it does not use.
	if min_target_health <= 0.0:
		return true
	for h in found:
		if h == null or not is_instance_valid(h):
			continue
		# A body with no hull at all — a prop, something mid-teardown — is not a
		# reason to spend the pack. `get` rather than `in`: the player and the
		# robots are different classes and only one of them is an Enemy.
		var hull = h.get("max_health")
		if hull != null and float(hull) >= min_target_health:
			return true
	return false


func execute(context: AIEquipment.EquipmentContext) -> void:
	if canister_scene == null:
		return
	var owner_ai := context.owner_ai
	var canister = canister_scene.instantiate()
	# THE LEVEL, not the current scene. See AIEquipment.spawn_host — the scene is
	# Master, which outlives the mission and took the ordnance with it.
	var host: Node = spawn_host(owner_ai)
	if host == null:
		return
	host.add_child(canister)

	var from: Vector3 = owner_ai.global_position + Vector3.UP * 1.2
	canister.global_position = from
	if canister.has_method("setup"):
		canister.setup(owner_ai)
	_Analytics.throw(owner_ai, _Analytics.label_for_scene(canister_scene.resource_path))

	# Away from us, toward the trouble if we have any idea where that is. Flat
	# and short: this is putting something down in front, not shelling a map
	# reference.
	#
	# A DESIGNATED POINT STEERS IT BUT DOES NOT CARRY IT. `ordered_at_point` is
	# false on both scenes that run this script, so the player cannot normally
	# point one anywhere — but if an order does arrive with a mark, throwing the
	# canister AT it would be wrong: what comes out flies and picks its own
	# target, so the mark is a direction to open toward, not a landing spot.
	var dir: Vector3 = context.threat_bearing
	if context.has_ordered_position:
		var toward := context.ordered_position - owner_ai.global_position
		toward = Vector3(toward.x, 0.0, toward.z)
		if toward.length_squared() > 0.0001:
			dir = toward.normalized()
	if dir == Vector3.ZERO:
		dir = -owner_ai.global_transform.basis.z
		dir = Vector3(dir.x, 0.0, dir.z)
		dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	if canister is RigidBody3D:
		(canister as RigidBody3D).linear_velocity = dir * toss_speed + Vector3.UP * 1.5
