extends Node
class_name ObjectManager

var objects: Array[GameObject] = []
var current_index := -1

func _ready():
	set_process_input(true)

func register_object(obj: GameObject):
	if obj not in objects:
		objects.append(obj)
func pause_object(obj: GameObject):
	obj.pause()

func start_object(obj: GameObject):
	obj.start()

func invulnerable(obj: GameObject):
	obj.make_invulnerable()
func vulnerable(obj: GameObject):
	obj.make_vulnerable()
	
