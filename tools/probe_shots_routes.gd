extends "res://tools/probe_legibility.gd"

# ─────────────────────────────────────────────
# WHAT THE PLAYER SEES GOING UP EACH ROUTE — through the game's own filter, at
# the player's own eye height, from stations derived from the route itself.
#
#   RENDER_OUT="D:/Godot Games/roboto_shots/salient_routes" \
#       godot --path . --script res://tools/probe_shots_routes.gd
#   RENDER_OUT=... ONLY=CommTrench ...
#   RENDER_OUT=... EYE=2.75 ...        # a Walker's head, for the comparison
#   RENDER_OUT=... STATIONS=6 ...
#
# NOT headless. The filter is a shader that READS THE SCREEN, so with no screen
# it filters nothing and the picture is not a picture of this game.
#
# WHY A SEPARATE SHOT PROBE. tools/probe_shots_salient.gd takes ten survey
# views of this map from TYPED coordinates at EYE 1.65, and
# tools/probe_shots_filtered.gd puts the HUD filter over a scene. Neither
# answers "what is it like to go up route C", because the answer has to come
# from where route C actually is — and the routes move whenever the generator
# refits them, which it did twice during this pass. So every camera here is
# derived: it stands on a laid piece of the route and looks at a later piece of
# the same route. Move the route and the shots follow it.
#
# THE EYE IS 1.50 m AND THAT IS NOT A STYLE CHOICE. Measured off
# Character/characters/player/test_character.tscn: a capsule 1.70 m tall centred
# on the node, camera at +0.65, so the eye is 1.50 above the feet. The 1.65 in
# probe_legibility.gd and probe_shots_salient.gd is 15 cm too high, which does
# not matter for a survey view of a hillside and matters a great deal in a
# trench whose parapet is 1.39 to 2.00 m above the floor: 15 cm is the
# difference between seeing the far wall and seeing over it. The height comes
# from probe_trench_lib.gd's PLAYER_EYE so there is one copy of it.
#
# It inherits probe_legibility.gd for the filter extraction, the project's real
# FOV and the ground sampler — all three are load-bearing and none of them
# should exist twice. Nothing of its measuring is used; _initialize is replaced.
# ─────────────────────────────────────────────

const LIB := preload("res://tools/probe_trench_lib.gd")

## How many stations along each route, including both ends.
const STATIONS := 4

## How far ahead along the route the camera looks, in pieces. Two pieces is
## 30-60 m on this kit: far enough to be a view down the trench rather than a
## photograph of the next wall.
const LOOK_AHEAD := 2


