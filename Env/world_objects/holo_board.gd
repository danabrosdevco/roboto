extends Node3D

# ─────────────────────────────────────────────
# HOLO BOARD — the projection itself, built from a list of sites and the
# routes between them.
#
# DELIBERATELY KNOWS NOTHING ABOUT THE CAMPAIGN. It takes nodes and edges as
# plain data and draws them. Everything about missions, locks, clears and
# rewards lives one layer up in ops_table.gd.
#
# That split is not tidiness. The whole point of the v1 board is that
# territory, per-turn yields and enemy attacks arrive later as MORE DATA ON
# THE SAME NODES rather than as a rebuild — and that only holds if the thing
# doing the drawing has no opinion about what a node means.
#
# ONE MESH FOR EVERY DASH. The routes are drawn as a single ArrayMesh built
# out of quads rather than one MeshInstance3D per dash: twenty routes at eight
# dashes each is a hundred and sixty nodes to add, transform and cull, for
# something that never changes between rebuilds.
#
# Nodes get an instance each, because each one carries its own faction tint
# and its own `present` as the board resolves.
# ─────────────────────────────────────────────

const _HOLO := preload("res://Env/world_objects/holo.gdshader")
const _Icons := preload("res://Env/world_objects/site_icons.gd")

## Metres across, for the whole board. map_position values are rescaled to fit.
## The long axis the sites are normalised into. 5.6 on TERRAIN's 7.0 m
## table: the sites keep their aspect, so a 5.6 m spread along the car comes
## out about 2.5 m across it, inside the 3.0 m the table gives.
@export var board_size: float = 5.6
## How far the projection floats above this node's origin.
@export var lift: float = 0.05
## How tall a landmark icon stands on the plate, in metres. SiteIcons draws
## every one into a unit box, so this is the only size knob.
## SIGNIFICANTLY BIGGER than the first pass. At 0.075 on a 1.1 m board each
## landmark was seven per cent of the board width and read as a scratch; the
## whole point of drawing the relay dish rather than a dot is that you can
## tell it from the ferris wheel.
## Roughly a twentieth of board_size. Not proportional in code — a landmark
## is read at arm's length and wants an absolute size, not a fraction of
## however big the table happens to be.
## 0.52, up from 0.30. At a third of a metre on a 5.6 m board the landmarks
## were legible but small — and the whole claim of drawing the relay dish
## rather than a dot is that you know the place by its silhouette.
@export var icon_height: float = 0.52
## Clearance kept around a site when a route is drawn to it, as a fraction of
## icon_height — a dotted line should stop at the landmark, not run into it.
@export var node_radius: float = 0.030
## Dash length and gap along a route, in metres.
@export var dash: float = 0.018
@export var dash_gap: float = 0.014
## The base plate's own colour. Deliberately dimmer than any node.
@export var plate_tint: Color = Color(0.30, 0.62, 0.78)

var _plate: MeshInstance3D = null
var _routes: MeshInstance3D = null
var _nodes: Dictionary = {}          # id -> MeshInstance3D
var _points: Dictionary = {}         # id -> Vector3, board-space, for routes
var _icon_cache: Dictionary = {}   # Kind -> Mesh


## Draw a board.
##
## `nodes` is an array of dictionaries: {id: StringName, at: Vector2,
## tint: Color, present: float}. `at` is in whatever units the caller likes —
## they are normalised to board_size here, so map_position's mixed scales do
## not have to be fixed before anything can be looked at.
##
## `edges` is an array of [from_id, to_id] pairs. An edge naming an id that is
## not in `nodes` is skipped with a warning rather than dropped silently: a
## route to nowhere means the data is wrong and that is worth hearing about.
func build(nodes: Array, edges: Array) -> void:
	_clear()
	if nodes.is_empty():
		push_warning("HoloBoard: asked to draw a board with no sites on it. Nothing is projected.")
		return

	_points = _layout(nodes)
	_build_plate()
	_build_routes(edges)
	for n in nodes:
		_build_node(n)
	_build_gauges(nodes, gauge_tints)


## Fit the incoming positions into board_size, centred.
##
## NORMALISED RATHER THAN TRUSTED. MissionDefinition.map_position is not in
## consistent units — most entries are tens-to-hundreds, one is a fraction,
## and several are (0,0). Scaling to the actual spread means the board is
## legible today and gets better, not different, when the layout pass happens.
##
## Everything at the same point (or one site only) falls back to a fixed span
## so the board does not divide by zero and collapse to a dot.
func _layout(nodes: Array) -> Dictionary:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for n in nodes:
		var p: Vector2 = n.get("at", Vector2.ZERO)
		lo.x = minf(lo.x, p.x); lo.y = minf(lo.y, p.y)
		hi.x = maxf(hi.x, p.x); hi.y = maxf(hi.y, p.y)
	var span := hi - lo
	if span.x < 0.0001 and span.y < 0.0001:
		span = Vector2.ONE
	var scale: float = board_size / maxf(maxf(span.x, span.y), 0.0001)
	var mid := (lo + hi) * 0.5

	var out := {}
	for n in nodes:
		var p: Vector2 = n.get("at", Vector2.ZERO)
		var local := (p - mid) * scale
		# Board X/Z, not X/Y: the projection lies flat and is read from above.
		out[n["id"]] = Vector3(local.x, lift, local.y)
	return out


