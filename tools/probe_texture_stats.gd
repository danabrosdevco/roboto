extends SceneTree

# ─────────────────────────────────────────────
# PROBE TEXTURE STATS — does a texture belong to the pack?
#
#   godot --headless --path . --script res://tools/probe_texture_stats.gd -- textures/PSX_Textures
#   ... -- textures/PSX_Textures camo epaulette      (only names containing these)
#
# The pack's look is measurable, not a matter of taste: 256x256 RGB8, a mean
# luminance near 0.20, a peak capped at 0.46, saturation between 0.08 and 0.25.
# A new texture that misses those is wrong beside everything else even when it
# is a better texture on its own.
#
# It also reports where the texture sits against the faction shader's paint
# band (Character/faction_metal.gdshader, centre 0.45 width 0.425), because
# that decides whether the faction colour repaints it. Under the band a texture
# keeps its own colours; inside it, it becomes the faction's.
#
# Luminance is weighted the way the shader weights it, not the way a paint
# program would, so the band numbers mean what they say.
# ─────────────────────────────────────────────

const LUM := Vector3(0.2126, 0.7152, 0.0722)
const BAND_CENTRE := 0.45
const BAND_HALF := 0.425 * 0.5


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: ... --script res://tools/probe_texture_stats.gd -- <dir> [name filters]")
		quit(2)
		return
	var dir: String = args[0]
	if not dir.begins_with("res://"):
		dir = "res://" + dir
	var filters: Array = args.slice(1)

	var d := DirAccess.open(dir)
	if d == null:
		print("FAIL  cannot open %s" % dir)
		quit(1)
		return
	var names: Array = []
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".png"):
			names.append(f)
		f = d.get_next()
	d.list_dir_end()
	names.sort()

	print("\n   %-26s %5s %6s %6s %6s %7s" % ["texture", "size", "mean", "peak", "sat", "inband"])
	var shown := 0
	for n: String in names:
		if not filters.is_empty():
			var keep := false
			for k: String in filters:
				if n.contains(k):
					keep = true
					break
			if not keep:
				continue
		var img := Image.load_from_file(ProjectSettings.globalize_path(dir.path_join(n)))
		if img == null:
			push_warning("probe_texture_stats: %s did not load — not measured" % n)
			continue
		var w := img.get_width()
		var h := img.get_height()
		var sum := 0.0
		var peak := 0.0
		var sat := 0.0
		var inband := 0
		for y in h:
			for x in w:
				var c := img.get_pixel(x, y)
				var v := Vector3(c.r, c.g, c.b)
				var l := v.dot(LUM)
				sum += l
				peak = maxf(peak, l)
				var hi: float = maxf(c.r, maxf(c.g, c.b))
				var lo: float = minf(c.r, minf(c.g, c.b))
				sat += 0.0 if hi <= 0.0 else (hi - lo) / hi
				if absf(l - BAND_CENTRE) <= BAND_HALF:
					inband += 1
		var px := float(w * h)
		print("   %-26s %5s %6.3f %6.3f %6.3f %6.1f%%" % [
				n.get_basename(), "%dx%d" % [w, h], sum / px, peak, sat / px,
				100.0 * float(inband) / px])
		shown += 1
	print("\n   %d texture(s). pack: mean ~0.20, peak <= 0.46, sat 0.08-0.25." % shown)
	print("   inband = share repainted in the faction colour by the derived mask")
	quit()
