extends Node
class_name CampaignManager

# Playtest analytics. By path: see the note in analytics.gd.
const _Analytics := preload("res://Managers/analytics.gd")
const _Induction := preload("res://Campaign/induction.gd")
const _SoftwareTree := preload("res://Campaign/software_tree.gd")

# ─────────────────────────────────────────────
# CAMPAIGN — the autoload that owns state across level loads.
#
# Register in Project Settings > Autoload with the name "Campaign". It has to
# be an autoload rather than a node under World: World.load_next_level() frees
# the level and the roster has to outlive that.
#
# LIFECYCLE
#   deploy(mission)  remembers the mission and hands World the level to load
#   on_level_loaded  the spawner builds the squad from the roster
#   extract()        write_back, pay rewards, save, return to base
#
# The base is just another TrenchBroomLevel. Deploying from it and extracting
# back to it are the same operation with different destinations, which is why
# MissionExit resolves its target from here instead of from the inspector.
# ─────────────────────────────────────────────

@export var base_level: PackedScene
# Everything the player can deploy to. Authored .tres definitions.
@export var missions: Array[MissionDefinition] = []
@export var autosave: bool = true

# Every item, module and chassis in the game. Handed to CampaignState so records
# can derive their stats, and read by the squad manager UI and the spawner.
@export var catalogue: ItemCatalogue

# ── DEV: launching a mission level directly ───
# Running valley_level.tscn (or world.tscn pointed at it) skips the base, so
# begin_deploy() never runs: in_mission stays false, current_mission stays null,
# the enemy force never spawns and the objective HUD hides itself. All silently.
#
# Assign a MissionDefinition here and the campaign assumes that operation when
# it finds itself in a level that isn't base. Leave null for shipping builds.
@export var debug_mission: MissionDefinition

## Every mission selectable at the terminal from a fresh campaign, ignoring both
## the `requires` chain and the "non-repeatable, already cleared" filter — so a
## mission stays on the list after you finish it and you can keep cycling.
##
## For testing a late mission without replaying the ones before it. Leave OFF in
## anything you send out: with this on, the arena → valley progression doesn't
## exist and the first press of F can drop you straight into Valley Siege.
@export var unlock_all_missions: bool = false

# ── STARTING ROSTER ───────────────────────────
# A brand new CampaignState has an empty roster, so without this nothing ever
# deploys and the spawner silently does nothing — which looks exactly like the
# spawner being broken. These are only used on a fresh save.
@export var starting_squad_size: int = 4
@export var starting_names: Array[String] = ["Bravo-1", "Bravo-2", "Bravo-3", "Bravo-4"]
@export var starting_chassis: PackedScene
# The frame every starting soldier is built on. Their health comes from this
# now, not from a number on the record.
@export var starting_chassis_id: StringName = &"soldier"
@export var starting_resources: int = 0
# Item ids granted to stores on a fresh campaign, and the weapon every starting
# soldier is issued. Without these a new save has an empty armoury and a squad
# holding nothing, because the chassis ships with no gun by design.
@export var starting_stock: Array[StringName] = [
]
@export var starting_weapon_id: StringName = &"m4"
## What the player's health opens the FIRST tutorial on, as a fraction of their
## maximum. Low enough that the repair tool is plainly the answer, high enough
## that a fall off the gantry cannot finish them before they find it.
@export_range(0.05, 1.0, 0.05) var tutorial_player_health: float = 0.35
## OFF FOR ANYTHING THAT IS NOT THE GAME. The lab boots the campaign to get at
## the catalogue and the spawner, lands at base like any other session, and was
## therefore staging the induction casualty in the middle of a measurement run —
## downing a robot and dropping the player to 35% in what is supposed to be a
## controlled fight. Master turns this off in lab_mode.
@export var stage_tutorial: bool = true

signal state_loaded
signal deployed(mission: MissionDefinition)
signal extracted(mission: MissionDefinition, result: Dictionary)
signal returned_to_base
signal mission_selected(mission: MissionDefinition)
signal departure_ready(mission: MissionDefinition)

var state: CampaignState
var current_mission: MissionDefinition = null
var spawner: SquadSpawner = null
var objectives: ObjectiveTracker = null
var enemy_spawner: EnemyForceSpawner = null
# The exits at base that the terminal writes a destination into. Registered by
# World on every level load, because they live in the level scene and die with
# it.
var departure_exits: Array[LevelExit] = []

# True while the player is on a mission map rather than at base.
var in_mission: bool = false
## Seconds of play on the current mission, paused time excluded. Read off the
## debrief as "how long that took".
var seconds_this_mission: float = 0.0
# The campaign as it stood when this deployment left base, for putting back if
# the player dies out there. Empty outside a mission, and empty for a level
# launched directly — see the void in extract().
var _pre_run: Dictionary = {}

# Resources a Reclaimer has ground out of enemy wrecks on this mission. Held
# here rather than paid as it comes in, so the debrief can show it as its own
# line and a mission abandoned halfway still pays it the same way.
var salvage_this_mission: int = 0


# Only runs on a mission (begin_deploy switches it on, extract switches it off)
# and never while the tree is paused, which is what makes this "time spent on
# the mission" rather than "time since you left base".
func _physics_process(delta: float) -> void:
	if in_mission:
		seconds_this_mission += delta


## A Reclaimer finished grinding a wreck worth `amount`. Counted only on a
## mission: a fight in the lab, or anything at base, pays nobody.
func add_salvage(amount: int) -> void:
	if not in_mission or amount <= 0:
		return   # not on a mission, or a wreck worth nothing: nothing to pay out
	salvage_this_mission += amount


