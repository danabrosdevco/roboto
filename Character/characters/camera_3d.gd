extends Camera3D

func _ready():
	camera_switcher.register_camera(self)
