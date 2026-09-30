extends SceneTree

# ─────────────────────────────────────────────
# THE PLAYER GETS OVER SMALL THINGS, AND STILL DOES NOT GET OVER BIG ONES.
#
# CharacterBody3D has no step-up. It slides along whatever it cannot climb, so
# a kerb, a doorway lip or the edge of a brush stopped you dead with nothing on
# screen to say why — and TrenchBroom geometry is made of those edges.
#
# Both halves matter. A step-up that lifts over anything is worse than none at
# all: it walks you up walls and over railings. So this drives the player into
# a low box (must pass) and then into a tall one (must NOT), from the same
# start, at the same speed.
#
# The third check is the one that is easy to lose: there has to be GROUND where
# the step would land, or the same code walks you off the lip of a pit into
# mid-air.
# ─────────────────────────────────────────────

const LOW := 0.22      # a kerb
const TALL := 1.10     # a wall
# Nothing in the way at all: the step must not fire on open ground.
const FLAT := 0.0

var _fails := 0
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
	_level.add_child(load("res://maps/valley_level.tscn").instantiate())
	for _i in 20:
		await physics_frame
	var space := _player.get_world_3d().direct_space_state
	_ground = func(x: float, z: float) -> Vector3:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -300, z))
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		return hit.position if hit else Vector3(x, -9.0, z)

	_check("(setup) the player has a step height at all", float(_player.step_height) > 0.0,
		"step_height is %s" % str(_player.step_height))

	var climbed := await _probe_step(LOW, 300.0)
	_check("a %.0fcm kerb does not stop the player" % (LOW * 100.0), climbed > LOW * 0.6,
		"only rose %.3fm" % climbed)

	var walled := await _probe_step(TALL, 340.0)
	_check("...but a %.1fm wall still does" % TALL, walled < LOW,
		"climbed %.3fm of it — the step-up is lifting over anything" % walled)

	var flat := await _probe_step(FLAT, 380.0)
	_check("...and it does not fire on open ground", is_equal_approx(flat, 0.0),
		"lifted %.3fm with nothing in front of them" % flat)

	print("")
	print("STEP FAILURES: %d" % _fails)
	if _fails == 0:
		print("ALL STEP CHECKS PASS")
	quit(1 if _fails > 0 else 0)


## Stands the player in front of a box of `height`, points their velocity at
## it, and asks _step_up() directly for how much it lifts them.
##
## Driving the player by setting velocity and waiting does NOT work: their own
## _physics_process rebuilds velocity from input every frame, so the test would
## be measuring the input map rather than the step code.
func _probe_step(height: float, at_x: float) -> float:
	var base: Vector3 = _ground.call(at_x, 150.0)
	var box: StaticBody3D = null
	if height > 0.0:
		box = StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(6.0, height, 2.0)
		shape.shape = b
		box.add_child(shape)
		_level.add_child(box)
		box.global_position = base + Vector3(0, height * 0.5, -1.2)

	_player.global_position = base + Vector3.UP * 1.0
	_player.velocity = Vector3.ZERO
	for _i in 40:
		await physics_frame
	var start_y: float = _player.global_position.y
	_check("(setup) standing on the ground before the %.2fm box" % height,
		_player.is_on_floor(), "not on the floor, so the step cannot run")

	# Straight at it, at walking speed, and ask for one step.
	_player.velocity = Vector3(0.0, 0.0, -6.0)
	_player._step_up(1.0 / 60.0)
	var gained: float = _player.global_position.y - start_y
	if box != null:
		box.queue_free()
	await physics_frame
	return gained