func _ready() -> void:
	# FIRST, before anything that can fail. Consumers find the campaign through
	# this group rather than assuming /root/Campaign (autoload) or a specific
	# parent chain — both of which break the moment you rewire it, and both of
	# which fail silently.
	add_to_group("campaign")
	# Only ticks while a mission is running; begin_deploy turns it on.
	set_physics_process(false)

	# Loud on purpose. A dev flag that removes the entire mission progression is
	# exactly the kind of thing that ships enabled because nobody could see it
	# was on — the terminal looks normal, it just offers everything.
	if unlock_all_missions:
		push_warning("Campaign: unlock_all_missions is ON. Every mission is selectable and none ever retire. Turn this off before exporting a build.")

	state = CampaignState.load_from_disk()
	if state == null:
		state = CampaignState.new()
		_seed_new_campaign()
	state.catalogue = catalogue
	if not state.soldier_repaired.is_connected(_on_soldier_repaired):
		state.soldier_repaired.connect(_on_soldier_repaired)

	# Armoury transactions write straight through, so a crash at base can never
	# cost you a purchase you already paid for.
	if not state.ledger_changed.is_connected(_queue_base_save):
		state.ledger_changed.connect(_queue_base_save)
	if not state.roster_changed.is_connected(_queue_base_save):
		state.roster_changed.connect(_queue_base_save)
	_repair_roster()
	state.recompute_roster()
	# After the catalogue: a save from before teams gets its INFANTRY and ARMOR
	# built from what each robot's frame is.
	state.ensure_teams()
	if not state.teams_changed.is_connected(_on_teams_changed):
		state.teams_changed.connect(_on_teams_changed)
	_pay_compute_owed()
	_grant_owed_unlocks()
	state_loaded.emit()


# A save from before compute — or from before an op paid any — has cleared ops
# it was never paid for. Each pays its first-clear compute now, once. Quietly:
# loading must not write the save by itself, and the next save keeps it (the
# claims and the compute are saved together, so nothing can be paid twice).
func _pay_compute_owed() -> void:
	var owed := 0
	for m in missions:
		if m != null and state.completed_missions.has(m.id):
			owed += state.claim_compute(CampaignState.clear_compute_key(m.id), m.compute_reward)
	if owed > 0:
		state.compute_earned += owed
		print("[Campaign] +%d compute for operations cleared before they paid it." % owed)
	# A program the tree no longer has (renamed or cut in a patch) hands its
	# compute back rather than holding it forever out of reach.
	var dropped := state.release_unknown_software(_SoftwareTree.ids())
	if not dropped.is_empty():
		push_warning("Campaign: software %s is no longer in the tree; its compute was freed." % str(dropped))


# The chassis every new soldier gets. Falls back to the FIRST chassis in the
# catalogue when starting_chassis_id doesn't resolve — renaming an id in a .tres
# and forgetting the export here otherwise produces a squad with no chassis,
# which shows up as "NO SLOTS ON THIS CHASSIS" and looks like the drag-and-drop
# being broken rather than a one-word mismatch.
func default_chassis() -> ChassisDefinition:
	if catalogue == null:
		push_warning("Campaign: no catalogue assigned — soldiers will have no chassis and no slots.")
		return null
	var frame := catalogue.chassis_def(starting_chassis_id)
	if frame != null:
		return frame
	if not catalogue.chassis.is_empty():
		var fallback: ChassisDefinition = catalogue.chassis[0]
		push_warning("Campaign: no chassis with id '%s'; falling back to '%s'. Fix starting_chassis_id or the .tres id." % [
			starting_chassis_id, fallback.id])
		return fallback
	push_warning("Campaign: the catalogue has no chassis at all.")
	return null


# Existing saves predate the chassis system, or were written when the id didn't
# match. Repairing on load beats telling people to delete their save.
func _repair_roster() -> void:
	var frame := default_chassis()
	if frame == null:
		return
	for r in state.roster:
		if r.chassis_id == &"" or catalogue.chassis_def(r.chassis_id) == null:
			r.set_chassis(frame, catalogue)
		_grow_weapon_slots(r)
	if state.player_record != null:
		if state.player_record.chassis_id == &"" or catalogue.chassis_def(state.player_record.chassis_id) == null:
			state.player_record.display_name = CampaignState.PLAYER_DEFAULT_NAME
			state.player_record.set_chassis(frame, catalogue)
	_return_unusable_player_kit()
	_return_unfittable_squad_kit()


# A frame can GAIN a weapon slot under a save — the Reclaimer's boom took one
# for the mortar — and a robot saved before has no slot to fit it into: fitting
# checks the record's own array, which the frame's new size never reaches until
# something resizes it. Grown only, empty, in place: nothing fitted moves, and
# loading still writes nothing.
func _grow_weapon_slots(r: SoldierRecord) -> void:
	var frame := catalogue.chassis_def(r.chassis_id)
	if frame == null or r.weapon_ids.size() >= frame.weapon_slots:
		return   # a frame this build lacks (repaired above), or already big enough
	r.weapon_ids.resize(frame.weapon_slots)


