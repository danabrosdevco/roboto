@tool
@icon("res://addons/plenticons/icons/64x-hidpi/3d/cone-gray.png")
class_name GeneratedTerrain
extends Node3D

# ─────────────────────────────────────────────
# GENERATED TERRAIN — a big heightfield level base, made from a recipe.
#
# WORKFLOW (docs/TERRAIN.md has the long version):
#   1. Add this node to a level, under the NavigationRegion3D like the valley's
#      terrain.fbx. Save the scene — the data is saved next to it.
#   2. Assign a recipe (Env/terrain/presets/) and tick Generate Terrain. To
#      decide the layout yourself, paint a sketch and put it in the recipe's
#      Sketch slot (see TerrainSketch and Env/terrain/sketches/).
#   3. Shape it: TerrainStamp children flatten pads for buildings, raise, dig
#      and crater; TerrainPath children cut roads, trenches and riverbeds.
#      Tick Generate Terrain again after changes (or turn on auto_regenerate).
#   4. Place buildings and props on it — Snap to Floor and drag-and-drop work,
#      because the collision exists in the editor too. Then bake navigation.
#
# WHAT IS SAVED: the heights, in a TerrainData .res file. Chunks and collision
# are rebuilt from it every time the scene loads, and are never written into
# the .tscn — they carry no owner, so the scene file stays small.
#
# The built nodes are ordinary children, NOT internal ones: NavigationRegion3D
# only parses get_children(), and an internal child would leave the terrain out
# of the navmesh bake without a word.
#
# Everything is built synchronously in _ready. world.gd drops the player at the
# spawn point straight after add_child; collision built a frame later would let
# them fall through the map.
# ─────────────────────────────────────────────

const Recipe := preload("res://Env/terrain/terrain_recipe.gd")
const Data := preload("res://Env/terrain/terrain_data.gd")
const Generator := preload("res://Env/terrain/terrain_generator.gd")
const MeshBuilder := preload("res://Env/terrain/terrain_mesh_builder.gd")
const DEFAULT_MATERIAL := preload("res://Env/terrain/terrain_material.tres")
const DEFAULT_WATER_MATERIAL := preload("res://Env/terrain/water_material.tres")

## Marks nodes this script built, so a rebuild — or a rebuild after the node was
## duplicated or its script reloaded — can find and remove every one of them.
const BUILT_META := &"_generated_terrain_built"
## Seconds of quiet before auto_regenerate runs, so dragging a slider or a stamp
## does not regenerate on every intermediate value.
const AUTO_DELAY := 0.6

## Emitted after the chunks and collision have been (re)built. TerrainScatter
## listens so props follow the ground when it changes.
signal rebuilt

## The generation settings. Assigning a preset in the editor makes a local copy,
## so tuning one level never edits the preset every other level starts from.
@export var recipe: Recipe:
	set(value):
		if value != null and _ready_done and Engine.is_editor_hint() and _is_file_resource(value):
			print("GeneratedTerrain %s: made a local copy of %s, so tuning this level never edits the preset." % [name, value.resource_path])
			value = value.duplicate()
		if recipe != null and recipe.changed.is_connected(_on_recipe_changed):
			recipe.changed.disconnect(_on_recipe_changed)
		recipe = value
		if recipe != null and Engine.is_editor_hint():
			recipe.changed.connect(_on_recipe_changed)
		_base_cache.clear()
		_schedule_auto()

## The baked result. Written by Generate Terrain; don't edit it by hand.
@export var data: Data:
	get:
		return _data
	set(value):
		_data = value
		_queue_rebuild()

@export_group("Generate")
## Tick to run the recipe and every stamp and path under this node, save the
## result and rebuild. (A checkbox standing in for a button — Godot 4.3 has no
## inspector buttons without an editor plugin.)
@export var generate_terrain: bool = false:
	set(value):
		if value and _ready_done:
			generate()
## Regenerate by itself shortly after any recipe, stamp or path change. Keep it
## off for big maps with erosion on: each run can take several seconds.
@export var auto_regenerate: bool = false
## Where the baked data is saved. Empty means terrain_data/<scene>_<node>.res
## beside the scene, which is what you want unless two scenes share one terrain.
@export_file("*.res") var data_path: String = ""
## Tick to write the terrain out as a .glb beside its data — a plain full-detail
## mesh for Blender or anything else that wants the shape.
@export var export_glb: bool = false:
	set(value):
		if value and _ready_done:
			export_to_glb()

