extends Node

# ─────────────────────────────────────────────
# ICON STUDIO — line-art icons drawn from the game's own 3D models.
#
# A model is rendered offscreen twice over: first with every surface painted
# its facing and its depth (icon_pass.gdshader), then through an edge filter
# that keeps only the outline, the creases and the places one part passes in
# front of another (icon_edges.gdshader). Both happen at SUPERSAMPLE times the
# icon's size; shrinking the result is the antialiasing. What comes out is
# white lines on transparent, tinted by whatever shows it.
#
# Things with no model (modules, the repair kit) come from line drawings in
# icon_art.gd, through render_svg(), so every icon shares one line weight.
#
# NEEDS A REAL RENDERER. Headless runs draw nothing, so this is a baking tool:
# tools/bake_icons.gd runs it in a window and writes res://icons/, and the
# game only ever reads those files (icons.gd).
# ─────────────────────────────────────────────

enum Framing {
	## Long side across, from the side: guns.
	SIDE,
	## Long side up, from the side: grenades and canisters.
	UPRIGHT,
	## Front three-quarter view from a little above: robots.
	THREE_QUARTER,
}

const PASS_SHADER := preload("res://Character/hud/icons/icon_pass.gdshader")
const EDGE_SHADER := preload("res://Character/hud/icons/icon_edges.gdshader")

## Rendered this many times larger, then shrunk.
const SUPERSAMPLE := 4
## Line width in pixels of the finished icon, whatever its size.
const LINE_PX := 1.25
## Empty margin kept round the model, as a fraction of the icon.
const PAD := 0.06


## Line art of `model` at `size` pixels, or null if nothing in it is visible.
## `fill` 1.0 fills the outline solid: at the smallest sizes the lines run
## together anyway, and a silhouette reads better than a smudge.
## Awaits a few rendered frames, so call it with await.
func render_model(model: PackedScene, size: Vector2i, framing: int, flip_h: bool = false,
		flip_v: bool = false, fill: float = 0.0) -> Image:
	if model == null:
		return null
	var big := size * SUPERSAMPLE
	var pass_vp := _viewport(big)
	pass_vp.own_world_3d = true
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.environment = _plain_environment()
	pass_vp.add_child(cam)
	cam.current = true
	var body := model.instantiate()
	_strip(body)
	pass_vp.add_child(body)
	# CSG builds its mesh on the frame after it enters the tree, and the
	# bounds are empty until it has.
	for i in 2:
		await get_tree().process_frame
	var bounds := _bounds(body)
	if bounds.size.length() < 0.0001:
		pass_vp.queue_free()
		return null

	var paint := ShaderMaterial.new()
	paint.shader = PASS_SHADER
	_aim(cam, bounds, framing, float(size.x) / float(size.y), paint)
	for geo in _geometry(body):
		geo.material_override = paint

	var edge_vp := _viewport(big)
	var sheet := TextureRect.new()
	sheet.texture = pass_vp.get_texture()
	sheet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sheet.stretch_mode = TextureRect.STRETCH_SCALE
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var edges := ShaderMaterial.new()
	edges.shader = EDGE_SHADER
	# A pixel is on a line within `radius` of an edge either side, so the line
	# is twice the radius wide before the shrink.
	edges.set_shader_parameter("radius", LINE_PX * SUPERSAMPLE * 0.5)
	edges.set_shader_parameter("fill", fill)
	sheet.material = edges
	edge_vp.add_child(sheet)

	# Viewports draw in tree order, and the edge pass reads the other one's
	# texture: a few frames guarantees it has read a finished one.
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := edge_vp.get_texture().get_image()
	pass_vp.queue_free()
	edge_vp.queue_free()
	return _finish(img, size, flip_h, flip_v)


