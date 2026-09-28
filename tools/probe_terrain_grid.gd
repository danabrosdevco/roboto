extends SceneTree
# Scratch: print a height grid out of a baked TerrainData, so placements can be
# planned against the ground that is actually on disk rather than a guess.
#
#   DATA=res://maps/terrain_data/x.res REGION=-400,-150,80,250,25 \
#     godot --headless --path . --script res://tools/probe_terrain_grid.gd
#
# Also prints the water mask and the pad/road control channels, because a metre
# of height tells you nothing about whether the spot is a river or a street.


func _initialize() -> void:
	var path := OS.get_environment("DATA")
	if path == "":
		path = "res://maps/terrain_data/mutaha_level_terrain.res"
	var data: TerrainData = load(path)
	var parts := OS.get_environment("REGION").split(",")
	var x0 := -400.0
	var x1 := -150.0
	var z0 := 80.0
	var z1 := 250.0
	var step := 25.0
	if parts.size() == 5:
		x0 = float(parts[0])
		x1 = float(parts[1])
		z0 = float(parts[2])
		z1 = float(parts[3])
		step = float(parts[4])
	var n: int = data.cells_x + 1
	var half := data.cells_x * data.cell_size * 0.5
	print("%s  %d x %d @ %.1f m" % [path.get_file(), data.cells_x, data.cells_z, data.cell_size])
	var head := "   z / x "
	var xs: Array[float] = []
	var x := x0
	while x <= x1:
		xs.append(x)
		head += "%7.0f" % x
		x += step
	print(head)
	var z := z0
	while z <= z1:
		var line := "%6.0f" % z
		var flags := ""
		for xx: float in xs:
			var i := int(roundf((xx + half) / data.cell_size))
			var j := int(roundf((z + half) / data.cell_size))
			i = clampi(i, 0, data.cells_x)
			j = clampi(j, 0, data.cells_z)
			var k := j * n + i
			var h: float = data.heights[k]
			var wet: bool = not data.water.is_empty() and data.water[k] > 0
			line += "%7.1f" % h
			var c := k * TerrainData.CONTROL_STRIDE
			if wet:
				flags += "~"
			elif data.control[c + 2] > 100:
				flags += "P"      # pad: a levelled building block
			elif data.control[c] > 100:
				flags += "R"      # road or street
			else:
				flags += "."
		print("%s   %s" % [line, flags])
		z += step
	quit()
