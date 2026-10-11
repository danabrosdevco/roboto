extends Node
class_name SquadCommander

# ─────────────────────────────────────────────
# SQUAD COMMANDER
# Child of Player. Owns the "command" input (T) and everything downstream of it.
#
# TAP T    — ADVANCE to the crosshair and hold, whatever is under it: ground,
#            one of your robots or a hostile (a hive included) all mean "go
#            there", to the ground it stands on. The tap never picks a team or
#            a target — G picks the team, and the squad fights what it meets.
#            Open sky → CONTACT callout down the sightline.
# HOLD T   — FOLLOW. Fires the moment the hold threshold passes.
# G        — switch the team T orders to the next one.
#
# TEAMS
# Your robots go in as one squad per team you made on the squad page, so a
# rover can hold a ridge while the rest follow you in. Orders go to one team at
# a time, your first to start with, and G steps to the next in the page's order
# and round again: no ALL to step through, so with two teams a switch is always
# one press. With one team nothing is different. (Cycling used to hang off Tab,
# which the squad manager takes first; it never fired.)
#
# WHY THREE VERBS
# The wheel used to carry MOVE TO / DEFEND / ATTACK / FALL BACK / CONTACT. Those
# weren't five orders, they were two questions collapsed into one list: WHERE
# and HOW. The aim point already answers WHERE in every case, so the verb only
# ever had to answer HOW.
#   ASSAULT at ground   = the old MOVE TO
#   ASSAULT at a hostile = the old ATTACK
#   DEFEND at a point behind you = the old FALL BACK
# CONTACT came off the wheel entirely — it isn't a posture, it's a report, and
# it needs to be instant. By the time you have held, scrubbed and released, the
# thing you spotted has moved. It is the TAP now.
#
# The old CommandMarker did a 600m physics sphere sweep every press to work out
# who should listen. That's replaced: the commander already knows which squad is
# selected, so it calls squad.receive_player_order() directly. The marker is now
# purely a visual.
# ─────────────────────────────────────────────

@export var player: Player
@export var cam: Camera3D
@export var world: Node3D
@export var hud: Control
@export var marker_scene: PackedScene

@export var ray_length: float = 500.0
# Layer 1 is level geometry. Widen this if your AI bodies sit on another layer —
# the commander needs to hit robots as well as terrain to infer intent.
@export var command_ray_mask: int = 0xFFFFFFFF

@export var hold_threshold: float = 0.22

# How often the squad registry is rebuilt. It used to be built exactly once in
# _ready(), so a squad that spawned later never became commandable and a wiped
# one stayed in the cycle list forever.
@export var registry_refresh_interval: float = 2.0

# ASSAULT is gone. "Go there and engage what you meet on the way" meant the
# squad self-directed mid-order, and self-direction is where almost every
# problem came from — chasing corpses, closing into shotgun range, stringing
# into a line, slipping the leash.
#
# ADVANCE is the old DEFEND behaviour under a better name: go there, hold, dig
# in. Taking ground becomes a sequence of orders you issue rather than a
# judgement call the AI gets wrong. Bounding a squad forward is now YOUR job,
# which is the whole appeal of a squad game.
enum Verb { ADVANCE, FOLLOW, CONTACT, ATTACK }

const VERB_LABELS := {
	Verb.ADVANCE: "ADVANCE",
	Verb.FOLLOW:  "FOLLOW",
	Verb.CONTACT: "CONTACT",
	Verb.ATTACK:  "ATTACK",
}

const SWITCH_TEAM_ACTION := &"switch_team"

## The two movement orders, as dial entries. Pseudo item ids, with a prefix no
## catalogue item can collide with: the dial carries equipment and these side by
## side, and the designator should not have to care which it is holding.
const MODE_ADVANCE := &"@advance"
const MODE_FOLLOW := &"@follow"

## Turns an equipment slot's item id back into its catalogue entry, for the
## designator's dial. By path: hud_glyphs.gd has no class_name.
const _Glyphs := preload("res://Character/hud/hud_glyphs.gd")

var commandable_squads: Array[Squad] = []
var selected_index: int = 0

var _hold_time: float = 0.0
# True once a hold has already issued FOLLOW, so releasing does not then also
# fire a tap order on the way out.
var _hold_fired: bool = false
var _markers: Dictionary = {}   # Squad -> CommandMarker
var _preview: CommandMarker = null
## The designated point, kept apart from the per-squad objective markers above.
## One at a time and NOT keyed by squad: designating smoke must not wipe the
## ADVANCE mark the squad is still walking toward.
var _equipment_marker: Node3D = null

# WHAT EACH SQUAD BROUGHT, kept for the mission. Squad -> {item_id: entry}.
#
# The dial used to be rebuilt from the living members' slots every time it was
# read, so it SHRANK as the mission went on: a carrier dying took its item off
# the dial, and the last Cluster Mine being thrown took the Cluster Mine with
# it. That makes the designator feel like it has ammo. It has none. The squad
# has ammo; the designator is a radio.
#
# So entries are added and never removed while the squad lives. An item the
# squad is out of stays on the dial saying so, which is information. An item
# that vanishes is just a tool that got smaller.
var _dials: Dictionary = {}

# ── A HELD ORDER ──────────────────────────────
# "RELOADING" IS NOT A REFUSAL, IT IS A WAIT. Every robot that carries the item
# is between uses — which, with the squad's own spacing rule in play, is most of
# the few seconds after anyone threw anything. Telling the player no and making
# them press again in four seconds is asking them to poll the squad; the order
# was perfectly good, it was just early.
#
# So an order that fails ONLY for timing is held and retried. The three refusals
# that are not about timing — nobody carrying it, nobody with one left, and out
# of throw range — are still refused immediately, because none of them resolves
# by waiting and a queue that never fires is worse than a no.
#
# ONE AT A TIME. A second designation replaces the first rather than stacking:
# the player pointing somewhere new has changed their mind, and a squad that
# answers a mark from fifteen seconds ago is answering a fight that has moved.
var _queued: Dictionary = {}
var _queue_retry: float = 0.0
## How often a held order asks again. Equipment cooldowns are whole seconds, so
## polling faster than this only burns the check.
@export var queue_retry_interval: float = 0.4
## How long it is held before it is given up on, out loud. Long enough to cover
## a smoke cooldown (16 s) plus the squad spacing, short enough that an order
## cannot fire into a fight that has long since moved.
@export var queue_timeout: float = 20.0
var _registry_timer: float = 0.0