@export_group("Rendering")
@export var material: Material = DEFAULT_MATERIAL:
	set(value):
		material = value
		_apply_render_settings()
@export var cast_shadows: bool = true:
	set(value):
		cast_shadows = value
		_apply_render_settings()
## Above 1 keeps full detail further out; below 1 drops it sooner.
@export_range(0.1, 8.0, 0.05) var lod_bias: float = 1.0:
	set(value):
		lod_bias = value
		_apply_render_settings()
## Draw the surface of water painted in the sketch. Purely visual: water never
## touches navigation or collision (see _build_water).
@export var show_water: bool = true:
	set(value):
		show_water = value
		if _ready_done:
			_build_water()
@export var water_material: Material = DEFAULT_WATER_MATERIAL:
	set(value):
		water_material = value
		if _ready_done:
			_build_water()

@export_group("Editor")
## Outline the building lots of painted urban areas in the editor viewport:
## blue for clean lots, orange for rubble. Never shown in the game.
@export var show_lots: bool = true:
	set(value):
		show_lots = value
		_queue_rebuild()

@export_group("Collision")
@export var collision_enabled: bool = true:
	set(value):
		collision_enabled = value
		_queue_rebuild()
@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value
		_queue_rebuild()
@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		collision_mask = value
		_queue_rebuild()
## Invisible walls around the playable area, so nobody climbs the border
## mountains and walks off the edge of the world.
@export var boundary_walls: bool = true:
	set(value):
		boundary_walls = value
		_queue_rebuild()
## How far in from the map edge the walls stand. Put them where the mountains
## get too steep to matter.
@export_range(0.0, 1000.0, 1.0, "suffix:m") var boundary_inset: float = 60.0:
	set(value):
		boundary_inset = value
		_queue_rebuild()
## How far above the highest ground the walls reach.
@export_range(5.0, 1000.0, 1.0, "suffix:m") var boundary_headroom: float = 80.0:
	set(value):
		boundary_headroom = value
		_queue_rebuild()

## At runtime, a terrain with no baked data generates from its recipe rather
## than leaving the player nothing to stand on. tools/terrain_bake.gd turns this
## off, because it is about to generate properly and would otherwise do it twice.
var generate_missing_at_runtime := true

var _data: Data
# Every chunk mesh, held here as well as by its MeshInstance3D. Headless Godot
# 4.3 (the dummy renderer the tests, smoke run and bake tool use) prints
# "mesh_get_surface_count: Parameter "m" is null" for every MeshInstance3D that
# is freed holding the LAST reference to a script-made mesh. This script's
# members outlive its children, so with these refs the meshes always die
# after the nodes that drew them, and level unloads stay quiet.
var _chunk_meshes: Array[Mesh] = []
# Water surfaces are RenderingServer instances, not nodes. NavigationRegion3D
# parses every MeshInstance3D beneath it, and a water mesh node would hand the
# navmesh bake a flat walkable sheet at the waterline: robots striding across
# lakes. Water is meant to be visual only, so it is kept out of the node tree.
var _water_instances: Array[RID] = []
var _water_meshes: Array[Mesh] = []   # outlive the instances; see _chunk_meshes
var _ready_done := false
var _rebuild_queued := false
var _regen_ticket := 0
var _hinted_empty := false
# Pre-modifier terrain from the last generate, keyed by recipe signature.
# Editor-only speed-up; never saved.
var _base_cache := {}


func _ready() -> void:
	_ready_done = true
	# The water instances live outside the node tree, so they have to be told
	# when the terrain moves.
	set_notify_transform(true)
	if recipe != null and Engine.is_editor_hint() and not recipe.changed.is_connected(_on_recipe_changed):
		recipe.changed.connect(_on_recipe_changed)
	rebuild()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			for rid in _water_instances:
				RenderingServer.instance_set_transform(rid, global_transform)
		NOTIFICATION_VISIBILITY_CHANGED:
			for rid in _water_instances:
				RenderingServer.instance_set_visible(rid, is_visible_in_tree())
		NOTIFICATION_ENTER_WORLD:
			if _ready_done:
				_build_water()   # back in a world after a reparent; _ready does the first build
		NOTIFICATION_EXIT_WORLD, NOTIFICATION_PREDELETE:
			_clear_water()


