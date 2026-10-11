extends SceneTree

# ─────────────────────────────────────────────
# A LEAP IS AN ARC, NOT A LAUNCH.
#
# Reported as hives "shooting randomly up into the air". The hive itself has no
# weapon node and no starting_weapon_id, so it cannot fire at all — what goes up
# is what it hatches. Half of a nest's roll is a HOPPER, and a hopper leaps.
#
# compute_leap_velocity_fixed_speed() solves the arc by fixing the HORIZONTAL
# speed and letting the flight time fall out of it: time = distance / speed,
# where `distance` is the horizontal gap only. There is an apex cap, but it is
# minf() — it only ever SHORTENS the flight, and a short flight is precisely
# what makes the arc tall, because vy carries displacement.y / time. A target
# nearly overhead — something stood on a hive's 2.2m roof, a helicopter hovering
# over the hatch — leaves a horizontal gap of a couple of centimetres, a flight
# time under a millisecond, and a vy in the hundreds of metres per second.
#
# Nothing downstream caught it either: the body stays MovementState.LEAPING all
# the way up, so the landing check never runs, and fell_out_speed only notices
# the way back down.
#
#   godot --headless --path . --script res://tools/test_leap.gd
# ─────────────────────────────────────────────

const HOPPER := "res://Character/characters/ai/enemy_nest-chaser.tscn"

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var hop: Node3D = load(HOPPER).instantiate()
	root.add_child(hop)
	hop.global_position = Vector3.ZERO
	await process_frame

	var g: float = hop.gravity
	var apex := func(v: Vector3) -> float:
		return 0.0 if v.y <= 0.0 or g <= 0.0 else (v.y * v.y) / (2.0 * g)

	# ── THE REPORTED CASE ────────────────────────────────────────────
	# 4cm sideways, 3m up: the geometry of leaping at something directly
	# overhead. Before the clamp this returned vy ≈ 1240 m/s.
	var straight_up: Vector3 = hop.compute_leap_velocity_fixed_speed(Vector3(0.04, 3.0, 0.0), 16.5)
	_check("a target almost directly overhead does not launch the hopper",
		straight_up.y < 20.0, "vy %.1f m/s" % straight_up.y)
	_check("...and the arc stays inside its apex budget",
		apex.call(straight_up) <= hop.leap_max_apex + 3.0 + 0.01,
		"apex %.2f m, budget %.2f m" % [apex.call(straight_up), hop.leap_max_apex + 3.0])
	# Capping vy alone would have left this at the full 16.5 m/s, which is a
	# hopper hurling itself sixteen metres sideways to reach something directly
	# above it. The flight time is what gets lengthened, so the speed goes into
	# the part of the arc that is actually aimed at the target.
	_check("...and it jumps UP at it rather than sixteen metres sideways",
		Vector2(straight_up.x, straight_up.z).length() < 1.0,
		"horizontal %.2f m/s" % Vector2(straight_up.x, straight_up.z).length())

	# ── AND THE ORDINARY LEAPS ARE UNTOUCHED ─────────────────────────
	# The clamp is a ceiling, not a rewrite. A flat pounce and a hop onto a
	# waist-high ledge both sit well under the budget, so neither sees it.
	var flat: Vector3 = hop.compute_leap_velocity_fixed_speed(Vector3(6.0, 0.0, 0.0), 16.5)
	_check("a flat pounce still clears the ground",
		flat.y > 0.5 and apex.call(flat) <= hop.leap_max_apex + 0.01,
		"vy %.2f m/s, apex %.2f m" % [flat.y, apex.call(flat)])
	_check("...and still covers the distance it was aimed at",
		absf(Vector2(flat.x, flat.z).length() - 16.5) < 0.01,
		"horizontal %.2f m/s" % Vector2(flat.x, flat.z).length())

	var onto_ledge: Vector3 = hop.compute_leap_velocity_fixed_speed(Vector3(4.0, 1.2, 0.0), 16.5)
	_check("a hop up onto a ledge still gets above the ledge",
		apex.call(onto_ledge) > 1.2,
		"apex %.2f m for a 1.2m step" % apex.call(onto_ledge))

	# ── THE DEGENERATE INPUT IS STILL REFUSED OUTRIGHT ───────────────
	# Under 1cm of horizontal gap there is no arc to solve. leap_towards() sets
	# LEAPING before asking, and a zero velocity resolves on the next
	# _apply_motion — which is why this returns zero rather than something small.
	var on_top: Vector3 = hop.compute_leap_velocity_fixed_speed(Vector3(0.001, 2.0, 0.0), 16.5)
	_check("a target in the same spot is not a leap at all",
		on_top == Vector3.ZERO, str(on_top))

	hop.free()
	print("")
	if _fails == 0:
		print("test_leap: PASS")
	else:
		print("test_leap: %d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
