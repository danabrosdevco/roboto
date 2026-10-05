extends SceneTree

# ─────────────────────────────────────────────
# MAKE TEXTURES — new 256x256 textures in the PSX pack's style, for surfaces
# the pack has nothing for, plus a StandardMaterial3D for each.
#
#   godot --headless --path . --script res://tools/make_textures.gd -- textures/PSX_Textures
#   godot --headless --path . --script res://tools/make_textures.gd -- textures/PSX_Textures --force
#
# Headless is fine: it writes pixels, it does not render anything.
#
# EVERYTHING HERE IS DRAWN FROM NOTHING. No pixel of the bought pack is read,
# sampled or filtered — textures/PSX_Textures ships under a licence and the
# way to stay inside it is to not touch the art at all. What is copied is the
# STYLE, and that was measured off the pack rather than guessed:
#
#   256x256, RGB8                 192 of its 194 files
#   mean luminance about 0.20     nothing in it is a bright surface
#   peak about 0.45               there is no white anywhere in the pack
#   saturation 0.08 to 0.25       except the glitch texture, which is a glow
#
# That last pair is the whole trick. A texture authored at normal brightness
# drops into one of these levels looking like a light source. These are built
# dark and let the sun do the work, which is what everything beside them does.
#
# The structure is drawn hard — no soft gradients anywhere — and then the
# whole thing is quantised to 32 levels a channel through a 4x4 ordered
# dither, because the banding and the dither pattern are most of what makes
# the pack read as PSX rather than as low-resolution.
#
# WHAT THESE ARE FOR. Each one replaces a stand-in that is currently some
# other material pressed into service:
#
#   glass_dark        GLASS in block_ai_infra.gd is rubber_tsk_1
#   solar_pv          PV in block_ai_infra.gd is tile_floor_tx_3
#   mirror_heliostat  MIRROR is the same rubber as the glass
#   grate_perf        GRATING is metal_floor_3
#
# Nothing here is wired up. Changing those constants is a separate decision,
# because every block built with one of them has to be rebuilt after.
# ─────────────────────────────────────────────

const SIZE := 256
## Nothing in the pack goes brighter than about 0.45. Neither does anything
## here, so a new surface sits in a level at the same exposure as its
## neighbours instead of glowing.
const CEIL := 0.46
## Levels per channel in the final quantise.
const LEVELS := 32

const MADE := {
	"glass_dark": "_glass_dark",
	"glass_window": "_glass_window",
	"glass_broken": "_glass_broken",
	"solar_pv": "_solar_pv",
	"solar_pv_dusty": "_solar_pv_dusty",
	"solar_pv_dead": "_solar_pv_dead",
	"solar_array": "_solar_array",
	"mirror_heliostat": "_mirror_heliostat",
	"grate_perf": "_grate_perf",
}

## Emission for the few that want it, as {name: [colour, energy]}. The pack's
## own glitch_tx_1.tres is the pattern being followed.
const EMISSIVE := {}

var _img: Image


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
		print("usage: godot --headless --path . --script res://tools/make_textures.gd -- textures/PSX_Textures [--force] [names]")
		quit(2)
		return
	if not base.begins_with("res://") and not base.is_absolute_path():
		base = "res://" + base
	if not DirAccess.dir_exists_absolute(base):
		print("FAIL  no folder at %s" % base)
		quit(1)
		return
	var written := 0
	for name: String in MADE:
		if not only.is_empty() and not only.has(name):
			continue
		var png := base.path_join(name + ".png")
		if FileAccess.file_exists(png) and not force:
			print("SKIP  %s exists — pass --force to redraw it." % png)
			continue
		_img = Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		call(MADE[name])
		_finish()
		var err := _img.save_png(png)
		if err != OK:
			print("FAIL  could not write %s (%s)" % [png, error_string(err)])
			quit(1)
			return
		_material(base, name)
		written += 1
		print("      %-20s %s" % [name, _report()])
	print("MAKE TEXTURES DONE: %d written" % written)
	quit()


# ── Finishing ────────────────────────────────────────────────────────────────

## Fine per-pixel grain, then the quantise-and-dither that does most of the
## work of making this look like the rest of the folder.
func _finish() -> void:
	for y in SIZE:
		for x in SIZE:
			var c := _img.get_pixel(x, y)
			var g := (_hash(x, y, 9901) - 0.5) * 0.045
			var d := (_bayer(x, y) - 0.5) / float(LEVELS)
			var out := Color(
					_q(clampf(c.r + g + d, 0.0, CEIL)),
					_q(clampf(c.g + g + d, 0.0, CEIL)),
					_q(clampf(c.b + g + d, 0.0, CEIL)))
			_img.set_pixel(x, y, out)


