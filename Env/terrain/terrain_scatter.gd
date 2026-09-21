@tool
@icon("res://addons/plenticons/icons/64x-hidpi/objects/axe-green.png")
class_name TerrainScatter
extends Node3D

# ─────────────────────────────────────────────
# TERRAIN SCATTER — props spread over a GeneratedTerrain by rule, not by hand.
#
# Each TerrainScatterLayer says what (scenes or meshes, at their authored size),
# how many per hectare, and where (slope, height, mountain zone, away from
# roads and building pads). The result is drawn as MultiMeshes — thousands of
# props for a handful of draw calls — with optional trunk/boulder colliders.
#
# NOTHING PER-PROP IS SAVED. The layout is a pure function of the seed, the
# layers and the terrain, so it is rebuilt on load like the terrain itself, and
# it follows the ground when the terrain is regenerated. Hand-placed set pieces
# belong in the level as ordinary nodes; this is for the thousand-rock layer.
#
# Put it under the GeneratedTerrain (or point terrain_path at one). Under the
# NavigationRegion3D its MultiMeshes are parsed as obstacles when you bake.
# ─────────────────────────────────────────────

const Layer := preload("res://Env/terrain/terrain_scatter_layer.gd")
const Data := preload("res://Env/terrain/terrain_data.gd")

const BUILT_META := &"_terrain_scatter_built"

## The terrain to scatter over. Empty = the nearest GeneratedTerrain above this.
@export var terrain_path: NodePath:
	set(value):
		terrain_path = value
		if _ready_done:
			_connect_terrain()
			_queue_rebuild()
@export var layers: Array[Layer] = []:
	set(value):
		for old in layers:
			if old != null and old.changed.is_connected(_queue_rebuild):
				old.changed.disconnect(_queue_rebuild)
		layers = value
		for layer in layers:
			if layer != null and not layer.changed.is_connected(_queue_rebuild):
				layer.changed.connect(_queue_rebuild)
		_queue_rebuild()
## Change for a different arrangement of the same layers.
@export var random_seed: int = 1:
	set(value):
		random_seed = value
		_queue_rebuild()
## Tick to scatter again now. (It also redoes itself whenever the terrain or a
## layer changes.)
@export var rebuild_scatter: bool = false:
	set(value):
		if value and _ready_done:
			rebuild()

@export_group("Collision")
@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value
		_queue_rebuild()
@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		collision_mask = value
		_queue_rebuild()

var _ready_done := false
var _rebuild_queued := false
var _connected_terrain: Node3D
var _hinted_empty := false
# Where each layer put its props, in this node's space. Kept rather than read
# back from the MultiMeshes: headless Godot's dummy renderer does not store
# MultiMesh transforms, so anything reading them there gets identities.
var _layer_transforms: Array = []


func _ready() -> void:
	_ready_done = true
	var terrain := _connect_terrain()
	if terrain == null:
		return   # _connect_terrain() has said why
	# A terrain ABOVE this node readies after it (children ready first) and
	# emits `rebuilt` once it has built — scattering now would be thrown away.
	if terrain.is_node_ready():
		rebuild()


## The GeneratedTerrain this scatters over, or null.
func get_terrain() -> Node3D:
	if not terrain_path.is_empty():
		var n := get_node_or_null(terrain_path)
		return n as Node3D if n != null and n.has_signal(&"rebuilt") else null
	var p := get_parent()
	while p != null:
		if p.has_signal(&"rebuilt") and p.has_method(&"get_playable_rect"):
			return p as Node3D
		p = p.get_parent()
	return null


func _connect_terrain() -> Node3D:
	var terrain := get_terrain()
	if _connected_terrain != null and _connected_terrain != terrain and is_instance_valid(_connected_terrain):
		if _connected_terrain.is_connected(&"rebuilt", rebuild):
			_connected_terrain.disconnect(&"rebuilt", rebuild)
	_connected_terrain = terrain
	if terrain == null:
		push_warning("TerrainScatter %s: no GeneratedTerrain above it and no terrain_path, so nothing is scattered." % name)
		return null
	if not terrain.is_connected(&"rebuilt", rebuild):
		terrain.connect(&"rebuilt", rebuild)
	return terrain


