extends "res://Character/characters/ai/rover.gd"

# ─────────────────────────────────────────────
# VESSEL — a six-wheeled carrier whose weapon releases bodies.
#
# Everything that makes this thing drive is rover.gd: Ackermann steering,
# reverse, whisker blocking, suspension, the traversing turret, the wreck pose.
# Everything that makes it a weapons platform is AIWeapon and
# Enemy.handle_weapon_logic. This script is ONE behaviour: THE BAY DOORS.
#
# ─────────────────────────────────────────────
# WHAT THE DOORS ARE FOR
#
# The frame's whole proposition is that open and closed are two readable
# silhouettes, so the state the player cares about is the state they can see
# from the command height. Shut while it travels; open when it is committed and
# loaded; shut again while it recharges. A door that opened and closed inside
# the release frame would not be a read at all — the player has to see the
# Vessel DECIDE, which is why the commit test below is not "opening at the
# instant of release".
#
# THE DOOR STATE AND THE LAUNCHER STATE ARE THE SAME FACT. bay_has_charges()
# reads the weapon's magazine, and _bay_display() derives the two cargo meshes
# from the same number. Nothing here counts charges of its own, so a bay that
# shows two drones and a launcher that has one round left cannot happen.
#
# ─────────────────────────────────────────────
# THE GEOMETRY, MEASURED OFF THE SCENE
#
# Rig/Bay/DoorL is authored at rotation.z = +130 degrees and Rig/Bay/DoorR at
# -130. build_vessel.gd's header is explicit: "TO CLOSE, ROTATE EACH DOOR'S
# LOCAL Z TO ZERO ... 130 degrees of travel each. Nothing else moves." The
# hinge bars are separate body-fixed meshes and the leaves are the only
# children, so this script touches two rotations and two visibilities and
# nothing else.
#
# A LERP OFF _physics_process, NOT A TWEEN AND NOT A COROUTINE. A coroutine
# that outlives the tree segfaults in cleanup at quit (see CLAUDE.md), and a
# tween on a frame that is about to be culled, wrecked or freed is state this
# does not need: one float of travel, driven by the same tick that drives the
# wheels, cannot get out of step with the body.
# ─────────────────────────────────────────────

enum DoorState { STOWED, OPENING, OPEN, CLOSING }

@export_group("Bay doors")
## Seconds for a full swing, either way. 130 degrees of travel.
@export var door_seconds: float = 1.1
## Out of contact — or out of charges — this long and the bay stows itself.
## Short enough that a spent Vessel does not drive home with its doors out;
## long enough that a lull in a firefight does not cycle them.
@export var close_after: float = 4.0
## How far open is open. Dropping this to ~110 costs half a metre of width for
## a read that is still unmistakable from above, and is the mitigation if the
## doors turn out to clip level geometry — see docs/integration/VESSEL.md §8.
@export var door_open_degrees: float = 130.0

var _door_state: int = DoorState.STOWED
## 0.0 shut, 1.0 fully open. The single piece of state the doors have.
var _door_travel: float = 0.0
var _uncommitted_for: float = 0.0

var _door_l: Node3D = null
var _door_r: Node3D = null
var _cargo_a: Node3D = null
var _cargo_b: Node3D = null
## Switched off, with a reason, if the bay is not wired. See _ready.
var _doors_wired: bool = false
var _warned_shut: bool = false


func _ready() -> void:
	_door_l = get_node_or_null("Rig/Bay/DoorL") as Node3D
	_door_r = get_node_or_null("Rig/Bay/DoorR") as Node3D
	_cargo_a = get_node_or_null("Rig/Bay/CargoA") as Node3D
	_cargo_b = get_node_or_null("Rig/Bay/CargoB") as Node3D
	_doors_wired = _door_l != null and _door_r != null
	if not _doors_wired:
		# EVERY EARLY RETURN WARNS. A Vessel whose doors are silently dead is a
		# frame whose entire read is missing and which still drives and fights,
		# so it would present as a complaint about the art weeks later.
		push_warning(("%s: Rig/Bay/DoorL or Rig/Bay/DoorR is missing, so the bay "
			+ "doors are switched off. The frame still drives and still releases "
			+ "hatchlings — it just does it through a roof that never moves.") % name)
	if _cargo_a == null or _cargo_b == null:
		push_warning(("%s: Rig/Bay/CargoA or CargoB is missing, so the bay cannot "
			+ "show what it is carrying. Releases still work.") % name)
	super()
	# CLOSED AT SPAWN. The scene is authored OPEN, because build_vessel.gd built
	# the leaves at 130 degrees — so without this line every Vessel in the game
	# drives out of the hub with its bay hanging open.
	_door_travel = 0.0
	_apply_doors()
	_bay_display()


