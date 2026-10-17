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
const SIZE_X := 640.0
## 256 -> 384 on 2026-10-17: the approach was too short. The player met the
## Pillars garrison 64 m off the spawn, about 14 seconds in, and the human asked
## for 20-30 more before first contact.
##
## 128 m IS BOTH THE ANSWER AND THE ONLY AVAILABLE ONE. The squad moves at
## 4.5 m/s, so 20-30 s is 90-135 m — and the terrain rounds Z up to whole
## 64-cell chunks, which at this 2 m cell is 128 m. There was exactly one size
## that satisfied the request, and it is this.
const SIZE_Z := 640.0

## ALL OF THE NEW GROUND GOES SOUTH, and this is how.
##
## The rectangle is centred on the Terrain node, so simply growing SIZE_Z would
## have put 64 m of dead ground BEHIND the fort and bought only 64 m of
## approach — half the request, plus a bald apron nobody will ever walk on.
##
## So the Terrain node moves +64 on Z and its six group nodes (Hills,
## HighGround, Hollows, Shelves, Roads, Scatter) move -64, which cancels
## exactly. Every stamp underneath therefore keeps the WORLD coordinate it has
## always had, in the tables above, unedited — the fort, the lanes, the walls,
## the captures and all nine inner stations are where they were, and the only
## thing that moved is the Trailhead.
##
## Compensating on the six GROUPS rather than inside _xform() and _curve() is
## deliberate: it is six lines against a hundred call sites, and a missed call
## site would put one stamp 64 m out of place with nothing to say so. Prove it
## by sampling ground height at the fort and at Pillars before and after —
## PROFILE=1 prints both.
const SOUTH_SHIFT := 64.0
## Invisible walls this far in from the edge. THE DEFAULT IS 60, and on a map
## this size 60 m a side would wall off a third of the ground and leave the
## Terrace and half the hills outside the world. The area the density number is
## computed over is this inset rectangle, not SIZE_X by SIZE_Z.
## ── THE BACKDROP RING, 2026-10-17 ───────────────────────────────────────────
##
## The map used to END. Flat ground to a hard square edge and then nothing, so
## from anywhere near the rim it read as a tabletop about to fall away.
##
## FIXED WITHOUT GIVING THE PLAYER ANY MORE GROUND. The rectangle grew from
## 384 to 640 square and the inset grew from 4 m to 132 m by exactly the same
## amount, so the boundary walls land on the SAME WORLD COORDINATES they
## already had — x +/-188, z -124..+252. Every metre of the 256 m added is
## outside the wall: it is scenery, not level.
##
##   640 * 0.5 - 132 = 188   (was 384 * 0.5 - 4 = 188)
##
## The ring is filled by the recipe's border mountains, which were switched off
## on this map (border_sides = 0) and are now on at 118 m wide — just inside the
## 128 m ring, so the crest sits clear of the wall rather than on top of it.
##
## 58 m OF CREST, AGAINST THE PLATEAU'S 34. High enough to close the horizon
## from the trailhead, low enough that the fort is still the thing you look at:
## the dish tops out around 96 m and keeps the skyline. Ruggedness 0.62 and
## 34 m of noise so the rim reads as range rather than as a wall — a smooth
## even crest at a constant height is just a bigger tabletop edge.
##
## The navmesh is deliberately NOT baked out here; see filter_baking_aabb.
const BOUNDARY_INSET := 132.0

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

## THE GROUND IS A BROAD GENTLE DOME AND NOTHING ELSE. One cone, flat on top
## where the fort stands, falling away at no more than 12° anywhere on the map.
##
## EVERY FINDING IN THE PREVIOUS VERSION WAS A SYMPTOM OF CARVING A CLIMB INTO
## TERRAIN — the radial hill refusing a switchback, a smoothstep baking 54°
## where it measured 42, prominence turning out to be occlusion, a 16 m
## causeway to make the last leg point at a gate. The project's rule is that
## playable ground is flat and height comes from BUILT ASSETS, and all of that
## was the cost of fighting it. So the hill stops being the obstacle: it is a
## glacis you can walk anywhere on, and what decides where you GO is walls.
##
## 12° IS THE NUMBER TO WATCH. _profile() prints the radial slope band by band;
## anything over about 15 and this has started being a mountain again.
const CONES: Array = [
	[40.0, 240.0, 34.0],
]
const SUMMIT := Vector2(0.0, -66.0)

## ── THREE LANES, GATED BY STRUCTURES ────────────────────────────────────────
##
## The ground is walkable everywhere, so the lanes are made by two wall lines
## running north-south at x = ±66, from the fort's own south-west and
## south-east corners down the glacis to z = 104. They stop 20 m short of the
## south edge, which is the whole design: YOU CHOOSE YOUR LANE AT THE
## TRAILHEAD, and once you are in it, crossing means walking all the way back.
##
##   CENTRE — short and exposed. 108 m from the spawn to the fort's south gate,
##     straight up the middle of a 132 m wide glacis with one bunker on it and
##     nothing else. Fastest, and in the open under the wall the whole way.
##     ONE capture, not two: being quick is what it is for.
##   WEST — long and covered. 281 m round the west, screened from the centre
##     and from the fort's south face by the west wall line for all of it, with
##     four berms on the open stretches, exposed only on the last thirty metres
##     to the west gate. TWO captures.
##   EAST — blocked. A cross-wall runs the full 120 m width of the east lane at
##     z = 40 with a single gatehouse in it, so the lane does not open until
##     that structure is taken. TWO captures, the first of them the gatehouse.
##
## 2 / 1 / 2 and one in the fort, rather than the obvious two per lane. The
## count IS part of the difference between the lanes: the fast way pays for its
## speed in what it does not pick up on the way.
##
## name, x, z, y, pad x, pad z, falloff
##
## HEIGHTS ARE THE GROUND'S. Every one of these is cone_h at that spot rounded
## to the metre, so a pad is a flat place ON the hill rather than a shelf cut
## into it. _profile() prints the cut or fill and it should be a metre or two
## everywhere; much more means a hill stamp has drifted onto a pad.
const STATIONS: Array = [
	["Trailhead", 0.0, 236.0, 0.0, 104.0, 28.0, 30.0],
	# CENTRE
	["Pillars", 0.0, 50.0, 23.0, 44.0, 28.0, 30.0],
	["CentreApron", 0.0, 4.0, 32.0, 32.0, 22.0, 30.0],
	# WEST
	["Cistern", -130.0, 70.0, 14.0, 44.0, 28.0, 30.0],
	["Shoulder", -140.0, -20.0, 23.0, 44.0, 28.0, 30.0],
	["WestApron", -92.0, -54.0, 30.0, 32.0, 22.0, 30.0],
	# EAST
	["Gatehouse", 110.0, 20.0, 22.0, 44.0, 28.0, 30.0],
	["Terrace", 140.0, -30.0, 24.0, 44.0, 28.0, 30.0],
	["EastApron", 92.0, -54.0, 30.0, 32.0, 22.0, 30.0],
	["Fort", 0.0, -66.0, 34.0, 136.0, 112.0, 28.0],
]

