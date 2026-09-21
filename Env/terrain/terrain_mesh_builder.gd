@tool
class_name TerrainMeshBuilder
extends RefCounted

# ─────────────────────────────────────────────
# TERRAIN MESH BUILDER — TerrainData in, render chunks and collision tiles out.
#
# RENDER: the map is cut into square chunks of `chunk_cells` cells. Each chunk
# is one ArrayMesh carrying every LOD as an extra index buffer over the same
# vertices, so Godot's own mesh LOD picks the level per chunk with no script
# running per frame. Every chunk has the same vertex layout, so the index
# buffers are identical too — built once and shared by every chunk.
#
# SKIRTS: neighbouring chunks can sit at different LODs, and where they meet
# the coarser edge skips vertices the finer one keeps, opening hairline cracks.
# Each chunk hangs a strip of wall below its edge, facing outward, which plugs
# any crack seen from either side. Skirts are never visible from above.
#
# COLLISION: square HeightMapShape3D tiles, scaled uniformly by the cell size.
# Square because godot-jolt only builds Jolt's native height field for square
# maps and silently falls back to a far slower triangle mesh for anything else.
#
# TRIANGULATION: every cell is split along its (x+1, z)–(x, z+1) diagonal, the
# split HeightMapShape3D uses in Godot Physics and in Jolt. The LOD0 mesh is
# therefore exactly the collision surface, so feet and bullet holes land on
# what you see.
# ─────────────────────────────────────────────

const Data := preload("res://Env/terrain/terrain_data.gd")

## How hard paint (roads, scorch, pads) resists LOD. A coarse LOD that would
## smear paint across ~20 px of screen is refused until the chunk is further
## away. Without it a flat chunk, whose geometric error is zero, would drop to
## its coarsest LOD at any distance and its road would dissolve at your feet.
const PAINT_ERROR_WEIGHT := 0.05

## Skirt depth bounds, metres.
const SKIRT_MIN := 1.0
const SKIRT_MAX := 64.0


## Index buffer per LOD, shared by every chunk. LOD n steps 2ⁿ cells.
static func build_lod_indices(c: int, lod_count: int) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var grid := (c + 1) * (c + 1)
	var perimeter := 4 * c
	for lod in lod_count:
		var s := 1 << lod
		@warning_ignore("integer_division")
		var cells := c / s
		var idx := PackedInt32Array()
		idx.resize(cells * cells * 6 + 4 * cells * 6)
		var w := 0
		for z in range(0, c, s):
			for x in range(0, c, s):
				var a := z * (c + 1) + x
				var b := a + s
				var d := a + s * (c + 1)
				var e := d + s
				# Clockwise seen from above — Godot's front face.
				idx[w] = a
				idx[w + 1] = b
				idx[w + 2] = d
				idx[w + 3] = b
				idx[w + 4] = e
				idx[w + 5] = d
				w += 6
		# Walking the perimeter clockwise from above, (edge, skirt, next edge)
		# faces outward on every side.
		for p in range(0, perimeter, s):
			var p2 := (p + s) % perimeter
			var top_a := perimeter_vertex(p, c)
			var top_b := perimeter_vertex(p2, c)
			idx[w] = top_a
			idx[w + 1] = grid + p
			idx[w + 2] = top_b
			idx[w + 3] = top_b
			idx[w + 4] = grid + p
			idx[w + 5] = grid + p2
			w += 6
		out.append(idx)
	return out


## Grid vertex index of perimeter position p (0 … 4c-1), walking clockwise
## from above: +X along z=0, +Z along x=c, -X along z=c, -Z along x=0.
static func perimeter_vertex(p: int, c: int) -> int:
	if p < c:
		return p
	if p < 2 * c:
		return (p - c) * (c + 1) + c
	if p < 3 * c:
		return c * (c + 1) + (3 * c - p)
	return (4 * c - p) * (c + 1)


