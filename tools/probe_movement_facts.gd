extends SceneTree
# REPORTS: prints the tables `Reference/Movement and navigation.md` is written
# from. There is no right answer to assert against — only the shape the
# movement layer currently has.

# ─────────────────────────────────────────────
# HOW A ROBOT GETS FROM HERE TO THERE, AND WHO PAYS FOR IT.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_movement_facts.gd
#
# The vault note `Reference/Movement and navigation.md` is written from this
# and names it in its `verified-by`. Re-run it before trusting the note.
#
# WHY IT EXISTS. Movement is the largest subsystem in `enemy.gd` and the one
# with the most already-paid-for knowledge in it, and three separate kinds of
# claim about it rot silently:
#
#   * HOW BIG IT IS, and therefore whether it still earns its own document.
#   * WHO OVERRIDES IT. "Soldier walks, the Rover drives, the Drone flies" was
#     the standing summary and it is not the whole list — this reads every
#     body script and reports what each one actually replaces.
#   * WHAT THE NUMBERS ARE. Every budget and threshold here is an `@export`,
#     and in this project **a scene value beats a script default**. A figure
#     quoted from `enemy.gd` is only true for the frames whose scenes do not
#     pin it, so this reports both and says plainly when they disagree.
#
# NOTHING IS INSTANTIATED. Every answer comes from `GDScript.source_code` and
# `SceneState`, never from a body in a tree — the same bargain
# probe_body_facts.gd makes, and for the same reason. The cost is that a value
# written by code at runtime is invisible here, which is the right trade for
# questions about structure and authored numbers.
# ─────────────────────────────────────────────

const AI_DIR := "res://Character/characters/ai"
const ENEMY := "res://Character/characters/ai/enemy.gd"

## The movement layer's entry points, as `Reference/The robot body` lists them.
## Order is reading order, not file order.
const MOVE_FUNCS := [
	"handle_movement", "move_to", "move_along_nav", "_path_steer_dir",
	"_tick_nav", "_take_nav_query", "_snap_to_nav", "_take_snap_query",
	"snap_on_map", "_first_clear_step", "_check_stuck", "_handle_path_blocked",
	"_apply_motion", "_damp_shoving", "_step_over", "_tick_adrift",
	"_drown_check", "_apply_give_way", "_tick_give_way",
	"off_navmesh_is_normal", "handle_gravity",
]

## The ones a subclass replacing them changes how a chassis MOVES, as opposed
## to tuning it. Reported per script.
const OVERRIDABLE := [
	"handle_movement", "move_along_nav", "_apply_motion",
	"off_navmesh_is_normal", "handle_gravity", "_path_steer_dir",
]

## Every authored number the movement layer reads: name, unit, and whether it
## is meant to be the SAME on every frame.
##
## That last column is the whole point of the table. A budget or a threshold
## differing between chassis is a finding; `move_speed` differing is the
## design. Flagging both the same way buries the first under the second — the
## first version of this printed eighteen move_speed values and a DISAGREES
## marker beside them, which is noise wearing a warning's clothes.
const MOVE_PROPS := [
	["nav_think_interval", "s", true],
	["nav_queries_per_frame", "per frame", true],
	["nav_query_budget_ms", "ms", true],
	["snap_queries_per_frame", "per frame", true],
	["snap_query_budget_ms", "ms", true],
	["step_height", "m", true],
	["step_forward", "m", true],
	["adrift_distance", "m", true],
	["adrift_seconds", "s", true],
	["drown_depth", "m", true],
	["move_speed", "m/s", false],
]

## Constants that are NOT exports, so no scene can move them.
const MOVE_CONSTS := [
	"NAV_LEG_REACHED", "NAV_UNDERFOOT", "SHOVE_STEP_LIMIT",
	"GIVE_WAY_BLOCKED_TIME", "GIVE_WAY_DURATION", "GIVE_WAY_SIDE_SPEED",
	"GIVE_WAY_MAX_TRIES", "GIVE_WAY_PROGRESS",
]


func _initialize() -> void:
	print("")
	var src := _source(ENEMY)
	if src.is_empty():
		push_error("probe_movement_facts: could not read %s" % ENEMY)
		quit(1)
		return
	_report_size(src)
	_report_constants(src)
	_report_overrides()
	_report_numbers()
	print("")
	print("probe_movement_facts: done")
	quit(0)


# ── how big is it ────────────────────────────────────────────────────────────

