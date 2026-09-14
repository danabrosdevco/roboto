extends LevelExit
class_name MissionExit

# ─────────────────────────────────────────────
# MISSION EXIT — a LevelExit whose destination isn't decided until you touch it.
#
# LevelExit takes `next_level` from the inspector, which can't work for a base
# that deploys to whichever mission you picked, or for an extraction pad that
# has to know which base to go home to. This asks Campaign instead.
#
# Place the SAME node in both maps. On the base it deploys; on a mission it
# extracts. Campaign.in_mission decides which, so there's nothing to configure
# per-map beyond the mode if you want to be explicit.
# ─────────────────────────────────────────────

enum Mode {
	AUTO,      # deploy at base, extract on a mission — usually what you want
	DEPLOY,
	EXTRACT,
}

@export var mode: Mode = Mode.AUTO
# Blocks extraction until the mission's objectives report done. Leave false
# while you're still building the loop out.
@export var requires_objectives_complete: bool = false
@export var prompt: String = ""

signal blocked(reason: String)


func _ready() -> void:
	# LevelExit is found by group in World._ready(), so stay in it.
	add_to_group("levelexit")


func _resolved_mode() -> Mode:
	if mode != Mode.AUTO:
		return mode
	return Mode.EXTRACT if Campaign.in_mission else Mode.DEPLOY


func _on_area_3d_body_entered(body: Node3D) -> void:
	if not (body is Player):
		return

	var resolved := _resolved_mode()
	var destination := Campaign.next_destination()

	if destination == null:
		# Refuse rather than loading null. At base this means no mission is
		# selected yet, which is a UI state, not an error.
		blocked.emit("NO DESTINATION SELECTED" if resolved == Mode.DEPLOY else "NO BASE LEVEL SET")
		return

	if resolved == Mode.DEPLOY:
		Campaign.begin_deploy()
	else:
		if requires_objectives_complete and not _objectives_complete():
			blocked.emit("OBJECTIVES INCOMPLETE")
			return
		# Collect BEFORE the signal — World frees the level in response to it,
		# and write_back needs the Soldier nodes to still exist.
		Campaign.extract(true)

	next_level_signal.emit(destination)


# Single definition of "can we leave", owned by the tracker. With no tracker or
# no objectives placed, this returns true so the flag stays safe to leave on.
func _objectives_complete() -> bool:
	if Campaign.objectives == null:
		return true
	return Campaign.objectives.all_required_complete()