# Anything fitted to a SQUADMATE that its frame no longer takes comes off and
# goes back to stores. A rule can change under a save — nanites stopped fitting
# frames that drive — and the alternative is a module that quietly still works
# on a frame the armourer will not let you fit it to.
#
# In place, for the same reason as the player's version below: loading should
# not write the save on its own.
func _return_unfittable_squad_kit() -> void:
	if catalogue == null:
		return
	for rec in state.roster:
		var frame := catalogue.chassis_def(rec.chassis_id)
		if frame == null:
			continue   # repaired above, or a frame this build no longer has
		var changed := false
		var held := {}   # one-per-robot items already counted on this robot
		for field in ["weapon_ids", "equipment_ids", "module_ids"]:
			var ids: Array = rec.get(field)
			for i in ids.size():
				var id_value: StringName = ids[i]
				if id_value == &"":
					continue
				var item: ItemDefinition = catalogue.item(id_value)
				if item != null and not frame.takes(item):
					ids[i] = &""
					state.armoury.add(id_value)
					changed = true
					print("[Campaign] %s no longer fits %s (%s); returned it to stores."
						% [item.display_name, rec.display_name, frame.display_name])
				elif item != null and item.one_per_robot:
					# Saved before the rule: the second copy of a one-per-robot
					# module comes off, the first stays where it was.
					if held.has(id_value):
						ids[i] = &""
						state.armoury.add(id_value)
						changed = true
						print("[Campaign] %s had a second %s; returned it to stores."
							% [rec.display_name, item.display_name])
					held[id_value] = true
		if changed:
			rec.recompute_stats(catalogue)


# Anything fitted to the PLAYER that no longer fits the player comes off and
# goes back to stores. The case this exists for: the Repair Tool became built
# in (key 3, permanent), and a save with one fitted in an equipment slot would
# otherwise build a second copy on key 4 or 5. Back in stores it is not lost —
# a squadmate can still carry it.
#
# Done in place rather than through unfit_item(), which announces roster_changed
# and — at base — saves. Loading should not write the save on its own; the fix
# rides along with the next save that happens for a real reason, and until then
# it simply reapplies on each load.
func _return_unusable_player_kit() -> void:
	var rec := state.player_record
	if rec == null or catalogue == null:
		return
	var changed := false
	for field in ["weapon_ids", "equipment_ids", "module_ids"]:
		var ids: Array = rec.get(field)
		for i in ids.size():
			var id_value: StringName = ids[i]
			if id_value == &"":
				continue
			var item: ItemDefinition = catalogue.item(id_value)
			if item != null and not item.fits_player():
				ids[i] = &""
				state.armoury.add(id_value)
				changed = true
				print("[Campaign] %s no longer fits the player; returned it to stores." % item.display_name)
	if changed:
		rec.recompute_stats(catalogue)


func _seed_new_campaign() -> void:
	state.supply_cap = starting_squad_size
	state.award(starting_resources)
	for i in starting_squad_size:
		var r := SoldierRecord.new()
		r.display_name = starting_names[i] if i < starting_names.size() else "Unit-%02d" % (i + 1)
		r.chassis_scene = starting_chassis
		var frame := default_chassis()
		if frame != null:
			r.set_chassis(frame, catalogue)
		state.add_soldier(r)
	# The player is a roster entry too, so they need a frame for their slots.
	var player_frame := default_chassis()
	if player_frame != null and state.player_record != null:
		state.player_record.display_name = CampaignState.PLAYER_DEFAULT_NAME
		state.player_record.set_chassis(player_frame, catalogue)

	# Stores first, then issue each soldier their weapon out of it.
	for item_id in starting_stock:
		state.armoury.add(item_id)
	if catalogue != null and starting_weapon_id != &"":
		var gun := catalogue.item(starting_weapon_id)
		if gun != null:
			for r in state.roster:
				state.fit_item(r, gun, 0)

	if autosave:
		state.save_to_disk()


# Wipes the save and starts over. Bind it to a debug key while you're iterating
# — otherwise every change to the starting roster is invisible until you go and
# delete user://campaign.json by hand.
func reset_campaign() -> void:
	state = CampaignState.new()
	_seed_new_campaign()
	current_mission = null
	in_mission = false
	state_loaded.emit()


# World registers itself here so Campaign doesn't have to go looking for it.
func register_spawner(s: SquadSpawner) -> void:
	spawner = s


# A repair has to reach the body, not just the record — and a rebuilt soldier
# who wasn't deployable at level load has to actually turn up.
# Write-through for base-side changes, coalesced to one write per frame.
#
# GATED ON BEING AT BASE, deliberately. ledger_changed and roster_changed also
# fire throughout a mission — every kill, repair and XP award — and writing on
# each would churn the disk for no benefit AND persist a half-dead roster over
# the healthy one you deployed with, so a crash mid-mission would cost you the
# squad instead of costing you nothing.
#
# Coalesced because one purchase emits both signals; without this, every buy
# would write the file twice.
var _save_queued: bool = false
## The depot induction while it is running, so the deferred casualty staging
## can hand it the robot it put on the floor. Null once it is finished.
var _induction: Node = null


func _queue_base_save() -> void:
	if in_mission or not autosave or _save_queued:
		return
	_save_queued = true
	_flush_base_save.call_deferred()


func _flush_base_save() -> void:
	_save_queued = false
	# Re-checked: a deferred call lands a frame later, and that frame may be
	# the one begin_deploy() ran in.
	if in_mission or not autosave:
		return
	state.save_to_disk()


## True for the hub, whichever way it got into the tree — pre-instanced under
## World at boot or loaded on the way home from an operation.
func _is_base(level: Node) -> bool:
	return level != null and base_level != null \
		and level.scene_file_path == base_level.resource_path


