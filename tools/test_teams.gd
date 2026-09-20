extends SceneTree

# ─────────────────────────────────────────────
# TEAMS — a rover goes into the field as a team of its own, ARMOR, and G picks
# which team T orders.
#
# Deploys a real roster (two robots on foot and a rover) through SquadSpawner,
# then drives the commander the way the keys do — cycle_team() is G, and
# _issue_order() is what a tap or a hold resolves to — and reads back where each
# order landed, what the HUD says and which markers are dimmed.
#
# Boots the real world with autosave off: it reads the save on this machine
# and never writes it. Everything happens at base, beside the player.
# ─────────────────────────────────────────────

const ROVER_SCRIPT := "res://Character/characters/ai/rover.gd"

var _fails := 0


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


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _recruit(state: CampaignState, frame: ChassisDefinition, record_name: String) -> SoldierRecord:
	var rec := state.recruit(frame)
	rec.display_name = record_name
	rec.benched = false
	return rec


func _marker_text(commander: SquadCommander, squad: Squad) -> String:
	var marker = commander._markers.get(squad)
	if marker == null or not is_instance_valid(marker) or marker._label == null:
		return "<no marker>"
	return marker._label.text


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
	var state := CampaignState.new()
	state.armoury = Armoury.new()
	state.catalogue = cat
	state.award(5000)
	var foot := cat.chassis_def(&"soldier")
	var ada := _recruit(state, foot, "Ada")
	var bo := _recruit(state, foot, "Bo")
	var rolly := _recruit(state, cat.chassis_def(&"rover"), "Rolly")
	var base_name: String = cm.state.squad_name if cm.state.squad_name != "" else "ALPHA"

	# ── DEPLOYMENT ───────────────────────────────
	_withdraw(spawner, ai)
	spawner.spawn_mode = SquadSpawner.SpawnMode.PLAYER
	var roster: Array[SoldierRecord] = [ada, bo, rolly]
	spawner.deploy_into(level, roster)
	for _i in 10:
		await physics_frame
	commander._refresh_registry_quietly()
	var teams := spawner.squads
	_check("a roster with a rover goes in as two teams", teams.size() == 2, "%d squads" % teams.size())
	if teams.size() != 2:
		quit(1)
		return
	var infantry: Squad = teams[0]
	var armor: Squad = teams[1]
	var rover: Soldier = armor.squad_members[0] if armor.squad_members.size() == 1 else null
	_check("...the robots on foot as INFANTRY", infantry.team == Squad.TEAM_INFANTRY
		and infantry.squad_members.size() == 2, "%s with %d" % [infantry.team, infantry.squad_members.size()])
	_check("...the rover as ARMOR, on its own", armor.team == Squad.TEAM_ARMOR and rover != null
		and rover.get_script().resource_path == ROVER_SCRIPT)
	_check("team names come from the squad's name", infantry.callsign == base_name
		and armor.callsign == base_name + " ARMOR", "%s / %s" % [infantry.callsign, armor.callsign])
	_check("both fall in on you, the armour further back", infantry.objective == Squad.SquadObjective.FOLLOW
		and armor.objective == Squad.SquadObjective.FOLLOW and armor.follow_distance > infantry.follow_distance)
	_check("whatever wants one squad is handed the infantry", spawner.active_squad == infantry)

	# ── WHO THE ORDERS GO TO ─────────────────────
	var heard: Array = []
	commander.team_selected.connect(func(label: String) -> void: heard.append(label))
	_check("orders start out going to the infantry", commander.has_teams()
		and commander.get_selected_squad() == infantry and commander.selection_label() == "INFANTRY")
	hud._refresh_roster()
	var shown := hud._shown_squads()
	_check("...the roster lists both teams, one header each, the armour dimmed", shown.size() == 2
		and shown[0] == infantry and shown[1] == armor and hud._roster.get_child_count() == 4
		and hud._roster.get_child(0).modulate.a > 0.99 and hud._roster.get_child(3).modulate.a < 0.5,
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
		and hud._roster.get_child(3).modulate.a > 0.99
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

	# ── ATTACK ───────────────────────────────────
	# Not registered with the AIManager, so it stands there and does nothing:
	# only the order is under test.
	var foe: Soldier = load("res://Character/characters/ai/soldier_rifle.tscn").instantiate()
	foe.faction = Enums.Factions.ENEMY
	level.add_child(foe)
	foe.global_position = here + ahead * 40.0
	await physics_frame
	commander._issue_order(SquadCommander.Verb.CONTACT, foe.global_position, foe)
	_check("calling out a hostile with INFANTRY selected is only a callout: the rover stays on its post",
		armor.objective == Squad.SquadObjective.DEFEND and armor.ordered_target != foe)
	commander.cycle_team()   # ARMOR
	commander._issue_order(SquadCommander.Verb.CONTACT, foe.global_position, foe)
	_check("with ARMOR selected, tapping a hostile sends the rover at it",
		armor.objective == Squad.SquadObjective.ATTACK and armor.ordered_target == foe)
	_check("...the toast and the marker say ARMOR : ATTACK", hud._toast.text.begins_with("ARMOR : ATTACK")
		and _marker_text(commander, armor) == "ARMOR : ATTACK", "%s / %s" % [hud._toast.text, _marker_text(commander, armor)])
	_check("...and the infantry stay where they were sent", infantry.objective == Squad.SquadObjective.DEFEND
		and _flat_dist(infantry.objective_position, spot_a) < 1.0)
	# A second before it goes. A robot freed within a frame or so of spawning
	# crashes the engine on the way out when stdout is a pipe, as test.sh has
	# it: a shutdown quirk, not the code under test, and nothing in the game
	# frees a robot that fast.
	for _i in 60:
		await physics_frame
	foe.queue_free()

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

	# ── RENAME ───────────────────────────────────
	var manager: SquadManagerUI = _find(root, "SquadManagerUI")
	if manager != null and manager._resolve_campaign():
		var was: String = cm.state.squad_name
		manager.rename_squad("TEAMTEST")
		_check("renaming the squad renames both teams", infantry.callsign == "TEAMTEST"
			and armor.callsign == "TEAMTEST ARMOR", "%s / %s" % [infantry.callsign, armor.callsign])
		cm.state.squad_name = was
	else:
		_check("(setup) found the squad manager to rename through", false)

	# ── ONE TEAM ─────────────────────────────────
	# Left with orders standing for both teams, as a mission ends.
	commander._issue_order(SquadCommander.Verb.ADVANCE, spot_a)
	commander.cycle_team()
	commander._issue_order(SquadCommander.Verb.ADVANCE, spot_b)
	var standing: Array = commander._markers.values()
	_withdraw(spawner, ai)
	var on_foot: Array[SoldierRecord] = [ada, bo]
	spawner.deploy_into(level, on_foot)
	for _i in 10:
		await physics_frame
	commander._refresh_registry_quietly()
	await process_frame
	_check("the last deployment's markers come down with its teams", standing.size() == 2
		and commander._markers.is_empty() and standing.all(func(m): return not is_instance_valid(m)),
		"%d standing, %d left" % [standing.size(), commander._markers.size()])
	_check("(one team) a roster without vehicles goes in as one squad, as it always did",
		spawner.squads.size() == 1 and spawner.squads[0].team == Squad.TEAM_INFANTRY
		and spawner.squads[0].callsign == base_name)
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
	var new_armor: Squad = spawner._squad_of_team(Squad.TEAM_ARMOR)
	_check("a rover repaired back in comes back as ARMOR, making the team",
		back != null and new_armor != null and new_armor.squad_members.has(back) and spawner.squads.size() == 2)
	_check("...named like the rest, and falling in on you", new_armor != null
		and new_armor.callsign == base_name + " ARMOR" and new_armor.objective == Squad.SquadObjective.FOLLOW
		and new_armor.follow_leader == player)
	var cy := _recruit(state, foot, "Cy")
	var back_on_foot := spawner.spawn_one(cy)
	await physics_frame
	_check("a robot on foot repaired back in rejoins the infantry",
		back_on_foot != null and spawner.squads[0].squad_members.has(back_on_foot)
		and spawner.squads[0].squad_members.size() == 3)
	commander._refresh_registry_quietly()
	_check("...and once the rover is back there are two teams to order", commander.has_teams())

	# The two just repaired in were spawned a frame ago: a second before they go
	# too, for the same reason as the hostile above.
	for _i in 60:
		await physics_frame
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
