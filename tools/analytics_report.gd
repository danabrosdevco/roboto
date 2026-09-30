extends SceneTree

# ─────────────────────────────────────────────
# ANALYTICS REPORT (merge) — one report from many playtest sessions.
#
#   tools/analytics.sh <folder>
#
# Finds every events.jsonl under <folder>, however deep — unzip each tester's
# folder into it side by side — tags each file's events with its session so
# attempts never merge across files, and writes <folder>/combined_report.md
# with the same tables the game writes per session.
#
# With no folder it reads this machine's own user://analytics.
# ─────────────────────────────────────────────

const _Report := preload("res://Managers/analytics_report.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var root_dir: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://analytics")
	root_dir = root_dir.replace("\\", "/").trim_suffix("/")
	var files: Array = []
	_find(root_dir, files)
	if files.is_empty():
		print("No events.jsonl found under %s" % root_dir)
		quit(1)
		return

	var events: Array = []
	var bad := 0
	for path in files:
		# The session's folder name, relative to the root: unique per tester
		# and per play session, which is all the report needs to keep them apart.
		var session: String = path.get_base_dir().trim_prefix(root_dir).trim_prefix("/")
		if session == "":
			session = path.get_base_dir().get_file()
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		while not f.eof_reached():
			var line := f.get_line().strip_edges()
			if line == "":
				continue
			var e = JSON.parse_string(line)
			if typeof(e) != TYPE_DICTIONARY:
				bad += 1
				continue
			e["s"] = session
			events.append(e)

	var title := "%d session(s) under %s" % [files.size(), root_dir]
	var text: String = _Report.build(events, title)
	var out_path := root_dir + "/combined_report.md"
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	if out == null:
		print("Could not write %s" % out_path)
		quit(1)
		return
	out.store_string(text)
	out.close()
	print("Read %d events from %d session(s)%s." % [events.size(), files.size(),
		(", skipped %d unreadable line(s)" % bad) if bad > 0 else ""])
	print("Wrote %s" % out_path)
	quit(0)


func _find(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for file in d.get_files():
		if file == "events.jsonl":
			out.append(dir + "/" + file)
	for sub in d.get_directories():
		_find(dir + "/" + sub, out)
