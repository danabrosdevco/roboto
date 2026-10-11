extends SceneTree

# ─────────────────────────────────────────────
# FACTIONS — who attacks whom
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_factions.gd
#
# WHY THIS SUITE EXISTS. Enums.are_hostile() used to be a `match` with four
# arms and a `return false` at the bottom. Appending a fifth Factions value to
# that gave you a robot that was simultaneously INVISIBLE and
# NEAR-INVULNERABLE, in both directions, across thirty-five call sites, not one
# of which errored:
#
#   * outbound-false (are_hostile(PLAYER, X) == false) means nothing ever
#     targets it, no mine ever arms on it, and killing it tallies as friendly
#     fire;
#   * inbound-false (are_hostile(X, PLAYER) == false) means ai_weapon.gd's
#     _is_friendly() calls every body in the world friendly, so
#     friendly_in_line() blocks the frame's own shot and check_melee_damage()
#     skips its whole sweep. The frame refuses to fight.
#
# GDScript does not warn on a non-exhaustive match on an enum, so nothing
# caught it and nothing would have.
#
# ASSERTION 1 IS THE POINT OF THE FILE. Every other assertion here guards a
# faction that already exists. "Every Factions value has a HOSTILITY row" is
# the only one that makes the NEXT append fail loudly instead of repeating the
# bug, which is why it runs first and why it is written as a loop over
# Factions.values() rather than a list of names.
# ─────────────────────────────────────────────

var _fails: int = 0

# The ORIGINAL four, by name, so the regression lock below cannot silently
# widen when a faction is appended.
const ORIGINAL := [
	Enums.Factions.PLAYER,
	Enums.Factions.ENEMY,
	Enums.Factions.ALLIED,
	Enums.Factions.NEUTRAL,
]

# The three hostile factions appended 2026-10-10.
const APPENDED := [
	Enums.Factions.SWARM,
	Enums.Factions.HOME,
	Enums.Factions.ARGUS,
]

# THE OLD FUNCTION'S TRUTH TABLE, transcribed by hand from the `match` that
# HOSTILITY replaced (Managers/enums.gd, pre-2026-10-10):
#
#	if faction_b == NEUTRAL: return false
#	match faction_a:
#		PLAYER:  return faction_b == ENEMY
#		ENEMY:   return faction_b == PLAYER or faction_b == ALLIED
#		ALLIED:  return faction_b == ENEMY
#		NEUTRAL: return false
#
# Sixteen ordered pairs. This is the evidence that the rewrite changed no
# existing behaviour, and it is deliberately a literal table rather than a
# re-expression of the new one — a table derived from HOSTILITY would agree
# with HOSTILITY by construction and prove nothing.
const OLD_TRUTH := {
	"PLAYER>PLAYER": false, "PLAYER>ENEMY": true,  "PLAYER>ALLIED": false, "PLAYER>NEUTRAL": false,
	"ENEMY>PLAYER":  true,  "ENEMY>ENEMY":  false, "ENEMY>ALLIED":  true,  "ENEMY>NEUTRAL":  false,
	"ALLIED>PLAYER": false, "ALLIED>ENEMY": true,  "ALLIED>ALLIED": false, "ALLIED>NEUTRAL": false,
	"NEUTRAL>PLAYER": false, "NEUTRAL>ENEMY": false, "NEUTRAL>ALLIED": false, "NEUTRAL>NEUTRAL": false,
}


