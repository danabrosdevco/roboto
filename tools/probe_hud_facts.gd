extends SceneTree
# REPORTS: prints the table Reference/HUD and barks.md asserts. Exits 1 if any chassis frame is mute on any line — not BUCKETed, because bucket.sh only collects test_*.gd

# ─────────────────────────────────────────────
# WHAT THE PLAYER IS TOLD, AND BY WHAT — the half of it that is data.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/probe_hud_facts.gd -- --no-save
#
# The vault note `Reference/HUD and barks.md` is written from this and names it
# in its `verified-by`. Re-run it before trusting the note.
#
# THE POINT OF IT. A robot has two ways to have a voice — Bark.bark_set (a
# BarkSet resource, one clip array per line) and Bark.bark_clips (the legacy
# flat array) — and "does this robot have a voice" has been answered off one
# of them alone. Bark._next_clip() asks the set first, falls to its `fallback`,
# and only THEN to bark_clips, per line. So the honest question is per LINE:
# which array does this line actually play from, if any. This answers it off
# the instanced scene, so scene inheritance and bark.tscn's own defaults are
# resolved exactly as the game resolves them — reading the .tscn text misses
# that bark.tscn itself assigns a bark_set, which every instance inherits.
#
# Also printed, because no document had them:
#   - every BarkSet on disk and which lines have no clips of their own
#   - BarkDirector's constants, and whether its NCO bonus can ever apply
#   - the comms log's vocabulary, line by line, straight from _compose()
#   - the HUD scene's children, the filter's REAL uniforms and the damage knobs
#   - every signal world.tscn wires into the HUD (a route a code grep misses)
#
# Instances are never added to the tree, so no _ready runs, nothing paths and
# nothing is saved. It reads; it writes nothing.
# ─────────────────────────────────────────────

const CHASSIS_DIR := "res://Campaign/chassis/"
const AI_DIR := "res://Character/characters/ai/"
const BARK_SCENE := "res://Character/components/bark.tscn"
const HUD_SCENE := "res://Character/hud/hud.tscn"
const WORLD := "res://Env/world.tscn"
const COMMS := "res://Character/hud/comms_log.gd"
const LIVE_CATALOGUE := "res://Campaign/items & catalogue/test_item_catalogue.tres"

const LINE_NAMES := ["CONTACT", "ORDER_ACK", "KILL", "RELOAD", "DOWNED", "HURT", "SEARCH"]

var _mute: Array[String] = []


func _init() -> void:
	Engine.max_fps = 60
	await process_frame
	_report_bark_sets()
	var default_clips := _bark_scene_defaults()
	_report_frames(default_clips)
	_report_director()
	_report_comms_vocabulary()
	_report_hud()
	_report_world_wiring()

	print("")
	if _mute.is_empty():
		print("VOICES  every chassis frame resolves a clip on every line")
		quit(0)
	else:
		print("VOICES  MUTE on %d frame/line pairs:" % _mute.size())
		for m in _mute:
			print("   %s" % m)
		quit(1)


# ─────────────────────────────────────────────
func _report_bark_sets() -> void:
	print("\n== BARK SETS (every BarkSet .tres under res://Character and res://Campaign)")
	var sets := []
	for root in ["res://Character/", "res://Campaign/"]:
		_collect(root, ".tres", sets)
	var found := 0
	for path in sets:
		# Read the header first: loading every .tres under Campaign/ drags in
		# the stub catalogue and a dozen stale-UID warnings that are not ours.
		if not ('script_class="BarkSet"' in FileAccess.get_file_as_string(path).left(400)):
			continue
		var res = load(path)
		if not (res is BarkSet):
			continue
		found += 1
		var counts := []
		var own_empty := []
		for i in LINE_NAMES.size():
			var own: Array = res.get(LINE_NAMES[i].to_lower())
			counts.append("%s %d" % [LINE_NAMES[i].to_lower(), own.size()])
			if own.is_empty():
				own_empty.append(LINE_NAMES[i])
		print("%s" % path)
		print("   %s | fallback %d" % [", ".join(counts), res.fallback.size()])
		print("   lines with no clips of their own: %s" % (", ".join(own_empty) if not own_empty.is_empty() else "none"))
	print("BarkSets on disk: %d" % found)


# What bark.tscn itself carries, so a frame that never overrode bark_clips can
# be told apart from one that set it (the Bulwark, K1).
func _bark_scene_defaults() -> PackedStringArray:
	var out := PackedStringArray()
	var bark: Node = (load(BARK_SCENE) as PackedScene).instantiate()
	print("\n== bark.tscn DEFAULTS (inherited by every instance that does not override them)")
	print("bark_set   = %s" % (bark.bark_set.resource_path if bark.bark_set != null else "null"))
	for c in bark.bark_clips:
		out.append(c.resource_path.get_file())
	print("bark_clips = %s" % ", ".join(out))
	print("pitch      = %.2f..%.2f" % [bark.pitch_min, bark.pitch_max])
	bark.free()
	return out


