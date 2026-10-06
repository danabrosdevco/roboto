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
## The convention for textures we generate: about 0.45. It is NOT a measured
## property of the pack (peaks there reach 1.0; mean ~0.175 is the signature).
## Nothing generated here goes brighter, so a new surface sits in a level at the same exposure as its
## neighbours instead of glowing.
const CEIL := 0.46
## Levels per channel in the final quantise.
const LEVELS := 32

## The faction shader's derived paint band: paint_band_center 0.45 and
## paint_band_width 0.425 as the shader is called (the shader's own defaults
## are 0.28 wide). Only used to
## REPORT how much of a texture would be repainted, never to draw with.
const BAND_CENTER := 0.45
const BAND_WIDTH := 0.425

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
	"camo_fabric": "_camo_fabric",
	"camo_fabric_worn": "_camo_fabric_worn",
	"epaulette_plain": "_epaulette_plain",
	"epaulette_braid": "_epaulette_braid",
	"epaulette_pips": "_epaulette_pips",
	"pauldron_plate": "_pauldron_plate",
	"pauldron_plate_worn": "_pauldron_worn",
	"pauldron_plate_dress": "_pauldron_dress",
	"pauldron_lame": "_pauldron_lame",
	"bearskin_fur": "_bearskin_fur",
	"bearskin_fur_worn": "_bearskin_fur_worn",
	"roach_comb": "_roach_comb_plain",
	"roach_comb_worn": "_roach_comb_worn",
}

## Textures that ship a second image beside the albedo: <name>_mask.png, whose
## red channel is the faction-paint mask Character/faction_metal.gdshader reads
## when derive_mask_from_albedo is off. See _epaulette for why these cannot use
## the shader's luminance band instead.
const MASKED := ["epaulette_plain", "epaulette_braid", "epaulette_pips", "pauldron_plate",
		"pauldron_plate_worn", "pauldron_plate_dress", "pauldron_lame",
		"bearskin_fur", "bearskin_fur_worn", "roach_comb", "roach_comb_worn"]

## Emission for the few that want it, as {name: [colour, energy]}. The pack's
## own glitch_tx_1.tres is the pattern being followed.
const EMISSIVE := {}

var _img: Image
## Only set while a MASKED texture is being drawn; null otherwise.
var _mask: Image
## The ceiling for the texture being drawn. CEIL unless a texture raises it for
## itself; reset per texture so nothing else in the pack moves.
var _ceil := CEIL
## Per-channel floor for the texture being drawn; 0 unless a texture sets one
## (the bearskin must never reach black). Reset per texture.
var _floor := 0.0


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
		_mask = null
		_ceil = CEIL
		_floor = 0.0
		_bear_alt_mask = null
		if MASKED.has(name):
			_mask = Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		call(MADE[name])
		_finish()
		var err := _img.save_png(png)
		if err != OK:
			print("FAIL  could not write %s (%s)" % [png, error_string(err)])
			quit(1)
			return
		if _mask != null:
			var merr := _mask.save_png(base.path_join(name + "_mask.png"))
			if merr != OK:
				print("FAIL  could not write mask for %s (%s)" % [name, error_string(merr)])
				quit(1)
				return
		# Bearskin only: the optional crown-band mask, kept beside the real one so
		# the human can pick from a picture. Wire it by renaming it over _mask.png.
		if _bear_alt_mask != null:
			_bear_alt_mask.save_png(base.path_join(name + "_mask_crown.png"))
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
					_q(clampf(c.r + g + d, _floor, _ceil)),
					_q(clampf(c.g + g + d, _floor, _ceil)),
					_q(clampf(c.b + g + d, _floor, _ceil)))
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
	# Luminance and saturation as the faction shader and the pack measurement see
	# them, so a number here means the same thing as the number in the brief.
	var lsum := 0.0
	var lhi := 0.0
	var ssum := 0.0
	# The shader's real paint weight, averaged: how much of the texture the
	# faction colour actually lands on.
	var wsum := 0.0
	var in_band := 0
	# Band occupancy split by the explicit mask, where there is one.
	var mask_on := 0
	var on_band := 0
	var off_band := 0
	for y in SIZE:
		for x in SIZE:
			var c := _img.get_pixel(x, y)
			var l := (c.r + c.g + c.b) / 3.0
			sum += l
			hi = maxf(hi, l)
			var lum := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			lsum += lum
			lhi = maxf(lhi, lum)
			ssum += c.s
			var w := 1.0 - smoothstep(0.0, BAND_WIDTH, absf(lum - BAND_CENTER))
			wsum += w
			# Weight 0.5 is the edge of the band the brief quotes (0.24 to 0.66).
			var inb := w >= 0.5
			if inb:
				in_band += 1
			if _mask != null:
				if _mask.get_pixel(x, y).r > 0.5:
					mask_on += 1
					if inb:
						on_band += 1
				elif inb:
					off_band += 1
	var n := float(SIZE * SIZE)
	var s := "mean %.2f peak %.2f | lum %.3f (peak %.3f) sat %.2f in-band %.1f%% paint-weight %.2f" % [
			sum / n, hi, lsum / n, lhi, ssum / n, 100.0 * in_band / n, wsum / n]
	if _mask != null:
		s += " | mask covers %.1f%%, of it in band %.1f%%; unmasked in band %.1f%%" % [
				100.0 * mask_on / n, 100.0 * on_band / maxf(mask_on, 1.0),
				100.0 * off_band / maxf(n - mask_on, 1.0)]
	return s


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


