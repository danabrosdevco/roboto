extends HUDWeapon
class_name PlayerClusterLauncher

# ─────────────────────────────────────────────
# CLUSTER LAUNCHER, in the player's hands.
#
# Extends HUDWeapon rather than PlayerEquipment, because it is a WEAPON: a
# six-round drum with a magazine, a reload, iron sights and recoil, all of
# which the template already does. The rocket is equipment — two shots, a
# decision, then it goes away. This is something you carry and work with.
#
# Only _fire_shot() is overridden. The template's comment above it says exactly
# what that means: the cooldown, the empty click and the ammo decrement happen
# in PlayerWeapon.try_fire(), and this is only what leaves the barrel. So the
# shell replaces the hitscan and nothing else changes.
#
# IT ARCS, AND THAT IS THE WEAPON. The shell leaves at launch_speed along the
# camera and falls the whole way, so at any useful distance you are holding
# over. The ladder on the rear sight exists to say so before the player has
# fired it. A flat-shooting version of this would just be a worse rifle; the
# arc is what lets it reach behind cover, and what makes a miss land somewhere
# rather than nowhere.
# ─────────────────────────────────────────────

## The carrier round. Without it the gun clicks, kicks and produces nothing, so
## it says so rather than failing quietly.
@export var shell_scene: PackedScene
## Muzzle velocity, and the number the SIGHT IS CUT FOR. The ladder's detents
## are solved from this and gravity — change it and every range mark on the
## rear leaf becomes a lie. cluster_launcher_model.tscn carries the table.
@export var launch_speed: float = 55.0
## Kept at zero. Elevation comes from the GUN being pitched nose-up by the ADS
## pose, which is how a real launcher does it; a separate upward nudge here
## would add angle the sight knows nothing about and break the 25m zero.
@export var launch_lift: float = 0.0
## How far in front of the eye the shell appears. Far enough to clear the
## player's own collider — a round spawned inside it is shoved sideways by the
## physics server before it has any velocity of its own.
@export var spawn_forward: float = 0.9
@export var spawn_drop: float = 0.12
## What the playtest log files the shell AND its bomblets under. Without it the
## bomblets score as Frag, because the round they are built from is the hand
## grenade's — the same trap ai_weapon_grenade_launcher.gd documents.
@export var analytics_label: String = "Cluster Launcher"


func _fire_shot() -> void:
	# A ROUND LEAVES AND THE CYLINDER TURNS, before anything else and before the
	# early returns below — the shot has happened either way and the template
	# decrements `loaded` regardless. See _spend_chamber.
	_spend_chamber()
	# The kick is the template's, not a copy of it: see HUDWeapon.arm_recoil().
	arm_recoil()

	if cam == null or tracer_origin == null:
		push_warning("PlayerClusterLauncher '%s' has no camera or muzzle — the trigger works and nothing is launched." % name)
		return
	if shell_scene == null:
		push_warning("PlayerClusterLauncher '%s' has no shell_scene — it fires, kicks, makes noise, and nothing comes out." % name)
		return

	# ALONG THE BORE, NOT THE CAMERA. This is the whole reason the sight works:
	# the ADS pose pitches the gun nose-up by 3.99 degrees, which is the
	# elevation that puts a 42 m/s shell on the ground at 25m — the range the
	# rear leaf's bottom detent is cut for. Launching down the camera's forward
	# instead would throw the round flat and make every mark on that ladder
	# decorative. Same axis the hitscan weapons trace down, for the same reason
	# (hud_weapon_template.gd's _fire_shot).
	var bore := tracer_origin.global_transform.basis.x.normalized()
	var origin := cam.global_position + bore * spawn_forward + Vector3.DOWN * spawn_drop

	var shell := shell_scene.instantiate()
	# setup() BEFORE the tree. The blast reads its owner on the frame it is
	# added, so a shell that entered first credited its kills to nobody and
	# skipped the friendly-fire multiplier — the bug ai_grenade_projectile.gd
	# already carries a comment about.
	if shell.has_method("setup"):
		shell.setup(player)
	if "analytics_label" in shell:
		shell.analytics_label = analytics_label
	level_node().add_child(shell)
	shell.global_position = origin

	if shell is RigidBody3D:
		var body := shell as RigidBody3D
		# The arc is meant to be predictable, so the round carries no drag —
		# the project default would pull it short of wherever the player
		# learned to hold, and a launcher you cannot learn is a random number.
		body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		body.linear_damp = 0.0
		body.linear_velocity = bore * launch_speed + Vector3.UP * launch_lift
		body.angular_velocity = Vector3(
			randf_range(-5.0, 5.0), randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))
		# A round must never collide with whoever fired it. It spawns less than
		# a metre from the player's own collider and at this speed one bad
		# physics tick puts it inside.
		if player is PhysicsBody3D:
			body.add_collision_exception_with(player)

	if rifle_stream_player != null:
		_WeaponAudio.stage(rifle_stream_player)
		rifle_stream_player.play()
	if muzzle_flash != null:
		muzzle_flash.play_flash()
	# You are still giving away where you are, same as any other weapon.
	if player != null and player.has_method("emit_noise"):
		player.emit_noise(StimulusManager.StimulusType.GUNSHOT_HEARD, noise_radius)
	request_status.emit()


