extends Node
class_name Induction

# ─────────────────────────────────────────────
# THE DEPOT INDUCTION — the first visit to base is a mission.
#
# The tutorial used to be signs you walked past, and when the depot replaced
# the old homebase the signs did not come with it: a new save arrived at a base
# that explained nothing. This replaces them with five objectives in the
# ordinary objective HUD, so the thing that teaches the game is the same thing
# the game uses to set tasks everywhere else.
#
#   1. patch yourself up          (you arrive damaged)
#   2. get your squadmate up      (one robot arrives on the floor)
#   3. buy an Ancient Rifle
#   4. fit it to a robot
#   5. choose an operation
#
# ONCE. Finishing the fifth sets `completed_tutorial`, which is the same flag
# the old GO FORTH sign set, and from then on the depot is just the depot. An
# induction left unfinished is rebuilt on the next visit — including the
# casualty — so the objectives and the world can never disagree about whether
# there is a robot on the floor.
#
# Built in code rather than authored into the level: the depot is TERRAIN's
# file, these five exist only at base and only once, and a level should not
# carry nodes that are freed on every visit after the first.
# ─────────────────────────────────────────────

const _Objective := preload("res://Campaign/induction_objective.gd")
const _Commander := preload("res://Character/components/squad_commander.gd")

## The rifle the induction teaches you to buy and fit.
const TAUGHT_WEAPON := &"m4"

signal finished

var _campaign: Node
var _objectives: Array[MissionObjective] = []


## Builds the induction into `level` and returns it, or null when the campaign
## has already been through it.
## Takes down a previous induction, objectives and all. ALWAYS call this on
## arriving at base, finished or not: on_level_loaded runs on every arrival —
## World._ready fires it at boot and the train fires it coming home — so
## without it the five objectives stack up one set per visit and the tracker
## reports ten, then fifteen.
##
## remove_child before queue_free, which is deferred: the objectives have to
## leave the "mission_objectives" group NOW, because objectives.refresh() runs
## later in the same frame and would otherwise collect the dead set.
static func clear(level: Node) -> void:
	if level == null:
		return
	var old := level.get_node_or_null("Induction")
	if old != null:
		level.remove_child(old)
		old.queue_free()


static func begin(campaign: Node, level: Node) -> Node:
	if campaign == null or level == null:
		return null
	clear(level)
	var induction = new()
	induction.name = "Induction"
	induction._campaign = campaign
	level.add_child(induction)
	induction._build()
	return induction


func _build() -> void:
	# ALL FIVE ACTIVE AT ONCE, no prerequisite chain. A player who buys the
	# rifle before patching themselves up has still done the thing, and an
	# objective that was not listening yet would never notice.
	_add(&"induct_repair_self", "REPAIR YOURSELF",
		"Your frame took damage on the way in. The repair tool is built in on 3 — hold it with the crosshair on nothing.",
		_Objective.Trigger.HEAL_SELF)
	_add(&"induct_revive_squad", "GET YOUR SQUADMATE UP",
		"One of Bravo is on the floor. Same tool, crosshair on them.",
		_Objective.Trigger.REVIVE_SQUADMATE)
	# SHOPPING, AND IT HAS TO BE REAL. YOU are the one who musters unarmed: the
	# seed issues a rifle to every roster record and the player's record is not
	# in the roster, so the squad arrives holding rifles and you do not. That is
	# what keeps these two from completing themselves the moment they are built.
	# Buying is counted against what you owned when the induction started, so
	# fitting the rifle the instant you buy it still counts as having bought it.
	_add(&"induct_buy_rifle", "BUY AN ANCIENT RIFLE",
		"Your squad mustered with rifles. You did not. The armoury sells them and you can afford one.",
		_Objective.Trigger.BUY_ITEM)
	_add(&"induct_fit_rifle", "PUT THE RIFLE IN YOUR OWN HANDS",
		"Buying it is not carrying it. Open the squad manager, find your own card, and fit it.",
		_Objective.Trigger.EQUIP_ITEM)
	_add(&"induct_order_follow", "ORDER YOUR SQUAD TO FOLLOW",
		"{command} gives orders. Aim at nothing in particular and your team forms up on you.",
		_Objective.Trigger.ORDER_SQUAD, _Commander.Verb.FOLLOW)
	_add(&"induct_order_advance", "ORDER YOUR SQUAD TO ADVANCE",
		"Same key, aimed at a spot on the ground: they move up to it and hold there without you.",
		_Objective.Trigger.ORDER_SQUAD, _Commander.Verb.ADVANCE)
	_add(&"induct_pick_op", "CHOOSE AN OPERATION",
		"The terminal lists what is open to you. Pick one, then take the train.",
		_Objective.Trigger.SELECT_MISSION)


func _add(id: StringName, title: String, blurb: String, trigger: int, verb: int = 0) -> void:
	var o := _Objective.new()
	o.name = String(id)
	o.id = id
	o.display_name = title
	o.description = blurb
	o.trigger = trigger
	o.item_id = TAUGHT_WEAPON
	o.order_verb = verb
	# No payout. The induction is worth doing because it is the way out of the
	# depot, and paying for it would make the first mission's reward look mean.
	o.reward_resources = 0
	# NOT starts_active. _ready() would activate it the moment add_child runs,
	# which is before watch() has handed over the player and the casualty — so
	# every objective would wire itself to nulls. arm() activates them once the
	# things they watch exist.
	o.starts_active = false
	add_child(o)
	o.objective_completed.connect(_on_one_done)
	_objectives.append(o)


## Hands every objective the things it watches and starts them. The casualty
## only exists a frame or two after the squad musters, which is why this is a
## second step rather than part of begin(). Safe to call with a null body.
func arm(player: Node, casualty: Node) -> void:
	for o in _objectives:
		o.watch(_campaign, player, casualty)
		o.activate()


func _on_one_done(_objective: MissionObjective) -> void:
	for o in _objectives:
		if not o.completed:
			return
	# THE WAY OUT OF THE DEPOT. Same flag the old GO FORTH sign set, so every
	# reader of it — the signs, the toast, the lesson prompts — sees a finished
	# tutorial without knowing the induction replaced them.
	var state = _campaign.get("state") if _campaign != null else null
	if state != null and not state.completed_tutorial:
		state.completed_tutorial = true
		if _campaign.has_method("_queue_base_save"):
			_campaign._queue_base_save()
	print("[Induction] all five done; the depot is just the depot from here.")
	finished.emit()
