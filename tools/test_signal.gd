extends SceneTree

# ─────────────────────────────────────────────
# SIGNAL INTEGRITY, AND THAT THE PLAYER HAS ONE
#
#   godot --headless --audio-driver Dummy --path . --script res://tools/test_signal.gd
#
# The thing being guarded here is an INHERITANCE fact, which is exactly the
# kind that looks fine in the source and is false at runtime. signal_integrity
# used to live on Enemy; Player extends AI directly, so the player had none —
# and both sources of signal damage find their victims by asking:
#
#   ai_weapon._apply_near_miss_suppression   if "signal_integrity" in body
#   emp_blast                                has_method("receive_signal_damage")
#                                            and membership of a group
#
# Every one of those is a silent miss. Nothing errors, nothing logs, the player
# simply never takes signal damage from anything — which is what shipped. So
# these assertions are deliberately about the PLUMBING rather than the numbers:
# does the property exist, does the real weapon code find it, does the real
# blast code find it, and does it climb back out on its own.
# ─────────────────────────────────────────────

const PLAYER := "res://Character/characters/player/test_character.tscn"
const SOLDIER := "res://Character/characters/ai/soldier_rifle.tscn"
const EMP := "res://Character/weapon/emp/emp_blast.tscn"

var _fails: int = 0