# ─────────────────────────────────────────────
# RELOADING A DRUM, ONE ROUND AT A TIME.
#
# The model is a real six-chamber revolver: ChamberA to ChamberF ring the barrel
# axis at radius 0.277, centred on the Spindle at y -0.06, z -0.277, with a Crank
# standing off the face. None of that was built for this, which is exactly why
# the reload should use it — the gun already tells you how it works, and the
# reload is the one time the player gets to watch it do so.
#
# WHAT IT DOES: the cylinder swings out of the frame, a round goes into each
# EMPTY chamber one at a time while the drum indexes round, and the cylinder
# snaps shut. Come back with four of six and you load two, not six: topping up is
# the whole reason a revolver reload is interesting, and six detents regardless
# of what you had left is just a wheel spinning.
#
# AND THE ROUNDS ARE REAL. Six of them, one per chamber, parented to the cylinder
# so they index with it, each visible exactly when its chamber is loaded. That
# costs nothing and means the drum face now tells you how many you have left
# without the HUD — which is the thing a revolver is for.
# ─────────────────────────────────────────────

## The round that goes in the chambers. Its own model, sized off the chamber bore
## rather than borrowed from the projectile the gun fires — cluster_shell.tscn is
## a thing in flight with a fuse and a trail, not a round sitting in a hole.
const ROUND_MODEL := preload("res://Character/weapon/models/cluster_round_model.tscn")

## Everything that turns with the cylinder, gathered under one node at load so a
## single transform drives the drum, the chambers, the crank and the rounds
## together. Posing them separately drifts them apart the moment anything is
## added, and the rounds have to ride exactly with the chambers.
const CYLINDER_PARTS: Array[String] = ["Drum", "Spindle", "Crank",
	"ChamberA", "ChamberB", "ChamberC", "ChamberD", "ChamberE", "ChamberF"]
const CHAMBERS: Array[String] = ["ChamberA", "ChamberB", "ChamberC",
	"ChamberD", "ChamberE", "ChamberF"]
const CYLINDER := "Cylinder"

## THE BARREL GOES WITH THE CYLINDER. Everything forward of the drum — barrel,
## muzzle ring, foregrip and front sight — tips away as one piece with it, which
## makes this a break-action rather than a revolver with a crane. The alternative
## was what it did before: the cylinder dropped out of the frame and left the
## barrel hanging in the air over nothing, attached to a breech it no longer met.
##
## Two nested groups, because the two movements are different. The CRANE tips;
## the CYLINDER inside it indexes. Put the barrel in one group with the chambers
## and it would spin a sixth of a turn with every round loaded.
const CRANE := "Crane"
const CRANE_PARTS: Array[String] = ["Barrel", "MuzzleRing", "Foregrip",
	"ForeMount", "FrontRiser", "FrontSight"]

## The axis the chambers ring, read straight off cluster_launcher_model.tscn.
const AXIS := Vector3(1, 0, 0)
const HUB := Vector3(0.0, -0.06, -0.277)
## One chamber's worth of turn.
const DETENT := 60.0

