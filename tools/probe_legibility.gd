extends SceneTree

# ─────────────────────────────────────────────
# PROBE LEGIBILITY — why you cannot read distance, measured rather than
# described.
#
#   RENDER_OUT="D:/Godot Games/roboto_shots/legibility" \
#       godot --path . --script res://tools/probe_legibility.gd
#   RENDER_OUT=... ONLY=salient godot --path . --script res://tools/probe_legibility.gd
#   RENDER_OUT=... ENV=proposal godot --path . --script res://tools/probe_legibility.gd
#   RENDER_OUT=... MOCKUP=both godot --path . --script res://tools/probe_legibility.gd
#   TALL=1 godot --path . --script res://tools/probe_legibility.gd   (inventory only)
#   KIT=1  godot --path . --script res://tools/probe_legibility.gd   (piece heights)
#
# NOT headless. The dummy renderer returns a blank image, and the signal filter
# is a shader that READS THE SCREEN — with no screen there is nothing to read,
# so a headless run of this reports a perfectly flat picture of nothing and
# looks like proof.
#
# WHY THE NUMBERS AND THE PICTURE COME OUT OF ONE TOOL. The question is not
# "how bright is the frame" and not "how far away is that" — it is whether
# brightness tracks distance, which is the cue the eye ranges with. That is a
# correlation between two things, so both have to be sampled at THE SAME
# PIXELS. A grid of rays is cast through the camera, each one recording the
# distance to what it hit; the frame is then rendered, the same grid of pixels
# is read back out of it, and luma is averaged per distance band. A separate
# depth probe and a separate screenshot cannot answer this at all.
#
# THE FRAME IS SHOT THROUGH THE GAME'S OWN FILTER, read out of
# Character/hud/hud.tscn the way tools/probe_shots_filtered.gd does it — scene
# values beat shader defaults, and the shader's declared defaults are not what
# ships. A render without the filter is not a picture of this game: the filter
# quantises luma to ten steps, so a smooth 4% haze gradient and no haze at all
# come out as the same flat band, which is the whole reason "just add fog"
# is not the answer here.
# ─────────────────────────────────────────────

const WIDTH := 1152
const HEIGHT := 648
const HUD_SCENE := "res://Character/hud/hud.tscn"
const FILTER_NODE := "SignalFilter"

## Height above whatever is under the camera, for "eye" views.
const EYE := 1.65

## The ray grid. 128 x 72 keeps the 16:9 shape. It was 64 x 36 and that was
## too coarse to see the thing being proposed: a 9.5 m pole half a kilometre
## of frontage away is under a third of a degree wide, and a 64-wide grid
## samples every 1.6 degrees, so it walked straight past most of them and
## reported that adding a hundred poles had changed nothing.
const GRID_X := 128
const GRID_Y := 72

## Distance bands, in metres. The bins are the ranges this game is played at:
## a squad order goes out to about 200 m and the map is a kilometre across.
const BANDS: Array = [0.0, 25.0, 50.0, 100.0, 200.0, 400.0, 800.0, 1.0e9]

## The real FOV. project.godot's display.fov, not a guess — see _fov().
const FOV_FALLBACK := 70.0

