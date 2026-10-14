extends Node3D
class_name HoldableCore

# ─────────────────────────────────────────────
# HOLDABLE CORE — a compute core that can change hands, both ways.
#
# NOT TO BE CONFUSED WITH `Env/world_objects/capture_point.tscn`, which is the
# EXISTING one-directional capture point: a dummy terminal, some motes and
# `interact_objective.gd`. That prefab is placed across nine maps and four
# times in Valley Basin alone, and it works the way everything in Campaign/
# works — it completes and can never un-complete.
#
# This is the replacement behaviour, named differently on purpose so the two
# are never mistaken for each other while both exist. Migrating the prefab
# onto this is Phase 5b and it touches every one of those nine maps; the slice
# does it for Valley Basin only.
#
# The structural change the whole campaign rework rests on. Objectives in this
# project are a CHECKLIST: there is no `uncomplete`, no `completed = false`
# anywhere in Campaign/, so an enemy can stand on a relay you took and never
# have it. This is the same idea built as STATE instead.
# docs/briefs/CAMPAIGN_REWORK.md §12.
#
# HOW IT GOES, and the asymmetry is deliberate:
#
#   YOU take a core by working its terminal. Not a squadmate — the core loop
#   cannot depend on an AI pathing to a console, and a capture that fails
#   because a robot caught a doorway is a failure the player can neither see
#   nor fix.
#
#   THEY take it back by shooting the tap off. No AI capture behaviour is
#   needed anywhere, which is the single biggest reason this is buildable.
#
# Shooting the anchor off UNDOES the capture: the core goes back to whoever
# held it before you took it. NEUTRAL stays in the enum — enums here are
# append-only, and an unowned core is still a coherent state for a map to
# author — but nothing produces it any more.
#
# ONE TAP PER CORE. Unlimited overall, but you cannot stack them: a second
# cannot be called while the first lives. The cost of losing one is the walk
# back and the terminal again, under whatever pressure the map is under by
# then — paid in exposure and time rather than in an inventory count.
#
# NO _process. _physics_process runs only while a channel is live and switches
# itself off the moment one is not.
# ─────────────────────────────────────────────

const _Tap := preload("res://Env/world_objects/capture_tap.gd")

enum Holder { HOSTILE, NEUTRAL, PLAYER }

## Three beats, so the channel has somewhere for sound and animation to land.
## A uniform progress bar has no beats, which is why the current capture feels
## like holding a key down rather than giving an order — §12.3.
enum Beat { CONTACT, OVERRIDE, COMMIT }

signal holder_changed(holder: Holder)
signal beat_reached(beat: Beat)
signal channel_progress(fraction: float)
signal channel_interrupted()
signal tap_called()
signal tap_docked()
signal tap_lost()

@export var holder: Holder = Holder.HOSTILE
## 0 small, 1 medium, 2 large. Drives the channel length, because a 12.38 m
## structure should not change hands as fast as a 4.19 m one — the three core
## prefabs are all `channel_duration = 3.0` today, which is the bug this fixes.
@export_range(0, 2) var size_tier: int = 1
@export var channel_seconds: Array[float] = [4.0, 6.0, 10.0]
## Measured from the terminal, not from this node.
@export var channel_range: float = 4.5
## Progress survives briefly if the player steps out and comes back.
@export var grace_seconds: float = 2.0
## How fast contested progress bleeds away, as a multiple of the fill rate.
@export var contest_bleed: float = 1.5
## The terminal. Handed over by whoever fits this, the way the ops table and
## the departure lever are — it is a sibling, not a child, when seated by a
## patch script.
@export var interactible: Interactible
## What the world marker calls this. The bunker is a HoldableCore too — it is
## held exactly the same way — but calling it a CORE on screen is a lie the
## player has to unlearn.
@export var mark_noun: String = "CORE"
## Where the tap sits when it lands, in metres above this node.
##
## -1 derives it from `size_tier`, which is right for the authored core
## prefabs and WRONG for anything else — the bunker is a 4.5 m post and tier 1
## would dock a tap at 7 m, hanging in the air above it. Anything that is not
## one of the three core prefabs should set this from its own geometry.
@export var dock_height: float = -1.0
## How long the tap takes to come down. Set on the tap before it is parented —
## see _call_tap.
@export var tap_flight_seconds: float = 4.2

