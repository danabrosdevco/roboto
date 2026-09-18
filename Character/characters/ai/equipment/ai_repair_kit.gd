extends AIEquipment
class_name AIRepairKit

# ─────────────────────────────────────────────
# AI REPAIR KIT — the squad's half of the repair tool.
#
# The player's version is a channelled beam you aim. An AI can't aim a channel
# sensibly, so this is the same idea expressed as something a robot can decide
# to do: patch up the worst-hurt ally within reach, instantly, on a cooldown.
#
# Deliberately NOT a revive. Bringing a downed squadmate back is the player's
# job and should stay the player's job — an AI that quietly undid your losses
# would remove the reason the repair tool matters.
# ─────────────────────────────────────────────

@export var heal_amount: int = 20
@export var heal_range: float = 6.0
# Won't bother unless someone is at least this hurt. Stops a kit being burned on
# a scratch the moment the cooldown comes up.
@export var min_wound_fraction: float = 0.6
@export var use_sound: AudioStreamPlayer3D


func can_use(context: EquipmentContext) -> bool:
	if context == null or context.owner_ai == null:
		return false
	return _find_patient(context.owner_ai) != null


func execute(context: EquipmentContext) -> void:
	if context == null or context.owner_ai == null:
		return
	var patient := _find_patient(context.owner_ai)
	if patient == null:
		return
	if patient.has_method("apply_healing"):
		patient.apply_healing(heal_amount, context.owner_ai)
	elif "health" in patient and "max_health" in patient:
		patient.health = mini(int(patient.max_health), int(patient.health) + heal_amount)
	if use_sound != null:
		use_sound.play()


# Worst-hurt living ally in range, including the user. Downed robots are skipped
# on purpose — see the note above.
func _find_patient(user: Enemy) -> Node:
	var best: Node = null
	var best_fraction := min_wound_fraction

	var candidates: Array = [user]
	for squad in user.get_tree().get_nodes_in_group("squads"):
		if squad is Squad:
			candidates.append_array((squad as Squad).get_living_members())

	for candidate in candidates:
		if candidate == null or not is_instance_valid(candidate):
			continue
		if not ("health" in candidate and "max_health" in candidate):
			continue
		if "downed" in candidate and candidate.downed:
			continue
		if "faction" in candidate and Enums.are_hostile(user.faction, candidate.faction):
			continue
		if user.global_position.distance_to(candidate.global_position) > heal_range:
			continue
		var fraction := float(candidate.health) / float(maxi(1, candidate.max_health))
		if fraction < best_fraction:
			best_fraction = fraction
			best = candidate
	return best
