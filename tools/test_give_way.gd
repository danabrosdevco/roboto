extends SceneTree

# ─────────────────────────────────────────────
# TWO ROBOTS THAT MEET IN A GAP HAVE TO GET PAST EACH OTHER.
#
# The reported symptom was a pair welded together — usually a rover across
# somebody's route — that only came apart when one of them was killed. The old
# recovery waited STUCK_CHECK_INTERVAL (three seconds), then spent a NAVIGATION
# query on a point a few metres to one side, which the navmesh was free to route
# straight back through the other robot because it cannot see robots at all.
# Both of them rolled randf() for a side independently, so they could keep
# picking the same one, and at nine seconds they gave up and stood still.
#
# WHAT THIS DRIVES. The velocity is set by hand each frame, which is exactly what
# the navigation layer does for a moving robot — it picks a direction and the body
# walks it. Everything downstream of that is the real thing: real physics contact,
# the real _apply_motion() chain, the real _damp_shoving() that discovers the
# contact and the real _tick_give_way() that acts on it. Pathfinding and combat
# action rolls are separate systems with their own suites, and letting them decide
# whether this robot feels like walking today is how a test of give-way ends up
# measuring something else.
#
#   godot --headless --path . --script res://tools/test_give_way.gd
# ─────────────────────────────────────────────

