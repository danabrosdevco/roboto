extends SceneTree

# ─────────────────────────────────────────────
# MAP CARD — one picture per map: the sketch and the plan view on top, the
# eye-level shots below. For showing a handful of maps rather than a whole
# deck; tools/contact_sheet.gd is the one for fifty at a time.
#
#   IN=<deck dir> OUT=<dir> IDS=ford_town,boulevard godot --headless \
#       --path . --script res://tools/map_card.gd
#
# Headless is fine: it only moves pixels about.
# ─────────────────────────────────────────────

const W := 1600
const TOP := Vector2i(800, 450)      ## sketch and plan, side by side
const EYE := Vector2i(400, 225)      ## up to four eye shots in a row below


func _initialize() -> void:
	var src := OS.get_environment("IN")
	var dst := OS.get_environment("OUT")
	if src == "" or dst == "" or OS.get_environment("IDS") == "":
		print("usage: IN=<dir> OUT=<dir> IDS=a,b,c")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(dst)
	var made := 0
	for id in OS.get_environment("IDS").split(",", false):
		id = id.strip_edges()
		var eyes: Array = []
		for n in range(1, 9):
			var p := src.path_join("%s_eye%d.png" % [id, n])
			if FileAccess.file_exists(p):
				eyes.append(p)
		var rows: int = 1 if eyes.is_empty() else 1 + int(ceil(float(eyes.size()) / 4.0))
		var card := Image.create(W, TOP.y + (rows - 1) * EYE.y, false, Image.FORMAT_RGB8)
		card.fill(Color(0.06, 0.06, 0.07))
		_place(card, src.path_join("%s_sketch.png" % id), Vector2i(0, 0), TOP)
		_place(card, src.path_join("%s_plan.png" % id), Vector2i(TOP.x, 0), TOP)
		for i in eyes.size():
			# Wraps to a second row. Without the modulo the fifth shot onward is
			# drawn off the right edge and the row below comes out black.
			_place(card, eyes[i], Vector2i((i % 4) * EYE.x, TOP.y + (i / 4) * EYE.y), EYE)
		var out := dst.path_join("%s_card.png" % id)
		card.save_png(out)
		made += 1
		print("   %-20s %d eye shot(s) -> %s" % [id, eyes.size(), out.get_file()])
	print("   %d card(s)" % made)
	quit()


func _place(card: Image, path: String, at: Vector2i, size: Vector2i) -> void:
	if not FileAccess.file_exists(path):
		return
	var img := Image.load_from_file(path)
	if img == null:
		return
	# Letterboxed, not stretched: a sketch is 2.75:1 and a screenshot is 16:9,
	# and squashing one to fit the other misreads the map's proportions, which
	# is the one thing a plan view is for.
	var scale: float = minf(float(size.x) / img.get_width(), float(size.y) / img.get_height())
	var w := maxi(int(img.get_width() * scale), 1)
	var h := maxi(int(img.get_height() * scale), 1)
	img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	card.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(w, h)),
			at + Vector2i((size.x - w) / 2, (size.y - h) / 2))
