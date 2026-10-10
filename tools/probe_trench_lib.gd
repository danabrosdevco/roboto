extends RefCounted

# ─────────────────────────────────────────────
# THE TRENCH MEASUREMENTS, IN ONE PLACE.
#
# Not a probe. The five trench probes —
#
#   probe_cover_continuity.gd   what share of an advance is exposed
#   probe_trench_share.gd       does the squad actually walk in the trenches
#   probe_over_the_top.gd       how many deliberate ways out of our own line
#   probe_no_mans_land.gd       is the crossing ground observed
#   probe_trench_straights.gd   can enfilade fire rake a whole run
#
# — all need the same four things: the measured chassis frames, the depth of a
# cut at a point, whether an eye can see a head, and where the enemy's eyes
# are. Those were written four times in the first draft of this pass and two of
# the copies already disagreed about head height. One copy, and every probe
# reports the same arithmetic.
#
# WHY A LIBRARY AND NOT A BASE CLASS. Two of the five probes have to inherit
# probe_nav_reach.gd instead, because the honest-bake machinery lives there and
# GDScript has no multiple inheritance. So the shared measurements are static
# functions on a RefCounted that anything can call, the way
# tools/mapdeck_data.gd is used.
#
# NOTHING HERE READS THE DISK TWICE on purpose; callers load the level.
#
# Used as:  const LIB := preload("res://tools/probe_trench_lib.gd")
#           LIB.cut_depth(space, x, z)
#
# No class_name: a global class would be registered for every editor run of
# this project to carry a thing only five probes call.
# ─────────────────────────────────────────────

## WHERE THE CHASSIS NUMBERS COME FROM, and why they are not typed here.
## probe_nav_reach.gd's FRAMES table is the one the navmesh bakes are taken
## from, and it is itself transcribed from tools/probe_chassis_size.gd, which
## measures the collision shapes. A second copy of those numbers is a second
## thing to get wrong — the Bulwark's shield and the Rover's height have each
## been wrong in a brief once already.
const REACH := "res://tools/probe_nav_reach.gd"
const KIT := "res://maps/blocks/trench/trench_kit.json"

## The player is NOT in FRAMES as a player: the squad frames come from the
## armoury and the player comes from Character/characters/player. Measured off
## test_character.tscn: a capsule 1.70 m tall, radius 0.25, centred on the
## node, with the camera at +0.65 — so the eye is 1.50 m above the feet and the
## top of the head is 1.70. Both numbers matter and they are different: 1.70 is
## what has to be below a parapet for the player to be covered, 1.50 is where
## the player's own view comes from.
const PLAYER_HEIGHT := 1.70
const PLAYER_EYE := 1.50

## How far below the top of its own head a body is "seen". A head hit is a hit;
## a hit on the last 25 cm of a Walker's aerial is not what anyone means by
## exposed, and measuring at the exact top of the capsule makes every grazing
## ray count.
const HEAD_DROP := 0.25

## How far an eye's ray starts from the eye itself. A pillbox eye sits INSIDE a
## pillbox and a trench eye inside a revetment, so a ray cast from the eye
## position hits its own wall and every enemy on the map reports seeing nothing.
## 1.2 m forward is through the embrasure and no further: it is less than the
## 1.6 m T_EMBR an embrasure is wide, so this cannot see through a solid wall
## that is thicker than a trench wall.
const EYE_OUT := 1.2

## Ring radius for the cut-depth measurement, and how many directions. 7 m is
## outside the widest thing in the kit (the 8 m sunken road is 4 m half-width
## plus 0.8 of wall) so the ring lands on the ground BESIDE the cut rather than
## on its own floor.
const RING := 7.0
const RING_N := 8

## Names of the things an enemy fires from. Matched as substrings against node
## names, because every placed piece on this map is named W####_<piece> or
## <route><nn>_<piece> and the piece name is the only thing that identifies it.
const FIRING_PIECES := [
	"feature_pillbox", "fort_hesco_sangar", "fort_gun_emplacement",
	"fort_mortar_pit", "feature_watchtower",
]

## Eye height above the floor it stands on, for an enemy in a hole or a box.
## A soldier frame is 2.00 m tall (measured), so its eye is about 1.5 m up, the
## same as the player's — enemies on this map are the soldier frames.
const FIRE_EYE := 1.5