## HOW THE BARREL AND CYLINDER LEAVE THE FRAME.
##
## A hinge now, not a slide: the assembly breaks open about a pin at the front of
## the frame, muzzle down, which carries the drum up and back and presents its
## face to the player. A negative turn about Z drops the muzzle.
##
## OLD NOTE, still true of the cylinder on its own:
##
## Mostly a translation with a tilt on the end of it, not a big rotation. A real
## crane hinges about an axis PARALLEL to the bore, which here is the same axis
## the chambers index about — so a large swing adds itself to the indexing and
## the drum appears to spin extra while it opens. The first attempt rotated 62
## degrees about Y and took the drum out of shot altogether.
##
## Down and a little forward, so the face stays square to the eye the whole time
## it is open. The face is the entire point: it is where the rounds go in and it
## is how the player counts them.
const SWING_PIVOT := Vector3(2.05, -0.30, 0.0)
const SWING_AXIS := Vector3(0, 0, 1)
const SWING_OFFSET := Vector3(0.0, -0.22, -0.14)
const SWING_TILT := -17.0

## Where a round waits before it goes in, as an offset from its chamber along the
## bore. Negative X is out of the back of the drum, which is the face you load.
const ROUND_OUT := Vector3(-1.15, 0.0, 0.0)
## End for end, so the round lies head-down-the-bore. See _build_rig.
const ROUND_FLIP := Transform3D(Basis(Vector3(1, 0, 0), PI), Vector3.ZERO)

var _rounds: Array[Node3D] = []
var _rig_built: bool = false
## How many rounds this reload is putting in. Captured when it starts, because
## `loaded` does not move until the reload finishes.
## WHICH CHAMBERS HOLD A ROUND, and the only source of truth about it.
##
## A count is not enough once the cylinder turns. Fire three and the drum has
## moved three detents, so "the first `loaded` chambers" stops describing where
## anything is — the rounds that are left are wherever the cylinder has carried
## them, and the empty ones have to be refilled in the order they come back past
## the loading face.
var _full: Array[bool] = [false, false, false, false, false, false]
## How far the cylinder has turned from rest, in whole chambers. Never reset:
## this is the drum's actual position and it persists between shots.
var _turned: int = 0
## The empty chambers this reload is filling, in the order it will fill them.
var _fill_order: Array[int] = []
## How many rounds this reload is putting in. Captured when it starts, because
## `loaded` does not move until the reload finishes.
var _to_load: int = 0

## The share of reload_time that is getting the cylinder out and back rather than
## feeding rounds — paid whether you are loading one or six.
const CRANE_SHARE := 0.34
## THE WORKING POSE, PROBED RATHER THAN GUESSED — see the note in
## player_bolt_rifle.gd. reload_position drops the launcher far enough that the
## drum leaves the bottom of the frame, and the drum IS this reload: six chambers
## turning past the barrel is the whole idea, and it has to be face-on to read.
## This holds it up and rolled over so all six are in shot at once.
const WORK_POS := Vector3(-1.7, -0.20, 0.48)
const WORK_ROT := Vector3(34.0, 16.0, -2.0)


func _ready() -> void:
	if viewmodel == null:
		viewmodel = weapon_model
	_build_rig()


func _on_initialize() -> void:
	super()
	_build_rig()
	# SYNC AFTER super(), not before. _ready builds the rig the moment the scene
	# enters the tree, when `loaded` is still 0 — so every chamber is marked empty.
	# super() is what fills the magazine, and _build_rig above early-returns because
	# the rig already exists, so without this the launcher is carried into the
	# mission showing six empty holes.
	#
	# That also hid the rotation: an empty six-chamber drum turned by exactly one
	# sixth is indistinguishable from one that has not moved. The rounds are what
	# make the turn visible.
	_sync_full()
	_settle()


