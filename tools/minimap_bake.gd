extends SceneTree

# ─────────────────────────────────────────────
# MINIMAP BAKE — renders each level from directly overhead and saves the image
# plus the world rectangle it covers and where the objectives are.
#
# GEOMETRY, NOT NAVMESH. A navmesh trace shows where the pathfinder may walk,
# which is a developer's view of a map. A player opening a briefing needs to
# recognise buildings, walls and open ground, and to see at a glance how big
# the place is — "how long is this mission" was a question a first-time player
# could not answer at all.
#
# CANNOT RUN --headless. Headless uses the dummy renderer, which returns blank
# textures; this needs a real one, so the bake opens a window briefly.
# ─────────────────────────────────────────────

const OUT_DIR := "res://maps/minimaps"
const RESOLUTION := 1024
# Breathing room around the level so nothing touches the image edge.
const MARGIN := 1.06
## How much ground to show around the objectives, as a multiple of their own
## extent. Enough context to orient without losing the markers.
const OBJECTIVE_PADDING := 1.9
## Never zoom in tighter than this many metres across.
const MIN_SPAN := 110.0
# By path: see the note on class names at the top of tutorial_label.gd.
const _TutorialLabel := preload("res://Env/world_objects/tutorial_label.gd")
const _TutorialToast := preload("res://Character/hud/tutorial_toast.gd")

var _levels := [
	"res://maps/valley_level.tscn",
	"res://maps/valley_basin_level.tscn",
	"res://maps/arena_level.tscn",
	"res://maps/homebase_level.tscn",
	"res://maps/coastal-road_level.tscn",
	"res://maps/mutaha_level.tscn",
	"res://maps/pittsburgh_level.tscn"
]


func _init() -> void:
	await process_frame
	# A SQUARE window, because the camera frames a square span and the render
	# comes out of the window verbatim. At the stock 16:9 the map was a strip
	# down the middle of a letterboxed image, wasting most of the pixels and
	# making world_min/max depend on an aspect ratio nobody would think to
	# check.
	# THE WINDOW IS LEFT ALONE ON PURPOSE.
	#
	# Resizing it to a square seemed obvious and produced worse results twice:
	# the project stretches to a fixed design resolution, so a square window
	# first letterboxed the render, and then — with stretch disabled — left the
	# drawn content offset in the corner. The native window renders correctly
	# and centred, so the bake takes that and crops the middle square out of it.
	for _i in 2:
		await process_frame
	var only: String = ""
	for a in OS.get_cmdline_user_args():
		only = a
	for path in _levels:
		if only != "" and not path.contains(only):
			continue
		await _bake(path)
	print("MINIMAP BAKE DONE")
	quit()


