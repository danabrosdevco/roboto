@icon ("res://addons/plenticons/icons/64x-hidpi/3d/torus-red.png")
extends Node3D
class_name TrenchBroomLevel
@onready var world_root = get_parent()
@export var spawn_point: Node3D
@export var nav_region: NavigationRegion3D
@export var func_godot_map: FuncGodotMap
@export var level_exits: Array[LevelExit]


# ─────────────────────────────────────────────
# THE MAP HAS TO AGREE WITH THE MESH ABOUT cell_size.
#
# A navigation MAP carries its own cell_size, separate from the mesh baked into
# the level, and it comes from ProjectSettings — which nothing here sets, so it
# is Godot's 0.25. Hand the server a region whose mesh was baked at anything
# else and it refuses the update outright:
#
#   Attempted to update a navigation region with a navigation mesh that uses a
#   `cell_size` of 0.5 while assigned to a navigation map set to 0.25.
#
# Qamareen's mesh is baked at 0.5 — 29,760 polygons down to 17,117 — because
# map_get_closest_point walks every polygon in the map and that query is the
# single most expensive thing the AI does on a large level (0.690 ms a call at
# 0.25, against 0.025 ms on the proving ground).
#
# Set from the level's OWN mesh rather than a project setting, so each map
# carries its own bake and a coarse one cannot quietly re-cut every other map.
func _ready() -> void:
	_match_map_cell_size()


func _match_map_cell_size() -> void:
	if nav_region == null or nav_region.navigation_mesh == null:
		# Not every level has a baked region — the depot and the arenas do not.
		# Silent here on purpose: the navigation server already warns loudly for
		# a level that needs one and has none.
		return
	var map := nav_region.get_navigation_map()
	if not map.is_valid():
		push_warning("%s: no navigation map to configure; its region may be refused." % name)
		return
	var want: float = nav_region.navigation_mesh.cell_size
	if absf(NavigationServer3D.map_get_cell_size(map) - want) > 0.0001:
		NavigationServer3D.map_set_cell_size(map, want)