var _channelling: bool = false
var _t: float = 0.0
var _grace: float = 0.0
var _beat: int = -1
## Typed Node3D rather than CaptureTap: a brand-new `class_name` is not visible
## to other scripts until the editor rescans, and this project cannot run
## --import. The preload above is the real reference; the type here is only a
## hint, so it costs nothing to leave it loose.
var _tap: Node3D = null
var _player: Node3D = null
var _anchor: Node3D = null
## How long the terminal watchdog has been running. See _watch_terminal.
var _watch_elapsed: float = 0.0
## WHO HELD THIS BEFORE YOU DID, captured at ready from whatever the level
## authored. Losing the anchor hands the core back to THEM, not to nobody, so
## this is the holder to revert to — and it is read rather than assumed to be
## HOSTILE because a defend operation starts with cores already yours.
var _authored_holder: int = Holder.HOSTILE


func _ready() -> void:
	_authored_holder = int(holder)
	set_physics_process(false)
	_wire_interactible()
	holder_changed.connect(_on_holder_changed)
	_on_holder_changed(holder)
	# DEFERRED, so the INITIAL STATE is not emitted into an empty room.
	# BasinSlice parents the cores before it builds the operation and the heat,
	# so a listener created afterwards connects to this signal one _ready too
	# late and never learns the starting holder. Anything that took its opening
	# state from this emit would silently sit on a default — SiteOperation only
	# escapes it today because it polls. Deferring puts the emit after every
	# _ready this frame, which is where a starting-state announcement belongs.
	holder_changed.emit.call_deferred(holder)


## A STATE READ YOU CAN SEE FROM ACROSS THE MAP.
##
## Slice scaffolding, and the thing whose absence made the first playtest look
## identical to the old map: every system was running and none of it was
## visible. A Label3D is not the final answer — §13.2 has the motes, the light
## climbing the shaft and the beacon — but it is the answer to "is anything
## happening at all", which is the question a slice has to settle first.


## Colour and text per state, STRAIGHT OFF THE PALETTE.
##
## Not invented here: HUDPalette already defines these exact meanings and the
## operations table already draws sites with them, so a core in the world and
## a site on the board say the same thing in the same colour. The first cut
## used a green of its own for "held", which is Home Command's institutional
## green — the wrong idea entirely. A site under your control is HELD blue.
##
## Plus the authored motes where there are any —
## capture_point.tscn carries a CPUParticles3D called Motes, and the bunker
## does not, so this has to cope with both.
func _on_holder_changed(h) -> void:
	var col := Color.WHITE
	match int(h):
		Holder.HOSTILE:
			col = HUDPalette.FAC_ADVERSARY
		Holder.NEUTRAL:
			col = HUDPalette.GONE
		Holder.PLAYER:
			col = HUDPalette.HELD
	var host := get_parent()
	if host == null:
		return   # unparented; nothing to recolour
	# The pillar itself, which is the part you see from distance.
	var bodyn := host.get_node_or_null(^"CoreBody")
	if bodyn != null and bodyn is MeshInstance3D:
		var bm := (bodyn as MeshInstance3D).material_override as StandardMaterial3D
		if bm != null:
			bm.emission = col
			bm.emission_energy_multiplier = 0.9 if int(h) == Holder.PLAYER else 0.55
	var motes := host.get_node_or_null(^"Motes")
	if motes != null and motes is CPUParticles3D:
		(motes as CPUParticles3D).color = col
	_drive_authored(h)


## DRIVE THE OBJECTIVE THIS CORE SITS ON, BOTH WAYS.
##
## The authored capture point IS a MissionObjective, already in the
## "mission_objectives" group, already listed by ObjectiveTracker, already
## drawn by the objective HUD and already baked into the minimap with an id.
## So the new state does not need its own UI — it needs to move the one that
## exists.
##
## Completing is the easy half. UN-completing is the half the project has
## never had: `completed` is a plain var and `complete()` is one-way, so this
## sets it back by hand and republishes through `progress_changed`, which is
## the only signal the tracker listens to that does not mean "finished".
## ObjectiveTracker._on_progress re-emits it as objective_changed, which is
## what makes the HUD line un-tick.
## IT DOES NOT CHECK `active`, and that is a trap worth naming. Both of the
## other objective types refuse to finish while inactive —
## reach_objective._try_complete and eliminate_objective both test it — so a
## core is the one kind that can tick an objective whose prerequisites are not
## met. No site authors a core with a prerequisite, so there is nothing here
## to break today; the sim arena's bunker does, and it enforces the order by
## shutting its own terminal (training_core.gd, _build). If you ever chain two
## site cores, do the same: a guard HERE would let the player channel the whole
## capture and then silently nothing, which is worse than no prompt at all.
func _drive_authored(h) -> void:
	var o = get_parent()
	if o == null or not is_instance_valid(o) or not (o is MissionObjective):
		return   # the bunker has no authored objective; it is a place, not a task
	var obj := o as MissionObjective
	if int(h) == Holder.PLAYER:
		if not obj.completed:
			obj.complete()
		return
	if obj.completed:
		obj.completed = false
		obj.active = true
		obj.progress_changed.emit(obj, 0, 1)