# level, name, from, look at, mode. FOV comes from the project setting, because
# the complaint is about the game and not about a nicely framed picture.
#   "abs" — both vectors are world positions.
#   "eye" — Y is a height ABOVE THE COLLISION under that point. A trench is a
#           cut, so a fixed Y is either buried or floating.
const VIEWS: Array = [
	# ── SALIENT: the three ways across, looked down from where you start.
	["salient", "S1_jumpoff_east", Vector3(-170.0, EYE, 0.0), Vector3(60.0, 2.0, 0.0), "eye"],
	["salient", "S2_over_the_parapet", Vector3(-150.0, EYE, 40.0), Vector3(60.0, 2.0, 34.0), "eye"],
	["salient", "S3_no_mans_land", Vector3(-95.0, EYE, 105.0), Vector3(60.0, 2.0, 55.0), "eye"],
	["salient", "S4_the_crater_lip", Vector3(-60.0, EYE, 46.0), Vector3(70.0, 2.0, -10.0), "eye"],
	["salient", "S5_front_line_east", Vector3(60.0, EYE, 34.0), Vector3(330.0, 2.0, 0.0), "eye"],
	["salient", "S6_down_the_trench", Vector3(-170.0, EYE, -60.0), Vector3(-170.0, 1.2, 120.0), "eye"],
	["salient", "S7_the_long_axis", Vector3(-410.0, EYE, 0.0), Vector3(430.0, 2.0, 0.0), "eye"],
	# ── THE COMPARATORS. The human says other games read better; these two
	# read better inside this project, through the same filter, so the
	# difference is the level and not the renderer.
	["hillfort", "H1_the_trailhead", Vector3(0.0, 2.6, 442.0), Vector3(20.0, 112.0, -270.0), "abs"],
	["hillfort", "H2_the_gate", Vector3(-196.0, 64.0, 146.0), Vector3(60.0, 96.0, -80.0), "abs"],
	["georgetown", "G1_the_towpath", Vector3(-100.0, 1.7, -7.0), Vector3(140.0, 1.0, -7.0), "abs"],
	["georgetown", "G2_the_stack", Vector3(30.0, -2.3, 60.0), Vector3(86.0, 20.0, 186.0), "abs"],
]

## MOCKUP=1. The proposal's geometry, dropped into the loaded level IN MEMORY
## so the argument comes with a picture of itself. Nothing is written back —
## maps/salient_art.tscn belongs to the builder and to another agent today.
##
## EVERY LINE RUNS ALONG THE AXIS OF ADVANCE, not across it. That inversion is
## the whole proposal: the map's existing dressing is rows at a constant x,
## which puts every copy of a repeated object at THE SAME DISTANCE from an
## attacker, so the repetition says nothing about range. The same objects on
## the same spacing turned through ninety degrees become a ruler.
##   kit path, z, x from, x to, spacing, yaw
## FIVE LINES, 90 m APART ACROSS THE FRONTAGE, because one is not enough. The
## first version of this ran two lines at z -46 and z +118, and from the
## jump-off they were either behind the camera or 57 degrees off axis: a ruler
## you cannot see down is not a ruler. The map is 430 m of frontage and the
## squad attacks on all of it, so every z has to have a line running away from
## it. 90 m spacing puts one within 45 m of wherever you stand.
## MOCKUP=poles, MOCKUP=track, MOCKUP=both.
##   kit path, x from, z from, x to, z to, spacing, yaw — the same shape as the
##   deck's own `row` dressing entry, so a line that works here transcribes
##   into tools/mapdeck_data.gd without being re-derived.
const MOCKUP_SETS: Dictionary = {
	# THE RANGING LADDER. A 9.5 m pole every 40 m, five lines 90 m apart, so
	# whatever part of a 430 m frontage you are on, one line is within 45 m and
	# runs away from you to the vanishing point.
	"poles": [
		["props/prop_power_pole", -400.0, -180.0, 400.0, -180.0, 40.0, 90.0],
		["props/prop_power_pole", -400.0, -90.0, 400.0, -90.0, 40.0, 90.0],
		["props/prop_power_pole", -400.0, 0.0, 400.0, 0.0, 40.0, 90.0],
		["props/prop_power_pole", -400.0, 90.0, 400.0, 90.0, 40.0, 90.0],
		["props/prop_power_pole", -400.0, 180.0, 400.0, 180.0, 40.0, 90.0],
	],
	# THE CONVERGING LINE. ground_track is ALREADY on this map in four rows,
	# and all four of them are in the rear areas: x -520..-190 behind our line
	# and x 210..500 behind theirs. They stop exactly where the player is
	# looking. These three join the two halves up across no-man's-land.
	"track": [
		["ground/ground_track", -190.0, 120.0, 210.0, 100.0, 4.0, 90.0],
		["ground/ground_track", -190.0, -100.0, 210.0, -120.0, 4.0, 90.0],
		["ground/ground_track", -190.0, 14.0, 210.0, 26.0, 4.0, 90.0],
	],
}
## Single pieces, added with every set. kit path, x, z, yaw
const MOCKUP_MARKS: Array = [
	["industrial/industrial_water_tower", -120.0, 86.0, 0.0],
	["industrial/industrial_water_tower", 150.0, -96.0, 0.0],
	["trench/op_tower_ruin", -34.0, -88.0, 0.0],
	["trench/op_tower_ruin", 124.0, 70.0, 180.0],
]


