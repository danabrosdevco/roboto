extends SceneTree

# ─────────────────────────────────────────────
# A DRONE HAS TO SEE A BLOCK AT ITS OWN HOVER HEIGHT.
#
# Every flying unit held altitude off one RayCast3D pointing straight DOWN, and
# steered on a heading with its Y zeroed. So the only thing it knew about the
# world was the ground beneath it, and the only thing it avoided was other
# aircraft. A block at hover height was invisible until the body touched its
# side — and then the down-ray still saw ground 22m below and reported the
# altitude as correct, so the drone pushed into the face forever.
#
# The test builds exactly that: a block across the flight path, centred on the
# drone's own cruising altitude. The CONTROL run disables the lookahead and has
# to fail to get past, because a test of this that passes either way is not
# testing anything.
#
#   godot --headless --path . --script res://tools/test_air_clearance.gd
# ─────────────────────────────────────────────

const DRONE := "res://Character/characters/ai/spotter_drone.tscn"

var _fails: int = 0
var _level: Node = null
var _player: Node3D = null
var _ground: Callable


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 90:
		await physics_frame
	_player = _find(root, "Player")
	_level = _player.get_parent()
	_level.add_child(load("res://maps/appendix/valley_level.tscn").instantiate())
	for _i in 30:
		await physics_frame

	var space := _player.get_world_3d().direct_space_state
	_ground = func(x: float, z: float) -> Vector3:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -300, z))
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		return hit.position if hit else Vector3(x, -9.0, z)

	var with_probe := await _fly(true)
	var without := await _fly(false)

	print("")
	_check("a drone flown at a block at its own hover height gets past it",
		with_probe["passed"], "travelled %.1f m of %.0f" % [with_probe["travelled"], with_probe["needed"]])
	_check("...by climbing over it, not squeezing through",
		with_probe["peak_rise"] > 3.0, "rose %.1f m above cruise" % with_probe["peak_rise"])
	_check("...and it was looking ahead, not reacting to what was under it",
		with_probe["saw_ahead"], "highest ground seen ahead: %.1f" % with_probe["ahead_max"])

	# THE CONTROL. Same flight, lookahead off. If this also gets past then the
	# block was never in the way and the three checks above mean nothing.
	_check("(control) with the lookahead off it wedges on the block",
		not without["passed"], "travelled %.1f m of %.0f" % [without["travelled"], without["needed"]])

	print("")
	print("ALL AIR CLEARANCE CHECKS PASS" if _fails == 0 else "%d AIR CLEARANCE CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


## Fly a drone due -Z into a block sitting at its cruising altitude.
func _fly(probe_on: bool) -> Dictionary:
	var g: Vector3 = _ground.call(300.0, 250.0) as Vector3
	var drone: Node3D = load(DRONE).instantiate()
	drone.faction = Enums.Factions.ENEMY
	_level.add_child(drone)
	var cruise: float = float(drone.cruise_height)
	var start := Vector3(300.0, g.y + cruise, 250.0)
	drone.global_position = start
	for _i in 10:
		await physics_frame

	# The block: 24m wide so it cannot be flown around in the time given, and
	# spanning the drone's own altitude so it is exactly the reported case.
	var block := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(24.0, 12.0, 6.0)
	cs.shape = box
	block.add_child(cs)
	block.collision_layer = 1
	_level.add_child(block)
	block.global_position = Vector3(300.0, g.y + cruise, 215.0)
	var block_top: float = block.global_position.y + 6.0
	for _i in 6:
		await physics_frame

	# Driven by this test, the way the navigation layer drives a ground robot:
	# a heading and a speed. Everything below that is the real flight code.
	drone.set_physics_process(false)
	if not probe_on:
		# The control. Nothing ahead is sampled, which is the old behaviour.
		drone._clearance.samples = 0
		drone._clearance.whisker_length = 0.0
	drone._fly_dir = Vector3(0.0, 0.0, -1.0)

	var target := Vector3(300.0, g.y + cruise, 150.0)
	var delta := 1.0 / 60.0
	var peak: float = drone.global_position.y
	var ahead_max: float = -INF
	for _f in 420:                                  # seven seconds
		drone._steer(target, float(drone.cruise_speed), cruise, delta)
		drone._apply_motion()
		peak = maxf(peak, drone.global_position.y)
		ahead_max = maxf(ahead_max, drone._clearance.ground_ahead())
		await physics_frame

	var travelled: float = start.z - drone.global_position.z
	var needed: float = start.z - (block.global_position.z - 3.0)
	var out := {
		"passed": drone.global_position.z < block.global_position.z - 3.0,
		"travelled": travelled,
		"needed": needed,
		"peak_rise": peak - start.y,
		"saw_ahead": ahead_max > block.global_position.y,
		"ahead_max": ahead_max,
	}
	print("  %s: z %.1f -> %.1f (block at %.1f), peak y %.1f (cruise %.1f, block top %.1f)" % [
		"with lookahead" if probe_on else "control, lookahead off",
		start.z, drone.global_position.z, block.global_position.z,
		peak, start.y, block_top])
	drone.free()
	block.free()
	return out
