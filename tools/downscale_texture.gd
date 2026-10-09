extends SceneTree

# ─────────────────────────────────────────────
# DOWNSCALE TEXTURE — bring a bought 4K texture into the PSX pack.
#
#   godot --headless --path . --script res://tools/downscale_texture.gd -- \
#       "2d_assets/metal textures poly.com/metal_plate_02_diff_4k.jpg" robot_metal_psx
#
#   MEAN=0.20 SIZE=256 ... (optional overrides)
#
# WHY THIS IS NOT JUST A RESIZE. Two 4K photographic textures are still in the
# game — a rusted metal plate on every robot hull, and a white tile AO map
# doing duty as the eye. Resized to 256 they would still not match: the pack is
# not merely small, it is DARK, QUANTISED and DITHERED. Measured over all its
# files, mean luminance averages 0.175 and nearly everything sits between 0.10
# and 0.28, every texture is 32 levels a channel, and the banding is broken by
# a 4x4 ordered dither rather than left smooth.
#
# A photograph dropped in at its own exposure reads as a photograph: it is
# brighter than everything round it, it has a smooth gradient where the pack
# has steps, and it has detail at a scale the pack never shows. So this
# rescales the luminance into the pack's range, caps the peak, then quantises
# through the same dither make_textures.gd uses.
#
# THE DITHER IS DUPLICATED FROM make_textures.gd ON PURPOSE. That file is
# large, frequently edited by whoever is making textures, and generates from
# nothing; this one only ever reads an existing file. Keeping them apart means
# a downscale run can never touch a generator. If the two drift, this comment
# is the place to notice.
#
# Licence note: these are assets already shipped in this project, being
# resized for use in it. The "draw from nothing, never sample the bought pack"
# rule in docs/briefs applies to GENERATING new textures in the pack's style,
# which is a different thing and is make_textures.gd's job.
# ─────────────────────────────────────────────

## The pack's signature, measured over all 212 files.
const PACK_MEAN := 0.175
## Nothing generated for this pack goes brighter. A photograph will, unless
## told not to.
const CEIL := 0.46
## Levels per channel in the final quantise.
const LEVELS := 32
## The same 4x4 ordered Bayer matrix the pack is dithered with.
const BAYER: Array = [
	[0.0, 8.0, 2.0, 10.0],
	[12.0, 4.0, 14.0, 6.0],
	[3.0, 11.0, 1.0, 9.0],
	[15.0, 7.0, 13.0, 5.0],
]
const LUM := Vector3(0.2126, 0.7152, 0.0722)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: ... --script res://tools/downscale_texture.gd -- <source path> <out name> [--force]")
		quit(2)
		return
	var src_path: String = args[0]
	var out_name: String = args[1]
	var force := args.has("--force")
	var size := int(OS.get_environment("SIZE")) if OS.get_environment("SIZE") != "" else 256
	var want_mean := float(OS.get_environment("MEAN")) if OS.get_environment("MEAN") != "" else PACK_MEAN

	var abs_src := ProjectSettings.globalize_path(src_path if src_path.begins_with("res://") else "res://" + src_path)
	var img := Image.load_from_file(abs_src)
	if img == null:
		print("FAIL  could not read %s" % src_path)
		quit(1)
		return
	var was := "%dx%d" % [img.get_width(), img.get_height()]
	var before := _stats(img)

	# Lanczos, not nearest: we are throwing away 99% of the pixels and want the
	# average of what is discarded, not one survivor from each block.
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)

	_retone(img, want_mean)
	_finish(img)

	var out_dir := "res://textures/PSX_Textures"
	var out_png := out_dir.path_join(out_name + ".png")
	if FileAccess.file_exists(ProjectSettings.globalize_path(out_png)) and not force:
		print("SKIP  %s exists — pass --force to overwrite it." % out_png)
		quit()
		return
	var err := img.save_png(ProjectSettings.globalize_path(out_png))
	if err != OK:
		print("FAIL  could not write %s (%s)" % [out_png, error_string(err)])
		quit(1)
		return
	_write_material(out_dir, out_name)

	var after := _stats(img)
	print("\n   %s" % src_path.get_file())
	print("   %-10s %9s  min %.3f  mean %.3f  peak %.3f  sat %.3f" % [
			"before", was, before.lo, before.mean, before.hi, before.sat])
	print("   %-10s %9s  min %.3f  mean %.3f  peak %.3f  sat %.3f" % [
			"after", "%dx%d" % [size, size], after.lo, after.mean, after.hi, after.sat])
	print("   pack: mean averages 0.175, nearly all 0.10-0.28, ceiling %.2f" % CEIL)
	print("   wrote %s and its .tres" % out_png.get_file())
	print("\nDOWNSCALE DONE")
	quit()


