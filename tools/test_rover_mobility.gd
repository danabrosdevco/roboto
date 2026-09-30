extends SceneTree

# ─────────────────────────────────────────────
# WHAT THE ROVER CAN DRIVE OVER, AND UP.
#
# It was getting stuck on things a wheeled vehicle has no business being
# stopped by, and could not climb out of a pit. Two causes, both numbers:
#
#   step_height was the inherited 0.45 — an infantry kerb. Anything taller
#   than that is a wall to move_and_slide, and the rover's own `_blocked`
#   whiskers only see obstacles above ~0.75m, so a lip between 0.45 and 0.75
#   was in a dead zone: too tall to step over, too short to steer around. It
#   drove at it and stopped.
#
#   floor_max_angle was 40 degrees — LESS than the 45 infantry get by default.
#   A powered six-wheeler had worse traction than a man on foot, so the sides
#   of any pit steeper than 40 degrees were walls and it sat at the bottom.
#
# Now 0.75m and 50 degrees, which is the hull talking: the capsule is 0.85
# radius, so "what its wheels could roll over" is about 0.75.
#
# BUILT FROM BARE BOXES on purpose. A level would drag a navmesh, a squad and
# a director into a question that is only about the body and its two numbers.
# The rover is driven by writing velocity and calling _apply_motion(), which is
# the same path handle_movement takes.
#
# Both ceilings are asserted as well as both floors: a step_height large enough
# to climb a wall, or a floor angle that lets it drive up a cliff, would be its
# own bug and would make every level's geometry meaningless.
# ─────────────────────────────────────────────

const ROVER := "res://Character/characters/ai/vehicle_rover.tscn"
const DT := 1.0 / 60.0
## Travel that counts as having got past the step, of about 14m offered.
const CLEARED_M := 12.0
## Height gained that counts as having climbed the ramp.
const CLIMBED_M := 1.5

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  %s" if ok else "FAIL  %s  " + detail) % label)
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var r: CharacterBody3D = load(ROVER).instantiate()
	var step: float = r.step_height
	var angle: float = rad_to_deg(r.floor_max_angle)
	r.free()
	_check("(setup) the rover is authored to step higher than infantry", step > 0.45,
		"step_height is %.2f, the inherited default" % step)
	_check("(setup) ...and to grip steeper ground than infantry", angle > 45.0,
		"floor_max_angle is %.0f degrees" % angle)

	# ── LIPS ─────────────────────────────────────
	for h in [0.3, 0.5, 0.7]:
		var got: float = await _lip(h)
		_check("it rolls over a %.1fm step" % h, got > CLEARED_M, "travelled %.1fm" % got)
	var tall: float = await _lip(step + 0.25)
	_check("...and a step taller than step_height still stops it",
		tall < CLEARED_M, "travelled %.1fm over a %.2fm step" % [tall, step + 0.25])

	# ── SLOPES ───────────────────────────────────
	for deg in [30.0, 45.0, 50.0]:
		var up: float = await _ramp(deg)
		_check("it climbs a %.0f degree slope" % deg, up > CLIMBED_M, "gained %+.1fm" % up)
	var cliff: float = await _ramp(angle + 5.0)
	_check("...and a slope past floor_max_angle is a wall, not a hill",
		cliff < CLIMBED_M, "gained %+.1fm on %.0f degrees" % [cliff, angle + 5.0])

	print("")
	print("ALL ROVER MOBILITY CHECKS PASS" if _fails == 0
		else "%d ROVER MOBILITY CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


func _box(world: Node3D, at: Vector3, size: Vector3, pitch := 0.0) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1   # GameWorld, the layer the generated terrain uses
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	b.add_child(cs)
	world.add_child(b)
	b.global_position = at
	b.rotation.x = pitch


## Straight ahead at a steady 7 m/s with gravity on, the way handle_movement
## drives it.
func _drive(r: CharacterBody3D, frames: int) -> void:
	for _i in frames:
		r.velocity.x = 0.0
		r.velocity.z = -7.0
		r.velocity.y -= 9.8 * DT
		r._apply_motion()
		await physics_frame


## Metres of ground covered towards a square step of `h`.
func _lip(h: float) -> float:
	var world := Node3D.new()
	root.add_child(world)
	_box(world, Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	_box(world, Vector3(0, h * 0.5, -10), Vector3(30, h, 14))
	var r: CharacterBody3D = load(ROVER).instantiate()
	world.add_child(r)
	r.global_position = Vector3(0, 1.0, 6)
	await physics_frame
	var z0: float = r.global_position.z
	await _drive(r, 200)
	var gained: float = z0 - r.global_position.z
	world.queue_free()
	await physics_frame
	return gained


## Height gained driving at a slope of `deg`.
func _ramp(deg: float) -> float:
	var world := Node3D.new()
	root.add_child(world)
	_box(world, Vector3(0, -0.5, 6), Vector3(40, 1, 24))
	_box(world, Vector3(0, 6.0 * tan(deg_to_rad(deg)) - 0.5, -6.0),
		Vector3(40, 1, 24), deg_to_rad(deg))
	var r: CharacterBody3D = load(ROVER).instantiate()
	world.add_child(r)
	r.global_position = Vector3(0, 1.0, 8)
	await physics_frame
	var y0: float = r.global_position.y
	await _drive(r, 300)
	var climbed: float = r.global_position.y - y0
	world.queue_free()
	await physics_frame
	return climbed
