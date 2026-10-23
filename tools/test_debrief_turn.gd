extends SceneTree
# BUCKET: campaign

# ─────────────────────────────────────────────
# THE DEBRIEF HAS TO SAY A TURN HAPPENED.
#
# Phase 6 made clearing an operation advance the campaign — time moves, held
# ground pays, the other side takes a site. All of it happened INVISIBLY: the
# debrief reported a payout and a body count exactly as before, so the player
# had no way to know a turn had passed or that something of theirs was gone.
#
# This checks the words actually reach the screen, which a parse check cannot.
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_debrief_turn.gd
# ─────────────────────────────────────────────

const _Debrief := preload("res://Character/hud/debrief_screen.gd")

var _fails: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fails += 1


func _init() -> void:
	Settings.path = "user://settings_probe.json"
	await process_frame
	var d = _Debrief.new()
	root.add_child(d)
	await process_frame

	# ── a turn in which they took something ─────
	var taken := _say(d, {
		"turn": 7, "site_taken": "Valley Basin", "site_compute": 1,
		"enemy": {"outcome": 2, "site": "coast_road"},
	})
	_check("the turn number is on the screen", _has(taken, "TURN 7"), str(taken))
	_check("...and what you took", _has(taken, "VALLEY BASIN IS YOURS"))
	_check("...and the compute it carries", _has(taken, "+1 COMPUTE"))
	_check("ADVERSARY TOOK SOMETHING, and it says so",
		_has(taken, "ADVERSARY TOOK COAST ROAD"), str(taken))

	# ── a raid in doubt is NOT reported here ────
	# It is a thing you go and ANSWER, so it belongs where you choose where to
	# go: the operations table marks it in CRIT red and offers the defence.
	# The debrief is the one screen you cannot act from.
	var doubt := _say(d, {
		"turn": 8, "enemy": {"outcome": 3, "site": "valley_basin"},
	})
	_check("an in-doubt raid is NOT announced on the debrief",
		not _has(doubt, "UNDER ATTACK") and not _has(doubt, "DEFEND IT"), str(doubt))
	_check("...and the turn is still reported", _has(doubt, "TURN 8"))

	# ── one you walked away from ────────────────
	var declined := _say(d, {
		"turn": 9, "declined_site": "polaris", "declined_outcome": 2,
	})
	_check("a defence you declined is reported", _has(declined, "POLARIS")
		and _has(declined, "LOST WITHOUT YOU"), str(declined))

	# ── a quiet turn says nothing extra ─────────
	var quiet := _say(d, {"turn": 10, "enemy": {"outcome": 0, "site": ""}})
	_check("a quiet turn does not invent news",
		_has(quiet, "TURN 10") and not _has(quiet, "UNDER ATTACK")
		and not _has(quiet, "ADVERSARY TOOK"), str(quiet))

	# ── A SIM ARENA IS NOT A TURN ───────────────
	var sim_box = d._turn_report({"sim": true, "turn": 10})
	_check("a sim run shows no turn report at all", not sim_box.visible)

	# ── the payout is a LIST of sources ─────────
	var rewards = d._rewards({
		"resources_before": 100, "resources_after": 160,
		"reward": 20, "income": 40,
	})
	var words := _labels(rewards)
	_check("every source is its own row, name and amount apart",
		_has(words, "HOLDINGS") and _has(words, "40")
		and _has(words, "OPERATION") and _has(words, "20"), str(words))
	_check("...not run together into a sentence", not _has(words, "40 HOLDINGS"))
	_check("...and the balance is not on this screen", not _has(words, "IN THE BANK"))

	print("")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)


func _say(d, result: Dictionary) -> Array:
	return _labels(d._turn_report(result))


func _labels(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		out.append_array(_labels(c))
	return out


func _has(texts: Array, want: String) -> bool:
	for t in texts:
		if String(t).findn(want) >= 0:
			return true
	return false
