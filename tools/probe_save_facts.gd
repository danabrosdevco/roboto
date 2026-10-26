extends SceneTree
# REPORTS: prints the table Reference/Saves and profiles.md asserts; tools/test_restore_from.gd is the suite that fails on the gap

# ─────────────────────────────────────────────
# WHAT A SAVE ACTUALLY HOLDS, AND WHAT A RESTORE QUIETLY KEEPS.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_save_facts.gd -- --no-save
#
# The vault note `Reference/Saves and profiles.md` is written from this and
# names it in its `verified-by`. Re-run it before trusting the note.
#
# THE POINT OF IT. CampaignState.restore_from() parses through from_dict and
# then MOVES the fields across by hand, because half the game holds the old
# object. A field added to to_dict() and not to that list is kept across a
# restore with no error. It used to name test_endings as its guard — and
# test_endings round-tripped a state into ITSELF, where a field that is not
# moved already holds the right value. It could not fail. This probe restores a
# state into a DIFFERENT one, with a sentinel in every field, and reports which
# sentinels survive.
#
# THE GAP WAS SEVEN FIELDS AND IS NOW NONE (Backlog SV1, 2026-10-26): before
# the fix §2 printed NOT MOVED (7) — lessons_seen, line_marks, line_modules,
# sites, turn, under_attack, under_attack_turn — and §3 printed the same seven
# dropped by a load and carried into the next profile. This probe still reports
# rather than asserting, because its sentinels are the exhaustive measurement;
# tools/test_restore_from.gd is the campaign-bucket suite that goes red if the
# gap ever reopens.
#
# restore_from is not only the rewind after a failed run. Campaign.load_profile
# and Campaign.new_profile both restore INTO the state the game is already
# holding, so the same gap is what one profile hands the next. The second pass
# replays both through the real CampaignManager, built from world.tscn's own
# scene values.
#
# WHERE IT WRITES. user://probe_save_facts/ and nothing else — SaveSlots.DIR
# and LEGACY are pointed there before the campaign exists. Under `--no-save`
# save_to_disk writes nothing, so the write-and-read-back pass stores the
# dictionary itself, with exactly save_to_disk's serialisation, and says so.
# Everything it writes it deletes. It READS the player's own saves to list
# their keys and versions, and opens them read-only.
# ─────────────────────────────────────────────

const _SaveSlots := preload("res://Campaign/save_slots.gd")
const CAMPAIGN_SCRIPT := "res://Campaign/campaign.gd"
const STATE_SCRIPT := "res://Campaign/campaign_state.gd"
const WORLD := "res://Env/world.tscn"

const SANDBOX := "user://probe_save_facts"
const SANDBOX_SAVES := "user://probe_save_facts/saves"
const SANDBOX_LEGACY := "user://probe_save_facts/legacy.json"
const WRITTEN := "user://probe_save_facts/written.json"
const VIA_SAVE_TO_DISK := "user://probe_save_facts/via_save_to_disk.json"

## The player's files. Stat'd before and after so the report can say they were
## not touched, and read (never opened for writing) for their real key lists.
const PLAYER_FILES := ["user://campaign.json", "user://saves"]

## to_dict key -> script variable, where the two are spelled differently.
const STATE_ALIAS := {"next_id": "_next_id", "purchase_counter": "_purchase_counter"}
const RECORD_ALIAS := {"team": "team_id", "chassis": "chassis_scene", "weapon": "weapon_scene"}

## What a dictionary sentinel holds, where 7 would not parse. Anything absent
## gets 7.
const SENTINEL_VALUE := {
	"sites": {"owner": 1, "since_turn": 1},
	"line_modules": "probe_module",
}

var _wrote: Array[String] = []


