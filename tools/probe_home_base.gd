extends SceneTree

# ─────────────────────────────────────────────
# IS THE HOME BASE ACTUALLY THE HOME BASE?
#
# Swapping the base is four lines in Env/world.tscn and every wrong
# combination fails QUIETLY in its own way:
#
#   base_level changed, instance not  -> Campaign._is_base() false at boot,
#                                        so no induction and no repair on
#                                        return, plus a misleading warning
#   instance changed, base_level not  -> deploying still goes to the old base
#   root script wrong                 -> world.gd casts `as TrenchBroomLevel`,
#                                        gets null, and the load just breaks
#   spawn_point unset                 -> World._ready() derefs it with no null
#                                        guard. A crash, not a warning.
#
# None of that is visible from reading the scene. This boots the real game
# and asks.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_home_base.gd -- --no-save
# ─────────────────────────────────────────────

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fail += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 180:
		await physics_frame
	for who in PauseHold.holders():
		PauseHold.release(who)

	var campaign = world.get_node("CampaignManager")
	var level = world.current_level

	_check("a level loaded at boot", level != null)
	if level == null:
		print("")
		quit(1)
		return
	_check("...and it is the train", level.scene_file_path.contains("railhead_level"),
		level.scene_file_path)
	_check("...and it passes as a TrenchBroomLevel", level is TrenchBroomLevel)
	_check("the campaign agrees it is the base", campaign._is_base(level),
		"base_level = %s" % (campaign.base_level.resource_path if campaign.base_level != null else "null"))

	# The spawn. Not the origin, which on a train is under the trackbed.
	var p: Node3D = world.player
	_check("the player spawned beside the ops table",
		p != null and p.global_position.z > 55.0 and p.global_position.z < 73.0,
		str(p.global_position.snapped(Vector3.ONE * 0.1)) if p != null else "-")

	# The squad.
	var mates := 0
	for squad in root.get_tree().get_nodes_in_group("squads"):
		for m in squad.squad_members:
			if m != null and is_instance_valid(m):
				mates += 1
	_check("the squad mustered", mates > 0, "%d member(s)" % mates)

	# AT THE RACKS, not in the corridor. The barracks car is around z -64;
	# the muster point and the arc fallback are back at z -92 on the platform.
	var in_barracks := 0
	var where: Array = []
	for squad in root.get_tree().get_nodes_in_group("squads"):
		for m in squad.squad_members:
			if m == null or not is_instance_valid(m):
				continue
			where.append("%.0f" % m.global_position.z)
			if m.global_position.z > -80.0 and m.global_position.z < -45.0:
				in_barracks += 1
	_check("...in the barracks car, not the corridor", in_barracks == mates,
		"%d of %d; z = %s" % [in_barracks, mates, str(where)])

	# Big frames belong in the bays, not the bunks. Fabrication mounts are
	# around z -24..-40, repair bays around z 24..40; the racks are -49..-79.
	var big_in_bays := 0
	var big_total := 0
	var st = campaign.state
	for squad in root.get_tree().get_nodes_in_group("squads"):
		for m in squad.squad_members:
			if m == null or not is_instance_valid(m):
				continue
			var rid = m.get_meta("record_id", &"")
			var rec = null
			for r in st.roster:
				if r != null and r.id == rid:
					rec = r
			if rec == null or st.supply_of(rec) < 2:
				continue
			big_total += 1
			if m.global_position.z > -45.0:
				big_in_bays += 1
	if big_total > 0:
		_check("big frames went to the bays, not the bunks", big_in_bays == big_total,
			"%d of %d" % [big_in_bays, big_total])
	else:
		# A FRESH ROSTER IS ALL INFANTRY, so the sort never fires on a default
		# save and shipping it untested would be shipping it on faith. Give one
		# squadmate a big frame and re-run the sort on the real bodies.
		var victim = null
		for squad in root.get_tree().get_nodes_in_group("squads"):
			for m in squad.squad_members:
				if m != null and is_instance_valid(m) and victim == null:
					victim = m
		var big = st.catalogue.chassis_def(&"walker")
		if victim != null and big != null:
			var rid2 = victim.get_meta("record_id", &"")
			for r in st.roster:
				if r != null and r.id == rid2:
					r.chassis_id = &"walker"
			var before_z: float = victim.global_position.z
			var lvl2 = world.current_level
			for squad in root.get_tree().get_nodes_in_group("squads"):
				lvl2._station_by_size(squad, 0)
			_check("a big frame is moved out of the bunks into a bay",
				victim.global_position.z > -45.0,
				"z %.0f -> %.0f  (supply %d)" % [before_z, victim.global_position.z, st.supply_of(st.roster[0])])

	# The way out.
	var departures := 0
	for e in root.get_tree().get_nodes_in_group("levelexit"):
		if e.get("is_departure"):
			departures += 1
	_check("there is exactly one departure pad", departures == 1, "%d found" % departures)

	# The table.
	var tables := root.get_tree().get_nodes_in_group("ops_tables")
	_check("the operations table is in the level", tables.size() > 0,
		"%d found" % tables.size())
	if tables.size() > 0:
		_check("...and it read the campaign", tables[0].facts.size() > 0,
			"%d sites" % tables[0].facts.size())

	# ── the interact ────────────────────────────
	# The Interactible in railhead_car_ops.tscn ships with the TEMPLATE
	# defaults: type 0 (HEALTH) and destroy_on_use true. Left alone, F would
	# read "Repair +0" and the table would delete its own trigger the first
	# time you used it. OpsTable._wire_interactible is supposed to correct
	# both on ready; this is where we find out.
	if tables.size() > 0:
		var t = tables[0]
		var inter = t.interactible
		_check("the table claimed its Interactible", inter != null)
		if inter != null:
			_check("...and set it to MISSION, not the HEALTH default",
				int(inter.type) == int(Enums.InteractTypes.MISSION), "type = %d" % int(inter.type))
			_check("...and stopped it destroying itself on use",
				not inter.destroy_on_use)
		_check("...and offers a prompt", String(t.get_prompt()) != "",
			"F | %s" % t.get_prompt())

		# ── STAND AT IT AND LOOK ──────────────────
		# NOT _on_interacted() directly. That calls the handler and proves
		# the handler works, which was never in doubt — it passed while the
		# table was unusable in the real game because the Interactible was
		# on a collision layer the player's raycast does not mask. The only
		# honest test is the player's own raycast finding it.
		var pl: Node3D = world.player
		var tbl_pos: Vector3 = inter.global_position if inter != null else t.global_position
		# DO NOT look_at THE PLAYER. Its own script owns its rotation and puts
		# it back, so the aim silently does not take — measured: the ray still
		# pointed down -Z with the table off to -X. Instead, put the player
		# where the table is already in front of the camera it has.
		var cam: Camera3D = pl.cam
		var fwd: Vector3 = -cam.global_transform.basis.z
		var eye_drop: float = cam.global_position.y - pl.global_position.y
		pl.global_position = tbl_pos - fwd * 1.35 - Vector3(0.0, eye_drop, 0.0)
		for _i in 25:
			await physics_frame
		var rc: RayCast3D = pl.interact_raycast
		print("      DIAG layer=%d  table=%s  player=%s  ray_from=%s  len=%s  colliding=%s  hit=%s" % [
			int(inter.collision_layer), str(tbl_pos.snapped(Vector3.ONE * 0.1)),
			str(pl.global_position.snapped(Vector3.ONE * 0.1)),
			str(rc.global_position.snapped(Vector3.ONE * 0.1)) if rc != null else "-",
			str(rc.target_position) if rc != null else "-",
			str(rc.is_colliding()) if rc != null else "-",
			str(rc.get_collider()) if rc != null and rc.is_colliding() else "none"])
		_check("standing at it, the player's raycast finds it",
			pl.current_interactible != null,
			"current_interactible = %s" % str(pl.current_interactible))
		_check("...and it is the TABLE's interactible",
			pl.current_interactible == inter)

		# Now press F the way handle_input does.
		if pl.current_interactible != null:
			pl.interact(pl.current_interactible)
		for _i in 20:
			await process_frame
		var zoom = t._zoom
		_check("F opens the zoomed view", zoom != null and zoom.is_open())
		if zoom != null and zoom.is_open():
			_check("...and it paused the game", paused)
			_check("...and hid the HUD but kept the wallet", zoom._hidden.size() > 0,
				"%d hidden" % zoom._hidden.size())
			zoom.close()
			for _i in 5:
				await process_frame
			_check("...and closing gives the game back", not paused)

	# ── the departure lever ─────────────────────
	# THE ONE THING IN DOUBT IS WHETHER THE RAY CAN REACH IT. The lever's
	# interact volume sits 0.12 m outboard of the table's, and a RayCast3D
	# returns the CLOSEST collider — so if that gap is wrong, or if the handle's
	# arc strays back over the slab, F silently gets the table instead and the
	# lever is decoration. Pressing the handler directly would pass either way,
	# which is exactly the mistake this file already records for the table.
	var levers: Array = []
	_collect_script(level, load("res://Env/world_objects/departure_lever.gd"), levers)
	_check("the departure lever is in the level", levers.size() == 1,
		"%d found" % levers.size())
	if levers.size() == 1:
		var lv = levers[0]
		var li = lv.interactible
		_check("the lever claimed its Interactible", li != null)
		if li != null:
			_check("...and set it to DEPART, not the HEALTH default",
				int(li.type) == int(Enums.InteractTypes.DEPART), "type = %d" % int(li.type))
			_check("...and stopped it destroying itself on use", not li.destroy_on_use)
			_check("...on a layer the player's ray actually masks",
				int(li.collision_layer) == 3, "layer = %d" % int(li.collision_layer))
		_check("...and it generated a handle", lv.get_node_or_null(^"Pivot/Knob") != null)

		# Nothing queued yet, so the prompt must say so rather than inviting a
		# throw that cannot go anywhere.
		var queued_now = campaign.selected_mission()
		_check("with nothing queued the prompt says so",
			String(lv.get_prompt()).contains("no operation queued") or queued_now != null,
			"F | %s" % lv.get_prompt())

		# STAND AT IT AND LOOK. Same approach as the table above, and for the
		# same reason: the player's own raycast is the only honest test.
		# AIM AT THE SHAPE, NOT THE AREA'S ORIGIN. The lever's box is offset
		# well clear of its anchor — the anchor is the handle's PIVOT and the
		# volume wraps the arc the handle swings through, so the origin is not
		# even inside its own box. Standing relative to the origin put the
		# player on a line that misses the volume entirely, and the symptom
		# was identical to a dead interactible.
		var lv_cs := li.get_node_or_null(^"CollisionShape3D") as CollisionShape3D if li != null else null
		var lv_pos: Vector3 = lv_cs.global_position if lv_cs != null \
				else (li.global_position if li != null else lv.global_position)
		var pl2: Node3D = world.player
		var cam2: Camera3D = pl2.cam
		var fwd2: Vector3 = -cam2.global_transform.basis.z
		var drop2: float = cam2.global_position.y - pl2.global_position.y
		pl2.global_position = lv_pos - fwd2 * 1.3 - Vector3(0.0, drop2, 0.0)
		for _i in 25:
			await physics_frame
		var rc2: RayCast3D = pl2.interact_raycast
		print("      DIAG lever=%s  player=%s  colliding=%s  hit=%s" % [
			str(lv_pos.snapped(Vector3.ONE * 0.1)),
			str(pl2.global_position.snapped(Vector3.ONE * 0.1)),
			str(rc2.is_colliding()) if rc2 != null else "-",
			str(rc2.get_collider()) if rc2 != null and rc2.is_colliding() else "none"])
		_check("standing at it, the player's raycast finds an interactible",
			pl2.current_interactible != null,
			"current_interactible = %s" % str(pl2.current_interactible))
		_check("...and it is the LEVER's, not the table's",
			pl2.current_interactible == li,
			"got %s" % str(pl2.current_interactible))

		# ── the ride, and the gate it opens ───────
		# Captured BEFORE the throw, because the state before is half the test:
		# a pad that is already armed proves nothing by becoming armed.
		var rides: Array = []
		_collect_script(level, load("res://Env/world_objects/departure_ride.gd"), rides)
		_check("the ride is fitted", rides.size() == 1, "%d found" % rides.size())
		var pad = null
		for e in root.get_tree().get_nodes_in_group("levelexit"):
			if e.get("is_departure"):
				pad = e
		# QUEUED FIRST, AND THAT ORDERING IS THE TEST. With nothing queued the
		# pad refuses on `next_level == null` and says "NO DESTINATION SET",
		# which looks like a pass and proves nothing about the arming gate. The
		# first run of this probe did exactly that.
		var options: Array = campaign.available_missions()
		_check("there is an operation available to queue", options.size() > 0,
			"%d available" % options.size())
		if options.size() > 0:
			campaign.select_mission(options[0].id)
			for _i in 5:
				await physics_frame
		if rides.size() == 1 and pad != null:
			var rd = rides[0]
			_check("the pad is gated behind the ride", pad.requires_arming == true)
			_check("...and is NOT armed before the train moves", pad.armed == false)
			_check("...and has somewhere to go, so only the gate can refuse",
				pad.next_level != null,
				"next_level = %s" % str(pad.next_level))
			# Walking out now has to refuse, with the ARMING reason, rather than
			# deploying you from the station you are standing in.
			var blocked: Array = []
			pad.exit_blocked.connect(func(r): blocked.append(r))
			var went: Array = []
			pad.next_level_signal.connect(func(l): went.append(l))
			pad._on_area_3d_body_entered(world.player)
			_check("...so stepping on it refuses, because the train has not moved",
				went.is_empty() and blocked == ["TRAIN HAS NOT MOVED"],
				"blocked = %s  departed = %d" % [str(blocked), went.size()])
			_check("the platform door leaf was built",
				rd.get_node_or_null(^"PlatformDoorLeaf") != null)
			_check("...and it is shut", rd._leaf != null \
					and rd._leaf.global_position.distance_to(rd._leaf_shut) < 0.01,
				"%.2f m from the closed marker" % (rd._leaf.global_position.distance_to(rd._leaf_shut) if rd._leaf != null else -1.0))
			_check("there is a scrolling tunnel layer, one plate per car per side",
				rd._mats.size() == 14, "%d plates" % rd._mats.size())
			_check("...and it is dark at a standstill",
				rd._mats.is_empty() or float(rd._mats[0].get_shader_parameter(&"rate")) == 0.0)
			_check("the interior lamps were found", rd._lamps.size() > 0,
				"%d lamp(s)" % rd._lamps.size())
			# The AUTHORED timing, checked separately from the wiring, because
			# the run below deliberately speeds it up.
			var total: float = rd.accelerate_seconds + rd.cruise_seconds + rd.brake_seconds
			_check("the authored ride is 8-12 seconds", total >= 8.0 and total <= 12.0,
				"%.1f s" % total)
			# SPED UP FOR THE RUN. `await physics_frame` in headless ticks at
			# real time, so the authored 10.5 s would add ten seconds to every
			# probe. The risk here is the wiring, not the duration, and the
			# duration is asserted above.
			rd.accelerate_seconds = 0.2
			rd.cruise_seconds = 0.2
			rd.brake_seconds = 0.2
			rd.door_seconds = 0.2

		# Now throw it for real.
		if options.size() > 0:
			_check("...and the prompt now names it",
				String(lv.get_prompt()).contains(options[0].display_name),
				"F | %s" % lv.get_prompt())
			var fired: Array = []
			lv.thrown.connect(func(m): fired.append(m))
			if pl2.current_interactible == li:
				pl2.interact(pl2.current_interactible)
			for _i in 40:
				await process_frame
			_check("F throws the lever", int(lv.pose) == int(lv.Pose.THROWN),
				"pose = %d" % int(lv.pose))
			_check("...and it reports what it is departing for", fired.size() == 1,
				"%d signal(s)" % fired.size())
			# The handle has to have actually moved, not just flipped a flag.
			var pivot: Node3D = lv.get_node_or_null(^"Pivot")
			_check("...and the handle went over",
				pivot != null and rad_to_deg(pivot.rotation.x) < lv.stowed_degrees - 20.0,
				"pivot x = %.1f deg" % (rad_to_deg(pivot.rotation.x) if pivot != null else 0.0))

			# ── and the train actually goes ───────
			if rides.size() == 1 and pad != null:
				var rd2 = rides[0]
				_check("...which starts the ride", rd2.running == true)
				# Mid-journey: the tunnel has to be moving, not just flagged.
				var moved_rate: float = 0.0
				var moved_scroll: float = 0.0
				# THE DIMMEST IT GOT, not what it reads afterwards. The lamp
				# curve is transient: it falls over accelerate_seconds, holds
				# through cruise and comes back over brake_seconds, and the run
				# below is sped up to 0.2 s a phase. Sampling the value after
				# the loop can easily land back at full and look like a failure
				# that is really a timing artefact in the test.
				var dimmest: float = 1.0
				var authored: float = rd2._lamp_energy[0] if not rd2._lamp_energy.is_empty() else 1.0
				for _i in 20:
					await physics_frame
					moved_rate = maxf(moved_rate, rd2._rate)
					moved_scroll = maxf(moved_scroll, rd2._scroll)
					if not rd2._lamps.is_empty() and authored > 0.0:
						dimmest = minf(dimmest, rd2._lamps[0].light_energy / authored)
				# THE DISTANCE IS THE EVIDENCE, NOT THE PEAK RATE. `_rate` is
				# sampled off an acceleration ramp, so what it reads depends
				# entirely on where in the ramp the sampling window happened
				# to land — a threshold on it fails for timing reasons rather
				# than real ones, which it did the moment line_speed changed.
				# The scroll is the integral: it cannot be large unless the
				# tunnel actually moved.
				_check("...and the tunnel goes past the windows",
					moved_rate > 0.0 and moved_scroll > 2.0,
					"peak rate %.2f, scrolled %.1f m" % [moved_rate, moved_scroll])
				print("      DIAG lamp0=%s authored=%.2f dimmest=%.2f target=%.2f" % [
					rd2._lamps[0].name if not rd2._lamps.is_empty() else "-",
					authored, dimmest, rd2.running_lamp_level])
				_check("...and the lamps dropped to a running state",
					dimmest < 0.95, "fell to %.0f%% of authored" % (dimmest * 100.0))
				# Then let it arrive.
				for _i in 120:
					await physics_frame
					if rd2.arrived_already:
						break
				_check("the train arrives", rd2.arrived_already == true)
				_check("...and stops integrating",
					not rd2.is_physics_processing() and rd2._rate == 0.0,
					"rate = %.4f, processing = %s" % [rd2._rate, str(rd2.is_physics_processing())])
				_check("...and puts the lamps back exactly",
					rd2._lamps.is_empty() or is_equal_approx(rd2._lamps[0].light_energy, rd2._lamp_energy[0]),
					"%.3f of %.3f" % [rd2._lamps[0].light_energy if not rd2._lamps.is_empty() else 0.0,
						rd2._lamp_energy[0] if not rd2._lamp_energy.is_empty() else 0.0])
				_check("...and arms the departure pad", pad.armed == true)
				for _i in 40:
					await process_frame
				_check("...and the door is open", rd2._leaf != null \
						and rd2._leaf.global_position.distance_to(rd2._leaf_open) < 0.05,
					"%.2f m from the open marker" % (rd2._leaf.global_position.distance_to(rd2._leaf_open) if rd2._leaf != null else -1.0))
				# And NOW walking out works.
				var went2: Array = []
				pad.next_level_signal.connect(func(l): went2.append(l))
				pad._on_area_3d_body_entered(world.player)
				_check("...so stepping on the pad now deploys", went2.size() == 1,
					"%d departure(s)" % went2.size())

	print("")
	print("%d failure(s)" % _fail)
	quit(1 if _fail > 0 else 0)


## Every node under `n` carrying `script`. By script rather than by group
## because the lever has no reason to join one — the level fits exactly one.
func _collect_script(n: Node, script: Script, out: Array) -> void:
	if n.get_script() == script:
		out.append(n)
	for c in n.get_children():
		_collect_script(c, script, out)
