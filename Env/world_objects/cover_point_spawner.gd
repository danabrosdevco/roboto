@tool
extends Node3D
class_name CoverPointSpawner

# ─────────────────────────────────────────────
# COVER POINT SPAWNER (Tool Script)
# Uses navmesh edge-walking to find cover points,
# per the approach described at:
# https://gamedev.net/blogs/entry/2276748-cover-system-in-games
#
# Strategy:
#   1. Walk every edge of the NavigationMesh polygons.
#   2. At each edge midpoint, cast two rays perpendicular
#      to the edge in opposite directions.
#   3. If one side hits geometry and the other is open,
#      this is a cover candidate (soldier stands on open
#      side, wall is on the other).
#   4. Validate: cast two rays at crouch/stand height to
#      confirm there's actual cover overhead.
#   5. Cast two "T-pose arm" rays downward to reject
#      edges/cliffs the soldier would fall off.
#   6. Deduplicate by min_spacing.
#
# Requires:
#   - A NavigationRegion3D in the scene (assign in inspector).
#   - FuncGodot map built so collision exists in editor.
#
# Usage:
#   1. Assign your NavigationRegion3D in the inspector.
#   2. Tune parameters.
#   3. Check "Generate" — points appear as green spheres.
#   4. Check "Clear" to redo.
#   5. Save scene — CoverPoints are baked in.
# ─────────────────────────────────────────────

@export_group("References")
@export var navigation_region: NavigationRegion3D

@export_group("Sampling")
## How many points to sample along each nav edge
@export var points_per_edge: int = 3
## Minimum distance between kept cover points
@export var min_spacing: float = 2.0
## Only process edges within this radius of the spawner
@export var sample_radius: float = 80.0

@export_group("Validation Raycasts")
## How far to cast perpendicular to edge to detect wall
@export var wall_detect_length: float = 1.5
## How far to cast perpendicular to edge to check open space
@export var open_detect_length: float = 2.0
## Height for stand-cover check (chest height ~1.2m)
@export var stand_check_height: float = 1.2
## Height for crouch-cover check (~0.6m)
@export var crouch_check_height: float = 0.6
## Arm-span offset for cliff/edge rejection
@export var arm_span_offset: float = 0.4
## Max drop before a point is rejected as a cliff
@export var max_cliff_drop: float = 0.5

@export_group("Visuals")
@export var debug_visualize: bool = true

@export_group("Actions")
@export var generate: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_clear()
			_generate()
		generate = false

@export var clear: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_clear()
		clear = false

# ─────────────────────────────────────────────
# GENERATE
# ─────────────────────────────────────────────
func _generate() -> void:
	if navigation_region == null:
		push_error("CoverPointSpawner: assign a NavigationRegion3D in the inspector.")
		return

	var nav_mesh: NavigationMesh = navigation_region.navigation_mesh
	if nav_mesh == null:
		push_error("CoverPointSpawner: NavigationRegion3D has no NavigationMesh baked.")
		return

	var viewport = get_viewport()
	if viewport == null:
		push_error("CoverPointSpawner: no viewport.")
		return
	var space_state = viewport.find_world_3d().direct_space_state
	if space_state == null:
		push_error("CoverPointSpawner: could not get direct_space_state.")
		return

	var vertices: PackedVector3Array = nav_mesh.get_vertices()
	var kept: Array[Vector3] = []
	var spawned: int = 0
	var origin: Vector3 = global_position

	# Walk every polygon in the nav mesh
	for poly_idx in nav_mesh.get_polygon_count():
		var poly: PackedInt32Array = nav_mesh.get_polygon(poly_idx)
		var vert_count: int = poly.size()

		# Walk each edge of this polygon
		for i in vert_count:
			var a: Vector3 = navigation_region.global_transform * vertices[poly[i]]
			var b: Vector3 = navigation_region.global_transform * vertices[poly[(i + 1) % vert_count]]

			# Skip edges outside our sample radius
			var edge_mid: Vector3 = (a + b) * 0.5
			if edge_mid.distance_to(origin) > sample_radius:
				continue

			# Skip very short edges (artifact-prone per the article)
			if a.distance_to(b) < 0.5:
				continue

			# Sample points_per_edge evenly along this edge
			for s in points_per_edge:
				var t: float = (float(s) + 0.5) / float(points_per_edge)
				var sample_pos: Vector3 = a.lerp(b, t)

				# ── Step 1: perpendicular check ──
				# Cast perpendicular to edge in both directions.
				# We want one side blocked (wall) and one open (soldier stands here).
				var edge_dir: Vector3 = (b - a).normalized()
				var perp: Vector3 = edge_dir.cross(Vector3.UP).normalized()

				var wall_hit: bool = _raycast(space_state, sample_pos + Vector3.UP * stand_check_height, perp, wall_detect_length)
				var open_hit: bool = _raycast(space_state, sample_pos + Vector3.UP * stand_check_height, -perp, open_detect_length)

				# Flip if needed — we want wall_side=true, open_side=false
				var cover_dir: Vector3
				if wall_hit and not open_hit:
					cover_dir = -perp   # soldier faces away from wall
				elif open_hit and not wall_hit:
					# Swap: the geometry is on the other side
					cover_dir = perp
					wall_hit = open_hit
				else:
					# Both blocked or both open — not a cover edge
					continue

				# ── Step 2: stand/crouch cover validation ──
				# The wall must actually block at stand height.
				# Optionally check crouch height for crouch-cover tagging.
				var stand_covered: bool = _raycast(space_state, sample_pos + Vector3.UP * stand_check_height, -cover_dir, wall_detect_length)
				if not stand_covered:
					continue
				var crouch_covered: bool = _raycast(space_state, sample_pos + Vector3.UP * crouch_check_height, -cover_dir, wall_detect_length)

				# ── Step 3: cliff/edge rejection ──
				# Cast two downward rays offset by arm_span to either side of the soldier.
				var left_ok: bool  = _cliff_check(space_state, sample_pos + cover_dir.cross(Vector3.UP).normalized() * arm_span_offset)
				var right_ok: bool = _cliff_check(space_state, sample_pos - cover_dir.cross(Vector3.UP).normalized() * arm_span_offset)
				if not left_ok or not right_ok:
					continue

				# ── Step 4: spacing dedup ──
				var too_close := false
				for kept_pos in kept:
					if sample_pos.distance_to(kept_pos) < min_spacing:
						too_close = true
						break
				if too_close:
					continue

				kept.append(sample_pos)
				_spawn_cover_point(sample_pos, cover_dir, crouch_covered)
				spawned += 1

	print("CoverPointSpawner: placed %d cover points from %d nav polygons." % [
		spawned, nav_mesh.get_polygon_count()
	])

