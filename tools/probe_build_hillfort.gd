extends SceneTree

# ─────────────────────────────────────────────
# BUILD HILLFORT — writes maps/hillfort_level.tscn from the station table below.
#
#   godot --headless --path . --script res://tools/probe_build_hillfort.gd
#   PROFILE=1 godot --headless --path . --script res://tools/probe_build_hillfort.gd
#   godot --headless --path . --script res://tools/probe_build_hillfort.gd -- --force
#
# IT WILL NOT OVERWRITE AN EXISTING LEVEL without --force. The scene on disk is
# the source once anyone has opened it; this table only made the first one.
#
# BOOTSTRAPPING A NEW LEVEL TAKES TWO WRITES, because the terrain data file
# does not exist until the first bake and an ext_resource pointing at a missing
# file is the silent-null bug check.sh hunts for. Build, bake the terrain,
# build again with --force, then bake the navmesh:
#
#   probe_build_hillfort.gd
#   terrain_bake.gd -- res://maps/hillfort_level.tscn
#   probe_build_hillfort.gd -- --force
#   probe_nav_hillfort.gd
#
# PROFILE=1 prints the massif's radial height and slope and the grade of every
# road leg, and writes nothing. Use it to tune before baking.
#
# WHY THE LEVEL IS GENERATED AND NOT HAND-WRITTEN. On a climb the two numbers
# that decide whether the map works are the grade of each leg (must be gentle
# enough to walk) and the slope of the face between the legs (must be steep
# enough that the squad CANNOT walk it, or the stair is decoration and every
# bot beelines up the mountain). Both are arithmetic over the same station
# table, so the table is the source and this derives the rest — including the
# road heights, which are interpolated along each leg by arc length so a leg's
# grade is CONSTANT by construction rather than by my getting it right by hand.
# It refuses to write if either number leaves its band.
#
# THE SHAPE OF THE MAP.
#   Act 1, z > +34: rolling hills. RAISE domes with FLATTEN crowns, roads that
#   climb between them. WALKABLE EVERYWHERE — open ground, flankable, hills
#   to fight over. The road is the fast way up, not the only way.
#   Act 2, z +34 … -140: the upland. Still rolling, but higher, barer and with
#   longer sightlines. Two more stations.
#   Act 3: the tor. A 40 m ring at 60°, which nothing walks, and one cut ramp
#   through it to the summit shelf — the only way onto the top of the map.
#
# Every surface the squad stands on is a TerrainStamp or a TerrainPath, never
# painted terrain: modifiers run LAST, after erosion and after the floor shift,
# at the exact heights written here. The sketch only supplies the rock.
# ─────────────────────────────────────────────

const OUT := "res://maps/hillfort_level.tscn"
const SIZE_X := 896.0
const SIZE_Z := 1024.0

## A leg gentler than this is a walk; steeper and the bots start scrabbling.
## The blocks' ramp rule is 30°, but that is authored geometry — a cut road is
## quantised to 2 m terrain cells and then smoothed, so it gets a margin.
const MAX_GRADE := 22.0
## The LEAST level ground at each end of every leg. See _curve: without it two
## roads meeting at a station write a step across each other. The real run-out
## is whatever it takes to cross that station's pad — see _runout.
const RUNOUT := 24.0
## The face between two flights has to beat the navmesh's agent_max_slope by
## enough that neither cell quantisation nor the finishing blur opens a way up.
const NAV_MAX_SLOPE := 45.0
const MIN_FACE := 52.0

## The high ground, as stacked RAISE cones about the summit. [radius, falloff,
## amount]
##
## NO STEEP RING. There was one — a 40 m band at 60° that ringed the summit and
## left exactly one cut ramp through it. It worked, and it read as a CRATER with
## a fort at the bottom rather than as a hilltop with a fort on it. So the
## ground now just rises to the top at about 20° from every side, the summit is
## a flat plateau, and whatever needs to stop the squad walking straight in is
## a WALL somebody built — which is what a fort looks like, and is the right
## place for that job anyway.
## PROMINENCE, not height. The first flat-topped version put the plateau at 132
## on ground that was already 127 a hundred metres out, so one ordinary hill
## stamp on the approach stood HIGHER than the objective and the fort could not
## be seen from the station below it. A hilltop fort that is invisible until you
## are on it is not a hilltop fort. The third cone is tighter and taller now, so
## the summit stands ~15 m clear at 120 m out and ~33 m clear at 160 m.
const CONES: Array = [
	[180.0, 420.0, 50.0],
	[140.0, 300.0, 26.0],
	# The summit dome. Its flat top is DELIBERATELY SMALLER than the plateau pad
	# above it: when the cone was flat out to r=76 and the pad only reached 60 in
	# Z, the ground just outside the pad stood 15-18 m HIGHER than the plateau
	# and the fort sat in a bowl. The pad has to be the top, so the ground under
	# it has to be falling by the time the pad ends.
	# 1.5 x 52/130 is a tangent of 0.6, so the steepest of this stands at 31 deg:
	# a hill you walk up from any side. At 100 m of falloff it was 42 and the
	# nav probe started reporting the west side as a detour.
	[40.0, 130.0, 52.0],
]
const SUMMIT := Vector2(30.0, -270.0)

## The band the profile is reported over. Nothing here has to be steep any more,
## so this is for looking at, not for passing.
const FACE_R0 := 80.0
const FACE_R1 := 260.0

## name, x, z, y, pad x, pad z, falloff
##
## KEEP THESE SMALL. The whole map is 132 m of relief; a 150 m pad levelled into
## it is not a clearing, it is a runway, and the first pass at hill scale came
## back as six concrete slabs joined by roads with the hills lost between them.
## A station is somewhere to stand and fight, not a parade ground — and the
## falloff does more for how it sits in the ground than the size does.
const STATIONS: Array = [
	["Trailhead", 0.0, 430.0, 0.0, 100.0, 70.0, 18.0],
	["Cistern", -170.0, 258.0, 10.0, 56.0, 40.0, 16.0],
	["Pillars", 150.0, 140.0, 34.0, 56.0, 40.0, 16.0],
	["Gate", -140.0, 34.0, 46.0, 56.0, 40.0, 16.0],
	["Terrace", 140.0, -46.0, 76.0, 56.0, 40.0, 16.0],
	["Shoulder", -205.0, -46.0, 62.0, 56.0, 40.0, 16.0],
	["Summit", 30.0, -270.0, 132.0, 150.0, 120.0, 14.0],
]

## from, to, bed width, bank falloff. In order: the road is walked in this order
## from the spawn, and the nav test walks the same chain.
const LEGS: Array = [
	["Trailhead", "Cistern", 14.0, 12.0],
	["Cistern", "Pillars", 14.0, 12.0],
	["Pillars", "Gate", 13.0, 11.0],
	["Gate", "Terrace", 13.0, 11.0],
	["Terrace", "Shoulder", 12.0, 10.0],
	["Shoulder", "Summit", 12.0, 26.0],
]

## The hills either side of the route, so the ground between the stations has
## shape to fight over rather than being a ramp across a plain.
## centre x, z, radius, falloff, amount
const HILLS: Array = [
	[-256.0, 306.0, 70.0, 150.0, 22.0],
	[268.0, 216.0, 72.0, 150.0, 30.0],
	[-40.0, 194.0, 58.0, 130.0, 22.0],
	[286.0, 268.0, 66.0, 140.0, 20.0],
	[-320.0, 110.0, 80.0, 160.0, 28.0],
	[276.0, 30.0, 70.0, 145.0, 26.0],
	[-24.0, 74.0, 54.0, 120.0, 20.0],
	# Kept off the line from the Terrace to the summit on purpose — at its old
	# place it raised the ground on that sightline by 27 m and hid the fort.
	[268.0, -120.0, 62.0, 110.0, 24.0],
	[-208.0, -232.0, 58.0, 125.0, 22.0],
]

