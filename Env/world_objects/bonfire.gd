extends Interactible
class_name Bonfire
@export var activated: bool = false
@export var console: Node3D
@export var activate_sound_effect: AudioStreamPlayer3D
signal bonfire_reset()

func get_activated():
	return activated
	
func activate():
	activated = true
func interacted_with():
	if activated == false:
		activate()
		if activate_sound_effect:
			activate_sound_effect.play()
		return
	bonfire_reset.emit()
	match destroy_on_use:
		true:
			destroy()
		false:
			pass
	match disable_on_use:
		true:
			disable()
		false:
			pass
	