## Smooth vertex normals for the whole map, from central differences. Built
## once over the full grid so chunk edges share identical normals — per-chunk
## normals would put a lighting seam along every chunk border.
static func compute_normals(data: Data) -> PackedVector3Array:
	var sx := data.cells_x + 1
	var sz := data.cells_z + 1
	var cell := data.cell_size
	var h := data.heights
	var out := PackedVector3Array()
	out.resize(sx * sz)
	for j in sz:
		var j_lo := maxi(j - 1, 0)
		var j_hi := mini(j + 1, sz - 1)
		var up := j_lo * sx
		var down := j_hi * sx
		var zspan := (j_hi - j_lo) * cell
		var row := j * sx
		for i in sx:
			var i_lo := maxi(i - 1, 0)
			var i_hi := mini(i + 1, sx - 1)
			var xspan := (i_hi - i_lo) * cell
			out[row + i] = Vector3((h[row + i_lo] - h[row + i_hi]) / xspan, 1.0,
					(h[up + i] - h[down + i]) / zspan).normalized()
	return out


## How deep the skirts hang: enough to cover the worst gap two neighbouring
## chunks at different LODs can open (at most the sum of their errors).
static func skirt_depth(data: Data) -> float:
	var worst := 0.0
	for e in data.lod_errors:
		worst = maxf(worst, e)
	return clampf(worst * 2.0 + data.cell_size * 0.5, SKIRT_MIN, SKIRT_MAX)


## One chunk: (c+1)² grid vertices then 4c skirt vertices, every LOD attached.
##
## Vertex data the shader reads:
##   COLOR  control paint — r road, g scorch, b pad, a hollow
##   UV     position across the whole terrain, 0…1
##   UV2    x = border-mountain factor, y = height within the map's range, 0…1
static func build_chunk(data: Data, normals: PackedVector3Array, cx: int, cz: int, lod_indices: Array[PackedInt32Array], skirt: float) -> ArrayMesh:
	var c := data.chunk_cells
	var sx := data.cells_x + 1
	var grid := (c + 1) * (c + 1)
	var count := grid + 4 * c
	var cell := data.cell_size
	var half_x := data.width() * 0.5
	var half_z := data.depth() * 0.5
	var inv_w := 1.0 / data.cells_x
	var inv_d := 1.0 / data.cells_z
	var h_min := data.min_height
	var inv_span := 1.0 / maxf(data.max_height - data.min_height, 0.001)
	var h := data.heights
	var ctl := data.control
	var zone := data.zone

	var verts := PackedVector3Array()
	verts.resize(count)
	var norms := PackedVector3Array()
	norms.resize(count)
	var colors := PackedColorArray()
	colors.resize(count)
	var uvs := PackedVector2Array()
	uvs.resize(count)
	var uv2s := PackedVector2Array()
	uv2s.resize(count)

	var v := 0
	for z in c + 1:
		var gj := cz * c + z
		var row := gj * sx
		var pz := gj * cell - half_z
		for x in c + 1:
			var gi := cx * c + x
			var k := row + gi
			var hk := h[k]
			var b := k * Data.CONTROL_STRIDE
			verts[v] = Vector3(gi * cell - half_x, hk, pz)
			norms[v] = normals[k]
			colors[v] = Color(ctl[b] / 255.0, ctl[b + 1] / 255.0, ctl[b + 2] / 255.0, ctl[b + 3] / 255.0)
			uvs[v] = Vector2(gi * inv_w, gj * inv_d)
			uv2s[v] = Vector2(zone[k] / 255.0, (hk - h_min) * inv_span)
			v += 1
	# Skirt vertices copy their edge vertex's normal and paint, so the strip
	# shades like the ground it hangs from.
	var drop := Vector3(0.0, skirt, 0.0)
	for p in 4 * c:
		var src := perimeter_vertex(p, c)
		var dst := grid + p
		verts[dst] = verts[src] - drop
		norms[dst] = norms[src]
		colors[dst] = colors[src]
		uvs[dst] = uvs[src]
		uv2s[dst] = uv2s[src]

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = lod_indices[0]

	# LOD keys are the chunk's own worst error in metres; the renderer uses a
	# LOD once that error projects under mesh_lod_threshold pixels. Keys must be
	# positive and strictly increasing, or RenderingServer drops the level with
	# an error — a dead-flat chunk has an error of exactly zero at every LOD.
	var lods := {}
	var base := (cz * data.chunks_x() + cx) * data.lod_count
	var have_errors := data.lod_errors.size() == data.chunks_x() * data.chunks_z() * data.lod_count
	var prev := 0.0
	for lod in range(1, lod_indices.size()):
		var err: float = data.lod_errors[base + lod] if have_errors else cell * (1 << lod)
		var key := maxf(err, prev + 0.001)
		lods[key] = lod_indices[lod]
		prev = key

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	return mesh