func _initialize() -> void:
	await process_frame
	if OS.get_environment("KIT") != "":
		_kit_heights()
		quit()
		return
	if OS.get_environment("TALL") != "":
		await _inventory()
		quit()
		return
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
	var only := OS.get_environment("ONLY")
	# ENV=proposal applies the proposal's environment numbers IN MEMORY before
	# rendering. Nothing is written back — the point is a before/after pair of
	# pictures of the same cameras, which is the only honest way to argue for
	# an environment change in a game that posterises its own output.
	var variant := OS.get_environment("ENV")
	var mat := _hud_filter()
	if mat == null:
		print("FAIL  no %s material in %s — has the HUD been rearranged?" % [FILTER_NODE, HUD_SCENE])
		quit(1)
		return
	var fov := _fov()
	print("   filter %s   fov %.0f   grid %dx%d   env %s" % [
			mat.shader.resource_path.get_file(), fov, GRID_X, GRID_Y,
			variant if variant != "" else "as-authored"])

	var order: Array = []
	for v: Array in VIEWS:
		if not order.has(v[0]):
			order.append(v[0])
	var done := 0
	for level_name: String in order:
		var wanted: Array = []
		for v: Array in VIEWS:
			if v[0] == level_name and (only == "" or only in level_name or only in String(v[1])):
				wanted.append(v)
		if wanted.is_empty():
			continue
		var packed := load("res://maps/%s_level.tscn" % level_name) as PackedScene
		if packed == null:
			print("FAIL  maps/%s_level.tscn will not load" % level_name)
			quit(1)
			return
		var level := packed.instantiate() as Node3D
		root.add_child(level)
		if variant != "":
			_apply_variant(level, variant)
		# The filter goes in the ROOT viewport, over the world, which is where
		# hud.tscn puts it. A SubViewport is a different render target and a
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
		var seen := root.get_visible_rect().size
		if int(seen.y) != HEIGHT:
			push_warning("probe_legibility: viewport is %dx%d, not %dx%d — the signal grid will not match the game's" % [
					int(seen.x), int(seen.y), WIDTH, HEIGHT])
		for _i in 60:
			await physics_frame
		var space := level.get_world_3d().direct_space_state
		# After the physics settle, because every mocked-up piece is dropped
		# onto the collision rather than placed at a guessed height — the same
		# reason the cameras are.
		var mock := OS.get_environment("MOCKUP")
		if mock != "" and level_name == "salient":
			_mockup(level, space, mock)
			for _i in 10:
				await physics_frame
		var cam := Camera3D.new()
		cam.far = 4000.0
		cam.fov = fov
		level.add_child(cam)
		cam.make_current()

		for v: Array in wanted:
			var from: Vector3 = v[2]
			var at: Vector3 = v[3]
			if v[4] == "eye":
				from.y += _ground(space, from.x, from.z)
				at.y += _ground(space, at.x, at.z)
			cam.position = from
			cam.look_at(at, Vector3.UP)
			# Two passes: the first frame off a fresh camera comes back blank
			# while the renderer warms up, and a blank screen filters to a
			# blank picture, so the filter needs the warm one too.
			var img: Image = null
			for pass_i in 2:
				for _i in 12:
					await process_frame
				if pass_i == 1:
					img = root.get_texture().get_image()
			var tag := "%s_%s%s" % [level_name, v[1], "_" + variant if variant != "" else ""]
			img.save_png(out.path_join("%s.png" % tag))
			_report(tag, _sample(cam, space, img))
			done += 1
		root.remove_child(level)
		level.queue_free()
		root.remove_child(layer)
		layer.queue_free()
		await process_frame
	print("   wrote %d view(s) to %s" % [done, out])
	quit()


