extends "res://Character/characters/ai/mechanic.gd"

# ─────────────────────────────────────────────
# RECLAIMER — the squad's workshop on tracks.
#
# Low and tracked, with a boom arm carrying a welding head in the middle and a
# grinder drum across the front. It works among the infantry, in their team and
# not the armour's, following their orders at the back of their line. Two jobs:
#
#   RECLAIMS SQUADMATES. This is the Mechanic's brain, so it does everything
#   the Mechanic does, from the arm. It stands downed robots back up first,
#   then repairs the damaged, vehicles first. The hull parks beside the patient
#   and the boom reaches over.
#
#   RECLAIMS WRECKS. With nobody to fix, it drives its drum into an enemy
#   wreck and grinds it down. That is a five-to-ten-second channel, longer for
#   bigger frames, for the wreck's worth (Enemy.bits) in resources, paid at
#   extraction (CampaignManager.add_salvage). A squadmate going down stops the
#   grinding at once, and the wreck keeps its progress for later.
#
# Enemies it leaves to the squad unless they come close. Then it drops the
# wreck and backs off behind the squad, and the drum chews anything that gets
# in front of it.
#
# It drives like something on tracks: it turns on the spot when it has to turn
# far, and never slides sideways. The hull goes where the tracks take it; the
# boom turns to its work on its own.
# ─────────────────────────────────────────────

@export_group("Tracks")
## Turning on the spot, degrees a second.
@export var turn_rate_degrees: float = 110.0
## Further off its heading than this, it stops and turns before driving on.
@export var pivot_above_degrees: float = 35.0
@export var drive_accel: float = 5.0
@export var brake_decel: float = 8.0
## How hard it slows for the end of a path: gently, rolling up to the spot
## rather than stopping for an obstacle.
@export var arrival_decel: float = 3.0
## Where it is going to work (a patient, a wreck), it has to stop this close
## to the spot. arrival_radius is for everywhere else.
@export var work_arrival: float = 0.45
## Throttle open and hardly moving for this long: something is in the way that
## the path does not know about, and it steps round it.
@export var pinned_after: float = 0.5
## Centre to centre of the tracks, for how fast each one runs in a turn.
@export var track_width: float = 1.24
## Length of the top run the tread plates travel along.
@export var tread_run: float = 2.06
@export var hub_radius: float = 0.13

@export_group("Salvage")
## How far from its squad's line it will go for a wreck.
@export var salvage_radius: float = 25.0
@export var salvage_seconds_min: float = 5.0
@export var salvage_seconds_max: float = 10.0
## A wreck with a live enemy this close to it is left where it is.
@export var salvage_keep_clear: float = 14.0
## Centre of the hull to the front of the drum.
@export var drum_reach: float = 1.85
## How close the front of the drum has to be to the wreck to bite.
@export var grind_reach: float = 0.25
@export var drum_grind_rpm: float = 220.0
## How far a wreck sinks into the drum by the time it is gone.
@export var grind_sink: float = 0.55

@export_group("Close threats")
## Enemies nearer than this it reacts to. Further out it gets on with the job.
@export var close_threat_radius: float = 10.0
## A hostile this close to the front of the drum is chewed.
@export var drum_bite_range: float = 1.4
@export var drum_bite_cone_degrees: float = 55.0
@export var drum_damage_per_second: float = 30.0

@export_group("Arm")
## Shoulder to elbow.
@export var upper_arm_length: float = 1.05
## Elbow to the tip of the welding head, with the wrist straight.
@export var forearm_length: float = 1.2
## HOW FAST THE BOOM GETS THERE, which is the whole of the difference between
## this and the Mechanic at the same job.
##
## Measured at the old 180/200: the Mechanic has its welder in its hands and is
## putting health back 0.32s after it picks a patient up; this one took 2.15s,
## every single time, because the stick is jackknifed back over the boom when
## stowed and the elbow has 233 degrees to travel before the torch is anywhere
## near. It welds HARDER once it starts (20/s against 15/s) and still lost,
## because a repair crew spends its day starting.
##
## The other half of that 2.15s was driving: weld_reach was 1.1m in the scene,
## so a machine with a 2.25m boom still parked on top of its patient. It is
## 1.7m now and the torch still lands 0.16m off the weld point — a boom arm's
## entire point is not having to pull alongside. Together: 2.15s down to 1.08s,
## and the Reclaimer now finishes a patient faster than the Mechanic does.
@export var arm_yaw_rate_degrees: float = 340.0
@export var arm_joint_rate_degrees: float = 420.0
## Folded for the road: the boom angled up over the nose, the stick jackknifed
## back along the top of it, and the torch resting on the mast.
# ── WRECKED ───────────────────────────────────
# What a dead one looks like. See _collapse_pieces.
## How far the hull rolls onto the side it went over on, and drops at the nose.
@export var wreck_roll_degrees: float = 9.0
@export var wreck_nose_degrees: float = 4.0
## How far the whole hull settles, in metres.
@export var wreck_settle: float = 0.5
## Where the arm ends up: shoulder dropped, elbow and wrist hanging open, so
## the boom lies out in front instead of folded against the hull. NEGATIVE is
## down — _pose_arm turns these about +X, where a positive angle lifts the
## boom, and a raised boom is exactly what a working reclaimer looks like.
@export var wreck_shoulder_degrees: float = -30.0
@export var wreck_elbow_degrees: float = -34.0
@export var wreck_wrist_degrees: float = -40.0

@export var stow_shoulder_degrees: float = 15.0
@export var stow_elbow_degrees: float = 163.0
@export var stow_wrist_degrees: float = 92.0