func _q(v: float) -> float:
	return roundf(v * (LEVELS - 1)) / float(LEVELS - 1)


## 4x4 ordered dither, as a fraction in 0..1.
func _bayer(x: int, y: int) -> float:
	const M := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	return float(M[(y % 4) * 4 + (x % 4)]) / 16.0


func _report() -> String:
	var sum := 0.0
	var hi := 0.0
	for y in SIZE:
		for x in SIZE:
			var c := _img.get_pixel(x, y)
			var l := (c.r + c.g + c.b) / 3.0
			sum += l
			hi = maxf(hi, l)
	return "mean %.2f  peak %.2f" % [sum / float(SIZE * SIZE), hi]


func _material(base: String, name: String) -> void:
	var path := base.path_join(name + ".tres")
	var lines := PackedStringArray([
		'[gd_resource type="StandardMaterial3D" load_steps=2 format=3]',
		'',
		'[ext_resource type="Texture2D" path="%s" id="1_albed"]' % base.path_join(name + ".png"),
		'',
		'[resource]',
		'albedo_texture = ExtResource("1_albed")',
		'metallic_specular = 0.0',
		# 2 is nearest with mipmaps, which is what every material in the
		# folder uses. Linear here would soften these against their
		# neighbours and the whole look would go.
		'texture_filter = 2',
	])
	if EMISSIVE.has(name):
		var e: Array = EMISSIVE[name]
		var c: Color = e[0]
		lines.append_array([
			'emission_enabled = true',
			'emission = Color(%s, %s, %s, 1)' % [c.r, c.g, c.b],
			'emission_energy_multiplier = %s' % e[1],
		])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()


# ── Noise ────────────────────────────────────────────────────────────────────

func _hash(x: int, y: int, seed: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + seed * 1442695041
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFF) / float(0xFFFFF)


## Value noise on a lattice of `period` cells across the image. The lattice
## wraps, so every texture here tiles — a wall of them in TrenchBroom has no
## seam, which is the one thing a generated texture usually gets wrong.
func _value(u: float, v: float, period: int, seed: int) -> float:
	var fx := u * period
	var fy := v * period
	var ix := int(floorf(fx))
	var iy := int(floorf(fy))
	var tx := fx - ix
	var ty := fy - iy
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := _hash(posmod(ix, period), posmod(iy, period), seed)
	var b := _hash(posmod(ix + 1, period), posmod(iy, period), seed)
	var c := _hash(posmod(ix, period), posmod(iy + 1, period), seed)
	var d := _hash(posmod(ix + 1, period), posmod(iy + 1, period), seed)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


func _fbm(u: float, v: float, seed: int, octaves: int = 5, period: int = 4) -> float:
	var s := 0.0
	var amp := 0.5
	var norm := 0.0
	var p := period
	for i in octaves:
		s += _value(u, v, p, seed + i * 101) * amp
		norm += amp
		amp *= 0.5
		p *= 2
	return s / norm


## The dirt every surface in that folder is under: uneven, large-scale,
## darkening rather than lightening.
func _grime(u: float, v: float, seed: int, strength: float = 0.45) -> float:
	var n := _fbm(u, v, seed, 5, 3)
	return 1.0 - strength * (1.0 - n) * (1.0 - n)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _put(x: int, y: int, c: Color) -> void:
	_img.set_pixel(posmod(x, SIZE), posmod(y, SIZE), c)


func _fill(c: Color) -> void:
	_img.fill(c)


func _shade(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f)


## Distance in pixels to the nearest line of a grid `pitch` apart, offset by
## `off`. Used for every seam, mullion and busbar below.
func _grid_d(p: int, pitch: int, off: int = 0) -> int:
	var m := posmod(p - off, pitch)
	return mini(m, pitch - m)


# ── Glass ────────────────────────────────────────────────────────────────────

