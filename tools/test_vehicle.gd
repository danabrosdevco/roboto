extends SceneTree

# ─────────────────────────────────────────────
# VEHICLE — the rover drives, aims and goes down like a vehicle, and the
# campaign treats it as a two-seat frame with a turret.
#
# It is a Soldier that drives (rover.gd): a heading it has to steer, a turret
# that traverses on its own, wheels and suspension drawn from what the body
# really did. These pin the parts that make it a vehicle rather than a robot
# on invisible legs — nothing here is tuning.
#
# Boots the real world with autosave off: it reads the save on this machine
# and never writes it. The rovers drive about the valley, well away from base.
# ─────────────────────────────────────────────

const ROVER := "res://Character/characters/ai/vehicle_rover.tscn"
const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"

var _fails := 0
var _catalogue: ItemCatalogue
var _mgr: Node


func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  %s" if ok else "FAIL  %s  " + detail) % label)
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


func _spawn(level: Node, at: Vector3, yaw: float, weapon_id: StringName = &"machine_gun") -> Soldier:
	var r: Soldier = load(ROVER).instantiate()
	r.faction = Enums.Factions.ALLIED
	if weapon_id != &"":
		r.equip_weapon_scene(_catalogue.item(weapon_id).ai_scene)
	level.add_child(r)
	r.global_position = at
	r.rotation.y = yaw
	# As the spawners do. Unregistered, a robot has no player to measure
	# anything against and its brain never runs.
	if _mgr != null:
		_mgr.register_enemy(r)
	return r


func _hull_forward(r: Node3D) -> Vector3:
	var f := -r.global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# Lowest and highest point of what is drawn of a robot, in world space.
func _drawn_span(body: Soldier) -> Vector2:
	var lo := INF
	var hi := -INF
	var stack: Array = body.visible_pieces.duplicate()
	while not stack.is_empty():
		var n = stack.pop_back()
		if n == null or not (n is Node3D) or not (n as Node3D).is_visible_in_tree():
			continue
		if n is CSGShape3D or n is MeshInstance3D:
			var box: AABB = (n as Node3D).global_transform * (n as VisualInstance3D).get_aabb()
			lo = minf(lo, box.position.y)
			hi = maxf(hi, box.end.y)
			continue
		stack.append_array(n.get_children())
	return Vector2(lo, hi)


# The underside of the hull itself — the CSG box, not the wheels round it.
func _hull_bottom(body: Soldier) -> float:
	var hull: VisualInstance3D = body.rig.get_node("Hull")
	return (hull.global_transform * hull.get_aabb()).position.y


# A stretch of solid wall facing south with open ground in front of it: where
# the wall's face is, at ground level, or INF. Searched for rather than written
# down, so an edit to the valley moves the test with it.
func _find_wall(space: PhysicsDirectSpaceState3D, ground_at: Callable) -> Vector3:
	for z in [70.0, 30.0, 110.0]:
		for xi in range(150, 340, 2):
			var p: Vector3 = ground_at.call(float(xi), z) + Vector3.UP * 0.8
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3(0, 0, 6)))
			if hit.is_empty() or absf((hit.normal as Vector3).z + 1.0) > 0.05:
				continue
			# Solid for a few metres either side, not a post or a door frame.
			var solid := true
			for dx in [-2.0, 2.0]:
				var q: Vector3 = p + Vector3(dx, 0, 0)
				if space.intersect_ray(PhysicsRayQueryParameters3D.create(q, q + Vector3(0, 0, 6))).is_empty():
					solid = false
			if solid:
				var face: Vector3 = hit.position
				return ground_at.call(face.x, face.z - 0.5) + Vector3(0, 0, 0.5)
	return Vector3.INF


func _deck_under(body: Node3D) -> float:
	var q := PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP * 5.0,
		body.global_position + Vector3.DOWN * 20.0)
	q.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else NAN