@export_group("Mortar")
## How often it looks for something to shell.
@export var mortar_think: float = 0.5
## Metres of scatter on each round, so a barrage walks around a position rather
## than stacking every shell in one crater.
@export var mortar_scatter: float = 2.5
## No round is aimed within this of one of ours — the player, a squadmate, or a
## squadmate already down. Kept above scatter plus blast radius so a round that
## drifts to the edge of its scatter still cannot reach them.
@export var danger_close: float = 9.0
## How far off the launch line the tube can be and still fire. The boom slews
## round and the tube lays before anything leaves it.
@export var mortar_lay_degrees: float = 6.0
## The boom's firing pose: raised, the stick level, the tube out on the end of
## it where the welding head was. The mount lays the tube itself.
@export var mortar_shoulder_degrees: float = 50.0
@export var mortar_elbow_degrees: float = -50.0

@export_group("Parts")
@export var rig: Node3D
@export var arm_base: Node3D
@export var shoulder: Node3D
@export var elbow: Node3D
@export var wrist: Node3D
## The end of the torch: what the arm puts on the patient.
@export var weld_tip: Node3D
@export var drum: Node3D
@export var beacon: Node3D
@export var treads_left: Array[Node3D] = []
@export var treads_right: Array[Node3D] = []
@export var hubs_left: Array[Node3D] = []
@export var hubs_right: Array[Node3D] = []
## A SparkBurst at the front of the drum, fired while it grinds.
@export var grind_sparks: Node3D
@export var grind_loop: AudioStreamPlayer3D

## What it has ground out this deployment, for the lab and the playtest log.
var salvaged: int = 0
var wrecks_ground: int = 0

var _wreck: Enemy = null
var _grinding := false
var _grind_t := 0.0
var _grind_need := 0.0
var _grind_spark_t := 0.0
var _wreck_t := 0.0                # seconds spent getting to the current wreck
var _progress: Dictionary = {}     # wreck instance id -> seconds already ground
var _wreck_rest: Dictionary = {}   # wreck piece -> its transform before grinding
var _salvage_think := 0.0
var _close: Enemy = null           # the nearest hostile inside close_threat_radius
var _scan_t := 0.0
var _speed := 0.0                  # along the hull, m/s
var _turn := 0.0                   # rad/s the hull is turning, + is left
var _tread_l := 0.0
var _tread_r := 0.0
var _tread_rest_l: Array[float] = []
var _tread_rest_r: Array[float] = []
var _rig_rest: Transform3D
var _tilt := Vector3.ZERO          # pitch, 0, roll of the ground under it, smoothed
var _tilt_t := 0.0
var _bite_t := 0.0
var _biting := false
var _beacon_t := 0.0
var _nav_end := Vector3.INF        # where the current path ends
var _path_fresh := false           # the path is for the current order
var _last_pos := Vector3.ZERO
var _pinned_t := 0.0
var _ray: PhysicsRayQueryParameters3D
# Joint angles, radians. Kept here and posed through basis, never read back off
# the nodes: the arm folds past 90 degrees, and a node's rotation read back
# after its transform is set (a revive restoring pieces) comes out as a
# different set of angles for the same pose.
var _yaw := 0.0
var _sh := 0.0
var _el := 0.0
var _wr := 0.0
var _drum_turn := 0.0
var _reach_t := 0.0                # seconds the arm has been reaching for the patient

# The mortar, when one is fitted. See _tick_mortar.
var _mortar_mount: Node3D = null   # on the wrist, where the welding head was
var _mortar_target: Node3D = null
var _mortar_offset := Vector3.ZERO  # this round's scatter, off wherever the target is
var _mortar_aim := Vector3.INF      # where this round goes: the target plus the scatter
var _mortar_think_t := 0.0
var _mortar_cool := 0.0
var _mortar_kick := 0.0             # 1 on the round leaving, back to 0 as the tube settles
# Metres the tube jumps back down its own axis on each round, and how fast
# (fractions of it a second) it comes home. Plain consts: the scene has no
# reason to tune them, and an export here is one more default for an open
# editor to write into vehicle_reclaimer.tscn.
const MORTAR_KICK := 0.14
const MORTAR_KICK_RETURN := 4.0
# The tube at rest on the wrist: muzzle UP with the arm folded. Hung the other
# way it pointed into the hull when stowed, and swung through half a circle
# every time it came up to fire.
const MORTAR_REST := Basis(Vector3.RIGHT, PI)


func _ready() -> void:
	if rig != null:
		_rig_rest = rig.transform
	for t in treads_left:
		_tread_rest_l.append(t.position.z if t != null else 0.0)
	for t in treads_right:
		_tread_rest_r.append(t.position.z if t != null else 0.0)
	if arm_base == null or shoulder == null or elbow == null:
		push_warning("%s has no boom arm wired: it will weld without reaching." % name)
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.exclude = [get_rid()]
	_last_pos = global_position
	_sh = deg_to_rad(stow_shoulder_degrees)
	_el = deg_to_rad(stow_elbow_degrees)
	_wr = deg_to_rad(stow_wrist_degrees)
	_pose_arm()
	super()


# ─────────────────────────────────────────────
# THE ORDER OF THINGS
# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	# The Mechanic's loop first: squadmates, and keeping back from a close
	# threat. What is left of the tick goes on wrecks.
	super(delta)
	# Down, asleep or jammed: the same states the Mechanic stops welding in.
	# Ordinary states rather than faults, every frame, so no warning.
	if not alive or not frame_waited or ai_state == AIState.PASSIVE \
			or get_signal_state() == SignalState.EKILL:
		_drop_wreck(false)
		_mortar_target = null
		_mortar_aim = Vector3.INF
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = think_interval
		_close = _hostile_near(close_threat_radius)
	if _patient == null:
		_tick_salvage(delta)
	elif _wreck != null:
		_drop_wreck(false)   # a squadmate needs it; the wreck keeps its progress
	_tick_bite(delta)
	_tick_pinned(delta)
	_tick_rig(delta)
	# The mortar is the ARM's job and the hull never waits on it: the tracks
	# carry on grinding or following orders while the boom shells whatever the
	# squad has in its sights. Before _tick_arm, which poses to its target.
	_tick_mortar(delta)
	_tick_arm(delta)