# ── Building ─────────────────────────────────────────────────────────────────

## Throws away the built chunks and collision and builds them again from
## `data`. Cheap next to generating: no noise, no erosion.
func rebuild() -> void:
	_rebuild_queued = false
	_clear_built()
	if _data == null:
		if Engine.is_editor_hint():
			# A fresh node has no data yet. That is its normal first state, so
			# say it once as a hint rather than warning on every rebuild.
			if not _hinted_empty:
				_hinted_empty = true
				print("GeneratedTerrain %s: no terrain yet — assign a recipe and tick Generate Terrain." % name)
			return
		if not generate_missing_at_runtime:
			print("GeneratedTerrain %s: no data yet; waiting for an explicit generate()." % name)
			return
		if recipe == null:
			push_error("GeneratedTerrain %s: no data and no recipe, so there is no ground here at all." % get_path())
			return
		push_warning("GeneratedTerrain %s: no baked data — generating from the recipe at runtime, which is slow and ignores anything placed against the editor's terrain. Tick Generate Terrain in the editor and save." % get_path())
		_data = Generator.generate(recipe, _collect_modifiers())
		if _data == null:
			return   # the generator has already said why
	if not _data.is_valid(str(name)):
		return   # is_valid() has already said which invariant broke

	var root := Node3D.new()
	root.name = "_Built"
	root.set_meta(BUILT_META, true)
	add_child(root)
	_build_render(root)
	if collision_enabled:
		_build_collision(root)
	if boundary_walls:
		_build_boundary(root)
	_build_water()
	_build_lots_overlay(root)
	rebuilt.emit()