## A GRID, NOT A SLAB. The first cut laid a filled quad under everything and
## it read as a sheet of lit perspex: the brightest thing on the table was the
## part carrying no information, and the markers sat on it rather than in the
## air. A hologram is mostly empty — the floor of one should be a ruling you
## can see the room through.
## RECTANGULAR, AND SIZED TO A REAL TABLE. The plate used to be a square
## derived from board_size, which was fine while this floated in a test
## harness and is wrong the moment it stands on furniture: TERRAIN's ops
## table is 7.0 x 3.0 m, and a square plate big enough to carry the board
## along its length hangs half a metre off both long sides.
##
## Default is the table's surface less a margin. The campaign runs east-west
## so the sites use the length and barely a third of the depth — see
## OpsTable.LAYOUT — which is why a board shaped like the table works at all.
@export var plate_size: Vector2 = Vector2(6.6, 2.7)


func _build_plate() -> void:
	var hx: float = plate_size.x * 0.5
	var hz: float = plate_size.y * 0.5
	var step: float = board_size / 8.0
	var w: float = board_size * 0.0016   # line half-width
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x: float = -hx
	while x <= hx + 0.0001:
		_bar(st, Vector3(x, 0.0, -hz), Vector3(x, 0.0, hz), w)
		x += step
	var z: float = -hz
	while z <= hz + 0.0001:
		_bar(st, Vector3(-hx, 0.0, z), Vector3(hx, 0.0, z), w)
		z += step
	st.generate_normals()
	_plate = _holo_mesh(st.commit(), plate_tint, 0.22)
	_plate.position = Vector3(0.0, lift * 0.5, 0.0)
	add_child(_plate)


## One flat bar between two points, lying in the board plane.
func _bar(st: SurfaceTool, a: Vector3, b: Vector3, half_width: float) -> void:
	var span := b - a
	if span.length() < 0.0001:
		return
	var dir := span.normalized()
	var side := Vector3(-dir.z, 0.0, dir.x) * half_width
	st.set_normal(Vector3.UP)
	st.add_vertex(a - side); st.add_vertex(b - side); st.add_vertex(b + side)
	st.set_normal(Vector3.UP)
	st.add_vertex(a - side); st.add_vertex(b + side); st.add_vertex(a + side)


## One site: a line drawing of its landmark, standing on the plate.
##
## THE ICON IS THE MARKER. There is no separate pin under it — SiteIcons
## builds every landmark standing on its own origin inside a unit box, so the
## drawing itself is what sits at the site's position. A pin as well would be
## two things claiming the same point.
##
## Meshes are cached PER KIND, not per site. Three sim arenas share one level
## and therefore one icon, and building that mesh three times would be three
## copies of the same forty struts.
func _build_node(n: Dictionary) -> void:
	var id = n["id"]
	if not _points.has(id):
		return   # laid out from the same list, so this cannot normally happen
	var kind: int = int(n.get("icon", _Icons.Kind.MARKER))
	if not _icon_cache.has(kind):
		_icon_cache[kind] = _Icons.build(kind)
	var tint: Color = n.get("tint", Color(0.40, 0.78, 0.95))
	var marker := _holo_mesh(_icon_cache[kind], tint, 1.0)
	marker.position = _points[id]
	# Per-site scale, so a 408 m tower stands over a 4 m bridge. See
	# OpsTable._icon_scale for why it is logarithmic and not linear.
	marker.scale = Vector3.ONE * icon_height * float(n.get("scale", 1.0))
	marker.set_meta(&"site", id)
	add_child(marker)
	_nodes[id] = marker


## Every dash of every route, in one mesh.
func _build_routes(edges: Array) -> void:
	if edges.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drawn := 0
	for e in edges:
		if e.size() < 2:
			continue
		if not _points.has(e[0]) or not _points.has(e[1]):
			push_warning("HoloBoard: route %s -> %s names a site that is not on the board, so it is not drawn." % [str(e[0]), str(e[1])])
			continue
		_dash_line(st, _points[e[0]], _points[e[1]])
		drawn += 1
	if drawn == 0:
		return
	st.generate_normals()
	_routes = _holo_mesh(st.commit(), plate_tint, 0.8)
	add_child(_routes)


