extends MissionObjective
class_name InductionObjective

# ─────────────────────────────────────────────
# AN OBJECTIVE THAT COMPLETES ON AN EVENT, not on a place.
#
# Every other objective in this game is spatial — stand in a zone, clear a
# zone, reach a pad — because every other objective happens in a level. The
# induction happens at BASE, and the things it teaches are verbs, not
# destinations: patch yourself up, pick a squadmate off the floor, buy a gun,
# fit it, choose an operation. None of those has a position.
#
# So this subclass hangs off signals the game already emits instead of an
# Area3D. It uses MissionObjective's own hooks, which means the tracker, the
# HUD, the ordering and the reward plumbing all treat it as a normal objective
# and none of them had to learn about the induction.
#
# WIRED WHEN ACTIVATED, NOT IN _ready: the bodies it watches are spawned by the
# squad spawner a frame or two after the level loads, so `watch()` hands them
# over and activation does the connecting.
# ─────────────────────────────────────────────

## What is loaded into MEMORY, and what that costs. Preloaded rather than
## named: a class_name is not visible until the editor rescans.
const _Software := preload("res://Campaign/software_tree.gd")

enum Trigger {
	## Player back to full frame, by any means.
	HEAL_SELF,
	## The robot the induction put on the floor, standing again.
	REVIVE_SQUADMATE,
	## RETIRED, slot kept. This was "`item_id` owned anywhere", and the only way
	## to acquire one was the shop, which went on 2026-10-22 — LOAD_PROGRAM
	## replaced it. THE VALUE STAYS WHERE IT IS: these are ints, and removing
	## one remaps every trigger after it. Nothing authors a trigger in a scene
	## today (induction steps are built in code, Campaign/induction.gd) but the
	## rule holds anyway, because the next thing to author one would inherit a
	## silently shifted table. Backlog S9.
	_RETIRED_BUY_ITEM,
	## `item_id` fitted to a robot on the roster, the player included.
	EQUIP_ITEM,
	## Any operation chosen at the terminal.
	SELECT_MISSION,
	## An order given to a team — `order_verb` says which.
	ORDER_SQUAD,
	## The KEYS tab of the options screen has been on screen. APPENDED, not
	## slotted in beside the other menu-ish triggers: these are ints in a save
	## and in any scene that ever authors one.
	REVIEW_KEYS,
	## `item_id` loaded into MEMORY (Campaign/software_tree.gd). Replaces
	## _RETIRED_BUY_ITEM for the induction, which cannot teach a shop that is gone.
	## APPENDED, for the same reason REVIEW_KEYS was.
	LOAD_PROGRAM,
}

@export var trigger: Trigger = Trigger.HEAL_SELF
## What EQUIP_ITEM and LOAD_PROGRAM are looking for.
@export var item_id: StringName = &"m4"
## Which order ORDER_SQUAD wants, as a SquadCommander.Verb.
@export var order_verb: int = 0

var _player: Node
var _casualty: Node
var _campaign: Node
## Handed the things it cannot look up for itself. Call before activate().
func watch(campaign: Node, player: Node, casualty: Node) -> void:
	_campaign = campaign
	_player = player
	_casualty = casualty


