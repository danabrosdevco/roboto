extends Node3D
class_name MissionObjective

# ─────────────────────────────────────────────
# MISSION OBJECTIVE — a thing that must happen for the mission to succeed.
#
# NOT THE SAME AS SquadObjectivePoint. That marks a place you can order a squad
# to; this marks something the mission requires. Conflating them would make
# every tactical waypoint a win condition, and would mean you could never have
# an objective that isn't a place — hold for 90 seconds, destroy three relays,
# get everyone out alive.
#
# They do often sit together, so `linked_squad_point` lets one objective expose
# an ordering target without the two becoming the same object.
#
# Subclasses decide WHEN complete() fires. This base owns the rest: activation,
# prerequisites, optional-vs-required, and the signals the tracker and HUD read.
# ─────────────────────────────────────────────

@export var id: StringName = &""
@export var display_name: String = "Objective"
@export_multiline var description: String = ""

# Bonus objectives don't gate extraction.
@export var optional: bool = false

# ─────────────────────────────────────────────
# NEITHER OF THE TWO BELOW IS PAID ANY MORE (decided 2026-10-23, Backlog K9).
#
# Objectives used to pay in both currencies on extraction — around 9,500
# resources and 10 compute authored across the operations, which was the
# largest income in the game. CONTROL PAYS now, and only control: held sites
# per turn, and the compute of held Locations.
#
# LEFT IN THE DATA ON PURPOSE. Stripping them would mean editing nineteen
# .tres files for a number nothing reads, and the enum-and-scene rule here is
# that authored values are not churned for tidiness. extract() no longer asks.
# If objectives are ever meant to pay again, this is where the figures still
# are — they are not lost, just unread.
# ─────────────────────────────────────────────
@export var reward_resources: int = 0
@export var compute_reward: int = 0

# Optional ordering target so you can send a squad to this objective.
@export var linked_squad_point: SquadObjectivePoint

# Hidden/inert until its prerequisites complete. A false here with no
# prerequisites means something else has to call activate().
@export var starts_active: bool = true
@export var prerequisites: Array[MissionObjective] = []

# Marks this as the one that ends the mission. MissionExit doesn't need it —
# it checks all required objectives — but the HUD wants to say "EXTRACT".
@export var is_extraction: bool = false

var completed: bool = false
var failed: bool = false
var active: bool = false

signal objective_activated(objective: MissionObjective)
signal objective_completed(objective: MissionObjective)
signal objective_failed(objective: MissionObjective)
# Emitted by the subclasses (interact/eliminate/reach), connected by
# ObjectiveTracker. The base class never emits it itself.
@warning_ignore("unused_signal")
signal progress_changed(objective: MissionObjective, current: int, target: int)


func _ready() -> void:
	# Switched off for operations that don't want it. The level holds every
	# objective it could ever need; the mission picks a subset. Freed rather
	# than hidden so the tracker never counts it and its props go with it.
	var campaign := _find_campaign()
	if campaign != null and id != &"" and not campaign.is_objective_active(id):
		queue_free()
		return

	# AN OBJECTIVE WITH NO ID CANNOT BE ASKED FOR, AND IS THEREFORE NEVER
	# DROPPED. `active_objectives` names ids, so a blank one can never appear
	# in it — which is exactly why the line above exempts it, and exactly why
	# a blank one then runs in EVERY operation on this level.
	#
	# That is right for the capture-point PREFABS, which ship blank and have
	# an id authored on each instance. It is wrong for anything else, and the
	# one time it happened the HUD counted 0/3 while listing four, with a
	# fourth line reading CAPTURE THE OBJECTIVE that nothing could ever tick.
	# It is not freed here — on those prefabs the script is on the root and
	# freeing it would take the art with it — so it says so instead.
	if campaign != null and id == &"":
		push_warning(("MissionObjective '%s' has no id, so no operation can ask for it and nothing "
			+ "will prune it: it will run in every operation on this level. Author an id on the "
			+ "instance, or have whatever adopted it stand it down. Node: %s") % [name, get_path()])

	add_to_group("mission_objectives")
	for prereq in prerequisites:
		if prereq != null:
			prereq.objective_completed.connect(_on_prerequisite_completed)
	if starts_active and _prerequisites_met():
		activate()
	_on_objective_ready()