# Vehicles do not take cover; the cover points in a level are sized for a robot
# on foot. Told to hold, it parks on the spot (Squad._parking_post).
func takes_cover() -> bool:
	return false


func enter_cover_seeking() -> void:
	change_soldier_state(SoldierState.NONE)


# It parks within arrival_radius of a spot rather than on it, and a slot check
# tighter than that re-orders it every tick.
func slot_tolerance(squad_tolerance: float) -> float:
	return maxf(squad_tolerance, arrival_radius)


# Grinding, the squad's orders wait, as they do for a patient: pulled off the
# wreck by every formation correction, it would never finish one.
func order_move_to(pos: Vector3, force: bool = false, keep_target: bool = false) -> void:
	if _wreck != null:
		_standing_order = pos
		_standing_force = force
		return   # carried out once it is off the wreck (_resume_orders)
	super(pos, force, keep_target)


# The Mechanic keeps behind its squad whenever there is shooting. This one only
# minds an enemy that is close; a firefight forty metres off is the squad's.
# In a squad told to hold as well, since it cannot take cover like the rest.
func _keeping_back() -> bool:
	if squad == null or not is_instance_valid(squad):
		return false   # no squad to keep behind
	return _live_threat() != null


# What it backs away from: the nearest enemy that is close, if any. Looked for
# on the think beat, and checked again here because the squad asks every frame.
func _live_threat() -> Node3D:
	if _close == null or not is_instance_valid(_close) or not _close.alive \
			or global_position.distance_to(_close.global_position) > close_threat_radius:
		return null   # nothing close, or it has gone down or moved off
	return _close


func is_salvaging() -> bool:
	return _grinding


# ─────────────────────────────────────────────
# SALVAGE
# ─────────────────────────────────────────────
func _tick_salvage(delta: float) -> void:
	if _keeping_back():
		_drop_wreck(true)
		return   # a live enemy close by: backing off comes first (_keep_back)
	_salvage_think -= delta
	if _salvage_think <= 0.0:
		_salvage_think = think_interval
		if _wreck != null and not _salvageable(_wreck):
			_drop_wreck(true)
		if _wreck == null:
			_take_wreck(_nearest_wreck())
	if _wreck == null:
		return   # nothing to grind: the squad's orders stand

	if _front_gap(_wreck) > grind_reach:
		_stop_grinding()
		_wreck_t += delta
		if _wreck_t > give_up_after:
			# Could not get the drum onto it. Leave it a while.
			_skip_until[_wreck.get_instance_id()] = _clock + retry_after * 2.0
			_drop_wreck(true)
			return
		var goal := _drive_at(_wreck)
		if movement_state != MovementState.MOVING or _walk_goal == Vector3.INF or _walk_goal.distance_to(goal) > 1.0:
			_walk_goal = goal
			move_to(goal)
		return   # on its way to it

	# The drum is on it: stop and grind.
	_wreck_t = 0.0
	if movement_state != MovementState.NONE:
		halt()
		_walk_goal = Vector3.INF
	if not _grinding:
		_start_grinding()
	_grind_t += delta
	_progress[_wreck.get_instance_id()] = _grind_t
	_sink_wreck(_grind_t / _grind_need, true)
	_grind_spark_t -= delta
	if _grind_spark_t <= 0.0:
		_grind_spark_t = 0.12
		if grind_sparks != null and grind_sparks.has_method("activate"):
			grind_sparks.activate()
	if _grind_t >= _grind_need:
		_finish_wreck()


# A wreck of the other side, near the squad, with no live enemy standing over
# it, nobody else already grinding it, and not one it recently gave up on.
func _salvageable(e: Enemy) -> bool:
	if e == null or not is_instance_valid(e) or e.is_queued_for_deletion():
		return false   # gone, or going
	if not e.downed or not _is_hostile(e):
		return false   # standing, destroyed, or one of ours: ours get welded, not ground
	if e.has_meta(&"reclaimed_by"):
		var claimed = e.get_meta(&"reclaimed_by")
		if is_instance_valid(claimed) and claimed != self:
			return false   # another Reclaimer has its drum in it
	if float(_skip_until.get(e.get_instance_id(), 0.0)) > _clock:
		return false   # gave up on it lately: left a while
	var home: Vector3 = squad.line_center() if squad != null and is_instance_valid(squad) else global_position
	if Vector2(e.global_position.x - home.x, e.global_position.z - home.z).length() > salvage_radius:
		return false   # too far from the squad to go for
	return _hostile_near(salvage_keep_clear, e.global_position) == null


func _nearest_wreck() -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if not _salvageable(e):
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _take_wreck(e: Enemy) -> void:
	_wreck = e
	_wreck_t = 0.0
	_wreck_rest.clear()
	if e == null:
		return   # no wreck worth going for: the squad's orders stand
	e.set_meta(&"reclaimed_by", self)
	_grind_t = float(_progress.get(e.get_instance_id(), 0.0))
	# Bigger frames take longer: a chaser five seconds, a rifle about six and
	# a half, a rover eight and a half.
	var size := clampf((float(e.max_health) - 40.0) / 200.0, 0.0, 1.0)
	_grind_need = lerpf(salvage_seconds_min, salvage_seconds_max, size)