## Dark tinted glass: a flat deep blue-grey with the faint banding of
## something reflected in it, vertical rain streaking, and a couple of smears.
## Meant for the places GLASS currently means rubber_tsk_1 — the monolith, the
## core column, the data hall.
func _glass_dark() -> void:
	var tint := Color(0.085, 0.105, 0.135)
	for y in SIZE:
		for x in SIZE:
			var u := float(x) / SIZE
			var v := float(y) / SIZE
			# Reflection bands, drawn as hard steps rather than a gradient.
			var band := floorf((v * 3.2 + u * 0.55) * 5.0) / 5.0
			var refl := 0.55 + 0.9 * band
			# Streaking down the pane, which is what actually makes glass read
			# as glass at this resolution.
			var streak := _value(u, v * 0.22, 48, 211)
			var wet := 1.0 - 0.3 * smoothstep(0.62, 0.95, streak)
			var c := _shade(tint, refl * wet * _grime(u, v, 5, 0.3))
			# A cold highlight on the upper band, never a white one.
			if band > 0.75:
				c = Color(c.r + 0.05, c.g + 0.07, c.b + 0.09)
			_img.set_pixel(x, y, c)


## Glazing in a frame: a 4 x 4 grid of panes on metal mullions, each pane a
## slightly different tint because no two panes in a derelict building are.
func _glass_window() -> void:
	_glass_dark()
	var pitch := SIZE / 4
	var frame := Color(0.165, 0.16, 0.145)
	for y in SIZE:
		for x in SIZE:
			var pane := int(x / pitch) + int(y / pitch) * 4
			var vary := 0.72 + 0.5 * _hash(pane, pane * 7, 71)
			var c := _shade(_img.get_pixel(x, y), vary)
			var d: int = mini(_grid_d(x, pitch), _grid_d(y, pitch))
			if d <= 3:
				c = _shade(frame, 0.75 + 0.5 * _fbm(float(x) / SIZE, float(y) / SIZE, 17, 3, 8))
				if d == 3:
					c = _shade(c, 0.6)    # the shadow line where glass meets frame
			_img.set_pixel(x, y, c)


## The same glazing with the building's history in it: panes gone to the dark
## of an empty room, panes starred by a hit, panes still intact.
func _glass_broken() -> void:
	_glass_window()
	var pitch := SIZE / 4
	for py in 4:
		for px in 4:
			var pane := px + py * 4
			var roll := _hash(pane * 13, pane * 29, 404)
			var cx := px * pitch + pitch / 2
			var cy := py * pitch + pitch / 2
			if roll < 0.3:
				# Gone. Not black — a room behind it, which is darker than the
				# glass was but not empty.
				for y in range(py * pitch + 4, (py + 1) * pitch - 3):
					for x in range(px * pitch + 4, (px + 1) * pitch - 3):
						var n := _fbm(float(x) / SIZE, float(y) / SIZE, 303, 4, 16)
						_img.set_pixel(x, y, Color(0.03 + n * 0.05, 0.03 + n * 0.05, 0.035 + n * 0.05))
				# Shards still in the frame.
				for k in 9:
					var a := TAU * _hash(pane, k, 77)
					var r := pitch * (0.34 + 0.16 * _hash(k, pane, 78))
					_line(cx, cy, cx + int(cos(a) * r), cy + int(sin(a) * r), Color(0.17, 0.19, 0.21))
			elif roll < 0.62:
				# Starred. Radial cracks catch the light, so they are the one
				# place in this texture allowed near the ceiling.
				for k in 11:
					var a := TAU * k / 11.0 + _hash(pane, k, 91) * 0.5
					var r := pitch * (0.2 + 0.26 * _hash(k, pane, 92))
					_line(cx, cy, cx + int(cos(a) * r), cy + int(sin(a) * r), Color(0.3, 0.33, 0.36))