# ── THE MEASUREMENT ─────────────────────────────────────────────────────────

## One ray and one pixel per grid point. Returns per-band luma and coverage,
## plus how much of the ten-step luma ladder the frame actually uses.
func _sample(cam: Camera3D, space: PhysicsDirectSpaceState3D, img: Image) -> Dictionary:
	var size := Vector2(img.get_width(), img.get_height())
	var bands := BANDS.size() - 1
	var sum := PackedFloat32Array()
	var count := PackedInt32Array()
	sum.resize(bands)
	count.resize(bands)
	var sky := 0
	var sky_luma := 0.0
	var steps := {}
	var skyline_up := 0            # grid points whose hit is ABOVE the eye plane
	# THE NUMBER THIS PROBE EXISTS FOR, in the end. Ground running away from a
	# 1.65 m eye compresses the whole 25-200 m range into about three degrees
	# just under the horizon, so the only way a frame can carry screen area at
	# ranging distance is if something is STANDING UP out there. This counts
	# exactly that: hits between 25 and 200 m whose surface is above the eye.
	#
	# The band stops at 200 m ON PURPOSE. It was 25-400 m first and the number
	# came back at 11% on the very frame the human is complaining about, which
	# is nonsense — what it was counting was the distant valley wall, which is
	# above the eye, is 400 m away, and is exactly the far mass you cannot
	# range against. 200 m is where a squad order goes.
	var standing := 0
	var near_far := []             # per-column nearest and farthest hit
	for ix in GRID_X:
		near_far.append([1.0e9, 0.0])
	for iy in GRID_Y:
		for ix in GRID_X:
			var sp := Vector2(
					(float(ix) + 0.5) / float(GRID_X) * size.x,
					(float(iy) + 0.5) / float(GRID_Y) * size.y)
			var l := _luma(img.get_pixel(int(sp.x), int(sp.y)))
			steps[roundi(l * 9.0)] = true
			var q := PhysicsRayQueryParameters3D.create(
					cam.project_ray_origin(sp),
					cam.project_ray_origin(sp) + cam.project_ray_normal(sp) * cam.far)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				# No geometry under this pixel: it is sky, and sky is the one
				# part of the frame that carries no distance at all.
				sky += 1
				sky_luma += l
				continue
			var d := cam.position.distance_to(hit["position"] as Vector3)
			if (hit["position"] as Vector3).y > cam.position.y + 0.5:
				skyline_up += 1
				if d >= 25.0 and d < 200.0:
					standing += 1
			var col: Array = near_far[ix]
			col[0] = minf(col[0], d)
			col[1] = maxf(col[1], d)
			for b in bands:
				if d >= float(BANDS[b]) and d < float(BANDS[b + 1]):
					sum[b] += l
					count[b] += 1
					break
	# HOW FAR YOU CAN SEE, per column of the frame, is the farthest thing the
	# column hits — the ground running away from you. The median of that across
	# the frame is the honest "sightline", not the single centre ray, which can
	# land on one sandbag and report 12 m down a 400 m view.
	var far_list := PackedFloat32Array()
	for col: Array in near_far:
		if col[1] > 0.0:
			far_list.append(float(col[1]))
	far_list.sort()
	return {
		"sum": sum, "count": count, "bands": bands,
		"sky": sky, "sky_luma": (sky_luma / float(sky)) if sky > 0 else 0.0,
		"steps": steps.size(), "skyline_up": skyline_up, "standing": standing,
		"reach": far_list[far_list.size() / 2] if far_list.size() > 0 else 0.0,
		"reach_max": far_list[far_list.size() - 1] if far_list.size() > 0 else 0.0,
		"total": GRID_X * GRID_Y,
	}


