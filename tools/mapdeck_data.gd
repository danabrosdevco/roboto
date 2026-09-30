extends RefCounted

# ─────────────────────────────────────────────
# MAP DECK DATA — the map ideas, one dictionary each. tools/mapdeck.gd builds
# and photographs them.
#
# FIELDS
#   id      short name, used for the filenames
#   name    what it is called
#   hook    the one line that says why it might be fun
#   shape   the tactical shape, which is the thing actually being compared
#   px      sketch size in pixels; at 8 m a pixel, 176 x 64 px is 1408 x 512 m,
#           the valley mission's own footprint
#   paint   sketch operations, in PIXELS, top of the image is north
#   recipe  overrides on the flat default in mapdeck.gd
#   dress   block placement, in METRES from the middle of the map
#   cams    eye-level cameras: [from_x, from_z, look_x, look_z, fov]
#
# TWO FRAMES, and mixing them up puts a building in the sea: PAINT IS PIXELS
# from the top-left, DRESS IS METRES from the middle. m(px) converts.
#
# THE GROUND UNDER ANYTHING THE SQUAD USES IS FLAT. Relief is backdrop and
# gating only — white mountains round the edge, water to force a crossing.
# Height where it matters comes from the blocks, which have their own ramps.
# ─────────────────────────────────────────────

const LONG := Vector2i(176, 64)      ## 1408 x 512 m — the valley footprint
const WIDE := Vector2i(128, 96)      ## 1024 x 768 m
const SQUARE := Vector2i(112, 112)   ## 896 x 896 m
const TALL := Vector2i(64, 176)      ## 512 x 1408 m — a north-south map
const MPP := 8.0


## Pixel -> metre, on a sketch `px` wide or tall.
static func m(v: float, span: int) -> float:
	return (v - span * 0.5) * MPP


## `n` evenly spaced parallel rows of `piece` running east-west.
static func rows(piece: String, x0: float, x1: float, z0: float, n: int, step: float,
		gap := 0.0) -> Array:
	var out: Array = []
	for i in n:
		out.append(["row", piece, x0, z0 + i * step, x1, z0 + i * step, gap])
	return out


## `n` evenly spaced parallel rows running north-south.
static func cols(piece: String, z0: float, z1: float, x0: float, n: int, step: float,
		gap := 0.0) -> Array:
	var out: Array = []
	for i in n:
		out.append(["row", piece, x0 + i * step, z0, x0 + i * step, z1, gap])
	return out


## Several pieces taking turns along one line, so a street is not one building
## repeated. Each gets its own stretch.
static func mix(pieces: Array, x0: float, z0: float, x1: float, z1: float, gap := 10.0) -> Array:
	var out: Array = []
	var n := pieces.size()
	for i in n:
		var a := float(i) / n
		var b := float(i + 1) / n
		out.append(["row", pieces[i], lerpf(x0, x1, a), lerpf(z0, z1, a),
				lerpf(x0, x1, b), lerpf(z0, z1, b), gap])
	return out


## A block of town: `pieces` laid as bands across the rectangle.
static func town(pieces: Array, x0: float, z0: float, x1: float, z1: float, bands := 3,
		gap := 12.0) -> Array:
	var out: Array = []
	for i in bands:
		var z := lerpf(z0, z1, (i + 0.5) / bands)
		# Every other band shifted half a building along, so a town is streets
		# and not a spreadsheet.
		var shift: float = 26.0 if i % 2 == 1 else 0.0
		out.append_array(mix(pieces, x0 + shift, z, x1 + shift, z, gap))
	return out


## Cover strewn along a line, the three-height rule the proving ground uses:
## something to shoot over, something to hide behind, something to break the
## sight line. A lane with one height of cover is a lane with no decisions.
static func cover(x0: float, z0: float, x1: float, z1: float, gap := 26.0) -> Array:
	return mix(["props/prop_jersey_barrier", "fortifications/fort_t_walls",
			"props/prop_concrete_blocks", "props/prop_sandbag_wall",
			"fortifications/fort_hesco_wall", "props/prop_rubble_pile"], x0, z0, x1, z1, gap)


## Common backdrops, so the fifty share a language.
const HILLS := ["rect", 0, 0, 176, 5, "W"]


## A trench line running north-south at `x`, TRAVERSED: stepped sideways every
## `step` metres so no length of it can be shot down end to end. Real trenches
## are cut this way for exactly that reason, and it does the same job here —
## it turns a 260 m ditch into a chain of 30 m rooms.
static func traverse(x: float, z0: float, z1: float, step := 30.0, amp := 5.0) -> Array:
	var out: Array = []
	var n := maxi(int(absf(z1 - z0) / step), 2)
	for i in n + 1:
		var z := lerpf(z0, z1, float(i) / n)
		out.append(Vector2(x + (amp if i % 2 == 0 else -amp), z))
		if i < n:
			out.append(Vector2(x + (amp if i % 2 == 0 else -amp), z + (z1 - z0) / n * 0.6))
			out.append(Vector2(x + (-amp if i % 2 == 0 else amp), z + (z1 - z0) / n * 0.6))
	return out


## A straight run east-west, for communication trenches and saps.
static func run(z: float, x0: float, x1: float) -> Array:
	return [Vector2(x0, z), Vector2(x1, z)]


