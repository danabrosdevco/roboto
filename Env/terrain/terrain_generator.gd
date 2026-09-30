@tool
class_name TerrainGenerator
extends RefCounted

# ─────────────────────────────────────────────
# TERRAIN GENERATOR — recipe + modifiers in, TerrainData out. No nodes.
#
# Pure functions over flat arrays, so it runs the same in the editor, in a
# headless test and at runtime, and a stage can be tested on its own.
#
# THE ORDER OF STAGES IS DELIBERATE:
#   shape (layout, mountains, hills, ridges, detail; painted mountains and
#   rough ground) → painted flat/urban levelled → terraces → erosion
#   → craters, painted shelling → smoothing → shift floor to y=0
#   → painted flat, urban, water, then roads → MODIFIERS → hollows
# Craters come after erosion because they are fresh — this is a war, not
# geology. The floor shift comes BEFORE the modifiers because a TerrainStamp
# flattens to its own authored Y; shifting afterwards would leave every
# building pad a few metres off the building that was placed on it. Painted
# water is finished after the shift for the same reason: water_level is a
# height in the final datum.
#
# Modifiers arrive as plain dictionaries (TerrainStamp / TerrainPath build them
# in to_terrain_modifier), so this file never needs the node classes.
#
# Grid convention matches TerrainData: row-major, X fastest, centred on the
# node. Every cell is split along its (i+1, j)–(i, j+1) diagonal, the same way
# HeightMapShape3D triangulates, so heights sampled here match the collision.
# ─────────────────────────────────────────────

const Recipe := preload("res://Env/terrain/terrain_recipe.gd")
const Data := preload("res://Env/terrain/terrain_data.gd")
const MeshBuilder := preload("res://Env/terrain/terrain_mesh_builder.gd")
const Sketch := preload("res://Env/terrain/terrain_sketch.gd")

const CHUNK_CELLS := 64
const LOD_COUNT := 5
## Refuse beyond 2049² samples. Past that, GDScript generation takes minutes and
## the meshes stop fitting sensible memory — raise cell_size instead.
const MAX_SAMPLES := 2049 * 2049

# Modifier enums. They MIRROR TerrainStamp.Shape / .Footprint / .Paint and
# TerrainPath.Mode, which are stored as ints in scenes — append-only, and
# tools/test_terrain.gd fails if the two ever drift apart.
const STAMP_FLATTEN := 0
const STAMP_RAISE := 1
const STAMP_LOWER := 2
const STAMP_CRATER := 3

const FOOTPRINT_CIRCLE := 0
const FOOTPRINT_RECT := 1

const PAINT_NONE := 0
const PAINT_PAD := 1
const PAINT_ROAD := 2
const PAINT_SCORCH := 3
const PAINT_RUBBLE := 4

const PATH_ROAD := 0
const PATH_TRENCH := 1
const PATH_RIVERBED := 2
const PATH_BERM := 3

# Byte offsets inside a control sample.
const CH_ROAD := 0
const CH_SCORCH := 1
const CH_PAD := 2
const CH_HOLLOW := 3

## Paint on a TerrainPath fades over at most this many metres past its edge, so
## a road with a wide embankment still has a crisp edge to its gravel.
const PAINT_EDGE := 1.5

## Grade of the approach where a road climbs to a bridge: rise per metre.
const BRIDGE_RAMP := 0.1


## Runs a recipe. `modifiers` are TerrainStamp/TerrainPath dictionaries, applied
## in order (later wins). `cache`, when passed, carries the pre-modifier terrain
## between calls: while only modifiers change — dragging a stamp about — the
## expensive stages are skipped. Returns null, loudly, on bad input.
static func generate(recipe: Recipe, modifiers: Array = [], cache: Dictionary = {}) -> Data:
	if recipe == null:
		push_error("TerrainGenerator: no recipe to generate from.")
		return null
	var t_start := Time.get_ticks_msec()
	var cell := maxf(recipe.cell_size, 0.25)
	var size := Vector2(recipe.size_x, recipe.size_z)
	if recipe.sketch != null:
		var px := Vector2(recipe.sketch.get_width(), recipe.sketch.get_height())
		if recipe.sketch_metres_per_pixel > 0.0:
			# The drawing sets the map: a tall image is a north–south map.
			size = px * recipe.sketch_metres_per_pixel
		elif absf(px.aspect() - size.aspect()) > size.aspect() * 0.15:
			push_warning("TerrainGenerator: the sketch is %d × %d px but the map is %.0f × %.0f m, so the drawing is stretched. Match the aspect, or set sketch_metres_per_pixel to size the map from the sketch." % [px.x, px.y, size.x, size.y])
	var cells_x := _snap_cells(size.x / cell)
	var cells_z := _snap_cells(size.y / cell)
	var sx := cells_x + 1
	var sz := cells_z + 1
	var n := sx * sz
	if n > MAX_SAMPLES:
		push_error("TerrainGenerator: %.0f × %.0f m at %.2f m cells is %d samples; the limit is %d. Raise cell_size or shrink the map." % [size.x, size.y, cell, n, MAX_SAMPLES])
		return null

	var signature := recipe.signature()
	var base: Dictionary
	var cached: bool = cache.get("signature", 0) == signature and cache.has("heights")
	if cached:
		base = cache
	else:
		base = _generate_base(recipe, cells_x, cells_z, cell)
		cache.clear()
		cache.merge(base)
		cache["signature"] = signature
	var t_base := Time.get_ticks_msec()

	# The cache is reused by the next call, so everything below works on copies.
	# Packed arrays are shared by reference in GDScript: without duplicate() the
	# modifiers would pile up in the cache, one drag at a time.
	var heights: PackedFloat32Array = (base.heights as PackedFloat32Array).duplicate()
	var control: PackedByteArray = (base.control as PackedByteArray).duplicate()
	var zone: PackedByteArray = (base.zone as PackedByteArray).duplicate()
	var half_x := cells_x * cell * 0.5
	var half_z := cells_z * cell * 0.5
	var water: PackedByteArray = base.get("water", PackedByteArray())
	var bridges: Array = (base.get("bridges", []) as Array).duplicate(true)

	for m in modifiers:
		if not (m is Dictionary):
			push_warning("TerrainGenerator: skipped a modifier that is not a Dictionary: %s" % str(m))
			continue
		match str(m.get("type", "")):
			"stamp":
				_apply_stamp(m, heights, control, sx, sz, cell, half_x, half_z)
			"path":
				# A hand-drawn road over painted water bridges it like a painted one.
				bridges.append_array(_apply_path(m, heights, control, sx, sz, cell, half_x, half_z, water,
						float(base.get("water_level", 0.0)) + recipe.bridge_clearance))
			_:
				push_warning("TerrainGenerator: unknown modifier type '%s' from %s — skipped." % [m.get("type", ""), m.get("source", "?")])

	_hollows(heights, control, sx, sz, cell)

	var lo := INF
	var hi := -INF
	for v in heights:
		lo = minf(lo, v)
		hi = maxf(hi, v)

	var data := Data.new()
	data.cells_x = cells_x
	data.cells_z = cells_z
	data.cell_size = cell
	data.chunk_cells = CHUNK_CELLS
	data.lod_count = LOD_COUNT
	data.heights = heights
	data.control = control
	data.zone = zone
	data.min_height = lo
	data.max_height = hi
	data.water_level = float(base.get("water_level", 0.0))
	data.water = water.duplicate()
	data.lots = (base.get("lots", []) as Array).duplicate(true)
	data.bridges = bridges
	data.recipe = recipe.duplicate()
	data.lod_errors = MeshBuilder.compute_lod_errors(data)
	var t_end := Time.get_ticks_msec()
	data.generated_info = "%.0f × %.0f m, %.2f m cells (%d × %d samples), seed %d, %s%s, %d modifier(s). Heights %.1f … %.1f m%s. %s in %.1f s (base %s)." % [
		cells_x * cell, cells_z * cell, cell, sx, sz, recipe.random_seed,
		Recipe.Layout.keys()[recipe.layout],
		(", sketch %s" % (recipe.sketch.resource_path.get_file() if recipe.sketch.resource_path != "" else "(embedded)")) if recipe.sketch != null else "",
		modifiers.size(), lo, hi,
		((", water at %.1f m" % data.water_level) if data.has_water() else "")
				+ ((", %d lot(s)" % data.lots.size()) if not data.lots.is_empty() else "")
				+ ((", %d bridge(s)" % data.bridges.size()) if not data.bridges.is_empty() else ""),
		Time.get_datetime_string_from_system(false, true), (t_end - t_start) / 1000.0,
		"cached" if cached else "%.1f s" % ((t_base - t_start) / 1000.0)]
	return data


