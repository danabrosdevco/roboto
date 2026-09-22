extends AI
class_name Enemy

# Playtest analytics. By path: see the note in analytics.gd.
const _Analytics := preload("res://Managers/analytics.gd")
# By path, not by class_name: Enemy is the base of every robot scene, and a
# class_name reference to a NEW script fails to compile until Godot has
# rebuilt its global class list — which turns every robot in the game into a
# placeholder. A preload never waits on the class list. Same reasoning as
# tutorial_label.gd's _Toast.
const _SignalArc := preload("res://Character/weapon/appx/signal_arc.gd")
const _KillKinds := preload("res://Campaign/kill_kinds.gd")
const _Ground := preload("res://Campaign/ground_snap.gd")

# ── NODE REFERENCES ───────────────────────────
@export var patrol_path: PatrolPath
@export var nav_agent: NavigationAgent3D
@export var weapon: AIWeapon
# Where a weapon gets attached at runtime. A chassis scene ships with an empty
# mount instead of a baked-in gun, so one frame can carry anything — which is
# what makes "buy a rifle, fit it to Bravo-2" mean something. Scenes that still
# have a weapon wired directly keep working; the mount is only used when a
# weapon is fitted from a record.
@export var weapon_mount: Node3D


# Swaps whatever is on the mount for a new weapon. Safe to call before _ready.
func equip_weapon_scene(scene: PackedScene) -> void:
	if weapon_mount == null:
		push_warning("%s has no weapon_mount; cannot fit a weapon at runtime." % name)
		return
	for child in weapon_mount.get_children():
		child.queue_free()
	if scene == null:
		weapon = null
		return
	var instance := scene.instantiate()
	weapon_mount.add_child(instance)
	instance.transform = Transform3D.IDENTITY
	weapon = instance as AIWeapon
	if weapon == null:
		push_warning("%s is not an AIWeapon scene." % scene.resource_path)
@export var bark: Bark
@export var detection: Area3D
@export var particle_effects_die: Array[ParticleEffect]
@export var particle_effects_hit: Array[ParticleEffect]
@export var visible_pieces: Array[Node3D]

# ── EXPORT DATA ───────────────────────────────
@export var activation_distance: int = 75
@export var health: int = 30
@export var max_health: int = 30
@export var faction: Enums.Factions = Enums.Factions.ENEMY
@export var move_speed: float = 4.5
## Movement response rate, used as 1-exp(-acceleration*delta).
## Framerate independent. ~8 is responsive, ~3 is heavy and lumbering.
## NOTE: scenes overriding this with the old ~1.5-2.0 values will feel sluggish.
@export var acceleration := 8.0
## Turn response rate, same curve as acceleration.
@export var rotation_speed := 7.0
## How near a destination counts as there once the path runs out. Further off
## than this and the path is taken to be blocked. Keep it above the nav agent's
## target_desired_distance, or every arrival reads as a blockage — which is why
## a vehicle, that cannot creep onto an exact spot, sets both larger.
@export var arrival_radius: float = 2.0
@export var reposition_distance: float = 2.0
@export var advance_distance: float = 3.0
# Fraction of the weapon's effective range to hold at. 0.8 keeps a rifle out at
# ~64m and a shotgun at ~36m, so the longer weapon fights at a distance the
# shorter one can't answer.
@export var engage_standoff: float = 0.8
# When the target outranges us we have to close, and crossing open ground to do
# it is how a shotgun squad dies to rifles without ever firing. Outranged
# advances hop cover to cover instead of walking a straight line.
@export var bound_when_outranged: bool = true
# How much further they'll detour for a covered position, as a multiple of the
# direct step. Above ~2 they start taking absurd routes.
## Leap window, in metres. Absolute rather than a fraction of weapon range —
## a melee frame reaches 1.5m and would otherwise never qualify. Too close and
## the leap overshoots; too far and it lands short in the open.
@export var leap_min_distance: float = 5.0
@export var leap_max_distance: float = 16.0
## Seconds after LANDING before another leap is allowed. The gap is spent
## closing on foot, which is what makes a hopper read as a predator that pounces
## rather than a ball bouncing around the sky.
@export var leap_cooldown: float = 2.4
## Highest point of any leap, in metres above the straight line to the target.
## Long leaps get faster and flatter instead of taller. 0 disables the cap.
@export var leap_max_apex: float = 1.3
@export var bound_detour_limit: float = 1.8
@export var fallback_distance: float = 1.25
@export var bits: int = 10
@export var equipment_slots: Array[AIEquipmentSlot] = []
@export var combat_recon_time: float = 1.65
# Display name — e.g. "Shotgun Grunt", "Sniper", "Heavy"
#
# NOTE: this is now PLAYER-FACING as well. The comms log prints it when a
# squadmate calls a contact or a kill, so "Grunt_ShotgunFrag" reads badly on
# screen. Name these the way a soldier would say them out loud.
@export var soldier_name: String = "Enemy"

# Kills this body has confirmed THIS MISSION. Read back onto the SoldierRecord
# at extraction and added to the career total there — the node is destroyed
# between missions, the record is not.
var confirmed_kills: int = 0
# The same kills by what they were (Campaign/kill_kinds.gd): frame id -> count.
# Read and cleared at extraction, like confirmed_kills.
var kills_by_kind: Dictionary = {}
# Squadmates this one got back on their feet this mission. Credited in
# apply_healing, read and cleared at extraction like the kills above.
var revives: int = 0
# Whose kills these really are. A hatchling is a thrown weapon that happens to
# have legs: it lives 25 seconds and has no record, so a kill credited to it was
# a kill nobody got. HatchlingPayload points this at the thrower, and a victim's
# apply_damage follows it — the player or squadmate who threw the canister gets
# the kill (and the bark, if it has a voice).
var credit_kills_to: Node = null

# ── ACCURACY ──────────────────────────────────
# accuracy_skill: static per-character. How close this AI shoots to the
# weapon's physical spread limit. Degraded at runtime by signal_integrity.
@export var accuracy_skill: float = 0.75

# ── AIMING ────────────────────────────────────
## Seconds of settled, stationary tracking before accuracy is at its best.
@export var aim_settle_time: float = 1.2
## Accuracy fraction at zero tracking. 0.35 means a snap shot has ~2.9x the
## spread of a settled shot.
@export var aim_floor: float = 0.35
## Spread multiplier applied while the body is actually moving.
@export var moving_accuracy_penalty: float = 3.0
## Shots per committed burst when the AI rolls FIRE.
@export var burst_min: int = 2
@export var burst_max: int = 5

# ── DECISION WEIGHTING ────────────────────────
## Multiplier applied to the previously chosen action when re-rolling.
## 1.0 = no memory, 0.0 = never repeat. Anything in between discourages
## repetition without banning it, which is what stops the metronome feel.
@export var repeat_penalty: float = 0.45
## Per-character jitter applied to combat_recon_time at spawn so squads
## don't re-decide in lockstep.
@export var recon_jitter: float = 0.25

# ── SEARCH ────────────────────────────────────
# Off by default. See _wander().
@export var enable_idle_wander: bool = false

# ── IDLE SCAN ─────────────────────────────────
# What a robot holding a position does instead of wandering: turns its head and
# nothing else. Deliberately slow and shallow — a guard sweeping a wide arc every
# second reads as nervous, not watchful. Never touches movement_state, so it
# cannot fight a squad holding formation.
@export var idle_scan_interval: float = 4.5
@export var idle_scan_arc_degrees: float = 55.0
@export var idle_scan_distance: float = 8.0
var _idle_scan_t: float = 0.0
var _idle_scan_base: Vector3 = Vector3.ZERO

# A squad member executing a move order shouldn't be distracted by stimuli
# behind them. Used to gate the "turn and look" reactions.
func _moving_under_orders() -> bool:
	return squad_directed and movement_state != MovementState.NONE


# Nothing updated look_target while a robot was walking with no target, so
# whatever it was last pointed at — a corpse, a squadmate's muzzle flash — stuck
# for the whole journey. Facing your direction of travel is the sane default.
func _tick_travel_look(_delta: float) -> void:
	if has_live_target():
		return
	if movement_state == MovementState.NONE:
		return
	if movement_target == Vector3.ZERO:
		return
	look_target = movement_target
	# Re-centre the idle scan arc so they sweep around where they ARRIVE, not
	# around where they set off from.
	_idle_scan_base = Vector3.ZERO


# ── LINE OF FIRE ──────────────────────────────
# Rounds hit allies for reduced damage rather than passing through, so having a
# squadmate in your line is a real cost. Rather than hold fire — which reads as
# the AI freezing — they take a step sideways to clear the shot. That's what a
# person does, and it's legible from outside.
@export var sidestep_when_blocked: bool = true
# How far to slide. Small: this is a shuffle to clear a shoulder, not a flank.
@export var sidestep_distance: float = 2.2
# Seconds before the same robot will sidestep again, so two soldiers in a line
# don't oscillate around each other forever.
@export var sidestep_cooldown: float = 1.8
# Give up and take the shot anyway after this many blocked attempts, so a robot
# pinned in a doorway behind a squadmate still contributes.
@export var sidestep_max_attempts: int = 2
var _sidestep_timer: float = 0.0
var _sidestep_attempts: int = 0


# True if the caller should hold this shot. Issues the sidestep as a side effect.
func _clear_line_of_fire() -> bool:
	if not sidestep_when_blocked or weapon == null:
		return false
	# Up to four raycasts per shot. With thirty robots firing that is the second
	# biggest cost after vision, and a careful sidestep 80m away is invisible.
	# Distant robots just take the shot; friendly fire is a third damage anyway.
	if lod_scale() > 2.0:
		return false
	if not weapon.has_method("friendly_in_line"):
		return false
	if not weapon.friendly_in_line(weapon_target):
		_sidestep_attempts = 0
		return false

	# Blocked. If we've already shuffled twice and someone is STILL in the way,
	# fire anyway — a third of damage to a squadmate beats a robot that never
	# shoots because the formation is tight.
	if _sidestep_attempts >= sidestep_max_attempts:
		return false
	if _sidestep_timer > 0.0:
		return true   # already moving out of the way; just don't fire yet

	_sidestep_timer = sidestep_cooldown
	_sidestep_attempts += 1

	# Perpendicular to the shot, whichever side has more room.
	var aim: Vector3 = weapon_target - global_position
	aim.y = 0.0
	if aim.length_squared() < 0.01:
		return false
	var lateral: Vector3 = aim.normalized().cross(Vector3.UP).normalized()
	var left: Vector3 = global_position + lateral * sidestep_distance
	var right: Vector3 = global_position - lateral * sidestep_distance
	var target_pos: Vector3 = left
	if not is_path_clear(global_position + Vector3.UP * 0.5, left, null):
		target_pos = right
	elif randf() < 0.5:
		target_pos = right

	move_to(target_pos)
	return true


# ── SQUAD CONTROL ─────────────────────────────
# True while a Squad is issuing this robot's orders. A squad member must not
# self-direct: AIState.IDLE runs _wander() on a timer and AIState.PATROL runs
# reconsider_patrol(), so a soldier who arrived at their formation slot would
# immediately wander off, get dragged back by the next follow order, and repeat.
# That loop is what reads as "they never stand still".
#
# Combat is unaffected — an engaged robot still manoeuvres for itself.
var squad_directed: bool = false


# Stop where you are. Called when a squad member is already standing in their
# slot, so nothing re-paths them onto a spot they occupy.
func halt() -> void:
	movement_state = MovementState.NONE
	if nav_agent != null:
		nav_agent.set_target_position(global_position)
	velocity.x = 0.0
	velocity.z = 0.0


# ── GUNSHOT RESPONSE ──────────────────────────
# Hearing a shot used to only set look_target and file the position away, so a
# robot would glance toward the noise and carry on patrolling. It now
# investigates, with the response scaled by distance: close enough and they come
# looking, far away and they just orient and go alert.
@export var investigate_gunshot_within: float = 20.0
# Don't re-path on every shot of a burst — one investigation per window.
@export var investigate_cooldown: float = 3.0
var _investigate_timer: float = 0.0

@export var search_duration: float = 9.0
@export var search_look_interval: float = 1.6

# ── SIGNAL INTEGRITY ──────────────────────────
# The health of this robot's networked systems.
# Degraded by suppressing fire, EMP, jamming. Recovers passively.
# Drives a cascade of behavioral degradation.
@export var signal_integrity: float = 1.0
@export var signal_recovery_rate: float = 0.08   # per second, passive recovery
@export var signal_resistance: float = 1.0       # damage multiplier. >1 = more resistant

# Never enters passive mode — set true on soldiers with active squad objectives
@export var always_active: bool = false
# Exempt from distance culling entirely: it has somewhere to be and a long way
# to go. Set by EnemyForceSpawner.wake() on reinforcements, which spawn well
# outside activation_distance and have to advance from there. A plain var
# rather than an export so it cannot be set per scene by accident, and so
# Enemy does not grow another property for an open editor to write into every
# robot scene in the game.
var never_culled: bool = false
## SHOOT WITHOUT WAITING FOR THE SIGHT PICTURE. Set from a module at spawn.
##
## Normally a robot holds its trigger until _aim_tracking passes
## _prefire_threshold(). That is why infantry that has stopped fires steadily
## at its cooldown and infantry on the move barely fires at all — the rover's
## machine gun only reads as "bursting" because a vehicle never stops long
## enough to settle, so a committed burst is the only way it can shoot.
##
## This makes that the normal state: open up anyway, in long bursts, with a
## breath between them. The spread for firing unsettled is 1/aim_floor (2.9x),
## and 3x again if moving, so this is volume and suppression, not kills.
##
## A plain var, not an export: Enemy is the base of every robot scene in the
## game and a new export on it makes an open editor write the default into all
## of them. Same reasoning as never_culled above.
var suppressive_fire: bool = false
## How long a suppressive robot breathes between bursts. Without this it
## re-commits the instant one runs out and fires forever in a flat line, which
## is neither a burst nor suppression, just a slower laser.
const SUPPRESSIVE_PAUSE := 0.45
## Bursts are longer when you are not aiming them.
const SUPPRESSIVE_BURST_SCALE := 2
## INSIDE a burst the trigger is held down, so rounds come at the weapon's
## CYCLIC rate rather than at the pace it takes aimed shots. fire_cooldown is
## the latter — 0.35s on the rifle, which is a marksman squeezing them off, not
## a weapon on automatic. A burst at that pace does not read as a burst at all.
const SUPPRESSIVE_CYCLIC := 0.3
## ...but never faster than this, or a weapon that is already quick (the
## machine gun at 0.13s) empties a hundred-round belt in three seconds.
const SUPPRESSIVE_FLOOR := 0.08
var _suppress_pause: float = 0.0
## Seconds after going down before this robot gets back up by itself, once per
## deployment. Set from the Nanite Reboot module at spawn; 0 is never.
@export var self_revive_seconds: float = 0.0
var _self_revive_used: bool = false
var _self_revive_gen: int = 0
# Seconds of blocked signal recovery left. See lock_signal().
var _signal_locked_t: float = 0.0
# The arcs coming off this one while its signal is down. Made on demand, freed
# when it recovers. See _tick_signal_vfx.
var _signal_arc: Node3D = null
# Edge flag for `ekilled` — the E-KILL check runs every frame.
var _ekill_announced: bool = false
# Set on the way down through SIGNAL_EKILL, cleared only on the way back up
# through SIGNAL_EKILL_RECOVER. See _update_ekill_latch.
var _ekill_latched: bool = false
# Whoever last put signal damage into this robot, so an e-kill can be credited.
var _signal_source: Node = null
# ...and what the playtest log was crediting at that moment ("EMP"), since the
# e-kill itself registers a frame later, when the blast has long cleared it.
var _signal_cause: String = ""
## Seconds a shot robot (and its squad) stays exempt from distance culling.
## Long enough to close on whoever is shooting and actually fight them.
@export var wake_on_damage_seconds: float = 20.0
var _woken_t: float = 0.0
# ── CLOSE THREAT ───────────────────────────────
# Opportunistic retargeting. The detection Area3D handles long-range
# acquisition; this handles "something is right next to me", which the old code
# had no concept of — reconsider_target() kept whatever target it already had as
# long as that target was alive, so a hostile that walked into arm's reach while
# you were shooting at someone 40m away was simply never noticed.
#
# Deliberately narrow. It only fires inside close_threat_range, so patrolling
# robots don't start aggroing across the level from the targeting tick; the
# Area3D still owns everything beyond a few metres.
@export var close_threat_range: float = 6.0
## How much more this robot is worth shooting than its distance says. Target
## choice divides distance by it, so at 1.15 something 11.5m away is picked like
## something 10m away.
##
## Tried on the Mechanic and taken off again: fights open with everyone about
## the same distance away, so even 1.15 made it every gun's first pick, and in
## the valley lab it was down inside two seconds, before anyone needed fixing.
## Left in for a frame that should draw fire.
@export var target_priority: float = 1.0
# How much closer the new contact has to be before it's worth switching. Without
# a margin two hostiles at similar range make the AI oscillate between them
# every targeting tick and it never shoots anything.
@export var close_threat_advantage: float = 8.0
# Don't swap onto something on the far side of a wall.
@export var close_threat_requires_los: bool = true