func duration() -> float:
	var i: int = clampi(size_tier, 0, channel_seconds.size() - 1)
	return maxf(channel_seconds[i], 0.1)


# ── Being used ───────────────────────────────────────────────────────────────

func _wire_interactible() -> void:
	if interactible == null:
		interactible = _find_interactible(self)
	if interactible == null:
		push_warning("CapturePoint '%s' has no Interactible, so it cannot be captured. Seat one on it." % name)
		return
	# LAYER 3, not the template's default 1. The player's InteractRaycast is
	# mask 2, and layer 1 never meets it — the ray goes straight through and no
	# prompt appears. Cost a session on the operations table; see ops_table.gd.
	interactible.collision_layer = 3
	interactible.destroy_on_use = false
	interactible.disable_on_use = false
	interactible.type = Enums.InteractTypes.OBJECTIVE
	# Connect first, take over second — see _take_terminal below.
	interactible.interacted.connect(_on_interacted)
	_take_terminal.call_deferred()
	_watch_terminal()
	_guard_authored.call_deferred()


## TAKING IT ONCE IS NOT ENOUGH, and this cost a playtest.
##
## The deferred takeover above runs at the end of the frame BasinSlice readies.
## But InteractObjective wires ITSELF to the same terminal in
## _on_objective_ready, and the campaign calls that when it ACTIVATES the
## mission's objectives — which is frames later, long after we looked. So the
## authored objective quietly reconnected, won the press, and completed the
## mission the old way: no channel, no colour change, no drone, no anchor. The
## map played exactly as it always had.
##
## probe_basin_slice.gd could not see this, because loading the level on its
## own readies every objective in the same frame and the deferred call catches
## them all. Only a real deploy has the gap.
##
## So the terminal is re-taken on a short watchdog rather than once. Six
## seconds covers the walk from the pass to the first core several times over,
## and the timer frees itself — this is not a permanent cost.
func _watch_terminal() -> void:
	var t := Timer.new()
	t.name = "TerminalWatch"
	t.wait_time = 0.5
	t.autostart = true
	add_child(t)
	t.timeout.connect(func() -> void:
		_watch_elapsed += t.wait_time
		_take_terminal()
		if _watch_elapsed >= 6.0:
			t.queue_free())


## TAKE THE TERMINAL OVER, AND DO IT DEFERRED.
	#
	# The authored capture points — capture_point.tscn, nine maps, four of them
	# in Valley Basin — wire their own InteractObjective to this same
	# Interactible. Two objectives racing for one terminal gives you a core
	# that completes AND channels, and the symptom is a capture that fires
	# twice for different reasons.
	#
	# The new behaviour wins and the old node is left in the scene doing
	# nothing, because it is still carrying the terminal mesh and the motes.
	# Setting `active = false` on it would not work: MissionObjective sets that
	# true itself on ready, so a value written into the scene is overwritten
	# before anybody sees it.
	#
	# DEFERRED, because doing it in _ready LOSES THE RACE. InteractObjective
	# connects itself in _on_objective_ready, and whether that has happened yet
	# depends on where the two nodes sit in the scene — BasinSlice is declared
	# near the top of valley_basin_level.tscn, so its cores were readied first,
	# disconnected nothing, and the authored objectives wired themselves up
	# afterwards. Both handlers then ran: the old objective still completed the
	# mission and the new channel ran underneath it, invisibly. The map played
	# exactly as it always had, which is the worst possible symptom.
	#
	# A deferred call runs once the whole tree is ready, so by then everyone who
	# wants this terminal has asked for it and there is something to take.
