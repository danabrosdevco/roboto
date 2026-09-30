class_name PauseHold

# ─────────────────────────────────────────────
# PAUSE HOLD — the one place get_tree().paused is written.
#
# Several systems pause the game for their own reasons: level loads, the squad
# manager, the pause menu, the splash, the mission briefing, the map. Each used
# to write get_tree().paused directly, so the LAST writer won. The bug that
# made this necessary: world.gd paused for a level load, the mission briefing
# opened inside that load, and then world.gd unconditionally unpaused once the
# level was in — releasing the briefing's pause along with its own. The game
# ran underneath the map screen while it waited for a keypress.
#
# Every holder takes a NAMED hold and releases the same name. The tree is
# paused while any hold is outstanding, and only unpauses when the last one
# lets go. Named rather than counted so take/release are idempotent — taking
# twice or releasing something never taken cannot drift the state — and so a
# hold that leaks can be identified by name instead of guessed at.
#
# Static, like BarkDirector: no autoload to register and no ready-order to get
# wrong. Engine.get_main_loop() is the tree whatever node is asking.
# ─────────────────────────────────────────────

static var _holds: Dictionary = {}


static func take(who: StringName) -> void:
	_holds[who] = true
	_apply()


static func release(who: StringName) -> void:
	_holds.erase(who)
	_apply()


static func is_held(who: StringName = &"") -> bool:
	if who == &"":
		return not _holds.is_empty()
	return _holds.has(who)


## Who is currently holding the game paused. For the log when something is
## stuck — "paused by [level_load]" says exactly who forgot to let go.
static func holders() -> Array:
	return _holds.keys()


static func _apply() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var held: bool = not _holds.is_empty()
	tree.paused = held
	# AND THE BATTLEFIELD GOES QUIET WITH IT.
	#
	# tree.paused stops nodes; it does not stop AudioServer. Every loop playing
	# at the moment you hit escape carried on underneath the menu — a leaper's
	# attack loop, a rover's engine, a firefight — which sounds exactly like
	# the game still running, and is why a paused screen felt like something
	# was going crazy out there. Effects and voices are held; INTERFACE is not,
	# because the menu you just opened needs its own clicks.
	AudioBuses.set_paused(held)
