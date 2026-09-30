extends RefCounted

# ─────────────────────────────────────────────
# WATER OUT OF THE NAVMESH
#
# A river is only a river if the squad has to cross it on something. The navmesh
# baker has no idea water is drawn over the bed — it sees gently sloping ground
# and paves it — so robots wade the Allegheny, the chokepoints stop being
# chokepoints and every bridge becomes decoration. Pittsburgh reached all eight
# hardpoints and the exit with sixteen of its seventeen bridges taken out.
#
# This takes the bed back out after the fact. AFTER, deliberately: carving it
# during the bake would mean teaching Recast about the water, which only holds
# until the next bake, and the expected workflow is a human pressing Bake
# NavigationMesh in the editor (docs/TERRAIN.md). Stripping at load holds
# however the navmesh was made, and it covers the levels that bake from the
# terrain's heightmap colliders as well as the ones that bake from its chunk
# meshes.
#
# It reads TerrainData's `water` mask, which is exact and river-specific — one
# byte per sample, set where a water surface is drawn. The `hollow` paint
# channel would be wrong here: trenches, craters and gullies all write it too.
# ─────────────────────────────────────────────

## A polygon this far above the water surface is a bridge over the river, not
## the bed of it. Every bridge in the kit stands its deck higher than this.
const FREEBOARD := 0.5


## Drops every navmesh polygon lying in `terrain`'s water from `region`, and
## returns how many went. The region keeps its bake settings — the mesh is
## duplicated, not rebuilt from nothing, and duplicated rather than edited in
## place because a navmesh embedded in a scene is shared by every instance of
## it.
static func strip(region: NavigationRegion3D, terrain: Node3D) -> int:
	var data = terrain.data
	if data == null or not data.has_water():
		push_warning("water_navmesh: %s has no water mask, so nothing was stripped — is the terrain generated?" % terrain.name)
		return 0
	var mesh := region.navigation_mesh
	if mesh == null:
		push_warning("water_navmesh: %s has no navigation mesh, so its river bed stays walkable — bake it" % region.name)
		return 0
	var verts := mesh.get_vertices()
	if verts.is_empty():
		push_warning("water_navmesh: %s's navigation mesh is empty, so its river bed stays walkable — bake it" % region.name)
		return 0

	# Which vertices stand in the river. Done once: a vertex is shared by
	# several polygons, and the mask lookup is the expensive part.
	var to_world := region.global_transform
	var ceiling: float = data.water_level + FREEBOARD
	var wet := {}
	for i in verts.size():
		var world: Vector3 = to_world * verts[i]
		if world.y >= ceiling:
			continue
		var local := terrain.to_local(world)
		if data.water_at_local(local.x, local.z):
			wet[i] = true
	if wet.is_empty():
		return 0

	# A polygon goes if it so much as touches the water. Dropping only the ones
	# wholly under it would leave the big merged polygons that reach from one
	# bank to the other, and one of those is a ford across the whole river.
	var kept := mesh.duplicate() as NavigationMesh
	kept.clear_polygons()
	kept.set_vertices(verts)
	var dropped := 0
	for p in mesh.get_polygon_count():
		var poly := mesh.get_polygon(p)
		var in_river := false
		for idx in poly:
			if wet.has(idx):
				in_river = true
				break
		if in_river:
			dropped += 1
		else:
			kept.add_polygon(poly)
	if dropped == 0:
		return 0
	region.navigation_mesh = kept
	return dropped