# What we were shooting at before a close threat interrupted. Restored when the
# close threat dies, so a squad ATTACK order survives being jumped en route.
var _preempted_target: CharacterBody3D = null

signal close_threat_engaged(target)

# Detection range used for signal-degraded sensor checks (match your Area3D radius)
@export var detection_radius: float = 20.0

# ── VISION ────────────────────────────────────
# The Area3D is a 25m sphere with no concept of facing or line of sight.
#
# Sight is a SENSOR stat, inherent to the robot — it is deliberately NOT derived
# from the weapon. Tying it to the gun would mean picking up a rifle magically
# improves your eyes, and it would leave nothing for a sensor module to upgrade.
#
# The consequence is the interesting part: default sensors (45m) are SHORTER
# than a rifle's reach (80m), so a rifle squad can out-shoot what it can't yet
# out-spot. Closing that gap is what a sensor module is for, and until you fit
# one the rifle is a gun you can't fully aim. That's a loadout decision rather
# than a bug.
#
# Note this only gates who spots FIRST. Once anyone in a squad calls contact the
# whole squad engages, so one good sensor package carries the fireteam.
@export var use_vision_cone: bool = true
@export var sensor_range: float = 45.0
# Set by modules at spawn. Additive metres.
var sensor_bonus: float = 0.0
# Total cone, degrees. Outside it you rely on peripheral_range and on hearing.
@export var fov_degrees: float = 130.0
# Anything this close is noticed regardless of facing — you don't need to be
# looking at someone standing next to you.
@export var peripheral_range: float = 8.0
# Seconds of clear, centred view before a contact is called at point blank.
@export var acquire_time: float = 0.35
# Multiplier on acquire_time at maximum range and at the edge of the cone.
# Spotting something far away and off to one side should take a beat; that beat
# is what makes who-saw-who-first feel earned rather than arbitrary.
@export var acquire_far_penalty: float = 4.0
@export var vision_interval: float = 0.15
# HARD CAP on line-of-sight raycasts per robot per vision tick.
#
# The first version scanned every hostile every tick: 35 robots x 34 candidates
# every 0.15s is ~8,000 raycasts a second, all of them on the same frames. That
# is the lag, and the fact that it spiked at the START of contact — when nobody
# has a target yet and everyone is scanning — matches exactly.
#
# You only need to notice the nearest few. Candidates are sorted by distance and
# the closest N get a raycast; the rest wait for the next tick.
@export var vision_los_checks: int = 3
# Robots far from the player think slower. Their behaviour barely reads at that
# distance, so the cost is the only thing you'd notice.
@export var lod_near_distance: float = 35.0
@export var lod_far_distance: float = 80.0
@export var lod_far_multiplier: float = 4.0
var _vision_timer: float = 0.0
var _awareness: Dictionary = {}   # body -> 0..1


# Every periodic timer starts at a random point in its cycle. Without this all
# 35 robots spawn together, tick together, and land every vision scan and
# targeting pass on the SAME frame — which is why the lag was intermittent
# rather than constant. Spreading the phase costs nothing and turns a spike
# into a flat line.
func _stagger_ai_timers() -> void:
	_vision_timer = randf() * vision_interval
	targeting_time = randf() * targeting_recon_time
	_investigate_timer = randf() * 0.5
	_sidestep_timer = randf() * 0.5
	# Without this a squad spawned in one loop resolves its paths in lockstep
	# forever, which is the spike the global budget then has to absorb every
	# single frame instead of it being spread out.
	_nav_think_timer = randf() * nav_think_interval


func sight_range() -> float:
	return maxf(4.0, sensor_range + sensor_bonus)


## How far a robot that has just lost its target will look for the next one.
## A little past what it can see, so it does not drop a target that stepped one
## metre behind a rock, and nowhere near far enough to pick a fight with
## something on the other side of the map. A constant rather than an export:
## Enemy is the base of every robot scene in the game, and a new property on it
## makes an open editor rewrite the default into all of them.
const REACQUIRE_SIGHT_SCALE := 1.25


func reacquire_range() -> float:
	return sight_range() * REACQUIRE_SIGHT_SCALE


# Polled rather than event-driven, because "can I see them" changes when EITHER
# of us moves or turns — there's no body_entered for that.
func _tick_vision(delta: float) -> void:
	if not use_vision_cone or ai_state == AIState.DEAD or downed:
		return
	var sig := get_signal_state()
	if sig == SignalState.EKILL or sig == SignalState.CRITICAL:
		return

	_vision_timer -= delta
	if _vision_timer > 0.0:
		return
	var lod: float = lod_scale()
	var elapsed: float = vision_interval * lod
	_vision_timer = elapsed

	var reach := sight_range()
	var forward: Vector3 = _sight_forward()
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var half_fov: float = deg_to_rad(fov_degrees * 0.5)

	# Cheapest tests first, and only the nearest few ever reach a raycast.
	var shortlist: Array = []
	var reach_sq: float = reach * reach
	var peripheral_sq: float = peripheral_range * peripheral_range
	for candidate in _visible_candidates():
		# queue_free() is deferred, so a body can be freed between the frame the
		# candidate list was built and the frame it is read — most obviously on
		# level unload, which crashed here. The list is also cached upstream, so
		# this loop cannot assume anything it was handed is still alive.
		if candidate == null or not is_instance_valid(candidate):
			_awareness.erase(candidate)
			continue
		var offset: Vector3 = candidate.global_position - global_position
		var dist_sq: float = offset.length_squared()
		if dist_sq > reach_sq:
			_awareness.erase(candidate)
			continue
		var flat: Vector3 = offset
		flat.y = 0.0
		var angle_to: float = forward.angle_to(flat.normalized()) if flat.length_squared() > 0.01 else 0.0
		if angle_to > half_fov and dist_sq > peripheral_sq:
			_awareness.erase(candidate)
			continue
		shortlist.append({"body": candidate, "dist_sq": dist_sq, "angle": angle_to})

	shortlist.sort_custom(func(a, b): return a["dist_sq"] < b["dist_sq"])
	var budget: int = maxi(1, vision_los_checks)

	for entry in shortlist:
		if budget <= 0:
			break
		budget -= 1
		var candidate = entry["body"]
		var distance: float = sqrt(entry["dist_sq"])
		var angle: float = entry["angle"]

		if not is_path_clear(global_position + Vector3.UP * 0.9, candidate.global_position, candidate):
			# Behind cover. Awareness decays rather than resetting, so stepping
			# in and out of cover doesn't make you permanently invisible.
			_awareness[candidate] = maxf(0.0, float(_awareness.get(candidate, 0.0)) - elapsed)
			continue

		# Centred and close acquires fast; far and peripheral takes a beat.
		var angle_factor: float = clampf(angle / maxf(half_fov, 0.01), 0.0, 1.0)
		var range_factor: float = clampf(distance / maxf(reach, 0.01), 0.0, 1.0)
		var penalty: float = 1.0 + (acquire_far_penalty - 1.0) * maxf(angle_factor, range_factor)
		var needed: float = maxf(0.05, acquire_time * penalty)

		var level: float = float(_awareness.get(candidate, 0.0)) + (elapsed / needed)
		if level < 1.0:
			_awareness[candidate] = level
			continue

		_awareness.erase(candidate)
		if ai_state != AIState.COMBAT:
			trigger_combat(candidate)
			combat_triggered.emit(self)
		elif not has_live_target():
			change_combat_target(candidate)
		return   # one contact per tick is plenty


# How near its slot counts as in position, given the squad's own tolerance. A
# robot on legs walks onto the spot; something that cannot creep onto an exact
# point answers with how near it parks, or the squad re-orders it forever.
func slot_tolerance(squad_tolerance: float) -> float:
	return squad_tolerance


# How much lateral room this frame needs in a formation line. 0 means "the
# squad's own spacing is fine", which is true of anything that walks. A wide
# hull answers with what it actually needs; see Squad._line_spacing.
func formation_width() -> float:
	return 0.0


# Which way this robot is looking. The body's facing for anything that turns its
# whole self to look; a vehicle looks with its turret, not its hull.
func _sight_forward() -> Vector3:
	return -global_transform.basis.z


# 1.0 close to the player, rising to lod_far_multiplier out at lod_far_distance.
# Squad members are always full fidelity — you're looking straight at them and
# any hitch in their behaviour is the most visible thing on screen.
func lod_scale() -> float:
	if squad_directed and not Enums.are_hostile(Enums.Factions.PLAYER, faction):
		return 1.0
	if player == null:
		return 1.0
	var d: float = global_position.distance_to(player.get_focus_position())
	if d <= lod_near_distance:
		return 1.0
	if d >= lod_far_distance:
		return lod_far_multiplier
	var t: float = (d - lod_near_distance) / maxf(lod_far_distance - lod_near_distance, 0.01)
	return lerpf(1.0, lod_far_multiplier, t)


# Uses AIManager's cached per-faction list rather than re-filtering every
# registered body on every tick, for every robot.
func _visible_candidates() -> Array:
	if ai_manager == null:
		if player != null and player.alive and _is_hostile(player) and player.is_targetable():
			return [player]
		return []
	if ai_manager.has_method("hostiles_for"):
		return ai_manager.hostiles_for(faction)

	var out: Array = []
	for other in ai_manager.all_ai:
		if other == null or other == self or not is_instance_valid(other):
			continue
		if not other.alive or not _is_hostile(other):
			continue
		out.append(other)
	return out

# ── ENUMS ─────────────────────────────────────
# NOTE: ordering is load-bearing. Scenes store these as raw ints.
enum AIState { COMBAT, PATROL, SEARCH, IDLE, DEAD, PASSIVE }
enum MovementState { NONE, MOVING, LEAPING, ADVANCING, CHASING }
enum WeaponState { FIRE, RELOAD, AIM, IDLE }
enum CombatOptions { MOVE, AIM, FIRE }
enum MovementOptions { ADVANCE, REPOSITION, FALLBACK, LEAP, CHASE }

# Signal degradation stages
## Emitted on the FRAME a robot crosses into E-KILL, once, with whoever last
## put signal damage into it. AIManager relays this so the HUD and the playtest
## log can hear about every robot in the level from one place.
signal ekilled(victim: Enemy, by: Node)

enum SignalState { CLEAN, FUZZED, DEGRADED, CRITICAL, EKILL }
const SIGNAL_FUZZED: float   = 0.75  # below here: accuracy penalty kicks in
const SIGNAL_DEGRADED: float = 0.50  # below here: sensors halved, movement stutters
const SIGNAL_CRITICAL: float = 0.25  # below here: ignores squad orders, erratic
const SIGNAL_EKILL: float    = 0.01  # below here: fully disabled
## ...and it STAYS disabled until signal has climbed back to here. The same
## shape as revive_at_fraction on a downed robot: going out takes one threshold,
## coming back takes another. Without it an e-kill was a flinch — recovery is
## 0.08/s, so a robot knocked to zero ticked back over 0.01 in an eighth of a
## second once its lock ran out and was fighting again. Now it is out for about
## six seconds after the lock, and it comes back at the top of DEGRADED — in
## practice FUZZED, since release is the first frame at or over 0.50 and
## DEGRADED ends at exactly 0.50 — then climbs to CLEAN the ordinary way.
const SIGNAL_EKILL_RECOVER: float = 0.50

@export var DefaultAIState: AIState
@export var AllowedMovementOptions: Array[MovementOptions]
@export var AllowedCombatOptions: Array[CombatOptions]

# ── CONST ─────────────────────────────────────
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
## Falling faster than this (m/s) means the robot has left the level: it goes
## down rather than falling forever. 0 disables.
@export var fell_out_speed: float = 50.0
var _leap_cooldown_t: float = 0.0

# ── MANAGER REFS ──────────────────────────────
var player: Player
var ai_manager: AIManager


# NOTHING WAS EVER DEREGISTERING. register_enemy() is called by the spawner, but
# deregister_enemy() had no callers anywhere in the project — the only cleanup
# was reset_all_reg_enemies() at level load. So every robot destroyed mid-mission
# stayed in all_ai as a freed reference, and the next get_nearest_hostile() walked
# over it and read `alive` off a corpse:
#   "Invalid access to property 'alive' on a base object of type 'previously freed'"
#
# It also meant all_ai grew for the whole mission, so the O(n) hostile scan got
# steadily slower the more things you killed.
func _exit_tree() -> void:
	if ai_manager != null and is_instance_valid(ai_manager):
		ai_manager.deregister_enemy(self)
var stimulus_manager: StimulusManager

# ── WORKING DATA ──────────────────────────────
var damaged_by_player: bool = false
var idle_to_wander = 3
var movement_recon_time = 1.5
var targeting_recon_time = 0.33
var weapon_recon_time = 1.5
var patrol_recon_time = 1.5
var chasing_recon_time = 0.2
var wander_delay = 1.5
var wander_radius = 3.5

var checking_for_target: bool = false
var ai_state = AIState.COMBAT
var movement_state = MovementState.NONE
var weapon_state = WeaponState.IDLE
var activation_distance_sq: float

var previous_combat_option: CombatOptions = CombatOptions.MOVE
var previous_movement_option: MovementOptions = MovementOptions.ADVANCE

var combat_target: CharacterBody3D
var movement_target: Vector3
var weapon_target: Vector3
var look_target: Vector3
var patrol_points: Array[Node3D] = []
var spawn_transform
var alive: bool = true

# ── DOWNED ────────────────────────────────────
# Robots don't die outright — they collapse and stay on the deck as a wreck that
# can be brought back with the repair tool. `alive` still goes false, which is
# what every targeting, squad and objective check already keys off, so nothing
# downstream has to learn a third state. `downed` is the extra bit that says the
# wreck is recoverable.
#
# Enemies collapse too. The repair tool only targets friendlies, so a downed
# hostile is just scrap on the floor — but it means every kill leaves a body,
# which is what a salvage economy would eventually hang off.
@export var can_be_downed: bool = true
# Repaired back to this fraction of max_health and they stand up.
@export var revive_at_fraction: float = 0.5
# Where health sits while down. Above zero so the repair maths has something to
# climb from.
@export var downed_health: int = 1
# How far the model tips over. Purely cosmetic — the body doesn't rotate,
# because that would drag the collision capsule and the nav agent with it.
@export var collapse_pitch_degrees: float = 84.0
@export var collapse_drop: float = 0.5
# The collider has to go down with the model. Tipping only the meshes leaves an
# upright 2m capsule standing where the robot was, so a corpse keeps blocking
# rounds at head height — worse, it becomes invisible cover, since nothing is
# drawn there any more.
#
# The SHAPE is untouched (shapes are shared resources between instances and
# editing one would flatten every robot in the level). The CollisionShape3D NODE
# is rotated instead, which lays the capsule on its side for free.
@export var flatten_collider_when_downed: bool = true

# ── SETTLING ──────────────────────────────────
# A prone collider is still something to trip over, and squads walking a line
# over a pile of wrecks jam on them. After a short beat the body sinks partway
# into the deck and its collider switches off entirely, so it becomes scenery
# you walk through rather than terrain you path around.
#
# It stays VISIBLE and stays revivable. The repair tool doesn't need a collider
# to find an ally — PlayerRepairTool falls back to a proximity cone around the
# crosshair precisely because a body on the floor is a miserable ray target.
@export var settle_after: float = 1.2
@export var settle_duration: float = 1.0
@export var settle_depth: float = 0.45
# Enemies sink further and faster — nobody is coming back for them, so the only
# job left is to stop being an obstacle.
@export var settle_depth_hostile: float = 0.7