## A dotted run between two points, as flat quads lying on the board.
func _dash_line(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var span := b - a
	var total := span.length()
	if total < 0.0001:
		return
	var dir := span / total
	# Across the line, in the board plane.
	var side := Vector3(-dir.z, 0.0, dir.x) * (node_radius * 0.10)
	# Start and end clear of the markers so a route does not run into a site.
	var inset: float = node_radius * 1.4
	var t: float = inset
	var stop: float = total - inset
	while t < stop:
		var t2: float = minf(t + dash, stop)
		var p0 := a + dir * t
		var p1 := a + dir * t2
		st.set_normal(Vector3.UP)
		st.add_vertex(p0 - side); st.add_vertex(p1 - side); st.add_vertex(p1 + side)
		st.set_normal(Vector3.UP)
		st.add_vertex(p0 - side); st.add_vertex(p1 + side); st.add_vertex(p0 + side)
		t = t2 + dash_gap


## One holo-shaded mesh instance. Its OWN material: a shared one would mean
## every node on the board changed colour together.
func _holo_mesh(mesh: Mesh, tint: Color, strength: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _HOLO
	mat.set_shader_parameter(&"tint", tint)
	mat.set_shader_parameter(&"intensity", strength)
	mi.material_override = mat
	return mi


# ─────────────────────────────────────────────
# GAUGES — three bars under every site, all the time.
#
# The readout used to appear only on hover, which meant the board told you
# nothing until you interrogated it one site at a time. These are always
# there: compute, resources, resistance, as LENGTHS. You read the whole
# theatre by shape before you read a single number, and the rich cheap site
# is visible without touching anything.
#
# FOUR MESHES FOR THE WHOLE BOARD, not six per site. The tracks share one
# mesh and each channel's fills share another, because a track is the same
# dim colour everywhere and a fill is the same channel colour everywhere —
# only the LENGTH differs, and length is geometry. Twelve sites would
# otherwise be seventy-two MeshInstance3Ds to add, transform and cull for
# something that only changes when the campaign does.
#
# Hover is the exception and gets its own small overlay: see light_gauges.
# ─────────────────────────────────────────────

## Bar length at full, in metres, and the bar's thickness.
@export var gauge_width: float = 0.26
## 0.015, not 0.007. A bar lying flat on the board is seen at a shallow
## angle from standing height, so its apparent thickness is a fraction of
## its real one — the first pass was invisible.
@export var gauge_height: float = 0.034
@export var gauge_gap: float = 0.016
## Unlit bars sit back so the icons stay the loudest thing on the board.
@export var gauge_rest: float = 0.62

const CH_COMPUTE := 0
const CH_RESOURCE := 1
const CH_RESIST := 2

var _gauge_meshes: Array = []        # the four MeshInstance3Ds
var _lit: Array = []                 # the hovered site's three overlay bars
## Compute, resources, resistance. Set by whoever drives the board so the
## bars and the figures beside them cannot drift to different colours.
var gauge_tints: Array = [Color(0.40, 0.78, 0.95), Color(0.95, 0.78, 0.35), Color(0.95, 0.42, 0.35)]


## Where a site's gauge block starts, in board space — the top-left of its
## first bar. Labels line up against this.
func gauge_anchor(id) -> Vector3:
	if not _points.has(id):
		return global_position
	return to_global(_points[id] + Vector3(-gauge_width * 0.5, 0.004,
		icon_height * 0.52))


func _build_gauges(nodes: Array, tints: Array) -> void:
	var track := SurfaceTool.new()
	track.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fills: Array = []
	for i in 3:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		fills.append(st)
	var any := false

	for n in nodes:
		var g = n.get("gauges", null)
		if g == null or not _points.has(n["id"]):
			continue
		any = true
		var base: Vector3 = _points[n["id"]] + Vector3(0.0, 0.003, icon_height * 0.52)
		for ch in 3:
			var y: float = base.z + float(ch) * (gauge_height + gauge_gap)
			var left: float = base.x - gauge_width * 0.5
			_quad(track, left, y, gauge_width, base.y)
			var f: float = clampf(float(g[ch]), 0.0, 1.0)
			if f > 0.001:
				_quad(fills[ch], left, y, gauge_width * f, base.y + 0.0012)

	if not any:
		return
	track.generate_normals()
	var tm := _holo_mesh(track.commit(), plate_tint, gauge_rest * 0.55)
	add_child(tm)
	_gauge_meshes.append(tm)
	for ch in 3:
		fills[ch].generate_normals()
		var mesh: ArrayMesh = fills[ch].commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := _holo_mesh(mesh, tints[ch], gauge_rest)
		add_child(mi)
		_gauge_meshes.append(mi)


## One flat bar lying on the board, from (x, z) running +x.
func _quad(st: SurfaceTool, x: float, z: float, w: float, y: float) -> void:
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(x, y, z)); st.add_vertex(Vector3(x + w, y, z))
	st.add_vertex(Vector3(x + w, y, z + gauge_height))
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(x, y, z)); st.add_vertex(Vector3(x + w, y, z + gauge_height))
	st.add_vertex(Vector3(x, y, z + gauge_height))


