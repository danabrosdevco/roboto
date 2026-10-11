extends SceneTree

# ─────────────────────────────────────────────
# MIGRATE A SAVE — an old campaign.json, brought up to what the game reads now.
#
#   godot --audio-driver Dummy --path . --script res://tools/migrate_save.gd \
#       -- <in.json> <out.json> [profile name] [--keep-won]
#
# THE FORMAT DID NOT CHANGE. SAVE_VERSION is still 1 and CampaignState.from_dict
# is written to tolerate old saves, so the work here is not reshaping records —
# it is the three things the format gained, and checking that every id the save
# names still exists. A save that loads but refers to a frame or an item the
# project has since dropped is worse than one that fails: it comes up looking
# fine with holes in it.
#
# WHAT IT DOES
#   - profile_name, created_utc, last_played_utc. Saves live in user://saves now,
#     one file per profile, and a file with no profile_name has no name in the
#     menu.
#   - campaign_won. See the note by _migrate(): this is the one judgement call,
#     and --keep-won overrides it.
#   - drops empty ids out of the slot arrays
#   - checks every chassis, item and mission id against what is on disk now
#   - LOADS THE RESULT through CampaignState.from_dict and reads it back, so the
#     thing written is a thing the game has actually parsed
#
# It never writes into user://. The output goes where you point it, and putting
# it in place is the player's move.
# ─────────────────────────────────────────────

const CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"
const MISSION_DIR := "res://Campaign/missions"

var _cat: ItemCatalogue
var _mission_ids := {}
var _notes: Array[String] = []
var _problems: Array[String] = []


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: migrate_save.gd -- <in.json> <out.json> [profile name] [--keep-won]")
		quit(2)
		return
	var in_path: String = args[0]
	var out_path: String = args[1]
	var profile := "Old Campaign"
	var keep_won := false
	for i in range(2, args.size()):
		if args[i] == "--keep-won":
			keep_won = true
		else:
			profile = args[i]
	await process_frame

	_cat = load(CATALOGUE)
	if _cat == null:
		printerr("migrate_save: no catalogue at %s" % CATALOGUE)
		quit(1)
		return
	_load_mission_ids()

	var text := FileAccess.get_file_as_string(in_path)
	if text == "":
		printerr("migrate_save: %s is empty or unreadable." % in_path)
		quit(1)
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr("migrate_save: %s does not parse as a campaign." % in_path)
		quit(1)
		return

	var data: Dictionary = parsed
	_audit(data)
	_migrate(data, profile, keep_won)

	# PROVE IT LOADS. Writing a file the game has never parsed is how a
	# migration ships broken: round-trip it through the real loader and read the
	# figures back out before anything hits disk.
	var state := CampaignState.from_dict(data)
	if state == null:
		printerr("migrate_save: the migrated save would not load.")
		quit(1)
		return
	print("")
	print("LOADED BACK: %d robots, %d resources, %d compute earned, %d seats, %d operations cleared"
		% [state.roster.size(), state.available(), state.compute_earned,
			state.supply_cap, state.completed_missions.size()])

	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("migrate_save: could not write %s" % out_path)
		quit(1)
		return
	f.store_string(JSON.stringify(data, "\t", true))
	f.close()
	print("wrote %s" % out_path)

	if not _notes.is_empty():
		print("")
		print("CHANGED")
		for n in _notes:
			print("  - %s" % n)
	if not _problems.is_empty():
		print("")
		print("NEEDS A LOOK")
		for p in _problems:
			print("  ! %s" % p)
	quit(0)


func _load_mission_ids() -> void:
	var dir := DirAccess.open(MISSION_DIR)
	if dir == null:
		_problems.append("could not open %s, so mission ids went unchecked" % MISSION_DIR)
		return
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var m = load("%s/%s" % [MISSION_DIR, file])
		if m != null and "id" in m:
			_mission_ids[String(m.id)] = true


# ── AUDIT ─────────────────────────────────────
#
# Everything the save names, checked against the project as it stands. Nothing
# is corrected here: a save that points at something gone is a decision, not a
# typo, and silently dropping a robot because its frame was retired is the kind
# of helpfulness nobody wants.

