extends Node3D
class_name SiteHeat

# ─────────────────────────────────────────────
# SITE HEAT — the in-mission commander.
#
# The enemy stops being `spawn X at Y with posture Z` and becomes a SUPPLY
# BUDGET committed over the course of a mission, in response to which cores are
# still theirs, what the player is doing, and how long it has gone on.
# docs/briefs/CAMPAIGN_REWORK.md §12.4 and Appendix C.
#
# TWO SOURCES, and they do different jobs:
#
#   CORES — every core still theirs emits. The main term, and the one the
#   PLAYER CONTROLS: clearing cores is how you turn the pressure down. This is
#   what makes the win condition causal (§12.7) rather than a checklist.
#
#   INCURSION — a slower term that rises with time on the map and never falls.
#   This is the answer to standing at 300 m with a mortar: patience is allowed,
#   it is just not free, and it cannot be made free by standing far away.
#
# AND IT SPENDS FROM A FINITE POOL. The site's `resistance` — total enemy
# supply, not squad count — is the budget. Heat is the RATE at which it is
# committed, not a tap that runs forever, so a site can be ground down and
# patience stays viable. Without that this is a timer that eventually kills
# everyone.
#
# WHAT IT BUYS COMES TO YOU. Reinforcements ADVANCE on the player, not on a
# post. That is the whole anti-range answer and it needs no special case: stand
# off at 300 m and what heat buys walks to 300 m and finds you.
#
# NO _process. _physics_process, and it stops itself the moment the pool is
# spent.
# ─────────────────────────────────────────────

signal pressure_changed(state: int)
signal committed(supply: int, at: Vector3)
signal pool_spent()

enum Pressure { QUIET, BUILDING, COMMITTED, SPENT }

## Total enemy supply available to this site across the whole operation. The
## location's `resistance` (§2) — supply, because five Walkers and two
## riflemen are both "one squad" and are not remotely the same problem.
## AN ASSAULT, RATHER THAN A SLOW BUILD (Phase 5).
##
## 0 is the attack behaviour below: pressure rises from cores the player has
## not taken, and the player turns it off by taking them.
##
## Above 0 this is a DEFENCE, and the whole model inverts. The attacker has
## already committed — there is nothing to build up to — so the pool drains
## over this many seconds and the readout becomes a clock the defender can
## watch run down.
##
## IT HAS TO BE SET OR A DEFENCE NEVER ENDS. _rate() sums heat from HOSTILE
## cores, and on a defence the player holds all of them, so that term is zero
## and only the incursion trickle is left: 0.25/s against a commit threshold of
## 40 spends four supply every 160 seconds, which is about an hour for a
## typical pool. Watched: every attacker was dead at three minutes and the
## operation was still running six minutes later.
@export var assault_seconds: float = 0.0

@export var resistance: int = 24

## Heat a hostile core emits per second, scaled by its size tier.
@export var core_heat: Array[float] = [0.6, 1.0, 1.6]
## Heat per second from simply being here, which never falls.
@export var incursion_heat: float = 0.25
## How long the incursion term takes to reach full, in seconds.
@export var incursion_ramp: float = 300.0

## Heat needed before anything is committed, and how much supply one commitment
## spends. Bigger packets later: an early response is a pair, a late one is
## something with a chassis.
@export var commit_threshold: float = 40.0
@export var packet_supply: int = 4

## Wired by whoever fits this. Without it there is nothing to read cores off.
@export var operation: Node3D

var heat: float = 0.0
var spent: int = 0
var elapsed: float = 0.0
var _pressure: int = Pressure.QUIET
var _player: Node3D = null


func _ready() -> void:
	_player = _find_player()
	if operation == null:
		push_warning("SiteHeat '%s': no SiteOperation wired, so it cannot see which cores are hostile and only the incursion term will run." % name)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if spent >= resistance:
		_set_pressure(Pressure.SPENT)
		set_physics_process(false)
		pool_spent.emit()
		return

	elapsed += delta
	heat += _rate() * delta
	_read_pressure()

	if heat < commit_threshold:
		return
	heat -= commit_threshold
	_commit()


## Cores plus incursion. The cores term is the one the player can turn off.
func _rate() -> float:
	# A DEFENCE DRAINS ON A CLOCK. The pool is the assault and it is already
	# committed, so it empties over assault_seconds regardless of who holds
	# what. Worked from the other two numbers so changing either keeps the
	# window honest: spending the whole pool takes
	# (resistance / packet_supply) commits, each needing commit_threshold heat.
	if assault_seconds > 0.0:
		var commits: float = float(resistance) / maxf(float(packet_supply), 1.0)
		return (commits * commit_threshold) / assault_seconds
	var r: float = 0.0
	if operation != null and is_instance_valid(operation) and "cores" in operation:
		for c in operation.cores:
			if c == null or not is_instance_valid(c):
				continue
			if c.is_held_by_player():
				continue
			var tier: int = clampi(int(c.size_tier), 0, core_heat.size() - 1)
			r += core_heat[tier]
	# Ramps in rather than applying from the first second, so the opening of a
	# mission is not already under pressure before anything has happened.
	r += incursion_heat * clampf(elapsed / maxf(incursion_ramp, 0.1), 0.0, 1.0)
	return r


## Spend a packet of the pool. The packet is capped by what is left, so the
## last commitment of a ground-down site is whatever it could still afford.
func _commit() -> void:
	var packet: int = mini(packet_supply, resistance - spent)
	if packet <= 0:
		return   # the pool is gone; the SPENT branch above will catch it next tick
	spent += packet
	# AT THE PLAYER. Not at a post — this is the whole answer to standing off
	# at range, and it needs no rule of its own.
	var at: Vector3 = _player.global_position if _player != null and is_instance_valid(_player) else global_position
	committed.emit(packet, at)


func remaining() -> int:
	return maxi(0, resistance - spent)


## A coarse read, deliberately. The player should be able to tell that
## something is coming without being handed a number — and SPENT matters most,
## because knowing their reserve is gone is what says the site is yours.
func _read_pressure() -> void:
	var left: float = float(remaining()) / maxf(float(resistance), 1.0)
	if left <= 0.0:
		_set_pressure(Pressure.SPENT)
	elif spent > 0:
		_set_pressure(Pressure.COMMITTED)
	elif heat > commit_threshold * 0.5:
		_set_pressure(Pressure.BUILDING)
	else:
		_set_pressure(Pressure.QUIET)


func _set_pressure(p: int) -> void:
	if _pressure == p:
		return
	_pressure = p
	pressure_changed.emit(p)


func pressure() -> int:
	return _pressure


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0]
	var node: Node = self
	while node != null:
		if node is World:
			return (node as World).player
		node = node.get_parent()
	return null
