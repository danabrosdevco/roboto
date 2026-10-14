extends HUDWeapon
class_name PlayerSquadAutomatic

# ─────────────────────────────────────────────
# SQUAD AUTOMATIC, reloading.
#
# A belt gun, and belt guns are the reason "true reload animation" is worth doing
# at all: the magazine rifle has one moving part and this has four, in an order
# that has to be right or it looks like nothing. Cover up, belt and box away, new
# box on, belt laid in the tray, cover down. Do the cover last-but-one and the
# belt appears to thread itself through a closed receiver.
#
# EVERY PART IS ALREADY IN THE MODEL. squad_automatic_model.tscn has FeedCover
# and its CoverLatch, the AmmoBox with its ribs and BoxLatch, and Link0 to Link3
# standing in for the belt between them. Nothing here was added for the
# animation; it is the gun being worked the way it was drawn.
#
# SEVEN SECONDS IS A LONG TIME, and that is the point of the weapon — the
# reload is the cost of the belt. The sequence is paced to use it rather than
# finishing in two and sitting still for five.
# ─────────────────────────────────────────────

## Hinged at its REAR edge, and opened only as far as it needs to read. The cover
## is 1.7 long against a 2.3 receiver, so at a realistic 58 degrees it swings a
## green plank across half the screen and stops looking like a part of the gun.
## 36 is enough to say "open" and leaves the receiver visible under it.
##
## Geometry: the cover box is 1.7 long centred at x 1.15, so the
## hinge line is x 0.30, and CoverLatch sits at x 2.05 which is the front. Open
## is the front end lifting, which is a positive turn about Z.
## THE REAR SIGHT IS ON THE COVER, and has to go up with it.
##
## squad_automatic_model.tscn says so in its own header: "a PEEP — a plate on
## the feed cover with a small hole punched through it and a windage knob on the
## right". RearSight sits at x 1.3, y 0.44, which is on top of a cover spanning
## x 0.30 to 2.00 at y 0.40. Leaving it behind drove the lid straight through the
## sight every time the gun was reloaded, which is exactly what it looked like.
##
## One entry does the whole assembly: Mount, the peep plate, the windage knob and
## the aperture are all children of that one node.
const COVER: Array[String] = ["FeedCover", "CoverLatch", "RearSight"]
const COVER_HINGE := Vector3(0.30, 0.40, 0.0)
const COVER_OPEN := 36.0

## The box and everything that comes off with it.
const BOX: Array[String] = ["AmmoBox", "Rib0", "Rib1", "Rib2", "BoxLatch"]
## Straight down and a little back, far enough to leave the frame.
const BOX_CLEAR := Vector3(-0.1, -2.6, 0.0)

## The belt. It travels with the box on the way out, because it is attached to
## it, and it is laid into the tray on the way in.
const BELT: Array[String] = ["Link0", "Link1", "Link2", "Link3"]

## THE WORKING POSE, PROBED RATHER THAN GUESSED. See the note in
## player_bolt_rifle.gd for why these are not derived from reload_position.
##
## This one took three tries and all three failures were instructive: a big pitch
## threw the gun out of frame, correcting it to a big roll filled the screen with
## the side of the receiver, and pulling the gun forward put a very long weapon
## straight into the lens. What works is holding it back and barely rolled — the
## top of the receiver is already toward the camera at rest, and the feed cover
## needs clear air ABOVE it to swing up into.
const WORK_POS := Vector3(-2.05, -0.55, 0.42)
const WORK_ROT := Vector3(-10.0, 6.0, -2.0)


func _reload_frame(t: float) -> Array:
	var up := [base_position, base_rotation]
	var open := [WORK_POS, WORK_ROT]
	var shut := [WORK_POS + Vector3(0.0, 0.015, 0.0), WORK_ROT + Vector3(6.0, -3.0, 0.0)]

	if t < 0.10:
		_rig(0.0, 0.0, 0.0)
		return ease_pose(up, open, t / 0.10)
	if t < 0.22:
		# Cover up. Fast, and the first thing that happens.
		_rig(smoothstep(0.0, 1.0, (t - 0.10) / 0.12), 0.0, 0.0)
		return ease_pose(open, open, 0.0)
	if t < 0.38:
		# Box and belt away, falling.
		var k: float = (t - 0.22) / 0.16
		_rig(1.0, k * k, k * k)
		return ease_pose(open, [(open[0] as Vector3) + Vector3(0.0, -0.04, 0.0), open[1]], k)
	if t < 0.56:
		# Open, empty, waiting. The long beat, and the one that makes the weapon
		# feel like a crew-served thing rather than a rifle.
		_rig(1.0, 1.0, 1.0)
		return ease_pose([(open[0] as Vector3) + Vector3(0.0, -0.04, 0.0), open[1]], open,
			(t - 0.38) / 0.18)
	if t < 0.74:
		# New box up and on. Decelerating — it is being lifted into place.
		var k: float = smoothstep(0.0, 1.0, (t - 0.56) / 0.18)
		_rig(1.0, 1.0 - k, 1.0)
		return ease_pose(open, open, 0.0)
	if t < 0.84:
		# Belt laid into the tray, then the cover comes down on it.
		var k: float = smoothstep(0.0, 1.0, (t - 0.74) / 0.10)
		_rig(1.0 - k * 0.15, 0.0, 1.0 - k)
		return ease_pose(open, open, 0.0)
	if t < 0.92:
		# SHUT, and hard. A feed cover is slammed, never closed.
		var k: float = (t - 0.84) / 0.08
		_rig(0.85 * (1.0 - k * k), 0.0, 0.0)
		return ease_pose(open, shut, k * k)
	_rig(0.0, 0.0, 0.0)
	return ease_pose(shut, up, (t - 0.92) / 0.08)


## One call so the four assemblies can never be set out of step with each other.
## `cover` 0 shut to 1 open, `box` 0 fitted to 1 clear, `belt` 0 laid in the tray
## to 1 gone with the box.
func _rig(cover: float, box: float, belt: float) -> void:
	var hinge := swing(Vector3(0, 0, 1), COVER_OPEN * clampf(cover, 0.0, 1.0), COVER_HINGE)
	for path in COVER:
		pose_part(path, hinge)
	var dropped := shift(BOX_CLEAR * clampf(box, 0.0, 1.0))
	for path in BOX:
		pose_part(path, dropped)
	# The belt goes with the box but lags it — it is hanging off the thing that
	# is falling, not falling on its own.
	var slack := shift(BOX_CLEAR * clampf(belt, 0.0, 1.0) * 0.85)
	for path in BELT:
		pose_part(path, slack)