# ── Robot clothing ───────────────────────────────────────────────────────────
#
# The robots are machines wearing the remains of a uniform, so these two
# families have to read as CLOTH against metal. Both pass through the faction
# shader (Character/faction_metal.gdshader), which repaints the mid-tones of the
# albedo (luminance 0.24 to 0.66 at half weight) in the faction colour. That is
# decided deliberately per family:
#
#   camo       must NOT be repainted — a disruptive pattern that turns flat
#              faction orange is not camo. Everything here stays under about
#              0.22 luminance, which is where the pack sits anyway, so the
#              shader's paint weight on it is small and the pattern survives.
#   epaulette  MUST be repainted, it is where a faction is read at a glance —
#              but only the board, not the braid and pips. See _epaulette.

## Large disruptive blobs in four tones. Four to six blobs across the tile,
## because at the size a sleeve is seen on a 1152 x 648 screen anything finer
## turns to grey mush. The warp is what makes them read as camo rather than as
## contour lines: a plain noise threshold gives round puddles.
##
## `fade` 0 is issue cloth, 1 is cloth that has been out in the weather for
## years: tones pulled toward one dusty grey, sun-bleached streaks, and stains.
func _camo(fade: float) -> void:
	# Dark to light. Kept at saturation 0.15 to 0.25, and luminance 0.08 to 0.22:
	# the pack mean is 0.20, but the faction shader paints from 0.24 up, so the
	# lightest tone sits just under where paint begins to bite.
	var tones := [
		Color(0.075, 0.088, 0.066),    # deep olive
		Color(0.138, 0.15, 0.115),     # olive drab
		Color(0.185, 0.168, 0.142),    # earth brown
		Color(0.222, 0.222, 0.192),    # dry khaki
	]
	var faded := Color(0.175, 0.17, 0.148)
	for y in SIZE:
		for x in SIZE:
			var u := float(x) / SIZE
			var v := float(y) / SIZE
			# Warp in both axes with a wrapped noise, so the pattern is bent but
			# still tiles: the warp is periodic, and so is the lattice it feeds.
			var wu := u + 0.16 * (_fbm(u, v, 601, 2, 3) - 0.5)
			var wv := v + 0.16 * (_fbm(u, v, 602, 2, 3) - 0.5)
			var n := _fbm(wu, wv, 603, 2, 4)
			# Thresholds sit at the measured quartiles of this noise (median 0.44, not 0.5):
			# value noise on so few lattice cells is lopsided, and evenly spaced thresholds gave
			# two tones nearly everything and the outer two a few specks.
			var t := 0
			if n > 0.53:
				t = 3
			elif n > 0.44:
				t = 2
			elif n > 0.36:
				t = 1
			# A second, independent field cuts dark patches across all of it.
			# That crossing is what the eye takes for disruption.
			var d := _fbm(wu, wv, 604, 2, 5)
			if d > 0.72:
				t = 0
			var c: Color = tones[t]
			if fade > 0.0:
				c = c.lerp(faded, 0.55 * fade)
				# Sun-bleach along streaks: long in one axis, like cloth that has
				# hung folded in a window.
				var sun := _value(u, v * 0.25, 22, 611)
				c = _shade(c, 1.0 + fade * 0.25 * smoothstep(0.62, 0.9, sun))
				# Stains darken, they never lighten.
				c = _shade(c, 1.0 - fade * 0.5 * smoothstep(0.6, 0.85, _fbm(u, v, 612, 4, 3)))
			# The weave: a 2 px twill, a few per cent either way. It is what
			# separates cloth from painted plastic at this resolution.
			var twill: float = 1.0 + (0.045 if posmod(x + y, 4) < 2 else -0.045)
			c = _shade(c, twill * _grime(u, v, 613, 0.18 + 0.12 * fade))
			_img.set_pixel(x, y, c)


func _camo_fabric() -> void:
	_camo(0.0)


func _camo_fabric_worn() -> void:
	_camo(1.0)


