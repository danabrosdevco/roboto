@tool
class_name TerrainSketch
extends RefCounted

# ─────────────────────────────────────────────
# TERRAIN SKETCH — a small painted image that sets a terrain's layout.
#
# Paint on black (or transparent). The top of the image is north (-Z).
#
#   white   mountains         blue    water
#   green   flat ground       grey    urban blocks
#   red     shelled ground    yellow  rough ground
#   magenta roads — drawn as lines; thicker strokes make wider roads
#   black / transparent — no preference: the rest of the recipe decides
#
# Area colours are classified to the nearest palette entry, blended across
# `sketch_blend` metres, and their edges wobbled by `sketch_edge_noise`
# metres, so blocky pixel art comes out as natural shapes. Colours far from
# every palette entry (anti-aliased fringes, stray tints) count as unpainted.
#
# Roads are different: they must stay continuous and smooth, so they are
# never blended or wobbled. trace_roads() thins each painted stroke to a
# one-pixel skeleton and follows it into centrelines; the generator grades
# those like a TerrainPath. Under a road, the area colours either side carry
# on through it, so a road across a river does not dam it and a road through
# a town does not split it in two.
#
# Pure image work only. TerrainGenerator decides what each mask and road does
# to the ground.
# ─────────────────────────────────────────────

const MOUNTAIN := 0
const WATER := 1
const FLAT := 2
const URBAN := 3
const SHELLED := 4
const ROUGH := 5
## Area colours are 0 … COUNT-1. ROAD comes after them: it is traced into
## lines, not blended into a mask.
const COUNT := 6
const ROAD := 6

const NAMES: Array[String] = ["mountains", "water", "flat", "urban", "shelled", "rough", "roads"]
## Magenta for roads because no fringe can fake it: anti-aliasing between any
## two other palette colours never lands near (1, 0, 1).
const COLOURS: Array[Color] = [Color(1, 1, 1), Color(0, 0, 1), Color(0, 1, 0), Color(0.5, 0.5, 0.5), Color(1, 0, 0), Color(1, 1, 0), Color(1, 0, 1)]
## Under a road pixel, an area colour carries on if at least this share of the
## pixel's non-road neighbours have it: a road ACROSS a river keeps the river
## beneath it, a road ALONG a shore does not drag the water out under itself.
const ROAD_CARRY := 0.6
## Furthest a pixel may sit from a palette colour (RGB distance, 0…1.7) and
## still count as it. Tight on purpose: the anti-aliased fringe between blue
## and green is a teal that sits nearer grey than either, and a loose match
## would lay a strip of city streets along every shoreline.
const MATCH := 0.3
## Darker than this on every channel is "unpainted", quietly.
const DARK := 0.25