# ─────────────────────────────────────────────
func _report_frames(default_clips: PackedStringArray) -> void:
	var player_side := {}
	var cat = load(LIVE_CATALOGUE)
	if cat != null and "chassis" in cat:
		for c in cat.chassis:
			if c != null:
				player_side[c.resource_path] = true

	print("\n== FRAMES (every ChassisDefinition in %s)" % CHASSIS_DIR)
	print("line source: S = bark_set's own array, F = bark_set.fallback, C = bark_clips, - = MUTE")
	print("%-20s %-4s %-26s %-10s %-6s %-12s %s" % ["chassis", "cat", "scene", "bark_set", "clips", "pitch", "C T K R D H S   bark_clips"])
	var seen_scenes := {}
	var defs := []
	_collect(CHASSIS_DIR, ".tres", defs)
	for path in defs:
		var def = load(path)
		if def == null or not ("scene" in def):
			continue
		var cat_flag := "live" if player_side.has(path) else "-"
		var sp: String = def.scene.resource_path if def.scene != null else ""
		seen_scenes[sp] = true
		_frame_row(String(def.id), cat_flag, sp, default_clips, true)

	print("\n== OTHER AI SCENES with a Bark, not reached from any ChassisDefinition")
	var scenes := []
	_collect(AI_DIR, ".tscn", scenes)
	for sp in scenes:
		if seen_scenes.has(sp):
			continue
		var text := FileAccess.get_file_as_string(sp)
		if not ("components/bark.tscn" in text):
			continue
		_frame_row(sp.get_file().get_basename(), "-", sp, default_clips, false)


func _frame_row(label: String, cat_flag: String, scene_path: String,
		default_clips: PackedStringArray, counts_as_chassis: bool) -> void:
	if scene_path == "":
		print("%-20s %-4s %s" % [label, cat_flag, "NO SCENE"])
		if counts_as_chassis:
			_mute.append("%s: no scene" % label)
		return
	var root: Node = (load(scene_path) as PackedScene).instantiate()
	var bark: Bark = root.get("bark") as Bark if "bark" in root else null
	if bark == null:
		print("%-20s %-4s %-26s %s" % [label, cat_flag, scene_path.get_file(), "NO Bark wired (root.bark is null) -> mute"])
		if counts_as_chassis:
			_mute.append("%s: no Bark" % label)
		root.free()
		return
	var set_name := bark.bark_set.resource_path.get_file().get_basename() if bark.bark_set != null else "null"
	var cells := []
	for i in LINE_NAMES.size():
		var src := "-"
		if bark.bark_set != null:
			var own: Array = bark.bark_set.get(LINE_NAMES[i].to_lower())
			if not own.is_empty():
				src = "S"
			elif not bark.bark_set.fallback.is_empty():
				src = "F"
		if src == "-" and not bark.bark_clips.is_empty():
			src = "C"
		cells.append(src)
		if src == "-" and counts_as_chassis:
			_mute.append("%s: %s" % [label, LINE_NAMES[i]])
	var names := PackedStringArray()
	for c in bark.bark_clips:
		names.append(c.resource_path.get_file().get_basename().replace("WAV_RDV__", "#"))
	var clip_note := ", ".join(names)
	var mine := PackedStringArray()
	for c in bark.bark_clips:
		mine.append(c.resource_path.get_file())
	if mine == default_clips:
		clip_note += "  (= bark.tscn defaults)"
	if not ("C" in cells) and not bark.bark_clips.is_empty():
		clip_note += "  [never reached]"
	print("%-20s %-4s %-26s %-10s %-6d %-12s %s   %s" % [label, cat_flag,
		scene_path.get_file(), set_name.replace("bark_set_", ""), bark.bark_clips.size(),
		"%.2f..%.2f" % [bark.pitch_min, bark.pitch_max], " ".join(cells), clip_note])
	root.free()