## A shoulder board. One strong idea per texture, because it is a few dozen
## pixels on screen: a metal-edged board of cloth, plus either nothing, a braid
## or rank pips.
##
## WHY THESE SHIP A MASK. The faction shader's derived mask paints luminance
## 0.24 to 0.66, and the pack's ceiling is CEIL (0.46). Braid and pips ought to
## stay bright metal, but "bright" in this pack is 0.40 to 0.46 — which is
## still inside the band, so on the derived mask the braid turns faction orange
## along with the cloth. There is no luminance above the band to put it in. The
## red channel of <name>_mask.png says exactly which pixels are the board:
## 1 on the cloth, 0 on the edge, braid and pips. Use it with
## derive_mask_from_albedo = false. (Green is 0: no emissive markers here.)
##
## `kind`: 0 plain, 1 braid, 2 pips.
func _epaulette(kind: int) -> void:
	var trim := Color(0.40, 0.385, 0.35)       # the bright metal edge, braid, pips
	var field := Color(0.325, 0.315, 0.28)     # the cloth — inside the paint band
	var seam := Color(0.04, 0.04, 0.042)
	var mid := SIZE / 2
	var pips := [40, 128, 216]
	for y in SIZE:
		for x in SIZE:
			var u := float(x) / SIZE
			var v := float(y) / SIZE
			var edge: int = mini(mini(x, SIZE - 1 - x), mini(y, SIZE - 1 - y))
			var c: Color
			var painted := true
			var chipped := false
			if edge < 10:
				c = _shade(trim, 0.88 + 0.24 * _fbm(u, v, 701, 3, 8))
				painted = false
				if edge < 2:
					c = _shade(c, 0.6)         # the lit lip of the rim
			elif edge < 13:
				c = seam                       # a shadow line between rim and cloth
			else:
				# Cloth: a coarse twill and the dirt of use. Painted in the
				# faction colour, so the weave has to survive the multiply.
				var twill: float = 1.0 + (0.07 if posmod(x + y, 4) < 2 else -0.07)
				c = _shade(field, twill * _grime(u, v, 702, 0.3))
				if kind == 1:
					var dy := y - mid
					if absi(dy) <= 33:
						painted = false
						if absi(dy) >= 32:
							c = seam
						else:
							# A chevron rope along the board: bright and dark
							# strands, which is what braid is.
							var strand := posmod(x + absi(dy) * 2, 16) < 8
							c = _shade(trim, 1.0 if strand else 0.62)
							if absi(dy) >= 29:
								c = _shade(trim, 0.8)    # the braid's own edging
				elif kind == 2:
					for px: int in pips:
						var dx := float(x - px)
						var dy := float(y - mid)
						var r := sqrt(dx * dx + dy * dy)
						if r < 23.0:
							painted = false
							if r >= 20.0:
								c = seam                  # outline
							elif r >= 9.0:
								c = _shade(trim, 1.0 - 0.18 * smoothstep(12.0, 20.0, r))
							else:
								c = _shade(trim, 0.58)    # the dished centre
			_img.set_pixel(x, y, c)
			if _mask != null:
				# A chip keeps 40% of the paint weight. Fully unpainted bare metal
				# beside a saturated cyan field reads pinkish by contrast alone (the
				# measured pixels are neutral, see the round-three notes), so the
				# worn metal keeps a little of the livery. Rim and rivets stay at 0.
				var mv := 1.0 if painted else (0.4 if chipped else 0.0)
				_mask.set_pixel(x, y, Color(mv, 0, 0))


func _epaulette_plain() -> void:
	_epaulette(0)


func _epaulette_braid() -> void:
	_epaulette(1)


func _epaulette_pips() -> void:
	_epaulette(2)


# ── Pauldron plate ───────────────────────────────────────────────────────────
#
# Painted steel for the shoulder dome and its lames, as opposed to the cloth
# board above. Seen only on curves, small (a lame is ~12 px tall at squad
# distance) and kit the robot has earned, so: a clean field, not a rusted one.
#
# THE MASK IS THE DESIGN. Same arrangement as _epaulette — red is paint, and the
# trim cannot be held out by luminance because CEIL sits inside the shader's
# band — but inverted in emphasis: here the FIELD is the larger part (about 65%
# of the tile) and what is held out is the places real painted armour wears back
# to metal first: the rolled edge top and bottom, the rivet heads, and chipped
# scuffs that gather toward the edges and on the highlight crest.
#
# GRAIN RUNS HORIZONTALLY, per row. Rolled steel is finished that way, and it
# is the one direction that does not skew as the UVs wrap round a sphere or a
# cylinder arc. Every noise below is stretched along x for that reason, and
# lattices wrap on x so the tile joins.
#
# THE HIGHLIGHT IS PAINTED IN. GL compatibility lights flat and these pieces are
# curved, so the sweep of light has to be in the albedo. It sits in the upper
# third, is broad with a narrower crest inside it, wobbles and breaks along u
# so it reads as a reflection travelling over a curve and not as a stripe. The
# mask bypasses the paint band, so luminance is NOT constrained to it: the crest
# goes to the ceiling and the lower third near black (round two, see _sweep_base).

