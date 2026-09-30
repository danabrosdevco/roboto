extends SceneTree

# ─────────────────────────────────────────────
# CONTACT SHEET — tiles a folder of PNGs into a few big sheets, so a deck of
# fifty can be looked at as a set rather than one file at a time.
#
#   IN=<dir> OUT=<dir> MATCH=_plan godot --headless --path . \
#       --script res://tools/contact_sheet.gd
#
# Headless is fine: it only moves pixels about.
# ─────────────────────────────────────────────

const COLS := 4
const PER_SHEET := 16
## Tile size. The default keeps a fifty-map sheet under a couple of megabytes,
## which matters when the sheets live in the repo next to the write-up.
var TILE := Vector2i(384, 216)
const LABEL := 16


func _initialize() -> void:
	var src := OS.get_environment("IN")
	var dst := OS.get_environment("OUT")
	if src == "" or dst == "":
		print("usage: IN=<dir> OUT=<dir> [MATCH=_plan]")
		quit(2)
		return
	var match_on := OS.get_environment("MATCH")
	if OS.get_environment("TILE_W") != "":
		var w := int(OS.get_environment("TILE_W"))
		TILE = Vector2i(w, int(w * 9.0 / 16.0))
	var files: Array = []
	for f in DirAccess.get_files_at(src):
		if f.ends_with(".png") and (match_on == "" or f.contains(match_on)):
			files.append(f)
	files.sort()
	if files.is_empty():
		print("FAIL  nothing matching in %s" % src)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(dst)
	var sheets := int(ceil(float(files.size()) / PER_SHEET))
	for s in sheets:
		var slice: Array = files.slice(s * PER_SHEET, mini((s + 1) * PER_SHEET, files.size()))
		var rows := int(ceil(float(slice.size()) / COLS))
		var sheet := Image.create(COLS * TILE.x, rows * (TILE.y + LABEL), false, Image.FORMAT_RGB8)
		sheet.fill(Color(0.07, 0.07, 0.08))
		for i in slice.size():
			var img := Image.load_from_file(src.path_join(slice[i]))
			if img == null:
				continue
			img.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
			if img.get_format() != Image.FORMAT_RGB8:
				img.convert(Image.FORMAT_RGB8)
			var at := Vector2i((i % COLS) * TILE.x, (i / COLS) * (TILE.y + LABEL))
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), at)
		var path := dst.path_join("sheet_%d.png" % (s + 1))
		sheet.save_png(path)
		print("   %s — %d tile(s): %s" % [path.get_file(), slice.size(),
				", ".join(slice.map(func(f: String) -> String: return f.get_basename()))])
	print("   %d sheet(s) from %d file(s)" % [sheets, files.size()])
	quit()
