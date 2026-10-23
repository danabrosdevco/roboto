extends Walker
class_name SeeEngine

# ─────────────────────────────────────────────
# SEE-ENGINE — the thing that is not shooting at you is why the things shooting
# at you are hitting.
#
# WHAT IT IS FOR. While it lives, every Argus unit shoots tighter at anything
# it can see. It barely fights, and that is the threat: it is the first enemy
# whose danger is legible without a gun pointed at you, and the counter is
# obvious without being easy — get past the escort and kill the thing that is
# not shooting.
#
# ─────────────────────────────────────────────
# WHAT IS FREE HERE, AND WHAT IS NOT. Read this before adding anything.
#
# THE AIM BONUS IS FREE — ZERO LINES. Enemy.get_aim_spread_multiplier
# (enemy.gd:3246-3261) already ends with `if _contact_assisted(): mult *=
# SPOTTED_SPREAD`, and _contact_assisted (5269-5276) is already keyed on the
# SHOOTER'S OWN faction via AIManager.is_fresh(faction, target). So the moment
# anything writes an ARGUS contact for a body, every ARGUS robot shooting at
# that body shoots 18% tighter — no radius, no registration, nothing to
# recompute. docs/frames/SEE_ENGINE.md proposes an explicit accuracy bonus
# applied to same-faction units in radius: DO NOT BUILD IT. It would be a
# second, disagreeing copy of a term that already exists.
#
# That also means "a Swarm or Home Command unit does not benefit" is
# STRUCTURAL rather than implemented — AIManager._contacts is keyed by faction,
# so a Swarm robot asking is_fresh(SWARM, x) reads a different table. There is
# no filter here to get wrong.
#
# THE SEEING IS NOT FREE, AND sensor_range DOES NOTHING FOR IT. _tick_vision
# (enemy.gd:929-1027) is the function sensor_range drives, and it NEVER calls
# note_seen — it ends at trigger_combat/change_combat_target. The only thing
# that writes a contact from a robot's own eyes is the Detection Area3D
# callback (enemy.gd:5136), a 25 m sphere that every robot in the game has.
# So a 110 m sensor — the highest in the game — buys this frame nothing at all
# without _tick_watch below. That is the whole cost of the frame.
#
# THE LEGIBILITY IS NOT FREE EITHER, AND IT IS MANDATORY. An 18% spread
# multiplier is below perception, and hud.gd:70-72 filters contact marks to
# ALLIED only — there is no player-facing readout of an enemy faction's contact
# table anywhere in the game. Without the lit pupil, killing this frame changes
# nothing the player can see, which is precisely the failure that got the
# Warden cut (git show c7178bf7). _tick_pupil is not polish.
#
# NO EDITS TO Enemy, Soldier, Walker, AI or AIManager. Everything below is a
# subclass override or a new function.
# ─────────────────────────────────────────────

@export_group("Watch")
## Seconds between contact sweeps. MUST stay comfortably under
## AIManager.contact_fresh_seconds (3.0, ai_manager.gd:201), or the contacts
## this frame is holding open go stale between sweeps and the whole formation's
## aim bonus flickers on and off.
@export var watch_interval: float = 1.0
## Rig/GimbalYaw/LensPitch/Pupil. Resolved in _ready if left null — a NodePath
## assigned to a typed MeshInstance3D export silently does nothing, which is
## why this is never authored in the .tscn.
@export var pupil: MeshInstance3D
@export var pupil_lit_energy: float = 2.4
## Tyrian, to match hud_palette.gd's FAC_ARGUS. Argus's own colour, not the
## faction paint — the pupil is deliberately outside the FactionLivery pieces
## array, same as the Walker's eye.
@export var pupil_colour: Color = Color(0.69, 0.20, 0.47)

var _watch_timer: float = 0.0
var _watching: bool = false
## Duplicated off the Pupil's material_override in _ready. RESOURCES ARE
## SHARED: the .tscn's StandardMaterial3D sub-resource is one object across
## every instance of this scene, so writing emission onto it directly would
## light the pupil of every See-Engine on the map — including the dead ones.
var _pupil_material: StandardMaterial3D = null


func _ready() -> void:
	super()
	if pupil == null:
		pupil = get_node_or_null("Rig/GimbalYaw/LensPitch/Pupil") as MeshInstance3D
	if pupil == null:
		push_warning("%s has no Rig/GimbalYaw/LensPitch/Pupil, so killing it will change nothing the player can see." % name)
	else:
		var base := pupil.material_override as StandardMaterial3D
		if base == null:
			push_warning("%s: the Pupil has no StandardMaterial3D override, so it cannot be lit." % name)
		else:
			_pupil_material = base.duplicate()
			_pupil_material.emission_enabled = true
			_pupil_material.emission = pupil_colour
			_pupil_material.emission_energy_multiplier = 0.0
			pupil.material_override = _pupil_material


