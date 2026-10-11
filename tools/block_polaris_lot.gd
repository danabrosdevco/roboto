extends "res://tools/block_polaris.gd"

# ─────────────────────────────────────────────
# BLOCK POLARIS LOT — the detail that makes the mall's car park somewhere to
# fight rather than four hundred metres of open asphalt.
#
#   maps/blocks/polaris/lot_*.map
#
#   godot --headless --path . --script res://tools/block_polaris_lot.gd -- maps/blocks
#   godot --headless --path . --script res://tools/block_polaris_lot.gd -- maps/blocks --force [names]
#
# WHY THIS FILE EXISTS. The first assembly of the Polaris map had one real
# defect and it was the obvious one: a mall's car park is enormous, flat and
# empty, and the pieces that shaped it — aisles, islands, light standards —
# are all ankle-high or thin. A squad crossing it had nothing between it and
# the far side. That is accurate and it is a bad map.
#
# THE FIX IS PARKED CARS. A car is 1.45 m high: over the 1.2 m a standing
# cover point probes at and under a head, so a row of them is a line of cover
# you can shoot over from a crouch and not from a stand. They come in rows
# rather than singly because a hundred separate car instances is a hundred
# prefabs to place and the same geometry either way. Everything else in here
# is the same argument — planters, tents, corrals, snow heaps: things a car
# park really has that happen to be between waist and head height.
# ─────────────────────────────────────────────

## Cars in these colours, picked off the car park and not off a palette.
const CAR_PAINT: Array = [
	"PSX_Textures/metal_wall_2", "PSX_Textures/concrete_1", "PSX_Textures/metal_wall_4",
	"PSX_Textures/metal_rusty_tsk_2", "PSX_Textures/metal_floor_1", "PSX_Textures/concrete_tx_5",
]

const LOT_PIECES := {
	"lot_car_row": "_car_row",
	"lot_car_row_sparse": "_car_row_sparse",
	"lot_planter_bed": "_planter_bed",
	"lot_transit_shelter": "_transit_shelter",
	"lot_event_marquee": "_event_marquee",
	"lot_dumpster_corral": "_dumpster_corral",
	"lot_valet_canopy": "_valet_canopy",
	"lot_snow_pile": "_snow_pile",
	"lot_food_pavilion": "_food_pavilion",
	"lot_garden_centre": "_garden_centre",
	"lot_sign_cluster": "_sign_cluster",
	"lot_charging_bank": "_charging_bank",
}


