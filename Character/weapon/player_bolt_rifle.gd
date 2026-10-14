extends HUDWeapon
class_name PlayerBoltRifle

# ─────────────────────────────────────────────
# MARK ONE, reloading.
#
# A box magazine out of a magazine well, which is the plainest reload in the
# game and therefore the one worth getting right first: everything else here is
# a variation on it.
#
# WHAT MAKES IT READ IS THE MAGAZINE, not the gun. The viewmodel move is small
# and mostly exists to get the well into view and to sell the weight of the
# thing; the beat the eye actually catches is a magazine leaving a hole and
# another one going into it. Both are solved from the same `t` as the pose, so
# they cannot drift apart — see PlayerWeapon._reload_frame.
#
# AND IT HAS A REAL BOLT. bolt_rifle_model.tscn carries a BoltKnob at
# (0.6, 0.3, 0.13) with an EjectionPort beside it, so the cycle does not have to
# be mimed by jerking the whole rifle: the handle lifts, draws, returns and turns
# down, which is the one piece of this weapon the player works after every single
# shot. See _pump_frame.
# ─────────────────────────────────────────────

const MAG := "Magazine"
## Where the magazine ends up once it has left the gun, as an offset from where
## the model scene parks it. Far enough to be out of the viewmodel's frame: it is
## not thrown, it is dropped, and the player should not watch it hang around.
const MAG_CLEAR := Vector3(0.0, -2.4, 0.18)

## THE WORKING POSE, PROBED RATHER THAN GUESSED.
##
## reload_position is not it. That pose was authored when a reload was one static
## tilt and nothing on the gun moved, so it drops the rifle about 18cm — which put
## the magazine well below the bottom of the frame, and an animation nobody can
## see is worse than no animation at all. Every guess at a correction was wrong in
## a different way until the poses were rendered side by side and one was picked:
## preview_viewmodel.gd takes POSES="at@x,y,z|rx,ry,rz;..." for exactly that.
##
## This brings the rifle UP and across so the magazine well is in shot with room
## underneath for the magazine to fall out of frame.
const WORK_POS := Vector3(-0.70, -0.25, 0.04)
const WORK_ROT := Vector3(30.0, 10.0, -2.0)


func _ready() -> void:
	# The handle has to exist before anything can pose it, and tools that render
	# this weapon never call initialize(). Guarded, so whichever fires first does
	# it once.
	if viewmodel == null:
		viewmodel = weapon_model
	_bolt_cut = split_part(BOLT_NAME, BOLT_REGIONS, BOLT_SOURCE, BOLT_MATERIALS)
	split_part(BOLT_BODY_NAME, BOLT_BODY_REGIONS, BOLT_SOURCE, BOLT_MATERIALS)


func _on_initialize() -> void:
	super()
	if viewmodel != null:
		_bolt_cut = split_part(BOLT_NAME, BOLT_REGIONS, BOLT_SOURCE, BOLT_MATERIALS)
	split_part(BOLT_BODY_NAME, BOLT_BODY_REGIONS, BOLT_SOURCE, BOLT_MATERIALS)


func _reload_frame(t: float) -> Array:
	var up := [base_position, base_rotation]
	var open := [WORK_POS, WORK_ROT]
	# Struck home: a short shove up and square, which is what seating a magazine
	# with the heel of the hand looks like from the holder's eye.
	var seat := [WORK_POS + Vector3(0.0, 0.035, 0.0), WORK_ROT + Vector3(5.0, -3.0, 0.0)]
	# Worked: the rifle is pulled back and twisted as the bolt is run. There is no
	# bolt handle in the model to turn, so the whole weapon does it instead.
	# Turned the same way the cycle turns it, so the bolt being run at the end of a
	# reload looks like the bolt being run after a shot. They are the same motion on
	# the same handle and should not read as two different things.
	var cycle := [WORK_POS + Vector3(0.05, -0.01, 0.0), WORK_ROT + Vector3(-2.0, 20.0, 2.0)]

	if t < 0.14:
		_mag(0.0)
		_bolt(0.0, 0.0)
		return ease_pose(up, open, t / 0.14)
	if t < 0.32:
		# OUT. Accelerating rather than eased, because it is falling.
		var k: float = (t - 0.14) / 0.18
		_mag(k * k)
		return ease_pose(open, open, 0.0)
	if t < 0.50:
		# Gone, and the rifle dips while the other hand finds a fresh one.
		_mag(1.0)
		return ease_pose(open, [(open[0] as Vector3) + Vector3(0.0, -0.05, 0.0), open[1]],
			(t - 0.32) / 0.18)
	if t < 0.70:
		# IN. Decelerating into the well: it is being pushed, not dropped.
		var k: float = (t - 0.50) / 0.20
		_mag(1.0 - smoothstep(0.0, 1.0, k))
		return ease_pose([(open[0] as Vector3) + Vector3(0.0, -0.05, 0.0), open[1]], open,
			(t - 0.50) / 0.20)
	_mag(0.0)
	if t < 0.76:
		_bolt(0.0, 0.0)
		return ease_pose(open, seat, (t - 0.70) / 0.06)   # struck home
	# AND THEN THE BOLT IS RUN, with the same handle the cycle uses. A magazine
	# rifle that reloads without chambering has not finished reloading, and
	# chamber_round is set on this weapon — so the round it comes away with has
	# to be seen going in.
	if t < 0.86:
		var k: float = (t - 0.76) / 0.10
		_bolt(smoothstep(0.0, 1.0, minf(k * 2.0, 1.0)), smoothstep(0.0, 1.0, k))
		return ease_pose(seat, cycle, k)
	if t < 0.94:
		var k: float = (t - 0.86) / 0.08
		_bolt(1.0 - smoothstep(0.0, 1.0, maxf(k * 2.0 - 1.0, 0.0)), 1.0 - smoothstep(0.0, 1.0, k))
		return ease_pose(cycle, cycle, 0.0)
	_bolt(0.0, 0.0)
	return ease_pose(cycle, up, (t - 0.94) / 0.06)