## THE THING AT THE TOP. A relay station: the machines' ear on the high ground,
## which is what the road is for and why anything garrisons the summit.
##
## piece, x, z (OFFSET FROM THE SUMMIT, not world), yaw°
## The plateau is 150 × 120, so nothing may sit outside ±68 / ±54 of centre or
## it hangs over the hillside. _installation() checks that, and checks every
## pair for overlap — two pieces in the same ground is the quickest way to make
## a level look broken, and the eye does not catch it on a plateau this size.
const SUMMIT_PIECES: Array = [
	# ── THE DISH IS THE COMPOUND NOW. At 59 m across and 63 m tall it fills the
	# middle of a 120 × 96 ring, and the composition is what fits round it
	# rather than an arrangement it stands in. That is the right way up: a
	# relay station is a dish with buildings at its feet, and the 24 m version
	# read as a speck from the station below the summit — which is the whole
	# job it has, to be seen from down the valley.
	#
	# YAW 0, AND THAT IS NOT LAZINESS. Turned 25° its bounding footprint grows
	# from 59 × 49 to 73 × 69 — twenty metres in both axes, most of the room
	# inside the wall — and square-on it still faces due south, which is within
	# a few degrees of the gate and the road. It leaves three strips: east 35 m,
	# south 38 m, west 23 m, and everything below lives in one of them.
	# At z −24, not −16: the piece's bounding box sits 7 m SOUTH of its own
	# origin, because the bowl overhangs the pedestal forward. Placing off the
	# origin put it seven metres into the yard.
	["landmarks/landmark_relay_dish", -6.0, -24.0, 0.0],

	# ── EAST: the plant. The hall turned side-on, because a 29 m building does
	# not fit across a 35 m strip with anything else in it.
	["compute/compute_data_hall", 42.0, -22.0, 90.0],
	["compute/compute_chiller_yard", 44.0, 10.0, 0.0],
	["compute/compute_network_cabinet", 56.0, -30.0, 90.0],
	["compute/compute_network_cabinet", 56.0, -36.0, 90.0],
	["compute/compute_network_cabinet", 56.0, -42.0, 90.0],
	["compute/compute_transformer", 54.0, 24.0, 0.0],
	["compute/compute_transformer", 54.0, 34.0, 0.0],
	["compute/compute_cable_run", 28.0, 24.0, 90.0],
	["compute/compute_generator", 34.0, 36.0, 90.0],

	# ── WEST: the working side, and the gun that covers the road's last turn.
	["features/feature_watchtower", -52.0, -26.0, 0.0],
	["fortifications/fort_gun_emplacement", -50.0, -6.0, 0.0],
	["compute/compute_rack_row", -50.0, 8.0, 0.0],
	["compute/compute_rack_row", -50.0, 18.0, 0.0],
	# Only one floodlight now. The north strip between the dish and the wall is
	# six metres and nothing stands in it.
	["features/feature_power_pylon", -48.0, 32.0, 0.0],

	# ── SOUTH: the gate quarter and the only open ground inside the wall. The
	# checkpoint sits across the line from the gate so the way in is a turn,
	# and the yard's cover is set off that axis so none of it lines up into a
	# shooting corridor.
	["fortifications/fort_checkpoint", -28.0, 32.0, 20.0],
	["features/feature_watchtower", 4.0, 40.0, 90.0],
	["fortifications/fort_hesco_sangar", 24.0, 36.0, 40.0],
	["fortifications/fort_sentry_turret", 12.0, 42.0, 215.0],
	["fortifications/fort_floodlight_mast", 44.0, 41.0, 0.0],
	["fortifications/fort_t_walls", -6.0, 18.0, 24.0],
	["fortifications/fort_t_walls", 12.0, 24.0, -32.0],
	["fortifications/fort_t_walls", -18.0, 14.0, 70.0],
	["props/prop_jersey_barrier", 2.0, 14.0, 12.0],
	["props/prop_jersey_barrier", 8.0, 12.0, 12.0],
	["props/prop_crates", -24.0, 16.0, 30.0],
	["props/prop_barrels", 16.0, 18.0, 0.0],
	["props/prop_sandbag_nest", -52.0, 41.0, 0.0],
]

## Saddles and hollows, as LOWER stamps. WITHOUT THESE THE MAP IS ONE DOME:
## the base cone lifts the whole north of the map smoothly, the hills sit on
## top of it, and nothing between them ever comes back DOWN, so from the air
## it reads as a single swell with bumps rather than as a series of hills.
## Every one of these is between two hills, on purpose.
## centre x, z, radius, falloff, amount
const HOLLOWS: Array = [
	[-64.0, 296.0, 40.0, 90.0, 9.0],
	[36.0, 170.0, 52.0, 130.0, 20.0],
	[-250.0, 190.0, 44.0, 110.0, 14.0],
	[60.0, 40.0, 50.0, 125.0, 18.0],
	[-230.0, -46.0, 48.0, 120.0, 16.0],
	[96.0, -128.0, 44.0, 110.0, 12.0],
	[330.0, 140.0, 54.0, 130.0, 18.0],
]


func _initialize() -> void:
	var force := false
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		else:
			print("ignoring argument '%s'" % a)
	var by_name := {}
	for s: Array in STATIONS:
		by_name[s[0]] = s
	var bad := _profile()
	bad += _grades(by_name)
	bad += await _installation()
	if OS.get_environment("PROFILE") != "":
		quit(0)
		return
	if bad > 0:
		print("FAIL  %d leg(s) or face(s) outside the band — nothing written" % bad)
		quit(1)
		return
	var text := _scene(by_name)
	# A guard, not a formality. _scene kept a station name that had been renamed
	# out from under it; the access threw, this came back empty, and the open
	# below truncated the level to nothing while the line at the end still said
	# it had been written. Never report a write that did not happen.
	if text.length() < 2000:
		print("FAIL  the scene text came back %d bytes — see the script error above" % text.length())
		quit(1)
		return
	# THE LEVEL FILE IS THE SOURCE NOW, not this script's output. Same rule the
	# block_*.gd tools keep, and for the same reason: once a human has opened
	# hillfort_level.tscn in the editor, the scene on disk holds work this
	# table knows nothing about — a moved prop, a light, a tweaked inspector
	# value — and a rebuild would take it all out without saying so. Pass
	# --force when you really do mean to regenerate, and back the scene up
	# first if it has been touched.
	if FileAccess.file_exists(OUT) and not force:
		print("SKIP  %s exists — it may hold editor changes. Pass --force to regenerate it." % OUT)
		quit()
		return
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		print("FAIL  could not write %s" % OUT)
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("   wrote %s — %d station(s), %d leg(s), %d hill(s), %d hollow(s)" % [
			OUT, STATIONS.size(), LEGS.size(), HILLS.size(), HOLLOWS.size()])
	quit()


## How far a leg leaving `station` in direction `dir` must stay level.
##
## IT HAS TO CROSS THE WHOLE PAD. Roads are cut AFTER the shelves, so a road
## still climbing where it crosses a station's pad wins that ground and digs a
## trench through it — which is how the summit fort ended up with its towers
## standing on the pad's level and the ground cut 3 to 10 m out from under
## them, visible as daylight under the buildings. Level from the pad's own
## boundary inwards and the road asks for exactly the height the pad is at.
func _runout(station: Array, dir: Vector2) -> float:
	var half := Vector2(float(station[4]), float(station[5])) * 0.5
	# Distance from the pad's centre to its edge along dir, for an axis-aligned
	# rectangle. A near-zero component would divide to infinity, hence the max.
	var reach: float = minf(half.x / maxf(absf(dir.x), 0.0001),
			half.y / maxf(absf(dir.y), 0.0001))
	return maxf(RUNOUT, reach + float(station[6]))


## Height the stacked cones give at radius r from the summit.
func cone_h(r: float) -> float:
	var h := 0.0
	for c: Array in CONES:
		var d: float = r - float(c[0])
		if d <= 0.0:
			h += float(c[2])
		elif d < float(c[1]):
			h += float(c[2]) * (1.0 - smoothstep(0.0, float(c[1]), d))
	return h