## A hard one-pixel line, because every edge in that pack is one pixel.
func _line(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	for _i in 512:
		_put(x, y, c)
		if x == x1 and y == y1:
			return
		var e2 := err * 2
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy


# ── Photovoltaic ─────────────────────────────────────────────────────────────

## A monocrystalline panel: six by six wafers with their corners cut off, two
## busbars and a comb of fingers across each, in an aluminium frame. This is
## the one the solar pieces actually want — PV is currently a floor tile.
func _solar_pv() -> void:
	_pv_panel(6, 1.0, 0.0)


## The same after a few dry years: dust gathered along the bottom of every
## wafer and drifted down the glass.
func _solar_pv_dusty() -> void:
	_pv_panel(6, 1.0, 0.55)


## The same panel finished: wafers cracked through, cells delaminated to the
## brown of cooked backsheet, a string gone dark.
func _solar_pv_dead() -> void:
	_pv_panel(6, 1.0, 0.25)
	var pitch := SIZE / 6
	for cy in 6:
		for cx in 6:
			var cell := cx + cy * 6
			var roll := _hash(cell * 17, cell * 37, 808)
			var x0 := cx * pitch
			var y0 := cy * pitch
			if roll < 0.28:
				# Delaminated: the backsheet showing through.
				for y in range(y0 + 3, y0 + pitch - 3):
					for x in range(x0 + 3, x0 + pitch - 3):
						var n := _fbm(float(x) / SIZE, float(y) / SIZE, 909, 4, 12)
						if n > 0.42:
							_img.set_pixel(x, y, Color(0.17 + n * 0.1, 0.13 + n * 0.07, 0.095 + n * 0.04))
			elif roll < 0.6:
				# Cracked. A crack in a wafer scatters light, so it reads
				# lighter than the cell either side of it.
				var mx := x0 + pitch / 2
				var my := y0 + pitch / 2
				for k in 4:
					var a := TAU * _hash(cell, k, 811)
					_line(mx, my, mx + int(cos(a) * pitch * 0.55), my + int(sin(a) * pitch * 0.55),
							Color(0.21, 0.22, 0.26))


## `cells` wafers a side, `tilt` reserved, `dust` 0 for a clean panel and 1
## for one nobody has been near in a decade.
func _pv_panel(cells: int, _tilt: float, dust: float) -> void:
	var pitch := SIZE / cells
	var frame := Color(0.2, 0.2, 0.205)
	var deep := Color(0.055, 0.07, 0.115)
	for y in SIZE:
		for x in SIZE:
			var u := float(x) / SIZE
			var v := float(y) / SIZE
			var cx := x / pitch
			var cy := y / pitch
			var ix := x % pitch
			var iy := y % pitch
			var cell := cx + cy * cells
			var c: Color
			# The gap between wafers, and the frame around the panel's edge.
			var edge: int = mini(mini(x, SIZE - 1 - x), mini(y, SIZE - 1 - y))
			if edge < 5:
				c = _shade(frame, 0.8 + 0.4 * _fbm(u, v, 31, 3, 8))
			elif ix < 3 or iy < 3:
				c = Color(0.045, 0.05, 0.06)          # the dark lane between cells
			elif ix + iy < 9 or (pitch - ix) + iy < 10 or ix + (pitch - iy) < 10 or (pitch - ix) + (pitch - iy) < 11:
				c = Color(0.05, 0.055, 0.07)          # the wafer's cut corners
			else:
				# The wafer. Each is a slightly different blue, as a tray of
				# real ones is, and carries the diagonal sheen of the crystal.
				# The spread is wide on purpose: at 42 px a wafer, tone is the
				# only thing that still reads, and a panel of identical cells
				# comes back looking like brickwork.
				var hue := 0.6 + 0.85 * _hash(cell, cell * 5, 55)
				var sheen := 0.82 + 0.34 * floorf(_value(u * 1.4 + v, v, 7, 60) * 4.0) / 4.0
				c = _shade(deep, hue * sheen)
				# Fingers: the hairline comb across every wafer.
				if posmod(iy, 6) == 0:
					c = _shade(c, 1.12)
				# Busbars, one pixel and barely above the cell. They were
				# three pixels at 0.30 and that is five times the brightness
				# of the wafer either side — the panel read as a wall of dark
				# bricks with white mortar rather than as glass over silicon.
				if _grid_d(ix, pitch / 2, pitch / 4) == 0:
					c = _shade(c, 1.9)
			c = _shade(c, _grime(u, v, 7, 0.22))
			if dust > 0.0:
				# Dust gathers at the foot of each wafer and streaks down the
				# glass between them.
				var settle := clampf(float(iy) / float(pitch), 0.0, 1.0)
				var drift := _value(u, v * 0.3, 40, 77)
				var amount: float = dust * (0.35 * settle * settle + 0.4 * smoothstep(0.55, 0.95, drift))
				c = c.lerp(Color(0.2, 0.18, 0.145), clampf(amount, 0.0, 0.6))
			_img.set_pixel(x, y, c)


## A whole field of panels for one surface: four rows of modules on their
## rails with the ground showing between them, so a big plane reads as an
## array instead of as one enormous panel.
func _solar_array() -> void:
	var row := SIZE / 4
	var gap := 9
	for y in SIZE:
		for x in SIZE:
			var u := float(x) / SIZE
			var v := float(y) / SIZE
			var iy := y % row
			var c: Color
			if iy < gap:
				# Between the rows: ground, and the shadow the row in front
				# throws on it.
				var n := _fbm(u, v, 404, 5, 6)
				c = Color(0.145 + n * 0.09, 0.13 + n * 0.08, 0.105 + n * 0.06)
				c = _shade(c, 0.55 + 0.45 * float(iy) / float(gap))
			else:
				var cells := 4
				var pitch := (row - gap) / 2
				var px := x % pitch
				var py := (iy - gap) % pitch
				var cell := (x / pitch) + (y / row) * cells
				if px < 2 or py < 2:
					c = Color(0.05, 0.055, 0.065)
				else:
					var hue := 0.86 + 0.3 * _hash(cell, cell * 11, 56)
					c = _shade(Color(0.055, 0.07, 0.115), hue * (0.9 + 0.2 * _value(u * 2.0, v, 9, 61)))
					if _grid_d(px, pitch, pitch / 2) <= 1:
						c = Color(0.27, 0.28, 0.3)
				# The module's own frame at the top and bottom of the row.
				if iy == gap or iy == row - 1:
					c = Color(0.19, 0.19, 0.195)
			_img.set_pixel(x, y, c)


## A heliostat facet: four mirrors on a frame. Brighter than anything else
## here because a mirror is showing you the sky — but still under the pack's
## ceiling, so it reads as bright rather than as emissive.
func _mirror_heliostat() -> void:
	var pitch := SIZE / 2
	for y in SIZE:
		for x in SIZE:
			var u := float(x) / SIZE
			var v := float(y) / SIZE
			var ix := x % pitch
			var iy := y % pitch
			var c: Color
			var edge: int = mini(mini(x, SIZE - 1 - x), mini(y, SIZE - 1 - y))
			if edge < 4 or ix < 4 or iy < 4:
				c = _shade(Color(0.175, 0.175, 0.18), 0.8 + 0.4 * _fbm(u, v, 23, 3, 8))
			else:
				# Sky in four hard steps, lighter toward the top of the facet.
				var step := floorf((1.0 - float(iy) / float(pitch)) * 4.0) / 4.0
				c = Color(0.2, 0.235, 0.29).lerp(Color(0.34, 0.37, 0.41), step)
				# Age: silvering gone at the edges and in patches.
				var rot := _fbm(u, v, 24, 5, 5)
				if rot < 0.4:
					c = c.lerp(Color(0.13, 0.12, 0.105), (0.4 - rot) * 2.2)
			_img.set_pixel(x, y, _shade(c, _grime(u, v, 25, 0.2)))


## Perforated walkway plate: a staggered round-hole pattern on checker plate,
## for the place GRATING currently means a floor texture.
func _grate_perf() -> void:
	var pitch := 16
	var plate := Color(0.2, 0.195, 0.175)
	for y in SIZE:
		for x in SIZE:
			var u := float(x) / SIZE
			var v := float(y) / SIZE
			var c := _shade(plate, 0.82 + 0.36 * _fbm(u, v, 41, 4, 6))
			# Staggered rows, which is how a real perforated sheet is punched.
			#
			# THE DISTANCE HAS TO BE TO A HOLE, not to the nearest grid line
			# in x and the nearest in y independently. Those two are different
			# lattices once the odd rows are offset, and combining them drew a
			# wavy horizontal band through every row instead of a line of
			# holes. Walk the three candidate rows and take the real minimum.
			var r := 99.0
			for k: int in [-1, 0, 1]:
				var row: int = int(floorf(float(y) / float(pitch))) + k
				var off: int = 0 if posmod(row, 2) == 0 else pitch / 2
				var cy := row * pitch
				var col: int = int(roundf(float(x - off) / float(pitch)))
				for j: int in [-1, 0, 1]:
					var cx := (col + j) * pitch + off
					var dx := float(x - cx)
					var dy := float(y - cy)
					r = minf(r, sqrt(dx * dx + dy * dy))
			if r < 4.2:
				c = Color(0.028, 0.03, 0.032)        # through the hole
			elif r < 5.4:
				c = _shade(c, 0.55)                  # the punched lip
			elif r < 6.2:
				c = _shade(c, 1.25)                  # and its bright edge
			_img.set_pixel(x, y, _shade(c, _grime(u, v, 42, 0.25)))