## Noise that is smooth along x (cells `xcell` px wide, wrapping) and independent
## per row, which is what brushed grain looks like.
func _brush(x: int, y: int, xcell: int, seed: int) -> float:
	var cells := SIZE / xcell
	var fx := float(x) / float(xcell)
	var i := int(floorf(fx))
	var t := fx - i
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(_hash(posmod(i, cells), y, seed), _hash(posmod(i + 1, cells), y, seed), t)


## Luminance of the field's sweep at height v (0..1 down the tile), BEFORE the
## crest is added. Knots are {v, luminance}; smoothstep between them so the
## ramp has no kinks for the eye to catch as bands.
##
## ROUND TWO'S WHOLE POINT. Round one hit every number and photographed as
## plastic because it spent its luminance on an even mid-field (0.25 everywhere)
## and left the sweep subtle. Two facts in faction_metal.gdshader decide
## where luminance should go: an explicit mask BYPASSES the paint band, so
## luminance is free to be anything; and the paint is albedo * colour * 2, a
## multiply, so the faction colour only reads where the albedo is bright. So
## the ramp takes the full range: crest at the ceiling, lower third near black.
func _sweep_base(v: float, lo: float, peak: float) -> float:
	var knots := [
		Vector2(0.00, lo * 1.5),
		Vector2(0.12, lerpf(lo, peak, 0.78)),
		Vector2(0.285, peak),
		Vector2(0.44, lerpf(lo, peak, 0.66)),
		Vector2(0.62, lerpf(lo, peak, 0.32)),
		Vector2(0.80, lo),
		Vector2(1.00, lo * 1.2),
	]
	for i in knots.size() - 1:
		var a: Vector2 = knots[i]
		var b: Vector2 = knots[i + 1]
		if v <= b.x:
			return lerpf(a.y, b.y, smoothstep(a.x, b.x, v))
	return (knots[knots.size() - 1] as Vector2).y


