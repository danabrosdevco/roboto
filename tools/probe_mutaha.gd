extends SceneTree
# Scratch: read mutaha's sketch and its baked terrain WITHOUT touching either.
# Prints the painted class map, a height/flatness map, the water mask and the
# generator's bridge list, so a layout change can be planned off the files on
# disk rather than off a builder's idea of them.

var sketch_path := "D:/Godot Games/roboto/Env/terrain/sketches/%s.png" % [OS.get_environment("SK") if OS.get_environment("SK") != "" else "mutaha"]
var data_path := "res://maps/terrain_data/%s.res" % [OS.get_environment("TD") if OS.get_environment("TD") != "" else "mutaha_level_terrain"]
const MPP := 8.0


func _initialize() -> void:
	var im := Image.load_from_file(sketch_path)
	print("sketch %d x %d  -> %.0f x %.0f m" % [im.get_width(), im.get_height(),
			im.get_width() * MPP, im.get_height() * MPP])
	# Legend: M mountain, ~ water, F flat, # urban, r shelled, y rough, = road.
	var counts := {}
	var rows: Array[String] = []
	for y in im.get_height():
		var line := ""
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			var k := _klass(c)
			line += k
			counts[k] = int(counts.get(k, 0)) + 1
		rows.append(line)
	print("counts: ", counts)
	print("     x -512 .. +512, one char = 8 m; row 0 is north (-512 z)")
	for y in rows.size():
		print("%4d %s" % [int(-512.0 + y * MPP), rows[y]])

	var data: TerrainData = load(data_path)
	print("\nterrain %d x %d cells @ %.1f m, height %.1f .. %.1f, water_level %.2f, %d lots, %d bridges" % [
			data.cells_x, data.cells_z, data.cell_size, data.min_height, data.max_height,
			data.water_level, data.lots.size(), data.bridges.size()])
	for b in data.bridges:
		print("   bridge  start %s  end %s  width %.1f" % [b.start, b.end, b.width])

	# Flatness: over each 32 x 32 m tile, the spread of heights.
	print("\nrelief per 32 m tile, one char per tile: . under 0.5 m  - 1 m  + 2 m  ^ 4 m  # more; ~ = water")
	var n: int = data.cells_x + 1
	var tile := int(32.0 / data.cell_size)
	var head := "     "
	for tx in range(0, data.cells_x / tile):
		head += "|" if tx % 4 == 0 else " "
	print(head)
	for tz in range(0, data.cells_z / tile):
		var line := ""
		for tx in range(0, data.cells_x / tile):
			var lo := INF
			var hi := -INF
			var wet := 0
			for j in range(tz * tile, (tz + 1) * tile + 1):
				for i in range(tx * tile, (tx + 1) * tile + 1):
					var h: float = data.heights[j * n + i]
					lo = minf(lo, h)
					hi = maxf(hi, h)
					if not data.water.is_empty() and data.water[j * n + i] > 0:
						wet += 1
			var span := hi - lo
			if wet > tile * tile / 3:
				line += "~"
			elif span < 0.5:
				line += "."
			elif span < 1.0:
				line += "-"
			elif span < 2.0:
				line += "+"
			elif span < 4.0:
				line += "^"
			else:
				line += "#"
		print("%5d%s" % [int(-512.0 + tz * 32.0), line])
	quit()


func _klass(c: Color) -> String:
	var r := c.r
	var g := c.g
	var b := c.b
	if c.a < 0.5:
		return " "
	if r > 0.7 and g > 0.7 and b > 0.7:
		return "M"
	if b > 0.6 and r < 0.4 and g < 0.4:
		return "~"
	if g > 0.6 and r < 0.4 and b < 0.4:
		return "F"
	if r > 0.6 and b > 0.6 and g < 0.4:
		return "="
	if r > 0.6 and g > 0.6 and b < 0.4:
		return "y"
	if r > 0.6 and g < 0.4 and b < 0.4:
		return "r"
	if absf(r - g) < 0.2 and absf(g - b) < 0.2 and r > 0.25:
		return "#"
	return " "