func _take_terminal() -> void:
	if interactible == null or not is_instance_valid(interactible):
		return   # the terminal went away with the level; nothing to take over
	var taken := 0
	for c in interactible.interacted.get_connections():
		var cb: Callable = c["callable"]
		if cb.get_object() != self:
			interactible.interacted.disconnect(cb)
			taken += 1
	if taken > 0:
		# Not a warning: this is the intended path on every authored core.
		print("[HoldableCore] %s took its terminal from %d other handler(s)" % [get_parent().name, taken])


func _find_interactible(n: Node):
	for c in n.get_children():
		if c is Interactible:
			return c
		var f = _find_interactible(c)
		if f != null:
			return f
	return null


## What the F prompt says. The HUD prefixes "F | ".
func get_prompt() -> String:
	if _tap != null and is_instance_valid(_tap):
		return "Core held"
	if _channelling:
		return "Overriding  %d%%" % int(round(_t / duration() * 100.0))
	return "Override Core"


func _on_interacted(_source) -> void:
	if _tap != null and is_instance_valid(_tap):
		# ONE TAP PER CORE. Not an error — the player pressing F on a core they
		# already hold is a reasonable thing to do and the prompt said so.
		return
	if _channelling:
		return   # already running; pressing again is harmless
	_channelling = true
	_beat = -1
	_player = _find_player()
	if _player == null:
		push_warning("CapturePoint '%s': no player found, so the channel cannot measure range and will not run." % name)
		_channelling = false
		return
	set_physics_process(true)


## The same lookup interact_objective.gd uses, including the walk up to World —
## the group is not populated in every scene this has to run in, and a capture
## point in the Laboratory or under a probe should still work.
func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0]
	var node: Node = self
	while node != null:
		if node is World:
			return (node as World).player
		node = node.get_parent()
	return null


# ── The channel ──────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not _channelling:
		set_physics_process(false)
		return
	if _player == null or not is_instance_valid(_player):
		_break_channel()
		return

	var at: Vector3 = interactible.global_position if interactible != null else global_position
	var in_range: bool = _player.global_position.distance_to(at) <= channel_range

	if not in_range:
		# GRACE, not an instant reset. Stepping out of the circle to deal with
		# something and coming back is play, not a mistake.
		_grace += delta
		if _grace >= grace_seconds:
			_break_channel()
		return
	_grace = 0.0

	if _contested(at):
		# Contested bleeds rather than freezing, so standing in a fight you are
		# losing costs you the progress instead of banking it.
		_t = maxf(0.0, _t - delta * contest_bleed)
		channel_progress.emit(_t / duration())
		return

	_t += delta
	_advance_beats()
	channel_progress.emit(clampf(_t / duration(), 0.0, 1.0))
	if _t >= duration():
		_complete()


## A hostile inside the same radius the player has to stand in. Deliberately
## the same number: the rule is "you cannot do this while they are on you",
## and two different radii would make that unreadable.
func _contested(at: Vector3) -> bool:
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if e == null or not is_instance_valid(e):
			continue
		if not (e is Node3D):
			continue
		if "alive" in e and not e.alive:
			continue
		if "faction" in e and not Enums.are_hostile(Enums.Factions.PLAYER, e.faction):
			continue
		if (e as Node3D).global_position.distance_to(at) <= channel_range:
			return true
	return false


## Fires each beat once as the channel passes it, so art and audio have three
## separate moments to hang off instead of one continuous bar.
func _advance_beats() -> void:
	var f: float = _t / duration()
	var want: int = -1
	if f >= 0.80:
		want = Beat.COMMIT
	elif f >= 0.30:
		want = Beat.OVERRIDE
	elif f > 0.0:
		want = Beat.CONTACT
	if want > _beat:
		_beat = want
		beat_reached.emit(want)


func _break_channel() -> void:
	_channelling = false
	_t = 0.0
	_grace = 0.0
	_beat = -1
	set_physics_process(false)
	channel_interrupted.emit()


func _complete() -> void:
	_channelling = false
	_t = 0.0
	_grace = 0.0
	_beat = -1
	set_physics_process(false)
	_call_tap()


# ── The tap ──────────────────────────────────────────────────────────────────

