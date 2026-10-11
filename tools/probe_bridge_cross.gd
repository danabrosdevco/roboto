extends SceneTree
# ─────────────────────────────────────────────
# A MIXED COLUMN OVER A REAL BRIDGE.
#
# 10 soldiers, 4 rovers, 2 walkers, all ordered across at once — the crowd that
# actually jams, rather than one robot in clean conditions.
#
# The bridge is found by NODE, and the crossing axis is MEASURED off the navmesh
# rather than assumed: an earlier version of this test used a squad point that
# merely had "Br05" in its name, sat 200m from any bridge, and reported a
# confident 0.0m for both modes because nothing ever stood on a deck.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/probe_bridge_cross.gd [-- 0|1]
#       0 CORRIDORFUNNEL (Godot default)   1 EDGECENTERED
# ─────────────────────────────────────────────
const SQUADS := [
	["soldier", "res://Character/characters/ai/soldier_rifle.tscn", 10],
	["rover",   "res://Character/characters/ai/vehicle_rover.tscn",  4],
	["walker",  "res://Character/characters/ai/walker.tscn",         2],
]

func _find(n: Node, cls: String) -> Node:
	var s: Script = n.get_script() as Script
	if s != null and s.get_global_name() == StringName(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null

func _byname(n: Node, want: String) -> Node:
	if n.name == want:
		return n
	for c in n.get_children():
		var f := _byname(c, want)
		if f != null:
			return f
	return null

## How far the navmesh runs from `at` along `dir` before it stops.
func _reach(map: RID, at: Vector3, dir: Vector3) -> float:
	var d := 1.0
	while d < 40.0:
		var p: Vector3 = at + dir * d
		var on := NavigationServer3D.map_get_closest_point(map, p)
		if Vector2(on.x - p.x, on.z - p.z).length() > 0.6:
			break
		d += 0.5
	return d


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	Engine.max_fps = 60
	await process_frame
	var args := OS.get_cmdline_user_args()
	var mode: int = int(args[0]) if args.size() > 0 else 1

	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 120:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	var level: Node = player.get_parent()
	level.add_child(load("res://maps/mutaha_wip_level.tscn").instantiate())
	for _i in 300:
		await physics_frame

	var mgr: Node = _find(root, "AIManager")
	var bridge := _byname(level, "Bridge02") as Node3D
	if bridge == null:
		print("  Bridge02 NOT FOUND"); quit(1); return
	var map := player.get_world_3d().navigation_map
	var centre := NavigationServer3D.map_get_closest_point(map, bridge.global_position)
	var ax := bridge.global_transform.basis.x.normalized()
	var az := bridge.global_transform.basis.z.normalized()
	# The deck runs the way the navmesh runs furthest. The other axis is width.
	var along_x: float = _reach(map, centre, ax) + _reach(map, centre, -ax)
	var along_z: float = _reach(map, centre, az) + _reach(map, centre, -az)
	var cross: Vector3 = ax if along_x > along_z else az
	var wide: Vector3 = az if along_x > along_z else ax
	var deck: float = minf(along_x, along_z)
	print("  Bridge02 at %s — deck %.1f m wide, crossing runs %s" % [
		centre.round(), deck, "X" if along_x > along_z else "Z"])
	player.global_position = centre + cross * 60.0 + Vector3.UP * 2.0

	var made: Array = []
	var kinds: Array = []
	var starts: Array = []
	var i := 0
	for spec in SQUADS:
		for n in int(spec[2]):
			var b: Node3D = load(str(spec[1])).instantiate()
			b.faction = Enums.Factions.ALLIED
			level.add_child(b)
			var lane: float = -3.0 + 1.2 * float(n % 6)
			var back: float = 18.0 + 3.0 * float(n / 6)
			b.global_position = centre - cross * back + wide * lane + Vector3.UP
			made.append(b)
			kinds.append(str(spec[0]))
			# WITHOUT THIS THEY NEVER MOVE. register_enemy is what hands a robot its
			# `player` reference, and _physics_process returns on its first line
			# while that is null — three runs of this test reported a confident
			# zero because sixteen robots were standing there switched off.
			if mgr != null:
				mgr.register_enemy(b)
			starts.append(b.global_position)
			i += 1
	for _i in 60:
		await physics_frame
	var goal: Vector3 = centre + cross * 22.0
	for b in made:
		b.nav_agent.path_postprocessing = mode
		b.order_move_to(goal, true, false)

	var worst := {}
	var crossed := {}
	var stuck := {}
	for k in ["soldier", "rover", "walker"]:
		worst[k] = 0.0; crossed[k] = 0; stuck[k] = 0
	for f in 7200:                       # 120 s
		await physics_frame
		if f % 6 != 0:
			continue
		for j in made.size():
			var b: Node3D = made[j]
			if not is_instance_valid(b):
				continue
			var rel: Vector3 = b.global_position - centre
			if absf(rel.dot(cross)) < deck * 0.5:         # on the deck
				worst[kinds[j]] = maxf(worst[kinds[j]], absf(rel.dot(wide)))
	for j in made.size():
		var b: Node3D = made[j]
		if not is_instance_valid(b):
			continue
		if (b.global_position - centre).dot(cross) > deck * 0.5:
			crossed[kinds[j]] += 1
		else:
			stuck[kinds[j]] += 1
	# DID THEY MOVE AT ALL? Three attempts at this test have reported zero, and
	# "nobody crossed" and "nobody moved" need telling apart before any of it
	# means anything.
	var moved_total := 0.0
	var moved_any := 0
	for j in made.size():
		var b: Node3D = made[j]
		if not is_instance_valid(b):
			continue
		var d: float = (b.global_position - (starts[j] as Vector3)).length()
		moved_total += d
		if d > 2.0:
			moved_any += 1
	print("  movement: %d of %d moved more than 2m, %.1f m travelled in total" % [
		moved_any, made.size(), moved_total])
	var b0: Node3D = made[0]
	if is_instance_valid(b0):
		print("  first soldier: start %s now %s target %s state=%s" % [
			(starts[0] as Vector3).round(), b0.global_position.round(),
			b0.movement_target.round(), str(b0.movement_state)])
	print("  goal %s   centre %s   cross %s" % [goal.round(), centre.round(), cross])
	print("  mode %s" % ("CORRIDORFUNNEL" if mode == 0 else "EDGECENTERED"))
	for spec in SQUADS:
		var k := str(spec[0])
		print("    %-8s across %2d/%-2d   still short %2d   worst %4.1f m off centre" % [
			k, crossed[k], int(spec[2]), stuck[k], worst[k]])
	quit(0)
