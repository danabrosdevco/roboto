extends HUDWeapon
class_name PlayerSquadAutomatic

# ─────────────────────────────────────────────
# SQUAD AUTOMATIC, reloading.
#
# A box gun: the magazine rifle has one moving part and this has one too, but
# a box that size is dropped and struck home rather than slipped in, and seven
# seconds of it is the cost of carrying the thing. Box away, a long empty beat,
# new box up, struck home.
#
# THERE WAS A BELT AND IT WAS CUT, 2026-10-16, along with the bipod. It was four
# links and they were authored at z 0.2 inside a receiver spanning z -0.25 to
# 0.25 — sealed in the gun, visible only mid-reload while they fell away with
# the box, which read as the weapon shedding debris. Routing them outside and
# feeding them a link per round was built and then dropped: eight links evenly
# spaced on a run that WRAPS, advanced by exactly one link, is the same eight
# positions again, so the belt that fed correctly also looked welded on. Making
# it read would have meant animating between stations every frame for a detail
# the player sees for half a second. Not worth the frame time. Do not re-add
# Link0..Link3 to squad_automatic_model.tscn expecting them to show.
#
# EVERY PART IS ALREADY IN THE MODEL. squad_automatic_model.tscn has the
# AmmoBox with its ribs and BoxLatch. Nothing here was added for the animation;
# it is the gun being worked the way it was drawn.
#
# SEVEN SECONDS IS A LONG TIME, and that is the point of the weapon. It is a
# balance number and lives in the scene, so the beats are paced to USE it
# rather than finishing in two and sitting still for five.
# ─────────────────────────────────────────────

## THE FEED COVER STAYS SHUT, and used to swing 36 degrees on a hinge at x 0.30.
## It opened because a belt had to be laid in the tray; with the belt gone it was
## opening onto an empty receiver and shutting again for no reason, which reads
## as a part flapping rather than a gun being worked. A box change does not need
## the lid.
##
## Kept as a note because the cover is still in the model and the geometry was
## measured: hinge at x 0.30 (the cover is 1.7 long centred at 1.15), latch at
## x 2.05, and the REAR SIGHT rides on it — RearSight sits at x 1.3 y 0.44, on
## top of a cover spanning x 0.30 to 2.00 at y 0.40, so anything that moves the
## lid has to move the sight with it or the lid goes straight through it. That
## cost a pass to find the first time.

## The box and everything that comes off with it.
const BOX: Array[String] = ["AmmoBox", "Rib0", "Rib1", "Rib2", "BoxLatch"]
## Straight down and a little back, far enough to leave the frame.
const BOX_CLEAR := Vector3(-0.1, -2.6, 0.0)


## THE WORKING POSE, PROBED RATHER THAN GUESSED. See the note in
## player_bolt_rifle.gd for why these are not derived from reload_position.
##
## THE FOURTH TRY, AND THE FIRST ONE MEASURED. The three before it were judged
## by eye from the player's camera, and all three were wrong in the same way the
## eye cannot catch: the animation played correctly and entirely off screen. The
## box left the frame 1.6 SCREEN HEIGHTS BELOW THE BOTTOM EDGE — at 135 degrees
## of field of view, nearly double the real lens, it was still not in shot — and
## the pose before this one never had the AmmoBox on screen at any beat of the
## reload, loaded or dropped.
##
## WHAT THE AXES ACTUALLY DO, because the old note here guessed and got it
## backwards. In this model's space +X is AWAY FROM THE EYE, not along the
## barrel: -3.05 puts the receiver two centimetres from the lens and -0.05 puts
## it seventy away. +Y is up the screen and +Z is right. Rotation is roll, yaw,
## pitch in that order.
##
## So the first fix was not the angle at all. The gun was too CLOSE, and no
## rotation fits a metre of weapon into a frame at arm's length: the box sat
## dead centre of the screen and behind the receiver, which is why a 2D
## measurement of where it would be drawn said everything was fine. Pushing it
## out to 0.6-0.9m and yawing it a quarter turn puts the whole left side —
## cover, tray, box — across the frame.
##
## THEN THE PITCH, which is what the 34 is for. Distance and yaw alone left the
## BUTT filling the right third of the screen: it is the nearest part of the gun
## to the eye and therefore the biggest, whatever else the pose does. Raising
## the muzzle swings the stock down and back out of shot — at 34 degrees the
## ButtPlate is past the bottom edge and the stock is a thin wedge leaving the
## corner, while the receiver, feed tray and box hold the middle. Past about 45
## the weapon stands up as a vertical pole and the tray turns away again, so
## this is a window and not a direction to keep pushing in.
##
## tools/probe_reload_pose.gd sweeps candidates without editing this, and prints
## each watched part's screen position AND ITS DISTANCE. It watches the Stock
## and ButtPlate too — those are measured to confirm they have gone, which is
## the only way to tell "out of frame" from "behind something". Use it rather
## than the eye; the eye is what produced the first three.
const WORK_POS := Vector3(-0.05, 0.05, -0.05)
const WORK_ROT := Vector3(-18.0, 30.0, 34.0)