## Prints the one table this whole probe exists to produce: mean luma against
## distance. If the numbers down that column are the same, the frame carries no
## ranging information and no amount of detail will put any in.
func _report(tag: String, m: Dictionary) -> void:
	print("")
	print("── %s" % tag)
	print("   sightline  median %.0f m   max %.0f m" % [m["reach"], m["reach_max"]])
	print("   sky %.0f%% of frame at luma %.3f   above-eye hits %.0f%%   luma steps used %d/10" % [
			100.0 * float(m["sky"]) / float(m["total"]), m["sky_luma"],
			100.0 * float(m["skyline_up"]) / float(m["total"]), m["steps"]])
	print("   STANDING AT RANGE (above eye, 25-200 m)  %.2f%% of frame" % [
			100.0 * float(m["standing"]) / float(m["total"])])
	var lo := 1.0
	var hi := 0.0
	var seen := 0
	for b in int(m["bands"]):
		var n: int = (m["count"] as PackedInt32Array)[b]
		if n == 0:
			continue
		var mean := (m["sum"] as PackedFloat32Array)[b] / float(n)
		seen += 1
		lo = minf(lo, mean)
		hi = maxf(hi, mean)
		print("   %4.0f-%-4s m  %5.1f%% of frame   mean luma %.3f   step %d" % [
				float(BANDS[b]),
				"inf" if b == int(m["bands"]) - 1 else "%.0f" % float(BANDS[b + 1]),
				100.0 * float(n) / float(m["total"]), mean, roundi(mean * 9.0)])
	if seen < 2:
		print("   NO SPREAD TO MEASURE — one distance band holds the whole frame")
		return
	print("   LUMA SPREAD NEAR TO FAR  %.3f  (%.1f of 10 filter steps)" % [
			hi - lo, (hi - lo) * 9.0])


# ── THE INVENTORY ───────────────────────────────────────────────────────────

## What is tall enough to range against, and from how far it is visible. Run
## with TALL=1. No rendering, so this one is happy headless.
func _inventory() -> void:
	for level_name: String in ["salient", "hillfort", "georgetown"]:
		var packed := load("res://maps/%s_level.tscn" % level_name) as PackedScene
		if packed == null:
			push_warning("probe_legibility: maps/%s_level.tscn will not load" % level_name)
			continue
		var level := packed.instantiate() as Node3D
		root.add_child(level)
		for _i in 30:
			await physics_frame
		# One AABB per PLACED PIECE, not per mesh. A trench run is a dozen
		# MeshInstances and reporting each of them separately buries the one
		# tower that matters under four hundred duckboards.
		var pieces: Array = []
		var total := 0
		for child in _art_children(level):
			var box := _bounds(child)
			if box.size == Vector3.ZERO:
				continue
			total += 1
			pieces.append([box.position.y + box.size.y, box.size.y,
					box.get_center().x, box.get_center().z, child.name])
		pieces.sort_custom(func(a, b): return a[0] > b[0])
		print("")
		print("── %s   %d placed piece(s)" % [level_name, total])
		var tall := 0
		for p: Array in pieces:
			if float(p[1]) >= 8.0:
				tall += 1
		print("   pieces 8 m or taller: %d of %d (%.1f%%)" % [
				tall, total, 100.0 * float(tall) / maxf(float(total), 1.0)])
		print("   the ten tallest:")
		for i in mini(10, pieces.size()):
			var p: Array = pieces[i]
			# The range at which a thing of that height still subtends one
			# degree, which is roughly where a silhouette stops being a shape
			# and becomes a smudge — and at 648p through an 8 px macroblock
			# grid, roughly where it stops being anything at all.
			print("      %-34s  top %6.1f m  h %5.1f m  at %7.0f, %-7.0f  1 deg at %.0f m" % [
					p[4], p[0], p[1], p[2], p[3], float(p[1]) / deg_to_rad(1.0)])
		root.remove_child(level)
		level.queue_free()
		await process_frame


## The placed pieces of a level's art: the children of the art scene's own
## groups, one level down, which is where the builders put each instance.
func _art_children(level: Node) -> Array:
	var out: Array = []
	var art: Node = null
	for n in level.find_children("*", "Node3D", true, false):
		if n.name.ends_with("Art"):
			art = n
			break
	if art == null:
		push_warning("probe_legibility: no *Art node under %s — nothing to inventory" % level.name)
		return out
	for group in art.get_children():
		if group.get_child_count() == 0:
			out.append(group)
			continue
		for piece in group.get_children():
			out.append(piece)
	return out