## Where layer `index` placed its props (this node's space), after the last
## rebuild. For gameplay that wants to know — cover at the boulders, say.
func get_layer_transforms(index: int) -> Array:
	if index < 0 or index >= _layer_transforms.size():
		return []
	return _layer_transforms[index]


## Throws the props away and scatters them again.
func rebuild() -> void:
	_rebuild_queued = false
	_clear_built()
	_layer_transforms.clear()
	_layer_transforms.resize(layers.size())
	for i in _layer_transforms.size():
		_layer_transforms[i] = []
	var terrain := get_terrain()
	if terrain == null:
		push_warning("TerrainScatter %s: no terrain to scatter over." % name)
		return
	var data: Data = terrain.get(&"data")
	if data == null:
		return   # not generated yet; the terrain prints its own hint and emits `rebuilt` once it is
	if layers.is_empty():
		if Engine.is_editor_hint() and not _hinted_empty:
			_hinted_empty = true
			print("TerrainScatter %s: no layers yet — add a TerrainScatterLayer and drop your prop scenes into it." % name)
		return
	var terrain_to_self := global_transform.affine_inverse() * terrain.global_transform
	var playable: Rect2 = terrain.call(&"get_playable_rect")
	var whole := Rect2(-data.width() * 0.5, -data.depth() * 0.5, data.width(), data.depth())
	var root := Node3D.new()
	root.name = "_Scattered"
	root.set_meta(BUILT_META, true)
	add_child(root)
	for i in layers.size():
		var layer := layers[i]
		if layer == null:
			push_warning("TerrainScatter %s: layer slot %d is empty — skipped." % [name, i])
			continue
		if not layer.enabled:
			continue   # switched off on purpose
		_scatter_layer(layer, i, data, playable if layer.inside_boundary else whole, terrain_to_self, root)


func _scatter_layer(layer: Layer, index: int, data: Data, area: Rect2, terrain_to_self: Transform3D, root: Node3D) -> void:
	var variants := _variants(layer)
	if variants.is_empty():
		push_warning("TerrainScatter %s: layer %d has no scenes or meshes with anything to draw — skipped." % [name, index])
		return
	if layer.per_hectare <= 0.0:
		push_warning("TerrainScatter %s: layer %d has per_hectare = 0 — skipped." % [name, index])
		return
	var spacing := 100.0 / sqrt(layer.per_hectare)
	var cols := int(area.size.x / spacing)
	var rows := int(area.size.y / spacing)
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed * 7907 + index * 104729 + 1
	var groves: FastNoiseLite = null
	if layer.clumping > 0.0:
		groves = FastNoiseLite.new()
		groves.seed = random_seed * 31 + index
		groves.frequency = 1.0 / maxf(layer.clump_size, 1.0)
		groves.fractal_octaves = 2
	var min_up := cos(deg_to_rad(layer.max_slope))
	var placed: Array = []
	placed.resize(variants.size())
	for v in variants.size():
		placed[v] = []

	# A jittered grid: one candidate per cell, so props spread evenly without
	# the clumps and gaps of pure random placement.
	for row in rows:
		for col in cols:
			# Every random number is drawn up front, whatever the verdict, so
			# tightening one rule never reshuffles the props that survive it.
			var jx := rng.randf()
			var jz := rng.randf()
			var pick := rng.randi() % variants.size()
			var size_k := rng.randf_range(minf(layer.min_scale, layer.max_scale), maxf(layer.min_scale, layer.max_scale))
			var yaw := rng.randf() * TAU
			var x := area.position.x + (col + jx) * spacing
			var z := area.position.y + (row + jz) * spacing
			if groves != null and groves.get_noise_2d(x, z) * 0.5 + 0.5 < layer.clumping:
				continue
			var n: Vector3 = data.normal_at_local(x, z)
			if n.y < min_up:
				continue
			var y: float = data.height_at_local(x, z)
			if y < layer.min_height or y > layer.max_height:
				continue
			var zone: float = data.zone_at_local(x, z)
			if zone < layer.min_mountain or zone > layer.max_mountain:
				continue
			var paint: Color = data.control_at_local(x, z)
			if maxf(paint.r, maxf(paint.g, paint.b)) > layer.max_paint:
				continue
			if layer.avoid_water and data.water_at_local(x, z):
				continue
			var up := Vector3.UP.slerp(n, layer.align_to_ground).normalized()
			var b := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw if layer.random_yaw else 0.0)
			b = b * Basis.from_scale(Vector3.ONE * size_k)
			placed[pick].append(terrain_to_self * Transform3D(b, Vector3(x, y - layer.sink, z)))

	var origins := PackedVector3Array()
	for v in variants.size():
		var xfs: Array = placed[v]
		if xfs.is_empty():
			continue
		(_layer_transforms[index] as Array).append_array(xfs)
		for part in variants[v]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part.mesh
			mm.instance_count = xfs.size()
			var part_xf: Transform3D = part.xf
			for k in xfs.size():
				mm.set_instance_transform(k, (xfs[k] as Transform3D) * part_xf)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Layer%d_Variant%d" % [index, v]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if layer.cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if part.material != null:
				mmi.material_override = part.material
			if layer.visibility_range_end > 0.0:
				mmi.visibility_range_end = layer.visibility_range_end
			root.add_child(mmi)
		for xf in xfs:
			origins.append((xf as Transform3D).origin)

	if layer.collision_radius > 0.0 and not origins.is_empty():
		# One body, one shared shape, one shape OWNER per prop — no node per
		# tree. Shape owners are what CollisionShape3D uses under the hood, so
		# physics and the navmesh bake see them exactly as they would nodes.
		var shape := CylinderShape3D.new()
		shape.radius = layer.collision_radius
		shape.height = layer.collision_height
		var body := StaticBody3D.new()
		body.name = "Layer%d_Collision" % index
		body.collision_layer = collision_layer
		body.collision_mask = collision_mask
		var lift := Vector3(0.0, layer.collision_height * 0.5, 0.0)
		for o in origins:
			var owner_id := body.create_shape_owner(body)
			body.shape_owner_add_shape(owner_id, shape)
			body.shape_owner_set_transform(owner_id, Transform3D(Basis(), o + lift))
		root.add_child(body)


