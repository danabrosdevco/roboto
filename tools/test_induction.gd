extends SceneTree

# ─────────────────────────────────────────────
# THE DEPOT INDUCTION — the first visit to base is a mission, and only the
# first. Five objectives that complete on events rather than on places.
#
# Walked end to end against the real campaign: a fresh save, then each of the
# five done the way a player would do it, then the visit AFTER, which must be
# an ordinary depot with no objectives and no robot on the floor.
#
# The last check is the one that matters for an export. An induction that
# cannot be finished, or one that comes back every time, is worse than none.
# ─────────────────────────────────────────────

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  %s" if ok else "FAIL  %s  " + detail) % label)
	if not ok:
		_fails += 1


func _ids(cm) -> Array:
	var out: Array = []
	for o in cm.objectives.objectives():
		out.append(String(o.id))
	out.sort()
	return out


func _obj(cm, id: StringName):
	for o in cm.objectives.objectives():
		if o.id == id:
			return o
	return null


func _done(cm, id: StringName) -> bool:
	var o = _obj(cm, id)
	return o != null and o.completed


func _commander(player: Node) -> Node:
	if player == null:
		return null
	for c in player.get_children():
		var s: Variant = c.get_script()
		if s != null and str(s.resource_path).ends_with("squad_commander.gd"):
			return c
	return null


func _find_hud(n: Node) -> ObjectiveHUD:
	if n is ObjectiveHUD:
		return n
	for c in n.get_children():
		var f := _find_hud(c)
		if f != null:
			return f
	return null


