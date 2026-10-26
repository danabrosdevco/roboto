extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# A RESTORE MUST LEAVE THE CAMPAIGN THE DICTIONARY DESCRIBES.
#
# Run with:  bash tools/bucket.sh campaign
# Directly:  godot --headless --audio-driver Dummy --path . \
#                --script res://tools/test_restore_from.gd
#
# WHY THIS FILE EXISTS. CampaignState.restore_from() moves fields across by
# hand, and it is not only the rewind after a failed run — Campaign.load_profile
# and Campaign.new_profile both go through it, because half the game holds a
# reference to the state object and rebinding them all is not on the table. So a
# field it forgets is not a rewind nicety. It is a field a LOAD does not load.
#
# It forgot seven of twenty-nine until 2026-10-26: line_marks, line_modules,
# turn, sites, under_attack, under_attack_turn, lessons_seen. Every boot came up
# at turn 0 on the authored board with every production line at Mk 0, and the
# next autosave wrote that over the file. See Backlog SV1.
#
# AND THE GUARD THAT WAS SUPPOSED TO CATCH IT COULD NOT. restore_from's own
# comment named test_endings, which restored a state into ITSELF: a field that
# is not moved already holds the right value, so the check passed on all seven.
# That is Backlog SV3, and it is why the checks below restore into a DIFFERENT
# state in both directions. A test that cannot fail is worse than no test,
# because it is reported as a pass.
#
# tools/probe_save_facts.gd is the exhaustive measurement — it plants a sentinel
# in every field and prints a table. This is the assertion.
#
# WHERE IT WRITES. user://test_restore_from/ and nothing else, and it deletes
# what it writes. It also checks that a campaign with no path of its own writes
# NOTHING, which it does by asserting the legacy user://campaign.json is not
# created — it never opens or reads the player's own saves.
# ─────────────────────────────────────────────

const STATE_SCRIPT := "res://Campaign/campaign_state.gd"
const SANDBOX := "user://test_restore_from"
const WRITTEN := "user://test_restore_from/written.json"

## to_dict key -> the variable it comes off, where the two are spelled
## differently. Same two as probe_save_facts.
const ALIAS := {"next_id": "_next_id", "purchase_counter": "_purchase_counter"}

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	# PACE THE LOOP — see the note in tools/test.sh.
	Engine.max_fps = 60
	test_a_load_arrives_whole()
	test_a_new_campaign_keeps_nothing()
	test_every_field_is_listed()
	test_a_restore_does_not_move_the_file()
	test_a_state_with_no_path_writes_nothing()
	test_saving_stamps_when_it_was_played()
	test_two_restores_of_one_snapshot_do_not_share()

	print("")
	# A RUN THAT ASSERTED NOTHING IS A FAILURE, NOT A PASS, and this suite
	# earned the line: an A/B that broke restore_from with a type error instead
	# of a dropped field made campaign_state.gd fail to compile, every test
	# above abort, and this block print "PASS 0 checks" and exit 0. Which is
	# the one result a suite must never produce.
	if _checks == 0:
		print("FAILED  nothing ran — no check was reached, which is not a pass")
		_failures += 1
	elif _failures == 0:
		print("PASS  %d checks" % _checks)
	else:
		print("FAILED  %d of %d checks" % [_failures, _checks])
	_clean()
	quit(1 if _failures > 0 else 0)


# ── the two directions ────────────────────────

## THE LOAD. A played campaign restored into a state that has never been
## anybody's: every field has to arrive, and a field restore_from forgets shows
## up here as the blank state's value instead of the save's.
func test_a_load_arrives_whole() -> void:
	var played := _played().to_dict()
	var fresh := CampaignState.new()
	fresh.restore_from(played)
	_same_fields("a load arrives whole", fresh.to_dict(), played)


## THE NEW CAMPAIGN. Campaign.new_profile blanks the open state by restoring a
## blank dictionary into it — so a field restore_from forgets is a field the
## previous campaign hands the next one. This is the direction that was
## carrying a finished campaign's board into a brand new profile.
func test_a_new_campaign_keeps_nothing() -> void:
	var blank := CampaignState.new().to_dict()
	var used := CampaignState.from_dict(_played().to_dict())
	used.restore_from(blank)
	_same_fields("a new campaign keeps nothing from the last one", used.to_dict(), blank)