func _physics_process(delta: float) -> void:
	# The driving, the navigation and the weapon all live above this call. A
	# Vessel that skipped it would be a statue with working doors.
	super(delta)
	if not alive:
		return   # a wreck's doors stay where they were; see _collapse_pieces on rover.gd
	_tick_doors(delta)
	_bay_display()


# ─────────────────────────────────────────────
# THE COMMIT TEST
# ─────────────────────────────────────────────

## The rounds this frame treats as cargo. A canister that bursts into bodies is
## the bay's contents; anything else in the mount is just a gun.
##
## THIS LIST IS WHY THE BAY CANNOT OPEN OVER A MACHINE GUN.
## item_machine_gun.tres whitelists &"vessel", so a player can legally trade the
## launcher for an MG — a carrier that gave up its bay for a gun, which is a
## fine thing to want. Without this check the MG's thirty rounds would read as
## thirty charges and the doors would swing open in every firefight over an
## empty bay. Nothing would error; it would just look broken.
const BAY_ROUNDS := [
	"res://Character/weapon/hatchling/vessel_brood_canister.tscn",
	"res://Character/weapon/hatchling/hatchling_canister.tscn",
]


## Which weapon the verdict below was reached about, so a refit re-asks and a
## tick does not. _bay_launcher is called twice a physics frame per Vessel and
## the test behind it is a string compare against a resource path — cheap once,
## absurd sixty times a second for a frame that has not changed its gun since
## it rolled out of the hub.
var _judged_weapon_id: int = 0
var _judged_is_bay: bool = false


## The fitted weapon, but only if it is a launcher loaded with bodies.
func _bay_launcher():
	if weapon == null or not is_instance_valid(weapon):
		return null   # the mount is empty: a legitimate state, and the bay stays shut
	var id := weapon.get_instance_id()
	if id != _judged_weapon_id:
		_judged_weapon_id = id
		var round_scene = weapon.get("grenade_scene")
		_judged_is_bay = round_scene != null \
				and BAY_ROUNDS.has(String(round_scene.resource_path))
	return weapon if _judged_is_bay else null


## Is there anything left to put out. Reads the LAUNCHER, not a counter of its
## own: magazine_current is the bay, and a reloading launcher is a bay that is
## refilling and has nothing in it yet.
##
## Null weapon is a legitimate state — a player can strip the mount — and the
## answer is correctly "no", so the bay stays shut. There is no warning here on
## purpose: an unarmed Vessel is a choice, not a fault.
func bay_has_charges() -> bool:
	var launcher = _bay_launcher()
	if launcher == null:
		return false
	if launcher.infinite_ammo:
		return true
	return launcher.magazine_current > 0 and not launcher.is_reloading


# The fight has started as far as this carrier is concerned. COPIED PART FOR
# PART from enemy_nest.gd:176-182, which is the other frame in this game whose
# whole job starts when a fight does; the two should not drift.
func _fighting() -> bool:
	if ai_state == AIState.COMBAT:
		return true
	if combat_target != null and is_instance_valid(combat_target) and combat_target.alive:
		return true
	return squad != null and is_instance_valid(squad) and squad.has_live_contact()


## Loaded and in a fight. This is the whole design decision.
func _committed() -> bool:
	return bay_has_charges() and _fighting()


# ─────────────────────────────────────────────
# THE DOOR STATE MACHINE
# ─────────────────────────────────────────────

func _tick_doors(delta: float) -> void:
	if not _doors_wired:
		return   # warned once in _ready
	if _committed():
		_uncommitted_for = 0.0
		if _door_state == DoorState.STOWED or _door_state == DoorState.CLOSING:
			_door_state = DoorState.OPENING
	else:
		_uncommitted_for += delta
		# Held for close_after rather than shut the instant contact drops: a
		# target dying mid-engagement should not slam the bay on the next frame.
		if _uncommitted_for >= close_after \
				and (_door_state == DoorState.OPEN or _door_state == DoorState.OPENING):
			_door_state = DoorState.CLOSING

	var rate: float = delta / maxf(door_seconds, 0.01)
	match _door_state:
		DoorState.OPENING:
			_door_travel = minf(1.0, _door_travel + rate)
			if _door_travel >= 1.0:
				_door_state = DoorState.OPEN
		DoorState.CLOSING:
			_door_travel = maxf(0.0, _door_travel - rate)
			if _door_travel <= 0.0:
				_door_state = DoorState.STOWED
	_apply_doors()