func _texts(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	for c in n.get_children():
		out += _texts(c)
	return out


func _says(n: Node, text: String) -> bool:
	return _texts(n).to_upper().contains(text.to_upper())


func _init() -> void:
	Settings.path = "user://settings_induction_test.json"
	await process_frame
	var master: Master = load("res://Managers/master.tscn").instantiate()
	master.skip_splash = true
	master.show_mission_briefing = false
	var cm: CampaignManager = master.find_child("CampaignManager", true, false)
	cm.autosave = false
	root.add_child(master)
	for _i in 90:
		await physics_frame
	var world: World = master._world()

	# ── A FRESH SAVE ARRIVES AT THE DEPOT ─────────
	cm.reset_campaign()
	cm.on_level_loaded(world.current_level)
	for _i in 60:
		await physics_frame

	var ids := _ids(cm)
	_check("the first visit sets eight objectives (%d)" % ids.size(), ids.size() == 8, str(ids))
	for want in [&"induct_read_keys", &"induct_repair_self", &"induct_revive_squad", &"induct_buy_rifle",
			&"induct_fit_rifle", &"induct_order_follow",
			&"induct_order_advance", &"induct_pick_op"]:
		_check("...including %s" % String(want), _obj(cm, want) != null, str(ids))

	# THE PANEL HAS TO BE ON SCREEN. It used to hide whenever you were not in a
	# mission, which at base is always — so the induction would have set five
	# objectives nobody could see.
	var hud := _find_hud(root)
	_check("(setup) found the objective HUD", hud != null)
	if hud != null:
		_check("the objective panel is up at base during the induction", hud._panel.visible)
		_check("...and it lists the objectives by name",
			_says(hud._panel, "REPAIR YOURSELF"), _texts(hud._panel).substr(0, 160))

	var player: Node = world.player
	var casualty = null
	for sq in world.squad_spawner.squads:
		if sq == null or not is_instance_valid(sq):
			continue
		for m in sq.squad_members:
			if m != null and is_instance_valid(m) and m.downed:
				casualty = m
	_check("a squadmate is on the floor to revive", casualty != null)
	_check("...and the player needs repairing (%d/%d)" % [
		int(player.health), int(player.max_health)],
		int(player.health) < int(player.max_health))
	_check("none of them is complete yet",
		not _done(cm, &"induct_repair_self") and not _done(cm, &"induct_revive_squad"))

	# ── 1. PATCH YOURSELF UP ──────────────────────
	player.apply_healing(player.max_health, player)
	await process_frame
	_check("repairing yourself to full completes that objective",
		_done(cm, &"induct_repair_self"))

	# ── 2. GET THE SQUADMATE UP ───────────────────
	if casualty != null:
		casualty.apply_healing(casualty.max_health, player)
		await process_frame
	_check("reviving the downed squadmate completes that one",
		_done(cm, &"induct_revive_squad"))

	# ── 3 AND 4. THE TWO ORDERS ───────────────────
	# Each objective wants ITS verb and no other, or ordering a follow would
	# tick the advance line off with it.
	var commander := _commander(world.player)
	_check("(setup) found the player's SquadCommander", commander != null)
	_check("(setup) neither order is done yet", not _done(cm, &"induct_order_follow")
		and not _done(cm, &"induct_order_advance"))
	if commander != null:
		commander.order_issued.emit(null, commander.Verb.FOLLOW, Vector3.ZERO, null)
		await process_frame
		_check("ordering a FOLLOW completes its objective", _done(cm, &"induct_order_follow"))
		_check("...and does NOT complete the advance objective",
			not _done(cm, &"induct_order_advance"), "one order ticked both off")
		commander.order_issued.emit(null, commander.Verb.ADVANCE, Vector3.ZERO, null)
		await process_frame
		_check("ordering an ADVANCE completes its objective", _done(cm, &"induct_order_advance"))

	# ── BUY A RIFLE, THEN PUT IT IN YOUR OWN HANDS ──
	# The squad musters armed and the player does not, which is the ONLY reason
	# these two are not complete before the player touches anything.
	_check("every starting soldier is issued an Ancient Rifle",
		cm.state.roster.all(func(r): return r != null and r.weapon_ids.has(&"m4")),
		str(cm.state.roster.map(func(r): return str(r.weapon_ids))))
	_check("...and you are the one who musters unarmed",
		not cm.state.player_record.weapon_ids.has(&"m4"),
		str(cm.state.player_record.weapon_ids))
	_check("(setup) so neither the buy nor the fit is done", not _done(cm, &"induct_buy_rifle")
		and not _done(cm, &"induct_fit_rifle"))

	cm.state.armoury.add(&"m4")
	cm.state.ledger_changed.emit()
	await process_frame
	_check("buying an Ancient Rifle completes the buy objective", _done(cm, &"induct_buy_rifle"))
	_check("...and the fit objective still wants it in YOUR hands",
		not _done(cm, &"induct_fit_rifle"), "fitting completed itself off a purchase")

	cm.state.player_record.weapon_ids[0] = &"m4"
	cm.state.roster_changed.emit()
	await process_frame
	_check("arming yourself completes the fit objective", _done(cm, &"induct_fit_rifle"))

	# ── 5. CHOOSE AN OPERATION ────────────────────
	_check("(setup) the induction is not finished yet", not cm.state.completed_tutorial)
	var first: MissionDefinition = cm.available_missions()[0]
	cm.select_mission(first.id)
	await process_frame
	_check("choosing an operation completes the last one", _done(cm, &"induct_pick_op"))
	_check("...and finishing all eight marks the tutorial done", cm.state.completed_tutorial)

	# ── THE VISIT AFTER ───────────────────────────
	# The whole point: the depot is a depot from here on.
	cm.current_mission = null
	cm.in_mission = false
	cm.on_level_loaded(world.current_level)
	for _i in 60:
		await physics_frame
	_check("the next visit sets no objectives at all", _ids(cm).is_empty(), str(_ids(cm)))
	if hud != null:
		hud._rebuild()
		_check("...and the objective panel is gone with them", not hud._panel.visible)
	var still_down := 0
	for sq in world.squad_spawner.squads:
		if sq == null or not is_instance_valid(sq):
			continue
		for m in sq.squad_members:
			if m != null and is_instance_valid(m) and m.downed:
				still_down += 1
	_check("...and nobody is left on the floor", still_down == 0, "%d down" % still_down)
	_check("...and the player is not re-damaged (%d/%d)" % [
		int(player.health), int(player.max_health)],
		int(player.health) >= int(player.max_health))

	# ── AN UNFINISHED INDUCTION COMES BACK ────────
	# A player who quits half way through must not lose it, and must not be
	# left an objective to revive a squadmate who is standing up.
	cm.state.completed_tutorial = false
	cm.on_level_loaded(world.current_level)
	for _i in 60:
		await physics_frame
	_check("an unfinished induction is rebuilt on the next visit", _ids(cm).size() == 8,
		str(_ids(cm)))
	# The casualty is staged ONCE per campaign, so a resumed induction finds
	# nobody on the floor. That objective must not block the other four — it
	# completes itself instead, which is the whole reason that branch exists.
	var redown := 0
	for sq in world.squad_spawner.squads:
		if sq == null or not is_instance_valid(sq):
			continue
		for m in sq.squad_members:
			if m != null and is_instance_valid(m) and m.downed:
				redown += 1
	_check("...and nobody is re-broken to go with it", redown == 0, "%d down" % redown)
	_check("...so the revive objective completes itself rather than blocking",
		_done(cm, &"induct_revive_squad"))

	if FileAccess.file_exists("user://settings_induction_test.json"):
		DirAccess.remove_absolute("user://settings_induction_test.json")
	print("")
	print("ALL INDUCTION CHECKS PASS" if _fails == 0 else "%d INDUCTION CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