## Light one site's gauges — an overlay drawn over the resting ones, because
## the resting bars are merged into shared meshes and a single site's three
## cannot be picked back out of them.
func light_gauges(id, fractions: Array, tints: Array) -> void:
	for m in _lit:
		if is_instance_valid(m):
			remove_child(m)
			m.queue_free()
	_lit.clear()
	if id == null or not _points.has(id) or fractions.is_empty():
		return
	var base: Vector3 = _points[id] + Vector3(0.0, 0.005, icon_height * 0.52)
	for ch in 3:
		var f: float = clampf(float(fractions[ch]), 0.0, 1.0)
		if f <= 0.001:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_quad(st, base.x - gauge_width * 0.5, base.z + float(ch) * (gauge_height + gauge_gap),
			gauge_width * f, base.y)
		st.generate_normals()
		var mi := _holo_mesh(st.commit(), tints[ch], 2.0)
		add_child(mi)
		_lit.append(mi)


# ─────────────────────────────────────────────
# THE QUEUED OPERATION
#
# Hover is a question and selection is a decision, so they cannot look the
# same. Hover lights a site for as long as you point at it; this is a ring
# cut into the plate around the one you have actually committed to, and it
# stays there after you look away, after you close the view, and while you
# walk the length of the train to the door.
#
# A RING ROUND THE SITE rather than a brighter icon, because the player
# needs to find it from across the table without hunting — a closed shape on
# the board reads at a glance where a change of brightness does not, and it
# cannot be confused with the hover lighting it has to coexist with.
# ─────────────────────────────────────────────

## Radius of the queued ring, as a multiple of icon_height.
@export var queued_ring: float = 0.62
@export var queued_tint: Color = Color(0.40, 0.78, 0.95)

var _queued: MeshInstance3D = null
var _queued_id = null


## Ring the operation that is queued, or clear it with null.
func set_queued(id) -> void:
	if id == _queued_id and _queued != null and is_instance_valid(_queued):
		return
	_queued_id = id
	if _queued != null and is_instance_valid(_queued):
		remove_child(_queued)
		_queued.queue_free()
		_queued = null
	if id == null or not _points.has(id):
		return
	var r: float = icon_height * queued_ring
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w: float = r * 0.07
	var prev := Vector2(r, 0.0)
	for i in range(1, 33):
		var a: float = float(i) / 32.0 * TAU
		var p := Vector2(cos(a) * r, sin(a) * r)
		_bar(st, Vector3(prev.x, 0.0, prev.y), Vector3(p.x, 0.0, p.y), w)
		prev = p
	# Four ticks outward, so it reads as a designation and not a puddle.
	for i in 4:
		var a: float = float(i) * PI * 0.5 + 0.78
		var c := Vector3(cos(a), 0.0, sin(a))
		_bar(st, c * r * 1.08, c * r * 1.42, w)
	st.generate_normals()
	_queued = _holo_mesh(st.commit(), queued_tint, 1.9)
	_queued.position = _points[id] + Vector3(0.0, 0.006, 0.0)
	add_child(_queued)


## Recolour or re-light one site without rebuilding the board — what selection
## and hover drive.
func set_site(id, tint: Color, strength: float = -1.0) -> void:
	var mi = _nodes.get(id)
	if mi == null or not is_instance_valid(mi):
		return
	var mat := mi.material_override as ShaderMaterial
	mat.set_shader_parameter(&"tint", tint)
	if strength >= 0.0:
		mat.set_shader_parameter(&"intensity", strength)


## Where a site sits in world space — for a label, a cursor, or the zoomed
## view to line itself up against.
func site_world_position(id) -> Vector3:
	var mi = _nodes.get(id)
	return mi.global_position if mi != null and is_instance_valid(mi) else global_position


func _clear() -> void:
	# remove_child before queue_free: a rebuild in the same frame would
	# otherwise lay the new board over the old one, which is still a child
	# until the deferred free lands.
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_nodes.clear()
	_points.clear()
	_plate = null
	_routes = null
	_gauge_meshes.clear()
	_lit.clear()
	_queued = null
	_queued_id = null
	# The icon cache is NOT cleared: the meshes are immutable and shared, and
	# rebuilding them on every refresh is the cost this cache exists to avoid.