func _init() -> void:
	Engine.max_fps = 60   # a --script run has no frame cap and starves physics
	Settings.path = "user://settings_probe.json"
	# Before anything can build a campaign: the sandbox, not the backstop.
	_SaveSlots.DIR = SANDBOX_SAVES
	_SaveSlots.LEGACY = SANDBOX_LEGACY
	var no_save := OS.get_cmdline_user_args().has("--no-save")
	var before := _stat_player_files()
	await process_frame

	print("══ WHERE THIS RUN POINTS ═════════════════════════════════")
	# user:// is named after config/name in project.godot. Renaming the project
	# moved it once (Roboto -> Data Center Wars, 2026-10-06), and every save
	# made before that is in a folder this build never opens.
	print("  user://              %s" % OS.get_user_data_dir())
	print("  --no-save            %s" % ("yes" if no_save else "NO — save_to_disk will write (sandbox paths only)"))
	print("  SaveSlots.DIR        %s" % _SaveSlots.DIR)
	print("  SaveSlots.LEGACY     %s" % _SaveSlots.LEGACY)
	print("  CampaignState.SAVE_PATH       %s" % CampaignState.SAVE_PATH)
	# NOT COVERED BY THE TOOL-RUN BACKSTOP. _is_tool_run swaps SaveSlots' paths;
	# this default is a const, and every bare CampaignState.new() carries it.
	print("  CampaignState.new().save_path %s" % CampaignState.new().save_path)
	print("  SAVE_VERSION         %d" % CampaignState.SAVE_VERSION)

	_report_shape()
	_report_restore_gap()
	await _report_profile_paths()
	_report_migrate()
	_report_write_and_read_back(no_save)
	_report_player_saves()

	_clean()
	var after := _stat_player_files()
	print("")
	print("══ THE PLAYER'S FILES ════════════════════════════════════")
	for p in before:
		print("  %-26s %s" % [p, "unchanged" if before[p] == after.get(p) else "CHANGED: %s -> %s" % [before[p], after.get(p)]])
	print("  this run wrote only: %s" % (", ".join(_wrote) if not _wrote.is_empty() else "nothing"))
	quit(0)


# ── 1. THE SHAPE ─────────────────────────────
## Every key to_dict writes against every script variable, and what from_dict
## reads against what to_dict writes. The two disagreeing is the finding.
func _report_shape() -> void:
	print("")
	print("══ 1. THE SHAPE OF A v%d SAVE ═════════════════════════════" % CampaignState.SAVE_VERSION)
	var s := CampaignState.new()
	var keys: Array = s.to_dict().keys()
	keys.sort()
	print("  top-level keys (%d): %s" % [keys.size(), ", ".join(keys)])
	var rec_keys: Array = SoldierRecord.new().to_dict().keys()
	rec_keys.sort()
	print("  roster[] / player_record keys (%d): %s" % [rec_keys.size(), ", ".join(rec_keys)])
	print("  armoury keys: %s" % ", ".join(Armoury.new().to_dict().keys()))

	_compare_vars("CampaignState", s, keys, STATE_ALIAS)
	_compare_vars("SoldierRecord", SoldierRecord.new(), rec_keys, RECORD_ALIAS)
	_compare_vars("Armoury", Armoury.new(), Armoury.new().to_dict().keys(), {})

	var src := FileAccess.get_file_as_string(STATE_SCRIPT)
	var body := _function_body(src, "static func from_dict(")
	var read := _keys_read(body)
	var unread: Array = keys.filter(func(k): return not read.has(k))
	var unwritten: Array = read.keys().filter(func(k): return not keys.has(k))
	print("  written by to_dict, not read by from_dict: %s" % (", ".join(unread) if not unread.is_empty() else "none"))
	print("  read by from_dict, not written by to_dict: %s" % (", ".join(unwritten) if not unwritten.is_empty() else "none"))

	# A SNAPSHOT THAT IS NOT ONE. _pre_run = state.to_dict() is the rewind, and
	# any container handed back by reference keeps changing after it is taken —
	# so whatever the run does to it, the rewind puts back the run's version.
	var live := CampaignState.new()
	live.allocations["probe"] = 1
	var snap := live.to_dict()
	var shared: Array[String] = []
	shared.append_array(_by_reference("", live, snap, STATE_ALIAS))
	shared.append_array(_by_reference("armoury.", live.armoury, snap["armoury"], {}))
	shared.append_array(_by_reference("player_record.", live.player_record, snap["player_record"], RECORD_ALIAS))
	print("  to_dict values that ARE the live container, not a copy: %s" % (", ".join(shared) if not shared.is_empty() else "none"))

	# WRITTEN AND READ, BUT IS IT EVER SET? A stamp nothing stamps is a field
	# that round-trips forever as its default — SaveSlots sorts the menu on it.
	for stamp in ["created_utc", "last_played_utc"]:
		var setters := _assignments(stamp)
		print("  who sets %s: %s" % [stamp, ", ".join(setters) if not setters.is_empty() else "NOTHING in game code"])