func _init() -> void:
	await process_frame
	_catalogue = load(CATALOGUE)
	var world_scene: Node = load("res://Env/world.tscn").instantiate()
	world_scene.get_node("CampaignManager").autosave = false
	root.add_child(world_scene)
	for _i in 90:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	var level: Node = player.get_parent()
	var cm: CampaignManager = world_scene.get_node("CampaignManager")
	_mgr = _find(root, "AIManager")
	var valley = load("res://maps/valley_level.tscn").instantiate()
	level.add_child(valley)
	for _i in 20:
		await physics_frame
	var space := player.get_world_3d().direct_space_state
	var ground_at := func(x: float, z: float) -> Vector3:
		var gq := PhysicsRayQueryParameters3D.create(Vector3(x, 300, z), Vector3(x, -300, z))
		gq.exclude = [player.get_rid()]   # or anything placed on the player stands on its head
		var hit := space.intersect_ray(gq)
		return hit.position if hit else Vector3(x, -9.0, z)
	player.global_position = ground_at.call(290.0, 160.0) + Vector3.UP

	# ── THE SCENE ────────────────────────────────
	var rover := _spawn(level, ground_at.call(300.0, 60.0) + Vector3.UP * 0.9, 0.0)
	for _i in 30:
		await physics_frame
	_check("(setup) a rover is a Soldier, so the squad and spawners take it", rover is Soldier)
	var mount: Node3D = rover.weapon_mount
	_check("the turret carries the fitted machine gun, and only that", rover.weapon != null
		and mount.get_child_count() == 1 and mount.get_child(0) == rover.weapon,
		"mount has %d children" % mount.get_child_count())
	var bare := _spawn(level, ground_at.call(360.0, 60.0) + Vector3.UP * 0.9, 0.0, &"")
	await physics_frame
	await physics_frame
	_check("...and a rover with nothing fitted shows an empty turret", bare.weapon == null
		and bare.weapon_mount.get_child_count() == 0)
	if _mgr != null:
		_mgr.deregister_enemy(bare)
	bare.queue_free()

	# ── IT DRIVES ────────────────────────────────
	# Sent somewhere off to its right. A robot on legs turns on the spot and
	# walks there; this one has to roll forward to turn.
	# Snapped onto the navmesh: somewhere it can actually get to.
	var on_nav := func(p: Vector3) -> Vector3:
		return NavigationServer3D.map_get_closest_point(rover.nav_agent.get_navigation_map(), p)
	var goal: Vector3 = on_nav.call(ground_at.call(326.0, 58.0))
	rover.move_to(goal)
	var slip := 0.0
	var turn_standing := 0.0
	var arrived := -1
	var prev_yaw := rover.rotation.y
	for i in 900:
		await physics_frame
		var fwd := _hull_forward(rover)
		var v := Vector3(rover.velocity.x, 0.0, rover.velocity.z)
		slip = maxf(slip, absf(v.dot(fwd.cross(Vector3.UP))))
		var yaw_rate := absf(wrapf(rover.rotation.y - prev_yaw, -PI, PI)) * 60.0
		prev_yaw = rover.rotation.y
		if v.length() < 0.2:
			turn_standing = maxf(turn_standing, yaw_rate)
		if _flat(rover.global_position - goal).length() <= rover.arrival_radius + 0.5:
			arrived = i
			break
	print("      drove to a point %.0fm off to its side: arrived at frame %d, sideways speed at most %.2f m/s" % [
		_flat(goal - Vector3(300.0, 0.0, 60.0)).length(), arrived, slip])
	_check("it gets to a point off to its side", arrived >= 0)
	_check("...moving only along its heading, never sideways", slip < 0.5, "%.2f m/s sideways" % slip)
	_check("...and it never turns on the spot", turn_standing < 0.15, "%.2f rad/s standing still" % turn_standing)

	for _i in 90:
		await physics_frame
	# Somewhere just behind it: backed onto, not driven round to.
	var yaw_before := rover.rotation.y
	var behind: Vector3 = rover.global_position + rover.global_transform.basis.z * 8.0
	behind = on_nav.call(ground_at.call(behind.x, behind.z))
	rover.move_to(behind)
	var backing := 0
	var forwards := 0
	arrived = -1
	for i in 480:
		await physics_frame
		var s := Vector3(rover.velocity.x, 0.0, rover.velocity.z).dot(_hull_forward(rover))
		if s < -0.3:
			backing += 1
		elif s > 0.3:
			forwards += 1
		if _flat(rover.global_position - behind).length() <= rover.arrival_radius + 0.5:
			arrived = i
			break
	var turned := rad_to_deg(absf(wrapf(rover.rotation.y - yaw_before, -PI, PI)))
	print("      8m behind: %d frames reversing, %d forwards, turned %.0f degrees" % [backing, forwards, turned])
	_check("it reverses onto a spot just behind it", arrived >= 0 and backing > forwards * 3,
		"arrived=%d back=%d fwd=%d" % [arrived, backing, forwards])
	_check("...without turning round to get there", turned < 45.0, "%.0f degrees" % turned)

	# ── A WALL ───────────────────────────────────
	# Parked nose-first against one and sent somewhere behind it. A car cannot
	# turn without rolling, so it used to sit there pushing until the 3-second
	# stuck check fired — and in a squad it sat there for good: every re-order
	# restarted that check. It takes a leg of a three-point turn at once now.
	var wall := _find_wall(space, ground_at)
	_check("(setup) found a wall in the valley to park against", wall != Vector3.INF)
	if wall != Vector3.INF:
		var parked := _spawn(level, wall + Vector3(0, 0.9, -2.1), PI)   # facing +Z, nose 0.4m off it
		for _i in 20:
			await physics_frame
		var back: Vector3 = on_nav.call(ground_at.call(wall.x, wall.z - 17.0))
		parked.move_to(back)
		var pinned := 0.0
		var lit_backing := false
		var lit_forward := false
		var spun := 0.0
		arrived = -1
		var last := parked.global_position
		var spin_node: Node3D = parked.wheels[0].get_node("Spin")
		var spin_before: Basis = spin_node.transform.basis
		for i in 600:
			await physics_frame
			var moved := _flat(parked.global_position - last).length() * 60.0
			last = parked.global_position
			if moved < 0.2:
				pinned += 1.0 / 60.0
			var s := Vector3(parked.velocity.x, 0.0, parked.velocity.z).dot(_hull_forward(parked))
			if s < -0.5 and parked.reverse_lamps[0].visible:
				lit_backing = true
			if s > 0.5 and parked.reverse_lamps[0].visible:
				lit_forward = true
			spun = maxf(spun, rad_to_deg(spin_node.transform.basis.get_rotation_quaternion().angle_to(spin_before.get_rotation_quaternion())))
			if _flat(parked.global_position - back).length() <= parked.arrival_radius + 0.5:
				arrived = i
				break
		print("      nose to a wall, sent 17m behind: arrived at frame %d, sat pinned %.1fs, %d turn legs" % [
			arrived, pinned, parked._manoeuvres])
		_check("nose to a wall and sent behind it, it backs off and gets there", arrived >= 0)
		_check("...without sitting there pushing first", pinned < 0.6, "%.1fs pinned" % pinned)
		_check("...its reverse lamps lit while it backs up", lit_backing)
		_check("...and dark when it drives forward", not lit_forward)
		_check("its wheels turn as it drives", spun > 30.0, "%.0f degrees" % spun)
		if _mgr != null:
			_mgr.deregister_enemy(parked)
		parked.queue_free()

		# The playtest case: in a squad, with the player moving about behind it,
		# so the squad re-orders it all the time.
		var follower := _spawn(level, wall + Vector3(0, 0.9, -2.1), PI)
		var squad := Squad.new()
		squad.callsign = "WALLTEST"
		squad.squad_members = [follower] as Array[Soldier]
		level.add_child(squad)
		var centre: Vector3 = ground_at.call(wall.x + 4.0, wall.z - 18.0)
		player.global_position = centre + Vector3.UP
		for _i in 10:
			await physics_frame
		squad.follow(player)
		var off_wall := -1
		for i in 420:
			var a := i / 60.0 * 1.3
			player.global_position = ground_at.call(centre.x + cos(a) * 4.0, centre.z + sin(a) * 2.5) + Vector3.UP
			await physics_frame
			if off_wall < 0 and follower.global_position.z < wall.z - 5.0:
				off_wall = i
		print("      in a squad, player moving about behind it: off the wall at frame %d" % off_wall)
		_check("...and in a squad being re-ordered all the time, it still gets off the wall", off_wall >= 0 and off_wall < 300,
			"frame %d" % off_wall)
		if _mgr != null:
			_mgr.deregister_enemy(follower)
		follower.queue_free()
		squad.queue_free()
		player.global_position = ground_at.call(290.0, 160.0) + Vector3.UP

	# ── THE TURRET ───────────────────────────────
	# A hostile off its right side. The hull is held still; the turret has to
	# traverse onto it, at a rate, and the gun waits until it is on.
	var right := _hull_forward(rover).cross(Vector3.UP)
	var at: Vector3 = rover.global_position + right * 22.0
	var dummy: Soldier = load("res://Character/characters/ai/enemy_chaser.tscn").instantiate()
	dummy.faction = Enums.Factions.ENEMY
	level.add_child(dummy)
	dummy.global_position = ground_at.call(at.x, at.z) + Vector3.UP * 1.05
	if _mgr != null:
		_mgr.register_enemy(dummy)
	dummy.set_physics_process(false)   # a target, not a fight
	dummy.health = 99999
	dummy.max_health = 99999
	for _i in 5:
		await physics_frame
	rover.hold_still()
	var hull_yaw := rover.rotation.y
	var rounds: int = rover.weapon.magazine_current
	rover.trigger_combat(dummy)
	var off_early := 0.0
	var fired_off_target := false
	var fired := false
	for i in 240:
		await physics_frame
		var to := dummy.global_position - rover.global_position
		to.y = 0.0
		var off := rad_to_deg(rover._turret_forward().angle_to(to.normalized()))
		if i == 18:
			off_early = off
		if rover.weapon.magazine_current < rounds:
			fired = true
			if off > rover.fire_cone_degrees + 2.0:
				fired_off_target = true
		rounds = rover.weapon.magazine_current
	var off_end := rad_to_deg(rover._turret_forward().angle_to((dummy.global_position - rover.global_position) * Vector3(1, 0, 1)))
	print("      turret: %.0f degrees off after 0.3s, %.1f after 4s" % [off_early, off_end])
	_check("the turret swings onto a target beside it", off_end <= rover.fire_cone_degrees, "%.1f degrees off" % off_end)
	_check("...at a rate, not in a snap", off_early > 40.0, "%.0f degrees off after 0.3s" % off_early)
	_check("...while the hull stays where it is pointed", absf(wrapf(rover.rotation.y - hull_yaw, -PI, PI)) < deg_to_rad(1.0))
	_check("...and it looks the way the turret points", rover._sight_forward().dot(rover._turret_forward()) > 0.999)
	_check("it opens fire once the gun is on", fired)
	_check("...and not a round before", not fired_off_target)
	rover.release_hold()
	if _mgr != null:
		_mgr.deregister_enemy(dummy)
	dummy.queue_free()

	# ── THE LAUNCHER LOBS ONTO ITS MARK ──────────
	var lobber := _spawn(level, ground_at.call(300.0, 110.0) + Vector3.UP * 0.9, 0.0, &"grenade_launcher")
	for _i in 30:
		await physics_frame
	var mark: Vector3 = ground_at.call(300.0, 80.0)
	var before := {}
	for n in lobber.get_parent().get_children():
		before[n] = true
	lobber.weapon.fire(mark)
	var round_node: Node3D = null
	for n in lobber.get_parent().get_children():
		if not before.has(n) and n is RigidBody3D:
			round_node = n
	var landed := Vector3.INF
	var apex := -INF
	if round_node != null:
		for _i in 300:
			await physics_frame
			if not is_instance_valid(round_node) or round_node._exploded:
				break
			landed = round_node.global_position
			apex = maxf(apex, landed.y)
	var miss := _flat(landed - mark).length() if landed != Vector3.INF else INF
	print("      a lob at 30m came down %.1fm from its mark, %.1fm up at the top" % [miss, apex - mark.y])
	_check("the grenade launcher lobs a round that comes down on its mark", miss < 2.5, "%.1fm off" % miss)
	_check("...on an arc, not a flat shot", apex - mark.y > 1.5, "apex %.1fm" % (apex - mark.y))
	if _mgr != null:
		_mgr.deregister_enemy(lobber)
	lobber.queue_free()

	# ── A PACK OF THEM ───────────────────────────
	# Four rovers in one squad, which is how they get used — armour pooled and
	# moved together. They used to converge on slots 2.6m apart (infantry
	# spacing, for a 1.5m hull that counts as parked anywhere within 3.5m),
	# find each other only by collision, and spend the move shunting apart:
	# _is_wall() ignores CharacterBody3D, so nothing steered around a
	# squadmate and the first sign of one was a three-point turn starting.
	#
	# The measure is the closest any two got at any point, and how much of the
	# move was spent reversing out of each other instead of driving.
	var pack: Array[Soldier] = []
	for i in 4:
		var spot: Vector3 = ground_at.call(292.0 + i * 3.0, 205.0 + (i % 2) * 2.0)
		pack.append(_spawn(level, spot + Vector3.UP * 0.9, PI))
	var pack_squad := Squad.new()
	pack_squad.callsign = "PACKTEST"
	pack_squad.squad_members = pack
	level.add_child(pack_squad)
	player.global_position = ground_at.call(296.0, 200.0) + Vector3.UP
	for _i in 20:
		await physics_frame
	pack_squad.follow(player)
	# Two numbers, because they start in a clump on purpose — that is how they
	# come off a spawn point. `closest` covers the untangle as well, `settled`
	# only once they have had two seconds to sort themselves out.
	var closest := INF
	var settled := INF
	var closest_at := 0
	var shunting := 0
	var start_gap: float = _flat(pack[0].global_position - player.global_position).length()
	for i in 900:
		# Walk them up the valley, far enough that they have to drive rather
		# than shuffle in place.
		player.global_position = ground_at.call(296.0, 200.0 - i / 900.0 * 45.0) + Vector3.UP
		await physics_frame
		for a in pack.size():
			if pack[a]._manoeuvre_t > 0.0 or pack[a]._pinned_t > 0.0:
				shunting += 1
			for b in range(a + 1, pack.size()):
				var gap: float = _flat(pack[a].global_position - pack[b].global_position).length()
				if gap < closest:
					closest = gap
					closest_at = i
				if i >= 120:
					settled = minf(settled, gap)
	var trailing := 0.0
	for r in pack:
		trailing = maxf(trailing, _flat(r.global_position - player.global_position).length())
	var shunt_share: float = float(shunting) / (900.0 * pack.size())
	# Every rover's nearest neighbour once they are where they were going: the
	# number the wider slots move. Measured, not guessed — with infantry-width
	# slots a pack of four settles about 4.7m apart and trails the squad by
	# 38m; with vehicle-width slots it is 6.8m apart and 22m back.
	var spread := 0.0
	for a in pack.size():
		var nearest := INF
		for b in pack.size():
			if a != b:
				nearest = minf(nearest, _flat(pack[a].global_position - pack[b].global_position).length())
		spread += nearest
	spread /= float(pack.size())
	print("      a pack of 4: closest %.1fm at frame %d (%.1fm once sorted out), %.1fm apart at the end, %.0f%% shunting, furthest %.0fm behind"
		% [closest, closest_at, settled, spread, shunt_share * 100.0, trailing])
	_check("a pack of rovers stands off each other rather than sharing a slot",
		spread > 5.5, "%.1fm between hulls" % spread)
	_check("...never hull to hull, even untangling from a clump", closest > 1.7,
		"closest %.1fm" % closest)
	_check("...without spending the move reversing out of each other", shunt_share < 0.25,
		"%.0f%% of the move" % (shunt_share * 100.0))
	_check("...and still moves as a pack rather than scattering", trailing < 30.0,
		"furthest %.0fm behind, started %.0fm" % [trailing, start_gap])
	for r in pack:
		if _mgr != null:
			_mgr.deregister_enemy(r)
		r.queue_free()
	pack_squad.queue_free()
	player.global_position = ground_at.call(290.0, 160.0) + Vector3.UP
	for _i in 20:
		await physics_frame

	# ── KNOCKED OUT ──────────────────────────────
	var live_turret: float = rover.turret.rotation.y
	rover.apply_damage(99999, player)
	for _i in 20:
		await physics_frame
	var span := _drawn_span(rover)
	var deck := _deck_under(rover)
	# Each wheel against the ground under IT — on a slope that is not the ground
	# under the hull — from its centre and radius. A tyre's bounding box, once
	# the wheel has spun to some angle, pokes up to 15cm below the rubber.
	var sunk := -INF
	var hovering := INF
	for w: Node3D in rover.wheels:
		var q := PhysicsRayQueryParameters3D.create(w.global_position + Vector3.UP * 2.0, w.global_position + Vector3.DOWN * 4.0)
		q.exclude = [rover.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var gap: float = (w.global_position.y - rover.wheel_radius) - (hit.position as Vector3).y
		sunk = maxf(sunk, -gap)
		hovering = minf(hovering, gap)
	var belly: float = _hull_bottom(rover) - deck
	print("      knocked out: deepest wheel %.2fm into the ground, belly %+.2fm, drawn top %+.2fm" % [sunk, belly, span.y - deck])
	_check("a knocked-out rover is down, not destroyed", rover.downed)
	_check("...its collider still lying along the hull, not stood on end", not rover._collider_flattened)
	# A WRECK LEANS. It goes over on one side now, so the low wheels dig in and
	# the high ones sit proud — every wheel exactly on the deck is what a
	# PARKED rover looks like, which was the whole complaint. What still has to
	# hold is that nothing floats and the hull is not buried in the terrain,
	# because hiding the model in the ground is the trick this replaced.
	_check("...and it lies on the deck at an angle, neither floating nor buried",
		sunk < 0.3 and hovering < 0.2 and belly < 0.3 and belly > -0.45,
		"deepest wheel %.2fm in, nearest %.2fm up, belly %+.2fm" % [sunk, hovering, belly])
	var lean := rad_to_deg(rover.rig.global_transform.basis.y.angle_to(Vector3.UP))
	_check("...canted over, so the silhouette is not a rover waiting for orders",
		lean > 6.0, "%.0f degrees off level" % lean)
	_check("...its turret knocked off the bearing it was aiming on",
		absf(rad_to_deg(wrapf(rover.turret.rotation.y - live_turret, -PI, PI))) > 30.0,
		"%.0f degrees" % rad_to_deg(wrapf(rover.turret.rotation.y - live_turret, -PI, PI)))
	_check("...and the barrel dropped below anything it could aim at alive",
		rover.gun_pivot.rotation.x < deg_to_rad(rover.gun_min_pitch_degrees),
		"%.0f degrees, live limit %.0f" % [rad_to_deg(rover.gun_pivot.rotation.x), rover.gun_min_pitch_degrees])
	for _i in 180:
		await physics_frame
	span = _drawn_span(rover)
	_check("...and once settled, most of it still shows", span.y - deck > 0.8, "top %+.2fm" % (span.y - deck))

	# ── THE CAMPAIGN ─────────────────────────────
	var frame: ChassisDefinition = _catalogue.chassis_def(&"rover")
	_check("the rover is in the catalogue as a two-seat turret frame", frame != null and frame.supply == 2 and frame.turret)
	var state := CampaignState.new()
	state.armoury = Armoury.new()
	state.catalogue = _catalogue
	state.award(2000)
	var rec := state.recruit(frame)
	_check("a new rover comes with the machine gun on its turret", rec != null and rec.weapon_ids[0] == &"machine_gun")
	_check("...and takes two seats", rec != null and state.supply_of(rec) == 2 and not rec.benched)
	for id in [&"m4", &"grenade_launcher", &"machine_gun"]:
		state.armoury.add(id)
	_check("a rifle does not go on a turret", not state.can_fit(rec, _catalogue.item(&"m4")))
	_check("...the grenade launcher does", state.can_fit(rec, _catalogue.item(&"grenade_launcher")))
	var grunt := state.recruit(_catalogue.chassis_def(&"soldier"))
	_check("turret weapons do not go on a soldier", not state.can_fit(grunt, _catalogue.item(&"machine_gun")))
	_check("...nor on you", not state.can_fit(state.player_record, _catalogue.item(&"machine_gun")))
	var second := state.recruit(frame)
	_check("a rover with one free seat waits on the bench", second != null and second.benched,
		"%d of %d seats used" % [state.supply_used(), state.supply_cap])
	var unlocks_it := cm.missions.filter(func(m): return m != null and m.unlocks.has(&"rover"))
	_check("the rover is unlocked by clearing the basin, with the gun it comes with",
		unlocks_it.size() == 1 and unlocks_it[0].id == &"basin_1_anchor"
		and unlocks_it[0].unlocks.has(&"machine_gun"), str(unlocks_it.map(func(m): return str(m.id))))
	# The grenade launcher is one of the late, high-power unlocks, not a
	# second gun that arrives with the rover.
	var gl_from := cm.missions.filter(func(m): return m != null and m.unlocks.has(&"grenade_launcher"))
	_check("...its grenade launcher comes later, from Coast Road",
		gl_from.size() == 1 and gl_from[0].id == &"coast_1_road", str(gl_from.map(func(m): return str(m.id))))
	var soldier_body: Soldier = load("res://Character/characters/ai/soldier_rifle.tscn").instantiate()
	_check("in a squad it counts as in its slot where it parks", rover.slot_tolerance(1.6) >= rover.arrival_radius
		and soldier_body.slot_tolerance(1.6) == 1.6)
	soldier_body.free()

	print("")
	print("ALL VEHICLE CHECKS PASS" if _fails == 0 else "%d VEHICLE CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
