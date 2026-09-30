extends "res://tools/probe_place_mutaha_wip.gd"

# ─────────────────────────────────────────────
# MUTAHA CORE — relays out the central island of the WIP copy as one thing: the
# machines' compute hub, rather than eleven small groups scattered down 400 m
# of ground with nothing between them.
#
#   godot --headless --path . --script res://tools/probe_place_mutaha_core.gd
#   → scratchpad/mutaha_core_nodes.txt, to append to maps/mutaha_wip_level.tscn
#
# Writes a text file and nothing else, like the tool it extends.
#
# THE ISLAND ALREADY HAS A GRID. The sketch paints it grey, so the generator
# levelled it into 34 × 26 m blocks on the town's own 41 × 33 m period, with a
# 7 m street down the spine at x = -44.5 and a cross street every 33 m. The old
# dressing ignored all of it and sat in a line down the east side. This puts the
# hub ON the grid, which is both what the ground is shaped for and the reason it
# will read as built rather than dropped.
#
#   column A, x = -65   the old town. Four houses survive on it (Lot068, 079,
#                       089, 111) and they stay; the plant fills the gaps.
#   column B, x = -24   the machines' side: switchyard, generators, halls, the
#                       server garden, cooling, docks.
#   the spine, x = -44.5  the avenue, with the obelisk standing in it at the
#                       island's middle where the two sides meet.
#
# North to south it is meant to read as one sequence: uplink, power, halls,
# the core, cooling, logistics. A player walking the island passes through the
# whole process.
#
# WHAT IS LEFT ALONE: ListeningPost on the north tip, LastStand at the west
# bridgehead, and the Factory, IslandSouthWall and BridgeOutSouth on the south
# tip. Their ground is reserved before anything is placed.
# ─────────────────────────────────────────────

const OUT_CORE := "C:/Users/User/AppData/Local/Temp/claude/D--Godot-Games-roboto/adb53eea-3f20-4c1a-a10d-7b2d1903ab73/scratchpad/mutaha_core_nodes.txt"

## The island's block grid, from the sketch: 34 × 26 m blocks, 41 × 33 m period.
const COL_A := -65.0
const COL_B := -24.0
const SPINE := -44.5
## Block centre for row m is 33 * m + 13.
const ROW := {"n2": -152.0, "n1": -119.0, "h1": -86.0, "h2": -53.0,
		"core": -20.0, "c1": 13.0, "c2": 46.0, "d1": 79.0, "d2": 112.0}


func _initialize() -> void:
	data = load(DATA)
	if data == null or data.cells_x == 0:
		print("FAIL  no terrain at %s — bake it first" % DATA)
		quit(1)
		return
	n = data.cells_x + 1
	half = data.cells_x * data.cell_size * 0.5
	print("   %s: %d lots, %d bridges" % [DATA.get_file(), data.lots.size(), data.bridges.size()])

	# Ground that belongs to something already. The four town houses come out of
	# the lot list; the rest are groups this pass does not touch.
	for l in data.lots:
		var c: Vector2 = l.centre
		if c.x > -110.0 and c.x < 30.0 and c.y > -240.0 and c.y < 240.0:
			taken.append([c, (l.size as Vector2) * 0.5, 0.0, "town lot"])
	_reserve_bridges()
	for keep: Array in [
			[Vector2(-50.0, -196.0), Vector2(22.0, 28.0), "ListeningPost"],
			[Vector2(-60.0, -20.0), Vector2(9.0, 10.0), "LastStand"],
			[Vector2(-48.0, 182.0), Vector2(64.0, 54.0), "the south tip"]]:
		taken.append([keep[0], keep[1], 0.0, keep[2]])

	_power()
	_halls()
	_plaza()
	_cooling()
	_docks()
	_avenue()

	var f := FileAccess.open(OUT_CORE, FileAccess.WRITE)
	if f == null:
		print("FAIL  could not write %s" % OUT_CORE)
		quit(1)
		return
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("   %d piece(s) placed, %d refused; wrote %s" % [placed, refused, OUT_CORE])
	quit()


# ── power: where the island's current comes from ─────────────────────────────