# The nearest live hostile within `radius` of `from` (of itself, by default).
func _hostile_near(radius: float, from: Vector3 = Vector3.INF) -> Enemy:
	if ai_manager == null:
		return null   # no roster of robots to look through yet
	var at := global_position if from == Vector3.INF else from
	var best: Enemy = null
	var best_d := radius
	for ai in ai_manager.all_ai:
		if ai == null or not is_instance_valid(ai) or not (ai is Enemy):
			continue
		var e := ai as Enemy
		if not e.alive or not _is_hostile(e):
			continue
		var d := e.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = e
	return best


# Where to drive to get the drum on it: at the wreck itself, which lines the
# hull up on the way in, and _tick_nav stops it when the drum touches. Parked
# over a settled wreck or right beside one, there is no run-up; out to a spot
# the drum can come in from first.
func _drive_at(e: Enemy) -> Vector3:
	var box := _box_of(e)
	var centre := box.get_center()
	var flat := Vector2(centre.x - global_position.x, centre.z - global_position.z).length()
	var map := nav_agent.get_navigation_map()
	if flat >= _edge_along(box, global_position - centre) + drum_reach:
		return NavigationServer3D.map_get_closest_point(map, centre)
	var away := global_position - centre
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = -_hull_forward()
	away = away.normalized()
	return NavigationServer3D.map_get_closest_point(map,
		centre + away * (_edge_along(box, away) + drum_reach + 1.2))


# Front of the drum to the wreck, flat. Measured to its collider as it lies,
# not to the world box round it: a wreck lying across the diagonal has a box
# with empty corners, and the drum stopped in them, short of anything to grind.
func _front_gap(e: Enemy) -> float:
	var front := global_position + _hull_forward() * drum_reach
	var cs: CollisionShape3D = e._collision_shape if e._collision_shape != null else e._find_collision_shape()
	if cs == null or cs.shape == null:
		return _flat_gap(e.global_position)   # nothing to measure to: to its middle
	var local := cs.global_transform.affine_inverse() * front
	var box := e._shape_box(cs.shape)
	var near := cs.global_transform * local.clamp(box.position, box.end)
	return Vector2(near.x - front.x, near.z - front.z).length()


func _start_grinding() -> void:
	_grinding = true
	_grind_spark_t = 0.0
	if grind_loop != null and not grind_loop.playing:
		grind_loop.play()


func _stop_grinding() -> void:
	if not _grinding:
		return   # not grinding: nothing to stop
	_grinding = false
	if grind_loop != null:
		grind_loop.stop()


# Down into the drum as it goes, shaking while the drum is in it.
func _sink_wreck(done: float, shaking: bool) -> void:
	if _wreck == null or not is_instance_valid(_wreck):
		return   # no wreck, or it has gone
	for piece in _wreck.visible_pieces:
		if piece == null or not is_instance_valid(piece):
			continue
		if not _wreck_rest.has(piece):
			_wreck_rest[piece] = piece.transform
		var t: Transform3D = _wreck_rest[piece]
		t.origin.y -= grind_sink * clampf(done, 0.0, 1.0)
		if shaking:
			t.origin += Vector3(randf_range(-0.03, 0.03), randf_range(-0.02, 0.02), randf_range(-0.03, 0.03))
		piece.transform = t


func _finish_wreck() -> void:
	var e := _wreck
	var worth: int = maxi(0, e.bits)
	_stop_grinding()
	_progress.erase(e.get_instance_id())
	_wreck_rest.clear()
	_wreck = null
	if e.has_meta(&"reclaimed_by"):
		e.remove_meta(&"reclaimed_by")
	e.destroy()
	salvaged += worth
	wrecks_ground += 1
	if weld_done != null:
		weld_done.play()
	_pay(worth)
	_salvage_think = 0.0   # straight on to the next one
	_resume_orders()


# To the campaign, which holds it for the debrief. Only a Reclaimer on the
# player's side is paying anyone.
func _pay(amount: int) -> void:
	if not _is_player_side() or amount <= 0:
		return   # the enemy's own salvage, or a wreck worth nothing
	var campaign := get_tree().get_first_node_in_group("campaign")
	if campaign == null or not campaign.has_method("add_salvage"):
		push_warning("%s ground a wreck worth %d but found no campaign to pay." % [name, amount])
		return
	campaign.add_salvage(amount)


# Off the wreck. What was ground stays ground: the wreck is left sunk as far as
# the drum got it, and remembers how far for next time. `resume` goes back to
# the squad's orders; not when something else is taking over (a patient), and
# not when it has just gone down itself.
func _drop_wreck(resume: bool) -> void:
	_stop_grinding()
	if _wreck == null:
		return   # not on a wreck
	if is_instance_valid(_wreck):
		if _wreck.has_meta(&"reclaimed_by") and _wreck.get_meta(&"reclaimed_by") == self:
			_wreck.remove_meta(&"reclaimed_by")
		_sink_wreck(_grind_t / maxf(_grind_need, 0.01), false)
	_wreck = null
	_wreck_rest.clear()
	if resume:
		_resume_orders()


# ─────────────────────────────────────────────
# THE DRUM, ON ANYTHING TOO CLOSE
# ─────────────────────────────────────────────
func _tick_bite(delta: float) -> void:
	_bite_t -= delta
	if _bite_t > 0.0:
		return   # four bites a second
	_bite_t = 0.25
	_biting = false
	var e := _live_threat() as Enemy
	if e == null:
		return   # nothing close: nothing in front of the drum either
	var front := global_position + _hull_forward() * drum_reach
	var to := e.global_position - global_position
	to.y = 0.0
	if Vector2(e.global_position.x - front.x, e.global_position.z - front.z).length() > drum_bite_range:
		return   # close, but not at the drum
	if to.length_squared() < 0.0001 or rad_to_deg(_hull_forward().angle_to(to.normalized())) > drum_bite_cone_degrees:
		return   # beside or behind it
	_biting = true
	e.apply_damage(int(ceil(drum_damage_per_second * 0.25)), self)