## The shape of the hill under the summit. Reports only — since the tor came
## out there is no slope here that has to be anything, and a check that cannot
## fail is worse than no check.
func _profile() -> int:
	print("   high ground, radial profile from the summit at (%.0f, %.0f)" % [SUMMIT.x, SUMMIT.y])
	print("   %8s %9s %9s" % ["r (m)", "height", "slope"])
	var bad := 0
	var r := 0.0
	while r <= 560.0:
		var step := 20.0 if r < FACE_R1 else 40.0
		var a := cone_h(r)
		var b := cone_h(r + step)
		var slope := rad_to_deg(atan2(a - b, step))
		var mark := ""
		if slope > NAV_MAX_SLOPE:
			# Not a fault, but say so: anywhere over the navmesh's limit is a
			# piece of hillside the squad cannot use, and on a map whose whole
			# point is that the hills are open, that wants to be deliberate.
			mark = "  over agent_max_slope — not walkable"
		elif r < FACE_R1 and slope > 26.0:
			mark = "  steep for a hill"
		print("   %8.0f %8.1f m %8.1f°%s" % [r, a, slope, mark])
		r += step
	return bad


## DISTRICT ANCHORS. A SquadObjectivePoint is a named place with a tag and no
## logic, and squad_objective_point.gd says in as many words that missions
## reference these BY TAG and never by node path. So a tag is a contract this
## lane can honour without touching an operation: these say WHERE the places
## are. What happens at each — who holds it, which is a capture, what order
## they come in — is GAMEPLAY's, and nothing under Campaign/ is opened here.
##
## Heights are the ground, sampled off the baked terrain, not guessed. An
## anchor floating 20 m over its district still reports "reached" because the
## navmesh query snaps in 3D; it is the OFFSET in probe_reach_mutaha.gd that
## catches it, and that only works if the height is honest to begin with.
##
## node, tag, display name, x, z, y
const OBJECTIVES: Array = [
	# The route, one per station.
	["Hillfort_Trailhead", "obj_hillfort_trailhead", "Trailhead", 0.0, 430.0, 0.0],
	["Hillfort_Cistern", "obj_hillfort_cistern", "The Cistern", -170.0, 258.0, 10.0],
	["Hillfort_Pillars", "obj_hillfort_pillars", "The Pillars", 150.0, 140.0, 34.0],
	["Hillfort_Gate", "obj_hillfort_gate", "The Gate", -140.0, 34.0, 46.0],
	["Hillfort_Terrace", "obj_hillfort_terrace", "The Terrace", 140.0, -46.0, 76.0],
	["Hillfort_Shoulder", "obj_hillfort_shoulder", "The Shoulder", -205.0, -46.0, 62.0],
	# The summit compound, broken up: taking the hilltop is not one objective,
	# it is a gate, a yard, and three things inside worth standing on.
	["Hillfort_FortGate", "obj_hillfort_fortgate", "Fort Gate", -18.0, -214.0, 132.0],
	["Hillfort_Yard", "obj_hillfort_yard", "The Yard", 30.0, -250.0, 132.0],
	# At the dish's FOOT, not under it: an anchor on the pedestal's own footprint
	# reported reached with a 0.0 offset and no route, because the navmesh it
	# snapped to was a scrap inside the piece.
	["Hillfort_Dish", "obj_hillfort_dish", "The Relay Dish", -12.0, -262.0, 132.0],
	["Hillfort_Hall", "obj_hillfort_hall", "Data Hall", 34.0, -266.0, 132.0],
	# Beside the plant, not on it: at the generator's own spot this reported
	# cut off the moment a rebake moved the walkable cells a hair.
	["Hillfort_Power", "obj_hillfort_power", "Power Yard", 68.0, -240.0, 132.0],
	["Hillfort_Postern", "obj_hillfort_postern", "The Postern", 54.0, -325.0, 132.0],
	# The extraction point, on the hall roof. Its height is the ROOF's, so the
	# reach probe's offset means something: an anchor left at ground level here
	# would report reached off the yard below and prove nothing.
	["Hillfort_Roof", "obj_hillfort_roof", "Hall Roof", 72.0, -292.0, 141.8],
	# OFF the road. Every one of these is somewhere the squad can stand that
	# the road does not go, so a mission can ask for a flank instead of a
	# column — which is the whole reason the hills are walkable.
	["Hillfort_WestHill", "obj_hillfort_west_hill", "West Hill", -300.0, 110.0, 26.0],
	["Hillfort_EastHill", "obj_hillfort_east_hill", "East Hill", 268.0, 216.0, 41.5],
	["Hillfort_Saddle", "obj_hillfort_saddle", "The Saddle", 36.0, 170.0, 21.2],
	["Hillfort_EastUpland", "obj_hillfort_east_upland", "East Upland", 276.0, 30.0, 51.3],
	["Hillfort_NorthSpur", "obj_hillfort_north_spur", "North-West Spur", -208.0, -232.0, 97.8],
]

## Patrol routes: plain Node3D children of an anchor, which is the shape
## probe_reach_mutaha.gd reads them in. HEIGHTS ARE SAMPLED, not guessed —
## two of these were 25 m under the hill on the first pass, and the symptom is
## not "cut off", it is an OFFSET of a few metres, because the navmesh query
## snaps in 3D and finds something further away sideways.
## anchor node, then points as x, z, y triples
const PATROLS: Array = [
	["Hillfort_Saddle", [
		[36.0, 170.0, 21.2], [-40.0, 194.0, 21.4], [-120.0, 150.0, 43.0],
		[-60.0, 96.0, 48.6], [30.0, 120.0, 26.0],
	]],
	["Hillfort_Yard", [
		[30.0, -250.0, 132.0], [24.0, -234.0, 132.0], [44.0, -238.0, 132.0],
		[60.0, -252.0, 132.0], [46.0, -264.0, 132.0], [22.0, -252.0, 132.0],
	]],
]


## THE CURTAIN WALL. The plateau is walkable from every side — that was the
## point of taking the steep ring out — so this is the thing that makes the
## summit somewhere to be held rather than somewhere to walk onto.
##
## The ring is sized to WHOLE SEGMENTS. fort_wall is 24 m long, so a half-extent
## that is not a multiple of 12 leaves either a gap at the corner or a pair of
## segments buried in each other. 120 × 96 is 5 segments by 4.
const WALL_HALF := Vector2(60.0, 48.0)
## Where the road crosses the wall. It is the south-west segment of the south
## run, because that is the side the road climbs from; _installation() checks
## the road's own centreline passes through the opening.
const GATE_AT := -48.0
## fort_wall is 3.2 m thick. The side runs are offset by half of it so the ring
## butts at the corners instead of interpenetrating.
const WALL_THICK := 3.2
## The postern, in the north run — the way OUT, and where the level exit sits.
const POSTERN_AT := 24.0
## The data hall, and how far up its walkable roof is. compute_data_hall is
## 10.3 m tall with its origin 0.5 m up from the bottom of its collision.
const HALL_AT := Vector2(42.0, -22.0)
const HALL_ROOF := 9.8


