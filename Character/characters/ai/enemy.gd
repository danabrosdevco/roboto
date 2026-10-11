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
## By path, not by class_name: a direct GeneratedTerrain reference from here is
## the cyclic-resolution trap this file already documents for SmokeVolume.
const _GeneratedTerrain := preload("res://Env/terrain/generated_terrain.gd")
## Smoke blocks sight but not bullets, so is_path_clear() asks it separately.
## By path for the same reason as the others: a brand-new class_name is not
## resolvable until the editor rescans, and enemy.gd is depended on by almost
## everything — referencing SmokeVolume directly failed the parse check on
## fifty scripts at once.
const _Smoke := preload("res://Character/weapon/smoke_volume.gd")

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

# ── THE SECOND MOUNT ──────────────────────────
# A COAXIAL gun, not a second independent weapon.
#
# ChassisDefinition has carried `weapon_slots` for a long time, but everything
# downstream assumed one gun: `weapon` is a single reference, equip_weapon_scene
# takes one scene, and handle_weapon_logic drives that one. Two guns is runtime
# work, and the cheap half of it is worth having on its own.
#
# So the coax is deliberately NOT a second decision-maker. The main gun picks
# the target, owns _prefire_threshold, bursts, reloads and the whole state
# machine, exactly as it does today. The coax only asks two questions, every
# tick: is the main gun on target, and is the range inside MY band. If both,
# it fires on its own cooldown.
#
# That means it keeps firing through the main gun's reload, which is what a
# coax is for, and it costs the AI no choices at all. Independent target
# selection can come later if this earns it.
@export var coax: AIWeapon
@export var coax_mount: Node3D
var _coax_time: float = 0.0


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


## The same, for the coaxial mount. A frame with no `coax_mount` has one gun
## and says so rather than silently dropping the second one the player fitted.
func equip_coax_scene(scene: PackedScene) -> void:
	if coax_mount == null:
		if scene != null:
			push_warning("%s was given a second weapon but has no coax_mount, so it was dropped. Only a two-mount frame (the Walker) can carry one." % name)
		return
	for child in coax_mount.get_children():
		child.queue_free()
	if scene == null:
		coax = null
		return
	var instance := scene.instantiate()
	coax_mount.add_child(instance)
	instance.transform = Transform3D.IDENTITY
	coax = instance as AIWeapon
	if coax == null:
		push_warning("%s is not an AIWeapon scene, so it cannot be a coax." % scene.resource_path)
@export var bark: Bark
@export var detection: Area3D
@export var particle_effects_die: Array[ParticleEffect]
@export var particle_effects_hit: Array[ParticleEffect]
@export var visible_pieces: Array[Node3D]

## HOW FAR A PATROL KEEPS WALKING. Not an exemption — a bigger radius.
##
## A patrol exempted from culling outright ticks for the whole mission wherever
## the fight is, and on a 1111 m map that is eighteen robots running full
## brains and asking the navigation server for paths forever. Qamareen went
## noticeably slow on it.
##
## This instead says a patrolling squad stays awake much further out than a
## garrison does, and sleeps beyond that. Picked so the route is already in
## motion by the time you can see down it: you still never find a patrol parked
## on point 0, and the ones on the far side of the city cost nothing.
@export var patrol_activation_distance: int = 260
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
## Frame id -> how many of that frame this robot got back up, so XP can be paid
## by what was saved. A walker is worth more to recover than a rifleman.
var revives_by_kind: Dictionary = {}

## What this robot last told the contact ledger it was shooting. Held so the
## release can be exact even after combat_target has already moved on.
var _claimed = null
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

# signal_integrity, signal_recovery_rate and signal_resistance are declared on
# AI now — see the header there. What stays in this file is the BEHAVIOUR the
# number drives: the cascade below, the chassis arcs, and the e-kill broadcast.

# Never enters passive mode — set true on soldiers with active squad objectives
@export var always_active: bool = false
# Exempt from distance culling entirely: it has somewhere to be and a long way
# to go. Set by EnemyForceSpawner.wake() on reinforcements, which spawn well
# outside activation_distance and have to advance from there. A plain var
# rather than an export so it cannot be set per scene by accident, and so
# Enemy does not grow another property for an open editor to write into every
# robot scene in the game.
## A HOSTILE ON A PATROL ROUTE IS NOT CULLED.
##
## Distance culling asks how far this robot is from the nearest thing it would
## fight, and freezes it beyond activation_distance. That is right for a
## garrison — a robot standing on a post you have not reached yet costs nothing
## and loses nothing by waiting. It is exactly wrong for a patrol, whose entire
## job is to be somewhere unpredictable by the time you arrive.
##
## Measured before this existed: of the four patrol routes in Qamareen, three
## squads walked 0.0 m in two minutes and not one advanced a single leg. They
## sat on point 0 until the player came within 75 m, which meant every patrol in
## the game was discovered parked at the start of its route. The fourth only
## moved because it had blundered into a fight.
##
## NOT `always_active`, which every EnemySquadSpec in every mission sets and
## which this check deliberately ignores — see the note on the cull below. This
## is set by Squad._issue_objective_orders and cleared the moment the squad is
## given anything else to do, so the exemption covers the patrol squads and
## nothing else: eighteen robots in Qamareen rather than two hundred.
var on_patrol: bool = false

var never_culled: bool = false
## Seconds of that exemption left, for one given by exempt_from_culling().
var _exempt_left: float = 0.0
## How long a reinforcement may keep it if it never reaches you: long enough to
## walk in from 90 m out at any speed, nowhere near long enough to last a
## mission.
const CULL_EXEMPT_SECONDS := 90.0
## Culled AND switched off: `_physics_process` is not running on this robot.
##
## PASSIVE already costs almost nothing to RUN — the early returns above the
## cull and the cheap-out in _apply_motion see to that — but the engine still
## pays to CALL the callback on every one of them. bench_qamareen measures the
## Qamareen garrison (186 hostiles, 176 culled) at 26.1 ms a physics frame and
## 23.3 ms with the callback switched off on the culled ones, with Jolt
## reporting zero active bodies and zero collision pairs either way: none of
## that is simulation, it is 176 script calls that early-return.
##
## A ROBOT WITH `_physics_process` OFF CANNOT NOTICE THAT IT SHOULD WAKE UP.
## That is the whole hazard here, and it is why waking lives outside the robot:
## AIManager polls the frozen ones on a slow round-robin (see _poll_frozen),
## and wake(), exempt_from_culling() and trigger_combat() thaw on the spot
## because they are already called from outside the tick. Nothing may be added
## to _physics_process that a frozen robot needs in order to come back.
var cull_frozen: bool = false
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
## How much wider it shoots, for as long as it is on the trigger.
##
## Skipping the sight picture was meant to be the cost, and it is not one: the
## aim goes on settling WHILE the burst fires, so a second in, the robot was
## putting out three rounds for one at a full sight picture. A rifleman with a
## Cyclic Feed came home ahead of a rover, and the answer at the time was to
## make it miss a great deal — 3.0, roughly a third of the hits at three times
## the rate.
##
## TONED DOWN TO 1.6, because the thing it was paying for now pays for itself.
## When 3.0 was set, suppression was measured at the round's IMPACT point, so a
## stream of near misses mostly did nothing at all and volume of fire had no
## value except the hits it happened to land — the penalty had to be brutal or
## the module was simply a damage upgrade. Volume is now worth something on its
## own: fire is measured along the whole flight path, a connecting round is
## worth 1.5x a passing one, and signal recovery is half what it was. A Cyclic
## Feed robot earns its seat by pinning things, so it no longer has to be
## crippled to stop it also winning the damage race.
##
## One const, deliberately: this is the global ratio between aimed and cyclic
## accuracy, not a per-robot dial.
const SUPPRESSIVE_SPREAD := 1.6
var _suppress_pause: float = 0.0
## Seconds after going down before this robot gets back up by itself, once per
## deployment. Set from the Nanite Reboot module at spawn; 0 is never.
@export var self_revive_seconds: float = 0.0
var _self_revive_used: bool = false
var _self_revive_gen: int = 0
# The arcs coming off this one while its signal is down. Made on demand, freed
# when it recovers. See _tick_signal_vfx.
var _signal_arc: Node3D = null
# Edge flag for `ekilled` — the E-KILL check runs every frame.
var _ekill_announced: bool = false
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
## Real seconds since the last vision scan actually ran. See _tick_vision.
var _vision_since: float = 0.0
var _awareness: Dictionary = {}   # body -> 0..1


# ─────────────────────────────────────────────
# HOW OFTEN A ROBOT DECIDES ANYTHING
# ─────────────────────────────────────────────
# THINKING IS SLICED. ACTING NEVER IS. That line is the whole of this, and
# putting it in the wrong place is how it ships broken — see the two halves of
# _physics_process.
#
# DECIDING is who to shoot, where to walk, can I see it, is something nearer,
# am I off the navmesh. All of it costs per robot per decision, which is what
# makes the frame scale with the size of the battle rather than with the size
# of the map.
#
# ACTING is movement, facing, animation and the trigger. None of it is sliced,
# at any distance, in any state: a robot that moves every other frame stutters
# and a robot that fires on a cadence feels broken, and both are visible from
# across the level.
#
# Three inputs decide the cadence, not one:
#
#   1. DISTANCE SETS THE FLOOR. Near, full rate. Mid, a quarter of it. Far,
#      much slower. The same question lod_scale() asks, in bands.
#   2. STATE MODIFIES IT, AND COMBAT IS THE *CHEAP* TIER. This is deliberate
#      and it is the opposite of what you would guess — see THINK_COMBAT_SCALE.
#   3. AN ADAPTIVE PER-FRAME BUDGET IS THE BACKSTOP. Tiers say who deserves a
#      slice; the budget says how many of this frame's candidates get one. See
#      take_think_slice().
#
# There is no setting for any of it. It tunes itself off measured frame time.

## Seconds a NEAR robot may go without thinking: one physics frame, which is
## exactly what every robot did before this existed.
const THINK_NEAR: float = 1.0 / 60.0
## MID — out past lod_near_distance. Quarter rate.
const THINK_MID: float = 4.0 / 60.0
## FAR — out past lod_far_distance. Much slower: at that range a robot reads as
## a silhouette that is either there or not, and nothing about its decisions
## reaches the player at all.
const THINK_FAR: float = 18.0 / 60.0

## COMBAT IS THE CHEAP TIER, AND THAT IS NOT A MISTAKE.
##
## A robot already trading fire can think far less often than one that is not.
## The human's words: "once they're in combat they're fine, they wiggle and
## shoot, it gets chaotic, the player can't track". A firefight hides latency —
## nobody is following an individual unit through it, and the acting half (the
## wiggling and the shooting) still runs every single frame.
##
## The EXPENSIVE moments are the watched ones: a fresh order, first contact, a
## robot crossing open ground. None of them gets this discount, the first two get
## full rate at any range (mark_watched), and all three get the top priority when
## the budget is rationing (_think_share). Do not invert this.
const THINK_COMBAT_SCALE: float = 12.0
## ...BUT NOTHING WAITS LONGER THAN THIS FOR A DECISION, whatever the tiers
## multiply out to, and this number was bought with a measurement.
##
## At 1.0 s the discount reached 0.8 s in the mid band and the ceiling itself out
## past 80 m, and the Laboratory's engagement-range plan said plainly what that
## costs: melee closers took 25% more kills per body and shotgun troopers 15%
## fewer, with rifle troopers unchanged — against a two-run noise band of about
## 6 percentage points on the aggregate. COARSE THINKING FAVOURS THE AGGRESSOR,
## which makes sense and is worth writing down: a charger's plan is "run at them"
## and running is the acting half, which never slowed down. A defender's whole
## advantage is REACTING — re-checking line of sight, re-picking a target, giving
## ground — and that is the half being rationed.
##
## 0.35 s is a shade over targeting_recon_time (0.33 s), so no robot's decisions
## go staler than the slowest timer the old code already ran them at. It costs
## almost nothing: the saving that matters is a near-band brawl, where the
## discount lands at 0.2 s and is nowhere near this cap.
##
## THE SIDE EFFECT, SAID OUT LOUD: out past lod_far_distance the distance tier is
## already at 0.3 s, so capping the discount at 0.35 s leaves the far band with
## no meaningful discount for being in combat. That is the ceiling overriding the
## model, not a bug in it — a robot nobody can see is already thinking rarely,
## and there was never much left for the firefight to take off it.
const THINK_CEILING: float = 0.35

## How long a watched moment stays watched. Long enough to cover the beat after
## an order arrives or a contact is called; short enough that it is an event
## rather than a state, because a 50v50 generates these constantly.
const THINK_WATCHED_SECONDS: float = 0.75

## HOW FAR INTO THE FRAME'S BUDGET EACH PRIORITY CLASS MAY REACH.
##
## This is how tiers become priority without a sort. Nobody can see the whole
## frame's candidate list — robots arrive one at a time, in tree order, through
## their own callbacks — so instead of ranking them, each class is simply told
## how much of the budget it is allowed to touch. The cheap classes hit their
## ceiling first and are refused, while the watched ones still have room. That is
## the degradation the human asked for: the far and the already-fighting starve
## before anything you are looking at does.
##
## AND IT ONLY APPLIES UNDER PRESSURE — see `_think_pressed`. A ceiling that
## bites on a frame with room to spare is not triage, it is just a slower AI:
## measured on the 100-robot bench, about ten robots sat permanently refused
## against a budget that was at its MAXIMUM and barely a third spent, each of
## them waiting out the full THINK_OVERDUE before being let through. Nothing was
## bought by that.
const THINK_SHARE_WATCHED: float = 1.0
const THINK_SHARE_PLAIN: float = 0.7
const THINK_SHARE_CHEAP: float = 0.3

## What the game may spend on its own scripts in a frame before the budget
## starts shrinking. 16.6 ms is the whole frame at 60 Hz; this leaves room for
## the physics solver, the servers and rendering.
const THINK_TARGET_MS: float = 11.0
## The budget never drops below this. A frame can always afford a handful of
## decisions, and a level that stops deciding anything is worse than a slow one.
const THINK_BUDGET_MIN_US: int = 400
const THINK_BUDGET_MAX_US: int = 4000
## ...AND IT WILL NOT SQUEEZE BELOW THINKING THAT IS NOT THE PROBLEM.
##
## A controller watching only total frame time pulls the only lever it has
## whenever the frame is late, whatever the frame is late FOR. Measured: Qamareen
## sits at 16 ms of physics with ten robots awake, almost none of it thinking, and
## the first version of this pinned the budget to its floor and refused 24,013
## slices in 400 frames to save nothing at all. Starving an AI that is not the
## bottleneck is the worst of both — slower frames and worse robots.
##
## So the frame has to be late AND thinking has to be a real part of why. Below
## this much spent per frame it is not, and the budget stops shrinking. Above it,
## squeezing works, which is exactly the 50v50 brawl this is for.
const THINK_WORTH_SQUEEZING_US: int = 1000
## Shrinks fast, grows slow — the usual asymmetry, so a spike is answered at
## once and recovery does not re-spike.
const THINK_BUDGET_SQUEEZE: float = 0.90
const THINK_BUDGET_EASE_US: int = 60
## A robot the budget has refused for this long thinks anyway, at the top
## priority, whatever its tier says.
##
## THIS IS THE SAFETY NET AND IT IS LOAD-BEARING. Without it a saturated frame
## starves the cheap classes indefinitely and a firefight on the far side of the
## level quietly stops being a firefight — the same hazard AIManager's frozen
## poll closes for the distance cull, by the same route through a different door.
const THINK_OVERDUE: float = 1.5