## `k` 0 is seated, 1 is clear of the gun. The magazine tips as it leaves rather
## than sliding straight down — a magazine that drops perfectly level reads as a
## lift, not a release.
func _mag(k: float) -> void:
	var e: float = clampf(k, 0.0, 1.0)
	var pivot := rest_origin(MAG)
	pose_part(MAG, shift(MAG_CLEAR * e) * swing(Vector3(0, 0, 1), -14.0 * e, pivot))


# ─────────────────────────────────────────────
# WORKING THE BOLT, after every shot.
#
# firemode is MANUAL and pump_time is 0.7, so the rifle already spent two thirds
# of a second between shots refusing to fire. Nothing moved during it: the gun
# simply went dead in the hand and came back, which reads as lag rather than as
# an action being worked.
#
# FOUR MOVEMENTS, because that is what a turnbolt does and the shape is the whole
# character of the weapon: lift the handle out of its notch, draw it back (the
# case leaves here), run it forward onto a fresh round, turn it down to lock.
# Nothing else in the game asks the player to wait like this, and the wait is
# only tolerable if they can see what it is for.
# ─────────────────────────────────────────────

## THE REAL HANDLE IS NOT A NODE. BoltKnob is a small block at x 0.56 to 0.65
## and it is NOT the bolt handle — animating it was wrong twice over. The handle
## is a lever buried in bolt_rifle_base.res, further BACK along the receiver at
## x 0.20 to 0.33, and it is the thing that sticks furthest out of the right side
## of this weapon: out to z 0.30 against a receiver that stops at 0.13.
##
## So it is cut out of the body at load, the same way the Ancient Rifle's
## magazine is — see PlayerWeapon.split_part. The region takes everything
## standing proud of the receiver skin in that short span, and nothing else on
## the gun reaches anywhere near that far out.
const BOLT := "Rifle/BoltHandle"
## THE BOLT IS THE CYLINDER, not the block beside it.
##
## BoltKnob is a rectangular lug at (0.6, 0.3, 0.13) and it is NOT the bolt — it
## stays put. The bolt is a cylinder of radius about 0.065 centred on y 0.295,
## z 0, running along the top of the receiver from x 0.06 to x 0.74, with the
## handle welded to it at x 0.22 to 0.33. Both are buried in the body mesh, so
## both are cut out of it at load.
const BOLT_PARTS: Array[String] = ["Rifle/BoltHandle", "Rifle/BoltBody"]
const BOLT_BODY_NAME := "BoltBody"
## THE BOLT IS METAL; THE RECEIVER PANEL BESIDE IT IS WOOD.
##
## The box alone cannot separate them — they occupy the same space, and the cut
## took 28 triangles of DarkWood along with the 101 of DarkMetal that are the
## bolt, so a tan slab of the receiver lifted and turned every time the bolt was
## worked. What tells them apart is what they are made of.
const BOLT_MATERIALS: Array[String] = ["DarkMetal", "Grey", "Black"]
## A box about the bolt axis: long enough to take the whole cylinder and the
## collar at its rear, tight enough in z to leave the receiver walls alone.
const BOLT_BODY_REGIONS: Array[AABB] = [
	AABB(Vector3(0.03, 0.185, -0.11), Vector3(0.76, 0.22, 0.22)),
]
const BOLT_NAME := "BoltHandle"
## The body mesh the handle is buried in.
const BOLT_SOURCE := "Rifle"
const BOLT_REGIONS: Array[AABB] = [
	AABB(Vector3(0.16, 0.06, 0.105), Vector3(0.24, 0.26, 0.30)),
]

