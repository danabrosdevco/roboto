extends SceneTree

# PauseHold composition — the exact sequence that let the game run underneath
# the mission briefing. world.gd holds "level_load", the briefing opens inside
# that load and takes "briefing", then the load finishes and releases its hold.
# The tree must STAY paused until the briefing lets go.
var _fails := 0

func _check(label: String, got: bool, want: bool) -> void:
	if got == want:
		print("PASS  %s" % label)
	else:
		print("FAIL  %s (got %s, want %s)" % [label, str(got), str(want)])
		_fails += 1

func _init() -> void:
	await process_frame

	PauseHold.take(&"level_load")
	_check("level load pauses", paused, true)

	PauseHold.take(&"briefing")
	PauseHold.release(&"level_load")
	_check("briefing survives the load finishing", paused, true)

	PauseHold.release(&"briefing")
	_check("unpauses once the last hold goes", paused, false)

	# Idempotent: a double take and a release of something never taken must
	# not drift the state.
	PauseHold.take(&"squad_manager")
	PauseHold.take(&"squad_manager")
	PauseHold.release(&"squad_manager")
	_check("double take then one release unpauses", paused, false)
	PauseHold.release(&"never_taken")
	_check("releasing an unknown hold is harmless", paused, false)

	# Pause menu and briefing independent of each other.
	PauseHold.take(&"master")
	PauseHold.take(&"briefing")
	PauseHold.release(&"master")
	_check("closing pause menu keeps briefing's pause", paused, true)
	PauseHold.release(&"briefing")
	_check("all released", paused, false)

	print("")
	print("ALL PAUSE CHECKS PASS" if _fails == 0 else "%d PAUSE CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