## Microseconds of thinking allowed across ALL robots in one physics frame.
## Static, like the nav and snap budgets above it, because the thing being
## rationed is the frame and not the robot.
static var _think_budget_us: int = THINK_BUDGET_MAX_US
static var _think_budget_frame: int = -1
static var _think_spent_us: int = 0
## IS THE FRAME ACTUALLY IN TROUBLE, AND IS THINKING PART OF WHY?
##
## Both halves, for the reason THINK_WORTH_SQUEEZING_US gives. This is the one
## flag that decides whether the cost model is rationing or merely scheduling:
## off it, the tiers alone set the cadence and every candidate that is due gets
## its slice; on it, the priority shares come in and the cheap classes are turned
## away. Set once a frame by the retune, off a measurement, with no setting
## anywhere near it.
static var _think_pressed: bool = false
## Slices refused this run. Counted rather than warned, exactly like
## `_snap_refused`: this is a designed fallback on a hot path, not a fault, and
## a warning per refusal would be a warning per frame.
static var _think_refused: int = 0

## Delta owed to the think half since its last slice. Handed to the decision
## functions in place of this frame's delta — see the note in _physics_process.
var _think_owed: float = 0.0
## Seconds until this robot wants another slice.
var _think_wait: float = 0.0
## Seconds of "the player is looking at this" left. Set by mark_watched(),
## wake() and trigger_combat() — which is to say by an order arriving from
## outside, by being shot at, and by first contact.
var _watched_t: float = 0.0


## This robot is in the middle of something the player is watching, so it thinks
## at full rate for a moment whatever its distance band says.
##
## FROM OUTSIDE ONLY. The point of a watched moment is that something happened
## TO the robot; a robot that marks its own decisions watched grants itself full
## rate for making decisions, which is a loop and not a model (see the note in
## move_to). Callers: Squad.set_objective, wake(), trigger_combat().
func mark_watched() -> void:
	_watched_t = maxf(_watched_t, THINK_WATCHED_SECONDS)


## 0 near, 1 mid, 2 far — the same bands lod_scale() lerps between, and the same
## exemption for your own robots.
##
## MEASURED TO THE PLAYER'S EYE, not to the nearest hostile. The distance CULL
## asks the other question deliberately (a robot 300 m away still has to fight
## your squad, so it stays awake), and this is not that question: this one is
## about FIDELITY, and fidelity is only owed to what someone can see.
func _think_tier() -> int:
	if squad_directed and not Enums.are_hostile(Enums.Factions.PLAYER, faction):
		return 0
	if player == null:
		return 0
	var d_sq: float = global_position.distance_squared_to(player.get_focus_position())
	if d_sq <= lod_near_distance * lod_near_distance:
		return 0
	if d_sq <= lod_far_distance * lod_far_distance:
		return 1
	return 2


## Is this robot in the open, under way, and not yet shooting at anything? The
## third of the human's three watched moments, and the only one of them that is a
## STATE rather than an event — which is why it is asked rather than timed.
func _crossing_open_ground() -> bool:
	return movement_state != MovementState.NONE and ai_state != AIState.COMBAT


## Seconds this robot may go without a decision. The cost model, assembled.
##
## Deliberately takes no tier: the tick reads this AFTER the thinking, off the
## state the decisions left behind, by which point the robot has moved and the
## tier it was PRIORITISED on is a frame out of date. One distance test per
## think, not per frame.
func think_wait_seconds() -> float:
	# A WATCHED MOMENT IS NEVER CHEAP, at any range.
	if _watched_t > 0.0:
		return 0.0
	var tier: int = _think_tier()
	var floor_s: float = THINK_NEAR if tier == 0 else (THINK_MID if tier == 1 else THINK_FAR)
	# ...and here is the cheap tier. has_live_target() rather than the state
	# alone: a robot sitting in COMBAT holding a target that has been downed is
	# not in a firefight, it is about to go and look for another one, which is a
	# decision worth making promptly.
	#
	# NOTHING ELSE MODIFIES THE FLOOR, and that is deliberate. The other two
	# watched moments are events and set _watched_t above; the third — crossing
	# open ground — is not in combat, so it never had the discount to lose, and
	# the band it is standing in is already its full rate.
	#
	# IT WAS PROMOTED A BAND AND THAT WAS WRONG. Handing every mid-band mover the
	# near band's every-frame cadence put about thirty of the bench's hundred
	# robots on full rate permanently — 33 candidates a frame against a budget
	# that could serve a handful, so the backstop refused 13,403 slices in 400
	# frames and the frame time did not move. A mover gets the top PRIORITY
	# instead (see _think_share), which is what being watched is actually worth:
	# never starved, not re-rated.
	if ai_state == AIState.COMBAT and has_live_target():
		return minf(floor_s * THINK_COMBAT_SCALE, THINK_CEILING)
	return floor_s


## How far into this frame's budget this robot is allowed to reach. `tier` comes
## from the tick, which has already worked it out; -1 asks for it.
func _think_share(tier: int = -1) -> float:
	# OVERDUE OUTRANKS EVERYTHING. See THINK_OVERDUE.
	if _think_owed >= THINK_OVERDUE:
		return THINK_SHARE_WATCHED
	# The three watched moments, and all three get the whole budget to reach into:
	# an order just arrived, contact was just called or this robot was just shot,
	# or it is out in the open on its way somewhere. Those are the frames a player
	# is reading a robot's behaviour on, so they are the last thing to starve.
	if _watched_t > 0.0 or _crossing_open_ground():
		return THINK_SHARE_WATCHED
	if ai_state == AIState.COMBAT and has_live_target():
		return THINK_SHARE_CHEAP
	if tier < 0:
		tier = _think_tier()
	if tier == 2:
		return THINK_SHARE_CHEAP
	return THINK_SHARE_PLAIN


## May this frame afford another decision from a robot of this priority class?
##
## The first candidate of a frame is always allowed, like the nav budget's, so
## that a pathologically tight frame still decides SOMETHING rather than nothing
## — and so that a single robot in an empty level never answers to a budget.
static func take_think_slice(share: float) -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _think_budget_frame:
		_think_budget_frame = frame
		_retune_think_budget()
		_think_spent_us = 0
		return true
	# The budget is the ceiling on any frame; the SHARE narrows it to this
	# priority class, and only while the frame is in trouble. See _think_pressed.
	var ceiling: int = _think_budget_us
	if _think_pressed:
		ceiling = int(float(_think_budget_us) * share)
	if _think_spent_us >= ceiling:
		_think_refused += 1
		return false
	return true


## Charged by the caller once the thinking is done, because only the caller
## knows where its own decisions ended.
static func spend_think(us: int) -> void:
	_think_spent_us += us