# ── THE FRAMES ──────────────────────────────────────────────────────────────

## radius, height, climb — per chassis, from probe_nav_reach.gd's table.
static func frames() -> Dictionary:
	var script: Variant = load(REACH)
	if script == null:
		push_error("probe_trench_lib: %s will not load — there are no chassis numbers to measure against" % REACH)
		return {}
	return (script.FRAMES as Dictionary).duplicate(true)


## One frame, or an empty array with a warning. Never a guess: a probe that
## invents a chassis size is the exact failure these probes exist to catch.
static func frame(who: String) -> Array:
	var all := frames()
	if not all.has(who):
		push_warning("probe_trench_lib: no chassis called '%s' — known: %s" % [
				who, ", ".join(all.keys())])
		return []
	return (all[who] as Array).duplicate()


## The height of a body, including the player, who is not in the armoury.
static func height_of(who: String) -> float:
	if who == "drone" or who == "player":
		return PLAYER_HEIGHT
	var f := frame(who)
	return float(f[1]) if f.size() >= 2 else 0.0


## Where that body's head is, for a line-of-sight test.
static func head_of(who: String) -> float:
	return maxf(height_of(who) - HEAD_DROP, 0.2)


# ── THE KIT'S OWN SECTION ───────────────────────────────────────────────────

## The trench section as block_trench.gd wrote it into the kit manifest:
## floor, half, wall, parapet, road_floor, road_half. READ, not typed — the
## whole point of the manifest is that the numbers in it cannot go stale.
static func section() -> Dictionary:
	if not FileAccess.file_exists(KIT):
		push_warning("probe_trench_lib: %s is missing — run tools/block_trench.gd; section numbers unavailable" % KIT)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT))
	if not (parsed is Dictionary):
		push_warning("probe_trench_lib: %s is not a kit manifest" % KIT)
		return {}
	return (parsed as Dictionary).get("section", {})


## The whole manifest's piece table, for the probes that count ports and digs.
static func pieces() -> Dictionary:
	if not FileAccess.file_exists(KIT):
		push_warning("probe_trench_lib: %s is missing — no kit pieces to read" % KIT)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT))
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).get("pieces", {})


# ── THE GROUND ──────────────────────────────────────────────────────────────