## WHAT IS AT EACH STATION. Played, the map was a road between bare pads with
## everything interesting on the hilltop — "overall except for the top of the
## hill there's nothing". A station has to be somewhere worth stopping and
## somewhere worth fighting over, which means two different things: COVER a
## squad can use, and enough built stuff that the place has a name for a
## reason.
##
## Offsets are from the station's centre and heights come from the station, so
## everything here stands on the flat the pad already guarantees. _installation
## checks each station's group the same way it checks the summit: on the pad,
## and clear of each other.
##
## station, piece, dx, dz, yaw
const STATION_DRESS: Array = [
	# ── TRAILHEAD. The staging area: where the squad comes from. Containers,
	# a hesco line to form up behind, the plant that got the road built.
	["Trailhead", "features/feature_container_stack", -30.0, -20.0, 0.0],
	["Trailhead", "features/feature_container_stack", 28.0, -18.0, 20.0],
	["Trailhead", "fortifications/fort_hesco_wall", -8.0, -26.0, 0.0],
	["Trailhead", "fortifications/fort_hesco_wall", 8.0, -26.0, 0.0],
	["Trailhead", "machines/machine_bulldozer", 26.0, 14.0, 200.0],
	["Trailhead", "machines/machine_semi_truck", -28.0, 16.0, 95.0],
	["Trailhead", "fortifications/fort_floodlight_mast", 0.0, -32.0, 0.0],
	["Trailhead", "props/prop_crates", -14.0, 4.0, 15.0],
	["Trailhead", "props/prop_barrels", -10.0, 12.0, 0.0],
	["Trailhead", "props/prop_jersey_barrier", 6.0, 6.0, 8.0],
	["Trailhead", "props/prop_jersey_barrier", 12.0, 4.0, 8.0],
	["Trailhead", "props/prop_lamp_post", 34.0, 22.0, 0.0],

	# ── THE CISTERN. Tanks and a pump house, and the pipe runs are the cover.
	["Cistern", "features/feature_fuel_tanks", 2.0, -8.0, 0.0],
	["Cistern", "building_house_small", -18.0, 8.0, 25.0],
	["Cistern", "props/prop_concrete_pipes", 10.0, 6.0, 10.0],
	["Cistern", "props/prop_concrete_pipes", 16.0, 2.0, 70.0],
	["Cistern", "compute/compute_cooling_unit", 0.0, 12.0, 0.0],
	["Cistern", "props/prop_sandbag_wall", 6.0, 16.0, 0.0],
	["Cistern", "props/prop_rubble_pile", 18.0, -12.0, 0.0],
	["Cistern", "props/prop_barrels", 12.0, 13.0, 0.0],

	# ── THE PILLARS. Named for what stands on it: rock spires with a pylon
	# line run through them. The spires ARE the cover, and they break a crown
	# that was otherwise a billiard table.
	["Pillars", "features/feature_rock_spire", -14.0, -10.0, 0.0],
	["Pillars", "features/feature_rock_spire", 10.0, -12.0, 140.0],
	["Pillars", "features/feature_rock_spire", 16.0, 6.0, 60.0],
	["Pillars", "features/feature_power_pylon", -2.0, 2.0, 0.0],
	["Pillars", "props/prop_boulder_c", -20.0, 6.0, 0.0],
	["Pillars", "props/prop_boulder_a", 4.0, 14.0, 0.0],
	["Pillars", "props/prop_rock_slabs", 22.0, -4.0, 45.0],
	["Pillars", "props/prop_tank_trap", -8.0, 13.0, 0.0],

	# ── THE GATE. The foot of the climb: a checkpoint on the road, teeth
	# across it, a pillbox looking back down the hill.
	["Gate", "fortifications/fort_checkpoint", 0.0, 8.0, 0.0],
	["Gate", "features/feature_pillbox", -16.0, -10.0, 0.0],
	["Gate", "fortifications/fort_dragon_teeth", 14.0, -8.0, 80.0],
	["Gate", "fortifications/fort_hesco_wall", -20.0, 6.0, 90.0],
	["Gate", "fortifications/fort_sentry_turret", 18.0, 6.0, 180.0],
	["Gate", "props/prop_car_wreck", -6.0, -15.0, 130.0],
	["Gate", "props/prop_sandbag_nest", 6.0, -15.0, 0.0],

	# ── THE TERRACE. A dug-in position on the shelf, and the one that looks
	# up at the fort.
	["Terrace", "fortifications/fort_gun_emplacement", 2.0, -9.0, 0.0],
	["Terrace", "fortifications/fort_ammo_dump", -14.0, -8.0, 0.0],
	["Terrace", "fortifications/fort_hesco_wall", 12.0, 6.0, 0.0],
	["Terrace", "fortifications/fort_hesco_wall", -4.0, 10.0, 0.0],
	["Terrace", "fortifications/fort_t_walls", 20.0, -2.0, 70.0],
	["Terrace", "props/prop_sandbag_wall", -20.0, 4.0, 0.0],
	["Terrace", "props/prop_crates", -16.0, 14.0, 20.0],
	["Terrace", "props/prop_robot_wreck", 22.0, -12.0, 60.0],

	# ── THE SHOULDER. A mortar position below the fort, and the wreck of
	# whatever tried this before.
	["Shoulder", "fortifications/fort_mortar_pit", -8.0, -8.0, 0.0],
	["Shoulder", "fortifications/fort_hesco_sangar", 10.0, -6.0, 30.0],
	["Shoulder", "fortifications/fort_hesco_wall", -18.0, 6.0, 90.0],
	["Shoulder", "props/prop_sandbag_wall", 2.0, 10.0, 0.0],
	["Shoulder", "props/prop_robot_wreck", 18.0, 6.0, 200.0],
	["Shoulder", "props/prop_rubble_pile", 20.0, -10.0, 0.0],
	["Shoulder", "props/prop_barrels", -18.0, -10.0, 0.0],
]


## The dressing as plain [piece, ...] rows, for the ext_resource count.
func _dress_pieces() -> Array:
	var out: Array = []
	for d: Array in STATION_DRESS:
		out.append([d[1], d[2], d[3], d[4]])
	return out


## The ring, built rather than typed: eighteen segments, two of them gates.
## Same [piece, x, z, yaw] shape as SUMMIT_PIECES, offsets from the summit.
func wall_pieces() -> Array:
	if OS.get_environment("NOWALL") != "":
		# Isolation switch, used once to prove the wall was NOT what broke the
		# navmesh. Kept: it is the cheapest way to ask that question again.
		return []
	var out: Array = []
	# fort_wall and fort_gate are 24 m along their OWN Z, so the runs that go
	# along X are turned a quarter.
	for x: float in [-48.0, -24.0, 0.0, 24.0, 48.0]:
		out.append([("fortress/fort_gate" if is_equal_approx(x, GATE_AT)
				else "fortress/fort_wall"), x, WALL_HALF.y, 90.0])
		# The postern, on the far side from the road. A compound with one way
		# in and out is a cul-de-sac: you fight in through the south gate and
		# leave by the back, which is where the level exit is.
		out.append([("fortress/fort_gate" if is_equal_approx(x, POSTERN_AT)
				else "fortress/fort_wall"), x, -WALL_HALF.y, 90.0])
	# THE SIDE RUNS ARE PUSHED OUT BY HALF THE WALL'S THICKNESS, so their inner
	# face lands exactly on the end of the runs above rather than inside them.
	# At WALL_HALF.x the two interpenetrated by 1.6 m at every corner — four
	# lumps of doubled brushwork that z-fight in game. Butted, they share a
	# face and nothing else.
	for z: float in [-36.0, -12.0, 12.0, 36.0]:
		out.append(["fortress/fort_wall", -WALL_HALF.x - WALL_THICK * 0.5, z, 0.0])
		out.append(["fortress/fort_wall", WALL_HALF.x + WALL_THICK * 0.5, z, 0.0])
	# THE FOUR SPURS ARE GONE. They were meant to cut the strip outside the
	# ring into pockets so the postern could not be walked round to, and the
	# ring test says plainly that they did not: it read the wall as holding on
	# none of six bearings with them exactly as it did without. What they DID
	# do was drive 6 m into the end of each side run — by far the worst
	# overlapping brushwork on the piece. Geometry that fails its own test and
	# costs that much comes out.
	return out


## Half-extents of the plateau the relay stands on, less a margin for the lip.
const SHELF_HALF := Vector2(68.0, 54.0)
## The plateau pad itself, which the wall ring and its spurs may reach.
const PAD_HALF := Vector2(78.0, 62.0)
## Clear ground between two pieces, so dressing them later does not collide.
const MARGIN := 1.5


## Every piece measured against the shelf and against every other piece.
## Returns the number of problems. Loads the real scenes: the docs round the
## numbers and an origin is often not in the middle of the mass.
## Every group of placed pieces: the summit compound, then each station's
## dressing. Same test for all of them — on the pad, and clear of each other.
func _installation() -> int:
	var bad := await _group("summit", SUMMIT_PIECES + wall_pieces(),
			Vector2.ZERO, SHELF_HALF, PAD_HALF)
	for s: Array in STATIONS:
		var dress: Array = []
		for d: Array in STATION_DRESS:
			if str(d[0]) == str(s[0]):
				dress.append([d[1], d[2], d[3], d[4]])
		if dress.is_empty():
			continue
		# Pieces may sit a little past the pad edge — the falloff keeps the
		# ground near level for a few metres — but not far, or they hang.
		var room := Vector2(float(s[4]), float(s[5])) * 0.5 + Vector2(6.0, 6.0)
		bad += await _group(str(s[0]), dress, Vector2(float(s[1]), float(s[2])), room, room)
	return bad