func _reload_frame(t: float) -> Array:
	var up := [base_position, base_rotation]
	var open := [WORK_POS, WORK_ROT]
	var shut := [WORK_POS + Vector3(0.0, 0.015, 0.0), WORK_ROT + Vector3(6.0, -3.0, 0.0)]

	# THE RAMPS IN AND OUT ARE 0.14, NOT 0.10 AND 0.08.
	#
	# They were widened when the working pose moved: the gun now travels 1.7
	# units from the hip to get the box into frame, where it used to travel 0.4,
	# and the same ramp over four times the distance is four times the speed.
	# test_reload_motion caught it as a jump at t=0.96 — the exit was moving
	# 0.052 units a sample against a 0.045 limit, which in the hand is the gun
	# snapping back rather than being lowered. The middle beats keep their
	# proportions; only the two ends are longer.
	#
	# THE BEATS WERE RE-CUT WHEN THE COVER STOPPED MOVING. The sequence used to
	# be cover up, box away, wait, box on, cover down, slam — and with the cover
	# out of it the two beats that worked the lid were four tenths of the reload
	# spent holding perfectly still. The box's own beats were stretched into
	# that time rather than the reload being shortened: seven seconds is the
	# weapon's cost and a balance number, not an animation one.
	if t < 0.14:
		_rig(0.0)
		return ease_pose(up, open, t / 0.14)
	if t < 0.34:
		# Box away, falling. Accelerating, because it is dropped and not placed.
		var k: float = (t - 0.14) / 0.20
		_rig(k * k)
		return ease_pose(open, [(open[0] as Vector3) + Vector3(0.0, -0.04, 0.0), open[1]], k)
	if t < 0.56:
		# Empty, waiting. The long beat, and the one that makes the weapon feel
		# like a crew-served thing rather than a rifle.
		_rig(1.0)
		return ease_pose([(open[0] as Vector3) + Vector3(0.0, -0.04, 0.0), open[1]], open,
			(t - 0.34) / 0.22)
	if t < 0.78:
		# New box up and on. Decelerating — it is being lifted into place.
		var k: float = smoothstep(0.0, 1.0, (t - 0.56) / 0.22)
		_rig(1.0 - k)
		return ease_pose(open, open, 0.0)
	if t < 0.86:
		# STRUCK HOME. A box is hit to seat it, never pushed.
		var k: float = (t - 0.78) / 0.08
		_rig(0.0)
		return ease_pose(open, shut, k * k)
	_rig(0.0)
	return ease_pose(shut, up, (t - 0.86) / 0.14)


## The box and everything that comes off with it, `box` 0 fitted to 1 clear.
##
## THIS TOOK THREE ARGUMENTS AND NOW TAKES ONE — belt, then feed cover, both cut
## on purpose; see the header. It is still a function rather than four lines
## inline because the five parts of the box assembly must never be set out of
## step with each other, which is the whole reason it existed.
func _rig(box: float) -> void:
	var dropped := shift(BOX_CLEAR * clampf(box, 0.0, 1.0))
	for path in BOX:
		pose_part(path, dropped)