# THE FIRST TUTORIAL OPENS ON A CASUALTY.
#
# A new player's first two verbs are the two no sign can teach: patch yourself
# up, and pick a squadmate off the floor. Both are the same tool — key 3, and
# the crosshair decides which one you get — so one downed robot and a hurt
# player covers the whole of it without a word of instruction.
#
# ONCE, EVER, and not once per visit. mark_lesson is the ledger built for this:
# true the first time, false after, and it is written to the save. Without it
# every walk back into the base before the last sign is read would put another
# robot on the floor.
#
# BODIES ONLY, NEVER RECORDS. The record is what deploys and what the repair
# desk bills for, so writing this damage there would charge the player compute
# to undo a scripted lesson and could bench the robot outright. Nothing can
# soft-lock on that choice: leaving for a mission repairs body and record both
# (TestCharacter._repair_at_base), so the worst case is a lesson skipped.
func _stage_first_tutorial(squad: Squad) -> void:
	if squad == null or not is_instance_valid(squad):
		return
	# The LAST one down, so Bravo-1 — the robot the player's eye goes to first
	# and the one every order demo talks about — is still on their feet.
	var casualty: Soldier = null
	for member in squad.squad_members:
		if member != null and is_instance_valid(member) \
				and member.can_be_downed and not member.downed:
			casualty = member
	if casualty != null:
		casualty.enter_downed()
	var body: Node = spawner.player if spawner != null else null
	if body != null and is_instance_valid(body) and "health" in body and "max_health" in body:
		body.health = maxi(1, int(round(float(body.max_health) * tutorial_player_health)))
	print("[Campaign] induction: %s is down, and you start at %d%% health." % [
		casualty.soldier_name if casualty != null else "nobody (no downable body mustered)",
		int(round(tutorial_player_health * 100.0))])
	# Arming is NOT done here. It has to happen on every visit the induction is
	# up, and this runs only on the visit that stages the casualty.


# Switches the induction's objectives on, once the bodies they watch exist.
# Finds the casualty rather than being handed it, because on a resumed
# induction nothing was staged and there is no casualty to hand over.
func _arm_induction() -> void:
	if _induction == null or not is_instance_valid(_induction):
		return
	var casualty: Soldier = null
	if spawner != null:
		for squad in spawner.squads:
			if squad == null or not is_instance_valid(squad):
				continue
			for member in squad.squad_members:
				if member != null and is_instance_valid(member) and member.downed:
					casualty = member
	_induction.arm(spawner.player if spawner != null else null, casualty)
	if objectives != null:
		objectives.refresh()


func _on_soldier_repaired(record: SoldierRecord) -> void:
	if spawner != null:
		spawner.sync_record(record)


# A robot moved to another team in the squad manager changes squad where it
# stands — at base or in the middle of a mission — and a new or renamed team is
# named in the field at once. The bench still waits for the next deploy.
func _on_teams_changed() -> void:
	if spawner != null:
		spawner.regroup()


func register_objective_tracker(t: ObjectiveTracker) -> void:
	objectives = t
	# THE REINFORCEMENT DIRECTOR. Posture.RESERVE has been implemented in the
	# spawner all along with nothing to trigger it; this is the trigger.
	# Escalation hangs off what the player DID — an objective completing — not
	# off a timer, so a cautious player and a fast one meet the same pressure at
	# the same point in the mission rather than the slow one being punished.
	if objectives != null and not objectives.objective_changed.is_connected(_on_objective_changed):
		objectives.objective_changed.connect(_on_objective_changed)


func _on_objective_changed(objective: MissionObjective) -> void:
	_Analytics.objective(objective)
	if objective == null or not objective.completed:
		return
	if enemy_spawner == null:
		return
	# The reserve's reinforcement_tag IS an objective id, so completing that
	# objective is the whole trigger condition. wake() is a no-op for any
	# objective no reserve is waiting on.
	var woken: int = enemy_spawner.wake(objective.id)
	# Says which failure it is when nothing arrives. A completed objective that
	# wakes nothing while reserves are still queued means the ids don't match —
	# almost always a typo between a mission's reinforcement_tag and the
	# level's objective id, which is otherwise completely silent.
	if woken == 0:
		var pending: Array = enemy_spawner.pending_reserve_tags()
		if not pending.is_empty():
			print("[Campaign] objective '%s' completed but no reserve answers to it. Still waiting on: %s" % [
				objective.id, str(pending)])


func register_enemy_spawner(s: EnemyForceSpawner) -> void:
	enemy_spawner = s


# True when this objective id should be live for the current operation. An empty
# active_objectives list on the mission means "all of them", so a level's
# objectives keep working with no mission configuration at all.
# Frees any objective the current mission didn't ask for. Safe to call twice —
# anything already gone isn't in the group.
func _prune_inactive_objectives() -> void:
	if current_mission == null or current_mission.active_objectives.is_empty():
		return
	var removed: Array[String] = []
	for node in get_tree().get_nodes_in_group("mission_objectives"):
		if not (node is MissionObjective):
			continue
		var objective := node as MissionObjective
		if objective.id == &"":
			continue
		if current_mission.active_objectives.has(objective.id):
			continue
		removed.append(String(objective.id))
		objective.queue_free()
	if not removed.is_empty():
		print("[Campaign] '%s' excludes %d objective(s): %s" % [
			current_mission.id, removed.size(), removed])


func is_objective_active(id: StringName) -> bool:
	if current_mission == null:
		return true
	if current_mission.active_objectives.is_empty():
		return true
	return current_mission.active_objectives.has(id)


# World calls this after each level load with whatever it found in the
# "departure_exits" group. Re-pushes the current selection so the train is
# already pointed somewhere if a mission was picked before this level existed.
func register_departure_exits(exits: Array) -> void:
	departure_exits.clear()
	for e in exits:
		if e is LevelExit:
			departure_exits.append(e)
	_push_destination()