func _build_render(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Chunks"
	root.add_child(holder)
	var normals := MeshBuilder.compute_normals(_data)
	var lod_indices := MeshBuilder.build_lod_indices(_data.chunk_cells, _data.lod_count)
	var skirt := MeshBuilder.skirt_depth(_data)
	for cz in _data.chunks_z():
		for cx in _data.chunks_x():
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.mesh = MeshBuilder.build_chunk(_data, normals, cx, cz, lod_indices, skirt)
			_chunk_meshes.append(mi.mesh)
			holder.add_child(mi)
	_apply_render_settings()


func _build_collision(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	for tile in MeshBuilder.build_collision_tiles(_data):
		var shape_node := CollisionShape3D.new()
		shape_node.name = tile.name
		shape_node.shape = tile.shape
		shape_node.position = tile.position
		shape_node.scale = Vector3.ONE * float(tile.scale)
		body.add_child(shape_node)
	root.add_child(body)


func _build_boundary(root: Node3D) -> void:
	var rect := get_playable_rect()
	var bottom := _data.min_height - 20.0
	var top := _data.max_height + boundary_headroom
	var height := top - bottom
	var mid_y := (top + bottom) * 0.5
	const THICK := 4.0
	var body := StaticBody3D.new()
	body.name = "Boundary"
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	var span_x := rect.size.x + THICK * 2.0
	var span_z := rect.size.y + THICK * 2.0
	var cx := rect.get_center().x
	var cz := rect.get_center().y
	var walls := [
		[Vector3(cx, mid_y, rect.position.y - THICK * 0.5), Vector3(span_x, height, THICK)],
		[Vector3(cx, mid_y, rect.end.y + THICK * 0.5), Vector3(span_x, height, THICK)],
		[Vector3(rect.position.x - THICK * 0.5, mid_y, cz), Vector3(THICK, height, span_z)],
		[Vector3(rect.end.x + THICK * 0.5, mid_y, cz), Vector3(THICK, height, span_z)],
	]
	for w in walls:
		var box := BoxShape3D.new()
		box.size = w[1]
		var shape_node := CollisionShape3D.new()
		shape_node.shape = box
		shape_node.position = w[0]
		body.add_child(shape_node)
	root.add_child(body)


func _build_water() -> void:
	_clear_water()
	if not show_water or _data == null or not _data.has_water():
		return   # no painted water, or switched off on purpose
	if not is_inside_tree():
		return   # ENTER_WORLD builds it when the node arrives
	var scenario := get_world_3d().scenario
	var mat := water_material
	if mat == null:
		push_warning("GeneratedTerrain %s: no water material set — using the default." % name)
		mat = DEFAULT_WATER_MATERIAL
	for cz in _data.chunks_z():
		for cx in _data.chunks_x():
			var mesh := MeshBuilder.build_water_chunk(_data, cx, cz)
			if mesh != null:
				_add_water_instance(mesh, scenario, mat)
	var apron := MeshBuilder.build_water_apron(_data)
	if apron != null:
		_add_water_instance(apron, scenario, mat)


func _add_water_instance(mesh: Mesh, scenario: RID, mat: Material) -> void:
	var rid := RenderingServer.instance_create2(mesh.get_rid(), scenario)
	RenderingServer.instance_set_transform(rid, global_transform)
	RenderingServer.instance_geometry_set_material_override(rid, mat.get_rid())
	RenderingServer.instance_geometry_set_cast_shadows_setting(rid, RenderingServer.SHADOW_CASTING_SETTING_OFF)
	RenderingServer.instance_set_visible(rid, is_visible_in_tree())
	_water_instances.append(rid)
	_water_meshes.append(mesh)


func _clear_water() -> void:
	for rid in _water_instances:
		RenderingServer.free_rid(rid)
	_water_instances.clear()
	# Only now the meshes: freed after the instances that drew them.
	_water_meshes.clear()


## How many water surfaces are drawn (chunks with water, plus the open-sea
## apron). For tests and debugging.
func get_water_surface_count() -> int:
	return _water_instances.size()


# Editor-only outlines of the building lots, all in one line surface: a mesh
# has at most 256 surfaces, and a big painted town has more lots than that.
func _build_lots_overlay(root: Node3D) -> void:
	if not (Engine.is_editor_hint() and show_lots) or _data.lots.is_empty():
		return   # only drawn in the editor, and only when there are lots to show
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for lot in _data.lots:
		var centre: Vector2 = lot.centre
		var half: Vector2 = lot.size * 0.5
		var turn := Basis(Vector3.UP, float(lot.angle))
		var y := float(lot.height) + 0.2
		var corners: Array[Vector3] = []
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p := turn * Vector3(c.x * half.x, 0.0, c.y * half.y)
			corners.append(Vector3(centre.x + p.x, y, centre.y + p.z))
		var colour := Color(1.0, 0.55, 0.2) if lot.ruined else Color(0.4, 0.9, 1.0)
		for e in 4:
			im.surface_set_color(colour)
			im.surface_add_vertex(corners[e])
			im.surface_set_color(colour)
			im.surface_add_vertex(corners[(e + 1) % 4])
	im.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	var mi := MeshInstance3D.new()
	mi.name = "LotOutlines"
	mi.mesh = im
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _apply_render_settings() -> void:
	var holder := get_node_or_null(^"_Built/Chunks")
	if holder == null:
		return   # nothing built yet; rebuild() calls this again when it is
	var mat := material
	if mat == null:
		push_warning("GeneratedTerrain %s: no material set — using the default terrain material." % name)
		mat = DEFAULT_MATERIAL
	for mi in holder.get_children():
		if mi is MeshInstance3D:
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.lod_bias = lod_bias


func _clear_built() -> void:
	_clear_water()
	for child in get_children():
		if child.has_meta(BUILT_META):
			# Detach the meshes while _chunk_meshes still holds them (see there).
			for mi in child.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).mesh = null
			# remove_child first: queue_free is deferred, and a second rebuild
			# in the same frame would otherwise still see the old chunks.
			remove_child(child)
			child.queue_free()
	_chunk_meshes.clear()


func _queue_rebuild() -> void:
	if not _ready_done or _rebuild_queued:
		return   # before _ready, _ready builds; if already queued, it runs once
	_rebuild_queued = true
	rebuild.call_deferred()


# ── Generating ───────────────────────────────────────────────────────────────

## Runs the recipe with every TerrainStamp and TerrainPath under this node,
## saves the result and rebuilds. Callable from code and tools/terrain_bake.gd,
## not only from the inspector.
func generate() -> bool:
	if recipe == null:
		push_warning("GeneratedTerrain %s: no recipe — assign one from Env/terrain/presets/ first." % name)
		return false
	var path := resolve_data_path()
	if path == "":
		push_warning("GeneratedTerrain %s: save the scene first — the terrain data is stored next to it." % name)
		return false
	var result: Data = Generator.generate(recipe, _collect_modifiers(), _base_cache)
	if result == null:
		return false   # the generator has already said why
	if not _save(result, path):
		return false
	print("GeneratedTerrain %s → %s\n    %s" % [name, path, _data.generated_info])
	rebuild()
	# `data` changed behind the inspector's back (the first generate points it
	# at a brand-new file); without this it keeps showing <empty> until reselected.
	notify_property_list_changed()
	return true


## Where Generate saves: data_path if set, else terrain_data/ beside the scene.
## Worked out from the CURRENT scene, never from data.resource_path, so a
## duplicated level gets a file of its own instead of silently overwriting the
## original level's terrain.
func resolve_data_path() -> String:
	if data_path != "":
		return data_path
	var scene_path := owner.scene_file_path if owner != null else scene_file_path
	if scene_path == "":
		return ""
	return "%s/terrain_data/%s_%s.res" % [scene_path.get_base_dir(),
			scene_path.get_file().get_basename(), String(name).to_snake_case()]


func _save(result: Data, path: String) -> bool:
	var target := result
	if _data != null and _data.resource_path == path:
		# That instance is what every open scene points at: update it in place
		# rather than orphaning it.
		_data.copy_from(result)
		target = _data
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var made := DirAccess.make_dir_recursive_absolute(dir)
		if made != OK:
			push_error("GeneratedTerrain %s: could not create %s (%s)." % [name, dir, error_string(made)])
			return false
	var err := ResourceSaver.save(target, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("GeneratedTerrain %s: could not save %s (%s)." % [name, path, error_string(err)])
		return false
	if target != _data:
		if _data != null and _data.resource_path != "" and _data.resource_path != path:
			print("GeneratedTerrain %s: terrain now saved to %s; %s is no longer used by this node." % [name, path, _data.resource_path])
		target.take_over_path(path)
		_data = target
	_refresh_editor_filesystem()
	return true


## Writes the terrain as a .glb beside its data file.
func export_to_glb() -> bool:
	if _data == null:
		push_warning("GeneratedTerrain %s: nothing to export — generate the terrain first." % name)
		return false
	var base := resolve_data_path()
	if base == "":
		push_warning("GeneratedTerrain %s: save the scene first — the .glb is written next to it." % name)
		return false
	var path := base.get_basename() + ".glb"
	var scene := Node3D.new()
	scene.name = String(name)
	var mi := MeshInstance3D.new()
	mi.name = "terrain"
	mi.mesh = MeshBuilder.build_export_mesh(_data)
	scene.add_child(mi)
	mi.owner = scene
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(scene, state)
	if err == OK:
		err = doc.write_to_filesystem(state, path)
	scene.free()
	if err != OK:
		push_error("GeneratedTerrain %s: .glb export to %s failed (%s)." % [name, path, error_string(err)])
		return false
	print("GeneratedTerrain %s: exported %s" % [name, path])
	_refresh_editor_filesystem()
	return true


func _collect_modifiers() -> Array:
	var out: Array = []
	_collect_from(self, out)
	return out


# Depth-first in tree order, so a modifier lower in the Scene dock wins.
# Folders (any plain node) are searched; another terrain's modifiers are not.
func _collect_from(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child.has_meta(BUILT_META) or child.get_script() == get_script():
			continue
		if child.has_method(&"to_terrain_modifier"):
			var m: Variant = child.call(&"to_terrain_modifier", self)
			if m is Dictionary and not (m as Dictionary).is_empty():
				out.append(m)
		_collect_from(child, out)


func _on_recipe_changed() -> void:
	_base_cache.clear()
	_schedule_auto()


## TerrainStamp and TerrainPath call this when they move or change.
func _on_terrain_modifier_changed() -> void:
	_schedule_auto()


func _schedule_auto() -> void:
	if not (auto_regenerate and _ready_done and Engine.is_editor_hint() and is_inside_tree()):
		return   # auto-regenerate is an editor convenience and it is off
	_regen_ticket += 1
	var ticket := _regen_ticket
	await get_tree().create_timer(AUTO_DELAY).timeout
	if ticket != _regen_ticket or not is_inside_tree():
		return   # a newer change arrived while waiting; its own timer runs it
	generate()


func _is_file_resource(res: Resource) -> bool:
	return res.resource_path != "" and not res.resource_path.contains("::")


func _refresh_editor_filesystem() -> void:
	if not Engine.is_editor_hint():
		return   # outside the editor there is no FileSystem dock to refresh
	# Looked up through Engine rather than named: EditorInterface does not exist
	# in an exported game, and naming it would stop this script compiling there.
	if not Engine.has_singleton(&"EditorInterface"):
		push_warning("GeneratedTerrain: EditorInterface not found; the FileSystem dock will catch up on its next scan.")
		return
	var fs: Object = Engine.get_singleton(&"EditorInterface").call(&"get_resource_filesystem")
	if fs != null:
		fs.call(&"scan")


# ── Queries ──────────────────────────────────────────────────────────────────
# World space in, world space out. Off the map these return NAN / ZERO rather
# than a plausible number, so "no ground here" can never pass for y = 0.

## Height of the ground under a world position, or NAN off the map.
func get_height_at(world_pos: Vector3) -> float:
	if _data == null:
		return NAN
	var p := to_local(world_pos)
	if not _data.contains_local(p.x, p.z):
		return NAN
	return to_global(Vector3(p.x, _data.height_at_local(p.x, p.z), p.z)).y


## The point on the ground straight below (or above) a world position.
## Returns the input unchanged, with a warning, off the map.
func get_ground_point(world_pos: Vector3) -> Vector3:
	var y := get_height_at(world_pos)
	if is_nan(y):
		push_warning("GeneratedTerrain %s: %s is off the map; left where it was." % [name, world_pos])
		return world_pos
	return Vector3(world_pos.x, y, world_pos.z)


## Ground normal under a world position (world space), or ZERO off the map.
func get_normal_at(world_pos: Vector3) -> Vector3:
	if _data == null:
		return Vector3.ZERO
	var p := to_local(world_pos)
	if not _data.contains_local(p.x, p.z):
		return Vector3.ZERO
	return (global_basis * _data.normal_at_local(p.x, p.z)).normalized()


## 0 on open ground … 1 on the border mountains. NAN off the map.
func get_zone_at(world_pos: Vector3) -> float:
	if _data == null:
		return NAN
	var p := to_local(world_pos)
	if not _data.contains_local(p.x, p.z):
		return NAN
	return _data.zone_at_local(p.x, p.z)


## Paint under a world position: r road, g scorch, b pad, a hollow. Clear
## (all zero) off the map.
func get_paint_at(world_pos: Vector3) -> Color:
	if _data == null:
		return Color(0, 0, 0, 0)
	var p := to_local(world_pos)
	if not _data.contains_local(p.x, p.z):
		return Color(0, 0, 0, 0)
	return _data.control_at_local(p.x, p.z)


## Building lots from grey (urban) sketch paint, in world space. Each is
## {transform: Transform3D — centred on the levelled block, X along the street
## grid; size: Vector2 — metres along that X and Z; ruined: bool}. Empty when
## the sketch paints no urban ground.
func get_lots() -> Array:
	var out: Array = []
	if _data == null:
		return out
	for lot in _data.lots:
		var centre: Vector2 = lot.centre
		var local := Transform3D(Basis(Vector3.UP, float(lot.angle)), Vector3(centre.x, float(lot.height), centre.y))
		out.append({"transform": global_transform * local, "size": lot.size, "ruined": lot.ruined})
	return out


## The area inside the boundary walls, in LOCAL x/z (Rect2.position is the
## -x/-z corner). The whole map when there is no data yet.
func get_playable_rect() -> Rect2:
	if _data == null:
		return Rect2()
	var w := _data.width()
	var d := _data.depth()
	var inset := clampf(boundary_inset, 0.0, minf(w, d) * 0.45)
	return Rect2(-w * 0.5 + inset, -d * 0.5 + inset, w - inset * 2.0, d - inset * 2.0)
