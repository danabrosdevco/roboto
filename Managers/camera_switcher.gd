extends Node
class_name CameraSwitcher

var cameras: Array[Camera3D] = []
var current_index := -1

func _ready():
	set_process_input(true)

func register_camera(cam: Camera3D):
	if cam not in cameras:
		cameras.append(cam)
		if current_index == -1:
			_activate_camera(0)

func _activate_camera(index: int):
	for i in cameras.size():
		var cam = cameras[i]
		var listener = cam.get_child(0) if cam.get_child_count() > 0 else null
		cam.current = (i == index)
		if is_instance_valid(listener) and listener is AudioListener3D:
			if i == index:
				listener.make_current()
			else:
				listener.clear_current()
	current_index = index

func _input(event):
	if event.is_action_pressed("1"):
				if cameras.size() >= 1:
					_activate_camera(0)
	if event.is_action_pressed("2"):
				if cameras.size() >= 2:
					_activate_camera(1)
	if event.is_action_pressed("3"):
				if cameras.size() >= 3:
					_activate_camera(2)
