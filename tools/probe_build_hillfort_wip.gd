extends SceneTree

# ─────────────────────────────────────────────
# BUILD HILLFORT WIP — the same idea as Hillfort at a quarter of the size.
#
#   godot --headless --path . --script res://tools/probe_build_hillfort_wip.gd
#   PROFILE=1 godot --headless --path . --script res://tools/probe_build_hillfort_wip.gd
#   godot --headless --path . --script res://tools/probe_build_hillfort_wip.gd -- --force
#
# WHY THIS FILE EXISTS AT ALL, rather than a new table in
# tools/probe_build_hillfort.gd. That tool carries a standing warning dated
# 2026-09-29: maps/hillfort_level.tscn HAS DIVERGED from its table, and --force
# WOULD DESTROY WORK — a ReachObjective, a RelayObjective with an interactible
# and a terminal, extra patrol points and a moved spawn, none of which it can
# reproduce. So nothing here reads or writes any shipped hillfort file. New
# files only, the way maps/mutaha_wip_level.tscn was done:
#
#   maps/hillfort_wip_art.tscn                            (terrain + geometry)
#   maps/hillfort_wip_level.tscn                          (spawn, nav, objectives)
#   maps/terrain_data/hillfort_wip_level_terrain.res       (the bake)
#   Env/terrain/sketches/hillfort_wip.png                  (probe_paint_hillfort_wip.gd)
#
# BOOTSTRAPPING TAKES TWO WRITES, because the terrain data file does not exist
# until the first bake and an ext_resource pointing at a missing file is the
# silent-null bug check.sh hunts for:
#
#   probe_paint_hillfort_wip.gd
#   probe_build_hillfort_wip.gd
#   terrain_bake.gd -- res://maps/hillfort_wip_level.tscn
#   probe_build_hillfort_wip.gd -- --force
#   BAKE_ONLY=1 LEVEL=res://maps/hillfort_wip_level.tscn probe_nav_hillfort.gd
#
# PROFILE=1 prints the hill's radial profile, every road's grade, the cut or
# fill under every bench, and the whole installation measured piece against
# piece — and writes nothing. Use it to tune before baking.
#
# ── WHAT WAS WRONG WITH THE BIG ONE ─────────────────────────────────────────
#
# Played: "fairly barren and time-consuming to navigate". Measured: 0.43 km²
# with 2 capture points is 217,440 m² per objective, 3.5x sparser than the next
# worst map in the project. The fort was never the problem. The 700 m of road
# to it was.
#
# So the FORT IS KEPT AT ITS REAL SIZE — the 120 x 96 curtain ring and the 58 m
# relay dish, almost exactly as the shipped level has them — and the approach
# is cut from 1024 m of depth to 288. On the old map the compound was 1.3% of
# the ground. Here it is 11%, which is what a climax is supposed to look like.
#
# ── THE CLIMB AGAINST THE FLAT-GROUND RULE ──────────────────────────────────
#
# Playable ground must be FLAT: bots cannot use jagged terrain or painted
# ridges, so height comes from built assets and terraces. A climb is the one
# shape that fights that rule hardest, and this is the resolution:
#
#   - Every place the squad is MEANT TO FIGHT is a flat stamp. Six station pads
#     and the plateau, plus five smaller benches on the hillside between them
#     so a flanker has somewhere level to stand that is not the road.
#   - Every route between them is a TerrainPath graded to a CONSTANT grade by
#     arc length, so a ramp cannot be steep in the middle and gentle at the
#     ends — the usual way a hand-placed road fails.
#   - The hillside in between is a SMOOTH CONE at 15-30°, which is walkable
#     (agent_max_slope is 45) but is not fighting ground. It is the thing you
#     cross to flank, not the thing you hold. That distinction is the whole
#     design: FLAT WHERE IT MATTERS, SMOOTH WHERE IT DOESN'T, and nothing
#     jagged anywhere, because the recipe's own relief is turned down to 2.5 m
#     of crag and three smoothing passes.
#   - Nothing gates by being steep. The plateau is reachable from every side;
#     what stops a walk-in is the WALL, which is a thing somebody built.
#
# ── THE TWO TRAPS, NAMED ────────────────────────────────────────────────────
#
# A FLAT HILLTOP HIDES WHAT STANDS ON IT. You need prominence plus about 23 m
# of height on the NEAR lip or the objective is invisible from the approach.
# The plateau is at 70 and the two stations below it are at 42 and 46, so the
# near lip is 24-28 m, and the dish on top of that is 62 m tall. _profile()
# prints the lip from every station so this cannot quietly rot.
#
# filter_baking_aabb COVERS THE WHOLE MAP, with eight metres to spare on every
# side. On Proving that box was silently clipping the bake to the old arena,
# and a new wing would have been unwalkable with nothing saying why.
# ─────────────────────────────────────────────

const OUT_LEVEL := "res://maps/hillfort_wip_level.tscn"
const OUT_ART := "res://maps/hillfort_wip_art.tscn"
const DATA_PATH := "res://maps/terrain_data/hillfort_wip_level_terrain.res"
const SKETCH := "res://Env/terrain/sketches/hillfort_wip.png"

## 384 x 256 = 0.0983 km², which is 1.85x Valley Basin and a quarter of today's
## Hillfort.
##
## THE TERRAIN ROUNDS BOTH OF THESE UP TO WHOLE 64-CELL CHUNKS, which at a 2 m
## cell is 128 m, so the only sizes that mean anything are multiples of 128.
## 352 x 288 — the shape this was laid out to, and a number that looked
## perfectly reasonable in the brief — baked as 384 x 384: half again as much
## ground as asked for, 0.147 km², and straight out of the band. The recipe
## says so in one line of @export doc and the bake prints the real figure;
## nothing else would have caught it.
const SIZE_X := 384.0
const SIZE_Z := 256.0
## Invisible walls this far in from the edge. THE DEFAULT IS 60, and on a map
## this size 60 m a side would wall off a third of the ground and leave the
## Terrace and half the hills outside the world. The area the density number is
## computed over is this inset rectangle, not SIZE_X by SIZE_Z.
const BOUNDARY_INSET := 4.0

## A leg gentler than this is a walk; steeper and the bots start scrabbling.
const MAX_GRADE := 22.0
## The least level ground at each end of a leg, before the pad crossing is
## taken into account. See _runout.
const RUNOUT := 20.0
## What the navmesh is baked at. Written into the scene rather than defaulted:
## a default is invisible until somebody changes it.
const NAV_MAX_SLOPE := 45.0
## The near lip the brief asks for: a station below the fort that can see less
## than this much of a rise is a station the fort is invisible from.
const MIN_LIP := 23.0

## The capture cores, by path rather than by block name. _piece_path() takes
## either, so a piece from Env/world_objects sits in the same tables as a
## TrenchBroom block.
const CORE := "res://Env/world_objects/compute_core_point.tscn"
const CORE_LARGE := "res://Env/world_objects/compute_core_point_large.tscn"
## The stand-in for "derive this height off the ground" in OBJECTIVES. A real
## NAN would be cleaner and cannot be a const expression.
const NAN_Y := 1e30

## The hill, as stacked RAISE cones about the fort. [radius, falloff, amount]
##
## NO STEEP RING, and for the reason the big map's comment gives: there was one
## there, it worked, and it read as a CRATER with a fort at the bottom. The
## ground rises to the plateau at 15-30° from every side and the curtain wall
## does the gating.
##
## THE FLAT TOP IS DELIBERATELY SMALLER THAN THE PAD ABOVE IT. Cone A is flat
## out to r=110 at 46 m and cone B adds 24 more inside r=54, so the ground is
## already falling by the time the 136 x 112 pad ends at r=68..88 — which is
## what stops the fort sitting in a bowl of its own hillside.
const CONES: Array = [
	[110.0, 120.0, 46.0],
	[54.0, 80.0, 24.0],
]
const SUMMIT := Vector2(0.0, -66.0)

## name, x, z, y, pad x, pad z, falloff
##
## ── WHY THE ROUTE IS A SPIRAL AND NOT A SWITCHBACK, which is the single
## biggest thing the small scale changed.
##
## RADIUS IS ALTITUDE. The hill is radial, so a station's height is decided by
## how far it is from the fort, and the climb has to march inwards.
##
## The obvious shape is the big map's: stations alternating west and east, long
## traverses between them. It does not fit, and the reason is arithmetic. A
## chord across a circle dips inside it by about L²/8R, so a 220 m traverse at
## r≈150 passes 40 m closer to the fort than its own ends — where the hill is
## 20 m higher. The road is cut LAST and wins, so what gets built is a 21 m
## deep defile with 60° walls across the hillside. _grades() printed exactly
## that: "cut -21m" on two legs of the first version.
##
## Shorten the legs and the dip goes with the square: at 95 m the sagitta is
## 7 m and the cut is 3. But a short leg needs a small angle between its ends,
## and small angles do not alternate — they SWEEP. So the road climbs round the
## hill in one direction: it starts on the west flank, works anticlockwise
## across the south face gaining 7-8 m a leg, reaches the east flank level with
## the fort's foot, and only then turns back west for the final ramp along the
## front of the wall to the gate.
##
## That is also just what a road up a hill looks like, which is the usual sign
## that the arithmetic was telling the truth.
##
##             r   y   near lip
## Trailhead 184  15   —          the spawn, west flank
## Cistern   170  23   47
## Pillars   156  31   39
## Gate      142  38   32
## Terrace   124  45   25         the last bench below the plateau
## Apron      82  70   —          outside the fort's gate
## Fort        0  70   —
const STATIONS: Array = [
	["Trailhead", -137.0, 57.0, 15.0, 56.0, 36.0, 12.0],
	["Cistern", -44.0, 98.0, 23.0, 44.0, 32.0, 11.0],
	["Pillars", 48.0, 82.0, 31.0, 44.0, 32.0, 11.0],
	["Gate", 115.0, 18.0, 39.0, 44.0, 32.0, 11.0],
	["Terrace", 124.0, -66.0, 47.0, 44.0, 32.0, 16.0],
	# THE APRON, and it is the trick that makes the last ramp possible. A road
	# leg's run-out has to cross the whole of the pad it arrives on, and the
	# plateau's pad is 136 m across — a 70 m run-out, which is longer than any
	# leg that fits on a map 288 m deep, so every version with the road ending
	# at the plateau's CENTRE failed with "pads eat the leg". The plateau is
	# therefore not a road endpoint at all: the road ends on a small level
	# apron at the plateau's own height, just outside the gate, and the two
	# stamps meet at the lip asking for the same number.
	["Apron", 48.0, 0.0, 70.0, 28.0, 20.0, 18.0],
	["Fort", 0.0, -66.0, 70.0, 136.0, 112.0, 34.0],
]

## from, to, bed width, bank falloff. Walked in this order from the spawn.
const LEGS: Array = [
	["Trailhead", "Cistern", 18.0, 11.0],
	["Cistern", "Pillars", 12.0, 10.0],
	["Pillars", "Gate", 12.0, 10.0],
	["Gate", "Terrace", 12.0, 10.0],
	["Terrace", "Apron", 12.0, 18.0],
]