signal squad_selected(squad: Squad)
signal squads_refreshed(squads: Array)
signal order_issued(squad: Squad, verb: int, position: Vector3, target: Node)
signal contact_called(position: Vector3, target: Node)
## Which team the orders now go to changed: the team's name — or a callsign.
signal team_selected(label: String)
## G with no other team in the field to switch to.
signal no_team_to_switch
## The squad spent kit because the player told it to: what, and how many robots
## answered. Separate from `order_issued` because it is not a posture change —
## nothing about where the squad is standing or what it is holding has altered.
signal equipment_ordered(squad: Squad, label: String, count: int)
## ...and the other half, which matters more. A designator press that quietly
## does nothing reads as a broken key, so every refusal has a reason and the
## reason goes on screen.
signal equipment_refused(reason: String)
## Nobody could answer YET, so the order is being held. See `_queued`.
signal equipment_queued(label: String)


func _ready() -> void:
	_autowire()
	# Settings registers G for this when it loads the bindings; whichever of us
	# is first makes it, so the key works before anyone opens the options.
	if not InputMap.has_action(SWITCH_TEAM_ACTION):
		InputMap.add_action(SWITCH_TEAM_ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_G
		InputMap.action_add_event(SWITCH_TEAM_ACTION, ev)
	# Squads add themselves to the group in their own _ready, which may not have
	# run yet. Wait a frame before the first sweep.
	await get_tree().process_frame
	refresh_squads()


# Teams are made and emptied on the squad page, which pauses the game while it
# is open. Sweep on the first frame after, rather than up to two seconds later:
# a team you just made has to be on G the moment you are back.
func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED:
		_registry_timer = registry_refresh_interval


# `world` and `hud` are not set in test_character.tscn. _place_marker() bails on
# `world == null` and _call_contact() skips the enemy marker on `hud == null`,
# which is the whole reason no marker ever appeared at the aim point. Player
# already holds both references, so take them from there rather than relying on
# the inspector.
func _autowire() -> void:
	if player == null:
		player = get_parent() as Player
	if player == null:
		return
	if cam == null:
		cam = player.cam
	if world == null:
		world = player.world
	if hud == null:
		hud = player.hud
	if marker_scene == null:
		marker_scene = player.command_marker_scene


# ─────────────────────────────────────────────
# SQUAD REGISTRY
# ─────────────────────────────────────────────
func refresh_squads() -> void:
	commandable_squads.clear()
	for s in get_tree().get_nodes_in_group("squads"):
		if not s is Squad:
			continue
		var squad := s as Squad
		# is_lost(), not is_wiped(): an all-downed squad is recoverable and must
		# stay commandable so its markers keep drawing.
		if squad.is_lost():
			continue
		if squad.player_commandable or _is_friendly_squad(squad):
			commandable_squads.append(squad)
	selected_index = clampi(selected_index, 0, maxi(0, commandable_squads.size() - 1))
	# Your first team, not whichever squad the group happened to list first.
	var teams := team_squads()
	if not teams.is_empty() and not teams.has(get_selected_squad()):
		selected_index = commandable_squads.find(teams[0])
	squads_refreshed.emit(commandable_squads)
	squad_selected.emit(get_selected_squad())


func _is_friendly_squad(squad: Squad) -> bool:
	for m in squad.get_living_members():
		return not Enums.are_hostile(Enums.Factions.PLAYER, m.faction)
	return false


# This node extends Node, which has no get_world_3d(). Borrow the player's —
# it's a CharacterBody3D and always lives in the same 3D world we care about.
func _space() -> PhysicsDirectSpaceState3D:
	return player.get_world_3d().direct_space_state


func get_selected_squad() -> Squad:
	if commandable_squads.is_empty():
		return null
	if selected_index >= commandable_squads.size():
		selected_index = 0
	var squad = commandable_squads[selected_index]
	# A level unload frees its squads before the registry's next sweep (up to
	# registry_refresh_interval later) takes them out of the list.
	if not is_instance_valid(squad):
		return null
	return squad


func cycle_squad(dir: int = 1) -> void:
	if commandable_squads.size() <= 1:
		return
	selected_index = wrapi(selected_index + dir, 0, commandable_squads.size())
	_refresh_marker_dimming()
	squad_selected.emit(get_selected_squad())


# ─────────────────────────────────────────────
# TEAMS
# ─────────────────────────────────────────────
## Your own squads, in the squad page's order: the teams SquadSpawner deployed.
func team_squads() -> Array[Squad]:
	var out: Array[Squad] = []
	for squad in commandable_squads:
		if not is_instance_valid(squad):
			continue
		if squad.player_commandable and squad.team != &"":
			out.append(squad)
	out.sort_custom(func(a: Squad, b: Squad) -> bool: return a.team_rank < b.team_rank)
	return out


## More than one team in the field — the only time there is anything to choose,
## and the only time the HUD says who the orders are for.
func has_teams() -> bool:
	return team_squads().size() > 1


## The team's name — or a callsign, for someone else's squad you are ordering.
func selection_label() -> String:
	var squad := get_selected_squad()
	return squad.team_name() if squad != null else "NOBODY"


## G: the next team, and round from the last to the first. From someone else's
## squad, back to your first. In a level whose squads were placed by hand rather
## than deployed as teams, it steps through those squads instead — the job Tab
## was meant to do.
func cycle_team() -> void:
	var teams := team_squads()
	if teams.is_empty() and commandable_squads.size() > 1:
		cycle_squad(1)
		return
	var at := teams.find(get_selected_squad())
	if teams.is_empty() or (teams.size() == 1 and at == 0):
		# Nothing to switch between. Said on the HUD rather than the key doing
		# nothing, which reads as a broken binding.
		no_team_to_switch.emit()
		return
	var next: Squad = teams[(at + 1) % teams.size()] if at >= 0 else teams[0]
	selected_index = commandable_squads.find(next)
	_refresh_marker_dimming()
	squad_selected.emit(next)
	team_selected.emit(selection_label())


# Squads within radius of the player, for the "squads around you" HUD readout.
# Nearest first. Group order is arbitrary and stable, so an unsorted list meant
# that whenever there were more squads in range than the HUD could show, the
# visible ones were an arbitrary fixed subset — the strip looked frozen while
# you walked past squads it never mentioned. Sorting makes the cut meaningful:
# whatever gets dropped is always the furthest away.
func get_nearby_squads(radius: float = 120.0) -> Array:
	var result: Array = []
	if player == null:
		return result
	var origin := player.global_position
	for s in get_tree().get_nodes_in_group("squads"):
		if not s is Squad:
			continue
		var squad := s as Squad
		if squad.is_wiped():
			continue
		if origin.distance_to(squad.get_center()) <= radius:
			result.append(squad)
	result.sort_custom(func(a: Squad, b: Squad) -> bool:
		return origin.distance_squared_to(a.get_center()) < origin.distance_squared_to(b.get_center()))
	return result


# ─────────────────────────────────────────────
# INPUT
# ─────────────────────────────────────────────

func _process(delta: float) -> void:
	_tick_link(delta)
	if player == null or not player.alive:
		return

	# A held equipment order asks again. Costs one `is_empty()` when there is
	# nothing waiting, which is almost always.
	_tick_queued_order(delta)

	_registry_timer += delta
	if _registry_timer >= registry_refresh_interval:
		_registry_timer = 0.0
		_refresh_registry_quietly()

	if Input.is_action_just_pressed(SWITCH_TEAM_ACTION):
		cycle_team()

	if Input.is_action_pressed("command"):
		_hold_time += delta
		# HOLD IS FOLLOW, and it fires the moment the threshold is crossed
		# rather than waiting for release. There is nothing left to choose —
		# the wheel offered exactly two verbs and ADVANCE is already the tap —
		# so holding for a decision you are not making is dead latency. "Come
		# to me" should land when you ask for it.
		if not _hold_fired and _hold_time >= hold_threshold:
			_hold_fired = true
			_issue_order(Verb.FOLLOW)
		return

	if Input.is_action_just_released("command") or (_hold_time > 0.0 and not Input.is_action_pressed("command")):
		# Released before the threshold: it was a tap, and the verb comes from
		# whatever the crosshair is on.
		if not _hold_fired and _hold_time > 0.0:
			_issue_contextual_order()
		_hold_time = 0.0
		_hold_fired = false


# CONTACT is deliberately absent — it's the tap, not a wheel entry.
# ─────────────────────────────────────────────
# AIM RESOLUTION
# One raycast, then branch on what it hit. The old version masked to layer 1
# only, which is why it could never resolve anything but terrain.
# ─────────────────────────────────────────────
func _aim_result() -> Dictionary:
	if cam == null or player == null:
		return {}
	var origin := cam.global_position
	var end := origin + (-cam.global_transform.basis.z * ray_length)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collide_with_areas = false
	query.collision_mask = command_ray_mask
	query.exclude = [player.get_rid()]
	return _space().intersect_ray(query)


func _issue_contextual_order() -> void:
	var hit := _aim_result()

	if hit.is_empty():
		# Looking at open sky. Treat as a callout down the sightline.
		var far_point = cam.global_position + (-cam.global_transform.basis.z * 60.0)
		_call_contact(far_point, null)
		return

	# ADVANCE, WHATEVER IS UNDER THE CROSSHAIR. One of your robots used to switch
	# the orders to its team, and a hostile (a hive included) got a callout, or
	# a vehicle team sent at it, instead of the move you asked for: a unit in
	# the way of where you were pointing hijacked the order. Aimed at a body,
	# "there" is the ground it stands on, not the point on its chest.
	var pos: Vector3 = hit.position
	var collider = hit.get("collider")
	if collider is CharacterBody3D or collider is RigidBody3D:
		pos = _snap_to_ground(pos)
	_issue_order(Verb.ADVANCE, pos)


func _issue_order(verb: int, position = null, target: Node = null) -> void:
	# Silent here: the dial and equipment paths announce the refusal, and this
	# is also reached by the contextual key, which would spam it.
	if link_down():
		return
	var squad := get_selected_squad()
	if squad == null:
		return

	# Resolve a position if the caller didn't supply one (hold, and the old
	# wheel path).
	var pos: Vector3
	if position == null:
		var hit := _aim_result()
		pos = player.global_position if hit.is_empty() else hit.position
	else:
		pos = position

	# EVERY VERB PAYS. Before the match, so CONTACT and FOLLOW — both of which
	# return early below — are charged exactly like ADVANCE. A callout is a
	# transmission; so is telling the squad to come with you.
	#
	# AFTER the position is resolved, though, because an ADVANCE is a DIRECTED
	# transmission and the direction is the point it is ordered at.
	_transmit(verb, pos)

	match verb:
		Verb.CONTACT:
			# A report for everyone in earshot, never an order: no team is sent
			# at anything by it.
			_call_contact(pos, target)
			return
		Verb.ADVANCE:
			# Maps to SquadObjective.DEFEND — go there and hold. The enum keeps
			# ADVANCE and ATTACK because EnemySquadSpec.Posture still uses them
			# for garrisons and patrols; enemies genuinely should push. Only the
			# PLAYER's vocabulary shrank.
			squad.receive_player_order(Squad.SquadObjective.DEFEND, pos)
		Verb.FOLLOW:
			# No world position to mark — the objective is a moving node. Clear
			# any standing marker so the map doesn't still show an objective the
			# squad has been pulled off.
			squad.follow(player)
			_clear_marker(squad)
			order_issued.emit(squad, verb, player.global_position, player)
			return

	_place_marker(squad, verb, pos)
	_refresh_marker_dimming()
	order_issued.emit(squad, verb, pos, target)


# ─────────────────────────────────────────────
# CONTACT CALLOUT
# Rides the existing StimulusManager. Note the faction: emit_stimulus filters
# on `ai.faction != emitting_faction`, and your friendly robots are ALLIED, not
# PLAYER — emitting as PLAYER would reach nobody.
# ─────────────────────────────────────────────
func _call_contact(position: Vector3, target: Node) -> void:
	# NOTE: Player has no ai_manager property (that lives on Enemy), so this
	# resolves through World, which exports one.
	var sm: StimulusManager = _get_stimulus_manager()

	if sm != null:
		sm.emit_stimulus(
			StimulusManager.StimulusType.ENEMY_SPOTTED,
			position,
			Enums.Factions.ALLIED,
			target,
			45.0)

	# AND A DESIGNATION, which is the half the stimulus cannot carry. The bus is
	# fire-and-forget, so it tells whoever is in earshot right now and remembers
	# nothing; the contact table holds the mark for as long as the HUD shows it.
	# A patient weapon reads that and swings onto it — a report that becomes a
	# fire mission without ever being an order.
	var mgr = _get_ai_manager()
	if mgr != null and target != null:
		mgr.designate(Enums.Factions.ALLIED, target, CONTACT_MARKER_SECONDS)

	# Reuse the scanner's existing world-space marker for the visual.
	#
	# TWO KINDS, AND THE SECOND ONE IS MOST OF THEM. A contact with a live body
	# behind it gets the scanner's tracking mark. A contact called at a PLACE —
	# which is the common case, and which produced nothing visible at all until
	# now — gets the same mark pinned to the ground with the age of the report
	# counting up beside it.
	#
	# Both go through the HUD, which refuses either when the uplink is too poor
	# to carry a report. See Hud.mark_contact.
	if hud != null:
		if target is Node3D and hud.has_method("activate_enemy_marker"):
			hud.activate_enemy_marker(target, CONTACT_MARKER_SECONDS)
		elif hud.has_method("mark_contact"):
			# Faction from the reported body when there is one; a report called at
			# bare ground has no identity and falls back to hostile.
			var fac = Enums.Factions.ENEMY
			if target != null and "faction" in target:
				fac = target.faction
			hud.mark_contact(position, CONTACT_MARKER_SECONDS, player, fac)

	contact_called.emit(position, target)


# ─────────────────────────────────────────────
# AIM PREVIEW — the marker you see while the wheel is open
# ─────────────────────────────────────────────
# Returns the world point currently under the crosshair, or a point 60m down
# the sightline when the ray hits nothing.
func get_aim_point() -> Vector3:
	var hit := _aim_result()
	if hit.is_empty():
		if cam == null:
			return Vector3.ZERO
		return cam.global_position + (-cam.global_transform.basis.z * 60.0)
	return hit.position


## GHOST THE ORDER WHERE IT WILL LAND, while the designator is being held.
##
## The hold is a second and a half of commitment, and until now the only thing
## telling you where it would go was the crosshair — which on a cluttered map
## tells you which PIXEL you are pointing at and not which patch of ground that
## resolves to. The mark can be a long way from where you thought: it snaps to
## the ground, and aiming at a body puts it at that body's feet.
##
## So the ghost goes down at the first frame of the hold and tracks the
## crosshair the whole way, which turns the hold from a wait into an aim.
##
## It reuses the preview CommandMarker the old command wheel used to show while
## it was open. That code had been orphaned since the wheel was removed —
## _update_preview was reachable only from _spawn_preview and vice versa — so
## this is the same idea put back to work rather than a second ghost marker.
func show_mark_preview(pos: Vector3, label: String) -> void:
	_spawn_preview()
	if _preview == null or not is_instance_valid(_preview):
		return
	_preview.global_position = _snap_to_ground(pos)
	_preview.set_order(Verb.CONTACT, label.to_upper())


## Take it away again. Called on release whether the hold completed or not: an
## aborted designation must not leave a mark on the ground suggesting an order
## that was never given.
func clear_mark_preview() -> void:
	_clear_preview()


func _spawn_preview() -> void:
	if marker_scene == null or world == null:
		return
	if _preview != null and is_instance_valid(_preview):
		return
	_preview = marker_scene.instantiate() as CommandMarker
	if _preview == null:
		push_warning("SquadCommander: marker_scene is not a CommandMarker.")
		return
	_preview.preview = true
	world.add_child(_preview)
	_update_preview()


func _update_preview() -> void:
	if _preview == null or not is_instance_valid(_preview):
		_spawn_preview()
		if _preview == null:
			return
	# The preview only ever shows ADVANCE now. FOLLOW fires the instant the hold
	# threshold passes and drops its own marker through _place_marker, so there
	# is nothing to preview for it — you are not choosing between two things any
	# more, so there is no decision to show you first.
	_preview.global_position = _snap_to_ground(get_aim_point())
	_preview.set_order(Verb.ADVANCE, str(VERB_LABELS.get(Verb.ADVANCE, "")))


func _clear_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null


# Rebuild the registry without firing squad_selected, so the HUD doesn't toast
# "COMMANDING X" twice a second.
func _refresh_registry_quietly() -> void:
	var previous := get_selected_squad()
	commandable_squads.clear()
	for s in get_tree().get_nodes_in_group("squads"):
		if not s is Squad:
			continue
		var squad := s as Squad
		# is_lost(), not is_wiped(). This runs every 2s, so it was the one that
		# actually dropped your squad mid-fight once the last member went down.
		if squad.is_lost():
			continue
		if squad.player_commandable or _is_friendly_squad(squad):
			commandable_squads.append(squad)
	if previous != null and commandable_squads.has(previous):
		selected_index = commandable_squads.find(previous)
	else:
		# The team you had picked is gone — a new mission, or it was wiped.
		# Orders go to your first team rather than to whatever slid into its slot.
		var teams := team_squads()
		if not teams.is_empty():
			selected_index = commandable_squads.find(teams[0])
		else:
			selected_index = clampi(selected_index, 0, maxi(0, commandable_squads.size() - 1))
		if get_selected_squad() != previous:
			squad_selected.emit(get_selected_squad())
			team_selected.emit(selection_label())
	# Markers sit in the World, which outlives every level: one whose squad is
	# gone (the last mission's, a wiped team) comes down with it. Untyped keys,
	# because a freed squad cannot be passed to _clear_marker(squad: Squad).
	for key in _markers.keys():
		if is_instance_valid(key) and commandable_squads.has(key):
			continue
		var marker = _markers[key]
		if marker != null and is_instance_valid(marker):
			marker.queue_free()
		_markers.erase(key)
	_refresh_marker_dimming()


# ─────────────────────────────────────────────
# MARKERS — one per squad, moved rather than respawned
# ─────────────────────────────────────────────
# ─────────────────────────────────────────────
# TRANSMITTING MAKES YOU LOUD
#
# The player's one irreplaceable verb is "tell the squad what to do", and
# until now it was free. Free in a game about a sensor war is the wrong price:
# the whole fiction is that you are a signal in a world of things listening
# for signals, and you were the only thing on the map that could broadcast
# without consequence.
#
# THREE THINGS HAPPEN WHEN YOU KEY THE RADIO.
#
#   1. A wavefront leaves you and runs out across the ground, visible, at a
#      speed you can read. See TransmitPing.
#   2. It costs you integrity. You are emitting instead of listening, and the
#      cost is small enough to ignore once and expensive enough to notice when
#      you micromanage — which is exactly the behaviour it is there to price.
#   3. Everything hostile the front reaches is told where you are, AS IT
#      ARRIVES. Not instantly: the thing on the far ridge finds out last.
#
# NO NEW STIMULUS TYPE. StimulusType is an enum and enums here are append-only;
# more to the point, ENEMY_SPOTTED already means exactly this — "a hostile is
# at this position" — and what the receivers do with it is already tuned. A
# TRANSMISSION_HEARD that behaved identically would be a second name for a
# thing we have.
# ─────────────────────────────────────────────

@export_group("Transmission")
## Metres a routine order carries. Anything hostile with a live receiver
## inside this learns your bearing as the front reaches it.
@export var tx_radius: float = 45.0
## Seconds for the front to run out to tx_radius.
@export var tx_travel: float = 0.9
## What keying the radio costs your own integrity. 0.06 is about a second and
## a half of passive recovery (0.04/s): one order is nothing, a dozen inside a
## firefight walks you down a band.
@export var tx_signal_cost: float = 0.06
## The carrier's colour. Player signal cyan — see HUDPalette.SIGNAL.
const TX_COLOUR := Color(0.40, 0.78, 0.95)
## By path, not by class_name: see the note on TransmitPing.fire.
const _PING := preload("res://Character/components/transmit_ping.gd")

## Emitted for every order, with how many hostile receivers were in reach.
## Nothing listens yet; it is here so a readout, a bark or a threat meter can
## be hung off the transmission without reaching back into this function.
signal transmitted(origin: Vector3, reach: float, receivers: int)


# ─────────────────────────────────────────────
# TWO SHAPES OF TRANSMISSION, because they are two different messages.
#
# FOLLOW and CONTACT have no bearing in them. "Come with me" and "there is
# something there" are addressed to the squad wherever it is, so they go out
# as a circle: everything in reach, in every direction.
#
# ADVANCE HAS A BEARING. "Go to that spot" is aimed, so the set is aimed with
# it — a lobe of a wave running out along the line you pointed down, rather
# than a ring that happens to pass over it.
#
# AND THE SET BEING AIMED IS NOT FREE. What is inside the lobe hears you and
# what is behind you does not, which makes WHERE YOU ARE FACING part of the
# cost of giving an order. Pointing your squad at a hill tells that hill. The
# alternative — drawing a lobe while every robot in the valley is quietly told
# anyway — is a readout that lies, and this HUD has enough of those behind it.
#
# 120 DEGREES, not a pencil beam. This is an antenna with a lobe, not a laser,
# and a narrow cone would turn every order into a precision aiming exercise.
# ─────────────────────────────────────────────

## How wide an ADVANCE's lobe is, total. Set 360 to make ADVANCE behave like
## the other verbs again.
##
## 50, DOWN FROM 120. At 120 the thing on screen was still most of a circle:
## wide enough that the curvature read before the direction did, so it looked
## like an omnidirectional wave with a bite out of it rather than like an
## order pointed somewhere.
@export var tx_cone_degrees: float = 50.0


## Key the radio. Called once per order from _issue_order, after the position
## is resolved — `at` is where the order points, which is what aims an ADVANCE.
func _transmit(verb: int, at: Vector3) -> void:
	if player == null or not is_instance_valid(player):
		return   # no body to transmit from; the order itself is still fine
	var origin: Vector3 = player.global_position

	# The bearing, flattened: a transmission aimed up a hill is still aimed
	# along the ground as far as who-can-hear-it is concerned.
	var heading := Vector3.ZERO
	if verb == Verb.ADVANCE or verb == Verb.ATTACK:
		heading = at - origin
		heading.y = 0.0
		if heading.length() < 0.5:
			# Ordered at your own feet. There is no bearing in that, so it goes
			# out as a circle rather than as a lobe pointing at random.
			heading = Vector3.ZERO
		else:
			heading = heading.normalized()
	var aimed: bool = heading != Vector3.ZERO
	var cone_cos: float = cos(deg_to_rad(clampf(tx_cone_degrees, 1.0, 360.0) * 0.5))

	# The cost. Before the ring, so a transmission that drops you through a
	# threshold shows the consequence on the same frame as the cause.
	if tx_signal_cost > 0.0 and player.has_method("receive_signal_damage"):
		player.receive_signal_damage(tx_signal_cost)

	# Who is in reach. Gathered here rather than left to emit_stimulus so the
	# count can be reported and so the alert can be DELAYED to the moment the
	# front arrives — the bus has no concept of a wave that travels.
	var heard: Array = []
	var sm := _get_stimulus_manager()
	if sm != null:
		for ai in sm.registered_ai:
			if ai == null or not is_instance_valid(ai) or not ai.alive:
				continue
			# NOT `faction != ENEMY`. There are four hostile factions now
			# (SWARM, HOME, ARGUS were appended 2026-10-10) and a hardcoded
			# comparison meant none of them ever heard the player's transmit.
			if not (ai is Enemy) or not Enums.are_hostile(Enums.Factions.PLAYER, (ai as Enemy).faction):
				continue
			# A jammed receiver hears nothing. The one case where being at the
			# bottom of the signal ladder works in somebody's favour, and it
			# cuts both ways: EMP the hill and you can talk in front of it.
			if ai.has_method("get_signal_state") \
					and int(ai.get_signal_state()) == int(AI.SignalState.EKILL):
				continue
			var to_them: Vector3 = ai.global_position - origin
			if to_them.length() > tx_radius:
				continue
			if aimed:
				var flat := Vector3(to_them.x, 0.0, to_them.z)
				# Standing on top of you: inside every lobe, no bearing to test.
				if flat.length() > 0.01 and flat.normalized().dot(heading) < cone_cos:
					continue
			heard.append(ai)

	# The wavefront, parented to the LEVEL rather than to the player: a ring
	# hung off a body that then walks away drags its own transmission with it.
	var host: Node = player.get_parent()
	var ping: Node3D = _PING.new().fire(host, origin, tx_radius, TX_COLOUR, tx_travel)
	if ping != null:
		if aimed:
			ping.aim(heading, tx_cone_degrees)
		# A lambda, not _front_reached.bind(origin). Chained binds come off in
		# the opposite order to the one you write them in, so the ping's own
		# .bind(receiver) landed in front of the origin and every callback
		# arrived with its arguments swapped.
		ping.notify_as_front_arrives(heard, func(n): _front_reached(origin, n))
	else:
		# No ground to draw on, but the transmission still happened — tell them
		# now rather than silently letting the player off.
		for n in heard:
			_front_reached(origin, n)

	transmitted.emit(origin, tx_radius, heard.size())


## The front has reached this receiver: it now knows roughly where you are.
func _front_reached(origin: Vector3, receiver: Node) -> void:
	if receiver == null or not is_instance_valid(receiver) or not receiver.alive:
		return   # died between keying the mic and the wave getting there
	if not receiver.has_method("receive_stimulus"):
		return
	receiver.receive_stimulus(StimulusManager.StimulusType.ENEMY_SPOTTED,
		origin, player, origin.distance_to(receiver.global_position))


func _get_stimulus_manager() -> StimulusManager:
	if world != null and world is World and (world as World).ai_manager != null:
		return (world as World).ai_manager.stimulus_manager
	for n in get_tree().get_nodes_in_group("ai_manager"):
		if n is AIManager:
			return (n as AIManager).stimulus_manager
	return null


# ─────────────────────────────────────────────
# EQUIPMENT ORDERS — the designator's half of the command layer
#
# It lives here rather than on the designator tool because this class already
# knows the three things such an order needs and the tool knows none of them:
# which squad is selected, what is under the crosshair, and how to put a marker
# on the ground. The tool handles the HOLD and the screen; the decision and the
# consequences are command.
# ─────────────────────────────────────────────

## THE WHOLE COMMAND VOCABULARY, as the designator's dial.
##
## [{item_id, label, holders, wants_point, deliberate, verb}], the two movement
## orders first and then one entry per piece of equipment the squad is carrying.
##
## MOVEMENT ORDERS ARE ON THE DIAL TOO, and that is the point of the tool. Split
## across a key (T) and a held object, the player had to learn that commanding
## was two unrelated systems; on one dial the vocabulary is simply what the
## screen says it is. T and G still work — nothing was taken away — but the tool
## is now the discoverable surface rather than a second, partial one.
##
## It is also why the dial is never empty. A squad carrying nothing still takes
## orders, so the tool always has something to do: "always available, like the
## welder" is only true once moving is on it.
##
## `deliberate` is the hold. Spending a finite canister deserves the second and
## a half; moving the squad does not, and T has always been instant — making the
## same order slower through a nicer interface would be a straight downgrade.
func command_modes() -> Array:
	var squad := get_selected_squad()
	if squad == null:
		return []
	var out: Array = [
		{
			"item_id": MODE_ADVANCE,
			"label": "Advance",
			"holders": squad.get_orderable_members().size(),
			"remaining": squad.get_orderable_members().size(),
			"wants_point": true,
			"deliberate": false,
			"verb": Verb.ADVANCE,
		},
		{
			"item_id": MODE_FOLLOW,
			"label": "Follow Me",
			"holders": squad.get_orderable_members().size(),
			"remaining": squad.get_orderable_members().size(),
			"wants_point": false,
			"deliberate": false,
			"verb": Verb.FOLLOW,
		},
	]
	out.append_array(orderable_equipment())
	return out


## Carry out one dial entry. Equipment goes the long way round through the
## squad; the two movement verbs are the same call T makes, so there is exactly
## one implementation of "advance" in the game and the tool is a second way to
## reach it rather than a second copy of it.
# ─────────────────────────────────────────────
# NO LINK, NO ORDERS.
#
# An e-killed drone keeps its gun and loses its command. That is the whole
# premise arriving at once: strip the squad layer and the player finds out they
# were a coordinator, not a shooter.
#
# AND IT DOES NOT COME BACK THE INSTANT THE BAR DOES. A link that flickers
# above the floor for one frame should not hand the squad back mid-firefight,
# so recovery is followed by a resync window — the bar is up, the squad is not
# answering yet, and the designator says so. Without it, jamming reads as a
# stutter rather than as something being taken away.
# ─────────────────────────────────────────────

## How long after the link comes back before the squad answers again.
@export var resync_seconds: float = 3.0
## Counts down once the link is above the floor. Above zero: no orders.
var _resync_t: float = 0.0
## Whether the link was down last tick, so the window is armed on the edge.
var _was_cut: bool = false


## True when the player cannot command: link at the floor, or still resyncing.
func link_down() -> bool:
	if player == null or not is_instance_valid(player):
		return false   # no player to ask: never refuse an order over it
	if player.has_method("get_signal_state") \
			and int(player.get_signal_state()) == int(AI.SignalState.EKILL):
		return true
	return _resync_t > 0.0


## Seconds left before the squad answers again, for the readout.
func resync_left() -> float:
	return maxf(_resync_t, 0.0)


## Runs the resync window and leans on the squad while the link is out. Called
## from _process.
func _tick_link(delta: float) -> void:
	if player == null or not is_instance_valid(player) \
			or not player.has_method("get_signal_state"):
		return
	var cut: bool = int(player.get_signal_state()) == int(AI.SignalState.EKILL)
	if cut:
		_resync_t = resync_seconds   # held full while it is down
		_lean_on_squad(delta)
	elif _was_cut:
		_resync_t = resync_seconds   # the edge: start counting from here
	else:
		_resync_t = maxf(0.0, _resync_t - delta)
	_was_cut = cut


## THE SQUAD IS ON YOUR UPLINK, SO IT GOES WITH YOU.
##
## Rather than inventing a second "badly commanded" state, this pushes their
## own signal down — which routes into every penalty the game already has and
## has already tuned: accuracy, sensor range, order compliance, the lot. One
## cause, all the existing effects.
##
## FLOORED AT CRITICAL. They get worse, they do not get e-killed: a jammed
## drone should cost the player a coordinated squad, not delete it.
func _lean_on_squad(delta: float) -> void:
	var squad := get_selected_squad()
	if squad == null:
		return
	for m in squad.squad_members:
		if m == null or not is_instance_valid(m) or not m.alive:
			continue
		if m.signal_integrity <= AI.SIGNAL_CRITICAL:
			continue
		if m.has_method("receive_signal_damage"):
			m.receive_signal_damage(uplink_drag * delta, player)


## Per second, how hard a dead uplink drags the squad's own link down.
@export var uplink_drag: float = 0.35


func issue_dial_order(mode: Dictionary, pos: Vector3) -> bool:
	if mode.is_empty():
		return false
	if link_down():
		equipment_refused.emit(_link_refusal())
		return false
	var id_value: StringName = mode.get("item_id", &"")
	if id_value == MODE_ADVANCE or id_value == MODE_FOLLOW:
		if get_selected_squad() == null:
			equipment_refused.emit("NO SQUAD IN COMMAND")
			return false
		_issue_order(int(mode["verb"]), pos if id_value == MODE_ADVANCE else null)
		return true
	return issue_equipment_order(id_value, str(mode["label"]), pos,
		bool(mode.get("wants_point", true)))


## What the selected squad is carrying that the player could order, as
## [{item_id, label, holders, wants_point, deliberate}] with the commonest first.
##
## Built from the robots' REAL slots rather than from the loadout the player
## bought, so a squadmate who has spent both canisters drops out of the count
## and the designator's readout goes dim instead of lying.
func orderable_equipment() -> Array:
	var squad := get_selected_squad()
	if squad == null:
		return []
	var by_id: Dictionary = {}
	for m in squad.get_orderable_members():
		if m == null or not is_instance_valid(m):
			continue
		var slots = m.get("equipment_slots")
		if slots == null:
			continue
		for i in slots.size():
			var slot: AIEquipmentSlot = slots[i]
			if slot == null or slot.item_id == &"" or slot.equipment_scene == null:
				continue
			var key := slot.item_id
			if not by_id.has(key):
				var at_point := true
				if _known_for(squad).has(key):
					at_point = bool(_known_for(squad)[key]["wants_point"])
				else:
					# ordered_at_point is on the AI scene, so reading it costs
					# one instantiate — ONCE per distinct item per squad, now
					# that the answer is kept. This is polled several times a
					# second, because the readout has to be live.
					var probe = slot.equipment_scene.instantiate() as AIEquipment
					if probe != null:
						at_point = probe.ordered_at_point
						probe.free()
				# THE FULL NAME, NOT THE SHORT ONE. The slot's label is
				# short_label(), which the squad HUD wants — it is captioning a
				# thing that just happened and the context is obvious. On the
				# designator it is the ONLY thing identifying what you are about
				# to order, and the short names collide: the Cluster Mine reads
				# "CLUSTER" and the Heavy Mine reads "MINE", which on a dial you
				# cycle with one key is worse than useless.
				var named: ItemDefinition = _Glyphs.item_by_id(key)
				var label: String = named.display_name if named != null else slot.label
				by_id[key] = {
					"item_id": key,
					"label": label if label != "" else "EQUIPMENT",
					"holders": 0,
					"remaining": 0,
					"wants_point": at_point,
					# Equipment is finite, so it gets the hold. See command_modes().
					"deliberate": true,
				}
			# TWO DIFFERENT NUMBERS, and conflating them is what made a squad
			# between uses look like a squad that was out. `holders` is who can
			# answer THIS INSTANT; `remaining` is how many throws the squad has
			# left at all. Everyone on cooldown is holders 0, remaining plenty.
			if m.can_answer_equipment_order(key):
				by_id[key]["holders"] = int(by_id[key]["holders"]) + 1
			by_id[key]["remaining"] = int(by_id[key]["remaining"]) + slot.remaining()
	# Fold into what this squad is remembered as carrying, so nothing drops off
	# the dial when it is spent or its carrier dies.
	var kept: Dictionary = _known_for(squad)
	for key in by_id:
		kept[key] = by_id[key]
	for key in kept:
		if not by_id.has(key):
			# Carried earlier and not now: still on the dial, with nothing left.
			kept[key]["holders"] = 0
			kept[key]["remaining"] = 0
	_dials[squad] = kept
	var out: Array = kept.values()
	out.sort_custom(func(a, b): return str(a["label"]) < str(b["label"]))
	return out


## What is already known about a squad's kit, as {item_id: entry}.
##
## The STATIC half of an entry — its name, and whether it is aimed — cannot
## change mid-mission, and reading `ordered_at_point` means instantiating the AI
## scene. The dial is polled several times a second now that the readout has to
## be live, so that work is done once per item per squad and kept.
func _known_for(squad: Squad) -> Dictionary:
	if not _dials.has(squad):
		_dials[squad] = {}
	return _dials[squad]


## Order it. Returns true if anything was actually spent NOW — a held order
## comes back false and fires later, which is why the designator reports through
## the signals rather than through this.
func issue_equipment_order(item_id: StringName, label: String, pos: Vector3,
		use_point: bool) -> bool:
	# Gated here as well as in issue_dial_order: equipment can be ordered from
	# the dial OR directly, and a gate on one entrance is not a gate.
	if link_down():
		equipment_refused.emit(_link_refusal())
		return false
	var squad := get_selected_squad()
	if squad == null:
		equipment_refused.emit("NO SQUAD IN COMMAND")
		return false
	# A fresh designation replaces whatever was being held. Pointing somewhere
	# new is changing your mind, not adding to a list.
	_queued.clear()
	return _attempt_equipment_order(squad, item_id, label, pos, use_point, true)


## One go at it. `may_queue` is false on the retries, so a held order that is
## still too early simply stays held instead of re-queueing itself and
## re-announcing on every tick.
func _attempt_equipment_order(squad: Squad, item_id: StringName, label: String,
		pos: Vector3, use_point: bool, may_queue: bool) -> bool:
	var result: Dictionary = squad.receive_player_equipment_order(item_id, pos, use_point)
	var spent := int(result.get("spent", 0))
	if spent <= 0:
		var why := str(result.get("reason", ""))
		# TIMING IS A WAIT, NOT A NO. Everyone who carries it is between uses,
		# which resolves on its own in a few seconds — so hold the order rather
		# than making the player poll their own squad.
		if why == "reloading":
			if may_queue:
				_queued = {
					"item_id": item_id,
					"label": label,
					"pos": pos,
					"use_point": use_point,
					"waited": 0.0,
				}
				_queue_retry = 0.0
				# The mark goes down NOW even though nothing has been thrown.
				# The player has designated; the squad agreeing to it in four
				# seconds does not change where they pointed.
				if use_point:
					_place_equipment_marker(pos, label)
				equipment_queued.emit(label)
			return false
		# THE REASON, NOT JUST A NO. These come back from the robots that were
		# asked, and none of the three resolves by waiting: "TOO FAR" means move,
		# "NONE LEFT" means it is out for the mission, "NOBODY CARRYING" means
		# go to the armoury.
		_queued.clear()
		equipment_refused.emit("%s: %s" % [label.to_upper(),
			why.to_upper() if why != "" else "NO ANSWER"])
		return false
	_queued.clear()
	# A mark on the ground, same as an ADVANCE gets, but only when there was a
	# point to mark — a drone pack release has no location to show.
	if use_point:
		_place_equipment_marker(pos, label)
	equipment_ordered.emit(squad, label, spent)
	return true


## What is being held, for the designator's readout. Empty when nothing is.
func queued_item_id() -> StringName:
	return _queued.get("item_id", &"") if not _queued.is_empty() else &""


func queued_label() -> String:
	return str(_queued.get("label", "")) if not _queued.is_empty() else ""


## Ask again, or give up out loud. Driven from _process; cheap when idle,
## because the common case is an empty dictionary and one compare.
func _tick_queued_order(delta: float) -> void:
	if _queued.is_empty():
		return
	_queued["waited"] = float(_queued["waited"]) + delta
	if float(_queued["waited"]) >= queue_timeout:
		# EVERY HELD ORDER ENDS WITH A SENTENCE. Dropping it quietly would leave
		# the player believing smoke is still coming, which is worse than having
		# been told no in the first place.
		var gone := str(_queued["label"]).to_upper()
		_queued.clear()
		equipment_refused.emit("%s: NOBODY COULD ANSWER" % gone)
		return
	_queue_retry += delta
	if _queue_retry < queue_retry_interval:
		return
	_queue_retry = 0.0
	var squad := get_selected_squad()
	if squad == null:
		return
	_attempt_equipment_order(squad, _queued["item_id"], str(_queued["label"]),
		_queued["pos"], bool(_queued["use_point"]), false)


## The designated point gets the same CommandMarker the orders use, so the
## vocabulary on the ground stays one vocabulary. Keyed separately from the
## squad's objective marker: designating smoke must not wipe the ADVANCE mark
## the squad is still working toward.
func _place_equipment_marker(pos: Vector3, label: String) -> void:
	if marker_scene == null or world == null:
		return
	if _equipment_marker == null or not is_instance_valid(_equipment_marker):
		_equipment_marker = marker_scene.instantiate()
		world.add_child(_equipment_marker)
	_equipment_marker.global_position = _snap_to_ground(pos)
	_equipment_marker.rotation = Vector3.ZERO
	if _equipment_marker.has_method("set_order"):
		_equipment_marker.set_order(Verb.CONTACT, label.to_upper())


## Where the crosshair is pointing, for the designator's live preview. Public
## because the tool needs the same ray the orders use — a preview computed a
## different way would land somewhere the order then does not.
func aim_mark() -> Vector3:
	var hit := _aim_result()
	if hit.is_empty():
		return cam.global_position + (-cam.global_transform.basis.z * 60.0)
	var pos: Vector3 = hit.position
	var collider = hit.get("collider")
	if collider is CharacterBody3D or collider is RigidBody3D:
		pos = _snap_to_ground(pos)
	return pos


func _place_marker(squad: Squad, verb: int, pos: Vector3) -> void:
	if marker_scene == null or world == null:
		return

	var marker: Node3D = _markers.get(squad)
	if marker == null or not is_instance_valid(marker):
		marker = marker_scene.instantiate()
		world.add_child(marker)
		_markers[squad] = marker

	marker.global_position = _snap_to_ground(pos)
	marker.rotation = Vector3.ZERO
	if marker.has_method("set_order"):
		var text: String = VERB_LABELS.get(verb, "")
		if has_teams():
			text = "%s : %s" % [squad.team_name(), text]
		marker.set_order(verb, text)


# The orders of the team you are not commanding right now stay on the map,
# quieter.
func _refresh_marker_dimming() -> void:
	var selected := get_selected_squad()
	for squad in _markers.keys():
		var marker = _markers[squad]
		if marker != null and is_instance_valid(marker):
			marker.set("dimmed", squad != selected)


func _clear_marker(squad: Squad) -> void:
	var marker = _markers.get(squad)
	if marker != null and is_instance_valid(marker):
		marker.queue_free()
	_markers.erase(squad)


# The old code forced marker.y = 0, which drops the marker to world origin
# height — fine on a flat arena, wrong on anything with terrain. Robots stand
# on layer 1 with the level, so the ray looks through bodies to the surface
# under them; otherwise an order aimed at a robot sat on its head.
func _snap_to_ground(pos: Vector3) -> Vector3:
	if player == null:
		return pos   # no world to look in (a test rig)
	var query := PhysicsRayQueryParameters3D.create(
		pos + Vector3.UP * 3.0, pos + Vector3.DOWN * 30.0)
	query.collision_mask = 1
	var skip: Array[RID] = []
	for _i in 4:
		query.exclude = skip
		var hit: Dictionary = _space().intersect_ray(query)
		if hit.is_empty():
			return pos   # nothing under it within reach: keep the point as given
		if hit.collider is CharacterBody3D or hit.collider is RigidBody3D:
			skip.append(hit.rid)
			continue
		return hit.position + Vector3.UP * 0.05
	return pos   # four bodies deep and still no ground: keep the point as given


## How long a called contact stays marked. ONE constant for the HUD marker and
## the designation both, so what you can see and what the tubes believe can
## never disagree.
const CONTACT_MARKER_SECONDS := 8.0


## The AI manager, through World, the same way _get_stimulus_manager does it —
## Player has no ai_manager property of its own.
func _get_ai_manager():
	if world != null and "ai_manager" in world:
		return world.ai_manager
	return null


## What the readout says when the link will not carry an order.
func _link_refusal() -> String:
	var left := resync_left()
	if player != null and is_instance_valid(player) and player.has_method("get_signal_state") \
			and int(player.get_signal_state()) == int(AI.SignalState.EKILL):
		return "LINK LOST"
	return "RESYNC %.0fs" % ceil(left)