## Gather the turning parts under one node and hang a round in every chamber.
##
## The cylinder parts are siblings at the model root, so this reparents them;
## their local transforms are already relative to that root and the group sits at
## the origin, so nothing moves in the process.
## Gather the turning parts under one node and hang a round in every chamber.
##
## The cylinder parts are siblings at the model root, so this reparents them;
## their local transforms are already relative to that root and the group sits at
## the origin, so nothing moves in the process.
func _build_rig() -> void:
	if _rig_built or viewmodel == null:
		return
	var crane := viewmodel.get_node_or_null(NodePath(CRANE)) as Node3D
	if crane == null:
		crane = Node3D.new()
		crane.name = CRANE
		viewmodel.add_child(crane)
		_gather(viewmodel, crane, CRANE_PARTS)
	var group := crane.get_node_or_null(NodePath(CYLINDER)) as Node3D
	if group == null:
		group = Node3D.new()
		group.name = CYLINDER
		crane.add_child(group)
		_gather(viewmodel, group, CYLINDER_PARTS)
	_rounds.clear()
	for i in CHAMBERS.size():
		var chamber := group.get_node_or_null(NodePath(CHAMBERS[i])) as Node3D
		if chamber == null:
			continue
		var round_node: Node3D = ROUND_MODEL.instantiate()
		round_node.name = "Round%d" % i
		group.add_child(round_node)
		# The chamber's own basis lies the round down the bore and its origin puts
		# it in that chamber, both straight off the model — but FLIPPED END FOR
		# END. A CylinderMesh builds along +Y and the chamber basis maps +Y to -X,
		# so an unflipped round goes in nose-first out of the back of the drum:
		# head to the loading face, brass rim pointing at the barrel. The half
		# turn puts the head down the bore where it belongs and leaves the rim at
		# the face, which is also the part that should be visible when the chamber
		# is full.
		round_node.transform = chamber.transform * ROUND_FLIP
		_rounds.append(round_node)
	_rig_built = true
	_sync_full()
	_settle()


## ─────────────────────────────────────────────
# FIRING TAKES A ROUND OUT AND TURNS THE DRUM.
#
# This is the half of a revolver that the player sees far more often than the
# reload: six shots, six rounds visibly gone, the cylinder a detent further round
# each time. Without it the drum sat full and still while the ammo counter went
# down on its own, which is the sort of thing that reads as the gun being a
# picture of a gun.
#
# Runs BEFORE the shell is spawned, so an early return further down — no camera,
# no shell scene — still costs a round and still turns the cylinder. The shot
# happened either way; `loaded` is decremented by the template regardless.
## ─────────────────────────────────────────────
func _spend_chamber() -> void:
	if not _rig_built:
		return
	var fired: int = _chamber_at_barrel()
	if fired >= 0 and fired < _full.size():
		_full[fired] = false
	_turned += 1
	_settle()


## WHICH CHAMBER IS UNDER THE BARREL.
##
## ChamberA's rest position IS the firing position: cluster_launcher_model.tscn
## puts it at y -0.06 z 0, the same place as the Barrel, while the other five
## ring round. So the chamber being fired is whichever one the cylinder's current
## rotation has carried into ChamberA's resting spot.
##
## Measured rather than solved from the detent count, because that way it cannot
## disagree with what is actually on screen if the turn direction is ever
## flipped.
func _chamber_at_barrel() -> int:
	var group := _cylinder_group()
	if group == null or _rounds.is_empty():
		return -1
	var spin := swing(AXIS, DETENT * float(_turned), HUB)
	var at_barrel: Vector3 = _chamber_rest(0).origin
	var best := -1
	var best_d := INF
	for i in CHAMBERS.size():
		var here: Vector3 = spin * _chamber_rest(i).origin
		var d: float = here.distance_to(at_barrel)
		if d < best_d:
			best_d = d
			best = i
	return best


## Put the cylinder and its rounds where they belong when nothing is animating:
## turned to its current detent, rounds seated, empties hidden.
func _settle() -> void:
	var group := _cylinder_group()
	if group == null:
		return
	var crane := _crane_group()
	if crane != null:
		crane.transform = Transform3D.IDENTITY   # shut, back in the frame
	group.transform = swing(AXIS, DETENT * float(_turned), HUB)
	for i in _rounds.size():
		if not is_instance_valid(_rounds[i]):
			continue
		_rounds[i].visible = _full[i]
		_rounds[i].transform = _round_rest(i)