# ─────────────────────────────────────────────
# TRACKS
# ─────────────────────────────────────────────
# A new order is a new path; until the agent has worked it out, the old one's
# end is not where it is going (see _tick_nav), and the old one being finished
# says nothing about the new one. Left standing, that went on until the agent
# next got a path query in, and nav queries are rationed across every robot:
# a frame without one and the new order read as finished short, and it stopped.
func move_to(pos: Vector3):
	_path_fresh = false
	_nav_finished = false
	super(pos)


# The agent counts the end of a path reached in 3D from the middle of the hull,
# and hands back a sidestep when it is not quite there. Here the end counts
# flat: within arrival_radius, or within work_arrival of a spot it is going to
# work from. And going to work, the job decides: the path is done when the
# drum is on the wreck, or the patient is in the arm's reach.
func _tick_nav(delta: float) -> void:
	var due := _nav_think_timer - delta
	super(delta)
	if _nav_think_timer > due + 0.0001:
		_path_fresh = true   # a query ran: the path is for what it was last told
		var path := nav_agent.get_current_navigation_path()
		_nav_end = path[path.size() - 1] if not path.is_empty() else Vector3.INF
	if _path_fresh and _nav_end != Vector3.INF:
		_nav_finished = _flat_gap(_nav_end) <= (work_arrival if _going_to_work() else arrival_radius)
	if _wreck != null and _front_gap(_wreck) <= grind_reach * 0.8:
		_nav_finished = true
	elif _patient != null and is_instance_valid(_patient) and _gap_to(_patient) <= weld_reach * 0.85:
		_nav_finished = true


func _going_to_work() -> bool:
	return _wreck != null or _patient != null


func _flat_gap(to: Vector3) -> float:
	return Vector2(to.x - global_position.x, to.z - global_position.z).length()


# Finished short of where it was sent is as near as it gets: the spot is off
# the navmesh, or the job stopped it early. Stop there. Otherwise it is stuck,
# and on tracks the base's sidestep is something it can do.
func _handle_path_blocked() -> void:
	if _nav_finished:
		movement_state = MovementState.NONE
		return   # as near as it gets: stop here
	super()


# Throttle open and hardly moving: up against something the path does not
# know about, most often a squadmate standing in the way (the one it has just
# stood back up, in front of its drum). The base notices after three seconds of
# pushing; this takes the sidestep after half of one.
func _tick_pinned(delta: float) -> void:
	var moved := global_position - _last_pos
	_last_pos = global_position
	if movement_state != MovementState.MOVING or _speed < 1.0:
		_pinned_t = 0.0
		return   # not driving, or only turning on the spot: nothing to be pinned against
	var fwd := _hull_forward()
	if Vector2(moved.x, moved.z).dot(Vector2(fwd.x, fwd.z)) >= _speed * delta * 0.25:
		_pinned_t = 0.0
		return   # getting somewhere
	_pinned_t += delta
	if _pinned_t >= pinned_after:
		_pinned_t = 0.0
		_speed = 0.0
		_handle_path_blocked()


# On the spot when it has to turn far, otherwise steering as it goes. Never
# sideways: the velocity is always along the hull.
func move_along_nav(delta):
	var fwd := _hull_forward()
	var want := _nav_dir
	want.y = 0.0
	var target_speed := 0.0
	var turn_to := 0.0
	if want.length() >= 0.15:
		var err := fwd.signed_angle_to(want.normalized(), Vector3.UP)
		turn_to = clampf(err * 3.0, -1.0, 1.0) * deg_to_rad(turn_rate_degrees)
		if absf(err) < deg_to_rad(pivot_above_degrees):
			target_speed = move_speed * clampf(cos(err), 0.0, 1.0)
			# Off the throttle for the end of the path, rather than arriving
			# flat out and rolling on past it.
			if _path_fresh and _nav_end != Vector3.INF:
				var left := _flat_gap(_nav_end) - (work_arrival if _going_to_work() else arrival_radius) * 0.5
				target_speed = minf(target_speed, maxf(sqrt(2.0 * arrival_decel * maxf(left, 0.0)), 0.8))
	_turn = turn_to
	rotation.y += _turn * delta
	var speeding_up := target_speed > _speed
	_speed = move_toward(_speed, target_speed, (drive_accel if speeding_up else brake_decel) * delta)
	fwd = _hull_forward()
	velocity.x = fwd.x * _speed
	velocity.z = fwd.z * _speed
	if _speed > 0.3:
		_last_move_dir = fwd


func _hull_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


# The hull points where the tracks take it. The boom turns to its work on its
# own (_tick_arm), so nothing here turns the body.
func _update_facing(_delta: float) -> void:
	pass


