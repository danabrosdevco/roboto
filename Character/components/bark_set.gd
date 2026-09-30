extends Resource
class_name BarkSet

# ─────────────────────────────────────────────
# BARK SET — the clip library for one voice, shared by every robot that uses it.
#
# One .tres, not an array per chassis scene. The old shape put bark_clips on
# each chassis, so retuning the voice meant editing soldier_chassis, then
# soldier_shotgun, then four appx enemies, and they drifted. Point them all at
# one resource and the voice is authored once.
#
# Splitting hostiles from friendlies is a GAMEPLAY decision, not flavour: if
# both sides draw from the same 105 clips you cannot tell whether the voice you
# just heard was yours. Give hostiles their own BarkSet (or the same clips at a
# different pitch on the Bark node) so the player can always tell.
# ─────────────────────────────────────────────

# APPEND ONLY. These are stored as ints in .tres files once a set is authored —
# inserting a value silently remaps every clip array in the project. Same rule
# as SquadObjective and InteractTypes.
enum Line {
	CONTACT,     # first sight of a hostile, once per squad per engagement
	ORDER_ACK,   # answering a player order. Short, and its own channel
	KILL,        # a contact ended, not every individual kill
	RELOAD,      # worth hearing from HOSTILES, noise from friendlies
	DOWNED,      # a squadmate went down. The one line that must always play
	HURT,        # took damage. Where the single existing trigger lives
	SEARCH,      # lost contact, going to look
}

@export var contact: Array[AudioStream] = []
@export var order_ack: Array[AudioStream] = []
@export var kill: Array[AudioStream] = []
@export var reload: Array[AudioStream] = []
@export var downed: Array[AudioStream] = []
@export var hurt: Array[AudioStream] = []
@export var search: Array[AudioStream] = []

# Fallback for any line with nothing authored, so a half-filled set still
# speaks rather than going silently mute — the failure mode this project
# dislikes most.
@export var fallback: Array[AudioStream] = []


func clips_for(line: int) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	match line:
		Line.CONTACT:   out = contact
		Line.ORDER_ACK: out = order_ack
		Line.KILL:      out = kill
		Line.RELOAD:    out = reload
		Line.DOWNED:    out = downed
		Line.HURT:      out = hurt
		Line.SEARCH:    out = search
	if out.is_empty():
		return fallback
	return out


func has_line(line: int) -> bool:
	return not clips_for(line).is_empty()
