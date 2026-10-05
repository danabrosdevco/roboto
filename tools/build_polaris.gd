extends SceneTree

# ─────────────────────────────────────────────
# BUILD POLARIS — assembles maps/polaris_art.tscn and maps/polaris_level.tscn
# from the suburban, street, suburbs and polaris block families.
#
#   godot --headless --path . --script res://tools/build_polaris.gd
#   godot --headless --path . --script res://tools/build_polaris.gd -- --force
#
# THE LAYOUT IS THIS FILE AND NOTHING ELSE. There is no painted sketch and no
# terrain recipe, because the site has no terrain: a mall is a graded slab,
# and the only ground feature on the real one is the detention basin, which is
# a block. That makes this the one level in the project whose shape is
# entirely in a list of transforms, and the reason it can be is that the
# geometry was built as a kit first.
#
# IT IS MODELLED ON POLARIS FASHION PLACE, COLUMBUS, and the four things that
# were worth copying off it are:
#
#   - the mall is ONE MASS with the anchors as lobes, not a row of buildings;
#   - a CLOSED RING ROAD loops round it as a rounded rectangle, so there is no
#     corner of the site a vehicle cannot reach and no straight longer than
#     about 150 m;
#   - the parking between them is A FAN OF AISLES, each with an island its
#     whole length, which is the only thing breaking up 400 m of asphalt;
#   - THE RESTAURANTS ARE OUTSIDE THE LOOP in a row of detached pads with open
#     ground between them. That row is the best infantry ground on the site
#     and it is the reason this is a map and not a car park.
#
# WHAT IT DOES NOT DO: bake the navmesh. Nothing here does.
#
#   BAKE_ONLY=1 LEVEL=res://maps/polaris_level.tscn godot --path . \
#       --script res://tools/probe_nav_hillfort.gd
# ─────────────────────────────────────────────

const ART := "res://maps/polaris_art.tscn"
const LEVEL := "res://maps/polaris_level.tscn"

const B_SUBURBAN := "res://maps/blocks/suburban/%s.tscn"
const B_STREETS := "res://maps/blocks/streets/%s.tscn"
const B_SUBURBS := "res://maps/blocks/suburbs/%s.tscn"
const B_POLARIS := "res://maps/blocks/polaris/%s.tscn"

## The ring road's rounded rectangle. The corner piece is 90° on a 50 m
## centreline with its origin AT THE CIRCLE CENTRE, so the four corners go in
## at the four corners of this rectangle and the straights fill between them.
const RING_X := 150.0
const RING_Y := 110.0
const RING_R := 50.0

var _cache := {}


func _initialize() -> void:
	await process_frame
	var force := OS.get_cmdline_user_args().has("--force")
	for p: String in [ART, LEVEL]:
		if FileAccess.file_exists(ProjectSettings.globalize_path(p)) and not force:
			print("SKIP  %s exists — pass --force to rebuild it." % p)
			quit()
			return

	var art := Node3D.new()
	art.name = "PolarisArt"
	root.add_child(art)
	art.owner = null

	_ground(art)
	_ring_road(art)
	_mall(art)
	_parking(art)
	_outlots(art)
	_power_centre(art)
	_housing(art)

	var placed := _own(art, art)
	var packed := PackedScene.new()
	var err := packed.pack(art)
	if err != OK:
		print("FAIL  could not pack the art scene (%s)" % error_string(err))
		quit(1)
		return
	err = ResourceSaver.save(packed, ART)
	if err != OK:
		print("FAIL  could not save %s (%s)" % [ART, error_string(err)])
		quit(1)
		return
	print("      %s  %d pieces" % [ART.get_file(), placed])

	_write_level()
	print("      %s" % LEVEL.get_file())
	print("BUILD POLARIS DONE")
	quit()


