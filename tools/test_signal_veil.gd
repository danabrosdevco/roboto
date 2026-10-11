extends SceneTree

# ─────────────────────────────────────────────
# LOSING SIGNAL TAKES INFORMATION AWAY, IN ORDER.
#
# The ladder is the point: a player has to be able to read their own condition
# off what is missing, which only works if the order never changes and the
# boundaries are the same ones that degrade a robot.
#
#   CLEAN      everything
#   FUZZED     health goes
#   DEGRADED   state goes
#   CRITICAL   the callsign goes, replaced by a contact number
#   EKILL      the squad layer is gone
#
# The corruption is tested for the two properties that make it read as a bad
# connection rather than a broken screen: it MOVES with the phase, and it
# leaves spaces alone so a mangled line still scans as the thing it used to be.
#
#   godot --headless --audio-driver Dummy --path . --script tools/test_signal_veil.gd
# ─────────────────────────────────────────────

const _Noise := preload("res://Character/hud/signal_noise.gd")

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fail += 1


func _init() -> void:
	Engine.max_fps = 60
	Settings.path = "user://settings_probe.json"
	await process_frame

	# ── the ladder sits on AI's own thresholds ──
	_check("a clean link shows everything",
		_Noise.veil_for(1.0) == _Noise.Veil.ALL)
	_check("FUZZED drops health",
		_Noise.veil_for(AI.SIGNAL_FUZZED) == _Noise.Veil.NO_HEALTH,
		"at %.2f" % AI.SIGNAL_FUZZED)
	_check("DEGRADED drops state",
		_Noise.veil_for(AI.SIGNAL_DEGRADED) == _Noise.Veil.NO_STATE,
		"at %.2f" % AI.SIGNAL_DEGRADED)
	_check("CRITICAL drops the callsign",
		_Noise.veil_for(AI.SIGNAL_CRITICAL) == _Noise.Veil.CONTACT_ONLY,
		"at %.2f" % AI.SIGNAL_CRITICAL)
	_check("the floor takes the squad layer",
		_Noise.veil_for(0.0) == _Noise.Veil.BLIND)
	_check("an e-killed drone is BLIND whatever its integrity reads",
		_Noise.veil_for(1.0, true) == _Noise.Veil.BLIND,
		"the latch has to win, or a recovering drone flickers its whole UI back")

	# MONOTONIC. The ladder only ever takes things away as signal falls — if it
	# ever gave something back on the way down, the player could not learn it.
	var last: int = -1
	var monotonic := true
	for i in 101:
		var v: int = _Noise.veil_for(1.0 - float(i) / 100.0)
		if v < last:
			monotonic = false
			break
		last = v
	_check("the ladder never hands information back as signal falls", monotonic)

	# ── corruption behaves like a bad link, not a broken screen ──
	var clean := "SQUAD KIT 2 OF 5"
	_check("a clean link corrupts nothing",
		_Noise.bleed(clean, _Noise.Veil.ALL) == clean)

	var bad := _Noise.corrupt(clean, 0.5, 1)
	_check("a bad link does corrupt",
		bad != clean, "nothing changed, so the effect is invisible")
	_check("...but keeps the line the same length",
		bad.length() == clean.length(),
		"a reflowing readout reads as a layout bug")

	var spaces_kept := true
	for i in clean.length():
		if clean[i] == " " and bad[i] != " ":
			spaces_kept = false
	_check("...and never eats spaces, so the line still scans", spaces_kept,
		"word shapes are what make it unsettling instead of illegible")

	_check("the noise MOVES between phases",
		_Noise.corrupt(clean, 0.5, 1) != _Noise.corrupt(clean, 0.5, 2),
		"a frozen pattern reads as a broken screen")
	_check("...but holds still within one phase",
		_Noise.corrupt(clean, 0.5, 7) == _Noise.corrupt(clean, 0.5, 7),
		"it must not strobe every frame")

	# Worse link, more damage — in the right direction.
	var fuzz := 0
	var crit := 0
	for i in clean.length():
		if _Noise.bleed(clean, _Noise.Veil.NO_HEALTH, 3)[i] != clean[i]:
			fuzz += 1
		if _Noise.bleed(clean, _Noise.Veil.CONTACT_ONLY, 3)[i] != clean[i]:
			crit += 1
	_check("a worse link eats more of the line", crit > fuzz,
		"fuzzed ate %d, critical ate %d" % [fuzz, crit])

	# ── the failure register ──
	_check("a dead readout says something procedural, not 'ERROR'",
		_Noise.lost_line(0) != "" and not _Noise.lost_line(0).contains("ERROR"))
	_check("...and it cycles rather than flashing one line",
		_Noise.lost_line(0) != _Noise.lost_line(1))
	_check("a contact without a callsign is still counted",
		_Noise.contact_name(0) == "CONTACT 01" and _Noise.contact_name(11) == "CONTACT 12")

	# ── fails open ──
	_check("no player to ask means show everything",
		_Noise.veil_of(null) == _Noise.Veil.ALL,
		"a readout that fails closed hides the game when something unrelated breaks")

	print("")
	print("VEIL FAILURES: %d" % _fail)
	print("ALL SIGNAL VEIL CHECKS PASS" if _fail == 0 else "SIGNAL VEIL CHECKS FAILED")
	quit(1 if _fail > 0 else 0)