## Worst error of every chunk at every LOD, chunk-major (chunk * lod_count +
## lod; LOD0 is always 0). Geometric error is how far the coarse surface strays
## from the full-resolution heights. Paint error is how much road/scorch/pad
## paint varies inside a coarse cell, scaled by the cell's size — see
## PAINT_ERROR_WEIGHT. The hollow channel is left out on purpose: it varies
## everywhere and would pin every chunk at full detail.
static func compute_lod_errors(data: Data) -> PackedFloat32Array:
	var c := data.chunk_cells
	var lods := data.lod_count
	var cxn := data.chunks_x()
	var czn := data.chunks_z()
	var sx := data.cells_x + 1
	var h := data.heights
	var ctl := data.control
	var stride := Data.CONTROL_STRIDE
	var out := PackedFloat32Array()
	out.resize(cxn * czn * lods)
	for cz in czn:
		for cx in cxn:
			var origin := cz * c * sx + cx * c
			# Most chunks carry no paint at all; skip the paint pass for those.
			var painted := false
			for z in c + 1:
				var row := origin + z * sx
				for x in c + 1:
					var b := (row + x) * stride
					if ctl[b] > 0 or ctl[b + 1] > 0 or ctl[b + 2] > 0:
						painted = true
						break
				if painted:
					break
			var base := (cz * cxn + cx) * lods
			for lod in range(1, lods):
				var s := 1 << lod
				var inv_s := 1.0 / s
				var geo := 0.0
				var smear := 0
				for bz in range(0, c, s):
					for bx in range(0, c, s):
						var k00 := origin + bz * sx + bx
						var h00 := h[k00]
						var h10 := h[k00 + s]
						var h01 := h[k00 + s * sx]
						var h11 := h[k00 + s * sx + s]
						for z in s + 1:
							var v := z * inv_s
							var row := k00 + z * sx
							for x in s + 1:
								var u := x * inv_s
								var coarse: float
								if u + v <= 1.0:
									coarse = h00 + u * (h10 - h00) + v * (h01 - h00)
								else:
									coarse = h11 + (1.0 - u) * (h01 - h11) + (1.0 - v) * (h10 - h11)
								geo = maxf(geo, absf(h[row + x] - coarse))
						if painted:
							# Conservative: the paint range inside the block.
							for ch in 3:
								var lo := 255
								var hi := 0
								for z in s + 1:
									var row := k00 + z * sx
									for x in s + 1:
										var p := ctl[(row + x) * stride + ch]
										lo = mini(lo, p)
										hi = maxi(hi, p)
								smear = maxi(smear, hi - lo)
				var paint_err := smear / 255.0 * s * data.cell_size * PAINT_ERROR_WEIGHT
				out[base + lod] = maxf(geo, paint_err)
	return out


## Edge of a collision tile in cells: the largest of 256 / 128 / 64 dividing
## the map both ways. Bigger tiles mean fewer seams for a sliding body to catch.
static func collision_tile_cells(data: Data) -> int:
	for t in [256, 128, 64]:
		if data.cells_x % t == 0 and data.cells_z % t == 0:
			return t
	push_warning("TerrainMeshBuilder: %d × %d cells has no 64-multiple tiling; using %d-cell collision tiles." % [data.cells_x, data.cells_z, data.chunk_cells])
	return data.chunk_cells


