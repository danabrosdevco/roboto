extends Node
class_name StimulusManager

# ─────────────────────────────────────────────
# STIMULUS MANAGER
# Scene-wide event bus for AI awareness.
# Lives in World alongside AIManager.
# Every Enemy gets a reference on registration.
#
# STIMULI:
#   GUNSHOT_HEARD — a weapon fired nearby
#   ALLY_SHOT     — a friendly AI took damage
#   ALLY_DIED     — a friendly AI was killed
#   ENEMY_SPOTTED — confirmed visual contact on a hostile
#
# Each stimulus has:
#   type            — StimulusType enum
#   source_position — where it originated
#   source_node     — who caused it (can be null)
#   radius          — how far it propagates
#   faction         — which faction's AIs should respond
# ─────────────────────────────────────────────

enum StimulusType {
	GUNSHOT_HEARD,
	ALLY_SHOT,
	ALLY_DIED,
	ENEMY_SPOTTED
}

# Default radii for each stimulus type (metres)
const DEFAULT_RADIUS := {
	StimulusType.GUNSHOT_HEARD: 30.0,
	StimulusType.ALLY_SHOT:     20.0,
	StimulusType.ALLY_DIED:     25.0,
	StimulusType.ENEMY_SPOTTED: 35.0,
}

# All registered AI — set by AIManager after registration
var registered_ai: Array[AI] = []

# Optional: debug print all stimuli
@export var debug_log: bool = false


# ─────────────────────────────────────────────
# EMIT
# The single entry point for broadcasting a stimulus.
# ─────────────────────────────────────────────
func emit_stimulus(
	type: StimulusType,
	source_position: Vector3,
	emitting_faction: Enums.Factions,
	source_node: Node = null,
	radius: float = -1.0
) -> void:

	var effective_radius: float = radius if radius > 0.0 else DEFAULT_RADIUS[type]

	if debug_log:
		print("[Stimulus] %s | faction=%s | pos=%s | r=%.1f" % [
			StimulusType.keys()[type],
			Enums.Factions.keys()[emitting_faction],
			source_position,
			effective_radius
		])

	for ai in registered_ai:
		if ai == null or not ai.alive:
			continue
		# Only notify AIs of the same faction as the emitter
		# (your allies hear your gunshots and deaths, not the enemy's)
		if ai is Enemy and (ai as Enemy).faction != emitting_faction:
			continue
		var dist = ai.global_position.distance_to(source_position)
		if dist > effective_radius:
			continue
		if ai.has_method("receive_stimulus"):
			ai.receive_stimulus(type, source_position, source_node, dist)


# ─────────────────────────────────────────────
# REGISTRATION (called by AIManager)
# ─────────────────────────────────────────────
func register_ai(ai: AI) -> void:
	if ai not in registered_ai:
		registered_ai.append(ai)

func deregister_ai(ai: AI) -> void:
	registered_ai.erase(ai)

func clear() -> void:
	registered_ai.clear()