func _call_tap() -> void:
	if _tap != null and is_instance_valid(_tap):
		push_warning("CapturePoint '%s': a tap is already docked, so the call is ignored. One per core." % name)
		return
	var tap := _Tap.new()
	tap.name = "Tap"
	# EVERYTHING BEFORE add_child. The tap builds its body and starts its
	# descent in _ready, which fires the moment it is parented — so a property
	# set afterwards is read by nothing and silently does not apply.
	tap.flight_seconds = tap_flight_seconds
	# On the core's head. Placeholder until the real cores carry a dock marker;
	# size_tier stands in for the three prefab heights until then.
	tap.position = Vector3(0.0, _dock_y(), 0.0)
	tap.docked.connect(_on_tap_docked)
	tap.destroyed.connect(_on_tap_destroyed)
	add_child(tap)
	_tap = tap
	tap_called.emit()


## THE POD LANDS AND BECOMES A STRUCTURE.
##
## The flyer is a delivery. What holds the core is a CaptureAnchor: a
## Nest-derived building with health, on the player's faction, registered the
## way every other body on the map is — so the enemy can target it, shoot it,
## and take the core back by bringing it down. capture_anchor.gd has the long
## version of why it has to be a Nest rather than a StaticBody3D.
func _on_tap_docked(tap_node) -> void:
	var scene: PackedScene = tap_node.anchor_scene if "anchor_scene" in tap_node else null
	if scene == null:
		push_warning("HoldableCore '%s': the tap has no anchor scene, so the core is held by nothing the enemy can shoot." % name)
		_set_holder(Holder.PLAYER)
		tap_docked.emit()
		return
	var anchor = scene.instantiate()
	anchor.name = "Anchor"
	# Parented to the LEVEL, not to this core. An AI registers itself with the
	# AIManager on ready and expects to live in the level the way every other
	# body does; burying one under an objective node is asking for trouble when
	# the objective is freed.
	var host := get_parent()
	var where: Vector3 = _anchor_point()
	var into: Node = host.get_parent() if host != null and host.get_parent() != null else self
	# PLACED BEFORE IT ENTERS THE TREE, the way enemy_force_spawner.gd does it
	# and for the reason written out at length there. add_child runs _ready
	# synchronously, so an anchor added first and moved after spends one frame
	# at the level's ORIGIN — where its 25 m Detection area overlaps everything
	# else spawned that frame and fills combat_target with whoever it found.
	# Worse here than for a soldier: CaptureAnchor is Nest-derived, and
	# Enemy.initialize() snapshots spawn_transform on ready, so the anchor's
	# reset point would be the map origin rather than the core it docked on.
	anchor.position = into.to_local(where) if into is Node3D else where
	into.add_child(anchor)
	if anchor.has_signal(&"anchor_lost"):
		anchor.anchor_lost.connect(_on_anchor_lost)
	_anchor = anchor
	# The pod has done its job and the structure is the thing from here.
	tap_node.queue_free()
	_tap = anchor
	_set_holder(Holder.PLAYER)
	tap_docked.emit()


func _on_anchor_lost(_a) -> void:
	_anchor = null
	_tap = null
	# BACK TO WHOEVER HELD IT, not to nobody.
	#
	# This was NEUTRAL for a while, on the argument that a core nobody owns
	# makes losing one a scramble rather than a flip. Overruled 2026-10-12, and
	# rightly: a site you have not taken is theirs, and a third state that only
	# ever appears for a few seconds after a specific failure is a rule the
	# player has to be taught for no gain. Shooting the anchor off UNDOES the
	# capture — that is the whole sentence.
	_set_holder(_authored_holder)
	tap_lost.emit()


func _on_tap_destroyed(tap_node) -> void:
	var had_landed: bool = tap_node != null and tap_node.landed
	_tap = null
	# ONLY A LANDED TAP CHANGES ANYTHING. A tap killed in flight never held the
	# core, so losing it must leave the holder alone — otherwise shooting your
	# own inbound tap would neutralise a core you never took. The flight is not
	# contestable by design, so this should be unreachable in play; it is here
	# because the state machine has to be right regardless.
	if had_landed:
		# BACK TO ITS AUTHORED OWNER, for the reason in _on_anchor_lost.
		# Unreachable in play; here so the state machine is right regardless.
		_set_holder(_authored_holder)
	tap_lost.emit()


func _set_holder(h: Holder) -> void:
	if holder == h:
		return
	holder = h
	holder_changed.emit(h)


## Whether this core is paying. The campaign layer reads this; nothing else
## should care how it got that way.
func is_held_by_player() -> bool:
	return holder == Holder.PLAYER


