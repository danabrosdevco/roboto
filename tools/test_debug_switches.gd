extends SceneTree

# ─────────────────────────────────────────────
# THE DEBUG TAB'S SWITCHES DO WHAT THE ROWS SAY THEY DO.
#
# The pause menu's DEBUG tab has two switches and two handouts, and the whole
# point of the switches is that they are READ LIVE and write nothing: ticking
# one opens the gate, unticking it closes it again, and the campaign save never
# learns either happened. That property is the only reason it is safe to hand a
# playtester, and it lives in two functions a long way from the menu —
# `Campaign.available_missions()` and `Campaign.is_locked()` — so nothing about
# the menu would break if someone changed them.
#
# So this pins the behaviour rather than the wiring: the same campaign, asked
# the same question, with the switch off and then on and then off again. If the
# last of those three does not match the first, something started persisting.
#
# Boots the real world with autosave off: it reads the save on this machine and
# never writes it. Settings go to a probe file for the same reason — the switches
# are stored in settings.json and a test must not leave them on.
# ─────────────────────────────────────────────

const MISSIONS := "debug.unlock_all_missions"
const GEAR := "debug.unlock_all_gear"

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  %s" if ok else "FAIL  %s  " + detail) % label)
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var world: PackedScene = load("res://Env/world.tscn")
	var scene: Node = world.instantiate()
	var cm = scene.get_node("CampaignManager")
	cm.autosave = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var state = cm.state
	_check("(setup) the campaign booted with a state", state != null)
	if state == null:
		_finish()
		return

	# Whatever this machine's save says, start from the switches OFF so the
	# "off" readings below are the campaign's own and not a leftover.
	Settings.set_value(MISSIONS, false)
	Settings.set_value(GEAR, false)
	await process_frame

	# WHICH HALF OF THIS SUITE RUNS. Read once: the switch-biting checks are
	# only meaningful where the tools exist, and the export run asserts the
	# opposite of every one of them further down.
	var editor: bool = Settings.debug_tools_enabled()
	print("      debug_tools_enabled()=%s  (editor=%s template=%s is_debug_build=%s)" % [
		editor, OS.has_feature("editor"), OS.has_feature("template"), OS.is_debug_build()])

	# ── SWITCH ONE: THE LADDER ───────────────────
	var closed: int = cm.available_missions().size()
	# EVERY MISSION THE LADDER CAN OPEN, which is not every mission there is.
	#
	# A DEFENCE IS NOT ON THE LADDER (Phase 6.2). available_missions() filters
	# the defences out BEFORE it looks at the switch, deliberately: a defence
	# answers a raid that is in doubt and exists only while one is waiting, so
	# a switch that opened the ladder AND conjured an attack would make losing
	# ground impossible. See the comment at the top of available_missions().
	#
	# This suite asserted `== cm.missions.size()` and so failed the day the
	# first defence was added — on correct behaviour, which is the worst kind
	# of red.
	var total: int = 0
	var defences: Array = []
	for m in cm.missions:
		if m == null:
			continue
		if m.defence:
			defences.append(String(m.id))
		else:
			total += 1
	print("      %d operation(s) on the ladder, plus %d defence(s) that are "
		% [total, defences.size()] + "never on it: %s" % str(defences))
	_check("(setup) the ladder gates something to begin with", closed < total,
		"%d of %d already open, so this proves nothing" % [closed, total])
	Settings.set_value(MISSIONS, true)
	if editor:
		_check("UNLOCK ALL MISSIONS opens every operation",
			cm.available_missions().size() == total,
			"%d of %d open" % [cm.available_missions().size(), total])
		# ...INCLUDING ONES ALREADY CLEARED. Dropping only the `requires` chain
		# would still retire each non-repeatable mission the moment it was done,
		# so you could reach the last mission and not be able to run it twice.
		var cleared: Array = []
		for m in cm.available_missions():
			if m != null and not m.repeatable and state.completed_missions.has(m.id):
				cleared.append(String(m.id))
		_check("...and a cleared operation is still on the list",
			state.completed_missions.is_empty() or not cleared.is_empty(),
			"this save has cleared %s and none of them came back" % str(state.completed_missions))
	Settings.set_value(MISSIONS, false)
	_check("...and unticking it puts the ladder back exactly as it was",
		cm.available_missions().size() == closed,
		"%d open, was %d" % [cm.available_missions().size(), closed])

	# ── SWITCH TWO: THE HARDWARE ─────────────────
	# Anything whose line is still shut. Found rather than named, so this keeps
	# working as the catalogue is re-tuned. Operations no longer gate kit
	# (Phase 3) — a line is shut until it is paid for — so this walks the
	# catalogue rather than the missions' `unlocks`.
	var gated: StringName = &""
	if cm.catalogue != null:
		for i in cm.catalogue.items:
			if i != null and cm.is_locked(i.id):
				gated = i.id
				break
		if gated == &"":
			for c in cm.catalogue.chassis:
				if c != null and cm.is_locked(c.id):
					gated = c.id
					break
	_check("(setup) something in the catalogue is still locked", gated != &"",
		"this save has unlocked everything, so the switch cannot be tested")
	if gated != &"" and editor:
		Settings.set_value(GEAR, true)
		_check("UNLOCK ALL HARDWARE unlocks %s" % String(gated), not cm.is_locked(gated))
		Settings.set_value(GEAR, false)
		_check("...and unticking it locks %s again" % String(gated), cm.is_locked(gated))

	# NEITHER SWITCH TOUCHES THE SAVE. This is the claim the DEBUG tab makes in
	# so many words, and the reason the switches are a setting rather than a
	# write into the ledger.
	#
	# THE ALLOCATIONS ARE THE UNLOCK SET NOW, so that is what must not move.
	var owned: int = state.allocations.size()
	Settings.set_value(MISSIONS, true)
	Settings.set_value(GEAR, true)
	var _ignored: Array = cm.available_missions()
	if gated != &"":
		var _also: bool = cm.is_locked(gated)
	_check("neither switch writes anything into the campaign",
		state.allocations.size() == owned,
		"allocations went from %d to %d" % [owned, state.allocations.size()])
	Settings.set_value(MISSIONS, false)
	Settings.set_value(GEAR, false)

	# ── WHAT AN EXPORT SEES ──────────────────────
	# The whole tab is editor-only, and "hidden" is not the claim being made:
	# settings.json ships beside the executable as plain text, so the claim is
	# that the switches do NOTHING in a build even when the file says they are
	# on. Run under ROBOTO_DEBUG_TOOLS=0 this suite takes the export branch, so
	# both halves of that are tested rather than one half tested and the other
	# hoped for.
	Settings.set_value(MISSIONS, true)
	Settings.set_value(GEAR, true)
	if editor:
		_check("in the editor the switches bite", cm.available_missions().size() == total)
	else:
		# THE EXPORT BRANCH. Both switches on in the file, and the game behaves
		# as though neither existed.
		_check("in an export UNLOCK ALL MISSIONS does nothing",
			cm.available_missions().size() == closed,
			"%d open with the switch ON, expected the gated %d" % [cm.available_missions().size(), closed])
		if gated != &"":
			_check("...and UNLOCK ALL HARDWARE does nothing", cm.is_locked(gated),
				"%s came unlocked with the switch ON" % String(gated))
		var menu := OptionsMenu.new()
		root.add_child(menu)
		await process_frame
		_check("...and the options screen has no DEBUG tab",
			menu._tab_buttons.size() == OptionsMenu.TABS.size() - 1,
			"%d tab button(s) for %d tabs" % [menu._tab_buttons.size(), OptionsMenu.TABS.size()])
		menu.show_tab(OptionsMenu.TAB_DEBUG)
		await process_frame
		_check("...and asking for it by index lands somewhere else", menu._tab != OptionsMenu.TAB_DEBUG,
			"showed tab %d" % menu._tab)
		menu.queue_free()
	Settings.set_value(MISSIONS, false)
	Settings.set_value(GEAR, false)

	# ── THE HANDOUTS ─────────────────────────────
	# These DO persist, which is exactly why the tab separates them under their
	# own heading. Checked here so the amounts the menu promises are the amounts
	# that arrive.
	var purse: int = state.available()
	state.award(5000)
	_check("GIVE RESOURCES adds 5000 to the purse", state.available() == purse + 5000,
		"%d -> %d" % [purse, state.available()])
	var compute: int = state.compute_free()
	state.award_compute(50)
	_check("GIVE COMPUTE adds 50 unspent", state.compute_free() == compute + 50,
		"%d -> %d" % [compute, state.compute_free()])

	_finish()


func _finish() -> void:
	# Left OFF whatever happened above, including a bail-out: a suite that exits
	# early must not leave the next run of the game with the gates open.
	Settings.set_value(MISSIONS, false)
	Settings.set_value(GEAR, false)
	print("")
	print("ALL DEBUG SWITCH CHECKS PASS" if _fails == 0
		else "%d DEBUG SWITCH CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