var _settle_timer: float = 0.0
var _settling: bool = false
var _crashing: bool = false
var _crash_timeout: float = 0.0
## How much of its speed a robot killed in mid-air keeps on the way down, and
## how fast the rest bleeds off (per second). Constants rather than exports:
## adding a property to Enemy makes an open editor rewrite defaults into every
## robot scene in the game, and nothing here wants tuning per frame.
const CRASH_MOMENTUM: float = 0.85
const CRASH_DRAG: float = 0.6
# What a wreck has been let fall through — whatever it went down standing on
# that is not the level itself. Given back when it stands up.
var _fell_through: Array[PhysicsBody3D] = []
var _settled: bool = false
var _settle_rest_y: float = 0.0
var _collider_rest: Transform3D
var _collider_flattened: bool = false

var downed: bool = false
var _piece_rest: Dictionary = {}   # Node3D -> original Transform3D

signal went_down
signal revived
## Gone for good, not merely on the floor: what a director counts when it is
## watching for losses. enter_downed() emits went_down instead, and a robot
## that cannot be downed (a building) only ever gets here.
signal destroyed

var combat_time: float = 0.0
var movement_time: float = 0.0
var search_time: float = 0.0
var patrol_time: float = 0.0
var fire_time: float = 0.0
var weapon_time: float = 0.0
var wander_time: float = 0.0
var targeting_time: float = 0.0
var idle_time: float = 0.0
var chasing_time: float = 0.0

var last_seen_point: Array[Vector3] = []
var seen_bodies: Array = []
var frame_waited: bool = false

# ── EQUIPMENT ─────────────────────────────────
var _equipment_cooldowns: Dictionary = {}
# Last equipment use, for the squad HUD readout. See the assignment in the
# equipment block for why this is a timestamp rather than a state.
var _last_equipment_ms: int = -100000
var _last_equipment_label: String = ""


func seconds_since_equipment() -> float:
	return (Time.get_ticks_msec() - _last_equipment_ms) / 1000.0


func last_equipment_label() -> String:
	return _last_equipment_label
var _target_stationary_time: float = 0.0
var _target_last_position: Vector3 = Vector3.ZERO
const EQUIPMENT_RECON_TIME: float = 1.5
var _equipment_recon_timer: float = 0.0

# ── STUCK DETECTION ───────────────────────────
const STUCK_CHECK_INTERVAL: float = 3.0
const STUCK_MOVE_THRESHOLD: float = 0.5
var _stuck_timer: float = 0.0
var _stuck_last_position: Vector3 = Vector3.ZERO
var _stuck_retry_count: int = 0

# ── NO-LOS TIMER ──────────────────────────────
const NO_LOS_PATIENCE: float = 4.0
var _no_los_timer: float = 0.0

# ── LOS CACHE ─────────────────────────────────
# One raycast per interval, shared by weapon logic, the no-LOS timer and
# the deferred-detection check. Previously each of those raycast separately,
# every frame, per AI.
const LOS_CHECK_INTERVAL: float = 0.15
var _has_los: bool = false
var _los_check_timer: float = 0.0

# ── AIM / BURST ───────────────────────────────
var _aim_tracking: float = 0.0
var _burst_left: int = 0

# ── FACING ────────────────────────────────────
var _last_move_dir: Vector3 = Vector3.ZERO

# ── SEARCH / WANDER ───────────────────────────
var _search_look_timer: float = 0.0
var _next_wander_at: float = 3.0

# ── LOS SEEK BUDGET ───────────────────────────
# One ring per call rather than four, so a squad losing LOS at the same
# moment doesn't spike the frame.
const SEEK_RING_RADII := [1.0, 1.5, 2.5, 4.0]
var _seek_ring_index: int = 0

# ── CACHED NODES ──────────────────────────────
var _collision_shape: CollisionShape3D = null
var _self_rid: RID

# ── SIGNAL WORKING STATE ──────────────────────
# Tracks stuttering for DEGRADED movement hesitation
var _signal_stutter_timer: float = 0.0
const SIGNAL_STUTTER_INTERVAL: float = 0.8  # how often to check for stutter

signal combat_triggered(ai: AI)


# ─────────────────────────────────────────────
# INIT
# ─────────────────────────────────────────────
func initialize():
	spawn_transform = transform
	activation_distance_sq = activation_distance * activation_distance
	_self_rid = get_rid()
	_collision_shape = _find_collision_shape()

	# PATH POINTS ARE JUDGED AT BODY HEIGHT. The nav agent counts a point
	# reached within path_desired_distance in 3D, from this node's origin —
	# the middle of a soldier's capsule, a metre above its feet — to a point on
	# the navmesh, which lies anywhere from just under the real ground to most
	# of a metre over it. A point under the ground was more than a metre away
	# with the robot standing on it, so it was never reached: the robot stopped
	# dead on it, and every squadmate whose path ran through the same point
	# queued up behind. That was Coast Road's whole squad, stuck on open
	# ground. Lifting the path by the depth of the feet leaves only the
	# navmesh's own height error in the gap.
	if nav_agent != null:
		nav_agent.path_height_offset = -_Ground.foot_depth(self)

	# Desynchronise decision cadence per character. Without this every
	# soldier in a squad re-rolls on exactly the same frame.
	combat_recon_time *= randf_range(1.0 - recon_jitter, 1.0 + recon_jitter)
	combat_time = randf() * combat_recon_time
	targeting_time = randf() * targeting_recon_time
	_los_check_timer = randf() * LOS_CHECK_INTERVAL
	_next_wander_at = wander_delay + randf_range(0.0, float(idle_to_wander))

	await get_tree().process_frame
	ai_state = DefaultAIState
	frame_waited = true
	for slot in equipment_slots:
		slot.initialize()
	if weapon != null and not weapon.reload_finished.is_connected(_on_reload_finished):
		weapon.reload_finished.connect(_on_reload_finished)
	reconsider_target()

func _find_collision_shape() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child
	return null


# ─────────────────────────────────────────────
# PHYSICS PROCESS
# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	# Downed robots run NOTHING except the sink, and once that finishes the tick
	# disables itself — so a battlefield full of wrecks costs zero per frame
	# rather than a permanent _process each. This branch is why enter_downed()
	# leaves physics running instead of switching it off immediately.
	if downed:
		# A WRECK THAT DIED IN THE AIR HAS TO FALL FIRST. _begin_settle() records
		# the body's current height as the rest height and sinks from there, so
		# a leaper killed mid-leap or a quadcopter bomber shot out of the sky settled into
		# thin air and hung there. Crash, land, and only then start settling.
		if _crashing:
			velocity.y -= gravity * delta
			velocity.x = lerp(velocity.x, 0.0, 1.0 - exp(-CRASH_DRAG * delta))
			velocity.z = lerp(velocity.z, 0.0, 1.0 - exp(-CRASH_DRAG * delta))
			move_and_slide()
			var landed := is_on_floor() and not _step_off_bodies()
			if landed or _crash_timeout <= 0.0:
				_crashing = false
				_on_crash_landed()
				_begin_settle()
			_crash_timeout -= delta
			return
		if _settling:
			_tick_settle(delta)
		else:
			set_physics_process(false)
		return

	if not frame_waited or ai_state == AIState.DEAD:
		return
	if player == null:
		return

	handle_gravity(delta)

	# Signal always ticks, even when passive or disabled, so a robot can
	# actually recover from an e-kill instead of being bricked forever.
	_tick_signal(delta)

	# E-KILL: electronically disabled — freeze in place, do nothing
	if get_signal_state() == SignalState.EKILL:
		_enter_ekill()
		_apply_motion()
		return

	# The player's own side is never culled. Passive mode zeroes velocity and
	# points the nav agent at the unit's own feet, so a soldier who falls more
	# than activation_distance (75m) behind can never close the gap on his own
	# — he stands there until the player happens to walk back to him. Order him
	# to a far objective and he freezes partway.
	#
	# The check has to be HERE rather than inside enter_passive_mode(), which
	# already honours always_active: the return below skips handle_movement,
	# handle_weapon_logic and _update_facing, so gating only the state change
	# leaves the unit's flags correct while its brain still stops running.
	#
	# Faction rather than always_active because reset() clears that flag, so a
	# soldier respawned or repaired since his last order was unprotected — and
	# because faction cannot be missed by a future code path that forgets to
	# set it. Hostiles are deliberately left culled; they are the population
	# that makes distance culling worth having.
	#
	# WOKEN robots are exempt too. Player hitscan reaches 250m and a chaser's
	# activation distance is 75m, so anything between the two could be shot to
	# death without ever running a physics tick: apply_damage is not gated by
	# physics, but everything that would make it RESPOND is. It died standing
	# still. Being shot now wakes it, and its squad, for wake_on_damage_seconds.
	if _woken_t > 0.0:
		_woken_t = maxf(0.0, _woken_t - delta)
	# AND SO IS ANYTHING MARKED never_culled.
	#
	# Reinforcements are spawned 90m out precisely so you watch them come, and
	# they stood exactly where they landed until the player walked within 75m
	# of them: enter_passive_mode() honours a flag, but the `return` below
	# skipped handle_movement regardless, so the freeze happened anyway.
	#
	# This is deliberately NOT always_active, which every EnemySquadSpec in
	# every mission sets — hanging the exemption on that made all seventy
	# robots in the Foundry tick from the far side of the valley, for the
	# benefit of the five squads that needed it. EnemyForceSpawner.wake() sets
	# this on the squads it sends in, and nothing else does.
	var dist_sq = global_position.distance_squared_to(player.global_position)
	if dist_sq > activation_distance_sq and not _is_player_side() \
			and not never_culled and _woken_t <= 0.0:
		enter_passive_mode()
		_apply_motion()
		return
	else:
		exit_passive_mode()

	_tick_los(delta)
	if checking_for_target and combat_target != null and _has_los:
		trigger_combat(combat_target)
	handle_time_passing(delta)
	handle_movement(delta)
	_update_facing(delta)
	handle_weapon_logic(delta)
	_apply_motion()


# ─────────────────────────────────────────────
# MOTION
# Single move_and_slide per frame, at the end.
# Previously it only ran inside move_along_nav / handle_leap, so a
# stationary AI accumulated velocity.y forever and never refreshed
# is_on_floor().
# ─────────────────────────────────────────────
func _apply_motion() -> void:
	# Cheap out for a settled passive body — nothing to resolve.
	if ai_state == AIState.PASSIVE and is_on_floor() and velocity.length_squared() < 0.01:
		return

	move_and_slide()

	# Leap landing is detected here now, after the move has resolved.
	if movement_state == MovementState.LEAPING and is_on_floor() and velocity.y <= 0.0:
		movement_state = MovementState.NONE
		velocity = Vector3.ZERO
		# Started on LANDING, not on takeoff, so the flight itself never eats
		# into the gap. Without it the roll below picked LEAP again the instant
		# they touched down — nothing stopped a hopper chaining leap after leap
		# for as long as the target stayed in band.
		_leap_cooldown_t = leap_cooldown
		roll_combat_action()


# ─────────────────────────────────────────────
# LOS CACHE
# ─────────────────────────────────────────────
func _tick_los(delta: float) -> void:
	_los_check_timer -= delta
	if _los_check_timer > 0.0:
		return
	_los_check_timer = LOS_CHECK_INTERVAL

	var had_los = _has_los
	if combat_target == null or not combat_target.alive:
		_has_los = false
	else:
		_has_los = is_path_clear(
			global_position + Vector3.UP * 0.8,
			combat_target.global_position,
			combat_target)
		# Remember where they were the moment we lost sight of them.
		# This is what SEARCH now runs on.
		if had_los and not _has_los:
			_remember_last_seen(combat_target.global_position)

func _remember_last_seen(pos: Vector3) -> void:
	last_seen_point.append(pos)
	if last_seen_point.size() > 4:
		last_seen_point.remove_at(0)


# ─────────────────────────────────────────────
# PASSIVE MODE
# ─────────────────────────────────────────────
# Anything fighting on the player's side. NEUTRAL is deliberately excluded —
# scenery robots are exactly the thing distance culling exists for.
func _is_player_side() -> bool:
	return faction == Enums.Factions.PLAYER or faction == Enums.Factions.ALLIED


## Exempt from distance culling for `seconds`. Called on taking damage, and by
## Squad on every member when any one of them enters combat — so shooting one
## robot at long range brings its whole squad, rather than one reaction and a
## group of statues standing beside it.
func wake(seconds: float) -> void:
	_woken_t = maxf(_woken_t, seconds)


func enter_passive_mode():
	if ai_state == AIState.PASSIVE:
		return
	if always_active or _is_player_side():
		return
	change_ai_state(AIState.PASSIVE)
	velocity.x = 0
	velocity.z = 0
	movement_state = MovementState.NONE
	weapon_state = WeaponState.IDLE
	nav_agent.set_target_position(global_position)

func exit_passive_mode():
	if ai_state != AIState.PASSIVE:
		return
	change_ai_state(DefaultAIState)
	# Re-issue movement if we had an active target before going passive
	if movement_target != Vector3.ZERO:
		move_to(movement_target)


# ─────────────────────────────────────────────
# TIME PASSING
# ─────────────────────────────────────────────
func handle_time_passing(delta):
	if _leap_cooldown_t > 0.0:
		_leap_cooldown_t = maxf(0.0, _leap_cooldown_t - delta)
	weapon_time += delta
	targeting_time += delta
	if movement_state == MovementState.MOVING:
		movement_time += delta

	match ai_state:
		AIState.COMBAT:
			combat_time += delta
			if combat_time >= combat_recon_time:
				reconsider_combat()
			# Track time without LOS — if too long, seek a new position.
			# Uses the cached LOS result now instead of its own raycast.
			if combat_target != null and combat_target.alive:
				if not _has_los:
					_no_los_timer += delta
					if _no_los_timer >= NO_LOS_PATIENCE:
						_no_los_timer = 0.0
						_seek_los_position()
				else:
					_no_los_timer = 0.0
		AIState.PATROL:
			patrol_time += delta
			# A squad on SquadObjective.PATROL walks its route as a unit; an
			# individual also re-picking patrol points fights it.
			if not squad_directed and patrol_time >= patrol_recon_time:
				reconsider_patrol()
		AIState.IDLE:
			idle_time += delta
			if squad_directed:
				# Standing in formation is a valid thing to be doing.
				idle_time = 0.0
				_tick_idle_scan(delta)
			elif idle_time >= _next_wander_at:
				idle_time = 0.0
				_next_wander_at = wander_delay + randf_range(0.0, float(idle_to_wander))
				_wander()
		AIState.SEARCH:
			search_time += delta
			_tick_search(delta)
			if search_time >= search_duration:
				_end_search()

	if _investigate_timer > 0.0:
		_investigate_timer = maxf(0.0, _investigate_timer - delta)
	if _sidestep_timer > 0.0:
		_sidestep_timer = maxf(0.0, _sidestep_timer - delta)
	_tick_vision(delta)
	_tick_travel_look(delta)

	if targeting_time >= targeting_recon_time * lod_scale():
		reconsider_target()

	if ai_state == AIState.COMBAT and not equipment_slots.is_empty():
		_tick_equipment(delta)



# ─────────────────────────────────────────────
# GRAVITY / MOVEMENT
# ─────────────────────────────────────────────
func handle_gravity(delta: float) -> void:
	if is_on_floor():
		# Zero out accumulated fall speed instead of letting it grow.
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
		# FELL OUT OF THE WORLD. Nothing else catches this: a leaper that
		# clips through the floor falls forever, still `alive`, and an
		# EliminateObjective waits on it for the rest of the mission — the
		# arena reading 7/8 with nothing left standing. No leap or crash comes
		# near this speed; five seconds of free fall does.
		if fell_out_speed > 0.0 and velocity.y < -fell_out_speed and alive:
			push_warning("%s fell out of the world at %s; counting it as down." % [name, global_position])
			die()

# ─────────────────────────────────────────────
# HOLD STILL
# ─────────────────────────────────────────────
# Stops TRANSLATION only. The robot keeps facing, aiming and firing — it just
# doesn't walk off while you're working on it.
#
# The gate sits in handle_movement() rather than in move_to(), because cover
# seeking, bounding and chasing all set nav targets by different routes
# (set_target_position directly in three places). handle_movement is the one
# funnel every one of them passes through, so gating here catches all of them
# without hunting down each caller.
#
# move_to() is ALSO gated, so a held robot doesn't burn pathfinding on orders it
# can't act on — and so the last order is replayed on release rather than lost.
var _hold_count: int = 0
var _hold_timer: float = 0.0
var _pending_move: Vector3 = Vector3.ZERO
var _has_pending_move: bool = false
# Safety release. Without it, anything that grabs a hold and then gets freed
# before releasing leaves a robot frozen for the rest of the mission.
@export var max_hold_time: float = 30.0