## Where a tap lands. The tier table matches the three authored core prefabs —
## 4.19 / 6.97 / 12.38 m — and `dock_height` overrides it for anything built
## rather than instanced.
func _dock_y() -> float:
	if dock_height >= 0.0:
		return dock_height
	return [4.2, 7.0, 12.4][clampi(size_tier, 0, 2)]


## How WIDE this core stands, matching the same three authored prefabs the
## height table comes from — 1.88 / 3.38 / 5.19 m across. Here rather than in
## whoever is drawing it, for the same reason _dock_y is: two tables that can
## disagree is one table too many, and the FX need the footprint to sit a
## collar outside the pillar instead of inside it.
func footprint() -> float:
	return [1.88, 3.38, 5.19][clampi(size_tier, 0, 2)]


## THE SAFETY NET, in case the watchdog above ever loses a race anyway.
##
## If the authored objective reports itself complete while this core is NOT
## held by the player, something other than a docked anchor completed it —
## which is precisely the bug the watchdog exists to prevent. Put it back, take
## the terminal again, and say so loudly: a core that ticks itself off without
## a capture is the difference between this system existing and not.
func _guard_authored() -> void:
	var o = get_parent()
	if o == null or not (o is MissionObjective):
		return   # the bunker has no authored objective; nothing to guard
	if not o.objective_completed.is_connected(_on_authored_completed):
		o.objective_completed.connect(_on_authored_completed)


func _on_authored_completed(obj) -> void:
	if int(holder) == Holder.PLAYER:
		return   # we completed it ourselves, which is the intended path
	push_warning("HoldableCore '%s': the authored objective completed without a capture, so something else is still driving this terminal. Reverting it." % get_parent().name)
	obj.completed = false
	obj.active = true
	obj.progress_changed.emit(obj, 0, 1)
	_take_terminal()


## ALREADY YOURS, FROM THE FIRST FRAME (Phase 5).
##
## On a DEFENCE you are not taking this place, you are holding it — so the core
## starts PLAYER-held with its anchor already standing, and the attackers take
## it the only way anybody takes a held core: by shooting the anchor off.
##
## That is the whole loss condition and it needed no new AI behaviour. A
## CaptureAnchor is Nest-derived, on the player's faction and in `all_ai`, so
## hostiles_for() offers it as a target to anything that walks past. §12.3 said
## this would fall out for free and it did.
##
## The first cut of the defence skipped this: the cores started HOSTILE and
## orange, exactly as in the attack, so there was nothing for the attackers to
## take and nothing for the garrison to lose. The map had no win or lose
## condition at all — reported from the first watch.
func start_held() -> void:
	if _anchor != null and is_instance_valid(_anchor):
		return   # already standing; re-entering a level must not stack anchors
	_authored_holder = Holder.HOSTILE
	var scene: PackedScene = _Tap.new().anchor_scene
	if scene == null:
		push_warning("HoldableCore '%s': no anchor scene, so a defended core has nothing the enemy can shoot and cannot be lost." % name)
		_set_holder(Holder.PLAYER)
		return
	var anchor = scene.instantiate()
	anchor.name = "Anchor"
	var host := get_parent()
	var into: Node = host.get_parent() if host != null and host.get_parent() != null else self
	var where: Vector3 = _anchor_point()
	# BEFORE add_child, for the reason spelled out in _on_tap_docked.
	anchor.position = into.to_local(where) if into is Node3D else where
	into.add_child(anchor)
	if anchor.has_signal(&"anchor_lost"):
		anchor.anchor_lost.connect(_on_anchor_lost)
	_anchor = anchor
	_tap = anchor
	_set_holder(Holder.PLAYER)


## WHERE THE ANCHOR STANDS — the FOOT of the core, not its head.
##
## The tap still flies to the top and docks there, because that is the arrival
## you watch. But the structure it leaves has to be a thing the enemy can
## actually shoot, and an anchor on the head of a 4-to-12 metre pillar is not:
## ground units stand at the base looking almost vertically up, which is
## outside their aim cone, and a melee chassis cannot reach it at all.
##
## Watched for five minutes: eighty-three attackers stood around the cores
## doing nothing while the garrison died, because the only thing that could
## have lost the player the site was parked above their heads. The operation
## could reach neither its win nor its loss.
func _anchor_point() -> Vector3:
	return global_position + Vector3(0.0, 0.6, 0.0)