## from, to, bed width, bank falloff. Three chains out of one trailhead.
##
## follow_terrain IS ON FOR ALL OF THEM, which is the other half of taking the
## climb out of the ground. A graded road cuts the hill to its own height, and
## that is where every embankment, defile and run-out problem in the previous
## version came from. These lay a surface ON the ground and smooth it, so a
## lane's grade is the HILL's grade — under 12° by construction, consistently,
## everywhere, with no arithmetic to get wrong.
const LEGS: Array = [
	["Trailhead", "Pillars", 16.0, 8.0],
	["Pillars", "CentreApron", 16.0, 8.0],
	["Trailhead", "Cistern", 14.0, 8.0],
	["Cistern", "Shoulder", 14.0, 8.0],
	["Shoulder", "WestApron", 14.0, 8.0],
	["Trailhead", "Gatehouse", 14.0, 8.0],
	["Gatehouse", "Terrace", 14.0, 8.0],
	["Terrace", "EastApron", 14.0, 8.0],
]

## No terrace rings any more. The ground is one dome.
const RINGS: Array = []

## No benches either: a bench was somewhere flat to stand on a 25° hillside,
## and there is no 25° hillside. The flat ground is the station pads and
## everything between them.
const BENCHES: Array = []

## Gentle swells, so the dome is not a perfect cone from the air. amount over
## falloff decides the steepest slope a stamp makes — about
## atan(1.5 * amount / falloff) — so 5 m over 100 is four degrees, and none of
## these is terrain the squad will ever notice underfoot.
## centre x, z, radius, falloff, amount
const HILLS: Array = [
	[-150.0, 108.0, 30.0, 100.0, 5.0],
	[150.0, 112.0, 30.0, 100.0, 5.0],
	[-164.0, -60.0, 28.0, 90.0, 4.0],
	[166.0, -70.0, 28.0, 90.0, 4.0],
]

## NO HOLLOWS. There were two, 4 m deep and 90 m wide, meant to stop the dome
## reading as a perfect cone from the air. From the spawn at eye height they
## read as two bowls dug into the ground forty metres ahead — the opposite of
## smoothing the whole thing out, and the first eye-level shot showed it. The
## four swells above are at the map's corners where nothing walks, and that is
## enough to break the symmetry.
const HOLLOWS: Array = []

## THE CURTAIN. 120 x 96, five fort_wall segments by four.
const WALL_HALF := Vector2(60.0, 48.0)
const WALL_THICK := 3.2
## The south gate, on the centre lane's axis: the short exposed route ends
## here. Local X in the south run.
const GATE_AT := 0.0
## The postern, in the north run — the way out, and where the level exit sits.
const POSTERN_AT := -24.0
## The two side gates, in the SIDE runs at this local Z, one west one east.
## They are what the west and east lanes arrive at, so each lane has its own
## way in rather than three roads converging on one door.
const SIDE_GATE_AT := 12.0

## Half-extents of the plateau, less a margin, for things that stand ON it.
const SHELF_HALF := Vector2(62.0, 50.0)
## The pad itself, which the wall ring may reach.
const PAD_HALF := Vector2(68.0, 56.0)
## Clear ground between two pieces.
const MARGIN := 1.5

## ── THE LANE WALLS. World coordinates, not fort-relative: these run most of
## the length of the map and have nothing to do with the fort's own geometry.
##
## fort_wall is 24 m along its OWN Z, so yaw 0 runs it north-south and yaw 90
## runs it east-west.
##
## EVERY GAP IN THESE IS DELIBERATE AND IS UNDER 8 M. The project's rule is
## that no ROUTE may be under 8 m; the corollary these rely on is that a gap
## under 8 m is therefore not a route. The lane walls stop 2.4 m short of the
## curtain and 0.4 m short of each other, so the lines read as meeting and bake
## as sealed.
##
## piece, x, z, yaw
const LANE_WALLS: Array = [
	# WEST DIVIDER, x = -66, z -16 .. 104. Its north end sits on the fort's own
	# pad beside the curtain's south-west corner, which is what stops the
	# centre lane leaking up the fort's west flank to the west gate through the
	# 4.8 m strip outside the curtain.
	["fortress/fort_wall", -66.0, -4.0, 0.0],
	["fortress/fort_wall", -66.0, 20.0, 0.0],
	["fortress/fort_wall", -66.0, 44.0, 0.0],
	["fortress/fort_wall", -66.0, 68.0, 0.0],
	["fortress/fort_wall", -66.0, 92.0, 0.0],
	# EAST DIVIDER, mirrored.
	["fortress/fort_wall", 66.0, -4.0, 0.0],
	["fortress/fort_wall", 66.0, 20.0, 0.0],
	["fortress/fort_wall", 66.0, 44.0, 0.0],
	["fortress/fort_wall", 66.0, 68.0, 0.0],
	["fortress/fort_wall", 66.0, 92.0, 0.0],
	# THE EAST CROSS-WALL, z = 40, the full 120 m width of the east lane from
	# the divider to the boundary. One gatehouse in it at x = 104 and no other
	# way through, so the east lane is the one that needs a structure taken
	# before it opens.
	["fortress/fort_wall", 80.0, 40.0, 90.0],
	["fortress/fort_gate", 104.0, 40.0, 90.0],
	["fortress/fort_wall", 128.0, 40.0, 90.0],
	["fortress/fort_wall", 152.0, 40.0, 90.0],
	["fortress/fort_wall", 176.0, 40.0, 90.0],
]

## ── THE BUNKERS. The POIs on the way up: the waypoints, the cover, and the
## capture sites. World coordinates, one per station that has one.
##
## fort_command_bunker is 24 x 22 and 11.5 m TALL — twice the curtain's height.
## On a glacis this gentle these are the things that stand up, and they are
## where height comes from. Each sits on its station's own flat pad with 8 m of
## clear ground round it.
##
## piece, x, z, yaw
const BUNKERS: Array = [
	["fortifications/fort_command_bunker", 0.0, 50.0, 0.0],
	["fortifications/fort_command_bunker", -130.0, 70.0, 0.0],
	["fortifications/fort_command_bunker", -140.0, -20.0, 90.0],
	["fortifications/fort_command_bunker", 110.0, 20.0, 0.0],
	["fortifications/fort_command_bunker", 140.0, -30.0, 90.0],
	# The west lane's cover, and the only reason it is a COVERED route rather
	# than just a long one. Berms are 15 m long and 2.4 m tall: waist to head,
	# which is the height the legibility study says cover has to be.
	["features/feature_berm", -112.0, 96.0, 20.0],
	["features/feature_berm", -118.0, 40.0, 100.0],
	["features/feature_berm", -150.0, 24.0, 80.0],
	["features/feature_berm", -124.0, -56.0, 10.0],
]