## Small flat benches on the hillside, so the ground between the stations is
## not all slope. These are NOT road endpoints and nothing is derived from
## their heights, so their y comes off ground_h() rather than being typed —
## which is the only way a bench stays level with the hill it is cut into when
## a hill stamp moves. Typed, three of them sat in 6 m holes.
##
## name, x, z, size x, size z, falloff
## THE UPPER TERRACE, and it is the thing that makes the fort read at all.
##
## PROMINENCE IS HEIGHT ABOVE THE NEAR GROUND, not above the stations. The
## near-lip column said 24-32 m from every station and every one of those
## numbers was true, and the fort was still invisible from the spawn — because
## the ground that hides it is not the station, it is the hill's own shoulder
## just outside the plateau. A smooth cone rises to 64.8 at the pad's edge and
## the pad is 70, so the fort stood FIVE METRES above the thing in front of it.
## Seen from 185 m that is nothing at all: the shoulder's skyline projected to
## 113 m at the dish's range and the dish tops out at 132, so nine metres of a
## 62 m landmark showed, in fog, and the first eye-level shot came back as a
## bare ridge.
##
## A circular FLATTEN out to r=112 at 48 m is the fix, and it is the brief's
## own answer rather than a new idea: a climb made of FLAT BENCHES joined by
## ramps. It makes the whole upper third of the map one level terrace, which is
## 35,000 m² of flat fighting ground where there was a 25° slope, and it leaves
## the plateau standing 22 m clear of it — a mesa with a fort on top, which is
## what a hillfort is.
##
## THE RIM IS NOT A CLIFF. 22 m over the pad's 24 m falloff is 42°, under the
## navmesh's 45, so the squad can still walk up anywhere and the curtain wall
## is what stops them — which is the conclusion the big map reached and wrote
## down after its own steep ring read as a crater. A ring that is LOWER than
## the thing it surrounds is a mesa; it was only ever the higher kind that was
## the problem.
##
## name, x, z, radius, falloff, y
## TWO STEPS, NOT ONE, AND THE SECOND ONE IS WHAT LETS THE ROAD GO IN AT THE
## GATE. The human played the first version and said the last ramp "doesn't
## make it up directly" — it climbed the mesa and then ran sideways along the
## front of the wall, because the climb finished 46 m before the gate and
## everything after that was level traverse.
##
## The arithmetic behind that: the terrace is at 48 and the fort at 70, so the
## last move is 22 m, and 22 m at the road's pitch needs ~70 m of graded run on
## a mesa face only 20-30 m wide. It has to wrap. The only question is whether
## it wraps while CLIMBING and then points at the gate, or climbs first and
## traverses after — and the second is what it was doing.
##
## THE FIX IS THE ROAD'S SHAPE, NOT THE HILL'S. The last leg now wraps the
## mesa while CLIMBING and spends its level run-out on a single stretch
## pointing due north at the gate, so the last thing you do is walk up at it.
## See _vias().
##
## TWO THINGS I TRIED FIRST AND TOOK BACK OUT, because the reasons are the
## useful part:
##
##   RAISE THE TERRACE so the last move is shorter. Closed off by the near lip:
##   a station standing on the terrace must be 23 m below the fort or the
##   objective is invisible from it, and the Terrace station stands on it. The
##   terrace is pinned at 48.
##
##   A SECOND STEP AT 59, halfway up the mesa, carrying no station and so not
##   bound by the near lip. It worked on paper — it halved the final embankment
##   from 20 m to 11 — and it does not fit. Three levels in the 44 m of radius
##   between the pad's edge and the terrace leaves bands 2 to 6 m wide: no flat
##   terrace to fight on, nowhere level to stand the glacis dressing, and a 46°
##   bank where the flat used to be. Widening the outer ring to make room
##   pushed 48 m ground out to r=130, where it became the skyline, and the dish
##   went from visible at every station to visible at NONE. One step, and the
##   last ramp rides a built causeway instead.
##
## name, x, z, radius, falloff, y
const RINGS: Array = [
	["UpperTerrace", 0.0, -66.0, 112.0, 24.0, 48.0],
]

## NARROW ACROSS THE SLOPE, AND A FALLOFF THAT CAN TAKE THE DROP. Both of
## those are corrections the bench report made. A flat pad cut into a 25° hill
## is cut into the uphill side and filled on the downhill one by half its own
## width times the slope — so a 30 m bench on this hill has a 7 m edge, and at
## the 9 m falloff the first pass used that is a 47° bank: a plinth, not a
## bench, which is the "gate with walls, not cliffs" fault in miniature. The
## long axis therefore runs ACROSS the fall line (which is radial here, so
## mostly along X on the flanks and along Z in the middle), and the falloff is
## 14-16 so the bank comes out around 20°.
## name, x, z, size x, size z, falloff
const BENCHES: Array = [
	# The road sweeps anticlockwise round the hill, which leaves the whole west
	# side of the map with no station on it. These are what is there instead:
	# flat ground a flanker can use, off every road, and the reason the ground
	# the road does not go is worth walking.
	["WestShelf", -140.0, -40.0, 22.0, 30.0, 16.0],
	["NorthWest", -116.0, -104.0, 26.0, 26.0, 16.0],
	# The middle of the map, between the two southern legs: the one piece of
	# flat ground with a view of the fort that nothing drives to.
	["MidBench", -6.0, 44.0, 30.0, 16.0, 14.0],
	["SouthMeadow", 90.0, 110.0, 30.0, 24.0, 14.0],
	["EastShelf", 146.0, -108.0, 24.0, 28.0, 24.0],
]

## The hills either side of the route, so the ground has shape to fight over
## rather than being one smooth cone.
## KEPT SMALL AND WIDE. amount/falloff decides the steepest slope a stamp makes
## — about atan(1.5 * amount / falloff) — so 12 m over 80 is 13° and nothing
## here is a ridge. Height on a map this size comes from the plateau and from
## what is built on it, not from painted hills.
## centre x, z, radius, falloff, amount
const HILLS: Array = [
	[-156.0, 128.0, 26.0, 80.0, 10.0],
	[96.0, 128.0, 24.0, 70.0, 10.0],
	[-172.0, -72.0, 26.0, 80.0, 10.0],
	[-130.0, -130.0, 26.0, 70.0, 12.0],
	[166.0, 100.0, 24.0, 70.0, 10.0],
]

## Saddles and hollows, as LOWER stamps. WITHOUT THESE THE MAP IS ONE DOME:
## the cone lifts everything smoothly and the hills sit on top of it, so
## nothing between them ever comes back down. Every one of these is between two
## things that stand up.
## The two under the plateau's flanks do a second job: prominence is height
## above the NEAR ground, so taking 7 m out of the ground beside the fort adds
## 7 m to what the fort reads as from the stations below it.
## centre x, z, radius, falloff, amount
const HOLLOWS: Array = [
	[-96.0, 118.0, 24.0, 65.0, 9.0],
	[-168.0, 112.0, 20.0, 55.0, 8.0],
	[4.0, 56.0, 26.0, 70.0, 6.0],
	[-90.0, -14.0, 24.0, 65.0, 8.0],
	[160.0, -20.0, 22.0, 60.0, 8.0],
	# On the hill’s south-east shoulder, between the Apron and the Terrace. A
	# convex hill hides its own top, and this is the 7 m that stops it: without
	# it the sight line from the Gate to the dish cleared the shoulder by 2 m,
	# which the recipe’s own noise would have closed.
	[86.0, -34.0, 20.0, 50.0, 7.0],
]

## THE CURTAIN WALL. 120 x 96, which is 5 fort_wall segments by 4 — the piece
## is 24 m long, so a half-extent that is not a multiple of 12 leaves either a
## gap at a corner or two segments buried in each other.
const WALL_HALF := Vector2(60.0, 48.0)
const WALL_THICK := 3.2
## Where the road crosses the wall, in the SOUTH run (local +Z is the side the
## trailhead is on). The EAST end of that run, because the road's last leg
## comes from the east flank — so the climb's final stretch runs west along the
## front of the wall and turns in at its far corner.
const GATE_AT := 48.0
## The postern, in the north run and as far from the gate as the ring allows.
## A compound with one way in is a cul-de-sac.
const POSTERN_AT := -24.0

## Half-extents of the plateau, less a margin, for things that stand ON it.
const SHELF_HALF := Vector2(62.0, 50.0)
## The pad itself, which the wall ring may reach — touching the lip is what a
## curtain wall is for.
const PAD_HALF := Vector2(68.0, 56.0)
## Clear ground between two pieces, so dressing them later does not collide.
const MARGIN := 1.5

## THE THING AT THE TOP. Offsets from the fort's centre, so nothing here moves
## when the fort does.
##
## THE DISH IS THE COMPOUND. 57.6 x 47.6 and 62 m tall, it fills the middle of
## the ring and everything else is what fits round it. That is the right way
## up for a relay station, and on a map only 288 m deep it is also what makes
## the objective visible from the spawn — which is the one job the big map's
## version failed at.
##
## ── THE DISH IS ON THE BROW, NOT IN THE MIDDLE, and that was the second
## thing the eye-level shots forced. Set back 44 m from the plateau's south rim
## it was invisible from the spawn whatever the hill did, because a rim 50 m
## above your eye and 97 m away subtends 27° and the dish's top at 185 m only
## subtends 32: five degrees of a 62 m landmark, in fog. Moved 20 m south its
## base is 25 m from the rim instead of 44, and the geometry opens up.
##
## It also turns the compound the right way round. The gate is in the south
## run, so what you walk into now is the dish itself, with the yard and the
## plant behind it — which is what a relay station looks like from the road,
## and the arrangement the big map describes but at 1 km could afford to get
## backwards.
##
## piece, x, z, yaw°
const FORT_PIECES: Array = [
	# At dz +1, not +8: the piece's bounding box sits 7 m SOUTH of its own
	# origin because the bowl overhangs the pedestal forward. Placing it on the
	# origin put it seven metres into the gate lane. _group() prints the real
	# box centre — read it there rather than trusting this.
	["landmarks/landmark_relay_dish", -10.0, 1.0, 0.0],

	# ── THE FOUR STRIPS, and they are measured off the wall's INNER face, not
	# off WALL_HALF. The side runs are pushed out by half the wall's thickness
	# so they butt the end runs instead of interpenetrating, which puts the
	# inner faces at x ±60.0 and z ±46.4 — an interior of 120 x 92.8, not the
	# 113.6 x 89.6 the first pass laid out to. The dish's box lands at
	# (-10, -12.2), so: west 21 m, east 41 m, north 10 m, south 35 m.
	#
	# ── EAST: the plant.
	["compute/compute_data_hall", 38.0, -22.0, 90.0],
	["compute/compute_chiller_yard", 34.0, 6.0, 0.0],
	["compute/compute_network_cabinet", 54.0, -34.0, 90.0],
	["compute/compute_network_cabinet", 54.0, -30.0, 90.0],
	["compute/compute_network_cabinet", 54.0, -26.0, 90.0],
	["compute/compute_transformer", 52.0, 6.0, 0.0],
	["compute/compute_transformer", 52.0, 14.0, 0.0],
	["compute/compute_generator", 52.0, 34.0, 90.0],
	["compute/compute_rack_row", 34.0, 30.0, 0.0],
	["compute/compute_rack_row", 34.0, 36.0, 0.0],
	# A mast rather than the pylon the big map uses: the pylon is 9.6 x 7.4 and
	# the north strip is 10 m wide, so it crowded the data hall at every
	# position that was not also inside the wall.
	["fortifications/fort_floodlight_mast", 46.0, -41.0, 0.0],

	# ── WEST: the working side, and the gun that covers the road's last turn.
	["features/feature_watchtower", -48.0, -30.0, 0.0],
	["fortifications/fort_gun_emplacement", -48.0, -8.0, 0.0],
	["fortifications/fort_hesco_sangar", -48.0, 12.0, 0.0],
	["fortifications/fort_floodlight_mast", -50.0, 28.0, 0.0],
	["props/prop_sandbag_nest", -56.0, 20.0, 0.0],
	# ── SOUTH: the gate lane, 14.6 m of it between the dish's pedestal and the
	# wall. With the dish on the brow this is a LANE and not a yard, which is
	# the right shape for the way in: you come through the gate and the dish is
	# directly over you. The open ground is now the north side, behind it.
	["features/feature_watchtower", 10.0, 40.0, 90.0],
	["fortifications/fort_sentry_turret", 44.0, 42.0, 215.0],
	["fortifications/fort_t_walls", -20.0, 40.0, 24.0],
	["fortifications/fort_t_walls", -56.0, 40.0, 70.0],
	["props/prop_jersey_barrier", 34.0, 44.0, 12.0],
	["props/prop_jersey_barrier", 28.0, 44.0, 12.0],
	["props/prop_crates", -34.0, 40.0, 30.0],
	["props/prop_barrels", 20.0, 40.0, 0.0],

	# ── NORTH: the yard, 30 m deep behind the dish, and the checkpoint that
	# used to be in the south when there was room for it there. A 25.7 x 20.6
	# piece does not fit a 14.6 m lane.
	["fortifications/fort_checkpoint", -30.0, -34.0, 20.0],
	["fortifications/fort_t_walls", 28.0, 24.0, -32.0],

	# THE CORES ARE NOT IN HERE. They live in CAPTURES, are emitted into the
	# LEVEL and not the art scene, and are folded into this group's clearance
	# check by _installation() — a capture point standing inside a transformer
	# is the quickest way to make an objective unpressable, so it is measured
	# with everything else even though it is not placed with it.
]

