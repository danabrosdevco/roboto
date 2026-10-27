extends RefCounted
class_name BarkDirector

# ─────────────────────────────────────────────
# BARK DIRECTOR — one arbiter owns the voice channel.
#
# THE PROBLEM THIS EXISTS FOR. Barking was a property of each robot: whoever
# ticked, spoke. A squad spotting the player meant four robots calling
# trigger_combat() within a few frames and four voices shouting "contact" over
# each other. Reducing it to a per-robot cooldown does not fix that — it just
# spreads the same four lines over four seconds, which sounds like four separate
# sightings, which is worse.
#
# The fix is to treat the VOICE CHANNEL as the scarce resource rather than the
# robot. Every bark is a request; this decides who, if anyone, speaks.
#
# THE ELECTION WINDOW is the important part. Requests are buffered for a moment
# instead of answered instantly, then the best one wins. Answering the first
# request means the winner is whichever robot's think-frame happened to land
# first — which is arbitrary, and biased by the vision stagger. Buffering lets
# the NCO answer, or whoever can actually see the target.
#
# Losers are DROPPED, never queued. A queued bark arrives after the moment has
# passed, and that is exactly what makes squad chatter sound like a machine
# reading a list.
#
# STATIC, deliberately. This project has a documented ready-order hazard in
# world.tscn and exactly one autoload. A static arbiter has no node to place, no
# group to resolve, and nothing to be null during _ready.
# ─────────────────────────────────────────────

# Channels are independent budgets. Hostiles must not be able to drown out your
# own squad — your squad's voice is the one carrying information you can act on.
# Orders get their own channel so an acknowledgement is never beaten by combat
# chatter; a player who commands and hears nothing concludes commanding does
# nothing.
enum Channel { FRIENDLY, HOSTILE, ORDERS }

const ELECTION_WINDOW := 0.15

# Nothing at all on a channel within this of its last bark.
const CHANNEL_COOLDOWN := {
	Channel.FRIENDLY: 1.0,
	Channel.HOSTILE: 1.4,
	Channel.ORDERS: 1.5,
}

const SQUAD_COOLDOWN := 3.0     # one squad may not dominate
const SPEAKER_COOLDOWN := 6.0   # one voice you get sick of

# Per squad, per line. THIS is what stops "Contact! Contact! Contact!" as each
# member acquires the same target a few frames apart.
const LINE_COOLDOWN := {
	BarkSet.Line.CONTACT: 10.0,
	BarkSet.Line.ORDER_ACK: 1.5,
	BarkSet.Line.KILL: 5.0,
	BarkSet.Line.RELOAD: 8.0,
	BarkSet.Line.DOWNED: 2.0,
	BarkSet.Line.HURT: 7.0,
	BarkSet.Line.SEARCH: 12.0,
}

const PRIORITY := {
	BarkSet.Line.DOWNED: 100,
	BarkSet.Line.CONTACT: 80,
	BarkSet.Line.KILL: 60,
	BarkSet.Line.ORDER_ACK: 50,
	BarkSet.Line.SEARCH: 30,
	BarkSet.Line.RELOAD: 20,
	BarkSet.Line.HURT: 10,
}

# Beyond this from the listener, drop the request entirely. Budget spent on a
# bark nobody can hear is budget stolen from one they can.
const EARSHOT := 55.0

static var enabled: bool = true

static var _channel_ms: Dictionary = {}   # Channel -> msec of last bark
static var _squad_ms: Dictionary = {}     # squad instance id -> msec
static var _speaker_ms: Dictionary = {}   # speaker instance id -> msec
static var _line_ms: Dictionary = {}      # "squad:line" -> msec
static var _pending: Dictionary = {}      # Channel -> candidate dictionary
## Elections where a candidate met a slot already held by a DIFFERENT squad.
## Counted, not warned — see the note where it is incremented. Backlog K18(b).
static var _slot_contested: int = 0

# Anything that wants to SEE what the squad is saying — the comms log reads
# these. GDScript has no static signals, so this is a plain callable registry.
# Only FRIENDLY and ORDERS are reported: the player's radio does not carry the
# enemy's traffic, and subtitling hostiles would give away positions the player
# has not earned.
static var _listeners: Array[Callable] = []


static func add_listener(cb: Callable) -> void:
	if not _listeners.has(cb):
		_listeners.append(cb)


static func remove_listener(cb: Callable) -> void:
	_listeners.erase(cb)


