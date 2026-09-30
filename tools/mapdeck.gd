extends SceneTree

# ─────────────────────────────────────────────
# MAP DECK — builds a concept for every map in mapdeck_data.gd: paints its
# sketch, generates the terrain, dresses it out of maps/blocks, and photographs
# it. For choosing which ideas are worth building properly, not for shipping.
#
#   RENDER_OUT=<dir> godot --path . --script res://tools/mapdeck.gd
#   RENDER_OUT=<dir> ONLY=rail_yard,port godot --path . --script res://tools/mapdeck.gd
#   RENDER_OUT=<dir> DRAFT=1 godot --path . --script res://tools/mapdeck.gd
#
# NOT headless: the dummy renderer returns blank images.
#
# WHY IT DRESSES THEM. Terrain alone cannot tell these ideas apart. The
# generator paints mountains, water, flat ground, a street grid, craters, rough
# ground and roads — and a rail yard, a container port and a refinery are all
# "flat ground with roads on it" to that list. What makes them different
# arrives as BLOCKS, so a deck of bare terrain would be fifty pictures of the
# same field and would answer nothing about whether any of it is fun.
#
# EVERY PIECE IS MEASURED, NOT REMEMBERED. Rows and grids space themselves off
# the prefab's own bounding box, read once per piece at build time. Sizing
# pieces from memory is how a placement pass puts three buildings through each
# other, and it has happened here before.
# ─────────────────────────────────────────────

const Data := preload("res://Env/terrain/terrain_data.gd")
const Recipe := preload("res://Env/terrain/terrain_recipe.gd")
const Generator := preload("res://Env/terrain/terrain_generator.gd")
const TerrainScript := preload("res://Env/terrain/generated_terrain.gd")
const DECK := preload("res://tools/mapdeck_data.gd")
var _deck: Array = DECK.maps()

## Sketch palette, as docs/TERRAIN.md defines it.
const INK := {
	"W": Color(1, 1, 1), "B": Color(0, 0, 1), "G": Color(0, 1, 0),
	"U": Color(0.502, 0.502, 0.502), "R": Color(1, 0, 0), "Y": Color(1, 1, 0),
	"M": Color(1, 0, 1), "_": Color(0, 0, 0),
}
## Metres per sketch pixel. Every map in the deck is painted at this scale, so
## a pixel means the same thing in all fifty and they can be compared.
const MPP := 8.0
## Block-out cell size. A concept does not need 2 m ground, and fifty of them
## at 2 m is an hour of erosion.
const CELL := 3.0
const DRAFT_CELL := 5.0

var _out := ""
var _draft := false
var _sizes := {}          ## piece -> its own AABB, read once
var _made: Array = []


func _initialize() -> void:
	await process_frame
	_out = OS.get_environment("RENDER_OUT")
	if _out == "":
		print("FAIL  set RENDER_OUT to a directory")
		quit(1)
		return
	_draft = OS.get_environment("DRAFT") != ""
	DirAccess.make_dir_recursive_absolute(_out)
	var only: Array = []
	if OS.get_environment("ONLY") != "":
		for n in OS.get_environment("ONLY").split(",", false):
			only.append(n.strip_edges())
	var started := Time.get_ticks_msec()
	var n := 0
	for map: Dictionary in _deck:
		if not only.is_empty() and not only.has(map.id):
			continue
		var t := Time.get_ticks_msec()
		await _build(map)
		n += 1
		print("   %-22s %5.1f s" % [map.id, (Time.get_ticks_msec() - t) / 1000.0])
	print("   %d map(s) in %.0f s, into %s" % [n, (Time.get_ticks_msec() - started) / 1000.0, _out])
	_manifest()
	quit()