func _init() -> void:
	_test_every_value_has_a_row()
	_test_the_original_four_are_unchanged()
	_test_the_new_factions_fight_the_player()
	_test_the_new_factions_fight_the_allies()
	_test_the_new_factions_do_not_fight_each_other()
	_test_nothing_attacks_neutral()
	_test_nothing_attacks_itself()

	print("")
	if _fails == 0:
		print("ALL FACTION CHECKS PASS")
	else:
		print("FACTION FAILURES: %d" % _fails)
	# EXIT CODE, NOT JUST A PRINTED COUNT. test.sh:120 keys the whole run on
	# PIPESTATUS alone, so a suite that prints FAILURES and quits 0 is reported
	# inside ALL SUITES PASS. test_ledger.gd and test_livery.gd get this right
	# and test_signal.gd and test_bulwark.gd do not; this is the right half.
	quit(1 if _fails > 0 else 0)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("PASS  %s" % label)
	else:
		_fails += 1
		print("FAIL  %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _name(f: int) -> String:
	return Enums.Factions.keys()[f]


# ─────────────────────────────────────────────
# 1. THE ONE THAT MATTERS. A value with no row gets a wrong answer from
# are_hostile() in both directions and nothing downstream errors. The
# push_error in are_hostile makes it loud at runtime; this makes it loud at
# commit time.
func _test_every_value_has_a_row() -> void:
	print("── every Factions value has a HOSTILITY row ──")
	for v in Enums.Factions.values():
		_ok("%s has a row" % _name(v), Enums.HOSTILITY.has(v),
			"append a row to Enums.HOSTILITY for it, or it is invisible and invulnerable")
	# And nothing extra, which would mean a row keyed by something that is not
	# a faction — a typo that reads as working.
	_ok("no orphan rows",
		Enums.HOSTILITY.size() == Enums.Factions.values().size(),
		"%d rows for %d values" % [Enums.HOSTILITY.size(), Enums.Factions.values().size()])


# ─────────────────────────────────────────────
# 2. The regression lock. This change touched every faction decision in the
# game, so the first question is whether it changed any of them.
func _test_the_original_four_are_unchanged() -> void:
	print("")
	print("── the original sixteen pairs are untouched ──")
	for a in ORIGINAL:
		for b in ORIGINAL:
			var key := "%s>%s" % [_name(a), _name(b)]
			var want: bool = OLD_TRUTH[key]
			var got: bool = Enums.are_hostile(a, b)
			_ok(key, got == want, "old said %s, table says %s" % [want, got])


# ─────────────────────────────────────────────
# 3 & 4. Both directions, every time, because §0.1 of
# docs/integration/BROODCARRIER.md shows the two directions fail differently
# and a frame can be broken in one of them while looking fine in the other.
func _test_the_new_factions_fight_the_player() -> void:
	print("")
	print("── the three new factions fight the player, both ways ──")
	for f in APPENDED:
		_ok("PLAYER attacks %s (outbound — or nothing targets it)" % _name(f),
			Enums.are_hostile(Enums.Factions.PLAYER, f))
		_ok("%s attacks PLAYER (inbound — or it refuses its own shot)" % _name(f),
			Enums.are_hostile(f, Enums.Factions.PLAYER))


func _test_the_new_factions_fight_the_allies() -> void:
	print("")
	print("── and the player's squad, both ways ──")
	for f in APPENDED:
		_ok("ALLIED attacks %s" % _name(f),
			Enums.are_hostile(Enums.Factions.ALLIED, f))
		_ok("%s attacks ALLIED" % _name(f),
			Enums.are_hostile(f, Enums.Factions.ALLIED))


# ─────────────────────────────────────────────
# 5. THE CULL INVARIANT, WRITTEN DOWN. AIManager.activation_sources() is built
# from hostiles_for(), and nearest_hostile_distance_sq() is the only thing that
# wakes a frozen robot. Make two hostile forces each other's activation sources
# and they keep each other awake across the whole map, and the distance cull
# stops culling — a performance cliff, not a nicety.
#
# It is also what the Bastion's hardening field depends on: its "ally" filter
# is same-faction rather than not-hostile precisely BECAUSE these are false.
func _test_the_new_factions_do_not_fight_each_other() -> void:
	print("")
	print("── the three new factions are NOT hostile to each other ──")
	for a in APPENDED:
		for b in APPENDED:
			if a == b:
				continue
			_ok("%s does not attack %s" % [_name(a), _name(b)],
				not Enums.are_hostile(a, b),
				"mutual hostility makes them each other's activation sources and the distance cull stops culling")


# ─────────────────────────────────────────────
# 6 & 7. The two properties that held for the old `match` by construction (its
# first line, and no arm naming its own faction) and now hold only because no
# row lists NEUTRAL and no row lists its own key.
func _test_nothing_attacks_neutral() -> void:
	print("")
	print("── nothing attacks NEUTRAL ──")
	for a in Enums.Factions.values():
		_ok("%s does not attack NEUTRAL" % _name(a),
			not Enums.are_hostile(a, Enums.Factions.NEUTRAL))


func _test_nothing_attacks_itself() -> void:
	print("")
	print("── no faction attacks itself ──")
	for a in Enums.Factions.values():
		_ok("%s does not attack %s" % [_name(a), _name(a)],
			not Enums.are_hostile(a, a))
