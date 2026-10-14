extends SceneTree

# ─────────────────────────────────────────────
# THE FRONT PAGE, DRIVEN THE WAY A PLAYER DRIVES IT.
#
# Find the button by what it says on it and press it. That catches a menu that
# builds without error and offers the wrong thing — which is most of the ways
# this screen can be wrong:
#
#   * nothing saved and it offers LOAD CAMPAIGN, which opens an empty list
#   * something saved and it offers no way back into it
#   * BEGIN on the new-campaign form making a campaign with no name, or not
#     making one at all
#   * a campaign deleted from the list and still sitting there
#
# SANDBOXED. SaveSlots.DIR and .LEGACY are redirected before anything runs, so
# this cannot see, write or delete a campaign somebody is actually playing.
#
#   godot --headless --path . --script res://tools/test_profile_menu.gd
# ─────────────────────────────────────────────

const _SaveSlots := preload("res://Campaign/save_slots.gd")
const SANDBOX := "user://test_menu_saves"
const SANDBOX_LEGACY := "user://test_menu_legacy.json"

var _fails: int = 0
var _master: Node = null


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	_SaveSlots.DIR = SANDBOX
	_SaveSlots.LEGACY = SANDBOX_LEGACY
	await process_frame
	_check("the suite is pointed at a sandbox, not the real saves",
		not _SaveSlots.DIR.ends_with("/saves") and not _SaveSlots.LEGACY.ends_with("/campaign.json"),
		"%s | %s" % [_SaveSlots.DIR, _SaveSlots.LEGACY])
	_wipe()

	var master: PackedScene = load("res://Managers/master.tscn")
	_master = master.instantiate()
	root.add_child(_master)
	for _i in 120:
		await process_frame

	await _test_empty()
	await _test_create()
	await _test_depot_populated()
	await _test_state_identity()
	await _test_returning()
	await _test_delete()

	_wipe()
	print("")
	print("ALL MENU CHECKS PASS" if _fails == 0 else "%d MENU CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


# ── NOTHING SAVED: ONE WAY IN ────────────────
func _test_empty() -> void:
	print("")
	print("══ A FIRST LAUNCH ════════════════════════════════════════")
	_master._show_main_menu()
	await process_frame
	var labels := _labels()
	print("     %s" % str(labels))
	_check("it offers START", labels.has("START"))
	_check("...and does NOT offer CONTINUE, which would resume nothing",
		not labels.has("CONTINUE"))
	_check("...nor LOAD CAMPAIGN, which would open an empty list",
		not labels.has("LOAD CAMPAIGN"))


# ── NAMING ONE AND BEGINNING ─────────────────
func _test_create() -> void:
	print("")
	print("══ NAMING A CAMPAIGN ═════════════════════════════════════")
	_master._open_new_campaign()
	await process_frame
	var fields := _fields()
	_check("the form asks for three names", fields.size() == 3, "%d field(s)" % fields.size())
	if fields.size() < 3:
		return
	fields[0].text = "Dana's Run"
	fields[1].text = "Hammer"
	fields[2].text = "DANA"
	_check("BEGIN is on the form", _labels().has("BEGIN"))
	_press("BEGIN")
	await process_frame

	var cm := _campaign()
	_check("a campaign is open afterwards", cm != null and cm.has_open_profile(),
		cm.active_slot if cm != null else "no campaign manager")
	if cm == null:
		return
	_check("...named what was typed", cm.state.profile_name == "Dana's Run", cm.state.profile_name)
	_check("...with the squad named too", cm.state.squad_name == "HAMMER", cm.state.squad_name)
	_check("...and the player", cm.state.player_record.display_name == "DANA",
		cm.state.player_record.display_name)
	_check("...and it is on disk, not only in memory", _SaveSlots.list().size() == 1,
		"%d file(s)" % _SaveSlots.list().size())
	# A roster, because a campaign you cannot play is not a campaign.
	_check("...with a squad seeded into it", cm.state.roster.size() > 0,
		"%d robot(s)" % cm.state.roster.size())



# ── AND THE DEPOT IS ACTUALLY POPULATED ──────
## The bug this is here for: making the menu choose the campaign meant the depot
## loaded BEFORE anyone had chosen one, deployed the squad from an empty roster,
## and came up with no allies at all. Checking that a profile is "open" does not
## catch that — the campaign was open, it was just open too late. So count the
## robots standing in the level.
func _test_depot_populated() -> void:
	print("")
	print("══ THE DEPOT AFTER CHOOSING ══════════════════════════════")
	# A frame first: the old squad is freed when the new one deploys, and a free
	# does not land until the end of the frame.
	await process_frame
	await process_frame
	var cm := _campaign()
	if cm == null:
		_check("there is a campaign manager to ask", false)
		return
	var deployed := 0
	var any := 0
	var factions := {}
	for n in _walk(_master):
		if n.is_in_group("enemies"):
			any += 1
			var fac = n.get("faction")
			factions[fac] = int(factions.get(fac, 0)) + 1
			# ALLIED, not PLAYER. The player is faction 0; the robots that muster
			# with them are 2. Checking for PLAYER counted none of them and read as
			# "the depot is empty" when it was full.
			if fac == Enums.Factions.ALLIED:
				deployed += 1
	var wnode = cm.get_parent()
	print("     bodies in group enemies: %d  factions %s" % [any, str(factions)])
	print("     campaign parent: %s   current_level: %s" % [
		str(wnode.name) if wnode != null else "none",
		str(wnode.get("current_level")) if wnode != null else "n/a"])
	_check("the squad is standing in the depot, not just listed in the save",
		deployed > 0, "%d ally in the level, %d on the roster" % [deployed, cm.state.roster.size()])
	# ONE EACH. Redeploying into a level that already had a squad used to leave
	# the old robots standing, so the depot filled up with duplicates every time
	# a campaign was opened.
	_check("...one robot per roster entry, not two", deployed == cm.state.roster.size(),
		"%d in the level vs %d on the roster" % [deployed, cm.state.roster.size()])
	_check("...and it is the roster that was just opened", cm.state.roster.size() > 0,
		"%d" % cm.state.roster.size())


# ── THE STATE OBJECT SURVIVES A PROFILE CHANGE ──
## Half the game binds to CampaignState's OWN signals and keeps the reference:
## the player's loadout to roster_changed, the squad manager, the wallet, the
## induction. Swapping the object out on load left every one of them listening
## to a state nobody emits on — so fitting a weapon at base changed the record
## and never reached the player's hands or the weapon bar.
##
## restore_from() exists precisely so a save can be read into the state the game
## is already holding, and its own comment says so. This checks it is used.
## Async: every profile change redeploys the squad, and the robots it replaces
## are freed at the end of the frame. Switching three times inside one frame
## piles the teardown up and takes the headless renderer down with it on exit.
func _test_state_identity() -> void:
	print("")
	print("══ THE SAME STATE THROUGHOUT ═════════════════════════════")
	var cm := _campaign()
	if cm == null:
		_check("there is a campaign manager", false)
		return

	var before: CampaignState = cm.state
	var heard := [0]
	# Bound the way the player binds: to the STATE, once, and kept.
	before.roster_changed.connect(func(): heard[0] += 1)

	var made: String = cm.new_profile("Identity", "IDENT", "TESTER")
	for _i in 4:
		await process_frame
	_check("a new campaign keeps the same state object", cm.state == before,
		"same object" if cm.state == before else "REPLACED")
	_check("...so a listener bound before it still hears roster changes", heard[0] > 0,
		"%d signal(s)" % heard[0])

	var heard_after := [0]
	before.roster_changed.connect(func(): heard_after[0] += 1)
	_check("...and the campaign that was made is the open one",
		cm.state.profile_name == "Identity", cm.state.profile_name)

	# And again across a LOAD, which is the path that actually broke.
	cm.new_profile("Other", "OTHER", "SOMEONE")
	for _i in 4:
		await process_frame
	var reloaded: bool = cm.load_profile(made)
	for _i in 4:
		await process_frame
	_check("loading another campaign keeps the same state object too",
		reloaded and cm.state == before, "same object" if cm.state == before else "REPLACED")
	_check("...with the loaded campaign's name, not the blank default",
		cm.state.profile_name == "Identity", cm.state.profile_name)
	_check("...and the listener bound before all of it is still live",
		heard_after[0] > 0, "%d signal(s)" % heard_after[0])

	# PUT THE SANDBOX BACK. This section makes two campaigns of its own, and the
	# sections after it count what is on disk.
	for spare in ["identity", "other"]:
		if _SaveSlots.exists(spare):
			_SaveSlots.delete(spare)
	var first := _SaveSlots.list()
	if not first.is_empty():
		cm.load_profile(String(first[0]["id"]))
	for _i in 6:
		await process_frame

# ── COMING BACK TO IT ────────────────────────
func _test_returning() -> void:
	print("")
	print("══ A SECOND LAUNCH ═══════════════════════════════════════")
	_master._show_main_menu()
	await process_frame
	var labels := _labels()
	print("     %s" % str(labels))
	_check("now it offers CONTINUE", labels.has("CONTINUE"))
	_check("...and NEW CAMPAIGN", labels.has("NEW CAMPAIGN"))
	_check("...and LOAD CAMPAIGN", labels.has("LOAD CAMPAIGN"))
	_check("...and no longer offers START, which would be ambiguous",
		not labels.has("START"))

	# The list shows what you would need to tell them apart.
	_master._open_load_campaign()
	await process_frame
	var rows := _labels()
	var found := false
	for l in rows:
		if l.contains("DANA'S RUN") and l.contains("HAMMER"):
			found = true
	_check("the load list names the campaign and its squad", found, str(rows))
	_check("...and offers to delete it", rows.has("DELETE"))


# ── AND REMOVING IT ──────────────────────────
func _test_delete() -> void:
	print("")
	print("══ DELETING FROM THE MENU ════════════════════════════════")
	_master._open_load_campaign()
	await process_frame
	_press("DELETE")
	await process_frame
	var confirm := _labels()
	print("     %s" % str(confirm))
	# IT HAS TO ASK. Deleting a campaign cannot be undone and the button sits
	# next to the one that opens it.
	_check("it asks before deleting", confirm.has("KEEP IT") and confirm.has("DELETE FOREVER"),
		str(confirm))
	_check("...and says which campaign", _titles().has("DELETE DANA'S RUN?"), str(_titles()))

	_press("KEEP IT")
	await process_frame
	_check("keeping it leaves the campaign alone", _SaveSlots.list().size() == 1,
		"%d left" % _SaveSlots.list().size())

	_press("DELETE")
	await process_frame
	_press("DELETE FOREVER")
	await process_frame
	_check("deleting it removes the file", _SaveSlots.list().is_empty(),
		"%d left" % _SaveSlots.list().size())
	_check("...and the list says so rather than looking broken",
		_labels().has("BACK") and _titles().has("NOTHING SAVED"), str(_titles()))


# ─────────────────────────────────────────────
## This script IS the SceneTree, so there is no get_tree() to call.
func _campaign() -> Node:
	return get_first_node_in_group("campaign")


## Every button on the overlay right now, by its text.
func _labels() -> PackedStringArray:
	var out := PackedStringArray()
	for n in _walk(_master):
		if n is Button:
			out.append((n as Button).text)
	return out


## Every non-button label, which is where titles and empty-state text live.
func _titles() -> PackedStringArray:
	var out := PackedStringArray()
	for n in _walk(_master):
		if n is Label:
			out.append((n as Label).text)
	return out


func _fields() -> Array:
	var out: Array = []
	for n in _walk(_master):
		if n is LineEdit:
			out.append(n)
	return out


## Press the first button whose text starts with `text`. The load rows carry
## their campaign's details in the label, so an exact match would not find them.
func _press(text: String) -> void:
	for n in _walk(_master):
		if n is Button and (n as Button).text.begins_with(text) and not (n as Button).disabled:
			(n as Button).pressed.emit()
			return
	_check("could not find a button starting with '%s'" % text, false, str(_labels()))


## IN TREE ORDER. pop_back made this a reversed depth-first walk, so the three
## name fields came back callsign-first and the test assigned them backwards —
## then blamed the form for swapping them.
func _walk(root: Node) -> Array:
	var out: Array = [root]
	var i := 0
	while i < out.size():
		for c in (out[i] as Node).get_children():
			out.append(c)
		i += 1
	return out


func _wipe() -> void:
	var dir := DirAccess.open(_SaveSlots.DIR)
	if dir != null:
		for f in dir.get_files():
			DirAccess.remove_absolute("%s/%s" % [_SaveSlots.DIR, f])
	if FileAccess.file_exists(_SaveSlots.LEGACY):
		DirAccess.remove_absolute(_SaveSlots.LEGACY)