func _report_size(src: String) -> void:
	print("══ THE MOVEMENT LAYER IN enemy.gd — measured, not estimated ═══════")
	var lines := src.split("\n")
	var starts := {}
	for i in lines.size():
		var name := _func_name(lines[i])
		if name != "":
			starts[name] = i
	# Every function's span is from its own line to the next `func` after it,
	# which counts its doc comment with the function BELOW it rather than above.
	# Close enough for a size question and it never double-counts.
	var all_starts: Array = starts.values()
	all_starts.sort()
	var total := 0
	var found := 0
	print("%-24s %6s  %s" % ["entry point", "line", "lines"])
	for fn in MOVE_FUNCS:
		if not starts.has(fn):
			print("%-24s %6s  NOT FOUND — renamed or gone" % [fn, "-"])
			continue
		var at: int = starts[fn]
		var next: int = lines.size()
		for s in all_starts:
			if int(s) > at:
				next = int(s)
				break
		var span: int = next - at
		total += span
		found += 1
		print("%-24s %6d  %d" % [fn, at + 1, span])
	print("")
	print("   %d of %d entry points found, %d lines of %d in the file (%.0f%%)" % [
		found, MOVE_FUNCS.size(), total, lines.size(),
		100.0 * float(total) / maxf(1.0, float(lines.size()))])
	print("   Bodies only — the banner comments above each one are counted with")
	print("   the function above them, so the layer's real footprint is larger.")


func _report_constants(src: String) -> void:
	print("")
	print("══ CONSTANTS — no scene can move these ════════════════════════════")
	for c in MOVE_CONSTS:
		var v := _const_value(src, c)
		print("   %-24s %s" % [c, v if v != "" else "NOT FOUND"])


# ── who overrides it ─────────────────────────────────────────────────────────

func _report_overrides() -> void:
	print("")
	print("══ WHO MOVES DIFFERENTLY — every body script, read for overrides ══")
	print("%-26s %s" % ["script", "replaces"])
	var scripts := _gd_files(AI_DIR)
	scripts.sort()
	var movers := 0
	for path in scripts:
		if path == ENEMY:
			continue
		var s := _source(path)
		if s.is_empty():
			continue
		var has: Array = []
		for fn in OVERRIDABLE:
			if _defines(s, fn):
				has.append(fn)
		if has.is_empty():
			continue
		movers += 1
		# off_navmesh_is_normal() returning true is the single most load-bearing
		# fact about a chassis here: it exempts the body from the adrift rescue
		# and from drowning, which is what "this thing flies" means in code.
		# Said as "off the mesh by design" rather than "flies", because the
		# Diver is down in the water rather than up in the air and the flag
		# means the same thing for both: do not rescue it, do not drown it.
		var flies := ""
		if has.has("off_navmesh_is_normal"):
			flies = "  [OFF-MESH BY DESIGN: no adrift rescue, no drowning]" \
				if _returns_true(s, "off_navmesh_is_normal") \
				else "  [declares off_navmesh_is_normal, returns false]"
		print("%-26s %s%s" % [path.get_file(), ", ".join(has), flies])
	print("")
	print("   %d of %d scripts in %s replace part of how they move." % [
		movers, scripts.size(), AI_DIR])
	print("   enemy.gd is the base and is excluded from the count.")


# ── what the numbers are ─────────────────────────────────────────────────────