func _build(map: Dictionary) -> void:
	var px: Vector2i = map.px
	var img := Image.create(px.x, px.y, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	for op: Array in map.get("paint", []):
		_paint(img, op)
	img.save_png(_out.path_join("%s_sketch.png" % map.id))

	var r := Recipe.new()
	r.layout = Recipe.Layout.OPEN
	r.border_sides = 0
	r.floor_at_zero = true
	r.cell_size = DRAFT_CELL if _draft else CELL
	r.random_seed = 7
	r.sketch = ImageTexture.create_from_image(img)
	r.sketch_metres_per_pixel = MPP
	# THE DEFAULTS ARE A FLAT MAP. Anywhere the squad fights has to be flat or
	# close to it — bots climb 0.25 m and broken ground bakes as a wall or as
	# slivers that get culled. So hills, ridges, erosion and crater depth all
	# start near nothing here and each map turns up only what it needs, which
	# is the opposite way round from the presets.
	r.floor_depth = 3.0
	r.hills_height = 2.5
	r.hills_scale = 320.0
	r.ridge_height = 0.0
	r.detail_height = 0.5
	r.terrace_strength = 0.0
	r.crater_count = 0
	r.thermal_passes = 2
	r.hydraulic_strength = 0.0
	r.smooth_passes = 2
	r.sketch_mountain_height = 34.0
	r.sketch_blend = 18.0
	r.sketch_edge_noise = 14.0
	r.rough_height = 5.0
	r.road_width = 6.0
	r.water_depth = 6.0
	r.water_bank = 22.0
	r.urban_block = Vector2(40.0, 32.0)
	r.urban_street = 9.0
	r.urban_ruin = 0.2
	r.shelling_per_hectare = 22.0
	r.crater_radius_min = 3.0
	r.crater_radius_max = 11.0
	r.crater_depth = 0.22
	for k: String in map.get("recipe", {}):
		r.set(k, map.recipe[k])

	var d: Data = Generator.generate(r, [])
	var terrain: Node3D = TerrainScript.new()
	terrain.data = d
	terrain.collision_enabled = false        # nothing here is walked
	terrain.boundary_walls = false
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(terrain)
	_light(world, map)
	var dressed := 0
	for op: Array in map.get("dress", []):
		dressed += _dress(world, d, op)
	# Ground cover, because bare terrain reads as a car park whatever is
	# standing on it, and "is this map worth building" is partly that question.
	var LayerType := load("res://Env/terrain/terrain_scatter_layer.gd")
	var layers := Array([], TYPE_OBJECT, "Resource", LayerType)
	for n: String in map.get("scatter", []):
		var layer := load("res://maps/blocks/scatter/%s.tres" % n)
		if layer != null:
			layers.append(layer)
	if not layers.is_empty():
		var scatter: Node3D = load("res://Env/terrain/terrain_scatter.gd").new()
		scatter.layers = layers
		terrain.add_child(scatter)
	for _i in 6:
		await process_frame
	await _shoot(world, d, map)
	_made.append({"id": map.id, "name": map.name, "hook": map.hook,
			"size": "%d x %d m" % [int(d.width()), int(d.depth())], "pieces": dressed})
	world.queue_free()
	await process_frame


# ── Painting ────────────────────────────────────────────────────────────────

func _paint(img: Image, op: Array) -> void:
	var c: Color = INK[op[-1]]
	match op[0]:
		"fill":
			img.fill(c)
		"rect":
			for x in range(maxi(op[1], 0), mini(op[3], img.get_width())):
				for y in range(maxi(op[2], 0), mini(op[4], img.get_height())):
					img.set_pixel(x, y, c)
		"oval":
			var cx: float = op[1]
			var cy: float = op[2]
			for x in img.get_width():
				for y in img.get_height():
					var dx := (x - cx) / maxf(float(op[3]), 0.001)
					var dy := (y - cy) / maxf(float(op[4]), 0.001)
					if dx * dx + dy * dy <= 1.0:
						img.set_pixel(x, y, c)
		"line":
			_stroke(img, [Vector2(op[1], op[2]), Vector2(op[3], op[4])], float(op[5]), c)
		"path":
			_stroke(img, op[1], float(op[2]), c)
		"poly":
			_fill_poly(img, op[1], c)


func _stroke(img: Image, pts: Array, w: float, c: Color) -> void:
	var half := maxf(w, 1.0) * 0.5
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var steps := int(maxf(a.distance_to(b) * 2.0, 1.0))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / steps)
			for x in range(int(floorf(p.x - half)), int(ceilf(p.x + half)) + 1):
				for y in range(int(floorf(p.y - half)), int(ceilf(p.y + half)) + 1):
					if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() \
							and Vector2(x, y).distance_to(p) <= half:
						img.set_pixel(x, y, c)


