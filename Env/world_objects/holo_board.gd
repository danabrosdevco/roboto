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
@export var board_size: float = 1.10
## How far the projection floats above this node's origin.
@export var lift: float = 0.04
## How tall a landmark icon stands on the plate, in metres. SiteIcons draws
## every one into a unit box, so this is the only size knob.
@export var icon_height: float = 0.105
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
func _build_plate() -> void:
	var half: float = board_size * 0.62
	var step: float = board_size / 8.0
	var w: float = board_size * 0.0016   # line half-width
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x: float = -half
	while x <= half + 0.0001:
		_bar(st, Vector3(x, 0.0, -half), Vector3(x, 0.0, half), w)
		x += step
	var z: float = -half
	while z <= half + 0.0001:
		_bar(st, Vector3(-half, 0.0, z), Vector3(half, 0.0, z), w)
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
	# The icon cache is NOT cleared: the meshes are immutable and shared, and
	# rebuilding them on every refresh is the cost this cache exists to avoid.
