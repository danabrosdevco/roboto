@tool
extends Node
class_name FactionLivery

# ─────────────────────────────────────────────────────────────
# FACTION LIVERY  (GL Compatibility safe)
#
# Add as a child of any robot scene (soldier_shotgun.tscn etc).
# Reads `faction` off the parent and assigns the matching shared
# material to every mesh below it.
#
# Compatibility has no per-instance uniforms, so instead of one
# material per robot we cache ONE MATERIAL PER FACTION and hand
# the same resource to every robot of that faction. Four
# materials for the whole game. Batching survives within a
# faction, which is how squads are grouped anyway.
#
# Per-robot state (the `shutdown` fade on death) is the one thing
# a shared material can't express, so that path duplicates on
# demand — see set_shutdown().
# ─────────────────────────────────────────────────────────────

const COLORS := {
	Enums.Factions.PLAYER:  Color(0.55, 0.90, 0.95),  # pale cyan
	Enums.Factions.ALLIED:  Color(0.20, 0.65, 0.80),  # teal
	Enums.Factions.ENEMY:   Color(0.70, 0.35, 0.02),  # amber
	Enums.Factions.NEUTRAL: Color(0.62, 0.60, 0.55),  # bare grey
}

# Shared cache, keyed by "<base material id>:<faction>".
static var _cache: Dictionary = {}

## The faction_metal material with your texture already assigned.
## This is the template — it is never modified, only duplicated.
@export var base_material: ShaderMaterial

## Leave empty to auto-discover every mesh under the parent.
@export var pieces: Array[Node3D] = []

@export_range(0.0, 1.0) var paint_blend: float = 0.40
@export_range(0.0, 6.0) var marker_energy: float = 2.2

## Preview a faction in the editor without a parent Enemy.
@export var editor_preview_faction: Enums.Factions = Enums.Factions.ENEMY

var _meshes: Array[GeometryInstance3D] = []


func _ready() -> void:
	_collect()
	apply(_resolve_faction())


func _resolve_faction() -> Enums.Factions:
	if Engine.is_editor_hint():
		return editor_preview_faction
	var p := get_parent()
	if p != null and "faction" in p:
		return p.faction
	return Enums.Factions.NEUTRAL


func _collect() -> void:
	_meshes.clear()
	if not pieces.is_empty():
		for n in pieces:
			_gather(n)
	else:
		var p := get_parent()
		if p != null:
			_gather(p)


func _gather(node: Node) -> void:
	if node == null:
		return
	# EVERY CSG SHAPE, not only CSGMesh3D. A CSG primitive sitting straight
	# under the rig — the nest's plinth, body and cap, the mechanic's tanks — is
	# a render root of its own and needs its own coat; only CSGMesh3D was ever
	# collected, so those stood in the stock material on every side. (A
	# primitive nested INSIDE another CSG shape is merged into that root and
	# painted through it, so collecting it changes nothing — which saves this
	# from having to know which is which.)
	#
	# Ordinary meshes come in the same way: the robots built from primitives are
	# CSG, the ones built from a GLB — the quadcopter bomber — are
	# MeshInstance3D, and collecting only CSG meant its listed pieces were
	# walked past every time. It flew in the model's own colours, untinted, on
	# both sides.
	if node is CSGShape3D or node is MeshInstance3D:
		_meshes.append(node)
	for child in node.get_children():
		_gather(child)


## Pieces that take the faction COLOUR but keep their own SURFACE.
##
## The default is one material for every piece of a robot, which is what keeps
## four materials covering the whole game. That is right for a hull — every
## panel of it is the same steel — and wrong for a hat: a beret painted with the
## hull's albedo is a beret made of concrete. So a piece may name its own base
## material, and gets the faction's colour applied to THAT instead.
##
## It costs one more cache entry per faction per base, which is four materials
## for each distinct surface. The sharing that matters — every robot of a
## faction drawing from one material per surface — is untouched.
var _bases: Dictionary = {}