## THE UPPER TERRACE, outside the wall and on the flat. Same [piece, dx, dz,
## yaw] shape and the same origin as FORT_PIECES, but its own table because it
## is measured against the TERRACE and not against the plateau — a piece 104 m
## out is correctly off the shelf and correctly on the ground.
const TERRACE_DRESS: Array = [
	# ── THE UPPER TERRACE, outside the wall. 35,000 m² of flat ground appeared
	# the moment the terrace ring went in, and the shot from the gate looking
	# back came out as an empty plain — which is the complaint this whole map
	# exists to answer, reproduced at a quarter of the size. A glacis is
	# supposed to be open, but open is not the same as EMPTY: the squad has to
	# cross it under the wall's guns and it needs things to get behind.
	#
	# Everything here sits in the annulus between the plateau's own falloff
	# (which reaches |x| 92, |z| 80) and the ring's edge at 112, because
	# anything inside that is on the mesa's bank rather than on the flat.
	["features/feature_rock_outcrop", -100.0, -20.0, 20.0],
	["props/prop_boulder_c", -104.0, 12.0, 0.0],
	["features/feature_boulder_field", -96.0, 40.0, 60.0],
	["props/prop_robot_wreck", -76.0, 80.0, 130.0],
	["features/feature_crater_rim", -40.0, 100.0, 0.0],
	["fortifications/fort_dragon_teeth", 0.0, 104.0, 90.0],
	["props/prop_rubble_pile", 40.0, 100.0, 0.0],
	["features/feature_rock_outcrop", 96.0, 36.0, 200.0],
	["props/prop_boulder_c", 104.0, 6.0, 0.0],
	["features/feature_boulder_field", 92.0, -22.0, 140.0],
	["props/prop_robot_wreck", -100.0, -48.0, 40.0],
	["features/feature_crater_rim", 90.0, -56.0, 0.0],
]

## What is at each station. Played, the big map was "a road between bare pads
## with everything interesting on the hilltop". A station has to be somewhere
## worth stopping AND somewhere worth fighting over, which means two different
## things: cover a squad can use, and enough built stuff that the place has a
## name for a reason.
##
## station, piece, dx, dz, yaw
const STATION_DRESS: Array = [
	# ── TRAILHEAD. Where the squad comes from. The spawn is at dz +4, so the
	# middle of the pad stays clear.
	#
	# EVERYTHING IS ON THE SOUTH AND WEST OF THIS PAD and the NORTH-EAST corner
	# is left empty, which was found by a probe and not by looking. The road to
	# the Cistern leaves through that corner, and the first layout put the
	# bulldozer's box 1.3 m short of the pad edge there. The Bulwark is 2.26 m
	# across its shield, so it could not take the first leg at all: it walked
	# 297 m to cover 100, round the whole south of the map and in from the
	# Pillars — and probe_nav_reach still called that PASS, because the
	# objective was reachable in the end. A gap is only a route if the widest
	# chassis fits, which here means 8 m, and that includes the gap between two
	# hescos and the gap between a parked machine and the pad's own edge.
	["Trailhead", "features/feature_container_stack", -20.0, -12.0, 0.0],
	# Turned 20° a 15.7 x 5.1 stack bounds 16.5 x 10.2 — five metres deeper
	# than it looks on paper, which is what put it through the hesco line.
	["Trailhead", "features/feature_container_stack", -20.0, 4.0, 20.0],
	["Trailhead", "fortifications/fort_hesco_wall", -4.0, -16.0, 0.0],
	["Trailhead", "fortifications/fort_hesco_wall", 16.0, -16.0, 0.0],
	["Trailhead", "machines/machine_bulldozer", 4.0, 14.0, 200.0],
	["Trailhead", "machines/machine_semi_truck", -14.0, 14.0, 95.0],
	["Trailhead", "fortifications/fort_floodlight_mast", 26.0, -4.0, 0.0],
	["Trailhead", "props/prop_crates", 12.0, -6.0, 15.0],
	["Trailhead", "props/prop_barrels", -8.0, 8.0, 0.0],
	# A lamp post is 0.5 m wide and Recast erodes an agent radius round it, so
	# for a Bulwark it takes a 2.8 m disc out of whatever lane it stands in.
	# Not the lane the road leaves by.
	["Trailhead", "props/prop_lamp_post", 26.0, -14.0, 0.0],

	# ── THE CISTERN. Tanks and a pump house; the pipe runs are the cover.
	["Cistern", "features/feature_fuel_tanks", -2.0, -16.0, 0.0],
	# At 18, not 12: turned 25° the house bounds 21.8 x 20.1 and it was sitting
	# on the capture core in the middle of the pad.
	["Cistern", "building_house_small", 14.0, 8.0, 25.0],
	["Cistern", "props/prop_concrete_pipes", -16.0, 6.0, 10.0],
	["Cistern", "props/prop_concrete_pipes", -18.0, 14.0, 70.0],
	["Cistern", "compute/compute_cooling_unit", -4.0, 6.0, 0.0],
	["Cistern", "props/prop_sandbag_wall", -18.0, -6.0, 0.0],
	["Cistern", "props/prop_rubble_pile", 16.0, -10.0, 0.0],

	# ── THE PILLARS. Named for what stands on it: rock spires with a pylon
	# line run through them. The spires ARE the cover, and they break a crown
	# that would otherwise be a billiard table.
	["Pillars", "features/feature_rock_spire", -14.0, -10.0, 0.0],
	["Pillars", "features/feature_rock_spire", 12.0, -12.0, 140.0],
	["Pillars", "features/feature_rock_spire", 16.0, 8.0, 60.0],
	["Pillars", "features/feature_power_pylon", -14.0, 6.0, 0.0],
	["Pillars", "props/prop_boulder_c", -20.0, -2.0, 0.0],
	["Pillars", "props/prop_rock_slabs", 2.0, 14.0, 45.0],
	["Pillars", "props/prop_tank_trap", 6.0, -2.0, 0.0],

	# ── THE GATE. The foot of the climb: a checkpoint on the road, teeth
	# across it, a pillbox looking back down the hill.
	["Gate", "fortifications/fort_checkpoint", 2.0, 8.0, 0.0],
	["Gate", "features/feature_pillbox", -12.0, -8.0, 0.0],
	["Gate", "fortifications/fort_dragon_teeth", 18.0, -8.0, 80.0],
	["Gate", "fortifications/fort_sentry_turret", 18.0, 4.0, 180.0],
	["Gate", "props/prop_car_wreck", -4.0, -14.0, 130.0],
	["Gate", "props/prop_sandbag_nest", 6.0, -14.0, 0.0],

	# ── THE TERRACE. A dug-in gun line on the shelf, and the one that looks up
	# at the fort.
	["Terrace", "fortifications/fort_gun_emplacement", 0.0, -8.0, 0.0],
	["Terrace", "fortifications/fort_mortar_pit", -14.0, -8.0, 0.0],
	["Terrace", "fortifications/fort_hesco_wall", 10.0, 6.0, 0.0],
	["Terrace", "fortifications/fort_hesco_wall", -6.0, 10.0, 0.0],
	["Terrace", "props/prop_sandbag_wall", -16.0, 2.0, 0.0],
	["Terrace", "props/prop_robot_wreck", 16.0, -2.0, 60.0],

	# ── THE APRON. The last level ground before the gate, and the place the
	# fort shoots at. Teeth and a wrecked column, nothing to hide behind.
	# The causeway head. The two hesco runs flank the ramp where it reaches the
	# apron, 19.6 m apart, so the way in reads as a made thing rather than a
	# slope that happens to be walkable — and so the last stretch has sides.
	["Apron", "fortifications/fort_hesco_wall", -12.0, 8.0, 90.0],
	["Apron", "fortifications/fort_hesco_wall", 12.0, 8.0, 90.0],
	["Apron", "fortifications/fort_dragon_teeth", -12.0, -8.0, 0.0],
	["Apron", "props/prop_robot_wreck", 0.0, -12.0, 200.0],
]

## THE CAPTURE SITES — six of them, which on 0.094 km² of walled-in ground is
## about 15,600 m² each. Georgetown is 14,436 and the coast road 19,250 and
## both of those work; today's Hillfort is 217,440.
##
## THE ANCHOR TAG IS WRITTEN HERE, not derived from the capture's id. It was
## derived, by stripping a prefix and adding one, and it was silently wrong for
## the two inside the fort — whose anchors are the DISH and the PLANT and not
## anything named after them. A capture pointing at the wrong anchor still
## works in game and reports the wrong place forever.
##
## node, id, display, description, reward, station or "Fort", dx, dz, scene,
## anchor tag
const CAPTURES: Array = [
	["CisternCore", "hfw_cistern", "The Cistern", "Take the core at the water tanks.",
			20, "Cistern", -6.0, 14.0, CORE, "obj_hfw_cistern"],
	["PillarsCore", "hfw_pillars", "The Pillars", "Take the core among the spires.",
			20, "Pillars", 0.0, 0.0, CORE, "obj_hfw_pillars"],
	["GateCore", "hfw_gate", "The Gate", "Take the core at the checkpoint.",
			25, "Gate", -16.0, 8.0, CORE, "obj_hfw_gate"],
	["TerraceCore", "hfw_terrace", "The Terrace", "Take the core on the gun line.",
			25, "Terrace", 14.0, -14.0, CORE, "obj_hfw_terrace"],
	["RelayCore", "hfw_relay", "The Relay", "Take the core in the fort yard.",
			40, "Fort", -10.0, 40.0, CORE_LARGE, "obj_hfw_dish"],
	["PowerCore", "hfw_power", "The Power Yard", "Take the core beside the plant.",
			30, "Fort", 48.0, 22.0, CORE, "obj_hfw_plant"],
]