## One plate texture, four ages and a lame variant.
##   tier 0 service   clean, light wear: the tier a new pauldron wears
##   tier 1 worn      more chips and edge-wear, darker grime, crest a little lower
##   tier 2 dress     cleanest, brightest crest, and a bare trim line held out
##                    of the mask across the dome: the lieutenant's
##   lame             the service plate with its grain turned 90 degrees in
##                    texture space (see below)
##
## THE LAME'S GRAIN. The lames' UVs come from faceted wrapped-plate geometry
## in mockup_parts.gd, which is off limits, and round one found they photograph
## with VERTICAL grain from a texture drawn with horizontal grain. A texture
## cannot fix a UV problem, but it can cancel it: draw the grain along y here
## and it lands along x on the lames. The sweep stays on v; it is long-
## wavelength and survives either mapping.
func _pauldron(tier: int, lame: bool = false) -> void:
	# THE CEILING IS RAISED FOR THIS FAMILY ONLY. faction_metal paints with
	# albedo * colour * 2, a multiply, so the faction colour is only as bright as
	# the albedo under it; at CEIL 0.46 a strong sweep forced the mean down and
	# took the colour with it. CEIL is our convention, not a pack property: the
	# pack's own peaks reach 1.0 (grass_6 0.999, grass_3 0.976, stone_3_2 0.937)
	# with a mean near 0.175. The headroom goes to the crest and upper shoulder,
	# not to a wider ramp; the lower third stays where it was.
	_ceil = 0.72
	var field := Color(0.318, 0.305, 0.272)    # paint colour: sets hue and sat
	var field_lum := field.r * 0.2126 + field.g * 0.7152 + field.b * 0.0722
	var steel := Color(0.15, 0.157, 0.165)      # bare rolled steel, a touch cool
	var bare := Color(0.40, 0.415, 0.415)       # worn through to bright metal
	var seam := Color(0.045, 0.045, 0.05)
	var rim := 14                               # rolled edge, top and bottom
	var peak: float = [0.53, 0.54, 0.54][tier]        # the broad shoulder of light
	var crest_add: float = [0.21, 0.21, 0.22][tier]   # narrow crest on top of it
	var lo: float = [0.085, 0.075, 0.09][tier]        # floor of the lower third
	var wear: float = [2.1, 3.2, 1.5][tier]          # scuff appetite
	var dirt: float = [0.12, 0.26, 0.06][tier]
	var rivets := []
	if not lame:
		for i in 16:
			rivets.append(Vector2(8 + i * 16, 168))
	for y in SIZE:
		var v := float(y) / SIZE
		var edge := mini(y, SIZE - 1 - y)
		for x in SIZE:
			var u := float(x) / SIZE
			var c: Color
			var painted := true
			var chipped := false
			# Fine grain: along x on the plate, along y on the lame.
			var g1 := _brush(y, x, 64, 801) if lame else _brush(x, y, 64, 801)
			var g2 := _brush(y, x, 16, 802) if lame else _brush(x, y, 16, 802)
			var grain := 0.5 * g1 + 0.5 * g2
			var wob := 0.03 * sin(u * TAU * 2.0 + 1.3) + 0.02 * sin(u * TAU * 3.0)
			# The crest is a reflection, so it breaks along u instead of
			# running as a ruled stripe, but never drops below 55%: the sweep
			# must survive wherever it is looked at.
			var gap := _value(u, v * 0.3, 5, 810)
			var crest := exp(-pow((v + wob - 0.275) / 0.04, 2.0)) * (0.55 + 0.45 * smoothstep(0.25, 0.75, gap))
			var lum_target := _sweep_base(clampf(v + wob, 0.0, 1.0), lo, peak) + crest_add * crest
			if edge < rim:
				# Rolled edge in four hard steps across its section: dark
				# underside, bright crest. The top lip catches the light, the
				# bottom one is in shadow.
				var s := edge
				var k := 0.62 if s < 3 else (1.55 if s < 6 else (1.15 if s < 9 else 0.8))
				var tone := 1.0
				if y >= SIZE / 2:
					k = 0.62 if s < 3 else (1.0 if s < 6 else (1.3 if s < 9 else 0.8))
					tone = 0.7
				c = _shade(steel, tone * k * (0.85 + 0.3 * grain))
				painted = false
			elif edge < rim + 2:
				c = seam
				painted = false
			else:
				# Field: the ramp, with grain and mottle as SMALL modulations
				# on top (about +-8% and +-5%), so they never compete with it.
				var f := lum_target / field_lum
				f *= 0.92 + 0.16 * grain
				f *= 0.95 + 0.10 * _value(u * 2.0, v * 0.5, 4, 820)
				c = _shade(field, f)
				# Scuffs: chipped to cool bare metal, gathering toward the
				# edges and on the crest where a hand or strap rubs. Bare metal
				# follows the ramp (lit where the plate is lit), so a chip on
				# the dark lower third does not glow like a lamp.
				var near := 1.0 - smoothstep(rim + 2.0, rim + 36.0, float(edge))
				var rub := (1.15 * near + 0.5 * crest) * wear
				# CHUNKY AND FEW: nothing finer than ~8 texels survives at squad
				# distance, so round two's many small chips were invisible.
				var chip := _brush(x, int(y / 6), 40, 830) * 0.6 + _value(u, v, 5, 831) * 0.4
				if lame:
					chip = _brush(int(x / 6), y, 40, 830) * 0.6 + _value(u, v, 5, 831) * 0.4
				if chip > 0.93 - rub * 0.42:
					var bl := clampf(0.16 + 0.55 * lum_target, 0.0, 0.60)
					c = _shade(bare, (bl / 0.41) * (0.85 + 0.3 * grain))
					painted = false
					chipped = true
				# Dress trim: a pair of bare lines across the dome, held out of
				# the mask so the faction field reads as inlaid between them.
				if tier == 2 and not lame and (absi(y - 98) < 2 or absi(y - 106) < 2):
					c = _shade(bare, 0.78 + 0.2 * grain)
					painted = false
			# Rivet heads: a dome, lit upper-left and dark lower-right, nine
			# texels across, in a tight row of sixteen (ten-texel rivets in a
			# row of eight rendered as two staring eyes on the dome).
			for rv: Vector2 in rivets:
				var dx := float(x) - rv.x
				var dy := float(y) - rv.y
				var r := sqrt(dx * dx + dy * dy)
				if r < 4.5:
					painted = false
					if r >= 3.6:
						c = seam
					else:
						c = _shade(bare, 1.1 if (dx + dy) < 0.0 else 0.6)
			c = _shade(c, _grime(u, v, 840, dirt))
			_img.set_pixel(x, y, c)
			if _mask != null:
				# A chip keeps 40% of the paint weight. Fully unpainted bare metal
				# beside a saturated cyan field reads pinkish by contrast alone (the
				# measured pixels are neutral, see the round-three notes), so the
				# worn metal keeps a little of the livery. Rim and rivets stay at 0.
				var mv := 1.0 if painted else (0.4 if chipped else 0.0)
				_mask.set_pixel(x, y, Color(mv, 0, 0))


func _pauldron_plate() -> void:
	_pauldron(0)


func _pauldron_worn() -> void:
	_pauldron(1)


func _pauldron_dress() -> void:
	_pauldron(2)


func _pauldron_lame() -> void:
	_pauldron(0, true)


