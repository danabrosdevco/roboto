extends RefCounted

# ─────────────────────────────────────────────
# WHAT THE LINK IS GOOD ENOUGH TO TELL YOU.
#
# You are not looking at the squad. You are reading a feed from them, and the
# feed is a stat with a number on it — signal_integrity, the same one that
# already slows a jammed robot and e-kills it at the floor.
#
# So losing signal should not make the screen LOOK damaged. It should take
# things AWAY, in a fixed order, so the player learns to read their own
# condition off what is missing:
#
#   CLEAN      callsign, health, state, live position
#   FUZZED     health goes. You know where they are, not how they are.
#   DEGRADED   state goes. They are somewhere doing something.
#   CRITICAL   the callsign goes. A contact number, and nothing else.
#   EKILL      the squad layer is gone. There is you, a gun, and a room.
#
# That last rung is the premise delivered in one moment: strip the command
# layer and the player finds out this was never a shooter. They were a
# coordinator the whole time, and they only learn it when it is taken.
#
# THE SLOT STAYS OPEN. A removed readout leaves a dead placeholder rather than
# a gap, for the same reason squad_hud already holds the signal bar's space:
# a column that reflows is read as a layout bug, and a row of dashes where a
# number belongs is read as a loss. One of those is the feature.
#
# ASCII ONLY in the noise pool. This project has twice had a file re-encoded
# into mojibake by an in-place edit, and a green-phosphor readout wants
# teleprinter characters anyway.
# ─────────────────────────────────────────────

## The rungs, as ints so callers can compare with <= rather than match.
enum Veil { ALL = 0, NO_HEALTH = 1, NO_STATE = 2, CONTACT_ONLY = 3, BLIND = 4 }

const NOISE := "#%&@*?!/|=+<>~^$0123456789ABCDEF"

## How much of a string is eaten at each rung.
const BLEED := {
	Veil.ALL: 0.0,
	Veil.NO_HEALTH: 0.06,
	Veil.NO_STATE: 0.18,
	Veil.CONTACT_ONLY: 0.42,
	Veil.BLIND: 0.85,
}

## What a dead readout shows instead of nothing. Three dashes read as "this
## had a value and does not now"; an empty cell reads as "nothing goes here".
const DEAD := "---"

## Lines for a readout that has given up entirely. Deliberately procedural and
## unhelpful: the machine is reporting its own failure in the only register it
## has, which is the register it uses for everything else.
const LOST := [
	"NO CARRIER",
	"LINK LOST",
	"RETRY 3/8",
	"RETRY 4/8",
	"NO ROUTE TO SQUAD",
	"UPLINK DOWN",
	"CARRIER 0.0",
	"REACQUIRING",
]


## Which rung a signal integrity sits on. Thresholds are AI's own, so the
## readout degrades on exactly the same boundaries that degrade the robot.
static func veil_for(integrity: float, ekilled: bool = false) -> int:
	if ekilled or integrity <= AI.SIGNAL_EKILL:
		return Veil.BLIND
	if integrity <= AI.SIGNAL_CRITICAL:
		return Veil.CONTACT_ONLY
	if integrity <= AI.SIGNAL_DEGRADED:
		return Veil.NO_STATE
	if integrity <= AI.SIGNAL_FUZZED:
		return Veil.NO_HEALTH
	return Veil.ALL


## The rung for a player, or ALL when there is no player to ask — a readout
## that fails open is a readout the player can still use while something else
## is broken.
static func veil_of(player: Node) -> int:
	if player == null or not is_instance_valid(player):
		return Veil.ALL
	if not ("signal_integrity" in player):
		return Veil.ALL
	var ek: bool = false
	if player.has_method("get_signal_state"):
		ek = int(player.get_signal_state()) == int(AI.SignalState.EKILL)
	return veil_for(float(player.signal_integrity), ek)


## `text` with some of its characters replaced by line noise.
##
## `phase` makes the pattern move without re-randomising every frame: pass a
## value that changes a few times a second and the corruption crawls, which
## reads as a live bad connection. Pass a constant and it holds still, which
## reads as a broken screen. Both are wanted in different places.
##
## Spaces are never eaten, so word shapes survive and the line still scans as
## the thing it used to be. That is what makes it unsettling rather than
## illegible.
static func corrupt(text: String, amount: float, phase: int) -> String:
	if amount <= 0.0 or text.is_empty():
		return text
	var rng := RandomNumberGenerator.new()
	var out := ""
	for i in text.length():
		var ch := text[i]
		if ch == " ":
			out += ch
			continue
		# Seeded per character AND per phase, so the same character flickers on
		# its own schedule rather than the whole line changing at once.
		rng.seed = hash("%d:%d:%s" % [phase, i, ch])
		if rng.randf() < amount:
			out += NOISE[rng.randi_range(0, NOISE.length() - 1)]
		else:
			out += ch
	return out


## Corruption for a rung, with the phase derived from the clock.
static func bleed(text: String, veil: int, phase: int = -1) -> String:
	var amount: float = float(BLEED.get(veil, 0.0))
	if amount <= 0.0:
		return text
	var p: int = phase if phase >= 0 else int(Time.get_ticks_msec() / 110)
	return corrupt(text, amount, p)


## A line for a readout with nothing left to say. Walks the LOST list slowly so
## it reads as a machine retrying rather than as a flashing error.
static func lost_line(phase: int = -1) -> String:
	var p: int = phase if phase >= 0 else int(Time.get_ticks_msec() / 700)
	return LOST[p % LOST.size()]


## What a robot is called when the link is too poor to carry who it is.
## Numbered rather than blanked: something is out there and you can count them.
static func contact_name(index: int) -> String:
	return "CONTACT %02d" % (index + 1)