func _fill_poly(img: Image, pts: Array, c: Color) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(maxi(int(lo.y), 0), mini(int(hi.y) + 1, img.get_height())):
		var xs: Array = []
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var i := 0
		while i + 1 < xs.size():
			for x in range(maxi(int(xs[i]), 0), mini(int(xs[i + 1]) + 1, img.get_width())):
				img.set_pixel(x, y, c)
			i += 2


# ── Dressing ────────────────────────────────────────────────────────────────

## Placement is in METRES, with the map's middle at 0, 0 — the same frame the
## terrain uses — so a sketch pixel (px, py) is at
## ((px - w/2) * MPP, (py - h/2) * MPP).
func _dress(world: Node3D, d: Data, op: Array) -> int:
	var piece: String = op[1]
	var box := _size_of(piece)
	if box.size == Vector3.ZERO:
		return 0
	var put: Array = []
	match op[0]:
		"at":
			put.append([Vector2(op[2], op[3]), float(op[4]) if op.size() > 4 else 0.0])
		"row":
			# Spaced off the piece's OWN length along the line, plus a gap, so
			# a row of anything comes out clear of itself.
			var a := Vector2(op[2], op[3])
			var b := Vector2(op[4], op[5])
			var gap: float = float(op[6]) if op.size() > 6 else 4.0
			var yaw: float = atan2(b.x - a.x, b.y - a.y)
			var step: float = _span(box, yaw) + gap
			var n := int(a.distance_to(b) / maxf(step, 1.0)) + 1
			for i in n:
				put.append([a.lerp(b, float(i) / maxf(n - 1, 1)), rad_to_deg(yaw) + 90.0])
		"grid":
			var lo := Vector2(op[2], op[3])
			var hi := Vector2(op[4], op[5])
			var yaw: float = float(op[6]) if op.size() > 6 else 0.0
			var gap: float = float(op[7]) if op.size() > 7 else 8.0
			var sx: float = box.size.x + gap
			var sz: float = box.size.z + gap
			var nx := maxi(int((hi.x - lo.x) / sx), 1)
			var nz := maxi(int((hi.y - lo.y) / sz), 1)
			for ix in nx:
				for iz in nz:
					put.append([Vector2(lo.x + (ix + 0.5) * (hi.x - lo.x) / nx,
							lo.y + (iz + 0.5) * (hi.y - lo.y) / nz), yaw])
		"ring":
			var c := Vector2(op[2], op[3])
			var rad: float = op[4]
			var n: int = op[5]
			for i in n:
				var a := TAU * i / n
				put.append([c + Vector2(sin(a), cos(a)) * rad, rad_to_deg(a)])
	var packed := load("res://maps/blocks/%s.tscn" % piece) as PackedScene
	if packed == null:
		return 0
	var done := 0
	for entry: Array in put:
		var p: Vector2 = entry[0]
		var y := d.height_at_local(p.x, p.y)
		if is_nan(y):
			continue
		var inst := packed.instantiate() as Node3D
		world.add_child(inst)
		inst.position = Vector3(p.x, y, p.y)
		inst.rotation.y = deg_to_rad(float(entry[1]))
		done += 1
	return done


## How much room the piece takes along a heading, from its own box.
func _span(box: AABB, yaw: float) -> float:
	return absf(box.size.x * sin(yaw)) + absf(box.size.z * cos(yaw))