## DISTRICT ANCHORS. A SquadObjectivePoint is a named place with a tag and no
## logic, and missions reference these BY TAG and never by node path — so a tag
## is a contract this lane can honour without touching an operation. These say
## WHERE the places are; what happens at each is GAMEPLAY's, and nothing under
## Campaign/ is opened here.
##
## Heights come off ground_h() or off the station they belong to, never guessed:
## an anchor floating over its district still reports "reached", because the
## navmesh query snaps in 3D.
##
## node, tag, display, x, z, y or NAN_Y to derive
const OBJECTIVES: Array = [
	["HFW_Trailhead", "obj_hfw_trailhead", "Trailhead", -137.0, 57.0, 15.0],
	["HFW_Cistern", "obj_hfw_cistern", "The Cistern", -44.0, 98.0, 23.0],
	["HFW_Pillars", "obj_hfw_pillars", "The Pillars", 48.0, 82.0, 31.0],
	["HFW_Gate", "obj_hfw_gate", "The Gate", 115.0, 18.0, 39.0],
	["HFW_Terrace", "obj_hfw_terrace", "The Terrace", 124.0, -66.0, 47.0],
	["HFW_Apron", "obj_hfw_apron", "The Apron", 48.0, 0.0, 70.0],
	# The compound, broken up: taking the hilltop is not one objective, it is a
	# gate, a yard, and three things inside worth standing on.
	["HFW_FortGate", "obj_hfw_fortgate", "Fort Gate", 48.0, -22.0, 70.0],
	["HFW_Yard", "obj_hfw_yard", "The Yard", 0.0, -100.0, 70.0],
	# At the dish's FOOT, not under it: an anchor on the pedestal's own
	# footprint reports reached with no route, because the navmesh it snapped
	# to is a scrap inside the piece.
	["HFW_Dish", "obj_hfw_dish", "The Relay Dish", -52.0, -60.0, 70.0],
	# In the 10 m lane between the dish and the data hall.
	["HFW_Plant", "obj_hfw_plant", "The Plant", 23.0, -96.0, 70.0],
	["HFW_Postern", "obj_hfw_postern", "The Postern", -24.0, -108.0, 70.0],
	# OFF the road. Every one of these is somewhere the squad can stand that no
	# road goes, so a mission can ask for a flank instead of a column. The
	# whole west side of the map is this, because the road sweeps the other way.
	["HFW_WestShelf", "obj_hfw_west_shelf", "West Shelf", -140.0, -40.0, NAN_Y],
	["HFW_NorthWest", "obj_hfw_north_west", "North-West Spur", -116.0, -104.0, NAN_Y],
	["HFW_MidBench", "obj_hfw_mid_bench", "The Watchpost", -6.0, 44.0, NAN_Y],
	["HFW_SouthMeadow", "obj_hfw_south_meadow", "South Meadow", 90.0, 110.0, NAN_Y],
	["HFW_EastShelf", "obj_hfw_east_shelf", "East Shelf", 146.0, -108.0, NAN_Y],
]

## Patrol routes: plain Node3D children of an anchor. HEIGHTS ARE DERIVED, not
## guessed — the symptom of a patrol point 20 m under the hill is not "cut
## off", it is an OFFSET of a few metres, because the query snaps in 3D.
## anchor node, then points as x, z pairs
const PATROLS: Array = [
	["HFW_Yard", [
		[0.0, -100.0], [-18.0, -96.0], [14.0, -94.0],
		[26.0, -100.0], [16.0, -110.0], [-10.0, -108.0],
	]],
	["HFW_MidBench", [
		[-6.0, 44.0], [4.0, 40.0], [-14.0, 40.0], [-16.0, 48.0],
	]],
]

