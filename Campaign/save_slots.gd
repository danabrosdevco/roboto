extends RefCounted

# ─────────────────────────────────────────────
# MORE THAN ONE CAMPAIGN AT A TIME.
#
# There was exactly one save, at user://campaign.json, and the only way to start
# again was to delete it by hand. This makes each campaign a file of its own
# under user://saves, named after the profile, so several can exist side by side
# and starting a new one costs nothing.
#
# NO INDEX FILE. The obvious design is a profiles.json listing what exists, and
# the obvious failure is that it drifts out of step with the directory — a save
# deleted by hand leaves a ghost in the menu, a save copied in never appears.
# The directory IS the list. Saves are small (about 10 KB) and there will be a
# handful, so reading them to build a menu costs nothing worth saving.
#
# THE OLD SAVE IS ADOPTED, NOT MOVED. A player mid-campaign must not lose it
# because they updated. adopt_legacy() COPIES user://campaign.json into a
# profile and leaves the original where it is: if this system is ever reverted,
# the old file is still sitting there, still current as of the moment they
# upgraded.
# ─────────────────────────────────────────────

## WHERE SAVES LIVE.
##
## Variables, not constants, so a suite can point them at a sandbox — Settings.path
## is a static var for the same reason.
##
## AND A TOOL RUN NEVER SEES THE PLAYER'S CAMPAIGNS AT ALL. `--script` means
## this is a test or a bench, not the game: tools/smoke.sh boots the real thing
## without it, every suite in tools/ runs with it. Without this split the boot
## path opened whoever played last, so the suites were reading a real campaign —
## one of them failed because it expected a team called INFANTRY and got the
## squad name out of somebody's actual save — and anything that wrote would have
## been writing into it.
static var DIR := _default_dir()
static var LEGACY := _default_legacy()


static func _is_tool_run() -> bool:
	return OS.get_cmdline_args().has("--script")


static func _default_dir() -> String:
	return "user://saves_probe" if _is_tool_run() else "user://saves"


static func _default_legacy() -> String:
	return "user://campaign_probe.json" if _is_tool_run() else "user://campaign.json"
const EXT := ".json"

## What a profile is called when the player has not said. Not "NAMELESS": that
## is the squad's default, and a save list full of NAMELESS is the problem this
## exists to solve.
const UNTITLED := "Campaign"


## Make sure user://saves exists. False means the save directory could not be
## created, which is worth saying out loud — every campaign write will fail.
static func ensure_dir() -> bool:
	# `-- --no-save` again. Nothing will be written under this flag, so there is
	# nothing to make room for — and creating the directory anyway left an empty
	# user://saves behind after every smoke run, which makes the flag a half-truth.
	# True rather than false: the caller carries on with a campaign in memory,
	# which is what a boot-and-look-for-errors run needs.
	if OS.get_cmdline_user_args().has("--no-save"):
		return true
	if DirAccess.dir_exists_absolute(DIR):
		return true
	var err := DirAccess.make_dir_recursive_absolute(DIR)
	if err != OK:
		push_error("SaveSlots: could not create %s (%s). Campaigns cannot be saved." % [
			DIR, error_string(err)])
		return false
	return true


static func path_for(id: String) -> String:
	return "%s/%s%s" % [DIR, id, EXT]


static func exists(id: String) -> bool:
	return id != "" and FileAccess.file_exists(path_for(id))


## A filename-safe id from whatever the player typed. Letters, digits and
## hyphens; everything else becomes a hyphen. Empty input still has to produce
## something, or the file is called ".json" and is invisible.
static func slug(text: String) -> String:
	var out := ""
	for c in text.strip_edges().to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif out != "" and not out.ends_with("-"):
			out += "-"
	out = out.trim_suffix("-")
	return out if out != "" else "campaign"


## `wanted` as an id nothing is using yet. Two campaigns may share a NAME — the
## player can call both of them Hammer if they like — but not a file.
static func unique_id(wanted: String) -> String:
	var base := slug(wanted)
	if not exists(base):
		return base
	var n := 2
	while exists("%s-%d" % [base, n]):
		n += 1
	return "%s-%d" % [base, n]