func _initialize() -> void:
	await process_frame
	var out := OS.get_environment("RENDER_OUT")
	if out == "":
		print("FAIL  set RENDER_OUT to a directory")
		quit(1)
		return
	if not DirAccess.dir_exists_absolute(out):
		var err := DirAccess.make_dir_recursive_absolute(out)
		if err != OK:
			print("FAIL  could not make %s (%s)" % [out, error_string(err)])
			quit(1)
			return
	var eye := float(OS.get_environment("EYE")) if OS.get_environment("EYE") != "" else LIB.PLAYER_EYE
	var stations := int(OS.get_environment("STATIONS")) if OS.get_environment("STATIONS") != "" else STATIONS
	var only := OS.get_environment("ONLY")
	var mat := _hud_filter()
	if mat == null:
		print("FAIL  no %s material in %s — has the HUD been rearranged?" % [FILTER_NODE, HUD_SCENE])
		quit(1)
		return
	var fov := _fov()
	print("   filter %s   fov %.0f   eye %.2f m%s" % [
			mat.shader.resource_path.get_file(), fov, eye,
			"  (the player's measured eye)" if is_equal_approx(eye, LIB.PLAYER_EYE) else ""])

	var packed := load("res://maps/salient_level.tscn") as PackedScene
	if packed == null:
		print("FAIL  maps/salient_level.tscn will not load")
		quit(1)
		return
	var level := packed.instantiate() as Node3D
	root.add_child(level)
	# The filter goes in the ROOT viewport, over the world, which is where
	# hud.tscn puts it: a SubViewport is a different render target and a
	# screen-reading shader is the one kind that can tell.
	var layer := CanvasLayer.new()
	layer.layer = 100
	var rect := ColorRect.new()
	rect.material = mat
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	root.add_child(layer)
	for _i in 60:
		await physics_frame
	var space := level.get_world_3d().direct_space_state
	var cam := Camera3D.new()
	cam.far = 3000.0
	cam.fov = fov
	level.add_child(cam)
	cam.make_current()

	var routes := _routes(level)
	if routes.is_empty():
		print("FAIL  no Trenchworks route groups — there are no routes to shoot,")
		print("      which is a missing art scene and not an empty map.")
		quit(1)
		return
	var done := 0
	var keys: Array = routes.keys()
	keys.sort()
	for key: String in keys:
		if only != "" and not key.containsn(only):
			continue
		var pieces: Array = routes[key]
		if pieces.size() < 2:
			print("   %s has %d piece(s) — too few to look along" % [key, pieces.size()])
			continue
		for s in stations:
			var i := int(roundf(float(s) * float(pieces.size() - 1) / float(maxi(stations - 1, 1))))
			var at: Vector3 = (pieces[i] as Array)[1]
			var j := mini(i + LOOK_AHEAD, pieces.size() - 1)
			if j == i:
				j = maxi(i - LOOK_AHEAD, 0)
			if j == i:
				continue
			var look: Vector3 = (pieces[j] as Array)[1]
			var g: float = LIB.ground(space, at.x, at.z)
			var gl: float = LIB.ground(space, look.x, look.z)
			if is_nan(g) or is_nan(gl):
				# EVERY SKIP SAYS WHY. No collision under a laid piece is a
				# floating piece, which is probe_footing.gd's business, and a
				# camera placed at a guessed height would hide it.
				print("   %s station %d: no collision under the piece at (%.0f, %.0f) — NOT SHOT" % [
						key, s, at.x, at.z])
				continue
			# Looking slightly DOWN the trench and not at the sky: the target is
			# the next piece's floor at the same eye height, so the horizon sits
			# where a player walking it would have it.
			cam.position = Vector3(at.x, g + eye, at.z)
			cam.look_at(Vector3(look.x, gl + eye, look.z), Vector3.UP)
			# Two passes: the first frame off a fresh camera comes back blank
			# while the renderer warms up, and a blank screen filters to a blank
			# picture.
			var img: Image = null
			for pass_i in 2:
				for _k in 12:
					await process_frame
				if pass_i == 1:
					img = root.get_texture().get_image()
			var tag := "salient_%s_%d_%s" % [key, s, (pieces[i] as Array)[0]]
			img.save_png(out.path_join("%s.png" % tag))
			print("   %-46s at %6.0f, %6.0f  floor %5.2f  -> %s" % [
					tag, at.x, at.z, g, (pieces[j] as Array)[0]])
			done += 1
	print("ROUTE SHOTS %s — wrote %d view(s) to %s" % ["PASS" if done > 0 else "FAIL", done, out])
	quit(0 if done > 0 else 1)


## The laid pieces of each route, in laid order. Anchors are markers and
## Landmarks are a tank and a tower; neither is a route.
func _routes(level: Node3D) -> Dictionary:
	var out := {}
	var works: Node = null
	for n in level.find_children("Trenchworks", "Node3D", true, false):
		works = n
		break
	if works == null:
		return out
	for group in works.get_children():
		if str(group.name) in ["Anchors", "Landmarks"]:
			continue
		var list: Array = []
		for piece in group.get_children():
			if piece is Node3D:
				list.append([str(piece.name), (piece as Node3D).global_position])
		list.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
		if list.size() > 0:
			out[str(group.name)] = list
	return out