func _audit(data: Dictionary) -> void:
	for id in data.get("completed_missions", []):
		if not _mission_ids.has(str(id)):
			_problems.append("completed operation '%s' no longer exists" % id)
	for id in data.get("mission_clears", {}):
		if not _mission_ids.has(str(id)):
			_problems.append("clear count for '%s', an operation that no longer exists" % id)

	var seen_items := {}
	for key in data.get("allocations", {}):
		var parts := str(key).split(":")
		if parts.size() >= 2 and parts[0] == "item":
			seen_items[parts[1]] = true
	for id in data.get("armoury", {}).get("stock", {}):
		seen_items[str(id)] = true
	for id in seen_items:
		if _cat.item(StringName(id)) == null:
			_problems.append("item '%s' is in the save and not in the catalogue" % id)

	var records: Array = data.get("roster", []).duplicate()
	if data.has("player_record"):
		records.append(data["player_record"])
	for r in records:
		if not (r is Dictionary):
			continue
		var who := str(r.get("display_name", "?"))
		var frame := str(r.get("chassis_id", ""))
		if frame != "" and _cat.chassis_def(StringName(frame)) == null:
			_problems.append("%s is a '%s', a frame the catalogue no longer carries" % [who, frame])
		var scene := str(r.get("chassis", ""))
		if scene != "" and not ResourceLoader.exists(scene):
			_problems.append("%s points at %s, which is not there any more" % [who, scene])
		for field in ["weapon_ids", "equipment_ids", "module_ids"]:
			for id in r.get(field, []):
				if str(id) == "":
					continue
				if _cat.item(StringName(str(id))) == null:
					_problems.append("%s carries '%s', which is not in the catalogue" % [who, id])

	# Prices move. The save records what was PAID, which is what it should keep —
	# this only says so out loud, because the difference shows up as spendable
	# resources and should not look like a bug later.
	for key in data.get("allocations", {}):
		var parts := str(key).split(":")
		if parts.size() < 3 or parts[0] != "item":
			continue
		var item := _cat.item(StringName(parts[1]))
		if item == null:
			continue
		var paid := int(data["allocations"][key])
		if paid != item.cost:
			var note := "%s was bought for %d and now costs %d" % [parts[1], paid, item.cost]
			if not _notes.has(note + " (left as paid)"):
				_notes.append(note + " (left as paid)")


# ── MIGRATE ───────────────────────────────────

func _migrate(data: Dictionary, profile: String, keep_won: bool) -> void:
	# Saves live in user://saves now, a file per profile. Without a name the menu
	# has nothing to call it.
	if str(data.get("profile_name", "")) == "":
		data["profile_name"] = profile
		_notes.append("profile_name set to \"%s\"" % profile)
	var now := Time.get_datetime_string_from_system(true)
	if str(data.get("created_utc", "")) == "":
		data["created_utc"] = now
		_notes.append("created_utc stamped (the old format had no dates)")
	if str(data.get("last_played_utc", "")) == "":
		data["last_played_utc"] = now
		_notes.append("last_played_utc stamped")

	# THE JUDGEMENT CALL. campaign_won does not mean "you have a trophy", it
	# means available_missions() returns EVERY operation with no gate at all —
	# including the arena entries and the TEST: Helicopters maps. On the ladder
	# this save was won against that was the end of the content; the ladder has
	# grown since, and Hillfort and Three Rivers now sit BETWEEN operations this
	# save has already cleared. Left true, the campaign reopens as an unsorted
	# list of everything. Set false, it resumes exactly at the new content.
	# Nothing else is lost: the clears, the kills and the squad are untouched.
	if bool(data.get("campaign_won", false)) and not keep_won:
		data["campaign_won"] = false
		_notes.append("campaign_won true -> false, so the ladder gates again "
			+ "(pass --keep-won to leave it)")

	# An empty id in a slot array is a slot nobody filled. Harmless, but it reads
	# back as a fitted item with no name.
	var records: Array = data.get("roster", [])
	var cleaned := 0
	for r in records:
		if not (r is Dictionary):
			continue
		for field in ["weapon_ids", "equipment_ids", "module_ids"]:
			var ids: Array = r.get(field, [])
			var keep: Array = []
			for id in ids:
				if str(id) != "":
					keep.append(str(id))
			if keep.size() != ids.size():
				cleaned += ids.size() - keep.size()
			r[field] = keep
	if cleaned > 0:
		_notes.append("%d empty slot entr%s removed" % [cleaned, "y" if cleaned == 1 else "ies"])