# ─────────────────────────────────────────────
# RIG: treads, hubs, drum, beacon, lean
# ─────────────────────────────────────────────
func _tick_rig(delta: float) -> void:
	if movement_state == MovementState.NONE:
		# Stopped, or coasting down: the speed is whatever the body is doing.
		var fwd := _hull_forward()
		_speed = Vector2(velocity.x, velocity.z).dot(Vector2(fwd.x, fwd.z))
		_turn = 0.0
	# Each track runs at the hull's speed, plus or minus the turn. Turning on
	# the spot, one runs forward and the other back.
	var along := _speed * delta
	var twist := _turn * track_width * 0.5 * delta
	_tread_l += along - twist
	_tread_r += along + twist
	_run_treads(treads_left, _tread_rest_l, _tread_l)
	_run_treads(treads_right, _tread_rest_r, _tread_r)
	for h in hubs_left:
		if h != null:
			h.basis = Basis(Vector3.RIGHT, wrapf(-_tread_l / hub_radius, -PI, PI))   # the top rolls forward, to -Z
	for h in hubs_right:
		if h != null:
			h.basis = Basis(Vector3.RIGHT, wrapf(-_tread_r / hub_radius, -PI, PI))
	if drum != null and (_grinding or _biting):
		_drum_turn = wrapf(_drum_turn - drum_grind_rpm * TAU / 60.0 * delta, -PI, PI)
		drum.basis = Basis(Vector3.RIGHT, _drum_turn)
	if beacon != null:
		# Steady while it drives about; flashing while it works.
		_beacon_t += delta
		beacon.visible = not (_welding or _grinding) or fmod(_beacon_t, 0.6) < 0.35
	if rig == null:
		return   # nothing drawn to lean
	_tilt_t -= delta
	var moving := absf(_speed) > 0.05 or absf(_turn) > 0.01
	if _tilt_t <= 0.0 and moving and lod_scale() <= 2.0:
		_tilt_t = 0.1
		_tilt = _tilt.lerp(_ground_tilt(), 0.6)
	var pose := _rig_rest
	pose.basis = Basis.from_euler(_tilt) * pose.basis
	if _grinding:
		pose.origin += Vector3(randf_range(-0.012, 0.012), randf_range(-0.008, 0.008), randf_range(-0.012, 0.012))
	rig.transform = pose


# The top run of a track travels forward over the hull as it drives.
func _run_treads(plates: Array[Node3D], rest: Array[float], run: float) -> void:
	var half := tread_run * 0.5
	for i in plates.size():
		var p := plates[i]
		if p != null and i < rest.size():
			p.position.z = wrapf(rest[i] - run, -half, half)


# Pitch and roll of the ground under the tracks, from four rays.
func _ground_tilt() -> Vector3:
	if not is_inside_tree():
		return Vector3.ZERO   # not in a world: nothing to lean on
	var space := get_world_3d().direct_space_state
	var hull := global_transform.basis
	var h: Array[float] = []
	for off in [Vector3(0, 0, -1.0), Vector3(0, 0, 1.0), Vector3(-0.62, 0, 0), Vector3(0.62, 0, 0)]:
		var at: Vector3 = global_position + hull * off
		_ray.from = at + Vector3.UP * 0.8
		_ray.to = at + Vector3.DOWN * 1.4
		var hit := space.intersect_ray(_ray)
		h.append((hit.position as Vector3).y if not hit.is_empty() else global_position.y - 0.42)
	var pitch := atan2(h[0] - h[1], 2.0)
	var roll := atan2(h[3] - h[2], 1.24)
	return Vector3(clampf(pitch, -0.35, 0.35), 0.0, clampf(roll, -0.3, 0.3))


# ─────────────────────────────────────────────
# ARM: folded over the hull, or reaching onto the patient
# ─────────────────────────────────────────────
func _tick_arm(delta: float) -> void:
	if arm_base == null or shoulder == null or elbow == null:
		return   # warned about in _ready
	var yaw := 0.0
	var want_sh := deg_to_rad(stow_shoulder_degrees)
	var want_el := deg_to_rad(stow_elbow_degrees)
	var want_wr := deg_to_rad(stow_wrist_degrees)
	if _welding and is_instance_valid(_patient):
		var target := _weld_point(_patient)
		var local := arm_base.get_parent_node_3d().global_transform.affine_inverse() * target - arm_base.position
		yaw = atan2(-local.x, -local.z)
		# Two joints in the arm's own plane, elbow up.
		var d := target - shoulder.global_position
		var h := Vector2(d.x, d.z).length()
		var l1 := upper_arm_length
		var l2 := forearm_length
		var dist := clampf(sqrt(h * h + d.y * d.y), 0.4, l1 + l2 - 0.02)
		var bend := acos(clampf((dist * dist - l1 * l1 - l2 * l2) / (2.0 * l1 * l2), -1.0, 1.0))
		want_sh = atan2(d.y, h) + atan2(l2 * sin(bend), l1 + l2 * cos(bend))
		want_el = -bend
		want_wr = 0.0
		_reach_t += delta
	elif _mortar_aim != Vector3.INF:
		# Up, and round to the bearing. The tube rides the end of the boom and
		# _lay_tube points it down the launch line once the arm is there.
		var local := arm_base.get_parent_node_3d().global_transform.affine_inverse() * _mortar_aim - arm_base.position
		yaw = atan2(-local.x, -local.z)
		want_sh = deg_to_rad(mortar_shoulder_degrees)
		want_el = deg_to_rad(mortar_elbow_degrees)
		want_wr = 0.0
		_reach_t = 0.0
	else:
		_reach_t = 0.0
	# The turntable takes the short way round. The joints do not: folded, the
	# stick lies back over the boom, and it unfolds up and over the top, the
	# way it would, rather than through the boom.
	_yaw = rotate_toward(_yaw, yaw, deg_to_rad(arm_yaw_rate_degrees) * delta)
	var rate := deg_to_rad(arm_joint_rate_degrees) * delta
	_sh = move_toward(_sh, want_sh, rate)
	_el = move_toward(_el, want_el, rate)
	_wr = move_toward(_wr, want_wr, rate)
	_pose_arm()
	_lay_tube(delta)


