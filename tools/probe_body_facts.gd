extends SceneTree
# REPORTS: prints the table `Reference/The robot body.md` asserts; there is no
# right answer to assert against, only the shape the hierarchy currently has

# ─────────────────────────────────────────────
# WHAT A ROBOT BODY IS, AND WHICH LAYER OWNS WHAT.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_body_facts.gd -- --no-save
#
# The vault note `Reference/The robot body.md` is written from this and names
# it in its `verified-by`. Re-run it before trusting the note.
#
# WHY IT EXISTS. One class hierarchy carries the player, your squad and every
# enemy, and its names actively mislead:
#
#   * `Enemy` is the base class of EVERY AKR in the game, yours included.
#   * `Soldier` is a BODY. `SoldierRecord` is a campaign-layer Resource with
#     no code in common. Two layers, one word.
#   * `AI` is the PLAYER's base class too, so anything on it is shared with
#     the human's own hands.
#
# Those three are claims about a class chain, which is exactly the kind of
# claim that rots silently: a new frame inserted one layer up, or a
# `class_name` added to a script that deliberately has none, changes the answer
# and nothing fails. So this reads the chain out of the scripts themselves.
#
# NOTHING IS INSTANTIATED. Every answer below comes from `Script` and
# `SceneState`, never from a body in a tree. A chassis scene is 120 load steps
# of CSG and instancing 27 of them to ask what class they are would be slower
# and would run `_ready` on things that expect a level around them. The cost of
# that choice is that a property set by code at runtime is invisible here —
# which is the right trade for a question about TYPES.
#
# ROUTE A / ROUTE B is the weapon question from `Reference/Weapons`:
#   A  `ChassisDefinition.starting_weapon_id` names an ItemDefinition, and the
#      campaign layer fits its `ai_scene` onto a mount.
#   B  `starting_weapon_id` is empty and the `.tscn` instances an `ai-wep_*`
#      scene directly. No ItemDefinition is consulted at all.
# A frame that is neither has nothing in its hands and says so — that is a real
# authored state (a Mechanic's welder, a Chaser's claws), not a fault.
# ─────────────────────────────────────────────

const CHASSIS_DIR := "res://Campaign/chassis"
const BODY_DIR := "res://Character/characters/ai"
const PLAYER_SCRIPT := "res://Character/characters/player/test_character.gd"
const AI_SCRIPT := "res://Character/characters/ai/ai.gd"
const ENEMY_SCRIPT := "res://Character/characters/ai/enemy.gd"
const SOLDIER_SCRIPT := "res://Character/characters/ai/soldier.gd"

# The layers worth reporting a size for. Everything else is a concrete frame.
const LAYERS := [
	["AI", AI_SCRIPT],
	["Enemy", ENEMY_SCRIPT],
	["Soldier", SOLDIER_SCRIPT],
	["Walker", "res://Character/characters/ai/walker.gd"],
	["SpotterDrone", "res://Character/characters/ai/spotter_drone.gd"],
	["rover.gd (no class_name)", "res://Character/characters/ai/rover.gd"],
	["Player", PLAYER_SCRIPT],
]


func _init() -> void:
	print("")
	print("════════════════════════════════════════════════════════════════")
	print(" THE ROBOT BODY — probe_body_facts")
	print("════════════════════════════════════════════════════════════════")
	_section_1_hierarchy()
	_section_2_frames()
	_section_3_orphans()
	_section_4_layers()
	_section_5_shared_with_player()
	print("")
	print("Done. Nothing was instantiated and nothing was written.")
	quit(0)