func _group(label: String, pieces: Array, origin: Vector2, room_a: Vector2, room_b: Vector2) -> int:
	var bad := 0
	var boxes: Array = []
	print("   %-38s %9s %9s %8s" % ["%s piece" % label, "x", "z", "size"])
	for p: Array in pieces:
		var path := "res://maps/blocks/%s.tscn" % p[0]
		var packed := load(path) as PackedScene
		if packed == null:
			print("   %-38s WILL NOT LOAD" % p[0])
			bad += 1
			continue
		var inst := packed.instantiate() as Node3D
		# Into the tree first. A CollisionShape3D's global_transform is only
		# meaningful once it has one, and measuring outside the tree gives every
		# shape the piece's origin.
		root.add_child(inst)
		await process_frame
		var box := _collision_aabb(inst)
		inst.free()
		var at := Vector2(float(p[1]), float(p[2]))
		var yaw := deg_to_rad(float(p[3]))
		var off := Vector2(box.position.x + box.size.x * 0.5, box.position.z + box.size.z * 0.5)
		var centre := at + Vector2(off.x * cos(yaw) + off.y * sin(yaw),
				-off.x * sin(yaw) + off.y * cos(yaw))
		# The rotated footprint as an axis-aligned rectangle. A circle round the
		# diagonal was the first try and it was useless: a 29 m hall gets a 17 m
		# radius and then reports an overlap with anything within 17 m of its
		# CENTRE, which on a 92 m shelf is most of the map.
		var half := Vector2(box.size.x, box.size.z) * 0.5
		var rot := Vector2(
				absf(half.x * cos(yaw)) + absf(half.y * sin(yaw)),
				absf(half.x * sin(yaw)) + absf(half.y * cos(yaw)))
		var ring: bool = str(p[0]).begins_with("fortress/")
		var note := ""
		# SHELF_HALF is a margin for things that stand ON the plateau. The wall
		# ring is measured against the pad itself, because reaching the lip is
		# what a curtain wall is FOR.
		var room := room_b if ring else room_a
		if absf(centre.x) + rot.x > room.x or absf(centre.y) + rot.y > room.y:
			note = "   OFF THE SHELF"
			bad += 1
		for b: Array in boxes:
			var d: Vector2 = (centre - (b[1] as Vector2)).abs() - rot - (b[2] as Vector2)
			# MARGIN, not zero. These get dressed later and grow parapets,
			# handrails and cable trays; touching now is overlapping then.
			#
			# THE RING IS THE EXCEPTION, and only just. A curtain wall has to
			# touch itself or it is a row of slabs, so ring-against-ring is
			# allowed to meet at a face — but NOT to interpenetrate, which is
			# what this used to skip entirely. Skipping it hid four corners
			# driven 1.6 m into each other and four spurs driven 6 m in, all of
			# which z-fight in game. Butt joints pass; overlaps do not.
			var allow: float = -0.05 if (ring and bool(b[3])) else MARGIN
			var gap: float = maxf(d.x, d.y)
			if gap < allow:
				note = "   %s %s by %.1f m" % [
						"OVERLAPS" if gap < 0.0 else "crowds", b[0], allow - gap]
				bad += 1
		boxes.append([str(p[0]).get_file(), centre, rot, ring])
		print("   %-38s %8.0fm %8.0fm %6.0fx%.0f%s" % [
				str(p[0]).get_file(), centre.x, centre.y, rot.x * 2.0, rot.y * 2.0, note])
	return bad


## The union of a piece's CollisionShape3D boxes, in the piece's own space.
func _collision_aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in node.find_children("*", "CollisionShape3D", true, false):
		var cs := c as CollisionShape3D
		if cs.shape == null:
			continue
		var box := cs.shape.get_debug_mesh().get_aabb()
		var t := cs.global_transform
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for i in 8:
			var w := t * box.get_endpoint(i)
			lo = Vector3(minf(lo.x, w.x), minf(lo.y, w.y), minf(lo.z, w.z))
			hi = Vector3(maxf(hi.x, w.x), maxf(hi.y, w.y), maxf(hi.z, w.z))
		var one := AABB(lo, hi - lo)
		out = one if first else out.merge(one)
		first = false
	if first:
		# No collision at all. Give it a metre so it still gets spaced.
		out = AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 2.0, 2.0))
	return out


func _grades(by_name: Dictionary) -> int:
	var bad := 0
	print("   %-24s %8s %8s %8s %8s" % ["leg", "run", "rise", "grade", "cut"])
	for l: Array in LEGS:
		var a: Array = by_name[l[0]]
		var b: Array = by_name[l[1]]
		var run := Vector2(float(b[1]) - float(a[1]), float(b[2]) - float(a[2])).length()
		var rise := float(b[3]) - float(a[3])
		# The grade of the GRADED part: the run-outs at each end are level, so
		# the climb is squeezed into what is left. Each end's run-out is however
		# far it takes to cross that station's own pad, so a big pad on a short
		# leg is what makes a grade fail here — move the station, or shrink it.
		var dir := Vector2(float(b[1]) - float(a[1]), float(b[2]) - float(a[2])).normalized()
		var ends := _runout(a, dir) + _runout(b, dir)
		if ends >= run - 8.0:
			bad += 1
			print("   %-24s %7.0fm %7.0fm  PADS EAT THE LEG — %.0f m of run-out in %.0f m" % [
					"%s → %s" % [l[0], l[1]], run, rise, ends, run])
			continue
		var graded: float = maxf(run - ends, 0.001)
		var grade := rad_to_deg(atan2(rise, graded))
		# How far the bed sits off the natural ground at the midpoint: a big
		# number means an embankment across the face rather than a shelf in it.
		var mid := Vector2((float(a[1]) + float(b[1])) * 0.5, (float(a[2]) + float(b[2])) * 0.5)
		var cut := (float(a[3]) + float(b[3])) * 0.5 - cone_h((mid - SUMMIT).length())
		if absf(grade) > MAX_GRADE:
			bad += 1
		print("   %-24s %7.0fm %7.0fm %7.1f°%s %7.0fm" % [
				"%s → %s" % [l[0], l[1]], run, rise, grade,
				"!" if absf(grade) > MAX_GRADE else " ", cut])
	return bad