func _pose_arm() -> void:
	if arm_base != null:
		arm_base.basis = Basis(Vector3.UP, _yaw)
	if shoulder != null:
		shoulder.basis = Basis(Vector3.RIGHT, _sh)
	if elbow != null:
		elbow.basis = Basis(Vector3.RIGHT, _el)
	if wrist != null:
		wrist.basis = Basis(Vector3.RIGHT, _wr)


# Nothing is welded until the torch is on the patient: the boom unfolds and
# swings round first, which takes it about half a second. Stretched as far as
# it goes and still short, it welds anyway rather than stand there — and the
# wait before it gives up came down with the arm rate, since three seconds of
# a fast arm standing still is just the old bug wearing a different hat.
func _tool_on(p: Enemy) -> bool:
	if weld_tip == null or shoulder == null:
		return true   # nothing to reach with: it welds from where it stands
	if weld_tip.global_position.distance_to(_weld_point(p)) <= 0.45:
		return true
	return _reach_t > 1.5


# The point of the patient nearest the boom's shoulder, a little up off the
# ground: where the torch goes. Welding ITSELF, that would be a target inside
# its own shoulder, so the torch goes to the engine deck behind the mast — the
# part of itself an arm this size can actually reach.
func _weld_point(p: Enemy) -> Vector3:
	if p == self:
		return global_transform * Vector3(0.0, 0.46, 0.7)
	var box := _box_of(p)
	var s := shoulder.global_position
	var q := Vector3(clampf(s.x, box.position.x, box.end.x), clampf(s.y, box.position.y, box.end.y),
		clampf(s.z, box.position.z, box.end.z))
	return q + Vector3.UP * 0.1


# ─────────────────────────────────────────────
# THE MORTAR
#
# A 60mm tube in place of the welding head, on the end of the boom. It shells
# what its SIDE can see, not what it can: every friendly robot's current target
# that it has a line of sight to, this one's included. So it can sit behind a
# wall while the squad does the spotting — which is the whole point of a mortar,
# and why this reads the squad rather than its own eyes.
#
# Of what is spotted and in range, it takes the tightest knot of them, and never
# one within danger_close of anyone on its own side. Each round is scattered a
# little so a barrage walks around a position instead of stacking in a crater.
#
# Everything here is the arm's. The hull goes on grinding wrecks and taking
# orders; the Mechanic's welding brain is simply switched off (_choose_patient).
# ─────────────────────────────────────────────

# Fitted at spawn, BEFORE the body enters the tree — so the mount is made here,
# on demand, rather than in _ready. The arm's node references are resolved by
# instantiate(), so the wrist is already there to hang it on.
func equip_weapon_scene(scene: PackedScene) -> void:
	if weapon_mount == null and wrist != null:
		_mortar_mount = Node3D.new()
		_mortar_mount.name = "MortarMount"
		_mortar_mount.basis = MORTAR_REST
		wrist.add_child(_mortar_mount)
		weapon_mount = _mortar_mount
	super(scene)
	_show_welder(weapon == null)


# The welding head and torch go when the mortar takes their place.
func _show_welder(on: bool) -> void:
	if wrist == null:
		return   # no arm wired: warned about in _ready
	for part in ["Head", "Torch"]:
		var n := wrist.get_node_or_null(part) as Node3D
		if n != null:
			n.visible = on


# ARMED, IT DOES NOT WELD: there is nothing on the end of the boom to repair
# anyone with. Leaving the patient empty drops the Mechanic's loop straight
# through to _keep_back, so it still keeps behind its squad in a fight.
func _choose_patient() -> void:
	if weapon != null:
		_set_patient(null)
		return
	super()


func _tick_mortar(delta: float) -> void:
	if weapon == null:
		return   # a welder frame: nothing to fire
	_mortar_cool = maxf(0.0, _mortar_cool - delta)
	# The target can die or leave between thinks; stand the tube down at once
	# rather than lob one more round at a wreck.
	if _mortar_target != null and (not is_instance_valid(_mortar_target) \
			or not _mortar_target.get("alive")):
		_mortar_target = null
	_mortar_think_t -= delta
	if _mortar_think_t <= 0.0:
		_mortar_think_t = mortar_think
		var picked := _pick_mortar_target()
		# A fresh spot in the scatter for a new target, and for the same one if
		# the old spot has come within danger close of a friendly: kept, the
		# tube would hold on it for as long as the target stayed picked.
		if picked != _mortar_target or (picked != null and _danger_close(picked.global_position + _mortar_offset)):
			_mortar_target = picked
			_mortar_offset = _scatter()
	# Laid on where the target IS rather than where it was when the last round
	# went: the spotters keep calling it, and the boom follows between rounds.
	_mortar_aim = _mortar_target.global_position + _mortar_offset if _mortar_target != null else Vector3.INF
	if _mortar_aim == Vector3.INF:
		return   # nothing spotted in range, or nothing safe to fire at
	if _mortar_cool > 0.0 or not weapon.can_fire() or not _laid_on():
		return   # between rounds, reloading, or still laying the tube
	if _danger_close(_mortar_aim):
		return   # a friendly has walked in since the think: held, re-scattered on the next
	weapon.fire(_mortar_aim)
	_mortar_cool = weapon.fire_cooldown
	_mortar_kick = 1.0
	_mortar_offset = _scatter()   # the next round goes somewhere else in the scatter


# What this robot's side currently has in its sights. Not a radar: it is what
# the squad is actually looking at, which is also what a mortar crew would be
# told to hit.
func _spotted() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var f := n as Enemy
		if f == null or not is_instance_valid(f) or not f.alive:
			continue
		if _is_hostile(f):
			continue   # theirs, spotting for the other side
		var t = f.combat_target
		if t == null or not is_instance_valid(t) or not f._has_los:
			continue
		if not t.get("alive") or not _is_hostile(t):
			continue
		if not out.has(t):
			out.append(t)
	return out