const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const ROVER := "res://Character/characters/ai/vehicle_rover.tscn"

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
	_level.add_child(load("res://maps/valley_level.tscn").instantiate())
	for _i in 30:
		await physics_frame

	var space := _player.get_world_3d().direct_space_state
	_ground = func(x: float, z: float) -> Vector3:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -300, z))
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		return hit.position if hit else Vector3(x, -9.0, z)

	await _test_sizes()
	await _test_yield()
	await _test_rule()

	print("")
	print("ALL GIVE-WAY CHECKS PASS" if _fails == 0 else "%d GIVE-WAY CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


# ─────────────────────────────────────────────
# EACH CHASSIS KNOWS ITS OWN SIZE
# ─────────────────────────────────────────────
# Measured off the collision shape rather than authored, so that it cannot drift
# away from the shape it describes — and so the pair can agree which of them is
# bigger without conferring. These are also the real clearance numbers: a soldier
# is a METRE across, not the 0.4 its visual suggests, because its capsule carries
# no overrides and takes Godot's 0.5 default radius.
func _test_sizes() -> void:
	var want := {
		"res://Character/characters/ai/soldier_rifle.tscn": 0.5,
		"res://Character/characters/ai/enemy_chaser.tscn": 0.5,
		"res://Character/characters/ai/walker.tscn": 0.85,
		"res://Character/characters/ai/vehicle_rover.tscn": 0.85,
		"res://Character/characters/ai/vehicle_reclaimer.tscn": 1.55,
	}
	for path in want:
		var b: Node3D = load(path).instantiate()
		_level.add_child(b)
		b.global_position = (_ground.call(260.0, 260.0) as Vector3) + Vector3.UP * 80.0
		for _i in 4:
			await physics_frame
		_check("%s measures itself at %.2f" % [path.get_file(), want[path]],
			is_equal_approx(b.body_radius, want[path]), "got %.2f" % b.body_radius)
		b.free()


# ─────────────────────────────────────────────
# A SOLDIER WALKED INTO A ROVER GETS AROUND IT
# ─────────────────────────────────────────────
func _test_yield() -> void:
	var at := (_ground.call(300.0, 250.0) as Vector3) + Vector3.UP
	var rover: Node3D = load(ROVER).instantiate()
	rover.faction = Enums.Factions.ENEMY
	_level.add_child(rover)
	rover.global_position = at

	var sol: Node3D = load(RIFLE).instantiate()
	sol.faction = Enums.Factions.ENEMY
	_level.add_child(sol)
	sol.global_position = at + Vector3(0.0, 0.0, 2.1)
	for _i in 20:
		await physics_frame

	# Both bodies driven by this test, not by their own AI. The rover is the
	# obstacle: one that wandered off would let this pass by accident.
	sol.set_physics_process(false)
	rover.set_physics_process(false)
	var rover_start: Vector3 = rover.global_position
	var start: Vector3 = sol.global_position

	var gave_way := false
	var tries_used := 0
	var worst_step := 0.0
	var prev: Vector3 = sol.global_position
	for _f in 180:                                    # three seconds
		# What the navigation layer would be asking for: straight at the rover.
		sol.movement_state = sol.MovementState.MOVING
		sol.velocity = Vector3(0.0, -2.0, -sol.move_speed)
		sol._apply_motion()
		if sol.get("_give_way_t") > 0.0:
			gave_way = true
		tries_used = maxi(tries_used, int(sol.get("_give_way_tries")))
		await physics_frame
		worst_step = maxf(worst_step, Vector2(
			sol.global_position.x - prev.x, sol.global_position.z - prev.z).length())
		prev = sol.global_position

	var sideways: float = absf(sol.global_position.x - start.x)
	_check("a soldier driven into a rover gives way", gave_way)
	_check("...sideways, which is the direction that gets it past",
		sideways > 1.0, "moved %.2f m across" % sideways)
	_check("...within its sidestep budget, not by exhausting it",
		tries_used > 0 and tries_used < sol.GIVE_WAY_MAX_TRIES,
		"%d of %d used" % [tries_used, sol.GIVE_WAY_MAX_TRIES])
	_check("the rover, which outweighs it, never budged",
		rover.global_position.distance_to(rover_start) < 0.3,
		"rover moved %.2f m" % rover.global_position.distance_to(rover_start))

	# THE POINT OF DOING IT THIS WAY. The old recovery's cost was a navigation
	# query per attempt; this must not have spent one, or it is the same bill
	# arriving four tenths of a second sooner.
	_check("...and it cost no path re-plan", int(sol.get("_stuck_retry_count")) == 0,
		"_stuck_retry_count = %d" % int(sol.get("_stuck_retry_count")))

	# THE SIDESTEP SETS THE VELOCITY, IT DOES NOT ADD TO IT.
	#
	# It used to add — velocity.x += side.x, every frame for the whole 0.7s of
	# the yield — on top of a velocity the movement code lerps towards its
	# target rather than overwriting. So the nudge compounded: measured ramping
	# 10 -> 35 -> 37 m/s over forty frames and carrying the robot twenty metres,
	# which read in game as two robots brushing past each other and one of them
	# being fired across the map. Nothing downstream caught it, because
	# _damp_shoving only caps a body that is still in contact and by then they
	# were long apart. A sidestep can never be faster than walking.
	var step_budget: float = sol.move_speed * maxf(1.0, sol.GIVE_WAY_SIDE_SPEED) \
		* sol.get_physics_process_delta_time() * 1.35
	_check("...at walking pace, never faster", worst_step <= step_budget,
		"worst step %.3f m, budget %.3f m (%.1f m/s)" % [
			worst_step, step_budget, worst_step / sol.get_physics_process_delta_time()])

	sol.free()
	rover.free()


# ─────────────────────────────────────────────
# EXACTLY ONE OF ANY PAIR MOVES
# ─────────────────────────────────────────────
# The rule both sides evaluate independently. If it ever answered the same for
# both, they would mirror each other forever — which is the failure it replaces.
func _test_rule() -> void:
	var at := (_ground.call(320.0, 250.0) as Vector3) + Vector3.UP
	var sol: Node3D = load(RIFLE).instantiate()
	var rover: Node3D = load(ROVER).instantiate()
	var sol2: Node3D = load(RIFLE).instantiate()
	for n in [sol, rover, sol2]:
		_level.add_child(n)
	sol.global_position = at
	rover.global_position = at + Vector3(6.0, 0.0, 0.0)
	sol2.global_position = at + Vector3(12.0, 0.0, 0.0)
	for _i in 6:
		await physics_frame

	_check("a soldier yields to a rover", sol._should_yield_to(rover))
	_check("...and a rover does not yield to a soldier", not rover._should_yield_to(sol))
	_check("two of the same size: exactly one gives way",
		sol._should_yield_to(sol2) != sol2._should_yield_to(sol),
		"a->b %s, b->a %s" % [str(sol._should_yield_to(sol2)), str(sol2._should_yield_to(sol))])
	for n in [sol, rover, sol2]:
		n.free()
