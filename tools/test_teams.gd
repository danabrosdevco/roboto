extends SceneTree

# ─────────────────────────────────────────────
# TEAMS — the squad goes into the field as the teams made on the squad page,
# each a squad of its own, and G picks which one T orders.
#
# Deploys a real roster (three robots on foot and a rover) through SquadSpawner,
# moves robots between teams the way the squad page does, and drives the
# commander the way the keys do — cycle_team() is G, and _issue_order() is what
# a tap or a hold resolves to — reading back where each order landed, what the
# HUD says and which markers are dimmed.
#
# Boots the real world with autosave off. Its campaign is this machine's save,
# loaded into memory: the test swaps in a roster of its own there and never
# writes it. Everything happens at base, beside the player.
# ─────────────────────────────────────────────

const ROVER_SCRIPT := "res://Character/characters/ai/rover.gd"

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  %s" if ok else "FAIL  %s  " + detail) % label)
	if not ok:
		_fails += 1


func _find_named(n: Node, node_name: String) -> Node:
	if n.name == node_name:
		return n
	for c in n.get_children():
		var f := _find_named(c, node_name)
		if f != null:
			return f
	return null


# Whether any label or button under `n` says `text`.
func _says(n: Node, text: String) -> bool:
	if (n is Label and (n as Label).text.contains(text)) or (n is Button and (n as Button).text.contains(text)):
		return true
	for c in n.get_children():
		if _says(c, text):
			return true
	return false


func _find(n: Node, cls: String) -> Node:
	if n.get_script() != null and n.get_script().get_global_name() == cls:
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _robot(state: CampaignState, frame: ChassisDefinition, record_name: String) -> SoldierRecord:
	var r := SoldierRecord.new()
	r.display_name = record_name
	r.set_chassis(frame, state.catalogue)
	r.recompute_stats(state.catalogue)
	state.add_soldier(r)
	return r


func _marker_text(commander: SquadCommander, squad: Squad) -> String:
	var marker = commander._markers.get(squad)
	if marker == null or not is_instance_valid(marker) or marker._label == null:
		return "<no marker>"
	return marker._label.text


func _names(state: CampaignState) -> Array:
	return state.teams.map(func(t: Dictionary) -> String: return t["name"])


# Same things in the same order. By element, because a typed array and an
# untyped one holding the same things need not compare equal.
func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


func _body(spawner: SquadSpawner, record: SoldierRecord) -> Soldier:
	return spawner.find_body(record)


# The bodies a deployment stood up go with it. clear() leaves them to the level
# unload, and this test never unloads the level.
func _withdraw(spawner: SquadSpawner, ai: AIManager) -> void:
	for squad in spawner.squads:
		if squad == null or not is_instance_valid(squad):
			continue
		for m in squad.squad_members:
			if m != null and is_instance_valid(m):
				if ai != null:
					ai.deregister_enemy(m)
				m.queue_free()
	spawner.clear()


