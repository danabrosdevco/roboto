extends Node
class_name LessonPrompts

# ─────────────────────────────────────────────
# LESSONS YOU EARN — the ones that cannot be signs.
#
# Every tutorial in this game is a TutorialLabel: a spot in the base you walk
# near. That works for the walkthrough and nothing else, for two reasons. The
# signs all retire once completed_tutorial is set, which by definition has
# happened long before any of these apply; and a sign teaches you whenever you
# happen to walk past it, which for a lesson about a frame you have not
# unlocked yet is either too early to mean anything or never.
#
# So these are keyed to the unlock instead. Come home with a Mechanic in the
# roster for the first time and the game tells you what the Factory is for.
# Come home with a Rover and it tells you those deploy as their own team and
# which key picks between them. Once each, recorded in the save.
#
# TIMING. It waits for the tree to unpause before it speaks. The debrief holds
# a pause while it is up, so this lands after the player has finished reading
# their payout and is standing in the base — not stacked on top of it. That
# also covers the squad manager and the pause menu for free.
#
# Self-wiring, built in code by ObjectiveHUD, same as the debrief and wallet.
# ─────────────────────────────────────────────

## id          what gets written into lessons_seen
## needs       the unlock that earns it
## text        first line is the headline, {action} expands to the live binding
const LESSONS: Array[Dictionary] = [
	{
		"id": &"supply",
		"needs": &"mechanic",
		"text": "TAKE MORE ROBOTS WITH YOU\n"
			+ "{squad_manager} OPENS THE FACTORY. COMPUTE BUYS SEATS THERE, AND "
			+ "EVERY SEAT IS ONE MORE ROBOT IN THE FIELD. TAKE A SEAT BACK ANY "
			+ "TIME YOU WANT THE COMPUTE SOMEWHERE ELSE.",
	},
	{
		"id": &"fireteams",
		"needs": &"rover",
		"text": "{switch_team} SWITCHES FIRETEAMS\n"
			+ "VEHICLES GO IN AS THEIR OWN TEAM, SEPARATE FROM YOUR INFANTRY. "
			+ "{switch_team} PICKS WHICH OF THEM YOUR ORDERS GO TO.",
	},
]

const _Toast := preload("res://Character/hud/tutorial_toast.gd")

## Seconds after the screen clears before it speaks. Long enough not to land on
## the last frame of the debrief fading out.
@export var settle_seconds: float = 1.6
@export var show_seconds: float = 11.0

var _campaign: Node
var _pending: String = ""
var _pending_id: StringName = &""
var _settle: float = 0.0


func _ready() -> void:
	_campaign = get_tree().get_first_node_in_group("campaign")
	if _campaign == null:
		push_warning("LessonPrompts: no campaign — unlock lessons will never fire.")
		set_process(false)
		return
	if _campaign.has_signal("returned_to_base"):
		_campaign.returned_to_base.connect(_on_home)
	set_process(true)


# The unlock is already in state by the time we are home: extract() grants it,
# and this fires afterwards.
func _on_home() -> void:
	if _pending != "":
		return   # one is already waiting; the next comes home next time
	var state = _campaign.get("state")
	if state == null:
		return
	for lesson in LESSONS:
		if not state.unlocked.has(lesson["needs"]):
			continue
		if not state.mark_lesson(lesson["id"]):
			continue
		_pending = lesson["text"]
		_pending_id = lesson["id"]
		_settle = settle_seconds
		# Straight to disk, like the tutorial sign does: the campaign only
		# autosaves on roster and ledger changes, and a lesson shown but not
		# recorded would come back every single time you came home.
		if bool(_campaign.get("autosave")):
			_campaign.save()
		return


func _process(delta: float) -> void:
	if _pending == "":
		return
	# Paused means something is on screen that the player is reading — the
	# debrief, the squad manager, the pause menu. Wait it out.
	if get_tree().paused:
		return
	_settle -= delta
	if _settle > 0.0:
		return
	_Toast.announce(get_tree(), _pending, show_seconds)
	_pending = ""
	_pending_id = &""