signal hold_started
signal hold_released


func is_held() -> bool:
	return _hold_count > 0


# Reference counted, so two things holding the same robot don't release each
# other early.
func hold_still() -> void:
	_hold_count += 1
	_hold_timer = 0.0
	if _hold_count == 1:
		hold_started.emit()


func release_hold() -> void:
	if _hold_count <= 0:
		return
	_hold_count -= 1
	if _hold_count > 0:
		return
	hold_released.emit()
	# Resume whatever was asked for while we were pinned.
	if _has_pending_move:
		_has_pending_move = false
		var pos := _pending_move
		_pending_move = Vector3.ZERO
		move_to(pos)


func force_release_hold() -> void:
	_hold_count = 0
	_has_pending_move = false


func _tick_hold(delta: float) -> void:
	if _hold_count <= 0:
		return
	_hold_timer += delta
	if max_hold_time > 0.0 and _hold_timer >= max_hold_time:
		push_warning("%s: hold exceeded %.0fs, force-releasing." % [name, max_hold_time])
		force_release_hold()
		hold_released.emit()


func handle_movement(delta):
	_tick_hold(delta)

	if is_held():
		# Same deceleration curve MovementState.NONE uses, so a pinned robot
		# coasts to a stop instead of snapping, and reads as deliberate.
		var hold_t = 1.0 - exp(-acceleration * delta)
		velocity.x = lerp(velocity.x, 0.0, hold_t)
		velocity.z = lerp(velocity.z, 0.0, hold_t)
		_stuck_timer = 0.0
		return

	match movement_state:
		MovementState.NONE:
			# Decelerate through the same curve as acceleration rather than
			# snapping to zero. Instant stops are most of the "mechanical" read.
			var t = 1.0 - exp(-acceleration * delta)
			velocity.x = lerp(velocity.x, 0.0, t)
			velocity.z = lerp(velocity.z, 0.0, t)
			_stuck_timer = 0.0
			_stuck_retry_count = 0
		MovementState.MOVING:
			_tick_nav(delta)
			if _nav_finished:
				var dist_to_target = global_position.distance_to(movement_target)
				if dist_to_target < arrival_radius:
					# Actually arrived — normal completion
					reconsider_movement()
					_stuck_timer = 0.0
					_stuck_retry_count = 0
				else:
					# Nav says done but we're NOT there — path is blocked
					var t = 1.0 - exp(-acceleration * delta)
					velocity.x = lerp(velocity.x, 0.0, t)
					velocity.z = lerp(velocity.z, 0.0, t)
					_handle_path_blocked()
			else:
				move_along_nav(delta)
				_check_stuck(delta)
		MovementState.LEAPING:
			pass  # ballistic — gravity and landing handled in _apply_motion
		MovementState.CHASING:
			handle_chasing(delta)

func _check_stuck(delta: float) -> void:
	_stuck_timer += delta
	if _stuck_timer < STUCK_CHECK_INTERVAL:
		return
	_stuck_timer = 0.0
	var moved = global_position.distance_to(_stuck_last_position)
	_stuck_last_position = global_position
	if moved > STUCK_MOVE_THRESHOLD:
		_stuck_retry_count = 0
		return
	# Still here — hand off to path blocked handler
	velocity.x = 0
	velocity.z = 0
	_handle_path_blocked()

func move_to(pos: Vector3):
	# Pinned. Remember where we were told to go and replay it on release.
	if is_held():
		_pending_move = pos
		_has_pending_move = true
		return
	nav_agent.set_target_position(pos)
	_nav_think_timer = 0.0  # new destination: refresh the cached direction now
	movement_target = pos
	movement_state = MovementState.MOVING
	movement_time = 0
	_stuck_timer = 0.0
	_stuck_last_position = global_position
	_stuck_retry_count = 0

# NAV QUERIES ARE TICKED OUT, NOT RUN EVERY FRAME.
#
# get_next_path_position() is where NavigationAgent3D actually resolves the
# path, and this used to call it once per moving robot per frame. Profiled at
# 381ms across 25 calls — roughly 15ms each — because a chasing melee unit
# re-resolves against a moving target and an agent standing off the navmesh
# searches hard before giving up.
#
# The direction is refreshed on a stagger instead and steered along in between.
# At 0.15s and 4.5 m/s a robot travels 0.67m between refreshes, which is well
# inside the 0.15m arrival threshold's tolerance and invisible in motion.
#
# TWO gates, because either alone leaves a hole: a per-robot interval (scaled by
# lod_scale, so distant robots refresh far less often) and a global per-frame
# budget so a single frame can never contain more than a fixed number of path
# resolutions no matter how many robots want one.
@export var nav_think_interval: float = 0.15
## Path resolutions allowed across ALL robots in one physics frame. Anything
## over budget steers on its cached direction and asks again next frame.
@export var nav_queries_per_frame: int = 8

static var _nav_budget: int = 0
static var _nav_budget_frame: int = -1

var _nav_dir: Vector3 = Vector3.ZERO
var _nav_think_timer: float = 0.0
var _nav_finished: bool = false


# BOTH nav queries live here, and nothing else may call the agent per frame.
#
# is_navigation_finished() is not a cheap flag read — it calls the agent's
# _update_navigation() internally, exactly like get_next_path_position(). The
# first version of this throttled the position query and left its twin running
# every frame at the top of the MOVING branch, which halved the per-call cost
# and left the other half intact. Keeping them together is the only way the
# budget means anything.
func _tick_nav(delta: float) -> void:
	_nav_think_timer -= delta
	if _nav_think_timer > 0.0:
		return
	if not _take_nav_query(nav_queries_per_frame):
		return
	_nav_think_timer = nav_think_interval * lod_scale()
	_nav_finished = nav_agent.is_navigation_finished()
	var fresh: Vector3 = nav_agent.get_next_path_position() - global_position
	fresh.y = 0
	_nav_dir = fresh


static func _take_nav_query(budget: int) -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _nav_budget_frame:
		_nav_budget_frame = frame
		_nav_budget = maxi(1, budget)
	if _nav_budget <= 0:
		return false
	_nav_budget -= 1
	return true


func move_along_nav(delta):
	# Queries happen in _tick_nav only; this just steers on the cached result.
	var path_dir = _nav_dir
	var t = 1.0 - exp(-acceleration * delta)
	if path_dir.length() < 0.15:
		velocity.x = lerp(velocity.x, 0.0, t)
		velocity.z = lerp(velocity.z, 0.0, t)
		return
	var base_dir = path_dir.normalized()
	_last_move_dir = base_dir
	var target_velocity = base_dir * move_speed
	velocity.x = lerp(velocity.x, target_velocity.x, t)
	velocity.z = lerp(velocity.z, target_velocity.z, t)
	# NOTE: rotation is no longer set here. Facing is decoupled from
	# movement so the body can strafe and backpedal while aiming.

func handle_chasing(delta):
	if combat_target == null or not combat_target.alive:
		movement_state = MovementState.NONE
		return

	# Stop chasing once we're close enough to engage from here
	var dist_to_target = global_position.distance_to(combat_target.global_position)
	if dist_to_target <= _max_range() * 0.7:
		movement_state = MovementState.NONE
		return

	chasing_time += delta
	if chasing_time >= chasing_recon_time:
		chasing_time = 0
		nav_agent.set_target_position(combat_target.global_position)
		_nav_think_timer = 0.0  # new destination: refresh the cached direction now

	_tick_nav(delta)
	move_along_nav(delta)
	_check_stuck(delta)

func _update_facing(delta: float) -> void:
	# The core fix for "faces where it walks while shooting sideways".
	# In combat the body tracks the target; movement direction is
	# independent, which gives strafing and backpedalling for free.
	var face_dir := _desired_facing()
	if face_dir == Vector3.ZERO:
		return   # nothing to look at and never moved: keep the facing it has
	var target_yaw = atan2(-face_dir.x, -face_dir.z)
	var t = 1.0 - exp(-rotation_speed * delta)
	rotation.y = lerp_angle(rotation.y, target_yaw, t)

# Which way to look, flat and normalised, or ZERO for nowhere in particular.
# The target in a fight, else what it was told to watch, else where it last
# walked. Shared with anything that aims a part of itself rather than its body.
func _desired_facing() -> Vector3:
	var face_dir := Vector3.ZERO
	if ai_state == AIState.COMBAT and combat_target != null and combat_target.alive:
		face_dir = combat_target.global_position - global_position
	elif weapon_target != Vector3.ZERO and ai_state == AIState.COMBAT:
		face_dir = weapon_target - global_position
	elif look_target != Vector3.ZERO and global_position.distance_squared_to(look_target) > 0.04:
		face_dir = look_target - global_position
	elif _last_move_dir.length_squared() > 0.0001:
		face_dir = _last_move_dir
	face_dir.y = 0.0
	if face_dir.length_squared() < 0.0001:
		return Vector3.ZERO
	return face_dir.normalized()


func _is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length() > 0.6


# ─────────────────────────────────────────────
# WEAPON LOGIC
# Now aware of magazines, reloads, sight-picture settling and
# committed bursts.
# ─────────────────────────────────────────────
func handle_weapon_logic(delta):
	if fire_time > 0.0:
		fire_time -= delta
	if _suppress_pause > 0.0:
		_suppress_pause -= delta
	if weapon == null:
		return
	if ai_state != AIState.COMBAT:
		weapon_state = WeaponState.IDLE
		_aim_tracking = 0.0
		_burst_left = 0
		return

	# Reload is now a real state the AI reacts to, rather than the weapon
	# silently refusing to fire while the AI kept cycling FIRE.
	if weapon.is_reloading:
		weapon_state = WeaponState.RELOAD
		_aim_tracking = 0.0
		_burst_left = 0
		return
	if weapon.needs_reload():
		weapon.start_reload()
		_on_reload_started()
		return

	# Tracking builds while settled with LOS, decays while moving.
	if _has_los and combat_target != null:
		if _is_moving():
			_aim_tracking = maxf(0.0, _aim_tracking - delta * 1.5)
		else:
			_aim_tracking = minf(aim_settle_time, _aim_tracking + delta)
	else:
		_aim_tracking = maxf(0.0, _aim_tracking - delta * 2.0)

	if weapon_time >= weapon_recon_time:
		reconsider_weapon()

	var dist = global_position.distance_to(weapon_target)
	var max_range = _max_range()
	var min_range = weapon.min_effective_range

	match weapon_state:
		WeaponState.IDLE, WeaponState.RELOAD:
			weapon_state = WeaponState.AIM
		WeaponState.AIM:
			if fire_time > 0.0:
				return
			if combat_target == null:
				return
			if not _has_los and not _can_fire_without_los():
				return
			if dist > max_range or dist < min_range:
				return
			# A committed burst fires immediately. Otherwise wait for a
			# sight picture proportional to range — snap shots up close,
			# a real pause before a long shot.
			if _burst_left <= 0 and _aim_tracking < _prefire_threshold():
				# SUPPRESSIVE FIRE does not wait for a sight picture — it is
				# the whole point of the module. Everything else about the
				# engagement still applies: line of sight, range, ammunition.
				if not suppressive_fire or _suppress_pause > 0.0:
					return
				_commit_burst()
			if not _weapon_on_target():
				return   # still slewing onto it
			weapon_state = WeaponState.FIRE
		WeaponState.FIRE:
			if fire_time <= 0.0:
				fire()
				fire_time = weapon.fire_cooldown
				if _burst_left > 0:
					_burst_left -= 1
					if suppressive_fire:
						if _burst_left > 0:
							# Still on the trigger: cyclic rate, not aimed pace.
							fire_time = maxf(weapon.fire_cooldown * SUPPRESSIVE_CYCLIC,
								SUPPRESSIVE_FLOOR)
						else:
							# Burst spent: breathe, then open up again.
							_suppress_pause = SUPPRESSIVE_PAUSE
				weapon_state = WeaponState.AIM

# Whether the gun is actually pointing at weapon_target. A robot turns its whole
# body and fires down its facing, so for one of those it always is. A turret
# has to traverse onto the target first, and firing while it swings is what
# would make one read as fake.
func _weapon_on_target() -> bool:
	return true


func _prefire_threshold() -> float:
	if weapon == null:
		return 0.0
	var d = global_position.distance_to(weapon_target)
	var ratio = clampf(d / maxf(_max_range(), 0.01), 0.0, 1.0)
	return aim_settle_time * ratio * 0.8

## Overridden by Soldier so a SUPPRESSING soldier can put rounds onto a
## position it can't currently see.
func _can_fire_without_los() -> bool:
	return false

# How far away this robot considers itself able to engage.
#
# A MELEE weapon's reach is melee_range, NOT max_effective_range — ai-wep_melee
# overrides neither, so it inherited AIWeapon's 70m default and every chaser and
# leaper decided it was "in range" at 49m (_max_range * 0.7), stopped dead, and
# swung a knife at nothing. They never closed, and the leaper never got near
# enough to leap either.
func _max_range() -> float:
	if weapon == null:
		return 30.0
	if weapon.weapon_type == Enums.AIWeaponTypes.MELEE:
		return maxf(weapon.melee_range, 1.0)
	return weapon.max_effective_range

func _on_reload_started() -> void:
	# Deliberately kept for hostiles and filtered out for friendlies in the
	# BarkSet: an ally announcing a reload is noise, an ENEMY announcing one
	# tells the player to push. Same clip, opposite value.
	if bark != null:
		bark.bark(BarkSet.Line.RELOAD)
	# Break contact while vulnerable rather than standing in the open.
	weapon_state = WeaponState.RELOAD
	_burst_left = 0
	_aim_tracking = 0.0
	if MovementOptions.FALLBACK in AllowedMovementOptions:
		move_to(find_fallback_target())
	elif MovementOptions.REPOSITION in AllowedMovementOptions:
		move_to(find_reposition_target())

func _on_reload_finished() -> void:
	if ai_state == AIState.COMBAT:
		weapon_state = WeaponState.AIM


# ─────────────────────────────────────────────
# RECONSIDER — weighted, context-driven
# ─────────────────────────────────────────────
func roll_combat_action():
	if AllowedCombatOptions.is_empty():
		return

	var weights: Dictionary = {}
	var total: float = 0.0
	for opt in AllowedCombatOptions:
		var w: float = maxf(_score_combat_option(opt), 0.0)
		if opt == previous_combat_option:
			w *= repeat_penalty
		weights[opt] = w
		total += w

	var chosen = AllowedCombatOptions[randi() % AllowedCombatOptions.size()]
	if total > 0.0:
		var roll = randf() * total
		for opt in AllowedCombatOptions:
			roll -= weights[opt]
			if roll <= 0.0:
				chosen = opt
				break

	perform_action(chosen)
	previous_combat_option = chosen

## Score, don't shuffle. The old version erased the previous option, which
## structurally forced move/stand/move/stand on a fixed timer.
func _score_combat_option(option: int) -> float:
	var max_range = _max_range()
	var dist = max_range
	if combat_target != null:
		dist = global_position.distance_to(combat_target.global_position)
	var range_ratio = clampf(dist / maxf(max_range, 0.01), 0.0, 2.0)
	var health_ratio = float(health) / maxf(float(max_health), 1.0)
	var pinned = signal_integrity < SIGNAL_FUZZED
	var low_ammo = false
	if weapon != null and not weapon.infinite_ammo:
		low_ammo = float(weapon.magazine_current) / maxf(float(weapon.magazine_size), 1.0) < 0.25

	var w: float = 1.0
	match option:
		CombatOptions.MOVE:
			w += range_ratio * 2.5             # far → close the distance
			if not _has_los:
				w += 3.0                       # blocked → moving is the only fix
			if range_ratio < 0.25:
				w += 1.0                       # crowding → open the range
			if health_ratio < 0.4:
				w += 0.8                       # hurt → don't stand still
			if pinned:
				w *= 0.5                       # under fire → less willing to move
		CombatOptions.AIM:
			if not _has_los:
				return 0.15                    # nothing to aim at
			w += 1.5
			w += range_ratio * 2.5             # long shots want a settled stance
			if low_ammo:
				w += 0.6                       # make the remaining rounds count
			if pinned:
				w *= 0.6
		CombatOptions.FIRE:
			# A MELEE weapon out of reach has nothing to swing at.
			#
			# Both melee chassis allow only MOVE and FIRE, and at 30m the
			# scoring gave MOVE ~6 against FIRE ~3.5 — so better than a third of
			# every action roll was "attack" from far outside a 1.5m reach, and
			# the robot simply stopped and swiped at nothing. That is the
			# standing-around; it was never a movement problem.
			if weapon != null and weapon.weapon_type == Enums.AIWeaponTypes.MELEE:
				if dist > weapon.melee_range * 1.25:
					return 0.0
			if not _has_los and not _can_fire_without_los():
				return 0.1
			w += 2.5
			w += (1.0 - minf(range_ratio, 1.0)) * 2.0   # close range → just shoot
			if low_ammo:
				w *= 0.4
			if pinned:
				w += 0.8                       # return fire even while suppressed
	return w