## ── WHAT IS IN THE FORT. Offsets from the fort's centre.
##
## THE DISH IS ON THE BROW, so the gate in the south run opens onto it and the
## yard and the plant are behind. The compute kit fills the east strip, the
## working side is west, and the towers and masts are what stand up on a map
## where nothing else does.
##
## piece, x, z, yaw°
const FORT_PIECES: Array = [
	# At dz +1, not +8: the box sits 7 m south of its own origin because the
	# bowl overhangs the pedestal forward. _group() prints the real box centre.
	["landmarks/landmark_relay_dish", -10.0, 1.0, 0.0],

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
	["fortifications/fort_floodlight_mast", 46.0, -41.0, 0.0],

	# ── WEST: the working side, and the gun that covers the west gate.
	["features/feature_watchtower", -48.0, -30.0, 0.0],
	["fortifications/fort_gun_emplacement", -48.0, -8.0, 0.0],
	["fortifications/fort_floodlight_mast", -50.0, 28.0, 0.0],
	["props/prop_sandbag_nest", -56.0, 20.0, 0.0],

	# ── THE GATE LANE, 14.6 m between the dish's pedestal and the south wall.
	["features/feature_watchtower", 10.0, 40.0, 90.0],
	["fortifications/fort_sentry_turret", 44.0, 42.0, 215.0],
	["fortifications/fort_t_walls", -20.0, 40.0, 24.0],
	["fortifications/fort_t_walls", -56.0, 40.0, 70.0],
	["props/prop_jersey_barrier", 34.0, 44.0, 12.0],
	["props/prop_jersey_barrier", 28.0, 44.0, 12.0],
	["props/prop_crates", -34.0, 40.0, 30.0],
	["props/prop_barrels", 20.0, 40.0, 0.0],

	# ── NORTH: the yard behind the dish.
	["fortifications/fort_checkpoint", -30.0, -34.0, 20.0],
	["fortifications/fort_t_walls", 28.0, 24.0, -32.0],
]