## Instance ROOTS are owned by the art root and nothing inside them is.
##
## This is the rule that was learned the expensive way on the art/level split:
## a packed scene writes every node its root owns, so setting the owner of an
## instance's INTERNALS writes them out as declared nodes, pins them, and
## quietly stops edits to the block in maps/blocks reaching the level that
## instances it. Hillfort's 96 prefabs became 2353 node entries that way.
func _own(node: Node, root_node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if c.scene_file_path != "":
			c.owner = root_node
			n += 1
			continue
		c.owner = root_node
		n += _own(c, root_node)
	return n


## One instance of `path`, at x,z metres, yawed `yaw` degrees, under `parent`.
func _put(parent: Node3D, path: String, x: float, z: float, yaw: float = 0.0, y: float = 0.0, name := "") -> Node3D:
	if not _cache.has(path):
		var packed := load(path) as PackedScene
		if packed == null:
			# Say which one and keep going: a layout that silently loses a
			# building is worse than one that is loudly missing it.
			push_warning("build_polaris: no prefab at %s — nothing placed" % path)
			_cache[path] = null
			return null
		_cache[path] = packed
	if _cache[path] == null:
		return null
	var inst := (_cache[path] as PackedScene).instantiate() as Node3D
	inst.name = name if name != "" else path.get_file().get_basename()
	parent.add_child(inst)
	inst.position = Vector3(x, y, z)
	inst.rotation_degrees = Vector3(0.0, yaw, 0.0)
	return inst


func _group(parent: Node3D, name: String) -> Node3D:
	var g := Node3D.new()
	g.name = name
	parent.add_child(g)
	return g


# ── Which way round everything goes ──────────────────────────────────────────
#
# FUNCGODOT MAPS QUAKE (x, y, z) TO GODOT (y, z, x). Every consequence of that
# is written here once, because guessing it at each of two hundred call sites
# is how the first assembly of this map came out with its ring road at right
# angles to its own corners.
#
#   - a block built ALONG ITS MAP X runs along GODOT'S Z. So a road laid with
#     no rotation runs north-south on this site, not east-west.
#   - a block whose FRONT is its map +Y faces GODOT'S +X, which is east here.
#
# +Z is south on this site, because the frontage and the restaurant row are
# on the +Z side and that is the way a player arrives.

## A piece that runs along its own map X, laid along the site's X or Z.
const ALONG_X := 90.0
const ALONG_Z := 0.0
## A piece whose front is its map +Y, turned to face each way.
const FACE_EAST := 0.0
const FACE_NORTH := 90.0
const FACE_WEST := 180.0
const FACE_SOUTH := 270.0


# ── The site ─────────────────────────────────────────────────────────────────

## The site it all stands on: the car park as ONE slab, and grass round it.
##
## The lot was nine asphalt fields in a 3 x 3 to start with, which put the
## subdivision and the church on a car park. The ground under a building is
## most of what tells you what kind of place you are in.
func _ground(art: Node3D) -> void:
	var g := _group(art, "Ground")
	_put(g, B_POLARIS % "polaris_lot_main", 0.0, 0.0, 0.0, 0.0, "Lot")
	# Grass fields butted to the lot's four edges. Same top height, so every
	# join is a texture change and not a step for anything to catch on.
	for j in 2:
		var s: float = -1.0 if j == 0 else 1.0
		_put(g, B_POLARIS % "polaris_ground_grass", -130.0, s * 280.0, 0.0, 0.0, "GrassZ_%d_a" % j)
		_put(g, B_POLARIS % "polaris_ground_grass", 130.0, s * 280.0, 0.0, 0.0, "GrassZ_%d_b" % j)
		_put(g, B_POLARIS % "polaris_ground_grass", s * 330.0, -100.0, 90.0, 0.0, "GrassX_%d_a" % j)
		_put(g, B_POLARIS % "polaris_ground_grass", s * 330.0, 100.0, 90.0, 0.0, "GrassX_%d_b" % j)
## Godot sends +X +Z to +X -Z and not to -X +Z.
func _ring_road(art: Node3D) -> void:
	var g := _group(art, "RingRoad")
	var corners: Array = [
		[RING_X, RING_Y, 0.0],
		[-RING_X, RING_Y, 270.0],
		[-RING_X, -RING_Y, 180.0],
		[RING_X, -RING_Y, 90.0],
	]
	for i in corners.size():
		var c: Array = corners[i]
		_put(g, B_POLARIS % "polaris_ring_corner", c[0], c[1], c[2], 0.0, "Corner_%d" % i)
	# The straights. The two that run across the site's X are turned ALONG_X;
	# the two that run up its Z are left alone.
	var along_x := int(round((RING_X * 2.0) / 32.0))
	for s: float in [-1.0, 1.0]:
		for i in along_x:
			var x := -RING_X + (i + 0.5) * (RING_X * 2.0 / along_x)
			_put(g, B_STREETS % "street_road_two_lane", x, s * (RING_Y + RING_R), ALONG_X, 0.0,
					"RingX_%s_%d" % ["S" if s > 0.0 else "N", i])
	var along_z := int(round((RING_Y * 2.0) / 32.0))
	for s: float in [-1.0, 1.0]:
		for i in along_z:
			var z := -RING_Y + (i + 0.5) * (RING_Y * 2.0 / along_z)
			_put(g, B_STREETS % "street_road_two_lane", s * (RING_X + RING_R), z, ALONG_Z, 0.0,
					"RingZ_%s_%d" % ["E" if s > 0.0 else "W", i])
	for i in 16:
		var a := TAU * i / 16.0
		_put(g, B_SUBURBAN % "suburban_lot_light",
				cos(a) * (RING_X + RING_R + 7.0), sin(a) * (RING_Y + RING_R + 7.0), 0.0, 0.0,
				"RingLight_%d" % i)


## THE MALL: two wings side by side along the site's X with an anchor pushed
## out of each end, the glazed court facing the car park to the south, and the
## service docks on the north where nobody arrives. One mass.
func _mall(art: Node3D) -> void:
	var g := _group(art, "Mall")
	_put(g, B_POLARIS % "polaris_mall_wing", -38.0, 0.0, ALONG_X, 0.0, "WingWest")
	_put(g, B_POLARIS % "polaris_mall_wing", 38.0, 0.0, ALONG_X, 0.0, "WingEast")
	_put(g, B_SUBURBAN % "suburban_mall_anchor", -108.0, 0.0, FACE_WEST, 0.0, "AnchorWest")
	_put(g, B_SUBURBAN % "suburban_mall_anchor", 108.0, 0.0, FACE_EAST, 0.0, "AnchorEast")
	_put(g, B_SUBURBAN % "suburban_mall_entry", 0.0, 34.0, FACE_SOUTH, 0.0, "EntryCourt")
	_put(g, B_SUBURBAN % "suburban_service_dock", -40.0, -30.0, FACE_NORTH, 0.0, "ServiceDock")
	_put(g, B_SUBURBAN % "suburban_service_dock", 52.0, -30.0, FACE_NORTH, 0.0, "ServiceDockEast")
	# The cinema and the deck, inside the loop at the two free corners.
	_put(g, B_POLARIS % "polaris_cinema", -120.0, 84.0, FACE_SOUTH, 0.0, "Cinema")
	_put(g, B_POLARIS % "polaris_parking_garage", 128.0, 74.0, ALONG_X, 0.0, "Garage")
	_put(g, B_SUBURBAN % "suburban_big_box", 112.0, -74.0, FACE_NORTH, 0.0, "Fieldhouse")


## THE PARKING FAN, and the cars in it.
##
## THE CAR ROWS ARE THE POINT OF THIS PASS. The first assembly gave the mall
## four hundred metres of flat asphalt with nothing on it taller than a kerb,
## and a squad crossing that had no decision to make and nowhere to make it.
## A parked car is 1.45 m: over the 1.2 m a standing cover point probes at and
## under a head, so a row of them is cover you fire over from a crouch and get
## shot over from a stand. The lot nearest the doors is packed, the far corners
## are emptying, and the gradient between those is the map telling a player
## where it is safe to cross.
func _parking(art: Node3D) -> void:
	var g := _group(art, "Parking")
	var cars := _group(art, "ParkedCars")
	for i in 5:
		var z := 58.0 + i * 20.0
		var fan := (i - 2) * 2.5
		for s: float in [-1.0, 1.0]:
			var yaw: float = ALONG_X + s * fan
			_put(g, B_POLARIS % "polaris_aisle_long", s * 34.0, z, yaw, 0.0,
					"SouthAisle_%d_%s" % [i, "E" if s > 0.0 else "W"])
			# A row of cars down each side of every aisle. The near aisles are
			# full and the far ones are not, which is what a car park does.
			var full: bool = i < 3
			for e: float in [-1.0, 1.0]:
				_put(cars, B_POLARIS % ("lot_car_row" if full else "lot_car_row_sparse"),
						s * 34.0 + e * 0.0, z + e * 4.3, yaw, 0.0,
						"SouthCars_%d_%s_%s" % [i, "E" if s > 0.0 else "W", "a" if e > 0.0 else "b"])
	for i in 3:
		var z := -58.0 - i * 20.0
		for s: float in [-1.0, 1.0]:
			var yaw: float = ALONG_X - s * (i - 1) * 3.0
			_put(g, B_POLARIS % "polaris_aisle_long", s * 36.0, z, yaw, 0.0,
					"NorthAisle_%d_%s" % [i, "E" if s > 0.0 else "W"])
			for e: float in [-1.0, 1.0]:
				_put(cars, B_POLARIS % "lot_car_row_sparse", s * 36.0, z + e * 4.3, yaw, 0.0,
						"NorthCars_%d_%s_%s" % [i, "E" if s > 0.0 else "W", "a" if e > 0.0 else "b"])
	for s: float in [-1.0, 1.0]:
		for i in 3:
			_put(g, B_POLARIS % "polaris_aisle_long", s * (152.0 + i * 20.0), 0.0, ALONG_Z, 0.0,
					"EndAisle_%s_%d" % ["E" if s > 0.0 else "W", i])
			for e: float in [-1.0, 1.0]:
				_put(cars, B_POLARIS % "lot_car_row_sparse", s * (152.0 + i * 20.0) + e * 4.3, 0.0, ALONG_Z, 0.0,
						"EndCars_%s_%d_%s" % ["E" if s > 0.0 else "W", i, "a" if e > 0.0 else "b"])
	# The two basins, wedged into the parking where the real ones are.
	_put(g, B_SUBURBS % "suburb_retention_pond", -158.0, 126.0, 20.0, 0.0, "BasinWest")
	_put(g, B_SUBURBS % "suburb_retention_pond", 168.0, -126.0, 200.0, 0.0, "BasinEast")
	# Things in the lot that are neither a car nor a kerb. Every one of these
	# is between waist and head height on purpose: a car park's real cover is
	# all accidental, and this is the accident.
	for i in 6:
		_put(g, B_SUBURBAN % "suburban_cart_corral", -80.0 + i * 32.0, 48.0, ALONG_X, 0.0, "Corral_%d" % i)
	for i in 5:
		_put(g, B_POLARIS % "lot_planter_bed", -112.0 + i * 56.0, 74.0, ALONG_X, 0.0, "Planter_%d" % i)
	for i in 4:
		_put(g, B_POLARIS % "lot_planter_bed", -96.0 + i * 64.0, 134.0, ALONG_X + 4.0, 0.0, "PlanterS_%d" % i)
	for i in 3:
		_put(g, B_POLARIS % "lot_sign_cluster", -92.0 + i * 92.0, 96.0, 0.0, 0.0, "AisleSign_%d" % i)
	# The marquee: a building-sized thing in the middle of open ground, which
	# makes it the obvious objective and the obvious ambush at the same time.
	_put(g, B_POLARIS % "lot_event_marquee", 10.0, 116.0, ALONG_X + 6.0, 0.0, "Marquee")
	_put(g, B_POLARIS % "lot_food_pavilion", -58.0, 52.0, ALONG_X, 0.0, "FoodPavilion")
	_put(g, B_POLARIS % "lot_charging_bank", 88.0, 56.0, ALONG_X, 0.0, "Chargers")
	_put(g, B_POLARIS % "lot_garden_centre", 150.0, -52.0, FACE_WEST, 0.0, "GardenCentre")
	for i: int in [0, 1]:
		_put(g, B_POLARIS % "lot_snow_pile", -186.0 + i * 372.0, 96.0 - i * 190.0, 0.0, 0.0, "Heap_%d" % i)
	for i in 3:
		_put(g, B_POLARIS % "lot_dumpster_corral", -70.0 + i * 108.0, -46.0, FACE_SOUTH, 0.0, "Bins_%d" % i)
	_put(g, B_POLARIS % "lot_valet_canopy", -26.0, 44.0, FACE_SOUTH, 0.0, "Valet")
	for i in 12:
		var a := TAU * i / 12.0
		_put(g, B_SUBURBAN % "suburban_lot_light", cos(a) * 118.0, 40.0 + sin(a) * 64.0, 0.0, 0.0,
				"LotLight_%d" % i)
	for i in 4:
		_put(g, B_POLARIS % "lot_transit_shelter", -120.0 + i * 80.0, RING_Y + RING_R + 10.0, FACE_NORTH, 0.0,
				"Shelter_%d" % i)


## THE RESTAURANT ROW and the other outlots, OUTSIDE the loop along the south
## frontage, each a detached pad with open ground between. All of them face
## north, back at the mall, because that is where their car parks are — which
## means a squad coming off the frontage arrives at the BACK of the row.
func _outlots(art: Node3D) -> void:
	var g := _group(art, "Outlots")
	var z := RING_Y + RING_R + 52.0
	_put(g, B_POLARIS % "polaris_restaurant_casual", -150.0, z, FACE_NORTH, 0.0, "Fridays")
	_put(g, B_POLARIS % "polaris_restaurant_upscale", -72.0, z + 4.0, FACE_NORTH, 0.0, "Steakhouse")
	_put(g, B_POLARIS % "polaris_restaurant_fast", -8.0, z, FACE_NORTH, 0.0, "FastA")
	_put(g, B_POLARIS % "polaris_restaurant_fast", 28.0, z, FACE_NORTH, 0.0, "FastB")
	_put(g, B_POLARIS % "polaris_patio", 52.0, z - 12.0, ALONG_X, 0.0, "Patio")
	_put(g, B_POLARIS % "polaris_bank_outlot", 104.0, z, FACE_NORTH, 0.0, "Bank")
	_put(g, B_SUBURBAN % "suburban_drive_thru", 162.0, z - 2.0, FACE_NORTH, 0.0, "DriveThru")
	_put(g, B_SUBURBAN % "suburban_gas_canopy", -216.0, z + 6.0, ALONG_X, 0.0, "Fuel")
	# The frontage arterial beyond them, and the walk along the row.
	for i in 14:
		_put(g, B_STREETS % "street_road_turn_lane", -208.0 + i * 32.0, z + 44.0, ALONG_X, 0.0, "Frontage_%d" % i)
	for i in 8:
		_put(g, B_STREETS % "street_sidewalk_run", -176.0 + i * 32.0, z - 26.0, ALONG_X, 0.0, "RowWalk_%d" % i)
	for i in 5:
		_put(g, B_STREETS % "street_lot_entry_throat", -140.0 + i * 70.0, z - 40.0, 180.0, 0.0, "Throat_%d" % i)
	_put(g, B_SUBURBAN % "suburban_pylon_sign", -4.0, z + 30.0, FACE_NORTH, 0.0, "Pylon")
	_put(g, B_SUBURBAN % "suburban_entry_monument", 60.0, RING_Y + RING_R + 16.0, ALONG_X, 0.0, "Monument")
	_put(g, B_SUBURBS % "suburb_billboard", 206.0, z + 36.0, ALONG_X, 0.0, "Billboard")
	for i in 5:
		_put(g, B_STREETS % "street_signal_mast", -160.0 + i * 70.0, z + 36.0, FACE_NORTH, 0.0, "Signal_%d" % i)


## The power centre across the arterial to the west: the big boxes, a strip,
## the storage lanes and an office. Everything here faces east, back toward
## the mall, for the same reason the row faces north.
func _power_centre(art: Node3D) -> void:
	var g := _group(art, "PowerCentre")
	var x := -(RING_X + RING_R + 96.0)
	_put(g, B_SUBURBAN % "suburban_big_box", x, -46.0, FACE_EAST, 0.0, "BigBoxNorth")
	_put(g, B_SUBURBAN % "suburban_retail_strip", x - 12.0, 64.0, FACE_EAST, 0.0, "Strip")
	_put(g, B_SUBURBS % "suburb_self_storage", x - 6.0, -158.0, ALONG_X, 0.0, "Storage")
	_put(g, B_SUBURBS % "suburb_office_lowrise", x + 2.0, 168.0, FACE_EAST, 0.0, "Office")
	for i in 4:
		_put(g, B_POLARIS % "polaris_aisle_long", x + 64.0, -96.0 + i * 40.0, ALONG_Z, 0.0, "PCAisle_%d" % i)
	for i in 10:
		_put(g, B_STREETS % "street_road_four_lane", x + 92.0, -128.0 + i * 32.0, ALONG_Z, 0.0, "Sancus_%d" % i)


## The subdivision behind the mall to the north, which is where the map stops
## being a car park: head-high fences, 6 m gaps and no sightline longer than
## a street. The two rows face each other across their street and their back
## fences meet in the middle.
func _housing(art: Node3D) -> void:
	var g := _group(art, "Housing")
	var z := -(RING_Y + RING_R + 62.0)
	for i in 8:
		var x := -130.0 + i * 34.0
		var kind: String = ["suburb_house_ranch", "suburb_house_two_story", "suburb_house_split"][i % 3]
		_put(g, B_SUBURBS % kind, x, z - 22.0, FACE_SOUTH, 0.0, "House_%d" % i)
		_put(g, B_SUBURBS % kind, x + 17.0, z - 72.0, FACE_NORTH, 0.0, "HouseBack_%d" % i)
		_put(g, B_SUBURBS % "suburb_fence_privacy", x, z - 47.0, ALONG_X, 0.0, "Fence_%d" % i)
	for i in 9:
		_put(g, B_STREETS % "street_road_two_lane", -144.0 + i * 32.0, z, ALONG_X, 0.0, "HouseStreet_%d" % i)
	_put(g, B_SUBURBS % "suburb_townhouse_row", 162.0, z - 36.0, FACE_WEST, 0.0, "Townhouses")
	_put(g, B_SUBURBS % "suburb_garden_apartment", 162.0, z - 96.0, FACE_WEST, 0.0, "Apartments")
	_put(g, B_SUBURBS % "suburb_church", -184.0, z - 52.0, FACE_SOUTH, 0.0, "Church")
	_put(g, B_SUBURBS % "suburb_school_wing", -44.0, z - 120.0, ALONG_X, 0.0, "School")


# ── The level ────────────────────────────────────────────────────────────────

## Objective anchors. TERRAIN puts the pins in and names them; what a mission
## does with them is GAMEPLAY's, which is why these are places and not tasks.
## node, tag, label, x, z
const OBJECTIVES: Array = [
	# In front of the row, not inside the steakhouse.
	["Polaris_Row", "obj_polaris_row", "The Restaurant Row", -70.0, 190.0],
	["Polaris_Court", "obj_polaris_court", "The Entry Court", 0.0, 48.0],
	["Polaris_Dock", "obj_polaris_dock", "Mall Service Dock", -30.0, -30.0],
	["Polaris_Garage", "obj_polaris_garage", "The Parking Deck", 96.0, 86.0],
	["Polaris_Cinema", "obj_polaris_cinema", "The Multiplex", -92.0, 92.0],
	["Polaris_Storage", "obj_polaris_storage", "The Storage Lanes", -296.0, -150.0],
	["Polaris_Basin", "obj_polaris_basin", "The West Basin", -150.0, 120.0],
	["Polaris_Houses", "obj_polaris_houses", "The Subdivision", -40.0, -196.0],
]


## The level scene: the art under a NavigationRegion3D, a spawn out on the
## frontage, an exit on the far side, and the objective anchors.
##
## Written as text rather than packed, because a level is a handful of nodes
## with scripts on them and an ext_resource list, and building that tree in
## memory to pack it means loading every script this file does not otherwise
## need. The art scene is packed, because it is four hundred instances.
func _write_level() -> void:
	var lines := PackedStringArray()
	var objs := PackedStringArray()
	for o: Array in OBJECTIVES:
		objs.append("""
[node name="%s" type="Node3D" parent="NavigationRegion3D/Objectives"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, 0, %s)
""".strip_edges() % [o[0], o[3], o[4]])
	lines.append("""[gd_scene load_steps=7 format=3]

[ext_resource type="PackedScene" path="%s" id="1_art"]
[ext_resource type="PackedScene" uid="uid://g7fmy28elpah" path="res://Env/world_objects/spawn_point.tscn" id="2_spawn"]

[sub_resource type="ProceduralSkyMaterial" id="Sky_mat"]
sky_horizon_color = Color(0.64, 0.66, 0.67, 1)
ground_horizon_color = Color(0.64, 0.66, 0.67, 1)

[sub_resource type="Sky" id="Sky_polaris"]
sky_material = SubResource("Sky_mat")

[sub_resource type="Environment" id="Env_polaris"]
background_mode = 2
sky = SubResource("Sky_polaris")
ambient_light_source = 3
ambient_light_color = Color(0.44, 0.45, 0.47, 1)
ambient_light_sky_contribution = 0.55
ambient_light_energy = 0.7
tonemap_mode = 2

[sub_resource type="NavigationMesh" id="NavigationMesh_polaris"]
vertices = PackedVector3Array()
polygons = []
cell_size = 0.25
agent_radius = 0.5
agent_height = 1.8
agent_max_climb = 0.25
region_min_size = 24.0
edge_max_error = 1.3
detail_sample_distance = 6.0
geometry_parsed_geometry_type = 1
filter_baking_aabb = AABB(-320, -12, -320, 640, 48, 640)

[node name="PolarisLevel" type="Node3D"]

[node name="NavigationRegion3D" type="NavigationRegion3D" parent="."]
navigation_mesh = SubResource("NavigationMesh_polaris")

[node name="PolarisArt" parent="NavigationRegion3D" instance=ExtResource("1_art")]

[node name="Objectives" type="Node3D" parent="NavigationRegion3D"]

%s

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Env_polaris")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.77, 0.41, -0.49, 0, 0.77, 0.64, 0.64, -0.49, 0.59, 0, 120, 0)
light_energy = 1.25
shadow_enabled = true
directional_shadow_max_distance = 420.0

[node name="SpawnPoint" parent="." instance=ExtResource("2_spawn")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -210, 0, 244)
""" % [ART, "\n\n".join(objs)])
	var f := FileAccess.open(LEVEL, FileAccess.WRITE)
	if f == null:
		print("FAIL  could not write %s (%s)" % [LEVEL, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string("\n".join(lines))
	f.close()