## BEARSKIN. The Walker's officer hat: a 0.96 m column and a 0.63 m crown, the
## largest cloth in the game, drawn as fur. docs/briefs/BEARSKIN_FUR.md governs.
##
## THE TWO NUMBERS THAT DECIDE IT, both unusual. A FLOOR: luminance never below
## BEAR_FLOOR, because pure black leaves a cut-out silhouette with no interior
## (pauldron_plate measures 0.000 and that is most of why it reads as chrome).
## And a low CEILING, 0.34, because a bright highlight on fur is wet plastic.
## The faction colour is NOT carried (mask is all 0 bar the optional crown
## band), so there is no multiply to feed and no excuse for brightness.
##
## NOTHING HORIZONTAL. The column is a 16-sided cylinder: any horizontal band
## becomes sixteen marching rings. Every field below varies along u fast and
## along v slowly, except the strand segments, which are hard-edged in u and
## long in v.
##
## Structure, in order of work done at distance:
##   1. strands     hard-edged vertical streaks 8-14 texels wide, in segments
##                  of 70-200 texels that never span the full height; two
##                  layers with different edges so the silhouette of a strand
##                  is broken by the one beneath it (that is the depth)
##   2. clumps      soft darker masses 40-65 texels, grouping the strands
##   3. gradient    gentle, brighter in the top third
##   4. tips        short bright strokes at the head of about 1 segment in 8
## tier 0 issue, tier 1 worn: matted felted patches, heavier clumping, some
## strands laid flat and shinier.
const BEAR_FLOOR := 0.075
## Optional faction highlight: the top rows of the crown. See _bearskin.
const BEAR_CROWN_BAND := 10

func _bear_strands(seed: int, wmin: int, wmax: int) -> Array:
	# Returns [[x0, x1, [[y0, len, bright], ...]], ...] covering 0..SIZE exactly.
	var out := []
	var x := int(_hash(seed, 1, 7) * 6.0)
	var first := x
	var i := 0
	while x < first + SIZE:
		var w := wmin + int(_hash(i, seed, 11) * float(wmax - wmin + 1))
		if first + SIZE - (x + w) < wmin:
			w = first + SIZE - x
		var segs := []
		var y := int(_hash(i, seed, 13) * SIZE)
		var total := 0
		var k := 0
		while total < SIZE:
			var ln := 120 + int(_hash(i * 31 + k, seed, 17) * 110.0)
			# NO GAP: at 3x tiling a gap is a dark horizontal rule round the column
			# (round six). Segments abut; the step is in brightness only.
			var gap := 0
			# Brightness is mostly the STRAND's (constant down its length) with a small
			# per-segment step: vertical streaks, not a brick pattern, because the
			# material tiles 3x down the column and every step is a horizontal edge.
			segs.append([y, ln, 0.9 * _hash(i, seed, 41) + 0.10 * _hash(i * 31 + k, seed, 23)])
			y += ln + gap
			total += ln + gap
			k += 1
		out.append([x, x + w, segs])
		x += w
		i += 1
	return out


## The segment covering row y on a strand, or [] if it is in a gap. Segments
## wrap vertically, so the texture has no seam, but none is the full height.
func _bear_seg(segs: Array, y: int) -> Array:
	for s: Array in segs:
		var d := posmod(y - int(s[0]), SIZE)
		if d < int(s[1]):
			return [d, s[1], s[2]]
	return []


func _bearskin(tier: int) -> void:
	_ceil = 0.34
	_floor = 0.05
	var worn := tier == 1
	var tint := Color(1.0, 0.97, 0.945)   # near neutral, a touch warm: sat ~0.055
	# SCALE IS SET BY THE TILING, NOT THE TEXEL COUNT. The material tiles 3x3, so
	# a texel is a third of its apparent size: the brief's 8-14 texel strands are
	# 2.7-4.7 effective, under a pixel at 20 m (round five: invisible). 26-42
	# texels, clumps on lattices of 2-3 cells (85-128 texels), same two-scale ratio.
	var under := _bear_strands(100 + tier, 16, 26)
	var over := _bear_strands(200 + tier, 17, 26)
	var crown_mask := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		var v := float(y) / SIZE
		# Gentle, and PERIODIC: the material tiles 3x down the column (FUR_TILING),
		# so a one-way ramp restarts every 0.32 m as a ring (round one saw exactly
		# that). +-6% on a cosine has no seam. Any steeper and
		# it reads as a gradient fill.
		var grad := 1.0 + 0.06 * cos(v * TAU)
		for x in SIZE:
			var u := float(x) / SIZE
			# Layer 0: the under-coat, darker, always present (no black holes).
			var lum := 0.095
			var tip := false
			var flat := false
			for st: Array in under:
				if x >= int(st[0]) and x < int(st[1]):
					var sg := _bear_seg(st[2], y)
					if not sg.is_empty():
						lum = 0.09 + 0.05 * float(sg[2])
					break
			# Layer 1: the nap on top. Missing in gaps, so the dark under-coat
			# shows through between strands.
			for st: Array in over:
				if x >= int(st[0]) and x < int(st[1]):
					var sg := _bear_seg(st[2], y)
					if sg.is_empty():
						break
					var d: int = sg[0]
					var ln: int = sg[1]
					var b: float = sg[2]
					lum = 0.085 + 0.16 * b
					# Darker toward the root (the foot) of each strand: the
					# valley between hairs.
					lum *= 0.80 + 0.20 * (1.0 - float(d) / float(ln))
					# Tips: about 1 strand in 8, the head of the segment only.
					if _hash(int(st[0]), int(sg[1]), 29) < 0.2 and d < 24:
						lum += 0.10 * (1.0 - float(d) / 24.0)
						tip = true
					# Flat shiny strands, worn only: laid down, even, lighter.
					if worn and _hash(int(st[0]), int(ln), 31) < 0.13:
						lum = 0.205 + 0.02 * b
						flat = true
					break
			# Clumps: soft, 40-65 texels (period 4 = 64, period 5 = 51).
			var cn := 0.6 * _value_aniso(u, v, 2, 2, 301) + 0.4 * _value_aniso(u, v, 3, 2, 302)
			var cd := 0.55 if worn else 0.70
			var cf := cd + (1.0 - cd) * smoothstep(0.30, 0.62, cn)
			lum *= cf
			if worn:
				# Matted patches: fur felted into a flat, even, slightly paler
				# mass, soft-edged, ~60 texels.
				var mat := _value_aniso(u, v, 2, 2, 311)
				var m := smoothstep(0.55, 0.68, mat)
				lum = lerpf(lum, 0.125 + 0.015 * _value(u, v, 16, 312), m)
			lum *= grad
			lum = clampf(lum, BEAR_FLOOR, 0.31)
			_img.set_pixel(x, y, Color(tint.r * lum, tint.g * lum, tint.b * lum))
			if y < BEAR_CROWN_BAND:
				crown_mask.set_pixel(x, y, Color(1, 0, 0))
	# Mask: everything held out. The silhouette does the rank-reading.
	if _mask != null:
		_mask.fill(Color(0, 0, 0))
	if tier == 0:
		_bear_alt_mask = crown_mask