## Fetch (or build) the shared material for a faction.
func _material_for(faction: Enums.Factions, base: ShaderMaterial = null) -> ShaderMaterial:
	if base == null:
		base = base_material
	if base == null:
		push_warning("FactionLivery: base_material not assigned on %s" % get_path())
		return null

	var key := "%d:%d" % [base.get_instance_id(), faction]
	if _cache.has(key):
		var cached: ShaderMaterial = _cache[key]
		if is_instance_valid(cached):
			return cached

	var mat: ShaderMaterial = base.duplicate()
	mat.set_shader_parameter("faction_color", COLORS.get(faction, COLORS[Enums.Factions.NEUTRAL]))
	mat.set_shader_parameter("paint_blend", paint_blend)
	mat.set_shader_parameter("marker_energy", marker_energy)
	mat.set_shader_parameter("shutdown", 0.0)
	_cache[key] = mat
	return mat


## Assign the shared faction material to every collected mesh.
func apply(faction: Enums.Factions) -> void:
	var fallback := _material_for(faction)
	for g in _meshes:
		# A piece that named its own base keeps it. Looked up per piece rather
		# than per call so a repaint after add_pieces_with() does not flatten the
		# hat back onto the hull material.
		var mat: ShaderMaterial = fallback
		if _bases.has(g.get_instance_id()):
			mat = _material_for(faction, _bases[g.get_instance_id()])
		if mat != null:
			g.material_override = mat


## Register pieces that arrived AFTER _ready, and repaint.
##
## `pieces` is exported as node_paths, which Godot resolves to live node objects
## when the scene is instantiated — so anything bolted on at spawn, like the rank
## headgear, is invisible to it and renders in the stock material on both sides.
## Collecting again is cheap: the walk is a few dozen nodes and the material is
## the shared one out of the cache, not a new allocation.
func add_pieces(extra: Array[Node3D]) -> void:
	var grew := false
	for n in extra:
		if n != null and not pieces.has(n):
			pieces.append(n)
			grew = true
	if not grew:
		return
	_collect()
	apply(_resolve_faction())


## Call from Enemy.die() to darken this robot's accent markers.
## Breaks sharing for this one corpse only — acceptable, since
## corpses are few and usually cleaned up.
func set_shutdown(amount: float) -> void:
	for g in _meshes:
		var mat := g.material_override as ShaderMaterial
		if mat == null:
			continue
		if not mat.resource_local_to_scene:
			mat = mat.duplicate()
			mat.resource_local_to_scene = true
			g.material_override = mat
		mat.set_shader_parameter("shutdown", clampf(amount, 0.0, 1.0))


## Call on level unload if you are hot-reloading scenes a lot.
static func clear_cache() -> void:
	_cache.clear()


## Register pieces that keep their OWN surface but take this frame's faction
## colour — the rank headgear. See the note on _bases.
func add_pieces_with(extra: Array[Node3D], base: ShaderMaterial) -> void:
	if base == null:
		add_pieces(extra)
		return
	for n in extra:
		if n == null:
			continue
		_bases[n.get_instance_id()] = base
		if not pieces.has(n):
			pieces.append(n)
	_collect()
	apply(_resolve_faction())


## Let go of pieces that are about to be freed.
##
## NOT OPTIONAL HOUSEKEEPING. `pieces` and `_meshes` hold LIVE NODE OBJECTS, so
## a hat swapped at runtime leaves both arrays pointing at a freed
## MeshInstance3D, and the next repaint — or set_shutdown on death — touches it
## and takes the game with it. csg_bake.gd learned this the same way.
func remove_pieces(gone: Array[Node3D]) -> void:
	for n in gone:
		if n == null:
			continue
		_bases.erase(n.get_instance_id())
		var i := pieces.find(n)
		if i >= 0:
			pieces.remove_at(i)
	_collect()
