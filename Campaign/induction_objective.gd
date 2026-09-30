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

enum Trigger {
	## Player back to full frame, by any means.
	HEAL_SELF,
	## The robot the induction put on the floor, standing again.
	REVIVE_SQUADMATE,
	## `item_id` owned anywhere — in stores or already fitted.
	BUY_ITEM,
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
}

@export var trigger: Trigger = Trigger.HEAL_SELF
## What BUY_ITEM and EQUIP_ITEM are looking for.
@export var item_id: StringName = &"m4"
## Which order ORDER_SQUAD wants, as a SquadCommander.Verb.
@export var order_verb: int = 0

var _player: Node
var _casualty: Node
var _campaign: Node
## How many of item_id the player already had when this switched on. BUY_ITEM
## measures against it rather than against zero.
var _baseline: int = 0


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
		Trigger.BUY_ITEM, Trigger.EQUIP_ITEM:
			var state = _campaign.get("state") if _campaign != null else null
			if state == null:
				push_warning("InductionObjective '%s': no campaign state; it can never complete." % id)
				return
			# Taken BEFORE the first check, so "you bought one" means one more
			# than the squad mustered with.
			_baseline = _owned(state)
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
# FIT: the gun is in YOUR hands. The squad musters armed and the player does
# not — `Campaign._seed_new_campaign` issues a rifle to every roster record and
# the player's own record is not in `roster` — so arming yourself is the one
# fitting the induction can ask for that is not already done.
func _check_kit() -> void:
	if completed:
		return
	var state = _campaign.get("state") if _campaign != null else null
	if state == null:
		return
	if trigger == Trigger.BUY_ITEM:
		if _owned(state) > _baseline:
			complete()
		return
	var me = state.player_record
	if me != null and me.weapon_ids.has(item_id):
		complete()


## Every one of `item_id` the player has, in stores and in hands alike.
func _owned(state) -> int:
	var n: int = state.armoury.spare(item_id)
	for record in _records(state):
		if record != null:
			n += record.weapon_ids.count(item_id)
	return n


func _records(state) -> Array:
	var out: Array = []
	for r in state.roster:
		out.append(r)
	if state.player_record != null:
		out.append(state.player_record)
	return out