## The world AABB of everything drawn under a node.
func _bounds(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for vi in n.find_children("*", "VisualInstance3D", true, false):
		var v := vi as VisualInstance3D
		if not v.visible:
			continue
		var b := v.global_transform * v.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	if n is VisualInstance3D and (n as VisualInstance3D).visible:
		var b2 := (n as VisualInstance3D).global_transform * (n as VisualInstance3D).get_aabb()
		box = b2 if first else box.merge(b2)
	return box


## KIT=1. The measured height of every piece the proposal names, and the range
## at which that height stops subtending one degree. Quoted heights in a design
## document go stale the first time a block is rebuilt; these are read off the
## scene.
func _kit_heights() -> void:
	var want: Array = []
	for key: String in MOCKUP_SETS:
		for line: Array in MOCKUP_SETS[key]:
			if not want.has(line[0]):
				want.append(line[0])
	for mark: Array in MOCKUP_MARKS:
		if not want.has(mark[0]):
			want.append(mark[0])
	for extra: String in ["features/feature_watchtower", "fortifications/fort_floodlight_mast",
			"props/prop_lamp_post", "landmarks/landmark_clock_tower",
			"props/prop_robot_wreck", "props/prop_tank_trap"]:
		if not want.has(extra):
			want.append(extra)
	print("   piece                                height   1 deg at   0.5 deg at")
	for kit: String in want:
		var packed := load("res://maps/blocks/%s.tscn" % kit) as PackedScene
		if packed == null:
			push_warning("probe_legibility: no kit piece res://maps/blocks/%s.tscn" % kit)
			continue
		var inst := packed.instantiate() as Node3D
		root.add_child(inst)
		var h := _bounds(inst).size.y
		print("   %-36s %6.2f m  %6.0f m   %6.0f m" % [
				kit, h, h / deg_to_rad(1.0), h / deg_to_rad(0.5)])
		root.remove_child(inst)
		inst.queue_free()


# ── THE PROPOSAL'S GEOMETRY, APPLIED IN MEMORY ─────────────────────────────

## MOCKUP=1. Lays MOCKUP_LINES and MOCKUP_MARKS into the loaded level. Pieces
## are dropped onto the collision under them: the ground here is shelled and
## a piece placed at y = 0 is either buried in a crater lip or standing in air
## over a shell hole, and both look like the proposal is wrong when it is the
## placement that is.
func _mockup(level: Node, space: PhysicsDirectSpaceState3D, which: String) -> void:
	var sets: Array = []
	for key: String in MOCKUP_SETS:
		if which == "both" or which == "1" or which == key:
			sets.append(key)
	if sets.is_empty():
		push_warning("probe_legibility: MOCKUP=%s names no set — nothing added" % which)
		return
	var host := Node3D.new()
	host.name = "LegibilityMockup"
	level.add_child(host)
	var n := 0
	for key: String in sets:
		for line: Array in MOCKUP_SETS[key]:
			var a := Vector2(float(line[1]), float(line[2]))
			var b := Vector2(float(line[3]), float(line[4]))
			var step := float(line[5])
			var count := int(a.distance_to(b) / step)
			for i in count + 1:
				var p := a.lerp(b, float(i) / float(maxi(count, 1)))
				if _place(host, space, String(line[0]), p.x, p.y, float(line[6])):
					n += 1
	for mark: Array in MOCKUP_MARKS:
		if _place(host, space, String(mark[0]), float(mark[1]), float(mark[2]), float(mark[3])):
			n += 1
	print("   MOCKUP %s: %d piece(s) added in memory — nothing written" % [
			", ".join(sets), n])


func _place(host: Node3D, space: PhysicsDirectSpaceState3D, kit: String,
		x: float, z: float, yaw: float) -> bool:
	var packed := load("res://maps/blocks/%s.tscn" % kit) as PackedScene
	if packed == null:
		push_warning("probe_legibility: no kit piece res://maps/blocks/%s.tscn — skipped" % kit)
		return false
	var inst := packed.instantiate() as Node3D
	host.add_child(inst)
	inst.position = Vector3(x, _ground(space, x, z), z)
	inst.rotation.y = deg_to_rad(yaw)
	return true


# ── THE PROPOSAL'S NUMBERS, APPLIED IN MEMORY ───────────────────────────────

## ENV=proposal. The environment half of docs/briefs/SALIENT_LEGIBILITY.md,
## so the argument comes with a picture of itself. Nothing is saved.
func _apply_variant(level: Node, variant: String) -> void:
	var we: WorldEnvironment = null
	for n in level.find_children("*", "WorldEnvironment", true, false):
		we = n as WorldEnvironment
		break
	if we == null or we.environment == null:
		push_warning("probe_legibility: %s has no WorldEnvironment — ENV=%s did nothing" % [level.name, variant])
		return
	# Duplicated: the Environment is a shared resource and writing through it
	# would hand the next level in the loop this one's sky.
	var env: Environment = we.environment.duplicate()
	match variant:
		"proposal":
			# FILMIC, AND THE SKY BACK TO 1x. Linear tonemapping with a 2x sky
			# multiplier clips the top of the range, which is where every far
			# surface sits — so near and far land in the same filter step.
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			env.background_energy_multiplier = 1.0
			env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			env.ambient_light_energy = 0.8
			# The height layer goes to the surface it is meant to be lying on.
			env.fog_density = 0.0022
			env.fog_height = 4.0
			env.fog_height_density = 0.05
			env.fog_sky_affect = 0.5
		"heightfog":
			# THE BRIEF'S CLAIM, ISOLATED. The authored layer is fog_height
			# -40 at fog_height_density 0.006, and the whole playable surface
			# is between -2.5 and +42, i.e. entirely above it. This moves the
			# layer to 4 m — just over a standing robot — and leaves every
			# other number alone. If the picture does not change, the layer
			# was doing nothing where it was; if it does, it was.
			env.fog_height = 4.0
			env.fog_height_density = 0.05
		"fogonly":
			# The control. Haze alone, nothing else touched — this is the
			# "just add fog" that the ten-step quantiser is supposed to eat.
			env.fog_density = 0.0022
		_:
			push_warning("probe_legibility: ENV=%s is not a variant I know" % variant)
			return
	we.environment = env


# ── PLUMBING ───────────────────────────────────────────────────────────────

## The HUD's own filter material, read out of the scene file rather than
## instantiated: hud.gd wants a player and a campaign that do not exist here.
func _hud_filter() -> ShaderMaterial:
	var packed := load(HUD_SCENE) as PackedScene
	if packed == null:
		return null
	var state := packed.get_state()
	for i in state.get_node_count():
		if state.get_node_name(i) != FILTER_NODE:
			continue
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) != "material":
				continue
			var m: Variant = state.get_node_property_value(i, j)
			if m is ShaderMaterial:
				return (m as ShaderMaterial).duplicate()
			return null
	return null


## The FOV the game plays at, read out of Managers/settings.gd's own SPEC
## rather than typed here. The Settings autoload is not up under `--script`,
## and instantiating it would have it read — and later possibly write — the
## player's real user://settings.json, which a probe has no business doing.
func _fov() -> float:
	var spec: Variant = load("res://Managers/settings.gd").SPEC
	if spec is Dictionary and (spec as Dictionary).has("display.fov"):
		return float(((spec as Dictionary)["display.fov"] as Dictionary)["default"])
	# Say which number is being used. A silently defaulted FOV is a frame that
	# is not the game's, and the whole complaint is about the frame.
	push_warning("probe_legibility: no display.fov in Settings.SPEC — using %.0f" % FOV_FALLBACK)
	return FOV_FALLBACK


## The top of the collision under x,z.
func _ground(space: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(x, 1200.0, z), Vector3(x, -400.0, z)))
	if hit.is_empty():
		push_warning("probe_legibility: nothing under %.0f, %.0f — camera placed at y = 0" % [x, z])
		return 0.0
	return (hit["position"] as Vector3).y


func _luma(c: Color) -> float:
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