## Make the chamber map agree with `loaded`, which other things can set directly
## — a fresh weapon starts full, and the armoury can hand one over part-loaded.
## Keeps whatever is already seated and fills or empties from the barrel round.
func _sync_full() -> void:
	var have := 0
	for f in _full:
		if f:
			have += 1
	var want: int = clampi(loaded, 0, _full.size())
	var order: Array[int] = _from_barrel()
	# Too few: fill the empties as they come past the face.
	for i in order:
		if have >= want:
			break
		if not _full[i]:
			_full[i] = true
			have += 1
	# Too many: take them off the same way.
	for i in order:
		if have <= want:
			break
		if _full[i]:
			_full[i] = false
			have -= 1


## The chambers in the order they reach the loading face, starting at the one
## under the barrel. A reload fills them in this order, so the rounds go in the
## way the drum turns rather than in whatever order the nodes happen to sit.
func _from_barrel() -> Array[int]:
	var start: int = maxi(_chamber_at_barrel(), 0)
	var out: Array[int] = []
	for k in CHAMBERS.size():
		out.append((start + k) % CHAMBERS.size())
	return out
func start_reload() -> void:
	var before: int = loaded
	super()
	if not is_reloading:
		return
	_to_load = clampi(magazine_size - before, 0, CHAMBERS.size())
	# WHICH chambers, not just how many. After firing, the empties are wherever
	# the cylinder has carried them, so the reload fills the ones that are actually
	# empty, in the order they come back past the loading face.
	_fill_order.clear()
	for i in _from_barrel():
		if not _full[i] and _fill_order.size() < _to_load:
			_fill_order.append(i)
	# A TOP-UP IS NOT A FULL RELOAD. reload_time is what six rounds cost; two cost
	# the fixed price of getting the cylinder open and shut again, plus two rounds
	# of feeding. Without this a one-round top-up sat with the drum hanging open
	# for five and a half seconds doing nothing, which is worse than the single
	# pose it replaced.
	var share: float = float(_to_load) / float(CHAMBERS.size())
	_reload_span = reload_time * (CRANE_SHARE + (1.0 - CRANE_SHARE) * share)
	_reload_t = _reload_span


func _finish_reload() -> void:
	super()
	# The chambers this reload filled are now full. _sync_full then reconciles with
	# whatever `loaded` actually came out as, in case the reserve ran short.
	for i in _fill_order:
		_full[i] = true
	_fill_order.clear()
	_sync_full()
	_settle()


func cancel_reload() -> void:
	super()
	_fill_order.clear()
	_settle()
func _reload_frame(t: float) -> Array:
	if not _rig_built:
		return []
	var up := [base_position, base_rotation]
	var open := [WORK_POS, WORK_ROT]
	# _to_load is captured when a reload starts. Outside one — a preview tool
	# rendering the animation on its own — fall back to a full six, so there is
	# something to look at rather than an empty frame.
	var n: int = _to_load if _to_load > 0 else CHAMBERS.size()

	if t < 0.10:
		# Coming up and over, cylinder still shut.
		_rig(0.0, 0.0, n, 0.0)
		return ease_pose(up, open, t / 0.10)
	if t < 0.20:
		# The cylinder comes out of the frame. Fast — it is sprung.
		_rig(smoothstep(0.0, 1.0, (t - 0.10) / 0.10), 0.0, n, 0.0)
		return ease_pose(open, open, 0.0)
	if t < 0.84:
		# ONE ROUND PER DETENT, and only as many as are missing.
		#
		# `step` runs 0..n across this window. The whole of each step is a round
		# going in; the LAST third of it is the drum indexing on to the next
		# empty chamber, so the round is seated before the cylinder moves and the
		# two never overlap. The final round does not index afterwards — there is
		# nothing left to bring round.
		var k: float = (t - 0.20) / 0.64
		var step: float = k * float(n)
		var done: float = floor(step)
		var into: float = step - done
		var seated: float = smoothstep(0.0, 0.62, into)
		var index: float = smoothstep(0.66, 1.0, into) if done < float(n - 1) else 0.0
		_rig(1.0, done + index, n, done + seated)
		# A nod on each detent, so the turn has something to push against.
		var nod: float = sin(clampf(into, 0.0, 1.0) * PI) * 1.4
		return [(open[0] as Vector3), (open[1] as Vector3) + Vector3(nod, 0.0, 0.0)]
	if t < 0.93:
		# SHUT, and hard. A cylinder is flicked home, never closed.
		var k: float = (t - 0.84) / 0.09
		_rig(1.0 - k * k, float(maxi(n - 1, 0)), n, float(n))
		return ease_pose(open, open, 0.0)
	_rig(0.0, float(maxi(n - 1, 0)), n, float(n))
	return ease_pose(open, up, (t - 0.93) / 0.07)