# The whole "terminal sets the train's destination" mechanic, in one place.
func _push_destination() -> void:
	var mission := selected_mission()

	# Departures belong to base. If we're on a mission, anything still holding
	# the flag gets pointed home instead of at the operation we're already in —
	# otherwise the exit becomes a loop back to this level's spawn point.
	if in_mission:
		for exit in departure_exits:
			if is_instance_valid(exit):
				exit.next_level = base_level
		return

	for exit in departure_exits:
		if not is_instance_valid(exit):
			continue
		var destination: PackedScene = mission.level_scene if mission != null else null
		# Belt and braces: a mission whose level_scene is the level we're
		# standing in would reload it rather than travel anywhere.
		if destination != null and current_mission != null \
				and destination == current_mission.level_scene and in_mission:
			destination = base_level
		exit.next_level = destination

	if mission != null:
		departure_ready.emit(mission)


# ─────────────────────────────────────────────
# MISSION SELECTION
# ─────────────────────────────────────────────
func get_mission(id: StringName) -> MissionDefinition:
	for m in missions:
		if m.id == id:
			return m
	return null


## The campaign's last operation: the last entry in `missions`, which is the
## order the terminal offers them in.
func is_final_mission(m: MissionDefinition) -> bool:
	if m == null:
		return false
	for i in range(missions.size() - 1, -1, -1):
		if missions[i] != null:
			return missions[i].id == m.id
	return false


func available_missions() -> Array[MissionDefinition]:
	var out: Array[MissionDefinition] = []
	# The exported flag OR the DEBUG tab's switch. Two sources rather than one
	# variable they fight over: the export is for launching the editor into a
	# late mission, the setting is for opening the ladder up mid-run from the
	# pause menu, and neither should silently turn the other off.
	var all_open: bool = unlock_all_missions or _debug_switch("debug.unlock_all_missions")
	for m in missions:
		if all_open or (state != null and state.campaign_won):
			# Both filters skipped, not just the gate: dropping only `requires`
			# would still retire each non-repeatable mission the moment you
			# cleared it, so you could reach Valley Siege but not run it twice.
			if m != null:
				out.append(m)
			continue
		if not m.repeatable and state.completed_missions.has(m.id):
			continue
		var gated := false
		for req in m.requires:
			if not state.completed_missions.has(req):
				gated = true
				break
		if not gated:
			out.append(m)
	return out


func select_mission(id: StringName) -> void:
	state.selected_mission_id = id
	# Writing the destination into the exit is the point of selecting. Do it
	# here rather than in the terminal so every terminal, and any future map
	# UI, gets the behaviour for free.
	_push_destination()
	mission_selected.emit(selected_mission())


func selected_mission() -> MissionDefinition:
	return get_mission(state.selected_mission_id)


# ─────────────────────────────────────────────
# DESTINATION — what the special level exit resolves to
# ─────────────────────────────────────────────
# On the base map this is the selected mission. On a mission map it's the base.
# Returns null when nothing is selected, and MissionExit refuses to fire rather
# than dumping the player into a null scene.
func next_destination() -> PackedScene:
	if in_mission:
		return base_level
	var mission := selected_mission()
	return mission.level_scene if mission != null else null


# ─────────────────────────────────────────────
# DEPLOY / EXTRACT
# ─────────────────────────────────────────────
func begin_deploy() -> void:
	current_mission = selected_mission()

	# SAVE BEFORE LEAVING BASE.
	#
	# The first write after an armoury trip used to be extract(), which only
	# runs if you finish the mission. Anything else — a mission that crashes,
	# hangs, spawns no enemies, or that you alt-F4 out of — threw away every
	# purchase and every refit made since the last extraction, so testing a
	# broken mission meant rebuying the same kit on every attempt.
	#
	# Safe to take here because in_mission and current_mission live on this
	# node, not on CampaignState: a save written at deploy has no idea a
	# mission was starting, so it always reloads at base with the kit intact.
	# Written before deployed.emit() so a listener that fails can't cost you
	# the purchases either.
	if autosave:
		if not state.save_to_disk():
			push_warning("Campaign: could not save before deploying to '%s'. Purchases made since the last extraction are at risk if this mission does not finish cleanly." % (current_mission.id if current_mission != null else &"?"))

	in_mission = true
	salvage_this_mission = 0
	seconds_this_mission = 0.0
	# TIME SPENT ON THE MISSION, not time since you pressed deploy. Accumulated
	# from the physics tick rather than read off the clock, so the briefing, the
	# squad manager, the map and the pause menu — every one of which holds the
	# tree paused — do not count against you. A wall-clock reading would say a
	# mission took twenty minutes because you spent fifteen of them in the
	# armoury.
	set_physics_process(true)
	# What to put back if you die out there. See the void in extract().
	_pre_run = state.to_dict()
	if current_mission != null:
		deployed.emit(current_mission)


# Who deploys on `mission`: everyone ACTIVE (fit and not benched), cut to the
# mission's squad_size. Roster order fills the places, so benching is how you
# choose who goes when the op only takes one or two.
func squad_for(mission: MissionDefinition) -> Array[SoldierRecord]:
	var going: Array[SoldierRecord] = state.deployable() if state != null else []
	if mission == null or mission.squad_size < 0 or going.size() <= mission.squad_size:
		return going
	var capped: Array[SoldierRecord] = []
	for i in mission.squad_size:
		capped.append(going[i])
	return capped