func _by_reference(prefix: String, obj: Object, d: Dictionary, alias: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k in d:
		var field: String = alias.get(k, k)
		if not (field in obj):
			continue
		var v = obj.get(field)
		if (v is Dictionary or v is Array) and is_same(v, d[k]):
			out.append(prefix + k)
	return out


func _compare_vars(label: String, obj: Object, keys: Array, alias: Dictionary) -> void:
	var saved := {}
	for k in keys:
		saved[alias.get(k, k)] = true
	var not_saved: Array[String] = []
	for p in obj.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n := String(p["name"])
		if saved.has(n):
			saved.erase(n)
			continue
		var exported := (int(p["usage"]) & PROPERTY_USAGE_STORAGE) != 0
		not_saved.append("%s%s" % [n, " (@export)" if exported else ""])
	print("  %s variables NOT in to_dict: %s" % [label, ", ".join(not_saved) if not not_saved.is_empty() else "none"])
	if not saved.is_empty():
		print("  %s to_dict keys with no variable of that name: %s" % [label, ", ".join(saved.keys())])


# ── 2. THE RESTORE GAP ───────────────────────
## A state full of sentinels, restored from a blank dictionary. Every field
## restore_from moves comes back blank; every field it does not still holds
## its sentinel.
func _report_restore_gap() -> void:
	print("")
	print("══ 2. WHAT restore_from() DOES NOT MOVE ══════════════════")
	var blank := CampaignState.new().to_dict()
	var marked := _sentinel_dict(blank)
	var marked_rt := CampaignState.from_dict(marked).to_dict()
	var blank_rt := CampaignState.from_dict(blank).to_dict()

	var s := CampaignState.from_dict(marked)
	s.restore_from(blank)
	var after := s.to_dict()

	var src := FileAccess.get_file_as_string(STATE_SCRIPT)
	var listed := _moved_fields(_function_body(src, "func restore_from("))

	var not_moved: Array[String] = []
	var untested: Array[String] = []
	var keys: Array = blank.keys()
	keys.sort()
	print("  %-22s %-10s %s" % ["key", "measured", "restore_from's own list"])
	for k in keys:
		if k == "version":
			continue
		var verdict := ""
		if _j(marked_rt[k]) == _j(blank_rt[k]):
			verdict = "UNTESTED"     # the sentinel did not survive from_dict
			untested.append(k)
		elif _j(after[k]) == _j(marked_rt[k]):
			verdict = "KEPT"
			not_moved.append(k)
		elif _j(after[k]) == _j(blank_rt[k]):
			verdict = "moved"
		else:
			verdict = "PARTIAL"
			not_moved.append(k)
		var field: String = STATE_ALIAS.get(k, k)
		print("  %-22s %-10s %s" % [k, verdict, "listed" if listed.has(field) else "-- not listed"])
	print("")
	print("  NOT MOVED (%d): %s" % [not_moved.size(), ", ".join(not_moved) if not not_moved.is_empty() else "none"])
	if not untested.is_empty():
		print("  UNTESTED (%d) — the probe could not plant a sentinel: %s" % [untested.size(), ", ".join(untested)])


# ── 3. THE TWO PROFILE PATHS ─────────────────
## The same gap, through the real CampaignManager: what profile A leaves in a
## profile loaded or made after it. Whatever is listed is what the next
## autosave would write into the second profile's file.
func _report_profile_paths() -> void:
	print("")
	print("══ 3. WHAT ONE PROFILE HANDS THE NEXT ════════════════════")
	DirAccess.make_dir_recursive_absolute(SANDBOX_SAVES)
	var cm := _campaign_from_world()
	if cm == null:
		push_warning("probe_save_facts: no CampaignManager in %s, so the profile paths were not replayed." % WORLD)
		print("  SKIPPED — no CampaignManager in %s" % WORLD)
		return
	cm.autosave = false
	root.add_child(cm)
	for _i in 3:
		await process_frame
	print("  booted: active_slot '%s' (empty = the scratch campaign behind the menu)" % cm.active_slot)

	# A reference new profile made from the scratch state, which has never
	# been anybody's campaign — so anything in a later new profile that differs
	# from this and matches A came from A.
	cm.new_profile("probe-ref")
	var ref: Dictionary = cm.state.to_dict()

	var a := _sentinel_dict(CampaignState.new().to_dict())
	a["profile_name"] = "probe-a"
	_write_json(_SaveSlots.path_for("probe-a"), a)
	var c := CampaignState.new().to_dict()
	c["profile_name"] = "probe-c"
	_write_json(_SaveSlots.path_for("probe-c"), c)

	if not cm.load_profile("probe-a"):
		print("  SKIPPED — the sentinel profile would not load")
		return
	var a_file := CampaignState.from_dict(a).to_dict()
	var a_loaded: Dictionary = cm.state.to_dict()

	# THE LOAD ITSELF. What A's file says that the state A was loaded into does
	# not — and therefore what the next autosave writes over A's file.
	# Dropped = the state did not move at all from where it stood before the
	# load, although the file says something else.
	var dropped: Array[String] = []
	for k in a_file:
		if k == "version":
			continue
		if _j(a_loaded.get(k)) == _j(ref.get(k)) and _j(a_file[k]) != _j(ref.get(k)):
			dropped.append(k)
	dropped.sort()
	print("  load_profile(A) — %d field(s) in A's file that never arrived:" % dropped.size())
	for k in dropped:
		print("      %-20s file %s   loaded %s" % [k, _short(a_file[k]), _short(a_loaded.get(k))])

	# A SESSION THAT HAD BEEN PLAYING A. The load cannot put those fields in,
	# so plant them the way play would have, then see what the next profile gets.
	var a_state := CampaignState.from_dict(a)
	_plant(cm.state, a_state, dropped)
	var a_played: Dictionary = cm.state.to_dict()

	cm.load_profile("probe-c")
	var c_own := CampaignState.from_dict(c).to_dict()
	_print_leak("PLAYING A, THEN LOAD C", a_played, cm.state.to_dict(), c_own)

	cm.load_profile("probe-a")
	_plant(cm.state, a_state, dropped)
	cm.new_profile("probe-b")
	_print_leak("PLAYING A, THEN NEW CAMPAIGN", a_played, cm.state.to_dict(), ref)

	root.remove_child(cm)
	cm.free()


func _plant(into: CampaignState, from: CampaignState, keys: Array[String]) -> void:
	for k in keys:
		var field: String = STATE_ALIAS.get(k, k)
		into.set(field, from.get(field))


func _print_leak(label: String, from_a: Dictionary, now: Dictionary, own: Dictionary) -> void:
	var leaked: Array[String] = []
	for k in now:
		if k == "version" or not from_a.has(k):
			continue
		# Equality only for scalars. A container is normalised on the way in
		# (_adopt_state repairs a blank player_record into the same default
		# for A and C alike), so two containers matching proves nothing — they
		# have to carry A's marker.
		var scalar := not (now[k] is Dictionary or now[k] is Array)
		var carries := scalar and _j(now[k]) == _j(from_a[k]) and _j(own.get(k)) != _j(from_a[k])
		var partial := _j(now[k]).contains("probe_") and not _j(own.get(k)).contains("probe_")
		if carries or partial:
			# A record carries over field by field, so name which ones.
			if now[k] is Dictionary and from_a[k] is Dictionary and own.get(k) is Dictionary:
				var subs: PackedStringArray = []
				for sk in now[k]:
					var same_as_a: bool = _j(now[k][sk]) == _j(from_a[k].get(sk))
					var not_own: bool = _j(own[k].get(sk)) != _j(now[k][sk])
					if same_as_a and not_own and _j(now[k][sk]).contains("probe_"):
						subs.append("%s=%s" % [sk, _short(now[k][sk])])
				leaked.append("%s: %s" % [k, ", ".join(subs) if not subs.is_empty() else _short(now[k])])
			else:
				leaked.append("%s=%s" % [k, _short(now[k])])
	leaked.sort()
	print("  %s — %d field(s) carried over from A:" % [label, leaked.size()])
	for l in leaked:
		print("      %s" % l)


# ── 4. THE VERSION GATE ──────────────────────
## There is no migrate() any more — it warned and returned its argument, and
## saying so was the only thing it ever did (Backlog SV6). is_outdated() is the
## entire gate, so this reports the gate.
func _report_migrate() -> void:
	print("")
	print("══ 4. THE VERSION GATE (is_outdated; there is no migrate) ═")
	for v in [0, 1, CampaignState.SAVE_VERSION, CampaignState.SAVE_VERSION + 1]:
		var probe := {"version": v}
		var verdict := "loaded"
		if CampaignState.is_outdated(probe):
			verdict = "refused, file left alone"
		elif v > CampaignState.SAVE_VERSION:
			# Not refused. load_dict warns and loads it, and the next autosave
			# writes this build's older shape back over it — Backlog SV5, which
			# is open and is the human's call.
			verdict = "loaded with a warning, and saving writes the older shape back (SV5)"
		print("  version %d: is_outdated %s — %s" % [v, str(CampaignState.is_outdated(probe)), verdict])
	print("  (no `version` key at all reads as 0)")


# ── 5. WRITE, READ BACK ──────────────────────
func _report_write_and_read_back(no_save: bool) -> void:
	print("")
	print("══ 5. A SAVE WRITTEN TO A THROWAWAY PATH AND READ BACK ═══")
	DirAccess.make_dir_recursive_absolute(SANDBOX)
	var s := CampaignState.from_dict(_sentinel_dict(CampaignState.new().to_dict()))
	# save_to_disk under --no-save is a no-op that returns true. Checked, not
	# assumed: a guard that still wrote would be the worst kind of pass.
	var said := s.save_to_disk(VIA_SAVE_TO_DISK)
	var landed := FileAccess.file_exists(VIA_SAVE_TO_DISK)
	if landed:
		_wrote.append(VIA_SAVE_TO_DISK)
	print("  save_to_disk(%s) returned %s, file written: %s%s" % [VIA_SAVE_TO_DISK, str(said), str(landed),
		"  (--no-save honoured)" if no_save and not landed else ""])
	# The same serialisation save_to_disk uses, by hand.
	_write_json(WRITTEN, s.to_dict())
	var back := CampaignState.load_dict(WRITTEN)
	var keys: Array = back.keys()
	keys.sort()
	print("  %s read back through load_dict: %d keys, version %d" % [WRITTEN, keys.size(), int(back.get("version", -1))])
	var lost: Array = s.to_dict().keys().filter(func(k): return not back.has(k))
	print("  keys lost on the round trip: %s" % (", ".join(lost) if not lost.is_empty() else "none"))
	var again := CampaignState.from_dict(back).to_dict()
	var drift: Array[String] = []
	for k in again:
		if _j(again[k]) != _j(s.to_dict()[k]):
			drift.append(k)
	print("  values that differ after disk + from_dict: %s" % (", ".join(drift) if not drift.is_empty() else "none"))


# ── 6. THE SAVES ON THIS MACHINE ─────────────
## Read-only. What a real file holds, which is not always what to_dict writes
## today — a save is written by whichever build last saved it.
func _report_player_saves() -> void:
	print("")
	print("══ 6. THE REAL SAVES ON THIS MACHINE (read-only) ═════════")
	var current: Array = CampaignState.new().to_dict().keys()
	var files: Array[String] = ["user://campaign.json"]
	var dir := DirAccess.open("user://saves")
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".json"):
				files.append("user://saves/" + f)
	for path in files:
		if not FileAccess.file_exists(path):
			print("  %-28s absent" % path)
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			print("  %-28s does not parse" % path)
			continue
		var d: Dictionary = parsed
		var missing: Array = current.filter(func(k): return not d.has(k))
		var extra: Array = d.keys().filter(func(k): return not current.has(k))
		print("  %-28s v%d %s — %d keys; missing vs today: %s; not written today: %s" % [path,
			int(d.get("version", 0)), "OUTDATED" if CampaignState.is_outdated(d) else "loadable",
			d.size(), ", ".join(missing) if not missing.is_empty() else "none",
			", ".join(extra) if not extra.is_empty() else "none"])