# Both leaves off ONE float, and signed opposite. Derived rather than lerped
# separately so a mirrored leaf is impossible: there is no second number to get
# wrong.
func _apply_doors() -> void:
	if not _doors_wired:
		return
	var open: float = deg_to_rad(door_open_degrees) * _door_travel
	_door_l.rotation.z = open
	_door_r.rotation.z = -open


## Pushes the doors towards open without waiting for the commit test. Used by
## the fire gate below, so a release that arrived through a shut bay is a
## one-cooldown hold rather than a refusal.
func _request_open() -> void:
	if not _doors_wired:
		return
	_uncommitted_for = 0.0
	if _door_state != DoorState.OPEN:
		_door_state = DoorState.OPENING


func door_state() -> int:
	return _door_state


func doors_open() -> bool:
	return not _doors_wired or _door_state == DoorState.OPEN


# ─────────────────────────────────────────────
# THE FIRE GATE — the seam the doors hang off
# ─────────────────────────────────────────────
#
# Enemy.fire() (enemy.gd:4141) is the funnel. It is the one place the trigger is
# actually pulled: handle_weapon_logic's FIRE arm calls it, weapon.fire()
# decrements magazine_current inside it, and nothing else in the project calls
# weapon.fire() on a squad body. So gating here gates every release, including a
# suppressive-fire commit and anything a future order path adds.
#
# NOT A COROUTINE, and not an await on the door swing. The round is spent inside
# this call; awaiting would leave a window in which the launcher still reports a
# round available and a second evaluation could spend it twice. A one-cooldown
# hold is the cheap correct answer, and the commit test means the doors are
# already open before the weapon ever settles — so this almost never refuses.
#
# Refusing costs exactly one fire_cooldown: handle_weapon_logic sets
# weapon_state back to AIM either way, so the frame keeps tracking and tries
# again rather than locking up.
#
# GATED ON THE BAY LAUNCHER, NOT ON THE MOUNT. A Vessel refitted with a machine
# gun never opens its doors — correctly, it is carrying nothing — so a gate that
# only read doors_open() would be a frame that can never pull its own trigger.
func fire():
	if _bay_launcher() != null and not doors_open():
		_request_open()
		if not _warned_shut:
			_warned_shut = true
			push_warning(("%s: a hatchling release was held because the bay doors "
				+ "were still swinging. They are opening now and the next pass "
				+ "will fire. Warned once per body, not per attempt.") % name)
		return
	super()


# ─────────────────────────────────────────────
# THE BAY DISPLAY — two hideable meshes
# ─────────────────────────────────────────────
#
# DERIVED FROM THE LAUNCHER, never tracked. A saved-and-restored Vessel, a
# refit, a Vessel with no weapon at all and a Vessel mid-recharge all show the
# right thing without this script knowing any of those cases exist.
#
# THE FORWARD BAY GOES FIRST, which is build_vessel.gd's own naming order:
# CargoA sits at local z -0.42 and CargoB at +1.08, and -Z is forward. So with
# one round left the remaining drone is the REAR one.
#
# NOTE: the integration brief's code snippet has this the other way round
# (`cargo_a.visible = left >= 1`), which contradicts both its own comment and
# its own test 23. The test is the one that is right.
func _bay_display() -> void:
	if _cargo_a == null or _cargo_b == null:
		return   # warned once in _ready
	var left: int = _charges_left()
	_cargo_a.visible = left >= 2
	_cargo_b.visible = left >= 1


## How many canisters are in the bay right now. 0 while recharging, which is
## what makes a spent bay look spent — and 0 for a Vessel refitted with a gun,
## because it really is carrying nothing.
func _charges_left() -> int:
	var launcher = _bay_launcher()
	if launcher == null:
		return 0
	if launcher.infinite_ammo:
		return 2
	if launcher.is_reloading:
		return 0
	return clampi(launcher.magazine_current, 0, 2)
