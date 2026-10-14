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

## EVERY capture-point scene, not one named path. The maps were swapped from
## capture_point.tscn to compute_core_point_small.tscn and this suite went on
## reporting every level "clean" — because it could no longer find a capture
## point to have a problem with. A test that passes by looking in the wrong place
## is worse than no test.
const CAPTURES := [
	"res://Env/world_objects/capture_point.tscn",
	"res://Env/world_objects/compute_core_point_small.tscn",
	"res://Env/world_objects/compute_core_point.tscn",
	"res://Env/world_objects/compute_core_point_large.tscn",
]
const TERMINAL := "res://Env/world_objects/dummy_terminal.tscn"
const MAPS := "res://maps"

var _fails: int = 0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	# What the capture point actually wires, read from the scene rather than
	# assumed — if someone adds a second terminal to capture_point.tscn ITSELF
	# and wires it, this test should stop complaining on its own.
	var wired := PackedStringArray()
	print("")
	for cap in CAPTURES:
		var w := _wired_paths(load(cap) as PackedScene)
		print("  %-34s wires: %s" % [cap.get_file(), " ".join(w) if not w.is_empty() else "NOTHING"])
		if w.is_empty():
			_fail("%s wires no interactible at all — every relay built on it is dead" % cap.get_file())
		for p in w:
			if not wired.has(p):
				wired.append(p)

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


## WHERE A LEVEL KEEPS ITS GAMEPLAY IS NOT THIS TEST'S BUSINESS, but it has to
## be able to find it. Georgetown, Polaris and Causeway keep their capture
## points in maps/gameplay/<name>_ops.tscn and only INSTANCE it, and an
## instanced scene's nodes are not in the parent's SceneState at all — so all
## three dropped out of this report entirely and the suite went on printing
## PASS. That is the same failure as the capture_point/compute_core swap the
## header above is about: a test that passes by looking in the wrong place.
##
## So the check follows instances, one scene at a time rather than node by
## node. The parent/child name logic below only makes sense WITHIN one state —
## `get_node_path` and `get_node_name` are state-local — so running the whole
## check again on the sub-scene is both simpler and more correct than trying to
## flatten the two states together.
##
## Only into scenes under res://maps, and never into an _art scene: a level's
## art is hundreds of instances and holds no objectives.
const MAX_SUB_DEPTH := 2


func _check(path: String, wired: PackedStringArray, depth: int = 0, seen: Dictionary = {}) -> void:
	if seen.has(path):
		return
	seen[path] = true
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var st := packed.get_state()

	if depth < MAX_SUB_DEPTH:
		for i in st.get_node_count():
			var sub := st.get_node_instance(i)
			if sub == null:
				continue
			var sub_path := str(sub.resource_path)
			if not sub_path.begins_with(MAPS + "/") or sub_path.get_basename().ends_with("_art"):
				continue
			_check(sub_path, wired, depth + 1, seen)

	# Which nodes in this level ARE capture points, by name.
	var captures := {}
	for i in st.get_node_count():
		var inst := st.get_node_instance(i)
		if inst != null and CAPTURES.has(inst.resource_path):
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