## One square HeightMapShape3D per tile, with where its CollisionShape3D goes.
## The shape stores heights ÷ cell_size and the node is scaled UP by cell_size:
## a HeightMapShape3D always spaces its samples one unit apart, and a uniform
## scale is the only kind every physics engine handles on every shape.
static func build_collision_tiles(data: Data) -> Array[Dictionary]:
	var t := collision_tile_cells(data)
	var sx := data.cells_x + 1
	var cell := data.cell_size
	var inv := 1.0 / cell
	var h := data.heights
	var half_x := data.width() * 0.5
	var half_z := data.depth() * 0.5
	var out: Array[Dictionary] = []
	@warning_ignore("integer_division")
	var tiles_x := data.cells_x / t
	@warning_ignore("integer_division")
	var tiles_z := data.cells_z / t
	for tz in tiles_z:
		for tx in tiles_x:
			var md := PackedFloat32Array()
			md.resize((t + 1) * (t + 1))
			var w := 0
			for z in t + 1:
				var row := (tz * t + z) * sx + tx * t
				for x in t + 1:
					md[w] = h[row + x] * inv
					w += 1
			var shape := HeightMapShape3D.new()
			shape.map_width = t + 1
			shape.map_depth = t + 1
			shape.map_data = md
			out.append({
				"name": "Tile_%d_%d" % [tx, tz],
				"shape": shape,
				"position": Vector3((tx + 0.5) * t * cell - half_x, 0.0, (tz + 0.5) * t * cell - half_z),
				"scale": cell,
			})
	return out


## Metres of water over which the surface shades from shallow to deep.
const WATER_DEPTH_SCALE := 6.0


## One chunk's water surface: a flat grid at data.water_level over every cell
## that touches a wet sample, or null when the chunk is dry. COLOR.r carries
## the depth below the surface (0 at the waterline … 1 at WATER_DEPTH_SCALE),
## so the shader can shade shallows, shoreline and deep water without reading
## the depth buffer — which the Compatibility renderer makes costly.
static func build_water_chunk(data: Data, cx: int, cz: int) -> ArrayMesh:
	if not data.has_water():
		return null
	var c := data.chunk_cells
	var sx := data.cells_x + 1
	var w := data.water
	var h := data.heights
	var cell := data.cell_size
	var half_x := data.width() * 0.5
	var half_z := data.depth() * 0.5
	var level := data.water_level
	var origin := cz * c * sx + cx * c
	var idx := PackedInt32Array()
	for z in c:
		var row := origin + z * sx
		for x in c:
			var k := row + x
			if w[k] == 0 and w[k + 1] == 0 and w[k + sx] == 0 and w[k + sx + 1] == 0:
				continue
			var a := z * (c + 1) + x
			idx.append_array(PackedInt32Array([a, a + 1, a + c + 1, a + 1, a + c + 2, a + c + 1]))
	if idx.is_empty():
		return null
	var count := (c + 1) * (c + 1)
	var verts := PackedVector3Array()
	verts.resize(count)
	var colors := PackedColorArray()
	colors.resize(count)
	var norms := PackedVector3Array()
	norms.resize(count)
	var v := 0
	for z in c + 1:
		var gj := cz * c + z
		for x in c + 1:
			var gi := cx * c + x
			var k := gj * sx + gi
			verts[v] = Vector3(gi * cell - half_x, level, gj * cell - half_z)
			colors[v] = Color(clampf((level - h[k]) / WATER_DEPTH_SCALE, 0.0, 1.0), 0.0, 0.0, 1.0)
			norms[v] = Vector3.UP
			v += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Share of a map edge that must be water before open sea runs on past it.
## A river leaving the map touches a sliver of the edge and must not trigger
## a sea three kilometres wide beyond it; a coast is a good stretch of edge.
const SEA_EDGE_SHARE := 0.25


