extends CharacterBody3D
class_name AI

# ─────────────────────────────────────────────
# THE BASE EVERY ROBOT SHARES, PLAYER INCLUDED.
#
# This was an eight-line stub, and that was the bug. Enemy carried the whole
# signal system and Player extends AI directly, not Enemy — so the player had
# no signal_integrity at all. Both existing sources of signal damage gate on
# finding it:
#
#   ai_weapon._apply_near_miss_suppression   if "signal_integrity" in body
#   emp_blast                                if not n.has_method("receive_signal_damage")
#
# Neither matched the player, so near-miss suppression and EMP have never done
# anything to you. The fix is this file rather than a second copy on Player:
# the two call sites above are already correct, and the moment the property
# exists on the shared base they start working on the player for free.
#
# WHAT LIVES HERE is the state and the arithmetic — the number, what takes it
# down, what brings it back, and which band it is in. WHAT STAYS ON ENEMY is
# everything that is robot BEHAVIOUR: the cull thaw, the analytics credit, the
# movement stutter, the arcs coming off the chassis, the e-kill broadcast.
# Enemy overrides the three hooks at the bottom to add those back.
# ─────────────────────────────────────────────

# ── SIGNAL INTEGRITY ──────────────────────────
# The health of this robot's networked systems.
# Degraded by suppressing fire, EMP, jamming. Recovers passively.
enum SignalState { CLEAN, FUZZED, DEGRADED, CRITICAL, EKILL }
# RAISED 2026-10-09, all four. The old floor was 0.01, which meant an e-kill
# wanted the link essentially at zero -- and with passive recovery running the
# whole time you bounced off it instead of landing on it. The most interesting
# state in the system was the one that almost never happened.
#
# GLOBAL, NOT JUST THE PLAYER. Every robot reads these, so enemies are now
# easier to suppress and to EMP by the same amount. That is the intent -- the
# player is an AI on the same rules -- but it is a real balance change and
# jamming is now a much stronger tool for both sides.
#
# Previous: 0.75 / 0.50 / 0.25 / 0.01
const SIGNAL_FUZZED: float   = 0.85  # below here: accuracy penalty kicks in
const SIGNAL_DEGRADED: float = 0.62  # below here: sensors halved, movement stutters
const SIGNAL_CRITICAL: float = 0.38  # below here: ignores squad orders, erratic
const SIGNAL_EKILL: float    = 0.12  # below here: fully disabled
## ...and it STAYS disabled until signal has climbed back to here. The same
## shape as revive_at_fraction on a downed robot: going out takes one threshold,
## coming back takes another. Without it an e-kill was a flinch — recovery is
## 0.08/s, so a robot knocked to zero ticked back over 0.01 in an eighth of a
## second once its lock ran out and was fighting again. Now it is out for about
## six seconds after the lock, and it comes back at the top of DEGRADED — in
## practice FUZZED, since release is the first frame at or over 0.50 and
## DEGRADED ends at exactly 0.50 — then climbs to CLEAN the ordinary way.
const SIGNAL_EKILL_RECOVER: float = 0.50

@export var signal_integrity: float = 1.0
## Per second, passive recovery. HALVED from 0.08: suppression was arriving
## faster than it mattered — a robot shrugged a burst off in a couple of
## seconds, so pinning anything took continuous fire from several guns and
## suppression never felt like a thing you could DO. At 0.04 a full recovery
## from the floor takes 25 seconds, which is long enough for the squad to
## exploit it.
##
## Nothing overrides this in a scene — checked — so changing it here really is
## global, for every robot and the player alike.
@export var signal_recovery_rate: float = 0.04
@export var signal_resistance: float = 1.0       # damage multiplier. >1 = more resistant

## A hardening field somebody else is holding over this robot, as a STAMP
## rather than a mutation: whoever projects it writes it every tick with an
## expiry, and nothing ever has to take it off. The Bastion is the first
## projector (bastion.gd).
##
## WHY NOT MUTATE signal_resistance. It is a plain export with no stack and no
## timer, so multiply-on-entry / divide-on-exit means: two overlapping
## projectors double it and only one divides back; a projector that dies
## mid-effect never divides back at all; and a projector frozen by the distance
## cull has its _physics_process switched off (ai_manager.gd:576-593), so it
## cannot run an exit path even in principle. Every one of those leaves a robot
## PERMANENTLY hardened, in silence, which is the expensive kind of bug.
##
## WHY NOT "RECOMPUTE FROM SCRATCH EACH TICK" EITHER, which is where
## docs/frames/BASTION.md §6.1 stops: the recompute would have to run on the
## RECEIVER, and a culled receiver's tick is off too, so it would keep whatever
## it was last given forever. An expiry is the only version that is correct
## when EITHER end is frozen.
var _hardening_bonus: float = 0.0
var _hardening_until: float = 0.0


## MAX, NOT SUM: two Bastions are not twice as good as one. The ceiling
## argument in docs/frames/BASTION.md §4 — "anything near 3.0 would make a
## Bastion squad effectively immune to suppression, which is not a fight, it is
## a wall" — is unenforceable under a sum.
func add_hardening(bonus: float, seconds: float) -> void:
	var now: float = float(Time.get_ticks_msec()) * 0.001
	if now > _hardening_until:
		_hardening_bonus = 0.0        # the old stamp had already lapsed
	_hardening_bonus = maxf(_hardening_bonus, bonus)
	_hardening_until = maxf(_hardening_until, now + seconds)


