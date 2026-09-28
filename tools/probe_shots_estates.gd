extends SceneTree

# ─────────────────────────────────────────────
# SHOTS OF THE ESTATE BLOCKS. Each piece on a flat pad, from eye height and
# from a corner above, so its massing and its ramps both read.
#
#   RENDER_OUT=<dir> godot --path . --script res://tools/probe_shots_estates.gd
#   RENDER_OUT=<dir> PIECES=estate_slab_five,... godot --path . --script ...
#
# NOT headless: the dummy renderer returns blank images.
#
# A figure for scale would be better than a caption, but robots are not built
# in TrenchBroom here — the 1.8 m post beside each piece is the stand-in.
# ─────────────────────────────────────────────

const DIR := "res://maps/blocks/estates"
## Eye height, and how far back the low camera stands.
const EYE := 1.7


func _initialize() -> void:
	await process_frame
	var out := OS.get_environment("RENDER_OUT")
	if out == "":
		print("FAIL  set RENDER_OUT to a directory")
		quit(1)
		return
	var only := OS.get_environment("PIECES").split(",", false)
	var names: Array = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".tscn"):
			names.append(f.get_basename())
	names.sort()

	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.60, 0.58, 0.54)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.70, 0.68, 0.64)
	e.ambient_light_energy = 1.05
	e.fog_enabled = true
	e.fog_light_color = Color(0.60, 0.58, 0.54)
	e.fog_density = 0.0008
	env.environment = e
	world.add_child(env)
	# The camera stands off the -X, +Z corner of every piece, so the sun has to
	# come over that shoulder or the only face in shot is the one in shadow.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -45.0, 0.0)
	sun.light_energy = 1.45
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 140.0, 0.0)
	fill.light_energy = 0.35
	world.add_child(fill)
	var cam := Camera3D.new()
	cam.far = 900.0
	world.add_child(cam)
	cam.make_current()

	var done := 0
	for n: String in names:
		if only.size() > 0 and not only.has(n):
			continue
		var packed := load(DIR.path_join(n + ".tscn")) as PackedScene
		if packed == null:
			continue
		var piece := packed.instantiate() as Node3D
		world.add_child(piece)
		# A 1.8 m post off the front corner: the only scale reference there is.
		var scale_post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 1.8, 0.5)
		scale_post.mesh = bm
		scale_post.position = Vector3(34.0, 0.9, -20.0)
		world.add_child(scale_post)
		var aabb := _span(piece)
		var span: float = maxf(aabb.size.x, aabb.size.z)
		var mid := aabb.get_center()
		# A prefab's front faces Godot -Z (Quake -X), so the "above" corner looks
		# at its BACK — which is where the ramps and galleries are, and where the
		# broken corners are not. "front" is the other diagonal.
		for shot: String in ["street", "above", "front"]:
			match shot:
				"street":
					cam.fov = 70.0
					cam.position = Vector3(mid.x - span * 0.62, EYE, aabb.end.z + span * 0.34)
					cam.look_at(Vector3(mid.x, minf(aabb.size.y * 0.45, 9.0), mid.z), Vector3.UP)
				"above":
					cam.fov = 52.0
					cam.position = Vector3(mid.x - span * 0.85, aabb.size.y * 1.5 + 16.0,
							aabb.end.z + span * 0.85)
					cam.look_at(Vector3(mid.x, aabb.size.y * 0.3, mid.z), Vector3.UP)
				_:
					cam.fov = 52.0
					cam.position = Vector3(mid.x + span * 0.85, aabb.size.y * 1.5 + 16.0,
							aabb.position.z - span * 0.85)
					cam.look_at(Vector3(mid.x, aabb.size.y * 0.3, mid.z), Vector3.UP)
			# The first frame of a fresh run comes back blank while the
			# renderer warms up, so each shot is taken twice.
			for pass_i in 2:
				for _i in 6:
					await process_frame
				if pass_i == 1:
					root.get_texture().get_image().save_png(
							out.path_join("%s_%s.png" % [n, shot]))
		piece.queue_free()
		scale_post.queue_free()
		await process_frame
		done += 1
	print("   wrote %d piece(s), two shots each, to %s" % [done, out])
	quit()


func _span(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in node.find_children("*", "VisualInstance3D", true, false):
		var v := c as VisualInstance3D
		var box := v.get_aabb()
		var t := v.global_transform
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for i in 8:
			var w := t * box.get_endpoint(i)
			lo = Vector3(minf(lo.x, w.x), minf(lo.y, w.y), minf(lo.z, w.z))
			hi = Vector3(maxf(hi.x, w.x), maxf(hi.y, w.y), maxf(hi.z, w.z))
		var one := AABB(lo, hi - lo)
		out = one if first else out.merge(one)
		first = false
	return out