# Called by World once the new level is in the tree and its spawn point exists.
func on_level_loaded(level: Node) -> void:
	if level == null:
		return

	# Direct launch: no one called begin_deploy(), so adopt debug_mission.
	if not in_mission and debug_mission != null:
		current_mission = debug_mission
		state.selected_mission_id = debug_mission.id
		in_mission = true
		salvage_this_mission = 0
		_pre_run = state.to_dict()
		print("[Campaign] debug_mission active: '%s'. Base flow was skipped." % debug_mission.id)

	if not in_mission and debug_mission == null and base_level != null:
		# AT BASE this is the normal state of affairs and nothing below is
		# skipped — the squad still musters. Compared by SCENE PATH: level is a
		# Node and base_level is a PackedScene, so `level == base_level` was
		# never once true, and the warning fired every time the player walked
		# into their own depot.
		if not _is_base(level):
			push_warning("Campaign: level loaded but in_mission is false, so NO enemy force will spawn and the objective HUD will stay hidden. If you launched this level directly, set Campaign.debug_mission.")

	if in_mission and current_mission == null:
		push_warning("Campaign: in a mission but current_mission is null. Nothing will spawn. Either deploy from base, or set Campaign.debug_mission while iterating.")
	if spawner != null:
		var going := squad_for(current_mission if in_mission else null)
		# NOT EVERYTHING MUSTERS AT THE HUB. A quadcopter cannot stand at ease:
		# parked at the base it hovers, and its rotor loop runs for as long as
		# you are in there buying things. It still deploys on every mission —
		# see ChassisDefinition.musters_at_base.
		if not in_mission:
			var mustering: Array[SoldierRecord] = []
			for record in going:
				var frame := catalogue.chassis_def(record.chassis_id) if catalogue != null else null
				if frame == null or frame.musters_at_base:
					mustering.append(record)
			going = mustering
		if going.is_empty():
			# A solo op, or nobody active. Clear rather than deploy_into([]),
			# which would warn about an empty roster that is empty on purpose.
			spawner.clear()
		else:
			var mustered := spawner.deploy_into(level, going)
			# Deferred so the bodies have finished being placed and grounded:
			# enter_downed() flattens a collider and settles a wreck, and doing
			# that to something still being seated reads as a robot falling over
			# on spawn.
			# THE CASUALTY IS STAGED ONCE PER CAMPAIGN, even though the five
			# objectives below are rebuilt until they are finished. Restaging on
			# every visit meant coming home from an operation re-broke you —
			# arriving at base heals you (TestCharacter._repair_at_base) and
			# this put you straight back on 35%, which test_endings caught as a
			# player who had survived a mission and was somehow still hurt.
			# An induction resumed with nobody on the floor is handled: the
			# revive objective completes itself rather than blocking.
			if stage_tutorial and _is_base(level) and not state.completed_tutorial \
					and state.mark_lesson(&"induction_triage"):
				_stage_first_tutorial.call_deferred(mustered)
	# Objectives filter themselves in _ready, but that runs before
	# debug_mission is adopted on a direct launch — and before current_mission
	# exists at all if anything loads the level out of band. Re-run it here,
	# where the mission is definitely known.
	_prune_inactive_objectives()

	# AFTER THE PRUNE, deliberately. _prune_inactive_objectives frees anything
	# the current mission does not name, and the induction's five are named by
	# no mission at all — built before it, they would be destroyed by it.
	_induction = null
	if _is_base(level):
		# Cleared whether or not a new one follows: the visit that FINISHES the
		# induction leaves five ticked objectives in the level, and the visit
		# after that has to arrive at an empty depot.
		_Induction.clear(level)
		if stage_tutorial and not state.completed_tutorial:
			_induction = _Induction.begin(self, level)
			# Deferred, and queued AFTER the casualty staging above so the robot
			# is already on the floor when "get your squadmate up" goes looking
			# for it. Arming is separate from staging because a resumed
			# induction stages nothing and still has to switch its objectives on.
			_arm_induction.call_deferred()

	# Opposition AFTER the player squad, so an EliminateObjective capturing
	# hostiles in a zone sees a fully populated map.
	if enemy_spawner != null and in_mission:
		enemy_spawner.deploy_force(level, current_mission)
	# After deploy: an EliminateObjective captures hostiles in its zone when it
	# activates, and the squad should already be in the world by then.
	if objectives != null:
		objectives.refresh()
	# Everyone is on the map now: the playtest log takes its squad snapshot.
	_Analytics.level_loaded()


# XP weighting is deliberate. SURVIVING is worth more than killing, because the
# pillar is that you care about these robots — if kills paid better, the correct
# play would be to push recklessly with them, which is the opposite game.
#
# Contribution is counted in KILLS rather than damage only because kills are
# what the body already tracks; damage dealt would be the better measure and is
# the natural upgrade when something records it.
const XP_SURVIVED := 25
const XP_PER_KILL := 6
const XP_MISSION_SUCCESS := 15


# Record -> [xp gained, rank before], for the debrief's cards.
var _xp_this_mission: Dictionary = {}