## Shift the image to `want` mean luminance and hold the peak under CEIL.
##
## A multiply, not a curve: it keeps the relationships inside the photograph
## intact, which is the whole reason for starting from one. If the multiply
## would push the brightest pixel over the ceiling the scale is reduced until
## it does not, so the ceiling wins over the mean — a texture a little darker
## than the pack reads as part of it, one that blows out does not.
func _retone(img: Image, want: float) -> void:
	var s := _stats(img)
	if float(s.mean) <= 0.0001:
		push_warning("downscale_texture: the source is black — nothing to retone")
		return
	var scale: float = want / float(s.mean)
	if float(s.hi) * scale > CEIL:
		scale = CEIL / maxf(float(s.hi), 0.0001)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(
					minf(c.r * scale, 1.0), minf(c.g * scale, 1.0), minf(c.b * scale, 1.0)))


## Quantise to LEVELS through the ordered dither, as the pack is.
func _finish(img: Image) -> void:
	var step := 1.0 / float(LEVELS - 1)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			# +0.5 centres the threshold so the dither does not bias the image
			# brighter or darker overall, only breaks up the bands.
			var t: float = (BAYER[y % 4][x % 4] + 0.5) / 16.0 - 0.5
			img.set_pixel(x, y, Color(
					_q(c.r, step, t), _q(c.g, step, t), _q(c.b, step, t)))


func _q(v: float, step: float, t: float) -> float:
	return clampf(roundf((v + t * step) / step) * step, 0.0, 1.0)


func _stats(img: Image) -> Dictionary:
	var sum := 0.0
	var hi := 0.0
	var lo := 1.0
	var sat := 0.0
	var n := 0
	# Every pixel on a 256, a 16-step stride on a 4K: this is a measurement,
	# not the output, and sampling 65k of 16M says the same thing far faster.
	var stride: int = maxi(1, img.get_width() / 256)
	for y in range(0, img.get_height(), stride):
		for x in range(0, img.get_width(), stride):
			var c := img.get_pixel(x, y)
			var l := Vector3(c.r, c.g, c.b).dot(LUM)
			sum += l
			hi = maxf(hi, l)
			lo = minf(lo, l)
			var mx: float = maxf(c.r, maxf(c.g, c.b))
			var mn: float = minf(c.r, minf(c.g, c.b))
			sat += 0.0 if mx <= 0.0 else (mx - mn) / mx
			n += 1
	return {"mean": sum / maxf(n, 1), "hi": hi, "lo": lo, "sat": sat / maxf(n, 1)}


func _write_material(dir: String, name: String) -> void:
	var path := dir.path_join(name + ".tres")
	var png := dir.path_join(name + ".png")
	var text := "\n".join([
		'[gd_resource type="StandardMaterial3D" load_steps=2 format=3]',
		'',
		'[ext_resource type="Texture2D" path="%s" id="1_albedo"]' % png,
		'',
		'[resource]',
		'albedo_texture = ExtResource("1_albedo")',
		'texture_filter = 0',
		'roughness = 1.0',
		'metallic = 0.0',
		'',
	])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("downscale_texture: could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(text)
	f.close()
