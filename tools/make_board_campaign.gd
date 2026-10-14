extends SceneTree

# ─────────────────────────────────────────────
# A CAMPAIGN THAT EXISTS TO BE LOOKED AT.
#
# The operations table shows who holds what, and on a fresh save the answer is
# "nobody holds anything" — eleven grey locked sites and one amber. That is an
# honest board and a useless photograph, so this writes a profile with the
# campaign part-played: some sites taken, some taken repeatedly, the frontier
# open, the rest dark.
#
# IT BUILDS THE SAVE THROUGH CampaignState AND to_dict(), never by writing
# JSON by hand. The format has a dozen fields and a migration path; the only
# way to be sure a generated save is a legal one is to let the class that
# loads it be the class that wrote it.
#
# IT WILL NOT OVERWRITE. A new profile, under a name nobody would pick by
# accident, and it refuses outright if that file already exists. This writes
# into the player's real save directory and nothing in here is worth losing a
# campaign over.
#
#   godot --headless --audio-driver Dummy --path . --script tools/make_board_campaign.gd
# ─────────────────────────────────────────────

const PROFILE_ID := "boardtest"
const PROFILE_NAME := "BOARD TEST"

## How the twelve sites stand. The spread is the point: a run of cleared
## ground behind you, one site cleared more than once, a live frontier, and a
## dark late campaign.
const CLEARED := {
	&"arena_1_contact": 2,
	&"arena_3_firing_line": 1,
	&"arena_5_proving": 3,
	&"hillfort_1_relay": 1,
	&"basin_1_anchor": 1,
	&"coast_1_road": 1,
}


func _init() -> void:
	await process_frame

	# The real directory, explicitly. A tool run sandboxes SaveSlots to
	# user://saves_probe (see SaveSlots._is_tool_run), which is right for every
	# other tool and wrong for this one: a profile written where the game
	# cannot see it is not a profile.
	var dir := "user://saves"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s.json" % [dir, PROFILE_ID]

	if FileAccess.file_exists(path) and not OS.get_cmdline_user_args().has("--force"):
		print("")
		print("  %s already exists. Refusing to overwrite it." % path)
		print("  Delete it yourself, or pass -- --force if you are sure.")
		print("")
		quit(1)
		return

	var cat: ItemCatalogue = load("res://Campaign/items & catalogue/test_item_catalogue.tres")
	var s := CampaignState.new()
	s.catalogue = cat
	s.profile_name = PROFILE_NAME
	s.created_utc = Time.get_datetime_string_from_system(true)
	s.last_played_utc = s.created_utc
	s.earned = 4200
	s.compute_earned = 9

	for id in CLEARED:
		if not s.completed_missions.has(id):
			s.completed_missions.append(id)
		for _i in int(CLEARED[id]):
			s.record_clear(id)

	# A squad worth looking at beside the board, recruited the ordinary way so
	# the ledger balances rather than being handed free robots.
	var built := 0
	for want in ["soldier", "soldier", "rover", "walker", "reclaimer", "spotter"]:
		var frame: ChassisDefinition = cat.chassis_def(StringName(want))
		if frame == null:
			continue
		if s.recruit(frame) != null:
			built += 1

	var text := JSON.stringify(s.to_dict(), "\t")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("  could not open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string(text)
	f.close()

	print("")
	print("  wrote %s" % ProjectSettings.globalize_path(path))
	print("  profile      %s" % PROFILE_NAME)
	print("  cleared      %d sites (%d total clears)" % [CLEARED.size(), _total_clears()])
	print("  squad        %d robots" % built)
	print("  purse        %d of %d earned" % [s.available(), s.earned])
	print("")
	print("  It appears in the game's LOAD CAMPAIGN list as \"%s\"." % PROFILE_NAME)
	print("")
	quit(0)


func _total_clears() -> int:
	var n := 0
	for id in CLEARED:
		n += int(CLEARED[id])
	return n