## Open water past the map edge, on each side that is coast (see
## SEA_EDGE_SHARE), so an island's sea runs to the horizon instead of stopping
## at a cliff of nothing. Null when no side is coast.
static func build_water_apron(data: Data, reach: float = 3000.0) -> ArrayMesh:
	if not data.has_water():
		return null
	var sx := data.cells_x + 1
	var sz := data.cells_z + 1
	var w := data.water
	var counts := [0, 0, 0, 0]   # north (-z), south (+z), west (-x), east (+x)
	for i in sx:
		counts[0] += 1 if w[i] > 0 else 0
		counts[1] += 1 if w[(sz - 1) * sx + i] > 0 else 0
	for j in sz:
		counts[2] += 1 if w[j * sx] > 0 else 0
		counts[3] += 1 if w[j * sx + sx - 1] > 0 else 0
	var wet := [counts[0] >= sx * SEA_EDGE_SHARE, counts[1] >= sx * SEA_EDGE_SHARE,
			counts[2] >= sz * SEA_EDGE_SHARE, counts[3] >= sz * SEA_EDGE_SHARE]
	if not (wet[0] or wet[1] or wet[2] or wet[3]):
		return null
	var hx := data.width() * 0.5
	var hz := data.depth() * 0.5
	# North and south strips always run on past both corners, so the sea off
	# a coast does not end at the map's own side edges. West and east strips
	# stop at the corners, so no two strips overlap: overlapping transparent
	# water would read as a darker square.
	var x0 := -hx - reach
	var x1 := hx + reach
	var rects: Array[Rect2] = []
	if wet[0]:
		rects.append(Rect2(x0, -hz - reach, x1 - x0, reach))
	if wet[1]:
		rects.append(Rect2(x0, hz, x1 - x0, reach))
	if wet[2]:
		rects.append(Rect2(-hx - reach, -hz, reach, hz * 2.0))
	if wet[3]:
		rects.append(Rect2(hx, -hz, reach, hz * 2.0))
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	const STEPS := 8   # a few interior vertices, so fog and lighting interpolate sanely
	for rect in rects:
		var base := verts.size()
		for j in STEPS + 1:
			for i in STEPS + 1:
				verts.append(Vector3(rect.position.x + rect.size.x * i / STEPS, data.water_level, rect.position.y + rect.size.y * j / STEPS))
		for j in STEPS:
			for i in STEPS:
				var a := base + j * (STEPS + 1) + i
				idx.append_array(PackedInt32Array([a, a + 1, a + STEPS + 1, a + 1, a + STEPS + 2, a + STEPS + 1]))
	var colors := PackedColorArray()
	colors.resize(verts.size())
	colors.fill(Color(1, 0, 0, 1))
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The whole terrain as one plain mesh — full detail, no skirts, no LODs — for
## exporting to other tools.
static func build_export_mesh(data: Data) -> ArrayMesh:
	var sx := data.cells_x + 1
	var sz := data.cells_z + 1
	var cell := data.cell_size
	var half_x := data.width() * 0.5
	var half_z := data.depth() * 0.5
	var h := data.heights
	var ctl := data.control
	var normals := compute_normals(data)
	var verts := PackedVector3Array()
	verts.resize(sx * sz)
	var colors := PackedColorArray()
	colors.resize(sx * sz)
	var uvs := PackedVector2Array()
	uvs.resize(sx * sz)
	for j in sz:
		for i in sx:
			var k := j * sx + i
			var b := k * Data.CONTROL_STRIDE
			verts[k] = Vector3(i * cell - half_x, h[k], j * cell - half_z)
			colors[k] = Color(ctl[b] / 255.0, ctl[b + 1] / 255.0, ctl[b + 2] / 255.0, ctl[b + 3] / 255.0)
			uvs[k] = Vector2(float(i) / data.cells_x, float(j) / data.cells_z)
	var idx := PackedInt32Array()
	idx.resize(data.cells_x * data.cells_z * 6)
	var w := 0
	for j in data.cells_z:
		for i in data.cells_x:
			var a := j * sx + i
			idx[w] = a
			idx[w + 1] = a + 1
			idx[w + 2] = a + sx
			idx[w + 3] = a + 1
			idx[w + 4] = a + sx + 1
			idx[w + 5] = a + sx
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