# In range, clear of our own, and the biggest knot of them.
func _pick_mortar_target() -> Node3D:
	var lo: float = weapon.min_effective_range
	var hi: float = weapon.max_effective_range
	var blast: float = maxf(float(weapon.get("blast_radius_override")), 2.5)
	var spotted := _spotted()
	var best: Node3D = null
	var best_score := -INF
	for t in spotted:
		var d := Vector2(t.global_position.x - global_position.x,
			t.global_position.z - global_position.z).length()
		if d < lo or d > hi:
			continue   # inside the minimum, or past what the tube can reach
		if _danger_close(t.global_position):
			continue   # one of ours is too close to it to shell
		var crowd := 0
		for o in spotted:
			if o.global_position.distance_to(t.global_position) <= blast:
				crowd += 1
		var score := float(crowd) * 100.0 - d * 0.1
		if score > best_score:
			best_score = score
			best = t
	return best


# Anyone on our side within danger_close of `at` — the player, a squadmate, or
# a squadmate already down, who is exactly the last thing to shell.
func _danger_close(at: Vector3) -> bool:
	var r2 := danger_close * danger_close
	for n in get_tree().get_nodes_in_group("enemies"):
		var f := n as Enemy
		if f == null or not is_instance_valid(f) or f == self:
			continue
		if not f.alive and not f.downed:
			continue   # destroyed: nothing left to hurt
		if _is_hostile(f):
			continue
		if f.global_position.distance_squared_to(at) < r2:
			return true
	if player != null and is_instance_valid(player) and not _is_hostile(player) \
			and player.global_position.distance_squared_to(at) < r2:
		return true
	return false


func _scatter() -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * mortar_scatter   # sqrt: even over the disc, not bunched at the middle
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


# Tube down the launch line once the boom is up; eased there, so it visibly
# lays rather than snapping. Stood down to the mount's rest with no target.
func _lay_tube(delta: float) -> void:
	if _mortar_mount == null or weapon == null:
		return   # a welder frame: no tube to lay
	# The kick: back down its own axis on each round, and eased home again.
	_mortar_kick = move_toward(_mortar_kick, 0.0, MORTAR_KICK_RETURN * delta)
	_mortar_mount.position = _mortar_mount.basis.z * (_mortar_kick * MORTAR_KICK)
	var ease := clampf(delta * 6.0, 0.0, 1.0)
	if _mortar_aim == Vector3.INF:
		# Orthonormalized first: laid through global_basis, the mount picks up a
		# hair of scale from the joints above it, and slerp will not take a
		# basis that is not a pure rotation (it errors, every frame).
		_mortar_mount.basis = _mortar_mount.basis.orthonormalized().slerp(MORTAR_REST, ease)
		return   # nothing to lay on: settling back to rest
	var want := _launch_dir()
	var up := Vector3.UP if absf(want.y) < 0.995 else Vector3.FORWARD
	var from_q := _mortar_mount.global_basis.orthonormalized().get_rotation_quaternion()
	var to_q := Basis.looking_at(want, up).get_rotation_quaternion()
	_mortar_mount.global_basis = Basis(from_q.slerp(to_q, ease))


func _launch_dir() -> Vector3:
	var muzzle: Vector3 = weapon.muzzle_origin.global_position
	return weapon.launch_velocity(muzzle, _mortar_aim).normalized()


# The tube is down the launch line, near enough. Nothing leaves it before.
func _laid_on() -> bool:
	if _mortar_mount == null or _mortar_aim == Vector3.INF:
		return false
	var have := -_mortar_mount.global_basis.z.normalized()
	return rad_to_deg(have.angle_to(_launch_dir())) <= mortar_lay_degrees


# ─────────────────────────────────────────────
# KNOCKED OUT
# ─────────────────────────────────────────────
# Tracks stay on the ground: a vehicle does not fall over like a robot on its
# feet. The hull settles, recorded in _piece_rest so the base revive() puts it
# back, and the drum and the beacon stop. The boom slumps; brought back, it
# folds itself up again from wherever it fell (_tick_arm).
func _collapse_pieces() -> void:
	# DEAD WEIGHT, NOT PARKED.
	#
	# The old wreck was the live model six centimetres lower with the arm
	# folded — which is what a reclaimer between jobs looks like, so a dead one
	# read as one waiting. It cannot sink its way out of that either: it is a
	# tracked hull and a boom, and half of it would still be standing. So the
	# ARM gives up. Held up is the whole tell that something is running; an arm
	# that has dropped out of its fold and is lying on the ground in front of
	# the hull cannot be read any other way.
	_stop_grinding()
	var over := 1.0 if randf() < 0.5 else -1.0
	if rig != null:
		if not _piece_rest.has(rig):
			_piece_rest[rig] = rig.transform
		var pose := _rig_rest
		pose.origin.y -= wreck_settle
		pose.basis = Basis.from_euler(Vector3(deg_to_rad(-wreck_nose_degrees), 0.0,
			deg_to_rad(wreck_roll_degrees * over + randf_range(-2.0, 2.0)))) * pose.basis
		rig.transform = pose
	# Swung off wherever it was working, then dropped: shoulder down, elbow and
	# wrist hanging open instead of tucked into the stow fold.
	_yaw += deg_to_rad(randf_range(40.0, 110.0)) * (1.0 if randf() < 0.5 else -1.0)
	_sh = deg_to_rad(wreck_shoulder_degrees)
	_el = deg_to_rad(wreck_elbow_degrees)
	_wr = deg_to_rad(wreck_wrist_degrees)
	_pose_arm()
	if beacon != null:
		beacon.visible = false