func _bake(path: String) -> void:
	var packed: PackedScene = load(path)
	if packed == null:
		print("FAIL  could not load %s" % path)
		return
	var level: Node = packed.instantiate()
	# Out BEFORE the level enters the tree — see _strip_tutorial_signs.
	var signs := _strip_tutorial_signs(level)

	# RENDERS THROUGH THE MAIN WINDOW, not a SubViewport.
	#
	# The SubViewport route produced a correctly cleared image with nothing in
	# it — not even a plain unshaded box parented beside the camera — while the
	# camera, framing, visibility and bounds all checked out. Whatever that is,
	# the main viewport is the one path guaranteed to actually draw, so the bake
	# borrows the window for a few frames instead of fighting it.
	root.add_child(level)
	await process_frame
	# The level ships with a player, and the player owns a Camera3D that makes
	# itself current — the first attempt rendered the arena's sky from head
	# height. Anything that can claim the viewport has to go before ours does.
	var stripped := _strip_conflicts(level)
	var texts := _hide_world_text(level)
	_drop_toast()
	await process_frame

	# FRAMED ON THE OBJECTIVES, RENDERED FROM THE GEOMETRY.
	#
	# Two earlier framings were both wrong for a briefing:
	#   - merged visual bounds gave 2660m for the valley, because its meshes
	#     include a skybox and distant terrain
	#   - the navmesh gave 1495m, which is honest about where you CAN walk and
	#     useless about where you are GOING — the mission is a 90m cluster of
	#     relays in one corner of it, rendered as a smudge.
	# What a player needs to see is the objectives and enough ground around
	# them to orient. So frame on those, and let the navmesh cap the zoom-out
	# for small maps like the arena.
	var data := MinimapData.new()
	data.level_scene_path = path
	data.image_path = "%s/%s.png" % [OUT_DIR, path.get_file().get_basename()]
	_collect_objectives(level, data)
	_collect_insertion(level, data)

	var nav := _play_bounds(level)
	var bounds := _objective_bounds(data)
	var framed_on := "objectives"
	if bounds.size == Vector3.ZERO and data.objective_count() < 1:
		bounds = nav
		framed_on = "navmesh"
	if bounds.size == Vector3.ZERO:
		bounds = _world_bounds(level)
		framed_on = "geometry"
	if bounds.size == Vector3.ZERO:
		print("FAIL  %s has no objectives, navmesh or geometry" % path)
		_discard(level)
		return

	var centre := bounds.get_center()
	var span: float = maxf(bounds.size.x, bounds.size.z)
	if framed_on == "objectives":
		# Context around the markers, and a floor so two objectives ten metres
		# apart don't produce a map zoomed into a doorway.
		span = maxf(span * OBJECTIVE_PADDING, MIN_SPAN)
		# Never wider than the walkable world — the arena is 90m and there is
		# nothing out there to show.
		if nav.size != Vector3.ZERO:
			span = minf(span, maxf(nav.size.x, nav.size.z))
		# ...but always wide enough to actually contain them.
		span = maxf(span, maxf(bounds.size.x, bounds.size.z) * 1.25)

	# THEN MAKE ROOM FOR THE INSERTION. Objectives still decide the frame — the
	# padding above is tuned for a cluster of targets — and it only grows as far
	# as it must to take in where you start. Folding the start into the
	# objective bounds instead multiplied the whole walk in by the padding: the
	# valley went from 299m to 716m across, mostly empty margin.
	for p in data.insertion_positions:
		var lo := Vector2(centre.x, centre.z) - Vector2(span, span) * 0.5
		var hi := lo + Vector2(span, span)
		lo = Vector2(minf(lo.x, p.x - INSERTION_MARGIN), minf(lo.y, p.z - INSERTION_MARGIN))
		hi = Vector2(maxf(hi.x, p.x + INSERTION_MARGIN), maxf(hi.y, p.z + INSERTION_MARGIN))
		span = maxf(hi.x - lo.x, hi.y - lo.y)
		var mid := (lo + hi) * 0.5
		centre = Vector3(mid.x, centre.y, mid.y)
	span *= MARGIN

	# KEEP THE FRAME OVER GROUND.
	#
	# Centring on the objectives is right for deciding what to show, but the
	# arena's two objectives sit at one end of it — so the frame hung half off
	# the level and the map came out as a floor shoved into a corner of black.
	# Slide the centre back until the view is inside the walkable world, unless
	# the world is smaller than the frame, in which case just centre on it.
	if nav.size != Vector3.ZERO:
		var h_span := span * 0.5
		var lo_x := nav.position.x + h_span
		var hi_x := nav.position.x + nav.size.x - h_span
		centre.x = clampf(centre.x, lo_x, hi_x) if lo_x <= hi_x else nav.position.x + nav.size.x * 0.5
		var lo_z := nav.position.z + h_span
		var hi_z := nav.position.z + nav.size.z - h_span
		centre.z = clampf(centre.z, lo_z, hi_z) if lo_z <= hi_z else nav.position.z + nav.size.z * 0.5

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = span
	cam.near = 0.05
	cam.far = 8000.0
	# -90 about X points the lens straight down and puts world -Z at the top of
	# the image, so north is up and MinimapData.to_uv() is its exact inverse.
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	root.add_child(cam)
	# Height comes from the WORLD, not the frame: objective bounds are flat (all
	# the relays sit at the same altitude), so using them would have parked the
	# camera below the terrain it is meant to be looking down at.
	var geo := _world_bounds(level)
	var top: float = maxf(geo.position.y + geo.size.y, bounds.position.y + bounds.size.y) + 300.0
	cam.global_position = Vector3(centre.x, top, centre.z)
	cam.make_current()

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62.0, -38.0, 0.0)
	sun.light_energy = 1.2
	root.add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.72)
	e.ambient_light_energy = 1.0
	env.environment = e
	root.add_child(env)

	# Several frames: the first is before the camera is current, and lighting
	# settles a frame or two behind that.
	for _i in 8:
		await process_frame
	_drop_toast()   # and once more, in case anything announced a lesson meanwhile
	await process_frame
	await RenderingServer.frame_post_draw

	var img: Image = root.get_texture().get_image()
	# CROP TO THE CENTRAL SQUARE rather than fighting the window size.
	# An orthographic camera's `size` is its VERTICAL extent, so a
	# height-by-height crop is exactly span x span metres whatever aspect the
	# window happens to be — which means world_min/max never has to know.
	var h: int = img.get_height()
	var x0: int = int(floor((img.get_width() - h) * 0.5))
	if x0 > 0:
		img = img.get_region(Rect2i(x0, 0, h, h))
	if img.get_width() != RESOLUTION:
		img.resize(RESOLUTION, RESOLUTION, Image.INTERPOLATE_LANCZOS)

	var base: String = path.get_file().get_basename()
	var png: String = "%s/%s.png" % [OUT_DIR, base]
	img.save_png(png)

	var half: float = span * 0.5
	data.world_min = Vector2(centre.x - half, centre.z - half)
	data.world_max = Vector2(centre.x + half, centre.z + half)
	ResourceSaver.save(data, "%s/%s.tres" % [OUT_DIR, base])

	print("OK    %-20s %5.0f m across  img %dx%d  %d obj  %d insertion  framed on %s -> %s%s" % [
		base, span, img.get_width(), img.get_height(),
		data.objective_count(), data.insertion_positions.size(), framed_on, png.get_file(),
		("  (%d tutorial signs, %d other labels left out)" % [signs, texts]) if signs + texts > 0 else ""])

	_discard(cam)
	_discard(sun)
	_discard(env)
	_discard(level)
	await process_frame