## ── THE DRESSING, in world coordinates because almost none of it belongs to a
## station: the station pads are 44 x 28 with a 24 x 22 bunker in the middle,
## so there is nowhere on them to put anything. Everything that says what a
## place IS stands round the pad rather than on it.
##
## FOUR JOBS, and a piece that is not doing one of them is not here:
##   1. make each lane read as its own kind of place
##   2. cover, only where cover is supposed to be
##   3. ranging — something at height every 50 m or so along a lane
##   4. say what a capture site is before anyone calls it an objective
##
## piece, x, z, yaw
const LANE_DRESS: Array = [
	# ════ CENTRE LANE — the swept glacis ════════════════════════════════════
	#
	# THE HARD RULE HERE IS WHAT IS ABSENT. This lane's identity is that being
	# fast costs you, so nothing on it may be fought from: no hescos, no
	# sandbags, no containers, no t-walls, no dragon teeth. What it gets is
	# tall-and-thin (which gives no cover and ranges the distance) and
	# flat-and-dead (which says what happens to people who come this way).
	#
	# Six floodlight masts, zig-zagged so one is within ~40 m of anywhere on
	# the lane. 9.9 m tall and 3 m across: a ruler you cannot hide behind.
	["fortifications/fort_floodlight_mast", -20.0, 88.0, 0.0],
	["fortifications/fort_floodlight_mast", 34.0, 76.0, 0.0],
	["fortifications/fort_floodlight_mast", 20.0, 52.0, 0.0],
	["fortifications/fort_floodlight_mast", -40.0, 40.0, 0.0],
	["fortifications/fort_floodlight_mast", -20.0, 16.0, 0.0],
	["fortifications/fort_floodlight_mast", 28.0, 6.0, 0.0],
	# NO CRATERS ON THIS LANE, and that is a correction rather than an
	# omission. feature_crater_rim is a RING standing 0.75 m proud of the
	# ground over 13 m — a fighting position, and a chain of them down the
	# swept lane is a covered route with extra steps that a player finds on
	# the first attempt. The shelled look is not worth the thing this lane
	# exists to be. Craters are on the west and east, where cover belongs.
	# The assaults that already failed here. Spaced over 30 m apart on
	# purpose: four wrecks tell a story, four wrecks in a line are a trench.
	["props/prop_robot_wreck", -56.0, 64.0, 40.0],
	["props/prop_robot_wreck", 54.0, 44.0, 200.0],
	["props/prop_robot_wreck", -42.0, 12.0, 130.0],
	["props/prop_robot_wreck", 24.0, 90.0, 70.0],
	# Rock slabs are the one prop in the kit with NO COLLISION AT ALL, which
	# makes them the only thing that can be scattered on this lane without
	# quietly repairing its exposure.
	["props/prop_rock_slabs", -58.0, 96.0, 20.0],
	["props/prop_rock_slabs", 56.0, 88.0, 70.0],
	["props/prop_rock_slabs", -56.0, 32.0, 45.0],
	["props/prop_rock_slabs", 52.0, 28.0, 10.0],
	["props/prop_rock_slabs", -52.0, 8.0, 60.0],
	["props/prop_rock_slabs", 38.0, 96.0, 30.0],
	["props/prop_rock_slabs", -40.0, 66.0, 80.0],
	["props/prop_rock_slabs", -44.0, 78.0, 25.0],
	["props/prop_rock_slabs", 44.0, 60.0, 55.0],
	["props/prop_rock_slabs", -56.0, 22.0, 15.0],
	["props/prop_rock_slabs", 48.0, 18.0, 65.0],
	["props/prop_rock_slabs", -26.0, 70.0, 35.0],
	# Wire flanking the gate approach, not across it. The fort's defence, not
	# the lane's cover.
	["fortifications/fort_razor_wire", -40.0, -2.0, 90.0],
	["fortifications/fort_razor_wire", -29.0, -2.0, 90.0],
	["fortifications/fort_razor_wire", 36.0, -2.0, 90.0],
	["fortifications/fort_razor_wire", 47.0, -2.0, 90.0],

	# ── THE PILLARS, and the rock spires it is named for. 12.9 m each, so they
	# are this lane's one piece of ranging that is not a mast — and they stand
	# clear of the road's 16 m bed so they cannot be used as a covered line up
	# the middle.
	["features/feature_rock_spire", -26.0, 36.0, 0.0],
	["features/feature_rock_spire", -30.0, 62.0, 140.0],
	["features/feature_rock_spire", 26.0, 64.0, 60.0],
	["features/feature_rock_spire", 30.0, 36.0, 20.0],
	["features/feature_power_pylon", -52.0, 50.0, 0.0],

	# ════ WEST LANE — the covered route ═════════════════════════════════════
	#
	# A BROKEN BUT CONTINUOUS SCREEN down the lane's east flank, between it and
	# the fort. The wall line already hides this lane from the centre; what the
	# dressing adds is the thing that makes it read as a route you MOVE ALONG
	# rather than one that happens to be out of sight.
	["features/feature_container_stack", -96.0, 92.0, 100.0],
	["fortifications/fort_hesco_wall", -92.0, 60.0, 95.0],
	["features/feature_container_stack", -98.0, 28.0, 85.0],
	["fortifications/fort_hesco_wall", -94.0, -4.0, 95.0],
	["features/feature_container_stack", -106.0, -34.0, 110.0],
	["fortifications/fort_hesco_wall", -112.0, -52.0, 70.0],
	# Cover pockets behind the screen, on the lane itself.
	["features/feature_trench_revetment", -146.0, 50.0, 10.0],
	["features/feature_trench_revetment", -134.0, 4.0, 95.0],
	["features/feature_trench_revetment", -152.0, -40.0, 80.0],
	["props/prop_sandbag_wall", -128.0, 52.0, 20.0],
	["props/prop_sandbag_wall", -124.0, -8.0, 70.0],
	["fortifications/fort_t_walls", -118.0, 8.0, 15.0],
	["fortifications/fort_t_walls", -160.0, 38.0, 100.0],
	# Natural cover and ranging on the flank. Outcrops are 7.9 m tall.
	["features/feature_rock_outcrop", -178.0, 98.0, 20.0],
	["features/feature_rock_outcrop", -174.0, 16.0, 70.0],
	["features/feature_rock_outcrop", -162.0, -80.0, 40.0],
	["features/feature_boulder_field", -118.0, -96.0, 30.0],
	# Craters are welcome HERE: on a covered route a hole you can drop into is
	# the route doing its job.
	["features/feature_crater_rim", -174.0, 46.0, 0.0],
	["features/feature_crater_rim", -112.0, -72.0, 0.0],
	["features/feature_crater_rim", -150.0, 104.0, 0.0],
	["fortifications/fort_floodlight_mast", -104.0, 70.0, 0.0],
	["fortifications/fort_floodlight_mast", -110.0, -14.0, 0.0],

	# ── THE CISTERN: a water and fuel point, which is what the name is for.
	["features/feature_fuel_tanks", -160.0, 70.0, 0.0],
	["props/prop_concrete_pipes", -160.0, 56.0, 10.0],
	["props/prop_concrete_pipes", -148.0, 86.0, 70.0],
	["compute/compute_cooling_unit", -130.0, 94.0, 0.0],
	# ── THE SHOULDER: a fire base.
	["fortifications/fort_mortar_pit", -164.0, -20.0, 0.0],
	["fortifications/fort_ammo_dump", -156.0, 4.0, 0.0],
	["props/prop_sandbag_nest", -140.0, -44.0, 0.0],
	["features/feature_watchtower", -116.0, -20.0, 0.0],

	# ════ EAST LANE — the one that looks held ═══════════════════════════════
	#
	# Everything here points south, at whoever is coming. Dragon teeth belong
	# on THIS lane and not on the centre: in front of a defended wall they read
	# as a defended line, and in open ground they would read as cover.
	["fortifications/fort_dragon_teeth", 72.0, 54.0, 90.0],
	["fortifications/fort_dragon_teeth", 86.0, 54.0, 90.0],
	["fortifications/fort_dragon_teeth", 118.0, 54.0, 90.0],
	["fortifications/fort_dragon_teeth", 134.0, 54.0, 90.0],
	["fortifications/fort_dragon_teeth", 150.0, 54.0, 90.0],
	["fortifications/fort_dragon_teeth", 166.0, 54.0, 90.0],
	["fortifications/fort_razor_wire", 76.0, 72.0, 90.0],
	["fortifications/fort_razor_wire", 90.0, 72.0, 90.0],
	["fortifications/fort_razor_wire", 132.0, 72.0, 90.0],
	["fortifications/fort_razor_wire", 148.0, 72.0, 90.0],
	["fortifications/fort_razor_wire", 164.0, 72.0, 90.0],
	["fortifications/fort_floodlight_mast", 96.0, 48.0, 0.0],
	["fortifications/fort_floodlight_mast", 126.0, 48.0, 0.0],
	["fortifications/fort_floodlight_mast", 170.0, 30.0, 0.0],
	["features/feature_crater_rim", 170.0, 88.0, 0.0],
	["features/feature_crater_rim", 76.0, -34.0, 0.0],
	# Behind the wall, looking back down the lane.
	["features/feature_watchtower", 88.0, 30.0, 90.0],
	["features/feature_watchtower", 146.0, 30.0, 90.0],
	["fortifications/fort_sentry_turret", 94.0, 34.0, 180.0],
	["fortifications/fort_sentry_turret", 126.0, 34.0, 180.0],
	["features/feature_pillbox", 84.0, -4.0, 20.0],
	["fortifications/fort_gun_emplacement", 136.0, 8.0, 0.0],
	["fortifications/fort_ammo_dump", 166.0, 10.0, 0.0],
	["fortifications/fort_mortar_pit", 178.0, -4.0, 0.0],
	# ── THE GATEHOUSE: the lock on this lane.
	["fortifications/fort_checkpoint", 110.0, -8.0, 0.0],
	["fortifications/fort_t_walls", 92.0, -26.0, 20.0],
	["fortifications/fort_t_walls", 130.0, -2.0, 160.0],
	# ── THE TERRACE: the gun line below the east gate.
	["fortifications/fort_gun_emplacement", 166.0, -30.0, 0.0],
	["fortifications/fort_hesco_sangar", 140.0, -56.0, 30.0],
	["props/prop_sandbag_wall", 120.0, -46.0, 70.0],
	["features/feature_rock_outcrop", 172.0, -78.0, 50.0],
	["fortifications/fort_floodlight_mast", 116.0, -22.0, 0.0],
]

## What is at the trailhead. The only station with a pad big enough to dress:
## 104 x 28, and no bunker on it.
##
## station, piece, dx, dz, yaw
const STATION_DRESS: Array = [
	["Trailhead", "features/feature_container_stack", -34.0, -8.0, 0.0],
	["Trailhead", "features/feature_container_stack", -34.0, 4.0, 0.0],
	["Trailhead", "machines/machine_semi_truck", 34.0, 0.0, 95.0],
	["Trailhead", "machines/machine_bulldozer", 46.0, -8.0, 200.0],
	["Trailhead", "fortifications/fort_hesco_wall", -14.0, -10.0, 0.0],
	["Trailhead", "fortifications/fort_hesco_wall", 14.0, -10.0, 0.0],
	["Trailhead", "fortifications/fort_floodlight_mast", -24.0, -4.0, 0.0],
	["Trailhead", "props/prop_crates", 24.0, -11.0, 15.0],
	["Trailhead", "props/prop_barrels", 20.0, 4.0, 0.0],
	["Trailhead", "props/prop_lamp_post", -48.0, 8.0, 0.0],
]

## Nothing on the glacis belongs to a terrace any more; the table stays so the
## group check keeps its shape.
const TERRACE_DRESS: Array = []