func _power() -> void:
	group("NavigationRegion3D/Dressing", "CorePower")
	var p := "NavigationRegion3D/Dressing/CorePower"
	# The switchyard, on the first block wide enough to hold one.
	put(p, "Substation", "dress_industrial_substation", COL_B, ROW.n2)
	put(p, "Transformer1", "dress_compute_transformer", -38.0, ROW.n2 - 7.0)
	put(p, "Transformer2", "dress_compute_transformer", -38.0, ROW.n2 + 7.0)
	put(p, "Cabinet1", "dress_compute_network_cabinet", -11.0, ROW.n2 - 8.0)
	put(p, "Mast1", "dress_fort_floodlight_mast", -11.0, ROW.n2 + 9.0)
	put(p, "Poles1", "dress_prop_power_pole", -44.0, ROW.n2 - 12.0)
	put(p, "Poles2", "dress_prop_power_pole", -44.0, ROW.n2 + 12.0)
	# The generator hall and its fuel, a block south.
	put(p, "Generator1", "dress_compute_generator", -30.0, ROW.n1 - 8.0)
	put(p, "Generator2", "dress_compute_generator", -30.0, ROW.n1 + 1.0)
	put(p, "FuelTanks", "dress_feature_fuel_tanks", -16.0, ROW.n1 + 8.0)
	put(p, "Transformer3", "dress_compute_transformer", -38.0, ROW.n1 + 9.0)
	put(p, "Cabinet2", "dress_compute_network_cabinet", -12.0, ROW.n1 - 8.0)
	# The trunk south, toward the halls.
	for i in 2:
		put(p, "Trunk%d" % (i + 1), "dress_compute_cable_run", -34.0 + i * 5.0, -103.0)


# ── halls: the mass of the thing ─────────────────────────────────────────────

func _halls() -> void:
	group("NavigationRegion3D/Dressing", "CoreHalls")
	var p := "NavigationRegion3D/Dressing/CoreHalls"
	put(p, "DataHall1", "dress_compute_data_hall", COL_B, ROW.h1)
	for i in 3:
		put(p, "Cooling%d" % (i + 1), "dress_compute_cooling_unit", -36.0 + i * 8.0, -70.0)
	put(p, "Cabinet1", "dress_compute_network_cabinet", -10.0, ROW.h1 - 10.0)
	put(p, "HallFeed", "dress_compute_cable_run", -38.0, ROW.h1 - 7.0)
	# The server garden: racks standing in the open, which is the image the
	# island had before and the one thing about it worth keeping.
	for i in 9:
		var gx: float = -36.0 + (i % 3) * 12.0
		var gz: float = ROW.h2 - 9.0 + floori(i / 3.0) * 9.0
		put(p, "RackRow%d" % (i + 1), "dress_compute_rack_row", gx, gz)
	put(p, "RacksToppled", "dress_compute_racks_toppled", -11.0, ROW.h2 + 15.0)
	put(p, "Cabinet2", "dress_compute_network_cabinet", -39.0, ROW.h2 + 10.0)
	# Cooling beside the core. It wanted to go on the town side, opposite the
	# obelisk — but the west bridge lands on that block and its ramp reaches
	# back to x = -78, so between the ramp and the sandbags there is nothing
	# left of it. The machines' side has the room.
	put(p, "ChillerYard1", "dress_compute_chiller_yard", -20.0, ROW.core)
	for i in 2:
		put(p, "ChillerUnit%d" % (i + 1), "dress_compute_cooling_unit", -30.0 + i * 9.0, -38.0)


# ── the plaza: the obelisk, on the axis instead of off it ────────────────────

func _plaza() -> void:
	group("NavigationRegion3D/Dressing", "CorePlaza")
	var p := "NavigationRegion3D/Dressing/CorePlaza"
	# It stood at (-10, -22), hard against the island's east bank, where it read
	# as one more machine in a row. On the spine at the island's middle it is
	# what the road leads to from either bridge.
	# THE NODE GOES AT -41, NOT -44.5. The piece's mass runs from 16 m west of
	# its origin to 8.25 m east of it, so an origin on the spine puts the thing
	# itself 4 m west of the spine and into the sandbags. At -41 the obelisk
	# stands centred on the carriageway, which is where it belongs.
	put(p, "Obelisk", "dress_compute_obelisk", -41.0, ROW.core)
	# The monoliths keep to the machines' side and to the kerb. West of the
	# obelisk is the old town and there is no room for them there.
	var k := 0
	for r: Array in [[-27.0, -33.0], [-27.0, -7.0], [-41.0, -43.0], [-41.0, 5.0]]:
		k += 1
		put(p, "Monolith%d" % k, "dress_compute_monolith", float(r[0]), float(r[1]), 90.0)
	# Cable runs into the foot of it from the halls and from the cooling side.
	# One feed across the street south of the plaza. There is no room for a
	# second one north of it: a cable run is 12.6 m end to end, the service
	# street is 7 m wide, and the chiller units and the rack rows have the rest.
	# The trunk from the generators comes down the hall side instead.
	put(p, "Feed2", "dress_compute_cable_run", -30.0, -3.0, 90.0)
	put(p, "Mast", "dress_fort_floodlight_mast", -33.0, -33.0)
	put(p, "Cabinet", "dress_compute_network_cabinet", -33.0, -7.0)


