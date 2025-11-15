extends Node
class_name GameManager

@export var player: Player
var enemies: Array
var pickups: Array
var interactibles: Array
var bonfires: Array

func _ready() -> void:
	var tree = get_tree()
	enemies = tree.get_nodes_in_group("enemies")
	pickups = tree.get_nodes_in_group("pickups")
	interactibles = tree.get_nodes_in_group("interactibles")
	bonfires = tree.get_nodes_in_group("bonfires")
	for b in bonfires:
		if b.has_signal("bonfire_reset"):
				b.bonfire_reset.connect(Callable(self, "reset_level"))
	pass

func reset_level():
	player.reset()
	for i in enemies:
		i.reset()
	for i in pickups:
		i.reset()
	for i in interactibles:
		i.reset()
	pass
	
	