## Line art from a drawing (an SVG path, in a `view`-sized box) at `size`
## pixels, in the same white and the same line weight as render_model().
func render_svg(path_d: String, view: Vector2, size: Vector2i) -> Image:
	var big := size * SUPERSAMPLE
	# The stroke is in the drawing's units: LINE_PX of the finished icon.
	var stroke := LINE_PX * view.x / float(size.x)
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %s %s\"><path d=\"%s\" fill=\"none\" stroke=\"#ffffff\" stroke-width=\"%.4f\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>" % [
		big.x, big.y, view.x, view.y, path_d, stroke]
	var img := Image.new()
	if img.load_svg_from_string(svg, 1.0) != OK:
		return null
	return _finish(img, size, false, false)


func _finish(img: Image, size: Vector2i, flip_h: bool, flip_v: bool) -> Image:
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	if flip_h:
		img.flip_x()
	if flip_v:
		img.flip_y()
	return img


func _viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(vp)
	return vp


# The project's default environment could bring sky, fog or glow into what is
# meant to be pure data.
func _plain_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	return env


# A model as a picture only. Scripts go before it enters the tree, so a robot
# never runs its AI, joins a squad or registers with a manager; anything that
# draws but is not the model (particles, sprites, labels) is hidden; nothing
# can make a sound.
func _strip(node: Node) -> void:
	node.set_script(null)
	for group in node.get_groups():
		node.remove_from_group(group)
	if node is GeometryInstance3D and not (node is MeshInstance3D or node is CSGShape3D):
		(node as GeometryInstance3D).visible = false
	elif node is Light3D:
		(node as Light3D).visible = false
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).autoplay = false
	elif node is AudioStreamPlayer:
		(node as AudioStreamPlayer).autoplay = false
	elif node is AnimationPlayer:
		(node as AnimationPlayer).autoplay = ""
	for child in node.get_children():
		_strip(child)


func _geometry(root: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	_collect(root, out)
	return out


func _collect(node: Node, out: Array[GeometryInstance3D]) -> void:
	if node is MeshInstance3D or (node is CSGShape3D and (node as CSGShape3D).is_root_shape()):
		var geo := node as GeometryInstance3D
		if geo.is_visible_in_tree():
			out.append(geo)
	for child in node.get_children():
		_collect(child, out)


func _bounds(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for geo in _geometry(root):
		var local := geo.get_aabb()
		if local.size.length() < 0.00001:
			continue
		var box: AABB = geo.global_transform * local
		out = box if first else out.merge(box)
		first = false
	return out


# Points the camera and sizes it to the model, and tells the paint the depth
# range it spans, so near-to-far always uses the whole 0..1.
func _aim(cam: Camera3D, box: AABB, framing: int, aspect: float, paint: ShaderMaterial) -> void:
	var center := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.001)
	var toward: Vector3
	var up: Vector3
	if framing == Framing.THREE_QUARTER:
		# Robots face -Z. From the front, 35 degrees round and 15 up.
		var yaw := deg_to_rad(35.0)
		var pitch := deg_to_rad(15.0)
		toward = Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
		up = Vector3.UP
	else:
		# Across the thinnest side, so the outline is the widest one there is.
		var axes := _axes_by_extent(box)
		toward = axes[2]
		up = axes[1] if framing == Framing.SIDE else axes[0]
	var dist := radius * 3.0 + 1.0
	cam.look_at_from_position(center + toward * dist, center, up)

	var to_view := cam.global_transform.affine_inverse()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p: Vector3 = to_view * box.get_endpoint(i)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span := hi - lo
	# Orthographic size is the visible HEIGHT; a wide model is fitted by width.
	cam.size = maxf(span.y, span.x / aspect) / (1.0 - PAD * 2.0)
	cam.near = 0.01
	cam.far = dist + radius * 2.0
	paint.set_shader_parameter("near_d", dist - radius)
	paint.set_shader_parameter("far_d", dist + radius)


# The box's axes, longest first.
static func _axes_by_extent(box: AABB) -> Array[Vector3]:
	var list := [[box.size.x, Vector3.RIGHT], [box.size.y, Vector3.UP], [box.size.z, Vector3.BACK]]
	list.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array[Vector3] = [list[0][1], list[1][1], list[2][1]]
	return out
