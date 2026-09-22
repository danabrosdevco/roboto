extends Resource
class_name MinimapData

# ─────────────────────────────────────────────
# MINIMAP DATA — a baked top-down picture of a level, plus where the things
# worth knowing about are on it.
#
# Baked offline by tools/minimap.sh, never built at runtime: framing a camera
# over a level and rendering it costs a scene load, and the whole point is to
# have this ready BEFORE the level exists.
#
# The image is a straight orthographic render of the level's own geometry, not
# a navmesh trace. A player reading a briefing needs to recognise buildings and
# open ground; "where the pathfinder is allowed to walk" is a developer's view
# of a map, not a human's.
#
# WORLD SPACE IS XZ. Y is height and is thrown away — this is a floor plan.
# world_min/world_max are the exact rectangle the camera framed, so to_uv() is
# the inverse of the bake and objective markers land where they actually are.
# ─────────────────────────────────────────────

@export var level_scene_path: String = ""
## Path rather than a Texture2D reference: the bake writes the PNG and the
## .tres in the same pass, before Godot has imported the PNG, so there is no
## texture to reference yet. Loaded on demand by texture().
@export var image_path: String = ""

## The world-space rectangle (X,Z) the render covers.
@export var world_min: Vector2 = Vector2.ZERO
@export var world_max: Vector2 = Vector2.ONE

## Parallel arrays rather than an array of dictionaries: Godot serialises typed
## arrays of primitives cleanly into .tres and reads them back with their types
## intact, which an Array[Dictionary] does not reliably do.
@export var objective_ids: Array[StringName] = []
@export var objective_names: Array[String] = []
@export var objective_positions: Array[Vector3] = []
## "capture", "extract", "start" — what symbol the briefing should draw.
@export var objective_kinds: Array[StringName] = []
## Where you come in: the level's SpawnPoint, plus any player SquadSpawnPoint
## that is not right beside it. Drawn as a friendly marker, and part of the
## framing — so the map shows the walk from insertion to the first objective,
## not just the objectives floating on their own. Empty on a map baked before
## this existed; re-run tools/minimap.sh to fill it.
@export var insertion_positions: Array[Vector3] = []


## World position to 0-1 image coordinates. Y of the returned vector runs DOWN
## the image, matching how the render was taken, so callers can multiply
## straight by a TextureRect's size without flipping anything.
func to_uv(world: Vector3) -> Vector2:
	var span := world_max - world_min
	if absf(span.x) < 0.001 or absf(span.y) < 0.001:
		return Vector2(0.5, 0.5)
	return Vector2(
		(world.x - world_min.x) / span.x,
		(world.z - world_min.y) / span.y)


func objective_count() -> int:
	return objective_ids.size()


## Metres across. Worth showing on the briefing — "how big is this and how long
## will it take" was the question a first-time player could not answer at all.
func world_span() -> Vector2:
	return world_max - world_min


var _cached: Texture2D = null


## The baked map. Loaded on first use and held, since a briefing screen asks
## for it once and then draws it every frame.
func texture() -> Texture2D:
	if _cached != null:
		return _cached
	if image_path == "" or not ResourceLoader.exists(image_path):
		return null
	_cached = load(image_path) as Texture2D
	return _cached


## The baked map for a mission's level, or null if it has not been baked.
##
## res://maps/valley_level.tscn -> res://maps/minimaps/valley_level.tres.
## Convention rather than a field on MissionDefinition: every mission already
## names its level, and a second reference would be one more thing to forget to
## set when adding a mission.
static func for_mission(mission: MissionDefinition) -> MinimapData:
	if mission == null or mission.level_scene == null:
		return null
	var base := mission.level_scene.resource_path.get_file().get_basename()
	var path := "res://maps/minimaps/%s.tres" % base
	if not ResourceLoader.exists(path):
		return null
	return load(path) as MinimapData


## The objectives a mission actually uses, as indices into the arrays above:
## the ones in its active_objectives (all of them when it lists none), goals
## first and extraction last, because that is the order you do them in.
##
## Goals go in the order you reach them crossing the map: sorted by how far
## along the line from insertion to extraction each one lies, which runs left
## to right on the valley and Coast Road. The order the level lists its nodes in
## numbered Coast Road's first bridge 1, the far town 3 and the first bridge
## again 4. With no line to follow — no insertion baked, no extraction, or the
## two in one place — it falls back to plain left to right.
##
## The bake holds every objective the level could ever need, so drawing all of
## them told the valley's first op it had three garrisons to take when it has
## one.
func objective_order(active: Array[StringName] = []) -> Array[int]:
	var goals: Array[int] = []
	var exits: Array[int] = []
	for i in objective_ids.size():
		if not active.is_empty() and not active.has(objective_ids[i]):
			continue
		if objective_kinds[i] == &"extract":
			exits.append(i)
		else:
			goals.append(i)
	var axis := _route_axis(exits)
	var along := func(i: int) -> float:
		return objective_positions[i].x * axis.x + objective_positions[i].z * axis.y
	# Ties fall back to bake order, so the numbering never shuffles between two
	# looks at the same board.
	goals.sort_custom(func(a: int, b: int) -> bool:
		var da: float = along.call(a)
		var db: float = along.call(b)
		return da < db if not is_equal_approx(da, db) else a < b)
	goals.append_array(exits)
	return goals


# Which way the op runs across the map, as a unit XZ direction: insertion to the
# first extraction. Plain +X — left to right on the image — when there is no such
# line to follow.
func _route_axis(exits: Array[int]) -> Vector2:
	if insertion_positions.is_empty() or exits.is_empty():
		return Vector2.RIGHT
	var from := insertion_positions[0]
	var to := objective_positions[exits[0]]
	var d := Vector2(to.x - from.x, to.z - from.z)
	if d.length() < 1.0:
		return Vector2.RIGHT
	return d.normalized()


## What to print beside objective i. An extraction nobody named says
## EXTRACTION rather than OBJECTIVE, or nothing at all.
func display_name_of(i: int) -> String:
	var text := objective_names[i].to_upper() if i < objective_names.size() else ""
	if objective_kinds[i] == &"extract" and (text == "" or text == "OBJECTIVE"):
		return "EXTRACTION"
	return text