## THE SOURCE, read as text. The two checks above only catch a field whose
## played value differs from a blank one — true for all 29 today, and not
## something a future field can be relied on to be. This one is exhaustive by
## construction: every key to_dict() writes must appear in restore_from's body
## as `field = was.field`. Same technique as probe_save_facts; deliberately a
## separate copy, so the suite does not depend on a probe.
func test_every_field_is_listed() -> void:
	var src := FileAccess.get_file_as_string(STATE_SCRIPT)
	if src == "":
		_check("restore_from's source could be read", false, STATE_SCRIPT)
		return
	var body := _function_body(src, "func restore_from(")
	var re := RegEx.create_from_string("(?m)^\\t(\\w+) = was\\.(\\w+)")
	var moved := {}
	for m in re.search_all(body):
		# Both halves, because `turn = was.sites` would otherwise read as fine.
		if m.get_string(1) == m.get_string(2):
			moved[m.get_string(1)] = true
	var missing: Array[String] = []
	for k in CampaignState.new().to_dict().keys():
		if k == "version":
			continue   # the shape marker, not a field
		if not moved.has(String(ALIAS.get(k, k))):
			missing.append(String(k))
	_check("every to_dict() field is in restore_from's list", missing.is_empty(),
		"not listed: %s" % ", ".join(missing))
	_check("...and restore_from lists nothing that is not a field",
		moved.size() == CampaignState.new().to_dict().size() - 1,
		"%d listed, %d fields" % [moved.size(), CampaignState.new().to_dict().size() - 1])


## WHICH FILE THIS IS SURVIVES A RESTORE. save_path is not in to_dict and must
## not be: a load that adopted the dictionary's idea of where it lives would
## write the loaded campaign back over the file it was read into. Campaign
## sets it immediately after restoring, and this is the reason it can.
func test_a_restore_does_not_move_the_file() -> void:
	var s := CampaignState.new()
	s.save_path = "%s/mine.json" % SANDBOX
	s.restore_from(_played().to_dict())
	_check("a restore does not move the campaign's file", s.save_path == "%s/mine.json" % SANDBOX,
		s.save_path)


# ── the legacy path (Backlog SV2) ─────────────

## A CAMPAIGN WITH NOWHERE TO LIVE IS NEVER WRITTEN. save_path used to default
## to user://campaign.json — the save a player may still be playing — so every
## bare CampaignState.new() came into the world pointed at it, and saving one
## wrote over a real campaign. It did exactly that once.
func test_a_state_with_no_path_writes_nothing() -> void:
	var s := CampaignState.new()
	_check("a bare CampaignState has nowhere to save", s.save_path == "", "'%s'" % s.save_path)
	# The legacy file is the player's. Asserted absent only if it is already
	# absent: a machine that has one is not a failure, and this must not delete
	# it to find out.
	var had := FileAccess.file_exists(CampaignState.SAVE_PATH)
	var wrote := s.save_to_disk()
	_check("...and saving it refuses rather than picking a file", wrote == false)
	if not had:
		_check("...and the legacy save was not created",
			not FileAccess.file_exists(CampaignState.SAVE_PATH))
	else:
		print("note  user://campaign.json already exists on this machine, so the "
			+ "'not created' half was skipped rather than risking it.")


# ── the stamp (Backlog SV4) ───────────────────

## WHEN IT WAS LAST PLAYED, which the profile menu sorts on. It was written to
## the save and read back and set by NOTHING, so the ordering was really file
## mtime and any tool that touched a save moved it to the top of the player's
## list.
func test_saving_stamps_when_it_was_played() -> void:
	if OS.get_cmdline_user_args().has("--no-save"):
		# EVERY EARLY RETURN WARNS. Under --no-save save_to_disk writes nothing
		# and stamps nothing, deliberately — a write that did not happen must
		# not claim a session — so there is no stamp to check.
		push_warning("test_restore_from: --no-save, so the last_played_utc stamp was not checked.")
		print("note  --no-save: the stamp check was skipped, not passed.")
		return
	DirAccess.make_dir_recursive_absolute(SANDBOX)
	var s := _played()
	s.last_played_utc = "2001-01-01T00:00:00"
	s.save_path = WRITTEN
	var wrote := s.save_to_disk()
	_check("a campaign with a path of its own is written", wrote and FileAccess.file_exists(WRITTEN))
	if not wrote:
		return
	_check("...and saving stamps when it was played", s.last_played_utc != "2001-01-01T00:00:00",
		s.last_played_utc)
	var back: Dictionary = CampaignState.load_dict(WRITTEN)
	_check("...and the stamp is in the file, not only in memory",
		str(back.get("last_played_utc", "")) == s.last_played_utc,
		"file '%s', state '%s'" % [str(back.get("last_played_utc", "")), s.last_played_utc])


# ── the shared-dictionary trap ────────────────