## Every campaign on disk, most recently played first.
##
## Each entry is what a menu needs without having to load the save properly:
## { id, path, profile_name, squad_name, player_name, missions, resources,
##   day, last_played, created, broken }
##
## `broken` marks a file that is present but unreadable. It is still listed, on
## purpose: a save that has gone bad should be visible and deletable rather than
## quietly absent, which reads as "the game ate my campaign".
static func list() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out                      # no saves yet; not an error
	for f in dir.get_files():
		if not f.ends_with(EXT):
			continue
		out.append(_summarise("%s/%s" % [DIR, f], f.trim_suffix(EXT)))
	out.sort_custom(func(a, b): return String(a["last_played"]) > String(b["last_played"]))
	return out


## The id of the campaign to open when nobody has chosen one — the one most
## recently played. Empty when there are none.
static func most_recent() -> String:
	var all := list()
	for entry in all:
		if not entry["broken"]:
			return String(entry["id"])
	return ""


static func delete(id: String) -> bool:
	if not exists(id):
		push_warning("SaveSlots: asked to delete '%s', which is not there." % id)
		return false
	var err := DirAccess.remove_absolute(path_for(id))
	if err != OK:
		push_error("SaveSlots: could not delete %s (%s)." % [path_for(id), error_string(err)])
		return false
	return true


## Copy the single old save into a profile, once, and answer with its id.
##
## Returns "" when there is nothing to adopt — no legacy file, or profiles
## already exist, which means this has run before and the player has moved on.
## The original is LEFT ALONE. See the note at the top.
static func adopt_legacy() -> String:
	# `-- --no-save`: a run that boots the real game to look for errors
	# (tools/smoke.sh) must not reach into the player's data, and adoption WRITES
	# — it would create user://saves and copy their campaign into it as a side
	# effect of running a test. CampaignState.save_to_disk honours the same flag;
	# this one goes through FileAccess directly and so has to check for itself.
	if OS.get_cmdline_user_args().has("--no-save"):
		return ""
	if not FileAccess.file_exists(LEGACY):
		return ""
	if not list().is_empty():
		return ""                       # already adopted, or they have real profiles
	if not ensure_dir():
		return ""

	var text := ""
	var src := FileAccess.open(LEGACY, FileAccess.READ)
	if src == null:
		push_warning("SaveSlots: %s exists but could not be read, so it was not adopted. It has not been touched." % LEGACY)
		return ""
	text = src.get_as_text()
	src.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveSlots: %s is not readable as a campaign, so it was not adopted. It has not been touched." % LEGACY)
		return ""
	var data: Dictionary = parsed
	# Name it after the squad, which is the only name the old format had.
	var squad := str(data.get("squad_name", "")).strip_edges()
	var wanted: String = squad if squad != "" and squad != "NAMELESS" else UNTITLED
	data["profile_name"] = wanted
	var id := unique_id(wanted)

	var dst := FileAccess.open(path_for(id), FileAccess.WRITE)
	if dst == null:
		push_error("SaveSlots: could not write %s while adopting the old save; it has been left where it was." % path_for(id))
		return ""
	dst.store_string(JSON.stringify(data, "\t"))
	dst.close()
	print("[SaveSlots] adopted %s as profile '%s' (%s). The original is untouched." % [
		LEGACY, wanted, id])
	return id


# ─────────────────────────────────────────────
# INTERNALS
# ─────────────────────────────────────────────

static func _summarise(path: String, id: String) -> Dictionary:
	var entry := {
		"id": id, "path": path, "profile_name": id, "squad_name": "",
		"player_name": "", "missions": 0, "resources": 0, "day": 0,
		"last_played": "", "created": "", "broken": true,
	}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return entry
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return entry
	var d: Dictionary = parsed
	entry["broken"] = false
	entry["profile_name"] = str(d.get("profile_name", "")).strip_edges()
	if entry["profile_name"] == "":
		entry["profile_name"] = str(d.get("squad_name", UNTITLED))
	entry["squad_name"] = str(d.get("squad_name", ""))
	entry["last_played"] = str(d.get("last_played_utc", ""))
	entry["created"] = str(d.get("created_utc", ""))
	entry["resources"] = int(d.get("earned", 0))
	var done = d.get("completed_missions", [])
	entry["missions"] = (done as Array).size() if done is Array else 0
	var rec = d.get("player_record", null)
	if rec is Dictionary:
		entry["player_name"] = str((rec as Dictionary).get("display_name", ""))
	# A file that is modified later than its own stamp is still the newest thing
	# the player touched, so fall back to the filesystem rather than sorting a
	# save written before stamps existed to the bottom of the list forever.
	if entry["last_played"] == "":
		entry["last_played"] = Time.get_datetime_string_from_unix_time(int(FileAccess.get_modified_time(path)))
	return entry
