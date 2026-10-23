extends SceneTree

# ─────────────────────────────────────────────
# TILE RENDERED FRAMES INTO ONE SHEET.
#
#   godot --headless --audio-driver Dummy --path . \
#       --script res://tools/contact_sheet.gd -- \
#       <out.png> <cols> <crop x> <crop y> <crop w> <crop h> <frame.png>...
#
# For looking at an ANIMATION. preview_viewmodel.gd writes one PNG per frame and
# stacks them in a tall column, which is unreadable past three frames and quite
# unusable for comparing frame 2 against frame 5 — which is the whole question
# when a reload is wrong. This lays them out in a grid at the crop you ask for,
# so the moment a part goes missing is next to the moment it comes back.
#
# The crop is in the source image's pixels and is applied to every frame, so the
# weapon stays put between cells and only the animation moves.
# ─────────────────────────────────────────────

const PAD := 6
const INK := Color(0.07, 0.08, 0.10)


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 7:
		printerr("contact_sheet: need out, cols, crop x/y/w/h and at least one frame")
		quit(1)
		return
	var out: String = a[0]
	var cols: int = maxi(int(a[1]), 1)
	var crop := Rect2i(int(a[2]), int(a[3]), int(a[4]), int(a[5]))
	var srcs: Array = a.slice(6)
	var rows: int = int(ceil(float(srcs.size()) / float(cols)))
	var sheet := Image.create((crop.size.x + PAD) * cols + PAD,
			(crop.size.y + PAD) * rows + PAD, false, Image.FORMAT_RGBA8)
	sheet.fill(INK)
	for i in srcs.size():
		var img := Image.load_from_file(srcs[i])
		if img == null:
			printerr("contact_sheet: cannot read %s" % srcs[i])
			continue
		var cell := img.get_region(crop)
		# blit_rect refuses a format mismatch, and a PNG may come back as RGB8.
		if cell.get_format() != Image.FORMAT_RGBA8:
			cell.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, crop.size), Vector2i(
			PAD + (crop.size.x + PAD) * (i % cols),
			PAD + (crop.size.y + PAD) * int(i / cols)))
	sheet.save_png(out)
	print("contact_sheet: %s  %dx%d, %d frame(s)" % [out, sheet.get_width(), sheet.get_height(), srcs.size()])
	quit(0)