func _on_activated() -> void:
	match trigger:
		Trigger.HEAL_SELF:
			if _player != null and is_instance_valid(_player) and _player.has_signal("healed"):
				_player.healed.connect(_on_player_healed)
			# Checked once on the way in: a player who is somehow already full
			# must not be handed an objective they cannot complete.
			_check_health()
		Trigger.REVIVE_SQUADMATE:
			if _casualty != null and is_instance_valid(_casualty) and _casualty.has_signal("revived"):
				_casualty.revived.connect(complete)
				if not bool(_casualty.get("downed")):
					complete()
			else:
				# NOTHING WAS PUT ON THE FLOOR. An objective that cannot be
				# completed would block the induction for good, so it passes
				# rather than hangs, and says why.
				push_warning("InductionObjective '%s': no downed squadmate to revive, completing it so the induction can finish." % id)
				complete()
		Trigger.EQUIP_ITEM, Trigger.LOAD_PROGRAM:
			var state = _campaign.get("state") if _campaign != null else null
			if state == null:
				push_warning("InductionObjective '%s': no campaign state; it can never complete." % id)
				return
			state.ledger_changed.connect(_check_kit)
			state.roster_changed.connect(_check_kit)
			_check_kit()
		Trigger.SELECT_MISSION:
			if _campaign != null and _campaign.has_signal("mission_selected"):
				_campaign.mission_selected.connect(_on_mission_selected)
		Trigger.REVIEW_KEYS:
			# Master is get_tree().current_scene in this project (see the note
			# in ai_weapon.gd) and it outlives every menu, so it is the only
			# thing an objective built at level load can connect to. Found by
			# signal rather than by class so a headless probe resolves it
			# before the editor has rescanned the class list.
			var master := get_tree().current_scene
			if master == null or not master.has_signal("keys_reviewed"):
				push_warning("InductionObjective '%s': nothing above the level emits keys_reviewed, so reading the keys can never complete it. Passing it rather than blocking the induction." % id)
				complete()
				return
			master.keys_reviewed.connect(complete)
		Trigger.ORDER_SQUAD:
			# SquadCommander owns the command key and announces every order it
			# sends, which is the only place an order can be observed — Squad
			# itself cannot tell a player's order from the AI director's.
			var commander := _commander()
			if commander == null:
				push_warning("InductionObjective '%s': no SquadCommander on the player, so no order can complete it." % id)
				return
			commander.order_issued.connect(_on_order)


func _on_player_healed(_amount: int, _healer: Node) -> void:
	_check_health()


func _check_health() -> void:
	if completed or _player == null or not is_instance_valid(_player):
		return
	if int(_player.get("health")) >= int(_player.get("max_health")):
		complete()


func _on_mission_selected(_mission) -> void:
	complete()


## The player's SquadCommander, found by script rather than by class_name so a
## probe run can resolve it before the editor has rescanned.
func _commander() -> Node:
	if _player == null or not is_instance_valid(_player):
		return null
	for child in _player.get_children():
		var s: Variant = child.get_script()
		if s != null and str(s.resource_path).ends_with("squad_commander.gd"):
			return child
	return null


func _on_order(_squad, verb: int, _position: Vector3, _target: Node) -> void:
	if verb == order_verb:
		complete()


# COUNTED AGAINST WHAT YOU STARTED WITH, not against zero.
#
# BUY: owning one MORE than when the induction began. A plain "is there one in
# stores" reads false again the moment the player fits it, and "does any robot
# hold one" was true before they had done anything — the squad musters holding
# rifles, one short. The baseline is the only version that survives the player
# buying and fitting in either order.
#
# LOAD: the item is in MEMORY. The induction names a weapon that is NOT
# issued, so this starts false — an issued one is loaded from the first frame
# and the step would be ticked before the player read it.
#
# FIT: the gun is in YOUR hands. You muster carrying the issued rifle, so a
# step naming THAT would also be done before it was read; naming something you
# had to load first is the version that asks for an action.
func _check_kit() -> void:
	if completed:
		return
	var state = _campaign.get("state") if _campaign != null else null
	if state == null:
		return
	if trigger == Trigger.LOAD_PROGRAM:
		# is_loaded(), never is_installed(): an ISSUED item costs 0 and is
		# never written to the ledger at all, so the ledger is the wrong place
		# to ask. An induction step naming an issued item would simply never
		# complete.
		if _Software.is_loaded(state, item_id):
			complete()
		return
	var me = state.player_record
	if me != null and me.weapon_ids.has(item_id):
		complete()


## _owned() AND _records() WENT WITH _RETIRED_BUY_ITEM. They counted every
## copy of item_id in stores and in hands, which is a question only a shop
## makes it possible to change the answer to. EQUIP_ITEM asks the player's own
## weapon_ids and LOAD_PROGRAM asks the software tree; neither needs a tally.
## Backlog S9.