func _discard(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	n.queue_free()



# Cameras and environments the level brought with it. A level's own Camera3D
# will re-claim the viewport, and its WorldEnvironment would override the flat
# lighting this bake needs — both have to be gone, not merely overridden.
func _strip_conflicts(node: Node) -> int:
	var n := 0
	var doomed: Array[Node] = []
	_gather_conflicts(node, doomed)
	for d in doomed:
		d.get_parent().remove_child(d)
		d.queue_free()
		n += 1
	return n


func _gather_conflicts(node: Node, out: Array[Node]) -> void:
	if node is Camera3D or node is WorldEnvironment:
		out.append(node)
		return
	for c in node.get_children():
		_gather_conflicts(c, out)


# TUTORIAL SIGNS COME OUT OF THE LEVEL BEFORE IT ENTERS THE TREE.
#
# In the tree, a sign bricks the map two ways. It is text drawn over everything,
# billboarded and with no depth test — and with the level's camera stripped it
# finds no player in its first frame and switches itself on for good. And it
# registers with TutorialToast, which stands the camera in for a missing player
# and measures FLAT distance: from straight overhead, any sign near the middle
# of the frame counted as stood next to, and its full-screen lesson panel was
# baked into the picture. Removed before _ready, a sign never draws, never
# registers, and never makes the toast at all.
func _strip_tutorial_signs(node: Node) -> int:
	var signs: Array[Node] = []
	_gather_signs(node, signs)
	for s in signs:
		s.get_parent().remove_child(s)
		s.queue_free()
	return signs.size()


func _gather_signs(node: Node, out: Array[Node]) -> void:
	if node is _TutorialLabel:
		out.append(node)
		return   # its children go with it
	for c in node.get_children():
		_gather_signs(c, out)


# Any other words in the world — a plain Label3D sign, a debug label a node
# makes for itself in _ready — are text at 3D scale on a map that has none of
# its own. Hidden once the level is in, so the ones made in _ready are caught.
func _hide_world_text(node: Node) -> int:
	var n := 0
	if node is Label3D and (node as Label3D).visible:
		(node as Label3D).visible = false
		n += 1
	for c in node.get_children():
		n += _hide_world_text(c)
	return n


# The toast hangs off the root, not the level, so it would outlive one level
# and show over the next. With the signs gone nothing should make one; this is
# for anything else that announces a lesson while the bake is looking.
func _drop_toast() -> void:
	var toast := root.get_node_or_null(_TutorialToast.NODE_NAME)
	if toast != null:
		_discard(toast)


# Merged AABB of everything that draws. Includes CSG, which FuncGodot leaves
# behind in some maps, because CSGShape3D is a VisualInstance3D too.
func _world_bounds(node: Node) -> AABB:
	var boxes: Array[AABB] = []
	_gather_aabbs(node, boxes)
	if boxes.is_empty():
		return AABB()
	var out: AABB = boxes[0]
	for i in range(1, boxes.size()):
		out = out.merge(boxes[i])
	return out


func _gather_aabbs(node: Node, out: Array[AABB]) -> void:
	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		var local := vi.get_aabb()
		if local.size != Vector3.ZERO:
			out.append(vi.global_transform * local)
	for c in node.get_children():
		_gather_aabbs(c, out)


# Objectives identify themselves: InteractObjective and ReachObjective both
# carry `id` and `display_name` already, which is what the briefing labels with.
func _collect_objectives(node: Node, data: MinimapData) -> void:
	if node is Node3D and "id" in node and "display_name" in node:
		var id: StringName = StringName(str(node.get("id")))
		if id != &"":
			var kind := &"capture"
			if String(id).contains("extract") or node.get_class() == "ReachObjective":
				kind = &"extract"
			data.objective_ids.append(id)
			data.objective_names.append(str(node.get("display_name")))
			data.objective_positions.append((node as Node3D).global_position)
			data.objective_kinds.append(kind)
	for c in node.get_children():
		_collect_objectives(c, data)


func _count_visible(node: Node, acc: Array) -> void:
	if node is VisualInstance3D:
		acc[0] += 1
		if (node as VisualInstance3D).is_visible_in_tree():
			acc[1] += 1
	for c in node.get_children():
		_count_visible(c, acc)


# The ground a player can actually stand on. Used for FRAMING only — see the
# note at the call site for why visual bounds are the wrong thing here.
#
# The region's own transform matters: homebase's NavigationRegion3D carries a
# 180-degree rotation about Y plus an offset, so raw navmesh vertices are
# mirrored and displaced from where the level really is.
func _play_bounds(node: Node) -> AABB:
	var regions: Array[Node] = []
	_gather_regions(node, regions)
	var out := AABB()
	var seeded := false
	for r in regions:
		var region := r as NavigationRegion3D
		var nm := region.navigation_mesh
		if nm == null:
			continue
		var verts := nm.get_vertices()
		if verts.is_empty():
			continue
		var xform := region.global_transform
		for v in verts:
			var w: Vector3 = xform * v
			if not seeded:
				out = AABB(w, Vector3.ZERO)
				seeded = true
			else:
				out = out.expand(w)
	return out if seeded else AABB()


func _gather_regions(node: Node, out: Array[Node]) -> void:
	if node is NavigationRegion3D:
		out.append(node)
	for c in node.get_children():
		_gather_regions(c, out)


# The box containing every objective. This is what the briefing is actually
# about — where you are going — as opposed to where you may walk (navmesh) or
# what exists (geometry).
func _objective_bounds(data: MinimapData) -> AABB:
	if data.objective_positions.is_empty():
		return AABB()
	var out := AABB(data.objective_positions[0], Vector3.ZERO)
	for i in range(1, data.objective_positions.size()):
		out = out.expand(data.objective_positions[i])
	return out


# The player's spawn first — the node world.gd actually drops you on, the
# level's `spawn_point`, falling back to a child called SpawnPoint — then any
# player-commandable SquadSpawnPoint that is not already beside it. The squad
# normally forms up next to you, and two markers on one spot is clutter.
const INSERTION_MERGE_DISTANCE := 15.0
## Ground kept around the insertion marker when the frame grows to include it.
const INSERTION_MARGIN := 30.0

func _collect_insertion(level: Node, data: MinimapData) -> void:
	var spawn := level.get("spawn_point") as Node3D
	if spawn == null:
		spawn = level.get_node_or_null("SpawnPoint") as Node3D
	if spawn != null:
		data.insertion_positions.append(spawn.global_position)
	var squads: Array[Node] = []
	_gather_squad_spawns(level, squads)
	for s in squads:
		var p: Vector3 = (s as Node3D).global_position
		var near := false
		for q in data.insertion_positions:
			if Vector2(p.x - q.x, p.z - q.z).length() < INSERTION_MERGE_DISTANCE:
				near = true
				break
		if not near:
			data.insertion_positions.append(p)


func _gather_squad_spawns(node: Node, out: Array[Node]) -> void:
	if node is SquadSpawnPoint and (node as SquadSpawnPoint).player_commandable:
		out.append(node)
	for c in node.get_children():
		_gather_squad_spawns(c, out)