func _pick_movement_option() -> int:
	if AllowedMovementOptions.is_empty():
		return -1
	var weights: Dictionary = {}
	var total: float = 0.0
	for m in AllowedMovementOptions:
		var w: float = maxf(_score_movement_option(m), 0.0)
		if m == previous_movement_option:
			w *= repeat_penalty
		weights[m] = w
		total += w
	if total <= 0.0:
		return AllowedMovementOptions[randi() % AllowedMovementOptions.size()]
	var roll = randf() * total
	for m in AllowedMovementOptions:
		roll -= weights[m]
		if roll <= 0.0:
			return m
	return AllowedMovementOptions[0]

func _score_movement_option(option: int) -> float:
	var max_range = _max_range()
	var dist = max_range
	if combat_target != null:
		dist = global_position.distance_to(combat_target.global_position)
	var range_ratio = clampf(dist / maxf(max_range, 0.01), 0.0, 2.0)
	var health_ratio = float(health) / maxf(float(max_health), 1.0)

	var w: float = 1.0
	match option:
		MovementOptions.ADVANCE:
			w = 0.4 + range_ratio * 3.0
			if range_ratio < 0.35:
				w *= 0.2
		MovementOptions.REPOSITION:
			w = 1.2
			if _has_los:
				w += 1.0                       # shuffle to break the firing solution
			else:
				w += 1.8                       # small step to try to open a lane
			if range_ratio > 1.0:
				w *= 0.5                       # too far for a 2m sidestep to matter
		MovementOptions.FALLBACK:
			w = 0.2
			if range_ratio < 0.3:
				w += 2.0                       # too close
			if health_ratio < 0.4:
				w += 1.5
			if weapon != null and weapon.is_reloading:
				w += 2.0
		MovementOptions.LEAP:
			if combat_target == null or not _has_los:
				return 0.0
			# Recovering from the last one. Zero rather than merely low: a
			# small weight still wins a roll sometimes, and one extra leap
			# straight off a landing is exactly the chain being prevented.
			if _leap_cooldown_t > 0.0:
				return 0.0
			# Gated on ABSOLUTE distance, not range_ratio. Everything else here
			# reasons in fractions of weapon range, which is meaningless for a
			# leaper: its weapon reaches 1.5m, so range_ratio is above 0.6 at
			# any distance worth leaping from and LEAP could never be chosen.
			# A leap is a mid-range closer — too near and it overshoots, too far
			# and it lands short in the open.
			if dist < leap_min_distance or dist > leap_max_distance:
				return 0.1
			# Was a flat 1.5, competing against ADVANCE at 0.4 + range_ratio*3.0
			# — which for a melee unit pins range_ratio at its 2.0 ceiling, so
			# ADVANCE scored 6.4 and the leaper walked instead of leaping. In
			# band, the leap IS the attack, so it should win clearly.
			w = 7.0
		MovementOptions.CHASE:
			w = 0.3 + range_ratio * 2.0
			if not _has_los:
				w += 1.5
			if range_ratio < 0.5:
				w *= 0.3
	return w

func _handle_path_blocked() -> void:
	_stuck_retry_count += 1

	var nav_map = nav_agent.get_navigation_map()

	if _stuck_retry_count == 1:
		# First block — try a lateral step to get around whatever is blocking
		var to_target = (movement_target - global_position).normalized()
		var right = to_target.cross(Vector3.UP).normalized()
		var lateral_dir = right if randf() > 0.5 else -right
		var step = global_position + lateral_dir * 3.0 + to_target * 1.5
		var nav_point = NavigationServer3D.map_get_closest_point(nav_map, step)
		nav_agent.set_target_position(nav_point)
		_nav_think_timer = 0.0  # new destination: refresh the cached direction now
		return

	if _stuck_retry_count == 2:
		# Second block — try the opposite lateral direction
		var to_target = (movement_target - global_position).normalized()
		var right = to_target.cross(Vector3.UP).normalized()
		var lateral_dir = -right if randf() > 0.5 else right
		var step = global_position + lateral_dir * 4.0
		var nav_point = NavigationServer3D.map_get_closest_point(nav_map, step)
		nav_agent.set_target_position(nav_point)
		_nav_think_timer = 0.0  # new destination: refresh the cached direction now
		return

	# Third block — path is genuinely impassable from here
	_stuck_retry_count = 0
	movement_state = MovementState.NONE
	if ai_state == AIState.COMBAT:
		# Stand and fight — roll a non-move combat action
		var options = AllowedCombatOptions.duplicate()
		options.erase(CombatOptions.MOVE)
		if not options.is_empty():
			perform_action(options[randi_range(0, options.size() - 1)])
	else:
		var random_offset = Vector3(randf_range(-5.0, 5.0), 0, randf_range(-5.0, 5.0))
		var fallback = NavigationServer3D.map_get_closest_point(nav_map, global_position + random_offset)
		move_to(fallback)

## One ring of 8 samples per call instead of 32 samples in a single frame.
## Successive calls widen the search; the angle offset is randomised so
## squadmates don't all test identical points.
func _seek_los_position() -> void:
	if combat_target == null:
		return
	var nav_map = nav_agent.get_navigation_map()
	var target_pos = combat_target.global_position
	var check_from_height = Vector3.UP * 0.8

	var radius = advance_distance * SEEK_RING_RADII[_seek_ring_index]
	_seek_ring_index = (_seek_ring_index + 1) % SEEK_RING_RADII.size()

	var best_pos: Vector3 = Vector3.ZERO
	var best_dist: float = INF
	var angle_offset = randf() * TAU

	for i in 8:
		var angle = angle_offset + (TAU / 8.0) * i
		var dir = Vector3(cos(angle), 0.0, sin(angle))
		var test = target_pos + dir * radius
		var nav_point = NavigationServer3D.map_get_closest_point(nav_map, test)
		if nav_point.distance_to(global_position) < 1.5:
			continue
		if is_path_clear(nav_point + check_from_height, target_pos, combat_target):
			var dist = global_position.distance_to(nav_point)
			if dist < best_dist:
				best_dist = dist
				best_pos = nav_point

	if best_pos != Vector3.ZERO:
		_seek_ring_index = 0
		move_to(best_pos)

func reconsider_movement():
	movement_time = 0
	match ai_state:
		AIState.COMBAT:
			roll_combat_action()
		AIState.PATROL:
			reconsider_patrol()
		_:
			movement_state = MovementState.NONE

func reconsider_weapon():
	weapon_time = 0
	if weapon == null:
		return
	# Top up out of contact rather than starting a fight on a half magazine.
	if not weapon.infinite_ammo and not weapon.is_reloading:
		var frac = float(weapon.magazine_current) / maxf(float(weapon.magazine_size), 1.0)
		if frac < 0.35 and (not _has_los or ai_state != AIState.COMBAT):
			weapon.start_reload()
			_on_reload_started()

func reconsider_combat():
	combat_time = 0
	roll_combat_action()

func reconsider_target() -> void:
	targeting_time = 0
	# Set when the target is dropped because it went DOWN, not because it was
	# lost. Decides whether "lost contact, searching" is the right thing to say.
	var target_down := false

	# Checked BEFORE the keep-current-target early return below. That return is
	# exactly what made a point-blank contact invisible — it fired whenever the
	# existing target was alive, without ever comparing distances.
	if _check_close_threat():
		return

	if combat_target != null and combat_target.alive:
		if _is_hostile(combat_target):
			weapon_target = combat_target.global_position
			look_target = combat_target.global_position
			return
	if combat_target != null and not combat_target.alive:
		# Deliberately NOT remembered as a last-known-position. You can see it's
		# down — filing the corpse as a lead is what sent them walking over to
		# stare at it instead of looking for whoever is still shooting.
		combat_target = null
		weapon_target = Vector3.ZERO
		_has_los = false
		if movement_target != Vector3.ZERO:
			look_target = movement_target

		# Close threat is down — go back to whatever we were on rather than
		# re-picking nearest, which would lose a player-designated target.
		var resumed := _take_preempted_target()
		if resumed != null:
			change_combat_target(resumed)
			return
		target_down = true

	var new_target: CharacterBody3D = _nearest_hostile()
	# AND NOT FROM ACROSS THE VALLEY.
	#
	# _nearest_hostile() asks the AI manager, which searches the whole level —
	# it answers "nearest", never "near". Handed straight to a robot in COMBAT,
	# one trigger anywhere ended with robots holding a target 150m away through
	# a hill, and a squad with a target is ENGAGED, and an ENGAGED squad does
	# not patrol. A whole valley's worth of hostiles stood locked onto one of
	# the player's robots from the first frame of the mission, picket included.
	#
	# Out of reach is the same as no target: fall through to the branch below,
	# which is the one that goes and looks. Return fire is unaffected —
	# apply_damage assigns the shooter directly, at any range.
	if new_target != null and global_position.distance_to(new_target.global_position) > reacquire_range():
		new_target = null

	if new_target != null:
		if ai_state == AIState.COMBAT:
			change_combat_target(new_target)
		elif ai_state == AIState.SEARCH:
			# Searching means we already know there's a fight on. Detection only
			# fires on body_entered, so a hostile that was already inside the
			# radius never re-triggers it — without this they search past someone
			# standing in plain sight.
			if is_path_clear(global_position + Vector3.UP * 0.8, new_target.global_position, new_target):
				trigger_combat(new_target)
		# Don't auto-trigger from IDLE/PATROL — let detection handle that
	else:
		combat_target = null
		weapon_target = Vector3.ZERO
		_has_los = false
		if movement_target != Vector3.ZERO:
			look_target = movement_target
		if ai_state == AIState.COMBAT:
			# Lost them — go look, rather than instantly forgetting. Unless the
			# target went DOWN: then nobody lost anything, and a squadmate has
			# usually just confirmed the kill.
			_enter_search(target_down)

# Extracted from reconsider_target so the close-threat check shares one source
# of truth for "who is hostile and nearby".
#
# MEMOISED FOR THE FRAME. reconsider_target() asks twice in a single call: once
# through _check_close_threat(), and again at the bottom when that returns
# false. Nothing between them moves a robot or changes a faction, so the second
# scan re-derived an answer it already had — and the scan is O(every registered
# AI). The memo cannot go stale within a frame, which is the only window it
# covers. Computing eagerly at the top of reconsider_target() instead would be
# worse: the common "keep current target" path returns before ever needing it.
var _nearest_cache: CharacterBody3D = null
var _nearest_cache_frame: int = -1

func _nearest_hostile() -> CharacterBody3D:
	var frame := Engine.get_physics_frames()
	if _nearest_cache_frame == frame:
		if _nearest_cache == null or is_instance_valid(_nearest_cache):
			return _nearest_cache
	_nearest_cache_frame = frame
	_nearest_cache = _compute_nearest_hostile()
	return _nearest_cache


func _compute_nearest_hostile() -> CharacterBody3D:
	if ai_manager != null:
		return ai_manager.get_nearest_hostile(self)
	if player != null and _is_hostile(player) and player.is_targetable():
		return player
	return null


func _take_preempted_target() -> CharacterBody3D:
	var t := _preempted_target
	_preempted_target = null
	if t == null or not is_instance_valid(t) or not t.alive:
		return null
	if not _is_hostile(t):
		return null
	return t


# Returns true if it took over targeting this tick.
# True when this robot is genuinely fighting something. COMBAT with a null or
# downed target is a leftover state, not a fight — and it's what kept squads
# pinned in CONTACT after the last enemy fell.
func has_live_target() -> bool:
	if combat_target == null or not is_instance_valid(combat_target):
		return false
	return combat_target.alive


func _check_close_threat() -> bool:
	if close_threat_range <= 0.0 or ai_state == AIState.DEAD:
		return false
	# Same sensor rule the detection area uses — a robot with a wrecked sensor
	# package doesn't get a free point-blank sense.
	var sig := get_signal_state()
	if sig == SignalState.EKILL or sig == SignalState.CRITICAL:
		return false

	var candidate := _nearest_hostile()
	if candidate == null or candidate == combat_target:
		return false

	var dist := global_position.distance_to(candidate.global_position)
	if dist > close_threat_range:
		return false

	var current_valid: bool = combat_target != null \
		and is_instance_valid(combat_target) \
		and combat_target.alive

	# Already fighting something at least as close? Leave it alone.
	if current_valid:
		var current_dist := global_position.distance_to(combat_target.global_position)
		if current_dist - dist < close_threat_advantage:
			return false

	if close_threat_requires_los:
		if not is_path_clear(global_position + Vector3.UP * 0.8, candidate.global_position, candidate):
			return false

	if current_valid:
		_preempted_target = combat_target

	if ai_state == AIState.COMBAT:
		change_combat_target(candidate)
	else:
		# Not fighting yet. This is the case the Area3D misses when the hostile
		# was already inside the radius before this robot became relevant —
		# body_entered never fires for an overlap that already existed.
		trigger_combat(candidate)

	close_threat_engaged.emit(candidate)
	return true


func reconsider_patrol():
	patrol_time = 0
	# A squad on SquadObjective.PATROL walks its route as a unit; an individual
	# re-picking its own patrol point underneath that fights the squad.
	if squad_directed:
		return
	if patrol_path == null or patrol_path.points.is_empty():
		return
	_tick_nav(get_physics_process_delta_time())
	if _nav_finished:
		var next_point = patrol_path.get_next_point(self)
		if next_point:
			move_to(next_point.global_position)
			look_target = next_point.global_position


# ─────────────────────────────────────────────
# SEARCH
# Previously a declared-but-unreachable state.
# ─────────────────────────────────────────────
# "LOST CONTACT, SEARCHING" is only said when it is true: the target slipped out
# of sight AND there is somewhere to look. It used to be barked first, always —
# so a squad whose target a squadmate had just killed announced they had lost
# it, and a robot with no lead at all said "searching" and then stood down.
func _enter_search(target_down: bool = false) -> void:
	if last_seen_point.is_empty():
		# Nothing to search. A squad member drops to IDLE and lets the squad
		# decide; PATROL here was putting follow squadmates into a state whose
		# tick restarts movement.
		change_ai_state(AIState.IDLE if squad_directed else AIState.PATROL)
		return
	# Older leads can still be worth checking after a kill — quietly.
	if bark != null and not target_down:
		bark.bark(BarkSet.Line.SEARCH)
	change_ai_state(AIState.SEARCH)
	search_time = 0.0
	_search_look_timer = 0.0
	move_to(last_seen_point.back())
	look_target = last_seen_point.back()

func _tick_search(delta: float) -> void:
	if movement_state != MovementState.NONE:
		return
	_search_look_timer -= delta
	if _search_look_timer > 0.0:
		return
	_search_look_timer = search_look_interval * randf_range(0.7, 1.4)

	# Sweep a random heading, and sometimes push to a new vantage point.
	var a = randf() * TAU
	look_target = global_position + Vector3(cos(a), 0.0, sin(a)) * 6.0
	# A squad member searching is still the squad's to move. Without this they
	# roam ±7m on their own while the squad is trying to hold formation, which
	# looks identical to the idle-wander problem.
	if squad_directed:
		return
	if randf() < 0.45:
		var nav_map = nav_agent.get_navigation_map()
		var offset = Vector3(randf_range(-7.0, 7.0), 0.0, randf_range(-7.0, 7.0))
		move_to(NavigationServer3D.map_get_closest_point(nav_map, global_position + offset))

func _end_search() -> void:
	search_time = 0.0
	last_seen_point.clear()
	if squad_directed:
		# The squad decides what happens next, not an individual patrol route.
		change_ai_state(AIState.IDLE)
		halt()
		return
	if patrol_path != null and not patrol_path.points.is_empty():
		change_ai_state(AIState.PATROL)
	else:
		change_ai_state(AIState.IDLE)


