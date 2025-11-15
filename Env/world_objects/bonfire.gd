extends Interactible
class_name Bonfire
@export var activated: bool = false
signal bonfire_reset()

func get_activated():
	return activated
	
func activate():
	activated = true
func interacted_with():
	if activated == false:
		activate()
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
	