func _report_numbers() -> void:
	print("")
	print("══ THE AUTHORED NUMBERS — script default vs what scenes pin ═══════")
	var scenes := _scenes(AI_DIR)
	scenes.sort()
	var src := _source(ENEMY)
	print("%-24s %10s  %-8s %s" % ["export", "default", "unit", "scenes that pin it"])
	var odd_ones: Array = []
	for row in MOVE_PROPS:
		var prop: String = row[0]
		var unit: String = row[1]
		var uniform: bool = row[2]
		var default := _export_default(src, prop)
		var values := {}        # value -> [scene names]
		for path in scenes:
			var v = _scene_value(path, prop)
			if v == null:
				continue
			var key := str(v)
			if not values.has(key):
				values[key] = []
			values[key].append(path.get_file().get_basename())
		if values.is_empty():
			print("%-24s %10s  %-9s none — the default is live everywhere" % [
				prop, default if default != "" else "?", unit])
			continue
		if not uniform:
			# Per-chassis by design. The range and the count say everything a
			# reader wants; the full list is eighteen numbers nobody reads.
			var lo := INF
			var hi := -INF
			var n := 0
			for key in values:
				# `: float` spelled out — a Dictionary key is a Variant, so
				# `:=` cannot infer a type off it and that is a parse error.
				var f: float = str(key).to_float()
				lo = minf(lo, f)
				hi = maxf(hi, f)
				n += int((values[key] as Array).size())
			print("%-24s %10s  %-9s %d scenes, %.2f to %.2f (per chassis, by design)" % [
				prop, default if default != "" else "?", unit, n, lo, hi])
			continue
		var parts: Array = []
		for key in values:
			var who: Array = values[key]
			parts.append("%s x%d" % [key, who.size()])
			if default != "" and not _same_number(key, default):
				odd_ones.append("%s = %s on %s (default %s)" % [
					prop, key, ", ".join(who), default])
		print("%-24s %10s  %-9s %s" % [prop, default if default != "" else "?",
			unit, ", ".join(parts)])
	if not odd_ones.is_empty():
		print("")
		print("   SCENES THAT DISAGREE WITH THE DEFAULT, named:")
		for o in odd_ones:
			print("      %s" % o)
	print("")
	print("   %d scenes scanned. A row reading \"none\" is safe to change from the" % scenes.size())
	print("   script; a row listing scenes is NOT — editing the default moves only")
	print("   the frames that do not pin it, and nothing reports the split.")


# ── helpers ──────────────────────────────────────────────────────────────────

## The function name a line declares, or "" if it declares none. Indented
## `func` lines belong to inner classes and are deliberately ignored.
func _func_name(line: String) -> String:
	var t := line
	if not (t.begins_with("func ") or t.begins_with("static func ")):
		return ""
	t = t.trim_prefix("static ").trim_prefix("func ").strip_edges()
	var paren := t.find("(")
	return t.substr(0, paren) if paren > 0 else ""


func _defines(src: String, fn: String) -> bool:
	for line in src.split("\n"):
		if _func_name(line) == fn:
			return true
	return false


## Whether a no-argument bool function's body contains `return true`. Enough
## for off_navmesh_is_normal(), which is one line in every override of it.
func _returns_true(src: String, fn: String) -> bool:
	var lines := src.split("\n")
	var inside := false
	for line in lines:
		var n := _func_name(line)
		if n != "":
			if inside:
				return false        # ran off the end of the function
			inside = n == fn
			continue
		if inside and line.strip_edges().begins_with("return true"):
			return true
	return false


func _const_value(src: String, name: String) -> String:
	for line in src.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("const %s " % name) or t.begins_with("const %s:" % name):
			var eq := t.find("=")
			if eq > 0:
				return t.substr(eq + 1).strip_edges()
	return ""


func _export_default(src: String, prop: String) -> String:
	for line in src.split("\n"):
		var t := line.strip_edges()
		if not t.begins_with("@export var %s" % prop):
			continue
		var eq := t.find("=")
		return t.substr(eq + 1).strip_edges() if eq > 0 else "(no default)"
	return ""


## What a scene writes for `prop` on its ROOT node, or null if it writes
## nothing. Root only: these are all properties of the body itself.
func _scene_value(path: String, prop: String):
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var st := packed.get_state()
	if st.get_node_count() == 0:
		return null
	for i in st.get_node_property_count(0):
		if st.get_node_property_name(0, i) == prop:
			return st.get_node_property_value(0, i)
	return null


## Two numbers written differently — "4" and "4.0" — are the same number. A
## plain string compare reports a disagreement that does not exist.
func _same_number(a: String, b: String) -> bool:
	if a == b:
		return true
	if not (a.is_valid_float() and b.is_valid_float()):
		return false
	return is_equal_approx(a.to_float(), b.to_float())


func _source(path: String) -> String:
	var s := load(path) as GDScript
	return s.source_code if s != null else ""


func _gd_files(dir: String) -> Array:
	return _by_extension(dir, "gd")


func _scenes(dir: String) -> Array:
	return _by_extension(dir, "tscn")


func _by_extension(dir: String, ext: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		push_warning("probe_movement_facts: cannot open %s" % dir)
		return out
	for f in d.get_files():
		# Godot ships imported resources as .remap in an exported build; in the
		# project they are plain files, but strip the suffix anyway so this does
		# not quietly report nothing from a different kind of run.
		var name := f.trim_suffix(".remap")
		if name.get_extension() == ext:
			out.append("%s/%s" % [dir, name])
	return out
