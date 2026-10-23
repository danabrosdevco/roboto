extends Node3D
class_name SiteOperation

# ─────────────────────────────────────────────
# SITE OPERATION — what it takes to win a map, and what it takes to lose one.
#
# The mission-level spine of the campaign rework's in-mission half. It knows
# every HoldableCore on the map and the bunker, and it is the only thing that
# decides the operation is over. docs/briefs/CAMPAIGN_REWORK.md §12.7.
#
# THE WIN IS CAUSAL, NOT A CHECKLIST, and this is the part worth reading:
#
#   Taking the bunker starts a STAND-DOWN — the time it takes to open the way
#   down into the network. You do not have to clear the cores first. But every
#   core still in their hands feeds the counter-attack on the bunker, so a
#   stand-down begun with three cores still theirs is one you hold a doorway
#   through against everything three cores can produce.
#
# So the order is the player's and both readings are legible: clear first and
# walk into a quiet stand-down, or rush the bunker and survive the one you
# asked for. Nothing is gated. The consequence does the work.
#
# AND THERE IS NO WITHDRAWAL. The bunker is not an exit you can take early.
# Losing is losing: the frame and kit the player was wearing are gone and some
# of the squad does not come back. It is not death — the player is a process,
# never authorised and on no roster, and a chassis is hardware it was running
# on. There is nothing in the premise that dies.
#
# NO _process. _physics_process runs only during a stand-down.
# ─────────────────────────────────────────────

const _Point := preload("res://Env/world_objects/holdable_core.gd")

signal stand_down_started()
signal stand_down_progress(fraction: float)
signal stand_down_interrupted()
signal operation_complete()
signal operation_failed(reason: String)

## The way down. Found by name under the level if not wired.
@export var bunker: Node3D
## How long the way down takes to open, in seconds, once the bunker is held.
## The one number that decides whether rushing it is a real option.
@export var stand_down_seconds: float = 45.0
## Progress is kept when the bunker is lost and retaken, rather than reset to
## zero. Losing it is punishing enough through what is happening at the time;
## wiping the bar as well turns a setback into a restart.
@export var keep_progress_on_loss: bool = true
## Where to look for cores. Set it BEFORE this node is parented — _ready runs
## the walk, so a value assigned afterwards is read by nothing.
##
## Unset, it falls back to `current_scene`, which is null in anything that
## instantiates a level by hand rather than changing to it — every probe and
## every test. Then it would walk from its own parent and find nothing, which
## is exactly as silent as it sounds.
@export var search_root: Node

var cores: Array = []
var _t: float = 0.0
var _running: bool = false
var _settled: bool = false


func _ready() -> void:
	set_physics_process(false)
	_collect_cores()
	_watch_player()
	if defence:
		# A DEFENCE IGNORES THE BUNKER. It is won by outlasting the attacker's
		# pool and lost by losing the ground — see _defence_tick.
		if heat != null and heat.has_signal(&"pool_spent"):
			heat.pool_spent.connect(_on_pool_spent)
		else:
			push_warning("SiteOperation '%s': a defence with no SiteHeat wired has no pool to outlast, so it can only be lost." % name)
		set_physics_process(true)
		return
	if bunker == null:
		push_warning("SiteOperation '%s': no bunker wired, so this operation has no win condition and can only be lost." % name)
		return
	if bunker.has_signal(&"holder_changed"):
		bunker.holder_changed.connect(_on_bunker_changed)

## Every HoldableCore under the level, the bunker included — it is one too.
## Walked rather than wired so a map can gain a core without anybody
## remembering to list it here.
func _collect_cores() -> void:
	cores.clear()
	var from: Node = search_root
	if from == null:
		from = get_tree().current_scene
	if from == null:
		# Last resort: the topmost ancestor, which in a hand-instantiated level
		# is the level itself.
		from = self
		while from.get_parent() != null and from.get_parent() != get_tree().root:
			from = from.get_parent()
	_walk(from)
	if cores.is_empty():
		push_warning("SiteOperation '%s': no capture points found, so nothing on this map can change hands." % name)


func _walk(n: Node) -> void:
	if n == null:
		return
	if n.get_script() == _Point and n != bunker:
		cores.append(n)
	for c in n.get_children():
		_walk(c)


## How many cores are still theirs. The number heat reads — every one of these
## is pressure arriving at the bunker.
func hostile_cores() -> int:
	var n := 0
	for c in cores:
		if c != null and is_instance_valid(c) and not c.is_held_by_player():
			n += 1
	return n


func held_cores() -> int:
	return cores.size() - hostile_cores()


# ── The stand-down ───────────────────────────────────────────────────────────

func _on_bunker_changed(_holder) -> void:
	if _settled:
		return   # the operation is already over; nothing left to start or stop
	if bunker.is_held_by_player():
		_start_stand_down()
	else:
		_interrupt_stand_down()


func _start_stand_down() -> void:
	if _running:
		return
	_running = true
	if not keep_progress_on_loss:
		_t = 0.0
	set_physics_process(true)
	stand_down_started.emit()


func _interrupt_stand_down() -> void:
	if not _running:
		return
	_running = false
	if not keep_progress_on_loss:
		_t = 0.0
	set_physics_process(false)
	stand_down_interrupted.emit()


func _physics_process(delta: float) -> void:
	if defence:
		_defence_tick(delta)
		return
	if not _running:
		set_physics_process(false)
		return
	_t += delta
	stand_down_progress.emit(clampf(_t / maxf(stand_down_seconds, 0.1), 0.0, 1.0))
	if _t >= stand_down_seconds:
		_succeed()