## One call, so the cylinder and the rounds riding in it can never be set out of
## step with each other.
##
##   `swing`  0 shut in the frame, 1 swung out to be loaded
##   `turns`  how far the cylinder has indexed, in chambers
##   `n`      how many rounds this reload is putting in
##   `fed`    how many of those are home, fractionally — 2.4 means two seated
##            and the third 40% of the way into its chamber
func _rig(swing_out: float, turns: float, n: int, fed: float) -> void:
	var group := _cylinder_group()
	if group == null:
		return
	# TWO GROUPS, TWO MOVEMENTS. The crane tips the barrel and cylinder away as one
	# break-action piece; the cylinder indexes inside it. Driving them separately is
	# what stops the barrel spinning a sixth of a turn with every round loaded.
	var s: float = clampf(swing_out, 0.0, 1.0)
	var crane := _crane_group()
	if crane != null:
		crane.transform = shift(SWING_OFFSET * s) * swing(SWING_AXIS, SWING_TILT * s, SWING_PIVOT)
	group.transform = swing(AXIS, DETENT * turns, HUB)

	# THE CHAMBERS THAT WERE ALREADY LOADED STAY LOADED. A reload of two rounds
	# into a gun holding four must not make the other four vanish and come back,
	# and after firing those four are not chambers 0 to 3 — they are wherever the
	# cylinder left them. Anything not on the fill list is simply left alone.
	for i in _rounds.size():
		var r: Node3D = _rounds[i]
		if not is_instance_valid(r):
			continue
		var slot: int = _fill_order.find(i)
		if slot < 0:
			r.visible = _full[i]
			r.transform = _round_rest(i)
			continue
		# One of the ones going in this reload.
		var how_far: float = clampf(fed - float(slot), 0.0, 1.0)
		r.visible = how_far > 0.0
		var rest: Transform3D = _round_rest(i)
		r.transform = Transform3D(rest.basis, rest.origin + ROUND_OUT * (1.0 - how_far))


## Move named parts into a group, keeping them exactly where they are. Both
## groups sit at the model origin, so the local transforms carry over untouched.
func _gather(from: Node3D, into: Node3D, names: Array[String]) -> void:
	for part_name in names:
		var p := from.get_node_or_null(NodePath(part_name)) as Node3D
		if p == null:
			push_warning("%s: no '%s' in its model, so that piece will not move with the rest." % [display_name, part_name])
			continue
		var keep: Transform3D = p.transform
		from.remove_child(p)
		into.add_child(p)
		p.transform = keep


## A chamber's own resting transform, straight off the model.
func _chamber_rest(i: int) -> Transform3D:
	var group := _cylinder_group()
	if group == null or i < 0 or i >= CHAMBERS.size():
		return Transform3D.IDENTITY
	var chamber := group.get_node_or_null(NodePath(CHAMBERS[i])) as Node3D
	return chamber.transform if chamber != null else Transform3D.IDENTITY


## Where the round in that chamber sits when it is seated.
func _round_rest(i: int) -> Transform3D:
	return _chamber_rest(i) * ROUND_FLIP


func _crane_group() -> Node3D:
	return viewmodel.get_node_or_null(NodePath(CRANE)) as Node3D if viewmodel != null else null


func _cylinder_group() -> Node3D:
	return viewmodel.get_node_or_null(NodePath("%s/%s" % [CRANE, CYLINDER])) as Node3D if viewmodel != null else null


func _reload_rest() -> void:
	super()
	# _settle, NOT identity. The drum keeps the position it has been fired round
	# to; resetting it here snapped the cylinder back to zero every time a reload
	# ended, which undid every shot the player had taken.
	_settle()