## Top of the collision at x,z, or NAN if there is nothing there. NAN and not
## 0.0: zero is a real height on this map and a sample that silently becomes
## sea level reads as a 2 m deep trench wherever the ray missed.
static func ground(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(
			Vector3(x, 900.0, z), Vector3(x, -400.0, z))
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return (hit["position"] as Vector3).y


## HOW DEEP THE CUT IS AT A POINT, which is the measurement this whole pass
## turns on. The floor under x,z against the MEDIAN of a ring of samples RING
## metres out: median and not mean, because one ring sample down a neighbouring
## shell hole would otherwise say the ground beside a trench is lower than the
## trench.
##
## Positive means sunken. It does not care whether the cut is a kit trench, a
## terrain path cut or a crater, which is deliberate — the squad does not care
## either, and the question is whether there is earth between it and the enemy.
##
## IT IS NOT THE SAME NUMBER AS COVER. Cover is this plus whatever parapet
## stands on the lip, and the parapet is dressing (feature_trench_revetment is
## +0.59 above grade) or kit wall (+0.60). Callers that want cover add it and
## say which they used.
static func cut_depth(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var floor_y := ground(space, x, z)
	if is_nan(floor_y):
		return NAN
	var ring: Array[float] = []
	for i in RING_N:
		var a := TAU * float(i) / float(RING_N)
		var h := ground(space, x + cos(a) * RING, z + sin(a) * RING)
		if not is_nan(h):
			ring.append(h)
	if ring.size() < 3:
		return NAN
	ring.sort()
	var grade: float = ring[ring.size() / 2]
	return grade - floor_y


# ── SEEING ──────────────────────────────────────────────────────────────────

## Can an eye see a point. The ray starts EYE_OUT metres along its own line so
## the eye does not see the inside of its own pillbox, and stops short of the
## target by a hair so a head standing ON geometry is not blocked by the
## geometry it stands on.
static func sees(space: PhysicsDirectSpaceState3D, eye: Vector3, at: Vector3) -> bool:
	var dir := at - eye
	var d := dir.length()
	if d < 0.5:
		return true
	dir /= d
	var from := eye + dir * minf(EYE_OUT, d * 0.5)
	var to := at - dir * 0.1
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	return hit.is_empty()


## How many of a set of eyes see a point. The count and not just a boolean,
## because one eye on a crossing is a risk and six is a killing ground, and the
## difference is the whole design question.
static func seen_by(space: PhysicsDirectSpaceState3D, eyes: Array, at: Vector3) -> int:
	var n := 0
	for e: Vector3 in eyes:
		if sees(space, e, at):
			n += 1
	return n


# ── WHERE THE ENEMY IS ──────────────────────────────────────────────────────

## EVERY ENEMY FIRING POSITION, DERIVED. Two kinds, because the map has two:
##
##   1. The emplacements — pillboxes, sangars, gun and mortar pits — found by
##      piece name anywhere on the enemy side of the contact line.
##   2. The enemy front trench itself, sampled along its frontage. A line held
##      by riflemen is the thing that actually shoots at a crossing, and it is
##      a terrain cut with no node of its own, so nothing names it and it would
##      otherwise be left out of every sightline measurement on this map.
##
## `front_x` is the enemy front line's x, read by the caller from the objective
## anchor rather than typed. Eyes are placed FIRE_EYE above whatever collision
## is under them, so one in a cut is in the cut.
static func firing_positions(level: Node3D, space: PhysicsDirectSpaceState3D,
		front_x: float, z_from: float, z_to: float, z_step: float) -> Array:
	var out: Array = []
	var named := 0
	for n in level.find_children("*", "Node3D", true, false):
		var nm := str(n.name)
		var is_gun := false
		for p: String in FIRING_PIECES:
			if nm.contains(p):
				is_gun = true
		if not is_gun:
			continue
		var at: Vector3 = (n as Node3D).global_position
		if at.x < front_x - 10.0:
			continue                    # ours, or in no-man's-land: not theirs
		var g := ground(space, at.x, at.z)
		out.append(Vector3(at.x, (at.y if is_nan(g) else g) + FIRE_EYE, at.z))
		named += 1
	var line := 0
	var z := z_from
	while z <= z_to:
		var g := ground(space, front_x, z)
		if is_nan(g):
			# EVERY SKIP SAYS WHY. A front-line sample with no collision under
			# it means the frontage asked for runs off the built map, and a
			# sightline measurement quietly taken with half the line missing is
			# worse than none.
			push_warning("probe_trench_lib: nothing under the enemy front line at z %.0f — that eye is not placed" % z)
		else:
			out.append(Vector3(front_x, g + FIRE_EYE, z))
			line += 1
		z += z_step
	if out.is_empty():
		push_warning("probe_trench_lib: no enemy firing positions found at all — every sightline measurement below is meaningless")
	print("   enemy eyes: %d emplacement(s) + %d front-line sample(s) = %d" % [
			named, line, out.size()])
	return out


## An objective anchor's world position, by node name, from any of the places a
## level in this project keeps them.
static func objective(level: Node3D, who: String) -> Vector3:
	for holder: String in ["EnemySquadObjs", "Objectives",
			"NavigationRegion3D/Objectives", "SquadObjectives"]:
		var h := level.get_node_or_null(holder)
		if h == null:
			continue
		var o := h.get_node_or_null(who)
		if o is Node3D:
			return (o as Node3D).global_position
	push_warning("probe_trench_lib: no objective anchor called %s — the caller is about to use a fallback" % who)
	return Vector3(NAN, NAN, NAN)


# ── PATHS ───────────────────────────────────────────────────────────────────

## A navmesh path resampled to a fixed pitch, so a measurement per sample is a
## measurement per metre of walking. map_get_path returns corners, and a 60 m
## straight leg is TWO points: averaging over the corners weights a hairpin the
## same as half the route.
static func densify(path: PackedVector3Array, step: float) -> Array:
	var out: Array = []
	if path.size() == 0:
		return out
	out.append(path[0])
	for i in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		var d := a.distance_to(b)
		var n := int(d / step)
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) * step / d))
		if out[out.size() - 1].distance_to(b) > 0.01:
			out.append(b)
	return out


## The length of a densified sample list.
static func run_length(samples: Array) -> float:
	var total := 0.0
	for i in range(1, samples.size()):
		total += (samples[i] as Vector3).distance_to(samples[i - 1] as Vector3)
	return total