func stand_down_fraction() -> float:
	return clampf(_t / maxf(stand_down_seconds, 0.1), 0.0, 1.0)


func is_standing_down() -> bool:
	return _running


# ── Ending it ────────────────────────────────────────────────────────────────

func _succeed() -> void:
	if _settled:
		return
	_settled = true
	_running = false
	set_physics_process(false)
	operation_complete.emit()


## The failstate the game has never had. Wired to the player rather than to the
## squad: losing Bravo is expensive and survivable, losing the body you were
## running on ends the operation.
func _watch_player() -> void:
	var p := _find_player()
	if p == null:
		push_warning("SiteOperation '%s': no player found, so the operation cannot be failed and can only be won." % name)
		return
	# STRING FORM, not `p.died.connect`. Property access on a signal only works
	# for one declared with `signal`; a signal added at runtime with
	# add_user_signal has no property, so the dot form raises "Invalid access to
	# property or key" and the operation silently cannot be failed. The string
	# form works for both, which also makes this testable with a stand-in.
	if p.has_signal(&"died"):
		p.connect("died", _on_player_died)


func _on_player_died(_where = null) -> void:
	fail("FRAME LOST")


func fail(reason: String) -> void:
	if _settled:
		return
	_settled = true
	_running = false
	set_physics_process(false)
	operation_failed.emit(reason)


## The same lookup interact_objective.gd uses, including the walk up to World,
## because the group is not populated in every scene this runs in.
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

# ── A DEFENCE ENDS DIFFERENTLY ───────────────────────────────────────────────
#
# An attack is won at the bunker: take the ground, stand down, go home. A
# defence has no bunker to take — you already hold everything — so the first
# cut of it had NO WIN CONDITION AT ALL and ran until somebody closed the
# window. Watched for fifteen minutes: the garrison killed every attacker by
# the five-minute mark, and then heat quietly refilled the field and it started
# again, forever.
#
# So a defence ends the way the thing it is made of ends: THE ATTACKER RUNS OUT.
# SiteHeat already spends from a finite pool — that pool IS the assault — so
# when it is spent and the field is clear, you have held. No timer, no new
# concept, and the pressure readout the player is already watching becomes the
# thing that tells them how much longer.

## Which kind of operation this is. A defence wins by outlasting the attacker's
## supply; an attack wins at the bunker.
@export var defence: bool = false

## The attacker's supply, on a defence. Its pool emptying is half the win.
@export var heat: Node3D

## How long the field has to stay clear after the pool is spent. Stops a win
## firing in the gap between one squad dying and the next walking in.
@export var clear_seconds: float = 8.0

var _pool_spent: bool = false
var _clear_t: float = 0.0
## A defence does not start judging until the player has actually held
## something — see _defence_tick.
var _armed: bool = false


## THE DEFENCE LOOP. Deliberately not in _physics_process with the stand-down:
## the two win conditions have nothing to do with each other and sharing a
## timer variable between them is how one starts counting during the other.
func _defence_tick(delta: float) -> void:
	if _settled:
		return
	# ARMED ONLY ONCE THE GROUND IS ACTUALLY YOURS.
	#
	# A HoldableCore defaults to HOSTILE, and the operation exists before
	# anything has called start_held() on them — so on the very first frame
	# "they hold everything" is TRUE and the defence failed before it began.
	# _settled was then set and neither the win nor a real loss could ever fire
	# afterwards. Caught by the suite; in the slice it was hidden only because
	# nothing happens to run a physics frame between the two calls.
	if not _armed:
		if held_cores() > 0:
			_armed = true
		return
	# LOSING: THEY HAVE TO TAKE EVERYTHING.
	#
	# Every point on the map — the cores AND the bunker — back in their hands.
	# `cores` is every HoldableCore under the level and the bunker is one of
	# them (see _collect_cores), so this is "all of it" rather than "the cores".
	# Holding one post means the site is still yours and the assault has not
	# succeeded, which is what makes a last stand a real thing rather than a
	# formality.
	#
	# Reachable without any new mechanic, because a held core goes back to them
	# when its anchor is shot off.
	if not cores.is_empty() and held_cores() == 0:
		fail("GROUND LOST")
		return
	if not _pool_spent:
		return
	# HOLDING MEANS THE ASSAULT RAN OUT AND YOU STILL HAVE GROUND.
	#
	# It used to also require the field to be CLEAR, and that is unreachable:
	# watched twice, the pool spent with fifty-odd attackers still standing and
	# two garrison left, so the win could never fire and neither could the loss
	# while a single anchor survived. The operation simply ran on.
	#
	# The attacker having no supply left to commit IS the end of the assault.
	# What is still walking around is a mop-up, and whether the defender clears
	# it is not what the operation was about. The grace is only so that a loss
	# that is one second away still lands first.
	if cores.is_empty() or held_cores() > 0:
		_clear_t += delta
		if _clear_t >= clear_seconds:
			_succeed()
	else:
		_clear_t = 0.0


func _hostiles_standing() -> int:
	var n := 0
	for ai in get_tree().get_nodes_in_group("enemies"):
		if ai == null or not is_instance_valid(ai):
			continue
		if "alive" in ai and not ai.alive:
			continue
		if "faction" in ai and Enums.are_hostile(Enums.Factions.PLAYER, ai.faction):
			n += 1
	return n


func _on_pool_spent() -> void:
	_pool_spent = true
	_clear_t = 0.0