var _bear_alt_mask: Image


func _bearskin_fur() -> void:
	_bearskin(0)


func _bearskin_fur_worn() -> void:
	_bearskin(1)


## _value with separate lattice periods across (pu) and down (pv): clumps that
## are narrow but long, so they group strands instead of banding the column.
func _value_aniso(u: float, v: float, pu: int, pv: int, seed: int) -> float:
	var fx := u * pu
	var fy := v * pv
	var ix := int(floorf(fx))
	var iy := int(floorf(fy))
	var tx := fx - ix
	var ty := fy - iy
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := _hash(posmod(ix, pu), posmod(iy, pv), seed)
	var b := _hash(posmod(ix + 1, pu), posmod(iy, pv), seed)
	var c := _hash(posmod(ix, pu), posmod(iy + 1, pv), seed)
	var d := _hash(posmod(ix + 1, pu), posmod(iy + 1, pv), seed)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


## ROACH COMB. The Tarleton's crest, deliberately metal (docs/briefs/BEARSKIN_FUR.md
## records the decision): a polished fluted comb, not fur.
##
## THE ARITHMETIC, done before any drawing. The roach is a CSG sphere squashed
## to a blade 1.32 m long, 0.92 m tall, 0.22 m thick, so the mapping is spherical:
## u runs around the polar axis, which is FORE-AND-AFT along the blade, and v is
## height with the crest at one pole. The plate material tiles 3x in u and 1x in
## v (PLATE_TILING), and the blade is about 62 x 43 px at 20 m. That is ~12 texels
## per pixel in u (256 over 62 px across 3 repeats) and ~6 in v. So:
##   - flutes are vertical stripes in texture space, 36-48 texels wide, which is
##     three to four pixels each: six per repeat, eighteen round the blade;
##   - nothing may be finer than ~24 texels in u or ~12 in v. The bearskin
##     shipped 8-14 texel strands against the same 3x and lost two rounds to it;
##   - the crest is a pole, so detail converges there, which suits a comb.
## Anything horizontal in texture space becomes a ring round the blade, so the
## only horizontal things here are the ones that should be: the crest band, the
## clamp strip at the base and the dark seat below it.
##
## FLOOR 0.032 (one quantise level): pauldron_plate has a minimum of 0.000 and
## photographs as chrome. PEAK 0.55: polished is the intent, but 0.70 against a
## 0.000 floor is what made the pauldron read as plastic.
## Scuffs are cool-neutral: warm bare-metal scuffs render as dirt under GL
## compatibility (it cost the pauldron a round).
const COMB_FLUTES := [44, 38, 46, 40, 42, 46]    # sums to SIZE; irregular on purpose
const COMB_STRIP_Y := 122
const COMB_STRIP_H := 34