# ─────────────────────────────────────────────
# §1  THE CHAIN, READ OUT OF THE SCRIPTS
# ─────────────────────────────────────────────
func _section_1_hierarchy() -> void:
	print("")
	print("── §1  THE CLASS CHAIN ─────────────────────────────────────────")
	print("Every body script under %s, with what it extends." % BODY_DIR)
	print("")
	var rows: Array = []
	for path in _scripts_in(BODY_DIR) + [PLAYER_SCRIPT]:
		var s: Script = load(path) as Script
		if s == null:
			continue
		# RefCounted helpers live in the same folder (air_clearance, csg_bake):
		# they are not bodies and must not be reported as frames.
		if not _descends_from(s, AI_SCRIPT) and path != AI_SCRIPT:
			continue
		rows.append([_label(s), _chain(s), path.get_file()])
	rows.sort_custom(func(a, b): return a[1].length() < b[1].length())
	print("%-26s %s" % ["script", "chain up to CharacterBody3D"])
	for r in rows:
		print("%-26s %s" % [r[2], r[1]])
	print("")
	print("%d body scripts. Note the ones with NO class_name — rover.gd, kite.gd," % rows.size())
	print("mechanic.gd, enemy_nest.gd, enemy_watcher.gd, reclaimer.gd, lance.gd,")
	print("drayman.gd, vessel.gd, capture_anchor.gd. That is deliberate: a global")
	print("class an open editor has not indexed yet takes the front end down, so")
	print("those are extended BY PATH. See rover.gd:467-470.")


# ─────────────────────────────────────────────
# §2  EVERY FRAME, ITS CLASS AND HOW IT IS ARMED
# ─────────────────────────────────────────────
func _section_2_frames() -> void:
	print("")
	print("── §2  THE FRAMES ──────────────────────────────────────────────")
	print("One row per ChassisDefinition in %s." % CHASSIS_DIR)
	print("SQUAD? is whether a spawner can use it at all. All THREE casts are")
	print("`as Soldier` — squad_spawner.gd:273, enemy_force_spawner.gd:335 and")
	print("lab.gd:265 — so a body that is not a Soldier or deeper cannot be put")
	print("into a level by anything, on either side. Two of the three push_error")
	print("on the null; lab.gd skips in silence.")
	print("")
	print("%-18s %-30s %-14s %-6s %s" % ["chassis id", "root script", "class", "SQUAD?", "armed"])
	print("%-18s %-30s %-14s %-6s %s" % ["─".repeat(18), "─".repeat(30), "─".repeat(14), "─".repeat(6), "─".repeat(22)])
	var a := 0
	var b := 0
	var neither := 0
	var not_soldier: Array = []
	for path in _resources_in(CHASSIS_DIR):
		var chassis = load(path)
		if chassis == null:
			continue
		var scene: PackedScene = chassis.scene
		if scene == null:
			print("%-18s %s" % [String(chassis.id), "NO SCENE — this frame cannot spawn"])
			continue
		var s: Script = _root_script(scene)
		var cls := _label(s) if s != null else "(no script)"
		var squad_ok: bool = s != null and _descends_from(s, SOLDIER_SCRIPT)
		if not squad_ok:
			not_soldier.append(String(chassis.id))
		var armed := _route(chassis, scene)
		if armed.begins_with("A"):
			a += 1
		elif armed.begins_with("B"):
			b += 1
		else:
			neither += 1
		print("%-18s %-30s %-14s %-6s %s" % [
			String(chassis.id),
			s.resource_path.get_file() if s != null else "-",
			cls,
			"yes" if squad_ok else "NO",
			armed,
		])
	print("")
	print("Route A %d · route B %d · neither %d." % [a, b, neither])
	if not_soldier.is_empty():
		print("Every chassis is a Soldier or deeper, so every one of them CAN be")
		print("spawned. There is no longer any body class that is not — `Boss`")
		print("(miniboss.gd) was the last one and was deleted on 2026-10-24.")
	else:
		print("NOT a Soldier, so no spawner can place it: %s" % ", ".join(not_soldier))