static func maps() -> Array:
	var out: Array = []

	# ═══ THE SALIENT ═════════════════════════════════════════════════════════
	# Trench warfare in a valley. Three lines each side, a traversed front, a
	# mine crater in the middle of no-man's-land and a ruined village behind
	# the enemy gun line.
	#
	# THE TRENCHES ARE CUT, NOT PLACED. feature_trench_revetment is a LINING:
	# its plank walls reach 2 m below its own origin and its sandbag parapet
	# 0.45 m above, so on flat ground it reads as a kerb and nothing else. Each
	# line here is a TerrainPath TRENCH first and revetment second.
	#
	# 2.2 m deep on a 3.5 m falloff is about 32 degrees — steep enough to be
	# cover, shallow enough that the baker walks it. A trench the squad cannot
	# climb out of is the crater bug in a longer shape, and that one has been
	# built here before.
	var fire_lines: Array = []
	var line_x := {"reserve": -430.0, "support": -300.0, "front": -170.0,
			"ef": 60.0, "es": 190.0, "eg": 330.0}
	for key: String in line_x:
		fire_lines.append(["trench", 7.0, 2.2, 3.5, traverse(line_x[key], -215.0, 215.0)])
	# Communication trenches back from the friendly front, and the enemy's own.
	for z: float in [-130.0, 0.0, 130.0]:
		fire_lines.append(["trench", 6.0, 2.0, 3.5, run(z, -430.0, -170.0)])
	for z: float in [-90.0, 90.0]:
		fire_lines.append(["trench", 6.0, 2.0, 3.5, run(z, 60.0, 330.0)])
	# Saps pushed out into no-man's-land: the only cover on the way over.
	for z: float in [-70.0, 70.0]:
		fire_lines.append(["trench", 5.0, 1.8, 3.0, run(z, -170.0, -95.0)])

	out.append({
		"id": "the_salient", "name": "The Salient",
		"hook": "Three lines each side of 230 m of shelled ground, and one sunken road across it.",
		"shape": "attrition frontage — parallel lines, one covered approach",
		"px": Vector2i(128, 64),
		"paint": [["rect", 0, 0, 128, 64, "G"],
			# The valley: rough shoulders rising to crests north and south.
			["rect", 0, 0, 128, 9, "Y"], ["rect", 0, 55, 128, 64, "Y"],
			["rect", 0, 0, 128, 4, "W"], ["rect", 0, 60, 128, 64, "W"],
			# No-man's-land, and the ground behind each front line that the
			# other side's guns have been working on.
			["rect", 43, 8, 72, 56, "R"], ["rect", 30, 12, 43, 52, "R"],
			["rect", 72, 12, 86, 52, "R"],
			# Flooded shell holes. Two metres of water is not a swim, it is a
			# reason to go round.
			["oval", 50, 22, 4, 3, "B"], ["oval", 60, 40, 5, 3, "B"],
			["oval", 67, 18, 3, 3, "B"],
			# The sunken road: graded flat with a bank either side, straight
			# across the middle of the worst of it.
			["line", 0, 27, 128, 27, 2.0, "M"],
			# A lateral road behind each line, and the village.
			["line", 0, 50, 40, 50, 1.0, "M"], ["line", 92, 14, 128, 14, 1.0, "M"],
			["rect", 106, 20, 124, 44, "U"]],
		"recipe": {"cell_size": 1.5, "shelling_per_hectare": 70.0,
			"crater_radius_min": 3.0, "crater_radius_max": 13.0,
			# SHALLOW ON PURPOSE. A deep crater with a heaved rim is a hole the
			# squad walks into and cannot leave, which has happened on this
			# project and had to be dug back out again.
			"crater_depth": 0.28, "crater_rim": 0.07,
			"rough_height": 7.0, "sketch_mountain_height": 42.0,
			"water_depth": 2.0, "water_bank": 6.0, "road_width": 7.0,
			"road_falloff": 6.0, "hills_height": 3.0, "smooth_passes": 1},
		"paths": fire_lines,
		"dress": []
			# Revetment in every cut, following the traverse.
			+ [["along", "features/feature_trench_revetment", traverse(-430.0, -215.0, 215.0), 0.0],
				["along", "features/feature_trench_revetment", traverse(-300.0, -215.0, 215.0), 0.0],
				["along", "features/feature_trench_revetment", traverse(-170.0, -215.0, 215.0), 0.0],
				["along", "features/feature_trench_revetment", traverse(60.0, -215.0, 215.0), 0.0],
				["along", "features/feature_trench_revetment", traverse(190.0, -215.0, 215.0), 0.0],
				["along", "features/feature_trench_revetment", run(0.0, -430.0, -170.0), 0.0],
				["along", "features/feature_trench_revetment", run(-130.0, -430.0, -170.0), 0.0],
				["along", "features/feature_trench_revetment", run(130.0, -430.0, -170.0), 0.0],
				["along", "features/feature_trench_revetment", run(-90.0, 60.0, 330.0), 0.0],
				["along", "features/feature_trench_revetment", run(90.0, 60.0, 330.0), 0.0]]
			# Wire: a belt in front of each front line, which is what makes the
			# 230 m between them a problem rather than a walk.
			+ [["row", "fortifications/fort_razor_wire", -140.0, -215.0, -140.0, 215.0, 4.0],
				["row", "fortifications/fort_razor_wire", -126.0, -215.0, -126.0, 215.0, 4.0],
				["row", "fortifications/fort_razor_wire", 26.0, -215.0, 26.0, 215.0, 4.0],
				["row", "fortifications/fort_razor_wire", 12.0, -215.0, 12.0, 215.0, 4.0],
				["row", "fortifications/fort_dragon_teeth", 40.0, -200.0, 40.0, 200.0, 14.0],
				["row", "features/feature_berm", -152.0, -200.0, -152.0, 200.0, 12.0],
				["row", "features/feature_berm", 44.0, -200.0, 44.0, 200.0, 12.0]]
			# Strongpoints on the line, guns behind it.
			+ [["at", "features/feature_pillbox", 64.0, -120.0, 270.0],
				["at", "features/feature_pillbox", 64.0, 0.0, 270.0],
				["at", "features/feature_pillbox", 64.0, 120.0, 270.0],
				["at", "fortifications/fort_command_bunker", 200.0, -40.0, 0.0],
				["at", "fortifications/fort_command_bunker", 200.0, 40.0, 0.0],
				["at", "fortifications/fort_command_bunker", -310.0, 0.0, 0.0],
				["row", "fortifications/fort_mortar_pit", 330.0, -160.0, 330.0, 160.0, 60.0],
				["row", "fortifications/fort_gun_emplacement", 300.0, -120.0, 300.0, 120.0, 90.0],
				["row", "fortifications/fort_ammo_dump", -420.0, -120.0, -420.0, 120.0, 70.0],
				["row", "props/prop_sandbag_nest", -160.0, -190.0, -160.0, 190.0, 40.0],
				["row", "props/prop_sandbag_nest", 70.0, -190.0, 70.0, 190.0, 40.0]]
			# No-man's-land: a mine crater, wrecks, and the stumps of a wood
			# that used to be here.
			+ [["at", "features/feature_crater_rim", -60.0, 10.0, 0.0],
				["at", "features/feature_crater_rim", -20.0, -110.0, 40.0],
				["row", "props/prop_tank_trap", -100.0, -200.0, -100.0, 200.0, 26.0],
				["row", "props/prop_robot_wreck", -80.0, -160.0, -80.0, 160.0, 44.0],
				["row", "props/prop_rubble_pile", -40.0, -180.0, -40.0, 180.0, 50.0],
				["row", "alpine/alpine_pine_skeleton", -120.0, -210.0, 20.0, -210.0, 26.0],
				["row", "alpine/alpine_snag_broken", -120.0, 210.0, 20.0, 210.0, 26.0],
				["row", "alpine/alpine_stump_burnt", -150.0, -60.0, 40.0, -60.0, 30.0],
				["row", "alpine/alpine_stump_burnt", -150.0, 100.0, 40.0, 100.0, 30.0],
				["row", "alpine/alpine_stump_burnt", -150.0, -150.0, 40.0, -150.0, 34.0],
				["row", "alpine/alpine_stump_burnt", -150.0, 170.0, 40.0, 170.0, 34.0],
				["row", "props/prop_dirt_mound", -130.0, -190.0, -130.0, 190.0, 22.0],
				["row", "props/prop_dirt_mound", 0.0, -190.0, 0.0, 190.0, 22.0],
				["row", "props/prop_rubble_pile", -110.0, -170.0, 20.0, -170.0, 30.0],
				["row", "props/prop_rubble_pile", -110.0, 60.0, 20.0, 60.0, 30.0],
				["row", "props/prop_car_wreck", -120.0, 140.0, 10.0, 140.0, 40.0],
				["row", "props/prop_tank_trap", -60.0, -200.0, -60.0, 200.0, 30.0],
				["row", "props/prop_robot_wreck", -30.0, -120.0, -30.0, 120.0, 38.0]]
			# The village behind their gun line: the reason to come this far.
			+ [["at", "landmarks/landmark_clock_tower", 420.0, -20.0, 0.0]]
			+ town(["estates/estate_collapsed_corner", "estates/estate_frame_shell",
				"estates/estate_slab_broken"], 370.0, -180.0, 500.0, 180.0, 3, 14.0),
		"scatter": ["scatter_debris", "scatter_alpine_snags", "scatter_micro_terrain"],
		# Behind the parapet, out in it, back from their side, and one straight
		# down a communication trench — the camera sits on the cut floor there,
		# which is the shot that says whether the trenches are trenches.
		"cams": [[-212.0, 45.0, 60.0, 20.0, 62.0],
			[-95.0, 105.0, 60.0, 55.0, 64.0],
			[255.0, 135.0, -260.0, 60.0, 60.0],
			[-390.0, 130.0, -180.0, 130.0, 60.0]],
	})

	# ═══ CROSSINGS ═══════════════════════════════════════════════════════════
	# Water that the squad cannot wade, so a bridge is a decision and not
	# scenery. Riverbeds are never navigable here — that is the whole point of
	# painting one.

	# ── LOCK LADDER ──────────────────────────────────────────────────────────
	out.append({
		"id": "lock_ladder", "name": "Lock Ladder",
		"hook": "Three staircase locks, and the gates are the only dry way across.",
		"shape": "sequential chokes on one axis",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "G"],
			["rect", 0, 26, 176, 38, "B"],
			["rect", 0, 0, 176, 4, "W"], ["rect", 0, 60, 176, 64, "W"],
			["line", 0, 20, 176, 20, 1.0, "M"], ["line", 0, 45, 176, 45, 1.0, "M"],
			["line", 44, 20, 44, 45, 1.0, "M"], ["line", 88, 20, 88, 45, 1.0, "M"],
			["line", 132, 20, 132, 45, 1.0, "M"],
			["rect", 30, 8, 58, 18, "U"], ["rect", 118, 46, 150, 58, "U"]],
		"recipe": {"water_depth": 9.0, "water_bank": 14.0},
		"dress": mix(["industrial/industrial_lock_dam"], -352.0, 0.0, -352.0, 0.0)
			+ [["at", "industrial/industrial_lock_dam", 0.0, 0.0, 0.0],
				["at", "industrial/industrial_lock_dam", 352.0, 0.0, 0.0],
				["at", "industrial/industrial_gatehouse", -352.0, -80.0, 0.0],
				["at", "industrial/industrial_gatehouse", 352.0, 80.0, 0.0],
				["at", "landmarks/landmark_clock_tower", -180.0, -180.0, 0.0]]
			+ town(["estates/estate_courtyard_block", "estates/estate_u_block",
				"estates/estate_podium_row"], -400.0, -190.0, -140.0, -120.0, 2)
			+ town(["estates/estate_gallery_block", "estates/estate_slab_dogleg"],
				240.0, 130.0, 600.0, 190.0, 2)
			+ cover(-620.0, -110.0, 620.0, -110.0, 40.0)
			+ cover(-620.0, 110.0, 620.0, 110.0, 40.0),
		"scatter": ["scatter_debris"],
		"cams": [[-352.0, -90.0, -352.0, 90.0, 58.0], [-620.0, -60.0, 400.0, -30.0, 64.0]],
	})

	# ── BRAIDED DELTA ────────────────────────────────────────────────────────
	out.append({
		"id": "braided_delta", "name": "Braided Delta",
		"hook": "Four channels, four islands, eight little crossings — flanks everywhere.",
		"shape": "many small chokes, high connectivity",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"],
			["path", [Vector2(0, 46), Vector2(30, 40), Vector2(60, 26), Vector2(128, 20)], 5.0, "B"],
			["path", [Vector2(0, 50), Vector2(34, 52), Vector2(72, 46), Vector2(128, 42)], 5.0, "B"],
			["path", [Vector2(0, 54), Vector2(36, 64), Vector2(76, 66), Vector2(128, 64)], 5.0, "B"],
			["path", [Vector2(0, 58), Vector2(30, 78), Vector2(80, 84), Vector2(128, 86)], 5.0, "B"],
			["line", 24, 0, 24, 96, 1.0, "M"], ["line", 64, 0, 64, 96, 1.0, "M"],
			["line", 100, 0, 100, 96, 1.0, "M"], ["line", 0, 10, 128, 10, 1.0, "M"],
			["rect", 0, 0, 128, 4, "Y"]],
		"recipe": {"water_depth": 7.0, "water_bank": 16.0},
		"dress": town(["estates/estate_courtyard_wing", "estates/estate_podium_row"],
				-380.0, -220.0, 380.0, -150.0, 2)
			+ cover(-420.0, 30.0, 420.0, 30.0, 34.0)
			+ cover(-420.0, 130.0, 420.0, 130.0, 34.0)
			+ cover(-420.0, 230.0, 420.0, 230.0, 34.0)
			+ [["at", "landmarks/landmark_clock_tower", -260.0, -200.0, 0.0],
				["at", "features/feature_watchtower", 120.0, 60.0, 0.0],
				["at", "features/feature_watchtower", -140.0, 170.0, 0.0],
				["row", "fortifications/fort_hesco_wall", 220.0, 250.0, 380.0, 250.0, 6.0]],
		"scatter": ["scatter_debris", "scatter_boulders"],
		"cams": [[-190.0, 10.0, 200.0, 180.0, 64.0], [130.0, -180.0, 130.0, 300.0, 60.0]],
	})

	# ── OXBOW ────────────────────────────────────────────────────────────────
	out.append({
		"id": "oxbow", "name": "Oxbow",
		"hook": "A river loops back on itself; the objective sits on the neck.",
		"shape": "peninsula with one land approach",
		"px": SQUARE,
		"paint": [["rect", 0, 0, 112, 112, "G"],
			["path", [Vector2(0, 74), Vector2(26, 72), Vector2(40, 40), Vector2(56, 18),
				Vector2(76, 30), Vector2(80, 60), Vector2(64, 78), Vector2(112, 84)], 6.0, "B"],
			["rect", 0, 0, 112, 5, "W"], ["rect", 0, 106, 112, 112, "W"],
			["line", 0, 96, 112, 96, 1.0, "M"], ["line", 56, 96, 56, 58, 1.0, "M"],
			["rect", 46, 40, 72, 58, "U"]],
		"recipe": {"water_depth": 8.0, "water_bank": 20.0},
		"dress": [["at", "fortress/fort_keep", 20.0, -60.0, 0.0],
				["at", "fortifications/fort_checkpoint", 20.0, 130.0, 0.0],
				["at", "landmarks/landmark_relay_dish", -40.0, -110.0, 30.0]]
			+ mix(["fortress/fort_wall"], -120.0, -20.0, 160.0, -20.0, 0.0)
			+ cover(-300.0, 200.0, 300.0, 200.0, 30.0)
			+ cover(-300.0, 300.0, 300.0, 300.0, 34.0)
			+ town(["estates/estate_frame_shell", "estates/estate_collapsed_corner"],
				-260.0, 260.0, 260.0, 330.0, 2),
		"scatter": ["scatter_debris", "scatter_alpine_ground"],
		"cams": [[20.0, 260.0, 20.0, -80.0, 58.0], [-180.0, -160.0, 60.0, -40.0, 62.0]],
	})

	# ── THE WEIR ─────────────────────────────────────────────────────────────
	out.append({
		"id": "the_weir", "name": "The Weir",
		"hook": "Still water above, a cut gorge below, one walkable crest between.",
		"shape": "single choke with a height difference either side",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "G"],
			["rect", 0, 0, 88, 64, "B"], ["rect", 0, 0, 176, 6, "W"],
			["rect", 0, 58, 176, 64, "W"], ["rect", 0, 6, 26, 58, "G"],
			["line", 88, 0, 88, 64, 1.5, "M"], ["line", 96, 6, 176, 6, 1.0, "M"],
			["rect", 104, 14, 150, 30, "U"], ["rect", 100, 38, 168, 54, "R"]],
		"recipe": {"water_depth": 12.0, "water_bank": 30.0, "sketch_mountain_height": 48.0},
		"dress": [["at", "industrial/industrial_lock_dam", 0.0, 0.0, 0.0],
				["at", "industrial/industrial_lock_dam", 0.0, 70.0, 0.0],
				["at", "industrial/industrial_lock_dam", 0.0, -70.0, 0.0],
				["at", "industrial/industrial_plant_office", 120.0, -120.0, 0.0],
				["at", "industrial/industrial_substation", 210.0, -130.0, 0.0],
				["at", "industrial/industrial_water_tower", 300.0, -150.0, 0.0]]
			+ town(["estates/estate_courtyard_block", "estates/estate_slab_stepped"],
				180.0, -140.0, 560.0, -80.0, 2)
			+ cover(120.0, 60.0, 620.0, 60.0, 30.0)
			+ cover(120.0, 150.0, 620.0, 150.0, 30.0),
		"scatter": ["scatter_debris", "scatter_boulders"],
		"cams": [[-60.0, 0.0, 400.0, 40.0, 60.0], [300.0, 120.0, 20.0, 0.0, 62.0]],
	})

	# ── FORD TOWN ────────────────────────────────────────────────────────────
	out.append({
		"id": "ford_town", "name": "Ford Town",
		"hook": "The river IS the main street, and both banks are built right up to it.",
		"shape": "linear choke through dense cover",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "U"],
			["path", [Vector2(0, 30), Vector2(50, 34), Vector2(110, 28), Vector2(176, 32)], 4.0, "B"],
			["rect", 0, 0, 176, 4, "Y"], ["rect", 0, 60, 176, 64, "Y"],
			["line", 0, 14, 176, 14, 1.0, "M"], ["line", 0, 48, 176, 48, 1.0, "M"],
			["line", 62, 14, 62, 48, 1.0, "M"], ["line", 114, 14, 114, 48, 1.0, "M"]],
		"recipe": {"water_depth": 4.0, "water_bank": 10.0, "urban_block": Vector2(34.0, 26.0),
			"urban_street": 8.0, "urban_ruin": 0.3},
		"dress": town(["estates/estate_courtyard_block", "estates/estate_u_block",
				"estates/estate_market_hall", "estates/estate_collapsed_corner"],
				-640.0, -180.0, 640.0, -90.0, 2)
			+ town(["estates/estate_gallery_block", "estates/estate_slab_broken",
				"estates/estate_podium_row", "estates/estate_frame_shell"],
				-640.0, 90.0, 640.0, 180.0, 2)
			+ [["at", "landmarks/landmark_clock_tower", -100.0, -140.0, 0.0],
				["at", "estates/estate_point_tower", 260.0, 150.0, 0.0]]
			+ cover(-620.0, -40.0, 620.0, -40.0, 26.0)
			+ cover(-620.0, 46.0, 620.0, 46.0, 26.0),
		"scatter": ["scatter_debris"],
		"cams": [[-200.0, -50.0, 420.0, -20.0, 62.0], [60.0, -170.0, 60.0, 180.0, 60.0]],
	})

	# ── TIDAL CAUSEWAY ───────────────────────────────────────────────────────
	out.append({
		"id": "tidal_causeway", "name": "Tidal Causeway",
		"hook": "One road to an island fort, no cover on it, and they can see all of it.",
		"shape": "gauntlet into a fortress",
		"px": SQUARE,
		"paint": [["rect", 0, 0, 112, 112, "B"],
			["rect", 0, 0, 112, 26, "G"], ["oval", 74, 76, 22, 20, "G"],
			["rect", 0, 0, 112, 4, "W"],
			["line", 30, 8, 30, 22, 1.0, "M"], ["path", [Vector2(30, 22), Vector2(44, 52),
				Vector2(62, 70), Vector2(74, 76)], 1.5, "M"],
			["oval", 74, 76, 9, 8, "U"]],
		"recipe": {"water_depth": 7.0, "water_bank": 8.0, "road_width": 9.0},
		"dress": [["at", "fortress/fort_keep", 190.0, 160.0, 20.0],
				["at", "fortress/fort_gate", 120.0, 120.0, 40.0]]
			+ [["ring", "fortress/fort_tower", 190.0, 160.0, 84.0, 6]]
			+ [["ring", "fortress/fort_wall", 190.0, 160.0, 84.0, 14]]
			+ town(["estates/estate_courtyard_wing", "estates/estate_podium_row"],
				-420.0, -330.0, 420.0, -280.0, 2)
			+ [["at", "fortifications/fort_checkpoint", -170.0, -270.0, 0.0],
				["at", "landmarks/landmark_relay_dish", 190.0, 160.0, 0.0]]
			+ cover(-420.0, -220.0, 420.0, -220.0, 34.0),
		"scatter": ["scatter_debris"],
		"cams": [[-150.0, -230.0, 180.0, 140.0, 58.0], [60.0, 40.0, 190.0, 150.0, 60.0]],
	})

	# ═══ WORKS ═══════════════════════════════════════════════════════════════
	# Flat ground, heavy cover, and height that comes from built structure with
	# its own stairs — never from the terrain.

	# ── REFINERY ─────────────────────────────────────────────────────────────
	out.append({
		"id": "refinery", "name": "Refinery",
		"hook": "Round tanks you orbit, pipe racks you duck under, a flare you can see from the map edge.",
		"shape": "orbital cover, roofed lanes",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "G"], ["rect", 0, 0, 176, 5, "Y"],
			["rect", 0, 59, 176, 64, "Y"],
			["line", 0, 32, 176, 32, 1.0, "M"], ["line", 44, 6, 44, 58, 1.0, "M"],
			["line", 132, 6, 132, 58, 1.0, "M"], ["rect", 150, 10, 174, 26, "R"]],
		"dress": [["grid", "industrial/industrial_gas_sphere", -600.0, -190.0, -300.0, -60.0, 0.0, 20.0],
				["grid", "features/feature_fuel_tanks", -260.0, -190.0, 80.0, -70.0, 0.0, 24.0],
				["at", "industrial/industrial_smokestack", 300.0, -150.0, 0.0],
				["at", "industrial/industrial_blast_furnace", 420.0, -120.0, 0.0],
				["at", "industrial/industrial_plant_office", -60.0, 160.0, 0.0],
				["at", "industrial/industrial_water_tower", 560.0, -170.0, 0.0]]
			+ rows("industrial/industrial_pipe_rack", -600.0, 600.0, 30.0, 3, 46.0, 2.0)
			+ mix(["industrial/industrial_warehouse_long", "industrial/industrial_hangar_shed"],
				180.0, 150.0, 620.0, 150.0, 16.0)
			+ cover(-620.0, -20.0, 620.0, -20.0, 28.0)
			+ cover(-620.0, 110.0, 620.0, 110.0, 28.0)
			+ [["row", "props/prop_barrels", -400.0, 190.0, 400.0, 190.0, 30.0]],
		"scatter": ["scatter_tech_debris"],
		"cams": [[-560.0, 0.0, 400.0, -60.0, 62.0], [40.0, 180.0, -200.0, -120.0, 64.0]],
	})

	# ── FOUNDRY ──────────────────────────────────────────────────────────────
	out.append({
		"id": "foundry", "name": "Foundry",
		"hook": "One vast shed with a crane down the middle, and a yard of steel outside it.",
		"shape": "big interior with a heavy exterior approach",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"], ["rect", 0, 0, 128, 5, "Y"],
			["line", 0, 74, 128, 74, 1.0, "M"], ["line", 64, 10, 64, 74, 1.0, "M"],
			["rect", 4, 82, 124, 94, "R"]],
		"dress": [["at", "industrial/industrial_blast_furnace", -200.0, -230.0, 0.0],
				["at", "industrial/industrial_blast_furnace", -80.0, -230.0, 0.0],
				["at", "industrial/industrial_smokestack", 40.0, -260.0, 0.0],
				["at", "industrial/industrial_sawtooth_factory", 220.0, -200.0, 0.0]]
			+ mix(["industrial/industrial_warehouse_long"], -420.0, -60.0, 420.0, -60.0, 8.0)
			+ [["row", "industrial/industrial_gantry_crane", -300.0, -60.0, 300.0, -60.0, 90.0]]
			+ rows("machines/machine_steel_coils", -380.0, 380.0, 40.0, 3, 34.0, 12.0)
			+ [["row", "industrial/industrial_conveyor", -360.0, 150.0, 360.0, 150.0, 4.0],
				["at", "industrial/industrial_coal_pile", -420.0, 210.0, 0.0],
				["at", "industrial/industrial_coal_pile", -300.0, 220.0, 0.0],
				["at", "industrial/industrial_substation", 300.0, 210.0, 0.0]]
			+ cover(-420.0, 260.0, 420.0, 260.0, 28.0)
			+ [["row", "machines/machine_semi_truck", -300.0, 320.0, 300.0, 320.0, 20.0]],
		"scatter": ["scatter_tech_debris"],
		"cams": [[-420.0, -60.0, 420.0, -60.0, 60.0], [0.0, 330.0, 0.0, -230.0, 62.0]],
	})

	# ── QUARRY BENCHES ───────────────────────────────────────────────────────
	out.append({
		"id": "quarry_benches", "name": "Quarry Benches",
		"hook": "A stepped pit: every bench is flat and open, every ramp between them is not.",
		"shape": "stepped assault, clean lanes",
		"px": SQUARE,
		"paint": [["rect", 0, 0, 112, 112, "Y"], ["oval", 56, 56, 40, 38, "G"],
			["oval", 56, 56, 26, 24, "G"], ["rect", 0, 0, 112, 6, "W"],
			["rect", 106, 0, 112, 112, "W"],
			["path", [Vector2(56, 106), Vector2(56, 88), Vector2(34, 72), Vector2(40, 54),
				Vector2(62, 44)], 1.5, "M"],
			["oval", 56, 56, 12, 11, "R"]],
		"recipe": {"terrace_step": 8.0, "terrace_strength": 0.85, "rough_height": 10.0,
			"sketch_mountain_height": 52.0},
		"dress": [["at", "machines/machine_excavator", 30.0, 20.0, 40.0],
				["at", "machines/machine_bulldozer", -60.0, 60.0, 200.0],
				["at", "industrial/industrial_conveyor", 120.0, -60.0, 20.0],
				["at", "industrial/industrial_silos", 260.0, -180.0, 0.0],
				["at", "industrial/industrial_plant_office", 320.0, -100.0, 0.0],
				["at", "features/feature_rock_outcrop", -230.0, -190.0, 0.0],
				["at", "features/feature_rock_outcrop", 220.0, 230.0, 60.0]]
			+ [["ring", "props/prop_rock_slabs", 0.0, 0.0, 190.0, 14],
				["ring", "props/prop_boulder_b", 0.0, 0.0, 260.0, 16],
				["ring", "props/prop_dirt_mound", 0.0, 0.0, 120.0, 10]]
			+ cover(-260.0, 300.0, 260.0, 300.0, 30.0)
			+ [["row", "machines/machine_semi_truck", -200.0, 340.0, 200.0, 340.0, 24.0]],
		"scatter": ["scatter_boulders", "scatter_micro_terrain"],
		"cams": [[0.0, 380.0, 0.0, 0.0, 58.0], [-160.0, 120.0, 140.0, -60.0, 62.0]],
	})

	# ── CEMENT WORKS ─────────────────────────────────────────────────────────
	out.append({
		"id": "cement_works", "name": "Cement Works",
		"hook": "A conveyor gallery three hundred metres long that you can fight on top of.",
		"shape": "elevated spine over a ground map",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "G"], ["rect", 0, 0, 176, 6, "Y"],
			["rect", 0, 58, 176, 64, "Y"], ["line", 0, 50, 176, 50, 1.0, "M"],
			["line", 30, 8, 30, 50, 1.0, "M"], ["line", 146, 8, 146, 50, 1.0, "M"]],
		"dress": [["row", "industrial/industrial_conveyor", -560.0, -40.0, 560.0, -40.0, 2.0],
				["row", "industrial/industrial_silos", -460.0, -150.0, -180.0, -150.0, 16.0],
				["row", "industrial/industrial_silos", 200.0, -150.0, 480.0, -150.0, 16.0],
				["at", "industrial/industrial_smokestack", -20.0, -170.0, 0.0],
				["at", "industrial/industrial_plant_office", 120.0, -140.0, 0.0],
				["at", "industrial/industrial_coal_pile", -600.0, 60.0, 0.0],
				["at", "industrial/industrial_gantry_crane", 300.0, 60.0, 0.0],
				["at", "industrial/industrial_water_tower", 560.0, 150.0, 0.0]]
			+ mix(["industrial/industrial_warehouse_long", "industrial/industrial_hangar_shed"],
				-560.0, 150.0, 200.0, 150.0, 14.0)
			+ cover(-620.0, 40.0, 620.0, 40.0, 26.0)
			+ cover(-620.0, 110.0, 620.0, 110.0, 30.0),
		"scatter": ["scatter_tech_debris", "scatter_debris"],
		"cams": [[-560.0, -40.0, 560.0, -40.0, 60.0], [0.0, 180.0, -200.0, -140.0, 62.0]],
	})

	# ── SCRAPYARD ────────────────────────────────────────────────────────────
	out.append({
		"id": "scrapyard", "name": "Scrapyard",
		"hook": "Walls of crushed metal that make a maze nobody designed, and a crane over all of it.",
		"shape": "improvised maze, one landmark",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"], ["rect", 0, 0, 128, 5, "Y"],
			["rect", 0, 90, 128, 96, "Y"], ["line", 0, 84, 128, 84, 1.0, "M"],
			["line", 64, 6, 64, 84, 1.0, "M"], ["rect", 88, 10, 124, 34, "R"]],
		"dress": [["grid", "industrial/industrial_scrap_yard", -480.0, -320.0, 480.0, 200.0, 0.0, 30.0],
				["at", "industrial/industrial_gantry_crane", 0.0, -60.0, 90.0],
				["at", "industrial/industrial_plant_office", -420.0, 260.0, 0.0],
				["at", "industrial/industrial_gatehouse", 0.0, 300.0, 0.0],
				["at", "machines/machine_excavator", 200.0, 120.0, 130.0]]
			+ [["row", "props/prop_car_wreck", -420.0, 250.0, 420.0, 250.0, 14.0],
				["row", "props/prop_robot_wreck", -380.0, 290.0, 380.0, 290.0, 22.0]]
			+ cover(-460.0, 220.0, 460.0, 220.0, 30.0),
		"scatter": ["scatter_wrecks", "scatter_tech_debris"],
		"cams": [[-440.0, -60.0, 440.0, -60.0, 62.0], [0.0, 280.0, 0.0, -200.0, 62.0]],
	})

	# ── POWER STATION ────────────────────────────────────────────────────────
	out.append({
		"id": "power_station", "name": "Power Station",
		"hook": "Cooling towers you can see from anywhere, and a switchyard nobody sane fights in.",
		"shape": "huge landmarks, a forbidden middle",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "G"], ["rect", 0, 0, 176, 5, "Y"],
			["rect", 0, 56, 176, 64, "B"], ["line", 0, 52, 176, 52, 1.0, "M"],
			["line", 52, 8, 52, 52, 1.0, "M"], ["line", 124, 8, 124, 52, 1.0, "M"]],
		"recipe": {"water_depth": 8.0},
		"dress": [["row", "industrial/industrial_gas_sphere", -520.0, -160.0, -160.0, -160.0, 26.0],
				["at", "industrial/industrial_smokestack", 0.0, -180.0, 0.0],
				["at", "industrial/industrial_smokestack", 90.0, -180.0, 0.0],
				["grid", "industrial/industrial_substation", 200.0, -190.0, 620.0, -60.0, 0.0, 22.0],
				["at", "industrial/industrial_water_tower", -600.0, -60.0, 0.0],
				["at", "industrial/industrial_coal_barge", 200.0, 200.0, 0.0],
				["at", "industrial/industrial_coal_pile", -300.0, 120.0, 0.0],
				["at", "industrial/industrial_coal_pile", -180.0, 130.0, 0.0]]
			+ mix(["industrial/industrial_warehouse_long", "industrial/industrial_hangar_arch"],
				-560.0, 30.0, -60.0, 30.0, 14.0)
			+ [["row", "features/feature_power_pylon", -400.0, -20.0, 500.0, -20.0, 70.0],
				["row", "industrial/industrial_conveyor", -300.0, 100.0, 180.0, 100.0, 3.0]]
			+ cover(-620.0, 60.0, 620.0, 60.0, 28.0)
			+ cover(-620.0, 150.0, 620.0, 150.0, 30.0),
		"scatter": ["scatter_tech_debris"],
		"cams": [[-560.0, 60.0, 400.0, -140.0, 62.0], [400.0, 140.0, -300.0, -160.0, 60.0]],
	})

	# ── PYLON LINE ───────────────────────────────────────────────────────────
	out.append({
		"id": "pylon_line", "name": "Pylon Line",
		"hook": "A transmission line across open country: the towers are the only cover for a kilometre.",
		"shape": "minimal cover, maximum distance",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "G"], ["rect", 0, 0, 176, 8, "W"],
			["rect", 0, 56, 176, 64, "Y"], ["line", 0, 44, 176, 44, 1.0, "M"],
			["oval", 30, 30, 10, 8, "Y"], ["oval", 96, 22, 12, 9, "Y"],
			["oval", 150, 36, 11, 8, "Y"]],
		"recipe": {"hills_height": 5.0, "rough_height": 7.0},
		"dress": [["row", "features/feature_power_pylon", -620.0, -80.0, 620.0, -80.0, 86.0],
				["at", "industrial/industrial_substation", -560.0, 90.0, 0.0],
				["at", "industrial/industrial_substation", 560.0, 90.0, 0.0],
				["at", "features/feature_rock_outcrop", -360.0, 50.0, 0.0],
				["at", "features/feature_rock_outcrop", 180.0, -150.0, 40.0],
				["at", "features/feature_boulder_field", 430.0, 20.0, 0.0],
				["at", "features/feature_boulder_field", -140.0, 130.0, 60.0],
				["at", "fortifications/fort_command_bunker", 0.0, 120.0, 0.0]]
			+ cover(-600.0, 0.0, 600.0, 0.0, 90.0)
			+ [["row", "props/prop_boulder_c", -600.0, 170.0, 600.0, 170.0, 60.0]],
		"scatter": ["scatter_boulders", "scatter_alpine_ground"],
		"cams": [[-600.0, -80.0, 600.0, -80.0, 60.0], [0.0, 190.0, 300.0, -120.0, 62.0]],
	})

	# ── GRAIN TERMINAL ───────────────────────────────────────────────────────
	out.append({
		"id": "grain_terminal", "name": "Grain Terminal",
		"hook": "A wall of silos between the town and the water, and one way through it.",
		"shape": "solid barrier with a single gap",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "G"], ["rect", 0, 46, 176, 64, "B"],
			["rect", 0, 0, 176, 4, "Y"], ["line", 0, 40, 176, 40, 1.0, "M"],
			["line", 88, 6, 88, 44, 1.0, "M"], ["rect", 20, 6, 76, 24, "U"]],
		"recipe": {"water_depth": 9.0, "water_bank": 14.0},
		"dress": [["row", "industrial/industrial_silos", -600.0, 30.0, -60.0, 30.0, 6.0],
				["row", "industrial/industrial_silos", 60.0, 30.0, 600.0, 30.0, 6.0],
				["row", "industrial/industrial_conveyor", -400.0, 90.0, 400.0, 90.0, 4.0],
				["at", "industrial/industrial_coal_barge", -200.0, 180.0, 0.0],
				["at", "industrial/industrial_coal_barge", 240.0, 190.0, 0.0],
				["at", "industrial/industrial_gantry_crane", 0.0, 140.0, 90.0],
				["at", "industrial/industrial_gatehouse", 0.0, -30.0, 0.0]]
			+ town(["estates/estate_courtyard_block", "estates/estate_podium_row",
				"estates/estate_market_hall"], -560.0, -200.0, 0.0, -110.0, 2)
			+ cover(-620.0, -60.0, 620.0, -60.0, 26.0)
			+ [["row", "machines/machine_semi_truck", -400.0, -20.0, 400.0, -20.0, 26.0]],
		"scatter": ["scatter_debris"],
		"cams": [[0.0, -110.0, 0.0, 180.0, 58.0], [-500.0, 60.0, 500.0, 60.0, 62.0]],
	})

	# ── CLARIFIER RINGS ──────────────────────────────────────────────────────
	out.append({
		"id": "clarifier_rings", "name": "Clarifier Rings",
		"hook": "Circular tanks you fight around and never across; every route is an arc.",
		"shape": "curved cover, no straight lines",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"], ["rect", 0, 0, 128, 5, "Y"],
			["oval", 34, 34, 11, 11, "B"], ["oval", 70, 34, 11, 11, "B"],
			["oval", 34, 66, 11, 11, "B"], ["oval", 70, 66, 11, 11, "B"],
			["oval", 104, 50, 9, 9, "B"],
			["line", 0, 50, 128, 50, 1.0, "M"], ["line", 52, 6, 52, 90, 1.0, "M"]],
		"recipe": {"water_depth": 5.0, "water_bank": 8.0},
		"dress": [["ring", "props/prop_concrete_pipes", -240.0, -160.0, 104.0, 10],
				["ring", "props/prop_concrete_pipes", 48.0, -160.0, 104.0, 10],
				["ring", "props/prop_concrete_pipes", -240.0, 96.0, 104.0, 10],
				["ring", "props/prop_concrete_pipes", 48.0, 96.0, 104.0, 10],
				["ring", "fortifications/fort_t_walls", 320.0, -32.0, 88.0, 8],
				["at", "industrial/industrial_plant_office", -420.0, -20.0, 0.0],
				["at", "industrial/industrial_water_tower", 420.0, 180.0, 0.0],
				["at", "industrial/industrial_substation", -60.0, -30.0, 0.0]]
			+ rows("industrial/industrial_pipe_rack", -440.0, 440.0, -20.0, 2, 60.0, 2.0)
			+ cover(-460.0, 270.0, 460.0, 270.0, 28.0)
			+ mix(["industrial/industrial_warehouse_long"], -420.0, 320.0, 420.0, 320.0, 16.0),
		"scatter": ["scatter_tech_debris"],
		"cams": [[-100.0, 20.0, 340.0, -40.0, 64.0], [0.0, 330.0, 0.0, -260.0, 60.0]],
	})

	# ── DRAGLINE PIT ─────────────────────────────────────────────────────────
	out.append({
		"id": "dragline_pit", "name": "Dragline Pit",
		"hook": "One machine the size of a building is the objective, and it is in a hole.",
		"shape": "descent into a bowl, one big prize",
		"px": SQUARE,
		"paint": [["rect", 0, 0, 112, 112, "Y"], ["oval", 56, 60, 34, 30, "G"],
			["rect", 0, 0, 112, 8, "W"], ["rect", 0, 0, 8, 112, "W"],
			["path", [Vector2(56, 6), Vector2(50, 26), Vector2(30, 44), Vector2(44, 60)], 1.5, "M"],
			["path", [Vector2(106, 90), Vector2(80, 84), Vector2(66, 70)], 1.5, "M"],
			["oval", 56, 60, 16, 14, "R"]],
		"recipe": {"terrace_step": 10.0, "terrace_strength": 0.8, "rough_height": 12.0,
			"sketch_mountain_height": 56.0},
		"dress": [["at", "machines/machine_excavator", 0.0, 40.0, 30.0],
				["at", "industrial/industrial_gantry_crane", 80.0, 90.0, 0.0],
				["at", "machines/machine_bulldozer", -120.0, 10.0, 210.0],
				["at", "industrial/industrial_conveyor", 150.0, 30.0, 40.0],
				["at", "industrial/industrial_plant_office", 300.0, 220.0, 0.0],
				["at", "features/feature_rock_outcrop", -280.0, -240.0, 0.0]]
			+ [["ring", "props/prop_dirt_mound", 0.0, 40.0, 180.0, 12],
				["ring", "props/prop_rock_slabs", 0.0, 40.0, 250.0, 14],
				["ring", "features/feature_berm", 0.0, 40.0, 320.0, 10]]
			+ cover(-300.0, -300.0, 300.0, -300.0, 34.0)
			+ [["row", "machines/machine_semi_truck", -200.0, 330.0, 200.0, 330.0, 28.0]],
		"scatter": ["scatter_boulders", "scatter_micro_terrain"],
		"cams": [[0.0, -330.0, 0.0, 60.0, 58.0], [-260.0, 140.0, 40.0, 40.0, 62.0]],
	})

	# ── 1. RAIL YARD ─────────────────────────────────────────────────────────
	# Long sightlines ALONG the tracks, nothing across them. The whole map is
	# one axis you can see a kilometre down and one axis you cannot see ten
	# metres across, and getting from lane to lane is the game.
	var rail: Array = rows("industrial/industrial_rail_track", -620.0, 620.0, -120.0, 9, 26.0)
	rail.append_array([
		["row", "industrial/industrial_rail_boxcar", -520.0, -120.0, -200.0, -120.0, 6.0],
		["row", "industrial/industrial_rail_gondola", 100.0, -68.0, 420.0, -68.0, 6.0],
		["row", "industrial/industrial_rail_tank_car", -420.0, 10.0, -100.0, 10.0, 6.0],
		["row", "industrial/industrial_rail_boxcar", 200.0, 62.0, 500.0, 62.0, 6.0],
		["at", "industrial/industrial_water_tower", -560.0, 140.0, 0.0],
		["at", "industrial/industrial_warehouse_long", 380.0, 150.0, 90.0],
		["at", "industrial/industrial_gatehouse", -20.0, 196.0, 0.0],
		["row", "industrial/industrial_silos", 520.0, 150.0, 620.0, 150.0, 14.0],
		["row", "props/prop_jersey_barrier", -300.0, 188.0, 300.0, 188.0, 10.0],
		["at", "industrial/industrial_gantry_crane", 0.0, -120.0, 0.0],
	])
	out.append({
		"id": "rail_yard", "name": "Rail Yard",
		"hook": "Nine tracks you can see a kilometre down and cannot see across.",
		"shape": "parallel lanes, hard to cross",
		"px": LONG,
		"paint": [
			["rect", 0, 0, 176, 64, "Y"],
			["rect", 4, 14, 172, 50, "G"],
			["line", 0, 56, 176, 56, 1.0, "M"],
			["rect", 0, 0, 176, 5, "W"],
		],
		"dress": rail,
		"cams": [[-560.0, -120.0, 560.0, -120.0, 58.0], [0.0, 170.0, -200.0, -60.0, 66.0]],
	})

	# ── 2. CONTAINER PORT ────────────────────────────────────────────────────
	# A maze at ground level with a roof you can also fight on. Stacks make
	# corridors that change every twenty metres, and the cranes tell you where
	# you are from anywhere in it.
	var port: Array = []
	for i in 5:
		port.append(["grid", "industrial/industrial_container_yard",
				-420.0 + i * 170.0, -160.0, -300.0 + i * 170.0, 120.0, 0.0, 26.0])
	port.append_array([
		["row", "industrial/industrial_gantry_crane", -300.0, 200.0, 300.0, 200.0, 60.0],
		["at", "industrial/industrial_warehouse_long", -520.0, 170.0, 0.0],
		["at", "industrial/industrial_plant_office", 480.0, 190.0, 0.0],
		["row", "props/prop_concrete_blocks", -400.0, 240.0, 400.0, 240.0, 12.0],
	])
	out.append({
		"id": "container_port", "name": "Container Port",
		"hook": "A maze that has a roof, and two cranes so you always know where you are.",
		"shape": "dense grid maze with rooftops",
		"px": LONG,
		"paint": [
			["rect", 0, 0, 176, 64, "G"],
			["rect", 0, 58, 176, 64, "B"],
			["line", 0, 55, 176, 55, 1.0, "M"],
			["rect", 0, 0, 176, 4, "Y"],
		],
		"recipe": {"water_depth": 9.0, "water_bank": 14.0},
		"dress": port,
		"cams": [[-460.0, -40.0, 400.0, -40.0, 60.0], [0.0, 230.0, 0.0, -100.0, 66.0]],
	})

	# ── 3. TWO BRIDGES ───────────────────────────────────────────────────────
	# One river, two crossings, six hundred metres apart. You cannot cover both
	# and neither can they, so the whole mission is one committed choice and
	# the price of getting it wrong is the walk back.
	out.append({
		"id": "two_bridges", "name": "Two Bridges",
		"hook": "One river, two crossings, and you can only be at one of them.",
		"shape": "forced choke, binary choice",
		"px": LONG,
		"paint": [
			["rect", 0, 0, 176, 64, "G"],
			["path", [Vector2(0, 28), Vector2(40, 33), Vector2(88, 26), Vector2(132, 34), Vector2(176, 29)], 7.0, "B"],
			["rect", 0, 0, 176, 4, "W"],
			["rect", 0, 60, 176, 64, "W"],
			["line", 40, 0, 40, 64, 1.5, "M"],
			["line", 132, 0, 132, 64, 1.5, "M"],
			["line", 0, 12, 176, 12, 1.0, "M"],
			["line", 0, 50, 176, 50, 1.0, "M"],
			["rect", 60, 14, 112, 24, "U"],
		],
		"recipe": {"water_depth": 8.0, "water_bank": 26.0, "road_width": 7.0},
		"dress": [
			["at", "fortifications/fort_checkpoint", -544.0, -100.0, 0.0],
			["at", "fortifications/fort_checkpoint", 352.0, 120.0, 0.0],
			["row", "fortifications/fort_hesco_wall", -600.0, 60.0, -480.0, 60.0, 4.0],
			["row", "fortifications/fort_hesco_wall", 300.0, -60.0, 420.0, -60.0, 4.0],
			["grid", "estates/estate_courtyard_block", -220.0, -180.0, 230.0, -90.0, 0.0, 18.0],
			["at", "landmarks/landmark_clock_tower", 20.0, -150.0, 0.0],
			["row", "props/prop_tank_trap", -560.0, -40.0, -460.0, -40.0, 8.0],
		],
		"cams": [[-544.0, -160.0, -544.0, 120.0, 60.0], [-200.0, -140.0, 360.0, 60.0, 62.0]],
	})

	# ── 4. SOLAR FIELD ───────────────────────────────────────────────────────
	# Waist-high cover as far as you can see, in rows a kilometre long. Almost
	# nothing blocks a sight line and almost everything breaks one, which is
	# the opposite of every other map here.
	var solar: Array = rows("solar/solar_panel_row", -600.0, 600.0, -200.0, 11, 38.0, 6.0)
	solar.append_array([
		["at", "solar/solar_tower_field", 0.0, 250.0, 0.0],
		["row", "solar/solar_inverter_skid", -400.0, 230.0, 400.0, 230.0, 60.0],
		["at", "solar/solar_wash_bay", -520.0, 230.0, 0.0],
		["at", "solar/solar_battery_container", 480.0, 230.0, 0.0],
	])
	out.append({
		"id": "solar_field", "name": "Solar Field",
		"hook": "Cover everywhere and cover nowhere: a kilometre of waist-high rows.",
		"shape": "open field, low cover, long sight lines",
		"px": LONG,
		"paint": [
			["rect", 0, 0, 176, 64, "G"],
			["rect", 0, 0, 176, 6, "Y"],
			["rect", 0, 58, 176, 64, "Y"],
			["line", 0, 54, 176, 54, 1.0, "M"],
			["line", 88, 0, 88, 64, 1.0, "M"],
		],
		"dress": solar,
		"cams": [[-560.0, -120.0, 400.0, 60.0, 62.0], [0.0, 180.0, 0.0, -180.0, 66.0]],
	})

	# ═══ TOWN ════════════════════════════════════════════════════════════════
	# The kind of map this project has liked best so far. Streets are lanes you
	# cannot see down, buildings are cover that also blocks, and a tower tells
	# you where you are without looking at a map.

	out.append({
		"id": "old_town", "name": "Old Town",
		"hook": "A dense core on a low mound behind one wall, and alleys too narrow to shoot down.",
		"shape": "concentric: outskirts, wall, warren",
		"px": SQUARE,
		"paint": [["rect", 0, 0, 112, 112, "G"], ["oval", 56, 52, 30, 28, "U"],
			["rect", 0, 0, 112, 5, "Y"],
			["line", 0, 88, 112, 88, 1.0, "M"], ["line", 56, 88, 56, 56, 1.0, "M"],
			["line", 0, 20, 112, 20, 1.0, "M"]],
		"recipe": {"urban_block": Vector2(26.0, 22.0), "urban_street": 7.0, "urban_ruin": 0.25},
		"dress": [["ring", "fortress/fort_wall", 0.0, -30.0, 250.0, 22],
				["at", "fortress/fort_gate", 0.0, 220.0, 0.0],
				["at", "landmarks/landmark_clock_tower", -40.0, -60.0, 0.0],
				["at", "estates/estate_market_hall", 70.0, -10.0, 20.0]]
			+ town(["estates/estate_courtyard_block", "estates/estate_u_block",
				"estates/estate_courtyard_wing"], -180.0, -170.0, 180.0, 90.0, 4, 14.0)
			+ town(["estates/estate_podium_row", "estates/estate_frame_shell"],
				-420.0, 280.0, 420.0, 350.0, 2)
			+ cover(-400.0, 180.0, 400.0, 180.0, 26.0)
			+ [["at", "fortifications/fort_checkpoint", 0.0, 300.0, 0.0]],
		"scatter": ["scatter_debris"],
		"cams": [[0.0, 320.0, 0.0, -60.0, 58.0], [-150.0, -20.0, 150.0, -40.0, 64.0]],
	})

	out.append({
		"id": "boulevard", "name": "Boulevard",
		"hook": "One forty-metre avenue you must cross, and side streets that are the only sane way.",
		"shape": "a killing ground with parallel safe routes",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "U"], ["rect", 0, 0, 176, 4, "Y"],
			["line", 0, 32, 176, 32, 3.0, "M"],
			["line", 0, 12, 176, 12, 1.0, "M"], ["line", 0, 52, 176, 52, 1.0, "M"],
			["line", 44, 12, 44, 52, 1.0, "M"], ["line", 132, 12, 132, 52, 1.0, "M"]],
		"recipe": {"urban_block": Vector2(38.0, 28.0), "urban_street": 9.0, "road_width": 9.0},
		"dress": town(["estates/estate_gallery_block", "estates/estate_podium_row",
				"estates/estate_slab_stepped"], -620.0, -170.0, 620.0, -80.0, 2)
			+ town(["estates/estate_courtyard_block", "estates/estate_slab_dogleg",
				"estates/estate_u_block"], -620.0, 80.0, 620.0, 170.0, 2)
			+ [["at", "landmarks/landmark_clock_tower", -20.0, -110.0, 0.0],
				["at", "estates/estate_twin_tower", 300.0, 130.0, 0.0],
				["row", "props/prop_lamp_post", -600.0, -26.0, 600.0, -26.0, 34.0],
				["row", "props/prop_lamp_post", -600.0, 26.0, 600.0, 26.0, 34.0],
				["row", "props/prop_car_wreck", -560.0, 0.0, 560.0, 0.0, 44.0]]
			+ cover(-620.0, -50.0, 620.0, -50.0, 30.0)
			+ cover(-620.0, 50.0, 620.0, 50.0, 30.0),
		"scatter": ["scatter_debris"],
		"cams": [[-560.0, 0.0, 560.0, 0.0, 60.0], [-100.0, -60.0, 100.0, 70.0, 64.0]],
	})

	out.append({
		"id": "market_quarter", "name": "Market Quarter",
		"hook": "Nothing is more than thirty metres away and none of it is a straight line.",
		"shape": "close quarters, no sight lines at all",
		"px": Vector2i(88, 88),
		"paint": [["rect", 0, 0, 88, 88, "U"], ["rect", 0, 0, 88, 4, "Y"],
			["line", 0, 44, 88, 44, 1.0, "M"], ["line", 44, 0, 44, 88, 1.0, "M"]],
		"recipe": {"urban_block": Vector2(20.0, 16.0), "urban_street": 6.0, "urban_ruin": 0.35},
		"dress": town(["estates/estate_market_hall", "estates/estate_courtyard_wing",
				"estates/estate_collapsed_corner", "estates/estate_frame_shell"],
				-300.0, -290.0, 300.0, 290.0, 6, 10.0)
			+ [["at", "landmarks/landmark_clock_tower", 0.0, 0.0, 0.0],
				["row", "props/prop_crates", -280.0, -60.0, 280.0, -60.0, 16.0],
				["row", "props/prop_barrels", -280.0, 60.0, 280.0, 60.0, 16.0],
				["row", "props/prop_rubble_pile", -280.0, 180.0, 280.0, 180.0, 20.0]]
			+ cover(-300.0, -180.0, 300.0, -180.0, 18.0),
		"scatter": ["scatter_debris"],
		"cams": [[-160.0, 120.0, 40.0, -30.0, 66.0], [0.0, 300.0, 0.0, -100.0, 62.0]],
	})

	out.append({
		"id": "tower_blocks", "name": "Tower Blocks",
		"hook": "Six slabs in a park. Each one is a fortress and the grass between them is not.",
		"shape": "strongpoints with open ground between",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"], ["rect", 0, 0, 128, 4, "Y"],
			["line", 0, 48, 128, 48, 1.0, "M"], ["line", 32, 8, 32, 88, 1.0, "M"],
			["line", 96, 8, 96, 88, 1.0, "M"],
			["rect", 10, 10, 50, 40, "U"], ["rect", 78, 56, 118, 86, "U"]],
		"dress": [["at", "estates/estate_slab_five", -320.0, -260.0, 0.0],
				["at", "estates/estate_slab_five", -80.0, -260.0, 0.0],
				["at", "estates/estate_slab_stepped", 180.0, -230.0, 90.0],
				["at", "estates/estate_twin_tower", -280.0, 60.0, 0.0],
				["at", "estates/estate_slab_pair_bridge", 60.0, 90.0, 0.0],
				["at", "estates/estate_point_tower", 340.0, 240.0, 0.0],
				["at", "estates/estate_slab_broken", -200.0, 280.0, 0.0],
				["at", "estates/estate_microdistrict", 300.0, -40.0, 0.0]]
			+ [["row", "industrial/industrial_parking_lot", -400.0, 330.0, 400.0, 330.0, 20.0],
				["row", "props/prop_lamp_post", -420.0, 0.0, 420.0, 0.0, 44.0]]
			+ cover(-420.0, -120.0, 420.0, -120.0, 26.0)
			+ cover(-420.0, 170.0, 420.0, 170.0, 26.0)
			+ cover(-420.0, 20.0, 420.0, 20.0, 34.0),
		"scatter": ["scatter_debris"],
		"cams": [[-300.0, 180.0, 200.0, -220.0, 62.0], [0.0, 340.0, 0.0, -300.0, 60.0]],
	})

	out.append({
		"id": "campus", "name": "Campus",
		"hook": "Big lawns framed by colonnades: open ground you can cross, watched from four sides.",
		"shape": "open squares inside a hard frame",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"], ["rect", 0, 0, 128, 4, "Y"],
			["rect", 6, 8, 54, 40, "U"], ["rect", 74, 8, 122, 40, "U"],
			["rect", 6, 56, 54, 88, "U"], ["rect", 74, 56, 122, 88, "U"],
			["line", 64, 0, 64, 96, 1.5, "M"], ["line", 0, 48, 128, 48, 1.5, "M"]],
		"recipe": {"urban_block": Vector2(34.0, 26.0), "urban_street": 8.0, "urban_ruin": 0.1},
		"dress": town(["estates/estate_gallery_block", "estates/estate_courtyard_block"],
				-460.0, -300.0, -80.0, -80.0, 3, 16.0)
			+ town(["estates/estate_gallery_block", "estates/estate_u_block"],
				80.0, -300.0, 460.0, -80.0, 3, 16.0)
			+ town(["estates/estate_courtyard_wing", "estates/estate_podium_row"],
				-460.0, 80.0, -80.0, 300.0, 3, 16.0)
			+ town(["estates/estate_market_hall", "estates/estate_courtyard_block"],
				80.0, 80.0, 460.0, 300.0, 3, 16.0)
			+ [["at", "landmarks/landmark_clock_tower", 0.0, 0.0, 0.0],
				["row", "props/prop_lamp_post", -400.0, 0.0, 400.0, 0.0, 40.0]]
			+ cover(-60.0, -300.0, -60.0, 300.0, 30.0)
			+ cover(60.0, -300.0, 60.0, 300.0, 30.0),
		"scatter": ["scatter_alpine_ground"],
		"cams": [[0.0, 300.0, 0.0, -300.0, 60.0], [-200.0, 30.0, 280.0, -20.0, 64.0]],
	})

	out.append({
		"id": "canal_district", "name": "Canal District",
		"hook": "Streets and canals alternate, so every block is an island and every bridge is narrow.",
		"shape": "grid of small forced crossings",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "U"], ["rect", 0, 0, 128, 4, "Y"],
			["rect", 0, 22, 128, 27, "B"], ["rect", 0, 50, 128, 55, "B"],
			["rect", 0, 76, 128, 81, "B"],
			["line", 20, 0, 20, 96, 1.0, "M"], ["line", 64, 0, 64, 96, 1.0, "M"],
			["line", 106, 0, 106, 96, 1.0, "M"], ["line", 0, 10, 128, 10, 1.0, "M"]],
		"recipe": {"water_depth": 5.0, "water_bank": 8.0, "urban_block": Vector2(28.0, 20.0),
			"urban_street": 7.0},
		"dress": town(["estates/estate_courtyard_block", "estates/estate_u_block",
				"estates/estate_podium_row"], -460.0, -300.0, 460.0, -230.0, 2, 12.0)
			+ town(["estates/estate_gallery_block", "estates/estate_courtyard_wing"],
				-460.0, -110.0, 460.0, -40.0, 2, 12.0)
			+ town(["estates/estate_slab_dogleg", "estates/estate_market_hall"],
				-460.0, 100.0, 460.0, 170.0, 2, 12.0)
			+ town(["estates/estate_frame_shell", "estates/estate_collapsed_corner"],
				-460.0, 300.0, 460.0, 360.0, 1, 12.0)
			+ [["at", "landmarks/landmark_clock_tower", -180.0, -60.0, 0.0],
				["at", "estates/estate_point_tower", 260.0, 140.0, 0.0]]
			+ cover(-460.0, -180.0, 460.0, -180.0, 24.0)
			+ cover(-460.0, 30.0, 460.0, 30.0, 24.0),
		"scatter": ["scatter_debris"],
		"cams": [[-380.0, -60.0, 380.0, 60.0, 62.0], [0.0, 330.0, 0.0, -280.0, 60.0]],
	})

	out.append({
		"id": "fairground", "name": "Fairground",
		"hook": "A wheel you can see from every corner, over open ground nobody should cross.",
		"shape": "one landmark, one exposed middle",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"], ["rect", 0, 0, 128, 4, "Y"],
			["rect", 0, 0, 44, 30, "U"], ["rect", 86, 66, 128, 94, "U"],
			["line", 0, 48, 128, 48, 1.0, "M"], ["line", 64, 0, 64, 96, 1.0, "M"],
			["rect", 96, 6, 126, 28, "R"]],
		"dress": [["at", "landmarks/landmark_ferris_wheel", 0.0, 0.0, 0.0],
				["at", "estates/estate_market_hall", -140.0, 110.0, 0.0],
				["at", "estates/estate_market_hall", 150.0, -120.0, 90.0]]
			+ [["ring", "props/prop_jersey_barrier", 0.0, 0.0, 130.0, 16],
				["ring", "fortifications/fort_t_walls", 0.0, 0.0, 210.0, 14],
				["ring", "props/prop_crates", 0.0, 0.0, 90.0, 10]]
			+ town(["estates/estate_courtyard_block", "estates/estate_podium_row"],
				-460.0, -320.0, -120.0, -180.0, 2)
			+ town(["estates/estate_slab_broken", "estates/estate_frame_shell"],
				120.0, 200.0, 460.0, 340.0, 2)
			+ cover(-440.0, -60.0, -180.0, -60.0, 24.0)
			+ cover(180.0, 60.0, 440.0, 60.0, 24.0),
		"scatter": ["scatter_debris"],
		"cams": [[-300.0, -200.0, 0.0, 20.0, 62.0], [0.0, 330.0, 0.0, -80.0, 60.0]],
	})

	out.append({
		"id": "institute_hill", "name": "Institute Hill",
		"hook": "One big block on a low rise, with terraced car parks climbing to it.",
		"shape": "stepped approach to a single objective",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"], ["rect", 0, 0, 128, 4, "Y"],
			["rect", 44, 12, 88, 40, "U"],
			["line", 0, 84, 128, 84, 1.0, "M"], ["line", 64, 84, 64, 40, 1.0, "M"],
			["line", 20, 60, 108, 60, 1.0, "M"]],
		"recipe": {"hills_height": 6.0, "urban_block": Vector2(36.0, 28.0)},
		"dress": [["at", "estates/estate_slab_five", 0.0, -230.0, 0.0],
				["at", "estates/estate_courtyard_block", -160.0, -200.0, 0.0],
				["at", "estates/estate_courtyard_block", 160.0, -200.0, 0.0],
				["at", "landmarks/landmark_relay_dish", 0.0, -300.0, 20.0]]
			+ [["row", "industrial/industrial_parking_deck", -320.0, -80.0, 320.0, -80.0, 20.0],
				["row", "industrial/industrial_parking_lot", -380.0, 40.0, 380.0, 40.0, 18.0],
				["row", "props/prop_car_wreck", -360.0, 100.0, 360.0, 100.0, 24.0]]
			+ cover(-400.0, -150.0, 400.0, -150.0, 26.0)
			+ cover(-400.0, -20.0, 400.0, -20.0, 26.0)
			+ town(["estates/estate_podium_row", "estates/estate_frame_shell"],
				-460.0, 200.0, 460.0, 300.0, 2)
			+ [["at", "fortifications/fort_checkpoint", 0.0, 160.0, 0.0]],
		"scatter": ["scatter_debris"],
		"cams": [[0.0, 300.0, 0.0, -260.0, 58.0], [-300.0, -60.0, 100.0, -220.0, 62.0]],
	})

	out.append({
		"id": "seafront", "name": "Seafront",
		"hook": "A promenade with hotels one side and open beach the other: one flank is sand.",
		"shape": "linear, with an exposed flank",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "G"], ["rect", 0, 46, 176, 64, "B"],
			["rect", 0, 40, 176, 47, "Y"], ["rect", 0, 0, 176, 4, "W"],
			["rect", 4, 10, 172, 32, "U"], ["line", 0, 37, 176, 37, 1.5, "M"],
			["line", 40, 6, 40, 37, 1.0, "M"], ["line", 130, 6, 130, 37, 1.0, "M"]],
		"recipe": {"water_depth": 6.0, "water_bank": 26.0, "urban_block": Vector2(30.0, 24.0)},
		"dress": town(["estates/estate_gallery_block", "estates/estate_slab_stepped",
				"estates/estate_podium_row", "estates/estate_point_tower"],
				-640.0, -180.0, 640.0, -90.0, 2, 14.0)
			+ [["row", "props/prop_lamp_post", -620.0, -20.0, 620.0, -20.0, 32.0],
				["row", "props/prop_concrete_blocks", -620.0, 30.0, 620.0, 30.0, 22.0],
				["at", "landmarks/landmark_ferris_wheel", -260.0, 20.0, 0.0],
				["at", "estates/estate_market_hall", 240.0, -30.0, 0.0]]
			+ cover(-620.0, -50.0, 620.0, -50.0, 26.0)
			+ [["row", "fortifications/fort_dragon_teeth", -600.0, 70.0, 600.0, 70.0, 16.0],
				["row", "fortifications/fort_razor_wire", -600.0, 96.0, 600.0, 96.0, 10.0]],
		"scatter": ["scatter_debris"],
		"cams": [[-560.0, 0.0, 560.0, 0.0, 60.0], [0.0, 120.0, -200.0, -140.0, 64.0]],
	})

	out.append({
		"id": "ruin_square", "name": "Ruin Square",
		"hook": "One enormous ruin in an open square, and everything else looks in at it.",
		"shape": "a single contested interior",
		"px": Vector2i(96, 96),
		"paint": [["rect", 0, 0, 96, 96, "U"], ["rect", 30, 30, 66, 66, "R"],
			["rect", 0, 0, 96, 4, "Y"],
			["line", 0, 48, 96, 48, 1.0, "M"], ["line", 48, 0, 48, 96, 1.0, "M"]],
		"recipe": {"urban_block": Vector2(28.0, 22.0), "urban_ruin": 0.45,
			"shelling_per_hectare": 40.0},
		"dress": [["at", "estates/estate_market_hall", 0.0, 0.0, 0.0],
				["at", "estates/estate_collapsed_corner", -70.0, -70.0, 0.0],
				["at", "estates/estate_collapsed_corner", 70.0, 70.0, 180.0],
				["at", "landmarks/landmark_clock_tower", -90.0, 80.0, 0.0]]
			+ [["ring", "props/prop_rubble_pile", 0.0, 0.0, 120.0, 14],
				["ring", "fortifications/fort_t_walls", 0.0, 0.0, 180.0, 12]]
			+ town(["estates/estate_frame_shell", "estates/estate_slab_broken",
				"estates/estate_courtyard_wing"], -340.0, -320.0, 340.0, -230.0, 2, 12.0)
			+ town(["estates/estate_u_block", "estates/estate_collapsed_corner"],
				-340.0, 240.0, 340.0, 330.0, 2, 12.0)
			+ cover(-340.0, -150.0, 340.0, -150.0, 22.0)
			+ cover(-340.0, 150.0, 340.0, 150.0, 22.0),
		"scatter": ["scatter_debris"],
		"cams": [[-240.0, -200.0, 0.0, -20.0, 62.0], [0.0, 320.0, 0.0, -60.0, 60.0]],
	})

	# ═══ INFRASTRUCTURE ══════════════════════════════════════════════════════

	out.append({
		"id": "interchange", "name": "Interchange",
		"hook": "A stacked motorway junction: real height, real cover, and ramps instead of stairs.",
		"shape": "layered, with curved approaches",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"], ["rect", 0, 0, 128, 4, "Y"],
			["line", 0, 48, 128, 48, 3.0, "M"], ["line", 64, 0, 64, 96, 3.0, "M"],
			["path", [Vector2(44, 48), Vector2(44, 32), Vector2(64, 28)], 1.5, "M"],
			["path", [Vector2(84, 48), Vector2(84, 64), Vector2(64, 68)], 1.5, "M"],
			["rect", 0, 70, 40, 94, "U"], ["rect", 92, 6, 128, 30, "R"]],
		"recipe": {"road_width": 10.0, "road_falloff": 8.0},
		"dress": [["row", "bridges/bridge_highway", -300.0, 0.0, 300.0, 0.0, 0.0],
				["row", "bridges/bridge_medium", 0.0, -300.0, 0.0, 300.0, 0.0],
				["at", "industrial/industrial_gatehouse", -420.0, -200.0, 0.0],
				["at", "features/feature_power_pylon", 300.0, -240.0, 0.0],
				["at", "features/feature_power_pylon", -300.0, 240.0, 0.0]]
			+ town(["estates/estate_podium_row", "estates/estate_courtyard_wing"],
				-460.0, 200.0, -120.0, 320.0, 2)
			+ [["row", "props/prop_jersey_barrier", -420.0, -40.0, 420.0, -40.0, 16.0],
				["row", "props/prop_jersey_barrier", -420.0, 40.0, 420.0, 40.0, 16.0],
				["row", "props/prop_car_wreck", -400.0, 14.0, 400.0, 14.0, 40.0]]
			+ cover(-440.0, -160.0, 440.0, -160.0, 30.0)
			+ cover(-440.0, 150.0, 440.0, 150.0, 30.0),
		"scatter": ["scatter_debris"],
		"cams": [[-380.0, 0.0, 380.0, 0.0, 62.0], [0.0, 300.0, 0.0, -260.0, 60.0]],
	})

	out.append({
		"id": "airfield", "name": "Airfield",
		"hook": "A runway is a kilometre of nothing; all the fighting is round its edges.",
		"shape": "a wide forbidden middle with hard edges",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "G"], ["rect", 0, 0, 176, 4, "Y"],
			["rect", 0, 58, 176, 64, "Y"], ["line", 0, 32, 176, 32, 4.0, "M"],
			["line", 0, 46, 176, 46, 1.0, "M"], ["line", 24, 46, 24, 32, 1.0, "M"],
			["line", 140, 46, 140, 32, 1.0, "M"], ["rect", 30, 48, 90, 56, "U"]],
		"recipe": {"road_width": 11.0},
		"dress": [["row", "industrial/industrial_hangar_arch", -520.0, 150.0, -120.0, 150.0, 20.0],
				["row", "industrial/industrial_hangar_shed", 80.0, 150.0, 460.0, 150.0, 20.0],
				["at", "features/feature_watchtower", -20.0, 130.0, 0.0],
				["at", "industrial/industrial_water_tower", 560.0, 160.0, 0.0],
				["at", "industrial/industrial_plant_office", -320.0, 210.0, 0.0]]
			+ [["row", "fortifications/fort_hesco_sangar", -560.0, -130.0, 560.0, -130.0, 60.0],
				["row", "features/feature_berm", -520.0, -190.0, 520.0, -190.0, 40.0],
				["row", "fortifications/fort_sentry_turret", -400.0, -60.0, 400.0, -60.0, 120.0],
				["row", "props/prop_concrete_blocks", -600.0, 70.0, 600.0, 70.0, 26.0]]
			+ cover(-620.0, 100.0, 620.0, 100.0, 30.0)
			+ cover(-620.0, -90.0, 620.0, -90.0, 30.0),
		"scatter": ["scatter_debris"],
		"cams": [[-560.0, 110.0, 560.0, 140.0, 60.0], [0.0, 200.0, 0.0, -200.0, 64.0]],
	})

	out.append({
		"id": "rail_station", "name": "Rail Station",
		"hook": "A train shed you fight inside, on a viaduct you fight under.",
		"shape": "interior over an exterior",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "U"], ["rect", 0, 0, 176, 4, "Y"],
			["rect", 56, 20, 120, 44, "G"],
			["line", 0, 32, 176, 32, 1.5, "M"], ["line", 0, 54, 176, 54, 1.0, "M"],
			["line", 88, 44, 88, 54, 1.0, "M"]],
		"recipe": {"urban_block": Vector2(30.0, 24.0), "urban_ruin": 0.25},
		"dress": rows("industrial/industrial_rail_track", -300.0, 300.0, -60.0, 4, 18.0)
			+ [["row", "industrial/industrial_rail_boxcar", -240.0, -60.0, 60.0, -60.0, 8.0],
				["row", "industrial/industrial_rail_gondola", -80.0, -6.0, 240.0, -6.0, 8.0],
				["at", "industrial/industrial_hangar_arch", 0.0, -30.0, 0.0],
				["at", "industrial/industrial_hangar_arch", 130.0, -30.0, 0.0],
				["at", "industrial/industrial_hangar_arch", -130.0, -30.0, 0.0],
				["at", "landmarks/landmark_clock_tower", -180.0, 60.0, 0.0],
				["row", "bridges/bridge_long", -620.0, -60.0, -340.0, -60.0, 0.0],
				["row", "bridges/bridge_long", 340.0, -60.0, 620.0, -60.0, 0.0]]
			+ town(["estates/estate_gallery_block", "estates/estate_podium_row"],
				-620.0, 130.0, 620.0, 200.0, 2)
			+ cover(-620.0, 60.0, 620.0, 60.0, 26.0),
		"scatter": ["scatter_debris"],
		"cams": [[-300.0, -30.0, 300.0, -30.0, 62.0], [0.0, 170.0, 0.0, -110.0, 62.0]],
	})

	out.append({
		"id": "tunnel_mouths", "name": "Tunnel Mouths",
		"hook": "Two portals in a hillside, a road between, and nowhere to go but in.",
		"shape": "convergent, two objectives",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"], ["rect", 0, 0, 128, 34, "W"],
			["rect", 0, 90, 128, 96, "Y"],
			["line", 0, 62, 128, 62, 1.5, "M"], ["line", 34, 62, 34, 34, 1.0, "M"],
			["line", 96, 62, 96, 34, 1.0, "M"], ["rect", 44, 70, 86, 88, "R"]],
		"recipe": {"sketch_mountain_height": 54.0, "sketch_blend": 26.0},
		"dress": [["at", "industrial/industrial_hangar_arch", -240.0, -110.0, 0.0],
				["at", "industrial/industrial_hangar_arch", 260.0, -110.0, 0.0],
				["at", "fortifications/fort_command_bunker", -240.0, -40.0, 0.0],
				["at", "fortifications/fort_command_bunker", 260.0, -40.0, 0.0],
				["at", "features/feature_pillbox", 0.0, -60.0, 0.0],
				["at", "features/feature_watchtower", 0.0, 40.0, 0.0]]
			+ [["row", "fortifications/fort_dragon_teeth", -420.0, 20.0, 420.0, 20.0, 12.0],
				["row", "fortifications/fort_razor_wire", -420.0, 46.0, 420.0, 46.0, 8.0],
				["row", "props/prop_tank_trap", -400.0, 120.0, 400.0, 120.0, 22.0]]
			+ cover(-440.0, 180.0, 440.0, 180.0, 26.0)
			+ cover(-440.0, 280.0, 440.0, 280.0, 30.0)
			+ [["at", "fortifications/fort_checkpoint", 0.0, 330.0, 0.0]],
		"scatter": ["scatter_boulders", "scatter_alpine_ground"],
		"cams": [[0.0, 320.0, -240.0, -100.0, 60.0], [-240.0, 60.0, 260.0, -60.0, 64.0]],
	})

	out.append({
		"id": "border_post", "name": "Border Post",
		"hook": "One road between two ranges, and everything that matters is on it.",
		"shape": "pure corridor",
		"px": TALL,
		"paint": [["rect", 0, 0, 64, 176, "G"], ["rect", 0, 0, 18, 176, "W"],
			["rect", 46, 0, 64, 176, "W"],
			["line", 32, 0, 32, 176, 1.5, "M"],
			["rect", 20, 70, 44, 104, "U"], ["rect", 20, 20, 44, 40, "R"]],
		"recipe": {"sketch_mountain_height": 58.0, "sketch_blend": 30.0},
		"dress": [["at", "fortifications/fort_checkpoint", 0.0, 80.0, 0.0],
				["at", "fortifications/fort_checkpoint", 0.0, -160.0, 0.0],
				["at", "fortifications/fort_command_bunker", -60.0, 0.0, 0.0],
				["at", "features/feature_watchtower", 60.0, -60.0, 0.0],
				["at", "features/feature_pillbox", -60.0, -120.0, 20.0],
				["at", "industrial/industrial_gatehouse", 0.0, 220.0, 0.0]]
			+ [["row", "fortifications/fort_dragon_teeth", -80.0, 140.0, 80.0, 140.0, 10.0],
				["row", "fortifications/fort_hesco_wall", -80.0, -40.0, 80.0, -40.0, 4.0],
				["row", "fortifications/fort_razor_wire", -80.0, 180.0, 80.0, 180.0, 8.0]]
			+ cover(-90.0, -560.0, 90.0, -560.0, 26.0)
			+ cover(-90.0, -380.0, 90.0, -380.0, 26.0)
			+ cover(-90.0, 380.0, 90.0, 380.0, 26.0)
			+ cover(-90.0, 560.0, 90.0, 560.0, 26.0)
			+ town(["estates/estate_courtyard_wing", "estates/estate_frame_shell"],
				-90.0, 260.0, 90.0, 340.0, 2, 10.0),
		"scatter": ["scatter_alpine_ground", "scatter_alpine_snags"],
		"cams": [[0.0, 480.0, 0.0, -400.0, 58.0], [-70.0, 40.0, 70.0, -200.0, 64.0]],
	})

	out.append({
		"id": "aqueduct", "name": "Aqueduct",
		"hook": "A kilometre of arches you can fight on top of and underneath at the same time.",
		"shape": "two maps stacked on one footprint",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "G"], ["rect", 0, 0, 176, 5, "Y"],
			["rect", 0, 58, 176, 64, "Y"],
			["line", 0, 30, 176, 30, 1.0, "M"], ["line", 0, 50, 176, 50, 1.0, "M"],
			["rect", 130, 8, 172, 26, "U"]],
		"dress": [["row", "bridges/bridge_arch", -620.0, -30.0, 620.0, -30.0, 0.0],
				["at", "landmarks/landmark_clock_tower", 400.0, -150.0, 0.0],
				["at", "estates/estate_market_hall", 520.0, -120.0, 0.0]]
			+ town(["estates/estate_courtyard_block", "estates/estate_frame_shell"],
				260.0, -190.0, 620.0, -120.0, 2)
			+ cover(-620.0, 30.0, 620.0, 30.0, 26.0)
			+ cover(-620.0, 120.0, 620.0, 120.0, 26.0)
			+ cover(-620.0, -100.0, 200.0, -100.0, 30.0)
			+ [["row", "props/prop_boulder_b", -600.0, 190.0, 600.0, 190.0, 40.0]],
		"scatter": ["scatter_alpine_ground", "scatter_boulders"],
		"cams": [[-500.0, -30.0, 500.0, -30.0, 60.0], [0.0, 130.0, 100.0, -60.0, 64.0]],
	})

	out.append({
		"id": "dam_crest", "name": "Dam Crest",
		"hook": "The crest is the only crossing and it is eight metres wide with a drop either side.",
		"shape": "the thinnest possible choke",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"], ["rect", 0, 0, 128, 44, "B"],
			["rect", 0, 0, 128, 6, "W"], ["rect", 0, 0, 10, 96, "W"],
			["rect", 118, 0, 128, 96, "W"], ["rect", 0, 52, 128, 96, "R"],
			["line", 64, 0, 64, 96, 1.5, "M"], ["line", 0, 74, 128, 74, 1.0, "M"],
			["rect", 14, 78, 50, 92, "U"]],
		"recipe": {"water_depth": 16.0, "water_bank": 22.0, "sketch_mountain_height": 60.0},
		"dress": [["at", "industrial/industrial_lock_dam", 0.0, 30.0, 0.0],
				["at", "industrial/industrial_lock_dam", -90.0, 30.0, 0.0],
				["at", "industrial/industrial_lock_dam", 90.0, 30.0, 0.0],
				["at", "industrial/industrial_substation", 220.0, 130.0, 0.0],
				["at", "industrial/industrial_plant_office", 300.0, 180.0, 0.0],
				["at", "features/feature_watchtower", 0.0, -20.0, 0.0],
				["at", "features/feature_power_pylon", 340.0, 60.0, 0.0]]
			+ town(["estates/estate_courtyard_wing", "estates/estate_frame_shell"],
				-420.0, 230.0, -100.0, 320.0, 2)
			+ cover(-440.0, 150.0, 440.0, 150.0, 28.0)
			+ cover(-440.0, 300.0, 440.0, 300.0, 28.0)
			+ [["row", "fortifications/fort_hesco_wall", -60.0, 90.0, 60.0, 90.0, 4.0]],
		"scatter": ["scatter_boulders", "scatter_debris"],
		"cams": [[0.0, 300.0, 0.0, -100.0, 58.0], [-300.0, 200.0, 40.0, 40.0, 62.0]],
	})

	out.append({
		"id": "air_cargo", "name": "Air Cargo Apron",
		"hook": "Parked freight and fuel bowsers on a concrete plain: cover that could go up.",
		"shape": "open ground with scattered hard cover",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "G"], ["rect", 0, 0, 176, 4, "Y"],
			["rect", 10, 12, 166, 50, "U"],
			["line", 0, 56, 176, 56, 1.5, "M"], ["line", 88, 12, 88, 56, 1.0, "M"]],
		"recipe": {"urban_block": Vector2(44.0, 34.0), "urban_street": 12.0, "urban_ruin": 0.05},
		"dress": [["grid", "features/feature_container_stack", -560.0, -160.0, 560.0, 40.0, 0.0, 34.0],
				["row", "features/feature_fuel_tanks", -480.0, 120.0, 480.0, 120.0, 40.0],
				["at", "industrial/industrial_hangar_arch", -400.0, -190.0, 0.0],
				["at", "industrial/industrial_hangar_arch", 400.0, -190.0, 0.0],
				["at", "features/feature_watchtower", 0.0, -190.0, 0.0],
				["row", "machines/machine_forklift", -400.0, 80.0, 400.0, 80.0, 44.0],
				["row", "machines/machine_semi_truck", -400.0, 170.0, 400.0, 170.0, 34.0]]
			+ cover(-620.0, 200.0, 620.0, 200.0, 28.0),
		"scatter": ["scatter_tech_debris"],
		"cams": [[-500.0, 60.0, 500.0, -60.0, 62.0], [0.0, 210.0, 0.0, -180.0, 62.0]],
	})

	# ═══ GATED BY THE LAND ═══════════════════════════════════════════════════
	# The terrain decides where you can go and never what you stand on. Every
	# floor in here is flat; the relief is the wall round it.

	out.append({
		"id": "mesa_top", "name": "Mesa Top",
		"hook": "A flat table with two ramps onto it, and open ground all the way round.",
		"shape": "one high flat prize, two ways up",
		"px": SQUARE,
		"paint": [["rect", 0, 0, 112, 112, "G"], ["oval", 56, 52, 30, 26, "W"],
			["oval", 56, 52, 24, 20, "G"], ["rect", 0, 0, 112, 4, "Y"],
			["path", [Vector2(56, 104), Vector2(56, 78), Vector2(50, 66)], 1.5, "M"],
			["path", [Vector2(104, 30), Vector2(80, 38), Vector2(70, 46)], 1.5, "M"],
			["line", 0, 100, 112, 100, 1.0, "M"]],
		"recipe": {"sketch_mountain_height": 40.0, "sketch_blend": 10.0, "floor_depth": 2.0},
		"dress": [["at", "fortifications/fort_command_bunker", 0.0, -50.0, 0.0],
				["at", "landmarks/landmark_relay_dish", -60.0, -80.0, 20.0],
				["at", "features/feature_watchtower", 80.0, -20.0, 0.0],
				["at", "fortifications/fort_gun_emplacement", -80.0, 0.0, 0.0]]
			+ [["ring", "fortifications/fort_hesco_wall", 0.0, -30.0, 150.0, 20],
				["ring", "props/prop_sandbag_nest", 0.0, -30.0, 110.0, 8]]
			+ cover(-400.0, 240.0, 400.0, 240.0, 30.0)
			+ cover(-400.0, 340.0, 400.0, 340.0, 34.0)
			+ [["at", "fortifications/fort_checkpoint", 0.0, 380.0, 0.0],
				["at", "features/feature_rock_outcrop", -300.0, 60.0, 0.0],
				["at", "features/feature_rock_outcrop", 320.0, 180.0, 40.0]],
		"scatter": ["scatter_boulders", "scatter_alpine_ground"],
		"cams": [[0.0, 380.0, 0.0, -40.0, 58.0], [-30.0, 20.0, 0.0, -80.0, 64.0]],
	})

	out.append({
		"id": "box_canyon", "name": "Box Canyon",
		"hook": "Flat floor, sheer sides, a dead end with something at the far wall.",
		"shape": "one way in, one way out",
		"px": TALL,
		"paint": [["rect", 0, 0, 64, 176, "W"],
			["poly", [Vector2(24, 176), Vector2(40, 176), Vector2(46, 110),
				Vector2(52, 60), Vector2(12, 56), Vector2(18, 110)], "G"],
			["rect", 0, 0, 64, 4, "W"],
			["path", [Vector2(32, 172), Vector2(32, 120), Vector2(30, 70)], 1.5, "M"],
			["rect", 18, 58, 46, 74, "U"]],
		"recipe": {"sketch_mountain_height": 62.0, "sketch_blend": 16.0},
		"dress": [["at", "fortress/fort_keep", 0.0, -420.0, 0.0],
				["at", "landmarks/landmark_relay_dish", -70.0, -460.0, 30.0],
				["at", "fortifications/fort_gun_emplacement", 70.0, -400.0, 180.0],
				["at", "fortifications/fort_checkpoint", 0.0, 560.0, 0.0]]
			+ [["row", "fortifications/fort_dragon_teeth", -90.0, -300.0, 90.0, -300.0, 10.0],
				["row", "fortifications/fort_hesco_wall", -80.0, -180.0, 80.0, -180.0, 4.0]]
			+ cover(-110.0, 400.0, 110.0, 400.0, 26.0)
			+ cover(-110.0, 200.0, 110.0, 200.0, 26.0)
			+ cover(-110.0, 20.0, 110.0, 20.0, 26.0)
			+ cover(-110.0, -100.0, 110.0, -100.0, 26.0)
			+ [["row", "features/feature_rock_outcrop", -130.0, 300.0, -130.0, -200.0, 90.0],
				["row", "features/feature_rock_outcrop", 130.0, 300.0, 130.0, -200.0, 90.0]],
		"scatter": ["scatter_boulders", "scatter_alpine_ground", "scatter_alpine_snags"],
		"cams": [[0.0, 600.0, 0.0, -420.0, 56.0], [-60.0, 100.0, 60.0, -300.0, 64.0]],
	})

	out.append({
		"id": "salt_flat", "name": "Salt Flat",
		"hook": "Dead flat to the horizon, with rock islands as the only thing in the world.",
		"shape": "extreme range, islands of cover",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "G"], ["rect", 0, 0, 176, 4, "W"],
			["oval", 30, 20, 8, 6, "Y"], ["oval", 68, 44, 9, 7, "Y"],
			["oval", 110, 18, 10, 7, "Y"], ["oval", 148, 42, 8, 6, "Y"],
			["line", 0, 32, 176, 32, 1.0, "M"]],
		"recipe": {"hills_height": 1.0, "detail_height": 0.2, "smooth_passes": 4,
			"rough_height": 9.0},
		"dress": [["at", "features/feature_rock_outcrop", -460.0, -160.0, 0.0],
				["at", "features/feature_boulder_field", -430.0, -100.0, 0.0],
				["at", "features/feature_rock_spire", -380.0, -180.0, 0.0],
				["at", "features/feature_rock_outcrop", -140.0, 90.0, 40.0],
				["at", "features/feature_boulder_field", -100.0, 130.0, 0.0],
				["at", "features/feature_rock_outcrop", 190.0, -170.0, 80.0],
				["at", "features/feature_rock_spire", 230.0, -120.0, 0.0],
				["at", "features/feature_rock_outcrop", 490.0, 80.0, 120.0],
				["at", "features/feature_boulder_field", 450.0, 130.0, 0.0],
				["at", "fortifications/fort_command_bunker", 0.0, 0.0, 0.0],
				["at", "landmarks/landmark_relay_dish", 40.0, -40.0, 0.0]]
			+ [["ring", "fortifications/fort_hesco_wall", 0.0, 0.0, 70.0, 12],
				["row", "props/prop_boulder_a", -600.0, 200.0, 600.0, 200.0, 70.0],
				["row", "props/prop_boulder_c", -600.0, -200.0, 600.0, -200.0, 70.0]],
		"scatter": ["scatter_boulders"],
		"cams": [[-560.0, 40.0, 500.0, -40.0, 60.0], [0.0, 150.0, 0.0, -60.0, 64.0]],
	})

	out.append({
		"id": "marsh_boardwalk", "name": "Marsh Boardwalks",
		"hook": "Water everywhere and movement only on the planks: the most channelled map here.",
		"shape": "a graph of narrow edges",
		"px": SQUARE,
		"paint": [["rect", 0, 0, 112, 112, "B"],
			["oval", 24, 24, 12, 10, "G"], ["oval", 84, 26, 13, 11, "G"],
			["oval", 56, 56, 15, 13, "G"], ["oval", 22, 86, 12, 10, "G"],
			["oval", 88, 88, 13, 11, "G"],
			["line", 24, 24, 56, 56, 1.0, "M"], ["line", 84, 26, 56, 56, 1.0, "M"],
			["line", 22, 86, 56, 56, 1.0, "M"], ["line", 88, 88, 56, 56, 1.0, "M"],
			["line", 24, 24, 84, 26, 1.0, "M"], ["line", 22, 86, 88, 88, 1.0, "M"],
			["line", 56, 0, 56, 24, 1.0, "M"], ["line", 56, 88, 56, 112, 1.0, "M"]],
		"recipe": {"water_depth": 5.0, "water_bank": 10.0, "road_width": 5.0},
		"dress": [["at", "fortifications/fort_command_bunker", 0.0, 0.0, 0.0],
				["at", "features/feature_watchtower", -256.0, -256.0, 0.0],
				["at", "features/feature_watchtower", 224.0, -240.0, 0.0],
				["at", "features/feature_pillbox", -272.0, 240.0, 0.0],
				["at", "features/feature_pillbox", 256.0, 256.0, 0.0],
				["at", "landmarks/landmark_relay_dish", 50.0, -40.0, 20.0]]
			+ [["ring", "props/prop_sandbag_wall", 0.0, 0.0, 90.0, 10],
				["ring", "fortifications/fort_hesco_wall", -256.0, -256.0, 60.0, 8],
				["ring", "fortifications/fort_hesco_wall", 224.0, -240.0, 60.0, 8],
				["ring", "props/prop_sandbag_nest", -272.0, 240.0, 55.0, 6],
				["ring", "props/prop_sandbag_nest", 256.0, 256.0, 55.0, 6]],
		"scatter": ["scatter_alpine_ground"],
		"cams": [[-150.0, -150.0, 0.0, 0.0, 62.0], [0.0, 330.0, 0.0, -300.0, 60.0]],
	})

	out.append({
		"id": "terraced_farms", "name": "Terraced Farms",
		"hook": "Stepped flat fields up a hillside: every terrace is a lane, every ramp is a choke.",
		"shape": "a ladder of lanes",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"], ["rect", 0, 0, 128, 30, "W"],
			["rect", 0, 26, 128, 34, "Y"],
			["line", 0, 42, 128, 42, 1.0, "M"], ["line", 0, 58, 128, 58, 1.0, "M"],
			["line", 0, 74, 128, 74, 1.0, "M"], ["line", 0, 90, 128, 90, 1.0, "M"],
			["line", 30, 42, 26, 90, 1.0, "M"], ["line", 98, 42, 102, 90, 1.0, "M"],
			["rect", 46, 76, 84, 92, "U"]],
		"recipe": {"terrace_step": 5.0, "terrace_strength": 0.9, "hills_height": 10.0,
			"sketch_mountain_height": 48.0},
		"dress": cover(-460.0, -110.0, 460.0, -110.0, 30.0)
			+ cover(-460.0, 20.0, 460.0, 20.0, 30.0)
			+ cover(-460.0, 150.0, 460.0, 150.0, 30.0)
			+ [["row", "features/feature_berm", -460.0, -50.0, 460.0, -50.0, 22.0],
				["row", "features/feature_berm", -460.0, 84.0, 460.0, 84.0, 22.0],
				["at", "landmarks/landmark_clock_tower", 0.0, 260.0, 0.0],
				["at", "estates/estate_market_hall", -120.0, 290.0, 0.0]]
			+ town(["estates/estate_courtyard_wing", "estates/estate_frame_shell"],
				-380.0, 260.0, 380.0, 330.0, 2)
			+ [["at", "features/feature_rock_outcrop", -400.0, -230.0, 0.0],
				["at", "features/feature_rock_outcrop", 380.0, -220.0, 60.0]],
		"scatter": ["scatter_alpine_ground", "scatter_alpine_snags"],
		"cams": [[0.0, 330.0, 0.0, -200.0, 58.0], [-420.0, 20.0, 420.0, 20.0, 62.0]],
	})

	out.append({
		"id": "fire_breaks", "name": "Fire Breaks",
		"hook": "Dense forest cut by wide straight lanes: total cover, and four places you can see.",
		"shape": "concealment with exposed corridors",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"], ["rect", 0, 0, 128, 4, "W"],
			["line", 32, 0, 32, 96, 2.0, "M"], ["line", 96, 0, 96, 96, 2.0, "M"],
			["line", 0, 32, 128, 32, 2.0, "M"], ["line", 0, 68, 128, 68, 2.0, "M"],
			["rect", 52, 40, 76, 60, "U"]],
		"recipe": {"road_width": 10.0, "hills_height": 5.0},
		"dress": [["at", "fortifications/fort_command_bunker", 0.0, 0.0, 0.0],
				["at", "landmarks/landmark_relay_dish", -60.0, -40.0, 30.0],
				["at", "features/feature_watchtower", 60.0, 40.0, 0.0],
				["at", "fortifications/fort_checkpoint", -256.0, 330.0, 0.0]]
			+ [["ring", "fortifications/fort_hesco_wall", 0.0, 0.0, 90.0, 12]]
			+ cover(-460.0, -160.0, 460.0, -160.0, 34.0)
			+ cover(-460.0, 130.0, 460.0, 130.0, 34.0)
			+ cover(-256.0, -360.0, -256.0, 360.0, 40.0)
			+ cover(256.0, -360.0, 256.0, 360.0, 40.0),
		"scatter": ["scatter_alpine_snags", "scatter_alpine_deadwood", "scatter_alpine_ground"],
		"cams": [[-256.0, 330.0, -256.0, -330.0, 60.0], [0.0, 200.0, 0.0, -20.0, 64.0]],
	})

	out.append({
		"id": "oasis", "name": "Oasis",
		"hook": "One green ring of cover in a hundred hectares of nothing. Everyone wants it.",
		"shape": "a single island of cover",
		"px": SQUARE,
		"paint": [["rect", 0, 0, 112, 112, "G"], ["oval", 56, 56, 26, 24, "Y"],
			["oval", 56, 56, 12, 11, "B"], ["rect", 0, 0, 112, 5, "W"],
			["line", 0, 56, 112, 56, 1.0, "M"], ["line", 56, 0, 56, 112, 1.0, "M"],
			["oval", 30, 30, 7, 6, "Y"], ["oval", 86, 84, 8, 6, "Y"]],
		"recipe": {"water_depth": 4.0, "water_bank": 30.0, "hills_height": 4.0,
			"rough_height": 6.0},
		"dress": [["at", "estates/estate_market_hall", -110.0, -40.0, 20.0],
				["at", "estates/estate_courtyard_block", 90.0, 60.0, 200.0],
				["at", "landmarks/landmark_clock_tower", -60.0, 120.0, 0.0],
				["at", "features/feature_watchtower", 130.0, -110.0, 0.0]]
			+ [["ring", "fortifications/fort_hesco_wall", 0.0, 0.0, 190.0, 22],
				["ring", "props/prop_sandbag_wall", 0.0, 0.0, 130.0, 12],
				["ring", "props/prop_boulder_b", 0.0, 0.0, 250.0, 14]]
			+ cover(-400.0, -330.0, 400.0, -330.0, 44.0)
			+ cover(-400.0, 330.0, 400.0, 330.0, 44.0)
			+ [["at", "features/feature_rock_outcrop", -280.0, -260.0, 0.0],
				["at", "features/feature_rock_outcrop", 300.0, 250.0, 70.0]],
		"scatter": ["scatter_alpine_ground", "scatter_boulders"],
		"cams": [[-330.0, -330.0, 0.0, 0.0, 60.0], [0.0, 180.0, 0.0, -160.0, 64.0]],
	})

	out.append({
		"id": "sinkhole", "name": "Sinkhole",
		"hook": "A spiral road down a hole, and the only cover is the wall you are walking beside.",
		"shape": "a descending spiral",
		"px": SQUARE,
		"paint": [["rect", 0, 0, 112, 112, "G"], ["oval", 56, 56, 32, 30, "Y"],
			["oval", 56, 56, 14, 13, "G"], ["rect", 0, 0, 112, 4, "W"],
			["path", [Vector2(56, 110), Vector2(56, 86), Vector2(28, 70), Vector2(26, 44),
				Vector2(56, 30), Vector2(80, 46), Vector2(74, 64), Vector2(58, 68)], 1.5, "M"],
			["oval", 56, 56, 8, 7, "R"]],
		"recipe": {"terrace_step": 7.0, "terrace_strength": 0.9, "rough_height": 14.0},
		"dress": [["at", "landmarks/landmark_tether_anchor", 0.0, 0.0, 0.0],
				["at", "compute/compute_monolith", 60.0, 30.0, 0.0],
				["at", "fortifications/fort_command_bunker", -60.0, 20.0, 40.0]]
			+ [["ring", "props/prop_rock_slabs", 0.0, 0.0, 160.0, 14],
				["ring", "props/prop_boulder_b", 0.0, 0.0, 230.0, 16],
				["ring", "props/prop_dirt_mound", 0.0, 0.0, 110.0, 10],
				["ring", "features/feature_berm", 0.0, 0.0, 300.0, 12]]
			+ cover(-320.0, 330.0, 320.0, 330.0, 30.0)
			+ [["at", "fortifications/fort_checkpoint", 0.0, 380.0, 0.0],
				["at", "machines/machine_excavator", -200.0, 300.0, 120.0]],
		"scatter": ["scatter_boulders", "scatter_micro_terrain"],
		"cams": [[0.0, 380.0, 0.0, 0.0, 58.0], [-180.0, 120.0, 30.0, 10.0, 64.0]],
	})

	out.append({
		"id": "cliff_stair", "name": "Cliff Stair",
		"hook": "A beach, a cliff, and one zigzag up to the battery that has been shelling you.",
		"shape": "a beach assault onto a single stair",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"], ["rect", 0, 60, 128, 96, "B"],
			["rect", 0, 52, 128, 62, "Y"], ["rect", 0, 0, 128, 34, "W"],
			["rect", 0, 30, 128, 38, "G"],
			["path", [Vector2(64, 50), Vector2(44, 42), Vector2(70, 34), Vector2(58, 26)], 1.5, "M"],
			["line", 0, 20, 128, 20, 1.0, "M"], ["rect", 40, 8, 84, 22, "R"]],
		"recipe": {"water_depth": 7.0, "water_bank": 18.0, "sketch_mountain_height": 46.0,
			"sketch_blend": 12.0},
		"dress": [["at", "fortifications/fort_gun_emplacement", -60.0, -300.0, 0.0],
				["at", "fortifications/fort_gun_emplacement", 60.0, -300.0, 0.0],
				["at", "fortifications/fort_command_bunker", 0.0, -350.0, 0.0],
				["at", "features/feature_pillbox", -160.0, -260.0, 20.0],
				["at", "features/feature_pillbox", 170.0, -260.0, 340.0],
				["at", "features/feature_watchtower", 0.0, -240.0, 0.0]]
			+ [["row", "fortifications/fort_dragon_teeth", -460.0, 40.0, 460.0, 40.0, 12.0],
				["row", "fortifications/fort_razor_wire", -460.0, 70.0, 460.0, 70.0, 8.0],
				["row", "props/prop_tank_trap", -440.0, 110.0, 440.0, 110.0, 20.0],
				["row", "features/feature_berm", -440.0, -60.0, 440.0, -60.0, 34.0]]
			+ cover(-460.0, -140.0, 460.0, -140.0, 28.0)
			+ cover(-460.0, -10.0, 460.0, -10.0, 34.0),
		"scatter": ["scatter_debris", "scatter_boulders"],
		"cams": [[0.0, 150.0, 0.0, -320.0, 60.0], [-300.0, -80.0, 300.0, -80.0, 62.0]],
	})

	# ═══ MACHINE WORLD ═══════════════════════════════════════════════════════
	# The fiction this game is actually about: a rogue drone in the places
	# machines built for themselves.

	out.append({
		"id": "server_farm", "name": "Server Farm",
		"hook": "Identical halls in identical rows: you win by learning to tell them apart.",
		"shape": "regular maze, deliberately disorienting",
		"px": WIDE,
		"paint": [["rect", 0, 0, 128, 96, "G"], ["rect", 0, 0, 128, 4, "Y"],
			["line", 0, 20, 128, 20, 1.0, "M"], ["line", 0, 48, 128, 48, 1.0, "M"],
			["line", 0, 76, 128, 76, 1.0, "M"], ["line", 64, 0, 64, 96, 1.5, "M"]],
		"dress": rows("compute/compute_data_hall", -460.0, 460.0, -270.0, 4, 100.0, 30.0)
			+ [["row", "compute/compute_chiller_yard", -400.0, -200.0, 400.0, -200.0, 60.0],
				["row", "compute/compute_chiller_yard", -400.0, 100.0, 400.0, 100.0, 60.0],
				["row", "compute/compute_transformer", -440.0, -120.0, 440.0, -120.0, 50.0],
				["row", "compute/compute_generator", -440.0, 180.0, 440.0, 180.0, 60.0],
				["at", "compute/compute_monolith", 0.0, 0.0, 0.0],
				["at", "landmarks/landmark_relay_dish", 280.0, 300.0, 20.0],
				["row", "compute/compute_cable_run", -440.0, 250.0, 440.0, 250.0, 6.0]]
			+ cover(-460.0, -40.0, 460.0, -40.0, 26.0)
			+ cover(-460.0, 320.0, 460.0, 320.0, 30.0),
		"scatter": ["scatter_tech_debris"],
		"cams": [[-420.0, -160.0, 420.0, -160.0, 62.0], [0.0, 330.0, 0.0, -300.0, 60.0]],
	})

	out.append({
		"id": "launch_complex", "name": "Launch Complex",
		"hook": "A crawlerway forty metres wide runs dead straight at a gantry. No cover on it at all.",
		"shape": "a processional axis you cannot use",
		"px": LONG,
		"paint": [["rect", 0, 0, 176, 64, "G"], ["rect", 0, 0, 176, 5, "Y"],
			["rect", 0, 58, 176, 64, "Y"], ["line", 0, 32, 176, 32, 5.0, "M"],
			["oval", 150, 32, 16, 14, "U"], ["rect", 10, 40, 60, 56, "U"],
			["line", 0, 50, 176, 50, 1.0, "M"]],
		"recipe": {"road_width": 9.0, "road_falloff": 10.0},
		"dress": [["at", "landmarks/landmark_tether_anchor", 520.0, 0.0, 0.0],
				["at", "compute/compute_monolith", 420.0, -60.0, 0.0],
				["at", "industrial/industrial_gantry_crane", 440.0, 60.0, 90.0],
				["at", "features/feature_fuel_tanks", 340.0, 130.0, 0.0],
				["at", "features/feature_fuel_tanks", 250.0, 140.0, 0.0],
				["at", "industrial/industrial_plant_office", -420.0, 110.0, 0.0],
				["at", "industrial/industrial_hangar_arch", -260.0, 130.0, 0.0],
				["row", "features/feature_power_pylon", -400.0, -140.0, 400.0, -140.0, 110.0]]
			+ [["row", "props/prop_concrete_blocks", -600.0, -50.0, 600.0, -50.0, 22.0],
				["row", "props/prop_concrete_blocks", -600.0, 50.0, 600.0, 50.0, 22.0]]
			+ cover(-620.0, -110.0, 620.0, -110.0, 30.0)
			+ cover(-620.0, 110.0, 620.0, 110.0, 30.0),
		"scatter": ["scatter_tech_debris"],
		"cams": [[-560.0, 0.0, 560.0, 0.0, 58.0], [0.0, 130.0, 460.0, 10.0, 62.0]],
	})

	out.append({
		"id": "dish_array", "name": "Dish Array",
		"hook": "Forty dishes on a plain, each one cover, a landmark and a thing worth taking.",
		"shape": "many equal objectives, no centre",
		"px": SQUARE,
		"paint": [["rect", 0, 0, 112, 112, "G"], ["rect", 0, 0, 112, 5, "Y"],
			["line", 0, 56, 112, 56, 1.0, "M"], ["line", 56, 0, 56, 112, 1.0, "M"],
			["line", 0, 24, 112, 24, 1.0, "M"], ["line", 0, 88, 112, 88, 1.0, "M"]],
		"dress": [["grid", "compute/compute_satellite_dish", -420.0, -420.0, 420.0, 420.0, 0.0, 70.0],
				["at", "landmarks/landmark_relay_dish", 0.0, 0.0, 0.0],
				["at", "compute/compute_data_hall", -320.0, 340.0, 0.0],
				["at", "compute/compute_generator", 300.0, 340.0, 0.0],
				["row", "compute/compute_cable_run", -420.0, 250.0, 420.0, 250.0, 6.0],
				["row", "compute/compute_transformer", -400.0, -330.0, 400.0, -330.0, 70.0]]
			+ cover(-420.0, -180.0, 420.0, -180.0, 34.0)
			+ cover(-420.0, 130.0, 420.0, 130.0, 34.0),
		"scatter": ["scatter_tech_debris", "scatter_alpine_ground"],
		"cams": [[-380.0, 60.0, 380.0, -60.0, 62.0], [0.0, 330.0, 0.0, -300.0, 60.0]],
	})

	return out