func _size_of(piece: String) -> AABB:
	if _sizes.has(piece):
		return _sizes[piece]
	var out := AABB()
	var packed := load("res://maps/blocks/%s.tscn" % piece) as PackedScene
	if packed == null:
		push_warning("mapdeck: no such piece %s" % piece)
		_sizes[piece] = out
		return out
	var inst := packed.instantiate() as Node3D
	var first := true
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var b := mi.transform * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	inst.free()
	_sizes[piece] = out
	return out


# ── Light and camera ────────────────────────────────────────────────────────

## THE GAME'S OWN ENVIRONMENT, not one made up here. The terrain material is
## lit and tone-mapped for that environment; under a hand-rolled sky with sky
## ambient it came back as a sheet of white paper with the map faintly printed
## on it. A deck lit differently from the game is a deck that cannot be
## compared with the game.
func _light(world: Node3D, _map: Dictionary) -> void:
	var packed := load("res://Env/world_environment.tscn") as PackedScene
	if packed == null:
		push_warning("mapdeck: no world_environment.tscn — the deck will be lit wrong")
		return
	var env := packed.instantiate()
	world.add_child(env)
	# Low and raking, so relief and the blocks both read. The scene's own sun
	# points wherever the level it was made for wanted it.
	var sun: DirectionalLight3D = env.get_node_or_null(^"Sun")
	if sun != null:
		sun.rotation_degrees = Vector3(-38.0, 132.0, 0.0)


## Two pictures each: the shape from above, and what it is like to stand in it.
## The aerial is framed off the map's own size so all fifty compare, and the
## ground camera is put at eye height on the terrain's own surface rather than
## a guessed y — on a map with relief, a guessed height is underground.
func _shoot(world: Node3D, d: Data, map: Dictionary) -> void:
	var cam := Camera3D.new()
	cam.far = 6000.0
	world.add_child(cam)
	cam.make_current()
	# FRAMED OFF THE MAP'S OWN SIZE, so a 1408 m map and a 768 m one fill the
	# picture the same and the deck can be read as a set. A fixed camera height
	# makes the small ones look empty and that is not a fact about the map.
	const FOV := 45.0
	const PITCH := 52.0
	var aspect := 16.0 / 9.0
	var need: float = maxf(d.width() / aspect, d.depth() * 1.3) * 0.62
	var dist: float = need / tan(deg_to_rad(FOV * 0.5))
	var shots: Array = [
		["plan", Vector3(0.0, dist * sin(deg_to_rad(PITCH)), dist * cos(deg_to_rad(PITCH))),
				Vector3.ZERO, FOV],
	]
	for i in (map.get("cams", []) as Array).size():
		var c: Array = map.cams[i]
		var from := Vector3(c[0], d.height_at_local(c[0], c[1]) + 1.7, c[1])
		var look := Vector3(c[2], d.height_at_local(c[2], c[3]) + 3.0, c[3])
		shots.append(["eye%d" % (i + 1), from, look, float(c[4]) if c.size() > 4 else 62.0])
	for s: Array in shots:
		cam.fov = float(s[3])
		cam.position = s[1]
		cam.look_at(s[2], Vector3.UP)
		# The first frame of a fresh camera comes back blank while the renderer
		# warms up, so every shot is taken twice and the second one kept.
		for pass_i in 2:
			for _i in 8:
				await process_frame
			if pass_i == 1:
				root.get_texture().get_image().save_png(
						_out.path_join("%s_%s.png" % [map.id, s[0]]))


func _manifest() -> void:
	var lines := PackedStringArray(["# Map deck", ""])
	for m: Dictionary in _made:
		lines.append("## %s — %s" % [m.id, m.name])
		lines.append("%s  ·  %s  ·  %d piece(s)" % [m.hook, m.size, m.pieces])
		lines.append("")
	var f := FileAccess.open(_out.path_join("DECK.md"), FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