## The scene text. ext_resource ids and load_steps are counted here rather than
## written by hand: check.sh fails a scene whose load_steps is off by one, and
## it has caught that twice already on hand-edited levels.
func _scene(by_name: Dictionary) -> String:
	var ext: Array = [
		["Script", "res://maps/trench_broom_level.gd", "1_level", ""],
		["PackedScene", "res://Env/world_objects/spawn_point.tscn", "2_spawn", "uid://g7fmy28elpah"],
		["Script", "res://Campaign/squad_spawn_point.gd", "3_squad", ""],
		["Script", "res://Env/terrain/generated_terrain.gd", "5_terrain", ""],
		["Script", "res://Env/terrain/terrain_recipe.gd", "6_recipe", ""],
		["Script", "res://Env/terrain/terrain_stamp.gd", "7_stamp", ""],
		["Script", "res://Env/terrain/terrain_path.gd", "8_path", ""],
		["Texture2D", "res://Env/terrain/sketches/hillfort.png", "9_sketch", ""],
		["PackedScene", "res://Env/world_objects/level_exit.tscn", "10_exit", "uid://big5ms541m2j7"],
		["PackedScene", "res://Env/world_environment.tscn", "11_env", "uid://cml2uoky1hnes"],
		["Shader", "res://Env/new_sky_oct.16.gdshader", "12_sky", ""],
		["PackedScene", "res://Env/world_objects/squad_objective_point.tscn",
				"14_sqpoint", "uid://62y43tyd5sx6"],
	]
	# The terrain data file does not exist until the first bake, and an
	# ext_resource pointing at a missing file is the silent-null bug check.sh
	# hunts for. So: write without it, bake, run this again — the second pass
	# picks it up. Nothing else about the scene changes between the two.
	var data_path := "res://maps/terrain_data/hillfort_level_terrain.res"
	var has_data := ResourceLoader.exists(data_path)
	if has_data:
		ext.append(["Resource", data_path, "13_data", ""])
	# One ext_resource per DISTINCT summit piece, however many times it is
	# placed. check.sh fails a scene that declares an id it never uses and a
	# scene whose load_steps is off, so both are counted rather than typed.
	var seen := {}
	for p: Array in SUMMIT_PIECES + wall_pieces() + _dress_pieces():
		var id: String = "p_" + str(p[0]).get_file()
		if seen.has(id):
			continue
		seen[id] = true
		ext.append(["PackedScene", "res://maps/blocks/%s.tscn" % p[0], id, ""])

	var subs: Array = ["NavigationMesh_hillfort", "Resource_recipe", "ShaderMaterial_sky",
			"Sky_hillfort", "Environment_hillfort"]
	var curves := {}
	for l: Array in LEGS:
		curves["Curve3D_%s_%s" % [str(l[0]).to_snake_case(), str(l[1]).to_snake_case()]] = l
	for k: String in curves:
		subs.append(k)

	var out: PackedStringArray = []
	out.append("[gd_scene load_steps=%d format=3 uid=\"uid://bhlfrt4rt0m1\"]" % (
			ext.size() + subs.size() + 1))
	out.append("")
	for e: Array in ext:
		var uid: String = " uid=\"%s\"" % e[3] if e[3] != "" else ""
		out.append("[ext_resource type=\"%s\"%s path=\"%s\" id=\"%s\"]" % [e[0], uid, e[1], e[2]])
	out.append("")

	# The navmesh. agent_max_slope is written down here on purpose: MIN_FACE
	# above is only a guarantee if this number is the one the baker uses, and
	# a default is invisible until somebody changes it.
	out.append("[sub_resource type=\"NavigationMesh\" id=\"NavigationMesh_hillfort\"]")
	# Empty placeholders: probe_nav_hillfort.gd replaces these two lines in place
	# with the baked result, and it can only replace a line that is there.
	out.append("vertices = PackedVector3Array()")
	out.append("polygons = []")
	# STATIC COLLIDERS, not mesh instances. A brush prefab's visual mesh is a
	# hollow box, so parsing meshes reads the inside of the data hall as a room
	# and lays a floor on every slab in it. The terrain builds real collision, so
	# this picks up the ground as well.
	out.append("geometry_parsed_geometry_type = 1")
	out.append("agent_radius = 0.5")
	out.append("agent_height = 1.8")
	out.append("agent_max_climb = 0.5")
	out.append("agent_max_slope = %.1f" % NAV_MAX_SLOPE)
	out.append("region_min_size = 6.0")
	out.append("edge_max_error = 2.0")
	out.append("detail_sample_distance = 16.0")
	out.append("filter_baking_aabb = AABB(%.0f, -40, %.0f, %.0f, 700, %.0f)" % [
			-SIZE_X * 0.5 - 8.0, -SIZE_Z * 0.5 - 8.0, SIZE_X + 16.0, SIZE_Z + 16.0])
	out.append("")

	out.append("[sub_resource type=\"Resource\" id=\"Resource_recipe\"]")
	out.append("script = ExtResource(\"6_recipe\")")
	for line in _recipe():
		out.append(line)
	out.append("")

	for k: String in curves:
		out.append("[sub_resource type=\"Curve3D\" id=\"%s\"]" % k)
		out.append("bake_interval = 2.0")
		out.append(_curve(by_name, curves[k]))
		out.append("")

	out.append("[sub_resource type=\"ShaderMaterial\" id=\"ShaderMaterial_sky\"]")
	out.append("shader = ExtResource(\"12_sky\")")
	out.append("shader_parameter/top_color = Color(0.1, 0.13, 0.19, 1)")
	out.append("shader_parameter/bottom_color = Color(0.52, 0.5, 0.47, 1)")
	out.append("shader_parameter/fog_color = Color(0.46, 0.46, 0.45, 1)")
	out.append("shader_parameter/horizon_falloff = 1.9")
	out.append("shader_parameter/fog_amount = 0.32")
	out.append("shader_parameter/fog_falloff = 3.4")
	out.append("shader_parameter/brightness = 0.85")
	out.append("")
	out.append("[sub_resource type=\"Sky\" id=\"Sky_hillfort\"]")
	out.append("sky_material = SubResource(\"ShaderMaterial_sky\")")
	out.append("radiance_size = 0")
	out.append("")
	out.append("[sub_resource type=\"Environment\" id=\"Environment_hillfort\"]")
	out.append("background_mode = 2")
	out.append("sky = SubResource(\"Sky_hillfort\")")
	out.append("ambient_light_source = 3")
	out.append("ambient_light_color = Color(0.36, 0.38, 0.42, 1)")
	out.append("ambient_light_sky_contribution = 0.7")
	out.append("ambient_light_energy = 0.7")
	out.append("tonemap_mode = 2")
	out.append("fog_enabled = true")
	out.append("fog_light_color = Color(0.5, 0.52, 0.55, 1)")
	# Thinner than the valley maps. Height fog over a 500 m mountain hides the
	# summit from the trailhead, and seeing where you are going is the whole
	# point of a climb.
	out.append("fog_density = 0.00032")
	out.append("fog_sky_affect = 0.3")
	out.append("fog_height = -60.0")
	out.append("fog_height_density = 0.004")
	# Glow, so the machines' seams read as light rather than as a pale stripe.
	# glitch_tx_1 carries emission now; without this the level has the emission
	# and none of the bloom.
	out.append("glow_enabled = true")
	out.append("glow_intensity = 0.55")
	out.append("glow_bloom = 0.05")
	out.append("glow_hdr_threshold = 1.0")
	out.append("")

	var trail: Array = by_name["Trailhead"]
	var summit: Array = by_name["Summit"]
	out.append("[node name=\"HillfortLevel\" type=\"Node3D\" node_paths=PackedStringArray(\"spawn_point\", \"nav_region\", \"level_exits\")]")
	out.append("script = ExtResource(\"1_level\")")
	out.append("spawn_point = NodePath(\"SpawnPoint\")")
	out.append("nav_region = NodePath(\"NavigationRegion3D\")")
	out.append("level_exits = [NodePath(\"NavigationRegion3D/LevelExit\")]")
	out.append("")
	out.append("[node name=\"SpawnPoint\" parent=\".\" instance=ExtResource(\"2_spawn\")]")
	# INSIDE THE PAD, measured off its own size. A fixed offset survived two pad
	# resizes and then put the spawn out on the hillside, where it snapped to a
	# scrap of navmesh that joined nothing and reported the ENTIRE MAP cut off.
	out.append(_xform(float(trail[1]), float(trail[3]) + 1.15,
			float(trail[2]) + float(trail[5]) * 0.5 - 16.0))
	out.append("")
	out.append("[node name=\"SquadSpawnPoint\" type=\"Node3D\" parent=\".\"]")
	out.append(_xform(float(trail[1]) - 14.0, float(trail[3]),
			float(trail[2]) + float(trail[5]) * 0.5 - 26.0))
	out.append("script = ExtResource(\"3_squad\")")
	out.append("")
	out.append("[node name=\"NavigationRegion3D\" type=\"NavigationRegion3D\" parent=\".\"]")
	out.append("navigation_mesh = SubResource(\"NavigationMesh_hillfort\")")
	out.append("")
	out.append("[node name=\"Terrain\" type=\"Node3D\" parent=\"NavigationRegion3D\"]")
	out.append("script = ExtResource(\"5_terrain\")")
	out.append("recipe = SubResource(\"Resource_recipe\")")
	if has_data:
		out.append("data = ExtResource(\"13_data\")")
	out.append("")

	# ORDER IS THE WHOLE POINT. Modifiers are collected depth-first in tree
	# order and a later one wins, so: the hills and the massif raise the ground,
	# the shelves cut flats into it, and the roads cut last of all. Move Roads
	# above Shelves and every landing swallows the flight arriving at it.
	out.append("[node name=\"Hills\" type=\"Node3D\" parent=\"NavigationRegion3D/Terrain\"]")
	out.append("")
	var hi := 1
	for hll: Array in HILLS:
		out.append("[node name=\"Hill%d\" type=\"Node3D\" parent=\"NavigationRegion3D/Terrain/Hills\"]" % hi)
		out.append(_xform(float(hll[0]), 0.0, float(hll[1])))
		out.append("script = ExtResource(\"7_stamp\")")
		out.append("shape = 1")
		out.append("radius = %.1f" % float(hll[2]))
		out.append("falloff = %.1f" % float(hll[3]))
		out.append("amount = %.1f" % float(hll[4]))
		out.append("paint = 0")
		out.append("")
		hi += 1

	out.append("[node name=\"Hollows\" type=\"Node3D\" parent=\"NavigationRegion3D/Terrain\"]")
	out.append("")
	var oi := 1
	for o: Array in HOLLOWS:
		out.append("[node name=\"Hollow%d\" type=\"Node3D\" parent=\"NavigationRegion3D/Terrain/Hollows\"]" % oi)
		out.append(_xform(float(o[0]), 0.0, float(o[1])))
		out.append("script = ExtResource(\"7_stamp\")")
		out.append("shape = 2")
		out.append("radius = %.1f" % float(o[2]))
		out.append("falloff = %.1f" % float(o[3]))
		out.append("amount = %.1f" % float(o[4]))
		out.append("paint = 0")
		out.append("")
		oi += 1

	out.append("[node name=\"HighGround\" type=\"Node3D\" parent=\"NavigationRegion3D/Terrain\"]")
	out.append("")
	var ci := 1
	for c: Array in CONES:
		out.append("[node name=\"Cone%d\" type=\"Node3D\" parent=\"NavigationRegion3D/Terrain/HighGround\"]" % ci)
		out.append(_xform(SUMMIT.x, 0.0, SUMMIT.y))
		out.append("script = ExtResource(\"7_stamp\")")
		out.append("shape = 1")
		out.append("radius = %.1f" % float(c[0]))
		out.append("falloff = %.1f" % float(c[1]))
		out.append("amount = %.1f" % float(c[2]))
		out.append("paint = 0")
		out.append("")
		ci += 1

	out.append("[node name=\"Shelves\" type=\"Node3D\" parent=\"NavigationRegion3D/Terrain\"]")
	out.append("")
	for s: Array in STATIONS:
		out.append("[node name=\"%s\" type=\"Node3D\" parent=\"NavigationRegion3D/Terrain/Shelves\"]" % s[0])
		out.append(_xform(float(s[1]), float(s[3]), float(s[2])))
		out.append("script = ExtResource(\"7_stamp\")")
		out.append("footprint = 1")
		out.append("size = Vector2(%.0f, %.0f)" % [float(s[4]), float(s[5])])
		out.append("falloff = %.1f" % float(s[6]))
		out.append("paint = 1")
		out.append("")

	out.append("[node name=\"Roads\" type=\"Node3D\" parent=\"NavigationRegion3D/Terrain\"]")
	out.append("")
	for k: String in curves:
		var l: Array = curves[k]
		out.append("[node name=\"%s_%s\" type=\"Path3D\" parent=\"NavigationRegion3D/Terrain/Roads\"]" % [l[0], l[1]])
		out.append("curve = SubResource(\"%s\")" % k)
		out.append("script = ExtResource(\"8_path\")")
		out.append("width = %.1f" % float(l[2]))
		out.append("falloff = %.1f" % float(l[3]))
		# follow_terrain OFF is what makes this a climb rather than a track over
		# whatever is already there: the ground is graded to the curve's own Y,
		# which is the number checked above.
		out.append("follow_terrain = false")
		out.append("")

	# Inside the NavigationRegion3D, so the baker sees the buildings and does not
	# lay navmesh through the hall and the mast.
	out.append("[node name=\"Relay\" type=\"Node3D\" parent=\"NavigationRegion3D\"]")
	out.append("")

	var ri := 1
	for p: Array in SUMMIT_PIECES + wall_pieces():
		var id: String = "p_" + str(p[0]).get_file()

		var yaw := deg_to_rad(float(p[3]))
		out.append("[node name=\"Relay%02d_%s\" parent=\"NavigationRegion3D/Relay\" instance=ExtResource(\"%s\")]" % [ri, str(p[0]).get_file(), id])
		out.append("transform = Transform3D(%s, 0, %s, 0, 1, 0, %s, 0, %s, %s, %s, %s)" % [
				_n(cos(yaw)), _n(-sin(yaw)), _n(sin(yaw)), _n(cos(yaw)),
				_n(float(summit[1]) + float(p[1])), _n(float(summit[3])),
				_n(float(summit[2]) + float(p[2]))])
		out.append("")
		ri += 1

	# ON THE DATA HALL ROOF, reached by the hall's own external stair. The first
	# try was the strip outside the postern, and the ring test killed it: the
	# hillside below the plateau is walkable, so anything can go round the
	# outside and up into that pocket without ever entering the compound. A roof
	# ten metres up inside the wall cannot be reached any way but through it.
	out.append("[node name=\"Stations\" type=\"Node3D\" parent=\"NavigationRegion3D\"]")
	out.append("")
	var si := 1
	for d: Array in STATION_DRESS:
		var st: Array = by_name[d[0]]
		var did: String = "p_" + str(d[1]).get_file()
		var dyaw := deg_to_rad(float(d[4]))
		out.append("[node name=\"%s%02d_%s\" parent=\"NavigationRegion3D/Stations\" instance=ExtResource(\"%s\")]" % [d[0], si, str(d[1]).get_file(), did])
		out.append("transform = Transform3D(%s, 0, %s, 0, 1, 0, %s, 0, %s, %s, %s, %s)" % [
				_n(cos(dyaw)), _n(-sin(dyaw)), _n(sin(dyaw)), _n(cos(dyaw)),
				_n(float(st[1]) + float(d[2])), _n(float(st[3])),
				_n(float(st[2]) + float(d[3]))])
		out.append("")
		si += 1

	out.append("[node name=\"LevelExit\" parent=\"NavigationRegion3D\" instance=ExtResource(\"10_exit\")]")
	out.append(_xform(float(summit[1]) + HALL_AT.x, float(summit[3]) + HALL_ROOF,
			float(summit[2]) + HALL_AT.y))
	out.append("")
	out.append("[node name=\"WorldEnvironment\" parent=\".\" instance=ExtResource(\"11_env\")]")
	out.append("environment = SubResource(\"Environment_hillfort\")")
	out.append("")
	out.append("[node name=\"Sun\" parent=\"WorldEnvironment\" index=\"0\"]")
	# Low and from the south-east, so the face the stair climbs is lit and the
	# switchbacks cast shadows across each other.
	out.append("transform = Transform3D(0.633, 0.548, -0.547, 0, 0.706, 0.708, 0.774, -0.448, 0.447, 0, 0, 0)")
	out.append("shadow_opacity = 0.9")
	out.append("directional_shadow_max_distance = 500.0")
	out.append("")
	out.append("[node name=\"EnemySquadObjs\" type=\"Node\" parent=\".\"]")
	out.append("")
	for o: Array in OBJECTIVES:
		out.append("[node name=\"%s\" parent=\"EnemySquadObjs\" instance=ExtResource(\"14_sqpoint\")]" % o[0])
		out.append(_xform(float(o[3]), float(o[5]), float(o[4])))
		out.append("objective_name = \"%s\"" % o[2])
		out.append("tag = &\"%s\"" % o[1])
		out.append("show_debug_label = false")
		out.append("")
	for p: Array in PATROLS:
		# A patrol point is a CHILD of its anchor, so its transform is relative
		# to it. The table holds world coordinates, which is how they are read
		# and checked, so the anchor's own position comes off here — emitted
		# raw, the first run put the yard patrol at twice its coordinates and
		# half a kilometre off the map.
		var at := Vector3.ZERO
		for o: Array in OBJECTIVES:
			if str(o[0]) == str(p[0]):
				at = Vector3(float(o[3]), float(o[5]), float(o[4]))
		var pi := 1
		for pt: Array in p[1]:
			out.append("[node name=\"Patrol%d\" type=\"Node3D\" parent=\"EnemySquadObjs/%s\"]" % [pi, p[0]])
			out.append(_xform(float(pt[0]) - at.x, float(pt[2]) - at.y, float(pt[1]) - at.z))
			out.append("")
			pi += 1

	out.append("[editable path=\"WorldEnvironment\"]")
	out.append("")
	return "\n".join(out)