func _initialize() -> void:
	var base := ""
	var force := false
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a == "--force":
			force = true
		elif base == "":
			base = a
		else:
			only.append(a)
	if base == "":
		print("usage: godot --headless --path . --script res://tools/block_polaris_lot.gd -- maps/blocks [--force] [names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	var dir := base.path_join("polaris")
	if not DirAccess.dir_exists_absolute(dir):
		print("FAIL  no folder at %s — run block_polaris.gd first" % dir)
		quit(1)
		return
	var written := 0
	var skipped := 0
	for name: String in LOT_PIECES:
		if not only.is_empty() and not only.has(name):
			continue
		var path := dir.path_join(name + ".map")
		if FileAccess.file_exists(path) and not force:
			print("SKIP  %s exists — it may hold TrenchBroom edits. Pass --force to overwrite it." % path)
			skipped += 1
			continue
		_brushes = []
		_ghost_from = -1
		_entities = []
		call(LOT_PIECES[name])
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("FAIL  could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			quit(1)
			return
		f.store_string(_map_text())
		f.close()
		written += 1
		print("      %-26s %3d brushes  %s" % [name, _brushes.size(), _extent_text()])
	print("BLOCK POLARIS LOT DONE: %d written%s" % [written, (" (%d skipped)" % skipped) if skipped > 0 else ""])
	quit()


## A parked car: block_industrial's car_at, except that the tyres stand OUTSIDE
## the body. In car_at each axle is one prism the full width of the car, which
## is a rod pushed through the body, and the body is the body in the same
## space. Four short stubs read the same from the side and share nothing.
func _park_car(c: Vector3, yaw: float, tex: String) -> void:
	psolid(c, yaw, [Vector3(-2.2, -0.9, 0.3), Vector3(2.2, -0.9, 0.3), Vector3(2.2, 0.9, 0.3), Vector3(-2.2, 0.9, 0.3),
			Vector3(-2.15, -0.88, 0.95), Vector3(2.1, -0.88, 0.88), Vector3(2.1, 0.88, 0.88), Vector3(-2.15, 0.88, 0.95)], {"top": tex, "side": tex, "bottom": RUST})
	psolid(c, yaw, [Vector3(-1.4, -0.82, 0.93), Vector3(1.0, -0.82, 0.9), Vector3(1.0, 0.82, 0.9), Vector3(-1.4, 0.82, 0.93),
			Vector3(-1.0, -0.72, 1.45), Vector3(0.45, -0.72, 1.45), Vector3(0.45, 0.72, 1.45), Vector3(-1.0, 0.72, 1.45)], {"top": tex, "side": GLASS, "bottom": tex})
	for x: float in [-1.35, 1.35]:
		for s: float in [-1.0, 1.0]:
			# A few cm clear of the body: both are turned and snapped to the grid
			# separately, and flush they would still catch each other.
			ppipe(c, yaw, Vector3(x, s * 0.95, 0.33), Vector3(x, s * 1.08, 0.33), 0.33, RUBBER, 8)


## `n` cars nose-in on a 2.7 m bay pitch, each sitting a little crooked in its
## bay because nobody parks straight. `fill` is the chance a bay has a car in
## it, so the same function gives a packed row and an emptying one.
func _park_row(n: int, fill: float, seed: int) -> void:
	for i in n:
		if _hash_f(i * 31 + seed) > fill:
			continue
		var x := (i - n * 0.5 + 0.5) * 2.7
		var skew := (_hash_f(i * 7 + seed) - 0.5) * 9.0
		var creep := (_hash_f(i * 13 + seed) - 0.5) * 0.7
		var paint: String = CAR_PAINT[int(_hash_f(i * 17 + seed) * CAR_PAINT.size()) % CAR_PAINT.size()]
		_park_car(Vector3(x, creep, 0.0), 90.0 + skew, paint)


## A FULL ROW, ten cars nose to tail across 27 m. The piece that gives the car
## park its cover: 1.45 m to the roof, so a body behind one is covered standing
## and a body on the far side can be hit from a roof or a deck.
func _car_row() -> void:
	_park_row(10, 1.0, 3)


## The same row three-quarters empty, for the edges of the lot where nobody
## parks. Gaps are the point — a line of cover with holes in it is a line a
## squad has to read before it commits.
func _car_row_sparse() -> void:
	_park_row(10, 0.42, 19)


## A RAISED PLANTER, 9 x 3.5: a brick kerb wall at cover height with soil and
## small trees in it. The one piece of lot furniture that is deliberately
## chest high rather than ankle high.
func _planter_bed() -> void:
	var w := 4.5
	var d := 1.75
	# The two long walls take the corners; the short ones run between them.
	for e: Array in [[-w, -d, w, -d + 0.35], [-w, d - 0.35, w, d], [-w, -d + 0.35, -w + 0.35, d - 0.35], [w - 0.35, -d + 0.35, w, d - 0.35]]:
		box(Vector3(e[0], e[1], -0.3), Vector3(e[2], e[3], COVER_H), {"top": COPING_TOP, "side": RETAIL_BRICK, "bottom": CONCRETE})
	box(Vector3(-w + 0.35, -d + 0.35, -0.3), Vector3(w - 0.35, d - 0.35, COVER_H - 0.25), {"top": DIRT, "side": SPOIL, "bottom": SPOIL})
	no_collision()
	for i in 3:
		var x := lerpf(-3.0, 3.0, float(i) / 2.0)
		# The trunk ends where the crown begins (the heap's flat base is at
		# COVER_H + 1.7); it used to run up into it.
		cylinder(Vector3(x, 0.0, COVER_H - 0.25), 0.2, 1.95, 6, SPOIL, 0.14)
		heap(Vector3(x, 0.0, COVER_H + 2.0), 1.5, 1.4, 1.5, i * 11 + 5, SPOIL)


const COPING_TOP := "PSX_Textures/concrete_1"


## A TRANSIT SHELTER on the ring road: glass on three sides under a
## cantilevered roof, with the route board on a post. See-through, so it hides
## nothing and is still 2.7 m of hard roof.
func _transit_shelter() -> void:
	box(Vector3(-2.6, -1.0, -0.3), Vector3(2.6, 1.0, KERB_H), {"top": WALK, "side": KERB, "bottom": CONCRETE})
	box(Vector3(-2.6, -1.0, KERB_H), Vector3(-2.45, 1.0, 2.4), STORE_GLASS)
	box(Vector3(2.45, -1.0, KERB_H), Vector3(2.6, 1.0, 2.4), STORE_GLASS)
	# The back pane runs between the two end panes, not through them.
	box(Vector3(-2.45, -1.0, KERB_H), Vector3(2.45, -0.85, 2.4), STORE_GLASS)
	# Posts at the four corners, just outside the glass: they used to stand
	# in it.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			post(sx * 2.665, sy * 1.065, KERB_H, 2.6, 0.13)
	box(Vector3(-2.9, -1.2, 2.6), Vector3(2.9, 1.7, 2.82), {"top": ROOF_MEMBRANE, "side": SIGN_BAND, "bottom": METAL})
	box(Vector3(-2.2, -0.8, 0.55), Vector3(2.2, -0.42, 0.72), {"top": WOOD, "side": METAL, "bottom": METAL})
	# The route board: a short post with the sign standing on it, beside the
	# roof's edge. The post used to run up through the sign and the sign into
	# the roof.
	box(Vector3(2.9, 0.7, KERB_H), Vector3(3.08, 0.88, 2.6), METAL)
	box(Vector3(2.9, 0.68, 2.6), Vector3(3.28, 0.9, 3.2), SIGN_BAND)


## THE EVENT MARQUEE: a 24 x 14 white tent on poles, the kind a mall puts up
## in its car park for a sale. A landmark across the lot, a big dark interior,
## and the only building-sized thing out there — which makes it the obvious
## objective on open ground and the obvious ambush.
func _event_marquee() -> void:
	var w := 12.0
	var d := 7.0
	var eave := 3.2
	var ridge := 6.0
	box(Vector3(-w, -d, -0.3), Vector3(w, d, 0.05), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	# The canopy as one solid, ridge along X, so it is one mesh and one hull.
	solid([Vector3(-w - 0.8, -d - 0.8, eave), Vector3(w + 0.8, -d - 0.8, eave),
			Vector3(w + 0.8, d + 0.8, eave), Vector3(-w - 0.8, d + 0.8, eave),
			Vector3(-w - 0.8, 0.0, ridge), Vector3(w + 0.8, 0.0, ridge)], {"top": BAG_WHITE, "side": BAG_WHITE, "bottom": BAG_WHITE})
	# Poles stand on the slab and stop at the canopy's underside, which is flat
	# at the eave height all the way across: a pole run on up to the ridge is a
	# pole inside the roof. The edge ones are against the inside of the wall,
	# on their ballast, rather than half in it.
	for i in 5:
		var x := lerpf(-w + 1.0, w - 1.0, float(i) / 4.0)
		for s: float in [-1.0, 1.0]:
			var wall_in := s * (d - 0.08)
			box(Vector3(x - 0.5, wall_in - s * 1.0, 0.05), Vector3(x + 0.5, wall_in, 0.45), CONCRETE)
			box(Vector3(x - 0.14, wall_in - s * 0.28, 0.45), Vector3(x + 0.14, wall_in, eave), METAL)
		box(Vector3(x - 0.16, -0.16, 0.05), Vector3(x + 0.16, 0.16, eave), METAL)
	# The walls, open at both ends: a tent is a corridor with a roof.
	for s: float in [-1.0, 1.0]:
		box(Vector3(-w + 2.5, s * d - s * 0.08, 0.05), Vector3(w - 2.5, s * d, eave), {"top": BAG_WHITE, "side": BAG_WHITE, "bottom": BAG_WHITE})


const BAG_WHITE := "PSX_Textures/fabric_tx_1"


## A BIN CORRAL: three brick walls at cover height round two skips, open to
## the lot. Cover with a back to it, which is rarer on this map than it
## sounds.
func _dumpster_corral() -> void:
	box(Vector3(-4.0, -3.0, -0.3), Vector3(4.0, 3.0, 0.05), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	# The walls stand on the slab, and the back wall runs between the side ones.
	for e: Array in [[-4.0, -3.0, 4.0, -2.6], [-4.0, 2.6, 4.0, 3.0], [-4.0, -2.6, -3.6, 2.6]]:
		box(Vector3(e[0], e[1], 0.05), Vector3(e[2], e[3], COVER_H + 0.35), {"top": COPING_TOP, "side": RETAIL_BRICK, "bottom": CONCRETE})
	box(Vector3(-3.2, -2.2, 0.05), Vector3(0.2, 1.6, 2.0), {"top": METAL, "side": GREEN, "bottom": METAL})
	box(Vector3(0.8, -2.2, 0.05), Vector3(3.4, 0.9, 1.65), {"top": METAL, "side": GREEN, "bottom": METAL})
	# The gate, standing open against the wall: just past the slab's edge, where
	# it used to stand half on it and half in the wall.
	box(Vector3(4.0, 2.6, 0.0), Vector3(4.2, 3.0, 2.0), METAL)
	box(Vector3(4.0, -0.4, 0.0), Vector3(4.12, 2.6, 1.9), SHUTTER)


## A valet or security stand: a hut and a small canopy at the court door.
func _valet_canopy() -> void:
	box(Vector3(-1.6, -1.4, -0.3), Vector3(1.6, 1.4, 2.6), {"top": ROOF_MEMBRANE, "side": EIFS, "bottom": CONCRETE})
	# The window stands on the hut's face, not in it.
	box(Vector3(-1.3, 1.4, 1.0), Vector3(1.3, 1.65, 2.1), DARK_GLASS)
	box(Vector3(-1.75, -1.55, 2.6), Vector3(1.75, 1.55, 2.85), {"top": ROOF_MEMBRANE, "side": SIGN_BAND, "bottom": METAL})
	box(Vector3(2.4, -3.6, 2.9), Vector3(9.0, 2.6, 3.15), {"top": ROOF_MEMBRANE, "side": SIGN_BAND, "bottom": METAL})
	for sx: float in [0.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			post(3.2 + sx * 5.0, sy * 2.6 - 0.5, -0.3, 2.9, 0.18)
	for i in 4:
		cylinder(Vector3(-3.0 + i * 1.6, 2.4, -0.3), 0.13, 1.1, 8, METAL)


## The points of one lumpy mound, as block_doodads' mound() builds them but
## without making the brush, so that two of them can be hulled as one.
func _mound_points(c: Vector3, rx: float, ry: float, h: float, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var pts: Array = []
	for ring in [[-0.3, 1.0], [0.45, 0.8], [0.8, 0.5], [1.0, 0.15]]:
		var t: float = ring[0]
		var k: float = ring[1]
		var count := 9 if k > 0.3 else 4
		for i in count:
			var a := TAU * i / count + rng.randf_range(-0.25, 0.25)
			var j := rng.randf_range(0.92, 1.05)
			pts.append(c + Vector3(cos(a) * rx * k * j, sin(a) * ry * k * j, t * h if t > 0.0 else t))
	return pts


## A PLOUGHED HEAP at the edge of the lot — snow in winter, grit and swept
## rubbish the rest of the year. Three metres of soft cover that was not put
## there on purpose, which is what a car park's cover mostly is.
func _snow_pile() -> void:
	# The two lumps are one hull. Two separate mounds this close interpenetrate
	# over a third of their length, and a hull of both is just a longer heap.
	solid(_mound_points(Vector3(0.0, 0.0, -0.2), 7.0, 3.4, 2.9, 77) + _mound_points(Vector3(6.5, 1.2, -0.2), 3.6, 2.2, 1.8, 91), SPOIL, 4)
	no_collision()
	# Rubble scattered round the foot of it, clear of the heap: on the old
	# ring they stood half inside it.
	var foot: Array = [Vector2(-6.3, -2.9), Vector2(-6.3, 2.9), Vector2(-3.4, -3.6), Vector2(3.0, -3.6), Vector2(7.0, -2.8), Vector2(8.8, -1.6), Vector2(-3.4, 3.5)]
	for i in foot.size():
		var p: Vector2 = foot[i]
		heap(Vector3(p.x, p.y, 0.0), 0.8, 0.6, 0.45, i * 23 + 4, RUBBLE)


## AN OUTDOOR FOOD COURT: a pergola over tables between two kiosks. Open
## sided, roofed, and right in the middle of the walk from the lot to the
## court — a place a fight has to go through rather than round.
func _food_pavilion() -> void:
	var w := 11.0
	var d := 6.0
	box(Vector3(-w - 1.0, -d - 1.0, -0.3), Vector3(w + 1.0, d + 1.0, KERB_H), {"top": WALK, "side": KERB, "bottom": CONCRETE})
	for s: float in [-1.0, 1.0]:
		box(Vector3(s * (w - 3.0), -d, KERB_H), Vector3(s * w, d - 2.0, 3.4), {"top": ROOF_MEMBRANE, "side": EIFS, "bottom": CONCRETE})
		# The serving window is on the kiosk's face, not in it.
		box(Vector3(s * (w - 2.9), d - 2.0, 1.1), Vector3(s * (w - 0.1), d - 1.9, 2.4), DARK_GLASS)
		box(Vector3(s * (w - 3.2), -d - 0.2, 3.4), Vector3(s * (w + 0.2), d - 1.8, 3.8), {"top": ROOF_MEMBRANE, "side": SIGN_BAND, "bottom": METAL})
	# The pergola between them: beams on posts, open to the sky, which still
	# breaks every sightline through it.
	for i in 7:
		var x := lerpf(-w + 3.6, w - 3.6, float(i) / 6.0)
		box(Vector3(x - 0.14, -d + 0.4, 3.0), Vector3(x + 0.14, d - 0.4, 3.3), WOOD_DARK)
	for s: float in [-1.0, 1.0]:
		box(Vector3(-w + 3.2, s * (d - 0.6) - 0.16, 2.7), Vector3(w - 3.2, s * (d - 0.6) + 0.16, 3.0), WOOD_DARK)
		for i in 4:
			var x := lerpf(-w + 3.6, w - 3.6, float(i) / 3.0)
			# The posts hold the side beam up; they stop under it.
			post(x, s * (d - 0.6), KERB_H, 2.7, 0.22, WOOD_DARK)
	no_collision()
	for i in 4:
		for j in 2:
			var x := lerpf(-5.5, 5.5, float(i) / 3.0)
			var y := lerpf(-2.4, 2.4, float(j))
			cylinder(Vector3(x, y, KERB_H), 0.7, 0.74, 8, {"top": WOOD, "side": METAL, "bottom": METAL})


## THE SEASONAL GARDEN CENTRE: a fenced yard off a big box, racks of stock in
## rows. The racks are 1.9 m and solid enough to stop sight — it is the one
## place on the map with a maze in it.
func _garden_centre() -> void:
	var w := 16.0
	var d := 11.0
	box(Vector3(-w, -d, -0.3), Vector3(w, d, 0.05), {"top": ASPHALT, "side": CONCRETE, "bottom": CONCRETE})
	# The fence stands on the slab, and its west run goes between the other two.
	for e: Array in [[-w, -d, w, -d + 0.2], [-w, d - 0.2, w, d], [-w, -d + 0.2, -w + 0.2, d - 0.2]]:
		box(Vector3(e[0], e[1], 0.05), Vector3(e[2], e[3], 2.3), {"top": METAL, "side": SHUTTER, "bottom": METAL})
	for i in 4:
		var x := lerpf(-w + 3.0, w - 3.0, float(i) / 3.0)
		box(Vector3(x - 0.7, -d + 2.0, 0.05), Vector3(x + 0.7, d - 2.0, 1.9), {"top": GRATING, "side": SHUTTER, "bottom": METAL})
		box(Vector3(x - 0.85, -d + 2.0, 1.9), Vector3(x + 0.85, d - 2.0, 2.05), METAL)
	# The shade canopy over half of it.
	box(Vector3(-w, -d, 3.2), Vector3(0.0, d, 3.35), {"top": GRATING, "side": METAL, "bottom": GRATING})
	for sx: float in [-1.0, 0.0]:
		for sy: float in [-1.0, 1.0]:
			post(sx * (w - 1.0), sy * (d - 1.0), 0.05, 3.2, 0.22)


## A cluster of directional signs at an aisle head: the aisle letter, a
## pedestrian sign and a trolley sign on one post.
func _sign_cluster() -> void:
	box(Vector3(-0.6, -0.6, -0.4), Vector3(0.6, 0.6, KERB_H), ISLAND)
	box(Vector3(-0.1, -0.1, KERB_H), Vector3(0.1, 0.1, 3.4), METAL)
	# The three signs are bolted to the faces of the post rather than passed
	# through it: one on the front, one on the side, one on the back.
	box(Vector3(-0.55, 0.1, 2.5), Vector3(0.55, 0.22, 3.3), SIGN_BAND)
	box(Vector3(0.1, -0.5, 1.9), Vector3(0.22, 0.5, 2.4), SIGN_BAND)
	box(Vector3(-0.4, -0.22, 1.1), Vector3(0.4, -0.1, 1.6), SIGN_BAND)


## A BANK OF CHARGERS under a small canopy with a PV deck on it, which is
## what the new ones all have — and the one place in the car park the solar
## texture belongs.
func _charging_bank() -> void:
	var w := 8.0
	box(Vector3(-w, -2.6, -0.3), Vector3(w, 2.6, KERB_H), ISLAND)
	for i in 4:
		var x := lerpf(-6.0, 6.0, float(i) / 3.0)
		box(Vector3(x - 0.35, -0.45, KERB_H), Vector3(x + 0.35, 0.45, 1.75), {"top": METAL, "side": SHUTTER, "bottom": METAL})
		# The screen is on the charger's face.
		box(Vector3(x - 0.28, -0.53, 1.1), Vector3(x + 0.28, -0.45, 1.6), DARK_GLASS)
	box(Vector3(-w - 0.5, -3.2, 4.2), Vector3(w + 0.5, 3.2, 4.45), {"top": "PSX_Textures/solar_pv", "side": METAL, "bottom": METAL})
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			post(sx * (w - 1.2), sy * 2.2, KERB_H, 4.2, 0.24)
