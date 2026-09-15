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
	if node is CSGMesh3D:
		_meshes.append(node)
	for child in node.get_children():
		_gather(child)


## Fetch (or build) the shared material for a faction.
func _material_for(faction: Enums.Factions) -> ShaderMaterial:
	if base_material == null:
		push_warning("FactionLivery: base_material not assigned on %s" % get_path())
		return null

	var key := "%d:%d" % [base_material.get_instance_id(), faction]
	if _cache.has(key):
		var cached: ShaderMaterial = _cache[key]
		if is_instance_valid(cached):
			return cached

	var mat: ShaderMaterial = base_material.duplicate()
	mat.set_shader_parameter("faction_color", COLORS.get(faction, COLORS[Enums.Factions.NEUTRAL]))
	mat.set_shader_parameter("paint_blend", paint_blend)
	mat.set_shader_parameter("marker_energy", marker_energy)
	mat.set_shader_parameter("shutdown", 0.0)
	_cache[key] = mat
	return mat


## Assign the shared faction material to every collected mesh.
func apply(faction: Enums.Factions) -> void:
	var mat := _material_for(faction)
	if mat == null:
		return
	for g in _meshes:
		g.material_override = mat


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
