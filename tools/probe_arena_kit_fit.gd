extends SceneTree

# ─────────────────────────────────────────────
# DOES THE BUNKER KIT ACTUALLY FIT IN THE ARENA BAY?
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_arena_kit_fit.gd
#
# The proving ground's bay is 30 x 30 m at Godot z 59..89, with the capture
# core at z 65 and the way out at z 80. Those spacings were chosen for two
# GENERATED BOXES about a metre across. Swapping in the real entrance kit puts
# a structure there instead, and site_slice.gd records the mountings as 33.8 m
# (open), 18.3 m (cliff) and smaller (wall) — deep enough that the wrong choice
# either swallows the core or runs out through the back of the bay.
#
# So this measures the three kits instead of trusting a comment written about
# a different map, and says which one fits with the core where it is.
#
# It places nothing and changes nothing.
# ─────────────────────────────────────────────

const MOUNTS := {
	&"open": "res://maps/blocks/bunker/bunker_entrance_open.tscn",
	&"cliff": "res://maps/blocks/bunker/bunker_entrance_cliff.tscn",
	&"wall": "res://maps/blocks/bunker/bunker_entrance_wall.tscn",
}

## The bay, from tools/build_proving.gd via training_core.gd's own note.
##
## MEASURED 2026-10-16, and it overturned the guess it was written to check.
## site_slice.gd records `open` as "33.8 m deep", which was read here as 33.8 m
## of TUNNEL running back behind the doorway — enough to swallow the core at
## z 65. It is the other way round: the kits reach FORWARD of their origin
## (open 22.8 m, cliff 6.8, wall 2.9) and only about 11 m back. The core was
## never at risk; the bay WALL was, and `open` overshoots it by 13.8 m.
##
## So the arena uses `cliff`: it spans z 68.5..86.8 inside a bay that ends at
## 89, and its revetted headwall is what a way down cut into the back of a
## firing range looks like. `wall` also fits but wants a ceiling it has not got.
const BAY_NEAR := 59.0
const BAY_FAR := 89.0
const CORE_Z := 65.0
const BUNKER_Z := 80.0
## The core prefab's own footprint has to be cleared too, not just its centre.
const CORE_HALF := 1.8


func _init() -> void:
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame

	print("bay z %.0f..%.0f, core at z %.0f, bunker at z %.0f" % [
		BAY_NEAR, BAY_FAR, CORE_Z, BUNKER_Z])
	print("")
	for name in MOUNTS:
		await _measure(String(name), String(MOUNTS[name]))
	quit(0)


func _measure(label: String, path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		print("%-6s  NO SCENE at %s" % [label, path])
		return
	var kit := packed.instantiate()
	root.add_child(kit)
	for _i in 6:
		await process_frame

	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var found := false
	for m in _meshes(kit):
		var box: AABB = (m as MeshInstance3D).get_aabb()
		box = (m as Node3D).global_transform * box
		lo = lo.min(box.position)
		hi = hi.max(box.position + box.size)
		found = true
	if not found:
		print("%-6s  no meshes to measure" % label)
		kit.queue_free()
		await process_frame
		return

	# The kit is authored facing +Z with its tunnel running back into -Z, so
	# "depth" is how far behind the origin it reaches and "front" how far in
	# front of it.
	var back: float = -lo.z
	var front: float = hi.z
	var wide: float = hi.x - lo.x
	var tall: float = hi.y - lo.y

	var reaches_to: float = BUNKER_Z - back
	var out_front: float = BUNKER_Z + front
	var clears_core: bool = reaches_to > CORE_Z + CORE_HALF
	var inside_bay: bool = reaches_to >= BAY_NEAR and out_front <= BAY_FAR

	print("%-6s  %5.1f m back, %4.1f m front, %5.1f wide, %5.1f tall" % [
		label, back, front, wide, tall])
	print("        placed at z %.0f it spans z %.1f .. %.1f" % [
		BUNKER_Z, reaches_to, out_front])
	print("        clears the core at z %.0f: %s" % [CORE_Z,
		"yes" if clears_core else "NO — it would swallow it"])
	print("        stays inside the bay:       %s" % [
		"yes" if inside_bay else "NO — it runs out through the wall"])
	print("        VERDICT: %s" % [
		"usable here" if (clears_core and inside_bay) else "does not fit at z %.0f" % BUNKER_Z])
	print("")

	kit.queue_free()
	await process_frame


func _meshes(n: Node, out: Array = []) -> Array:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)
	return out
