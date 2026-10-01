extends SceneTree

# ─────────────────────────────────────────────
# EVERY CONSOLE A PLAYER CAN WALK UP TO HAS TO BE WIRED TO SOMETHING.
#
# capture_point.tscn is an InteractObjective with ONE terminal inside it, and
# its interactibles array names exactly that one child:
#
#   interactibles = [NodePath("Terminal/Interactible")]
#
# InteractObjective._on_objective_ready() connects `interacted` and sets the
# `mission_objective` meta on the members of that array and on nothing else. So
# a second terminal added to a capture point in a level is inert: it draws the
# same box, lights the same green lamp, and carries its own 1.6 x 2 x 1.6
# interact volume in the same place as the real one — and whichever of the two
# the player's interact query happens to return, half the time the answer is the
# one that does nothing. Three Rivers had five of them and every relay on the
# map read as broken.
#
# They got there by name collision. A node added as `Terminal` to something that
# already has a child called Terminal is renamed `Terminal2` when the editor
# saves, which is why four maps say Terminal2 and the one that has not been
# re-saved since still says Terminal.
#
# So: no level may add a terminal to a capture point. If a relay needs its
# console somewhere other than the objective's origin, move the capture point's
# own Terminal child — do not add a second one.
#
#   godot --headless --path . --script res://tools/test_objective_terminals.gd
# ─────────────────────────────────────────────

const CAPTURE := "res://Env/world_objects/capture_point.tscn"
const TERMINAL := "res://Env/world_objects/dummy_terminal.tscn"
const MAPS := "res://maps"

var _fails: int = 0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	# What the capture point actually wires, read from the scene rather than
	# assumed — if someone adds a second terminal to capture_point.tscn ITSELF
	# and wires it, this test should stop complaining on its own.
	var wired := _wired_paths(load(CAPTURE) as PackedScene)
	print("")
	print("capture_point.tscn wires: %s" % (" ".join(wired) if not wired.is_empty() else "NOTHING"))
	if wired.is_empty():
		_fail("capture_point.tscn wires no interactible at all — every relay in the game is dead")

	print("")
	print("══ TERMINALS ADDED TO CAPTURE POINTS ═════════════════════")
	for path in _level_paths():
		_check(path, wired)

	print("")
	if _fails == 0:
		print("PASS — no level adds an unwired console to an objective")
	else:
		print("FAIL — %d unwired console(s)" % _fails)
	quit(1 if _fails > 0 else 0)


## The NodePaths an InteractObjective scene names in its own interactibles array,
## as plain strings ("Terminal/Interactible").
func _wired_paths(packed: PackedScene) -> PackedStringArray:
	var out := PackedStringArray()
	if packed == null:
		return out
	var st := packed.get_state()
	for j in st.get_node_property_count(0):
		if String(st.get_node_property_name(0, j)) != "interactibles":
			continue
		var v: Variant = st.get_node_property_value(0, j)
		if v is Array:
			for np in v:
				out.append(str(np))
	return out


func _check(path: String, wired: PackedStringArray) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var st := packed.get_state()

	# Which nodes in this level ARE capture points, by name.
	var captures := {}
	for i in st.get_node_count():
		var inst := st.get_node_instance(i)
		if inst != null and inst.resource_path == CAPTURE:
			captures[String(st.get_node_name(i))] = true
	if captures.is_empty():
		return

	# The first path segment of each wired NodePath is the child the objective
	# actually listens to. Anything else the level hangs off a capture point and
	# instances as a terminal is a console that does nothing.
	var wired_children := {}
	for w in wired:
		wired_children[w.split("/")[0]] = true

	var added := PackedStringArray()
	for i in st.get_node_count():
		var inst := st.get_node_instance(i)
		if inst == null or inst.resource_path != TERMINAL:
			continue
		var parent := String(st.get_node_path(i, true))   # path to the PARENT
		if not captures.has(parent.get_file()):
			continue
		var child := String(st.get_node_name(i))
		# Godot renames a colliding addition, so the name on disk may be
		# Terminal2 OR the original Terminal — both are the same mistake.
		if wired_children.has(child) and child != "Terminal2":
			# Declared with the wired name AND with instance=: still an addition
			# rather than an override, because an override carries no instance.
			added.append("%s/%s (collides with the wired child)" % [parent.get_file(), child])
			continue
		added.append("%s/%s" % [parent.get_file(), child])

	print("")
	print("  %-34s %d capture point(s)" % [path.get_file(), captures.size()])
	if added.is_empty():
		print("     clean")
		return
	for a in added:
		_fail("%s: %s is a console wired to nothing" % [path.get_file(), a])


func _level_paths() -> Array:
	var out: Array = []
	var dir := DirAccess.open(MAPS)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".tscn") and not f.get_basename().ends_with("_art"):
			out.append("%s/%s" % [MAPS, f])
	out.sort()
	return out


func _fail(msg: String) -> void:
	_fails += 1
	print("     >> FAIL: %s" % msg)