# Returns the soldiers who gained a rank, so the payout card can say so.
func _award_experience(success: bool) -> Array:
	var promoted: Array = []
	if state == null:
		return promoted
	# ONLY THE ONES WHO WENT. This walked the whole roster, so a robot left at
	# base — benched, or past a spawn point's slot count — was paid "survived"
	# XP for a mission it never saw, which is exactly backwards for the pillar
	# above. The spawner knows who had a body; with no spawner, nobody deployed.
	var went: Array[SoldierRecord] = spawner.deployed_records() if spawner != null else []
	for record in state.roster:
		if record == null or record.status == SoldierRecord.Status.DESTROYED:
			continue   # lost robots earn nothing; there is nobody to promote
		if not went.has(record):
			continue
		var before := record.rank
		var gained := XP_PER_KILL * record.confirmed_kills_this_mission
		gained += XP_SURVIVED
		if success:
			gained += XP_MISSION_SUCCESS
		record.add_xp(gained)
		_xp_this_mission[record] = [gained, before]
		if record.rank > before:
			promoted.append(record)
	return promoted


# Who went, and what each did: the debrief's cards. You first — kills only,
# since you have no rank — then every robot that had a body this mission, in
# roster order, with its XP and whether it came home.
func _debrief_squad() -> Array:
	var out: Array = []
	var you := state.player_record
	if you != null:
		out.append({"record": you, "player": true, "xp": 0, "rank_before": 0, "destroyed": false,
			"kills": you.confirmed_kills_this_mission, "kinds": you.kills_by_kind_this_mission.duplicate(),
			"revives": you.revives_this_mission, "team": state.team_of(you)})
	var went: Array = spawner.deployed_records() if spawner != null else []
	for r in state.roster:
		if r == null or not went.has(r):
			continue
		var xp: Array = _xp_this_mission.get(r, [0, r.rank])
		# The team it went in with, and who it stood back up: the debrief lists
		# the squad by team, and a Mechanic's whole mission is its revives.
		out.append({"record": r, "player": false, "xp": xp[0], "rank_before": xp[1],
			"destroyed": r.status == SoldierRecord.Status.DESTROYED,
			"kills": r.confirmed_kills_this_mission, "kinds": r.kills_by_kind_this_mission.duplicate(),
			"revives": r.revives_this_mission, "team": r.team_id})
	return out


## One of the DEBUG tab's switches, and false in anything that is not the
## editor whatever the file says.
##
## Checked HERE rather than only where the menu draws it. settings.json ships
## beside the executable and is plain text, so hiding the tab alone would leave
## "unlock everything" two lines away from anyone with a text editor. In an
## export those lines are inert.
func _debug_switch(key: String) -> bool:
	if not Settings.debug_tools_enabled():
		return false
	return bool(Settings.get_value(key))


## The operation that unlocks `id` (an item or a frame) while it is still
## locked; null when it isn't locked. Only what an operation lists in its
## `unlocks` is ever locked: everything else is simply available.
func locked_by(id: StringName) -> MissionDefinition:
	if state == null or id == &"" or state.unlocked.has(id):
		return null
	# THE ONE GATE, so the DEBUG switch only has to open this. The armourer, the
	# factory, the squad manager and the chassis holograms all ask this same
	# question, so opening it here opens weapons, frames, equipment and modules
	# together and nothing had to learn about the switch.
	#
	# `in_shop = false` is NOT affected and must not be: that is a thing taken
	# out of the player's game (the shotgun, the pistol), not a thing they have
	# yet to earn.
	if _debug_switch("debug.unlock_all_gear"):
		return null
	for m in missions:
		if m != null and m.unlocks.has(id):
			return m
	return null


# A save from before an operation unlocked something has cleared it without
# being given it. Hand those over quietly on load (loading must not save).
func _grant_owed_unlocks() -> void:
	for m in missions:
		if m == null or not state.completed_missions.has(m.id):
			continue
		for u in m.unlocks:
			if not state.unlocked.has(u):
				state.unlocked.append(u)


# Pulls the live player body's condition onto their record.
func _write_back_player() -> void:
	if state == null or state.player_record == null:
		return
	var body := get_tree().get_first_node_in_group("player")
	if body == null:
		# The player group is not guaranteed; fall back to the world's export.
		var world_node := get_parent()
		if world_node != null and "player" in world_node:
			body = world_node.player
	if body == null or not is_instance_valid(body):
		return
	var record := state.player_record
	if "max_health" in body and int(body.max_health) > 0:
		record.max_health = int(body.max_health)
	if "health" in body:
		record.damage = clampi(record.max_health - int(body.health), 0, record.max_health)
	if "confirmed_kills" in body:
		record.confirmed_kills += body.confirmed_kills
		record.confirmed_kills_this_mission = body.confirmed_kills
		body.confirmed_kills = 0
	if "kills_by_kind" in body:
		record.take_kills_by_kind(body.kills_by_kind)
	if "revives" in body:
		record.revives_this_mission = body.revives
		record.revives += body.revives
		body.revives = 0
	record.missions_survived += 1