# ── cooling: the canopies that replaced the tracker rows ─────────────────────

func _cooling() -> void:
	group("NavigationRegion3D/Dressing", "CoreCooling")
	var p := "NavigationRegion3D/Dressing/CoreCooling"
	# The east bridge lands on this island at x = 4 and its ramp reaches back to
	# about x = -18, so the block behind it stays clear: arriving over a bridge
	# into a yard full of machinery is how the west bridgehead used to be, and
	# that was the thing worth fixing.
	put(p, "GateCabinet", "dress_compute_network_cabinet", -38.0, ROW.c1 - 6.0)
	put(p, "GateCable", "dress_compute_cable_run", -34.0, ROW.c1 + 6.0)
	put(p, "GateMast", "dress_fort_floodlight_mast", -38.0, ROW.c1 + 12.0)
	# THE SWAP. solar_tracker_row is 20 m long and 2.8 m tall with a solid
	# collider: a wall across an island that is only 90 m wide. solar_canopy is
	# the same array carried on legs 7 m up, so the squad walks under it and the
	# yard underneath is still a yard. Turned 90 degrees to follow the block,
	# which leaves it overhanging the street at each end — that is the point.
	# Placed loose, because everything below is meant to be below it.
	put(p, "Canopy1", "dress_solar_canopy", COL_B, 48.0, 90.0, NAN, 0.6, true)
	put(p, "Inverter1", "dress_solar_inverter_skid", -37.0, 40.0)
	put(p, "Inverter2", "dress_solar_inverter_skid", -37.0, 56.0)
	put(p, "Battery1", "dress_solar_battery_container", -16.0, 40.0)
	put(p, "Battery2", "dress_solar_battery_container", -16.0, 56.0)
	put(p, "Cabinet", "dress_compute_network_cabinet", -10.0, 48.0)
	# The chiller plant opposite, in the gap the town leaves on column A.
	put(p, "ChillerYard2", "dress_compute_chiller_yard", COL_A, ROW.c2)
	put(p, "Cooling1", "dress_compute_cooling_unit", -78.0, ROW.c2 - 8.0)
	put(p, "Cooling2", "dress_compute_cooling_unit", -78.0, ROW.c2 + 8.0)
	put(p, "Pipes", "dress_prop_concrete_pipes", -52.0, ROW.c2 + 9.0)


# ── docks: what leaves the island ────────────────────────────────────────────

func _docks() -> void:
	group("NavigationRegion3D/Dressing", "CoreDocks")
	var p := "NavigationRegion3D/Dressing/CoreDocks"
	var k := 0
	for dx: float in [-36.0, -14.0]:
		for dz: float in [ROW.d1 - 8.0, ROW.d1 + 8.0]:
			k += 1
			put(p, "Dock%d" % k, "dress_solar_drone_dock", dx, dz)
	put(p, "DockCabinet", "dress_compute_network_cabinet", -25.0, ROW.d1)
	put(p, "DockMast", "dress_fort_floodlight_mast", -25.0, ROW.d1 + 14.0)
	# The second canopy stands over the town side's yard, with two more docks
	# under it — a broken one, because the island has been fought over once.
	put(p, "Canopy2", "dress_solar_canopy_broken", COL_A, ROW.d1, 90.0, NAN, 0.6, true)
	for dx: float in [-75.0, -57.0]:
		k += 1
		put(p, "Dock%d" % k, "dress_solar_drone_dock", dx, ROW.d1 - 6.0)
	put(p, "Battery3", "dress_solar_battery_container", -66.0, ROW.d1 + 8.0)
	# The last block before the wall: the hub's back gate.
	put(p, "Cabinet2", "dress_compute_network_cabinet", -30.0, ROW.d2 - 6.0)
	put(p, "Transformer", "dress_compute_transformer", -18.0, ROW.d2 - 6.0)
	put(p, "Cable", "dress_compute_cable_run", -24.0, ROW.d2 + 8.0)


# ── the avenue: monoliths lining the spine, as waymarkers ────────────────────

func _avenue() -> void:
	group("NavigationRegion3D/Dressing", "CoreAvenue")
	var p := "NavigationRegion3D/Dressing/CoreAvenue"
	# Off the kerb on alternate sides, never in the 7 m carriageway: the road
	# is the island's only through route and the squad has to be able to use it.
	var k := 0
	for z: float in [-140.0, -105.0, -70.0, -2.0, 30.0, 66.0, 110.0]:
		k += 1
		var x: float = -51.0 if k % 2 == 1 else -38.0
		put(p, "Way%d" % k, "dress_compute_monolith", x, z, 90.0)