func _recipe() -> PackedStringArray:
	return PackedStringArray([
		"size_x = %.1f" % SIZE_X,
		"size_z = %.1f" % SIZE_Z,
		"cell_size = 2.0",
		"random_seed = 19",
		# OPEN, not VALLEY: a valley floor would cut a trough through the
		# foothills, and the shape of this map is the massif, not a basin.
		"layout = 2",
		"floor_at_zero = true",
		"floor_width = 400.0",
		"floor_shoulder = 200.0",
		"floor_depth = 4.0",
		"floor_roughness = 0.3",
		"floor_edge_noise = 0.4",
		"meander = 0.0",
		"meander_scale = 600.0",
		# North off: the massif IS the north edge, and a border range on top of
		# it would stack into a wall behind the summit.
		"border_sides = 13",
		"border_height = 44.0",
		"border_width = 100.0",
		"border_noise = 60.0",
		"border_ruggedness = 0.7",
		"hills_height = 5.0",
		"hills_scale = 240.0",
		"hills_octaves = 5",
		"hills_warp = 60.0",
		"ridge_height = 5.0",
		"ridge_scale = 340.0",
		"ridge_on_floor = 0.08",
		"detail_height = 0.7",
		"detail_scale = 16.0",
		"terrace_step = 0.0",
		"terrace_strength = 0.75",
		"crater_count = 24",
		"crater_radius_min = 3.0",
		"crater_radius_max = 12.0",
		"crater_depth = 0.3",
		"crater_rim = 0.1",
		"craters_on_floor = true",
		# Talus high and hydraulic low: thermal erosion at the usual 42° would
		# knock the massif's flanks down to 42°, which is UNDER the navmesh's
		# 45° — the stair would still be there and nothing would use it.
		"thermal_passes = 3",
		"talus_angle = 66.0",
		"hydraulic_strength = 0.25",
		"smooth_passes = 2",
		"sketch = ExtResource(\"9_sketch\")",
		"sketch_metres_per_pixel = 4.0",
		"sketch_blend = 26.0",
		"sketch_edge_noise = 30.0",
		# Low on purpose. The white mask is here for the rock zone and for
		# crags; the 500 m is stamped on afterwards, in the final datum.
		"sketch_mountain_height = 4.0",
		# No painted water anywhere, and the level parked far below the map:
		# water_level is ONE global height, so a tarn on a shelf 300 m up would
		# flood the valley to match.
		"water_level = -200.0",
		"water_depth = 5.0",
		"water_bank = 30.0",
		"urban_block = Vector2(40, 32)",
		"urban_street = 8.0",
		"urban_angle = 0.0",
		"urban_ruin = 0.25",
		"shelling_per_hectare = 30.0",
		"rough_height = 7.0",
		"road_width = 5.0",
		"road_falloff = 5.0",
		"road_smoothing = 40.0",
		"bridge_clearance = 2.0",
	])


