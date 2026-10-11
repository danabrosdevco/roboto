extends SceneTree

# ─────────────────────────────────────────────
# MAP RETEXTURE — changes a texture on part of a .map file, in place, without
# regenerating it.
#
#   MAP=res://maps/blocks/fortress/fort_tower.map \
#   FROM=PSX_Textures/glitch_tx_1 TO=PSX_Textures/concrete_tx_5 \
#   BOX=-9999,-9999,780,9999,9999,805 \
#       godot --headless --path . --script res://tools/map_retexture.gd
#
#   ...and again with --apply. It writes nothing without it.
#
# Headless is fine: it reads and writes text.
#
# WHY THIS EXISTS. A .map that has been opened in TrenchBroom is the source —
# the generator that first wrote it is not. Re-running the generator to change
# one texture throws away every hand edit made since, and that is exactly how
# 136 faces of someone's clipping fixes were destroyed on fort_tower. The rule
# in docs/BLOCKS.md says the file on disk wins; this is the tool that lets a
# small change be made without breaking it.
#
# BOX is in QUAKE UNITS (32 to the metre), and a brush is changed only if the
# whole of it lies inside. Matching faces rather than brushes would retexture
# one side of something and leave the rest, which is worse than not doing it.
# ─────────────────────────────────────────────


func _initialize() -> void:
	var path := OS.get_environment("MAP")
	var from := OS.get_environment("FROM")
	var to := OS.get_environment("TO")
	var box_text := OS.get_environment("BOX")
	if path == "" or from == "" or to == "" or box_text == "":
		print("usage: MAP=.. FROM=<texture> TO=<texture> BOX=x0,y0,z0,x1,y1,z1 [--apply]")
		quit(2)
		return
	var b: Array = []
	for v in box_text.split(",", false):
		b.append(float(v.strip_edges()))
	if b.size() != 6:
		print("FAIL  BOX wants six numbers, got %d" % b.size())
		quit(1)
		return
	var lo := Vector3(minf(b[0], b[3]), minf(b[1], b[4]), minf(b[2], b[5]))
	var hi := Vector3(maxf(b[0], b[3]), maxf(b[1], b[4]), maxf(b[2], b[5]))
	var apply := OS.get_cmdline_user_args().has("--apply")

	var text := FileAccess.get_file_as_string(path)
	if text == "":
		print("FAIL  could not read %s" % path)
		quit(1)
		return
	var lines := text.split("\n")
	var out := PackedStringArray()
	var brush: Array = []        # line indexes of the faces of the brush in hand
	var brush_lo := Vector3(INF, INF, INF)
	var brush_hi := Vector3(-INF, -INF, -INF)
	var hits := 0
	var faces := 0
	for i in lines.size():
		var line: String = lines[i]
		out.append(line)
		if line.begins_with("("):
			brush.append(out.size() - 1)
			for p in _points(line):
				brush_lo = Vector3(minf(brush_lo.x, p.x), minf(brush_lo.y, p.y), minf(brush_lo.z, p.z))
				brush_hi = Vector3(maxf(brush_hi.x, p.x), maxf(brush_hi.y, p.y), maxf(brush_hi.z, p.z))
			continue
		if line.strip_edges() == "}" and not brush.is_empty():
			# THE WHOLE BRUSH, OR NONE OF IT.
			var inside: bool = brush_lo.x >= lo.x and brush_lo.y >= lo.y and brush_lo.z >= lo.z \
					and brush_hi.x <= hi.x and brush_hi.y <= hi.y and brush_hi.z <= hi.z
			if inside:
				var touched := false
				for k: int in brush:
					if out[k].contains(from):
						out[k] = out[k].replace(from, to)
						faces += 1
						touched = true
				if touched:
					hits += 1
			brush = []
			brush_lo = Vector3(INF, INF, INF)
			brush_hi = Vector3(-INF, -INF, -INF)
	print("   %s" % path.get_file())
	print("   %d brush(es) inside the box carried %s — %d face(s) to %s" % [
			hits, from.get_file(), faces, to.get_file()])
	if not apply:
		print("   DRY RUN — pass --apply")
		quit()
		return
	if hits == 0:
		print("   nothing to do")
		quit()
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	print("      written. Rebuild the prefab, then re-bake anything using it.")
	quit()


## The three points a Valve-220 face line starts with.
func _points(line: String) -> Array:
	var out: Array = []
	var at := 0
	for _i in 3:
		var open := line.find("(", at)
		var close := line.find(")", open)
		if open < 0 or close < 0:
			return out
		var n := line.substr(open + 1, close - open - 1).strip_edges().split(" ", false)
		if n.size() < 3:
			return out
		out.append(Vector3(float(n[0]), float(n[1]), float(n[2])))
		at = close + 1
	return out