## Map dimension in cells, rounded UP to whole chunks so every chunk and every
## LOD step lines up with the grid.
static func _snap_cells(cells: float) -> int:
	return maxi(1, ceili(cells / CHUNK_CELLS - 0.0001)) * CHUNK_CELLS


static func _noise(seed_value: int, type: FastNoiseLite.NoiseType, fractal: FastNoiseLite.FractalType, octaves: int, scale: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = type
	n.fractal_type = fractal
	n.fractal_octaves = maxi(octaves, 1)
	n.frequency = 1.0 / maxf(scale, 0.001)
	return n


# ── Base terrain: everything that depends on the recipe alone ────────────────

static func _generate_base(r: Recipe, cells_x: int, cells_z: int, cell: float) -> Dictionary:
	var sx := cells_x + 1
	var sz := cells_z + 1
	var n := sx * sz
	var half_x := cells_x * cell * 0.5
	var half_z := cells_z * cell * 0.5
	var s := r.random_seed

	var hills := _noise(s, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.FRACTAL_FBM, r.hills_octaves, r.hills_scale)
	if r.hills_warp > 0.0:
		hills.domain_warp_enabled = true
		hills.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
		hills.domain_warp_amplitude = r.hills_warp
		hills.domain_warp_frequency = 1.0 / maxf(r.hills_scale * 1.7, 1.0)
		hills.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
		hills.domain_warp_fractal_octaves = 2
	var ridges := _noise(s + 101, FastNoiseLite.TYPE_SIMPLEX, FastNoiseLite.FRACTAL_RIDGED, 5, r.ridge_scale)
	var peaks := _noise(s + 202, FastNoiseLite.TYPE_SIMPLEX, FastNoiseLite.FRACTAL_RIDGED, 4, maxf(r.border_width * 0.9, 60.0))
	# Whole massifs and saddles along the range, so the skyline is not one
	# even wall of same-height peaks.
	var massif := _noise(s + 606, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.FRACTAL_FBM, 2, maxf(r.border_width * 2.5, 200.0))
	var detail := _noise(s + 303, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.FRACTAL_FBM, 3, r.detail_scale)
	var wobble := _noise(s + 404, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.FRACTAL_FBM, 3, maxf(r.border_width, 80.0) * 1.3)
	var bends := _noise(s + 505, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.FRACTAL_FBM, 2, r.meander_scale)

	# The painted layout, if any: one 0…1 mask per colour at this grid's
	# resolution. With no sketch every mask is empty and every sketch stage
	# below is skipped, so a recipe without one generates exactly as it did
	# before sketches existed — maps baked back then regenerate unchanged.
	var sk := {}
	var roads: Array = []
	var sketch_px := Vector2i.ZERO
	if r.sketch != null:
		var img := Sketch.load_image(r.sketch)
		if img != null:
			sk = Sketch.grid_masks(img, cells_x, cells_z, cell, r.sketch_blend, r.sketch_edge_noise, s)
			roads = Sketch.trace_roads(img)
			sketch_px = img.get_size()
			if sk.is_empty() and roads.is_empty():
				push_warning("TerrainGenerator: the sketch has no painted colours in it, so the recipe decides everything.")
	var sk_mtn: PackedFloat32Array = sk.get(Sketch.MOUNTAIN, PackedFloat32Array())
	var sk_rough: PackedFloat32Array = sk.get(Sketch.ROUGH, PackedFloat32Array())
	var sk_flat: PackedFloat32Array = sk.get(Sketch.FLAT, PackedFloat32Array())
	var sk_urban: PackedFloat32Array = sk.get(Sketch.URBAN, PackedFloat32Array())
	var sk_water: PackedFloat32Array = sk.get(Sketch.WATER, PackedFloat32Array())
	var sk_shell: PackedFloat32Array = sk.get(Sketch.SHELLED, PackedFloat32Array())
	var has_mtn := not sk_mtn.is_empty()
	var has_rough := not sk_rough.is_empty()
	var rough_a: FastNoiseLite = null
	var rough_b: FastNoiseLite = null
	if has_rough:
		rough_a = _noise(s + 909, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.FRACTAL_FBM, 4, 90.0)
		rough_b = _noise(s + 1010, FastNoiseLite.TYPE_SIMPLEX, FastNoiseLite.FRACTAL_RIDGED, 3, 150.0)

	var heights := PackedFloat32Array()
	heights.resize(n)
	var floor_mask := PackedFloat32Array()
	floor_mask.resize(n)
	var mountain := PackedFloat32Array()
	mountain.resize(n)
	var zone := PackedByteArray()
	zone.resize(n)
	var control := PackedByteArray()
	control.resize(n * Data.CONTROL_STRIDE)   # resize() zero-fills

	# VALLEY centreline: one lateral offset per sample along the long axis, plus
	# its slope, so the floor width is measured square to the valley rather than
	# along the axis (which would pinch the floor on every bend).
	var along_x := cells_x >= cells_z
	var t_count := sx if along_x else sz
	var half_lat := half_z if along_x else half_x
	var centre := PackedFloat32Array()
	centre.resize(t_count)
	var stretch := PackedFloat32Array()
	stretch.resize(t_count)
	if r.layout == Recipe.Layout.VALLEY:
		# Keep the floor clear of the mountains on either side.
		var room := maxf(half_lat - r.floor_width * 0.5 - _border_reach(r, along_x), 0.0)
		var swing := minf(r.meander, room)
		for t in t_count:
			centre[t] = bends.get_noise_1d(t * cell) * 1.6 * swing
		for t in t_count:
			var slope := (centre[mini(t + 1, t_count - 1)] - centre[maxi(t - 1, 0)]) / (2.0 * cell)
			stretch[t] = 1.0 / sqrt(1.0 + slope * slope)

	var floor_half := r.floor_width * 0.5
	var shoulder := maxf(r.floor_shoulder, 0.001)
	var basin_scale := minf(half_x, half_z)
	var sides := r.border_sides
	var edge_wobble := r.floor_edge_noise * r.floor_width * 0.35

	for j in sz:
		var z := j * cell - half_z
		for i in sx:
			var x := i * cell - half_x
			var k := j * sx + i
			var wob := wobble.get_noise_2d(x, z)

			# Border mountains: distance in from the nearest mountain edge.
			var b := 0.0
			if sides != 0 and r.border_width > 0.0:
				var d_edge := INF
				if sides & 1:
					d_edge = minf(d_edge, z + half_z)
				if sides & 2:
					d_edge = minf(d_edge, half_z - z)
				if sides & 4:
					d_edge = minf(d_edge, x + half_x)
				if sides & 8:
					d_edge = minf(d_edge, half_x - x)
				d_edge += wob * r.border_noise
				b = 1.0 - smoothstep(0.0, r.border_width, d_edge)
			# Painted mountains count as mountains everywhere a border would.
			var km := sk_mtn[k] if has_mtn else 0.0
			var bm := maxf(b, km)

			# Floor: 1 on the playable low ground, 0 on the land around it.
			var f := 1.0
			match r.layout:
				Recipe.Layout.VALLEY:
					var t := i if along_x else j
					var lat := z if along_x else x
					var d_floor := absf(lat - centre[t]) * stretch[t] + wob * edge_wobble
					f = 1.0 - smoothstep(floor_half, floor_half + shoulder, d_floor)
				Recipe.Layout.BASIN:
					var d_centre := Vector2(x / half_x, z / half_z).length() * basin_scale + wob * edge_wobble
					f = 1.0 - smoothstep(floor_half, floor_half + shoulder, d_centre)
			f *= 1.0 - bm

			var hv := hills.get_noise_2d(x, z)
			var rv := ridges.get_noise_2d(x, z) * 0.5 + 0.5
			var land := r.floor_depth + hv * r.hills_height + rv * r.ridge_height
			var low := hv * r.hills_height * r.floor_roughness + rv * r.ridge_height * r.ridge_on_floor
			var h := lerpf(land, low, f)
			if bm > 0.0:
				# border_height is the TYPICAL crest: massifs swing it about ±30%
				# and ridged peaks about ±45% on top, so the highest summits reach
				# roughly 1.7× it. Keep that in mind when matching a reference map.
				var pv := peaks.get_noise_2d(x, z) * 0.5 + 0.5
				var mv := 1.0 + massif.get_noise_2d(x, z) * 0.5
				var rise := b * b * (3.0 - 2.0 * b)
				if km > 0.0:
					# The larger of the two, never the sum: white painted over a
					# border would otherwise stack into a range twice the height.
					var painted := km * km * (3.0 - 2.0 * km)
					h += maxf(rise * r.border_height, painted * r.sketch_mountain_height) * mv * lerpf(1.0, 0.45 + pv * 0.9, r.border_ruggedness)
				else:
					# Kept as the exact pre-sketch expression: floating-point
					# multiplication is not associative, and reordering it would
					# nudge every mountain on maps already baked.
					h += rise * r.border_height * mv * lerpf(1.0, 0.45 + pv * 0.9, r.border_ruggedness)
			if has_rough:
				var kr := sk_rough[k]
				if kr > 0.0:
					h += kr * r.rough_height * (rough_a.get_noise_2d(x, z) + (rough_b.get_noise_2d(x, z) * 0.5 + 0.5) * 0.6)
			h += detail.get_noise_2d(x, z) * r.detail_height

			heights[k] = h
			floor_mask[k] = f
			mountain[k] = bm
			zone[k] = clampi(int(bm * 255.0), 0, 255)

	var has_flat := not sk_flat.is_empty()
	var has_urban := not sk_urban.is_empty()
	var has_water := not sk_water.is_empty()
	# Painted flat and urban ground is levelled BEFORE erosion as well as after,
	# so the rain finds nothing there to carve.
	if has_flat or has_urban:
		var smooth := heights.duplicate()
		_wide_blur(smooth, sx, sz, 24.0, cell)
		for k in n:
			var kf := maxf(sk_flat[k] if has_flat else 0.0, sk_urban[k] * 0.8 if has_urban else 0.0)
			if kf > 0.0:
				heights[k] = lerpf(heights[k], smooth[k], kf * 0.9)
	# Where terraces, random craters and the floor average keep out: painted
	# flat, urban and water ground each get their own treatment below.
	var protect := PackedFloat32Array()
	if has_flat or has_urban or has_water:
		protect.resize(n)
		for k in n:
			protect[k] = maxf(sk_flat[k] if has_flat else 0.0, maxf(sk_urban[k] if has_urban else 0.0, sk_water[k] if has_water else 0.0))

	if r.terrace_step > 0.0 and r.terrace_strength > 0.0:
		_terraces(heights, floor_mask, r.terrace_step, r.terrace_strength, protect)
	if r.thermal_passes > 0:
		_thermal(heights, sx, sz, cell, r.thermal_passes, r.talus_angle)
	if r.hydraulic_strength > 0.0:
		_hydraulic(heights, sx, sz, int(n * 0.3 * r.hydraulic_strength), s)
	if r.crater_count > 0:
		_scatter_craters(r, heights, control, floor_mask, mountain, sx, sz, cell, protect)
	if not sk_shell.is_empty():
		_shell(r, heights, control, sk_shell, sx, sz, cell)
	if r.smooth_passes > 0:
		_blur(heights, sx, sz, r.smooth_passes)
	if r.floor_at_zero:
		_shift_floor_to_zero(heights, floor_mask, mountain, sk_water)

	# Painted finishing, in the final height datum so water_level means what it
	# says. Order matters: water last, so a lake painted into a town floods it.
	if has_flat:
		var level := heights.duplicate()
		_wide_blur(level, sx, sz, 6.0, cell)
		for k in n:
			if sk_flat[k] > 0.0:
				heights[k] = lerpf(heights[k], level[k], sk_flat[k] * 0.85)
	var lots: Array = []
	if has_urban:
		lots = _urbanise(r, heights, control, sk_urban, sx, sz, cell, half_x, half_z)
	var water := PackedByteArray()
	if has_water:
		water = _flood(r, heights, control, sk_water, sx, sz, cell)
	# Roads last: they cut through towns and bridge the finished water.
	var bridges: Array = []
	if not roads.is_empty():
		bridges = _sketch_roads(r, roads, sketch_px, heights, control, water, sx, sz, cell, half_x, half_z)
		if not lots.is_empty():
			lots = _drop_blocked_lots(lots, heights, control, sx, sz, cell, half_x, half_z)

	return {"heights": heights, "control": control, "zone": zone,
			"water": water, "water_level": r.water_level, "lots": lots, "bridges": bridges}


## A wide, cheap blur: two box passes of `radius_m`, whatever the radius.
## The [1 2 1] _blur needs passes that grow with the square of the radius.
static func _wide_blur(h: PackedFloat32Array, sx: int, sz: int, radius_m: float, cell: float) -> void:
	var r := maxi(1, roundi(radius_m * 0.5 / cell))
	Sketch.box_blur(h, sx, sz, r)
	Sketch.box_blur(h, sx, sz, r)


## How far the mountains reach in from the lateral edges of a valley.
static func _border_reach(r: Recipe, along_x: bool) -> float:
	var lateral_sides := 3 if along_x else 12   # N+S walls a valley running along X
	return r.border_width * 0.8 if (r.border_sides & lateral_sides) != 0 else 0.0


static func _terraces(h: PackedFloat32Array, floor_mask: PackedFloat32Array, step: float, strength: float, protect: PackedFloat32Array = PackedFloat32Array()) -> void:
	var guarded := not protect.is_empty()
	for k in h.size():
		var v := h[k]
		var t := v / step
		var fl := floorf(t)
		# Flat treads, with the rise packed into the top 40% of each step.
		var shaped := (fl + smoothstep(0.6, 1.0, t - fl)) * step
		# Terraces are for hillsides and mesas; the floor keeps most of its shape.
		var w := strength * (1.0 - floor_mask[k] * 0.85)
		if guarded:
			w *= 1.0 - protect[k]
		h[k] = lerpf(v, shaped, w)


## Slumping. Any cell steeper than the talus angle to its steepest downhill
## neighbour sheds half the excess onto it. Alternating the sweep direction
## each pass stops the whole map creeping one way.
static func _thermal(h: PackedFloat32Array, sx: int, sz: int, cell: float, passes: int, talus_deg: float) -> void:
	var talus := tan(deg_to_rad(talus_deg)) * cell
	for p in passes:
		var reverse := p % 2 == 1
		for jj in range(1, sz - 1):
			var j := (sz - 1 - jj) if reverse else jj
			var row := j * sx
			for ii in range(1, sx - 1):
				var k := row + ((sx - 1 - ii) if reverse else ii)
				var hc := h[k]
				var target := k - 1
				var drop := hc - h[k - 1]
				var d := hc - h[k + 1]
				if d > drop:
					drop = d
					target = k + 1
				d = hc - h[k - sx]
				if d > drop:
					drop = d
					target = k - sx
				d = hc - h[k + sx]
				if d > drop:
					drop = d
					target = k + sx
				if drop > talus:
					var move := (drop - talus) * 0.5
					h[k] = hc - move
					h[target] += move


## Rainfall erosion, particle style: each droplet runs downhill, picks up
## sediment where it speeds up and drops it where it slows, carving gullies
## and leaving fans below them.
##
## Runs in units of the terrain's own relief, so the constants behave the same
## on a 20 m hillock and a 300 m massif.
##
## Two things stop it looking combed. Droplets erode through a 3×3 brush
## rather than the four corners of their cell — single-cell carving scores
## hair-thin parallel grooves down every slope. And the total carved-away
## difference is blurred once at the end, which merges neighbouring grooves
## into gullies without softening the terrain it did not touch.
static func _hydraulic(h: PackedFloat32Array, sx: int, sz: int, droplets: int, seed_value: int) -> void:
	if droplets <= 0:
		push_warning("TerrainGenerator: hydraulic erosion asked for %d droplets — skipped." % droplets)
		return
	const INERTIA := 0.3
	const CAPACITY := 8.0
	const MIN_CAPACITY := 0.0005
	const ERODE := 0.25
	const DEPOSIT := 0.3
	const EVAPORATE := 0.03
	const GRAVITY := 8.0
	const MAX_STEPS := 40
	var lo := INF
	var hi := -INF
	for v in h:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var relief := maxf(hi - lo, 1.0)
	var inv := 1.0 / relief
	for k in h.size():
		h[k] = (h[k] - lo) * inv
	var before := h.duplicate()

	# Brush: weight 1 - distance/2 over the 3×3 around the nearest sample.
	var brush_off := PackedInt32Array()
	var brush_w := PackedFloat32Array()
	var brush_total := 0.0
	for bz in range(-1, 2):
		for bx in range(-1, 2):
			var bw := 1.0 - sqrt(float(bx * bx + bz * bz)) * 0.5
			brush_off.append(bz * sx + bx)
			brush_w.append(bw)
			brush_total += bw
	for b in brush_w.size():
		brush_w[b] /= brush_total

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 1000003 + 11
	# Two samples of margin: the brush reaches one past the nearest sample.
	var max_x := float(sx - 3)
	var max_z := float(sz - 3)
	for _drop in droplets:
		var px := rng.randf_range(2.0, max_x)
		var pz := rng.randf_range(2.0, max_z)
		var dx := 0.0
		var dz := 0.0
		var speed := 1.0
		var water := 1.0
		var sediment := 0.0
		for _step in MAX_STEPS:
			var ix := int(px)
			var iz := int(pz)
			var fx := px - ix
			var fz := pz - iz
			var k := iz * sx + ix
			var h00 := h[k]
			var h10 := h[k + 1]
			var h01 := h[k + sx]
			var h11 := h[k + sx + 1]
			var gx := (h10 - h00) * (1.0 - fz) + (h11 - h01) * fz
			var gz := (h01 - h00) * (1.0 - fx) + (h11 - h10) * fx
			var here := h00 + (h10 - h00) * fx + (h01 - h00) * fz + (h00 - h10 - h01 + h11) * fx * fz
			dx = dx * INERTIA - gx * (1.0 - INERTIA)
			dz = dz * INERTIA - gz * (1.0 - INERTIA)
			var dir_len := sqrt(dx * dx + dz * dz)
			if dir_len < 1e-9:
				break   # dead flat: the droplet pools and soaks away
			dx /= dir_len
			dz /= dir_len
			var nx := px + dx
			var nz := pz + dz
			if nx < 2.0 or nx >= max_x or nz < 2.0 or nz >= max_z:
				break   # ran off the map
			var jx := int(nx)
			var jz := int(nz)
			var gfx := nx - jx
			var gfz := nz - jz
			var q := jz * sx + jx
			var q00 := h[q]
			var q10 := h[q + 1]
			var q01 := h[q + sx]
			var q11 := h[q + sx + 1]
			var there := q00 + (q10 - q00) * gfx + (q01 - q00) * gfz + (q00 - q10 - q01 + q11) * gfx * gfz
			var dh := there - here
			var capacity := maxf(-dh * speed * water * CAPACITY, MIN_CAPACITY)
			var w00 := (1.0 - fx) * (1.0 - fz)
			var w10 := fx * (1.0 - fz)
			var w01 := (1.0 - fx) * fz
			var w11 := fx * fz
			if dh > 0.0 or sediment > capacity:
				# Uphill: fill the dip it is climbing out of. Otherwise drop the excess.
				var amount := minf(dh, sediment) if dh > 0.0 else (sediment - capacity) * DEPOSIT
				sediment -= amount
				h[k] += amount * w00
				h[k + 1] += amount * w10
				h[k + sx] += amount * w01
				h[k + sx + 1] += amount * w11
			else:
				# Never dig deeper than the step it just went down, or it bores pits.
				var amount := minf((capacity - sediment) * ERODE, -dh)
				var centre := roundi(pz) * sx + roundi(px)
				for b in brush_off.size():
					h[centre + brush_off[b]] -= amount * brush_w[b]
				sediment += amount
			speed = sqrt(maxf(speed * speed - dh * GRAVITY, 0.0))
			water *= 1.0 - EVAPORATE
			px = nx
			pz = nz

	var carved := PackedFloat32Array()
	carved.resize(h.size())
	for k in h.size():
		carved[k] = h[k] - before[k]
	_blur(carved, sx, sz, 1)
	for k in h.size():
		h[k] = (before[k] + carved[k]) * relief + lo


static func _scatter_craters(r: Recipe, h: PackedFloat32Array, control: PackedByteArray, floor_mask: PackedFloat32Array, mountain: PackedFloat32Array, sx: int, sz: int, cell: float, protect: PackedFloat32Array = PackedFloat32Array()) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = r.random_seed * 7919 + 3
	var rmin := minf(r.crater_radius_min, r.crater_radius_max)
	var rmax := maxf(r.crater_radius_min, r.crater_radius_max)
	var guarded := not protect.is_empty()
	var placed := 0
	for _c in r.crater_count:
		var gx := 0.0
		var gz := 0.0
		var found := false
		for _attempt in 24:
			gx = rng.randf_range(0.03, 0.97) * (sx - 1)
			gz = rng.randf_range(0.03, 0.97) * (sz - 1)
			var k := int(gz) * sx + int(gx)
			if mountain[k] > 0.3:
				continue
			if r.craters_on_floor and floor_mask[k] < 0.5:
				continue
			# Painted flat, urban and water ground takes no random hits: shelling
			# there is asked for in red, not left to chance.
			if guarded and protect[k] > 0.3:
				continue
			found = true
			break
		# The radius is drawn whether or not a spot was found, so one crater's
		# failure does not reshuffle the size of every crater after it.
		var radius := lerpf(rmin, rmax, pow(rng.randf(), 2.0))
		if not found:
			continue
		_add_crater(h, control, sx, sz, cell, gx, gz, radius, radius * r.crater_depth, radius * r.crater_rim, 1.0)
		placed += 1
	if placed < r.crater_count:
		push_warning("TerrainGenerator: placed %d of %d craters — too little %s to fit the rest. Turn off craters_on_floor or widen the floor." % [placed, r.crater_count, "floor" if r.craters_on_floor else "open ground"])


## Adds a crater centred on grid coordinates (gx, gz). Additive, so a crater on
## a slope still follows the slope. Paints scorch into the bowl.
static func _add_crater(h: PackedFloat32Array, control: PackedByteArray, sx: int, sz: int, cell: float, gx: float, gz: float, radius: float, depth: float, rim: float, scorch: float) -> void:
	radius = maxf(radius, 0.01)
	var reach := radius * 1.8 / cell
	var i0 := maxi(0, floori(gx - reach))
	var i1 := mini(sx - 1, ceili(gx + reach))
	var j0 := maxi(0, floori(gz - reach))
	var j1 := mini(sz - 1, ceili(gz + reach))
	var to_t := cell / radius
	for j in range(j0, j1 + 1):
		var dzt := (j - gz) * to_t
		for i in range(i0, i1 + 1):
			var dxt := (i - gx) * to_t
			var t := sqrt(dxt * dxt + dzt * dzt)
			if t >= 1.8:
				continue
			var k := j * sx + i
			if t < 1.0:
				h[k] += -depth + (depth + rim) * t * t   # bowl rising to the rim crest
			else:
				h[k] += rim * (1.0 - smoothstep(1.0, 1.8, t))   # outer slope of the rim
			if scorch > 0.0:
				var c := k * Data.CONTROL_STRIDE + CH_SCORCH
				control[c] = maxi(control[c], int((1.0 - smoothstep(0.5, 1.35, t)) * scorch * 255.0))


## Separable [1 2 1] blur, `passes` times. Edges clamp.
static func _blur(h: PackedFloat32Array, sx: int, sz: int, passes: int) -> void:
	var tmp := PackedFloat32Array()
	tmp.resize(h.size())
	for _p in passes:
		for j in sz:
			var row := j * sx
			for i in sx:
				tmp[row + i] = (h[row + maxi(i - 1, 0)] + h[row + i] * 2.0 + h[row + mini(i + 1, sx - 1)]) * 0.25
		for j in sz:
			var up := maxi(j - 1, 0) * sx
			var row := j * sx
			var down := mini(j + 1, sz - 1) * sx
			for i in sx:
				h[row + i] = (tmp[up + i] + tmp[row + i] * 2.0 + tmp[down + i]) * 0.25


## Painted water is left out of the average: a sea covering half an island
## map would otherwise drag "the floor" down toward the seabed.
static func _shift_floor_to_zero(h: PackedFloat32Array, floor_mask: PackedFloat32Array, mountain: PackedFloat32Array, water: PackedFloat32Array = PackedFloat32Array()) -> void:
	var wet := not water.is_empty()
	var total := 0.0
	var count := 0
	for k in h.size():
		if floor_mask[k] > 0.6 and mountain[k] < 0.05 and not (wet and water[k] > 0.3):
			total += h[k]
			count += 1
	if count * 100 < h.size():
		# Barely any floor (all mountains, or a tiny basin): use the open ground.
		total = 0.0
		count = 0
		for k in h.size():
			if mountain[k] < 0.1 and not (wet and water[k] > 0.3):
				total += h[k]
				count += 1
	if count == 0:
		push_warning("TerrainGenerator: floor_at_zero found no open ground to measure (the border mountains cover the whole map) — heights left unshifted.")
		return
	var shift := total / count
	for k in h.size():
		h[k] -= shift


# ── Painted finishing (sketch) ───────────────────────────────────────────────

## Red: craters packed in at shelling_per_hectare, sized from the Craters group.
static func _shell(r: Recipe, h: PackedFloat32Array, control: PackedByteArray, mask: PackedFloat32Array, sx: int, sz: int, cell: float) -> void:
	var spots := PackedInt32Array()
	for k in mask.size():
		if mask[k] > 0.5:
			spots.append(k)
	var target := roundi(spots.size() * cell * cell / 10000.0 * r.shelling_per_hectare)
	if spots.is_empty() or target <= 0:
		push_warning("TerrainGenerator: the red (shelled) paint covers too little ground for any craters at %.1f per hectare." % r.shelling_per_hectare)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = r.random_seed * 7907 + 11
	var rmin := minf(r.crater_radius_min, r.crater_radius_max)
	var rmax := maxf(r.crater_radius_min, r.crater_radius_max)
	for _c in target:
		var k := spots[rng.randi() % spots.size()]
		var radius := lerpf(rmin, rmax, pow(rng.randf(), 2.5))
		_add_crater(h, control, sx, sz, cell, float(k % sx) + rng.randf() - 0.5, floorf(float(k) / sx) + rng.randf() - 0.5,
				radius, radius * r.crater_depth, radius * r.crater_rim, 1.0)


## Grey: a street grid. Streets follow the lie of the land, each block is
## levelled to its own height — so a hillside town steps down in terraces —
## and every block wholly inside the paint becomes a building lot. Returns
## the lots (terrain-local; see TerrainData.lots).
static func _urbanise(r: Recipe, h: PackedFloat32Array, control: PackedByteArray, mask: PackedFloat32Array, sx: int, sz: int, cell: float, half_x: float, half_z: float) -> Array:
	var block := Vector2(maxf(r.urban_block.x, 4.0), maxf(r.urban_block.y, 4.0))
	var street := maxf(r.urban_street, 1.0)
	var period := block + Vector2(street, street)
	var ang := deg_to_rad(r.urban_angle)
	var ca := cos(ang)
	var sa := sin(ang)
	# The ground smoothed at block scale: what the streets follow.
	var base := h.duplicate()
	_wide_blur(base, sx, sz, maxf(block.x, block.y), cell)

	# Pass 1: each block's mean height, over its samples well inside the paint.
	var sums := {}
	for j in sz:
		var z := j * cell - half_z
		for i in sx:
			var k := j * sx + i
			if mask[k] < 0.5:
				continue
			var x := i * cell - half_x
			var gx := x * ca + z * sa
			var gz := -x * sa + z * ca
			var bx := floori(gx / period.x)
			var bz := floori(gz / period.y)
			if gx - bx * period.x >= block.x or gz - bz * period.y >= block.y:
				continue   # a street sample
			var key := Vector2i(bx, bz)
			sums[key] = (sums.get(key, Vector2.ZERO) as Vector2) + Vector2(base[k], 1.0)

	# Pass 2: shape and paint.
	for j in sz:
		var z := j * cell - half_z
		for i in sx:
			var k := j * sx + i
			var m := mask[k]
			if m <= 0.01:
				continue
			var x := i * cell - half_x
			var gx := x * ca + z * sa
			var gz := -x * sa + z * ca
			var bx := floori(gx / period.x)
			var bz := floori(gz / period.y)
			var key := Vector2i(bx, bz)
			var on_street := gx - bx * period.x >= block.x or gz - bz * period.y >= block.y
			var target := base[k]
			if not on_street and sums.has(key):
				var s: Vector2 = sums[key]
				target = s.x / s.y
			var w := smoothstep(0.25, 0.65, m)
			h[k] = lerpf(h[k], target, w)
			var c := k * Data.CONTROL_STRIDE
			if on_street:
				control[c + CH_ROAD] = maxi(control[c + CH_ROAD], int(w * 255.0))
			else:
				control[c + CH_PAD] = maxi(control[c + CH_PAD], int(w * 215.0))
				if _ruined(key, r):
					control[c + CH_HOLLOW] = maxi(control[c + CH_HOLLOW], int(w * 190.0))
					control[c + CH_SCORCH] = maxi(control[c + CH_SCORCH], int(w * 70.0))

	# Lots: blocks the paint covers almost entirely. A block the paint only
	# clips is ground, not a lot.
	var lots: Array = []
	var full := block.x * block.y / (cell * cell)
	for key: Vector2i in sums:
		var s: Vector2 = sums[key]
		if s.y < full * 0.8:
			continue
		var gcx := key.x * period.x + block.x * 0.5
		var gcz := key.y * period.y + block.y * 0.5
		lots.append({
			"centre": Vector2(gcx * ca - gcz * sa, gcx * sa + gcz * ca),
			"size": block - Vector2(2.0, 2.0),   # a metre of pavement all round
			"angle": -ang,
			"height": s.x / s.y,
			"ruined": _ruined(key, r),
		})
	if lots.is_empty():
		push_warning("TerrainGenerator: the grey (urban) paint is too small for a whole %.0f × %.0f m block, so it has streets but no building lots." % [block.x, block.y])
	return lots


## Magenta: every traced stroke becomes a graded ROAD path — the same cut and
## fill a TerrainPath does — `road_width` metres for each pixel of stroke
## thickness, bridged over painted water. Returns the bridge spans.
static func _sketch_roads(r: Recipe, roads: Array, sketch_px: Vector2i, h: PackedFloat32Array, control: PackedByteArray, water: PackedByteArray, sx: int, sz: int, cell: float, half_x: float, half_z: float) -> Array:
	var mpp := Vector2(half_x * 2.0 / sketch_px.x, half_z * 2.0 / sketch_px.y)
	var bridges: Array = []
	for road in roads:
		var line := PackedVector2Array()
		for p: Vector2 in road.pixels:
			line.append(Vector2(p.x * mpp.x - half_x, p.y * mpp.y - half_z))
		# Pixel centres make a staircase on every diagonal: round it off,
		# then space the points evenly so grading treats every metre alike.
		var smooth := _chaikin(line, 3)
		var m := {
			"type": "path",
			"source": "sketch road",
			"mode": PATH_ROAD,
			"points": _resample(smooth, maxf(cell, 2.0)),
			"width": r.road_width * float(road.width_px),
			"falloff": r.road_falloff,
			"depth": 0.0,
			"follow_terrain": true,
			"smoothing": r.road_smoothing,
			"paint": true,
		}
		bridges.append_array(_apply_path(m, h, control, sx, sz, cell, half_x, half_z, water, r.water_level + r.bridge_clearance))
	return bridges


## Chaikin corner cutting. Keeps both end points, so roads that meet at a
## junction still meet after smoothing.
static func _chaikin(p: PackedVector2Array, iterations: int) -> PackedVector2Array:
	for _i in iterations:
		if p.size() < 3:
			return p
		var out := PackedVector2Array([p[0]])
		for k in p.size() - 1:
			out.append(p[k].lerp(p[k + 1], 0.25))
			out.append(p[k].lerp(p[k + 1], 0.75))
		out.append(p[p.size() - 1])
		p = out
	return p


## A polyline as points `spacing` metres apart (x, 0, z), ends included.
static func _resample(line: PackedVector2Array, spacing: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if line.size() < 2:
		for p in line:
			out.append(Vector3(p.x, 0.0, p.y))
		return out
	out.append(Vector3(line[0].x, 0.0, line[0].y))
	var carry := 0.0
	for k in line.size() - 1:
		var a := line[k]
		var b := line[k + 1]
		var seg := a.distance_to(b)
		var t := spacing - carry
		while t < seg:
			var p := a.lerp(b, t / seg)
			out.append(Vector3(p.x, 0.0, p.y))
			t += spacing
		carry = seg - (t - spacing)
	var last := line[line.size() - 1]
	if Vector2(out[out.size() - 1].x, out[out.size() - 1].z).distance_to(last) > spacing * 0.25:
		out.append(Vector3(last.x, 0.0, last.y))
	return out


## Drops building lots a road has run through: a lot must still be level at
## its recorded height and carry no road paint well inside its edges.
static func _drop_blocked_lots(lots: Array, h: PackedFloat32Array, control: PackedByteArray, sx: int, sz: int, cell: float, half_x: float, half_z: float) -> Array:
	var kept: Array = []
	for lot in lots:
		var centre: Vector2 = lot.centre
		var size: Vector2 = lot.size
		var angle := float(lot.angle)
		# Inset a little over a cell: the streets round a block are painted
		# road too, and a nearest-sample lookup at the very edge would hit them.
		var inset := Vector2(minf(cell * 1.25 + 0.5, size.x * 0.4), minf(cell * 1.25 + 0.5, size.y * 0.4))
		var half := size * 0.5 - inset
		var ca := cos(angle)
		var sa := sin(angle)
		var clear := true
		for s in [Vector2(0, 0), Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
			var o := Vector2(s.x * half.x, s.y * half.y)
			# Basis(UP, angle) turns local x toward (cos, -sin) in x/z.
			var p := centre + Vector2(o.x * ca + o.y * sa, -o.x * sa + o.y * ca)
			if absf(sample_height(h, sx, sz, cell, p.x, p.y) - float(lot.height)) > 0.05:
				clear = false
				break
			var i := clampi(roundi((p.x + half_x) / cell), 0, sx - 1)
			var j := clampi(roundi((p.y + half_z) / cell), 0, sz - 1)
			if control[(j * sx + i) * Data.CONTROL_STRIDE + CH_ROAD] > 128:
				clear = false
				break
		if clear:
			kept.append(lot)
	return kept


## Whether a block is rubble: fixed per block and seed, independent of scan order.
static func _ruined(key: Vector2i, r: Recipe) -> bool:
	return absi(hash(Vector3i(key.x, key.y, r.random_seed))) % 1000 < int(r.urban_ruin * 1000.0)


## Blue: water at water_level. The bed shelves down from the shoreline to
## water_depth, the land within water_bank slopes down to meet it with a dry
## lip just above the waterline, and the shore is painted dark and wet.
## Returns where the water surface should be drawn.
static func _flood(r: Recipe, h: PackedFloat32Array, control: PackedByteArray, mask: PackedFloat32Array, sx: int, sz: int, cell: float) -> PackedByteArray:
	var n := sx * sz
	var inside := PackedByteArray()
	inside.resize(n)
	var wet := 0
	for k in n:
		if mask[k] > 0.5:
			inside[k] = 1
			wet += 1
	if wet == 0:
		push_warning("TerrainGenerator: the blue (water) paint is too small to survive blending — paint it bigger or lower sketch_blend.")
		return PackedByteArray()
	var to_shore := Sketch.chamfer(inside, 0, sx, sz)    # inside: cells to the nearest dry sample
	var to_water := Sketch.chamfer(inside, 1, sx, sz)    # outside: cells to the nearest wet sample
	var level := r.water_level
	var bank := maxf(r.water_bank, 0.0)
	var surface := PackedByteArray()
	surface.resize(n)
	for k in n:
		var c := k * Data.CONTROL_STRIDE + CH_HOLLOW
		if inside[k] == 1:
			var from_shore := to_shore[k] * cell
			h[k] = minf(h[k], level - minf(r.water_depth, 0.3 + from_shore * 0.3))
			surface[k] = 255
			control[c] = 255
			continue
		var d := to_water[k] * cell
		if d < bank:
			# Never below the lip (no dry pit beside the water), never above a
			# gentle rise away from it.
			var rise := maxf(level + 0.3 + d * 0.12, level + 0.25)
			var w := 1.0 - smoothstep(bank * 0.6, bank, d)
			h[k] = lerpf(h[k], clampf(h[k], level + 0.25, rise), w)
		if d <= cell * 2.0:
			surface[k] = 255   # a sliver of bank under the surface: a clean waterline
		control[c] = maxi(control[c], int((1.0 - smoothstep(0.0, 6.0, d)) * 200.0))
	return surface


# ── Modifiers ────────────────────────────────────────────────────────────────

static func _apply_stamp(m: Dictionary, h: PackedFloat32Array, control: PackedByteArray, sx: int, sz: int, cell: float, half_x: float, half_z: float) -> void:
	var shape := int(m.get("shape", STAMP_FLATTEN))
	var centre: Vector2 = m.get("centre", Vector2.ZERO)
	var target_y := float(m.get("y", 0.0))
	var radius := maxf(float(m.get("radius", 10.0)), 0.1)
	var rect := int(m.get("footprint", FOOTPRINT_CIRCLE)) == FOOTPRINT_RECT
	var half: Vector2 = m.get("half_size", Vector2(10.0, 10.0))
	half = Vector2(maxf(half.x, 0.05), maxf(half.y, 0.05))
	var ax: Vector2 = m.get("axis_x", Vector2(1.0, 0.0))
	var az: Vector2 = m.get("axis_z", Vector2(0.0, 1.0))
	var falloff := maxf(float(m.get("falloff", 0.0)), 0.0)
	var amount := float(m.get("amount", 0.0))
	var strength := clampf(float(m.get("strength", 1.0)), 0.0, 1.0)
	var paint := int(m.get("paint", PAINT_NONE))
	var source := str(m.get("source", "stamp"))

	var gx := (centre.x + half_x) / cell
	var gz := (centre.y + half_z) / cell
	if shape == STAMP_CRATER:
		var scorch := strength if paint == PAINT_SCORCH else 0.0
		_add_crater(h, control, sx, sz, cell, gx, gz, radius, amount * strength, amount * 0.35 * strength, scorch)
		return

	var reach := ((half.length() if rect else radius) + falloff) / cell
	var i0 := maxi(0, floori(gx - reach))
	var i1 := mini(sx - 1, ceili(gx + reach))
	var j0 := maxi(0, floori(gz - reach))
	var j1 := mini(sz - 1, ceili(gz + reach))
	if i0 > i1 or j0 > j1:
		push_warning("TerrainGenerator: %s sits entirely off the map (local %s) — skipped." % [source, centre])
		return
	var paint_ch := _paint_channel(paint)
	var paint_edge := minf(falloff, PAINT_EDGE)
	for j in range(j0, j1 + 1):
		var pz := j * cell - half_z
		for i in range(i0, i1 + 1):
			var rel := Vector2(i * cell - half_x, pz) - centre
			var d: float   # signed distance to the footprint edge, metres
			if rect:
				var qx := absf(rel.dot(ax)) - half.x
				var qz := absf(rel.dot(az)) - half.y
				d = Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length() + minf(maxf(qx, qz), 0.0)
			else:
				d = rel.length() - radius
			var w := _edge_weight(d, falloff) * strength
			if w <= 0.0:
				continue
			var k := j * sx + i
			match shape:
				STAMP_FLATTEN:
					h[k] = lerpf(h[k], target_y, w)
				STAMP_RAISE:
					h[k] += amount * w
				STAMP_LOWER:
					h[k] -= amount * w
			if paint_ch >= 0:
				var c := k * Data.CONTROL_STRIDE + paint_ch
				control[c] = maxi(control[c], int(_edge_weight(d, paint_edge) * strength * 255.0))


## Cuts one path into the ground. Returns its bridge spans: when `water` (a
## TerrainData.water coverage array) is given and the path is a ROAD, the road
## is carried across every stretch of drawn water at the height of its banks —
## at least `deck`, climbing to it on embankments where the banks are lower —
## and the water itself is left alone: no causeway dammed across the river.
## Each span is {start: Vector3, end: Vector3, width: float}, terrain-local,
## from the last dry road point before the water to the first one after it.
## Without water, or for any other mode, this cuts exactly as it always has.
static func _apply_path(m: Dictionary, h: PackedFloat32Array, control: PackedByteArray, sx: int, sz: int, cell: float, half_x: float, half_z: float, water: PackedByteArray = PackedByteArray(), deck: float = -INF) -> Array:
	var pts: PackedVector3Array = m.get("points", PackedVector3Array())
	var source := str(m.get("source", "path"))
	if pts.size() < 2:
		push_warning("TerrainGenerator: %s has %d point(s); a path needs at least 2 — skipped." % [source, pts.size()])
		return []
	var mode := int(m.get("mode", PATH_ROAD))
	var half_w := maxf(float(m.get("width", 8.0)), 0.1) * 0.5
	var falloff := maxf(float(m.get("falloff", 6.0)), 0.0)
	var depth := float(m.get("depth", 2.0))
	var follow := bool(m.get("follow_terrain", true))
	var smoothing := maxf(float(m.get("smoothing", 40.0)), 0.0)
	var paint := bool(m.get("paint", true))
	var count := pts.size()
	var bridging := mode == PATH_ROAD and not water.is_empty()

	# 1. Height profile along the path: the ground under it, or the curve's own Y.
	var ys := PackedFloat32Array()
	ys.resize(count)
	var length := 0.0
	for p in count:
		ys[p] = sample_height(h, sx, sz, cell, pts[p].x, pts[p].z) if follow else pts[p].y
		if p > 0:
			length += Vector2(pts[p].x - pts[p - 1].x, pts[p].z - pts[p - 1].z).length()
	var wet := PackedByteArray()
	if bridging:
		wet.resize(count)
		for p in count:
			wet[p] = 1 if _water_at(water, sx, sz, cell, half_x, half_z, pts[p].x, pts[p].z) else 0
	var spacing := maxf(length / (count - 1), 0.01)
	if bridging and follow:
		# Under water the ground is the river bottom: carry the road over
		# at the height of its banks, as a bridge would. Banks sit barely
		# above the waterline, so lift the span to the deck as well — a
		# bridge level with the water has its girders in it.
		_span_wet_runs(ys, wet)
		_lift_over_water(ys, wet, deck, spacing)
	if follow and smoothing > 0.0 and count > 2:
		# A road that copied every bump of the ground would be a roller coaster.
		var win := clampi(int(smoothing / spacing * 0.5), 1, count)
		for _pass in 2:
			ys = _smooth_1d(ys, win)
		if bridging:
			# Smoothing sags the deck toward its lower approaches. Lift again
			# so the clearance holds exactly rather than roughly.
			_lift_over_water(ys, wet, deck, spacing)

	# 2. What each point wants the ground to become.
	var offset := 0.0
	match mode:
		PATH_TRENCH, PATH_RIVERBED:
			offset = -depth
		PATH_BERM:
			offset = depth
	for p in count:
		ys[p] += offset

	# 3. Nearest-segment distance and target height for every sample in reach.
	var reach := half_w + falloff
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var ri0 := maxi(0, floori((lo.x - reach + half_x) / cell))
	var ri1 := mini(sx - 1, ceili((hi.x + reach + half_x) / cell))
	var rj0 := maxi(0, floori((lo.y - reach + half_z) / cell))
	var rj1 := mini(sz - 1, ceili((hi.y + reach + half_z) / cell))
	if ri0 > ri1 or rj0 > rj1:
		push_warning("TerrainGenerator: %s lies entirely off the map — skipped." % source)
		return []
	var rw := ri1 - ri0 + 1
	var rh := rj1 - rj0 + 1
	var best_d := PackedFloat32Array()
	best_d.resize(rw * rh)
	best_d.fill(INF)
	var best_y := PackedFloat32Array()
	best_y.resize(rw * rh)
	for p in count - 1:
		var a := Vector2(pts[p].x, pts[p].z)
		var b := Vector2(pts[p + 1].x, pts[p + 1].z)
		var ab := b - a
		var len2 := ab.length_squared()
		var si0 := maxi(ri0, floori((minf(a.x, b.x) - reach + half_x) / cell))
		var si1 := mini(ri1, ceili((maxf(a.x, b.x) + reach + half_x) / cell))
		var sj0 := maxi(rj0, floori((minf(a.y, b.y) - reach + half_z) / cell))
		var sj1 := mini(rj1, ceili((maxf(a.y, b.y) + reach + half_z) / cell))
		for j in range(sj0, sj1 + 1):
			var pz := j * cell - half_z
			for i in range(si0, si1 + 1):
				var q := Vector2(i * cell - half_x, pz)
				var t := 0.0 if len2 < 1e-8 else clampf((q - a).dot(ab) / len2, 0.0, 1.0)
				var d := q.distance_to(a + ab * t)
				var r := (j - rj0) * rw + (i - ri0)
				if d < best_d[r]:
					best_d[r] = d
					best_y[r] = lerpf(ys[p], ys[p + 1], t)

	# 4. Blend the ground toward the target.
	var ch := -1
	if paint:
		match mode:
			PATH_ROAD:
				ch = CH_ROAD
			PATH_TRENCH, PATH_RIVERBED:
				ch = CH_HOLLOW
	var paint_edge := minf(falloff, PAINT_EDGE)
	for j in range(rj0, rj1 + 1):
		for i in range(ri0, ri1 + 1):
			var r := (j - rj0) * rw + (i - ri0)
			var d := best_d[r] - half_w
			var w := _edge_weight(d, falloff)
			if w <= 0.0:
				continue
			var k := j * sx + i
			if bridging and water[k] > 0:
				continue   # leave the water to the bridge
			var ty := best_y[r]
			match mode:
				PATH_ROAD:
					h[k] = lerpf(h[k], ty, w)   # cut AND fill: a road is level
				PATH_TRENCH, PATH_RIVERBED:
					h[k] = lerpf(h[k], minf(h[k], ty), w)   # only ever digs
				PATH_BERM:
					h[k] = lerpf(h[k], maxf(h[k], ty), w)   # only ever builds up
			if ch >= 0:
				var c := k * Data.CONTROL_STRIDE + ch
				control[c] = maxi(control[c], int(_edge_weight(d, paint_edge) * 255.0))

	# 5. Bridge spans: every wet stretch with dry road at both ends. A road that
	# runs INTO water and stops there is a slipway, not a bridge.
	var spans: Array = []
	if bridging:
		var p := 0
		while p < count:
			if wet[p] == 0:
				p += 1
				continue
			var first := p
			while p < count and wet[p] == 1:
				p += 1
			if first > 0 and p < count:
				spans.append({
					"start": Vector3(pts[first - 1].x, ys[first - 1], pts[first - 1].z),
					"end": Vector3(pts[p].x, ys[p], pts[p].z),
					"width": half_w * 2.0,
				})
	return spans


## Whether drawn water covers the nearest sample to a terrain-local (x, z).
static func _water_at(water: PackedByteArray, sx: int, sz: int, cell: float, half_x: float, half_z: float, x: float, z: float) -> bool:
	var i := clampi(roundi((x + half_x) / cell), 0, sx - 1)
	var j := clampi(roundi((z + half_z) / cell), 0, sz - 1)
	return water[j * sx + i] > 0


## Replaces each wet stretch of a profile with a straight line between the
## dry values either side (or the one dry side, at a path's end).
static func _span_wet_runs(ys: PackedFloat32Array, wet: PackedByteArray) -> void:
	var count := ys.size()
	var p := 0
	while p < count:
		if wet[p] == 0:
			p += 1
			continue
		var first := p
		while p < count and wet[p] == 1:
			p += 1
		var before := ys[first - 1] if first > 0 else NAN
		var after := ys[p] if p < count else NAN
		if is_nan(before) and is_nan(after):
			return   # the whole path is under water: nothing dry to carry it from
		if is_nan(before):
			before = after
		if is_nan(after):
			after = before
		for q in range(first, p):
			ys[q] = lerpf(before, after, float(q - first + 1) / float(p - first + 1))


## Holds each bridged stretch of a profile at `deck` or above, and the road
## either side at no less than a BRIDGE_RAMP climb up to it. Only stretches
## with dry road at both ends count: a road that runs into the water and
## stops is a slipway, and a slipway goes down to the water, not over it.
## `spacing` is the distance between profile points, in metres.
static func _lift_over_water(ys: PackedFloat32Array, wet: PackedByteArray, deck: float, spacing: float) -> void:
	if is_inf(deck):
		return   # no deck height asked for: the banks decide, as they always did
	var count := ys.size()
	var bridged := PackedByteArray()
	bridged.resize(count)
	var p := 0
	var any := false
	while p < count:
		if wet[p] == 0:
			p += 1
			continue
		var first := p
		while p < count and wet[p] == 1:
			p += 1
		if first > 0 and p < count:
			for q in range(first, p):
				bridged[q] = 1
			any = true
	if not any:
		return   # this road crosses no water bank to bank: nothing to lift
	# Two sweeps: each point learns how far it is from the nearest bridged
	# point behind it, then ahead of it. The ramp is a floor, never a cut.
	var step := spacing * BRIDGE_RAMP
	var floor_y := -INF
	for q in count:
		floor_y = deck if bridged[q] == 1 else floor_y - step
		ys[q] = maxf(ys[q], floor_y)
	floor_y = -INF
	for q in range(count - 1, -1, -1):
		floor_y = deck if bridged[q] == 1 else floor_y - step
		ys[q] = maxf(ys[q], floor_y)


## 1 inside (d <= 0), easing to 0 at `falloff` metres outside.
static func _edge_weight(d: float, falloff: float) -> float:
	if d <= 0.0:
		return 1.0
	if falloff <= 0.001:
		return 0.0
	return 1.0 - smoothstep(0.0, falloff, d)


static func _paint_channel(paint: int) -> int:
	match paint:
		PAINT_PAD:
			return CH_PAD
		PAINT_ROAD:
			return CH_ROAD
		PAINT_SCORCH:
			return CH_SCORCH
		PAINT_RUBBLE:
			return CH_HOLLOW
	return -1


static func _smooth_1d(v: PackedFloat32Array, half_window: int) -> PackedFloat32Array:
	var count := v.size()
	var out := PackedFloat32Array()
	out.resize(count)
	# Running sum, window clamped at the ends so the endpoints keep their height.
	var prefix := PackedFloat64Array()
	prefix.resize(count + 1)
	for i in count:
		prefix[i + 1] = prefix[i] + v[i]
	for i in count:
		var w := mini(half_window, mini(i, count - 1 - i))
		out[i] = (prefix[i + w + 1] - prefix[i - w]) / (2 * w + 1)
	return out


## Dark, damp ground in dips: how far each sample sits below the average of its
## surroundings. Feeds the shader's rubble and darkening, and costs nothing at
## runtime because it is baked into the control alpha.
static func _hollows(h: PackedFloat32Array, control: PackedByteArray, sx: int, sz: int, cell: float) -> void:
	var around := h.duplicate()
	_blur(around, sx, sz, clampi(roundi(6.0 / cell), 1, 6))
	for k in h.size():
		var c := k * Data.CONTROL_STRIDE + CH_HOLLOW
		var hollow := (around[k] - h[k]) / 0.6   # 0.6 m below its surroundings = fully hollow
		control[c] = maxi(control[c], clampi(int(hollow * 255.0), 0, 255))


## Height on a raw array at a terrain-local (x, z), using the collision's
## triangle split. Clamps to the map edge.
static func sample_height(h: PackedFloat32Array, sx: int, sz: int, cell: float, x: float, z: float) -> float:
	var gx := clampf((x + (sx - 1) * cell * 0.5) / cell, 0.0, sx - 1.0)
	var gz := clampf((z + (sz - 1) * cell * 0.5) / cell, 0.0, sz - 1.0)
	var i := mini(int(gx), sx - 2)
	var j := mini(int(gz), sz - 2)
	var u := gx - i
	var v := gz - j
	var k := j * sx + i
	if u + v <= 1.0:
		return h[k] + u * (h[k + 1] - h[k]) + v * (h[k + sx] - h[k])
	var h11 := h[k + sx + 1]
	return h11 + (1.0 - u) * (h[k + sx] - h11) + (1.0 - v) * (h[k + 1] - h11)