# Success path. Collect the squad, pay out, save, and head home.
func extract(success: bool = true) -> Dictionary:
	var result := {"survivors": 0, "lost": 0, "reward": 0, "success": success, "seconds": seconds_this_mission}
	# The clock stops the moment the exit fires, not when the debrief closes.
	set_physics_process(false)
	# Before anything is paid: the debrief counts up from these.
	result["resources_before"] = state.available()
	result["compute_before"] = state.compute_free()
	# This mission's tallies start empty for everyone, so a robot that sat it
	# out never shows the last mission's kills.
	var everyone: Array = state.roster.duplicate()
	everyone.append(state.player_record)
	for r in everyone:
		if r != null:
			r.confirmed_kills_this_mission = 0
			r.kills_by_kind_this_mission = {}
	_xp_this_mission.clear()
	if spawner != null:
		var counts := spawner.write_back()
		result["survivors"] = counts["survivors"]
		result["lost"] = counts["lost"]

	# THE PLAYER IS A ROSTER ENTRY TOO, and nothing was writing their body back.
	# SquadSpawner only walks the squadmates it spawned, so the player's record
	# kept its starting health and zero kills no matter what happened in the
	# mission — which is why the management screen showed a pristine AKR-00
	# standing next to four dented squadmates.
	_write_back_player()

	# Veterancy. add_xp(), rank, rank_title() and every required_rank gate have
	# been implemented all along with NOTHING calling add_xp — so rank was
	# permanently 0 and every gate permanently shut. This is the missing call.
	result["ranked_up"] = _award_experience(success)

	# Bonus objectives pay out whether or not the mission itself succeeded —
	# you did the work, and withholding it makes players avoid optional content.
	var objective_reward := 0
	var compute := 0
	if objectives != null:
		objective_reward = objectives.earned_objective_rewards()
		state.award(objective_reward)
		# Compute objectives pay once per campaign, success or not — the same
		# "you did the work" rule as bonus resources, minus the farming.
		for o in objectives.earned_compute():
			var key := "%s:%s" % [String(current_mission.id) if current_mission != null else "", o["id"]]
			compute += state.claim_compute(key, int(o["compute"]))
	result["objective_reward"] = objective_reward

	# Salvage pays the same way: the wrecks were ground whether or not the
	# mission came off.
	var salvage := salvage_this_mission
	salvage_this_mission = 0
	state.award(salvage)
	result["salvage"] = salvage

	if success and current_mission != null:
		state.award(current_mission.reward_resources)
		result["reward"] = current_mission.reward_resources
		if not state.completed_missions.has(current_mission.id):
			state.completed_missions.append(current_mission.id)
		# FIRST clear only. Compute grows the squad; replaying the arena must
		# not be a way to buy an army. A claim rather than "was it completed",
		# so an op cleared before it paid anything still pays (on load).
		compute += state.claim_compute(CampaignState.clear_compute_key(current_mission.id),
			current_mission.compute_reward)
		# Separate from completed_missions because that array is a set: running
		# the arena a third time must not append a duplicate id, but it does
		# need to bump the counter the terminal reads.
		state.record_clear(current_mission.id)
		var newly: Array[StringName] = []
		for u in current_mission.unlocks:
			if not state.unlocked.has(u):
				state.unlocked.append(u)
				newly.append(u)
		result["unlocked"] = newly
		# THE END. Clearing the last operation wins the campaign, once: the
		# HUD follows MISSION COMPLETE with YOU WON, and from then on every
		# operation is open at the terminal to replay in any order.
		if is_final_mission(current_mission) and not state.campaign_won:
			state.campaign_won = true
			result["won"] = true

	state.award_compute(compute)
	result["compute"] = compute
	result["resources_after"] = state.available()
	result["squad"] = _debrief_squad()

	# ─────────────────────────────────────────────
	# A DEATH DOES NOT COUNT.
	#
	# Dying used to cost you the run AND the squad: five robots written off in
	# one bad push, with nothing to show for it, and the only way back was to
	# rebuild them. So a failed run is now VOIDED — the campaign goes back to
	# the dictionary taken at deployment, which is the same one save_to_disk
	# writes, so the roster, the stores, the armoury, the XP and the compute
	# are all exactly as you left base with. You lost the time, not the squad.
	#
	# The DEBRIEF still tells you what happened out there, wrecks and all: it
	# holds the record objects this run used, and those are discarded by the
	# restore rather than written back. What it must not do is claim you were
	# paid, so the payouts are zeroed here to match the state the player
	# actually goes home with.
	#
	# Nothing to restore (a level launched directly, no begin_deploy) means the
	# old behaviour, because there is no "before" to go back to.
	var rewound := not success and not _pre_run.is_empty()
	if rewound:
		state.restore_from(_pre_run)
		result["rewound"] = true
		result["reward"] = 0
		result["objective_reward"] = 0
		result["compute"] = 0
		result["resources_after"] = result["resources_before"]
		result["ranked_up"] = []
	_pre_run = {}

	extracted.emit(current_mission, result)
	in_mission = false
	# Home repaired, whatever happened out there — only the destroyed need a
	# rebuild. After extracted, so anything reading the mission's damage (the
	# playtest data) saw it first; before the save below, so it sticks.
	#
	# Skipped on a voided run: those records came back from the snapshot in the
	# state they deployed in, and healing them here would quietly rebuild a
	# wreck you are meant to pay for.
	if not rewound:
		state.heal_survivors()

	# Clear the selection HERE rather than in on_returned_to_base(), because
	# World calls _register_exits() — and therefore _push_destination() — before
	# on_returned_to_base(). Clearing later would leave the train at base still
	# pointed at the operation you just came back from.
	state.selected_mission_id = &""

	if autosave:
		state.save_to_disk()
	return result


# The player died, or withdrew. Same collection, no rewards, no completion.
func abort() -> Dictionary:
	return extract(false)


func on_returned_to_base() -> void:
	current_mission = null
	in_mission = false
	# Belt and braces: if anything reached base without going through extract()
	# — a debug jump, a future abort path — the train still comes back blank.
	state.selected_mission_id = &""
	_push_destination()
	# Home. Everyone rearms — the squad from their records, the player through
	# the returned_to_base signal their loadout listens for.
	state.restock_roster()
	if autosave:
		state.save_to_disk()
	if spawner != null:
		spawner.clear()
	if objectives != null:
		objectives.clear()
	if enemy_spawner != null:
		enemy_spawner.clear()
	returned_to_base.emit()


func save() -> void:
	state.save_to_disk()
