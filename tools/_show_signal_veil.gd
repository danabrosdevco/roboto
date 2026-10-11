extends SceneTree

# ─────────────────────────────────────────────
# SEE THE LADDER. Not a description of it — the real thing.
#
# This builds actual SquadHUD rows with _make_member_row_veiled() and reads the
# Label text back out of them, and drives the real designator strings through
# the real corruption. So what prints is what the screen would draw, not a
# second implementation that could drift from it.
#
# Headless cannot render pixels, so this prints the text. For actual in-game
# frames the rig is tools/mockup_shots.gd, which runs headful.
#
#   godot --headless --audio-driver Dummy --path . --script tools/_show_signal_veil.gd
# ─────────────────────────────────────────────

const _Noise := preload("res://Character/hud/signal_noise.gd")
const RIFLE := "res://Character/characters/ai/soldier_rifle.tscn"
const HUD := "res://Character/hud/squad_hud.gd"

const TIERS := [
	{"v": 0, "sig": 1.00, "name": "CLEAN",    "why": "full link"},
	{"v": 1, "sig": 0.70, "name": "FUZZED",   "why": "health gone"},
	{"v": 2, "sig": 0.45, "name": "DEGRADED", "why": "state gone"},
	{"v": 3, "sig": 0.20, "name": "CRITICAL", "why": "callsign gone"},
	{"v": 4, "sig": 0.00, "name": "EKILL",    "why": "squad layer gone"},
]


## Every Label in a built row, in order, as the player would read it.
func _row_text(row: Node) -> String:
	var parts: Array[String] = []
	_walk(row, parts)
	return "  ".join(parts) if not parts.is_empty() else "(no text)"


func _walk(n: Node, out: Array[String]) -> void:
	if n is Label and String((n as Label).text).strip_edges() != "":
		out.append(String((n as Label).text).strip_edges())
	elif n.get_class() == "ColorRect" or n.get_class() == "TextureRect":
		pass
	for c in n.get_children():
		_walk(c, out)


func _init() -> void:
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame

	var world: Node = load("res://Env/world.tscn").instantiate()
	world.get_node("CampaignManager").autosave = false   # never write the real save
	root.add_child(world)
	for _i in 60:
		await physics_frame
	var level: Node = world.player.get_parent()

	# Three bodies at different health, so the ladder has something to hide.
	var names := ["BRAVO-1", "BRAVO-2", "BRAVO-3"]
	var hurt := [1.0, 0.55, 0.2]
	var bots: Array = []
	for i in 3:
		var b = load(RIFLE).instantiate()
		level.add_child(b)
		await process_frame
		b.faction = Enums.Factions.PLAYER
		b.player = world.player
		b.soldier_name = names[i]
		b.health = maxi(1, int(b.max_health * hurt[i]))
		bots.append(b)
	for _i in 10:
		await physics_frame

	var hud = load(HUD).new()
	hud.player = world.player

	print("")
	print("==========================================================================")
	print("  SQUAD ROSTER, AS THE LINK DEGRADES")
	print("  Real rows from SquadHUD._make_member_row_veiled(), text read back out.")
	print("==========================================================================")
	for t in TIERS:
		var veil: int = _Noise.veil_for(float(t["sig"]))
		print("")
		print("  signal %.2f   %-9s  %s" % [t["sig"], t["name"], t["why"]])
		print("  " + "-".repeat(70))
		if veil >= _Noise.Veil.BLIND:
			print("    %s" % _Noise.lost_line(0))
			print("    (no roster at all — not an empty panel, nothing)")
			continue
		for i in bots.size():
			var row = hud._make_member_row_veiled(bots[i], veil, i)
			print("    %s" % _row_text(row))
			row.free()

	print("")
	print("==========================================================================")
	print("  THE DESIGNATOR, SAME LADDER")
	print("  Real strings through Noise.bleed(), three consecutive phases each,")
	print("  so you can see the corruption CRAWL rather than sit still.")
	print("==========================================================================")
	var label := "SQUAD KIT"
	var status := "3 CAN ANSWER"
	for t in TIERS:
		var veil: int = _Noise.veil_for(float(t["sig"]))
		print("")
		print("  signal %.2f   %s" % [t["sig"], t["name"]])
		print("  " + "-".repeat(70))
		if veil >= _Noise.Veil.BLIND:
			for p in 3:
				print("    %-18s  %s" % [_Noise.lost_line(p),
					_Noise.corrupt("SQUAD UNREACHABLE", 0.5, p)])
			continue
		for p in 3:
			print("    %-18s  %-20s  %s" % [
				_Noise.bleed(label, veil, p),
				_Noise.bleed(status, veil, p),
				_Noise.bleed("2/5", veil, p)])

	print("")
	print("==========================================================================")
	print("  Thresholds are AI's own: FUZZED %.2f  DEGRADED %.2f  CRITICAL %.2f  EKILL %.2f"
		% [AI.SIGNAL_FUZZED, AI.SIGNAL_DEGRADED, AI.SIGNAL_CRITICAL, AI.SIGNAL_EKILL])
	print("  So the readout degrades on exactly the boundaries that degrade a robot.")
	print("==========================================================================")
	print("")
	quit(0)