# A CULLED SEE-ENGINE STOPS FEEDING, AND THAT IS CORRECT. The distance cull
# switches _physics_process off entirely (ai_manager.gd:576-593), so a frozen
# frame stops stamping and the contacts lapse within contact_fresh_seconds.
# Stated because the mechanism is invisible and somebody will otherwise "fix"
# it by moving the sweep somewhere that still ticks.
func _physics_process(delta: float) -> void:
	super(delta)
	_tick_watch(delta)
	_tick_pupil()


# WHAT MAKES THIS FRAME A FRAME. ~20 lines, and everything it calls already
# exists: AIManager.get_hostiles_in_radius (ai_manager.gd:501-520, which
# already filters by Enums.are_hostile — the reason the faction table had to
# land first), Enemy.is_path_clear (enemy.gd:5062), AIManager.note_seen (260).
# Enemy._threat_actor (5514) is the shipped precedent for calling
# get_hostiles_in_radius with sensor_range.
#
# THE TEMPTING SHORTCUT IS ENLARGING THE DETECTION Area3D TO 110 m, which needs
# no script at all. Do not: _on_detection_body_entered (5103-5145) also calls
# trigger_combat and emits ENEMY_SPOTTED, so a 110 m detection sphere makes a
# weaponless command node charge into every fight on the map — and a 110 m
# physics area on a 186-body level is a real broadphase cost. That callback is
# an acquisition path, not a sensor.
func _tick_watch(delta: float) -> void:
	_watch_timer -= delta
	if _watch_timer > 0.0:
		return
	_watch_timer = watch_interval
	_watching = false
	if ai_manager == null or not alive or downed \
			or get_signal_state() == SignalState.EKILL:
		return   # down, jammed or standing in a level with no AIManager
	var eyes_at: Vector3 = global_position + Vector3.UP * 0.9
	for h in ai_manager.get_hostiles_in_radius(self, sight_range()):
		if h == null or not is_instance_valid(h) or not (h is Node3D):
			continue
		# IT HAS TO ACTUALLY SEE IT. Without this the frame feeds the whole
		# formation contacts through terrain, which is a wallhack and not a
		# sensor — and it is the one thing about this frame a player would be
		# right to call cheating.
		if not is_path_clear(eyes_at, (h as Node3D).global_position, h as Node3D):
			continue
		ai_manager.note_seen(faction, h)
		_watching = true


# THE ONLY PART OF THIS FRAME'S DEATH THE PLAYER CAN SEE. See the header: the
# effect itself is an 18% spread multiplier and the HUD has no readout for an
# enemy faction's contacts, so the eye going dark IS the mechanic's feedback.
# The gimbal is already traversing onto whatever the body has noticed
# (walker.gd:206-228), which is the other half of the read.
func _tick_pupil() -> void:
	if _pupil_material == null:
		return
	var want: float = pupil_lit_energy if (_watching and alive and not downed) else 0.0
	if not is_equal_approx(_pupil_material.emission_energy_multiplier, want):
		_pupil_material.emission_energy_multiplier = want


# ─────────────────────────────────────────────
# SEAMS
# ─────────────────────────────────────────────
# AN EXPLICIT STUB, NOT A RELIANCE ON `weapon == null`. The frame has no weapon
# so the machine would do nothing anyway — but "it never enters a firing state"
# should be a property of this script rather than an accident of an empty
# mount. spotter_drone.gd is the shipped example.
#
# roll_combat_action is deliberately NOT stubbed, unlike the Spotter's: this
# frame needs the dice to pick MOVE so it can back away. See §5.2 of
# docs/integration/SEE_ENGINE.md and the option arrays on the scene.
func handle_weapon_logic(_delta):
	pass


# THE EYE GOES OUT WITH IT. die() switches the physics tick off, so _tick_pupil
# stops being called and whatever the emission was on that last frame is what
# it would keep, forever, on a dead frame staring at nothing. Put it out here
# rather than relying on a tick that is about to stop — the same reason
# enemy_nest.gd douses its flames in destroy().
func die() -> void:
	_watching = false
	if _pupil_material != null:
		_pupil_material.emission_energy_multiplier = 0.0
	super()


func enter_downed() -> void:
	_watching = false
	if _pupil_material != null:
		_pupil_material.emission_energy_multiplier = 0.0
	super()


## Whether it fed a contact on its last sweep. For the test and the debrief.
func is_watching() -> bool:
	return _watching