func _roach_comb(worn: bool) -> void:
	_ceil = 0.55
	_floor = 0.032
	var tint := Color(0.96, 1.0, 1.06)        # steel, very slightly cool
	var n := COMB_FLUTES.size()
	var edges := []                            # nominal left edge of each flute
	var acc := 0
	for w: int in COMB_FLUTES:
		edges.append(acc)
		acc += w
	# Per-flute character, so no two read as the same stamping.
	var gain := []
	var lit := []
	var phase := []
	for k in n:
		gain.append(0.88 + 0.24 * _hash(k, 1, 4101))
		lit.append(0.27 + 0.12 * _hash(k, 2, 4102))
		phase.append(_hash(k, 3, 4103) * TAU)
	for y in SIZE:
		var v := float(y) / SIZE
		# Flute edges drift with height by a few texels, telescoping so the
		# widths still sum to SIZE and the texture still tiles.
		var b := []
		for k in n:
			b.append(float(edges[k]) + 3.0 * sin(v * TAU + phase[k]))
		b.append(float(SIZE) + float(b[0]) - float(edges[0]))
		# Crest: a band at the top edge, broken along u but never below 55%.
		var crest_w := 0.26 if worn else 0.32
		for x in SIZE:
			var u := float(x) / SIZE
			var k := 0
			var xx := float(x)
			var found := false
			for kk in n:
				for off in [0.0, float(SIZE), -float(SIZE)]:
					if xx + off >= float(b[kk]) and xx + off < float(b[kk + 1]):
						k = kk
						xx += off
						found = true
						break
				if found:
					break
			var wk: float = float(b[k + 1]) - float(b[k])
			var t := clampf((xx - float(b[k])) / wk, 0.0, 1.0)
			var s := sin(PI * t)
			var prof := pow(s, 0.6) * (0.45 + 0.55 * exp(-pow((t - float(lit[k])) / 0.30, 2.0)))
			prof *= float(gain[k])
			var gap := _value_aniso(u, v, 6, 3, 4110)
			var crest := (1.0 - smoothstep(0.04, crest_w, v)) * (0.55 + 0.45 * smoothstep(0.25, 0.75, gap))
			# Height: bright shoulder in the upper half, falling to the seat.
			var hf := lerpf(1.0, 0.86, smoothstep(0.2, 0.55, v))
			hf = lerpf(hf, 0.55, smoothstep(0.60, 0.95, v))
			var floor_l := lerpf(0.07, 0.33, crest)
			var peak_l := lerpf(0.45 * hf, 0.54, crest)
			if worn:
				floor_l *= 0.75
				peak_l *= 0.92
			var lum := floor_l + (peak_l - floor_l) * clampf(prof, 0.0, 1.0)
			var painted := true
			# Soft mottle so the flutes are not one flat ramp (large: 85+ texels).
			lum *= 0.94 + 0.12 * _value_aniso(u, v, 3, 2, 4120)
			if worn:
				lum *= _grime(u, v, 4130, 0.5)
			# Highlight on each flute: held out of the mask, bare steel.
			if prof > 0.80 and v > 0.03:
				painted = false
			# Wear: crest edge ONLY. Cool bright scuffs, chunky (cells of 32 texels).
			var rub := 1.0 - smoothstep(0.06, 0.20 if worn else 0.14, v)
			var chip := _value_aniso(u, v, 8, 8, 4140) * 0.7 + _value_aniso(u, v, 16, 6, 4141) * 0.3
			if rub > 0.0 and chip > (0.62 if worn else 0.70) - 0.12 * rub:
				lum = maxf(lum, 0.50 - 0.06 * (1.0 - rub))
				painted = false
			# Clamp strip and rivets: a ring round the base where the comb seats
			# into the skull. Bare steel, so held out of the mask.
			var sy := y - COMB_STRIP_Y
			var c: Color
			if sy >= 0 and sy < COMB_STRIP_H:
				painted = false
				var grain := _brush(x, y, 64, 4150)
				if sy < 8:
					lum = 0.30 + 0.06 * grain
				elif sy < COMB_STRIP_H - 6:
					lum = 0.12 + 0.05 * grain
				else:
					lum = 0.05
				# One rivet at each flute boundary: 28 x 16 texels, which is
				# roughly round on screen once the 3x u tiling is allowed for.
				for kk in n:
					var dx := (xx - float(b[kk])) / 14.0
					if absf(dx) > 1.0:
						dx = (xx - float(b[kk]) - float(SIZE)) / 14.0
					if absf(dx) > 1.0:
						dx = (xx - float(b[kk]) + float(SIZE)) / 14.0
					var dy := (float(sy) - 15.0) / 8.0
					var r := sqrt(dx * dx + dy * dy)
					if r < 1.0:
						if r > 0.78:
							lum = 0.04
						else:
							lum = 0.34 if (dx + dy) < 0.0 else 0.15
			c = Color(tint.r * lum, tint.g * lum, tint.b * lum)
			_img.set_pixel(x, y, c)
			if _mask != null:
				_mask.set_pixel(x, y, Color(1.0 if painted else 0.0, 0, 0))


func _roach_comb_plain() -> void:
	_roach_comb(false)


func _roach_comb_worn() -> void:
	_roach_comb(true)