func _init() -> void:
	await process_frame
	var world_scene: Node = load("res://Env/world.tscn").instantiate()
	world_scene.get_node("CampaignManager").autosave = false
	root.add_child(world_scene)
	for _i in 90:
		await physics_frame
	var player: Player = _find(root, "Player")
	var level: Node = player.get_parent()
	var cm: CampaignManager = world_scene.get_node("CampaignManager")
	var spawner: SquadSpawner = cm.spawner
	var commander: SquadCommander = _find(root, "SquadCommander")
	var hud: SquadHUD = _find(root, "SquadHUD")
	var ai: AIManager = _find(root, "AIManager")
	_check("(setup) the world has a spawner, a commander and a squad HUD",
		spawner != null and commander != null and hud != null)
	if spawner == null or commander == null or hud == null:
		quit(1)
		return

	var cat: ItemCatalogue = cm.catalogue
	var foot := cat.chassis_def(&"soldier")
	var wheels := cat.chassis_def(&"rover")

	# ── A SAVE FROM BEFORE TEAMS ─────────────────
	var old := CampaignState.new()
	old.catalogue = cat
	_robot(old, foot, "Old-1")
	_robot(old, wheels, "Old-2")
	var data := old.to_dict()
	data.erase("teams")
	for entry in data["roster"]:
		entry.erase("team")
	data["squad_name"] = "HAMMER"
	var loaded := CampaignState.from_dict(data)
	loaded.catalogue = cat
	loaded.ensure_teams()
	_check("a save from before teams is split as the game used to split it: on foot first, the rover in ARMOR",
		_names(loaded) == ["HAMMER", "ARMOR"] and loaded.team_name(loaded.roster[1].team_id) == "ARMOR"
		and loaded.team_name(loaded.roster[0].team_id) == "HAMMER", str(loaded.teams))
	_check("...the first team named after the squad, since it was named", _names(loaded)[0] == "HAMMER")
	data["squad_name"] = "NAMELESS"
	var unnamed := CampaignState.from_dict(data)
	unnamed.catalogue = cat
	unnamed.ensure_teams()
	_check("...and INFANTRY when it never was", _names(unnamed) == ["INFANTRY", "ARMOR"], str(unnamed.teams))
	var round_trip := CampaignState.from_dict(loaded.to_dict())
	_check("teams and who is in them survive a save and a load", round_trip.teams == loaded.teams
		and round_trip.roster[1].team_id == loaded.roster[1].team_id, str(round_trip.teams))

	# ── THIS TEST'S ROSTER ───────────────────────
	# In memory only: autosave is off, and nothing here deploys or goes home.
	var state: CampaignState = cm.state
	state.roster.clear()
	state.teams.clear()
	state.supply_cap = 20
	var ada := _robot(state, foot, "Ada")
	var bo := _robot(state, foot, "Bo")
	var cy := _robot(state, foot, "Cy")
	var rolly := _robot(state, wheels, "Rolly")
	_check("robots join by frame: on foot the first team, a rover a team of vehicles", _names(state) == ["INFANTRY", "ARMOR"]
		and ada.team_id == state.teams[0]["id"] and rolly.team_id == state.teams[1]["id"], str(state.teams))

	# ── DEPLOYMENT ───────────────────────────────
	_withdraw(spawner, ai)
	spawner.spawn_mode = SquadSpawner.SpawnMode.PLAYER
	var roster: Array[SoldierRecord] = [ada, bo, cy, rolly]
	spawner.deploy_into(level, roster)
	for _i in 10:
		await physics_frame
	commander._refresh_registry_quietly()
	var teams := spawner.squads
	_check("the squad goes in as one squad per team", teams.size() == 2, "%d squads" % teams.size())
	if teams.size() != 2:
		quit(1)
		return
	var infantry: Squad = teams[0]
	var armor: Squad = teams[1]
	var rover: Soldier = _body(spawner, rolly)
	_check("...each named after its team", infantry.callsign == "INFANTRY" and armor.callsign == "ARMOR",
		"%s / %s" % [infantry.callsign, armor.callsign])
	_check("...the robots on foot together", infantry.squad_members.size() == 3 and not infantry.vehicles_only)
	_check("...the rover on its own, a team of vehicles", _same(armor.squad_members, [rover]) and armor.vehicles_only
		and rover.get_script().resource_path == ROVER_SCRIPT)
	_check("both fall in on you, the vehicles further back", infantry.objective == Squad.SquadObjective.FOLLOW
		and armor.objective == Squad.SquadObjective.FOLLOW and armor.follow_distance > infantry.follow_distance)
	_check("whatever wants one squad is handed the first team", spawner.active_squad == infantry)

	# ── WHO THE ORDERS GO TO ─────────────────────
	var heard: Array = []
	commander.team_selected.connect(func(label: String) -> void: heard.append(label))
	_check("orders start out going to the first team", commander.has_teams()
		and commander.get_selected_squad() == infantry and commander.selection_label() == "INFANTRY")
	hud._refresh_roster()
	var shown := hud._shown_squads()
	_check("...the roster lists both teams, one header each, the other dimmed", shown.size() == 2
		and shown[0] == infantry and shown[1] == armor and hud._roster.get_child_count() == 5
		and hud._roster.get_child(0).modulate.a > 0.99 and hud._roster.get_child(4).modulate.a < 0.5,
		"%d shown, %d roster rows" % [shown.size(), hud._roster.get_child_count()])
	hud._refresh_nearby()
	var strip: Array = hud._nearby.get_children().map(func(l): return (l as Label).text)
	_check("...and IN RANGE names them by team, the ordered one starred",
		strip.any(func(t): return t.begins_with("*INFANTRY")) and strip.any(func(t): return t.begins_with(" ARMOR")),
		str(strip))
	_check("nothing about it sits in the middle of the screen",
		hud.get_children().all(func(c): return not (c is Label and (c as Label).anchor_top == 0.5)))

	commander.cycle_team()
	_check("G: ARMOR", commander.get_selected_squad() == armor and commander.selection_label() == "ARMOR")
	var bar: WeaponBar = _find(root, "WeaponBar")
	var row: Rect2 = bar._row.get_global_rect() if bar != null else Rect2()
	var toast: Rect2 = hud._toast.get_global_rect()
	_check("...said just above the weapon bar, centred on it", hud._toast.visible
		and hud._toast.text == "ORDERS > ARMOR" and toast.end.y <= row.position.y
		and row.position.y - toast.end.y < 16.0 and absf(toast.get_center().x - row.get_center().x) < 2.0,
		"toast %s, bar row %s, '%s'" % [toast, row, hud._toast.text])
	strip = hud._nearby.get_children().map(func(l): return (l as Label).text)
	_check("...the roster and IN RANGE follow at once", hud._roster.get_child(0).modulate.a < 0.5
		and hud._roster.get_child(4).modulate.a > 0.99
		and strip.any(func(t): return t.begins_with("*ARMOR")) and strip.any(func(t): return t.begins_with(" INFANTRY")),
		str(strip))
	commander.cycle_team()
	_check("G again: straight back to INFANTRY, nothing in between", commander.get_selected_squad() == infantry)
	_check("...each switch announced", heard == ["ARMOR", "INFANTRY"], str(heard))

	# ── ORDERS ───────────────────────────────────
	var here := player.global_position
	var ahead := -player.global_transform.basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var spot_a := here + ahead * 12.0
	var spot_b := here + ahead * 12.0 + ahead.cross(Vector3.UP) * 10.0
	commander._issue_order(SquadCommander.Verb.ADVANCE, spot_a)
	await physics_frame
	_check("an order to INFANTRY goes to the infantry", infantry.objective == Squad.SquadObjective.DEFEND
		and _flat_dist(infantry.objective_position, spot_a) < 1.0, str(infantry.objective_position))
	_check("...and not to the armour", armor.objective == Squad.SquadObjective.FOLLOW)
	_check("...the toast names the team", hud._toast.text == "INFANTRY : ADVANCE", hud._toast.text)
	_check("...and so does its marker", _marker_text(commander, infantry) == "INFANTRY : ADVANCE",
		_marker_text(commander, infantry))

	commander.cycle_team()   # ARMOR
	commander._issue_order(SquadCommander.Verb.ADVANCE, spot_b)
	await physics_frame
	_check("an order to ARMOR moves the rover", armor.objective == Squad.SquadObjective.DEFEND
		and _flat_dist(armor.objective_position, spot_b) < 1.0)
	_check("...and leaves the infantry where they were sent", infantry.objective == Squad.SquadObjective.DEFEND
		and _flat_dist(infantry.objective_position, spot_a) < 1.0)
	var post = armor._defend_posts.get(rover)
	_check("a rover holds by parking on the point, not by hunting for cover",
		post != null and _flat_dist(post, armor.objective_position) < 0.1, str(post))
	var inf_marker = commander._markers.get(infantry)
	var armor_marker = commander._markers.get(armor)
	_check("the team you are not ordering has its marker dimmed", inf_marker != null and armor_marker != null
		and inf_marker.dimmed and not armor_marker.dimmed)
	commander.cycle_team()   # INFANTRY
	_check("...and switching swaps which one", not inf_marker.dimmed and armor_marker.dimmed)

	# ── A TAP AT A UNIT IS STILL JUST ADVANCE ────
	# Aimed at a hostile, a hive or one of your own robots, the tap used to
	# pick that robot's team, call a contact, or send a team of vehicles at it:
	# a unit where you were pointing hijacked the move. It only ever advances
	# the selected team now, to the ground under what you aimed at.
	# Not registered with the AIManager, so it stands there and does nothing.
	# Put where the crosshair can reach it: the base has walls, and your own
	# robots stand ahead of you.
	var foe: Soldier = load("res://Character/characters/ai/soldier_rifle.tscn").instantiate()
	foe.faction = Enums.Factions.ENEMY
	level.add_child(foe)
	var side := ahead.cross(Vector3.UP)
	var in_sight := false
	for dir in [-ahead, side, -side, (-ahead + side).normalized(), (-ahead - side).normalized()]:
		for dist in [8.0, 5.0]:
			foe.global_position = here + dir * dist
			await physics_frame
			commander.cam.look_at(foe.global_position)
			if commander._aim_result().get("collider") == foe:
				in_sight = true
				break
		if in_sight:
			break
	commander.cycle_team()   # ARMOR, a team of vehicles
	var switches := heard.size()
	commander.cam.look_at(foe.global_position)
	_check("(setup) the crosshair is on the hostile", commander._aim_result().get("collider") == foe,
		str(commander._aim_result().get("collider")))
	commander._issue_contextual_order()
	await physics_frame
	_check("a tap at a hostile with ARMOR selected advances ARMOR to it, targeting nothing",
		armor.objective == Squad.SquadObjective.DEFEND and armor.ordered_target == null
		and _flat_dist(armor.objective_position, foe.global_position) < 1.5,
		"%s at %s" % [armor.objective, armor.objective_position])
	_check("...to the ground under it, not the point on its chest",
		armor.objective_position.y < foe.global_position.y - 0.5,
		"order at y %.2f, hostile at %.2f" % [armor.objective_position.y, foe.global_position.y])
	_check("...the toast and the marker say ARMOR : ADVANCE", hud._toast.text == "ARMOR : ADVANCE"
		and _marker_text(commander, armor) == "ARMOR : ADVANCE", "%s / %s" % [hud._toast.text, _marker_text(commander, armor)])
	var mine: Soldier = infantry.squad_members[0]
	commander.cam.look_at(mine.global_position)
	var aimed = commander._aim_result().get("collider")
	_check("(setup) the crosshair is on one of your robots", aimed is Soldier
		and not Enums.are_hostile(Enums.Factions.PLAYER, (aimed as Soldier).faction), str(aimed))
	commander._issue_contextual_order()
	await physics_frame
	_check("a tap at one of your robots advances the selected team there",
		armor.objective == Squad.SquadObjective.DEFEND and aimed is Node3D
		and _flat_dist(armor.objective_position, (aimed as Node3D).global_position) < 1.5)
	_check("...and does not change which team the orders go to",
		commander.get_selected_squad() == armor and heard.size() == switches, "%d switches" % (heard.size() - switches))
	_check("...and the infantry stay where they were sent", infantry.objective == Squad.SquadObjective.DEFEND
		and _flat_dist(infantry.objective_position, spot_a) < 1.0)

	commander._issue_order(SquadCommander.Verb.FOLLOW)   # ARMOR is selected
	await physics_frame
	_check("hold T calls in the selected team, and only it", armor.objective == Squad.SquadObjective.FOLLOW
		and infantry.objective == Squad.SquadObjective.DEFEND)
	_check("...its marker comes down, the other team's stays", not commander._markers.has(armor)
		and commander._markers.has(infantry))
	_check("...and the toast says ARMOR : FOLLOW", hud._toast.text == "ARMOR : FOLLOW", hud._toast.text)
	commander.cycle_team()   # INFANTRY
	commander._issue_order(SquadCommander.Verb.FOLLOW)
	await physics_frame
	_check("everyone back is hold, G, hold", infantry.objective == Squad.SquadObjective.FOLLOW
		and armor.objective == Squad.SquadObjective.FOLLOW and commander._markers.is_empty())

	# ── REACH ────────────────────────────────────
	# A get-everyone-there objective, never activated so it cannot complete —
	# only who it waits for is under test.
	var zone := ReachObjective.new()
	zone.starts_active = false
	zone.requires_squad = true
	zone.squad_radius = 12.0
	zone.add_child(Area3D.new())
	level.add_child(zone)
	var far := here + ahead * 80.0
	zone.global_position = far
	await physics_frame
	_check("(reach) with both teams back here, the squad is not at the zone", not zone._squad_present())
	for squad in [infantry, armor]:
		for m in squad.get_living_members():
			m.global_position = far + Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
	_check("(reach) both teams there: it is", zone._squad_present())
	armor.receive_player_order(Squad.SquadObjective.DEFEND, spot_b)
	rover.global_position = here + Vector3.UP
	_check("(reach) a team you left holding a point does not keep you waiting", zone._squad_present())
	armor.follow(player)
	_check("(reach) ...but one following you does", not zone._squad_present())
	zone.queue_free()
	for squad in [infantry, armor]:
		for m in squad.get_living_members():
			m.global_position = here + Vector3(randf_range(-4.0, 4.0), 1.0, randf_range(-4.0, 4.0))
	await physics_frame

	# ── MOVING ROBOTS BETWEEN TEAMS ──────────────
	# What dragging a card does on the squad page. The campaign hands every change
	# to the spawner, so the robots standing here change squad on the spot.
	_check("a robot let go on the strip under the teams starts a team of its own",
		state.move_to_new_team(cy) and _names(state) == ["INFANTRY", "ARMOR", "TEAM 3"], str(state.teams))
	await physics_frame
	var third: Squad = _body(spawner, cy).squad
	_check("...which is in the field at once, with it in it", spawner.squads.size() == 3 and third != null
		and third.callsign == "TEAM 3" and _same(third.squad_members, [_body(spawner, cy)])
		and not infantry.squad_members.has(_body(spawner, cy)))
	_check("...falling in on you, behind the others", third.objective == Squad.SquadObjective.FOLLOW
		and third.follow_leader == player and third.follow_distance > armor.follow_distance)
	# As the squad page leaves it: the game paused while it was open.
	paused = true
	await process_frame
	paused = false
	await process_frame
	await process_frame
	_check("...and on G the moment the game runs again", _same(commander.team_squads(), [infantry, armor, third]),
		str(commander.team_squads().map(func(s): return s.callsign)))
	var round_the_teams: Array = []
	for _i in 3:
		commander.cycle_team()
		round_the_teams.append(commander.selection_label())
	_check("G steps through them all in the page's order, and round", round_the_teams == ["ARMOR", "TEAM 3", "INFANTRY"],
		str(round_the_teams))

	_check("a team can be renamed, upper case", state.rename_team(third.team, "snipers")
		and state.team_name(third.team) == "SNIPERS")
	_check("...and is renamed where it stands", third.callsign == "SNIPERS" and third.team_name() == "SNIPERS")
	_check("...but not to another team's name, nor to nothing", not state.rename_team(third.team, "armor")
		and not state.rename_team(third.team, "  ") and state.team_name(third.team) == "SNIPERS")

	commander.selected_index = commander.commandable_squads.find(third)
	commander._issue_order(SquadCommander.Verb.ADVANCE, spot_b)
	await physics_frame
	_check("(orders) SNIPERS sent to hold a point", third.objective == Squad.SquadObjective.DEFEND)
	_check("a robot dropped on another team joins it", state.move_to_team(bo, third.team)
		and _body(spawner, bo).squad == third and third.squad_members.size() == 2
		and _same(infantry.squad_members, [_body(spawner, ada)]))
	_check("...and takes up what that team is doing: a post of its own on the point",
		third._defend_posts.has(_body(spawner, bo)), str(third._defend_posts.keys()))

	_check("the rover dropped in with robots on foot", state.move_to_team(rolly, infantry.team))
	await physics_frame
	_check("...empties ARMOR, and a team nobody is in is gone: from the page", _names(state) == ["INFANTRY", "SNIPERS"],
		str(state.teams))
	_check("...and from the field", not is_instance_valid(armor) and _body(spawner, rolly).squad == infantry)
	_check("a team of robots on foot and a rover is not a team of vehicles", not infantry.vehicles_only)
	commander._refresh_registry_quietly()
	commander.selected_index = commander.commandable_squads.find(infantry)

	# Robots only: you are in a team too now, and which one depends on the save.
	var robots_in := func(id: StringName) -> Array:
		return state.members_of(id, false).filter(func(r): return not state.is_player_record(r))
	_check("the bench keeps a robot's team: benched, it is still in it", state.set_benched(ada, true)
		and ada.team_id == infantry.team and robots_in.call(infantry.team).size() == 1,
		"%s benched=%s, team holds %s" % [ada.display_name, str(ada.benched),
			str(state.members_of(infantry.team, false).map(func(r): return r.display_name))])
	_check("...and DEPLOY puts it back there", state.set_benched(ada, false) and ada.team_id == infantry.team)
	_check("the bench is the one place you cannot be put", not state.set_benched(state.player_record, true)
		and not state.player_record.benched)

	# ── MAKING TEAMS UP TO THE LIMIT ─────────────
	var extra: Array[SoldierRecord] = []
	for i in 3:
		extra.append(_robot(state, foot, "Extra-%d" % i))
	var made := 0
	for r in extra:
		if state.move_to_new_team(r):
			made += 1
	_check("at most %d teams: the one past that is refused" % CampaignState.MAX_TEAMS,
		made == CampaignState.MAX_TEAMS - 2 and state.teams.size() == CampaignState.MAX_TEAMS, "%d made" % made)
	for r in extra:
		state.move_to_team(r, infantry.team)
	_check("...and moving them back out ends those teams", _names(state) == ["INFANTRY", "SNIPERS"], str(state.teams))
	for r in extra:
		state.roster.erase(r)

	# ── ONE TEAM ─────────────────────────────────
	# Left with orders standing, as a mission ends.
	commander._issue_order(SquadCommander.Verb.ADVANCE, spot_a)
	var standing: Array = commander._markers.values()
	_withdraw(spawner, ai)
	var just_bo: Array[SoldierRecord] = [bo]
	spawner.deploy_into(level, just_bo)
	for _i in 10:
		await physics_frame
	commander._refresh_registry_quietly()
	await process_frame
	_check("the last deployment's markers come down with its teams", not standing.is_empty()
		and commander._markers.is_empty() and standing.all(func(m): return not is_instance_valid(m)),
		"%d standing, %d left" % [standing.size(), commander._markers.size()])
	_check("(one team) only the team that has anyone deployed goes in", spawner.squads.size() == 1
		and spawner.squads[0].callsign == "SNIPERS")
	hud._refresh_roster()
	_check("(one team) nothing to choose: one squad on the roster, and yours to order",
		not commander.has_teams() and hud._shown_squads().size() == 1
		and commander.get_selected_squad() == spawner.squads[0])
	var refused := [false]
	commander.no_team_to_switch.connect(func() -> void: refused[0] = true)
	commander.cycle_team()
	_check("(one team) G says there is no other team", refused[0] and hud._toast.text == "NO OTHER TEAM",
		hud._toast.text)
	commander._issue_order(SquadCommander.Verb.ADVANCE, spot_a)
	_check("(one team) orders still go to it, the marker without a team name",
		spawner.squads[0].objective == Squad.SquadObjective.DEFEND
		and _marker_text(commander, spawner.squads[0]) == "ADVANCE", _marker_text(commander, spawner.squads[0]))

	# ── REPAIRED BACK IN ─────────────────────────
	var back := spawner.spawn_one(rolly)
	await physics_frame
	var rejoined: Squad = back.squad if back != null else null
	_check("a robot repaired back in comes back in its own team, making it if it is not out",
		back != null and rejoined != null and rejoined.team == rolly.team_id and spawner.squads.size() == 2)
	_check("...named like the rest, and falling in on you", rejoined != null
		and rejoined.callsign == "INFANTRY" and rejoined.objective == Squad.SquadObjective.FOLLOW
		and rejoined.follow_leader == player)
	var back_too := spawner.spawn_one(cy)
	await physics_frame
	_check("one whose team is out rejoins that team", back_too != null and back_too.squad == spawner.squads[0]
		and spawner.squads[0].squad_members.size() == 2)
	commander._refresh_registry_quietly()
	_check("...and with two teams out there are two to order", commander.has_teams())

	# ── THE DEBRIEF, BY TEAM ─────────────────────
	# What each team did rather than one flat run of cards, and a robot that
	# killed nothing but stood squadmates back up counted for that instead of
	# reading "0 KILLS".
	var debrief := _find_named(root, "DebriefScreen")
	# You fight WITH a team rather than above them all, so you are counted in
	# whichever one you joined — there is no group of your own on the screen.
	_check("you go in a team like anyone else", state.move_to_team(state.player_record, ada.team_id)
		and state.player_record.team_id == ada.team_id
		and state.members_of(ada.team_id).has(state.player_record), str(state.player_record.team_id))
	var rows := [
		{"record": state.player_record, "player": true, "xp": 0, "rank_before": 0, "destroyed": false,
			"kills": 3, "kinds": {}, "revives": 0, "team": state.player_record.team_id},
		{"record": ada, "player": false, "xp": 10, "rank_before": 0, "destroyed": false,
			"kills": 0, "kinds": {}, "revives": 2, "team": ada.team_id},
		{"record": bo, "player": false, "xp": 10, "rank_before": 0, "destroyed": false,
			"kills": 0, "kinds": {}, "revives": 0, "team": bo.team_id},
		{"record": rolly, "player": false, "xp": 10, "rank_before": 0, "destroyed": false,
			"kills": 5, "kinds": {}, "revives": 1, "team": rolly.team_id},
	]
	var groups: Array = debrief._by_team(rows)
	var labels: Array = groups.map(func(g): return str(g["label"]))
	_check("the debrief lists the squad by team, with no group of your own", not labels.has("YOU")
		and labels.all(func(l): return _names(state).has(l)), "%s of %s" % [str(labels), str(_names(state))])
	# Whoever ada and rolly are teamed with by now, their numbers land in it.
	var ada_group: Dictionary = {}
	var rolly_group: Dictionary = {}
	for g in groups:
		if (g["entries"] as Array).any(func(e): return e["record"] == ada):
			ada_group = g
		if (g["entries"] as Array).any(func(e): return e["record"] == rolly):
			rolly_group = g
	_check("...with each team's kills and revives", int(ada_group.get("revives", -1)) >= 2
		and int(rolly_group.get("kills", -1)) >= 5, "%s / %s" % [str(ada_group.get("revives")), str(rolly_group.get("kills"))])
	var you_group: Dictionary = {}
	for g in groups:
		if (g["entries"] as Array).any(func(e): return bool(e.get("player", false))):
			you_group = g
	_check("...and your own kills counted in the team you went in with",
		str(you_group.get("id", "")) == str(ada_group.get("id", "-")) and int(you_group.get("kills", -1)) >= 3,
		"%s: %s kills" % [str(you_group.get("label")), str(you_group.get("kills"))])
	_check("a robot that killed nothing and stood two back up counts the revives, not 0 kills",
		debrief._tally_text(0, 2) == "2 REVIVES", debrief._tally_text(0, 2))
	_check("...one that did both says both", debrief._tally_text(5, 1) == "5 KILLS : 1 REVIVE", debrief._tally_text(5, 1))
	_check("...and neither is still 0 kills", debrief._tally_text(0, 0) == "0 KILLS", debrief._tally_text(0, 0))
	debrief.show_result(null, {"success": true, "squad": rows})
	await process_frame
	_check("the screen draws a heading per team, and the squad's whole tally",
		labels.all(func(l): return _says(debrief, l)) and _says(debrief, "8 KILLS : 3 REVIVES"), str(labels))
	debrief.close()
	await process_frame

	# The ones just repaired in and the hostile were spawned a moment ago: a
	# second before they go. A robot freed within a frame or so of spawning
	# crashes the engine on the way out when stdout is a pipe, as test.sh has
	# it: a shutdown quirk, not the code under test.
	for _i in 60:
		await physics_frame
	foe.queue_free()
	_withdraw(spawner, ai)
	# Let everything in flight finish before quitting: the frees, the last order's
	# confirm sound and the bark election it opened. Quitting under them leaked
	# the playback and the timer, and now and then crashed on the way out.
	await create_timer(1.5).timeout
	for _i in 5:
		await physics_frame
	print("")
	print("ALL TEAM CHECKS PASS" if _fails == 0 else "%d TEAM CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