## SELF-TUNING, OFF MEASURED FRAME TIME, WITH NO SETTING.
##
## Both monitors, summed: the think half runs in _physics_process and the squad
## half runs in _process, and what is being rationed is the CPU the game spends
## on its own scripts — the number the player feels. Reading one of them would
## leave the budget blind to half of its own cost.
##
## The monitors report the frame that has just finished, which is the only
## sample available part-way through this one, and is exactly the feedback this
## wants: spend less after an expensive frame, a little more after a cheap one.
static func _retune_think_budget() -> void:
	var spent_ms: float = (Performance.get_monitor(Performance.TIME_PROCESS) \
		+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	# No sample yet — the first frames of a level, or a harness that never ran a
	# frame. Left exactly as it is rather than tuned off a zero, which would peg
	# the budget to its maximum on the frame a level loads, which is the single
	# most expensive frame there is.
	if spent_ms <= 0.0:
		return
	# `_think_spent_us` is still the frame that has just finished: the caller
	# zeroes it immediately after this returns. Both halves of the test are
	# needed — see THINK_WORTH_SQUEEZING_US.
	_think_pressed = spent_ms > THINK_TARGET_MS and _think_spent_us > THINK_WORTH_SQUEEZING_US
	if _think_pressed:
		_think_budget_us = maxi(THINK_BUDGET_MIN_US,
			int(float(_think_budget_us) * THINK_BUDGET_SQUEEZE))
	else:
		_think_budget_us = mini(THINK_BUDGET_MAX_US, _think_budget_us + THINK_BUDGET_EASE_US)


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
	# AND THE ADRIFT POLL, WHICH HAD BEEN MISSED ALL ALONG.
	#
	# It resets to a flat second and started at zero on every robot, so the whole
	# population asked NavigationServer3D.map_get_closest_point on the SAME frame
	# once a second, for the whole mission. bench_ai with 100 robots on Mutaha:
	# 50-65 ms frames at f31, f91, f151, f211, f271, f331, f391 — every sixtieth
	# frame, to the frame — against a 14 ms median. See _tick_adrift.
	_adrift_poll = randf()
	# Think slices spread too, so a squad spawned in one loop does not queue its
	# whole first round of decisions onto one frame either.
	_think_wait = randf() * THINK_FAR



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
	_vision_since += delta
	if _vision_timer > 0.0:
		return
	var lod: float = lod_scale()
	# CHARGED IN REAL SECONDS, NOT NOMINAL ONES.
	#
	# `elapsed` is the time step the awareness arithmetic below integrates over —
	# a contact is called after `needed` seconds of clear view, built up
	# elapsed-at-a-time. It used to be the INTERVAL this tick was scheduled at
	# rather than the time that actually passed, which was close enough while
	# vision was the only thing throttling it (one frame of overshoot) and stops
	# being close enough the moment anything coarser does: the think slice can be
	# a fifth of a second apart in a firefight and a whole second apart out past
	# lod_far_distance, and charging 0.15 s for 1.0 s of looking would have made
	# acquisition take six times as long for robots out there.
	#
	# With the real figure, acquiring a contact takes `acquire_time * penalty`
	# seconds under ANY cadence, which is what acquire_time claims to mean. The
	# decay path below wants the same number for the same reason.
	var elapsed: float = _vision_since
	_vision_since = 0.0
	_vision_timer = vision_interval * lod

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

# SignalState, the four thresholds and SIGNAL_EKILL_RECOVER now live on AI, so
# the player shares them. Still reachable unqualified here, and as
# Enemy.SignalState from outside, because Enemy extends AI.

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
@export var adrift_distance: float = 4.0
@export var adrift_seconds: float = 4.0
## How far back the recovery will reach for the spot this robot fell from.
## Beyond it the remembered point is stale and the nearest mesh point is used
## instead — see the note in _tick_adrift.
@export var adrift_return_limit: float = 25.0
## How deep it has to be before it drowns. Measured from the water SURFACE, so
## this is "up to its neck", not "its feet are wet" — wading a shallow margin
## at the edge of a river has to stay survivable or every bank becomes a cliff.
@export var drown_depth: float = 2.5
var _adrift_t: float = 0.0
var _adrift_poll: float = 0.0
## The last place this robot stood that was ON the navmesh.
var _last_on_mesh: Vector3 = Vector3.ZERO
var _has_last_on_mesh: bool = false
var activation_distance_sq: float
var patrol_activation_distance_sq: float

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
## Seconds since anything last hit this robot, for EquipmentContext. Counted
## rather than flagged so "under fire" can be asked with a threshold instead of
## something having to remember to clear a bool. Starts at NEVER_HIT.
var _since_hit: float = AIEquipment.NEVER_HIT
## How far out we are willing to look for the hostiles standing around a
## prospective landing point. Beyond this a throw is not on anyway.
const EQUIPMENT_CLUSTER_RADIUS: float = 6.0
## How far a robot will throw to a point the player designated. AIGrenade's own
## max_throw_distance is 30 and it is the longest throw in the kit, so this is
## that with a little slack: a robot a metre outside the grenade's own limit
## should walk-to-throw eventually rather than refuse on a rounding error.
## Beyond it the order is refused OUT LOUD — see order_use_equipment.
const ORDERED_THROW_RANGE: float = 34.0

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
## See _enter_tree() and csg_bake.gd.
const _CsgBake := preload("res://Character/characters/ai/csg_bake.gd")
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
	patrol_activation_distance_sq = float(patrol_activation_distance) * float(patrol_activation_distance)
	_self_rid = get_rid()
	_collision_shape = _find_collision_shape()
	_measure_body_radius()

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
		_path_height_base = nav_agent.path_height_offset

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


# EVERY shape, not just the first. A frame is allowed more than one — the Rover
# wears a low box for its hull and wheels and a second, much smaller one around
# its turret, because one capsule big enough to cover the turret also filled a
# metre of empty air over the whole length of the deck and caught every shot
# that should have sailed across it. Turning off only the first left a dead
# rover's turret standing there solid, stopping rounds and shouldering the
# living out of the way.
func _set_colliders_disabled(off: bool) -> void:
	if _collision_shape == null:
		_collision_shape = _find_collision_shape()
	var found := false
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", off)
			found = true
	if not found and _collision_shape != null:
		_collision_shape.set_deferred("disabled", off)


# ─────────────────────────────────────────────
# PHYSICS PROCESS
# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	# BEFORE ANYTHING READS A TARGET. See the note on the function.
	_drop_freed_references()
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

	# Signal still ticks when passive or disabled, so a robot can actually
	# recover from an e-kill instead of being bricked forever.
	#
	# NOMINAL SIGNAL COSTS NOTHING NOW.
	#
	# The whole signal machine is three values — integrity, the jam-lock timer
	# and the e-kill latch — and on a robot that has never been jammed all three
	# sit at rest. _tick_signal then makes five calls that each early-return,
	# every frame, for every robot in the level. This runs AHEAD of the distance
	# cull, so on Qamareen that was 186 robots paying it whether culled or not,
	# and culling could do nothing about it.
	#
	# GATED, NOT MOVED BEHIND THE CULL. A jammed robot has to keep recovering
	# while you are somewhere else: move this below the cull and walking away
	# from an EMP'd robot leaves it latched in EKILL with nothing left running
	# to climb it back out. The gate is exact rather than approximate — with all
	# three at rest get_signal_state() returns CLEAN, so the branch below could
	# not have fired anyway.
	if signal_integrity < 1.0 or _signal_locked_t > 0.0 or _ekill_latched:
		_tick_signal(delta)
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
	# HOW FAR FROM THE NEAREST THING IT WOULD FIGHT, not how far from the player.
	# Measuring to the player said the player is the only thing worth reacting
	# to: send a squad 300 m up the road and it walked into a garrison frozen
	# solid, because you were still back at the insertion point. Your own robots
	# fought statues until you caught up. AIManager answers this from the same
	# cached hostile list the targeting already uses; without a manager the
	# player is the only source there is, which is the old behaviour.
	var dist_sq: float = ai_manager.nearest_hostile_distance_sq(faction, global_position) \
		if ai_manager != null and is_instance_valid(ai_manager) \
		else global_position.distance_squared_to(player.global_position)
	# A reinforcement keeps its exemption only until it ARRIVES, or until the
	# walk it was given runs out. It is there so it can come in from 90 m
	# without being frozen on the way, not so it ticks for the rest of the
	# mission wherever the fight goes: Coast Road wakes 39 of them, and every
	# one was still running a full brain — and asking for paths across 1.3 km
	# of map — at the extraction. A flag set by hand (a test rig) is left alone.
	if never_culled and _exempt_left > 0.0:
		_exempt_left = maxf(0.0, _exempt_left - delta)
		if _exempt_left <= 0.0:
			never_culled = false
	if never_culled and dist_sq <= activation_distance_sq:
		never_culled = false
	# A PATROL GETS A BIGGER RADIUS, NOT A FREE PASS. Exempting them outright
	# kept eighteen robots on this map running full brains and path queries for
	# the whole mission, wherever the fight was, and it cost real frame time.
	var cull_sq: float = activation_distance_sq
	if on_patrol:
		cull_sq = maxf(cull_sq, patrol_activation_distance_sq)
	if dist_sq > cull_sq and not _is_player_side() \
			and not never_culled \
			and _woken_t <= 0.0 and not squad_is_engaged():
		enter_passive_mode()
		_apply_motion()
		# AND STOP BEING CALLED AT ALL. Everything above this line that a culled
		# robot still needed — the signal recovery, the wake countdown, the
		# exemption countdown — is either excluded by _can_freeze_for_cull() or
		# already at rest by the time we get here, so the only thing left to pay
		# for is the call itself. 176 of them on Qamareen; see `cull_frozen`.
		#
		# Not an early return: when the robot cannot be frozen safely it keeps
		# its tick and the behaviour is exactly what it was before.
		if _can_freeze_for_cull():
			_freeze_for_cull()
		return
	else:
		exit_passive_mode()

	# ── THINK ─────────────────────────────────────
	# Sliced. See "HOW OFTEN A ROBOT DECIDES ANYTHING" for the cost model.
	#
	# EVERY DECISION BELOW IS ALREADY A TIMER MEASURED IN SECONDS — _tick_vision
	# at vision_interval, reconsider_target at targeting_recon_time,
	# reconsider_combat at combat_recon_time, the adrift poll at a second. So
	# they are handed the delta OWED since the last slice
	# rather than this frame's, and every one of those periods stays exactly what
	# it was authored to be. What coarsens is the GRANULARITY, and it coarsens by
	# at most think_wait_seconds() — which is the number the tiers above are choosing.
	#
	# That is why the cadence can be changed without the behaviour drifting: a
	# robot does not think LESS over a second, it thinks in fewer, bigger steps.
	_watched_t = maxf(0.0, _watched_t - delta)
	_think_owed += delta
	_think_wait -= delta
	# A robot that is not due does not even ask for a slice: asking costs a
	# distance test and a static check, and a refused candidate pays both for
	# nothing. The tier is worked out ONCE and handed to both halves of the
	# decision below.
	var thinking := false
	var tier := 0
	if _think_wait <= 0.0:
		tier = _think_tier()
		thinking = take_think_slice(_think_share(tier))
	if thinking:
		var owed: float = _think_owed
		var asked := Time.get_ticks_usec()
		_think_owed = 0.0
		_tick_adrift(owed)
		if checking_for_target and combat_target != null and _has_los:
			trigger_combat(combat_target)
		handle_time_passing(owed)
		# Still AFTER handle_time_passing, which is where reconsider_target may
		# have just written weapon_target: a self-targeting weapon's pick has to
		# win over the body's, and that precedence is the order of these two.
		_tick_weapon_target(owed)
		# THE NEXT WAIT IS SET FROM THE STATE THE THINKING LEFT BEHIND, not the
		# one it started from, and the order of these two lines is the whole
		# reason. The commonest decision made above is "my target is dead" —
		# reconsider_target drops it and enters SEARCH — and a robot that was in
		# the cheap tier when the slice began would otherwise have been handed a
		# firefight's wait on its way OUT of the firefight: up to a second of
		# standing in the open with nothing to shoot at before it was allowed to
		# notice. Read afterwards, it is already in SEARCH and gets its band's
		# ordinary rate.
		_think_wait = think_wait_seconds()
		spend_think(Time.get_ticks_usec() - asked)

	# ── ACT ───────────────────────────────────────
	# NEVER sliced. Not at range, not in a firefight, not when the budget is
	# spent. These run on THIS frame's delta for every awake robot in the level,
	# and they are what makes a robot look alive: the legs, the facing and the
	# trigger. handle_movement steers on the cached nav direction, _update_facing
	# lerps toward a target the think half chose, and handle_weapon_logic settles
	# its own aim and fires — so a robot whose thinking is a tenth of a second
	# stale still walks, turns and shoots smoothly on every single frame.
	#
	# _tick_los IS ON THIS SIDE OF THE LINE, AND IT WAS NOT AT FIRST.
	#
	# It looks like a decision — it is a raycast, and the brief for this work lists
	# line-of-sight tests among the things that may be sliced. But `_has_los` is
	# not consulted by any decision; it is the GATE ON THE TRIGGER. A stale "no"
	# is a robot that will not shoot at something standing in front of it, and a
	# stale "yes" is a robot emptying a magazine into a wall. Both of those are
	# firing behaviour.
	#
	# It cost exactly what that argument predicts. Sliced, the refresh went from a
	# flat 0.15 s to the think cadence, and the Laboratory found the damage where a
	# shooter can least afford to be a fifth of a second behind: against LEAPERS,
	# which are ballistic and go airborne, rifle troopers lost about a quarter of
	# their damage output and 4 hoppers vs 4 rifles moved from ~33% to ~55% ally
	# wins across two runs of six. Staleness barely touches a fight between things
	# that walk and badly hurts the one shooting at something that jumps.
	#
	# It costs one raycast per robot per 0.15 s, which is what it always cost:
	# LOS_CHECK_INTERVAL is a constant and was never LOD-scaled, so nothing is
	# given back here that the old code was saving. Everything genuinely expensive
	# — the vision scan and its three rays, target selection, repathing, the
	# combat rolls — stays sliced.
	_tick_los(delta)
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

	var before := global_position
	# Captured BEFORE the move: move_and_slide rewrites velocity, cancelling it
	# against whatever it hit, so afterwards there is no record of where the
	# robot was trying to go.
	var intent := Vector3(velocity.x, 0.0, velocity.z)
	_apply_give_way()
	move_and_slide()
	_damp_shoving(before)
	_step_over(before, intent)
	_tick_give_way(before, intent)

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
# TWO ROBOTS INSIDE ONE ANOTHER PUSH EACH OTHER OFF THE MAP.
#
# When a pair ends up interpenetrating, the solver separates them every tick
# and each one shoves the other, so the PAIR accelerates. Measured on Mutaha:
# get_last_motion() a full metre per frame — 52 m/s — with the body's own
# velocity at zero, running until the boundary wall stopped them or they fell
# out of the world and were counted as down. Survivors end up stranded off the
# navmesh, where every path they ask for is a whole-map search costing 40-120 ms
# a go (see Managers/AI/navmesh_islands.gd). It is also what a stuck robot
# "freaking out" on a barrier looks like from the outside.
#
# So while a body is in contact with another body, it may not be displaced
# HORIZONTALLY further than it could have walked. A tangle then unwinds at
# walking pace instead of launching. Height is left alone, so falling, leaping
# and being blown up all still behave.
# ─────────────────────────────────────────────

## How much of its own walking step a shoved robot may be moved in one frame.
const SHOVE_STEP_LIMIT := 1.5

## This chassis's own half-width, measured off its collision shape at spawn
## rather than authored. A hand-kept number drifts away from the shape it is
## supposed to describe, and the give-way rule below needs two robots to agree
## about which of them is the bigger without being able to confer.
var body_radius: float = 0.5

func _damp_shoving(before: Vector3) -> void:
	# Cleared FIRST. Both early returns below leave the frame without looking at
	# the slide collisions, and a stale contact would have the give-way rule
	# yielding to a robot this one stopped touching several frames ago.
	_touching = null
	# A leap IS a big horizontal step, and a crashing gunship is meant to fly
	# its wreck somewhere. Neither is a tangle.
	if movement_state == MovementState.LEAPING or _crashing:
		return
	var touching := false
	for i in get_slide_collision_count():
		var other = get_slide_collision(i).get_collider()
		if other is CharacterBody3D:
			touching = true
			# Remembered for the give-way rule below, which would otherwise have
			# to walk these same collisions a second time.
			_touching = other
			break
	if not touching:
		return
	var moved := global_position - before
	var flat := Vector2(moved.x, moved.z)
	var cap: float = maxf(move_speed, 1.0) * get_physics_process_delta_time() * SHOVE_STEP_LIMIT
	if flat.length() <= cap:
		return
	var kept := flat.normalized() * cap
	global_position = Vector3(before.x + kept.x, global_position.y, before.z + kept.y)


# ─────────────────────────────────────────────
# WALKING OVER A LIP.
#
# move_and_slide has no step-up. A slope up to floor_max_angle is walkable and
# anything steeper is a WALL, so a kerb, a doorway sill, a rock, the lip where
# two brushes meet — any vertical face at all, however low — stops a robot
# dead. From the outside it looks like the AI is broken, and it is why every
# level has had to have a ramp built onto everything.
#
# So when a move is blocked, try it again from `step_height` higher. If the way
# is clear up there AND there is ground to come down onto just beyond, the
# robot is lifted onto it. If it is still blocked up there it was a real wall,
# and if nothing is underneath it was a ledge over a drop — both are left
# alone. Three shape casts, and only on a frame where something got in the way.
# ─────────────────────────────────────────────

## The tallest lip a robot will walk up. Above this it is a wall and wants a
## ramp, or a Leaper.
@export var step_height: float = 0.45
## How far past the lip it has to be able to stand before the step is taken —
## stops a robot climbing onto something it would immediately fall off.
@export var step_forward: float = 0.35


func _step_over(before: Vector3, intent: Vector3) -> void:
	if step_height <= 0.0 or not is_on_floor():
		return
	if movement_state == MovementState.LEAPING or _crashing:
		return
	var wanted := intent * get_physics_process_delta_time()
	var want_len := wanted.length()
	if want_len < 0.02:
		return                      # not trying to go anywhere
	var got := global_position - before
	got.y = 0.0
	if got.length() > want_len * 0.5:
		return                      # it got most of the way; nothing in the way

	var dir := wanted / want_len
	var reach: float = maxf(want_len, step_forward)
	var lift := Vector3.UP * step_height
	var here := global_transform
	if test_move(here, lift):
		return                      # no headroom to lift over anything
	var raised := here.translated(lift)
	if test_move(raised, dir * reach):
		return                      # still blocked up there: a wall, not a lip
	var landing := raised.translated(dir * reach)
	var drop := Vector3.DOWN * (step_height + 0.05)
	var touchdown := KinematicCollision3D.new()
	if not test_move(landing, drop, touchdown):
		return                      # nothing to stand on: a ledge, not a step
	global_position = landing.origin + touchdown.get_travel()


# ─────────────────────────────────────────────
# LOS CACHE
# ─────────────────────────────────────────────


# ─────────────────────────────────────────────
# IN THE RIVER, AND NO PATH WILL EVER GET IT OUT.
#
# The navmesh stops at the bank on purpose — rivers exist to force the squad
# onto a crossing. So a robot that ends up in the water is standing on nothing
# walkable, and the nearest mesh point is the FLANK of a bridge or a bank it
# cannot climb. It walks at that wall, bumps, re-paths to the same wall, and
# does it until the mission ends. "Go round to the ramp" is not something a path
# query can suggest, because from where it stands there is no path at all.
#
# GATED ON BEING GENUINELY ADRIFT, NOT ON BEING STUCK. An earlier version of
# this hung off _check_stuck, which fires on "has not moved lately" — and a
# Mechanic standing over a casualty has not moved lately either, so it got
# rescued three metres away from the robot it was repairing and the repair
# failed. Distance from the navmesh is the honest test: a Mechanic beside a
# body is on walkable ground, metres inside the mesh. Four metres outside it,
# for four seconds, is a robot in the water.
#
# Cheap because it only runs for robots that are awake — the cull returns long
# before this — and asks the navigation server once a second, not once a frame.
## Whether being far from the navmesh is this chassis's normal state.
##
## FALSE for anything that walks, which is what _tick_adrift is for. TRUE for
## anything that flies: a Spotter Drone on station is permanently 11-26 m off
## the mesh because that is what flying is, and the recovery below was hauling
## it out of the sky onto the ground every four seconds. Six of the nine
## recoveries in one Causeway run were this, not a stranding.
func off_navmesh_is_normal() -> bool:
	return false


func _tick_adrift(delta: float) -> void:
	if not alive or downed or nav_agent == null:
		return
	if off_navmesh_is_normal():
		return   # it is supposed to be up there
	_adrift_poll -= delta
	if _adrift_poll > 0.0:
		return
	# THIS SNAP WENT ROUND THE BUDGET, AND IT WAS THE WORST FRAME IN THE GAME.
	#
	# map_get_closest_point walks EVERY polygon in the navigation map — 1.021 ms
	# a call on Three Rivers (see the note above _take_snap_query). The poll
	# resets to a flat second and _adrift_poll started at zero on every robot, so
	# the whole population asked on the same frame, once a second, and the snap
	# budget could not see it: bench_ai with 100 robots on Mutaha reported 50-65
	# ms frames at f31, f91, f151, f211, f271, f331 and f391 — every sixtieth
	# frame — against a 14.3 ms median, with the NAV budget reporting only 1.8 ms
	# of it because this is not a path resolution.
	#
	# Two fixes, the same pair the nav queries got: a stagger so the hundred
	# calls land on a hundred different frames (_stagger_ai_timers), and the
	# existing per-frame budget so no frame can be made expensive by them however
	# they happen to land.
	if not _take_snap_query(snap_queries_per_frame, int(snap_query_budget_ms * 1000.0)):
		# Counted rather than warned, like every other refusal of this budget:
		# nothing is lost and nothing is skipped. _adrift_poll is deliberately
		# NOT reset, so a refused robot asks again next frame instead of waiting
		# another whole second to find out it is standing in a river.
		_snap_refused += 1
		return
	# How long since this poll last ran, which is not a flat second any more:
	# the poll is staggered, can be refused for budget, and is called from the
	# think slice with the delta owed since the last one. _adrift_t is patience
	# measured in SECONDS (adrift_seconds, 4.0), so it has to be charged in
	# seconds — adding a flat 1.0 per poll made it count polls and called that
	# four seconds.
	var since: float = 1.0 - _adrift_poll
	_adrift_poll = 1.0
	var asked := Time.get_ticks_usec()
	var on: Vector3 = NavigationServer3D.map_get_closest_point(
		nav_agent.get_navigation_map(), global_position)
	_snap_spent_us += Time.get_ticks_usec() - asked
	if on == Vector3.ZERO:
		return   # no navmesh in this level at all; nothing to be adrift from
	var gap := Vector2(on.x - global_position.x, on.z - global_position.z).length()
	if gap < adrift_distance:
		_adrift_t = 0.0
		# WHERE IT WAS WHEN IT WAS STILL FINE. Kept every poll it is on the
		# mesh, and it is what the recovery below puts it back on. See the note
		# there: the nearest mesh point is the wrong answer on a causeway.
		_last_on_mesh = global_position
		_has_last_on_mesh = true
		return
	# DROWNED, rather than recovered. Checked BEFORE the teleport, or a robot in
	# deep water gets fished out and put on the far bank instead of dying.
	if _drown_check():
		return
	_adrift_t += since
	if _adrift_t < adrift_seconds:
		return
	_adrift_t = 0.0
	var was := global_position
	# ─────────────────────────────────────────────
	# PUT IT BACK WHERE IT FELL FROM, NOT WHERE THE MESH HAPPENS TO BE NEAREST.
	#
	# map_get_closest_point is geometry and knows nothing about where the robot
	# came from. A hostile that falls off the Causeway lands in the channel
	# roughly between the carriageway and the main island, so "nearest" is a
	# coin toss — and when it came up island, the recovery walked a dead squad
	# onto the shore BEHIND the player and they attacked from the rear. From the
	# outside that reads as deliberate AI flanking, which is the worst kind of
	# bug: it looks like a feature.
	#
	# The last on-mesh position is almost always the lip it fell from. Capped,
	# because a robot can be adrift for a long time and travel while adrift —
	# a stale point from the other end of the map would be a worse teleport than
	# the nearest one.
	# ─────────────────────────────────────────────
	var home: Vector3 = on
	if _has_last_on_mesh and global_position.distance_to(_last_on_mesh) <= adrift_return_limit:
		home = _last_on_mesh
	global_position = _Ground.stand(home, self, get_parent())
	velocity = Vector3.ZERO
	_stuck_last_position = global_position
	movement_state = MovementState.NONE
	# WARNED, because a robot teleporting is not normal and the interesting
	# question is how it got in the water. If this fires in the same place
	# repeatedly, that bank has a hole in it.
	push_warning("%s was %.1fm off the navmesh at %s — put back on it. Check how it got there." % [
		name, gap, was.round()])

# ─────────────────────────────────────────────
# DEEP WATER DROWNS.
#
# Before this, a robot that went in simply stood on the bottom: off the navmesh
# with nowhere to path to, alive, still a valid target. The squad stopped and
# stared at something they could neither reach nor finish, and an
# EliminateObjective waited on it for the rest of the mission. "It drowned" is
# a thing a player can read off the screen; "it is standing underwater forever"
# is not.
#
# The depth test is GeneratedTerrain.submersion_at, which is the same test
# water_navmesh.strip() uses to cut the bed out of the navmesh — so the water
# that has no paths through it is exactly the water that drowns you, by
# construction rather than by two numbers being kept in step by hand.
#
# Only on the adrift poll, so it costs a group lookup a second on robots that
# are ALREADY off the mesh — a robot walking around on dry land never reaches
# this function at all.
# ─────────────────────────────────────────────
func _drown_check() -> bool:
	if drown_depth <= 0.0 or not alive or downed:
		return false
	if off_navmesh_is_normal():
		return false   # it is flying over the water, not in it
	var deep: float = _GeneratedTerrain.submersion_in(get_tree(), global_position)
	if deep < drown_depth:
		return false
	# YOUR SIDE GOES DOWN, NOT AWAY. The squad is persistent and a soldier lost
	# to a shove off a bridge is a mission's worth of progress gone to physics.
	# Downed is recoverable with the repair tool and still costs you the body
	# for the fight, which is the right price. Hostiles are simply destroyed.
	if _is_player_side():
		enter_downed()
	else:
		die()
	push_warning("%s drowned in %.1fm of water at %s." % [name, deep, global_position.round()])
	return true


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
	# AND IT IS BEING WATCHED — BUT ONLY IF IT IS NOT ALREADY IN A FIGHT.
	#
	# This is the "first contact" case of the cost model: wake() is called from
	# apply_damage and from Squad._on_combat_triggered, so it covers being shot
	# and a squadmate calling contact, which are the two moments that most need a
	# prompt decision and the two the player is most certainly reading.
	#
	# THE GUARD IS THE WHOLE VALUE OF IT. Unguarded, "being shot" fires several
	# times a second for every robot in a firefight, so a brawl marked its entire
	# population watched and every one of them asked for a slice on every frame:
	# measured at 35 refused candidates a frame on the 100-robot bench, with the
	# cheap tier never actually applying to anybody. Being shot at while already
	# trading fire is not first contact, it is the chaotic middle — which is
	# exactly what the cheap tier is for. Same guard, same reasoning as the one in
	# trigger_combat().
	if not (ai_state == AIState.COMBAT and has_live_target()):
		mark_watched()
	# AND GIVE IT ITS TICK BACK, NOW. Setting the countdown is useless on a
	# frozen robot: the thing that reads it is the cull branch of
	# _physics_process, which is exactly what is switched off. Called from
	# apply_damage and from Squad._on_combat_triggered, both of which run
	# outside this robot's tick, so this is allowed to act immediately rather
	# than waiting for AIManager's round-robin to come round.
	thaw_from_cull()


## Walk in from wherever you were dropped without being frozen on the way:
## distance culling lets this one alone until it reaches the player, or until
## the time runs out. EnemyForceSpawner gives it to the reserves it sends in.
func exempt_from_culling(seconds: float = CULL_EXEMPT_SECONDS) -> void:
	never_culled = true
	_exempt_left = maxf(_exempt_left, seconds)
	# Same reasoning as wake(): the exemption is read inside the tick, so a
	# reinforcement handed one while frozen would never read it.
	thaw_from_cull()



## Is this robot's squad in a fight? A squad that is fighting stays awake, ALL
## of it, for as long as the fight lasts. Squad._on_combat_triggered already
## wakes every member when one of them makes contact, but that is a countdown
## (wake_on_damage_seconds) — so in a long fight the ones who had not personally
## been shot at went back to sleep mid-battle, and a flanking half of a squad
## froze while the other half was still trading fire. Being in a fight is a
## state, not an event, so it is asked as one.
##
## Overridden by Soldier, which is what carries a squad; a robot with no squad
## answers for itself.
func squad_is_engaged() -> bool:
	return false

func enter_passive_mode():
	if ai_state == AIState.PASSIVE:
		return
	# THE CALLER HAS ALREADY DECIDED. This used to refuse when always_active was
	# set, which every EnemySquadSpec in every mission sets — and the one call
	# site is the distance cull in _physics_process, which stopped honouring
	# that flag when it was found to keep seventy Foundry robots thinking from
	# across the valley. So the robot was culled but never MARKED culled, and
	# _apply_motion()'s cheap-out reads exactly this state: a hundred-odd
	# hostiles standing still 300 m away each paid for a full move_and_slide,
	# every frame, for the whole mission. Behaviour and state have to agree.
	if _is_player_side():
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


# ── FREEZING THE CALLBACK ─────────────────────
# See `cull_frozen` for the measurement and for the hazard.

## May this robot's `_physics_process` be switched off outright? Asked on the
## frame the cull puts it in PASSIVE, and deliberately conservative: everything
## below is something the tick is still doing for a culled robot, and freezing
## through it would strand the robot rather than rest it.
func _can_freeze_for_cull() -> bool:
	# NOTHING COULD WAKE IT. Waking is AIManager's job, and the lab, the test
	# rigs and a hand-placed robot in a bare scene run without one. 23 µs a
	# frame is a far better trade than a level that quietly stops fighting back.
	if ai_manager == null or not is_instance_valid(ai_manager):
		return false
	# ONLY A BODY THAT HAS ALREADY STOPPED. This is the same test _apply_motion
	# cheaps out on, asked deliberately: where the cheap-out fires, the tick was
	# not moving the robot anyway, so freezing changes nothing about its motion.
	# A body still falling or still sliding has move_and_slide and
	# handle_gravity to finish — freeze it and it hangs in the air where the
	# cull caught it, and the fell-out-of-the-world check in handle_gravity
	# never fires either. On Qamareen all 176 culled robots are settled, so
	# this costs nothing in practice.
	if not is_on_floor() or velocity.length_squared() >= 0.01:
		return false
	# A JAMMED ROBOT HAS TO KEEP RECOVERING. _tick_signal runs ABOVE the cull
	# precisely so that walking away from an EMP'd robot does not leave it
	# latched in EKILL forever — see the gate in _physics_process. Freezing the
	# callback would brick it by the same route through a different door.
	if signal_integrity < 1.0 or _signal_locked_t > 0.0 or _ekill_latched:
		return false
	return true


## Switch the tick off and hand this robot to AIManager, which is the only
## thing that can give it back. Called from the cull branch, so physics is
## running by definition; the current invocation of _physics_process finishes
## normally, which is what lets the subclass tails below `super(delta)`
## (enemy_nest's flames, mechanic's _stop_welding, reclaimer's _drop_wreck) run
## their passive cleanup one last time before the tick stops.
func _freeze_for_cull() -> void:
	cull_frozen = true
	set_physics_process(false)
	ai_manager.watch_frozen(self)


## Give the tick back. Safe to call on a robot that was never frozen.
func thaw_from_cull() -> void:
	if not cull_frozen:
		return
	cull_frozen = false
	# NEVER ON A WRECK. destroy() and the end of the settle switch the tick off
	# on purpose; a thaw arriving afterwards — a stray stimulus, AIManager's
	# poll one frame late — would restart a dead robot's brain.
	if not alive or downed or ai_state == AIState.DEAD:
		return
	set_physics_process(true)
	# exit_passive_mode is left to the robot's own next tick, where the cull
	# branch owns that transition. Doing it here as well would mean two places
	# deciding when a robot stops being passive.


## Has this robot got a reason to be awake again? Asked from OUTSIDE, by
## AIManager._poll_frozen, because a frozen robot cannot ask it of itself.
##
## This is the cull predicate in _physics_process read the other way round, and
## it has to STAY that way: a wake reason the cull honours but this does not is
## a robot that sleeps through the rest of the mission. `dist_sq` is passed in
## because the manager already has the per-frame activation positions cached.
func cull_wake_wanted(dist_sq: float) -> bool:
	if _is_player_side() or never_culled or _woken_t > 0.0 or squad_is_engaged():
		return true
	var cull_sq: float = activation_distance_sq
	if on_patrol:
		cull_sq = maxf(cull_sq, patrol_activation_distance_sq)
	return dist_sq <= cull_sq


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
			# AND NOT WHILE AN ORDER IS IN FLIGHT. _seek_los_position walks to a
			# ring around the TARGET — back towards the fight — which outvoted
			# the move order that had just arrived: order a rover away from a
			# contact, it loses sight on the way, sits out NO_LOS_PATIENCE, then
			# re-routes itself to somewhere it can shoot from.
			#
			# _moving_under_orders(), NOT squad_directed. The blunt version
			# stranded enemy garrisons: _tick_defend skips any member already in
			# COMBAT, so a robot holding a target it cannot see gets no order
			# from its squad — and with a blanket guard it could not reposition
			# itself either, leaving it stood in the open doing nothing. This
			# only suppresses the override while the robot is actually
			# executing a move; a stationary one still works for its shot.
			if combat_target != null and combat_target.alive and not _moving_under_orders():
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
			# WARNED ONCE, THEN COUNTED. push_warning captures a stack trace, which
			# is nothing once and ruinous when a whole wave spawns over a hole and
			# falls out together — twenty-eight in one frame measured 450ms, and a
			# 450ms frame is indistinguishable from a hang. The information is kept
			# (the first one names a position to go and look at, and the tally says
			# how bad it is); only the per-robot stack trace goes.
			_fell_out_count += 1
			if not _fell_out_warned:
				_fell_out_warned = true
				push_warning("%s fell out of the world at %s; counting it as down. Further fall-outs this run are counted in Enemy._fell_out_count rather than logged." % [name, global_position])
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
	# A BODY IN THE WAY IS NOT A BLOCKED PATH. Give-way is already working on it
	# and costs nothing; re-pathing on top would buy a navigation query and send
	# the robot back through the robot, because the navmesh cannot see it. Once
	# give-way has run out of sidesteps it stops claiming the tangle and this
	# takes over.
	if _touching != null and _give_way_tries > 0 and _give_way_tries < GIVE_WAY_MAX_TRIES:
		return
	# Still here — hand off to path blocked handler
	velocity.x = 0
	velocity.z = 0
	_handle_path_blocked()

func move_to(pos: Vector3, think_delay: float = 0.0):
	# Pinned. Remember where we were told to go and replay it on release.
	if is_held():
		_pending_move = pos
		_has_pending_move = true
		return
	# CULLED. The same bargain as being held, for the same reason: a squad goes
	# on giving orders to robots the distance cull has switched off — DEFEND
	# re-posts its line, ADVANCE re-slots it — and every one of those calls used
	# to buy a nav query for a robot nobody can see. Remember where it was sent;
	# exit_passive_mode() replays movement_target the moment the player is close
	# enough for any of it to matter.
	if ai_state == AIState.PASSIVE:
		movement_target = pos
		return
	nav_agent.set_target_position(pos)
	# WHOSE TURN IT IS TO ASK.
	#
	# A new destination refreshes the cached direction now — except when the
	# caller is ordering a whole squad at once. Every member setting this to
	# zero queued a path resolution for the same frame: profiled at 323 ms
	# across 21 `_tick_nav` calls in ONE frame on Coast Road, which is what an
	# ADVANCE order felt like out there. `think_delay` deals the squad's
	# requests out over the next few frames instead (Squad.order_stagger_seconds).
	#
	# It keeps whatever direction it already had while it waits — a fraction of
	# a second of the old heading. Pointing it straight at the destination
	# instead was worse than the stall it was meant to cover: on broken ground
	# the blind bearing walked robots into walls, stuck recovery re-pathed them,
	# and one order turned into two seconds of solid pathfinding.
	_nav_think_timer = maxf(0.0, think_delay)
	# NO WATCHED MARK HERE, AND IT WAS TRIED. "A fresh order is a watched moment"
	# is right, and this is the wrong place to say it: move_to is not where orders
	# arrive, it is where EVERY movement in the game ends up. The robot's own
	# decisions come through here too — roll_combat_action's advance and fallback,
	# _handle_path_blocked, _seek_los_position, the search roam, the wander — so
	# marking it meant a robot that had just decided to move was granted full rate
	# for 0.75 s, inside which it decided to move again. Measured: 60 of 100 robots
	# permanently watched, the think budget pinned to its floor, 24,013 slices
	# refused in 400 frames and no change to the frame time at all — the model
	# turned itself off and left the backstop holding it.
	#
	# A real order comes from outside, so it is marked from outside:
	# Squad.set_objective calls mark_watched() on its members, and wake() covers
	# being shot at and a squadmate calling contact.
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
## ...and the milliseconds of NavigationServer time they may take between them.
## A count is no budget when one query can cost 90 ms: eight of those made a
## 240 ms frame at the end of a Coast Road run, where a path can cross 1.3 km
## of map. The first query of a frame always runs, so nothing ever stops
## getting one; the rest steer on their cached direction and ask again next
## frame, which is what the interval above already assumes.
@export var nav_query_budget_ms: float = 6.0

## Robots that have fallen out of the world this run. See handle_gravity.
static var _fell_out_count: int = 0
static var _fell_out_warned: bool = false

static var _nav_budget: int = 0
static var _nav_budget_frame: int = -1
static var _nav_spent_us: int = 0

## Microseconds and ray count spent in is_path_clear — every sight question the
## AI asks: can I see it, can I shoot it from that cover point, who shot me.
## Cumulative, read by tools/bench_ai.gd, same purpose as _nav_spent_us. Added
## because 5.25 ms of combat cost was not nav and not think, and nothing in the
## game could say what it was. See the note by AIWeapon._shot_spent_us.
static var _sight_spent_us: int = 0
static var _sight_rays: int = 0

var _nav_dir: Vector3 = Vector3.ZERO
var _nav_think_timer: float = 0.0
var _nav_finished: bool = false

# ─────────────────────────────────────────────
# WALKING THE PATH, EVERY FRAME, FOR NOTHING.
#
# _tick_nav is throttled — nav_think_interval times lod_scale(), which past
# lod_far_distance is 0.15 * 4 = 0.6 s. It used to cache a DIRECTION, and
# move_along_nav then drove at full speed along that vector for the whole
# interval. A direction is only true at the position it was computed from: a
# 12 m/s chaser travels 7.2 m on it, toward a path corner it passed six metres
# back, and the next query points it the way it came. Measured on Georgetown:
# 0.5 m of progress in five seconds at an average speed of 9.6 m/s. It was
# sprinting in a circle, and every chassis above 5 m/s does it.
#
# The fix is that the PATH is cheap even though resolving it is not.
# get_current_navigation_path() hands back the array the agent already holds
# without re-resolving anything — measured at 0.6 us a call against 135 us for
# a resolve. So the robot reads its own path every frame and steers at the leg
# it is on, which stays correct however far it has travelled, while the
# expensive resolve stays exactly as throttled as it was. Smoothness is no
# longer tied to query rate.
#
# Path points are navmesh corners, not a fixed grid: 17 points across 167 m on
# Georgetown, so legs run about ten metres and the robot walks long straight
# runs between them.
# ─────────────────────────────────────────────

## How close, flat, counts as having reached a corner. Small, because the point
## is to round the corner rather than to stop on it.
const NAV_LEG_REACHED := 0.75
## Which leg of the current path the robot is walking.
var _nav_leg: int = 0
## What the path looked like last frame, so a re-resolve restarts the walk.
## Size alone does not catch it — a new path can have the same corner count —
## so the endpoint is compared too.
var _nav_path_size: int = 0
var _nav_path_end: Vector3 = Vector3.ZERO
## The agent's path_height_offset as initialize() set it; _tick_nav levels it
## with a point underfoot for one query at a time and puts this back.
var _path_height_base: float = 0.0
## A path point this close, flat, is the one the robot is standing on.
const NAV_UNDERFOOT := 0.35


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
	if not _take_nav_query(nav_queries_per_frame, int(nav_query_budget_ms * 1000.0)):
		return
	_nav_think_timer = nav_think_interval * lod_scale()
	var asked := Time.get_ticks_usec()
	_nav_finished = nav_agent.is_navigation_finished()
	var next: Vector3 = nav_agent.get_next_path_position()
	_nav_spent_us += Time.get_ticks_usec() - asked
	var fresh: Vector3 = next - global_position
	fresh.y = 0
	# A POINT UNDERFOOT THAT NEVER COUNTS AS REACHED. The agent judges path
	# points in 3D from the origin, and where the navmesh sits a metre off the
	# real ground — or the path starts on the body's own origin, which the
	# offset above lifts exactly path_desired_distance clear — the point the
	# robot stands on stays ahead of it forever. It steered at nothing and
	# stopped dead with a whole path in hand: three of four robots on
	# Pittsburgh's staging ground. Level the offset with that point (the
	# returned position already has the offset taken off) so the next query
	# lets go of it; the base goes back once there is somewhere to walk to.
	if not _nav_finished and fresh.length() < NAV_UNDERFOOT:
		nav_agent.path_height_offset += next.y - global_position.y
		_nav_think_timer = 0.0   # ask again next frame: that query moves the path on
	elif nav_agent.path_height_offset != _path_height_base:
		nav_agent.path_height_offset = _path_height_base
	_nav_dir = fresh


static func _take_nav_query(budget: int, spend_us: int) -> bool:
	var frame := Engine.get_physics_frames()
	var first := frame != _nav_budget_frame
	if first:
		_nav_budget_frame = frame
		_nav_budget = maxi(1, budget)
		_nav_spent_us = 0
	if _nav_budget <= 0:
		return false   # this frame has had its share of resolutions
	if _nav_spent_us >= spend_us and not first:
		return false   # and its share of the time they took
	_nav_budget -= 1
	return true



# ─────────────────────────────────────────────
# SNAPPING A POINT ONTO THE NAVMESH IS NOT FREE.
#
# NavigationServer3D.map_get_closest_point walks EVERY polygon in the navigation
# map. Measured on Three Rivers: 1.021 ms a call. One call.
#
# find_advance_target used to spend THREE of them per decision — snap each
# candidate step, then test whether it had line of sight — which is the 3.09 ms
# the in-editor profiler showed, against a 16 ms frame. Sixteen robots walking
# out of a reserve spawn all advanced on the same frame and that one function
# ate 50 ms of it. find_reposition_target and find_fallback_target had the same
# shape at two queries each.
#
# It was invisible to the existing nav budget, which only counts path
# resolutions, and invisible to bench_ai_calls.gd, which reports
# find_advance_target at 0.002 ms because its robots are already inside
# engage_standoff and take the early return above the loop. Both numbers were
# true of different branches.
#
# Two things fix it, and the first is most of it:
#
#   * TEST FIRST, SNAP THE WINNER. The raw candidate is a short step along the
#     ground from a robot that is already standing on the navmesh, so it is as
#     good a place to test sight FROM as the snapped one. The snap exists to make
#     the destination walkable, not to make the test honest. N queries become 1.
#   * A FRAME BUDGET, like path resolutions already answer to, but its own: a
#     snap is a convenience and a path is not, so they must not be able to starve
#     each other. Over budget, hand back the raw point — NavigationAgent3D
#     resolves an off-mesh target itself when it paths to it, so the robot still
#     goes somewhere sensible instead of standing still.
# ─────────────────────────────────────────────

## Snaps allowed across ALL robots in one physics frame...
@export var snap_queries_per_frame: int = 6
## ...and the milliseconds they may take between them.
@export var snap_query_budget_ms: float = 3.0

static var _snap_budget: int = 0
static var _snap_budget_frame: int = -1
static var _snap_spent_us: int = 0
## Snaps refused for budget this run. Counted rather than warned: this is a
## designed fallback on a hot path, not a fault.
static var _snap_refused: int = 0


static func _take_snap_query(budget: int, spend_us: int) -> bool:
	var frame := Engine.get_physics_frames()
	var first := frame != _snap_budget_frame
	if first:
		_snap_budget_frame = frame
		_snap_budget = maxi(1, budget)
		_snap_spent_us = 0
	if _snap_budget <= 0:
		return false
	if _snap_spent_us >= spend_us and not first:
		return false
	_snap_budget -= 1
	return true




## THE SAME BUDGET, FOR CALLERS THAT ARE NOT AN Enemy.
##
## The budget above was private to this class, so every other snap on the map
## went round it: Squad._on_ground, the Reclaimer's drive-up point, the
## Mechanic's stand-beside point. Those are the ones a crowd pays — a squad
## re-measuring a formation slot is once per robot — and between them they could
## spend a frame's worth of navigation the budget never saw.
##
## Returns `p` unchanged when the frame is spent, which is the same designed
## fallback _snap_to_nav uses: NavigationAgent3D resolves an off-mesh target
## itself when it paths to it, so the caller still gets somewhere sensible.
static func snap_on_map(map: RID, p: Vector3, budget: int = 6, spend_ms: float = 3.0) -> Vector3:
	if not map.is_valid():
		return p
	if not _take_snap_query(budget, int(spend_ms * 1000.0)):
		_snap_refused += 1
		return p
	var asked := Time.get_ticks_usec()
	var out: Vector3 = NavigationServer3D.map_get_closest_point(map, p)
	_snap_spent_us += Time.get_ticks_usec() - asked
	return p if out == Vector3.ZERO else out

## `p` placed on the navmesh, or `p` unchanged when this frame has spent its
## share. See the note above for why giving back the raw point is safe.
func _snap_to_nav(p: Vector3) -> Vector3:
	if nav_agent == null:
		return p
	if not _take_snap_query(snap_queries_per_frame, int(snap_query_budget_ms * 1000.0)):
		_snap_refused += 1
		return p
	var asked := Time.get_ticks_usec()
	var out: Vector3 = NavigationServer3D.map_get_closest_point(nav_agent.get_navigation_map(), p)
	_snap_spent_us += Time.get_ticks_usec() - asked
	return out


## The first candidate with line of sight to `target`, placed on the navmesh —
## or where we already are, when none of them has it.
##
## ONE snap, on the winner. See the note above.
func _first_clear_step(candidates: Array, target: Node3D) -> Vector3:
	if target == null or not is_instance_valid(target):
		return global_position
	for p in candidates:
		if is_path_clear(p + Vector3.UP * 0.8, target.global_position, target):
			return _snap_to_nav(p)
	return global_position

## Which way to steer RIGHT NOW, read off the path the agent already holds. See
## the note by NAV_LEG_REACHED: this is what makes throttled thinking and smooth
## walking compatible.
##
## Returns ZERO when there is no path worth walking, and the caller falls back
## to the cached _nav_dir so arrival and the underfoot case behave as before.
func _path_steer_dir() -> Vector3:
	if nav_agent == null or _nav_finished:
		return Vector3.ZERO
	var path: PackedVector3Array = nav_agent.get_current_navigation_path()
	if path.size() < 2:
		return Vector3.ZERO   # nothing resolved yet, or a single-point path
	# A RE-RESOLVE MEANS WALK IT AGAIN FROM THE FRONT. This is also the safety
	# net for a robot shoved off its route: the agent re-resolves once it drifts
	# past path_max_distance, which arrives here as a new path and resets the leg.
	var last: Vector3 = path[path.size() - 1]
	if path.size() != _nav_path_size or last != _nav_path_end:
		_nav_path_size = path.size()
		_nav_path_end = last
		_nav_leg = 1   # 0 is where the path started, which is behind us
	_nav_leg = clampi(_nav_leg, 1, path.size() - 1)
	# Walk past every corner already rounded. FLAT distance: the navmesh sits at
	# a different height than the robot's origin, and a 3D measure leaves a
	# point underfoot permanently unreached — the same trap as NAV_UNDERFOOT.
	while _nav_leg < path.size() - 1:
		var leg: Vector3 = path[_nav_leg] - global_position
		leg.y = 0.0
		if leg.length() > NAV_LEG_REACHED:
			break
		_nav_leg += 1
	var steer: Vector3 = path[_nav_leg] - global_position
	steer.y = 0.0
	return steer


func move_along_nav(delta):
	# Steering reads the cached PATH every frame; only resolving it is throttled,
	# in _tick_nav. _nav_dir is the fallback for when there is no path to walk.
	var path_dir = _path_steer_dir()
	if path_dir == Vector3.ZERO:
		path_dir = _nav_dir
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
	# MARCHING SOMEWHERE LOOKS WHERE IT IS GOING — UNLESS IT CAN STILL SHOOT.
	#
	# The combat branch below tracks the target whatever the legs are doing, and
	# the note above _update_facing calls that deliberate: it is what gives
	# strafing and backpedalling for free. Within weapon range that is a
	# fighting withdrawal and it is exactly right — the robot gives ground with
	# its gun still on the thing it is backing away from.
	#
	# Past that range it is just blindness. Ordered off a contact it can no
	# longer reach, a rover kept its body square to the enemy and reversed the
	# whole way, sensors and gun pointed behind it, and answered nothing in
	# front of it until something shot it.
	#
	# Two tests, both needed. The order has to be taking it AWAY — destination
	# further from the target than it is standing — so a step sideways or a push
	# in still faces the threat. And the target has to be out of its own
	# weapon's reach, so the withdrawal stays a fighting one for as long as it
	# can actually fight.
	if _moving_under_orders() and combat_target != null and is_instance_valid(combat_target) \
			and movement_target != Vector3.ZERO:
		var here := global_position.distance_to(combat_target.global_position)
		var sent := movement_target.distance_to(combat_target.global_position)
		if sent > here + 1.0 and here > _max_range():
			face_dir = movement_target - global_position
			face_dir.y = 0.0
			if face_dir.length_squared() > 0.0001:
				return face_dir.normalized()
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
	# Ticked before the main gun's early returns, so the coax keeps working
	# while the main is reloading or out of its own range band. That is the
	# whole point of carrying one.
	_tick_coax(delta)
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
	# A TURRET IS NOT SPOILED BY THE HULL MOVING.
	#
	# _aim_tracking is the settle timer the MAIN gun waits on before it will
	# fire, and it DECAYS while the robot is moving. For infantry that is right:
	# the whole body is the gun mount, so walking ruins the shot. For a turreted
	# frame it is wrong — the gun is on its own bearing and the hull underneath
	# it is irrelevant.
	#
	# What it cost: a Walker on the move never settled, so the autocannon never
	# left WeaponState.AIM and only the coax fired — the coax has no settle gate
	# at all, it shoots the moment the bearing is good. Worse, _prefire_threshold
	# scales with RANGE (aim_settle_time * dist/max_range * 0.8), so the one time
	# a moving Walker did fire its main gun was at something almost on top of it,
	# where the threshold is near zero. Reported as exactly that: "fires once,
	# and only when the turret is pointing at something very close."
	#
	# `turret` is declared on the frames that have one (Walker, Rover), so this
	# asks the object rather than naming classes.
	var hull_spoils_aim: bool = _is_moving() and not ("turret" in self and get("turret") != null)
	if _has_los and combat_target != null:
		if hull_spoils_aim:
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
			if _aimed_body() == null:
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

# ─────────────────────────────────────────────
# THE COAX
# ─────────────────────────────────────────────
# It makes no decisions. It rides the main gun's bearing and fires whenever that
# bearing is good and the target is inside ITS OWN band — which may be shorter
# or longer than the main gun's. Fit a short coax and it only answers what gets
# close; fit the Ancient MG (99 m) and it fires at essentially everything the
# main gun engages, which is a lot of output for one supply slot. That is a
# balance question for the fit, not a rule for the code.
#
# Every gate here is a condition of the MAIN engagement (are we fighting, can
# we see it, is the turret on it) except the range check and its own reload,
# which are the coax's own business.
func _tick_coax(delta: float) -> void:
	if _coax_time > 0.0:
		_coax_time -= delta
	if coax == null:
		return
	if ai_state != AIState.COMBAT or combat_target == null:
		return
	if coax.is_reloading:
		return
	if coax.needs_reload():
		coax.start_reload()
		return
	if not _has_los and not _can_fire_without_los():
		return
	# Its own band, not the main gun's. A coax is short-ranged on purpose: past
	# its falloff it is throwing rounds away.
	var dist := global_position.distance_to(weapon_target)
	if dist > coax.max_effective_range or dist < coax.min_effective_range:
		return
	# The main gun's bearing IS the coax's bearing — they are on one mount. If
	# the turret is still slewing, neither of them is on target.
	if not _weapon_on_target():
		return
	if _coax_time > 0.0:
		return
	if _clear_line_of_fire():
		return   # a squadmate is in the way; the main gun checks the same thing
	coax.fire(get_inaccurate_target(weapon_target))
	_coax_time = coax.fire_cooldown


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



# ─────────────────────────────────────────────
# WEDGED IS NOT BLOCKED, AND RE-PATHING WILL NEVER FIX IT.
#
# _handle_path_blocked answers a stuck robot with navigation: step left, step
# right, then stand and fight. That is the right answer when something is IN THE
# WAY — but not when the capsule itself is jammed in the geometry, because then
# the body cannot move whatever the path says. The agent points somewhere, the
# body pushes, collision refuses, and three retries later it stands there for
# the rest of the mission. Reported as soldiers squeezing into terrain and never
# coming out.
#
# So the third retry tries a PHYSICAL escape before it gives up. Every candidate
# is proved free with test_move first, so this can never place a robot inside
# something — it is the same technique _step_over already uses to clear a lip,
# aimed at a different problem.
#
# Ordered by preference: towards the navmesh (somewhere it is known to be able
# to stand), then the compass. Lifted slightly on the way, because most wedges
# are a foot caught under a lip rather than a body in a wall.
func _handle_path_blocked() -> void:
	_stuck_retry_count += 1

	var nav_map = nav_agent.get_navigation_map()

	if _stuck_retry_count == 1:
		# First block — try a lateral step to get around whatever is blocking
		var to_target = (movement_target - global_position).normalized()
		var right = to_target.cross(Vector3.UP).normalized()
		var lateral_dir = right if randf() > 0.5 else -right
		var step = global_position + lateral_dir * 3.0 + to_target * 1.5
		var nav_point = _snap_to_nav(step)
		nav_agent.set_target_position(nav_point)
		_nav_think_timer = 0.0  # new destination: refresh the cached direction now
		return

	if _stuck_retry_count == 2:
		# Second block — try the opposite lateral direction
		var to_target = (movement_target - global_position).normalized()
		var right = to_target.cross(Vector3.UP).normalized()
		var lateral_dir = -right if randf() > 0.5 else right
		var step = global_position + lateral_dir * 4.0
		var nav_point = _snap_to_nav(step)
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
		var fallback = _snap_to_nav(global_position + random_offset)
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
		var nav_point = _snap_to_nav(test)
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
		# Scored rather than purely nearest. Falls back to nearest on its own
		# when distribution is switched off, so this is the only call site that
		# ever needed changing.
		return ai_manager.get_best_hostile(self)
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

	# ALREADY FIGHTING SOMETHING IN YOUR FACE.
	#
	# This check exists to catch a hostile walking up while you shoot at
	# something further off. If the thing you are already on is itself inside
	# close_threat_range there is nothing here to find — and the scan below is
	# the single most expensive thing reconsider_target() does, run on every
	# re-decision by every robot in the fight.
	if combat_target != null and is_instance_valid(combat_target) and combat_target.alive \
			and global_position.distance_to(combat_target.global_position) <= close_threat_range:
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
	# A SQUAD MEMBER SEARCHES FROM WHERE IT IS STANDING.
	#
	# This move_to was the one place in the search cycle that moved a
	# squad-directed robot on its own authority. _tick_search refuses to roam
	# one, _end_search hands it back to the squad, reconsider_patrol refuses to
	# re-route one — and then this, which fires FIRST, drove it to the last
	# place it saw the target.
	#
	# What that looked like: order a rover away from a fight, it starts moving,
	# loses sight of what it was shooting at a few metres later, reconsider_
	# target() finds nothing, and this sends it straight back to the spot it was
	# engaging from. Re-issuing the order just restarts the loop, which is why
	# spamming move and follow did not help — the squad and the robot were
	# fighting over the same destination, and the robot got the last word.
	#
	# IT DOES NOT TURN TO WATCH IT EITHER. An earlier pass left look_target on
	# the last contact here, reasoning that knowing where it came from was the
	# useful half. It is not: the facing rules fall through to look_target once
	# COMBAT ends, so that pinned a squad member's body to a spot behind it and
	# it marched away backwards. The squad decides where its members look as
	# well as where they stand.
	if squad_directed:
		return
	look_target = last_seen_point.back()
	move_to(last_seen_point.back())

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
		move_to(_snap_to_nav(global_position + offset))

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
	var pt = _snap_to_nav(global_position + Vector3(cos(a), 0.0, sin(a)) * r)
	move_to(pt)
	look_target = pt


# ─────────────────────────────────────────────
# EQUIPMENT
# ─────────────────────────────────────────────
func _tick_equipment(delta: float) -> void:
	# Counted here rather than in _physics_process so the hot path gains
	# nothing. This tick is handed the delta OWED since the last one, so the
	# total is right even when thinking is sliced.
	if _since_hit < AIEquipment.NEVER_HIT:
		_since_hit = minf(_since_hit + delta, AIEquipment.NEVER_HIT)
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

## NO COMBAT TARGET IS NOT A REASON TO SKIP THIS.
##
## It used to return here unless the robot already had something to shoot, which
## is the one condition a grenade wants and the exact opposite of what the rest
## of the kit is for — smoke exists to stop a firefight, a mine is laid before
## one. AIGrenade.can_use() makes the same check itself, first line, so nothing
## that worked before behaves differently now; what changes is that equipment
## which does NOT need a target finally gets asked.
func _evaluate_equipment_use() -> void:
	# RESOLVED ONCE, AND VALIDATED. The assignment below is unconditional, and
	# EquipmentContext.combat_target is typed — so handing it a freed node is
	# not a null that something downstream copes with, it is an immediate
	# "Invalid assignment ... previously freed" and the game is gone.
	#
	# _drop_freed_references() at the top of the tick should mean this never
	# sees one. This is the belt to that braces, because the cost of being
	# wrong here is a crash rather than a wrong decision, and the robot that
	# proved it — a Diver, which frees itself outright instead of leaving a
	# wreck — can die between the guard and this line.
	var target = combat_target if combat_target != null and is_instance_valid(combat_target) \
			else null
	var context = AIEquipment.EquipmentContext.new()
	context.owner_ai = self
	context.combat_target = target
	# Where the fight is, when there is one. Our own feet otherwise, so an
	# equipment that places something on the ground has somewhere to start.
	context.target_position = target.global_position if target != null \
		else global_position
	context.time_since_target_moved = _target_stationary_time
	context.owner_is_reloading = weapon != null and weapon.is_reloading
	context.under_fire_seconds = _since_hit
	context.squad_objective = _squad_objective()
	context.downed_friendly = _nearest_downed_friendly()
	# One lookup, three answers. The bearing says "something is out there", the
	# point says how far, the body is what a sight test has to exclude — the
	# grenade only ever needed the first.
	var threat: Node3D = _threat_actor()
	context.threat_actor = threat
	context.threat_position = threat.global_position if threat != null else Vector3.ZERO
	context.threat_bearing = _bearing_to(context.threat_position) if threat != null \
		else Vector3.ZERO
	context.squad_last_equipment_ms = _squad_last_equipment_ms()
	context.nearby_hostiles = []
	context.hostiles_near_target = []
	if ai_manager != null:
		context.nearby_hostiles = ai_manager.get_hostiles_in_radius(self, 5.0)
		context.hostiles_near_target = _hostiles_around(context.target_position,
			EQUIPMENT_CLUSTER_RADIUS)
	for i in equipment_slots.size():
		var slot: AIEquipmentSlot = equipment_slots[i]
		if not _equipment_slot_ready(i):
			continue
		var equipment = slot.equipment_scene.instantiate() as AIEquipment
		if equipment == null:
			continue
		if equipment.can_use(context):
			_spend_equipment(i, equipment, context)
			return
		else:
			equipment.free()


## Has this slot anything left, and has it cooled down? Shared by the
## autonomous path and the ordered one so a slot cannot be spendable to the
## player and not to the robot, or the reverse.
func _equipment_slot_ready(index: int) -> bool:
	if index < 0 or index >= equipment_slots.size():
		return false
	var slot: AIEquipmentSlot = equipment_slots[index]
	if slot == null or slot.equipment_scene == null:
		return false
	if not slot.has_uses():
		return false
	return _equipment_cooldowns.get(index, 0.0) <= 0.0


## Actually spend it. Takes an already-instantiated equipment because both
## callers have had to build one to ask it a question first — the autonomous
## path asks `can_use`, the ordered path asks `ordered_at_point`.
##
## ONE PLACE, because the accounting is the easy thing to get half right: the
## slot has to be consumed, the cooldown set, AND the timestamp recorded, or the
## squad spends the same canister twice, or four of them answer one order
## because nobody logged that the first one went.
func _spend_equipment(index: int, equipment: AIEquipment,
		context: AIEquipment.EquipmentContext) -> void:
	var slot: AIEquipmentSlot = equipment_slots[index]
	# The running scene when there is one; the level this robot is in when the
	# tree was started by a script (the tests, a lab run from the command line),
	# which has none — the grenade was never thrown.
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	host.add_child(equipment)
	equipment.execute(context)
	slot.consume()
	# Recorded for the squad HUD. Equipment use is instantaneous — instantiate,
	# execute, free — so there is no "currently using" state to read anywhere; a
	# timestamp is the only way the readout can say what a squadmate just did.
	_last_equipment_ms = Time.get_ticks_msec()
	_last_equipment_label = slot.label if slot.label != "" else "EQUIPMENT"
	_equipment_cooldowns[index] = equipment.cooldown
	if equipment.is_inside_tree():
		equipment.queue_free()


# ─────────────────────────────────────────────
# ORDERED EQUIPMENT — the player pointed, this robot answers
# ─────────────────────────────────────────────

## Which slot holds `item_id`, or -1. Used by the designator to turn "throw
## smoke" into "spend slot 1 on this robot".
func equipment_slot_for(item_id: StringName) -> int:
	for i in equipment_slots.size():
		var slot: AIEquipmentSlot = equipment_slots[i]
		if slot != null and slot.item_id == item_id:
			return i
	return -1


## Can this robot answer an order for `item_id` right now? Separate from
## `order_use_equipment` so the designator can count holders and grey its
## readout without spending anything to find out.
func can_answer_equipment_order(item_id: StringName) -> bool:
	if not alive or downed:
		return false
	return _equipment_slot_ready(equipment_slot_for(item_id))


## THE PLAYER HAS DECIDED. Spend `item_id` at `at`.
##
## `can_use()` IS NOT CONSULTED, and that is the whole difference between this
## and the autonomous path. can_use answers "is this a good idea", which is a
## judgement the player has just overridden by pointing at something. What still
## applies is everything the player cannot see: the slot has to have a use left
## and be off cooldown (`_equipment_slot_ready`), and the throw has to be
## physically possible, which `execute()` checks for itself and warns about.
##
## Returns why it refused, or "" on success — a verb that does nothing is worse
## than one that says no, and the only place that knows the reason is here.
func order_use_equipment(item_id: StringName, at: Vector3, use_point: bool) -> String:
	if not alive or downed:
		return "down"
	var index := equipment_slot_for(item_id)
	if index < 0:
		return "not carried"
	if not _equipment_slot_ready(index):
		var slot: AIEquipmentSlot = equipment_slots[index]
		return "none left" if (slot != null and not slot.has_uses()) else "reloading"
	var equipment = equipment_slots[index].equipment_scene.instantiate() as AIEquipment
	if equipment == null:
		push_warning("%s: equipment slot %d has a scene that is not an AIEquipment." % [name, index])
		return "broken"
	# OUT OF RANGE IS THE REFUSAL THE PLAYER WILL HIT MOST. A robot sixty metres
	# from the mark cannot throw to it, and silently doing nothing would read as
	# the designator being broken.
	if use_point and equipment.ordered_at_point:
		var reach: float = global_position.distance_to(at)
		if reach > ORDERED_THROW_RANGE:
			equipment.free()
			return "too far"
	var context := _ordered_context(at, use_point and equipment.ordered_at_point)
	_spend_equipment(index, equipment, context)
	return ""


## A context for an ordered use. The situational fields are still filled in —
## an ordered smoke should know where the threat is so it can aim its own
## fallbacks — but `ordered_position` overrides the placement every equipment
## would have chosen.
func _ordered_context(at: Vector3, use_point: bool) -> AIEquipment.EquipmentContext:
	var context := AIEquipment.EquipmentContext.new()
	context.owner_ai = self
	context.combat_target = combat_target
	context.target_position = at
	context.time_since_target_moved = _target_stationary_time
	context.owner_is_reloading = weapon != null and weapon.is_reloading
	context.under_fire_seconds = _since_hit
	context.squad_objective = _squad_objective()
	context.downed_friendly = _nearest_downed_friendly()
	var threat: Node3D = _threat_actor()
	context.threat_actor = threat
	context.threat_position = threat.global_position if threat != null else at
	# TOWARD THE MARK when nothing is known, not ZERO. An ordered throw with no
	# located threat is the normal case — you are pointing at a corner you want
	# screened precisely because nobody has eyes on it — and a ZERO bearing
	# makes every directional fallback in the kit refuse to place anything.
	context.threat_bearing = _bearing_to(context.threat_position if threat != null else at)
	context.squad_last_equipment_ms = _squad_last_equipment_ms()
	context.nearby_hostiles = []
	context.hostiles_near_target = []
	if ai_manager != null:
		context.nearby_hostiles = ai_manager.get_hostiles_in_radius(self, 5.0)
		context.hostiles_near_target = _hostiles_around(at, EQUIPMENT_CLUSTER_RADIUS)
	context.ordered_position = at
	context.has_ordered_position = use_point
	return context


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
		# THE CLAIM LEDGER, and this is the ONLY place it is touched. Every
		# target assignment in the game funnels through here — trigger_combat,
		# the squad push, the aggressive pull, return fire — so one decrement
		# and one increment keeps `by` and `incoming` exact. The moment
		# something else learns to assign a target directly, the ledger drifts
		# and every distribution decision after it is quietly wrong.
		_release_claim()
		_claim(body)
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
	var steps: Array = []
	for mult in [1.0, 0.5]:
		steps.append(global_position + lateral_dir * reposition_distance * mult)
	return _first_clear_step(steps, combat_target)

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

	# ONE navmesh query, on whichever step wins. See _first_clear_step.
	var steps: Array = []
	for mult in [1.0, 0.6, 0.3]:
		steps.append(global_position + direction * step * mult)
	return _first_clear_step(steps, combat_target)

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
	var steps: Array = []
	for mult in [1.0, 0.5]:
		steps.append(global_position + away_dir * fallback_distance * mult)
	return _first_clear_step(steps, combat_target)


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

	# AND A FLOOR UNDER THE FLIGHT TIME TOO. The cap above only ever SHORTENS
	# the flight, and a short flight is exactly what makes the arc tall:
	# `distance` is the HORIZONTAL gap, floored at 1cm, so a target nearly
	# overhead — something stood on a hive's 2.2m roof, a helicopter hovering
	# over the hatch — gives time = 0.002s and a `displacement.y / time` in the
	# hundreds of metres per second. The hopper went straight up and out of the
	# level, and nothing downstream caught it: it stays LEAPING the whole way
	# up, so the landing check never runs, and fell_out_speed only notices the
	# way back down.
	#
	# FLOOR THE TIME RATHER THAN CLAMP THE VELOCITY, because those two fail
	# differently. Capping vy on its own leaves the horizontal at the full leap
	# speed, so a hopper aimed at something directly overhead hurls itself
	# sixteen metres sideways to get nowhere. Lengthening the flight spends the
	# arc going UP instead, which is a robot visibly jumping at something it
	# cannot reach and landing where it started — the honest read.
	#
	# The floor is the shortest flight whose apex still fits the budget: at most
	# leap_max_apex above whichever end is higher. Solving 0.5*g*t^2 - vy*t + dy
	# for that vy leaves the root below; an ordinary leap has dy near zero,
	# which makes it zero, so nothing that could already make its jump moves.
	if gravity > 0.0:
		var apex: float = maxf(leap_max_apex, 0.0)
		var vy_max: float = sqrt(2.0 * gravity * (apex + maxf(displacement.y, 0.0)))
		time = maxf(time, (vy_max - sqrt(2.0 * gravity * apex)) / gravity)

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
	# "Under fire" starts here and is counted down in _tick_equipment. Set on
	# EVERY hit including friendly splash: a robot does not know who shot it,
	# and for deciding to throw smoke it does not matter.
	_since_hit = 0.0
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
	# Out of the fight, so let go of whatever we were shooting. A claim held by
	# a wreck occupies a slot in `incoming` forever and makes every robot still
	# standing think that target is already handled.
	_release_claim()
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
	_watch_for_targets(false)
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
	_set_colliders_disabled(false)
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
	_release_claim()
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
	_watch_for_targets(false)
	for i in particle_effects_die:
		i.activate()
	nav_agent.set_target_position(global_position)
	# A kill used to pay the player a handful of "bits" here. Nothing ever
	# spent them, so they are gone; `bits` is still what the WRECK is worth,
	# which is what a Reclaimer grinds it down for. See reclaimer.gd.
	_set_colliders_disabled(true)
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
	# SPENT BODIES DO NOT GET UP. Patching one is not refused outright — the
	# health still goes in, so a medic topping up a wreck is not doing nothing
	# — but it will not stand. The repair tool declines to target it in the
	# first place (see _is_repairable_ally), which is where the player is told
	# why; a silent no here would be the bug, a documented one is the rule.
	if downed and _revive_spent:
		pass
	elif downed and health >= int(ceil(max_health * revive_at_fraction)):
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
		# AND WHAT WAS SAVED. Same guard and the same reason as the kill tally
		# above: not every healer carries a counter.
		if "revives_by_kind" in healer:
			var rkind := _KillKinds.kind_of(self)
			healer.revives_by_kind[rkind] = int(healer.revives_by_kind.get(rkind, 0)) + 1
	_Analytics.heal(self, health - before, healer, was_down and not downed)


# ─────────────────────────────────────────────
# ONE REVIVE PER ROBOT PER MISSION.
#
# A squadmate can be stood back up once. The second time it goes down it stays
# down for the rest of the operation — NOT destroyed, and not lost: it comes
# home, it just takes no further part. The whole point is that a revive stops
# being a reflex and becomes a decision made while people are shooting at you.
#
# ONE ALLOWANCE, WHATEVER SPENDS IT. The player's repair tool, a mechanic's
# kit, a reclaimer's welder and a self-revive nanite charge all come through
# here, so all of them cost the same single charge. That deliberately changes
# what the self-revive module is worth: it no longer grants an EXTRA life, it
# means nobody has to walk over and spend yours. Said plainly because it is a
# balance decision, not a side effect.
#
# `spends` is false for the repair-shop restoration between missions
# (SquadSpawner), which is not a field revive and must not burn the next
# operation's charge before it starts.
# ─────────────────────────────────────────────
## True once this robot's single field revive has been used. Lives on the node,
## not the record, so it clears itself when the squad is rebuilt for the next
## mission — "per mission" is exactly this node's lifetime.
var _revive_spent: bool = false


## Whether this robot can still be stood back up. Read by the repair tool so a
## spent body is not even offered as a patient.
func can_revive() -> bool:
	return downed and not _revive_spent


func revive(spends: bool = true) -> void:
	if not downed:
		return
	# ASSIGNED, NOT JUST SET. A field revive spends the charge; a refit between
	# operations RESTORES it. The first version only skipped setting the flag on
	# a refit, which left a robot that had been patched up at base deploying
	# with last mission's charge already gone — it came home repaired and went
	# out with no revive left, which is the opposite of what the repair bought.
	_revive_spent = spends
	# Cancels any nanite timer still running. If a squadmate or the player got
	# here first, the charge was not spent and stays available for next time.
	_self_revive_gen += 1
	downed = false
	alive = true
	_watch_for_targets(true)
	health = maxi(health, int(ceil(max_health * revive_at_fraction)))
	_restore_pieces()
	_unsettle()
	_restore_collider()
	_stop_falling_through()
	_set_colliders_disabled(false)
	if weapon != null:
		weapon.show()
	# Same reasoning as in reset(): cleared alongside the tick it stands for.
	cull_frozen = false
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
	_on_revived()


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
	_set_colliders_disabled(true)
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
	# TIP THE WHOLE BODY OVER, don't spin each piece where it stands. Rotating a
	# piece about its OWN origin leaves it exactly where it was and only changes
	# which way it faces, so nothing travels with anything else: the marksman's
	# hat kept the same 0.58 m it had above the head while standing, and ended
	# up hovering at ground level over a head that had gone into the deck. The
	# body capsule looked right only because it sits at the origin, where the
	# two rotations are the same.
	#
	# The pitch is applied IN THE BODY'S OWN SPACE, not the piece's parent's, so
	# a rig with things hung off it (the Walker's hull under Rig, its turret
	# body under Turret) tips about the same point as everything else instead of
	# each sub-pivot spinning separately.
	var pitch := Basis(Vector3.RIGHT, deg_to_rad(collapse_pitch_degrees))
	var to_body := global_transform.affine_inverse()
	for piece in visible_pieces:
		if piece == null or not is_instance_valid(piece):
			continue
		if not _piece_rest.has(piece):
			_piece_rest[piece] = piece.transform
		var parent := piece.get_parent() as Node3D
		var parent_to_body := (to_body * parent.global_transform) if parent != null else Transform3D.IDENTITY
		var rest := parent_to_body * (_piece_rest[piece] as Transform3D)
		var tipped := Transform3D(pitch * rest.basis, pitch * rest.origin)
		tipped.origin.y -= collapse_drop
		piece.transform = parent_to_body.affine_inverse() * tipped
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
	# A NEW MISSION IS A NEW ALLOWANCE. reset() is the fresh-start path, so the
	# single field revive comes back with it.
	_revive_spent = false
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
	# The think half's own state. A robot that comes back owes nothing and is
	# watched for the moment it does, the same as one that has just been ordered
	# somewhere — see think_wait_seconds().
	_think_owed = 0.0
	_think_wait = 0.0
	_watched_t = THINK_WATCHED_SECONDS
	_vision_since = 0.0
	_adrift_poll = randf()
	_adrift_t = 0.0
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
	# Cleared alongside the tick it stands for. AIManager's poll would notice
	# the tick came back and drop the robot on its own pass, but this is the
	# same shape as always_active above — a flag set by one system and left for
	# another to tidy up is how always_active ended up never being reset at all.
	cull_frozen = false
	set_physics_process(true)
	set_process(true)
	_set_colliders_disabled(false)
	_on_revived()




## Called whenever this robot comes back — stood up by a Mechanic, self-revived
## off a nanite charge, or reset with the level.
##
## ANYTHING A SUBCLASS SWITCHED OFF ON THE WAY DOWN HAS TO COME BACK HERE.
## _ready() does not run twice, so a drone that stops its rotor loop when it is
## downed (spotter_drone, enemy_helicopter: enter_downed and both crash
## handlers) flew again in total silence once repaired — which reads as a broken
## drone rather than a quiet one. Both revive() and reset() call this, because
## they are separate paths back to life and only one of them used to be
## remembered.
func _on_revived() -> void:
	pass
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
			# A SQUADMATE SAW IT, SO WE KNOW ABOUT IT. This is the line that makes
			# seeing a squad property rather than a private one — the caller has
			# eyes on, so the contact is fresh for everybody on this side, whether
			# or not they are in a fight and whether or not they can see it
			# themselves. Written before the state guard below deliberately: a
			# robot already in COMBAT still benefits from the knowledge even
			# though it will not break off to go and look.
			if ai_manager != null and source_node != null and _is_hostile(source_node):
				ai_manager.note_seen(faction, source_node)
			if ai_state != AIState.COMBAT and ai_state != AIState.SEARCH:
				_remember_last_seen(source_position)
				if distance < 20.0:
					move_to(source_position)
				else:
					look_target = source_position


# ─────────────────────────────────────────────
# SIGNAL INTEGRITY — the robot half
#
# get_signal_state, receive_signal_damage, lock_signal and the e-kill latch are
# on AI now, shared with the player. What is left here is everything that only
# makes sense for a robot with a body and a squad: crediting whoever did it,
# thawing out of the distance cull so a suppressed robot can actually recover,
# stopping the chassis dead on an e-kill, and the arcs.
# ─────────────────────────────────────────────

## Thaw first, then the shared arithmetic.
##
## AND IT HAS TO BE TICKING TO CLIMB BACK OUT. _tick_signal is the only thing
## that recovers signal, and it is gated above the cull precisely so a culled
## robot keeps recovering — see the gate in _physics_process. A frozen robot
## has no tick at all, so suppression landing near one (a near-miss carries
## 250 m, well past the 75 m that froze it) would degrade it and leave it
## degraded until something else happened to wake it. _can_freeze_for_cull
## refuses while signal is off nominal, so it stays awake only for the second
## or so the recovery takes and then freezes itself again.
func receive_signal_damage(amount: float, source: Node = null) -> void:
	thaw_from_cull()
	super(amount, source)


## `source` is remembered rather than passed on: signal damage arrives in
## dozens of tiny helpings and the one that tips a robot over is rarely the
## interesting one — what the player wants told is who had been working on them.
func _on_signal_damaged(before: float, after: float, source: Node) -> void:
	if source != null:
		_signal_source = source
		_signal_cause = _Analytics.cause()
	# What was actually taken off, not what was thrown at it: a robot already
	# at zero loses nothing to a second EMP.
	_Analytics.signal_damage(self, before - after, source)


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


func lock_signal(seconds: float) -> void:
	super(seconds)
	# Same reasoning as receive_signal_damage: the lock is a countdown only
	# _tick_signal decrements, so handing one to a frozen robot would hold it
	# down for however long it stayed asleep rather than for `seconds`. In
	# practice the EMP that calls this has a 9 m radius and can never reach a
	# robot the cull has frozen at 75 m — this is here so that holds by design
	# and not by luck, if the blast ever grows or something else locks signal.
	thaw_from_cull()


func _tick_signal(delta: float) -> void:
	# The lock countdown, the passive climb and the latch — all shared.
	tick_signal(delta)

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

# A wreck notices nothing, so it stops testing for company. Its detection
# sphere is 20-25 m across and kept pairing with every body on the map: at the
# end of a Coast Road run that is hundreds of broad-phase pairs a frame for
# robots that are out of the fight. Put back on revive.
func _watch_for_targets(on: bool) -> void:
	if detection == null or not is_instance_valid(detection):
		return   # no sensor area on this frame (a nest, a test rig)
	detection.set_deferred("monitoring", on)


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
	var _los_at := Time.get_ticks_usec()
	var _los_hit = space_state.intersect_ray(query)
	_sight_spent_us += Time.get_ticks_usec() - _los_at
	_sight_rays += 1
	if _los_hit:
		return false
	# SMOKE BLOCKS SIGHT AND NOTHING ELSE. It cannot be a collider or the ray
	# above would stop bullets too, so it is asked separately — and it is asked
	# HERE because every caller of this function is a sight question (can I see
	# it, can I shoot it from that cover point, who shot me, can I throw there).
	# Movement never comes through here; that is the navmesh's job, and walking
	# into smoke has to stay possible or it is a wall.
	#
	# Free when no smoke exists: blocks_sight() returns on an integer compare.
	return not _Smoke.blocks_sight(get_tree(), from, to)

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
		# A confirmed sighting, into the faction's contact table. This is the
		# other half of the callout below: the stimulus tells the squad, this
		# tells the table, and both are needed for a contact to be FRESH.
		if ai_manager != null:
			ai_manager.note_seen(faction, body)
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
	# AND ONLY THE TRANSITION IS A WATCHED MOMENT, for exactly the reason the bark
	# above only fires on it. Inside a firefight trigger_combat is called over and
	# over — Squad._tick_aggressive_pull alone hands every targetless rusher a
	# contact four times a second — and a firefight is the CHEAP tier, not an
	# event. Marking every one of those watched would hand the whole brawl full
	# rate and undo the model.
	if ai_state != AIState.COMBAT:
		mark_watched()
	change_combat_target(body)
	movement_target = Vector3.ZERO
	change_ai_state(AIState.COMBAT)
	# A ROBOT HANDED A TARGET MUST BE ABLE TO ACT ON IT. The detection Area3D is
	# engine-driven: _on_detection_body_entered fires on a culled robot whose
	# tick is off, and the state change above would leave it in COMBAT with
	# nothing running to fight. AIManager's poll would catch it anyway (the
	# detection radius is well inside activation_distance), but that is a sweep
	# of latency for a contact, and contact is the one thing not worth being
	# late about.
	thaw_from_cull()
	combat_triggered.emit(self)
	checking_for_target = false
	combat_time = combat_recon_time
	reconsider_combat()


# ─────────────────────────────────────────────
# ACCURACY


# ─────────────────────────────────────────────
# WHERE THE ROUND GOES, which is not always what the robot is fighting.
# ─────────────────────────────────────────────
# A weapon set to pick its own target (AIWeapon.Targeting) gets asked here once
# a tick. Everything else answers `combat_target` and behaves exactly as before.
#
# The body's own target is deliberately NOT changed by this. Movement, facing
# and the squad's idea of who it is fighting all stay on `combat_target`, so a
# mortar robot advances with its squad while its tube is on something else.
func _tick_weapon_target(delta: float) -> void:
	if weapon == null or weapon.targeting == AIWeapon.Targeting.FOLLOW_BODY:
		return
	var picked := weapon.acquire(self, _visible_candidates(), delta)
	if picked != null and is_instance_valid(picked):
		weapon_target = picked.global_position


# What the gun is aimed at, as a body. Used for the range and line-of-fire
# checks so they ask about the thing being shot at rather than the thing being
# fought.
func _aimed_body() -> CharacterBody3D:
	if weapon != null and weapon.targeting != AIWeapon.Targeting.FOLLOW_BODY \
			and weapon.own_target != null and is_instance_valid(weapon.own_target):
		return weapon.own_target
	return combat_target
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
	if suppressive_fire:
		mult *= SUPPRESSIVE_SPREAD
	# SOMEBODY HAS EYES ON IT. A fresh contact does not let you shoot further —
	# it lets you shoot straighter, which is the version of spotting that costs
	# no sensor or range value anywhere. It is also what turns the Spotter from
	# a frame that sees things into a damage multiplier for the whole squad.
	if _contact_assisted():
		mult *= SPOTTED_SPREAD
	return mult


## Multiplier applied while a squadmate has current eyes on what we are shooting.
## Below 1.0 because this function returns SPREAD: smaller is tighter.
const SPOTTED_SPREAD := 0.82


func _contact_assisted() -> bool:
	if ai_manager == null or combat_target == null or not is_instance_valid(combat_target):
		return false
	if Settings.debug_tools_enabled():
		if not bool(Settings.get_value("debug.contact_accuracy")):
			return false
	return ai_manager.is_fresh(faction, combat_target)


# ─────────────────────────────────────────────
# GIVING WAY.
#
# Two robots that meet in a gap only one of them fits through used to stand there
# for three seconds before anything happened, and what happened then was a
# NAVIGATION query: _handle_path_blocked() asks the server for a point a few
# metres to one side and re-paths to it. That is the wrong tool twice over. It
# costs a path resolution — the most expensive thing a robot can do — and the
# navmesh has no idea another robot is standing there, so the new path can run
# straight back through it. Both of them roll randf() independently for which
# side to try, so they can keep choosing the same one; at nine seconds they give
# up and stand still. From the outside the pair is welded together and the only
# way out is to kill one.
#
# This resolves it in four tenths of a second and costs NOTHING: no raycast, no
# navigation query, no change to movement_target. _damp_shoving() already walks
# the slide collisions every frame to find out whether this body is touching
# another one, so the contact is known for free; the response is a sideways
# velocity for a fraction of a second.
#
# ONLY ONE OF THE PAIR MOVES. The smaller chassis steps aside and the bigger one
# holds its line — a rover does not shuffle for a soldier. Equal sizes fall back
# to instance order, which both of them compute the same way from the same two
# numbers. That is what stops the mirroring, and it is also why this cannot turn
# into the whole squad spreading out: a robot that is not the one yielding does
# not move at all, and the one that is keeps its original destination and resumes
# the moment it is clear.
#
# After GIVE_WAY_MAX_TRIES sidesteps that did not help, it stops trying and lets
# the slow path above have it — at that point it is not a tangle, it is a wall.
# ─────────────────────────────────────────────

## Seconds of being in contact AND making no progress before one of them moves.
const GIVE_WAY_BLOCKED_TIME: float = 0.4
## How long a sidestep lasts once started.
const GIVE_WAY_DURATION: float = 0.7
## Sidestep speed, as a fraction of this chassis's own walking speed.
const GIVE_WAY_SIDE_SPEED: float = 0.9
## Sidesteps before this is declared not-a-tangle and handed to _check_stuck.
const GIVE_WAY_MAX_TRIES: int = 4
## A move counts as progress at this fraction of what was asked for. Contact
## scrubs some speed off legitimately, so it cannot be judged against the full
## intent.
const GIVE_WAY_PROGRESS: float = 0.35

## The other body this one is touching, if any. Set by _damp_shoving(), which
## already has to look.
var _touching: Node = null
var _blocked_t: float = 0.0
var _give_way_t: float = 0.0
var _give_way_dir: Vector3 = Vector3.ZERO
var _give_way_tries: int = 0

## Warned once per run, then counted. A tangle that sidestepping cannot fix is
## worth knowing about, but it is not worth a stack trace per robot per attempt —
## see the fall-out counter for the same bargain.
static var _wedged_count: int = 0
static var _wedged_warned: bool = false


## Folded into velocity before the move. Does nothing unless a sidestep is live.
func _apply_give_way() -> void:
	if _give_way_t <= 0.0:
		return                      # not yielding; the common case, and free
	# SET, NOT ADD, AND THIS IS THE WHOLE BUG.
	#
	# This was `velocity.x += ...` every frame for the length of the sidestep.
	# The movement code LERPS velocity toward what it wants rather than
	# overwriting it, so the nudge did not get cleared between frames — it
	# compounded. Measured: 5.4 m/s of sidestep climbing monotonically to 37 m/s
	# over forty frames and throwing the robot twenty metres, long after the pair
	# had separated. _damp_shoving never caught it because by then they were not
	# touching, and it only caps a body that is.
	#
	# "Robots randomly bump and go flying" was this, not the physics solver.
	#
	# Stepping aside IS the whole of the movement for those seven tenths of a
	# second, so setting it outright is also what the behaviour wants.
	var side := _give_way_dir * move_speed * GIVE_WAY_SIDE_SPEED
	velocity.x = side.x
	velocity.z = side.z


## Called after the move has resolved, with where it started and what it asked
## for. Decides whether this robot is the one that should step aside.
func _tick_give_way(before: Vector3, intent: Vector3) -> void:
	var delta := get_physics_process_delta_time()
	if _give_way_t > 0.0:
		_give_way_t -= delta
		return                      # already stepping aside; let it finish

	if movement_state != MovementState.MOVING or _touching == null:
		# Not trying to go anywhere, or not touching anybody. Nothing to resolve,
		# and the counters must not carry over into the next tangle.
		_blocked_t = 0.0
		_give_way_tries = 0
		return

	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	var wanted := Vector2(intent.x, intent.z).length() * delta
	if wanted < 0.0001:
		_blocked_t = 0.0
		return                      # asked for nothing, so being still is right
	if moved > wanted * GIVE_WAY_PROGRESS:
		_blocked_t = 0.0
		return                      # still getting somewhere: brushing past, not wedged

	_blocked_t += delta
	if _blocked_t < GIVE_WAY_BLOCKED_TIME:
		return                      # not long enough yet to call it a wedge
	_blocked_t = 0.0

	if _give_way_tries >= GIVE_WAY_MAX_TRIES:
		# Sidestepping has not worked. Leave it to _check_stuck's re-path, which
		# is the right tool for geometry even though it is the wrong one for a
		# robot, and say so once.
		_wedged_count += 1
		if not _wedged_warned:
			_wedged_warned = true
			push_warning("%s could not get past %s in %d sidesteps, so it is being treated as blocked terrain. Further wedges this run are counted in Enemy._wedged_count rather than logged." % [
				name, str(_touching.name) if _touching != null else "another body", GIVE_WAY_MAX_TRIES])
		return

	if not _should_yield_to(_touching):
		return                      # the bigger chassis holds its line

	_give_way_tries += 1
	_give_way_dir = _give_way_side(_touching, intent)
	_give_way_t = GIVE_WAY_DURATION


## Which of the two moves. Both sides answer this identically from the same two
## numbers, without talking to each other — that is the whole trick.
func _should_yield_to(other: Node) -> bool:
	var theirs: float = 0.5
	var v = other.get("body_radius")
	if v != null:
		theirs = float(v)
	if absf(body_radius - theirs) > 0.05:
		return body_radius < theirs           # the smaller one steps aside
	# Same size. Somebody still has to move, so the lower instance id does.
	return get_instance_id() < other.get_instance_id()


## Which way to step: perpendicular to the line between the pair, and of the two
## perpendiculars the one that still makes progress toward where this robot was
## already going. A sidestep that goes backwards buys nothing and is exactly what
## "spreading out and then re-walking it" looks like.
func _give_way_side(other: Node, intent: Vector3) -> Vector3:
	var away := global_position - (other as Node3D).global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		# Exactly co-located. Any direction serves, but it has to be a STABLE
		# one or the pair jitters instead of separating.
		away = Vector3.RIGHT
	var side := away.normalized().cross(Vector3.UP).normalized()
	var want := Vector3(intent.x, 0.0, intent.z)
	if want.length_squared() > 0.0001 and side.dot(want.normalized()) < 0.0:
		side = -side
	return side


## This chassis's half-width, off its own shape. See body_radius.
func _measure_body_radius() -> void:
	var s: Shape3D = _collision_shape.shape if _collision_shape != null else null
	if s is CapsuleShape3D:
		body_radius = (s as CapsuleShape3D).radius
	elif s is CylinderShape3D:
		body_radius = (s as CylinderShape3D).radius
	elif s is SphereShape3D:
		body_radius = (s as SphereShape3D).radius
	elif s is BoxShape3D:
		var e := (s as BoxShape3D).size
		body_radius = maxf(e.x, e.z) * 0.5
	else:
		# Left at the infantry default. Not fatal — give-way falls back to
		# instance order — but this chassis will shuffle aside for things it
		# actually outweighs, so it is worth knowing.
		push_warning("%s has no measurable body shape, so its size is unknown and it will give way as though it were infantry." % name)


# ── EQUIPMENT CONTEXT ─────────────────────────
#
# What the kit needs to know beyond who it is shooting. All four are asked once
# per EQUIPMENT_RECON_TIME (1.5s), not per frame, so they can afford to look
# around a little.
#
# `squad` lives on Soldier rather than on Enemy — a garrison robot in no squad
# is a perfectly ordinary thing — so it is reached the way this file reaches
# other optional members, by asking whether the property is there at all.

## The squad's current order, or NONE when this robot is in no squad. Returned
## as an int because Squad.SquadObjective is not visible from here.
func _squad_objective() -> int:
	var sq = get("squad") if "squad" in self else null
	if sq == null or not is_instance_valid(sq):
		return 0   # SquadObjective.NONE
	return int(sq.objective)


## The nearest squadmate on the floor, or null. Downed rather than dead: a wreck
## is nobody's problem, a downed robot is something a mechanic can still stand
## back up — and the thing worth screening with smoke.
func _nearest_downed_friendly() -> Node3D:
	var sq = get("squad") if "squad" in self else null
	if sq == null or not is_instance_valid(sq) or not sq.has_method("get_orderable_members"):
		return null
	var best: Node3D = null
	var best_d := INF
	for m in sq.get_orderable_members():
		if m == null or not is_instance_valid(m) or m == self:
			continue
		if not bool(m.get("downed")):
			continue
		var d: float = global_position.distance_squared_to((m as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = m
	return best


## WHAT the trouble is. The target if there is one, the nearest hostile
## otherwise — a robot taking fire from something it has not identified still
## knows roughly where the trouble is. Null when nothing is known.
##
## Returns the BODY rather than a point, and the one caller derives the point
## and the bearing from it, so the manager is asked once. The body is the part
## that matters: anything that wants to know whether that threat can see it has
## to exclude it from the raycast, because a ray cast at something's own
## position stops inside its collider (see `_update_los`, which passes
## combat_target to is_path_clear for this reason).
func _threat_actor() -> Node3D:
	if combat_target != null and is_instance_valid(combat_target) and combat_target.alive:
		return combat_target
	if ai_manager == null:
		return null
	var near: Array = ai_manager.get_hostiles_in_radius(self, sensor_range)
	var best := INF
	var who: Node3D = null
	for h in near:
		if h == null or not is_instance_valid(h) or not (h is Node3D):
			continue
		var d: float = global_position.distance_squared_to((h as Node3D).global_position)
		if d < best:
			best = d
			who = h
	return who


## The flat unit vector from here to `at`. Flat on purpose: everything this aims
## is placed on the ground, and a bearing that tilts up toward a walker's head
## puts the cloud short.
##
## ZERO means "nowhere to point" — either nothing was found or it is standing on
## top of us, and both of those mean "do not place anything directional".
func _bearing_to(at: Vector3) -> Vector3:
	var flat := Vector3(at.x - global_position.x, 0.0, at.z - global_position.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO


## Hostiles standing within `radius` of a POINT, which is a different question
## to the ones standing near us. One manager call, then filtered: asking the
## manager for a radius big enough to reach the point and trimming is cheaper
## than teaching it a second query shape.
func _hostiles_around(point: Vector3, radius: float) -> Array:
	if ai_manager == null:
		return []
	var reach: float = global_position.distance_to(point) + radius
	var out: Array = []
	for h in ai_manager.get_hostiles_in_radius(self, reach):
		if h == null or not is_instance_valid(h):
			continue
		if (h as Node3D).global_position.distance_to(point) <= radius:
			out.append(h)
	return out


## When anyone in this squad last spent a piece of equipment. Four soldiers
## evaluating the same situation on the same tick is how a squad answers one
## grenade's worth of problem with four grenades; this is what lets a rule say
## "not if somebody just did".
func _squad_last_equipment_ms() -> int:
	var sq = get("squad") if "squad" in self else null
	if sq == null or not is_instance_valid(sq) or not sq.has_method("get_orderable_members"):
		return _last_equipment_ms
	var newest := _last_equipment_ms
	for m in sq.get_orderable_members():
		if m == null or not is_instance_valid(m):
			continue
		if not ("_last_equipment_ms" in m):
			continue
		newest = maxi(newest, int(m.get("_last_equipment_ms")))
	return newest


# ─────────────────────────────────────────────
# CLAIM LEDGER
# ─────────────────────────────────────────────
# What this robot contributes to a target's `incoming`: its own sustained
# damage per second. Weapon-accurate rather than a headcount, because that is
# the whole point — a mortar at 20 DPS and a Heavy MG at 183 should not count
# the same towards "this one is already handled".
func sustained_dps() -> float:
	if weapon == null:
		return 0.0
	var cd: float = maxf(weapon.fire_cooldown, 0.01)
	return float(weapon.base_damage) * maxf(float(weapon.pellets), 1.0) / cd


## The reach the scorer asks about, so "inside my effective band" means the same
## thing here as it does when the robot decides to fire.
func weapon_max_range() -> float:
	return _max_range()


func _claim(body) -> void:
	if ai_manager == null or body == null or not is_instance_valid(body):
		return
	ai_manager.claim(faction, body, sustained_dps())
	_claimed = body


func _release_claim() -> void:
	if ai_manager == null or _claimed == null or not is_instance_valid(_claimed):
		_claimed = null
		return
	ai_manager.release(faction, _claimed, sustained_dps())
	_claimed = null


# ─────────────────────────────────────────────
# A FREED NODE IS NOT NULL
# ─────────────────────────────────────────────
# In GDScript a freed object is a DANGLING reference: it fails is_instance_valid
# but it is not `null`, so `if combat_target != null` passes and the next line
# touching it takes the game down.
#
# About twenty places in this file read combat_target behind exactly that
# `!= null` check, and every one of them is correct ONLY while the invariant
# "combat_target is either null or valid" holds. Rather than add twenty guards —
# and miss the twenty-first — this restores the invariant once, at the top of
# the tick, before anything reads it.
#
# FOUND BY A DIVER. An equipment drone frees itself outright rather than leaving
# a repairable wreck, so a soldier holding one as a target was left with a
# dangling reference the moment it was shot down; _evaluate_equipment_use then
# assigned it into an EquipmentContext and crashed.
#
# Note what is NOT done here: nothing is released from the contact ledger for a
# freed body, because there is nothing to release it from. AIManager._prune_contacts
# drops rows whose body has gone invalid on the same 0.4 s tick that clears the
# hostile cache, so the row and its `incoming` disappear together.
func _drop_freed_references() -> void:
	if combat_target != null and not is_instance_valid(combat_target):
		combat_target = null
		weapon_target = Vector3.ZERO
		_has_los = false
	if _preempted_target != null and not is_instance_valid(_preempted_target):
		_preempted_target = null
	if _claimed != null and not is_instance_valid(_claimed):
		_claimed = null