## The level exit, inside the postern. Offsets from the fort.
const EXIT_AT := Vector2(-24.0, -38.0)


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
	var bad := _profile(by_name)
	bad += _sightlines(by_name)
	bad += _grades(by_name)
	bad += _bench_report()
	bad += await _installation()
	if OS.get_environment("PROFILE") != "":
		quit(0 if bad == 0 else 1)
		return
	if bad > 0:
		print("FAIL  %d problem(s) — nothing written" % bad)
		quit(1)
		return
	# A guard, not a formality: the big builder's _scene() once kept a station
	# name that had been renamed out from under it, the access threw, the text
	# came back empty, and the open below truncated the level to nothing while
	# the line at the end still said it had been written.
	var art := _art(by_name)
	var level := _level(by_name)
	if art.length() < 2000 or level.length() < 1500:
		print("FAIL  the scene text came back %d / %d bytes — see the error above" % [
				art.length(), level.length()])
		quit(1)
		return
	# THE FILES ON DISK ARE THE SOURCE once a human has opened them. Same rule
	# the block_*.gd tools keep and for the same reason.
	for pair: Array in [[OUT_ART, art], [OUT_LEVEL, level]]:
		if FileAccess.file_exists(pair[0]) and not force:
			print("SKIP  %s exists — it may hold editor changes. Pass --force." % pair[0])
			continue
		var f := FileAccess.open(pair[0], FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s" % pair[0])
			quit(1)
			return
		f.store_string(pair[1])
		f.close()
		print("   wrote %s" % pair[0])
	print("   %d station(s), %d bench(es), %d leg(s), %d capture(s), %d hill(s), %d hollow(s)" % [
			STATIONS.size(), BENCHES.size(), LEGS.size(), CAPTURES.size(),
			HILLS.size(), HOLLOWS.size()])
	quit()


# ── the shape of the ground ──────────────────────────────────────────────────

## Height the stacked cones give at radius r from the fort.
func cone_h(r: float) -> float:
	var h := 0.0
	for c: Array in CONES:
		var d: float = r - float(c[0])
		if d <= 0.0:
			h += float(c[2])
		elif d < float(c[1]):
			h += float(c[2]) * (1.0 - smoothstep(0.0, float(c[1]), d))
	return h


## What the stamps make the ground at (x, z), BEFORE the pads and roads cut
## into it: the cones plus every hill minus every hollow.
##
## IT IS AN ESTIMATE, AND SAYING WHICH PART IS ESTIMATED MATTERS. It does not
## include the recipe's own noise, the sketch's crag, or erosion — a few metres
## in each direction. What it is exactly right about is the part that decides
## whether a bench sits in a hole: the stamps, which run last and win.
func ground_h(x: float, z: float) -> float:
	var at := Vector2(x, z)
	var h := cone_h(at.distance_to(SUMMIT))
	for g: Array in HILLS:
		h += _stamp(at, g, 1.0)
	for g: Array in HOLLOWS:
		h -= _stamp(at, g, 1.0)
	return h


## The ground AFTER the flat stamps are cut into it: ground_h, then every
## station pad and bench in the order the art scene writes them, each one
## FLATTENing towards its own height with the generator's own weight —
## a rounded-box signed distance eased by 1 - smoothstep(0, falloff, d).
##
## IT HAS TO MATCH THE GENERATOR, not approximate it, because the thing it is
## used for is the sight line, and a sight line is decided by a few metres.
## The one thing left out is the roads, which only ever cut DOWN along narrow
## strips — leaving them out can hide a view that is really there, never
## invent one.
func terrain_h(x: float, z: float) -> float:
	var h := ground_h(x, z)
	# Same order as the art scene writes them: the big terrace first, then the
	# pads that stand on it, then the benches. A later stamp wins.
	for r: Array in RINGS:
		h = _flatten_disc(h, x, z, Vector2(float(r[1]), float(r[2])),
				float(r[3]), float(r[4]), float(r[5]))
	for s: Array in STATIONS:
		h = _flatten(h, x, z, Vector2(float(s[1]), float(s[2])),
				Vector2(float(s[4]), float(s[5])) * 0.5, float(s[6]), float(s[3]))
	for b: Array in BENCHES:
		h = _flatten(h, x, z, Vector2(float(b[1]), float(b[2])),
				Vector2(float(b[3]), float(b[4])) * 0.5, float(b[5]), bench_y(b))
	return h


## One circular FLATTEN stamp, as terrain_generator.gd applies it.
func _flatten_disc(h: float, x: float, z: float, centre: Vector2, radius: float,
		falloff: float, target: float) -> float:
	var d := Vector2(x, z).distance_to(centre) - radius
	if d >= falloff:
		return h
	var w := 1.0 if d <= 0.0 else 1.0 - smoothstep(0.0, falloff, d)
	return lerpf(h, target, w)


## One rectangular FLATTEN stamp, as terrain_generator.gd applies it.
func _flatten(h: float, x: float, z: float, centre: Vector2, half: Vector2,
		falloff: float, target: float) -> float:
	var rel := Vector2(x, z) - centre
	var q := rel.abs() - half
	var d: float = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
	if d >= falloff:
		return h
	var w := 1.0 if d <= 0.0 else 1.0 - smoothstep(0.0, falloff, d)
	return lerpf(h, target, w)


## One radial stamp's contribution at `at`. [cx, cz, radius, falloff, amount]
func _stamp(at: Vector2, g: Array, sign_: float) -> float:
	var d: float = at.distance_to(Vector2(float(g[0]), float(g[1]))) - float(g[2])
	if d <= 0.0:
		return float(g[4]) * sign_
	if d >= float(g[3]):
		return 0.0
	return float(g[4]) * sign_ * (1.0 - smoothstep(0.0, float(g[3]), d))


## The radial profile, the cut or fill under every station, and THE NEAR LIP —
## how far the fort stands above each station below it. A flat hilltop hides
## what stands on it, so a lip under MIN_LIP is a fault and not a note.
func _profile(by_name: Dictionary) -> int:
	var bad := 0
	print("   the hill, radial profile from the fort at (%.0f, %.0f)" % [SUMMIT.x, SUMMIT.y])
	print("   %8s %9s %9s" % ["r (m)", "height", "slope"])
	var r := 0.0
	while r <= 240.0:
		var step := 16.0
		var a := cone_h(r)
		var b := cone_h(r + step)
		var slope := rad_to_deg(atan2(a - b, step))
		var mark := ""
		if slope > NAV_MAX_SLOPE:
			# Not a fault here, but say so: anywhere over the baker's limit is
			# hillside the squad cannot use, and on a map whose point is that
			# the hill is open that wants to be deliberate.
			mark = "  OVER agent_max_slope — not walkable"
			bad += 1
		elif slope > 30.0:
			mark = "  steep for a hill"
		print("   %8.0f %8.1f m %8.1f°%s" % [r, a, slope, mark])
		r += step
	print("")
	var top: float = float((by_name["Fort"] as Array)[3])
	print("   %-12s %7s %9s %9s %9s" % ["station", "r", "authored", "stamps", "near lip"])
	for s: Array in STATIONS:
		var at := Vector2(float(s[1]), float(s[2]))
		var y := float(s[3])
		var nat := ground_h(at.x, at.y)
		var note := ""
		var lip := top - y
		var lip_s := "%.0f m" % lip
		if str(s[0]) == "Fort" or str(s[0]) == "Apron":
			lip_s = "—"
		elif lip < MIN_LIP and str(s[0]) in ["Terrace", "Gate"]:
			# Only the two stations at the plateau's foot have to clear it. From
			# further down the hill the lip is bigger by construction.
			note = "   LIP UNDER %.0f m — the fort is invisible from here" % MIN_LIP
			bad += 1
		if absf(y - nat) > 10.0:
			note += "   %s of %.0f m" % ["cut" if nat > y else "fill", absf(y - nat)]
		print("   %-12s %6.0fm %8.0fm %8.1fm %9s%s" % [
				s[0], at.distance_to(SUMMIT), y, nat, lip_s, note])
	return bad


## HOW MUCH OF THE DISH CAN YOU SEE FROM THERE, which is a different question
## from how much higher it is and the one that was being answered by accident.
##
## The near-lip rule — 23 m or the objective is invisible from the approach —
## is about HEIGHT, and _profile() checks it and it passed everywhere. Then the
## first eye-level shot from the spawn came back with no fort in it at all: a
## hill stamp 190 m away and well off to one side had raised the ground under
## the sight line, and the line cleared it by well under a metre once the
## recipe's own noise was added. Height was never the problem. OCCLUSION was,
## and nothing was asking.
##
## "Is the top of the dish visible" turned out to be the wrong question too. It
## is a yes/no over a 62 m object, and the first version failed the Gate on
## 3.6 m of clearance — a station from which two thirds of the dish is in plain
## sight. So this measures the ANSWER rather than a proxy: it walks the ground
## between the eye and the dish, takes the highest elevation angle anything
## reaches, and reports how many metres of the dish stand above it.
##
## THE SAMPLE IS AGAINST terrain_h, so the pads and benches are in it, and it
## stops 12 m short of each end so a station's own dressing and the dish's own
## pedestal are not counted as the thing hiding it.
##
## VISIBLE must beat this, in metres of dish. CALIBRATED AGAINST THE PICTURE,
## not guessed: at 7 m the trailhead shot came back as a bare ridge with no
## fort in it; at 11 the bowl stands clear on the skyline and the place is
## unmistakable. 10 is the line between those two, and it is a
## REGRESSION guard rather than a target: anything well above it is fine, and
## the picture is always the arbiter rather than this number.
const MIN_VISIBLE := 10.0
## What the ground_h estimate does not know: the recipe's 3 m of hills, 2 m of
## ridge and the sketch's 2.5 m of crag, none of which are stamps. Occluders
## are raised by this before the angle is taken.
const SIGHT_NOISE := 4.0
## Closer than this to the plateau's own edge and the mesa fills the sky; the
## question stops meaning anything and is reported rather than failed.
const UNDER_THE_MESA := 70.0

func _sightlines(by_name: Dictionary) -> int:
	var bad := 0
	var fort: Array = by_name["Fort"]
	# The dish: 62 m of it standing on the 70 m plateau. Its box centre is 10 m
	# west and 12 m north of the fort's own middle — read off the _group print,
	# not off the placement, because the bowl overhangs its own pedestal.
	var base := Vector3(float(fort[1]) - 10.0, float(fort[3]), float(fort[2]) + 8.0)
	var top := base.y + 62.0
	print("")
	print("   HOW MUCH OF THE DISH CAN BE SEEN — 62 m of it on the plateau")
	print("   %-12s %9s %11s %10s %s" % ["from", "range", "visible", "hidden by", "at"])
	for s: Array in STATIONS:
		if str(s[0]) in ["Fort", "Apron"]:
			continue
		var from := Vector3(float(s[1]), float(s[3]) + 1.5, float(s[2]))
		var flat := Vector2(base.x - from.x, base.z - from.z)
		var span := flat.length()
		# HOW CLOSE IS IT TO THE MESA, which decides whether the answer means
		# anything. The Gate sits 55 m from the plateau's south-east corner, so
		# a 22 m rim 55 m away fills most of its sky and the dish behind it is
		# hidden — and that is not a fault, it is what being directly under a
		# hillfort looks like. A station is only asked to see the dish while it
		# is still far enough off for the dish to be the thing you navigate by.
		var corner: float = Vector2(
				maxf(absf(from.x - float(fort[1])) - float(fort[4]) * 0.5, 0.0),
				maxf(absf(from.z - float(fort[2])) - float(fort[5]) * 0.5, 0.0)).length()
		# The highest elevation angle anything between here and there reaches.
		# Expressed as a height AT THE DISH, which is what it is wanted for.
		var skyline := base.y
		var at := Vector2.ZERO
		var d := 12.0
		while d < span - 12.0:
			var p := Vector2(from.x, from.z) + flat * (d / span)
			var h := terrain_h(p.x, p.y) + SIGHT_NOISE
			var reach := from.y + (h - from.y) * (span / d)
			if reach > skyline:
				skyline = reach
				at = p
			d += 4.0
		var visible: float = clampf(top - skyline, 0.0, 62.0)
		var note := ""
		if corner < UNDER_THE_MESA:
			note = "   under the wall — nothing to read from here, by design"
		elif visible < MIN_VISIBLE:
			note = "   TOO LITTLE — the fort does not read from here"
			bad += 1
		print("   %-12s %8.0fm %9.0f m %9.0fm   (%.0f, %.0f)%s" % [
				s[0], span, visible, skyline - base.y, at.x, at.y, note])
	return bad


## The benches, with their derived heights and the slope of the bank each one
## cuts. A bench whose bank is over agent_max_slope is a bench on a plinth.
func _bench_report() -> int:
	var bad := 0
	print("")
	print("   %-12s %9s %9s %9s" % ["bench", "derived y", "edge drop", "bank"])
	for b: Array in BENCHES:
		var y := bench_y(b)
		# The worst corner: where the natural ground is furthest from the pad.
		var worst := 0.0
		var hx: float = float(b[3]) * 0.5
		var hz: float = float(b[4]) * 0.5
		for sx: float in [-1.0, 0.0, 1.0]:
			for sz: float in [-1.0, 0.0, 1.0]:
				var g := ground_h(float(b[1]) + hx * sx, float(b[2]) + hz * sz)
				worst = maxf(worst, absf(g - y))
		# 1.5 x, BECAUSE A SMOOTHSTEP IS NOT A STRAIGHT LINE. Its steepest point
		# is half again as steep as the average over the falloff, and the first
		# version of this divided drop by falloff and reported 42° for a bank
		# that was really 54. The navmesh bake is what caught it: every station
		# above the terrace came back UNREACHABLE and the whole fort was an
		# island, on numbers this said were fine.
		var bank := rad_to_deg(atan2(worst * 1.5, float(b[5])))
		var note := ""
		if bank > NAV_MAX_SLOPE:
			note = "   BANK OVER agent_max_slope — it is a plinth, not a bench"
			bad += 1
		print("   %-12s %8.1fm %8.1fm %8.1f°%s" % [b[0], y, worst, bank, note])
	return bad


## A bench's height: the ground under its own middle, rounded to the metre so
## the scene file reads cleanly.
func bench_y(b: Array) -> float:
	return roundf(ground_h(float(b[1]), float(b[2])))


# ── the roads ────────────────────────────────────────────────────────────────

## How far a leg leaving `station` in direction `dir` must stay level.
##
## IT HAS TO CROSS THE WHOLE PAD. Roads are cut AFTER the shelves, so a road
## still climbing where it crosses a pad wins that ground and digs a trench
## through it. Level from the pad's own boundary inwards and the road asks for
## exactly the height the pad is at.
func _runout(station: Array, dir: Vector2) -> float:
	var half := Vector2(float(station[4]), float(station[5])) * 0.5
	var reach: float = minf(half.x / maxf(absf(dir.x), 0.0001),
			half.y / maxf(absf(dir.y), 0.0001))
	return maxf(RUNOUT, reach + float(station[6]))


## Bends, so the roads wrap the hill instead of ruling a line across it — and,
## on two legs, so they stay OFF the plateau's pad. A road is cut last and wins
## whatever ground it is on, so the Gate-to-Apron leg ruled straight would have
## dug a 28 m trench through the fort's own south wall. The vias are what keep
## it south of the lip.
func _vias(from_name: String, to_name: String) -> Array[Vector2]:
	match "%s-%s" % [from_name, to_name]:
		# The sweep's legs are short enough to be ruled straight: the sagitta
		# of a 95 m chord at r≈160 is 7 m, which is a 3 m cut and a bank the
		# falloff can hold. Bending them would only put them back on the
		# contour they are already nearly on.
		#
		# THE LAST LEG IS THE ONE THAT NEEDS VIAS, and it needs them for both
		# reasons at once. Ruled straight from the Terrace to the Apron it
		# crosses the plateau's own pad — a 25 m trench through the fort's
		# south-east corner — AND it is only 101 m long, which at 25 m of rise
		# is 27°. The dogleg round the plateau's foot fixes both: it stays
		# south of the lip the whole way, and the extra 33 m of road is what
		# brings the grade to 20°. The last fifty metres of the climb are
		# therefore walked along the front of the wall, under the guns.
		# THE LAST LEG, AND THE WHOLE POINT OF IT IS WHERE THE LEVEL BIT GOES.
		#
		# 23 m of rise at the road's pitch needs ~75 m of graded run, and the
		# mesa's face is 30 m wide, so this leg HAS to wrap. The first version
		# wrapped the wrong way round: it climbed up the east side and then
		# spent its whole 46 m run-out running WEST along the front of the wall
		# to a gate off to one side. Played, that reads as the road arriving at
		# the hill and giving up — "the last ramp doesn't make it up directly".
		#
		# Same wrap, opposite order. The climb now happens on the way round,
		# and the level run-out is spent on ONE 27 m stretch from (56, 26) to
		# the apron, pointing due north with the gate 18 m beyond it. You climb,
		# you turn once at the foot, and the last thing you do is walk up at the
		# gate.
		#
		# The cost is honest and it is fill: 16 m of embankment under the
		# midpoint, 17 m under that last stretch. It is a built causeway across
		# the terrace, its flanks are too steep to climb, and that is the
		# correct shape for the approach to a hillfort — one way up, in the
		# open, under the wall.
		"Terrace-Apron":
			return [Vector2(118.0, -26.0), Vector2(92.0, 4.0), Vector2(56.0, 26.0)]
	return []


## The polyline a leg is actually cut along, station to station through its
## vias.
func _poly(by_name: Dictionary, leg: Array) -> Array[Vector2]:
	var a: Array = by_name[leg[0]]
	var b: Array = by_name[leg[1]]
	var pts: Array[Vector2] = [Vector2(float(a[1]), float(a[2]))]
	for v in _vias(str(a[0]), str(b[0])):
		pts.append(v)
	pts.append(Vector2(float(b[1]), float(b[2])))
	return pts


func _cum(pts: Array[Vector2]) -> Array[float]:
	var cum: Array[float] = [0.0]
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	return cum


## Every leg's grade, and whether it crosses the plateau.
##
## THE RUN IS THE POLYLINE'S LENGTH, NOT THE STRAIGHT LINE between stations,
## and that is a correction to the big builder rather than a shortcut. There,
## `run` is the straight-line distance while _curve spreads the height along
## the POLYLINE, so a leg bent through vias is reported steeper than it is —
## conservative, which is the safe direction, but on a map this size the error
## is the whole margin. Two legs here only fit because their vias are real
## metres of road, so the number checked has to be the number cut.
func _grades(by_name: Dictionary) -> int:
	var bad := 0
	print("")
	print("   %-24s %8s %8s %8s %8s %8s" % ["leg", "run", "rise", "grade", "level", "cut"])
	for l: Array in LEGS:
		var a: Array = by_name[l[0]]
		var b: Array = by_name[l[1]]
		var pts := _poly(by_name, l)
		var cum := _cum(pts)
		var run: float = cum[cum.size() - 1]
		var rise := float(b[3]) - float(a[3])
		var dir := (pts[pts.size() - 1] - pts[0]).normalized()
		var ends := _runout(a, dir) + _runout(b, dir)
		var label: String = "%s → %s" % [l[0], l[1]]
		if ends >= run - 8.0:
			bad += 1
			print("   %-24s %7.0fm %7.0fm  PADS EAT THE LEG — %.0f m of run-out in %.0f m" % [
					label, run, rise, ends, run])
			continue
		var graded: float = maxf(run - ends, 0.001)
		var grade := rad_to_deg(atan2(rise, graded))
		# How far the bed sits off the natural ground at its midpoint: a big
		# number means an embankment across the face rather than a shelf in it.
		var mid := _along(pts, cum, run * 0.5)
		var cut := lerpf(float(a[3]), float(b[3]), 0.5) - ground_h(mid.x, mid.y)
		var note := ""
		if absf(grade) > MAX_GRADE:
			note = "  OVER %.0f°" % MAX_GRADE
			bad += 1
		# AND IT MUST NOT CROSS THE PLATEAU. A road's influence is half its bed
		# plus its bank falloff; anywhere inside the fort's pad it would cut
		# the plateau down to road height.
		var reach: float = float(l[2]) * 0.5 + float(l[3])
		var fort: Array = by_name["Fort"]
		var fh := Vector2(float(fort[4]), float(fort[5])) * 0.5
		var worst := 0.0
		var s := 0.0
		while s <= run:
			var p := _along(pts, cum, s)
			var inside := Vector2(
					fh.x + reach - absf(p.x - float(fort[1])),
					fh.y + reach - absf(p.y - float(fort[2])))
			if inside.x > 0.0 and inside.y > 0.0:
				worst = maxf(worst, minf(inside.x, inside.y))
			s += 4.0
		if worst > 0.0 and str(l[1]) != "Apron":
			note += "   CROSSES THE PLATEAU PAD by %.0f m" % worst
			bad += 1
		elif worst > 0.0:
			# The apron leg is allowed to touch, because the apron is at the
			# plateau's own height. Say by how much anyway.
			note += "   touches the pad by %.0f m (same height)" % worst
		print("   %-24s %7.0fm %7.0fm %7.1f° %7.0fm %7.0fm%s" % [
				label, run, rise, grade, ends, cut, note])
	return bad


## A leg's curve. Heights are spread along the polyline BY ARC LENGTH, so the
## grade is the same at every point of the graded part whatever shape the leg
## is bent into — and the first and last run-out metres are dead level.
##
## THE RUN-OUT IS NOT DECORATION. Two legs meet at a station and their beds
## overlap for 20-odd metres around it. Whichever is cut second wins that
## ground, so if either is still climbing when it gets there it writes its own
## height across the other one's bed and leaves a step. Both arriving level at
## the station's own height means the overlap is two cuts asking for the same
## number, and the step cannot happen.
func _curve(by_name: Dictionary, leg: Array) -> String:
	var a: Array = by_name[leg[0]]
	var b: Array = by_name[leg[1]]
	var pts := _poly(by_name, leg)
	var cum := _cum(pts)
	var total: float = maxf(cum[cum.size() - 1], 0.001)
	var dir := (pts[pts.size() - 1] - pts[0]).normalized()
	var r0: float = minf(_runout(a, dir), total * 0.45)
	var r1: float = minf(_runout(b, dir), total * 0.45)
	# The two kinks in the height profile become real curve points, or the
	# resampler rounds the corner and the run-out is not level after all.
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


# ── the installation ─────────────────────────────────────────────────────────

## The ring, built rather than typed: eighteen segments, two of them gates.
## Same [piece, dx, dz, yaw] shape as FORT_PIECES.
func wall_pieces() -> Array:
	if OS.get_environment("NOWALL") != "":
		# Isolation switch. The cheapest way to ask "was it the wall that broke
		# the navmesh" a second time.
		return []
	var out: Array = []
	# fort_wall and fort_gate are 24 m along their OWN Z, so the runs that go
	# along X are turned a quarter.
	for x: float in [-48.0, -24.0, 0.0, 24.0, 48.0]:
		out.append([("fortress/fort_gate" if is_equal_approx(x, GATE_AT)
				else "fortress/fort_wall"), x, WALL_HALF.y, 90.0])
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
	return out


## The dressing for one station, as [piece, dx, dz, yaw] rows.
func dress_for(station: String) -> Array:
	var out: Array = []
	for d: Array in STATION_DRESS:
		if str(d[0]) == station:
			out.append([d[1], d[2], d[3], d[4]])
	return out


## Every distinct piece the two scenes instance, for the ext_resource count.
func all_pieces() -> Array:
	var out: Array = []
	for p: Array in FORT_PIECES + wall_pieces() + TERRACE_DRESS:
		out.append(p)
	for d: Array in STATION_DRESS:
		out.append([d[1], d[2], d[3], d[4]])
	return out


func _piece_path(name_: String) -> String:
	return name_ if name_.begins_with("res://") else "res://maps/blocks/%s.tscn" % name_


## The capture cores hosted by one station or by the fort, as [piece, dx, dz,
## yaw] rows, so they can be measured alongside the dressing they stand in.
func cores_for(host: String) -> Array:
	var out: Array = []
	for c: Array in CAPTURES:
		if str(c[5]) == host:
			out.append([c[8], c[6], c[7], 0.0])
	return out


## Every placed group measured on its pad and against itself. Same test for the
## fort and for each station: on the pad, and clear of each other.
func _installation() -> int:
	print("")
	var bad := await _group("fort", FORT_PIECES + wall_pieces() + cores_for("Fort"),
			Vector2.ZERO, SHELF_HALF, PAD_HALF)
	# The glacis, measured against the terrace ring rather than the plateau.
	# One room for both arguments: nothing out here is a wall segment.
	var terrace := Vector2(RINGS[0][3], RINGS[0][3])
	bad += await _group("terrace", TERRACE_DRESS, Vector2.ZERO, terrace, terrace)
	for s: Array in STATIONS:
		# The fort's own group is above and already holds its cores; running it
		# again as a station would report every pair twice.
		if str(s[0]) == "Fort":
			continue
		var dress: Array = dress_for(str(s[0])) + cores_for(str(s[0]))
		if dress.is_empty():
			continue
		# Pieces may sit a little past the pad edge — the falloff keeps the
		# ground near level for a few metres — but not far, or they hang.
		var room := Vector2(float(s[4]), float(s[5])) * 0.5 + Vector2(5.0, 5.0)
		bad += await _group(str(s[0]), dress, Vector2(float(s[1]), float(s[2])), room, room)
	return bad


func _group(label: String, pieces: Array, _origin: Vector2, room_a: Vector2, room_b: Vector2) -> int:
	var bad := 0
	var boxes: Array = []
	print("   %-38s %9s %9s %10s" % ["%s piece" % label, "dx", "dz", "size"])
	for p: Array in pieces:
		var path := _piece_path(str(p[0]))
		var packed := load(path) as PackedScene
		if packed == null:
			print("   %-38s WILL NOT LOAD (%s)" % [str(p[0]).get_file(), path])
			bad += 1
			continue
		var inst := packed.instantiate() as Node3D
		# Into the tree first. A CollisionShape3D's global_transform is only
		# meaningful once it has one, and measuring outside the tree gives
		# every shape the piece's own origin.
		root.add_child(inst)
		await process_frame
		var box := _collision_aabb(inst)
		inst.free()
		var at := Vector2(float(p[1]), float(p[2]))
		var yaw := deg_to_rad(float(p[3]))
		var off := Vector2(box.position.x + box.size.x * 0.5, box.position.z + box.size.z * 0.5)
		var centre := at + Vector2(off.x * cos(yaw) + off.y * sin(yaw),
				-off.x * sin(yaw) + off.y * cos(yaw))
		# The rotated footprint as an axis-aligned rectangle. A circle round
		# the diagonal is useless: a 29 m hall gets a 17 m radius and then
		# reports an overlap with anything within 17 m of its CENTRE.
		var half := Vector2(box.size.x, box.size.z) * 0.5
		var rot := Vector2(
				absf(half.x * cos(yaw)) + absf(half.y * sin(yaw)),
				absf(half.x * sin(yaw)) + absf(half.y * cos(yaw)))
		var ring: bool = str(p[0]).begins_with("fortress/")
		var note := ""
		# SHELF_HALF is the margin for things that stand ON the plateau. The
		# wall ring is measured against the pad itself.
		var room := room_b if ring else room_a
		if absf(centre.x) + rot.x > room.x or absf(centre.y) + rot.y > room.y:
			note = "   OFF THE SHELF"
			bad += 1
		for b: Array in boxes:
			var d: Vector2 = (centre - (b[1] as Vector2)).abs() - rot - (b[2] as Vector2)
			# MARGIN, not zero. These get dressed later and grow parapets and
			# cable trays; touching now is overlapping then.
			#
			# THE RING IS THE EXCEPTION, and only just. A curtain wall has to
			# touch itself or it is a row of slabs, so ring-against-ring may
			# meet at a face — but NOT interpenetrate.
			var allow: float = -0.05 if (ring and bool(b[3])) else MARGIN
			var gap: float = maxf(d.x, d.y)
			if gap < allow:
				note = "   %s %s by %.1f m" % [
						"OVERLAPS" if gap < 0.0 else "crowds", b[0], allow - gap]
				bad += 1
		boxes.append([str(p[0]).get_file(), centre, rot, ring])
		print("   %-38s %8.1fm %8.1fm %6.1fx%.1f%s" % [
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


# ── the art scene: terrain and everything built ──────────────────────────────

func _art(by_name: Dictionary) -> String:
	var ext: Array = [
		["Script", "res://Env/terrain/generated_terrain.gd", "1_terrain", ""],
		["Script", "res://Env/terrain/terrain_recipe.gd", "2_recipe", ""],
		["Texture2D", SKETCH, "3_sketch", ""],
		["Script", "res://Env/terrain/terrain_stamp.gd", "4_stamp", ""],
		["Script", "res://Env/terrain/terrain_path.gd", "5_path", ""],
		["Script", "res://Env/terrain/terrain_scatter.gd", "6_scatter", ""],
		["Script", "res://Env/terrain/terrain_scatter_layer.gd", "7_layer", ""],
		["Resource", "res://maps/blocks/scatter/scatter_alpine_ground.tres", "8_ground", ""],
		["Resource", "res://maps/blocks/scatter/scatter_alpine_deadwood.tres", "9_dead", ""],
		["Resource", "res://maps/blocks/scatter/scatter_alpine_snags.tres", "10_snags", ""],
	]
	# The terrain data file does not exist until the first bake, and an
	# ext_resource pointing at a missing file is the silent-null bug check.sh
	# hunts for. So: write without it, bake, run this again with --force.
	var has_data := ResourceLoader.exists(DATA_PATH)
	if has_data:
		ext.append(["Resource", DATA_PATH, "11_data", ""])
	# One ext_resource per DISTINCT piece, however many times it is placed.
	# check.sh fails a scene that declares an id it never uses and a scene
	# whose load_steps is off, so both are counted rather than typed.
	var ids := {}
	for p: Array in all_pieces():
		var id := _ext_id(str(p[0]))
		if ids.has(id):
			continue
		ids[id] = true
		ext.append(["PackedScene", _piece_path(str(p[0])), id, ""])

	var subs: Array = ["Resource_recipe"]
	var curves := {}
	for l: Array in LEGS:
		curves["Curve3D_%s_%s" % [str(l[0]).to_snake_case(), str(l[1]).to_snake_case()]] = l
	for k: String in curves:
		subs.append(k)

	var out: PackedStringArray = []
	out.append("[gd_scene load_steps=%d format=3]" % (ext.size() + subs.size() + 1))
	out.append("")
	for e: Array in ext:
		out.append("[ext_resource type=\"%s\" path=\"%s\" id=\"%s\"]" % [e[0], e[1], e[2]])
	out.append("")
	out.append("[sub_resource type=\"Resource\" id=\"Resource_recipe\"]")
	out.append("script = ExtResource(\"2_recipe\")")
	for line in _recipe():
		out.append(line)
	out.append("")
	for k: String in curves:
		out.append("[sub_resource type=\"Curve3D\" id=\"%s\"]" % k)
		out.append("bake_interval = 2.0")
		out.append(_curve(by_name, curves[k]))
		out.append("")

	out.append("[node name=\"HillfortWipArt\" type=\"Node3D\"]")
	out.append("")
	out.append("[node name=\"Terrain\" type=\"Node3D\" parent=\".\"]")
	out.append("script = ExtResource(\"1_terrain\")")
	out.append("recipe = SubResource(\"Resource_recipe\")")
	if has_data:
		out.append("data = ExtResource(\"11_data\")")
	out.append("data_path = \"%s\"" % DATA_PATH)
	out.append("boundary_inset = %.1f" % BOUNDARY_INSET)
	out.append("")
	out.append("[node name=\"Scatter\" type=\"Node3D\" parent=\"Terrain\"]")
	out.append("script = ExtResource(\"6_scatter\")")
	out.append("layers = Array[ExtResource(\"7_layer\")]([ExtResource(\"8_ground\"), ExtResource(\"9_dead\"), ExtResource(\"10_snags\")])")
	out.append("")

	# ORDER IS THE WHOLE POINT. Modifiers are collected depth-first in tree
	# order and a later one wins, so: the hills and the cones raise the ground,
	# the hollows take it back down, the shelves cut flats into it, and the
	# roads cut last of all. Move Roads above Shelves and every landing
	# swallows the leg arriving at it.
	out.append("[node name=\"Hills\" type=\"Node3D\" parent=\"Terrain\"]")
	out.append("")
	var i := 1
	for g: Array in HILLS:
		out.append("[node name=\"Hill%d\" type=\"Node3D\" parent=\"Terrain/Hills\"]" % i)
		out.append(_xform(float(g[0]), 0.0, float(g[1])))
		out.append("script = ExtResource(\"4_stamp\")")
		out.append("shape = 1")
		out.append("radius = %.1f" % float(g[2]))
		out.append("falloff = %.1f" % float(g[3]))
		out.append("amount = %.1f" % float(g[4]))
		out.append("paint = 0")
		out.append("")
		i += 1

	out.append("[node name=\"HighGround\" type=\"Node3D\" parent=\"Terrain\"]")
	out.append("")
	i = 1
	for c: Array in CONES:
		out.append("[node name=\"Cone%d\" type=\"Node3D\" parent=\"Terrain/HighGround\"]" % i)
		out.append(_xform(SUMMIT.x, 0.0, SUMMIT.y))
		out.append("script = ExtResource(\"4_stamp\")")
		out.append("shape = 1")
		out.append("radius = %.1f" % float(c[0]))
		out.append("falloff = %.1f" % float(c[1]))
		out.append("amount = %.1f" % float(c[2]))
		out.append("paint = 0")
		out.append("")
		i += 1

	out.append("[node name=\"Hollows\" type=\"Node3D\" parent=\"Terrain\"]")
	out.append("")
	i = 1
	for g: Array in HOLLOWS:
		out.append("[node name=\"Hollow%d\" type=\"Node3D\" parent=\"Terrain/Hollows\"]" % i)
		out.append(_xform(float(g[0]), 0.0, float(g[1])))
		out.append("script = ExtResource(\"4_stamp\")")
		out.append("shape = 2")
		out.append("radius = %.1f" % float(g[2]))
		out.append("falloff = %.1f" % float(g[3]))
		out.append("amount = %.1f" % float(g[4]))
		out.append("paint = 0")
		out.append("")
		i += 1

	out.append("[node name=\"Shelves\" type=\"Node3D\" parent=\"Terrain\"]")
	out.append("")
	# THE BIG TERRACE GOES DOWN FIRST, so the pads and benches that stand on it
	# win where they overlap. Put it after them and the fort's plateau becomes
	# a 48 m disc with no fort on it.
	for r: Array in RINGS:
		out.append("[node name=\"%s\" type=\"Node3D\" parent=\"Terrain/Shelves\"]" % r[0])
		out.append(_xform(float(r[1]), float(r[5]), float(r[2])))
		out.append("script = ExtResource(\"4_stamp\")")
		out.append("footprint = 0")
		out.append("radius = %.1f" % float(r[3]))
		out.append("falloff = %.1f" % float(r[4]))
		out.append("paint = 1")
		out.append("")
	for s: Array in STATIONS:
		out.append("[node name=\"%s\" type=\"Node3D\" parent=\"Terrain/Shelves\"]" % s[0])
		out.append(_xform(float(s[1]), float(s[3]), float(s[2])))
		out.append("script = ExtResource(\"4_stamp\")")
		out.append("footprint = 1")
		out.append("size = Vector2(%.0f, %.0f)" % [float(s[4]), float(s[5])])
		out.append("falloff = %.1f" % float(s[6]))
		out.append("paint = 1")
		out.append("")
	for b: Array in BENCHES:
		out.append("[node name=\"%s\" type=\"Node3D\" parent=\"Terrain/Shelves\"]" % b[0])
		out.append(_xform(float(b[1]), bench_y(b), float(b[2])))
		out.append("script = ExtResource(\"4_stamp\")")
		out.append("footprint = 1")
		out.append("size = Vector2(%.0f, %.0f)" % [float(b[3]), float(b[4])])
		out.append("falloff = %.1f" % float(b[5]))
		out.append("paint = 1")
		out.append("")

	out.append("[node name=\"Roads\" type=\"Node3D\" parent=\"Terrain\"]")
	out.append("")
	for k: String in curves:
		var l: Array = curves[k]
		out.append("[node name=\"%s_%s\" type=\"Path3D\" parent=\"Terrain/Roads\"]" % [l[0], l[1]])
		out.append("curve = SubResource(\"%s\")" % k)
		out.append("script = ExtResource(\"5_path\")")
		out.append("width = %.1f" % float(l[2]))
		out.append("falloff = %.1f" % float(l[3]))
		# follow_terrain OFF is what makes this a climb rather than a track
		# over whatever is already there: the ground is graded to the curve's
		# own Y, which is the number _grades checked.
		out.append("follow_terrain = false")
		out.append("")

	var fort: Array = by_name["Fort"]
	out.append("[node name=\"Fort\" type=\"Node3D\" parent=\".\"]")
	out.append("")
	i = 1
	for p: Array in FORT_PIECES + wall_pieces() + TERRACE_DRESS:
		out.append("[node name=\"Fort%02d_%s\" parent=\"Fort\" instance=ExtResource(\"%s\")]" % [
				i, _node_tag(str(p[0])), _ext_id(str(p[0]))])
		out.append(_rot_xform(float(p[3]),
				float(fort[1]) + float(p[1]), float(fort[3]), float(fort[2]) + float(p[2])))
		out.append("")
		i += 1

	out.append("[node name=\"Stations\" type=\"Node3D\" parent=\".\"]")
	out.append("")
	i = 1
	for d: Array in STATION_DRESS:
		var st: Array = by_name[d[0]]
		out.append("[node name=\"%s%02d_%s\" parent=\"Stations\" instance=ExtResource(\"%s\")]" % [
				d[0], i, _node_tag(str(d[1])), _ext_id(str(d[1]))])
		out.append(_rot_xform(float(d[4]),
				float(st[1]) + float(d[2]), float(st[3]), float(st[2]) + float(d[3])))
		out.append("")
		i += 1
	return "\n".join(out)


# ── the level scene: spawn, navigation, objectives ───────────────────────────

func _level(by_name: Dictionary) -> String:
	var ext: Array = [
		["Script", "res://maps/trench_broom_level.gd", "1_level", ""],
		["PackedScene", "res://Env/world_objects/spawn_point.tscn", "2_spawn", "uid://g7fmy28elpah"],
		["Script", "res://Campaign/squad_spawn_point.gd", "3_squad", ""],
		["PackedScene", OUT_ART, "4_art", ""],
		["PackedScene", "res://Env/world_objects/level_exit.tscn", "5_exit", "uid://big5ms541m2j7"],
		["PackedScene", "res://Env/world_environment.tscn", "6_env", "uid://cml2uoky1hnes"],
		["Shader", "res://Env/new_sky_oct.16.gdshader", "7_sky", ""],
		["PackedScene", "res://Env/world_objects/squad_objective_point.tscn",
				"8_sqpoint", "uid://62y43tyd5sx6"],
	]
	var seen := {}
	for c: Array in CAPTURES:
		var id := _ext_id(str(c[8]))
		if seen.has(id):
			continue
		seen[id] = true
		ext.append(["PackedScene", str(c[8]), id, ""])
	var subs: Array = ["NavigationMesh_hfw", "ShaderMaterial_sky", "Sky_hfw", "Environment_hfw"]

	var out: PackedStringArray = []
	out.append("[gd_scene load_steps=%d format=3]" % (ext.size() + subs.size() + 1))
	out.append("")
	for e: Array in ext:
		var uid: String = " uid=\"%s\"" % e[3] if e[3] != "" else ""
		out.append("[ext_resource type=\"%s\"%s path=\"%s\" id=\"%s\"]" % [e[0], uid, e[1], e[2]])
	out.append("")

	# ── THE NAVMESH, SET DELIBERATELY AND NOT INHERITED.
	# A survey found agent_radius ranging 0.4 to 1.0 across the project with
	# three levels falling through to Godot's 0.5, so every number here is
	# written down even where it agrees with the default.
	out.append("[sub_resource type=\"NavigationMesh\" id=\"NavigationMesh_hfw\"]")
	# Empty placeholders: probe_nav_hillfort.gd replaces these two lines in
	# place with the baked result, and it can only replace a line that is
	# there.
	out.append("vertices = PackedVector3Array()")
	out.append("polygons = []")
	# STATIC COLLIDERS, not mesh instances. A brush prefab's visual mesh is a
	# hollow box, so parsing meshes reads the inside of the data hall as a room
	# and lays a floor on every slab in it. The terrain builds real collision,
	# so this picks up the ground as well.
	out.append("geometry_parsed_geometry_type = 1")
	out.append("cell_size = 0.25")
	out.append("cell_height = 0.25")
	out.append("agent_radius = 0.5")
	# 3.0, NOT THE 1.8 DEFAULT. The Walker is 3.00 m tall; a mesh baked at 1.8
	# describes clearance nothing in the squad actually needs and says a 2 m
	# doorway is fine.
	out.append("agent_height = 3.0")
	# agent_max_climb IS IN VOXELS OF cell_height, so 0.5 is two of them. The
	# AI's own step-over is 0.45, and the band between the baker's climb and
	# the body's step is where routes quietly close; at 0.5 that band shuts.
	out.append("agent_max_climb = 0.5")
	out.append("agent_max_slope = %.1f" % NAV_MAX_SLOPE)
	out.append("region_min_size = 6.0")
	out.append("edge_max_error = 2.0")
	out.append("detail_sample_distance = 16.0")
	# COVERS THE WHOLE MAP, with eight metres to spare on every side. On
	# Proving this box was silently clipping the bake to the old arena, and a
	# new wing would have been unwalkable with nothing saying why. It is
	# derived from SIZE_X and SIZE_Z so it cannot fall behind them.
	out.append("filter_baking_aabb = AABB(%.0f, -40, %.0f, %.0f, 400, %.0f)" % [
			-SIZE_X * 0.5 - 8.0, -SIZE_Z * 0.5 - 8.0, SIZE_X + 16.0, SIZE_Z + 16.0])
	out.append("")

	out.append("[sub_resource type=\"ShaderMaterial\" id=\"ShaderMaterial_sky\"]")
	out.append("shader = ExtResource(\"7_sky\")")
	out.append("shader_parameter/top_color = Color(0.1, 0.13, 0.19, 1)")
	out.append("shader_parameter/bottom_color = Color(0.52, 0.5, 0.47, 1)")
	out.append("shader_parameter/fog_color = Color(0.46, 0.46, 0.45, 1)")
	out.append("shader_parameter/horizon_falloff = 1.9")
	out.append("shader_parameter/fog_amount = 0.32")
	out.append("shader_parameter/fog_falloff = 3.4")
	out.append("shader_parameter/brightness = 0.85")
	out.append("")
	out.append("[sub_resource type=\"Sky\" id=\"Sky_hfw\"]")
	out.append("sky_material = SubResource(\"ShaderMaterial_sky\")")
	out.append("radiance_size = 0")
	out.append("")
	out.append("[sub_resource type=\"Environment\" id=\"Environment_hfw\"]")
	out.append("background_mode = 2")
	out.append("sky = SubResource(\"Sky_hfw\")")
	out.append("ambient_light_source = 3")
	out.append("ambient_light_color = Color(0.36, 0.38, 0.42, 1)")
	out.append("ambient_light_sky_contribution = 0.7")
	out.append("ambient_light_energy = 0.7")
	out.append("tonemap_mode = 2")
	out.append("fog_enabled = true")
	out.append("fog_light_color = Color(0.5, 0.52, 0.55, 1)")
	# THICKER THAN THE BIG MAP'S, because there is no border range here. On a
	# 1 km map a 100 m mountain wall closes the horizon; on this one the ground
	# just falls away at the edge, so the haze is what the eye stops at. Still
	# thin enough that the dish reads from the spawn, which is the one thing
	# the fog may not be allowed to take.
	out.append("fog_density = 0.0009")
	out.append("fog_sky_affect = 0.3")
	out.append("fog_height = -40.0")
	out.append("fog_height_density = 0.004")
	out.append("glow_enabled = true")
	out.append("glow_intensity = 0.55")
	out.append("glow_bloom = 0.05")
	out.append("glow_hdr_threshold = 1.0")
	out.append("")

	var trail: Array = by_name["Trailhead"]
	var fort: Array = by_name["Fort"]
	out.append("[node name=\"HillfortWipLevel\" type=\"Node3D\" node_paths=PackedStringArray(\"spawn_point\", \"nav_region\", \"level_exits\")]")
	out.append("script = ExtResource(\"1_level\")")
	out.append("spawn_point = NodePath(\"SpawnPoint\")")
	out.append("nav_region = NodePath(\"NavigationRegion3D\")")
	out.append("level_exits = [NodePath(\"NavigationRegion3D/LevelExit\")]")
	out.append("")
	# INSIDE THE PAD, measured off its own size. A fixed offset survived two
	# pad resizes on the big map and then put the spawn out on the hillside,
	# where it snapped to a scrap of navmesh that joined nothing and reported
	# the ENTIRE MAP cut off.
	out.append("[node name=\"SpawnPoint\" parent=\".\" instance=ExtResource(\"2_spawn\")]")
	out.append(_xform(float(trail[1]), float(trail[3]) + 1.15,
			float(trail[2]) + float(trail[5]) * 0.5 - 14.0))
	out.append("")
	out.append("[node name=\"SquadSpawnPoint\" type=\"Node3D\" parent=\".\"]")
	out.append(_xform(float(trail[1]) - 10.0, float(trail[3]),
			float(trail[2]) + float(trail[5]) * 0.5 - 20.0))
	out.append("script = ExtResource(\"3_squad\")")
	out.append("")
	out.append("[node name=\"NavigationRegion3D\" type=\"NavigationRegion3D\" parent=\".\"]")
	out.append("navigation_mesh = SubResource(\"NavigationMesh_hfw\")")
	out.append("")
	# INSIDE the NavigationRegion3D, so the baker sees the terrain and the
	# buildings and does not lay navmesh through the data hall.
	out.append("[node name=\"HillfortWipArt\" parent=\"NavigationRegion3D\" instance=ExtResource(\"4_art\")]")
	out.append("")
	out.append("[node name=\"LevelExit\" parent=\"NavigationRegion3D\" instance=ExtResource(\"5_exit\")]")
	out.append(_xform(float(fort[1]) + EXIT_AT.x, float(fort[3]), float(fort[2]) + EXIT_AT.y))
	out.append("")
	out.append("[node name=\"WorldEnvironment\" parent=\".\" instance=ExtResource(\"6_env\")]")
	out.append("environment = SubResource(\"Environment_hfw\")")
	out.append("")
	out.append("[node name=\"Sun\" parent=\"WorldEnvironment\" index=\"0\"]")
	# Low and from the south-east, so the face the road climbs is lit and the
	# plateau's rim throws a shadow down it.
	out.append("transform = Transform3D(0.633, 0.548, -0.547, 0, 0.706, 0.708, 0.774, -0.448, 0.447, 0, 0, 0)")
	out.append("shadow_opacity = 0.9")
	out.append("directional_shadow_max_distance = 400.0")
	out.append("")

	out.append("[node name=\"EnemySquadObjs\" type=\"Node\" parent=\".\"]")
	out.append("")
	for o: Array in OBJECTIVES:
		out.append("[node name=\"%s\" parent=\"EnemySquadObjs\" instance=ExtResource(\"8_sqpoint\")]" % o[0])
		out.append(_xform(float(o[3]), _obj_y(o), float(o[4])))
		out.append("objective_name = \"%s\"" % o[2])
		out.append("tag = &\"%s\"" % o[1])
		out.append("show_debug_label = false")
		out.append("")
	for p: Array in PATROLS:
		# A patrol point is a CHILD of its anchor, so its transform is relative
		# to it. The table holds world coordinates, so the anchor's own
		# position comes off here — emitted raw, the big map's first run put
		# the yard patrol at twice its coordinates and half a kilometre off.
		var at := Vector3.ZERO
		for o: Array in OBJECTIVES:
			if str(o[0]) == str(p[0]):
				at = Vector3(float(o[3]), _obj_y(o), float(o[4]))
		var pi := 1
		for pt: Array in p[1]:
			out.append("[node name=\"Patrol%d\" type=\"Node3D\" parent=\"EnemySquadObjs/%s\"]" % [pi, p[0]])
			# The anchor and its points are all on one flat, so the height is
			# the anchor's: a patrol point whose y came off ground_h() would
			# sit under a pad that had cut the ground away beneath it.
			out.append(_xform(float(pt[0]) - at.x, 0.0, float(pt[1]) - at.z))
			out.append("")
			pi += 1

	for c: Array in CAPTURES:
		var host: Array = by_name[c[5]]
		out.append("[node name=\"%s\" parent=\".\" node_paths=PackedStringArray(\"linked_squad_point\") instance=ExtResource(\"%s\")]" % [
				c[0], _ext_id(str(c[8]))])
		out.append(_xform(float(host[1]) + float(c[6]), float(host[3]),
				float(host[2]) + float(c[7])))
		out.append("id = &\"%s\"" % c[1])
		out.append("display_name = \"%s\"" % c[2])
		out.append("description = \"%s\"" % c[3])
		out.append("reward_resources = %d" % int(c[4]))
		out.append("linked_squad_point = NodePath(\"../EnemySquadObjs/%s\")" % _anchor_for(str(c[9])))
		out.append("")

	out.append("[editable path=\"WorldEnvironment\"]")
	out.append("")
	return "\n".join(out)


## An objective anchor's height: typed where it stands on a pad, derived off
## the stamps where it stands on the hill.
func _obj_y(o: Array) -> float:
	var y := float(o[5])
	if y < NAN_Y * 0.5:
		return y
	return roundf(ground_h(float(o[3]), float(o[4])))


## The node name of the anchor a capture reports against, looked up by the TAG
## the capture names. Missions reference anchors by tag and never by node path,
## so the tag is the thing worth writing down and the node name is derived from
## it — which also means a renamed anchor fails loudly here instead of leaving
## a capture pointing at nothing.
func _anchor_for(want: String) -> String:
	for o: Array in OBJECTIVES:
		if str(o[1]) == want:
			return str(o[0])
	push_warning("probe_build_hillfort_wip: no anchor tagged '%s' — falling back to the yard" % want)
	return "HFW_Yard"


func _recipe() -> PackedStringArray:
	return PackedStringArray([
		"size_x = %.1f" % SIZE_X,
		"size_z = %.1f" % SIZE_Z,
		"cell_size = 2.0",
		"random_seed = 23",
		# OPEN, not VALLEY: the shape of this map is a hill, not a basin, and a
		# valley floor would cut a trough through the approach.
		"layout = 2",
		"floor_at_zero = true",
		"floor_width = 200.0",
		"floor_shoulder = 90.0",
		"floor_depth = 3.0",
		"floor_roughness = 0.25",
		"floor_edge_noise = 0.35",
		"meander = 0.0",
		"meander_scale = 300.0",
		# NO BORDER RANGE AT ALL, and this is the one place the small map has to
		# differ rather than scale. The big one uses a 100 m wide, 44 m tall
		# range on three sides, which is 1/10 of that map and 1/3 of this one:
		# at this size it put the Terrace and the Trailhead INSIDE the
		# mountain, and a flat pad cut into a mountainside is the crater the
		# rules warn about. The hill itself is the relief; the fog and the
		# boundary walls close the edge.
		"border_sides = 0",
		"border_height = 0.0",
		"border_width = 0.0",
		"border_noise = 0.0",
		"border_ruggedness = 0.0",
		# TURNED DOWN, not off. Playable ground must be flat and bots cannot
		# use jagged terrain, so the recipe's own relief is texture rather than
		# shape: 3 m of hill over a 160 m wavelength is a swell you do not
		# notice walking, and the stamps overwrite it anywhere it matters.
		"hills_height = 3.0",
		"hills_scale = 160.0",
		"hills_octaves = 4",
		"hills_warp = 40.0",
		"ridge_height = 2.0",
		"ridge_scale = 220.0",
		"ridge_on_floor = 0.05",
		"detail_height = 0.4",
		"detail_scale = 14.0",
		"terrace_step = 0.0",
		"terrace_strength = 0.75",
		"crater_count = 12",
		"crater_radius_min = 3.0",
		"crater_radius_max = 9.0",
		"crater_depth = 0.25",
		"crater_rim = 0.08",
		"craters_on_floor = true",
		# Talus high and hydraulic low. Thermal erosion at the usual 42° would
		# knock the hill's flanks back to 42°, which is UNDER the navmesh's 45
		# — harmless here, because nothing on this map gates by being steep,
		# but it would also round the plateau's rim off and take the
		# prominence with it.
		"thermal_passes = 2",
		"talus_angle = 60.0",
		"hydraulic_strength = 0.2",
		# THREE PASSES, not two. Smoothing is what keeps the hillside walkable
		# rather than jagged, and at this scale one cell is a bigger share of
		# everything.
		"smooth_passes = 3",
		"sketch = ExtResource(\"3_sketch\")",
		"sketch_metres_per_pixel = 4.0",
		"sketch_blend = 14.0",
		"sketch_edge_noise = 14.0",
		# Low on purpose. The white mask is here for the rock ZONE; the hill's
		# real 70 m is stamped on afterwards.
		"sketch_mountain_height = 2.5",
		# No painted water anywhere, and the level parked far below the map:
		# water_level is ONE global height, so a tarn on the plateau would
		# flood the trailhead to match.
		"water_level = -200.0",
		"water_depth = 5.0",
		"water_bank = 30.0",
		"urban_block = Vector2(40, 32)",
		"urban_street = 8.0",
		"urban_angle = 0.0",
		"urban_ruin = 0.25",
		"shelling_per_hectare = 24.0",
		"rough_height = 4.0",
		"road_width = 5.0",
		"road_falloff = 5.0",
		"road_smoothing = 40.0",
		"bridge_clearance = 2.0",
	])


# ── text ─────────────────────────────────────────────────────────────────────

## An ext_resource id for a piece. It has to be unique per PATH and stable
## across runs, and a block name and a res:// path can both arrive here.
func _ext_id(name_: String) -> String:
	return "p_" + name_.get_file().get_basename()


## The part of a node name that says what the piece is.
func _node_tag(name_: String) -> String:
	return name_.get_file().get_basename()


func _zeros(n: int) -> PackedStringArray:
	var z: PackedStringArray = []
	for _i in n:
		z.append("0")
	return z


func _xform(x: float, y: float, z: float) -> String:
	return "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)" % [_n(x), _n(y), _n(z)]


func _rot_xform(yaw_deg: float, x: float, y: float, z: float) -> String:
	var yaw := deg_to_rad(yaw_deg)
	return "transform = Transform3D(%s, 0, %s, 0, 1, 0, %s, 0, %s, %s, %s, %s)" % [
			_n(cos(yaw)), _n(-sin(yaw)), _n(sin(yaw)), _n(cos(yaw)), _n(x), _n(y), _n(z)]


## Godot's own float formatting, so the file reads the way the editor writes it.
func _n(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return String.num(v, 4).rstrip("0").rstrip(".")