func _init() -> void:
	await _test_player_has_a_signal()
	await _test_suppression_finds_the_player()
	await _test_emp_finds_the_player()
	await _test_it_recovers()
	await _test_lock_holds_it_down()
	await _test_enemy_still_works()
	await _test_the_player_suppresses_too()
	await _test_player_weapon_has_the_knobs()
	await _test_a_failing_link_slows_the_player()
	await _test_the_player_is_in_its_own_group()
	await _test_a_hit_suppresses_harder_than_a_miss()
	await _test_a_round_going_past_suppresses()
	await _test_explosions_rattle_the_link()
	await _test_a_blast_is_softer_on_your_own_side()
	await _test_tracers_are_coloured_by_side()

	print("")
	if _fails == 0:
		print("ALL SIGNAL CHECKS PASS")
	else:
		print("SIGNAL FAILURES: %d" % _fails)
	quit(0)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("PASS  %s" % label)
	else:
		_fails += 1
		print("FAIL  %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _spawn(path: String, at: Vector3 = Vector3.ZERO) -> Node:
	var body: Node = load(path).instantiate()
	root.add_child(body)
	if body is Node3D:
		(body as Node3D).global_position = at
	body.set_physics_process(false)
	body.set_process(false)
	return body


func _drop(n: Node) -> void:
	if is_instance_valid(n):
		n.free()
	await process_frame


# ─────────────────────────────────────────────
func _test_player_has_a_signal() -> void:
	var p := _spawn(PLAYER)
	await process_frame
	# Written exactly the way ai_weapon asks the question, not with a direct
	# property read — the point is that THAT test passes, not that the field
	# exists under some other name.
	_ok("the player answers to \"signal_integrity\" in body", "signal_integrity" in p)
	_ok("...and to has_method(receive_signal_damage)", p.has_method("receive_signal_damage"))
	_ok("...and to has_method(lock_signal)", p.has_method("lock_signal"))
	_ok("...and starts clean", is_equal_approx(float(p.signal_integrity), 1.0))
	_ok("...and is in the signal group, which is how EMP finds it",
			p.is_in_group(AI.SIGNAL_GROUP))
	await _drop(p)


func _test_suppression_finds_the_player() -> void:
	# THROUGH THE REAL WEAPON. Calling receive_signal_damage by hand would pass
	# whatever the plumbing did, which is the bug this is here to catch.
	var p := _spawn(PLAYER, Vector3.ZERO)
	var foe := _spawn(SOLDIER, Vector3(0, 0, 30))
	foe.faction = Enums.Factions.ENEMY
	if "faction" in p:
		p.faction = Enums.Factions.ALLIED
	await process_frame
	await physics_frame

	var gun := _find_ai_weapon(foe)
	if gun == null:
		_ok("the enemy soldier has an AIWeapon to suppress with", false,
				"found none under %s" % foe.name)
		await _drop(p)
		await _drop(foe)
		return
	var before: float = p.signal_integrity
	# A round going PAST the player and landing well beyond, which is what a
	# near miss actually is — see the note on suppress_along.
	gun._apply_near_miss_suppression(Vector3(0.6, 1.0, 30.0), Vector3(0.6, 1.0, -30.0))
	_ok("a near miss costs the player signal", p.signal_integrity < before,
			"%.3f -> %.3f" % [before, p.signal_integrity])

	# ...and its own side does not.
	var mate := _spawn(SOLDIER, Vector3(0, 0, 5))
	mate.faction = Enums.Factions.ALLIED
	await process_frame
	var mate_gun := _find_ai_weapon(mate)
	if mate_gun != null:
		var held: float = p.signal_integrity
		mate_gun._apply_near_miss_suppression(Vector3(0.6, 1.0, 30.0), Vector3(0.6, 1.0, -30.0))
		_ok("...but a squadmate's near miss does not",
				is_equal_approx(p.signal_integrity, held),
				"%.3f -> %.3f" % [held, p.signal_integrity])
	await _drop(mate)
	await _drop(p)
	await _drop(foe)


func _test_emp_finds_the_player() -> void:
	var p := _spawn(PLAYER, Vector3.ZERO)
	await process_frame
	var before: float = p.signal_integrity

	var blast: Node = load(EMP).instantiate()
	blast.source_faction = Enums.Factions.ENEMY
	root.add_child(blast)
	(blast as Node3D).global_position = Vector3(0, 0, 1.0)
	# _detonate is deferred from _ready, so the pulse lands next frame.
	await process_frame
	await process_frame

	_ok("an EMP at the player's feet costs it signal", p.signal_integrity < before,
			"%.3f -> %.3f" % [before, p.signal_integrity])
	_ok("...enough to e-kill at the centre",
			p.get_signal_state() == AI.SignalState.EKILL,
			"state=%d integrity=%.3f" % [p.get_signal_state(), p.signal_integrity])
	_ok("...and locks recovery", p.signal_locked())

	if is_instance_valid(blast):
		blast.free()
	await _drop(p)


func _test_it_recovers() -> void:
	var p := _spawn(PLAYER)
	await process_frame
	p.receive_signal_damage(0.4)
	var hurt: float = p.signal_integrity
	_ok("signal damage lands", hurt < 1.0)
	# One second of ticks at the stock 0.08/s.
	for _i in 60:
		p.tick_signal(1.0 / 60.0)
	_ok("...and recovers passively", p.signal_integrity > hurt,
			"%.3f -> %.3f" % [hurt, p.signal_integrity])
	# Against the property, not a literal: the rate is a balance knob and a test
	# that hardcodes it fails the moment anyone turns it, which teaches nothing.
	var want: float = p.signal_recovery_rate
	_ok("...at roughly signal_recovery_rate per second",
			absf((p.signal_integrity - hurt) - want) < 0.01,
			"climbed %.3f, expected ~%.3f" % [p.signal_integrity - hurt, want])
	# And it does not run away past full.
	for _i in 600:
		p.tick_signal(1.0 / 60.0)
	_ok("...and stops at 1.0", is_equal_approx(p.signal_integrity, 1.0),
			"%.3f" % p.signal_integrity)
	await _drop(p)


func _test_lock_holds_it_down() -> void:
	var p := _spawn(PLAYER)
	await process_frame
	p.receive_signal_damage(1.5)
	p.lock_signal(1.0)
	var floor_v: float = p.signal_integrity
	for _i in 30:   # half a second, still locked
		p.tick_signal(1.0 / 60.0)
	_ok("a lock stops recovery dead", is_equal_approx(p.signal_integrity, floor_v),
			"%.3f -> %.3f" % [floor_v, p.signal_integrity])
	for _i in 60:   # past the lock
		p.tick_signal(1.0 / 60.0)
	_ok("...and it climbs again once the lock runs out",
			p.signal_integrity > floor_v)
	# E-KILL latches out, not merely over the threshold.
	_ok("...but stays e-killed until SIGNAL_EKILL_RECOVER",
			p.get_signal_state() == AI.SignalState.EKILL,
			"integrity=%.3f" % p.signal_integrity)
	await _drop(p)


func _test_enemy_still_works() -> void:
	# The move to AI must not have cost the robots anything.
	var e := _spawn(SOLDIER)
	await process_frame
	_ok("a robot still has a signal", "signal_integrity" in e)
	e.receive_signal_damage(0.3)
	_ok("...still takes damage", e.signal_integrity < 1.0)
	_ok("...and still reports a band",
			e.get_signal_state() == Enemy.SignalState.FUZZED,
			"state=%d at %.2f" % [e.get_signal_state(), e.signal_integrity])
	# Enemy.SignalState and AI.SignalState have to be the same enum, or every
	# comparison across the two classes is a silent mismatch.
	_ok("...and Enemy.SignalState is AI.SignalState",
			int(Enemy.SignalState.EKILL) == int(AI.SignalState.EKILL)
			and int(Enemy.SignalState.CLEAN) == int(AI.SignalState.CLEAN))
	await _drop(e)


func _find_ai_weapon(body: Node) -> Node:
	for n in body.find_children("*", "", true, false):
		if n is AIWeapon:
			return n
	return null


# ─────────────────────────────────────────────
func _test_the_player_suppresses_too() -> void:
	# THE OTHER DIRECTION. Suppression used to be AI-only, which meant the
	# mechanic existed solely as something done TO you. Exercised through
	# AIWeapon.suppress_along, which is the function the player's gun actually
	# calls — a hand-rolled sphere query here would prove nothing about it.
	var foe := _spawn(SOLDIER, Vector3.ZERO)
	foe.faction = Enums.Factions.ENEMY
	var mate := _spawn(SOLDIER, Vector3(1.0, 0, 0))
	mate.faction = Enums.Factions.ALLIED
	await process_frame
	await physics_frame

	var before: float = foe.signal_integrity
	var mate_before: float = mate.signal_integrity
	var touched: int = AIWeapon.suppress_along(root.get_tree(),
			Vector3(0.5, 0.5, -4.0), Vector3(0.5, 0.5, 4.0),
			2.5, 0.035, null, Enums.Factions.ALLIED)
	_ok("the player's round suppresses a hostile", foe.signal_integrity < before,
			"%.3f -> %.3f (touched %d)" % [before, foe.signal_integrity, touched])
	_ok("...and leaves its own side alone",
			is_equal_approx(mate.signal_integrity, mate_before),
			"%.3f -> %.3f" % [mate_before, mate.signal_integrity])

	# A round that lands well away from anyone costs nobody anything.
	var held: float = foe.signal_integrity
	AIWeapon.suppress_along(root.get_tree(), Vector3(0, 0, 60.0), Vector3(0, 0, 70.0),
			2.5, 0.035, null, Enums.Factions.ALLIED)
	_ok("...and a round nowhere near anyone suppresses nobody",
			is_equal_approx(foe.signal_integrity, held))

	await _drop(mate)
	await _drop(foe)


## THE ACTUAL SCENES, not the script default.
##
## Scene values beat script defaults in this engine, so a weapon whose .tscn
## never mentions suppression_per_shot is the only thing the default protects —
## and a weapon whose .tscn sets it to something wrong would sail past a test
## that only ever instantiated the script. Each expected figure here is the AI
## weapon of the same kind, so the two sides of a firefight suppress alike.
func _test_player_weapon_has_the_knobs() -> void:
	var want := {
		"m4_hud_weapon": 3.5,
		"pistol_hud_weapon": 1.5,
		"bolt_hud_weapon": 7.0,
		"shotgun_hud_weapon": 5.0,
		"squad_auto_hud_weapon": 4.0,
		"cluster_hud_weapon": 22.0,
	}
	for name: String in want:
		var scene: PackedScene = load("res://Character/weapon/%s.tscn" % name)
		if scene == null:
			_ok("%s loads" % name, false)
			continue
		var w: Node = scene.instantiate()
		var got: float = float(w.suppression_per_shot) if "suppression_per_shot" in w else -1.0
		_ok("%s suppresses at %.1f" % [name, float(want[name])],
				is_equal_approx(got, float(want[name])), "got %.2f" % got)
		w.free()


# ─────────────────────────────────────────────
func _test_a_failing_link_slows_the_player() -> void:
	var p := _spawn(PLAYER)
	await process_frame
	var clean: float = p._signal_move_scale()
	_ok("a clean link costs no speed", is_equal_approx(clean, 1.0),
			"%.2f" % clean)

	# SAMPLED FROM THE CONSTANTS, NOT FROM FOUR NUMBERS I TYPED.
	#
	# This read [0.6, 0.4, 0.2, 0.0] and asserted the first was FUZZED. The
	# thresholds were then retuned — FUZZED 0.75 -> 0.85, DEGRADED 0.50 ->
	# 0.62 — and 0.60 moved into the band below, so the test failed over a
	# change that was entirely correct. The same mistake the recovery-rate
	# check above avoids by reading signal_recovery_rate off the body.
	#
	# A point in the middle of each band, derived, so retuning the ladder
	# cannot break this and a band that is accidentally made EMPTY will.
	var mid := func(hi: float, lo: float) -> float: return (hi + lo) * 0.5
	var samples := [
		mid.call(AI.SIGNAL_FUZZED, AI.SIGNAL_DEGRADED),
		mid.call(AI.SIGNAL_DEGRADED, AI.SIGNAL_CRITICAL),
		mid.call(AI.SIGNAL_CRITICAL, AI.SIGNAL_EKILL),
		0.0,
	]
	var seen: Array = []
	for level: float in samples:
		p.signal_integrity = level
		p._update_ekill_latch()
		seen.append(p._signal_move_scale())
	_ok("...FUZZED is still full speed", is_equal_approx(float(seen[0]), 1.0),
			"%.2f at integrity %.2f" % [float(seen[0]), float(samples[0])])
	# Monotonic: each band must be slower than the one above it, or the squeeze
	# does not build and a player cannot read it coming.
	var falling := true
	for i in range(1, seen.size()):
		if float(seen[i]) > float(seen[i - 1]):
			falling = false
	_ok("...and it gets slower every band down", falling,
			"%s" % str(seen))
	_ok("...e-killed is a serious slow", float(seen[3]) <= 0.4,
			"%.2f" % float(seen[3]))
	# ...but never a freeze. Being motionless and blind while something shoots
	# you is a cutscene, not a fight.
	_ok("...but never a stop", float(seen[3]) > 0.0)
	await _drop(p)


func _test_the_player_is_in_its_own_group() -> void:
	# mission_briefing, tutorial_toast and weapon_bar all find the player with
	# get_first_node_in_group("player"), and nothing ever put it there.
	var p := _spawn(PLAYER)
	await process_frame
	_ok("the player is in the \"player\" group", p.is_in_group("player"))
	_ok("...and is what get_first_node_in_group returns",
			root.get_tree().get_first_node_in_group("player") == p)
	await _drop(p)


# ─────────────────────────────────────────────
func _test_a_hit_suppresses_harder_than_a_miss() -> void:
	# A round that CONNECTS is worth AIWeapon.HIT_SUPPRESSION times one that
	# went past. Two hostiles inside the same sphere, one of them named as the
	# struck body, so the comparison is between them on the same call — a
	# before/after on one body would also pass if the multiplier applied to
	# everybody, which is the mistake worth catching.
	var hit_me := _spawn(SOLDIER, Vector3.ZERO)
	hit_me.faction = Enums.Factions.ENEMY
	var beside_me := _spawn(SOLDIER, Vector3(1.0, 0, 0))
	beside_me.faction = Enums.Factions.ENEMY
	await process_frame
	await physics_frame

	AIWeapon.suppress_along(root.get_tree(), Vector3(0.5, 0.5, -4.0), Vector3(0.5, 0.5, 4.0),
			2.5, 0.04, null, Enums.Factions.ALLIED, hit_me)
	var on_hit: float = 1.0 - hit_me.signal_integrity
	var on_near: float = 1.0 - beside_me.signal_integrity

	_ok("the near miss took the flat dose", absf(on_near - 0.04) < 0.001,
			"%.4f" % on_near)
	_ok("...and the body it hit took %.1fx that" % AIWeapon.HIT_SUPPRESSION,
			absf(on_hit - 0.04 * AIWeapon.HIT_SUPPRESSION) < 0.001,
			"%.4f, expected %.4f" % [on_hit, 0.04 * AIWeapon.HIT_SUPPRESSION])
	_ok("...so a hit really is worse than a miss", on_hit > on_near)

	# With nothing named as struck, everyone takes the flat dose.
	var a := _spawn(SOLDIER, Vector3(0, 0, 40.0))
	a.faction = Enums.Factions.ENEMY
	await process_frame
	await physics_frame
	AIWeapon.suppress_along(root.get_tree(), Vector3(0, 0.5, 36.0), Vector3(0, 0.5, 44.0),
			2.5, 0.04, null, Enums.Factions.ALLIED, null)
	_ok("...and a shot that hit nothing gives nobody the bonus",
			absf((1.0 - a.signal_integrity) - 0.04) < 0.001,
			"%.4f" % (1.0 - a.signal_integrity))

	await _drop(a)
	await _drop(beside_me)
	await _drop(hit_me)


# ─────────────────────────────────────────────
func _test_a_round_going_past_suppresses() -> void:
	# THE BUG THIS WHOLE SEGMENT TEST EXISTS FOR, kept as a regression.
	#
	# Reported from play: "enemies were shooting pretty close to me but I
	# didn't get any suppression at all." The pass used to drop its sphere at
	# the round's IMPACT, so a shot that missed by half a metre and carried on
	# to bury itself thirty metres away suppressed nothing — the nearer the
	# miss, the more reliably it cost the shooter nothing.
	var target := _spawn(SOLDIER, Vector3.ZERO)
	target.faction = Enums.Factions.ENEMY
	await process_frame

	# Muzzle 20 m one side, impact 30 m the other, passing 0.5 m from the
	# target. Nothing is within 2.5 m of EITHER endpoint.
	var muzzle := Vector3(0.5, 0, -20.0)
	var impact := Vector3(0.5, 0, 30.0)
	_ok("the test geometry really does miss both ends",
			muzzle.distance_to(Vector3.ZERO) > 2.5 and impact.distance_to(Vector3.ZERO) > 2.5)

	AIWeapon.suppress_along(root.get_tree(), muzzle, impact, 2.5, 0.05,
			null, Enums.Factions.ALLIED)
	_ok("a round passing close suppresses, even landing far away",
			target.signal_integrity < 1.0,
			"%.3f" % target.signal_integrity)

	# ...and one down a parallel lane well wide of it does not.
	target.signal_integrity = 1.0
	AIWeapon.suppress_along(root.get_tree(), Vector3(9.0, 0, -20.0),
			Vector3(9.0, 0, 30.0), 2.5, 0.05, null, Enums.Factions.ALLIED)
	_ok("...but a round down a lane 9 m wide of it does not",
			is_equal_approx(target.signal_integrity, 1.0),
			"%.3f" % target.signal_integrity)

	# A round that STOPPED short must not reach past its own impact — the
	# clamp on t is what stops a short round suppressing from behind.
	target.signal_integrity = 1.0
	AIWeapon.suppress_along(root.get_tree(), Vector3(0.5, 0, -20.0),
			Vector3(0.5, 0, -10.0), 2.5, 0.05, null, Enums.Factions.ALLIED)
	_ok("...and a round that stopped 10 m short reaches nobody",
			is_equal_approx(target.signal_integrity, 1.0),
			"%.3f" % target.signal_integrity)

	await _drop(target)


# ─────────────────────────────────────────────
const EXPLOSION := "res://Character/weapon/explosion.tscn"


func _test_explosions_rattle_the_link() -> void:
	# Three hostiles at increasing range from one blast, so falloff is checked
	# as an ordering rather than against magic numbers that move when the
	# values are tuned.
	var near := _spawn(SOLDIER, Vector3(0, 0, 1.0))
	var mid := _spawn(SOLDIER, Vector3(0, 0, 4.0))
	var far := _spawn(SOLDIER, Vector3(0, 0, 7.0))
	var away := _spawn(SOLDIER, Vector3(0, 0, 40.0))
	for b in [near, mid, far, away]:
		b.faction = Enums.Factions.ENEMY
	await process_frame

	var blast: Node = load(EXPLOSION).instantiate()
	blast.source_faction = Enums.Factions.ALLIED
	root.add_child(blast)
	(blast as Node3D).global_position = Vector3.ZERO
	# _pulse_signal is deferred from _ready, same as EmpBlast.
	await process_frame
	await process_frame

	_ok("a blast costs signal", near.signal_integrity < 1.0,
			"%.3f" % near.signal_integrity)
	_ok("...and falls off with range",
			near.signal_integrity < mid.signal_integrity
			and mid.signal_integrity < far.signal_integrity,
			"%.3f / %.3f / %.3f" % [near.signal_integrity, mid.signal_integrity, far.signal_integrity])
	_ok("...and reaches nobody past signal_radius",
			is_equal_approx(away.signal_integrity, 1.0),
			"%.3f at 40 m" % away.signal_integrity)
	# THE LINE BETWEEN A FRAG AND AN EMP. Ordinary ordnance must not do the
	# EMP's job, or there is no reason to carry one.
	_ok("...but does not e-kill even at the centre",
			near.get_signal_state() != AI.SignalState.EKILL,
			"state=%d at %.3f" % [near.get_signal_state(), near.signal_integrity])
	_ok("...and does not lock recovery, which is the EMP's trick",
			not near.signal_locked())

	if is_instance_valid(blast):
		blast.free()
	for b in [near, mid, far, away]:
		await _drop(b)


func _test_a_blast_is_softer_on_your_own_side() -> void:
	var foe := _spawn(SOLDIER, Vector3(0, 0, 1.0))
	foe.faction = Enums.Factions.ENEMY
	var mate := _spawn(SOLDIER, Vector3(1.0, 0, 0))
	mate.faction = Enums.Factions.ALLIED
	await process_frame

	var blast: Node = load(EXPLOSION).instantiate()
	blast.source_faction = Enums.Factions.ALLIED
	root.add_child(blast)
	(blast as Node3D).global_position = Vector3.ZERO
	await process_frame
	await process_frame

	_ok("your own blast still rattles your own squad", mate.signal_integrity < 1.0,
			"%.3f" % mate.signal_integrity)
	_ok("...but less than it rattles theirs",
			mate.signal_integrity > foe.signal_integrity,
			"mate %.3f vs foe %.3f" % [mate.signal_integrity, foe.signal_integrity])

	if is_instance_valid(blast):
		blast.free()
	await _drop(mate)
	await _drop(foe)


# ─────────────────────────────────────────────
const TRACER := "res://Character/weapon/tracer.tscn"


func _test_tracers_are_coloured_by_side() -> void:
	# ALLIES AND THE PLAYER YELLOW, ENEMIES RED. Pinned because the mapping
	# runs through Enums.are_hostile, which is shared with damage and targeting
	# — a change there that was correct for who-can-shoot-whom could silently
	# invert who-looks-like-what, and nothing on screen would say so.
	var seen: Dictionary = {}
	for f in [Enums.Factions.PLAYER, Enums.Factions.ALLIED,
			Enums.Factions.ENEMY, Enums.Factions.NEUTRAL]:
		var t: Node = load(TRACER).instantiate()
		root.add_child(t)
		t.set_side(f)
		var mesh := t.get_node_or_null("MeshInstance3D") as MeshInstance3D
		var m := mesh.material_override as ShaderMaterial
		seen[f] = Color(m.get_shader_parameter("body_color"))
		t.free()
	await process_frame

	_ok("the player's rounds are yellow",
			seen[Enums.Factions.PLAYER].is_equal_approx(Tracer.FRIENDLY_BODY))
	_ok("...and an ally's are the same yellow",
			seen[Enums.Factions.ALLIED].is_equal_approx(Tracer.FRIENDLY_BODY))
	_ok("...and the enemy's are red",
			seen[Enums.Factions.ENEMY].is_equal_approx(Tracer.HOSTILE_BODY))
	_ok("...and the two are not the same colour",
			not seen[Enums.Factions.PLAYER].is_equal_approx(seen[Enums.Factions.ENEMY]))
	# Far enough apart in HUE, not merely in brightness — two shades of one hue
	# collapse to the same value under the signal filter's chroma quantiser.
	var fy: Color = Tracer.FRIENDLY_BODY
	var hr: Color = Tracer.HOSTILE_BODY
	_ok("...and separated by hue, which is what survives the filter",
			absf(fy.h - hr.h) > 0.06,
			"hue %.3f vs %.3f" % [fy.h, hr.h])
	# One material per side, handed out by reference. Tracer materials are a
	# sub-resource shared by every instance, so a per-tracer duplicate would
	# allocate a ShaderMaterial on every bullet fired.
	var a: Node = load(TRACER).instantiate()
	var b: Node = load(TRACER).instantiate()
	root.add_child(a)
	root.add_child(b)
	a.set_side(Enums.Factions.ENEMY)
	b.set_side(Enums.Factions.ENEMY)
	var ma = (a.get_node("MeshInstance3D") as MeshInstance3D).material_override
	var mb = (b.get_node("MeshInstance3D") as MeshInstance3D).material_override
	_ok("two rounds from the same side share one material", ma == mb)
	a.free()
	b.free()
	await process_frame