## What the two signal paths below divide by. ADDITIVE, not multiplicative:
## the three other things that touch signal_resistance — enemy_loadouts.gd:431,
## squad_spawner.gd:355 and squad_page.gd's readout — all ADD module bonuses
## into it at spawn, so a multiplier here would compose wrongly with them.
##
## Everything else in the project keeps reading signal_resistance directly,
## which is still the robot's own permanent figure.
func effective_signal_resistance() -> float:
	if float(Time.get_ticks_msec()) * 0.001 > _hardening_until:
		return signal_resistance
	return signal_resistance + _hardening_bonus

# Seconds of blocked signal recovery left. See lock_signal().
var _signal_locked_t: float = 0.0
# Set on the way down through SIGNAL_EKILL, cleared only on the way back up
# through SIGNAL_EKILL_RECOVER. See _update_ekill_latch.
var _ekill_latched: bool = false


## Everything with a signal_integrity, in one group — robots and the player.
##
## EMP used to sweep "enemies", which the player is not in, so a blast at your
## own feet did nothing to you however close it landed. Near-miss suppression
## never had the problem because it is a physics query, not a group lookup.
## Joining here rather than in each subclass means nothing can be given a
## signal and left out of the sweep.
const SIGNAL_GROUP := "signal"


func _ready() -> void:
	add_to_group(SIGNAL_GROUP)
	initialize()

func initialize():
	pass


# ─────────────────────────────────────────────
# SIGNAL INTEGRITY
# ─────────────────────────────────────────────
func get_signal_state() -> SignalState:
	# Latched OR at the floor: the second covers a frame where signal was set
	# directly and the latch has not been updated yet.
	if _ekill_latched or signal_integrity <= SIGNAL_EKILL:
		return SignalState.EKILL
	elif signal_integrity <= SIGNAL_CRITICAL:
		return SignalState.CRITICAL
	elif signal_integrity <= SIGNAL_DEGRADED:
		return SignalState.DEGRADED
	elif signal_integrity <= SIGNAL_FUZZED:
		return SignalState.FUZZED
	return SignalState.CLEAN


## Called by near-miss suppression, EMP grenades, jamming, etc.
##
## `source` is whoever did it. What is done with that is a subclass's business —
## Enemy credits it so an e-kill can be attributed; the player has nobody to
## report to and ignores it.
func receive_signal_damage(amount: float, source: Node = null) -> void:
	# effective_, not the raw export: a Bastion's canopy is a stamp with an
	# expiry on top of the robot's own figure. See effective_signal_resistance.
	var actual: float = amount / maxf(effective_signal_resistance(), 0.01)
	var before: float = signal_integrity
	signal_integrity = maxf(0.0, signal_integrity - actual)
	_on_signal_damaged(before, signal_integrity, source)
	_update_ekill_latch()
	if signal_integrity <= SIGNAL_EKILL:
		_enter_ekill()


## Hold signal where it is for `seconds` — no passive recovery.
##
## What turns an EMP from a flicker into a stun. E-KILL is a threshold at 0.01
## and recovery is 0.08/s, so a robot knocked flat to zero climbed back out of
## E-KILL in about an eighth of a second: it twitched and carried on. Locked, it
## stays down for the duration, then climbs back through CRITICAL, DEGRADED and
## FUZZED the ordinary way — so the whole disruption lasts several seconds and
## tapers rather than switching off.
##
## Divided by signal_resistance, the same as the damage itself: a Hardened
## Uplink shortens the lock as well as softening the hit.
func lock_signal(seconds: float) -> void:
	# effective_, as above: standing in a Bastion's canopy shortens the lock as
	# well as softening the hit.
	_signal_locked_t = maxf(_signal_locked_t, seconds / maxf(effective_signal_resistance(), 0.01))


# In at SIGNAL_EKILL, out only at SIGNAL_EKILL_RECOVER. Updated where signal
# goes down (receive_signal_damage) and where it comes back (tick_signal),
# rather than inside get_signal_state(), which half the game calls every frame
# and which should not have side effects.
func _update_ekill_latch() -> void:
	if signal_integrity <= SIGNAL_EKILL:
		_ekill_latched = true
	elif _ekill_latched and signal_integrity >= SIGNAL_EKILL_RECOVER:
		_ekill_latched = false


## The lock countdown and the passive climb back. Every subclass with a signal
## has to call this each physics frame or its signal never recovers.
func tick_signal(delta: float) -> void:
	if _signal_locked_t > 0.0:
		_signal_locked_t = maxf(0.0, _signal_locked_t - delta)
	elif signal_integrity < 1.0:
		signal_integrity = minf(1.0, signal_integrity + signal_recovery_rate * delta)
	_update_ekill_latch()


## True while something is holding signal down, so recovery is not running.
func signal_locked() -> bool:
	return _signal_locked_t > 0.0


# ── HOOKS ─────────────────────────────────────
# Overridden by Enemy to add the things that are robot behaviour rather than
# signal arithmetic. Base versions do nothing on purpose: the player needs the
# number without the chassis arcs or the analytics credit.

## Signal just went down. Enemy credits the source and lets Soldier enter
## SUPPRESSED from here.
func _on_signal_damaged(_before: float, _after: float, _source: Node) -> void:
	pass

## Crossed into E-KILL. Enemy stops the body dead; the player overrides nothing
## and simply watches the feed collapse.
func _enter_ekill() -> void:
	pass