## A leg's curve. Heights are spread along the polyline BY ARC LENGTH, so the
## grade is the same at every point of the graded part whatever shape the leg
## is bent into — and the first and last RUNOUT metres are dead level.
##
## THE RUN-OUT IS NOT DECORATION. Two flights meet at a landing and their beds
## overlap for 20-odd metres around it. Whichever is cut second wins that
## ground, so if either is still climbing when it gets there it writes its own
## height across the other one's bed and leaves a step — 8 m of step, in the
## run that found this, which walled off the whole stair above the Gate. Both
## flights arriving level at the landing's own height means the overlap is two
## cuts asking for the same number, and the step cannot happen.
func _curve(by_name: Dictionary, leg: Array) -> String:
	var a: Array = by_name[leg[0]]
	var b: Array = by_name[leg[1]]
	var pts: Array[Vector2] = [Vector2(float(a[1]), float(a[2]))]
	for v in _vias(str(a[0]), str(b[0])):
		pts.append(v)
	pts.append(Vector2(float(b[1]), float(b[2])))
	var cum: Array[float] = [0.0]
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total: float = maxf(cum[cum.size() - 1], 0.001)
	# The two kinks in the height profile become real curve points, or the
	# resampler rounds the corner and the run-out is not level after all.
	var dir := (pts[pts.size() - 1] - pts[0]).normalized()
	var r0: float = minf(_runout(a, dir), total * 0.45)
	var r1: float = minf(_runout(b, dir), total * 0.45)
	for s: float in [r0, total - r1]:
		var at := _along(pts, cum, s)
		var slot := 1
		while slot < cum.size() and cum[slot] < s:
			slot += 1
		pts.insert(slot, at)
		cum.insert(slot, s)
	var nums: PackedStringArray = []
	for i in pts.size():
		var y := _height(float(a[3]), float(b[3]), cum[i], total, r0, r1)
		# Zero handles: every segment is a straight line, so the height really
		# is linear in arc length. A Bezier handle would bow the curve and the
		# grade with it.
		nums.append("0, 0, 0, 0, 0, 0, %s, %s, %s" % [_n(pts[i].x), _n(y), _n(pts[i].y)])
	return "_data = {\n\"points\": PackedVector3Array(%s),\n\"tilts\": PackedFloat32Array(%s)\n}\npoint_count = %d" % [
			", ".join(nums), ", ".join(_zeros(pts.size())), pts.size()]


## Level for `r0` at the start and `r1` at the end, one constant grade between.
func _height(y0: float, y1: float, s: float, total: float, r0: float, r1: float) -> float:
	var graded: float = maxf(total - r0 - r1, 0.001)
	return lerpf(y0, y1, clampf((s - r0) / graded, 0.0, 1.0))


## The point `s` metres along the polyline.
func _along(pts: Array[Vector2], cum: Array[float], s: float) -> Vector2:
	for i in range(1, pts.size()):
		if cum[i] >= s:
			var span: float = maxf(cum[i] - cum[i - 1], 0.001)
			return pts[i - 1].lerp(pts[i], (s - cum[i - 1]) / span)
	return pts[pts.size() - 1]


## Bends, so the foothill roads wrap the ground instead of ruling a line over
## it. The five flights are deliberately straight: a cut shelf on a 58° face
## that wanders leaves thin spurs of rock nothing can stand on.
func _vias(from_name: String, to_name: String) -> Array[Vector2]:
	match "%s-%s" % [from_name, to_name]:
		"Trailhead-Cistern":
			return [Vector2(-70.0, 402.0), Vector2(-160.0, 366.0)]
		"Cistern-Pillars":
			return [Vector2(-90.0, 288.0), Vector2(30.0, 246.0), Vector2(120.0, 214.0)]
		"Pillars-Gate":
			return [Vector2(60.0, 150.0), Vector2(-60.0, 112.0)]
		"Shoulder-Sanctum":
			return [Vector2(120.0, -212.0), Vector2(58.0, -288.0)]
	return []


func _zeros(n: int) -> PackedStringArray:
	var z: PackedStringArray = []
	for _i in n:
		z.append("0")
	return z


func _xform(x: float, y: float, z: float) -> String:
	return "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)" % [_n(x), _n(y), _n(z)]


## Godot's own float formatting, so the file reads the way the editor writes it.
func _n(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return String.num(v, 4).rstrip("0").rstrip(".")
