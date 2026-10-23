extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# MORE THAN ONE CAMPAIGN, AND THE OLD ONE SURVIVES.
#
# There was one save at user://campaign.json and one way to start over: delete
# it by hand. Campaigns are files under user://saves now.
#
# THE FIRST CHECK IS THE IMPORTANT ONE. Somebody is mid-campaign when they take
# this update. Their save must still be there, still theirs, and still readable
# by the version they came from if they ever go back — so adopt_legacy COPIES it
# and the original is never written to or removed. A save system that eats one
# campaign to give you five is not an improvement.
#
# Everything here runs against a SANDBOX directory, never user://saves, so the
# suite cannot touch a real campaign.
#
#   godot --headless --path . --script res://tools/test_profiles.gd
# ─────────────────────────────────────────────

const _SaveSlots := preload("res://Campaign/save_slots.gd")
## SANDBOXED. Both paths are redirected before anything is written: the legacy
## path defaults to the real user://campaign.json, and this suite deletes what it
## writes. Pointed at the real file that cleanup destroys a campaign somebody is
## playing — which is the exact failure this whole feature exists to prevent.
const SANDBOX := "user://test_profiles"
const SANDBOX_LEGACY := "user://test_profiles_legacy.json"

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	_SaveSlots.DIR = SANDBOX
	_SaveSlots.LEGACY = SANDBOX_LEGACY
	await process_frame
	_check("the suite is pointed at a sandbox, not the real save",
		_SaveSlots.DIR == SANDBOX and _SaveSlots.LEGACY == SANDBOX_LEGACY
			and not _SaveSlots.LEGACY.ends_with("/campaign.json"),
		"%s | %s" % [_SaveSlots.DIR, _SaveSlots.LEGACY])
	_clean()

	_test_slug()
	_test_adopt()
	_test_never_writes_without_a_profile()
	_test_many()
	_test_delete()
	_test_outdated()

	_clean()
	print("")
	print("ALL PROFILE CHECKS PASS" if _fails == 0 else "%d PROFILE CHECK(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


# ── NAMES BECOME FILENAMES ───────────────────
func _test_slug() -> void:
	print("")
	print("══ NAMING ════════════════════════════════════════════════")
	_check("a plain name becomes a plain id", _SaveSlots.slug("Hammer") == "hammer",
		_SaveSlots.slug("Hammer"))
	_check("spaces and punctuation become hyphens",
		_SaveSlots.slug("Dana's  Second Run!") == "dana-s-second-run",
		_SaveSlots.slug("Dana's  Second Run!"))
	# A name of nothing but punctuation still has to produce a filename, or the
	# save is called ".json" and is invisible to the player and the menu alike.
	_check("a name with nothing usable in it still makes a file",
		_SaveSlots.slug("***") == "campaign", _SaveSlots.slug("***"))
	_check("...and so does an empty one", _SaveSlots.slug("") == "campaign")


# ── THE OLD SAVE IS ADOPTED, NOT EATEN ───────
func _test_adopt() -> void:
	print("")
	print("══ THE SAVE SOMEBODY IS ALREADY PLAYING ══════════════════")
	# A legacy save, shaped like the real thing.
	var legacy := {
		"version": 1, "squad_name": "HAMMER", "earned": 1234,
		"completed_missions": ["valley", "coast_1_road"],
		"player_record": {"display_name": "DANA"},
	}
	var before := JSON.stringify(legacy, "\t")
	_write(_SaveSlots.LEGACY, before)

	var id := _SaveSlots.adopt_legacy()
	_check("the old campaign.json is adopted as a profile", id != "", "id '%s'" % id)

	# THE POINT OF ALL THIS.
	_check("...and the original file is still there",
		FileAccess.file_exists(_SaveSlots.LEGACY))
	_check("...byte for byte unchanged, so going back still works",
		_read(_SaveSlots.LEGACY) == before)

	var all := _SaveSlots.list()
	_check("it shows up in the list exactly once", all.size() == 1, "%d profile(s)" % all.size())
	if all.size() == 1:
		var e: Dictionary = all[0]
		_check("...named after the squad, which is the only name it had",
			String(e["profile_name"]) == "HAMMER", str(e["profile_name"]))
		_check("...carrying its progress for the menu to show",
			int(e["missions"]) == 2 and int(e["resources"]) == 1234
				and String(e["player_name"]) == "DANA",
			"%d missions, %d resources, player %s" % [e["missions"], e["resources"], e["player_name"]])
		_check("...and not marked broken", not e["broken"])

	# Running twice must not make a second copy.
	var again := _SaveSlots.adopt_legacy()
	_check("adopting again does nothing — no duplicate profile", again == "",
		"returned '%s', %d profile(s)" % [again, _SaveSlots.list().size()])



# ── A CAMPAIGN THAT IS NOT A PROFILE IS NEVER WRITTEN ──
## THE WORST BUG THIS FEATURE HAD, AND IT DESTROYED A REAL CAMPAIGN.
##
## Before the player picks anything, a scratch campaign stands behind the main
## menu so the depot is not empty. It is not a profile and has no file. But
## save_to_disk fell back to SAVE_PATH when it had no path of its own — and
## SAVE_PATH is user://campaign.json, the save the player had been playing for
## eight missions. One roster change behind the menu overwrote it with a brand
## new campaign: 10,557 bytes of progress replaced by 3,445 bytes of nothing.
##
## It was only recoverable because adopt_legacy had already copied it.
##
## So: no path means NO WRITE, anywhere, ever. Not a default, not a fallback.
func _test_never_writes_without_a_profile() -> void:
	print("")
	print("══ A CAMPAIGN WITH NOWHERE TO LIVE ═══════════════════════")
	# The legacy file already holds the save _test_adopt wrote. Keep it, and put
	# it back afterwards: this section only needs SOMETHING there to notice being
	# clobbered, and the check at the end needs the original still intact.
	var original := _read(_SaveSlots.LEGACY)
	var marker := "DO NOT OVERWRITE ME"
	_write(_SaveSlots.LEGACY, marker)

	var scratch := CampaignState.new()
	scratch.save_path = ""
	scratch.earned = 999
	_check("saving a campaign with no file is refused", not scratch.save_to_disk())
	_check("...and the legacy save is untouched", _read(_SaveSlots.LEGACY) == marker,
		_read(_SaveSlots.LEGACY).left(40))

	# The specific thing that went wrong: asking for the default path must not
	# quietly resolve to the player's save.
	_check("...even when asked to save with no argument at all",
		not scratch.save_to_disk() and _read(_SaveSlots.LEGACY) == marker)

	# And one that DOES have a file still writes, or the guard has gone too far
	# and nothing saves at all.
	var real := CampaignState.new()
	real.save_path = "%s/writes-ok.json" % _SaveSlots.DIR
	real.earned = 42
	_SaveSlots.ensure_dir()
	_check("a campaign that IS a profile still saves", real.save_to_disk()
		and FileAccess.file_exists(real.save_path))
	# Cleaned up here rather than at the end: the next section counts what is in
	# the sandbox, and this one is not one of its campaigns.
	if FileAccess.file_exists(real.save_path):
		DirAccess.remove_absolute(real.save_path)
	# The legacy file is PUT BACK as it was. A later check asserts it survived
	# everything, which is the whole point of adopting rather than moving.
	_write(_SaveSlots.LEGACY, original)

# ── SEVERAL CAMPAIGNS SIDE BY SIDE ───────────
func _test_many() -> void:
	print("")
	print("══ SEVERAL AT ONCE ═══════════════════════════════════════")
	_make("Hammer", "HAMMER", "DANA")           # same NAME as the adopted one
	_make("Anvil", "ANVIL", "RIO")
	var all := _SaveSlots.list()
	_check("three campaigns can exist together", all.size() == 3, "%d" % all.size())

	var ids := {}
	for e in all:
		ids[String(e["id"])] = true
	_check("...each with its own file, even when two share a name",
		ids.size() == 3, str(ids.keys()))

	# The menu opens the one you were last in.
	var recent := _SaveSlots.most_recent()
	_check("the most recently played one is offered first", recent != "", recent)

	var names := PackedStringArray()
	for e in all:
		names.append("%s/%s" % [e["profile_name"], e["squad_name"]])
	print("     %s" % " | ".join(names))


# ── AND THEY CAN BE REMOVED ──────────────────
func _test_delete() -> void:
	print("")
	print("══ DELETING ══════════════════════════════════════════════")
	var all := _SaveSlots.list()
	var victim := String(all[0]["id"])
	_check("a campaign can be deleted", _SaveSlots.delete(victim))
	_check("...and is gone from the list", _SaveSlots.list().size() == all.size() - 1,
		"%d left" % _SaveSlots.list().size())
	# Asking twice is a warning, not a crash.
	_check("deleting one that is not there is refused, not fatal",
		not _SaveSlots.delete(victim))
	_check("the old campaign.json is STILL there after all of that",
		FileAccess.file_exists(_SaveSlots.LEGACY))


# ─────────────────────────────────────────────
## A CAMPAIGN FROM AN OLDER BUILD.
##
## The Mark system took SAVE_VERSION to 2 and v1 saves are not loadable: they
## describe robots carrying modules fitted one at a time from a shop that no
## longer exists. The human's call was to drop them rather than invent a
## migration nobody can verify.
##
## WHAT THIS IS REALLY ABOUT IS HOW IT IS TOLD. "Old" and "corrupt" are
## different things to say to somebody about their campaign, and the easy
## implementation — reuse `broken` — tells half the players something untrue
## and frightening about a file that is perfectly intact. And nothing deletes
## it: refusing to load is the whole requirement.
func _test_outdated() -> void:
	_clean()
	_make("Current Run", "Bravo", "Dana")
	var old_path := _SaveSlots.path_for(_SaveSlots.unique_id("Old Run"))
	_write(old_path, JSON.stringify({
		"version": 1, "profile_name": "Old Run", "squad_name": "Alpha",
		"earned": 4200, "completed_missions": ["arena_3_firing_line"],
		"player_record": {"display_name": "Dana"},
		"last_played_utc": Time.get_datetime_string_from_system(true),
	}, "\t"))

	var all := _SaveSlots.list()
	_check("an older build's campaign is still listed", all.size() == 2,
		"%d profile(s)" % all.size())
	var old_entry := {}
	var new_entry := {}
	for e in all:
		if String(e["profile_name"]) == "Old Run":
			old_entry = e
		elif String(e["profile_name"]) == "Current Run":
			new_entry = e
	if old_entry.is_empty() or new_entry.is_empty():
		_check("both profiles are in the list", false,
			str(all.map(func(e): return e["profile_name"])))
		return

	_check("...and is marked as from an older build", bool(old_entry["outdated"]))
	_check("...and NOT as broken, because it is not damaged",
		not bool(old_entry["broken"]),
		"calling an old campaign corrupt is untrue and frightening")
	_check("...while the current one is neither",
		not bool(new_entry["outdated"]) and not bool(new_entry["broken"]))

	# It still shows what it was, so the player can tell which campaign they
	# are being asked to give up.
	_check("...and it still shows its name and progress",
		String(old_entry["profile_name"]) == "Old Run"
			and int(old_entry["resources"]) == 4200
			and int(old_entry["missions"]) == 1,
		str(old_entry))

	_check("the game does not open into it",
		_SaveSlots.most_recent() != String(old_entry["id"]),
		"most_recent picked '%s'" % _SaveSlots.most_recent())
	_check("...it opens into the playable one instead",
		_SaveSlots.most_recent() == String(new_entry["id"]))
	_check("loading it is refused", CampaignState.load_from_disk(old_path) == null)
	_check("...and the file is left exactly where it was",
		FileAccess.file_exists(old_path),
		"refusing to load is the requirement; deleting is not")


# ─────────────────────────────────────────────
## OFF THE CONSTANT, NOT A LITERAL. These fixtures stand for campaigns this
## build can play; writing a fixed version number meant that the day
## SAVE_VERSION moved, every profile in this suite silently became an OLD
## profile and the suite started testing the opposite of what it says.
## _test_outdated below is where an old one is written on purpose.
func _make(profile: String, squad: String, who: String) -> void:
	var d := {"version": CampaignState.SAVE_VERSION,
		"profile_name": profile, "squad_name": squad,
		"earned": 10, "completed_missions": [],
		"player_record": {"display_name": who},
		"last_played_utc": Time.get_datetime_string_from_system(true)}
	_write(_SaveSlots.path_for(_SaveSlots.unique_id(profile)), JSON.stringify(d, "\t"))


func _write(path: String, text: String) -> void:
	_SaveSlots.ensure_dir()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


## Everything this suite made, and nothing it did not. The legacy path it writes
## is the REAL user://campaign.json, so it is removed again at both ends — a test
## must not leave a fake campaign where the game will find it.
func _clean() -> void:
	var dir := DirAccess.open(_SaveSlots.DIR)
	if dir != null:
		for f in dir.get_files():
			DirAccess.remove_absolute("%s/%s" % [_SaveSlots.DIR, f])
	if FileAccess.file_exists(_SaveSlots.LEGACY):
		DirAccess.remove_absolute(_SaveSlots.LEGACY)
	if DirAccess.dir_exists_absolute(_SaveSlots.DIR) and _SaveSlots.DIR == SANDBOX:
		DirAccess.remove_absolute(_SaveSlots.DIR)
