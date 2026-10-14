extends SceneTree

# ─────────────────────────────────────────────
# DEEP WATER, AND WHAT COMES OUT OF IT.
#
# Three behaviours, all of them seen going wrong on Causeway in one run:
#
#   1. A robot that falls into deep water DROWNS, instead of standing on the
#      bottom as a target nobody can reach and an objective nobody can finish.
#   2. A robot recovered from off the navmesh goes back WHERE IT FELL FROM.
#      The old recovery used the nearest mesh point, which from the middle of a
#      channel is a coin toss — and when it came up "far bank" the hostiles
#      reappeared behind the player and attacked from the rear.
#   3. A FLYER is not recovered at all. A Spotter Drone on station is
#      permanently 11-26 m off the mesh because that is what flying is, and it
#      was being teleported to the ground every four seconds. Six of the nine
#      recoveries in that Causeway log were this.
#
#   godot --headless --audio-driver Dummy --path . --script tools/test_water.gd
# ─────────────────────────────────────────────

const DRONE := "res://Character/characters/ai/spotter_drone.tscn"
const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fail += 1


func _init() -> void:
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false   # never write the real save
	root.add_child(world)
	for _i in 90:
		await physics_frame
	var player: Node3D = world.player
	var level: Node = player.get_parent()
	level.add_child(load("res://maps/causeway_level.tscn").instantiate())
	for _i in 120:
		await physics_frame

	# ── the terrain query itself ────────────────
	var terrain: Node = null
	for t in root.get_tree().get_nodes_in_group(&"terrain"):
		terrain = t
	_check("the terrain joins the 'terrain' group so it can be found at runtime",
		terrain != null,
		"nothing in the group" if terrain == null else terrain.name)
	if terrain == null:
		_finish()
		return

	var wl: float = terrain.data.water_level if terrain.data != null else 0.0
	_check("(setup) Causeway's terrain carries a water level", terrain.data != null,
		"water_level %.1f" % wl)

	# A point well under the surface, found by sampling the painted mask rather
	# than by guessing a coordinate that only means something on this map today.
	var wet := Vector3.ZERO
	var found := false
	for gx in range(-400, 401, 10):
		for gz in range(-400, 401, 10):
			var p := Vector3(float(gx), wl - 6.0, float(gz))
			if terrain.submersion_at(p) >= 4.0:
				wet = p
				found = true
				break
		if found:
			break
	_check("submersion_at finds deep water somewhere on the map", found,
		"%s is %.1fm down" % [wet.round(), terrain.submersion_at(wet)] if found else "none sampled")
	_check("...and reports dry ground as dry",
		is_equal_approx(terrain.submersion_at(Vector3(wet.x, wl + 50.0, wet.z)), 0.0),
		"50m above the surface")
	if not found:
		_finish()
		return

	# ── 1. a hostile in deep water drowns ───────
	var bot = load(RIFLE).instantiate()
	level.add_child(bot)
	await process_frame
	bot.faction = Enums.Factions.ENEMY
	bot.player = player
	bot.ai_manager = world.ai_manager
	bot.global_position = wet
	bot.exempt_from_culling(1000.0)   # so its brain actually ticks out here
	var drowned := false
	for _i in 480:
		await physics_frame
		if not bot.alive or bot.downed:
			drowned = true
			break
	_check("a hostile dropped into deep water drowns", drowned,
		"still alive after 8s" if not drowned else "")

	# ── 3. a flyer is left alone ────────────────
	var drone = load(DRONE).instantiate()
	level.add_child(drone)
	await process_frame
	drone.faction = Enums.Factions.ENEMY
	drone.player = player
	drone.ai_manager = world.ai_manager
	var station := Vector3(wet.x, wl + 15.0, wet.z)
	drone.global_position = station
	drone.exempt_from_culling(1000.0)
	_check("(setup) the drone says being off the navmesh is normal for it",
		drone.off_navmesh_is_normal())

	# THE RECOVERY IS CALLED DIRECTLY, not waited for. A drone parks itself when
	# the campaign is not in a mission (SpotterDrone._parked), and a parked drone
	# descends under gravity — so watching its altitude in a bare level measures
	# parking, not the adrift fix. An earlier version of this test did exactly
	# that and failed on correct behaviour. Ten polls of two seconds each is far
	# past adrift_seconds, so an unguarded recovery would certainly have fired.
	# A FRAME BETWEEN EACH. _tick_adrift goes through _take_snap_query, a
	# STATIC per-frame budget shared by every robot — call it in a tight loop
	# and the budget is spent, every call after it returns early, nothing moves
	# and the test passes for the wrong reason. The control below caught exactly
	# that.
	for _i in 10:
		await physics_frame
		drone.global_position = station
		drone._tick_adrift(2.0)
	var held: bool = drone.global_position.is_equal_approx(station)
	_check("a flying drone is never pulled back onto the navmesh", held,
		"held station" if held else "recovery dragged it to %s" % drone.global_position.round())
	_check("...and it did not drown while flying over water", drone.alive and not drone.downed)

	# POSITIVE CONTROL. The same treatment on a walker MUST move it, or the test
	# above is passing because the recovery is broken rather than because the
	# guard works.
	var walker = load(RIFLE).instantiate()
	level.add_child(walker)
	await process_frame
	walker.faction = Enums.Factions.ENEMY
	walker.player = player
	walker.ai_manager = world.ai_manager
	walker.drown_depth = 0.0            # drowning off, so this isolates recovery
	walker.global_position = station
	walker.exempt_from_culling(1000.0)
	for _i in 10:
		await physics_frame
		walker.global_position = station
		walker._tick_adrift(2.0)
	var moved: bool = not walker.global_position.is_equal_approx(station)
	_check("(control) a GROUND robot in the same spot IS recovered", moved,
		("recovered to %s, so the guard above means something" % walker.global_position.round()) if moved
			else "stayed put — the recovery is not firing, so the drone check proves nothing")

	_finish()


func _finish() -> void:
	print("")
	print("WATER FAILURES: %d" % _fail)
	print("ALL WATER CHECKS PASS" if _fail == 0 else "WATER CHECKS FAILED")
	quit(1 if _fail > 0 else 0)
