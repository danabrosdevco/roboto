@icon ("res://addons/plenticons/icons/64x-hidpi/3d/torus-red.png")
extends Node3D
class_name TrenchBroomLevel
@export var spawn_point: Node3D
@export var nav_region: NavigationRegion3D
@export var func_godot_map: FuncGodotMap
@export var level_exits: Array[LevelExit]
