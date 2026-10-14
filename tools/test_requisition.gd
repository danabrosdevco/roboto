extends SceneTree

# ─────────────────────────────────────────────
# ARGUS TAKES THE SURPLUS, AND THE PLAYER DECIDES WHAT TO DROP.
#
# The campaign goes well, compute accumulates, and the thing at the top of the
# chain of command notices there is a surplus down here and requisitions it.
#
# Five things have to hold:
#   1. a requisition inside the surplus is painless — it eats free compute and
#      the books still balance
#   2. a requisition BEYOND the surplus leaves the ledger over-allocated rather
#      than failing, and rather than choosing a robot to stand down for you
#   3. nothing is destroyed: the seats and software are all still held, so the
#      player's squad and build are intact until they choose otherwise
#   4. freeing a seat or uninstalling a program clears the debt
#   5. compute_earned never goes negative, however much is taken
#
#   godot --headless --audio-driver Dummy --path . --script tools/test_requisition.gd
# ─────────────────────────────────────────────

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s%s" % ["PASS" if ok else "FAIL", label, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fail += 1


func _init() -> void:
	await process_frame
	var s := CampaignState.new()

	# A campaign that has been going well: 10 compute earned, four of it spent
	# holding seats, three on a program. Three free.
	s.compute_earned = 10
	s.compute_held = {"seat:1": 1, "seat:2": 1, "seat:3": 1, "seat:4": 1, "software:command_1": 3}
	_check("(setup) ten earned, seven held, three free", s.compute_free() == 3,
		"free reads %d" % s.compute_free())
	_check("...and the books balance", not s.over_allocated())

	# ── 1. inside the surplus ───────────────────
	var over := s.requisition_compute(2)
	_check("a small requisition just eats the surplus", over == 0 and s.compute_free() == 1,
		"free %d, over %d" % [s.compute_free(), over])

	# ── 2. beyond the surplus ───────────────────
	over = s.requisition_compute(4)
	_check("a big one leaves the ledger OVER-ALLOCATED", s.over_allocated(),
		"it should not fail and should not refuse")
	_check("...by the right amount", over == 3 and s.over_allocated_by() == 3,
		"owed %d, earned %d, held 7" % [over, s.compute_earned])
	_check("...and compute_free goes negative rather than clamping",
		s.compute_free() == -3,
		"a clamp would hide the debt and block deployment for no visible reason")

	# ── 3. nothing was taken from the player ────
	_check("the seats are all still held", s.seats_held() == 4,
		"Argus takes compute, not robots")
	_check("...and the program is still installed", s.is_installed(&"command_1"),
		"nothing is uninstalled for you; the choice is the player's")

	# ── 4. the player pays it back ──────────────
	s.compute_held.erase("software:command_1")       # uninstall the tier-3 program
	_check("uninstalling a program clears the debt", not s.over_allocated(),
		"still owed %d" % s.over_allocated_by())
	_check("...and leaves exactly the right surplus", s.compute_free() == 0,
		"free reads %d" % s.compute_free())

	# ── 5. the floor ────────────────────────────
	s.requisition_compute(9999)
	_check("earned never goes negative", s.compute_earned == 0,
		"earned reads %d" % s.compute_earned)
	_check("...and the debt is the whole of what is still held",
		s.over_allocated_by() == 4,
		"four seats held against nothing earned")

	# ── and a requisition of nothing does nothing ──
	var before := s.compute_earned
	s.requisition_compute(0)
	s.requisition_compute(-5)
	_check("a zero or negative requisition is a no-op", s.compute_earned == before)

	print("")
	print("REQUISITION FAILURES: %d" % _fail)
	print("ALL REQUISITION CHECKS PASS" if _fail == 0 else "REQUISITION CHECKS FAILED")
	quit(1 if _fail > 0 else 0)