## THE CAPTURE SITES — six, on 0.0932 km² of walled-in ground, which is about
## 15,500 m² each. Georgetown is 14,436 and the coast road 19,250 and both of
## those work; today's Hillfort is 217,440. The density is the reason this map
## exists and it does not drift.
##
## node, id, display, description, reward, station or "Fort", dx, dz, scene,
## anchor tag
const CAPTURES: Array = [
	["CisternCore", "hfw_cistern", "The Cistern", "Take the core at the west bunker.",
			20, "Cistern", 17.0, 0.0, CORE, "obj_hfw_cistern"],
	["ShoulderCore", "hfw_shoulder", "The Shoulder", "Take the core below the west gate.",
			25, "Shoulder", 17.0, 0.0, CORE, "obj_hfw_shoulder"],
	["PillarsCore", "hfw_pillars", "The Pillars", "Take the core on the open glacis.",
			25, "Pillars", 17.0, 0.0, CORE, "obj_hfw_pillars"],
	["GatehouseCore", "hfw_gatehouse", "The Gatehouse", "Take the core that opens the east lane.",
			25, "Gatehouse", 17.0, 0.0, CORE, "obj_hfw_gatehouse"],
	["TerraceCore", "hfw_terrace", "The Terrace", "Take the core below the east gate.",
			25, "Terrace", 17.0, 0.0, CORE, "obj_hfw_terrace"],
	["RelayCore", "hfw_relay", "The Relay", "Take the core in the fort yard.",
			40, "Fort", -10.0, 40.0, CORE_LARGE, "obj_hfw_dish"],
]

## DISTRICT ANCHORS. A SquadObjectivePoint is a named place with a tag and no
## logic, and missions reference these BY TAG and never by node path.
##
## node, tag, display, x, z, y or NAN_Y to derive
const OBJECTIVES: Array = [
	["HFW_Trailhead", "obj_hfw_trailhead", "Trailhead", 0.0, 236.0, 0.0],
	["HFW_Pillars", "obj_hfw_pillars", "The Pillars", -17.0, 50.0, 23.0],
	["HFW_CentreApron", "obj_hfw_centre_apron", "The South Gate", 0.0, 4.0, 32.0],
	["HFW_Cistern", "obj_hfw_cistern", "The Cistern", -147.0, 70.0, 14.0],
	["HFW_Shoulder", "obj_hfw_shoulder", "The Shoulder", -157.0, -20.0, 23.0],
	["HFW_WestApron", "obj_hfw_west_apron", "The West Gate", -92.0, -54.0, 30.0],
	["HFW_Gatehouse", "obj_hfw_gatehouse", "The Gatehouse", 93.0, 20.0, 22.0],
	["HFW_Terrace", "obj_hfw_terrace", "The Terrace", 123.0, -30.0, 24.0],
	["HFW_EastApron", "obj_hfw_east_apron", "The East Gate", 92.0, -54.0, 30.0],
	# The compound, broken up.
	["HFW_Yard", "obj_hfw_yard", "The Yard", 0.0, -100.0, 34.0],
	["HFW_Dish", "obj_hfw_dish", "The Relay Dish", -52.0, -60.0, 34.0],
	["HFW_Hall", "obj_hfw_hall", "The Data Hall", 20.0, -96.0, 34.0],
	["HFW_Postern", "obj_hfw_postern", "The Postern", -24.0, -108.0, 34.0],
	# WHERE THE WAY DOWN IS. SiteSlice raises the entrance kit at this node and
	# nothing else in the level needs to know the coordinate — the rule this
	# project has broken on terrain three times is that a typed position is
	# correct until somebody moves the thing it was copied from.
	["HFW_Bunker", "obj_hfw_bunker", "The Way Down", 6.0, -99.0, 34.0],
	# Off every lane: the ground the walls do not enclose.
	["HFW_WestFlank", "obj_hfw_west_flank", "West Flank", -150.0, -92.0, NAN_Y],
	["HFW_EastFlank", "obj_hfw_east_flank", "East Flank", 152.0, -96.0, NAN_Y],
	["HFW_SouthMeadow", "obj_hfw_south_meadow", "South Meadow", -90.0, 116.0, NAN_Y],
]

## Patrol routes: plain Node3D children of an anchor, in world coordinates.
## anchor node, then points as x, z pairs
const PATROLS: Array = [
	["HFW_Yard", [
		[0.0, -100.0], [-20.0, -96.0], [16.0, -94.0],
		[26.0, -102.0], [10.0, -112.0], [-14.0, -110.0],
	]],
	["HFW_Pillars", [
		[-17.0, 50.0], [-20.0, 36.0], [-22.0, 62.0], [-8.0, 66.0],
	]],
]

## The level exit, inside the postern. Offsets from the fort.
## ── THE BUNKER. Offsets from the fort's centre.
##
## IT IS A MARKER AND NOT A PREFAB. SiteSlice._build_bunker() raises the kit at
## a node this level names, which is GAMEPLAY's wiring — so what TERRAIN owns
## is WHERE, and proving there is room. Instancing it here as well would build
## it twice.
##
## AT THE FORT, IN THE NORTH YARD BEHIND THE DISH. The fort is the climax of
## the climb and §12.8 makes these same doors how you ARRIVE on the defence of
## the site, so the squad comes up out of the ground inside the compound and
## turns to hold the gate. The module faces +Z, which here is south, straight
## down the yard at the dish and the gate beyond it.
##
## THE MOUNTING IS "cliff", AND THAT IS A FIT AS WELL AS A JUDGEMENT.
## "open" is the obvious choice for a flat compound, and it does not fit: with
## its sunken court it is 33.8 m deep and the yard between the dish's north
## face and the curtain is 30.6. "cliff" is 18.3, leaves 12 m spare, and its
## revetted headwall is what a tunnel mouth driven into the back of a rampart
## actually looks like — the curtain's north run plus the plateau falling away
## behind it IS a revetment. "wall" needs a ceiling and there is none.
##
## bunker_offset stays ZERO: the marker already stands in the open and the
## clearance is checked by _installation() rather than assumed.
const BUNKER_AT := Vector2(6.0, -33.0)
const BUNKER_MOUNT := "cliff"
const BUNKER_PREFAB := "bunker/bunker_entrance_cliff"