# ─────────────────────────────────────────────
func _report_director() -> void:
	print("\n== BARK DIRECTOR")
	print("ELECTION_WINDOW   %.2fs   EARSHOT %.0fm   SQUAD_COOLDOWN %.1fs   SPEAKER_COOLDOWN %.1fs" % [
		BarkDirector.ELECTION_WINDOW, BarkDirector.EARSHOT,
		BarkDirector.SQUAD_COOLDOWN, BarkDirector.SPEAKER_COOLDOWN])
	print("CHANNEL_COOLDOWN  FRIENDLY %.1f  HOSTILE %.1f  ORDERS %.1f" % [
		BarkDirector.CHANNEL_COOLDOWN[BarkDirector.Channel.FRIENDLY],
		BarkDirector.CHANNEL_COOLDOWN[BarkDirector.Channel.HOSTILE],
		BarkDirector.CHANNEL_COOLDOWN[BarkDirector.Channel.ORDERS]])
	print("%-10s %8s %14s" % ["line", "priority", "line cooldown"])
	for i in LINE_NAMES.size():
		print("%-10s %8d %13.1fs" % [LINE_NAMES[i], BarkDirector.PRIORITY.get(i, 0), BarkDirector.LINE_COOLDOWN.get(i, 5.0)])

	# THE NCO BONUS. Bark.bark() hands the director `self` — the Bark node — as
	# the speaker, and _speaker_score compares that against squad.nco, which is
	# the Soldier body. Asked both ways, so the answer is measured, not argued.
	var soldier: Node = (load(AI_DIR + "soldier_chassis.tscn") as PackedScene).instantiate()
	var squad := Squad.new()
	squad.nco = soldier
	var via_bark: float = BarkDirector._speaker_score(soldier.bark, squad)
	var via_body: float = BarkDirector._speaker_score(soldier, squad)
	print("NCO bonus: speaker = Bark node (what Bark.bark() passes) -> %.0f ; speaker = Soldier body -> %.0f" % [via_bark, via_body])
	# THE SQUADLESS CHANNEL. _channel_for falls back to the speaker's faction
	# when there is no squad to ask — and the speaker is the Bark node, which
	# has no get_faction() of its own, so this used to land EVERY squadless
	# robot on HOSTILE and keep friendlies out of the comms log entirely.
	# Since K13 it walks up to the body the way Bark._resolve_squad() does.
	#
	# ASKED FROM BOTH SIDES, because one answer proves nothing: a hostile body
	# returning HOSTILE is the right answer for the wrong reason if the walk is
	# broken. The chassis defaults to Factions.ENEMY, so the friendly case has
	# to be set deliberately.
	var ch_hostile: int = BarkDirector._channel_for(soldier.bark, BarkSet.Line.CONTACT, null)
	soldier.faction = Enums.Factions.PLAYER
	var ch_friendly: int = BarkDirector._channel_for(soldier.bark, BarkSet.Line.CONTACT, null)
	print("Squadless channel, read off the BODY (Bark itself has get_faction: %s):" % \
		soldier.bark.has_method("get_faction"))
	print("   body faction ENEMY  -> %s" % BarkDirector.Channel.keys()[ch_hostile])
	print("   body faction PLAYER -> %s%s" % [BarkDirector.Channel.keys()[ch_friendly],
		"" if ch_friendly == BarkDirector.Channel.FRIENDLY \
		else "   <-- K13 REOPENED: a squadless friendly cannot reach the comms log"])
	squad.free()
	soldier.free()


func _report_comms_vocabulary() -> void:
	print("\n== COMMS LOG VOCABULARY (CommsLog._compose, who=\"Vex\", context=\"Chaser\" / empty)")
	var log: Control = (load(COMMS) as GDScript).new()
	for i in LINE_NAMES.size():
		print("%-10s %-44s | %s" % [LINE_NAMES[i], log._compose("Vex", i, "Chaser"), log._compose("", i, "")])
	log.free()
	print("Channels reported to the log: FRIENDLY, ORDERS (BarkDirector._resolve). HOSTILE never.")


# ─────────────────────────────────────────────
func _report_hud() -> void:
	print("\n== HUD SCENE (%s), children as authored" % HUD_SCENE)
	var hud: Node = (load(HUD_SCENE) as PackedScene).instantiate()
	for c in hud.get_children():
		var s: Script = c.get_script()
		print("   %-16s %-14s %s" % [c.name, c.get_class(), s.resource_path.get_file() if s != null else ""])
	var filter := hud.get_node_or_null("SignalFilter") as CanvasItem
	if filter != null and filter.material is ShaderMaterial:
		var mat := filter.material as ShaderMaterial
		print("SignalFilter uniforms FROM THE SCENE (not the shader defaults):")
		for p in ["luma_levels", "chroma_levels", "palette_strength", "saturation",
				"edge_strength", "edge_threshold", "dither_strength", "signal_height",
				"signal_fps", "mid_tint", "high_tint", "edge_color"]:
			print("   %-16s %s" % [p, str(mat.get_shader_parameter(p))])
	else:
		print("SignalFilter: not found or not a ShaderMaterial")
	print("hud.gd damage knobs (scene values): spike %.2f  decay %.2f/s  cap %.2f  ceiling %.2f" % [
		hud.damage_spike, hud.damage_spike_decay, hud.damage_spike_cap, hud.damage_ceiling])
	hud.free()


func _report_world_wiring() -> void:
	print("\n== SIGNALS world.tscn wires INTO the HUD (invisible to a grep for the method's callers)")
	for line in FileAccess.get_file_as_string(WORLD).split("\n"):
		if line.begins_with("[connection") and "to=\"HUD" in line:
			print("   %s" % line)


# ─────────────────────────────────────────────
func _collect(dir_path: String, ext: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("probe_hud_facts: cannot open %s, so nothing under it is reported." % dir_path)
		return
	for f in dir.get_files():
		if f.ends_with(ext):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		if d.begins_with("."):
			continue
		_collect(dir_path.path_join(d), ext, out)