# ─────────────────────────────────────────────
# §3  BODY SCENES NO CHASSIS POINTS AT
# ─────────────────────────────────────────────
# A class with no frame under it is not dead until the second route is checked,
# so this names the scenes rather than judging them. `Where the truth lives`
# has the rule.
func _section_3_orphans() -> void:
	print("")
	print("── §3  BODY SCENES WITH NO CHASSIS ─────────────────────────────")
	var claimed := {}
	for path in _resources_in(CHASSIS_DIR):
		var chassis = load(path)
		if chassis != null and chassis.scene != null:
			claimed[chassis.scene.resource_path] = String(chassis.id)
	var orphans: Array = []
	for path in _scenes_in(BODY_DIR):
		if claimed.has(path):
			continue
		var s: Script = _root_script(load(path) as PackedScene)
		if s == null or not _descends_from(s, AI_SCRIPT):
			continue   # art-only scenes (the watcher variants) are not bodies
		orphans.append("%s  (%s)" % [path.get_file(), _label(s)])
	print("These are AI bodies that no ChassisDefinition names. Each one needs its")
	print("second route checked — a map's FGD entity, a level, the Laboratory, a")
	print("tool — before anyone calls it dead:")
	for o in orphans:
		print("  %s" % o)
	print("")
	print("%d chassis claim %d distinct scenes; %d body scenes are unclaimed." % [
		_resources_in(CHASSIS_DIR).size(), claimed.size(), orphans.size()])


# ─────────────────────────────────────────────
# §4  WHAT EACH LAYER ADDS, BY SIZE
# ─────────────────────────────────────────────
# Counted off the source rather than reflection: `get_script_property_list`
# reports the whole inherited chain, which is the opposite of the question.
func _section_4_layers() -> void:
	print("")
	print("── §4  WHAT EACH LAYER ADDS ────────────────────────────────────")
	print("Declared at the top level of that one file — not inherited.")
	print("")
	print("%-26s %6s %6s %8s %8s %6s" % ["layer", "lines", "funcs", "exports", "signals", "enums"])
	for layer in LAYERS:
		var c := _count_source(layer[1])
		print("%-26s %6d %6d %8d %8d %6d" % [
			layer[0], c["lines"], c["funcs"], c["exports"], c["signals"], c["enums"]])


# ─────────────────────────────────────────────
# §5  WHAT THE PLAYER ACTUALLY SHARES
# ─────────────────────────────────────────────
# The third decoy, measured. `Player extends AI` exactly as `Enemy` does, so
# the natural reading is that the two share a body. They share the SIGNAL
# SYSTEM and nothing else: health, faction, gravity, movement, kills and death
# are declared TWICE, independently, with the same names and no common base.
# That is why so much of the game duck-types (`if "health" in body`) instead of
# casting.
func _section_5_shared_with_player() -> void:
	print("")
	print("── §5  WHAT IS ON `AI`, AND THEREFORE THE PLAYER'S TOO ─────────")
	var ai_names := _top_level_names(AI_SCRIPT)
	print("Every top-level member of ai.gd (%d):" % ai_names.size())
	for n in ai_names:
		print("  %s" % n)
	print("")
	print("Changing any of those changes the human's own robot.")
	print("")
	print("── NAMES DECLARED IN BOTH enemy.gd AND test_character.gd ───────")
	var shared: Array = []
	var player_names := _top_level_names(PLAYER_SCRIPT)
	for n in _top_level_names(ENEMY_SCRIPT):
		if player_names.has(n) and not ai_names.has(n):
			shared.append(n)
	print("%d names, none of them on the shared base:" % shared.size())
	print("  %s" % ", ".join(shared))
	print("")
	print("These are PARALLEL declarations, not overrides. A change to one is not")
	print("a change to the other, and nothing in the type system will say so. It")
	print("is why so much of the game asks `if \"health\" in body` instead of")
	print("casting — there is no type that has it. (`_Analytics` is a preload the")
	print("two files happen to share, not duplicated state; the other 17 are.)")


# ─────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────
func _label(s: Script) -> String:
	if s == null:
		return "-"
	var n := String(s.get_global_name())
	if n != "":
		return n
	return "(%s)" % s.resource_path.get_file()


func _chain(s: Script) -> String:
	var parts: Array = []
	var cur := s
	# Bounded: a cycle here would hang the probe, and the chain is four deep.
	var guard := 0
	while cur != null and guard < 16:
		parts.append(_label(cur))
		cur = cur.get_base_script()
		guard += 1
	parts.append("CharacterBody3D")
	return " < ".join(parts)


