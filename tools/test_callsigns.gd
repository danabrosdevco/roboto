extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# THE THREE FACTIONS DO NOT SOUND ALIKE.
#
# That contrast is the cheapest characterisation in the game and the easiest
# thing to erode by accident — one helpful "fall back to the other pool" and
# the Swarm starts fielding squads called OVERWATCH. So it is a test.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_callsigns.gd
# ─────────────────────────────────────────────

const _Cs := preload("res://Campaign/callsigns.gd")

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame

	var swarm := _Cs.pool(Enums.Factions.SWARM)
	var home := _Cs.pool(Enums.Factions.HOME)
	_check("the Swarm has a deep pool", swarm.size() >= 150, "%d names" % swarm.size())
	_check("Home Command has one too", home.size() >= 80, "%d names" % home.size())

	# ── the contrast, which is the point ────────
	var overlap: Array = []
	for n in swarm:
		if home.has(n):
			overlap.append(String(n))
	_check("no name belongs to both factions", overlap.is_empty(), str(overlap))

	# THE SWARM NEVER SPEAKS ENGLISH. The site pools are English and suit Home
	# Command; a Swarm squad called ABUTMENT on the Causeway would throw away
	# the one thing telling the player who they are fighting.
	var leaked: Array = []
	for site in [&"causeway", &"lockside", &"polaris", &"hillfort_wip"]:
		var with_site := _Cs.pool(Enums.Factions.SWARM, site)
		if with_site.size() != swarm.size():
			leaked.append(String(site))
	_check("a site NEVER widens the Swarm's vocabulary", leaked.is_empty(), str(leaked))

	var cause := _Cs.pool(Enums.Factions.HOME, &"causeway")
	_check("...but it does widen Home Command's", cause.size() > home.size(),
		"%d -> %d on the Causeway" % [home.size(), cause.size()])

	# ── seeded, so a squad keeps its name ───────
	var a: StringName = _Cs.take(Enums.Factions.SWARM, "basin/squad/3")
	var b: StringName = _Cs.take(Enums.Factions.SWARM, "basin/squad/3")
	_check("the same seed gives the same name every time", a == b, "%s / %s" % [a, b])
	_check("...and a different one gives a different name",
		_Cs.take(Enums.Factions.SWARM, "basin/squad/4") != a)

	# ── no duplicates in one operation ──────────
	var taken: Array = []
	for i in 40:
		var n: StringName = _Cs.take(Enums.Factions.SWARM, "basin/squad/%d" % i, taken)
		if taken.has(n):
			_check("forty squads, forty different names", false, "%s repeated" % n)
			break
		taken.append(n)
	if taken.size() == 40:
		_check("forty squads, forty different names", true)

	# Even past the end of the pool it must not repeat.
	var all_taken: Array = []
	all_taken.append_array(swarm)
	var past: StringName = _Cs.take(Enums.Factions.SWARM, "x", all_taken)
	_check("a pool run dry numbers rather than repeats",
		not swarm.has(past), String(past))

	# ── Argus does not use language ─────────────
	var argus: Array = []
	for i in 20:
		argus.append(_Cs.take(Enums.Factions.ARGUS, "argus/%d" % i, argus))
	var worded: Array = []
	for n in argus:
		if swarm.has(n) or home.has(n):
			worded.append(String(n))
	_check("Argus never produces a real callsign", worded.is_empty(), str(worded))
	var machine := 0
	for n in argus:
		var s := String(n)
		if s.contains("-") or s.contains(".") or s.contains("_") or s.contains("0x") \
				or s.length() >= 4:
			machine += 1
	_check("...it produces identifiers", machine == argus.size(),
		"%d of %d: %s" % [machine, argus.size(), str(argus.slice(0, 6))])
	_check("...and no two alike", argus.size() == _unique(argus).size())

	print("")
	print("  swarm sample: %s" % str(_sample(Enums.Factions.SWARM, &"", 6)))
	print("  home  sample: %s" % str(_sample(Enums.Factions.HOME, &"causeway", 6)))
	print("  argus sample: %s" % str(argus.slice(0, 6)))
	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _sample(faction: int, site: StringName, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(String(_Cs.take(faction, "sample/%d" % i, out, site)))
	return out


func _unique(a: Array) -> Array:
	var seen := {}
	for x in a:
		seen[x] = true
	return seen.keys()
