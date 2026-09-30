extends SceneTree

# ─────────────────────────────────────────────
# TUTORIAL SIGNS — stand at one and it is readable.
#
# The homebase signs are toasts now: walk up to one and its text takes the top
# of the screen, above the CRT filter. This walks the real homebase and checks
# the parts that could quietly not work: that the signs registered at all, that
# the RIGHT sign wins when you stand at it, that {action} keys expand to the
# live bindings (so the weapon sign says the repair tool is on 3, not a knife),
# and that it gets out of the way when you leave or pause. Then the pause
# menu's TUTORIALS library, the one-time line saying so, and a finished
# player's base, where every sign has stood down.
#
# Scratch settings file first, so a rebound key on this machine cannot change
# what the key checks expect.
# ─────────────────────────────────────────────

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


func _signs(n: Node, out: Array) -> void:
	if n is TutorialLabel:
		out.append(n)
	for c in n.get_children():
		_signs(c, out)


func _texts(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	for c in n.get_children():
		out += _texts(c)
	return out


## Names of every squad body currently on the floor.
func _downed(world: Node) -> Array:
	var out: Array = []
	for sq in world.squad_spawner.squads:
		if sq == null or not is_instance_valid(sq):
			continue
		for m in sq.squad_members:
			if m != null and is_instance_valid(m) and m.downed:
				out.append(m.soldier_name)
	return out


func _sign_saying(signs: Array, fragment: String) -> TutorialLabel:
	for s in signs:
		if str(s.toast_text).contains(fragment):
			return s
	return null


func _init() -> void:
	Settings.path = "user://settings_tutorial_test.json"
	# A new player's base. Whether the signs are up depends on the save, and
	# this machine's save is whatever was last played.
	TutorialLabel.veteran_override = 0
	await process_frame
	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 90:
		await physics_frame
	var player: Node3D = _find(root, "Player")
	var signs: Array = []
	_signs(root, signs)
	var toast = root.get_node_or_null("TutorialToast")
	# A SIGN WITHOUT toast_text IS SIGNAGE, NOT A LESSON. The rebuilt depot has
	# six Label3Ds — DEPOT, TERMINAL, MUSTER, BAYS, RANGE, TRANSIT — and not one
	# of them carries a lesson, so there is nothing in the base to stand at and
	# read. That is the whole of "the tutorial is gone": the TutorialLabel and
	# toast machinery are intact and the CONTENT was dropped with the old layout.
	var carrying: Array = signs.filter(func(s): return str(s.toast_text) != "")
	_check("the homebase signs are toasts (%d sign(s), %d carrying a lesson)" % [
		signs.size(), carrying.size()],
		signs.size() >= 10 and toast != null and carrying.size() >= 7)
	# BAIL OUT RATHER THAN RUN ON NULLS. Every check from here to the library
	# needs a lesson sign to walk up to, and reaching into a null inside a
	# coroutine does not fail the test — it kills the coroutine before quit(),
	# leaving the process alive forever. Eighteen of those were found holding
	# this suite open, which is why no full run ever printed a total.
	var weapons := _sign_saying(signs, "{reload}")
	_check("(setup) found the weapon sign", weapons != null)
	if toast == null or weapons == null:
		printerr("test_tutorial: this base has %d sign(s) and none of them teaches a weapon, so the walk-up, library and stand-down checks cannot run. Author the lessons back into the depot and this test comes back to life." % signs.size())
		await _check_opening(world)
		TutorialLabel.veteran_override = -1
		_done()
		return
	_check("signs leave a small marker in the world, not their paragraph",
		weapons.text == weapons.marker_text)

	# Stand at the weapon sign.
	player.global_position = weapons.global_position + Vector3(1.0, 0.0, 0.5)
	for _i in 40:
		await physics_frame
	var body: String = toast._body.text
	_check("standing at a sign puts it on screen", toast._panel.modulate.a > 0.8 and toast._current == weapons,
		"alpha=%.2f current=%s" % [toast._panel.modulate.a, str(toast._current)])
	_check("keys come from the live bindings", body.contains("R - RELOAD") and body.contains("SHIFT"), body)
	_check("...and key 3 is the repair tool now, not the knife",
		body.contains("3 - REPAIR TOOL") and not body.contains("KNIFE"), body)

	# Walk away.
	player.global_position = weapons.global_position + Vector3(40.0, 0.0, 0.0)
	for _i in 120:
		await physics_frame
	_check("walking away clears it", toast._panel.modulate.a < 0.05 and toast._current == null,
		"alpha=%.2f" % toast._panel.modulate.a)

	# Pausing (squad manager, pause menu) hides it at once.
	player.global_position = weapons.global_position + Vector3(1.0, 0.0, 0.5)
	for _i in 40:
		await physics_frame
	PauseHold.take(&"test")
	for _i in 20:
		await process_frame
	_check("pausing clears it rather than hanging over the menu", toast._panel.modulate.a < 0.1,
		"alpha=%.2f" % toast._panel.modulate.a)
	PauseHold.release(&"test")

	# ── Reading the last sign finishes the tutorial ──
	var state = world.get_node("CampaignManager").state
	state.completed_tutorial = false
	var last := _sign_saying(signs, "GO FORTH")
	_check("(setup) found the last sign", last != null)
	if last != null:
		player.global_position = last.global_position + Vector3(1.0, 0.0, 0.5)
		for _i in 40:
			await physics_frame
		_check("reading GO FORTH marks the tutorial done in the save",
			toast._current == last and state.completed_tutorial)
		_check("...and that once, it says the lessons are in the pause menu",
			toast._body.text.contains("PAUSE MENU"), toast._body.text)
		# Step off and back on: the line does not come back.
		player.global_position = last.global_position + Vector3(40.0, 0.0, 0.0)
		for _i in 120:
			await physics_frame
		player.global_position = last.global_position + Vector3(1.0, 0.0, 0.5)
		for _i in 40:
			await physics_frame
		_check("...and never again", toast._current == last and not toast._body.text.contains("PAUSE MENU"),
			toast._body.text)

	# ── THE LIBRARY: every lesson, read out of the homebase scene ──
	var library_script := preload("res://Character/hud/tutorial_library.gd")
	var lessons: Array = library_script.collect(load("res://maps/depot_level.tscn"))
	var heads: Array = lessons.map(func(l): return str(l["headline"]).to_upper())
	var weapon_lessons := heads.filter(func(h): return h.contains("{1}"))
	_check("the pause-menu library lists the base's lessons (%d)" % lessons.size(), lessons.size() >= 7, str(heads))
	_check("...the weapon keys once, though two signs carry them", weapon_lessons.size() == 1, str(heads))
	_check("...and not the directions or the flavour",
		not heads.any(func(h): return h.contains("GO FORTH") or h.contains("WALK IN") \
			or h.contains("TUTORIAL IS ON") or h.contains("THIS IS YOUR SQUAD") or h.contains("SHOOT SOME")), str(heads))
	var screen: Control = library_script.new()
	root.add_child(screen)
	await process_frame
	var shown := _texts(screen)
	_check("the library screen shows live keys, not tokens",
		shown.contains("R - RELOAD") and not shown.contains("{"), shown.substr(0, 200))
	screen.queue_free()

	# ── AFTER THE TUTORIAL: every sign stands down ──
	world.queue_free()
	for _i in 10:
		await process_frame
	TutorialLabel.veteran_override = 1
	world = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false
	root.add_child(world)
	for _i in 90:
		await physics_frame
	signs.clear()
	_signs(root, signs)
	var live := signs.filter(func(s): return s.toast_text != "" or s.visible)
	_check("a returning player's base has no signs left (%d active)" % live.size(), live.is_empty(), str(live))
	_check("...and nothing that can toast", TutorialToast._signs.is_empty(), str(TutorialToast._signs.size()))

	await _check_opening(world)
	TutorialLabel.veteran_override = -1
	_done()


# ── THE OPENING STATE: the first tutorial starts on a casualty ──
# The two verbs no sign can teach are patching yourself up and picking a
# squadmate up off the floor, so a fresh campaign hands the player both jobs on
# the way in the door. The second muster is the half that matters: the lesson
# ledger has to stop this firing again every time they walk home.
#
# Its own function because it needs the campaign and not the signs, so it still
# runs on the bail-out path below, where there are no lessons in the base to
# stand at.
func _check_opening(world: Node) -> void:
	var cm = world.get_node("CampaignManager")
	cm.reset_campaign()
	cm.on_level_loaded(world.current_level)
	for _i in 40:
		await physics_frame
	var hero: Node = _find(root, "Player")
	var floored := _downed(world)
	_check("the first tutorial opens with one robot down", floored.size() == 1, str(floored))
	_check("...and the player hurt enough to need the repair tool (%d/%d)" % [
		int(hero.health), int(hero.max_health)], int(hero.health) < int(hero.max_health))
	cm.on_level_loaded(world.current_level)
	for _i in 40:
		await physics_frame
	var relapse := _downed(world)
	_check("...and nobody else goes down on a later muster", relapse.is_empty(), str(relapse))


func _done() -> void:
	if FileAccess.file_exists("user://settings_tutorial_test.json"):
		DirAccess.remove_absolute("user://settings_tutorial_test.json")
	print("")
	print("ALL TUTORIAL CHECKS PASS" if _fails == 0 else "%d TUTORIAL CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
