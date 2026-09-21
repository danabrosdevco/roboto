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
#   black / transparent — no preference: the rest of the recipe decides
#
# Pixels are classified to the nearest palette colour, blended across
# `sketch_blend` metres, and the edges wobbled by `sketch_edge_noise` metres,
# so blocky pixel art comes out as natural shapes. Colours far from every
# palette entry (anti-aliased fringes, stray tints) count as unpainted.
#
# Pure image work only: this turns a sketch into one mask per colour at the
# terrain's resolution. TerrainGenerator decides what each mask does to the
# ground.
# ─────────────────────────────────────────────

const MOUNTAIN := 0
const WATER := 1
const FLAT := 2
const URBAN := 3
const SHELLED := 4
const ROUGH := 5
const COUNT := 6

const NAMES: Array[String] = ["mountains", "water", "flat", "urban", "shelled", "rough"]
const COLOURS: Array[Color] = [Color(1, 1, 1), Color(0, 0, 1), Color(0, 1, 0), Color(0.5, 0.5, 0.5), Color(1, 0, 0), Color(1, 1, 0)]
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
	for i in COUNT:
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
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var cat := classify(c)
			if cat >= 0:
				per[cat][y * w + x] = 1.0
				present[cat] = true
			elif cat == -2:
				unknown += 1
				example = c
	if unknown > 0:
		push_warning("TerrainSketch: %d pixel(s) match no sketch colour (e.g. #%s) and are left to the recipe. Palette: white mountains, blue water, green flat, grey urban, red shelled, yellow rough, black nothing." % [unknown, example.to_html(false)])

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