# ─────────────────────────────────────────────
# INTERNALS
# ─────────────────────────────────────────────

## A copy of `d` with a recognisable value in every key but `version`.
func _sentinel_dict(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	for k in out:
		if k == "version":
			continue
		var v = out[k]
		# The four with a shape of their own. if/elif rather than match: a
		# `continue` inside match is not something to be clever about.
		if k == "armoury":
			out[k] = {"stock": {"probe_armoury": 7}, "chassis_stock": {}}
			continue
		elif k == "player_record":
			var p: Dictionary = (v as Dictionary).duplicate(true)
			p["display_name"] = "probe_player_record"
			out[k] = p
			continue
		elif k == "roster":
			var r := SoldierRecord.new()
			r.id = &"probe_roster"
			r.display_name = "probe_roster"
			out[k] = (v as Array) + [r.to_dict()]
			continue
		elif k == "teams":
			out[k] = (v as Array) + [{"id": "probe_teams", "name": "PROBE_TEAMS"}]
			continue
		match typeof(v):
			TYPE_BOOL:
				out[k] = not v
			TYPE_INT, TYPE_FLOAT:
				out[k] = 4242
			TYPE_STRING, TYPE_STRING_NAME:
				out[k] = "probe_%s" % k
			TYPE_DICTIONARY:
				var dd: Dictionary = (v as Dictionary).duplicate(true)
				dd["probe_%s" % k] = SENTINEL_VALUE.get(k, 7)
				out[k] = dd
			TYPE_ARRAY:
				out[k] = (v as Array) + ["probe_%s" % k]
			_:
				push_warning("probe_save_facts: no sentinel for '%s' (type %d); it will read UNTESTED." % [k, typeof(v)])
	return out


## The text of one function, from its signature to the next top-level line.
func _function_body(src: String, signature: String) -> String:
	var at := src.find(signature)
	if at < 0:
		push_warning("probe_save_facts: '%s' not found in %s; its source checks are blank." % [signature, STATE_SCRIPT])
		return ""
	var lines := src.substr(at).split("\n")
	var out: PackedStringArray = [lines[0]]
	for i in range(1, lines.size()):
		var l: String = lines[i]
		if l != "" and not l.begins_with("\t") and not l.begins_with(" "):
			break
		out.append(l)
	return "\n".join(out)


## Every key a function reads off `data` — get, has or subscript.
func _keys_read(body: String) -> Dictionary:
	var re := RegEx.create_from_string("data(?:\\.get\\(|\\.has\\(|\\[)\"([a-z_]+)\"")
	var out := {}
	for m in re.search_all(body):
		out[m.get_string(1)] = true
	return out


## Every `<x>.field = ` / `field = ` in game code, outside the two functions
## that only copy it (from_dict and restore_from).
func _assignments(field: String) -> Array[String]:
	var re := RegEx.create_from_string("(^|[^\\w])%s\\s*=[^=]" % field)
	var out: Array[String] = []
	for dir in ["res://Campaign", "res://Managers", "res://Character", "res://Env"]:
		for path in _gd_files(dir):
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for i in lines.size():
				var l: String = lines[i]
				if l.strip_edges().begins_with("#") or re.search(l) == null:
					continue
				if "was.%s" % field in l or "data.get(\"%s\"" % field in l:
					continue   # restore_from's move, from_dict's read
				out.append("%s:%d" % [path.trim_prefix("res://"), i + 1])
	return out


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_gd_files(dir + "/" + sub))
	return out