# ─────────────────────────────────────────────
# IDLE WANDER
# Previously four declared variables and no implementation.
# ─────────────────────────────────────────────
# Look-only. Picks a heading within idle_scan_arc_degrees of the direction this
# robot was facing when it settled, so a guard watches roughly one way rather
# than spinning on the spot.
func _tick_idle_scan(delta: float) -> void:
	if movement_state != MovementState.NONE:
		return
	if _idle_scan_base.length_squared() < 0.01:
		var facing := _sight_forward()
		facing.y = 0.0
		_idle_scan_base = facing.normalized() if facing.length_squared() > 0.01 else Vector3.FORWARD

	_idle_scan_t -= delta
	if _idle_scan_t > 0.0:
		return
	_idle_scan_t = idle_scan_interval * randf_range(0.7, 1.4)

	var swing := deg_to_rad(randf_range(-idle_scan_arc_degrees, idle_scan_arc_degrees))
	var dir := _idle_scan_base.rotated(Vector3.UP, swing)
	look_target = global_position + dir * idle_scan_distance


# Call when a robot takes up a new post, so its scan arc re-centres on whatever
# it should now be watching.
func set_scan_facing(towards: Vector3) -> void:
	var dir := towards - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		_idle_scan_base = dir.normalized()
		_idle_scan_t = 0.0


# Idle wander is OFF by default now. It gave every stationary robot a random
# stroll on a timer, which for a squad on FOLLOW meant arriving at a formation
# slot, wandering away, being dragged back, and repeating forever. Nothing in
# the game needed it, and a robot standing still reads as deliberate rather than
# broken. Flip enable_idle_wander per-scene if you want it back somewhere.
func _wander() -> void:
	if not enable_idle_wander:
		return
	if squad_directed:
		return
	if movement_state != MovementState.NONE:
		return
	var nav_map = nav_agent.get_navigation_map()
	var a = randf() * TAU
	var r = randf_range(wander_radius * 0.4, wander_radius)
	var pt = NavigationServer3D.map_get_closest_point(
		nav_map, global_position + Vector3(cos(a), 0.0, sin(a)) * r)
	move_to(pt)
	look_target = pt


# ─────────────────────────────────────────────
# EQUIPMENT
# ─────────────────────────────────────────────
func _tick_equipment(delta: float) -> void:
	for i in _equipment_cooldowns.keys():
		_equipment_cooldowns[i] = maxf(0.0, _equipment_cooldowns[i] - delta)
	if combat_target != null and combat_target.alive:
		var target_pos = combat_target.global_position
		if target_pos.distance_to(_target_last_position) < 0.5:
			_target_stationary_time += delta
		else:
			_target_stationary_time = 0.0
			_target_last_position = target_pos
	_equipment_recon_timer += delta
	if _equipment_recon_timer < EQUIPMENT_RECON_TIME:
		return
	_equipment_recon_timer = 0.0
	_evaluate_equipment_use()

func _evaluate_equipment_use() -> void:
	if combat_target == null:
		return
	var context = AIEquipment.EquipmentContext.new()
	context.owner_ai = self
	context.combat_target = combat_target
	context.target_position = combat_target.global_position
	context.time_since_target_moved = _target_stationary_time
	context.owner_is_reloading = weapon != null and weapon.is_reloading
	context.nearby_hostiles = []
	if ai_manager != null:
		context.nearby_hostiles = ai_manager.get_hostiles_in_radius(self, 5.0)
	for i in equipment_slots.size():
		var slot: AIEquipmentSlot = equipment_slots[i]
		if not slot.has_uses():
			continue
		if _equipment_cooldowns.get(i, 0.0) > 0.0:
			continue
		if slot.equipment_scene == null:
			continue
		var equipment = slot.equipment_scene.instantiate() as AIEquipment
		if equipment == null:
			continue
		if equipment.can_use(context):
			# The running scene when there is one; the level this robot is in
			# when the tree was started by a script (the tests, a lab run from
			# the command line), which has none — the grenade was never thrown.
			var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
			host.add_child(equipment)
			equipment.execute(context)
			slot.consume()
			# Recorded for the squad HUD. Equipment use is instantaneous —
			# instantiate, execute, free — so there is no "currently using" state
			# to read anywhere; a timestamp is the only way the readout can say
			# what a squadmate just did.
			_last_equipment_ms = Time.get_ticks_msec()
			_last_equipment_label = slot.label if slot.label != "" else "EQUIPMENT"
			_equipment_cooldowns[i] = equipment.cooldown
			if equipment.is_inside_tree():
				equipment.queue_free()
			return
		else:
			equipment.free()

func change_ai_state(new_state: AIState):
	if ai_state != new_state:
		ai_state = new_state
		movement_time = 0
		idle_time = 0
		wander_time = 0
		combat_time = 0
		search_time = 0
		patrol_time = 0
		chasing_time = 0
		targeting_time = 0
		_no_los_timer = 0.0

func change_combat_target(body):
	if body != combat_target:
		_aim_tracking = 0.0
		_burst_left = 0
		_has_los = false
		_los_check_timer = 0.0
	combat_target = body
	weapon_target = body.global_position
	look_target = body.global_position


# ─────────────────────────────────────────────
# ACTIONS / MOVEMENT FINDERS
# ─────────────────────────────────────────────
func perform_action(action: CombatOptions):
	match action:
		CombatOptions.MOVE:
			var movement = _pick_movement_option()
			if movement < 0:
				return
			previous_movement_option = movement as MovementOptions
			match movement:
				MovementOptions.LEAP:
					if combat_target != null:
						leap_towards(combat_target.global_position)
				MovementOptions.REPOSITION:
					move_to(find_reposition_target())
				MovementOptions.ADVANCE:
					move_to(find_advance_target())
				MovementOptions.CHASE:
					if combat_target != null:
						movement_state = MovementState.CHASING
				MovementOptions.FALLBACK:
					move_to(find_fallback_target())
		CombatOptions.FIRE:
			_commit_burst()
		CombatOptions.AIM:
			_enter_aim_stance()

## AIM used to be `pass`. It now means: stop, settle, let accuracy build.
func _enter_aim_stance() -> void:
	if movement_state == MovementState.MOVING or movement_state == MovementState.CHASING:
		movement_state = MovementState.NONE
	_burst_left = 0

## FIRE used to be `pass`. It now means: commit to a burst from wherever
## you are — if you were moving, keep moving and eat the accuracy penalty.
func _commit_burst() -> void:
	var lo := burst_min
	var hi := burst_max
	# A weapon with a rhythm of its own keeps it whatever it is bolted to: a
	# machine gun talks in long bursts, a grenade launcher in twos and threes.
	if weapon != null and weapon.burst_min > 0:
		lo = weapon.burst_min
		hi = weapon.burst_max
	if suppressive_fire:
		lo *= SUPPRESSIVE_BURST_SCALE
		hi *= SUPPRESSIVE_BURST_SCALE
	_burst_left = randi_range(lo, maxi(lo, hi))

func find_reposition_target():
	if combat_target == null:
		return global_position
	var nav_map = nav_agent.get_navigation_map()
	var to_target = (combat_target.global_position - global_position).normalized()
	var right = to_target.cross(Vector3.UP).normalized()
	var lateral_dir = right if randf() > 0.5 else -right
	for mult in [1.0, 0.5]:
		var test_pos = global_position + lateral_dir * reposition_distance * mult
		var closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
		if is_path_clear(closest_point + Vector3.UP * 0.8, combat_target.global_position, combat_target):
			return closest_point
	return global_position

## Step length now scales with range: long bounds when far, short careful
## steps when close, and it won't step inside a crowding distance.
func find_advance_target():
	if combat_target == null:
		return global_position
	var nav_map = nav_agent.get_navigation_map()
	var to_target = combat_target.global_position - global_position
	to_target.y = 0.0
	var dist = to_target.length()
	if dist < 0.01:
		return global_position
	var direction = to_target / dist
	var max_range = _max_range()

	# Outranged? Take the covered route in.
	if bound_when_outranged and _is_outranged() and has_method("find_best_cover_point"):
		var bound := _find_bound_cover(dist)
		if bound != Vector3.INF:
			return bound

	# Stop closing once we can reliably hit them. The old floor was
	# max_range * 0.35 — for an 80m rifle that walked them to 28m, deep inside a
	# 45m shotgun's envelope, and handed the fight to the shorter weapon. Hold
	# at most of your own reach instead; that IS the advantage of a long gun.
	var standoff: float = max_range * engage_standoff
	if dist <= standoff:
		return global_position

	var step = advance_distance * clampf(dist / maxf(max_range, 0.01), 0.4, 3.0)
	step = minf(step, dist - standoff)
	if step <= 0.2:
		return global_position

	for mult in [1.0, 0.6, 0.3]:
		var test_pos = global_position + direction * step * mult
		var closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
		# Previously this checked test_pos but returned closest_point.
		if is_path_clear(closest_point + Vector3.UP * 0.8, combat_target.global_position, combat_target):
			return closest_point
	return global_position

# True when whatever we're fighting can hit us from further away than we can hit
# them. That asymmetry, not the raw numbers, is what should change how we move.
func _is_outranged() -> bool:
	if combat_target == null or not is_instance_valid(combat_target):
		return false
	var theirs: float = 0.0
	if "weapon" in combat_target and combat_target.weapon != null \
			and "max_effective_range" in combat_target.weapon:
		theirs = combat_target.weapon.max_effective_range
	elif combat_target is Player:
		# The player's HUDWeapon uses hitscan_range rather than an AI falloff
		# curve, so assume they outrange us unless we're already long-ranged.
		theirs = 60.0
	return theirs > _max_range() * 1.15


# A cover point that actually gets us closer, without walking miles for it.
func _find_bound_cover(current_dist: float) -> Vector3:
	var cover = call("find_best_cover_point")
	if cover == null:
		return Vector3.INF
	var cover_pos: Vector3 = cover.global_position
	var new_dist: float = cover_pos.distance_to(combat_target.global_position)
	# Must make progress. A cover point that leaves us no closer is a retreat
	# dressed up as an advance.
	if new_dist >= current_dist - 1.0:
		return Vector3.INF
	# And must not be a ludicrous detour.
	var travel: float = global_position.distance_to(cover_pos)
	if travel > (current_dist - new_dist) * bound_detour_limit + advance_distance:
		return Vector3.INF
	return cover_pos


func find_fallback_target():
	if combat_target == null:
		return global_position
	var nav_map = nav_agent.get_navigation_map()
	var away_dir = (global_position - combat_target.global_position).normalized()
	for mult in [1.0, 0.5]:
		var test_pos = global_position + away_dir * fallback_distance * mult
		var closest_point = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
		# Same copy-paste bug as find_advance_target had.
		if is_path_clear(closest_point + Vector3.UP * 0.8, combat_target.global_position, combat_target):
			return closest_point
	return global_position


# ─────────────────────────────────────────────
# LEAP
# ─────────────────────────────────────────────
func leap_towards(target_pos: Vector3, leap_vel: float = 16.5):
	movement_state = MovementState.LEAPING
	velocity = compute_leap_velocity_fixed_speed(target_pos, leap_vel)
	look_target = target_pos

func compute_leap_velocity(target: Vector3, time: float) -> Vector3:
	if time <= 0.0:
		return Vector3.ZERO
	var displacement := target - global_position
	var vy = (displacement.y / time) + (0.5 * gravity * time)
	return Vector3(displacement.x / time, vy, displacement.z / time)

func compute_leap_velocity_fixed_speed(target: Vector3, speed: float) -> Vector3:
	if speed <= 0.0:
		return Vector3.ZERO
	var displacement := target - global_position
	var horiz = displacement
	horiz.y = 0.0
	var distance = horiz.length()
	if distance < 0.01:
		return Vector3.ZERO
	var time = distance / speed

	# CAP THE ARC. With horizontal speed fixed, a longer leap means more time in
	# the air, and time in the air is what makes the arc tall: on flat ground
	# the apex is g*t^2/8. A 24m leap at 16.5 m/s hung for 1.45s and peaked
	# around 2.6m — a lob, not a pounce, and it read as the robot bouncing
	# around the sky. Shortening the flight time to fit under leap_max_apex
	# makes long leaps FASTER and flatter instead of higher, which is what a
	# lunge at someone actually looks like.
	if leap_max_apex > 0.0 and gravity > 0.0:
		var max_time: float = sqrt(8.0 * leap_max_apex / gravity)
		time = minf(time, max_time)

	var direction = horiz.normalized()
	var vy = (displacement.y / time) + (0.5 * gravity * time)
	return Vector3(direction.x * distance / time, vy, direction.z * distance / time)


# ─────────────────────────────────────────────
# FIRE / DAMAGE / DEATH
# ─────────────────────────────────────────────
func fire():
	# Check before the trigger, not after. A round that has already left can't
	# be un-fired, and holding for a frame while stepping clear is invisible to
	# the player except as a robot that doesn't shoot its own squad in the back.
	if _clear_line_of_fire():
		return
	var final_target = get_inaccurate_target(weapon_target)
	weapon.fire(final_target)
	if stimulus_manager != null:
		stimulus_manager.emit_stimulus(
			StimulusManager.StimulusType.GUNSHOT_HEARD,
			global_position, faction, self)

func apply_damage(damage, source) -> void:
	if ai_state == AIState.DEAD:
		return
	if downed:
		# Already on the floor. Shooting a wreck does nothing — if you want a
		# finishing blow, call destroy() from here instead.
		return
	# Whatever else happens, a robot being shot is not asleep. See the passive
	# gate in _physics_process for the bug this closes.
	wake(wake_on_damage_seconds)
	if source is Player:
		player = source
		damaged_by_player = true
	if source is CharacterBody3D and _is_hostile(source):
		# Being shot must never be ignorable. The old test was
		# `elif combat_target == null`, which misses the case that actually
		# happens: still in COMBAT, holding a target that is non-null but DOWNED.
		# Neither branch fired, so a robot would keep "fighting" a corpse while
		# something live shot it in the back until the 0.33s targeting tick
		# happened to notice.
		if ai_state != AIState.COMBAT:
			trigger_combat(source)
			combat_triggered.emit(self)
		elif not has_live_target():
			change_combat_target(source)
		if stimulus_manager != null:
			stimulus_manager.emit_stimulus(
				StimulusManager.StimulusType.ALLY_SHOT,
				global_position, faction, source)
	if bark != null:
		bark.bark(BarkSet.Line.HURT)
	health -= damage
	_Analytics.damage(self, damage, damage, source, health <= 0)
	if health <= 0:
		# Kill credit. apply_damage has always carried the attributor; die()
		# discarded it, which is why nothing could report a kill — and why XP
		# has nowhere to come from. The killer speaks, not the victim.
		var killer = source
		# Kills made on someone's behalf (a hatchling's) go to that someone.
		if killer != null and is_instance_valid(killer) and "credit_kills_to" in killer \
				and killer.credit_kills_to != null and is_instance_valid(killer.credit_kills_to):
			killer = killer.credit_kills_to
		# Only kills of the OTHER side count. Bravo-2 put a burst through a
		# rover in the valley and came home with it on their tally, with the
		# rover's silhouette in the debrief beside their real kills — a record
		# of a mistake, scored as an achievement.
		if killer != null and is_instance_valid(killer) and killer != self and _is_hostile(killer):
			# Guarded with `in` rather than a type check: the killer may be a
			# Soldier, the Player, or anything else that deals damage, and only
			# some of those carry a counter.
			if "confirmed_kills" in killer:
				killer.confirmed_kills += 1
			# And WHAT it was, for the debrief: "2 CHASERS, 1 RIFLE TROOPER".
			if "kills_by_kind" in killer:
				var kind := _KillKinds.kind_of(self)
				killer.kills_by_kind[kind] = int(killer.kills_by_kind.get(kind, 0)) + 1
			if "bark" in killer and killer.bark != null:
				killer.bark.bark(BarkSet.Line.KILL, soldier_name)
		die()
		return
	for i in particle_effects_hit:
		i.activate()

# Entry point for lethal damage. Sends them to the floor rather than deleting
# them, unless downing is switched off for this robot.
func die():
	force_release_hold()
	if not alive:
		return
	if can_be_downed and not downed:
		enter_downed()
		return
	destroy()