# The only entry point. Safe to call from anywhere, every frame, from any
# number of robots — that is the point.
static func request(speaker: Node3D, line: int, squad: Node = null,
		context: String = "") -> void:
	if not enabled or speaker == null or not is_instance_valid(speaker):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if tree.paused:
		# THE SQUAD MANAGER AND THE PAUSE SCREEN STAY QUIET — but one line is
		# not chatter. DOWNED is the only line this file calls "pure
		# information the player has to have", and it was being dropped with
		# everything else: a squadmate could go down across a level load or a
		# briefing and nothing would ever say so. Backlog K18(a).
		#
		# REPORTED, NOT HELD. The alternative was queueing it until the tree
		# unpauses, which needs an unpause hook and can double-fire; the text
		# is the part that carries the information, and the voice line would be
		# landing seconds late by then anyway.
		#
		# NO ELECTION AND NO COOLDOWN, deliberately: there is nothing to
		# compete with while paused, and DOWNED fires once per robot per
		# downing, so it cannot repeat its way into a spam.
		#
		# FRIENDLY ONLY, like every other report. The player's radio does not
		# carry the enemy's traffic.
		if line == BarkSet.Line.DOWNED \
				and _channel_for(speaker, line, squad) == Channel.FRIENDLY:
			_report(speaker, line, context)
		return

	var channel := _channel_for(speaker, line, squad)
	var now := Time.get_ticks_msec()

	if not _passes_cooldowns(channel, line, speaker, squad, now):
		return
	if not _in_earshot(speaker):
		return

	var candidate := {
		"speaker": speaker,
		"line": line,
		"squad": squad,
		"context": context,
		"priority": int(PRIORITY.get(line, 0)),
		"score": _speaker_score(speaker, squad),
	}

	# First request of this burst opens the window; later ones compete inside it.
	if not _pending.has(channel):
		_pending[channel] = candidate
		_open_window(tree, channel)
		return

	var best: Dictionary = _pending[channel]
	# MEASURING K18(b) RATHER THAN GUESSING AT IT.
	#
	# There is ONE pending slot per channel, game-wide, so two squads on
	# opposite sides of the map compete in a single 0.15 s election and the
	# loser is silenced. Whether that is a real fault depends entirely on how
	# often it happens, and EARSHOT already bounds it to 55 m of the camera —
	# which may make it almost never.
	#
	# So this counts the only case that matters: a candidate meeting a slot
	# already held by a DIFFERENT squad. Two robots of the same squad competing
	# is the election working as designed. reset() reports the tally at level
	# unload, and it stays silent when the answer is zero.
	#
	# IT CANNOT BE MEASURED HEADLESS. _in_earshot() returns true when there is
	# no camera ("don't silence the game"), so a headless run has no 55 m bound
	# at all and would overstate this freely.
	if best["squad"] != squad:
		_slot_contested += 1
	if candidate["priority"] > best["priority"] \
			or (candidate["priority"] == best["priority"] and candidate["score"] > best["score"]):
		_pending[channel] = candidate


# Level unload frees every speaker. Pending candidates hold hard references, and
# the cooldown dictionaries would grow forever across a campaign.
## Called on level unload. **It was never called in the campaign** until
## 2026-10-26 — only `Managers/lab.gd` ever did, although the comment here has
## always said level unload should. Cooldown stamps from the last level carried
## into the next one and the dictionaries grew for the whole session.
## `World.load_next_level` calls it now. Backlog K18(c).
static func reset() -> void:
	# THE K18(b) TALLY, REPORTED WHERE IT IS FINALLY COMPLETE. Silent at zero,
	# which is the answer that means the single pending slot never bit.
	if _slot_contested > 0:
		print("[BarkDirector] %d election(s) where two DIFFERENT squads wanted the same channel slot. See Backlog K18(b)." % _slot_contested)
	_slot_contested = 0
	_pending.clear()
	_squad_ms.clear()
	_speaker_ms.clear()
	_line_ms.clear()
	_channel_ms.clear()


# ─────────────────────────────────────────────
static func _open_window(tree: SceneTree, channel: int) -> void:
	# process_always so the window still closes if something pauses mid-burst.
	var timer := tree.create_timer(ELECTION_WINDOW, true)
	timer.timeout.connect(func(): _resolve(channel))


static func _resolve(channel: int) -> void:
	if not _pending.has(channel):
		return
	var winner: Dictionary = _pending[channel]
	_pending.erase(channel)

	# Untyped until checked. The speaker can be freed inside the window — a level
	# unload, a body taken off the field — and assigning a freed instance to a
	# typed variable is itself an error, before this check could catch it.
	var candidate = winner["speaker"]
	if candidate == null or not is_instance_valid(candidate):
		return
	var speaker: Node3D = candidate
	if not speaker.has_method("bark_now"):
		push_warning("BarkDirector: %s has no bark_now(); nothing will be heard." % speaker.name)
		return

	var now := Time.get_ticks_msec()
	_channel_ms[channel] = now
	var squad = winner["squad"]
	_line_ms[_line_key(squad, winner["line"])] = now

	# ORDERS does not spend the shared per-squad and per-speaker budgets. It has
	# its own channel precisely so acknowledgements and combat chatter do not
	# compete — but stamping the shared clocks reintroduced exactly that: every
	# acknowledgement locked its speaker out for 6s and the squad for 3s, and
	# contact, kill and hurt lines stopped being heard at all.
	if channel != Channel.ORDERS:
		_speaker_ms[speaker.get_instance_id()] = now
		if squad != null and is_instance_valid(squad):
			_squad_ms[squad.get_instance_id()] = now

	speaker.bark_now(winner["line"])

	# Report only what the player's own radio would carry. Reported AFTER the
	# clip starts so the text and the voice land together.
	if channel == Channel.FRIENDLY or channel == Channel.ORDERS:
		_report(speaker, winner["line"], String(winner["context"]))