# ─────────────────────────────────────────────
# RAYCAST HELPERS
# ─────────────────────────────────────────────
func _raycast(space_state: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, length: float) -> bool:
	var query = PhysicsRayQueryParameters3D.create(from, from + dir * length)
	return not space_state.intersect_ray(query).is_empty()

func _cliff_check(space_state: PhysicsDirectSpaceState3D, pos: Vector3) -> bool:
	# Returns true if ground is within max_cliff_drop below pos
	var from = pos + Vector3.UP * 0.1
	var to   = pos + Vector3.DOWN * (max_cliff_drop + 0.2)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	return not space_state.intersect_ray(query).is_empty()

# ─────────────────────────────────────────────
# CLEAR
# ─────────────────────────────────────────────
func _clear() -> void:
	for child in get_children():
		child.free()
	print("CoverPointSpawner: cleared.")

# ─────────────────────────────────────────────
# SPAWN
# ─────────────────────────────────────────────
func _spawn_cover_point(pos: Vector3, cover_dir: Vector3, is_crouch_cover: bool) -> void:
	var cp = CoverPoint.new()
	cp.position = pos
	cp.name = "CoverPoint_%d" % get_child_count()
	# Store the direction the soldier faces when using this cover
	cp.set_meta("cover_direction", cover_dir)
	cp.set_meta("is_crouch_cover", is_crouch_cover)
	add_child(cp)
	cp.owner = get_tree().edited_scene_root

	if debug_visualize:
		# Sphere marker
		var mesh_inst = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 0.18
		sphere.height = 0.36
		mesh_inst.mesh = sphere
		var mat = StandardMaterial3D.new()
		# Green = stand cover, yellow = crouch-only cover
		mat.albedo_color = Color(0.0, 1.0, 0.4, 0.8) if not is_crouch_cover else Color(1.0, 0.9, 0.0, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_inst.material_override = mat
		cp.add_child(mesh_inst)
		mesh_inst.owner = get_tree().edited_scene_root

		# Direction arrow (shows which way soldier faces)
		# Build rotation from basis instead of look_at — node isn't in tree yet
		var arrow = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.05, 0.05, 0.4)
		arrow.mesh = box
		arrow.position = cover_dir * 0.3 + Vector3.UP * 0.18
		var forward := cover_dir.normalized()
		var up := Vector3.UP
		# If cover_dir is nearly vertical, pick a different up vector
		if abs(forward.dot(up)) > 0.99:
			up = Vector3.FORWARD
		var right := forward.cross(up).normalized()
		up = right.cross(forward).normalized()
		# BoxMesh points along -Z by default, so use -forward as Z axis
		arrow.transform.basis = Basis(right, up, -forward)
		var arrow_mat = StandardMaterial3D.new()
		arrow_mat.albedo_color = Color(1.0, 0.3, 0.1)
		arrow.material_override = arrow_mat
		cp.add_child(arrow)
		arrow.owner = get_tree().edited_scene_root