# The wreck stays in the world, visible and repairable.
# ─────────────────────────────────────────────
# SELF-REVIVE (the Nanite Reboot module)
#
# A real timer, not a countdown in _physics_process: the downed branch switches
# physics OFF once the wreck has settled, so anything ticked there would simply
# stop and the robot would never get up.
#
# Guarded by a generation counter. Without it a timer armed by an EARLIER
# downing — one the player revived by hand — would still fire later and pull
# the robot up in the middle of its second downing, long before its own timer.
# ─────────────────────────────────────────────
func _arm_self_revive() -> void:
	if self_revive_seconds <= 0.0 or _self_revive_used:
		return
	_self_revive_gen += 1
	var gen := _self_revive_gen
	# process_always = false: a squad manager opened mid-fight pauses the game,
	# and the countdown should pause with it.
	var timer := get_tree().create_timer(self_revive_seconds, false)
	timer.timeout.connect(func():
		if not is_instance_valid(self) or gen != _self_revive_gen or not downed:
			return
		_self_revive_used = true
		_Analytics.self_revive(self)
		# No bark: BarkSet has no revive line, and borrowing KILL would
		# announce a kill that did not happen. The robot visibly standing back
		# up is the cue.
		revive())


func enter_downed() -> void:
	if downed:
		return
	_quiet_signal_arc()
	# The one line that is pure information rather than flavour — it is how the
	# player learns a squadmate is recoverable rather than gone. BarkDirector
	# lets DOWNED skip the channel budget for exactly this reason.
	if bark != null:
		bark.bark(BarkSet.Line.DOWNED)
	downed = true
	alive = false
	health = downed_health
	_arm_self_revive()
	change_ai_state(AIState.DEAD)
	# Held for the crash path at the end of this function: something killed in
	# mid-air should carry on the way it was going. Anything that died standing
	# on the ground stops where it fell, which is what zeroing is for.
	var carried := velocity
	velocity = Vector3.ZERO
	if nav_agent != null:
		nav_agent.set_target_position(global_position)
	if weapon != null:
		weapon.hide()
	# Collision stays ENABLED while downed. Disabling it (which is what a proper
	# death does) meant the repair tool's aim ray passed straight through the
	# wreck, fell back to the player, and stopped with "full" — you cannot
	# repair something you cannot hit. Damage is already ignored while downed,
	# so a live collider costs nothing.
	if _collision_shape == null:
		_collision_shape = _find_collision_shape()
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", false)
	_flatten_collider()
	if stimulus_manager != null:
		stimulus_manager.emit_stimulus(
			StimulusManager.StimulusType.ALLY_DIED,
			global_position, faction, self)
	_collapse_pieces()
	# Airborne when it died — fall before settling. The timeout is a safety net
	# so a wreck that lands somewhere is_on_floor() never reports (a slope it
	# slides along, geometry it clips into) still settles rather than falling
	# forever with its physics tick alive.
	#
	# Standing on something that can move counts as airborne. A hopper that
	# died perched on your head settled up there and hung in mid-air once you
	# walked out from under it — as did a wreck on a wreck, when the one below
	# settled and switched its collider off.
	if not is_on_floor() or _step_off_bodies():
		# A KILL DOES NOT CANCEL MOMENTUM. Zeroing velocity above turned a
		# quadcopter bomber doing 27 m/s into a brick that dropped straight
		# down the instant it died — it read as the game switching the thing
		# off rather than shooting it down. It keeps most of what it had and
		# flies its own wreck into the ground somewhere ahead of you.
		velocity = carried * CRASH_MOMENTUM
		_crashing = true
		_crash_timeout = 6.0
		_on_crash_started()
		# The downed branch of _physics_process drives the fall.
		set_physics_process(true)
	else:
		_begin_settle()
	went_down.emit()


# Subclass hooks for whatever a particular frame does on the way down. Base
# robots have nothing to add; a helicopter kills its rotor.
func _on_crash_started() -> void:
	pass


func _on_crash_landed() -> void:
	pass


# Actually gone. Kept for can_be_downed = false, and as the place a finishing
# blow or a salvage system would eventually call into.
func destroy():
	force_release_hold()
	_quiet_signal_arc()
	downed = false
	if stimulus_manager != null:
		stimulus_manager.emit_stimulus(
			StimulusManager.StimulusType.ALLY_DIED,
			global_position, faction, self)
	set_physics_process(false)
	set_process(false)
	alive = false
	change_ai_state(AIState.DEAD)
	for i in particle_effects_die:
		i.activate()
	nav_agent.set_target_position(global_position)
	# Salvage off the other side only, for the same reason the kill tally is:
	# shooting your own robot is not a payday.
	if damaged_by_player and player != null and Enums.are_hostile(faction, player.faction):
		player.add_bits(bits)
	if _collision_shape == null:
		_collision_shape = _find_collision_shape()
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", true)
	damaged_by_player = false
	hide_body()
	if weapon != null:
		weapon.hide()
	destroyed.emit()


# ─────────────────────────────────────────────
# REPAIR / REVIVE
# ─────────────────────────────────────────────
# Called by PlayerRepairTool. Works on a standing robot (topping them up) and on
# a downed one (bringing them back), so the tool needs no special case.
## `healer` is whoever did it, for the playtest log: the player's repair tool
## or a squadmate's kit. Optional — nothing else reads it.
func apply_healing(amount: int, healer: Node = null) -> void:
	if ai_state == AIState.DEAD and not downed:
		return   # properly destroyed, nothing to repair
	var before: int = health
	var was_down := downed
	health = mini(max_health, health + amount)
	if downed and health >= int(ceil(max_health * revive_at_fraction)):
		revive()
	# WHO GOT THEM BACK UP. Every revive in the game comes through here — the
	# player's repair tool, a mechanic's kit, a reclaimer's welder — so this is
	# the one place that has to count it. Guarded with `in` for the same reason
	# kill credit is: a healer may be the Player, a Soldier or a pickup, and
	# only some of those carry a tally. A robot standing itself back up on a
	# nanite charge never reaches this, which is right: nobody did it for them.
	if was_down and not downed and healer != null and is_instance_valid(healer) \
			and healer != self and "revives" in healer:
		healer.revives += 1
	_Analytics.heal(self, health - before, healer, was_down and not downed)


func revive() -> void:
	if not downed:
		return
	# Cancels any nanite timer still running. If a squadmate or the player got
	# here first, the charge was not spent and stays available for next time.
	_self_revive_gen += 1
	downed = false
	alive = true
	health = maxi(health, int(ceil(max_health * revive_at_fraction)))
	_restore_pieces()
	_unsettle()
	_restore_collider()
	_stop_falling_through()
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", false)
	if weapon != null:
		weapon.show()
	set_physics_process(true)
	set_process(true)
	seen_bodies.clear()
	last_seen_point.clear()
	checking_for_target = false
	combat_target = null
	movement_state = MovementState.NONE
	change_ai_state(DefaultAIState)
	if nav_agent != null:
		nav_agent.set_target_position(global_position)
	revived.emit()


# Tip the visible pieces over. The CharacterBody3D itself stays upright —
# rotating it would take the collision capsule and the nav agent with it, and a
# revived robot would come back facing the floor.
# ─────────────────────────────────────────────
# SETTLING INTO THE GROUND
# ─────────────────────────────────────────────
func _begin_settle() -> void:
	if settle_after < 0.0:
		# Settling switched off — nothing left to tick, so stop now.
		set_physics_process(false)
		return
	_settle_rest_y = global_position.y
	_settle_timer = 0.0
	_settling = true
	_settled = false
	# The downed branch of _physics_process drives it from here.
	set_physics_process(true)


# The settle depths were tuned on the standard 2m frame. A hopper is a 1m
# capsule, and sinking it the same 0.7m put it almost entirely through the deck
# — so the sink scales with the body's own height. A 2m robot is unchanged.
const SETTLE_REFERENCE_HEIGHT := 2.0


func _settle_scale() -> float:
	var h := _body_height()
	if h <= 0.0:
		return 1.0
	return clampf(h / SETTLE_REFERENCE_HEIGHT, 0.25, 1.5)


# From the body's own collider rather than its mesh: every frame has one. Measured
# on the collider as it STANDS — its rest transform once flattening has rotated
# it — so a wreck still measures as the robot it was. The vertical extent, not
# the shape's own height: a vehicle's capsule lies along its length, and its
# "height" is how long it is.
func _body_height() -> float:
	if _collision_shape == null or _collision_shape.shape == null:
		return 0.0
	var standing := _collider_rest if _collider_flattened else _collision_shape.transform
	return (standing * _shape_box(_collision_shape.shape)).size.y * absf(global_transform.basis.get_scale().y)


func _tick_settle(delta: float) -> void:
	if not _settling:
		return
	_settle_timer += delta
	if _settle_timer < settle_after:
		return

	var depth: float = settle_depth
	if Enums.are_hostile(Enums.Factions.PLAYER, faction):
		depth = settle_depth_hostile
	depth *= _settle_scale()

	var progress: float = clampf((_settle_timer - settle_after) / maxf(settle_duration, 0.01), 0.0, 1.0)
	global_position.y = _settle_rest_y - depth * progress

	if progress < 1.0:
		return

	_settling = false
	_settled = true
	# Down and out of the way. Collision off, so nothing paths around it and
	# nothing trips over it — and the next tick turns the tick itself off.
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", true)
	set_physics_process(false)


# Undo the sink. Called on revive, so a repaired squadmate stands back up at
# ground level rather than knee-deep in it.
func _unsettle() -> void:
	if _settling or _settled:
		global_position.y = _settle_rest_y
	_settling = false
	_settled = false
	_settle_timer = 0.0


# Lays the collider on its side so a wreck is prone cover rather than a pillar.
# Still solid, still hittable by the repair tool's ray — just the right height.
func _flatten_collider() -> void:
	if not flatten_collider_when_downed or _collision_shape == null:
		return
	if _collider_flattened:
		return
	_collider_rest = _collision_shape.transform
	_collider_flattened = true

	var lying := _collider_rest.rotated_local(Vector3.RIGHT, deg_to_rad(90.0))
	# Its underside stays where the standing shape's was, on the deck. This used
	# to put the centre one radius above the body's ORIGIN, as if the origin were
	# the feet — it is the middle of the capsule. So a wreck's collider hung a
	# metre in the air, and a robot that died airborne fell until that reached
	# the deck, taking the body a metre into the floor. Hoppers die mid-leap more
	# than anything else does; they vanished into the ground.
	lying.origin.y += _feet_y() - _shape_bottom(lying)
	_collision_shape.transform = lying


func _restore_collider() -> void:
	if not _collider_flattened or _collision_shape == null:
		return
	_collision_shape.transform = _collider_rest
	_collider_flattened = false


# Lets a wreck fall through whatever it is standing on that is not the level —
# a robot, the player, another wreck — and says whether there was anything.
# None of those stays put: it walks off, or settles and turns its collider off,
# and a wreck resting on it is left hanging in the air.
func _step_off_bodies() -> bool:
	var found := false
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var body := hit.get_collider() as PhysicsBody3D
		if body == null or body is StaticBody3D or hit.get_angle(0, up_direction) > floor_max_angle + 0.01:
			continue   # the level, or a wall — not something it is standing on
		if not _fell_through.has(body):
			add_collision_exception_with(body)
			_fell_through.append(body)
		found = true
	return found


func _stop_falling_through() -> void:
	for body in _fell_through:
		if is_instance_valid(body):
			remove_collision_exception_with(body)
	_fell_through.clear()


# The underside of the STANDING collider, in the body's own space: where the
# deck is under a robot on its feet. Not zero — the origin is the middle of the
# capsule, so it is -1.0 on a 2m frame and about -0.47 on a hopper.
func _feet_y() -> float:
	if _collision_shape == null:
		push_warning("%s: no collider, so its feet are taken to be at its origin." % name)
		return 0.0
	return _shape_bottom(_collider_rest if _collider_flattened else _collision_shape.transform)


# The lowest point of the body's collision shape, were it placed at `at`.
func _shape_bottom(at: Transform3D) -> float:
	return (at * _shape_box(_collision_shape.shape)).position.y


func _shape_box(shape: Shape3D) -> AABB:
	if shape is CapsuleShape3D:
		var c := shape as CapsuleShape3D
		return AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius), Vector3(c.radius * 2.0, c.height, c.radius * 2.0))
	if shape is CylinderShape3D:
		var y := shape as CylinderShape3D
		return AABB(Vector3(-y.radius, -y.height * 0.5, -y.radius), Vector3(y.radius * 2.0, y.height, y.radius * 2.0))
	if shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		return AABB(Vector3.ONE * -r, Vector3.ONE * r * 2.0)
	if shape is BoxShape3D:
		var b := (shape as BoxShape3D).size
		return AABB(b * -0.5, b)
	# Anything else is measured off the outline the editor draws for it.
	return shape.get_debug_mesh().get_aabb() if shape != null else AABB()


func _collapse_pieces() -> void:
	for piece in visible_pieces:
		if piece == null or not is_instance_valid(piece):
			continue
		if not _piece_rest.has(piece):
			_piece_rest[piece] = piece.transform
		var t: Transform3D = _piece_rest[piece]
		t = t.rotated_local(Vector3.RIGHT, deg_to_rad(collapse_pitch_degrees))
		t.origin.y -= collapse_drop
		piece.transform = t
	_keep_pieces_above_deck()


# collapse_drop is tuned on the 2m frames: on its side a robot is thinner than
# it was tall, and it has to come down half a metre to reach the deck. A hopper
# is a puck — on its side it is TALLER — and the same half metre put it half
# through the floor before it had started to settle. So the drop stops at the
# deck, whatever the frame; settling is what takes a wreck into the ground.
func _keep_pieces_above_deck() -> void:
	var lowest := INF
	for piece in _piece_rest.keys():
		if piece != null and is_instance_valid(piece):
			lowest = minf(lowest, _lowest_drawn(piece, global_transform.affine_inverse()))
	if lowest == INF:
		push_warning("%s: nothing drawn to measure, so the collapse is not checked against the deck." % name)
		return
	var lift := maxf(0.0, _feet_y() - lowest)
	for piece in _piece_rest.keys():
		if piece != null and is_instance_valid(piece):
			piece.position.y += lift


# The lowest point of anything drawn at or under `node`, in the body's space
# (`to_body` takes world space there). Meshes and whole CSG shapes only — a
# particle emitter's bounds are where its sparks might fly, not the body.
func _lowest_drawn(node: Node, to_body: Transform3D) -> float:
	if node is Node3D and not (node as Node3D).is_visible_in_tree():
		return INF
	if node is CSGShape3D or node is MeshInstance3D:
		var box := (node as VisualInstance3D).get_aabb()
		if box.size != Vector3.ZERO:
			return (to_body * (node as Node3D).global_transform * box).position.y
	var lowest := INF
	if not node is CSGShape3D:   # a CSG shape's children are already part of it
		for child in node.get_children():
			lowest = minf(lowest, _lowest_drawn(child, to_body))
	return lowest


func _restore_pieces() -> void:
	for piece in _piece_rest.keys():
		if piece != null and is_instance_valid(piece):
			piece.transform = _piece_rest[piece]
	_piece_rest.clear()


func respawn():
	reset()

func hide_body():
	for i in visible_pieces:
		i.visible = false
func show_body():
	for i in visible_pieces:
		i.visible = true

func reset():
	ai_state = DefaultAIState
	transform = spawn_transform
	health = max_health
	alive = true
	change_ai_state(DefaultAIState)
	seen_bodies.clear()
	last_seen_point.clear()
	checking_for_target = false
	velocity = Vector3.ZERO
	weapon_target = Vector3.ZERO
	look_target = Vector3.ZERO
	combat_target = null
	show_body()
	if weapon != null:
		weapon.show()
	movement_state = MovementState.NONE
	weapon_state = WeaponState.IDLE
	movement_time = 0
	combat_time = 0
	weapon_time = 0
	targeting_time = 0
	fire_time = 0
	idle_time = 0
	search_time = 0
	wander_time = 0
	_stuck_timer = 0.0
	_stuck_last_position = Vector3.ZERO
	_stuck_retry_count = 0
	_no_los_timer = 0.0
	_has_los = false
	_los_check_timer = 0.0
	_aim_tracking = 0.0
	_burst_left = 0
	_last_move_dir = Vector3.ZERO
	_seek_ring_index = 0
	_search_look_timer = 0.0
	# Was never reset — squads set this true and nothing ever set it back,
	# so every squad member ran full physics forever.
	always_active = false
	_stop_falling_through()
	# A level reset is a fresh start, so the nanite charge comes back with it.
	_self_revive_used = false
	_self_revive_gen += 1
	signal_integrity = 1.0
	_signal_locked_t = 0.0
	_woken_t = 0.0
	_signal_stutter_timer = 0.0
	_equipment_cooldowns.clear()
	_target_stationary_time = 0.0
	_target_last_position = Vector3.ZERO
	_equipment_recon_timer = 0.0
	for slot in equipment_slots:
		slot.initialize()
	set_physics_process(true)
	set_process(true)
	if _collision_shape == null:
		_collision_shape = _find_collision_shape()
	if _collision_shape != null:
		_collision_shape.set_deferred("disabled", false)