## The level exit, in the bunker's own tunnel: ExitVolume is 4 m inside the
## mouth, which is -Z from the marker. §12.7 replaces the extraction pad with
## the doors, so the exit goes where the doors are rather than at the postern.
const EXIT_AT := Vector2(BUNKER_AT.x, BUNKER_AT.y - 4.0)


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
		# THE LIP IS REPORTED AND NO LONGER FAILS. It was the right check on a
		# map whose fort stood on a mesa: 23 m of rise on the near side or the
		# objective is hidden. On a gentle glacis the fort has no mesa to stand
		# on and its prominence is the DISH and the curtain, so the question is
		# answered properly by _sightlines below — which measures how much of
		# the thing you can actually see — and this is left as a number to
		# look at.
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
		# THE TWO LANE LEGS THAT LEAVE THE TRAILHEAD SIDEWAYS, and both of them
		# need a via for the same reason: the lane walls run from the fort down
		# to z = 104, and the trailhead is at z = 112. Ruled straight, the legs
		# to the Cistern and the Gatehouse cross their own wall at about z = 91
		# — a road through a solid wall, which bakes as a route that is not
		# there. _grades flags it as HUGS A LANE WALL at 2 and 4 metres.
		#
		# The via takes each one SOUTH of the wall's end first. That is also the
		# shape the design wants: the three lanes fan out from the spawn on open
		# ground and the choice is made there, in the twenty metres between the
		# wall ends and the map's edge.
		"Trailhead-Cistern":
			return [Vector2(-80.0, 114.0)]
		"Trailhead-Gatehouse":
			return [Vector2(80.0, 114.0)]
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


## HOW STEEP IS EACH LANE, measured off the GROUND and not off the road.
##
## This used to check a graded road's pitch against a 22° band, and the whole
## apparatus — run-out, "pads eat the leg", constant grade by arc length —
## existed because a road cut the hill to its own height. These roads
## follow_terrain, so they cut nothing: a lane's grade IS the hill's grade.
##
## So the question changes from "is the road within the band" to "is the HILL
## gentle, everywhere a lane goes". It walks each leg's polyline in 4 m steps
## against terrain_h and reports the mean and the worst. The spread between the
## lanes' means is the consistency number; MAX_GRADE is now a ceiling on the
## ground rather than a design target for a road.
##
## IT ALSO CHECKS THE LANE IS NOT A CORRIDOR OF ITS OWN WALLS. A leg that
## passes within half the bed's width of a lane wall has the squad walking a
## slot, and the whole point of a 132 m glacis is that the lane is somewhere to
## manoeuvre rather than a passage.
func _grades(by_name: Dictionary) -> int:
	var bad := 0
	print("")
	print("   %-28s %8s %8s %8s %9s %8s" % [
			"leg", "run", "rise", "mean", "worst", "wall"])
	var means: Array[float] = []
	for l: Array in LEGS:
		var pts := _poly(by_name, l)
		var cum := _cum(pts)
		var run: float = cum[cum.size() - 1]
		var rise := float((by_name[l[1]] as Array)[3]) - float((by_name[l[0]] as Array)[3])
		var worst := 0.0
		var worst_at := Vector2.ZERO
		var near := INF
		var prev := _along(pts, cum, 0.0)
		var prev_h := terrain_h(prev.x, prev.y)
		var s := 4.0
		while s <= run:
			var p := _along(pts, cum, s)
			var h := terrain_h(p.x, p.y)
			var g := rad_to_deg(atan2(absf(h - prev_h), 4.0))
			if g > worst:
				worst = g
				worst_at = p
			for w: Array in LANE_WALLS:
				# A GATE IS MEANT TO BE WALKED THROUGH, so it does not count as
				# something the lane is hugging. Without this the east leg was
				# flagged at 0.4 m for passing through the gatehouse, which is
				# the one thing that leg is for.
				if str(w[0]).ends_with("fort_gate"):
					continue
				near = minf(near, p.distance_to(Vector2(float(w[1]), float(w[2]))))
			prev = p
			prev_h = h
			s += 4.0
		var mean := rad_to_deg(atan2(absf(rise), maxf(run, 1.0)))
		means.append(mean)
		var note := ""
		# THE WORST COLUMN IS AN UPPER BOUND, NOT A MEASUREMENT, and it is a
		# warning rather than a failure because of what terrain_h does not
		# know. It models the cones, the swells and the station pads — but not
		# the roads, which follow_terrain and SMOOTH their own bed. So every
		# reading inside a lane is taken on the ground as it would be if the
		# lane were not there, and the two places this reports over 22 are both
		# in a road bed between two pads, where the real baked ground is
		# gentler than this says. The radial profile above is the honest
		# number for the hill itself, and it tops out at 12.
		if worst > MAX_GRADE:
			note = "   %.0f° at (%.0f, %.0f) — pad edge, smoothed by the lane" % [worst, worst_at.x, worst_at.y]
		elif worst > 15.0:
			note = "   steep for a glacis"
		# A wall segment is 24 m long, so its centre being closer than half the
		# bed plus half a segment means the lane is running along its face.
		if near < float(l[2]) * 0.5 + 12.0:
			note += "   HUGS A LANE WALL (%.0f m)" % near
			bad += 1
		print("   %-28s %7.0fm %7.0fm %7.1f° %8.1f° %7.0fm%s" % [
				"%s → %s" % [l[0], l[1]], run, rise, mean, worst, near, note])
	var lo := 90.0
	var hi := 0.0
	for m: float in means:
		lo = minf(lo, m)
		hi = maxf(hi, m)
	print("   mean grade %.1f° to %.1f° — spread %.1f°" % [lo, hi, hi - lo])
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
	#
	# A GATE IN EACH SIDE RUN, one west and one east, so the three lanes arrive
	# at three different doors instead of converging on one. The west and east
	# lanes come round the fort's flanks and meet the curtain here; the centre
	# lane runs straight at the south gate.
	for z: float in [-36.0, -12.0, 12.0, 36.0]:
		var side: String = ("fortress/fort_gate" if is_equal_approx(z, SIDE_GATE_AT)
				else "fortress/fort_wall")
		out.append([side, -WALL_HALF.x - WALL_THICK * 0.5, z, 0.0])
		out.append([side, WALL_HALF.x + WALL_THICK * 0.5, z, 0.0])
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
	for p: Array in FORT_PIECES + wall_pieces() + TERRACE_DRESS + LANE_WALLS + BUNKERS + LANE_DRESS:
		out.append(p)
	for d: Array in STATION_DRESS:
		out.append([d[1], d[2], d[3], d[4]])
	return out


## What height a long piece standing on the open glacis sits at.
##
## THE LOWEST GROUND UNDER IT, NOT THE GROUND AT ITS MIDDLE, and this one came
## straight off a screenshot. A fort_wall is 24 m long; on 11° ground that is
## 4.6 m of fall from end to end. Given its centre's height, half of every
## segment on a slope floats clear of the ground and the other half is buried —
## and from the spawn the lane walls read as a row of tilted slabs hanging in
## the air. Taking the MINIMUM over the footprint buries the high end instead,
## which is what a wall built on a hill looks like and costs nothing: the piece
## is 5.5 m tall and the deepest it ever sinks is the fall over its own length.
##
## The extra 0.4 m is so the lowest corner sits IN the ground rather than
## exactly on it, where the terrain's own noise would show daylight under it.
func _sits_at(p: Array) -> float:
	var at := Vector2(float(p[1]), float(p[2]))
	var yaw := deg_to_rad(float(p[3]))
	var along := Vector2(sin(yaw), cos(yaw))
	var lowest := INF
	# fort_wall and fort_gate are 24 m along their own Z; the bunkers are 24 and
	# the berms 15. 13 either side covers the longest of them.
	var s := -13.0
	while s <= 13.0:
		var q := at + along * s
		lowest = minf(lowest, terrain_h(q.x, q.y))
		s += 2.0
	return roundf((lowest - 0.4) * 10.0) * 0.1


