extends SceneTree

# ─────────────────────────────────────────────
# AUDIO AUDIT — how loud is every gun at the listener, at range, and which bus
# does it actually land on.
#
# "Can you hear it from over there" is a number, not an opinion. Godot's
# inverse-distance attenuation is
#
#     gain_db(d) = volume_db + min(max_db, linear_to_db(unit_size / d))
#
# so unit_size is the distance at which a sound plays at its authored volume,
# and every doubling past that costs 6 dB. This prints that curve for every
# weapon in the project, alongside the bus it will really be on once
# AudioBuses._route has moved anything still sitting on Master.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/audit_audio.gd
# ─────────────────────────────────────────────

const RANGES := [10.0, 25.0, 50.0, 100.0, 200.0, 400.0]
## Below this at the listener, a sound is masked by anything else going on.
const FLOOR_DB := -40.0


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var rows: Array = []
	for dir in ["res://Character/weapon", "res://Character/equipment"]:
		for path in _scenes(dir):
			var packed: PackedScene = load(path)
			if packed == null:
				continue
			for r in _players(packed.get_state(), path.get_file().get_basename()):
				rows.append(r)

	print("")
	print("══ AUDIO AUDIT ════════════════════════════════════════════════════")
	print("gain at the listener, dB. Anything under %.0f is masked in a firefight." % FLOOR_DB)
	print("%-30s %-9s %5s %6s %7s %s" % ["sound", "bus", "unit", "vol", "cutoff",
		" ".join(RANGES.map(func(d): return "%6dm" % int(d)))])
	rows.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))
	for r in rows:
		var line := ""
		for d in RANGES:
			if r["max_distance"] > 0.0 and d > r["max_distance"]:
				line += "%7s" % "--"
				continue
			line += "%7.1f" % _gain(r, d)
		print("%-30s %-9s %5.0f %6.1f %7s %s" % [
			r["name"], r["bus"], r["unit_size"], r["volume_db"],
			("%.0fm" % r["max_distance"]) if r["max_distance"] > 0.0 else "none", line])

	# ── WHAT IS ON THE GUN BUS ───────────────────
	print("")
	print("── THE WEAPONS BUS ────────────────────────────────────────────────")
	print("AudioBuses builds a Weapons bus (EQ + compressor + limiter) under")
	print("Effects for exactly this job. _route() only moves Master -> Effects,")
	print("so a scene that does not NAME the bus never reaches those effects.")
	var on_weapons: Array = []
	var on_effects: Array = []
	for r in rows:
		if String(r["bus"]) == "Weapons":
			on_weapons.append(r["name"])
		else:
			on_effects.append(r["name"])
	print("  on Weapons (%d): %s" % [on_weapons.size(), ", ".join(on_weapons)])
	print("  on Effects (%d): %s" % [on_effects.size(), ", ".join(on_effects)])

	print("")
	print("── CUT OFF EARLY ──────────────────────────────────────────────────")
	var capped := rows.filter(func(r): return r["max_distance"] > 0.0)
	if capped.is_empty():
		print("  nothing sets max_distance")
	for r in capped:
		print("  %-28s silent past %.0fm" % [r["name"], r["max_distance"]])
	quit(0)


## Godot's inverse-distance law, the default attenuation_model.
func _gain(r: Dictionary, distance: float) -> float:
	var att: float = float(r["unit_size"]) / maxf(distance, 0.0001)
	return float(r["volume_db"]) + minf(float(r["max_db"]), linear_to_db(att))


## Every AudioStreamPlayer3D a scene declares, read as packed data so nothing
## has to be instantiated or make a sound.
func _players(st: SceneState, scene: String) -> Array:
	var out: Array = []
	for i in st.get_node_count():
		if st.get_node_type(i) != &"AudioStreamPlayer3D":
			continue
		var row := {
			"name": "%s/%s" % [scene, st.get_node_name(i)],
			"bus": "Master", "unit_size": 10.0, "volume_db": 0.0,
			"max_db": 3.0, "max_distance": 0.0,
		}
		for j in st.get_node_property_count(i):
			var prop := String(st.get_node_property_name(i, j))
			var v: Variant = st.get_node_property_value(i, j)
			if row.has(prop):
				row[prop] = str(v) if prop == "bus" else float(v)
		# What AudioBuses._route will have done by the time it plays.
		if String(row["bus"]) == "Master":
			row["bus"] = "Effects"
		out.append(row)
	return out


func _scenes(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".tscn"):
			out.append("%s/%s" % [dir, f])
	return out