## The sketch's pixels, RGBA8, no mipmaps. Reads the source file when there
## is one — exact pixels, no import filtering, and it works headless, where a
## CompressedTexture2D has nothing to read back — and falls back to the
## texture's own image (an ImageTexture made in code, or an exported game).
static func load_image(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img: Image = null
	var path := tex.resource_path
	if path != "" and not path.contains("::") and FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		var loaded := Image.new()
		var err := ERR_FILE_UNRECOGNIZED
		match path.get_extension().to_lower():
			"png":
				err = loaded.load_png_from_buffer(bytes)
			"jpg", "jpeg":
				err = loaded.load_jpg_from_buffer(bytes)
			"webp":
				err = loaded.load_webp_from_buffer(bytes)
			"bmp":
				err = loaded.load_bmp_from_buffer(bytes)
			"tga":
				err = loaded.load_tga_from_buffer(bytes)
		if err == OK:
			img = loaded
	if img == null:
		img = tex.get_image()
	if img == null or img.is_empty():
		push_error("TerrainSketch: could not read any pixels from %s." % (path if path != "" else "the sketch texture"))
		return null
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Changes whenever the sketch's pixels change. Feeds TerrainRecipe.signature(),
## so editing and re-saving the PNG invalidates the generator's cache.
static func fingerprint(tex: Texture2D) -> int:
	if tex == null:
		return 0
	var path := tex.resource_path
	if path != "" and not path.contains("::") and FileAccess.file_exists(path):
		return hash(FileAccess.get_file_as_bytes(path))
	var img := tex.get_image()
	return hash(img.get_data()) if img != null else tex.get_instance_id()


## Palette index for a colour: 0…COUNT-1, -1 unpainted, -2 unrecognised.
static func classify(c: Color) -> int:
	if c.a < 0.5:
		return -1
	if c.r < DARK and c.g < DARK and c.b < DARK:
		return -1
	var best := -2
	var best_d := MATCH
	for i in COLOURS.size():
		var p := COLOURS[i]
		var d := Vector3(c.r - p.r, c.g - p.g, c.b - p.b).length()
		if d < best_d:
			best_d = d
			best = i
	return best


## One mask per painted colour, sampled onto a (cells_x+1) × (cells_z+1)
## grid: 0 unpainted … 1 fully painted. Colours the sketch never uses are
## absent from the result, so callers can skip them entirely.
static func grid_masks(img: Image, cells_x: int, cells_z: int, cell: float, blend_m: float, edge_noise_m: float, seed_value: int) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var per: Array[PackedFloat32Array] = []
	for _i in COUNT:
		var a := PackedFloat32Array()
		a.resize(w * h)
		per.append(a)
	var present: Array[bool] = []
	present.resize(COUNT)
	present.fill(false)
	var unknown := 0
	var example := Color()
	var road := PackedByteArray()
	road.resize(w * h)
	var any_road := false
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var cat := classify(c)
			if cat == ROAD:
				road[y * w + x] = 1
				any_road = true
			elif cat >= 0:
				per[cat][y * w + x] = 1.0
				present[cat] = true
			elif cat == -2:
				unknown += 1
				example = c
	if unknown > 0:
		push_warning("TerrainSketch: %d pixel(s) match no sketch colour (e.g. #%s) and are left to the recipe. Palette: white mountains, blue water, green flat, grey urban, red shelled, yellow rough, magenta roads, black nothing." % [unknown, example.to_html(false)])
	if any_road:
		_carry_under_roads(per, present, road, w, h)

	var sx := cells_x + 1
	var sz := cells_z + 1
	var metres_per_px := (cells_x * cell / w + cells_z * cell / h) * 0.5
	var blur_px := blend_m / maxf(metres_per_px, 0.001)
	var out := {}
	for cat in COUNT:
		if not present[cat]:
			continue
		var mask := per[cat]
		if blur_px >= 1.0:
			var r := maxi(1, roundi(blur_px * 0.5))
			box_blur(mask, w, h, r)
			box_blur(mask, w, h, r)
		var up := Image.create_from_data(w, h, false, Image.FORMAT_RF, mask.to_byte_array())
		up.resize(sx, sz, Image.INTERPOLATE_BILINEAR)
		out[cat] = up.get_data().to_float32_array()

	if edge_noise_m > 0.0 and not out.is_empty():
		# Look every sample up a little off to one side, wandering smoothly:
		# a pixel staircase becomes a ragged shoreline or a lumpy ridge.
		var nx := FastNoiseLite.new()
		nx.seed = seed_value + 707
		nx.frequency = 1.0 / (edge_noise_m * 4.0 + 20.0)
		nx.fractal_octaves = 3
		var nz := FastNoiseLite.new()
		nz.seed = seed_value + 808
		nz.frequency = nx.frequency
		nz.fractal_octaves = 3
		var cats: Array = out.keys()
		var dst: Array[PackedFloat32Array] = []
		var src: Array[PackedFloat32Array] = []
		for cat in cats:
			var a: PackedFloat32Array = out[cat]
			dst.append(a)
			src.append(a.duplicate())
		var half_x := cells_x * cell * 0.5
		var half_z := cells_z * cell * 0.5
		var reach := edge_noise_m * 1.6 / cell
		for j in sz:
			var z := j * cell - half_z
			for i in sx:
				var x := i * cell - half_x
				var si := clampi(roundi(i + nx.get_noise_2d(x, z) * reach), 0, sx - 1)
				var sj := clampi(roundi(j + nz.get_noise_2d(x, z) * reach), 0, sz - 1)
				var from := sj * sx + si
				var to := j * sx + i
				for c in cats.size():
					dst[c][to] = src[c][from]
	return out


## Area colours carry on under road pixels (see ROAD_CARRY).
static func _carry_under_roads(per: Array[PackedFloat32Array], present: Array[bool], road: PackedByteArray, w: int, h: int) -> void:
	var counts := PackedInt32Array()
	counts.resize(COUNT)
	for y in h:
		for x in w:
			var k := y * w + x
			if road[k] == 0:
				continue
			counts.fill(0)
			var around := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if (dx == 0 and dy == 0) or nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var nk := ny * w + nx
					if road[nk] == 1:
						continue
					around += 1
					for cat in COUNT:
						if present[cat] and per[cat][nk] >= 1.0:
							counts[cat] += 1
			if around == 0:
				continue
			for cat in COUNT:
				if counts[cat] >= around * ROAD_CARRY:
					per[cat][k] = 1.0


## Road centrelines from magenta paint, in sketch pixel space. Each is
## {pixels: PackedVector2Array — pixel centres in order along the road,
##  width_px: float — how many pixels thick the stroke is}.
## Strokes are thinned to a one-pixel skeleton first, so a 3-pixel highway and
## a 1-pixel track both come out as single lines, each keeping its width.
## Ends and junctions split the network into separate roads that share their
## junction pixel, so they still meet once graded.
static func trace_roads(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	# Padded with a pixel of nothing all round: strokes running off the edge
	# thin like any other, and neighbour lookups never leave the array.
	var pw := w + 2
	var ph := h + 2
	var mask := PackedByteArray()
	mask.resize(pw * ph)
	var any := false
	for y in h:
		for x in w:
			if classify(img.get_pixel(x, y)) == ROAD:
				mask[(y + 1) * pw + x + 1] = 1
				any = true
	if not any:
		return []
	var skeleton := _thin(mask, pw, ph)
	var chains := _follow(skeleton, pw, ph)
	var widths := _chain_widths(mask, chains, pw)
	var out: Array = []
	var dots := 0
	for c in chains.size():
		var chain: PackedInt32Array = chains[c]
		if chain.size() < 2:
			dots += 1
			continue
		var pts := PackedVector2Array()
		for k in chain:
			var p := _cell(k, pw)
			pts.append(Vector2(p.x - 1 + 0.5, p.y - 1 + 0.5))   # back to unpadded pixel centres
		out.append({"pixels": pts, "width_px": maxf(1.0, roundf(widths[c]))})
	if dots > 0:
		push_warning("TerrainSketch: %d magenta dot(s) too small to trace into a road — draw roads as lines." % dots)
	return out


static func _cell(k: int, pw: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(k % pw, k / pw)


## Zhang–Suen thinning: peels a stroke down to a one-pixel skeleton without
## breaking it or shortening its ends.
static func _thin(mask: PackedByteArray, pw: int, ph: int) -> PackedByteArray:
	var m := mask.duplicate()
	var changed := true
	while changed:
		changed = false
		for step in 2:
			var remove := PackedInt32Array()
			for y in range(1, ph - 1):
				for x in range(1, pw - 1):
					var k := y * pw + x
					if m[k] == 0:
						continue
					var p2 := m[k - pw]
					var p3 := m[k - pw + 1]
					var p4 := m[k + 1]
					var p5 := m[k + pw + 1]
					var p6 := m[k + pw]
					var p7 := m[k + pw - 1]
					var p8 := m[k - 1]
					var p9 := m[k - pw - 1]
					var b := p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
					if b < 2 or b > 6:
						continue
					var a := int(p2 == 0 and p3 == 1) + int(p3 == 0 and p4 == 1) + int(p4 == 0 and p5 == 1) \
							+ int(p5 == 0 and p6 == 1) + int(p6 == 0 and p7 == 1) + int(p7 == 0 and p8 == 1) \
							+ int(p8 == 0 and p9 == 1) + int(p9 == 0 and p2 == 1)
					if a != 1:
						continue
					if step == 0 and (p2 * p4 * p6 != 0 or p4 * p6 * p8 != 0):
						continue
					if step == 1 and (p2 * p4 * p8 != 0 or p2 * p6 * p8 != 0):
						continue
					remove.append(k)
			for k in remove:
				m[k] = 0
			if not remove.is_empty():
				changed = true
	return m


## Skeleton neighbours by m-adjacency: a diagonal pixel only counts when
## neither orthogonal pixel between them is set. Otherwise every staircase
## step is also a diagonal shortcut, and reads as a junction.
static func _neighbours(s: PackedByteArray, k: int, pw: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := s[k - pw] == 1
	var south := s[k + pw] == 1
	var e := s[k + 1] == 1
	var west := s[k - 1] == 1
	if n:
		out.append(k - pw)
	if south:
		out.append(k + pw)
	if e:
		out.append(k + 1)
	if west:
		out.append(k - 1)
	if s[k - pw + 1] == 1 and not n and not e:
		out.append(k - pw + 1)
	if s[k - pw - 1] == 1 and not n and not west:
		out.append(k - pw - 1)
	if s[k + pw + 1] == 1 and not south and not e:
		out.append(k + pw + 1)
	if s[k + pw - 1] == 1 and not south and not west:
		out.append(k + pw - 1)
	return out


## Splits a skeleton into chains: from every end and junction, each untaken
## edge is walked to the next end or junction. Closed loops, which have
## neither, are started anywhere.
static func _follow(s: PackedByteArray, pw: int, ph: int) -> Array[PackedInt32Array]:
	var n := pw * ph
	var degree := PackedByteArray()
	degree.resize(n)
	var cells := PackedInt32Array()
	for k in n:
		if s[k] == 1:
			cells.append(k)
			degree[k] = _neighbours(s, k, pw).size()
	var taken := {}
	var chains: Array[PackedInt32Array] = []
	for k in cells:
		if degree[k] == 0:
			chains.append(PackedInt32Array([k]))   # an isolated dot: reported, not traced
		elif degree[k] != 2:
			for nb in _neighbours(s, k, pw):
				if not taken.has(mini(k, nb) * n + maxi(k, nb)):
					chains.append(_walk(s, degree, taken, k, nb, pw, n))
	for k in cells:
		if degree[k] == 2:
			for nb in _neighbours(s, k, pw):
				if not taken.has(mini(k, nb) * n + maxi(k, nb)):
					chains.append(_walk(s, degree, taken, k, nb, pw, n))
	return chains


static func _walk(s: PackedByteArray, degree: PackedByteArray, taken: Dictionary, start: int, first: int, pw: int, n: int) -> PackedInt32Array:
	var chain := PackedInt32Array([start])
	var prev := start
	var cur := first
	taken[mini(prev, cur) * n + maxi(prev, cur)] = true
	while true:
		chain.append(cur)
		if degree[cur] != 2 or cur == start:
			break   # reached an end, a junction, or came round a loop
		var next := -1
		for nb in _neighbours(s, cur, pw):
			if nb != prev and not taken.has(mini(cur, nb) * n + maxi(cur, nb)):
				next = nb
				break
		if next < 0:
			break
		taken[mini(cur, next) * n + maxi(cur, next)] = true
		prev = cur
		cur = next
	return chain


## Stroke thickness of each chain: every painted road pixel is claimed by the
## nearest skeleton pixel (breadth-first from the skeleton), and a chain's
## width is the pixels it claimed per pixel of its length.
static func _chain_widths(mask: PackedByteArray, chains: Array[PackedInt32Array], pw: int) -> PackedFloat32Array:
	var label := PackedInt32Array()
	label.resize(mask.size())
	label.fill(-1)
	var length := PackedInt32Array()
	length.resize(chains.size())
	var area := PackedInt32Array()
	area.resize(chains.size())
	var queue := PackedInt32Array()
	for c in chains.size():
		for k in chains[c]:
			if label[k] == -1:
				label[k] = c
				length[c] += 1
				area[c] += 1
				queue.append(k)
	var head := 0
	var offsets := PackedInt32Array([-pw - 1, -pw, -pw + 1, -1, 1, pw - 1, pw, pw + 1])
	while head < queue.size():
		var k := queue[head]
		head += 1
		for off in offsets:
			var nk := k + off
			if mask[nk] == 1 and label[nk] == -1:
				label[nk] = label[k]
				area[label[k]] += 1
				queue.append(nk)
	var widths := PackedFloat32Array()
	widths.resize(chains.size())
	for c in chains.size():
		widths[c] = float(area[c]) / maxf(float(length[c]), 1.0)
	return widths


## Two-pass chamfer distance, in cells, from every cell to the nearest cell
## whose `mask` value is `target`.
static func chamfer(mask: PackedByteArray, target: int, w: int, h: int) -> PackedFloat32Array:
	const DIAG := 1.41421356
	var d := PackedFloat32Array()
	d.resize(w * h)
	for k in d.size():
		d[k] = 0.0 if mask[k] == target else 1e9
	for j in h:
		for i in w:
			var k := j * w + i
			var v := d[k]
			if i > 0:
				v = minf(v, d[k - 1] + 1.0)
			if j > 0:
				v = minf(v, d[k - w] + 1.0)
				if i > 0:
					v = minf(v, d[k - w - 1] + DIAG)
				if i < w - 1:
					v = minf(v, d[k - w + 1] + DIAG)
			d[k] = v
	for j in range(h - 1, -1, -1):
		for i in range(w - 1, -1, -1):
			var k := j * w + i
			var v := d[k]
			if i < w - 1:
				v = minf(v, d[k + 1] + 1.0)
			if j < h - 1:
				v = minf(v, d[k + w] + 1.0)
				if i < w - 1:
					v = minf(v, d[k + w + 1] + DIAG)
				if i > 0:
					v = minf(v, d[k + w - 1] + DIAG)
			d[k] = v
	return d


## In-place separable box blur, radius r pixels, edges clamped.
static func box_blur(a: PackedFloat32Array, w: int, h: int, r: int) -> void:
	var tmp := PackedFloat32Array()
	tmp.resize(a.size())
	var span := 2 * r + 1
	for y in h:
		var row := y * w
		var acc := 0.0
		for k in range(-r, r + 1):
			acc += a[row + clampi(k, 0, w - 1)]
		for x in w:
			tmp[row + x] = acc / span
			acc += a[row + mini(x + r + 1, w - 1)] - a[row + maxi(x - r, 0)]
	for x in w:
		var acc := 0.0
		for k in range(-r, r + 1):
			acc += tmp[clampi(k, 0, h - 1) * w + x]
		for y in h:
			a[y * w + x] = acc / span
			acc += tmp[mini(y + r + 1, h - 1) * w + x] - tmp[maxi(y - r, 0) * w + x]
