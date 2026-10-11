extends RefCounted

# ─────────────────────────────────────────────
# WHAT IS IN FRONT OF AN AIRCRAFT, NOT JUST UNDER IT.
#
# Every flying unit in the game held its altitude off ONE RayCast3D pointing
# straight down, and steered on a heading with its Y zeroed. So the only thing a
# drone knew about the world was the ground directly beneath it, and the only
# thing it avoided was other aircraft (_separation(), which is horizontal and
# only looks at the "air" group).
#
# A block at hover height is therefore invisible until the body touches its side.
# The down-ray still sees ground 22m below and reports the altitude as correct,
# so the drone keeps pushing forward into the face, slides along it or wedges in
# a corner, and never climbs — there is nothing in the loop that could tell it
# to. And when it does scrape over the top, the down-ray suddenly finds the
# block instead of the ground, the target altitude jumps by the block's height,
# and it pogos.
#
# This looks AHEAD. It samples the ground at a few points out along the flight
# direction and reports the highest, so the aircraft starts climbing before it
# arrives rather than after it has stopped. One probe set per aircraft, refreshed
# on an interval rather than every frame — at 18 m/s a 27m lookahead does not
# change meaningfully inside a tenth of a second, and the whole point is to spend
# as little as possible on it.
#
# WHY THE SAMPLES COME DOWN FROM ABOVE. The obvious thing is to cast down from
# the aircraft's own altitude at each sample point. That fails on exactly the
# case this exists for: if the block is at hover height then the sample point is
# INSIDE it, and intersect_ray does not report a hit for a ray that starts inside
# a shape. The probe would come back empty and the drone would fly into the one
# obstacle it most needed to see. So each sample starts well above and comes
# down, which finds the TOP of whatever is in the way.
# ─────────────────────────────────────────────


## How far ahead to look, in seconds of flight. Distance scales with speed
## because that is what the aircraft needs: the faster it goes, the sooner it has
## to know. 1.5s is roughly 27m for a spotter drone and 30m for a gunship, which
## is comfortably more than either needs to gain a block's height.
var lookahead_seconds: float = 1.5

## Sample points along the lookahead. Three gives a 9m spacing at cruise, which
## resolves anything with footprint. The forward whisker below is what catches
## a mast thin enough to sit between two samples.
var samples: int = 3

## The most it will ask the aircraft to climb. Without this a drone passing a
## tall building would try to hold cruise height above the ROOF, and a bridge
## deck overhead would read as ground and pull it up through the span. Past this
## the obstacle is a ceiling to be steered around, not terrain to be crossed.
var max_rise: float = 26.0

## Seconds between probe refreshes. The cached answer is used in between.
var refresh_interval: float = 0.1

## A short ray straight along the flight direction at body height. The sample
## ring above finds things with a footprint; this finds the pole, the mast, the
## corner of a wall the samples straddle. On a hit the aircraft is told to climb
## by this much over its own position, which turns "grind along a face" into
## "go over it".
var whisker_length: float = 7.0
var whisker_climb: float = 7.0

## How high above the aircraft each sample starts. See the header: a sample that
## begins inside the obstacle reports nothing at all.
var probe_above: float = 40.0
var probe_below: float = 300.0

var _cached: float = -INF
var _age: float = INF
var _warned_no_world: bool = false


## Refresh the probe if it is due. Safe to call every frame.
##
## `fly_dir` is the aircraft's own flight direction (flat, normalised) and
## `speed` is how fast it is travelling along it; a stationary aircraft has
## nothing ahead of it and the probe is skipped.
func tick(delta: float, body: CharacterBody3D, fly_dir: Vector3, speed: float) -> void:
	_age += delta
	if _age < refresh_interval:
		return
	_age = 0.0

	if body == null or not body.is_inside_tree():
		# Not an error — an aircraft is built before it is added — but it must
		# not leave a stale answer standing.
		_cached = -INF
		return
	var world := body.get_world_3d()
	if world == null:
		if not _warned_no_world:
			_warned_no_world = true
			push_warning("AirClearance: %s has no World3D, so nothing ahead of it can be probed and it will fly on its down-ray alone." % body.name)
		_cached = -INF
		return

	var flat := Vector3(fly_dir.x, 0.0, fly_dir.z)
	if flat.length_squared() < 0.0001 or speed < 0.5:
		# Hovering. There is no "ahead", and holding the last answer would keep a
		# drone parked at the altitude of a block it is no longer flying at.
		_cached = -INF
		return
	flat = flat.normalized()

	var space := world.direct_space_state
	var from: Vector3 = body.global_position
	var reach: float = maxf(speed, 1.0) * lookahead_seconds
	var ceiling: float = from.y + max_rise
	var highest: float = -INF

	for i in range(1, maxi(samples, 1) + 1):
		var at: Vector3 = from + flat * (reach * float(i) / float(samples))
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(at.x, from.y + probe_above, at.z),
			Vector3(at.x, from.y - probe_below, at.z))
		q.exclude = [body.get_rid()]
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var y: float = hit.position.y
		# Anything above the climb ceiling is not terrain to cross. Ignoring it
		# here rather than clamping keeps a bridge deck from reading as a hill.
		if y <= ceiling and y > highest:
			highest = y

	# The whisker. Straight ahead, at the altitude it is actually flying.
	var wq := PhysicsRayQueryParameters3D.create(from, from + flat * whisker_length)
	wq.exclude = [body.get_rid()]
	wq.collision_mask = 1
	var whit := space.intersect_ray(wq)
	if not whit.is_empty():
		highest = maxf(highest, minf(from.y + whisker_climb, ceiling))

	_cached = highest


## The highest ground found ahead, or -INF when there is nothing (which maxf()s
## away harmlessly against the aircraft's own down-ray).
func ground_ahead() -> float:
	return _cached