## Every drawable part of every variant: an Array (one per scene or mesh) of
## Arrays of {mesh, xf, material}. xf places the part relative to the prop.
func _variants(layer: Layer) -> Array:
	var out: Array = []
	for scene in layer.scenes:
		if scene == null:
			continue
		var parts := _mesh_parts(scene)
		if parts.is_empty():
			push_warning("TerrainScatter %s: %s has no MeshInstance3D to draw — left out." % [name, scene.resource_path])
			continue
		out.append(parts)
	for mesh in layer.meshes:
		if mesh != null:
			out.append([{"mesh": mesh, "xf": Transform3D(), "material": null}])
	return out


static func _mesh_parts(scene: PackedScene) -> Array:
	var parts: Array = []
	var inst := scene.instantiate()
	var found: Array[Node] = inst.find_children("*", "MeshInstance3D", true, false)
	if inst is MeshInstance3D:
		found.push_front(inst)
	for node in found:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		# Relative to the scene root: the root's own transform is where the
		# scene would be placed, which is our job, not the model's.
		var xf := Transform3D() if mi == inst else mi.transform
		var p := mi.get_parent() if mi != inst else null
		while p != null and p != inst:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		# MultiMesh has no per-surface overrides, so bake any into a copy of the mesh.
		var mesh: Mesh = mi.mesh
		var overridden := false
		for s in mi.get_surface_override_material_count():
			if mi.get_surface_override_material(s) != null:
				overridden = true
		if overridden and mesh is ArrayMesh:
			mesh = mesh.duplicate()
			for s in mi.get_surface_override_material_count():
				var m := mi.get_surface_override_material(s)
				if m != null:
					(mesh as ArrayMesh).surface_set_material(s, m)
		parts.append({"mesh": mesh, "xf": xf, "material": mi.material_override})
	inst.free()
	return parts


func _clear_built() -> void:
	for child in get_children():
		if child.has_meta(BUILT_META):
			# remove_child first: queue_free is deferred, and a second rebuild
			# in the same frame would otherwise still see the old props.
			remove_child(child)
			child.queue_free()


func _queue_rebuild() -> void:
	if not _ready_done or _rebuild_queued:
		return   # before _ready, _ready builds; if already queued, it runs once
	_rebuild_queued = true
	rebuild.call_deferred()