var _bolt_cut: bool = false
## THE BOLT.S OWN AXIS, which is not the model centreline.
##
## A rotation about X ignores the pivot's x and uses its y and z, and the first
## version passed (0.18, 0, 0) — so the knob turned about the line y=0 z=0, half
## a receiver below where the bolt actually runs. At that radius a 78 degree lift
## threw the handle in a wide arc off the side of the gun, which is why it did
## not read as a bolt being worked: it was not lifting, it was orbiting.
##
## THE BOLT'S OWN CENTRELINE, measured off the cylinder: y 0.295, z 0. Two
## earlier guesses put it at y 0 and then y 0.185, both below the real thing, and
## a pivot that is low swings the handle through a wider arc than it should — it
## orbits instead of lifting.
const BOLT_AXIS := Vector3(0.40, 0.295, 0.0)
## How far the handle turns up out of its notch, and how far back it draws.
##
## THE DRAW IS SHORT ON PURPOSE. Only the knob moves — there is no bolt body in
## THE DRAW IS SHORT ON PURPOSE. The bolt is a handle and a body, not a whole
## assembly — a realistic full-length draw takes them off the back of the
## receiver and reads as a part coming loose. Far enough to see it travel, near
## enough that it never leaves the gun.
const BOLT_LIFT := 78.0
const BOLT_DRAW := 0.20

## WHAT THE RIFLE DOES WHILE THE BOLT IS WORKED. Almost nothing, on purpose.
##
## An earlier version yawed 24 degrees to swing the right flank toward the eye so
## the handle could be seen. That is the wrong trade: this runs after EVERY shot,
## and a rifle that turns a quarter of the way off target each time it cycles is
## unusable. Down the sights it is worse than unusable, because the sight picture
## is the thing being thrown away — and the handle is readable enough from where
## the rifle already sits.
##
## So: a touch UP, and the smallest tilt that says a hand is doing something.
## The follow-through stays a follow-through.
const CYCLE_POS := Vector3(0.0, 0.035, 0.0)
const CYCLE_ROT := Vector3(3.0, 3.5, 0.0)

func _pump_frame(t: float) -> Array:
	# FROM WHEREVER THE RIFLE IS BEING HELD, not always from the hip.
	#
	# _get_pose_target asks for the cycle BEFORE it asks about ADS, so a cycle
	# built on base_position dragged an aiming rifle back down to the hip for two
	# thirds of a second after every shot and then shoved it back up again. Down
	# the sights the cycle has to happen in the sights.
	var up: Array = [ads_position, ads_rotation] if is_ads else [base_position, base_rotation]
	var hold: Array = [(up[0] as Vector3) + CYCLE_POS, (up[1] as Vector3) + CYCLE_ROT]
	if t < 0.22:
		_bolt(smoothstep(0.0, 1.0, t / 0.22), 0.0)      # lifted out of the notch
		return ease_pose(up, hold, t / 0.22)
	if t < 0.46:
		_bolt(1.0, smoothstep(0.0, 1.0, (t - 0.22) / 0.24))   # drawn, case out
		return ease_pose(hold, hold, 0.0)
	if t < 0.70:
		_bolt(1.0, 1.0 - smoothstep(0.0, 1.0, (t - 0.46) / 0.24))   # run forward
		return ease_pose(hold, hold, 0.0)
	if t < 0.86:
		_bolt(1.0 - smoothstep(0.0, 1.0, (t - 0.70) / 0.16), 0.0)   # turned down
		return ease_pose(hold, hold, 0.0)
	_bolt(0.0, 0.0)
	return ease_pose(hold, up, (t - 0.86) / 0.14)

## `lift` 0 locked down to 1 standing up, `draw` 0 forward to 1 fully back. The
## draw happens along the bore and the lift turns about it, so the two compose
## the way the real thing does rather than fighting each other.
func _bolt(lift: float, draw: float) -> void:
	var turn := swing(Vector3(1, 0, 0), -BOLT_LIFT * clampf(lift, 0.0, 1.0), BOLT_AXIS)
	var move := shift(Vector3(-BOLT_DRAW * clampf(draw, 0.0, 1.0), 0.0, 0.0)) * turn
	# THE BODY TURNS WITH THE HANDLE. On a turnbolt they are one piece: the handle
	# is a lever welded to the bolt, and a handle that lifts while the bolt sits
	# still is two parts that have come apart. Same transform for both, so they
	# cannot drift.
	for p in BOLT_PARTS:
		pose_part(p, move)