## RESOURCES AND DICTIONARIES ARE SHARED. A Dictionary read out of JSON belongs
## to that parse, so two states restored from one snapshot used to be handed the
## same `line_marks` — and adopting a mark on one advanced the other's line.
## `sites` was already duplicated for this reason and the two line dictionaries
## were not.
func test_two_restores_of_one_snapshot_do_not_share() -> void:
	var snap := _played().to_dict()
	var a := CampaignState.new()
	var b := CampaignState.new()
	a.restore_from(snap)
	b.restore_from(snap)
	a.line_marks["probe_frame"] = 99
	a.sites["probe_site"] = {"owner": 2, "since_turn": 9}
	_check("two states restored from one snapshot do not share line_marks",
		int(b.line_marks.get("probe_frame", -1)) == 2, str(b.line_marks))
	_check("...or sites", int((b.sites.get("probe_site", {}) as Dictionary).get("owner", -1)) == 1,
		str(b.sites))
	_check("...or the snapshot itself", int((snap["line_marks"] as Dictionary).get("probe_frame", -1)) == 2,
		str(snap["line_marks"]))


# ── helpers ───────────────────────────────────

## A campaign that has been played, with every field holding something a blank
## one does not. Set field by field rather than through the API on purpose: the
## point is that EVERY field differs, and a campaign driven through missions
## would leave several at their defaults and quietly stop testing them.
##
## The typed arrays are built as typed locals. Assigning an untyped array
## literal to `Array[SoldierRecord]` is the trap that cost the Bulwark its
## voice — see Backlog K1.
func _played() -> CampaignState:
	var s := CampaignState.new()
	s.earned = 4242
	s.allocations = {"unit:probe": 7}
	s.line_marks = {"probe_frame": 2}
	s.line_modules = {"probe_frame": "probe_module"}
	var r := SoldierRecord.new()
	r.id = &"probe_unit"
	r.display_name = "PROBE UNIT"
	var roster: Array[SoldierRecord] = [r]
	s.roster = roster
	var done: Array[StringName] = [&"probe_op"]
	s.completed_missions = done
	s.mission_clears = {"probe_op": 3}
	s.turn = 9
	s.sites = {"probe_site": {"owner": 1, "since_turn": 4}}
	s.under_attack = &"probe_site"
	s.under_attack_turn = 8
	s.completed_tutorial = true
	var lessons: Array[StringName] = [&"probe_lesson"]
	s.lessons_seen = lessons
	s.campaign_won = true
	s.compute_earned = 11
	s.compute_held = {"probe_hold": 3}
	var claimed: Array[String] = ["probe_claim"]
	s.compute_claimed = claimed
	# Above BASE_SEATS, because from_dict raises a recorded cap to seat
	# everyone active and a cap below that would come back changed.
	s.supply_cap = 9
	var unlocks: Array[StringName] = [&"probe_unlock"]
	s.unlocked = unlocks
	s.selected_mission_id = &"probe_op"
	s.squad_name = "PROBE SQUAD"
	s.profile_name = "probe profile"
	s.created_utc = "2026-01-01T00:00:00"
	s.last_played_utc = "2026-01-02T00:00:00"
	s.teams = [{"id": &"probe_team", "name": "PROBE TEAM"}]
	if s.player_record != null:
		s.player_record.display_name = "PROBE PLAYER"
	s.armoury = Armoury.from_dict({"stock": {"probe_item": 2}, "chassis_stock": {}})
	s._next_id = 77
	s._purchase_counter = 55
	return s


## Every key of `want` present and equal in `got`, reported as one check with
## the offending keys named — a bare "the dictionaries differ" is a failure
## nobody can act on.
func _same_fields(label: String, got: Dictionary, want: Dictionary) -> void:
	var differ: Array[String] = []
	for k in want:
		if k == "version":
			continue
		if JSON.stringify(got.get(k)) != JSON.stringify(want[k]):
			differ.append("%s: got %s, wanted %s" % [k, JSON.stringify(got.get(k)),
				JSON.stringify(want[k])])
	_check(label, differ.is_empty(), "\n        " + "\n        ".join(differ))


## The lines of one function, from its signature to the first line that is not
## indented. Copied from probe_save_facts on purpose — see the note on
## test_every_field_is_listed.
func _function_body(src: String, signature: String) -> String:
	var at := src.find(signature)
	if at < 0:
		push_warning("test_restore_from: '%s' not found in %s, so its source check is blank." % [
			signature, STATE_SCRIPT])
		return ""
	var lines := src.substr(at).split("\n")
	var out: PackedStringArray = [lines[0]]
	for i in range(1, lines.size()):
		var l: String = lines[i]
		if l != "" and not l.begins_with("\t") and not l.begins_with(" "):
			break
		out.append(l)
	return "\n".join(out)


func _clean() -> void:
	if FileAccess.file_exists(WRITTEN):
		DirAccess.remove_absolute(WRITTEN)
	DirAccess.remove_absolute(SANDBOX)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	var suffix := ("  — " + detail) if detail != "" else ""
	print("FAIL  %s%s" % [label, suffix])