# ─────────────────────────────────────────────
# STIMULUS
# ─────────────────────────────────────────────
func receive_stimulus(
	type: StimulusManager.StimulusType,
	source_position: Vector3,
	source_node: Node,
	distance: float
) -> void:
	if ai_state == AIState.DEAD or ai_state == AIState.PASSIVE:
		return
	match type:
		StimulusManager.StimulusType.GUNSHOT_HEARD:
			# Gunshots stopped being faction-filtered so hostiles could hear the
			# player — which also means you now hear your OWN squad. Turning to
			# face every friendly muzzle behind you is why an advancing squad
			# walked forward staring backwards. Only a hostile shot is worth
			# turning for.
			var shot_is_hostile: bool = source_node != null and _is_hostile(source_node)
			if ai_state != AIState.COMBAT and shot_is_hostile:
				look_target = source_position
				_remember_last_seen(source_position)
				# A shot from someone hostile is a contact, not ambient noise.
				# If we can see where it came from, engage; otherwise go look.
				# This is what lets a long-range weapon start a fight at all —
				# the shooter is well outside the detection Area3D.
				if source_node != null and _is_hostile(source_node):
					if is_path_clear(global_position + Vector3.UP * 0.8, source_position, source_node):
						trigger_combat(source_node)
				# Close enough to be worth walking over to. SEARCH already
				# drives the look-around-and-reposition behaviour, so this just
				# points it at the right place.
				if shot_is_hostile and distance <= investigate_gunshot_within and _investigate_timer <= 0.0:
					_investigate_timer = investigate_cooldown
					if ai_state != AIState.SEARCH:
						change_ai_state(AIState.SEARCH)
					search_time = 0.0
					move_to(source_position)
		StimulusManager.StimulusType.ALLY_SHOT:
			# The stimulus position is where the VICTIM is, not where the shot
			# came from. Filing that as a last-known-position sends people to
			# stand where their friend was hit rather than toward the shooter.
			if ai_state != AIState.COMBAT and not _moving_under_orders():
				look_target = source_position
			if source_node != null and _is_hostile(source_node):
				_remember_last_seen(source_node.global_position)
			if source_node != null and _is_hostile(source_node):
				if is_path_clear(global_position + Vector3.UP * 0.8, source_position, source_node):
					trigger_combat(source_node)
		StimulusManager.StimulusType.ALLY_DIED:
			# Same again, and this is the one that had squads advancing over
			# bodies while staring at them.
			if ai_state != AIState.COMBAT and not _moving_under_orders():
				look_target = source_position
			if distance < StimulusManager.DEFAULT_RADIUS[type] * 0.5:
				if source_node != null and _is_hostile(source_node):
					if is_path_clear(global_position + Vector3.UP * 0.8, source_node.global_position, source_node):
						trigger_combat(source_node)
		StimulusManager.StimulusType.ENEMY_SPOTTED:
			if ai_state != AIState.COMBAT and ai_state != AIState.SEARCH:
				_remember_last_seen(source_position)
				if distance < 20.0:
					move_to(source_position)
				else:
					look_target = source_position


# ─────────────────────────────────────────────
# SIGNAL INTEGRITY
# ─────────────────────────────────────────────
func get_signal_state() -> SignalState:
	# Latched OR at the floor: the second covers a frame where signal was set
	# directly and the latch has not been updated yet.
	if _ekill_latched or signal_integrity <= SIGNAL_EKILL:
		return SignalState.EKILL
	elif signal_integrity <= SIGNAL_CRITICAL:
		return SignalState.CRITICAL
	elif signal_integrity <= SIGNAL_DEGRADED:
		return SignalState.DEGRADED
	elif signal_integrity <= SIGNAL_FUZZED:
		return SignalState.FUZZED
	return SignalState.CLEAN

# Called by near-miss suppression, EMP grenades, jamming, etc.
#
# `source` is whoever did it, so an e-kill can be credited to the robot that
# suppressed them or the hand that threw the EMP. Optional, and remembered
# rather than passed on: signal damage arrives in dozens of tiny helpings and
# the one that tips a robot over is rarely the interesting one — what the
# player wants told is who had been working on them.
func receive_signal_damage(amount: float, source: Node = null) -> void:
	if source != null:
		_signal_source = source
		_signal_cause = _Analytics.cause()
	var actual = amount / maxf(signal_resistance, 0.01)
	var before = signal_integrity
	signal_integrity = maxf(0.0, signal_integrity - actual)
	# What was actually taken off, not what was thrown at it: a robot already
	# at zero loses nothing to a second EMP.
	_Analytics.signal_damage(self, before - signal_integrity, source)
	_on_signal_damaged(before, signal_integrity)
	_update_ekill_latch()
	if signal_integrity <= SIGNAL_EKILL:
		_enter_ekill()


# In at SIGNAL_EKILL, out only at SIGNAL_EKILL_RECOVER. Updated where signal
# goes down (receive_signal_damage) and where it comes back (_tick_signal),
# rather than inside get_signal_state(), which half the game calls every frame
# and which should not have side effects.
func _update_ekill_latch() -> void:
	if signal_integrity <= SIGNAL_EKILL:
		_ekill_latched = true
	elif _ekill_latched and signal_integrity >= SIGNAL_EKILL_RECOVER:
		_ekill_latched = false

## Hook for subclasses. Soldier uses this to enter SUPPRESSED.
func _on_signal_damaged(_before: float, _after: float) -> void:
	pass

func _enter_ekill() -> void:
	# Robot is electronically disabled — physically intact, non-functional.
	# Recovers automatically once signal_integrity climbs back to
	# SIGNAL_EKILL_RECOVER -- not merely back over SIGNAL_EKILL; see the latch.
	movement_state = MovementState.NONE
	velocity.x = 0
	velocity.z = 0
	weapon_state = WeaponState.IDLE
	_burst_left = 0
	_aim_tracking = 0.0

## Hold signal where it is for `seconds` — no passive recovery.
##
## What turns an EMP from a flicker into a stun. E-KILL is a threshold at 0.01
## and recovery is 0.08/s, so a robot knocked flat to zero climbed back out of
## E-KILL in about an eighth of a second: it twitched and carried on. Locked, it
## stays down for the duration, then climbs back through CRITICAL, DEGRADED and
## FUZZED the ordinary way — so the whole disruption lasts several seconds and
## tapers rather than switching off.
##
## Divided by signal_resistance, the same as the damage itself: a Hardened
## Uplink shortens the lock as well as softening the hit.
func lock_signal(seconds: float) -> void:
	_signal_locked_t = maxf(_signal_locked_t, seconds / maxf(signal_resistance, 0.01))


func _tick_signal(delta: float) -> void:
	# Passive signal recovery, unless something is holding it down.
	if _signal_locked_t > 0.0:
		_signal_locked_t = maxf(0.0, _signal_locked_t - delta)
	elif signal_integrity < 1.0:
		signal_integrity = minf(1.0, signal_integrity + signal_recovery_rate * delta)
	_update_ekill_latch()

	# DEGRADED: movement hesitation — occasional stutter
	if get_signal_state() == SignalState.DEGRADED:
		_signal_stutter_timer += delta
		if _signal_stutter_timer >= SIGNAL_STUTTER_INTERVAL:
			_signal_stutter_timer = 0.0
			if randf() < 0.35:  # 35% chance to stutter each interval
				velocity.x = 0
				velocity.z = 0

	_tick_signal_vfx(delta)
	_tick_ekill_edge()


# Arcs off the chassis, heavier the worse the signal is. Driven from here
# rather than from _enter_ekill(), which is called EVERY PHYSICS FRAME while a
# robot is down — anything spawned in there fires sixty times a second.
#
# The whole ramp is one effect at one dial. Suppression is a meter the player
# is filling, and it should look like one: nothing at all while clean, a
# flicker at FUZZED, spitting at CRITICAL, and a robot standing in its own
# short circuit at E-KILL.
#
# BUILT ONCE, THEN ONLY DIMMED. The first version built a particle system each
# time signal dipped under FUZZED and freed it each time it climbed back — and a
# robot under suppression does not sit at 0.2, it hovers right on the 0.75 line,
# pushed under by near-misses and pulled back by recovery. That was a whole
# ParticleProcessMaterial, CurveTexture, QuadMesh and material allocated and
# thrown away on every crossing. Now it is made the first time it is needed and
# just stops emitting on recovery; the node goes when the robot does.
func _tick_signal_vfx(delta: float) -> void:
	if signal_integrity >= SIGNAL_FUZZED or not alive:
		_quiet_signal_arc()
		return
	if _signal_arc == null or not is_instance_valid(_signal_arc):
		_signal_arc = _SignalArc.new()
		add_child(_signal_arc)
		_signal_arc.position = Vector3(0, 0.9, 0)
	# 0 at the FUZZED threshold, 1 at dead. Held at full for the whole of an
	# e-kill, recovery included: a continuous crackle is how you tell a robot
	# that is still out from one that is merely hurting.
	var level: float = 1.0 if _ekill_latched else inverse_lerp(SIGNAL_FUZZED, 0.0, signal_integrity)
	_signal_arc.tick(delta, level)


# Stops the arcs without freeing anything. Called on recovery, and on death:
# the downed branch of _physics_process switches physics OFF before
# _tick_signal_vfx can run again, so without a call here a robot that went down
# while suppressed kept sparking as a wreck — through the fall, the settle and
# the reclaimer — and a sparking wreck reads as a robot that is still alive.
func _quiet_signal_arc() -> void:
	# Every clean robot that was ever suppressed comes through here every
	# frame; only the first one after recovery has anything to do.
	if _signal_arc != null and is_instance_valid(_signal_arc) and _signal_arc._intensity > 0.0:
		_signal_arc.set_intensity(0.0)


# ONE announcement per e-kill, not one per frame. Cleared when the robot climbs
# back out, so a robot knocked down twice is two events — which is right, it
# was taken out of the fight twice.
func _tick_ekill_edge() -> void:
	var down: bool = get_signal_state() == SignalState.EKILL and alive
	if down == _ekill_announced:
		return
	_ekill_announced = down
	if down:
		ekilled.emit(self, _signal_source)
		_Analytics.ekill(self, _signal_source, _signal_cause)

func _can_receive_orders() -> bool:
	# CRITICAL or E-KILL: robot ignores squad orders
	var state = get_signal_state()
	return state != SignalState.CRITICAL and state != SignalState.EKILL

func get_effective_detection_radius() -> float:
	match get_signal_state():
		SignalState.FUZZED:    return detection_radius * 0.85
		SignalState.DEGRADED:  return detection_radius * 0.5
		SignalState.CRITICAL:  return detection_radius * 0.2
		SignalState.EKILL:     return 0.0
		_:                     return detection_radius

func get_faction():
	return faction

func _is_hostile(body: Node3D) -> bool:
	if body is Player:
		return Enums.are_hostile(faction, (body as Player).faction)
	if body is Enemy:
		return Enums.are_hostile(faction, (body as Enemy).faction)
	return false

## `exclude` in Godot 4 is Array[RID], not Array[Node]. The old version
## passed nodes, which meant the exclusion silently did nothing and rays
## could hit the caster's own capsule. Also no longer blanket-excludes the
## player when there's no combat target.
func is_path_clear(from: Vector3, to: Vector3, ignore: Node3D = null) -> bool:
	var space_state = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclusion: Array[RID] = [_self_rid]
	if ignore != null and ignore is CollisionObject3D:
		exclusion.append((ignore as CollisionObject3D).get_rid())
	query.exclude = exclusion
	return not space_state.intersect_ray(query)

func force_check_detection():
	if detection == null or detection.get_child_count() == 0:
		return
	var shape = detection.get_child(0).shape
	var space_state = get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = detection.global_transform
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var exclusion: Array[RID] = [_self_rid]
	query.exclude = exclusion
	var results = space_state.intersect_shape(query, 64)
	for result in results:
		var collider = result.collider
		if collider is Player or collider is Enemy:
			_on_detection_body_entered(collider)

func _on_detection_body_entered(body: Node3D) -> void:
	if ai_state == AIState.DEAD:
		return
	# E-KILL and CRITICAL: sensors too degraded to detect anything
	var sig_state = get_signal_state()
	if sig_state == SignalState.EKILL or sig_state == SignalState.CRITICAL:
		return
	if not (body is Player or body is Enemy):
		return
	# Downed or destroyed: not a threat, and not worth acquiring.
	if "alive" in body and not body.alive:
		return
	if ai_state == AIState.COMBAT and combat_target == body:
		return
	if not _is_hostile(body):
		return
	# Detection used to be last-enterer-wins: anything walking into the radius
	# took the target, even from 40m away while something was shooting at us
	# from 3m. Nearest wins now, which is the same rule _check_close_threat uses.
	if ai_state == AIState.COMBAT and combat_target != null \
			and is_instance_valid(combat_target) and combat_target.alive:
		if global_position.distance_to(body.global_position) \
				>= global_position.distance_to(combat_target.global_position):
			return
	if sig_state != SignalState.CLEAN:
		var eff_range = get_effective_detection_radius()
		if global_position.distance_to(body.global_position) > eff_range:
			return
	if is_path_clear(global_position + Vector3.UP * 0.8, body.global_position, body):
		trigger_combat(body)
		if stimulus_manager != null:
			stimulus_manager.emit_stimulus(
				StimulusManager.StimulusType.ENEMY_SPOTTED,
				body.global_position, faction, body)
	else:
		# Spotted but no clear line. This used to assign combat_target directly,
		# which silently replaced whatever we were actually fighting with a body
		# behind a wall — without changing state, so nothing corrected it. Only
		# fill the slot when it's empty.
		checking_for_target = true
		if combat_target == null:
			combat_target = body

func _on_detection_body_exited(body: Node3D) -> void:
	if checking_for_target and body == combat_target:
		checking_for_target = false

func trigger_combat(body: AI):
	# A downed robot keeps its collider (so the repair tool can hit it) and is
	# still found by detection and line-of-sight checks. Without this guard the
	# squad re-triggers combat on a wreck forever and never stands down.
	if body == null or not is_instance_valid(body):
		return
	if not body.alive:
		return
	# Only the TRANSITION into combat is worth announcing. Re-triggering on an
	# already-engaged target would call contact every time the target moved.
	# The director throttles per squad on top of this, so four robots acquiring
	# the same enemy still produce one call.
	if bark != null and ai_state != AIState.COMBAT:
		bark.bark(BarkSet.Line.CONTACT, body.soldier_name if "soldier_name" in body else "")
	change_combat_target(body)
	movement_target = Vector3.ZERO
	change_ai_state(AIState.COMBAT)
	combat_triggered.emit(self)
	checking_for_target = false
	combat_time = combat_recon_time
	reconsider_combat()


# ─────────────────────────────────────────────
# ACCURACY
# ─────────────────────────────────────────────
func get_inaccurate_target(target_pos: Vector3) -> Vector3:
	if weapon == null:
		return target_pos
	# Was measuring distance to weapon_target rather than the passed-in
	# position, which diverged whenever a subclass passed something else.
	var dist := global_position.distance_to(target_pos)

	var effective_skill = accuracy_skill * maxf(signal_integrity, 0.1)
	var spread_mrad = weapon.ai_spread_mrad / maxf(effective_skill, 0.01)
	spread_mrad *= get_aim_spread_multiplier()

	var spread_m = spread_mrad * dist / 1000.0

	return target_pos + Vector3(
		randf_range(-spread_m, spread_m),
		randf_range(-spread_m * 0.35, spread_m * 0.35),
		randf_range(-spread_m, spread_m)
	)

## Settled and stationary shoots tight. Snap-firing on the move is bad.
## This is what makes "stop and aim" vs "shoot while moving" a real choice
## rather than two labels for the same behaviour.
func get_aim_spread_multiplier() -> float:
	var mult := 1.0
	if aim_settle_time > 0.0:
		var t = clampf(_aim_tracking / aim_settle_time, 0.0, 1.0)
		mult = 1.0 / maxf(lerp(aim_floor, 1.0, t), 0.01)
	if _is_moving():
		mult *= moving_accuracy_penalty
	return mult