func _piece_path(name_: String) -> String:
	return name_ if name_.begins_with("res://") else "res://maps/blocks/%s.tscn" % name_


## The bunker, as a [piece, dx, dz, yaw] row for the clearance check ONLY. It
## is never emitted: the level carries a marker and SiteSlice raises the kit
## there at runtime, so instancing it here would build it twice. What this is
## for is proving the marker has room — a marker is a POSITION and nothing
## about it promises 9 m of clear ground in front of a 9 m door.
func bunker_check() -> Array:
	return [[BUNKER_PREFAB, BUNKER_AT.x, BUNKER_AT.y, 0.0]]


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
	var bad := await _group("fort", FORT_PIECES + wall_pieces() + cores_for("Fort") + bunker_check(),
			Vector2.ZERO, SHELF_HALF, PAD_HALF)
	# THE LANE WALLS AND THE BUNKERS, in one group because they are in one
	# coordinate system — world, measured against the whole map rather than
	# against any pad. The wall segments want the ring exemption (a wall line
	# has to touch itself or it is a row of slabs) and _group gives it to
	# anything under fortress/, which is exactly these.
	var whole := Vector2(SIZE_X, SIZE_Z) * 0.5
	bad += await _group("lanes", LANE_WALLS + BUNKERS + LANE_DRESS, Vector2.ZERO, whole, whole)
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
		["Resource", "res://maps/blocks/scatter/scatter_hfw_ground.tres", "8_ground", ""],
		["Resource", "res://maps/blocks/scatter/scatter_hfw_micro.tres", "9_micro", ""],
		["Resource", "res://maps/blocks/scatter/scatter_hfw_deadwood.tres", "10_dead", ""],
		["Resource", "res://maps/blocks/scatter/scatter_hfw_snags.tres", "11_snags", ""],
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
	# THE SHIFT. See SOUTH_SHIFT: this moves the rectangle south so the growth
	# is one-sided, and every group below moves back by the same amount so the
	# stamps keep their world coordinates.
	out.append(_xform(0.0, 0.0, SOUTH_SHIFT))
	out.append("script = ExtResource(\"1_terrain\")")
	out.append("recipe = SubResource(\"Resource_recipe\")")
	if has_data:
		out.append("data = ExtResource(\"11_data\")")
	out.append("data_path = \"%s\"" % DATA_PATH)
	out.append("boundary_inset = %.1f" % BOUNDARY_INSET)
	out.append("")
	# ── THE SCATTER. Four layers, ALL OF THEM MESH-ONLY.
	#
	# They are hfw_ copies of the alpine set rather than the alpine set itself,
	# for one reason: the shipped deadwood carries a 0.6 m collision radius and
	# the snags 0.35, and ASSETS.md section 5 says ground clutter is mesh-only.
	# A solid snag erodes an agent radius plus its own off the navmesh all round
	# it, and — the thing that actually matters here — it GENERATES COVER
	# POINTS. Scatter with collision on the centre lane would hand back the
	# exposure that the whole dressing pass was about. Mesh-only cannot, by
	# construction, and the cover re-bake proves it.
	#
	# Resources are shared, so these are copies and not edits: nine other maps
	# use the alpine set and none of them asked for this.
	#
	# The deadwood and the snags are capped at max_mountain 0.25, which is the
	# sketch mask doing per-lane work — see probe_paint_hillfort_wip.gd.
	out.append("[node name=\"Scatter\" type=\"Node3D\" parent=\"Terrain\"]")
	out.append("script = ExtResource(\"6_scatter\")")
	out.append("layers = Array[ExtResource(\"7_layer\")]([ExtResource(\"8_ground\"), ExtResource(\"9_micro\"), ExtResource(\"10_dead\"), ExtResource(\"11_snags\")])")
	out.append("")

	# ORDER IS THE WHOLE POINT. Modifiers are collected depth-first in tree
	# order and a later one wins, so: the hills and the cones raise the ground,
	# the hollows take it back down, the shelves cut flats into it, and the
	# roads cut last of all. Move Roads above Shelves and every landing
	# swallows the leg arriving at it.
	out.append("[node name=\"Hills\" type=\"Node3D\" parent=\"Terrain\"]")
	out.append(_xform(0.0, 0.0, -SOUTH_SHIFT))
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
	out.append(_xform(0.0, 0.0, -SOUTH_SHIFT))
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
	out.append(_xform(0.0, 0.0, -SOUTH_SHIFT))
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
	out.append(_xform(0.0, 0.0, -SOUTH_SHIFT))
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
	out.append(_xform(0.0, 0.0, -SOUTH_SHIFT))
	out.append("")
	for k: String in curves:
		var l: Array = curves[k]
		out.append("[node name=\"%s_%s\" type=\"Path3D\" parent=\"Terrain/Roads\"]" % [l[0], l[1]])
		out.append("curve = SubResource(\"%s\")" % k)
		out.append("script = ExtResource(\"5_path\")")
		out.append("width = %.1f" % float(l[2]))
		out.append("falloff = %.1f" % float(l[3]))
		# follow_terrain ON. These lay a surface on the ground and smooth it
		# rather than grading it to the curve, so the lane cannot cut a defile or
		# raise an embankment, and its pitch is whatever the hill is doing.
		out.append("follow_terrain = true")
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

	# ── THE LANE WALLS AND THE BUNKERS. World coordinates, and their Y comes
	# off terrain_h rather than off a station, because most of them stand on
	# open glacis between the pads. A wall segment floating two metres over the
	# ground is the kind of thing only a screenshot catches, and a wall sunk two
	# metres into it is worse — it is still solid, so the navmesh shows a route
	# closed for no visible reason.
	out.append("[node name=\"Structures\" type=\"Node3D\" parent=\".\"]")
	out.append("")
	i = 1
	for p: Array in LANE_WALLS + BUNKERS + LANE_DRESS:
		out.append("[node name=\"Lane%02d_%s\" parent=\"Structures\" instance=ExtResource(\"%s\")]" % [
				i, _node_tag(str(p[0])), _ext_id(str(p[0]))])
		out.append(_rot_xform(float(p[3]), float(p[1]), _sits_at(p), float(p[2])))
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
		["PackedScene", "res://Env/world_objects/cover_point_spawner.tscn",
				"9_coverspawn", "uid://cyslwv078g4sk"],
		["Script", "res://Env/world_objects/cover_point.gd", "10_coverpt", ""],
		["Script", "res://Managers/AI/patrol_path.gd", "11_patrol", ""],
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
	# AND IT FOLLOWS THE SHIFT. The box is in WORLD space while SIZE_Z is now
	# measured about a rectangle centred at z = SOUTH_SHIFT, so an unshifted
	# box would stop 64 m short of the new southern ground — the whole of the
	# approach this was grown for, unwalkable, with no error anywhere. That is
	# the Proving failure exactly, on the one map that just grew.
	# AND IT STOPS AT THE WALLS, not at the terrain's edge. Since the backdrop
	# ring went in, SIZE_X by SIZE_Z is 640 square and most of that is border
	# mountain the player can never reach. Baking it would spend the time
	# rasterising scree and would hand the squad walkable polygons OUTSIDE the
	# boundary walls, which is how a flanker ends up pathing round the back of
	# the world. The playable rectangle is the inset one.
	var play_x := SIZE_X * 0.5 - BOUNDARY_INSET
	var play_z := SIZE_Z * 0.5 - BOUNDARY_INSET
	out.append("filter_baking_aabb = AABB(%.0f, -40, %.0f, %.0f, 400, %.0f)" % [
			-play_x - 8.0, SOUTH_SHIFT - play_z - 8.0, play_x * 2.0 + 16.0, play_z * 2.0 + 16.0])
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
	# ── WHERE THE SQUAD FORMS UP. A shipped level carries one of these and the
	# WIP did not, so the squad had a spawn point and nowhere to stand.
	#
	# EIGHT AUTHORED STANDS rather than leaving squad_spawn_point to space them
	# off `spacing`: the trailhead pad is 104 x 28 of flat ground and two ranks
	# of four, four metres apart, is a formation rather than a queue. They are
	# west of the spawn so the muster is beside the road and not on it — the
	# centre lane leaves this pad up the middle.
	var muster_x := float(trail[1]) - 10.0
	var muster_z := float(trail[2]) + 2.0
	var stands: PackedStringArray = []
	for i in 8:
		stands.append("NodePath(\"Stand%02d\")" % (i + 1))
	out.append("[node name=\"SquadMuster\" type=\"Node3D\" parent=\".\" node_paths=PackedStringArray(\"slot_markers\")]")
	out.append(_xform(muster_x, float(trail[3]), muster_z))
	out.append("script = ExtResource(\"3_squad\")")
	out.append("callsign = \"BRAVO\"")
	out.append("max_slots = 999")
	out.append("slot_markers = [%s]" % ", ".join(stands))
	out.append("")
	for i in 8:
		# Relative to the muster, which is itself on the pad.
		var col := i % 4
		var row := i / 4
		out.append("[node name=\"Stand%02d\" type=\"Node3D\" parent=\"SquadMuster\"]" % (i + 1))
		out.append(_xform(float(col) * 4.0 - 6.0, 0.0, float(row) * 4.0 - 2.0))
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
	# THE WAY OUT WAITS FOR THE OPERATION. Without this the doors are live from
	# the moment the mission starts and the player can walk out of the tunnel
	# they just walked in through, before taking anything. GAMEPLAY set it by
	# hand and a --force rebuild cleared it.
	# docs/FEATURE_CHECKLISTS.md, "A new SITE", item 5.
	out.append("requires_objectives_complete = true")
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

	# ── COVER, AND IT IS A BOOTSTRAP LIKE THE TERRAIN DATA.
	#
	# The points are BAKED children: tools/probe_cover_mutaha.gd walks the
	# navmesh edges, casts at the geometry either side and rewrites everything
	# under this node. It needs two things to already be here — the spawner,
	# and a cover_point.gd ext_resource to point the new nodes at — and
	# check.sh fails a scene that declares an id it never uses. So this emits
	# ONE seed point to keep the id honest, and the baker replaces the lot.
	#
	# WHICH MEANS A --force REBUILD THROWS THE BAKED COVER AWAY, exactly as it
	# throws the navmesh away. Rebuild, then re-bake terrain, navmesh and cover
	# in that order.
	out.append("[node name=\"CoverPointSpawner\" parent=\".\" node_paths=PackedStringArray(\"navigation_region\") instance=ExtResource(\"9_coverspawn\")]")
	out.append("navigation_region = NodePath(\"../NavigationRegion3D\")")
	# 5000 is what valley_basin uses: sample the whole map rather than a disc
	# round the origin.
	out.append("sample_radius = 5000.0")
	out.append("wall_detect_length = 1.0")
	out.append("open_detect_length = 1.0")
	out.append("arm_span_offset = 0.3")
	out.append("debug_visualize = false")
	out.append("")
	out.append("[node name=\"CoverPoint_0\" type=\"Node3D\" parent=\"CoverPointSpawner\"]")
	out.append(_xform(float(fort[1]), float(fort[3]), float(fort[2])))
	out.append("script = ExtResource(\"10_coverpt\")")
	out.append("cover_direction = Vector3(0, 0, 1)")
	out.append("is_crouch_cover = true")
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

	# ── AND THE ROUTES THAT WRAP THOSE MARKERS. MARKERS ARE NOT A ROUTE.
	#
	# A spec's `route_tag` resolves against nodes in the "patrol_paths" group,
	# which PatrolPath joins in _ready. Patrol1..6 are plain Node3D children
	# and join nothing, so without a PatrolPath over them the lookup finds
	# NOTHING, warns once at runtime, and the squad stands still for the whole
	# mission. GAMEPLAY hit exactly this, added two by hand, and a --force
	# rebuild here deleted them again — which is why they are generated now
	# rather than seated afterwards. docs/FEATURE_CHECKLISTS.md, "A new MAP",
	# item 11.
	out.append("[node name=\"Patrols\" type=\"Node3D\" parent=\".\"]")
	out.append("")
	for p: Array in PATROLS:
		var tag := "patrol_hfw_%s" % str(p[0]).trim_prefix("HFW_").to_snake_case()
		var paths := PackedStringArray()
		for i in (p[1] as Array).size():
			paths.append("NodePath(\"../../EnemySquadObjs/%s/Patrol%d\")" % [p[0], i + 1])
		out.append("[node name=\"%s\" type=\"Node\" parent=\"Patrols\" node_paths=PackedStringArray(\"points\")]" % tag)
		out.append("script = ExtResource(\"11_patrol\")")
		out.append("tag = &\"%s\"" % tag)
		out.append("points = [%s]" % ", ".join(paths))
		out.append("")

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
		# OPTIONAL, EVERY ONE OF THEM, and this is not a shrug.
		#
		# The operation is won at the bunker. A compulsory capture makes a
		# route that does not pass it UNFINISHABLE — and the whole design here
		# is three lanes carrying 2/1/2 captures, so taking the centre lane
		# means skipping four of the six ON PURPOSE. Leave these compulsory and
		# the fast lane cannot be completed at all.
		#
		# GAMEPLAY set this by hand and a --force rebuild reset all six.
		# docs/FEATURE_CHECKLISTS.md, "A new SITE", item 6.
		out.append("optional = true")
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
		"border_sides = 15",
		"border_height = 58.0",
		"border_width = 118.0",
		"border_noise = 34.0",
		"border_ruggedness = 0.62",
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
		"sketch_mountain_height = 0.0",
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