# Subclass hook. Use this instead of overriding _ready so the registration and
# prerequisite wiring above can't be accidentally skipped.
func _on_objective_ready() -> void:
	pass


func _prerequisites_met() -> bool:
	for prereq in prerequisites:
		if prereq != null and not prereq.completed:
			return false
	return true


func _on_prerequisite_completed(_objective: MissionObjective) -> void:
	if not active and not completed and _prerequisites_met():
		activate()


func activate() -> void:
	if active or completed:
		return
	active = true
	if linked_squad_point != null:
		linked_squad_point.visible = true
	objective_activated.emit(self)
	_on_activated()


func _on_activated() -> void:
	pass


func complete() -> void:
	if completed or failed:
		return
	completed = true
	active = false
	objective_completed.emit(self)
	_on_completed()


func _on_completed() -> void:
	pass


func fail() -> void:
	if completed or failed:
		return
	failed = true
	active = false
	objective_failed.emit(self)


# [current, target] for the HUD. Override where a count makes sense.
func progress() -> Array:
	return [1 if completed else 0, 1]


func counts_toward_extraction() -> bool:
	return not optional and not is_extraction


# ─────────────────────────────────────────────
# LABELLING
# What the HUD and the interact prompt call this objective.
#
# display_name names the PLACE ("Garrison"). On its own that doesn't tell the
# player what to do with it, and an objective whose display_name was never
# authored fell back to the literal word "Objective", which told them nothing at
# all. The verb supplies the action, so a level author only has to name the
# thing: "Garrison" becomes CAPTURE GARRISON, and an unnamed extraction point
# reads EXTRACT instead of OBJECTIVE.
# ─────────────────────────────────────────────
const DEFAULT_DISPLAY_NAME := "Objective"


# Subclasses override. Empty means "no verb", and label() falls back to the name.
func verb() -> String:
	return ""


func has_authored_name() -> bool:
	return display_name != "" and display_name != DEFAULT_DISPLAY_NAME


func label() -> String:
	var action := verb()
	if action == "":
		return display_name if has_authored_name() else DEFAULT_DISPLAY_NAME
	if has_authored_name():
		return "%s %s" % [action, _without_doubled_article(action, display_name)]
	return action


# "Capture the" + "The Cistern" rendered "Capture the The Cistern" on the HUD —
# on 23 of the 99 authored objectives, which is nearly every InteractObjective
# in the game, because a place in this world is usually named with its article.
#
# BOTH HALVES ARE RIGHT AND ONLY THE JOIN IS WRONG. The verb carries the
# article deliberately (see interact_objective.verb(): without it, CAPTURE WEST
# GARRISON read as a telegram) and a level author names the place as the place
# is called. So this collapses the join rather than renaming authored content
# across eleven level scenes.
#
# WHICH ARTICLE SURVIVES IS NOT A CASE QUESTION. The list is rendered through a
# display font with no lowercase glyphs — a shot of mutaha_wip reads CAPTURE
# THE GATEHOUSE RELAY, though nothing in objective_hud.gd calls to_upper() on
# the row. The verb's article is kept because the verb is the half this file
# owns; the name is the level author's and is returned to them untouched.
#
# Backlog K10. Measured by tools/probe_objective_labels.gd, which composes
# every authored objective's real label() without instantiating a level.
func _without_doubled_article(action: String, name_text: String) -> String:
	var low := action.to_lower()
	for article in ["the", "a", "an"]:
		# The trailing space matters: a name that is only the bare word "The"
		# is left alone, and so is "Anchor" against the article "an".
		if low.ends_with(" " + article) and name_text.to_lower().begins_with(article + " "):
			return name_text.substr(article.length() + 1)
	return name_text


# Finds the campaign however it's wired: a node in the "campaign" group (the
# reliable way), a /root/Campaign autoload, or a parent's Campaign export.
#
# This file was still hard-coded to the autoload path. There is no autoload in
# this project — CampaignManager is a node under World — so `campaign` was
# always null, the active_objectives filter never ran, and EVERY objective in
# the level survived regardless of which mission you were on.
func _find_campaign() -> Node:
	var found := get_tree().get_first_node_in_group("campaign")
	if found != null:
		return found
	found = get_node_or_null("/root/Campaign")
	if found != null:
		return found
	var node: Node = self
	while node != null:
		if "Campaign" in node and node.get("Campaign") != null:
			return node.get("Campaign")
		node = node.get_parent()
	return null