func _descends_from(s: Script, base_path: String) -> bool:
	var cur := s
	var guard := 0
	while cur != null and guard < 16:
		if cur.resource_path == base_path:
			return true
		cur = cur.get_base_script()
		guard += 1
	return false


## The root node's script, out of the SceneState. Nothing is instantiated.
func _root_script(scene: PackedScene) -> Script:
	if scene == null:
		return null
	var st := scene.get_state()
	if st.get_node_count() == 0:
		return null
	for i in st.get_node_property_count(0):
		if st.get_node_property_name(0, i) == &"script":
			return st.get_node_property_value(0, i) as Script
	return null


## Route A, route B, or neither. See the header.
func _route(chassis, scene: PackedScene) -> String:
	var starting := String(chassis.starting_weapon_id)
	if starting != "":
		var extra := ""
		if String(chassis.coax_weapon_id) != "":
			extra = " + coax %s" % String(chassis.coax_weapon_id)
		return "A  item '%s'%s" % [starting, extra]
	var baked := _baked_weapons(scene)
	if not baked.is_empty():
		return "B  scene '%s'" % ", ".join(baked)
	var built_in := String(chassis.built_in)
	return "neither — built-in %s" % (built_in if built_in != "" else "NOTHING")


## Every `ai-wep_*` scene instanced anywhere in this chassis scene.
func _baked_weapons(scene: PackedScene) -> Array:
	var out: Array = []
	var st := scene.get_state()
	for i in st.get_node_count():
		var inst: PackedScene = st.get_node_instance(i)
		if inst == null:
			continue
		var f := inst.resource_path.get_file()
		if f.begins_with("ai-wep_") and not out.has(f):
			out.append(f)
	return out


func _count_source(path: String) -> Dictionary:
	var text := _read(path)
	var out := {"lines": 0, "funcs": 0, "exports": 0, "signals": 0, "enums": 0}
	# trim_suffix first: a file ending in a newline splits to a trailing empty
	# segment, which reported every script one line longer than `wc -l` does.
	for line in text.trim_suffix("\n").split("\n"):
		out["lines"] += 1
		if line.begins_with("func ") or line.begins_with("static func "):
			out["funcs"] += 1
		elif line.begins_with("@export"):
			out["exports"] += 1
		elif line.begins_with("signal "):
			out["signals"] += 1
		elif line.begins_with("enum "):
			out["enums"] += 1
	return out


## Top-level declared names in one script: vars, exported vars, funcs, signals,
## consts and enums. Column zero only, so nothing inside a function counts.
func _top_level_names(path: String) -> Array:
	var out: Array = []
	for raw in _read(path).split("\n"):
		var line := raw
		if line.begins_with("@export"):
			# `@export var x: T = y` and `@export_range(...) var x`
			var at := line.find("var ")
			if at < 0:
				continue
			line = line.substr(at)
		if not (line.begins_with("var ") or line.begins_with("func ")
				or line.begins_with("static func ") or line.begins_with("signal ")
				or line.begins_with("const ") or line.begins_with("enum ")):
			continue
		var rest := line.trim_prefix("static ").split(" ", true, 1)[1]
		var name_end := rest.length()
		for ch in [" ", ":", "(", "=", "\t"]:
			var at := rest.find(ch)
			if at >= 0 and at < name_end:
				name_end = at
		var n := rest.substr(0, name_end).strip_edges()
		if n != "" and not out.has(n):
			out.append(n)
	return out


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("probe_body_facts: cannot read %s" % path)
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _scripts_in(dir: String) -> Array:
	return _files_in(dir, ".gd")


func _scenes_in(dir: String) -> Array:
	return _files_in(dir, ".tscn")


func _resources_in(dir: String) -> Array:
	return _files_in(dir, ".tres")


func _files_in(dir: String, ext: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		push_warning("probe_body_facts: cannot open %s" % dir)
		return out
	for f in d.get_files():
		# Exported builds rename .gd to .gdc and append .remap; the source tree
		# never does, but strip it anyway so this cannot half-work.
		var name := f.trim_suffix(".remap")
		if name.ends_with(ext):
			out.append("%s/%s" % [dir, name])
	out.sort()
	return out