## restore_from's own move list: `field = was.field`.
func _moved_fields(body: String) -> Dictionary:
	var re := RegEx.create_from_string("(?m)^\\t(\\w+) = was\\.(\\w+)")
	var out := {}
	for m in re.search_all(body):
		out[m.get_string(1)] = true
	return out


## The CampaignManager with world.tscn's own values on it, read off the packed
## scene WITHOUT instancing the world — scene values beat script defaults, and
## the world is a lot to stand up just to read a node's exports.
func _campaign_from_world() -> Node:
	var packed := load(WORLD) as PackedScene
	if packed == null:
		return null
	var st := packed.get_state()
	for i in st.get_node_count():
		if String(st.get_node_name(i)) != "CampaignManager":
			continue
		var cm: Node = load(CAMPAIGN_SCRIPT).new()
		cm.name = "Campaign"
		for p in st.get_node_property_count(i):
			var n := String(st.get_node_property_name(i, p))
			if n != "script":
				cm.set(n, st.get_node_property_value(i, p))
		cm.add_to_group(&"campaign")
		return cm
	return null


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("probe_save_facts: could not write %s (%s)." % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if not _wrote.has(path):
		_wrote.append(path)


func _stat_player_files() -> Dictionary:
	var out := {}
	for p in PLAYER_FILES:
		if FileAccess.file_exists(p):
			out[p] = "%d bytes, mtime %d" % [FileAccess.get_file_as_bytes(p).size(), FileAccess.get_modified_time(p)]
		elif DirAccess.dir_exists_absolute(p):
			var d := DirAccess.open(p)
			var parts: PackedStringArray = []
			for f in d.get_files():
				parts.append("%s@%d" % [f, FileAccess.get_modified_time(p + "/" + f)])
			out[p] = ", ".join(parts)
		else:
			out[p] = "absent"
	return out


## Only what this run made. Never a directory it did not create.
func _clean() -> void:
	for p in _wrote:
		DirAccess.remove_absolute(p)
	for dir in [SANDBOX_SAVES, SANDBOX]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			DirAccess.remove_absolute(dir + "/" + f)
		DirAccess.remove_absolute(dir)


func _j(v) -> String:
	return JSON.stringify(v)


func _short(v) -> String:
	var s := _j(v)
	return s if s.length() <= 70 else s.substr(0, 67) + "..."