static func _report(speaker: Node3D, line: int, context: String) -> void:
	var who := ""
	if "soldier_name" in speaker:
		who = str(speaker.soldier_name)
	elif speaker.get_parent() != null and "soldier_name" in speaker.get_parent():
		who = str(speaker.get_parent().soldier_name)
	for cb in _listeners.duplicate():
		if cb.is_valid():
			cb.call(who, line, context)
		else:
			_listeners.erase(cb)


static func _passes_cooldowns(channel: int, line: int, speaker: Node3D,
		squad: Node, now: int) -> bool:
	# DOWNED ignores the channel budget. It is the one line that is pure
	# information the player has to have — losing it to chatter is losing the
	# thing barks are for.
	var urgent: bool = line == BarkSet.Line.DOWNED

	if not urgent and _elapsed(_channel_ms, channel, now) < float(CHANNEL_COOLDOWN.get(channel, 1.0)):
		return false
	if _elapsed(_line_ms, _line_key(squad, line), now) < float(LINE_COOLDOWN.get(line, 5.0)):
		return false
	# Orders are exempt both ways — they neither spend the shared budgets nor
	# get blocked by them. An acknowledgement that loses to unrelated chatter
	# teaches the player that commanding does nothing.
	if not urgent and channel != Channel.ORDERS:
		if _elapsed(_speaker_ms, speaker.get_instance_id(), now) < SPEAKER_COOLDOWN:
			return false
		if squad != null and is_instance_valid(squad):
			if _elapsed(_squad_ms, squad.get_instance_id(), now) < SQUAD_COOLDOWN:
				return false
	return true


static func _elapsed(store: Dictionary, key, now: int) -> float:
	if not store.has(key):
		return 9999.0
	return float(now - int(store[key])) / 1000.0


static func _line_key(squad: Node, line: int) -> String:
	var sid := 0
	if squad != null and is_instance_valid(squad):
		sid = squad.get_instance_id()
	return "%d:%d" % [sid, line]


static func _channel_for(speaker: Node3D, line: int, squad: Node) -> int:
	if line == BarkSet.Line.ORDER_ACK:
		return Channel.ORDERS
	if squad != null and is_instance_valid(squad) and "player_commandable" in squad:
		return Channel.FRIENDLY if squad.player_commandable else Channel.HOSTILE
	# No squad to ask: fall back to the faction of whatever is speaking.
	var f = _speaker_faction(speaker)
	if f != null and (f == Enums.Factions.PLAYER or f == Enums.Factions.ALLIED):
		return Channel.FRIENDLY
	return Channel.HOSTILE


## The faction of the thing actually speaking.
##
## THE SPEAKER IS A `Bark` NODE, NOT THE ROBOT. `Bark.bark()` passes `self`,
## and a Bark has no `get_faction()` — so this used to ask an object that
## could never answer, every squadless robot fell through to HOSTILE, and a
## friendly without a squad never reached the comms log at all. Walk up to the
## body, the same way `Bark._resolve_squad()` already does for the squad.
##
## Still asks the speaker FIRST, because the director does not require its
## speakers to be Barks and anything that answers for itself should be
## believed. Backlog K13.
static func _speaker_faction(speaker: Node) -> Variant:
	var n: Node = speaker
	while n != null:
		if n.has_method("get_faction"):
			return n.get_faction()
		n = n.get_parent()
	return null


# The camera IS the audio listener, so this is literally "can it be heard".
static func _in_earshot(speaker: Node3D) -> bool:
	var cam := speaker.get_viewport().get_camera_3d() if speaker.is_inside_tree() else null
	if cam == null:
		return true   # no listener to reason about; don't silence the game
	return speaker.global_position.distance_to(cam.global_position) <= EARSHOT


# Who should speak for the squad. The NCO is the mouthpiece if there is one,
# which finally gives Squad.nco a job; otherwise whoever is closest to the
# listener, so the line comes from somewhere the player is looking.
## NEAREST TO THE CAMERA WINS, and that is the whole rule.
##
## THERE WAS AN NCO BONUS HERE AND IT NEVER FIRED. It compared `squad.nco` to
## the speaker — and the speaker is a `Bark` node, never the NCO robot — so
## the +1000 could not match and `probe_hud_facts.gd` measured it at 0 against
## 1000. NCOs were deprecated on 2026-10-23, so this is removed rather than
## repaired: nearest-to-camera is what you already hear, and **nothing audible
## changes.** Backlog K13.
##
## `Squad.nco` itself stays — `_acknowledge_order` still picks it first, and
## whether that field goes is a separate question.
static func _speaker_score(speaker: Node3D, _squad: Node) -> float:
	var score := 0.0
	if speaker.is_inside_tree():
		var cam := speaker.get_viewport().get_camera_3d()
		if cam != null:
			score += maxf(0.0, EARSHOT - speaker.global_position.distance_to(cam.global_position))
	return score
